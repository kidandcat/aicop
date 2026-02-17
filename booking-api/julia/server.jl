using HTTP
using SQLite
using JSON3
using SHA
using Base64
using Dates

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const JWT_SECRET = "booking-api-secret-key-2026"
const BCRYPT_AVAILABLE = false  # We use SHA-256 + salt for password hashing

# ---------------------------------------------------------------------------
# Database initialisation
# ---------------------------------------------------------------------------

const WORKDIR = get(ENV, "WORKDIR", ".")

function init_db()
    db_path = joinpath(WORKDIR, "booking.db")
    db = SQLite.DB(db_path)

    SQLite.execute(db, "PRAGMA journal_mode=WAL")
    SQLite.execute(db, "PRAGMA busy_timeout=5000")
    SQLite.execute(db, "PRAGMA foreign_keys=ON")

    schema_path = joinpath(WORKDIR, "schema.sql")
    schema = read(schema_path, String)

    # SQLite.execute can only run one statement at a time, so split on ";"
    for stmt in split(schema, ";")
        s = strip(stmt)
        isempty(s) && continue
        try
            SQLite.execute(db, s * ";")
        catch e
            # Ignore errors from IF NOT EXISTS statements that are fine
            @warn "Schema statement warning" exception = e
        end
    end

    return db
end

const DB = init_db()

# ---------------------------------------------------------------------------
# Password hashing (SHA-256 + random salt)
# ---------------------------------------------------------------------------

function hash_password(password::AbstractString)::String
    salt = bytes2hex(rand(UInt8, 16))
    h = bytes2hex(sha256(salt * password))
    return salt * ":" * h
end

function verify_password(password::AbstractString, stored::AbstractString)::Bool
    parts = split(stored, ":")
    length(parts) != 2 && return false
    salt = parts[1]
    expected_hash = parts[2]
    actual_hash = bytes2hex(sha256(String(salt) * password))
    return actual_hash == expected_hash
end

# ---------------------------------------------------------------------------
# JWT (manual HS256)
# ---------------------------------------------------------------------------

function base64url_encode(data::AbstractVector{UInt8})::String
    b64 = base64encode(data)
    b64 = replace(b64, "+" => "-")
    b64 = replace(b64, "/" => "_")
    b64 = rstrip(b64, '=')
    return b64
end

function base64url_encode(s::AbstractString)::String
    return base64url_encode(Vector{UInt8}(codeunits(s)))
end

function base64url_decode(s::AbstractString)::Vector{UInt8}
    b64 = replace(s, "-" => "+")
    b64 = replace(b64, "_" => "/")
    # Add padding
    while length(b64) % 4 != 0
        b64 *= "="
    end
    return base64decode(b64)
end

function create_jwt(user_id::Int)::String
    header = base64url_encode(JSON3.write(Dict("alg" => "HS256", "typ" => "JWT")))
    exp_time = Int(floor(datetime2unix(now(UTC) + Hour(24))))
    payload = base64url_encode(JSON3.write(Dict("user_id" => user_id, "exp" => exp_time)))
    signing_input = header * "." * payload
    sig = base64url_encode(hmac_sha256(Vector{UInt8}(codeunits(JWT_SECRET)), Vector{UInt8}(codeunits(signing_input))))
    return signing_input * "." * sig
end

function verify_jwt(token::AbstractString)::Union{Int, Nothing}
    parts = split(token, ".")
    length(parts) != 3 && return nothing

    signing_input = parts[1] * "." * parts[2]
    expected_sig = base64url_encode(hmac_sha256(Vector{UInt8}(codeunits(JWT_SECRET)), Vector{UInt8}(codeunits(signing_input))))

    if expected_sig != parts[3]
        return nothing
    end

    try
        payload_json = String(base64url_decode(String(parts[2])))
        payload = JSON3.read(payload_json)
        user_id = get(payload, :user_id, nothing)
        exp = get(payload, :exp, nothing)

        if user_id === nothing
            return nothing
        end

        # Check expiration
        if exp !== nothing && exp < Int(floor(datetime2unix(now(UTC))))
            return nothing
        end

        return Int(user_id)
    catch
        return nothing
    end
