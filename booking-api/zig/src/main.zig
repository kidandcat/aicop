const std = @import("std");
const posix = std.posix;
const net = std.net;
const mem = std.mem;
const Sha256 = std.crypto.hash.sha2.Sha256;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

const c = @cImport({
    @cInclude("sqlite3.h");
});

// --- Constants ---

const jwt_secret = "booking-api-secret-key-2026";
const password_salt = "booking-api-salt-2026";
const listen_port: u16 = 8080;
const max_request_size: usize = 1024 * 1024; // 1MB
const read_buf_size: usize = 8192;

// --- Global state ---

var db: ?*c.sqlite3 = null;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// --- Main ---

pub fn main() !void {
    initDB();

    const address = net.Address.parseIp4("0.0.0.0", listen_port) catch unreachable;
    var server = address.listen(.{ .reuse_address = true }) catch |err| {
        std.log.err("Failed to listen on port {d}: {}", .{ listen_port, err });
        return err;
    };
    defer server.deinit();

    std.log.info("Booking API listening on port {d}", .{listen_port});

    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("Accept error: {}", .{err});
            continue;
        };

        handleConnection(conn.stream) catch |err| {
            std.log.err("Connection error: {}", .{err});
        };
        conn.stream.close();
    }
}

// --- Database ---

fn initDB() void {
    const base_dir = std.posix.getenv("WORKDIR") orelse ".";

    // Build DB path
    const db_path = std.fmt.allocPrintSentinel(allocator, "{s}/booking.db", .{base_dir}, 0) catch @panic("OOM");

    // Open DB
    var rc = c.sqlite3_open(db_path.ptr, &db);
    if (rc != c.SQLITE_OK) {
        std.log.err("Failed to open database: {s}", .{c.sqlite3_errmsg(db)});
        std.process.exit(1);
    }

    // Enable pragmas
    execSQL("PRAGMA journal_mode=WAL");
    execSQL("PRAGMA busy_timeout=5000");
    execSQL("PRAGMA foreign_keys = ON");

    // Read and execute schema
    const schema_path = std.fmt.allocPrintSentinel(allocator, "{s}/schema.sql", .{base_dir}, 0) catch @panic("OOM");

    const schema_file = std.fs.cwd().openFile(schema_path, .{}) catch |err| {
        std.log.err("Failed to open schema file '{s}': {}", .{ schema_path, err });
        std.process.exit(1);
    };
    defer schema_file.close();

    const schema = schema_file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.log.err("Failed to read schema file: {}", .{err});
        std.process.exit(1);
    };
    defer allocator.free(schema);

    const schema_z = allocator.dupeZ(u8, schema) catch @panic("OOM");
    defer allocator.free(schema_z);

    rc = c.sqlite3_exec(db, schema_z.ptr, null, null, null);
    if (rc != c.SQLITE_OK) {
        std.log.err("Failed to execute schema: {s}", .{c.sqlite3_errmsg(db)});
        std.process.exit(1);
    }
}

fn execSQL(sql: [*:0]const u8) void {
    const rc = c.sqlite3_exec(db, sql, null, null, null);
    if (rc != c.SQLITE_OK) {
        std.log.err("SQL error: {s}", .{c.sqlite3_errmsg(db)});
    }
}

// --- HTTP Request Parsing ---

const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    query: ?[]const u8,
    body: []const u8,
    authorization: ?[]const u8,
    content_length: usize,
};

fn parseHttpRequest(raw: []const u8) ?HttpRequest {
    // Find end of headers
    const header_end = mem.indexOf(u8, raw, "\r\n\r\n") orelse return null;
    const headers_section = raw[0..header_end];
    const body_start = header_end + 4;

    // Parse request line
    const first_line_end = mem.indexOf(u8, headers_section, "\r\n") orelse return null;
    const request_line = headers_section[0..first_line_end];

    // Parse method
    const method_end = mem.indexOf(u8, request_line, " ") orelse return null;
    const method = request_line[0..method_end];

    // Parse path (after method space, before HTTP version space)
    const rest_after_method = request_line[method_end + 1 ..];
    const path_end = mem.indexOf(u8, rest_after_method, " ") orelse return null;
    const full_path = rest_after_method[0..path_end];

    // Split path and query
    var path: []const u8 = full_path;
    var query: ?[]const u8 = null;
    if (mem.indexOf(u8, full_path, "?")) |q_pos| {
        path = full_path[0..q_pos];
        query = full_path[q_pos + 1 ..];
    }

    // Parse headers
    var authorization: ?[]const u8 = null;
    var content_length: usize = 0;

    const headers_rest = headers_section[first_line_end + 2 ..];
    var line_iter = mem.splitSequence(u8, headers_rest, "\r\n");
    while (line_iter.next()) |line| {
        if (line.len == 0) break;
        const colon_pos = mem.indexOf(u8, line, ":") orelse continue;
        const header_name = line[0..colon_pos];
        var header_value = line[colon_pos + 1 ..];
        // Trim leading spaces
        while (header_value.len > 0 and header_value[0] == ' ') {
            header_value = header_value[1..];
        }

        if (std.ascii.eqlIgnoreCase(header_name, "authorization")) {
            authorization = header_value;
        } else if (std.ascii.eqlIgnoreCase(header_name, "content-length")) {
            content_length = std.fmt.parseInt(usize, header_value, 10) catch 0;
        }
    }

    const body = if (body_start + content_length <= raw.len)
        raw[body_start .. body_start + content_length]
    else if (body_start < raw.len)
        raw[body_start..]
    else
        raw[raw.len..raw.len];

    return HttpRequest{
        .method = method,
        .path = path,
        .query = query,
        .body = body,
        .authorization = authorization,
        .content_length = content_length,
    };
}

