/*
 * Booking API - C implementation
 *
 * Single-file HTTP server using raw POSIX sockets.
 * Dependencies: sqlite3, openssl, cJSON
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <sqlite3.h>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <openssl/rand.h>

#include "cJSON.h"

/* ─── Constants ─────────────────────────────────────────────────────────── */

/* Portable case-insensitive substring search */
#ifndef HAVE_STRCASESTR
static char *my_strcasestr(const char *haystack, const char *needle) {
    size_t nlen = strlen(needle);
    if (nlen == 0) return (char *)haystack;
    for (; *haystack; haystack++) {
        if (strncasecmp(haystack, needle, nlen) == 0)
            return (char *)haystack;
    }
    return NULL;
}
#define strcasestr my_strcasestr
#endif

#define PORT            8080
#define BACKLOG         128
#define MAX_REQUEST     (1 << 20)   /* 1 MiB */
#define JWT_SECRET      "booking-api-secret-key-2026"
#define SALT_LEN        16
#define HASH_HEX_LEN    (32 * 2)  /* SHA-256 = 32 bytes */

/* ─── Globals ───────────────────────────────────────────────────────────── */

static sqlite3 *g_db   = NULL;
static int      g_sock = -1;

/* ─── Utility: base64url ────────────────────────────────────────────────── */

static const char b64url_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

static char *base64url_encode(const unsigned char *data, size_t len) {
    size_t out_len = 4 * ((len + 2) / 3);
    char *out = malloc(out_len + 1);
    if (!out) return NULL;

    size_t i, j = 0;
    for (i = 0; i + 2 < len; i += 3) {
        unsigned int n = ((unsigned int)data[i] << 16) |
                         ((unsigned int)data[i+1] << 8) |
                          (unsigned int)data[i+2];
        out[j++] = b64url_table[(n >> 18) & 0x3F];
        out[j++] = b64url_table[(n >> 12) & 0x3F];
        out[j++] = b64url_table[(n >>  6) & 0x3F];
        out[j++] = b64url_table[n & 0x3F];
    }
    if (i < len) {
        unsigned int n = (unsigned int)data[i] << 16;
        if (i + 1 < len) n |= (unsigned int)data[i+1] << 8;
        out[j++] = b64url_table[(n >> 18) & 0x3F];
        out[j++] = b64url_table[(n >> 12) & 0x3F];
        if (i + 1 < len)
            out[j++] = b64url_table[(n >> 6) & 0x3F];
    }
    out[j] = '\0';
    return out;
}

static int b64url_char_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-') return 62;
    if (c == '_') return 63;
    return -1;
}

static unsigned char *base64url_decode(const char *input, size_t *out_len) {
    size_t in_len = strlen(input);
    /* Pad to multiple of 4 */
    size_t padded = in_len;
    while (padded % 4) padded++;

    size_t max_out = (padded / 4) * 3;
    unsigned char *out = malloc(max_out + 1);
    if (!out) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < padded; i += 4) {
        int a = (i   < in_len) ? b64url_char_val(input[i])   : 0;
        int b = (i+1 < in_len) ? b64url_char_val(input[i+1]) : 0;
        int c = (i+2 < in_len) ? b64url_char_val(input[i+2]) : 0;
        int d = (i+3 < in_len) ? b64url_char_val(input[i+3]) : 0;

        unsigned int n = (a << 18) | (b << 12) | (c << 6) | d;
        out[j++] = (n >> 16) & 0xFF;
        if (i + 2 < in_len) out[j++] = (n >> 8) & 0xFF;
        if (i + 3 < in_len) out[j++] = n & 0xFF;
    }
    *out_len = j;
    out[j] = '\0';
    return out;
}

/* ─── Utility: hex ──────────────────────────────────────────────────────── */

static void to_hex(const unsigned char *bin, size_t len, char *hex) {
    static const char h[] = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        hex[2*i]   = h[bin[i] >> 4];
        hex[2*i+1] = h[bin[i] & 0x0F];
    }
    hex[2*len] = '\0';
}

/* ─── Password hashing (SHA-256 + salt) ─────────────────────────────────── */

static void sha256_hash(const unsigned char *data1, size_t len1,
                        const unsigned char *data2, size_t len2,
                        unsigned char *out) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
    EVP_DigestUpdate(ctx, data1, len1);
    EVP_DigestUpdate(ctx, data2, len2);
    unsigned int out_len = 0;
    EVP_DigestFinal_ex(ctx, out, &out_len);
    EVP_MD_CTX_free(ctx);
}

