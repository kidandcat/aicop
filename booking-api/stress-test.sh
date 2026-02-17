#!/usr/bin/env bash
#
# Stress test runner for Booking API implementations.
# Benchmarks each server using `hey` and collects results.
#
# Usage: ./stress-test.sh <language> <command to start server>
#   e.g. ./stress-test.sh typescript ./typescript/run.sh
#        ./stress-test.sh rust ./rust/target/release/booking-api
#
# Results are saved to results/<language>.json

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# --- Config ---
DURATION=10          # seconds per benchmark
CONCURRENCY=50       # concurrent connections
BASE_URL="http://localhost:8080"
DB_FILE="$DIR/booking.db"
RESULTS_DIR="$DIR/results"
SERVER_PID=""

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$DB_FILE"
}
trap cleanup EXIT

# Parses hey output, returns: rps|avg_ms|p99_ms
parse_hey_output() {
    local output="$1"

    local rps avg_s p99_s

    rps=$(echo "$output" | grep "Requests/sec:" | awk '{printf "%.1f", $2}')
    avg_s=$(echo "$output" | grep "Average:" | head -1 | awk '{print $2}')
    # hey format: "  99% in 0.1064 secs"
    p99_s=$(echo "$output" | grep "99% in" | head -1 | awk '{print $3}')
    # Fallback to Slowest if no percentile data
    if [[ -z "$p99_s" ]]; then
        p99_s=$(echo "$output" | grep "Slowest:" | awk '{print $2}')
    fi

    # Convert seconds to milliseconds
    local avg_ms p99_ms
    avg_ms=$(awk "BEGIN {printf \"%.2f\", ${avg_s:-0} * 1000}")
    p99_ms=$(awk "BEGIN {printf \"%.2f\", ${p99_s:-0} * 1000}")

    echo "${rps:-0}|${avg_ms}|${p99_ms}"
}

get_memory_kb() {
    local pid=$1
    ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0"
}

# --- Validate ---