// --- HTTP Response Writing ---

fn writeResponse(stream: net.Stream, status_code: u16, status_text: []const u8, body: []const u8) void {
    var buf: [64]u8 = undefined;
    const content_len_str = std.fmt.bufPrint(&buf, "{d}", .{body.len}) catch "0";

    stream.writeAll("HTTP/1.1 ") catch return;
    var status_buf: [4]u8 = undefined;
    const status_str = std.fmt.bufPrint(&status_buf, "{d}", .{status_code}) catch "500";
    stream.writeAll(status_str) catch return;
    stream.writeAll(" ") catch return;
    stream.writeAll(status_text) catch return;
    stream.writeAll("\r\nContent-Type: application/json\r\nContent-Length: ") catch return;
    stream.writeAll(content_len_str) catch return;
    stream.writeAll("\r\nConnection: close\r\n\r\n") catch return;
    stream.writeAll(body) catch return;
}

fn jsonError(stream: net.Stream, status_code: u16, status_text: []const u8, err_msg: []const u8) void {
    var buf: [256]u8 = undefined;
    const body = std.fmt.bufPrint(&buf, "{{\"error\":\"{s}\"}}", .{err_msg}) catch "{\"error\":\"internal error\"}";
    writeResponse(stream, status_code, status_text, body);
}

// --- Connection Handler ---

fn handleConnection(stream: net.Stream) !void {
    var buf: [max_request_size]u8 = undefined;
    var total_read: usize = 0;

    // Read until we have the complete request
    while (total_read < buf.len) {
        const n = stream.read(buf[total_read..]) catch |err| {
            std.log.err("Read error: {}", .{err});
            return;
        };
        if (n == 0) break;
        total_read += n;

        // Check if we have complete headers
        if (mem.indexOf(u8, buf[0..total_read], "\r\n\r\n")) |header_end| {
            // Parse content-length to see if we need more body
            const headers = buf[0..header_end];
            var cl: usize = 0;
            var line_iter = mem.splitSequence(u8, headers, "\r\n");
            while (line_iter.next()) |line| {
                if (line.len > 16 and std.ascii.eqlIgnoreCase(line[0..15], "content-length:")) {
                    var val = line[15..];
                    while (val.len > 0 and val[0] == ' ') val = val[1..];
                    cl = std.fmt.parseInt(usize, val, 10) catch 0;
                }
            }
            const body_start = header_end + 4;
            const body_received = total_read - body_start;
            if (body_received >= cl) break;
        }
    }

    const raw = buf[0..total_read];
    const request = parseHttpRequest(raw) orelse {
        jsonError(stream, 400, "Bad Request", "bad request");
        return;
    };

    routeRequest(stream, request);
}

// --- Router ---

fn routeRequest(stream: net.Stream, req: HttpRequest) void {
    if (mem.eql(u8, req.method, "POST") and mem.eql(u8, req.path, "/api/auth/register")) {
        handleRegister(stream, req);
    } else if (mem.eql(u8, req.method, "POST") and mem.eql(u8, req.path, "/api/auth/login")) {
        handleLogin(stream, req);
    } else if (mem.eql(u8, req.method, "GET") and mem.eql(u8, req.path, "/api/spaces")) {
        handleListSpaces(stream, req);
    } else if (mem.eql(u8, req.method, "POST") and mem.eql(u8, req.path, "/api/spaces")) {
        withAuth(stream, req, handleCreateSpace);
    } else if (mem.eql(u8, req.method, "GET") and mem.eql(u8, req.path, "/api/bookings/my")) {
        withAuth(stream, req, handleMyBookings);
    } else if (mem.eql(u8, req.method, "POST") and mem.eql(u8, req.path, "/api/bookings")) {
        withAuth(stream, req, handleCreateBooking);
    } else if (mem.eql(u8, req.method, "DELETE") and mem.startsWith(u8, req.path, "/api/bookings/")) {
        withAuth(stream, req, handleCancelBooking);
    } else {
        jsonError(stream, 404, "Not Found", "not found");
    }
}

// --- Auth Middleware ---