static char *hash_password(const char *password) {
    unsigned char salt[SALT_LEN];
    RAND_bytes(salt, SALT_LEN);

    char salt_hex[SALT_LEN * 2 + 1];
    to_hex(salt, SALT_LEN, salt_hex);

    /* hash = SHA256(salt_hex + password) */
    unsigned char digest[32]; /* SHA-256 = 32 bytes */
    sha256_hash((const unsigned char *)salt_hex, strlen(salt_hex),
                (const unsigned char *)password, strlen(password), digest);

    char hash_hex[HASH_HEX_LEN + 1];
    to_hex(digest, 32, hash_hex);

    /* Store as "salt_hex$hash_hex" */
    size_t total = strlen(salt_hex) + 1 + strlen(hash_hex) + 1;
    char *result = malloc(total);
    snprintf(result, total, "%s$%s", salt_hex, hash_hex);
    return result;
}

static int verify_password(const char *password, const char *stored) {
    /* stored = "salt_hex$hash_hex" */
    const char *dollar = strchr(stored, '$');
    if (!dollar) return 0;

    size_t salt_len = (size_t)(dollar - stored);
    char salt_hex[256];
    if (salt_len >= sizeof(salt_hex)) return 0;
    memcpy(salt_hex, stored, salt_len);
    salt_hex[salt_len] = '\0';

    const char *expected_hash = dollar + 1;

    unsigned char digest[32];
    sha256_hash((const unsigned char *)salt_hex, salt_len,
                (const unsigned char *)password, strlen(password), digest);

    char computed[HASH_HEX_LEN + 1];
    to_hex(digest, 32, computed);

    return strcmp(computed, expected_hash) == 0;
}

/* ─── JWT (HS256) ───────────────────────────────────────────────────────── */

static char *jwt_create(long long user_id) {
    /* Header: {"alg":"HS256","typ":"JWT"} */
    const char *header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
    char *header_b64 = base64url_encode((const unsigned char *)header_json,
                                         strlen(header_json));

    /* Payload: {"user_id":N,"exp":T} */
    long long exp_time = (long long)time(NULL) + 86400;
    char payload_json[256];
    snprintf(payload_json, sizeof(payload_json),
             "{\"user_id\":%lld,\"exp\":%lld}", user_id, exp_time);
    char *payload_b64 = base64url_encode((const unsigned char *)payload_json,
                                          strlen(payload_json));

    /* Signing input = header_b64.payload_b64 */
    size_t input_len = strlen(header_b64) + 1 + strlen(payload_b64);
    char *input = malloc(input_len + 1);
    snprintf(input, input_len + 1, "%s.%s", header_b64, payload_b64);

    /* HMAC-SHA256 */
    unsigned char hmac_out[EVP_MAX_MD_SIZE];
    unsigned int hmac_len = 0;
    HMAC(EVP_sha256(), JWT_SECRET, (int)strlen(JWT_SECRET),
         (const unsigned char *)input, input_len, hmac_out, &hmac_len);

    char *sig_b64 = base64url_encode(hmac_out, hmac_len);

    /* token = header.payload.signature */
    size_t token_len = strlen(header_b64) + 1 + strlen(payload_b64) + 1 +
                       strlen(sig_b64);
    char *token = malloc(token_len + 1);
    snprintf(token, token_len + 1, "%s.%s.%s", header_b64, payload_b64,
             sig_b64);

    free(header_b64);
    free(payload_b64);
    free(input);
    free(sig_b64);

    return token;
}

/* Returns user_id on success, -1 on failure */
static long long jwt_verify(const char *token) {
    if (!token || !*token) return -1;

    /* Split token into 3 parts */
    const char *dot1 = strchr(token, '.');
    if (!dot1) return -1;
    const char *dot2 = strchr(dot1 + 1, '.');
    if (!dot2) return -1;
    if (strchr(dot2 + 1, '.')) return -1;  /* too many dots */

    size_t header_len  = (size_t)(dot1 - token);
    size_t payload_len = (size_t)(dot2 - dot1 - 1);
    const char *sig_part = dot2 + 1;

    /* Reconstruct signing input */
    size_t input_len = header_len + 1 + payload_len;
    char *input = malloc(input_len + 1);
    memcpy(input, token, input_len);
    input[input_len] = '\0';

    /* Compute expected HMAC */
    unsigned char hmac_out[EVP_MAX_MD_SIZE];
    unsigned int hmac_len = 0;
    HMAC(EVP_sha256(), JWT_SECRET, (int)strlen(JWT_SECRET),
         (const unsigned char *)input, input_len, hmac_out, &hmac_len);
    free(input);

    char *expected_sig = base64url_encode(hmac_out, hmac_len);

    if (strcmp(sig_part, expected_sig) != 0) {
        free(expected_sig);
        return -1;
    }
    free(expected_sig);

    /* Decode payload */
    char payload_b64[1024];
    if (payload_len >= sizeof(payload_b64)) return -1;
    memcpy(payload_b64, dot1 + 1, payload_len);
    payload_b64[payload_len] = '\0';

    size_t decoded_len = 0;
    unsigned char *decoded = base64url_decode(payload_b64, &decoded_len);
    if (!decoded) return -1;

    cJSON *json = cJSON_ParseWithLength((const char *)decoded, decoded_len);
    free(decoded);
    if (!json) return -1;

    cJSON *uid = cJSON_GetObjectItem(json, "user_id");
    cJSON *exp = cJSON_GetObjectItem(json, "exp");

    long long user_id = -1;
    if (uid && cJSON_IsNumber(uid)) {
        /* Check expiration */
        if (exp && cJSON_IsNumber(exp)) {
            if ((long long)exp->valuedouble < (long long)time(NULL)) {
                cJSON_Delete(json);
                return -1;
            }
        }
        user_id = (long long)uid->valuedouble;
    }

    cJSON_Delete(json);
    return user_id;
}

