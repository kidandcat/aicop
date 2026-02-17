#include <httplib.h>
#include <nlohmann/json.hpp>
#include <sqlite3.h>
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <openssl/rand.h>
#include <openssl/evp.h>

#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <functional>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>
#include <iomanip>

using json = nlohmann::json;

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

static const std::string JWT_SECRET = "booking-api-secret-key-2026";
static sqlite3* g_db = nullptr;
static std::mutex g_db_mutex;

// ---------------------------------------------------------------------------
// Base64-URL helpers
// ---------------------------------------------------------------------------

static const char B64_TABLE[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string base64_encode(const unsigned char* data, size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        unsigned int n = ((unsigned int)data[i]) << 16;
        if (i + 1 < len) n |= ((unsigned int)data[i + 1]) << 8;
        if (i + 2 < len) n |= ((unsigned int)data[i + 2]);
        out += B64_TABLE[(n >> 18) & 0x3f];
        out += B64_TABLE[(n >> 12) & 0x3f];
        out += (i + 1 < len) ? B64_TABLE[(n >> 6) & 0x3f] : '=';
        out += (i + 2 < len) ? B64_TABLE[n & 0x3f] : '=';
    }
    return out;
}

static std::string base64url_encode(const unsigned char* data, size_t len) {
    std::string b64 = base64_encode(data, len);
    // Convert to base64url: + -> -, / -> _, strip '='
    for (auto& c : b64) {
        if (c == '+') c = '-';
        else if (c == '/') c = '_';
    }
    // Remove trailing '='
    while (!b64.empty() && b64.back() == '=') b64.pop_back();
    return b64;
}

static std::string base64url_encode(const std::string& s) {
    return base64url_encode(reinterpret_cast<const unsigned char*>(s.data()), s.size());
}

static int b64_char_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

static std::string base64_decode(const std::string& in) {
    // Pad to multiple of 4
    std::string input = in;
    while (input.size() % 4 != 0) input += '=';

    std::string out;
    out.reserve((input.size() / 4) * 3);
    for (size_t i = 0; i < input.size(); i += 4) {
        int a = b64_char_val(input[i]);
        int b = b64_char_val(input[i + 1]);
        int c = (input[i + 2] != '=') ? b64_char_val(input[i + 2]) : 0;
        int d = (input[i + 3] != '=') ? b64_char_val(input[i + 3]) : 0;

        unsigned int n = (a << 18) | (b << 12) | (c << 6) | d;
        out += (char)((n >> 16) & 0xff);
        if (input[i + 2] != '=') out += (char)((n >> 8) & 0xff);
        if (input[i + 3] != '=') out += (char)(n & 0xff);
    }
    return out;
}

static std::string base64url_decode(const std::string& in) {
    // Convert base64url -> base64
    std::string b64 = in;
    for (auto& c : b64) {
        if (c == '-') c = '+';
        else if (c == '_') c = '/';
    }
    return base64_decode(b64);
}

// ---------------------------------------------------------------------------
// HMAC-SHA256
// ---------------------------------------------------------------------------

static std::string hmac_sha256(const std::string& key, const std::string& data) {
    unsigned char result[EVP_MAX_MD_SIZE];
    unsigned int result_len = 0;
    HMAC(EVP_sha256(),
         key.data(), static_cast<int>(key.size()),
         reinterpret_cast<const unsigned char*>(data.data()), data.size(),
         result, &result_len);
    return std::string(reinterpret_cast<char*>(result), result_len);
}

// ---------------------------------------------------------------------------
// JWT
// ---------------------------------------------------------------------------