fn withAuth(stream: net.Stream, req: HttpRequest, handler: *const fn (net.Stream, HttpRequest, i64) void) void {
    const user_id = authenticateRequest(req) orelse {
        jsonError(stream, 401, "Unauthorized", "unauthorized");
        return;
    };
    handler(stream, req, user_id);
}

fn authenticateRequest(req: HttpRequest) ?i64 {
    const auth_header = req.authorization orelse return null;
    if (!mem.startsWith(u8, auth_header, "Bearer ")) return null;
    const token = auth_header[7..];
    return verifyJWT(token);
}

// --- Password Hashing (SHA-256 with salt) ---

fn hashPassword(password: []const u8) [64]u8 {
    var hasher = Sha256.init(.{});
    hasher.update(password_salt);
    hasher.update(password);
    const digest = hasher.finalResult();

    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        const high = byte >> 4;
        const low = byte & 0x0f;
        hex[i * 2] = if (high < 10) '0' + high else 'a' + high - 10;
        hex[i * 2 + 1] = if (low < 10) '0' + low else 'a' + low - 10;
    }
    return hex;
}

fn verifyPassword(password: []const u8, stored_hash: []const u8) bool {
    const computed = hashPassword(password);
    return mem.eql(u8, &computed, stored_hash);
}

// --- JWT (HS256) ---

fn base64UrlEncode(data: []const u8, out: []u8) usize {
    const b64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    var i: usize = 0;
    var o: usize = 0;

    while (i < data.len) {
        const b0 = data[i];
        const b1 = if (i + 1 < data.len) data[i + 1] else 0;
        const b2 = if (i + 2 < data.len) data[i + 2] else 0;

        out[o] = b64_alphabet[@as(usize, b0 >> 2)];
        out[o + 1] = b64_alphabet[@as(usize, ((b0 & 0x03) << 4) | (b1 >> 4))];

        if (i + 1 < data.len) {
            out[o + 2] = b64_alphabet[@as(usize, ((b1 & 0x0f) << 2) | (b2 >> 6))];
        } else {
            o += 2;
            break;
        }

        if (i + 2 < data.len) {
            out[o + 3] = b64_alphabet[@as(usize, b2 & 0x3f)];
        } else {
            o += 3;
            break;
        }

        i += 3;
        o += 4;
    }

    return o;
}

fn base64UrlDecode(encoded: []const u8, out: []u8) ?usize {
    var i: usize = 0;
    var o: usize = 0;

    while (i < encoded.len) {
        const v0 = b64UrlCharVal(encoded[i]) orelse return null;
        if (i + 1 >= encoded.len) return null;
        const v1 = b64UrlCharVal(encoded[i + 1]) orelse return null;

        if (o >= out.len) return null;
        out[o] = (v0 << 2) | (v1 >> 4);
        o += 1;

        if (i + 2 < encoded.len) {
            const v2 = b64UrlCharVal(encoded[i + 2]) orelse return null;
            if (o >= out.len) return null;
            out[o] = ((v1 & 0x0f) << 4) | (v2 >> 2);
            o += 1;

            if (i + 3 < encoded.len) {
                const v3 = b64UrlCharVal(encoded[i + 3]) orelse return null;
                if (o >= out.len) return null;
                out[o] = ((v2 & 0x03) << 6) | v3;
                o += 1;
                i += 4;
            } else {
                i += 3;
            }
        } else {
            i += 2;
        }
    }

    return o;
}

fn b64UrlCharVal(ch: u8) ?u8 {
    if (ch >= 'A' and ch <= 'Z') return ch - 'A';
    if (ch >= 'a' and ch <= 'z') return ch - 'a' + 26;
    if (ch >= '0' and ch <= '9') return ch - '0' + 52;
    if (ch == '-') return 62;
    if (ch == '_') return 63;
    if (ch == '=') return 0; // padding
    return null;
}

fn generateJWT(user_id: i64) ?[]const u8 {
    const header = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
    const exp_time = std.time.timestamp() + 86400; // 24 hours

    var payload_buf: [256]u8 = undefined;
    const payload = std.fmt.bufPrint(&payload_buf, "{{\"user_id\":{d},\"exp\":{d}}}", .{ user_id, exp_time }) catch return null;

    var header_enc: [128]u8 = undefined;
    const header_len = base64UrlEncode(header, &header_enc);

    var payload_enc: [512]u8 = undefined;
    const payload_len = base64UrlEncode(payload, &payload_enc);

    // Sign: HMAC-SHA256(header_b64 + "." + payload_b64)
    var signing_input_buf: [1024]u8 = undefined;
    const signing_input_len = header_len + 1 + payload_len;
    if (signing_input_len > signing_input_buf.len) return null;
    @memcpy(signing_input_buf[0..header_len], header_enc[0..header_len]);
    signing_input_buf[header_len] = '.';
    @memcpy(signing_input_buf[header_len + 1 .. signing_input_len], payload_enc[0..payload_len]);

    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input_buf[0..signing_input_len], jwt_secret);

    var sig_enc: [128]u8 = undefined;
    const sig_len = base64UrlEncode(&mac, &sig_enc);

    // Concatenate: header.payload.signature
    const total_len = header_len + 1 + payload_len + 1 + sig_len;
    const result = allocator.alloc(u8, total_len) catch return null;
    @memcpy(result[0..header_len], header_enc[0..header_len]);
    result[header_len] = '.';
    @memcpy(result[header_len + 1 .. header_len + 1 + payload_len], payload_enc[0..payload_len]);
    result[header_len + 1 + payload_len] = '.';
    @memcpy(result[header_len + 1 + payload_len + 1 .. total_len], sig_enc[0..sig_len]);

    return result;
}