/* ─── HTTP request/response structures ─────────────────────────────────── */

typedef struct {
    char method[16];
    char path[2048];
    char query[2048];       /* raw query string */
    char *body;
    size_t body_len;
    char auth_token[4096];  /* Bearer token if present */
} http_request_t;

typedef struct {
    int  status;
    char *body;             /* JSON body (caller frees) */
} http_response_t;

/* ─── HTTP parsing ──────────────────────────────────────────────────────── */

static int parse_request(int fd, http_request_t *req) {
    memset(req, 0, sizeof(*req));

    /* Read full request into buffer */
    char *buf = malloc(MAX_REQUEST + 1);
    if (!buf) return -1;

    size_t total = 0;
    int headers_done = 0;
    size_t content_length = 0;
    char *body_start = NULL;

    /* Read headers first */
    while (total < MAX_REQUEST) {
        ssize_t n = read(fd, buf + total, MAX_REQUEST - total);
        if (n <= 0) {
            if (total == 0) { free(buf); return -1; }
            break;
        }
        total += n;
        buf[total] = '\0';

        if (!headers_done) {
            body_start = strstr(buf, "\r\n\r\n");
            if (body_start) {
                headers_done = 1;
                body_start += 4;

                /* Find Content-Length */
                char *cl = strcasestr(buf, "Content-Length:");
                if (cl) {
                    cl += 15;
                    while (*cl == ' ') cl++;
                    content_length = (size_t)atol(cl);
                }

                size_t body_received = total - (size_t)(body_start - buf);
                if (body_received >= content_length) break;
            }
        } else {
            size_t body_received = total - (size_t)(body_start - buf);
            if (body_received >= content_length) break;
        }
    }

    if (!headers_done) { free(buf); return -1; }

    /* Find Authorization header BEFORE modifying the buffer */
    char *auth = strcasestr(buf, "\r\nAuthorization:");
    if (auth) {
        auth += 16;  /* skip "\r\nAuthorization:" */
        while (*auth == ' ') auth++;
        char *auth_end = strstr(auth, "\r\n");
        if (auth_end) {
            size_t alen = (size_t)(auth_end - auth);
            if (alen > sizeof(req->auth_token) - 1)
                alen = sizeof(req->auth_token) - 1;
            memcpy(req->auth_token, auth, alen);
            req->auth_token[alen] = '\0';
        }
    }

    /* Parse request line (modifies buffer) */
    char *line_end = strstr(buf, "\r\n");
    if (!line_end) { free(buf); return -1; }

    *line_end = '\0';
    char *sp1 = strchr(buf, ' ');
    if (!sp1) { free(buf); return -1; }
    *sp1 = '\0';
    char *sp2 = strchr(sp1 + 1, ' ');
    if (sp2) *sp2 = '\0';

    strncpy(req->method, buf, sizeof(req->method) - 1);

    /* Split path and query */
    char *qmark = strchr(sp1 + 1, '?');
    if (qmark) {
        *qmark = '\0';
        strncpy(req->path, sp1 + 1, sizeof(req->path) - 1);
        strncpy(req->query, qmark + 1, sizeof(req->query) - 1);
    } else {
        strncpy(req->path, sp1 + 1, sizeof(req->path) - 1);
    }

    /* Copy body */
    if (content_length > 0 && body_start) {
        req->body = malloc(content_length + 1);
        memcpy(req->body, body_start, content_length);
        req->body[content_length] = '\0';
        req->body_len = content_length;
    }

    free(buf);
    return 0;
}

