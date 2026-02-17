#!/usr/bin/env bash
#
# Test runner for Booking API solutions.
# Starts the server, runs 9 test scenarios against it, then kills the server.
#
# Usage: ./test.sh <command to start server>
#   e.g. ./test.sh python3 solution.py
#        ./test.sh go run solution.go
#        ./test.sh node solution.js

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

BASE_URL="http://localhost:8080"
DB_FILE="$DIR/booking.db"
SERVER_PID=""

# --- Helpers ---

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$DB_FILE"
}
trap cleanup EXIT

assert_status() {
    local test_name="$1"
    local expected_status="$2"
    local actual_status="$3"
    local response_body="$4"

    TOTAL=$((TOTAL + 1))

    if [[ "$actual_status" -eq "$expected_status" ]]; then
        echo -e "  ${GREEN}PASS${NC}  $test_name (HTTP $actual_status)"
        PASS=$((PASS + 1))
        return 0
    else
        echo -e "  ${RED}FAIL${NC}  $test_name"
        echo -e "        Expected HTTP: $expected_status"
        echo -e "        Actual HTTP:   $actual_status"
        echo -e "        Body: $response_body"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"
    local expected="$4"

    TOTAL=$((TOTAL + 1))

    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null || echo "PARSE_ERROR")

    if [[ "$actual" == "$expected" ]]; then
        echo -e "  ${GREEN}PASS${NC}  $test_name — $field = $expected"
        PASS=$((PASS + 1))
        return 0
    else
        echo -e "  ${RED}FAIL${NC}  $test_name — $field"
        echo -e "        Expected: $expected"
        echo -e "        Actual:   $actual"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

assert_json_length() {
    local test_name="$1"
    local json="$2"
    local expected="$3"

    TOTAL=$((TOTAL + 1))

    local actual
    actual=$(echo "$json" | jq 'length' 2>/dev/null || echo "PARSE_ERROR")

    if [[ "$actual" -eq "$expected" ]]; then
        echo -e "  ${GREEN}PASS${NC}  $test_name — array length = $expected"
        PASS=$((PASS + 1))
        return 0
    else
        echo -e "  ${RED}FAIL${NC}  $test_name — array length"
        echo -e "        Expected: $expected"
        echo -e "        Actual:   $actual"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

# HTTP helper: sets RESP_STATUS and RESP_BODY
http() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local token="${4:-}"

    local curl_args=(-s -w "\n%{http_code}" -X "$method")

    if [[ -n "$token" ]]; then
        curl_args+=(-H "Authorization: Bearer $token")
    fi

    curl_args+=(-H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    local response
    response=$(curl "${curl_args[@]}" "${BASE_URL}${path}" 2>/dev/null || echo -e "\n000")

    RESP_BODY=$(echo "$response" | sed '$d')
    RESP_STATUS=$(echo "$response" | tail -1)
}

# --- Validate prerequisites ---

if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 <command to start server>${NC}"
    echo "  e.g. $0 python3 solution.py"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo -e "${RED}curl is required but not found${NC}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}jq is required but not found${NC}"
    exit 1
fi

# --- Start server ---

echo -e "${BOLD}Booking API — Test Suite${NC}"
echo "========================"
echo ""

# Remove any previous DB
rm -f "$DB_FILE"

echo -e "${YELLOW}Starting server:${NC} $*"
"$@" &
SERVER_PID=$!

# Wait for server to be ready (max 15 seconds)
echo -n "Waiting for server..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null "${BASE_URL}/api/spaces" 2>/dev/null; then
        echo -e " ${GREEN}ready${NC}"
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e " ${RED}server exited prematurely${NC}"
        exit 1
    fi
    sleep 0.5
done

# Final check
if ! curl -s -o /dev/null "${BASE_URL}/api/spaces" 2>/dev/null; then
    echo -e " ${RED}timeout — server not responding${NC}"
    exit 1
fi

echo ""

# Storage for tokens
TOKEN_A=""
TOKEN_B=""
BOOKING_ID=""

# =========================================
# Test 1: Register 2 users
# =========================================
echo -e "${BOLD}[Test 1] Register Users${NC}"

http POST "/api/auth/register" '{"email":"alice@test.com","name":"Alice Smith","password":"password123"}'
assert_status "Register Alice" 201 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_field "Register Alice" "$RESP_BODY" ".email" "alice@test.com" || true
assert_json_field "Register Alice" "$RESP_BODY" ".name" "Alice Smith" || true

http POST "/api/auth/register" '{"email":"bob@test.com","name":"Bob Jones","password":"secret456"}'
assert_status "Register Bob" 201 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_field "Register Bob" "$RESP_BODY" ".email" "bob@test.com" || true

# Duplicate email
http POST "/api/auth/register" '{"email":"alice@test.com","name":"Alice Again","password":"other"}'
assert_status "Duplicate email rejected" 409 "$RESP_STATUS" "$RESP_BODY" || true

echo ""

# =========================================
# Test 2: Login and obtain tokens
# =========================================
echo -e "${BOLD}[Test 2] Login${NC}"

http POST "/api/auth/login" '{"email":"alice@test.com","password":"password123"}'
assert_status "Login Alice" 200 "$RESP_STATUS" "$RESP_BODY" || true
TOKEN_A=$(echo "$RESP_BODY" | jq -r '.token' 2>/dev/null || echo "")
if [[ -n "$TOKEN_A" && "$TOKEN_A" != "null" ]]; then
    echo -e "  ${GREEN}PASS${NC}  Alice token received"; PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC}  Alice token missing"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