fn verifyJWT(token: []const u8) ?i64 {
    // Split into 3 parts
    const first_dot = mem.indexOf(u8, token, ".") orelse return null;
    const rest = token[first_dot + 1 ..];
    const second_dot = mem.indexOf(u8, rest, ".") orelse return null;

    const payload_b64 = rest[0..second_dot];
    const sig_b64 = rest[second_dot + 1 ..];

    // Verify signature
    const signing_input_len = first_dot + 1 + second_dot;
    if (signing_input_len > 1024) return null;

    var expected_mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&expected_mac, token[0..signing_input_len], jwt_secret);

    var sig_decoded: [64]u8 = undefined;
    const sig_len = base64UrlDecode(sig_b64, &sig_decoded) orelse return null;
    if (sig_len != HmacSha256.mac_length) return null;

    if (!mem.eql(u8, expected_mac[0..], sig_decoded[0..sig_len])) return null;

    // Decode payload
    var payload_decoded: [512]u8 = undefined;
    const payload_len = base64UrlDecode(payload_b64, &payload_decoded) orelse return null;
    const payload_str = payload_decoded[0..payload_len];

    // Extract user_id from JSON payload
    return extractJsonInt(payload_str, "user_id");
}

// --- Simple JSON Parsing ---

fn extractJsonString(json_bytes: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":"value" or "key": "value"
    var search_buf: [128]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = mem.indexOf(u8, json_bytes, search_key) orelse return null;
    var pos = key_pos + search_key.len;

    // Skip whitespace and colon
    while (pos < json_bytes.len and (json_bytes[pos] == ' ' or json_bytes[pos] == ':' or json_bytes[pos] == '\t' or json_bytes[pos] == '\n' or json_bytes[pos] == '\r')) {
        pos += 1;
    }

    if (pos >= json_bytes.len) return null;

    if (json_bytes[pos] == '"') {
        pos += 1; // skip opening quote
        const end = mem.indexOf(u8, json_bytes[pos..], "\"") orelse return null;
        return json_bytes[pos .. pos + end];
    }

    return null;
}

fn extractJsonInt(json_bytes: []const u8, key: []const u8) ?i64 {
    var search_buf: [128]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = mem.indexOf(u8, json_bytes, search_key) orelse return null;
    var pos = key_pos + search_key.len;

    // Skip whitespace and colon
    while (pos < json_bytes.len and (json_bytes[pos] == ' ' or json_bytes[pos] == ':' or json_bytes[pos] == '\t' or json_bytes[pos] == '\n' or json_bytes[pos] == '\r')) {
        pos += 1;
    }

    if (pos >= json_bytes.len) return null;

    // Find end of number
    var end = pos;
    if (end < json_bytes.len and json_bytes[end] == '-') end += 1;
    while (end < json_bytes.len and json_bytes[end] >= '0' and json_bytes[end] <= '9') {
        end += 1;
    }

    if (end == pos) return null;
    return std.fmt.parseInt(i64, json_bytes[pos..end], 10) catch return null;
}

fn extractJsonFloat(json_bytes: []const u8, key: []const u8) ?f64 {
    var search_buf: [128]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "\"{s}\"", .{key}) catch return null;

    const key_pos = mem.indexOf(u8, json_bytes, search_key) orelse return null;
    var pos = key_pos + search_key.len;

    // Skip whitespace and colon
    while (pos < json_bytes.len and (json_bytes[pos] == ' ' or json_bytes[pos] == ':' or json_bytes[pos] == '\t' or json_bytes[pos] == '\n' or json_bytes[pos] == '\r')) {
        pos += 1;
    }

    if (pos >= json_bytes.len) return null;

    // Find end of number (digits, dot, minus, e, E)
    var end = pos;
    while (end < json_bytes.len and (json_bytes[end] == '-' or json_bytes[end] == '+' or json_bytes[end] == '.' or json_bytes[end] == 'e' or json_bytes[end] == 'E' or (json_bytes[end] >= '0' and json_bytes[end] <= '9'))) {
        end += 1;
    }

    if (end == pos) return null;
    return std.fmt.parseFloat(f64, json_bytes[pos..end]) catch return null;
}

