import os
import sqlite3
import datetime

from flask import Flask, request, jsonify, g
import jwt
import bcrypt

JWT_SECRET = "booking-api-secret-key-2026"
WORKDIR = os.environ.get("WORKDIR", ".")

app = Flask(__name__)


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_db():
    if "db" not in g:
        db_path = os.path.join(WORKDIR, "booking.db")
        conn = sqlite3.connect(db_path)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.row_factory = sqlite3.Row
        g.db = conn
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def init_db():
    """Execute the shared schema.sql to create tables/indexes."""
    schema_path = os.path.join(WORKDIR, "schema.sql")
    with open(schema_path, "r") as f:
        schema = f.read()
    db_path = os.path.join(WORKDIR, "booking.db")
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(schema)
    conn.close()


# ---------------------------------------------------------------------------
# JWT helpers
# ---------------------------------------------------------------------------

def generate_token(user_id: int) -> str:
    payload = {
        "user_id": user_id,
        "exp": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=24),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def auth_required(fn):
    """Decorator that validates the Bearer token and injects ``user_id``."""
    from functools import wraps

    @wraps(fn)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "unauthorized"}), 401

        token_str = auth_header[len("Bearer "):]
        try:
            payload = jwt.decode(token_str, JWT_SECRET, algorithms=["HS256"])
        except jwt.PyJWTError:
            return jsonify({"error": "unauthorized"}), 401

        user_id = payload.get("user_id")
        if user_id is None:
            return jsonify({"error": "unauthorized"}), 401

        kwargs["user_id"] = int(user_id)
        return fn(*args, **kwargs)

    return wrapper


# ---------------------------------------------------------------------------
# Auth endpoints
# ---------------------------------------------------------------------------

@app.route("/api/auth/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    email = data.get("email", "")
    name = data.get("name", "")
    password = data.get("password", "")

    if not email or not name or not password:
        return jsonify({"error": "missing required fields"}), 400

    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())

    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)",
            (email, name, hashed.decode("utf-8")),
        )
        db.commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "email already exists"}), 409

    return jsonify({"id": cur.lastrowid, "email": email, "name": name}), 201


