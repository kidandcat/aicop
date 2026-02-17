package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	_ "github.com/mattn/go-sqlite3"
	"golang.org/x/crypto/bcrypt"
)

const jwtSecret = "booking-api-secret-key-2026"

var db *sql.DB

func main() {
	initDB()
	defer db.Close()

	app := fiber.New(fiber.Config{
		DisableStartupMessage: true,
	})

	// Auth routes
	app.Post("/api/auth/register", register)
	app.Post("/api/auth/login", login)

	// Public routes
	app.Get("/api/spaces", listSpaces)

	// Protected routes
	app.Post("/api/spaces", authMiddleware, createSpace)
	app.Get("/api/bookings/my", authMiddleware, myBookings)
	app.Post("/api/bookings", authMiddleware, createBooking)
	app.Delete("/api/bookings/:id", authMiddleware, cancelBooking)

	log.Fatal(app.Listen(":8080"))
}

func initDB() {
	baseDir := os.Getenv("WORKDIR")
	if baseDir == "" {
		baseDir = "."
	}

	dbPath := filepath.Join(baseDir, "booking.db")

	var err error
	db, err = sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=5000&_foreign_keys=on")
	if err != nil {
		log.Fatal(err)
	}

	schemaPath := filepath.Join(baseDir, "schema.sql")
	schema, err := os.ReadFile(schemaPath)
	if err != nil {
		log.Fatal(err)
	}

	if _, err := db.Exec(string(schema)); err != nil {
		log.Fatal(err)
	}
}

// --- Auth Middleware ---

func authMiddleware(c *fiber.Ctx) error {
	auth := c.Get("Authorization")
	if auth == "" || !strings.HasPrefix(auth, "Bearer ") {
		return c.Status(401).JSON(fiber.Map{"error": "unauthorized"})
	}

	tokenStr := strings.TrimPrefix(auth, "Bearer ")
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return []byte(jwtSecret), nil
	})
	if err != nil || !token.Valid {
		return c.Status(401).JSON(fiber.Map{"error": "unauthorized"})
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return c.Status(401).JSON(fiber.Map{"error": "unauthorized"})
	}

	userID, ok := claims["user_id"].(float64)
	if !ok {
		return c.Status(401).JSON(fiber.Map{"error": "unauthorized"})
	}

	c.Locals("user_id", int64(userID))
	return c.Next()
}

func generateToken(userID int64) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID,
		"exp":     time.Now().Add(24 * time.Hour).Unix(),
	})
	return token.SignedString([]byte(jwtSecret))
}

// --- Handlers ---

func register(c *fiber.Ctx) error {
	var req struct {
		Email    string `json:"email"`
		Name     string `json:"name"`
		Password string `json:"password"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}
	if req.Email == "" || req.Name == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}

	result, err := db.Exec("INSERT INTO users (email, name, password_hash) VALUES (?, ?, ?)", req.Email, req.Name, string(hash))
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return c.Status(409).JSON(fiber.Map{"error": "email already exists"})
		}
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}

	id, _ := result.LastInsertId()
	return c.Status(201).JSON(fiber.Map{
		"id":    id,
		"email": req.Email,
		"name":  req.Name,
	})
}

func login(c *fiber.Ctx) error {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(401).JSON(fiber.Map{"error": "invalid credentials"})
	}

	var id int64
	var name, hash string
	err := db.QueryRow("SELECT id, name, password_hash FROM users WHERE email = ?", req.Email).Scan(&id, &name, &hash)
	if err != nil {
		return c.Status(401).JSON(fiber.Map{"error": "invalid credentials"})
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.Password)); err != nil {
		return c.Status(401).JSON(fiber.Map{"error": "invalid credentials"})
	}

	token, err := generateToken(id)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}

	return c.JSON(fiber.Map{
		"token": token,
		"user": fiber.Map{
			"id":    id,
			"email": req.Email,
			"name":  name,
		},
	})
}

func listSpaces(c *fiber.Ctx) error {
	query := "SELECT id, name, description, price_per_hour, owner_id, created_at FROM spaces WHERE 1=1"
	var args []interface{}

	if v := c.Query("min_price"); v != "" {
		if p, err := strconv.ParseFloat(v, 64); err == nil {
			query += " AND price_per_hour >= ?"
			args = append(args, p)
		}
	}
	if v := c.Query("max_price"); v != "" {
		if p, err := strconv.ParseFloat(v, 64); err == nil {
			query += " AND price_per_hour <= ?"
			args = append(args, p)
		}
	}
	if v := c.Query("available_at"); v != "" {
		query += " AND id NOT IN (SELECT space_id FROM bookings WHERE status IN ('pending','confirmed') AND start_time < ? AND ? < end_time)"
		args = append(args, v, v)
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}
	defer rows.Close()

	spaces := make([]fiber.Map, 0)
	for rows.Next() {
		var id, ownerID int64
		var name, createdAt string
		var description sql.NullString
		var price float64

		if err := rows.Scan(&id, &name, &description, &price, &ownerID, &createdAt); err != nil {
			continue
		}

		desc := ""
		if description.Valid {
			desc = description.String
		}

		spaces = append(spaces, fiber.Map{
			"id":             id,
			"name":           name,
			"description":    desc,
			"price_per_hour": price,
			"owner_id":       ownerID,
			"created_at":     createdAt,
		})
	}

	return c.JSON(spaces)
}

func createSpace(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	var req struct {
		Name         string  `json:"name"`
		Description  string  `json:"description"`
		PricePerHour float64 `json:"price_per_hour"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}
	if req.Name == "" || req.PricePerHour == 0 {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}

	result, err := db.Exec("INSERT INTO spaces (name, description, price_per_hour, owner_id) VALUES (?, ?, ?, ?)",
		req.Name, req.Description, req.PricePerHour, userID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}

	id, _ := result.LastInsertId()

	var createdAt string
	db.QueryRow("SELECT created_at FROM spaces WHERE id = ?", id).Scan(&createdAt)

	return c.Status(201).JSON(fiber.Map{
		"id":             id,
		"name":           req.Name,
		"description":    req.Description,
		"price_per_hour": req.PricePerHour,
		"owner_id":       userID,
		"created_at":     createdAt,
	})
}