// --- JSON String Escaping ---

fn jsonEscapeString(input: []const u8, out: []u8) usize {
    var o: usize = 0;
    for (input) |ch| {
        switch (ch) {
            '"' => {
                if (o + 2 > out.len) break;
                out[o] = '\\';
                out[o + 1] = '"';
                o += 2;
            },
            '\\' => {
                if (o + 2 > out.len) break;
                out[o] = '\\';
                out[o + 1] = '\\';
                o += 2;
            },
            '\n' => {
                if (o + 2 > out.len) break;
                out[o] = '\\';
                out[o + 1] = 'n';
                o += 2;
            },
            '\r' => {
                if (o + 2 > out.len) break;
                out[o] = '\\';
                out[o + 1] = 'r';
                o += 2;
            },
            '\t' => {
                if (o + 2 > out.len) break;
                out[o] = '\\';
                out[o + 1] = 't';
                o += 2;
            },
            else => {
                if (o + 1 > out.len) break;
                out[o] = ch;
                o += 1;
            },
        }
    }
    return o;
}

// --- Format price: always show as a number, remove trailing zeros but keep at least one decimal ---

fn formatPrice(price: f64, buf: []u8) []const u8 {
    // Check if it's a whole number
    const rounded = @round(price);
    if (@abs(price - rounded) < 0.0001) {
        // Whole number - format as integer
        const int_val = @as(i64, @intFromFloat(rounded));
        const len = std.fmt.bufPrint(buf, "{d}", .{int_val}) catch return "0";
        return buf[0..len.len];
    }

    // Format with enough decimals
    const len = std.fmt.bufPrint(buf, "{d:.2}", .{price}) catch return "0";
    // Remove trailing zeros after decimal point
    var end: usize = len.len;
    while (end > 0 and buf[end - 1] == '0') {
        end -= 1;
    }
    if (end > 0 and buf[end - 1] == '.') {
        end -= 1;
    }
    return buf[0..end];
}

// --- Query Parameter Parsing ---

fn getQueryParam(query: ?[]const u8, key: []const u8) ?[]const u8 {
    const q = query orelse return null;
    var iter = mem.splitScalar(u8, q, '&');
    while (iter.next()) |param| {
        if (mem.indexOf(u8, param, "=")) |eq_pos| {
            const param_key = param[0..eq_pos];
            const param_val = param[eq_pos + 1 ..];
            if (mem.eql(u8, param_key, key)) {
                return param_val;
            }
        }
    }
    return null;
}

// --- SQLite helpers ---

fn sqliteColumnText(stmt: ?*c.sqlite3_stmt, col: c_int) []const u8 {
    const ptr = c.sqlite3_column_text(stmt, col);
    if (ptr == null) return "";
    const len = c.sqlite3_column_bytes(stmt, col);
    if (len <= 0) return "";
    return @as([*]const u8, @ptrCast(ptr))[0..@as(usize, @intCast(len))];
}

fn sqliteBindText(stmt: ?*c.sqlite3_stmt, col: c_int, text: []const u8) void {
    // Use SQLITE_STATIC (null) since data remains valid through sqlite3_step
    _ = c.sqlite3_bind_text(stmt, col, text.ptr, @as(c_int, @intCast(text.len)), null);
}

fn sqliteBindInt64(stmt: ?*c.sqlite3_stmt, col: c_int, val: i64) void {
    _ = c.sqlite3_bind_int64(stmt, col, val);
}

fn sqliteBindDouble(stmt: ?*c.sqlite3_stmt, col: c_int, val: f64) void {
    _ = c.sqlite3_bind_double(stmt, col, val);
}

// --- Handlers ---

fn handleRegister(stream: net.Stream, req: HttpRequest) void {
    const email = extractJsonString(req.body, "email") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };
    const name = extractJsonString(req.body, "name") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };
    const password = extractJsonString(req.body, "password") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };

    if (email.len == 0 or name.len == 0 or password.len == 0) {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    }

    const password_hash = hashPassword(password);

    // Insert user
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, "INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)", -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    sqliteBindText(stmt, 1, email);
    sqliteBindText(stmt, 2, name);
    sqliteBindText(stmt, 3, &password_hash);

    rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_DONE) {
        const err_msg_ptr = c.sqlite3_errmsg(db);
        if (err_msg_ptr != null) {
            const err_msg_len = mem.len(@as([*:0]const u8, err_msg_ptr));
            const err_msg = @as([*]const u8, @ptrCast(err_msg_ptr))[0..err_msg_len];
            if (mem.indexOf(u8, err_msg, "UNIQUE") != null) {
                jsonError(stream, 409, "Conflict", "email already exists");
                return;
            }
        }
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }

    const user_id = c.sqlite3_last_insert_rowid(db);

    // Escape strings for JSON
    var email_esc: [512]u8 = undefined;
    const email_esc_len = jsonEscapeString(email, &email_esc);
    var name_esc: [512]u8 = undefined;
    const name_esc_len = jsonEscapeString(name, &name_esc);

    var body_buf: [1024]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"id\":{d},\"email\":\"{s}\",\"name\":\"{s}\"}}", .{
        user_id,
        email_esc[0..email_esc_len],
        name_esc[0..name_esc_len],
    }) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };

    writeResponse(stream, 201, "Created", body);
}