static void send_response(int fd, int status, const char *body) {
    const char *status_text;
    switch (status) {
        case 200: status_text = "OK"; break;
        case 201: status_text = "Created"; break;
        case 400: status_text = "Bad Request"; break;
        case 401: status_text = "Unauthorized"; break;
        case 403: status_text = "Forbidden"; break;
        case 404: status_text = "Not Found"; break;
        case 409: status_text = "Conflict"; break;
        default:  status_text = "Internal Server Error"; status = 500; break;
    }

    size_t body_len = body ? strlen(body) : 0;
    char header[512];
    int hlen = snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        status, status_text, body_len);

    write(fd, header, (size_t)hlen);
    if (body && body_len > 0) {
        write(fd, body, body_len);
    }
}

static void send_json_response(int fd, int status, cJSON *json) {
    char *body = cJSON_PrintUnformatted(json);
    send_response(fd, status, body);
    free(body);
}

/* ─── Query parameter parsing ──────────────────────────────────────────── */

static const char *get_query_param(const char *query, const char *key,
                                    char *value, size_t value_size) {
    if (!query || !*query) return NULL;

    size_t key_len = strlen(key);
    const char *p = query;

    while (*p) {
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *val_start = p + key_len + 1;
            const char *val_end = strchr(val_start, '&');
            size_t vlen;
            if (val_end)
                vlen = (size_t)(val_end - val_start);
            else
                vlen = strlen(val_start);
            if (vlen >= value_size) vlen = value_size - 1;
            memcpy(value, val_start, vlen);
            value[vlen] = '\0';
            return value;
        }
        const char *amp = strchr(p, '&');
        if (!amp) break;
        p = amp + 1;
    }
    return NULL;
}

/* ─── Auth middleware helper ────────────────────────────────────────────── */

static long long extract_user_id(const http_request_t *req) {
    if (!req->auth_token[0]) return -1;
    if (strncmp(req->auth_token, "Bearer ", 7) != 0) return -1;
    return jwt_verify(req->auth_token + 7);
}

/* ─── Handlers ──────────────────────────────────────────────────────────── */

static void handle_register(int fd, http_request_t *req) {
    if (!req->body) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *json = cJSON_Parse(req->body);
    if (!json) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *j_email = cJSON_GetObjectItem(json, "email");
    cJSON *j_name  = cJSON_GetObjectItem(json, "name");
    cJSON *j_pass  = cJSON_GetObjectItem(json, "password");

    if (!j_email || !cJSON_IsString(j_email) || !j_email->valuestring[0] ||
        !j_name  || !cJSON_IsString(j_name)  || !j_name->valuestring[0] ||
        !j_pass  || !cJSON_IsString(j_pass)  || !j_pass->valuestring[0]) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        cJSON_Delete(json);
        return;
    }

    char *pw_hash = hash_password(j_pass->valuestring);

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        free(pw_hash);
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_bind_text(stmt, 1, j_email->valuestring, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, j_name->valuestring,  -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, pw_hash,              -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    free(pw_hash);

    if (rc != SQLITE_DONE) {
        const char *errmsg = sqlite3_errmsg(g_db);
        if (errmsg && strstr(errmsg, "UNIQUE")) {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "email already exists");
            send_json_response(fd, 409, err);
            cJSON_Delete(err);
        } else {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "internal error");
            send_json_response(fd, 500, err);
            cJSON_Delete(err);
        }
        cJSON_Delete(json);
        return;
    }

    long long id = sqlite3_last_insert_rowid(g_db);

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id", (double)id);
    cJSON_AddStringToObject(resp, "email", j_email->valuestring);
    cJSON_AddStringToObject(resp, "name", j_name->valuestring);
    send_json_response(fd, 201, resp);
    cJSON_Delete(resp);
    cJSON_Delete(json);
}