@app.route("/api/auth/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    email = data.get("email", "")
    password = data.get("password", "")

    db = get_db()
    row = db.execute(
        "SELECT id, name, password_hash FROM users WHERE email = ?", (email,)
    ).fetchone()

    if row is None:
        return jsonify({"error": "invalid credentials"}), 401

    if not bcrypt.checkpw(password.encode("utf-8"), row["password_hash"].encode("utf-8")):
        return jsonify({"error": "invalid credentials"}), 401

    token = generate_token(row["id"])
    return jsonify({
        "token": token,
        "user": {
            "id": row["id"],
            "email": email,
            "name": row["name"],
        },
    }), 200


# ---------------------------------------------------------------------------
# Spaces endpoints
# ---------------------------------------------------------------------------

@app.route("/api/spaces", methods=["GET"])
def list_spaces():
    query = "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1"
    params: list = []

    min_price = request.args.get("min_price")
    if min_price is not None:
        try:
            val = float(min_price)
            query += " AND price_per_hour >= ?"
            params.append(val)
        except ValueError:
            pass

    max_price = request.args.get("max_price")
    if max_price is not None:
        try:
            val = float(max_price)
            query += " AND price_per_hour <= ?"
            params.append(val)
        except ValueError:
            pass

    available_at = request.args.get("available_at")
    if available_at is not None:
        query += (
            " AND id NOT IN ("
            "SELECT space_id FROM bookings "
            "WHERE status IN ('pending','confirmed') "
            "AND start_time < ? AND ? < end_time"
            ")"
        )
        params.extend([available_at, available_at])

    db = get_db()
    rows = db.execute(query, params).fetchall()

    spaces = []
    for r in rows:
        spaces.append({
            "id": r["id"],
            "name": r["name"],
            "description": r["description"] if r["description"] is not None else "",
            "price_per_hour": r["price_per_hour"],
            "owner_id": r["owner_id"],
            "created_at": r["created_at"],
        })

    return jsonify(spaces), 200


@app.route("/api/spaces", methods=["POST"])
@auth_required
def create_space(user_id: int):
    data = request.get_json(silent=True) or {}
    name = data.get("name", "")
    description = data.get("description", "")
    price_per_hour = data.get("price_per_hour", 0)

    if not name or not price_per_hour:
        return jsonify({"error": "missing required fields"}), 400

    db = get_db()
    cur = db.execute(
        "INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)",
        (name, description, price_per_hour, user_id),
    )
    db.commit()

    row = db.execute("SELECT created_at FROM spaces WHERE id = ?", (cur.lastrowid,)).fetchone()

    return jsonify({
        "id": cur.lastrowid,
        "name": name,
        "description": description,
        "price_per_hour": price_per_hour,
        "owner_id": user_id,
        "created_at": row["created_at"],
    }), 201


# ---------------------------------------------------------------------------
# Bookings endpoints
# ---------------------------------------------------------------------------

@app.route("/api/bookings/my", methods=["GET"])
@auth_required
def my_bookings(user_id: int):
    db = get_db()
    rows = db.execute(
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at "
        "FROM bookings WHERE user_id = ?",
        (user_id,),
    ).fetchall()

    bookings = []
    for r in rows:
        bookings.append({
            "id": r["id"],
            "space_id": r["space_id"],
            "user_id": r["user_id"],
            "start_time": r["start_time"],
            "end_time": r["end_time"],
            "status": r["status"],
            "created_at": r["created_at"],
        })

    return jsonify(bookings), 200


@app.route("/api/bookings", methods=["POST"])
@auth_required
def create_booking(user_id: int):
    data = request.get_json(silent=True) or {}
    space_id = data.get("space_id", 0)
    start_time = data.get("start_time", "")
    end_time = data.get("end_time", "")

    if not space_id or not start_time or not end_time:
        return jsonify({"error": "missing required fields"}), 400

    db = get_db()

    # Check space exists
    row = db.execute("SELECT COUNT(*) AS cnt FROM spaces WHERE id = ?", (space_id,)).fetchone()
    if row["cnt"] == 0:
        return jsonify({"error": "space not found"}), 404

    # Check overlap
    row = db.execute(
        "SELECT COUNT(*) AS cnt FROM bookings "
        "WHERE space_id = ? AND status IN ('pending','confirmed') "
        "AND start_time < ? AND ? < end_time",
        (space_id, end_time, start_time),
    ).fetchone()
    if row["cnt"] > 0:
        return jsonify({"error": "booking overlap"}), 409

    cur = db.execute(
        "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) "
        "VALUES (?, ?, ?, ?, 'confirmed')",
        (space_id, user_id, start_time, end_time),
    )
    db.commit()

    booking_row = db.execute(
        "SELECT created_at FROM bookings WHERE id = ?", (cur.lastrowid,)
    ).fetchone()

    return jsonify({
        "id": cur.lastrowid,
        "space_id": space_id,
        "user_id": user_id,
        "start_time": start_time,
        "end_time": end_time,
        "status": "confirmed",
        "created_at": booking_row["created_at"],
    }), 201


@app.route("/api/bookings/<int:booking_id>", methods=["DELETE"])
@auth_required
def cancel_booking(user_id: int, booking_id: int):
    db = get_db()

    row = db.execute(
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at "
        "FROM bookings WHERE id = ?",
        (booking_id,),
    ).fetchone()

    if row is None:
        return jsonify({"error": "booking not found"}), 404

    if row["user_id"] != user_id:
        return jsonify({"error": "forbidden"}), 403

    db.execute("UPDATE bookings SET status = 'cancelled' WHERE id = ?", (booking_id,))
    db.commit()

    return jsonify({
        "id": row["id"],
        "space_id": row["space_id"],
        "user_id": row["user_id"],
        "start_time": row["start_time"],
        "end_time": row["end_time"],
        "status": "cancelled",
        "created_at": row["created_at"],
    }), 200


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)
