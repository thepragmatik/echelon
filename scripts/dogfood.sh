#!/bin/bash
# Echelon Dogfooding Gate — automated release verification
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo -e "${GREEN}  PASS${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "${RED}  FAIL${NC} $1"; }

echo "=== Echelon Dogfooding Gate ==="
echo ""

# 1. Build
echo "[1/7] Building all modules..."
if mvn clean compile -q 2>/dev/null; then ok "Maven compile"; else fail "Maven compile"; fi

# 2. Docker compose build
echo "[2/7] Building Docker images..."
if docker compose -f echelon-docker/docker-compose.yml build --quiet 2>/dev/null; then ok "Docker images build"; else fail "Docker images build"; fi

# 3. Start services
echo "[3/7] Starting services..."
if docker compose -f echelon-docker/docker-compose.yml up -d 2>/dev/null; then ok "Services started"; else fail "Services started"; fi

# 4. Health checks
echo "[4/7] Checking health endpoints..."
sleep 10
if curl -sf http://localhost:8080/actuator/health >/dev/null 2>&1; then ok "Actuator health"; else fail "Actuator health"; fi
if curl -sf http://localhost:8080/health >/dev/null 2>&1; then ok "Router health"; else fail "Router health"; fi

# 5. Redis streams
echo "[5/7] Checking Redis streams..."
if docker compose exec -T redis-primary redis-cli XLEN tasks:build >/dev/null 2>&1; then ok "Redis tasks:build stream"; else fail "Redis tasks:build stream"; fi
if docker compose exec -T redis-primary redis-cli XLEN events:governance >/dev/null 2>&1; then ok "Redis events:governance stream"; else fail "Redis events:governance stream"; fi

# 6. Prometheus metrics
echo "[6/7] Checking Prometheus metrics..."
if curl -sf http://localhost:8080/actuator/prometheus 2>/dev/null | grep -q "policy_permit"; then ok "Prometheus metrics available"; else fail "Prometheus metrics"; fi

# 7. Pipeline test
echo "[7/7] Testing task pipeline..."
TEST_ISSUE_URL="https://github.com/thepragmatik/echelon/issues/1"
if curl -sf -X POST "http://localhost:8080/api/tasks" -H "Content-Type: application/json" -d "{\"issueUrl\":\"$TEST_ISSUE_URL\",\"priority\":0}" >/dev/null 2>&1; then ok "Task submission"; else fail "Task submission (API may not be exposed)"; fi

# Summary
echo ""
echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${RED}FAIL: $FAIL${NC}"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}DOGFOODING GATE PASSED${NC}"
    exit 0
else
    echo -e "${RED}DOGFOODING GATE FAILED — review failures above${NC}"
    exit 1
fi