func myBookings(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	rows, err := db.Query("SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE user_id = ?", userID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}
	defer rows.Close()

	bookings := make([]fiber.Map, 0)
	for rows.Next() {
		var id, spaceID, uID int64
		var startTime, endTime, status, createdAt string
		if err := rows.Scan(&id, &spaceID, &uID, &startTime, &endTime, &status, &createdAt); err != nil {
			continue
		}
		bookings = append(bookings, fiber.Map{
			"id":         id,
			"space_id":   spaceID,
			"user_id":    uID,
			"start_time": startTime,
			"end_time":   endTime,
			"status":     status,
			"created_at": createdAt,
		})
	}

	return c.JSON(bookings)
}

func createBooking(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	var req struct {
		SpaceID   int64  `json:"space_id"`
		StartTime string `json:"start_time"`
		EndTime   string `json:"end_time"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}
	if req.SpaceID == 0 || req.StartTime == "" || req.EndTime == "" {
		return c.Status(400).JSON(fiber.Map{"error": "missing required fields"})
	}

	// Check space exists
	var exists int
	err := db.QueryRow("SELECT COUNT(*) FROM spaces WHERE id = ?", req.SpaceID).Scan(&exists)
	if err != nil || exists == 0 {
		return c.Status(404).JSON(fiber.Map{"error": "space not found"})
	}

	// Check overlap
	var overlapCount int
	err = db.QueryRow(`
		SELECT COUNT(*) FROM bookings
		WHERE space_id = ? AND status IN ('pending','confirmed')
		AND start_time < ? AND ? < end_time
	`, req.SpaceID, req.EndTime, req.StartTime).Scan(&overlapCount)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}
	if overlapCount > 0 {
		return c.Status(409).JSON(fiber.Map{"error": "booking overlap"})
	}

	result, err := db.Exec(`
		INSERT INTO bookings (space_id, user_id, start_time, end_time, status)
		VALUES (?, ?, ?, ?, 'confirmed')
	`, req.SpaceID, userID, req.StartTime, req.EndTime)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "internal error"})
	}

	id, _ := result.LastInsertId()

	var createdAt string
	db.QueryRow("SELECT created_at FROM bookings WHERE id = ?", id).Scan(&createdAt)

	return c.Status(201).JSON(fiber.Map{
		"id":         id,
		"space_id":   req.SpaceID,
		"user_id":    userID,
		"start_time": req.StartTime,
		"end_time":   req.EndTime,
		"status":     "confirmed",
		"created_at": createdAt,
	})
}

func cancelBooking(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(int64)

	bookingID, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "booking not found"})
	}

	var id, spaceID, ownerID int64
	var startTime, endTime, status, createdAt string
	err = db.QueryRow("SELECT id, space_id, user_id, start_time, end_time, status, created_at FROM bookings WHERE id = ?", bookingID).
		Scan(&id, &spaceID, &ownerID, &startTime, &endTime, &status, &createdAt)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "booking not found"})
	}

	if ownerID != userID {
		return c.Status(403).JSON(fiber.Map{"error": "forbidden"})
	}

	db.Exec("UPDATE bookings SET status = 'cancelled' WHERE id = ?", bookingID)

	return c.JSON(fiber.Map{
		"id":         id,
		"space_id":   spaceID,
		"user_id":    ownerID,
		"start_time": startTime,
		"end_time":   endTime,
		"status":     "cancelled",
		"created_at": createdAt,
	})
}
