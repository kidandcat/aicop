use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use bcrypt::{hash, verify, DEFAULT_COST};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

const JWT_SECRET: &str = "booking-api-secret-key-2026";
const SCHEMA_SQL: &str = include_str!("../../schema.sql");

type Db = Arc<Mutex<Connection>>;

// --- Models ---

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    user_id: i64,
    exp: usize,
}

#[derive(Serialize)]
struct UserResponse {
    id: i64,
    email: String,
    name: String,
}

#[derive(Serialize)]
struct LoginResponse {
    token: String,
    user: UserResponse,
}

#[derive(Serialize)]
struct SpaceResponse {
    id: i64,
    name: String,
    description: Option<String>,
    price_per_hour: f64,
    owner_id: i64,
    created_at: String,
}

#[derive(Serialize)]
struct BookingResponse {
    id: i64,
    space_id: i64,
    user_id: i64,
    start_time: String,
    end_time: String,
    status: String,
    created_at: String,
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
}

#[derive(Deserialize)]
struct SpaceFilter {
    min_price: Option<f64>,
    max_price: Option<f64>,
    available_at: Option<String>,
}

// --- Helpers ---

fn err_json(status: StatusCode, msg: &str) -> (StatusCode, Json<ErrorBody>) {
    (status, Json(ErrorBody { error: msg.into() }))
}

fn create_token(user_id: i64) -> Result<String, jsonwebtoken::errors::Error> {
    let claims = Claims {
        user_id,
        exp: 9999999999,
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_ref()),
    )
}

fn extract_user_id(headers: &HeaderMap) -> Result<i64, (StatusCode, Json<ErrorBody>)> {
    let auth = headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| err_json(StatusCode::UNAUTHORIZED, "unauthorized"))?;

    let token = auth
        .strip_prefix("Bearer ")
        .ok_or_else(|| err_json(StatusCode::UNAUTHORIZED, "unauthorized"))?;

    let validation = Validation::new(Algorithm::HS256);
    let data = decode::<Claims>(token, &DecodingKey::from_secret(JWT_SECRET.as_ref()), &validation)
        .map_err(|_| err_json(StatusCode::UNAUTHORIZED, "unauthorized"))?;

    Ok(data.claims.user_id)
}

// --- Handlers ---

async fn register(
    State(db): State<Db>,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    let email = match body.get("email").and_then(|v| v.as_str()) {
        Some(e) => e.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let name = match body.get("name").and_then(|v| v.as_str()) {
        Some(n) => n.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let password = match body.get("password").and_then(|v| v.as_str()) {
        Some(p) => p.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };

    let password_hash = match hash(&password, DEFAULT_COST) {
        Ok(h) => h,
        Err(_) => {
            return err_json(StatusCode::INTERNAL_SERVER_ERROR, "internal error").into_response()
        }
    };

    let conn = db.lock().unwrap();

    let exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM users WHERE email = ?1",
            [&email],
            |row| row.get::<_, i64>(0),
        )
        .map(|c| c > 0)
        .unwrap_or(false);

    if exists {
        return err_json(StatusCode::CONFLICT, "email already exists").into_response();
    }

    match conn.execute(
        "INSERT INTO users (email, name, password_hash) VALUES (?1, ?2, ?3)",
        rusqlite::params![email, name, password_hash],
    ) {
        Ok(_) => {
            let id = conn.last_insert_rowid();
            (StatusCode::CREATED, Json(UserResponse { id, email, name })).into_response()
        }
        Err(_) => err_json(StatusCode::CONFLICT, "email already exists").into_response(),
    }
}

async fn login(
    State(db): State<Db>,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    let email = match body.get("email").and_then(|v| v.as_str()) {
        Some(e) => e.to_string(),
        None => {
            return err_json(StatusCode::UNAUTHORIZED, "invalid credentials").into_response()
        }
    };
    let password = match body.get("password").and_then(|v| v.as_str()) {
        Some(p) => p.to_string(),
        None => {
            return err_json(StatusCode::UNAUTHORIZED, "invalid credentials").into_response()
        }
    };

    let conn = db.lock().unwrap();

    let result = conn.query_row(
        "SELECT id, email, name, password_hash FROM users WHERE email = ?1",
        [&email],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        },
    );

    match result {
        Ok((id, email, name, password_hash)) => {
            if !verify(&password, &password_hash).unwrap_or(false) {
                return err_json(StatusCode::UNAUTHORIZED, "invalid credentials").into_response();
            }

            let token = match create_token(id) {
                Ok(t) => t,
                Err(_) => {
                    return err_json(StatusCode::INTERNAL_SERVER_ERROR, "internal error")
                        .into_response()
                }
            };

            (
                StatusCode::OK,
                Json(LoginResponse {
                    token,
                    user: UserResponse { id, email, name },
                }),
            )
                .into_response()
        }
        Err(_) => err_json(StatusCode::UNAUTHORIZED, "invalid credentials").into_response(),
    }
}