fn handleLogin(stream: net.Stream, req: HttpRequest) void {
    const email = extractJsonString(req.body, "email") orelse {
        jsonError(stream, 401, "Unauthorized", "invalid credentials");
        return;
    };
    const password = extractJsonString(req.body, "password") orelse {
        jsonError(stream, 401, "Unauthorized", "invalid credentials");
        return;
    };

    // Look up user
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, "SELECT id, name, password_hash FROM users WHERE email = ?", -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    sqliteBindText(stmt, 1, email);

    rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_ROW) {
        jsonError(stream, 401, "Unauthorized", "invalid credentials");
        return;
    }

    const user_id = c.sqlite3_column_int64(stmt, 0);
    const name = sqliteColumnText(stmt, 1);
    const stored_hash = sqliteColumnText(stmt, 2);

    if (!verifyPassword(password, stored_hash)) {
        jsonError(stream, 401, "Unauthorized", "invalid credentials");
        return;
    }

    // Copy name since stmt will be finalized
    var name_copy: [256]u8 = undefined;
    const name_len = @min(name.len, name_copy.len);
    @memcpy(name_copy[0..name_len], name[0..name_len]);

    const token = generateJWT(user_id) orelse {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };
    defer allocator.free(token);

    var email_esc: [512]u8 = undefined;
    const email_esc_len = jsonEscapeString(email, &email_esc);
    var name_esc: [512]u8 = undefined;
    const name_esc_len = jsonEscapeString(name_copy[0..name_len], &name_esc);

    var body_buf: [2048]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"token\":\"{s}\",\"user\":{{\"id\":{d},\"email\":\"{s}\",\"name\":\"{s}\"}}}}", .{
        token,
        user_id,
        email_esc[0..email_esc_len],
        name_esc[0..name_esc_len],
    }) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };

    writeResponse(stream, 200, "OK", body);
}

fn handleListSpaces(stream: net.Stream, req: HttpRequest) void {
    var query_buf: [1024]u8 = undefined;
    var query_len: usize = 0;

    const base_query = "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1";
    @memcpy(query_buf[0..base_query.len], base_query);
    query_len = base_query.len;

    var bind_values: [4]f64 = undefined;
    var bind_count: usize = 0;

    if (getQueryParam(req.query, "min_price")) |min_price_str| {
        if (std.fmt.parseFloat(f64, min_price_str)) |_| {
            const clause = " AND price_per_hour >= ?";
            @memcpy(query_buf[query_len .. query_len + clause.len], clause);
            query_len += clause.len;
            bind_values[bind_count] = std.fmt.parseFloat(f64, min_price_str) catch 0;
            bind_count += 1;
        } else |_| {}
    }

    if (getQueryParam(req.query, "max_price")) |max_price_str| {
        if (std.fmt.parseFloat(f64, max_price_str)) |_| {
            const clause = " AND price_per_hour <= ?";
            @memcpy(query_buf[query_len .. query_len + clause.len], clause);
            query_len += clause.len;
            bind_values[bind_count] = std.fmt.parseFloat(f64, max_price_str) catch 0;
            bind_count += 1;
        } else |_| {}
    }

    const query_z = allocator.dupeZ(u8, query_buf[0..query_len]) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };
    defer allocator.free(query_z);

    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, query_z.ptr, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    for (0..bind_count) |i| {
        sqliteBindDouble(stmt, @as(c_int, @intCast(i + 1)), bind_values[i]);
    }

    // Build JSON array
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    result.appendSlice(allocator, "[") catch return;

    var first = true;
    while (true) {
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) break;

        if (!first) {
            result.appendSlice(allocator, ",") catch return;
        }
        first = false;

        const id = c.sqlite3_column_int64(stmt, 0);
        const name = sqliteColumnText(stmt, 1);
        const description = sqliteColumnText(stmt, 2);
        const price = c.sqlite3_column_double(stmt, 3);
        const owner_id = c.sqlite3_column_int64(stmt, 4);
        const created_at = sqliteColumnText(stmt, 5);

        var name_esc: [512]u8 = undefined;
        const name_esc_len = jsonEscapeString(name, &name_esc);
        var desc_esc: [1024]u8 = undefined;
        const desc_esc_len = jsonEscapeString(description, &desc_esc);
        var created_at_esc: [128]u8 = undefined;
        const created_at_esc_len = jsonEscapeString(created_at, &created_at_esc);

        var price_buf: [64]u8 = undefined;
        const price_str = formatPrice(price, &price_buf);

        var entry_buf: [2048]u8 = undefined;
        const entry = std.fmt.bufPrint(&entry_buf, "{{\"id\":{d},\"name\":\"{s}\",\"description\":\"{s}\",\"price_per_hour\":{s},\"owner_id\":{d},\"created_at\":\"{s}\"}}", .{
            id,
            name_esc[0..name_esc_len],
            desc_esc[0..desc_esc_len],
            price_str,
            owner_id,
            created_at_esc[0..created_at_esc_len],
        }) catch continue;

        result.appendSlice(allocator, entry) catch return;
    }

    result.appendSlice(allocator, "]") catch return;

    writeResponse(stream, 200, "OK", result.items);
}