static std::string jwt_encode(int64_t user_id) {
    json header = {{"alg", "HS256"}, {"typ", "JWT"}};
    json payload = {
        {"user_id", user_id},
        {"exp", std::time(nullptr) + 86400}  // 24h
    };

    std::string h = base64url_encode(header.dump());
    std::string p = base64url_encode(payload.dump());
    std::string signing_input = h + "." + p;
    std::string sig = hmac_sha256(JWT_SECRET, signing_input);
    std::string s = base64url_encode(reinterpret_cast<const unsigned char*>(sig.data()), sig.size());

    return signing_input + "." + s;
}

// Returns user_id or -1 on failure
static int64_t jwt_decode(const std::string& token) {
    // Split into 3 parts
    auto p1 = token.find('.');
    if (p1 == std::string::npos) return -1;
    auto p2 = token.find('.', p1 + 1);
    if (p2 == std::string::npos) return -1;

    std::string header_payload = token.substr(0, p2);
    std::string sig_encoded = token.substr(p2 + 1);

    // Verify signature
    std::string expected_sig = hmac_sha256(JWT_SECRET, header_payload);
    std::string expected_encoded = base64url_encode(
        reinterpret_cast<const unsigned char*>(expected_sig.data()), expected_sig.size());
    if (sig_encoded != expected_encoded) return -1;

    // Decode payload
    std::string payload_str = base64url_decode(token.substr(p1 + 1, p2 - p1 - 1));
    try {
        auto payload = json::parse(payload_str);

        // Check expiration
        if (payload.contains("exp")) {
            int64_t exp = payload["exp"].get<int64_t>();
            if (std::time(nullptr) > exp) return -1;
        }

        if (!payload.contains("user_id")) return -1;
        // user_id can be int or float in JSON
        if (payload["user_id"].is_number_integer()) {
            return payload["user_id"].get<int64_t>();
        } else if (payload["user_id"].is_number_float()) {
            return static_cast<int64_t>(payload["user_id"].get<double>());
        }
        return -1;
    } catch (...) {
        return -1;
    }
}

// ---------------------------------------------------------------------------
// Password hashing (SHA-256 + random salt)
// ---------------------------------------------------------------------------

static std::string sha256_hex(const std::string& input) {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(input.data()), input.size(), hash);
    std::ostringstream oss;
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i)
        oss << std::hex << std::setfill('0') << std::setw(2) << (int)hash[i];
    return oss.str();
}

static std::string random_salt(int len = 16) {
    unsigned char buf[16];
    RAND_bytes(buf, len);
    std::ostringstream oss;
    for (int i = 0; i < len; ++i)
        oss << std::hex << std::setfill('0') << std::setw(2) << (int)buf[i];
    return oss.str();
}

static std::string hash_password(const std::string& password) {
    std::string salt = random_salt();
    std::string hash = sha256_hex(salt + password);
    return salt + ":" + hash;
}

static bool verify_password(const std::string& password, const std::string& stored) {
    auto colon = stored.find(':');
    if (colon == std::string::npos) return false;
    std::string salt = stored.substr(0, colon);
    std::string hash = stored.substr(colon + 1);
    return sha256_hex(salt + password) == hash;
}

// ---------------------------------------------------------------------------
// Database helpers
// ---------------------------------------------------------------------------

static void init_db() {
    std::string workdir = ".";
    const char* env = std::getenv("WORKDIR");
    if (env && env[0]) workdir = env;

    std::string db_path = workdir + "/booking.db";
    std::string schema_path = workdir + "/schema.sql";

    int rc = sqlite3_open(db_path.c_str(), &g_db);
    if (rc != SQLITE_OK) {
        std::cerr << "Cannot open database: " << sqlite3_errmsg(g_db) << std::endl;
        std::exit(1);
    }

    // Enable WAL mode, busy timeout, foreign keys
    sqlite3_exec(g_db, "PRAGMA journal_mode=WAL;", nullptr, nullptr, nullptr);
    sqlite3_exec(g_db, "PRAGMA busy_timeout=5000;", nullptr, nullptr, nullptr);
    sqlite3_exec(g_db, "PRAGMA foreign_keys=ON;", nullptr, nullptr, nullptr);

    // Read and execute schema
    std::ifstream f(schema_path);
    if (!f.is_open()) {
        std::cerr << "Cannot open schema file: " << schema_path << std::endl;
        std::exit(1);
    }
    std::string schema((std::istreambuf_iterator<char>(f)),
                        std::istreambuf_iterator<char>());

    char* err_msg = nullptr;
    rc = sqlite3_exec(g_db, schema.c_str(), nullptr, nullptr, &err_msg);
    if (rc != SQLITE_OK) {
        std::cerr << "Schema error: " << err_msg << std::endl;
        sqlite3_free(err_msg);
        std::exit(1);
    }
}