static void handle_login(int fd, http_request_t *req) {
    if (!req->body) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "invalid credentials");
        send_json_response(fd, 401, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *json = cJSON_Parse(req->body);
    if (!json) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "invalid credentials");
        send_json_response(fd, 401, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *j_email = cJSON_GetObjectItem(json, "email");
    cJSON *j_pass  = cJSON_GetObjectItem(json, "password");

    if (!j_email || !cJSON_IsString(j_email) ||
        !j_pass  || !cJSON_IsString(j_pass)) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "invalid credentials");
        send_json_response(fd, 401, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT id, name, password_hash FROM users WHERE email = ?",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_bind_text(stmt, 1, j_email->valuestring, -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "invalid credentials");
        send_json_response(fd, 401, err);
        cJSON_Delete(err);
        return;
    }

    long long user_id = sqlite3_column_int64(stmt, 0);
    const char *name  = (const char *)sqlite3_column_text(stmt, 1);
    const char *hash  = (const char *)sqlite3_column_text(stmt, 2);

    /* Copy before finalize */
    char *name_copy = strdup(name);
    char *hash_copy = strdup(hash);

    sqlite3_finalize(stmt);

    if (!verify_password(j_pass->valuestring, hash_copy)) {
        free(name_copy);
        free(hash_copy);
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "invalid credentials");
        send_json_response(fd, 401, err);
        cJSON_Delete(err);
        return;
    }

    char *token = jwt_create(user_id);

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "token", token);

    cJSON *user_obj = cJSON_CreateObject();
    cJSON_AddNumberToObject(user_obj, "id", (double)user_id);
    cJSON_AddStringToObject(user_obj, "email", j_email->valuestring);
    cJSON_AddStringToObject(user_obj, "name", name_copy);
    cJSON_AddItemToObject(resp, "user", user_obj);

    send_json_response(fd, 200, resp);

    cJSON_Delete(resp);
    cJSON_Delete(json);
    free(name_copy);
    free(hash_copy);
    free(token);
}

static void handle_list_spaces(int fd, http_request_t *req) {
    char sql[1024];
    strcpy(sql, "SELECT id, name, description, price_per_hour, owner_id, "
                "created_at FROM spaces WHERE 1=1");

    char min_price_str[64] = {0};
    char max_price_str[64] = {0};
    double min_price = 0, max_price = 0;
    int has_min = 0, has_max = 0;

    if (get_query_param(req->query, "min_price", min_price_str,
                        sizeof(min_price_str))) {
        min_price = atof(min_price_str);
        strcat(sql, " AND price_per_hour >= ?");
        has_min = 1;
    }
    if (get_query_param(req->query, "max_price", max_price_str,
                        sizeof(max_price_str))) {
        max_price = atof(max_price_str);
        strcat(sql, " AND price_per_hour <= ?");
        has_max = 1;
    }

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    int bind_idx = 1;
    if (has_min) sqlite3_bind_double(stmt, bind_idx++, min_price);
    if (has_max) sqlite3_bind_double(stmt, bind_idx++, max_price);

    cJSON *arr = cJSON_CreateArray();
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        cJSON *space = cJSON_CreateObject();
        cJSON_AddNumberToObject(space, "id",
            (double)sqlite3_column_int64(stmt, 0));
        cJSON_AddStringToObject(space, "name",
            (const char *)sqlite3_column_text(stmt, 1));

        /* description: return "" if NULL */
        const char *desc = (const char *)sqlite3_column_text(stmt, 2);
        cJSON_AddStringToObject(space, "description", desc ? desc : "");

        cJSON_AddNumberToObject(space, "price_per_hour",
            sqlite3_column_double(stmt, 3));
        cJSON_AddNumberToObject(space, "owner_id",
            (double)sqlite3_column_int64(stmt, 4));
        cJSON_AddStringToObject(space, "created_at",
            (const char *)sqlite3_column_text(stmt, 5));

        cJSON_AddItemToArray(arr, space);
    }
    sqlite3_finalize(stmt);

    send_json_response(fd, 200, arr);
    cJSON_Delete(arr);
}

static void handle_create_space(int fd, http_request_t *req,
                                 long long user_id) {
    if (!req->body) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *json = cJSON_Parse(req->body);
    if (!json) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *j_name  = cJSON_GetObjectItem(json, "name");
    cJSON *j_desc  = cJSON_GetObjectItem(json, "description");
    cJSON *j_price = cJSON_GetObjectItem(json, "price_per_hour");

    if (!j_name || !cJSON_IsString(j_name) || !j_name->valuestring[0] ||
        !j_price || !cJSON_IsNumber(j_price) || j_price->valuedouble == 0) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    const char *desc = "";
    if (j_desc && cJSON_IsString(j_desc))
        desc = j_desc->valuestring;

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "INSERT INTO spaces (name, description, price_per_hour, owner_id) "
        "VALUES (?, ?, ?, ?)",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_bind_text(stmt, 1, j_name->valuestring, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, desc, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 3, j_price->valuedouble);
    sqlite3_bind_int64(stmt, 4, user_id);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    long long id = sqlite3_last_insert_rowid(g_db);

    /* Fetch created_at */
    char created_at[64] = "";
    sqlite3_stmt *sel;
    if (sqlite3_prepare_v2(g_db,
        "SELECT created_at FROM spaces WHERE id = ?", -1, &sel, NULL)
        == SQLITE_OK) {
        sqlite3_bind_int64(sel, 1, id);
        if (sqlite3_step(sel) == SQLITE_ROW) {
            const char *ca = (const char *)sqlite3_column_text(sel, 0);
            if (ca) strncpy(created_at, ca, sizeof(created_at) - 1);
        }
        sqlite3_finalize(sel);
    }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id", (double)id);
    cJSON_AddStringToObject(resp, "name", j_name->valuestring);
    cJSON_AddStringToObject(resp, "description", desc);
    cJSON_AddNumberToObject(resp, "price_per_hour", j_price->valuedouble);
    cJSON_AddNumberToObject(resp, "owner_id", (double)user_id);
    cJSON_AddStringToObject(resp, "created_at", created_at);

    send_json_response(fd, 201, resp);
    cJSON_Delete(resp);
    cJSON_Delete(json);
}