fn handleCreateSpace(stream: net.Stream, req: HttpRequest, user_id: i64) void {
    const name = extractJsonString(req.body, "name") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };
    const description = extractJsonString(req.body, "description") orelse "";
    const price = extractJsonFloat(req.body, "price_per_hour") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };

    if (name.len == 0 or price == 0) {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    }

    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, "INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)", -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    sqliteBindText(stmt, 1, name);
    sqliteBindText(stmt, 2, description);
    sqliteBindDouble(stmt, 3, price);
    sqliteBindInt64(stmt, 4, user_id);

    rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_DONE) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }

    const space_id = c.sqlite3_last_insert_rowid(db);

    // Get created_at
    var stmt2: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, "SELECT created_at FROM spaces WHERE id = ?", -1, &stmt2, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt2);

    sqliteBindInt64(stmt2, 1, space_id);
    rc = c.sqlite3_step(stmt2);

    var created_at_copy: [64]u8 = undefined;
    var created_at_len: usize = 0;
    if (rc == c.SQLITE_ROW) {
        const ca = sqliteColumnText(stmt2, 0);
        created_at_len = @min(ca.len, created_at_copy.len);
        @memcpy(created_at_copy[0..created_at_len], ca[0..created_at_len]);
    }

    var name_esc: [512]u8 = undefined;
    const name_esc_len = jsonEscapeString(name, &name_esc);
    var desc_esc: [1024]u8 = undefined;
    const desc_esc_len = jsonEscapeString(description, &desc_esc);

    var price_buf: [64]u8 = undefined;
    const price_str = formatPrice(price, &price_buf);

    var body_buf: [2048]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"id\":{d},\"name\":\"{s}\",\"description\":\"{s}\",\"price_per_hour\":{s},\"owner_id\":{d},\"created_at\":\"{s}\"}}", .{
        space_id,
        name_esc[0..name_esc_len],
        desc_esc[0..desc_esc_len],
        price_str,
        user_id,
        created_at_copy[0..created_at_len],
    }) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };

    writeResponse(stream, 201, "Created", body);
}

fn handleMyBookings(stream: net.Stream, _: HttpRequest, user_id: i64) void {
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?", -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    sqliteBindInt64(stmt, 1, user_id);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    result.appendSlice(allocator, "[") catch return;

    var first = true;
    while (true) {
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) break;

        if (!first) {
            result.appendSlice(allocator, ",") catch return;
        }
        first = false;

        const id = c.sqlite3_column_int64(stmt, 0);
        const space_id = c.sqlite3_column_int64(stmt, 1);
        const uid = c.sqlite3_column_int64(stmt, 2);
        const start_time = sqliteColumnText(stmt, 3);
        const end_time = sqliteColumnText(stmt, 4);
        const status = sqliteColumnText(stmt, 5);
        const created_at = sqliteColumnText(stmt, 6);

        var entry_buf: [1024]u8 = undefined;
        const entry = std.fmt.bufPrint(&entry_buf, "{{\"id\":{d},\"space_id\":{d},\"user_id\":{d},\"start_time\":\"{s}\",\"end_time\":\"{s}\",\"status\":\"{s}\",\"created_at\":\"{s}\"}}", .{
            id,
            space_id,
            uid,
            start_time,
            end_time,
            status,
            created_at,
        }) catch continue;

        result.appendSlice(allocator, entry) catch return;
    }

    result.appendSlice(allocator, "]") catch return;

    writeResponse(stream, 200, "OK", result.items);
}