// RAII wrapper for sqlite3_stmt
struct StmtGuard {
    sqlite3_stmt* stmt;
    StmtGuard(sqlite3_stmt* s) : stmt(s) {}
    ~StmtGuard() { if (stmt) sqlite3_finalize(stmt); }
};

// ---------------------------------------------------------------------------
// Auth middleware helper
// ---------------------------------------------------------------------------

// Returns user_id or -1 if unauthorized. Sets error response if unauthorized.
static int64_t authenticate(const httplib::Request& req, httplib::Response& res) {
    auto it = req.headers.find("Authorization");
    if (it == req.headers.end()) {
        res.status = 401;
        res.set_content(json({{"error", "unauthorized"}}).dump(), "application/json");
        return -1;
    }

    const std::string& auth = it->second;
    if (auth.substr(0, 7) != "Bearer ") {
        res.status = 401;
        res.set_content(json({{"error", "unauthorized"}}).dump(), "application/json");
        return -1;
    }

    std::string token = auth.substr(7);
    int64_t user_id = jwt_decode(token);
    if (user_id < 0) {
        res.status = 401;
        res.set_content(json({{"error", "unauthorized"}}).dump(), "application/json");
        return -1;
    }
    return user_id;
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

static void handle_register(const httplib::Request& req, httplib::Response& res) {
    json body;
    try {
        body = json::parse(req.body);
    } catch (...) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    std::string email = body.value("email", "");
    std::string name = body.value("name", "");
    std::string password = body.value("password", "");

    if (email.empty() || name.empty() || password.empty()) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    std::string pw_hash = hash_password(password);

    std::lock_guard<std::mutex> lock(g_db_mutex);

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(g_db,
        "INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)",
        -1, &stmt, nullptr);
    StmtGuard guard(stmt);

    if (rc != SQLITE_OK) {
        res.status = 500;
        res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        return;
    }

    sqlite3_bind_text(stmt, 1, email.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, pw_hash.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std::string err = sqlite3_errmsg(g_db);
        if (err.find("UNIQUE") != std::string::npos) {
            res.status = 409;
            res.set_content(json({{"error", "email already exists"}}).dump(), "application/json");
        } else {
            res.status = 500;
            res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        }
        return;
    }

    int64_t id = sqlite3_last_insert_rowid(g_db);

    res.status = 201;
    res.set_content(json({
        {"id", id},
        {"email", email},
        {"name", name}
    }).dump(), "application/json");
}

static void handle_login(const httplib::Request& req, httplib::Response& res) {
    json body;
    try {
        body = json::parse(req.body);
    } catch (...) {
        res.status = 401;
        res.set_content(json({{"error", "invalid credentials"}}).dump(), "application/json");
        return;
    }

    std::string email = body.value("email", "");
    std::string password = body.value("password", "");

    std::lock_guard<std::mutex> lock(g_db_mutex);

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT id, name, password_hash FROM users WHERE email = ?",
        -1, &stmt, nullptr);
    StmtGuard guard(stmt);

    if (rc != SQLITE_OK) {
        res.status = 401;
        res.set_content(json({{"error", "invalid credentials"}}).dump(), "application/json");
        return;
    }

    sqlite3_bind_text(stmt, 1, email.c_str(), -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        res.status = 401;
        res.set_content(json({{"error", "invalid credentials"}}).dump(), "application/json");
        return;
    }

    int64_t id = sqlite3_column_int64(stmt, 0);
    std::string name(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1)));
    std::string pw_hash(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2)));

    if (!verify_password(password, pw_hash)) {
        res.status = 401;
        res.set_content(json({{"error", "invalid credentials"}}).dump(), "application/json");
        return;
    }

    std::string token = jwt_encode(id);

    res.status = 200;
    res.set_content(json({
        {"token", token},
        {"user", {
            {"id", id},
            {"email", email},
            {"name", name}
        }}
    }).dump(), "application/json");
}