http POST "/api/auth/login" '{"email":"bob@test.com","password":"secret456"}'
assert_status "Login Bob" 200 "$RESP_STATUS" "$RESP_BODY" || true
TOKEN_B=$(echo "$RESP_BODY" | jq -r '.token' 2>/dev/null || echo "")
if [[ -n "$TOKEN_B" && "$TOKEN_B" != "null" ]]; then
    echo -e "  ${GREEN}PASS${NC}  Bob token received"; PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC}  Bob token missing"; FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# Wrong password
http POST "/api/auth/login" '{"email":"alice@test.com","password":"wrongpass"}'
assert_status "Wrong password rejected" 401 "$RESP_STATUS" "$RESP_BODY" || true

echo ""

# =========================================
# Test 3: Create 3 spaces
# =========================================
echo -e "${BOLD}[Test 3] Create Spaces${NC}"

http POST "/api/spaces" '{"name":"Conference Room A","description":"Large room with projector","price_per_hour":50.0}' "$TOKEN_A"
assert_status "Create space 1" 201 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_field "Create space 1" "$RESP_BODY" ".name" "Conference Room A" || true
SPACE_1_ID=$(echo "$RESP_BODY" | jq -r '.id' 2>/dev/null || echo "")

http POST "/api/spaces" '{"name":"Meeting Room B","description":"Small huddle room","price_per_hour":25.0}' "$TOKEN_A"
assert_status "Create space 2" 201 "$RESP_STATUS" "$RESP_BODY" || true
SPACE_2_ID=$(echo "$RESP_BODY" | jq -r '.id' 2>/dev/null || echo "")

http POST "/api/spaces" '{"name":"Executive Suite","description":"Premium space","price_per_hour":150.0}' "$TOKEN_B"
assert_status "Create space 3" 201 "$RESP_STATUS" "$RESP_BODY" || true
SPACE_3_ID=$(echo "$RESP_BODY" | jq -r '.id' 2>/dev/null || echo "")

echo ""

# =========================================
# Test 4: Search spaces by price range
# =========================================
echo -e "${BOLD}[Test 4] Search Spaces by Price${NC}"

http GET "/api/spaces?min_price=20&max_price=60"
assert_status "Filter by price range" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "Filter 20-60" "$RESP_BODY" 2 || true

http GET "/api/spaces?min_price=100"
assert_status "Filter min_price=100" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "Filter min 100" "$RESP_BODY" 1 || true

http GET "/api/spaces?max_price=30"
assert_status "Filter max_price=30" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "Filter max 30" "$RESP_BODY" 1 || true

http GET "/api/spaces"
assert_status "List all spaces" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "All spaces" "$RESP_BODY" 3 || true

echo ""

# =========================================
# Test 5: Create a valid booking
# =========================================
echo -e "${BOLD}[Test 5] Create Valid Booking${NC}"

http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T09:00:00Z\",\"end_time\":\"2026-03-01T11:00:00Z\"}" "$TOKEN_A"
assert_status "Create booking" 201 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_field "Booking space_id" "$RESP_BODY" ".space_id" "$SPACE_1_ID" || true
assert_json_field "Booking start_time" "$RESP_BODY" ".start_time" "2026-03-01T09:00:00Z" || true
assert_json_field "Booking end_time" "$RESP_BODY" ".end_time" "2026-03-01T11:00:00Z" || true
BOOKING_ID=$(echo "$RESP_BODY" | jq -r '.id' 2>/dev/null || echo "")

# Bob books a different space — should succeed
http POST "/api/bookings" "{\"space_id\":$SPACE_2_ID,\"start_time\":\"2026-03-01T09:00:00Z\",\"end_time\":\"2026-03-01T11:00:00Z\"}" "$TOKEN_B"
assert_status "Bob books different space (no overlap)" 201 "$RESP_STATUS" "$RESP_BODY" || true
BOOKING_B_ID=$(echo "$RESP_BODY" | jq -r '.id' 2>/dev/null || echo "")