if [[ $# -lt 2 ]]; then
    echo -e "${RED}Usage: $0 <language> <command to start server>${NC}"
    echo "  e.g. $0 typescript ./typescript/run.sh"
    exit 1
fi

if ! command -v hey &>/dev/null; then
    echo -e "${RED}hey is required. Install with: brew install hey${NC}"
    exit 1
fi

LANG_NAME="$1"
shift

mkdir -p "$RESULTS_DIR"

# --- Start server ---

echo -e "${BOLD}Booking API — Stress Test${NC}"
echo "========================="
echo -e "${CYAN}Language:${NC}    $LANG_NAME"
echo -e "${CYAN}Duration:${NC}    ${DURATION}s per endpoint"
echo -e "${CYAN}Concurrency:${NC} ${CONCURRENCY} connections"
echo ""

rm -f "$DB_FILE"

echo -e "${YELLOW}Starting server:${NC} $*"
"$@" &
SERVER_PID=$!

# Wait for server readiness (max 30 seconds)
echo -n "Waiting for server..."
READY=0
for i in $(seq 1 60); do
    if curl -s -o /dev/null "${BASE_URL}/api/spaces" 2>/dev/null; then
        echo -e " ${GREEN}ready${NC}"
        READY=1
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e " ${RED}server exited prematurely${NC}"
        exit 1
    fi
    sleep 0.5
done

if [[ "$READY" -eq 0 ]]; then
    echo -e " ${RED}timeout — server not responding${NC}"
    exit 1
fi

# Let server stabilize
sleep 1

# Measure idle memory
IDLE_MEM=$(get_memory_kb "$SERVER_PID")
echo -e "${CYAN}Idle memory:${NC} ${IDLE_MEM} KB ($(( IDLE_MEM / 1024 )) MB)"
echo ""

# --- Seed data ---

echo -e "${BOLD}Seeding test data...${NC}"

# Register user
curl -s -X POST "${BASE_URL}/api/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"bench@test.com","name":"Bench User","password":"benchpass123"}' > /dev/null

# Login to get token
TOKEN=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"bench@test.com","password":"benchpass123"}' | jq -r '.token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo -e "${RED}Failed to obtain auth token${NC}"
    exit 1
fi

# Create spaces for querying
for i in $(seq 1 10); do
    curl -s -X POST "${BASE_URL}/api/spaces" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "{\"name\":\"Space $i\",\"description\":\"Bench space $i\",\"price_per_hour\":$(( i * 10 ))}" > /dev/null
done

# Create some bookings for querying
for i in $(seq 1 5); do
    curl -s -X POST "${BASE_URL}/api/bookings" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "{\"space_id\":$i,\"start_time\":\"2026-06-0${i}T09:00:00Z\",\"end_time\":\"2026-06-0${i}T11:00:00Z\"}" > /dev/null
done

echo -e "${GREEN}Seeded 1 user, 10 spaces, 5 bookings${NC}"
echo ""

# --- Warmup ---
echo -e "${BOLD}Warming up (3s)...${NC}"
hey -z 3s -c 10 "${BASE_URL}/api/spaces" > /dev/null 2>&1
echo ""

# --- Benchmarks ---

echo -e "${BOLD}Running benchmarks...${NC}"
echo ""

# 1. GET /api/spaces (unauthenticated read)
echo -e "${CYAN}[1/4] GET /api/spaces${NC}"
RESULT_SPACES=$(hey -z ${DURATION}s -c ${CONCURRENCY} "${BASE_URL}/api/spaces" 2>&1)
SPACES_PARSED=$(parse_hey_output "$RESULT_SPACES")
SPACES_RPS=$(echo "$SPACES_PARSED" | cut -d'|' -f1)
SPACES_AVG=$(echo "$SPACES_PARSED" | cut -d'|' -f2)
SPACES_P99=$(echo "$SPACES_PARSED" | cut -d'|' -f3)
echo -e "  RPS: ${GREEN}${SPACES_RPS}${NC}  Avg: ${SPACES_AVG}ms  P99: ${SPACES_P99}ms"

# 2. GET /api/spaces?min_price=30&max_price=80 (filtered query)
echo -e "${CYAN}[2/4] GET /api/spaces (filtered)${NC}"
RESULT_FILTER=$(hey -z ${DURATION}s -c ${CONCURRENCY} "${BASE_URL}/api/spaces?min_price=30&max_price=80" 2>&1)
FILTER_PARSED=$(parse_hey_output "$RESULT_FILTER")
FILTER_RPS=$(echo "$FILTER_PARSED" | cut -d'|' -f1)
FILTER_AVG=$(echo "$FILTER_PARSED" | cut -d'|' -f2)
FILTER_P99=$(echo "$FILTER_PARSED" | cut -d'|' -f3)
echo -e "  RPS: ${GREEN}${FILTER_RPS}${NC}  Avg: ${FILTER_AVG}ms  P99: ${FILTER_P99}ms"

# 3. GET /api/bookings/my (authenticated read)
echo -e "${CYAN}[3/4] GET /api/bookings/my (authenticated)${NC}"
RESULT_BOOKINGS=$(hey -z ${DURATION}s -c ${CONCURRENCY} \
    -H "Authorization: Bearer ${TOKEN}" \
    "${BASE_URL}/api/bookings/my" 2>&1)
BOOKINGS_PARSED=$(parse_hey_output "$RESULT_BOOKINGS")
BOOKINGS_RPS=$(echo "$BOOKINGS_PARSED" | cut -d'|' -f1)
BOOKINGS_AVG=$(echo "$BOOKINGS_PARSED" | cut -d'|' -f2)
BOOKINGS_P99=$(echo "$BOOKINGS_PARSED" | cut -d'|' -f3)
echo -e "  RPS: ${GREEN}${BOOKINGS_RPS}${NC}  Avg: ${BOOKINGS_AVG}ms  P99: ${BOOKINGS_P99}ms"

# 4. POST /api/auth/login (CPU-intensive: password hashing)
echo -e "${CYAN}[4/4] POST /api/auth/login (password hashing)${NC}"
RESULT_LOGIN=$(hey -z ${DURATION}s -c ${CONCURRENCY} \
    -m POST \
    -H "Content-Type: application/json" \
    -d '{"email":"bench@test.com","password":"benchpass123"}' \
    "${BASE_URL}/api/auth/login" 2>&1)
LOGIN_PARSED=$(parse_hey_output "$RESULT_LOGIN")
LOGIN_RPS=$(echo "$LOGIN_PARSED" | cut -d'|' -f1)
LOGIN_AVG=$(echo "$LOGIN_PARSED" | cut -d'|' -f2)
LOGIN_P99=$(echo "$LOGIN_PARSED" | cut -d'|' -f3)
echo -e "  RPS: ${GREEN}${LOGIN_RPS}${NC}  Avg: ${LOGIN_AVG}ms  P99: ${LOGIN_P99}ms"

# Measure peak memory
PEAK_MEM=$(get_memory_kb "$SERVER_PID")

echo ""
echo -e "${CYAN}Peak memory:${NC} ${PEAK_MEM} KB ($(( PEAK_MEM / 1024 )) MB)"

# --- Save results ---

cat > "${RESULTS_DIR}/${LANG_NAME}.json" <<JSONEOF
{
  "language": "${LANG_NAME}",
  "concurrency": ${CONCURRENCY},
  "duration_seconds": ${DURATION},
  "idle_memory_kb": ${IDLE_MEM},
  "peak_memory_kb": ${PEAK_MEM},
  "benchmarks": {
    "get_spaces": {
      "rps": ${SPACES_RPS},
      "avg_latency_ms": ${SPACES_AVG},
      "p99_latency_ms": ${SPACES_P99}
    },
    "get_spaces_filtered": {
      "rps": ${FILTER_RPS},
      "avg_latency_ms": ${FILTER_AVG},
      "p99_latency_ms": ${FILTER_P99}
    },
    "get_bookings_auth": {
      "rps": ${BOOKINGS_RPS},
      "avg_latency_ms": ${BOOKINGS_AVG},
      "p99_latency_ms": ${BOOKINGS_P99}
    },
    "post_login": {
      "rps": ${LOGIN_RPS},
      "avg_latency_ms": ${LOGIN_AVG},
      "p99_latency_ms": ${LOGIN_P99}
    }
  }
}
JSONEOF

echo ""
echo -e "${BOLD}Results saved to ${RESULTS_DIR}/${LANG_NAME}.json${NC}"
echo ""

# --- Summary table ---
echo -e "${BOLD}Summary: ${LANG_NAME}${NC}"
echo "┌─────────────────────────────┬──────────┬──────────┬──────────┐"
echo "│ Endpoint                    │ Req/sec  │ Avg (ms) │ P99 (ms) │"
echo "├─────────────────────────────┼──────────┼──────────┼──────────┤"
printf "│ GET /api/spaces             │ %8s │ %8s │ %8s │\n" "$SPACES_RPS" "$SPACES_AVG" "$SPACES_P99"
printf "│ GET /api/spaces (filtered)  │ %8s │ %8s │ %8s │\n" "$FILTER_RPS" "$FILTER_AVG" "$FILTER_P99"
printf "│ GET /api/bookings/my        │ %8s │ %8s │ %8s │\n" "$BOOKINGS_RPS" "$BOOKINGS_AVG" "$BOOKINGS_P99"
printf "│ POST /api/auth/login        │ %8s │ %8s │ %8s │\n" "$LOGIN_RPS" "$LOGIN_AVG" "$LOGIN_P99"
echo "└─────────────────────────────┴──────────┴──────────┴──────────┘"
echo ""
echo -e "Memory: idle=$(( IDLE_MEM / 1024 )) MB, peak=$(( PEAK_MEM / 1024 )) MB"