static void handle_list_spaces(const httplib::Request& req, httplib::Response& res) {
    std::string query = "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1";
    std::vector<std::string> params;

    if (req.has_param("min_price")) {
        std::string val = req.get_param_value("min_price");
        try {
            std::stod(val);
            query += " AND price_per_hour >= ?";
            params.push_back(val);
        } catch (...) {}
    }
    if (req.has_param("max_price")) {
        std::string val = req.get_param_value("max_price");
        try {
            std::stod(val);
            query += " AND price_per_hour <= ?";
            params.push_back(val);
        } catch (...) {}
    }
    if (req.has_param("available_at")) {
        std::string val = req.get_param_value("available_at");
        query += " AND id NOT IN (SELECT space_id FROM bookings WHERE status IN ('pending','confirmed') AND start_time < ? AND ? < end_time)";
        params.push_back(val);
        params.push_back(val);
    }

    std::lock_guard<std::mutex> lock(g_db_mutex);

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(g_db, query.c_str(), -1, &stmt, nullptr);
    StmtGuard guard(stmt);

    if (rc != SQLITE_OK) {
        res.status = 500;
        res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        return;
    }

    for (size_t i = 0; i < params.size(); ++i) {
        sqlite3_bind_text(stmt, static_cast<int>(i + 1), params[i].c_str(), -1, SQLITE_TRANSIENT);
    }

    json spaces = json::array();
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int64_t id = sqlite3_column_int64(stmt, 0);
        std::string name(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1)));

        std::string description = "";
        if (sqlite3_column_type(stmt, 2) != SQLITE_NULL) {
            description = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2));
        }

        double price = sqlite3_column_double(stmt, 3);
        int64_t owner_id = sqlite3_column_int64(stmt, 4);
        std::string created_at(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5)));

        spaces.push_back({
            {"id", id},
            {"name", name},
            {"description", description},
            {"price_per_hour", price},
            {"owner_id", owner_id},
            {"created_at", created_at}
        });
    }

    res.status = 200;
    res.set_content(spaces.dump(), "application/json");
}

static void handle_create_space(const httplib::Request& req, httplib::Response& res) {
    int64_t user_id = authenticate(req, res);
    if (user_id < 0) return;

    json body;
    try {
        body = json::parse(req.body);
    } catch (...) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    std::string name = body.value("name", "");
    std::string description = body.value("description", "");
    double price_per_hour = body.value("price_per_hour", 0.0);

    if (name.empty() || price_per_hour == 0) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    std::lock_guard<std::mutex> lock(g_db_mutex);

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(g_db,
        "INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)",
        -1, &stmt, nullptr);
    StmtGuard guard(stmt);

    if (rc != SQLITE_OK) {
        res.status = 500;
        res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        return;
    }

    sqlite3_bind_text(stmt, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, description.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 3, price_per_hour);
    sqlite3_bind_int64(stmt, 4, user_id);

    rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        res.status = 500;
        res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        return;
    }

    int64_t id = sqlite3_last_insert_rowid(g_db);

    // Fetch created_at
    sqlite3_stmt* stmt2 = nullptr;
    sqlite3_prepare_v2(g_db, "SELECT created_at FROM spaces WHERE id = ?", -1, &stmt2, nullptr);
    StmtGuard guard2(stmt2);
    sqlite3_bind_int64(stmt2, 1, id);

    std::string created_at;
    if (sqlite3_step(stmt2) == SQLITE_ROW) {
        created_at = reinterpret_cast<const char*>(sqlite3_column_text(stmt2, 0));
    }

    res.status = 201;
    res.set_content(json({
        {"id", id},
        {"name", name},
        {"description", description},
        {"price_per_hour", price_per_hour},
        {"owner_id", user_id},
        {"created_at", created_at}
    }).dump(), "application/json");
}

