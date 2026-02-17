# Booking API — REST API with SQLite

## Problem Statement

Build a REST API for managing space bookings. The API must handle user authentication via JWT, CRUD operations for spaces and bookings, and enforce booking overlap validation.

Unlike the other AICOP challenges (stdin/stdout algorithms), this problem tests the ability to build a **complete web service** — routing, middleware, database operations, authentication, and business logic.

## Data Model

Three tables stored in SQLite:

### Users
| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY, AUTOINCREMENT |
| email | TEXT | UNIQUE, NOT NULL |
| name | TEXT | NOT NULL |
| password_hash | TEXT | NOT NULL |
| created_at | TEXT | DEFAULT CURRENT_TIMESTAMP |

### Spaces
| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY, AUTOINCREMENT |
| name | TEXT | NOT NULL |
| description | TEXT | |
| price_per_hour | REAL | NOT NULL |
| owner_id | INTEGER | FOREIGN KEY → users(id) |
| created_at | TEXT | DEFAULT CURRENT_TIMESTAMP |

### Bookings
| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY, AUTOINCREMENT |
| space_id | INTEGER | FOREIGN KEY → spaces(id), NOT NULL |
| user_id | INTEGER | FOREIGN KEY → users(id), NOT NULL |
| start_time | TEXT | NOT NULL (ISO 8601) |
| end_time | TEXT | NOT NULL (ISO 8601) |
| status | TEXT | DEFAULT 'pending', CHECK(status IN ('pending','confirmed','cancelled')) |
| created_at | TEXT | DEFAULT CURRENT_TIMESTAMP |

## API Specification

All endpoints accept and return `application/json`. The server **must** listen on port `8080`.

### Authentication

JWT tokens are passed in the `Authorization` header as `Bearer <token>`. The JWT secret can be any static string chosen by the implementation. Tokens must contain at least the `user_id` claim.

### Endpoints

#### POST /api/auth/register

Create a new user account.

**Request:**
```json
{
  "email": "user@example.com",
  "name": "John Doe",
  "password": "secret123"
}
```

**Response (201):**
```json
{
  "id": 1,
  "email": "user@example.com",
  "name": "John Doe"
}
```

**Errors:**
- `409` — Email already exists: `{"error": "email already exists"}`
- `400` — Missing fields: `{"error": "missing required fields"}`

#### POST /api/auth/login

Authenticate and receive a JWT token.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "secret123"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": 1,
    "email": "user@example.com",
    "name": "John Doe"
  }
}
```

**Errors:**
- `401` — Invalid credentials: `{"error": "invalid credentials"}`

#### GET /api/spaces

List all spaces. Supports optional query filters.

**Query Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| min_price | number | Minimum price per hour |
| max_price | number | Maximum price per hour |
| available_at | string | ISO 8601 datetime — only return spaces with no confirmed/pending bookings overlapping this time |

**Response (200):**
```json
[
  {
    "id": 1,
    "name": "Conference Room A",
    "description": "Large room with projector",
    "price_per_hour": 50.0,
    "owner_id": 1,
    "created_at": "2026-01-15T10:00:00Z"
  }
]
```

No auth required.

#### POST /api/spaces

Create a new space. **Requires auth.**

**Request:**
```json
{
  "name": "Conference Room A",
  "description": "Large room with projector",
  "price_per_hour": 50.0
}
```

**Response (201):**
```json
{
  "id": 1,
  "name": "Conference Room A",
  "description": "Large room with projector",
  "price_per_hour": 50.0,
  "owner_id": 1,
  "created_at": "2026-01-15T10:00:00Z"
}
```

**Errors:**
- `400` — Missing required fields: `{"error": "missing required fields"}`
- `401` — Not authenticated

#### GET /api/bookings/my

List bookings for the authenticated user. **Requires auth.**

**Response (200):**
```json
[
  {
    "id": 1,
    "space_id": 1,
    "user_id": 1,
    "start_time": "2026-02-20T09:00:00Z",
    "end_time": "2026-02-20T11:00:00Z",
    "status": "confirmed",
    "created_at": "2026-02-15T10:00:00Z"
  }
]
```

#### POST /api/bookings

Create a new booking. **Requires auth.** Must validate that no existing booking (with status `pending` or `confirmed`) overlaps with the requested time range for the same space.

**Request:**
```json
{
  "space_id": 1,
  "start_time": "2026-02-20T09:00:00Z",
  "end_time": "2026-02-20T11:00:00Z"
}
```

**Response (201):**
```json
{
  "id": 1,
  "space_id": 1,
  "user_id": 1,
  "start_time": "2026-02-20T09:00:00Z",
  "end_time": "2026-02-20T11:00:00Z",
  "status": "confirmed",
  "created_at": "2026-02-15T10:00:00Z"
}
```

**Errors:**
- `400` — Missing fields: `{"error": "missing required fields"}`
- `409` — Time overlap: `{"error": "booking overlap"}`
- `404` — Space not found: `{"error": "space not found"}`
- `401` — Not authenticated

**Overlap rule:** Two bookings overlap when `start_time_A < end_time_B AND start_time_B < end_time_A`. Only bookings with status `pending` or `confirmed` are considered (cancelled bookings are ignored).

#### DELETE /api/bookings/:id

Cancel a booking (sets status to `cancelled`). **Requires auth + ownership** — only the user who created the booking can cancel it.

**Response (200):**
```json
{
  "id": 1,
  "space_id": 1,
  "user_id": 1,
  "start_time": "2026-02-20T09:00:00Z",
  "end_time": "2026-02-20T11:00:00Z",
  "status": "cancelled",
  "created_at": "2026-02-15T10:00:00Z"
}
```

**Errors:**
- `404` — Booking not found: `{"error": "booking not found"}`
- `403` — Not the owner: `{"error": "forbidden"}`
- `401` — Not authenticated

## Constraints

- **Database:** SQLite, using the provided `schema.sql`
- **Port:** Server must listen on `8080`
- **DB file:** `booking.db` (created in the solution's working directory)
- **Password storage:** Passwords must be hashed (bcrypt, argon2, or SHA-256 with salt at minimum)
- **JWT:** Any signing algorithm (HS256 recommended), any secret string
- **Dates:** ISO 8601 format (`2026-02-20T09:00:00Z`)
- **Same schema** across all language implementations
- **Same JSON response format** across all implementations

## Solutions

| File | Language | Notes |
|------|----------|-------|
| _TBD_ | | |

### Build & Run

Each solution should be runnable with a single command and listen on port 8080. The server must initialize the database from `schema.sql` on startup if `booking.db` does not exist.

## Testing

Run `./test.sh` to execute the API test suite against a running server. The test script will:

1. Start the server (the solution path is passed as an argument)
2. Wait for it to be ready
3. Run all 9 test scenarios
4. Kill the server
5. Report results

```bash
./test.sh python3 solution.py
./test.sh go run solution.go
./test.sh node solution.js
```