end

# ---------------------------------------------------------------------------
# Auth middleware helper
# ---------------------------------------------------------------------------

function extract_user_id(request::HTTP.Request)::Union{Int, Nothing}
    auth_header = ""
    for h in request.headers
        if lowercase(h[1]) == "authorization"
            auth_header = h[2]
            break
        end
    end

    isempty(auth_header) && return nothing
    !startswith(auth_header, "Bearer ") && return nothing

    token = auth_header[8:end]
    return verify_jwt(token)
end

function unauthorized_response()
    return HTTP.Response(401, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict("error" => "unauthorized")))
end

# ---------------------------------------------------------------------------
# Query parameter parsing
# ---------------------------------------------------------------------------

function parse_query_params(target::AbstractString)::Dict{String, String}
    params = Dict{String, String}()
    idx = findfirst('?', target)
    idx === nothing && return params

    query_string = target[idx+1:end]
    for pair in split(query_string, "&")
        kv = split(pair, "="; limit=2)
        if length(kv) == 2
            params[HTTP.URIs.unescapeuri(kv[1])] = HTTP.URIs.unescapeuri(kv[2])
        end
    end
    return params
end

function get_path(target::AbstractString)::String
    idx = findfirst('?', target)
    idx === nothing && return target
    return target[1:idx-1]
end

# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

function handle_register(request::HTTP.Request)
    local req
    try
        req = JSON3.read(String(request.body))
    catch
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    email = get(req, :email, nothing)
    name = get(req, :name, nothing)
    password = get(req, :password, nothing)

    if email === nothing || name === nothing || password === nothing ||
       isempty(string(email)) || isempty(string(name)) || isempty(string(password))
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    pw_hash = hash_password(string(password))

    try
        SQLite.execute(DB, "INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)",
            (string(email), string(name), pw_hash))
    catch e
        if occursin("UNIQUE", string(e))
            return HTTP.Response(409, ["Content-Type" => "application/json"],
                body = JSON3.write(Dict("error" => "email already exists")))
        end
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "internal error")))
    end

    # Get the last inserted ID
    result = SQLite.DBInterface.execute(DB, "SELECT last_insert_rowid() as id")
    row = first(result)
    id = row.id

    return HTTP.Response(201, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict("id" => id, "email" => string(email), "name" => string(name))))
end

function handle_login(request::HTTP.Request)
    local req
    try
        req = JSON3.read(String(request.body))
    catch
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "invalid credentials")))
    end

    email = get(req, :email, nothing)
    password = get(req, :password, nothing)

    if email === nothing || password === nothing
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "invalid credentials")))
    end

    result = SQLite.DBInterface.execute(DB,
        "SELECT id, name, password_hash FROM users WHERE email = ?", (string(email),))

    user_row = nothing
    for row in result
        user_row = (id=Int(row.id), name=string(row.name), password_hash=string(row.password_hash))
        break
    end

    if user_row === nothing
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "invalid credentials")))
    end

    if !verify_password(string(password), user_row.password_hash)
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "invalid credentials")))
    end

    token = create_jwt(user_row.id)

    return HTTP.Response(200, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict(
            "token" => token,
            "user" => Dict("id" => user_row.id, "email" => string(email), "name" => user_row.name)
        )))
end