static void handle_my_bookings(const httplib::Request& req, httplib::Response& res) {
    int64_t user_id = authenticate(req, res);
    if (user_id < 0) return;

    std::lock_guard<std::mutex> lock(g_db_mutex);

    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(g_db,
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?",
        -1, &stmt, nullptr);
    StmtGuard guard(stmt);

    if (rc != SQLITE_OK) {
        res.status = 500;
        res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
        return;
    }

    sqlite3_bind_int64(stmt, 1, user_id);

    json bookings = json::array();
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        bookings.push_back({
            {"id", sqlite3_column_int64(stmt, 0)},
            {"space_id", sqlite3_column_int64(stmt, 1)},
            {"user_id", sqlite3_column_int64(stmt, 2)},
            {"start_time", std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3)))},
            {"end_time", std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 4)))},
            {"status", std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5)))},
            {"created_at", std::string(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 6)))}
        });
    }

    res.status = 200;
    res.set_content(bookings.dump(), "application/json");
}

static void handle_create_booking(const httplib::Request& req, httplib::Response& res) {
    int64_t user_id = authenticate(req, res);
    if (user_id < 0) return;

    json body;
    try {
        body = json::parse(req.body);
    } catch (...) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    int64_t space_id = body.value("space_id", (int64_t)0);
    std::string start_time = body.value("start_time", "");
    std::string end_time = body.value("end_time", "");

    if (space_id == 0 || start_time.empty() || end_time.empty()) {
        res.status = 400;
        res.set_content(json({{"error", "missing required fields"}}).dump(), "application/json");
        return;
    }

    std::lock_guard<std::mutex> lock(g_db_mutex);

    // Check space exists
    {
        sqlite3_stmt* stmt = nullptr;
        sqlite3_prepare_v2(g_db, "SELECT COUNT(*) FROM spaces WHERE id = ?", -1, &stmt, nullptr);
        StmtGuard guard(stmt);
        sqlite3_bind_int64(stmt, 1, space_id);

        int exists = 0;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            exists = sqlite3_column_int(stmt, 0);
        }
        if (exists == 0) {
            res.status = 404;
            res.set_content(json({{"error", "space not found"}}).dump(), "application/json");
            return;
        }
    }

    // Check overlap
    {
        sqlite3_stmt* stmt = nullptr;
        sqlite3_prepare_v2(g_db,
            "SELECT COUNT(*) FROM bookings "
            "WHERE space_id = ? AND status IN ('pending','confirmed') "
            "AND start_time < ? AND ? < end_time",
            -1, &stmt, nullptr);
        StmtGuard guard(stmt);
        sqlite3_bind_int64(stmt, 1, space_id);
        sqlite3_bind_text(stmt, 2, end_time.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, start_time.c_str(), -1, SQLITE_TRANSIENT);

        int overlap_count = 0;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            overlap_count = sqlite3_column_int(stmt, 0);
        }
        if (overlap_count > 0) {
            res.status = 409;
            res.set_content(json({{"error", "booking overlap"}}).dump(), "application/json");
            return;
        }
    }

    // Insert booking
    {
        sqlite3_stmt* stmt = nullptr;
        sqlite3_prepare_v2(g_db,
            "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) "
            "VALUES (?, ?, ?, ?, 'confirmed')",
            -1, &stmt, nullptr);
        StmtGuard guard(stmt);
        sqlite3_bind_int64(stmt, 1, space_id);
        sqlite3_bind_int64(stmt, 2, user_id);
        sqlite3_bind_text(stmt, 3, start_time.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, end_time.c_str(), -1, SQLITE_TRANSIENT);

        int rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            res.status = 500;
            res.set_content(json({{"error", "internal error"}}).dump(), "application/json");
            return;
        }
    }

    int64_t id = sqlite3_last_insert_rowid(g_db);

    // Fetch created_at
    std::string created_at;
    {
        sqlite3_stmt* stmt = nullptr;
        sqlite3_prepare_v2(g_db, "SELECT created_at FROM bookings WHERE id = ?", -1, &stmt, nullptr);
        StmtGuard guard(stmt);
        sqlite3_bind_int64(stmt, 1, id);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            created_at = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        }
    }

    res.status = 201;
    res.set_content(json({
        {"id", id},
        {"space_id", space_id},
        {"user_id", user_id},
        {"start_time", start_time},
        {"end_time", end_time},
        {"status", "confirmed"},
        {"created_at", created_at}
    }).dump(), "application/json");
}