echo ""

# =========================================
# Test 6: Booking overlap must fail
# =========================================
echo -e "${BOLD}[Test 6] Booking Overlap Detection${NC}"

# Exact same time range
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T09:00:00Z\",\"end_time\":\"2026-03-01T11:00:00Z\"}" "$TOKEN_B"
assert_status "Exact overlap rejected" 409 "$RESP_STATUS" "$RESP_BODY" || true

# Partial overlap — starts during existing booking
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T10:00:00Z\",\"end_time\":\"2026-03-01T12:00:00Z\"}" "$TOKEN_B"
assert_status "Partial overlap (starts during) rejected" 409 "$RESP_STATUS" "$RESP_BODY" || true

# Partial overlap — ends during existing booking
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T08:00:00Z\",\"end_time\":\"2026-03-01T10:00:00Z\"}" "$TOKEN_B"
assert_status "Partial overlap (ends during) rejected" 409 "$RESP_STATUS" "$RESP_BODY" || true

# Superset overlap — new booking encompasses existing
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T07:00:00Z\",\"end_time\":\"2026-03-01T13:00:00Z\"}" "$TOKEN_B"
assert_status "Superset overlap rejected" 409 "$RESP_STATUS" "$RESP_BODY" || true

# Adjacent (no overlap) — should succeed
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T11:00:00Z\",\"end_time\":\"2026-03-01T13:00:00Z\"}" "$TOKEN_B"
assert_status "Adjacent booking (no overlap) accepted" 201 "$RESP_STATUS" "$RESP_BODY" || true

echo ""

# =========================================
# Test 7: List my bookings
# =========================================
echo -e "${BOLD}[Test 7] List My Bookings${NC}"

http GET "/api/bookings/my" "" "$TOKEN_A"
assert_status "Alice's bookings" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "Alice has 1 booking" "$RESP_BODY" 1 || true

http GET "/api/bookings/my" "" "$TOKEN_B"
assert_status "Bob's bookings" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_length "Bob has 2 bookings" "$RESP_BODY" 2 || true

echo ""

# =========================================
# Test 8: Cancel booking
# =========================================
echo -e "${BOLD}[Test 8] Cancel Booking${NC}"

# Bob tries to cancel Alice's booking — forbidden
http DELETE "/api/bookings/$BOOKING_ID" "" "$TOKEN_B"
assert_status "Bob cannot cancel Alice's booking" 403 "$RESP_STATUS" "$RESP_BODY" || true

# Alice cancels her own booking
http DELETE "/api/bookings/$BOOKING_ID" "" "$TOKEN_A"
assert_status "Alice cancels her booking" 200 "$RESP_STATUS" "$RESP_BODY" || true
assert_json_field "Status is cancelled" "$RESP_BODY" ".status" "cancelled" || true

# After cancellation, the same time slot should be available
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-03-01T09:00:00Z\",\"end_time\":\"2026-03-01T11:00:00Z\"}" "$TOKEN_B"
assert_status "Book cancelled slot succeeds" 201 "$RESP_STATUS" "$RESP_BODY" || true

echo ""

# =========================================
# Test 9: Auth enforcement
# =========================================
echo -e "${BOLD}[Test 9] Auth Enforcement${NC}"

# No token — create space
http POST "/api/spaces" '{"name":"No Auth Space","price_per_hour":10}'
assert_status "Create space without token → 401" 401 "$RESP_STATUS" "$RESP_BODY" || true

# No token — create booking
http POST "/api/bookings" "{\"space_id\":$SPACE_1_ID,\"start_time\":\"2026-04-01T09:00:00Z\",\"end_time\":\"2026-04-01T10:00:00Z\"}"
assert_status "Create booking without token → 401" 401 "$RESP_STATUS" "$RESP_BODY" || true

# No token — list my bookings
http GET "/api/bookings/my"
assert_status "List bookings without token → 401" 401 "$RESP_STATUS" "$RESP_BODY" || true

# No token — cancel booking
http DELETE "/api/bookings/$BOOKING_ID"
assert_status "Cancel booking without token → 401" 401 "$RESP_STATUS" "$RESP_BODY" || true

# Invalid token
http POST "/api/spaces" '{"name":"Bad Token","price_per_hour":10}' "invalid.token.here"
assert_status "Invalid token → 401" 401 "$RESP_STATUS" "$RESP_BODY" || true

echo ""

# --- Summary ---

echo "========================"
echo -e "${BOLD}Results:${NC} ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} (out of $TOTAL)"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
