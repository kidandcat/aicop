-- Booking API — Database Schema
-- SQLite compatible. All implementations must use this exact schema.

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS spaces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    price_per_hour REAL NOT NULL,
    owner_id INTEGER NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS bookings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    space_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'cancelled')),
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    FOREIGN KEY (space_id) REFERENCES spaces(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Index for overlap queries: find active bookings for a space in a time range
CREATE INDEX IF NOT EXISTS idx_bookings_space_time
    ON bookings(space_id, start_time, end_time)
    WHERE status IN ('pending', 'confirmed');

-- Index for user's bookings lookup
CREATE INDEX IF NOT EXISTS idx_bookings_user
    ON bookings(user_id);

-- Index for space price filtering
CREATE INDEX IF NOT EXISTS idx_spaces_price
    ON spaces(price_per_hour);