static void handle_my_bookings(int fd, http_request_t *req,
                                long long user_id) {
    (void)req;
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT id, space_id, user_id, start_time, end_time, status, "
        "created_at FROM bookings WHERE user_id = ?",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_bind_int64(stmt, 1, user_id);

    cJSON *arr = cJSON_CreateArray();
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        cJSON *booking = cJSON_CreateObject();
        cJSON_AddNumberToObject(booking, "id",
            (double)sqlite3_column_int64(stmt, 0));
        cJSON_AddNumberToObject(booking, "space_id",
            (double)sqlite3_column_int64(stmt, 1));
        cJSON_AddNumberToObject(booking, "user_id",
            (double)sqlite3_column_int64(stmt, 2));
        cJSON_AddStringToObject(booking, "start_time",
            (const char *)sqlite3_column_text(stmt, 3));
        cJSON_AddStringToObject(booking, "end_time",
            (const char *)sqlite3_column_text(stmt, 4));
        cJSON_AddStringToObject(booking, "status",
            (const char *)sqlite3_column_text(stmt, 5));
        cJSON_AddStringToObject(booking, "created_at",
            (const char *)sqlite3_column_text(stmt, 6));
        cJSON_AddItemToArray(arr, booking);
    }
    sqlite3_finalize(stmt);

    send_json_response(fd, 200, arr);
    cJSON_Delete(arr);
}

static void handle_create_booking(int fd, http_request_t *req,
                                   long long user_id) {
    if (!req->body) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *json = cJSON_Parse(req->body);
    if (!json) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    cJSON *j_space = cJSON_GetObjectItem(json, "space_id");
    cJSON *j_start = cJSON_GetObjectItem(json, "start_time");
    cJSON *j_end   = cJSON_GetObjectItem(json, "end_time");

    if (!j_space || !cJSON_IsNumber(j_space) || j_space->valuedouble == 0 ||
        !j_start || !cJSON_IsString(j_start) || !j_start->valuestring[0] ||
        !j_end   || !cJSON_IsString(j_end)   || !j_end->valuestring[0]) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "missing required fields");
        send_json_response(fd, 400, err);
        cJSON_Delete(err);
        return;
    }

    long long space_id = (long long)j_space->valuedouble;

    /* Check space exists */
    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT COUNT(*) FROM spaces WHERE id = ?", -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }
    sqlite3_bind_int64(stmt, 1, space_id);
    int exists = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW)
        exists = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);

    if (exists == 0) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "space not found");
        send_json_response(fd, 404, err);
        cJSON_Delete(err);
        return;
    }

    /* Check overlap */
    rc = sqlite3_prepare_v2(g_db,
        "SELECT COUNT(*) FROM bookings "
        "WHERE space_id = ? AND status IN ('pending','confirmed') "
        "AND start_time < ? AND ? < end_time",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }
    sqlite3_bind_int64(stmt, 1, space_id);
    sqlite3_bind_text(stmt, 2, j_end->valuestring,   -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, j_start->valuestring, -1, SQLITE_TRANSIENT);

    int overlap = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW)
        overlap = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);

    if (overlap > 0) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "booking overlap");
        send_json_response(fd, 409, err);
        cJSON_Delete(err);
        return;
    }

    /* Insert booking */
    rc = sqlite3_prepare_v2(g_db,
        "INSERT INTO bookings (space_id, user_id, start_time, end_time, "
        "status) VALUES (?, ?, ?, ?, 'confirmed')",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }
    sqlite3_bind_int64(stmt, 1, space_id);
    sqlite3_bind_int64(stmt, 2, user_id);
    sqlite3_bind_text(stmt, 3, j_start->valuestring, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, j_end->valuestring,   -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        cJSON_Delete(json);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    long long booking_id = sqlite3_last_insert_rowid(g_db);

    /* Fetch created_at */
    char created_at[64] = "";
    sqlite3_stmt *sel;
    if (sqlite3_prepare_v2(g_db,
        "SELECT created_at FROM bookings WHERE id = ?", -1, &sel, NULL)
        == SQLITE_OK) {
        sqlite3_bind_int64(sel, 1, booking_id);
        if (sqlite3_step(sel) == SQLITE_ROW) {
            const char *ca = (const char *)sqlite3_column_text(sel, 0);
            if (ca) strncpy(created_at, ca, sizeof(created_at) - 1);
        }
        sqlite3_finalize(sel);
    }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id", (double)booking_id);
    cJSON_AddNumberToObject(resp, "space_id", (double)space_id);
    cJSON_AddNumberToObject(resp, "user_id", (double)user_id);
    cJSON_AddStringToObject(resp, "start_time", j_start->valuestring);
    cJSON_AddStringToObject(resp, "end_time", j_end->valuestring);
    cJSON_AddStringToObject(resp, "status", "confirmed");
    cJSON_AddStringToObject(resp, "created_at", created_at);

    send_json_response(fd, 201, resp);
    cJSON_Delete(resp);
    cJSON_Delete(json);
}

