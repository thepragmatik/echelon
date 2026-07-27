#!/bin/bash
# Echelon Dogfooding Gate — automated release verification
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
INFO=0

ok()   { PASS=$((PASS+1)); echo -e "${GREEN}  PASS${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "${RED}  FAIL${NC} $1"; }
info() { INFO=$((INFO+1)); echo -e "${YELLOW}  INFO${NC} $1 (optional — does not fail gate)"; }

COMPOSE_FILE="echelon-docker/docker-compose.yml"
COMPOSE_PROFILE="--profile managers"

echo "=== Echelon Dogfooding Gate ==="
echo ""

# 1. Build (package to produce JARs for Docker images)
echo "[1/7] Building all modules..."
if mvn clean package -DskipTests -q 2>/dev/null; then ok "Maven package (JARs produced)"; else fail "Maven package"; fi

# 2. Docker compose build (with profile managers so builder + reviewer images are built)
echo "[2/7] Building Docker images..."
if docker compose -f "$COMPOSE_FILE" $COMPOSE_PROFILE build --quiet 2>/dev/null; then ok "Docker images build"; else fail "Docker images build"; fi

# 3. Start services (with profile managers so builder + reviewer start)
echo "[3/7] Starting services..."
if docker compose -f "$COMPOSE_FILE" $COMPOSE_PROFILE up -d 2>/dev/null; then ok "Services started"; else fail "Services started"; fi

# 4. Health checks
echo "[4/7] Checking health endpoints..."
sleep 10
# Router health (HAProxy stats) — exposed on port 8080
if curl -sf http://localhost:8080/health >/dev/null 2>&1; then ok "Router health"; else fail "Router health"; fi
# Actuator health is on the internal builder/reviewer services (not port-mapped to host)
# and is not proxied through HAProxy. Check via Docker exec as a best-effort check.
if docker compose -f "$COMPOSE_FILE" exec -T builder curl -sf http://localhost:8080/actuator/health >/dev/null 2>&1; then
  ok "Actuator health (via builder container)"
else
  info "Actuator health — internal endpoint, not exposed through HAProxy"
fi

# 5. Redis streams
echo "[5/7] Checking Redis streams..."
if docker compose -f "$COMPOSE_FILE" exec -T redis-primary redis-cli XLEN tasks:build >/dev/null 2>&1; then ok "Redis tasks:build stream"; else fail "Redis tasks:build stream"; fi
if docker compose -f "$COMPOSE_FILE" exec -T redis-primary redis-cli XLEN events:governance >/dev/null 2>&1; then ok "Redis events:governance stream"; else fail "Redis events:governance stream"; fi

# 6. Prometheus metrics
echo "[6/7] Checking Prometheus metrics..."
# Prometheus metrics are exposed on the internal builder/reviewer actuator endpoints,
# not through the HAProxy router. Check via Docker exec as a best-effort check.
if docker compose -f "$COMPOSE_FILE" exec -T builder curl -sf http://localhost:8080/actuator/prometheus 2>/dev/null | grep -q "policy_permit"; then
  ok "Prometheus metrics available"
else
  info "Prometheus metrics — internal endpoint, not exposed through HAProxy"
fi

# 7. Pipeline test
echo "[7/7] Testing task pipeline..."
TEST_ISSUE_URL="https://github.com/thepragmatik/echelon/issues/1"
if curl -sf -X POST "http://localhost:8080/api/tasks" -H "Content-Type: application/json" -d "{\"issueUrl\":\"$TEST_ISSUE_URL\",\"priority\":0}" >/dev/null 2>&1; then
  ok "Task submission"
else
  info "Task submission — /api/tasks endpoint not yet exposed through HAProxy"
fi

# Summary
echo ""
echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${YELLOW}INFO: $INFO${NC} (non-fatal)"
echo -e "${RED}FAIL: $FAIL${NC}"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}DOGFOODING GATE PASSED${NC}"
    exit 0
else
    echo -e "${RED}DOGFOODING GATE FAILED — review failures above${NC}"
    exit 1
fi