static void handle_cancel_booking(const httplib::Request& req, httplib::Response& res) {
    int64_t user_id = authenticate(req, res);
    if (user_id < 0) return;

    int64_t booking_id;
    try {
        booking_id = std::stoll(req.matches[1]);
    } catch (...) {
        res.status = 404;
        res.set_content(json({{"error", "booking not found"}}).dump(), "application/json");
        return;
    }

    std::lock_guard<std::mutex> lock(g_db_mutex);

    // Fetch booking
    sqlite3_stmt* stmt = nullptr;
    sqlite3_prepare_v2(g_db,
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?",
        -1, &stmt, nullptr);
    StmtGuard guard(stmt);
    sqlite3_bind_int64(stmt, 1, booking_id);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        res.status = 404;
        res.set_content(json({{"error", "booking not found"}}).dump(), "application/json");
        return;
    }

    int64_t id = sqlite3_column_int64(stmt, 0);
    int64_t space_id = sqlite3_column_int64(stmt, 1);
    int64_t owner_id = sqlite3_column_int64(stmt, 2);
    std::string start_time(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3)));
    std::string end_time(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 4)));
    std::string status(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5)));
    std::string created_at(reinterpret_cast<const char*>(sqlite3_column_text(stmt, 6)));

    if (owner_id != user_id) {
        res.status = 403;
        res.set_content(json({{"error", "forbidden"}}).dump(), "application/json");
        return;
    }

    // Update status
    sqlite3_exec(g_db, ("UPDATE bookings SET status = 'cancelled' WHERE id = " + std::to_string(booking_id)).c_str(),
                 nullptr, nullptr, nullptr);

    res.status = 200;
    res.set_content(json({
        {"id", id},
        {"space_id", space_id},
        {"user_id", owner_id},
        {"start_time", start_time},
        {"end_time", end_time},
        {"status", "cancelled"},
        {"created_at", created_at}
    }).dump(), "application/json");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main() {
    init_db();

    httplib::Server svr;

    // Auth routes
    svr.Post("/api/auth/register", handle_register);
    svr.Post("/api/auth/login", handle_login);

    // Public routes
    svr.Get("/api/spaces", handle_list_spaces);

    // Protected routes
    svr.Post("/api/spaces", handle_create_space);
    svr.Get("/api/bookings/my", handle_my_bookings);
    svr.Post("/api/bookings", handle_create_booking);
    svr.Delete(R"(/api/bookings/(\d+))", handle_cancel_booking);

    std::cout << "Booking API (C++) listening on :8080" << std::endl;
    svr.listen("0.0.0.0", 8080);

    sqlite3_close(g_db);
    return 0;
}