static void handle_cancel_booking(int fd, http_request_t *req,
                                   long long user_id, long long booking_id) {
    (void)req;

    sqlite3_stmt *stmt;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT id, space_id, user_id, start_time, end_time, status, "
        "created_at FROM bookings WHERE id = ?",
        -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "internal error");
        send_json_response(fd, 500, err);
        cJSON_Delete(err);
        return;
    }

    sqlite3_bind_int64(stmt, 1, booking_id);

    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "booking not found");
        send_json_response(fd, 404, err);
        cJSON_Delete(err);
        return;
    }

    long long id        = sqlite3_column_int64(stmt, 0);
    long long space_id  = sqlite3_column_int64(stmt, 1);
    long long owner_id  = sqlite3_column_int64(stmt, 2);
    const char *start   = (const char *)sqlite3_column_text(stmt, 3);
    const char *end     = (const char *)sqlite3_column_text(stmt, 4);
    /* status column not used, we set to 'cancelled' */
    const char *created = (const char *)sqlite3_column_text(stmt, 6);

    /* Copy strings before finalize */
    char *start_copy   = strdup(start);
    char *end_copy     = strdup(end);
    char *created_copy = strdup(created);

    sqlite3_finalize(stmt);

    if (owner_id != user_id) {
        free(start_copy);
        free(end_copy);
        free(created_copy);
        cJSON *err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "forbidden");
        send_json_response(fd, 403, err);
        cJSON_Delete(err);
        return;
    }

    /* Update status */
    rc = sqlite3_prepare_v2(g_db,
        "UPDATE bookings SET status = 'cancelled' WHERE id = ?",
        -1, &stmt, NULL);
    if (rc == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, booking_id);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id", (double)id);
    cJSON_AddNumberToObject(resp, "space_id", (double)space_id);
    cJSON_AddNumberToObject(resp, "user_id", (double)owner_id);
    cJSON_AddStringToObject(resp, "start_time", start_copy);
    cJSON_AddStringToObject(resp, "end_time", end_copy);
    cJSON_AddStringToObject(resp, "status", "cancelled");
    cJSON_AddStringToObject(resp, "created_at", created_copy);

    send_json_response(fd, 200, resp);
    cJSON_Delete(resp);

    free(start_copy);
    free(end_copy);
    free(created_copy);
}

/* ─── Router ────────────────────────────────────────────────────────────── */