function handle_list_spaces(request::HTTP.Request)
    params = parse_query_params(request.target)

    query = "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1"
    args = Any[]

    if haskey(params, "min_price")
        p = tryparse(Float64, params["min_price"])
        if p !== nothing
            query *= " AND price_per_hour >= ?"
            push!(args, p)
        end
    end

    if haskey(params, "max_price")
        p = tryparse(Float64, params["max_price"])
        if p !== nothing
            query *= " AND price_per_hour <= ?"
            push!(args, p)
        end
    end

    if haskey(params, "available_at")
        query *= " AND id NOT IN (SELECT space_id FROM bookings WHERE status IN ('pending','confirmed') AND start_time < ? AND ? < end_time)"
        push!(args, params["available_at"])
        push!(args, params["available_at"])
    end

    result = SQLite.DBInterface.execute(DB, query, tuple(args...))

    spaces = Dict{String, Any}[]
    for row in result
        desc = row.description === missing ? "" : string(row.description)
        push!(spaces, Dict(
            "id" => Int(row.id),
            "name" => row.name,
            "description" => desc,
            "price_per_hour" => row.price_per_hour,
            "owner_id" => Int(row.owner_id),
            "created_at" => row.created_at
        ))
    end

    return HTTP.Response(200, ["Content-Type" => "application/json"],
        body = JSON3.write(spaces))
end

function handle_create_space(request::HTTP.Request)
    user_id = extract_user_id(request)
    user_id === nothing && return unauthorized_response()

    local req
    try
        req = JSON3.read(String(request.body))
    catch
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    name = get(req, :name, nothing)
    description = get(req, :description, "")
    price_per_hour = get(req, :price_per_hour, nothing)

    if name === nothing || isempty(string(name)) || price_per_hour === nothing || price_per_hour == 0
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    desc_val = description === nothing ? "" : string(description)

    SQLite.execute(DB,
        "INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)",
        (string(name), desc_val, Float64(price_per_hour), user_id))

    id_result = SQLite.DBInterface.execute(DB, "SELECT last_insert_rowid() as id")
    id = Int(first(id_result).id)

    cat_result = SQLite.DBInterface.execute(DB, "SELECT created_at FROM spaces WHERE id = ?", (id,))
    created_at = first(cat_result).created_at

    return HTTP.Response(201, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict(
            "id" => id,
            "name" => string(name),
            "description" => desc_val,
            "price_per_hour" => Float64(price_per_hour),
            "owner_id" => user_id,
            "created_at" => created_at
        )))
end

function handle_my_bookings(request::HTTP.Request)
    user_id = extract_user_id(request)
    user_id === nothing && return unauthorized_response()

    result = SQLite.DBInterface.execute(DB,
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?",
        (user_id,))

    bookings = Dict{String, Any}[]
    for row in result
        push!(bookings, Dict(
            "id" => Int(row.id),
            "space_id" => Int(row.space_id),
            "user_id" => Int(row.user_id),
            "start_time" => row.start_time,
            "end_time" => row.end_time,
            "status" => row.status,
            "created_at" => row.created_at
        ))
    end

    return HTTP.Response(200, ["Content-Type" => "application/json"],
        body = JSON3.write(bookings))
end