fn handleCreateBooking(stream: net.Stream, req: HttpRequest, user_id: i64) void {
    const space_id = extractJsonInt(req.body, "space_id") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };
    const start_time = extractJsonString(req.body, "start_time") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };
    const end_time = extractJsonString(req.body, "end_time") orelse {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    };

    if (space_id == 0 or start_time.len == 0 or end_time.len == 0) {
        jsonError(stream, 400, "Bad Request", "missing required fields");
        return;
    }

    // Check space exists
    {
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM spaces WHERE id = ?", -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        sqliteBindInt64(stmt, 1, space_id);
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW or c.sqlite3_column_int(stmt, 0) == 0) {
            jsonError(stream, 404, "Not Found", "space not found");
            return;
        }
    }

    // Check overlap
    {
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM bookings WHERE space_id = ? AND status IN ('pending','confirmed') AND start_time < ? AND ? < end_time", -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        sqliteBindInt64(stmt, 1, space_id);
        sqliteBindText(stmt, 2, end_time);
        sqliteBindText(stmt, 3, start_time);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }

        if (c.sqlite3_column_int(stmt, 0) > 0) {
            jsonError(stream, 409, "Conflict", "booking overlap");
            return;
        }
    }

    // Insert booking
    {
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(db, "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) VALUES (?, ?, ?, ?, 'confirmed')", -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        sqliteBindInt64(stmt, 1, space_id);
        sqliteBindInt64(stmt, 2, user_id);
        sqliteBindText(stmt, 3, start_time);
        sqliteBindText(stmt, 4, end_time);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }
    }

    const booking_id = c.sqlite3_last_insert_rowid(db);

    // Get created_at
    var created_at_copy: [64]u8 = undefined;
    var created_at_len: usize = 0;
    {
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(db, "SELECT created_at FROM bookings WHERE id = ?", -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            jsonError(stream, 500, "Internal Server Error", "internal error");
            return;
        }
        defer _ = c.sqlite3_finalize(stmt);

        sqliteBindInt64(stmt, 1, booking_id);
        rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_ROW) {
            const ca = sqliteColumnText(stmt, 0);
            created_at_len = @min(ca.len, created_at_copy.len);
            @memcpy(created_at_copy[0..created_at_len], ca[0..created_at_len]);
        }
    }

    var body_buf: [1024]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"id\":{d},\"space_id\":{d},\"user_id\":{d},\"start_time\":\"{s}\",\"end_time\":\"{s}\",\"status\":\"confirmed\",\"created_at\":\"{s}\"}}", .{
        booking_id,
        space_id,
        user_id,
        start_time,
        end_time,
        created_at_copy[0..created_at_len],
    }) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };

    writeResponse(stream, 201, "Created", body);
}

fn handleCancelBooking(stream: net.Stream, req: HttpRequest, user_id: i64) void {
    // Extract booking ID from path: /api/bookings/:id
    const prefix = "/api/bookings/";
    if (!mem.startsWith(u8, req.path, prefix)) {
        jsonError(stream, 404, "Not Found", "booking not found");
        return;
    }
    const id_str = req.path[prefix.len..];
    const booking_id = std.fmt.parseInt(i64, id_str, 10) catch {
        jsonError(stream, 404, "Not Found", "booking not found");
        return;
    };

    // Find booking
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(db, "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?", -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt);

    sqliteBindInt64(stmt, 1, booking_id);
    rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_ROW) {
        jsonError(stream, 404, "Not Found", "booking not found");
        return;
    }

    const id = c.sqlite3_column_int64(stmt, 0);
    const space_id = c.sqlite3_column_int64(stmt, 1);
    const owner_id = c.sqlite3_column_int64(stmt, 2);
    const start_time = sqliteColumnText(stmt, 3);
    const end_time = sqliteColumnText(stmt, 4);
    // status column at index 5 -- not needed since we override with "cancelled"
    const created_at = sqliteColumnText(stmt, 6);

    if (owner_id != user_id) {
        jsonError(stream, 403, "Forbidden", "forbidden");
        return;
    }

    // Copy strings before finalizing stmt implicitly (we keep stmt alive via defer, but let's be safe for the UPDATE)
    var start_time_copy: [64]u8 = undefined;
    const st_len = @min(start_time.len, start_time_copy.len);
    @memcpy(start_time_copy[0..st_len], start_time[0..st_len]);

    var end_time_copy: [64]u8 = undefined;
    const et_len = @min(end_time.len, end_time_copy.len);
    @memcpy(end_time_copy[0..et_len], end_time[0..et_len]);

    var created_at_copy: [64]u8 = undefined;
    const ca_len = @min(created_at.len, created_at_copy.len);
    @memcpy(created_at_copy[0..ca_len], created_at[0..ca_len]);

    // Update status
    var stmt2: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, "UPDATE bookings SET status = 'cancelled' WHERE id = ?", -1, &stmt2, null);
    if (rc != c.SQLITE_OK) {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    }
    defer _ = c.sqlite3_finalize(stmt2);

    sqliteBindInt64(stmt2, 1, booking_id);
    _ = c.sqlite3_step(stmt2);

    var body_buf: [1024]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"id\":{d},\"space_id\":{d},\"user_id\":{d},\"start_time\":\"{s}\",\"end_time\":\"{s}\",\"status\":\"cancelled\",\"created_at\":\"{s}\"}}", .{
        id,
        space_id,
        owner_id,
        start_time_copy[0..st_len],
        end_time_copy[0..et_len],
        created_at_copy[0..ca_len],
    }) catch {
        jsonError(stream, 500, "Internal Server Error", "internal error");
        return;
    };

    writeResponse(stream, 200, "OK", body);
}