static void handle_request(int fd) {
    http_request_t req;
    if (parse_request(fd, &req) < 0) {
        send_response(fd, 400, "{\"error\":\"bad request\"}");
        return;
    }

    /* POST /api/auth/register */
    if (strcmp(req.method, "POST") == 0 &&
        strcmp(req.path, "/api/auth/register") == 0) {
        handle_register(fd, &req);
    }
    /* POST /api/auth/login */
    else if (strcmp(req.method, "POST") == 0 &&
             strcmp(req.path, "/api/auth/login") == 0) {
        handle_login(fd, &req);
    }
    /* GET /api/spaces */
    else if (strcmp(req.method, "GET") == 0 &&
             strcmp(req.path, "/api/spaces") == 0) {
        handle_list_spaces(fd, &req);
    }
    /* POST /api/spaces (auth required) */
    else if (strcmp(req.method, "POST") == 0 &&
             strcmp(req.path, "/api/spaces") == 0) {
        long long uid = extract_user_id(&req);
        if (uid < 0) {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "unauthorized");
            send_json_response(fd, 401, err);
            cJSON_Delete(err);
        } else {
            handle_create_space(fd, &req, uid);
        }
    }
    /* GET /api/bookings/my (auth required) */
    else if (strcmp(req.method, "GET") == 0 &&
             strcmp(req.path, "/api/bookings/my") == 0) {
        long long uid = extract_user_id(&req);
        if (uid < 0) {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "unauthorized");
            send_json_response(fd, 401, err);
            cJSON_Delete(err);
        } else {
            handle_my_bookings(fd, &req, uid);
        }
    }
    /* POST /api/bookings (auth required) */
    else if (strcmp(req.method, "POST") == 0 &&
             strcmp(req.path, "/api/bookings") == 0) {
        long long uid = extract_user_id(&req);
        if (uid < 0) {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "unauthorized");
            send_json_response(fd, 401, err);
            cJSON_Delete(err);
        } else {
            handle_create_booking(fd, &req, uid);
        }
    }
    /* DELETE /api/bookings/:id (auth required) */
    else if (strcmp(req.method, "DELETE") == 0 &&
             strncmp(req.path, "/api/bookings/", 14) == 0) {
        long long uid = extract_user_id(&req);
        if (uid < 0) {
            cJSON *err = cJSON_CreateObject();
            cJSON_AddStringToObject(err, "error", "unauthorized");
            send_json_response(fd, 401, err);
            cJSON_Delete(err);
        } else {
            const char *id_str = req.path + 14;
            long long bid = atoll(id_str);
            if (bid <= 0) {
                cJSON *err = cJSON_CreateObject();
                cJSON_AddStringToObject(err, "error", "booking not found");
                send_json_response(fd, 404, err);
                cJSON_Delete(err);
            } else {
                handle_cancel_booking(fd, &req, uid, bid);
            }
        }
    }
    else {
        send_response(fd, 404, "{\"error\":\"not found\"}");
    }

    free(req.body);
}

/* ─── Database initialization ───────────────────────────────────────────── */

static void init_db(void) {
    const char *workdir = getenv("WORKDIR");
    if (!workdir || !*workdir) workdir = ".";

    char db_path[4096];
    snprintf(db_path, sizeof(db_path), "%s/booking.db", workdir);

    char schema_path[4096];
    snprintf(schema_path, sizeof(schema_path), "%s/schema.sql", workdir);

    int rc = sqlite3_open(db_path, &g_db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to open database: %s\n",
                sqlite3_errmsg(g_db));
        exit(1);
    }

    /* Enable WAL, busy timeout, foreign keys */
    sqlite3_exec(g_db, "PRAGMA journal_mode=WAL", NULL, NULL, NULL);
    sqlite3_exec(g_db, "PRAGMA busy_timeout=5000", NULL, NULL, NULL);
    sqlite3_exec(g_db, "PRAGMA foreign_keys=ON", NULL, NULL, NULL);

    /* Read and execute schema */
    FILE *f = fopen(schema_path, "r");
    if (!f) {
        fprintf(stderr, "Failed to open schema: %s\n", schema_path);
        exit(1);
    }

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *schema = malloc((size_t)fsize + 1);
    fread(schema, 1, (size_t)fsize, f);
    schema[fsize] = '\0';
    fclose(f);

    char *err_msg = NULL;
    rc = sqlite3_exec(g_db, schema, NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Schema execution failed: %s\n",
                err_msg ? err_msg : "unknown error");
        sqlite3_free(err_msg);
        free(schema);
        exit(1);
    }
    free(schema);
}

/* ─── Signal handling ───────────────────────────────────────────────────── */

static void handle_signal(int sig) {
    (void)sig;
    if (g_sock >= 0) close(g_sock);
    if (g_db) sqlite3_close(g_db);
    exit(0);
}

/* ─── Main ──────────────────────────────────────────────────────────────── */

int main(void) {
    signal(SIGINT,  handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGPIPE, SIG_IGN);

    init_db();

    g_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (g_sock < 0) {
        perror("socket");
        return 1;
    }

    int opt = 1;
    setsockopt(g_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(PORT);

    if (bind(g_sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(g_sock);
        return 1;
    }

    if (listen(g_sock, BACKLOG) < 0) {
        perror("listen");
        close(g_sock);
        return 1;
    }

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(g_sock, (struct sockaddr *)&client_addr,
                               &client_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }

        handle_request(client_fd);
        close(client_fd);
    }

    close(g_sock);
    sqlite3_close(g_db);
    return 0;
}