function handle_create_booking(request::HTTP.Request)
    user_id = extract_user_id(request)
    user_id === nothing && return unauthorized_response()

    local req
    try
        req = JSON3.read(String(request.body))
    catch
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    space_id = get(req, :space_id, nothing)
    start_time = get(req, :start_time, nothing)
    end_time = get(req, :end_time, nothing)

    if space_id === nothing || space_id == 0 || start_time === nothing || end_time === nothing ||
       isempty(string(start_time)) || isempty(string(end_time))
        return HTTP.Response(400, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "missing required fields")))
    end

    space_id = Int(space_id)

    # Check space exists
    exists_result = SQLite.DBInterface.execute(DB,
        "SELECT COUNT(*) as cnt FROM spaces WHERE id = ?", (space_id,))
    exists = Int(first(exists_result).cnt)
    if exists == 0
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "space not found")))
    end

    # Check overlap
    overlap_result = SQLite.DBInterface.execute(DB, """
        SELECT COUNT(*) as cnt FROM bookings
        WHERE space_id = ? AND status IN ('pending','confirmed')
        AND start_time < ? AND ? < end_time
    """, (space_id, string(end_time), string(start_time)))
    overlap_count = Int(first(overlap_result).cnt)
    if overlap_count > 0
        return HTTP.Response(409, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "booking overlap")))
    end

    SQLite.execute(DB, """
        INSERT INTO bookings (space_id, user_id, start_time, end_time, status)
        VALUES (?, ?, ?, ?, 'confirmed')
    """, (space_id, user_id, string(start_time), string(end_time)))

    id_result = SQLite.DBInterface.execute(DB, "SELECT last_insert_rowid() as id")
    id = Int(first(id_result).id)

    cat_result = SQLite.DBInterface.execute(DB, "SELECT created_at FROM bookings WHERE id = ?", (id,))
    created_at = first(cat_result).created_at

    return HTTP.Response(201, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict(
            "id" => id,
            "space_id" => space_id,
            "user_id" => user_id,
            "start_time" => string(start_time),
            "end_time" => string(end_time),
            "status" => "confirmed",
            "created_at" => created_at
        )))
end

function handle_cancel_booking(request::HTTP.Request, booking_id::Int)
    user_id = extract_user_id(request)
    user_id === nothing && return unauthorized_response()

    result = SQLite.DBInterface.execute(DB,
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?",
        (booking_id,))

    booking_row = nothing
    for row in result
        booking_row = (id=Int(row.id), space_id=Int(row.space_id), user_id=Int(row.user_id),
                       start_time=string(row.start_time), end_time=string(row.end_time),
                       status=string(row.status), created_at=string(row.created_at))
        break
    end

    if booking_row === nothing
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "booking not found")))
    end

    if booking_row.user_id != user_id
        return HTTP.Response(403, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "forbidden")))
    end

    SQLite.execute(DB, "UPDATE bookings SET status = 'cancelled' WHERE id = ?", (booking_id,))

    return HTTP.Response(200, ["Content-Type" => "application/json"],
        body = JSON3.write(Dict(
            "id" => booking_row.id,
            "space_id" => booking_row.space_id,
            "user_id" => booking_row.user_id,
            "start_time" => booking_row.start_time,
            "end_time" => booking_row.end_time,
            "status" => "cancelled",
            "created_at" => booking_row.created_at
        )))
end

# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

function router(request::HTTP.Request)
    method = request.method
    path = get_path(request.target)

    try
        # Auth routes
        if method == "POST" && path == "/api/auth/register"
            return handle_register(request)
        elseif method == "POST" && path == "/api/auth/login"
            return handle_login(request)

        # Spaces
        elseif method == "GET" && path == "/api/spaces"
            return handle_list_spaces(request)
        elseif method == "POST" && path == "/api/spaces"
            return handle_create_space(request)

        # Bookings
        elseif method == "GET" && path == "/api/bookings/my"
            return handle_my_bookings(request)
        elseif method == "POST" && path == "/api/bookings"
            return handle_create_booking(request)

        # DELETE /api/bookings/:id
        elseif method == "DELETE" && startswith(path, "/api/bookings/")
            id_str = path[length("/api/bookings/")+1:end]
            booking_id = tryparse(Int, id_str)
            if booking_id === nothing
                return HTTP.Response(404, ["Content-Type" => "application/json"],
                    body = JSON3.write(Dict("error" => "booking not found")))
            end
            return handle_cancel_booking(request, booking_id)

        else
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                body = JSON3.write(Dict("error" => "not found")))
        end

    catch e
        @error "Request handler error" exception = (e, catch_backtrace())
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            body = JSON3.write(Dict("error" => "internal error")))
    end
end

# ---------------------------------------------------------------------------
# Start server
# ---------------------------------------------------------------------------

println("Booking API (Julia) listening on :8080")
HTTP.serve(router, "0.0.0.0", 8080)