async fn list_spaces(
    State(db): State<Db>,
    Query(filter): Query<SpaceFilter>,
) -> impl IntoResponse {
    let conn = db.lock().unwrap();

    let mut sql = String::from(
        "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1",
    );
    let mut params: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
    let mut idx = 1;

    if let Some(min_price) = filter.min_price {
        sql.push_str(&format!(" AND price_per_hour >= ?{}", idx));
        params.push(Box::new(min_price));
        idx += 1;
    }
    if let Some(max_price) = filter.max_price {
        sql.push_str(&format!(" AND price_per_hour <= ?{}", idx));
        params.push(Box::new(max_price));
        idx += 1;
    }
    if let Some(ref available_at) = filter.available_at {
        sql.push_str(&format!(
            " AND id NOT IN (SELECT space_id FROM bookings WHERE status IN ('pending','confirmed') AND start_time < ?{} AND end_time > ?{})",
            idx, idx + 1
        ));
        params.push(Box::new(available_at.clone()));
        params.push(Box::new(available_at.clone()));
        idx += 2;
    }

    let _ = idx;
    let refs: Vec<&dyn rusqlite::types::ToSql> = params.iter().map(|p| p.as_ref()).collect();

    let mut stmt = match conn.prepare(&sql) {
        Ok(s) => s,
        Err(e) => {
            return err_json(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()).into_response()
        }
    };

    let spaces: Vec<SpaceResponse> = stmt
        .query_map(refs.as_slice(), |row| {
            Ok(SpaceResponse {
                id: row.get(0)?,
                name: row.get(1)?,
                description: row.get(2)?,
                price_per_hour: row.get(3)?,
                owner_id: row.get(4)?,
                created_at: row.get(5)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    (StatusCode::OK, Json(spaces)).into_response()
}

async fn create_space(
    State(db): State<Db>,
    headers: HeaderMap,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    let user_id = match extract_user_id(&headers) {
        Ok(id) => id,
        Err(e) => return e.into_response(),
    };

    let name = match body.get("name").and_then(|v| v.as_str()) {
        Some(n) => n.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let price_per_hour = match body.get("price_per_hour").and_then(|v| v.as_f64()) {
        Some(p) => p,
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let description = body
        .get("description")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let conn = db.lock().unwrap();

    match conn.execute(
        "INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![name, description, price_per_hour, user_id],
    ) {
        Ok(_) => {
            let id = conn.last_insert_rowid();
            let created_at: String = conn
                .query_row("SELECT created_at FROM spaces WHERE id = ?1", [id], |row| {
                    row.get(0)
                })
                .unwrap_or_default();

            (
                StatusCode::CREATED,
                Json(SpaceResponse {
                    id,
                    name,
                    description,
                    price_per_hour,
                    owner_id: user_id,
                    created_at,
                }),
            )
                .into_response()
        }
        Err(e) => {
            err_json(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()).into_response()
        }
    }
}

async fn create_booking(
    State(db): State<Db>,
    headers: HeaderMap,
    Json(body): Json<serde_json::Value>,
) -> impl IntoResponse {
    let user_id = match extract_user_id(&headers) {
        Ok(id) => id,
        Err(e) => return e.into_response(),
    };

    let space_id = match body.get("space_id").and_then(|v| v.as_i64()) {
        Some(s) => s,
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let start_time = match body.get("start_time").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };
    let end_time = match body.get("end_time").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return err_json(StatusCode::BAD_REQUEST, "missing required fields").into_response(),
    };

    let conn = db.lock().unwrap();

    let space_exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM spaces WHERE id = ?1",
            [space_id],
            |row| row.get::<_, i64>(0),
        )
        .map(|c| c > 0)
        .unwrap_or(false);

    if !space_exists {
        return err_json(StatusCode::NOT_FOUND, "space not found").into_response();
    }

    let overlap: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM bookings WHERE space_id = ?1 AND status IN ('pending', 'confirmed') AND start_time < ?3 AND end_time > ?2",
            rusqlite::params![space_id, start_time, end_time],
            |row| row.get::<_, i64>(0),
        )
        .map(|c| c > 0)
        .unwrap_or(false);

    if overlap {
        return err_json(StatusCode::CONFLICT, "booking overlap").into_response();
    }

    match conn.execute(
        "INSERT INTO bookings (space_id, user_id, start_time, end_time, status) VALUES (?1, ?2, ?3, ?4, 'confirmed')",
        rusqlite::params![space_id, user_id, start_time, end_time],
    ) {
        Ok(_) => {
            let id = conn.last_insert_rowid();
            let created_at: String = conn
                .query_row(
                    "SELECT created_at FROM bookings WHERE id = ?1",
                    [id],
                    |row| row.get(0),
                )
                .unwrap_or_default();

            (
                StatusCode::CREATED,
                Json(BookingResponse {
                    id,
                    space_id,
                    user_id,
                    start_time,
                    end_time,
                    status: "confirmed".into(),
                    created_at,
                }),
            )
                .into_response()
        }
        Err(e) => {
            err_json(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()).into_response()
        }
    }
}

async fn list_my_bookings(
    State(db): State<Db>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let user_id = match extract_user_id(&headers) {
        Ok(id) => id,
        Err(e) => return e.into_response(),
    };

    let conn = db.lock().unwrap();

    let mut stmt = conn
        .prepare("SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?1")
        .unwrap();

    let bookings: Vec<BookingResponse> = stmt
        .query_map([user_id], |row| {
            Ok(BookingResponse {
                id: row.get(0)?,
                space_id: row.get(1)?,
                user_id: row.get(2)?,
                start_time: row.get(3)?,
                end_time: row.get(4)?,
                status: row.get(5)?,
                created_at: row.get(6)?,
            })
        })
        .unwrap()
        .filter_map(|r| r.ok())
        .collect();

    (StatusCode::OK, Json(bookings)).into_response()
}

async fn cancel_booking(
    State(db): State<Db>,
    headers: HeaderMap,
    Path(booking_id): Path<i64>,
) -> impl IntoResponse {
    let user_id = match extract_user_id(&headers) {
        Ok(id) => id,
        Err(e) => return e.into_response(),
    };

    let conn = db.lock().unwrap();

    let booking = conn.query_row(
        "SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?1",
        [booking_id],
        |row| {
            Ok(BookingResponse {
                id: row.get(0)?,
                space_id: row.get(1)?,
                user_id: row.get(2)?,
                start_time: row.get(3)?,
                end_time: row.get(4)?,
                status: row.get(5)?,
                created_at: row.get(6)?,
            })
        },
    );

    match booking {
        Ok(b) => {
            if b.user_id != user_id {
                return err_json(StatusCode::FORBIDDEN, "forbidden").into_response();
            }

            conn.execute(
                "UPDATE bookings SET status = 'cancelled' WHERE id = ?1",
                [booking_id],
            )
            .unwrap();

            (
                StatusCode::OK,
                Json(BookingResponse {
                    status: "cancelled".into(),
                    ..b
                }),
            )
                .into_response()
        }
        Err(_) => err_json(StatusCode::NOT_FOUND, "booking not found").into_response(),
    }
}

#[tokio::main]
async fn main() {
    let conn = Connection::open("booking.db").expect("Failed to open database");
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        .unwrap();
    conn.execute_batch(SCHEMA_SQL)
        .expect("Failed to initialize database schema");

    let db: Db = Arc::new(Mutex::new(conn));

    let app = Router::new()
        .route("/api/auth/register", post(register))
        .route("/api/auth/login", post(login))
        .route("/api/spaces", get(list_spaces).post(create_space))
        .route("/api/bookings", post(create_booking))
        .route("/api/bookings/my", get(list_my_bookings))
        .route("/api/bookings/:id", delete(cancel_booking))
        .with_state(db);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("Failed to bind to port 8080");

    axum::serve(listener, app).await.unwrap();
}
