#!/bin/bash
set -euo pipefail

# Echelon E2E Pipeline Test
# Validates: Docker Compose → Redis → BuildManager → implement.sh → PR → ReviewManager → verdicts

REDIS_CLI="docker compose -f echelon-docker/docker-compose.yml exec -T redis-primary redis-cli"
COMPOSE="docker compose -f echelon-docker/docker-compose.yml --profile managers"

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

echo "=== Echelon E2E Pipeline Test ==="

# 1. Start fresh
echo "[1/7] Starting services..."
$COMPOSE down -v 2>/dev/null || true
$COMPOSE up -d
$COMPOSE config >/dev/null 2>&1 && ok "Docker Compose validates" || fail "Docker Compose validates"

# 2. Wait for health
echo "[2/7] Waiting for services..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/health >/dev/null 2>&1; then ok "Router health"; break; fi
  [ "$i" -eq 30 ] && fail "Router health timeout"; sleep 2
done

# 3. Push task to stream
echo "[3/7] Pushing build task..."
TASK_ID="e2e-$(date +%s)"
$REDIS_CLI XADD tasks:build "*" taskId "$TASK_ID" issueUrl "https://github.com/thepragmatik/echelon/issues/1" priority "0" 2>/dev/null
$REDIS_CLI XLEN tasks:build 2>/dev/null | grep -q '[1-9]' && ok "Task pushed to tasks:build" || fail "Task not in stream"

# 4. Check builder processes it
echo "[4/7] Checking builder..."
$COMPOSE logs builder --tail 20 2>/dev/null | grep -q "$TASK_ID" && ok "Builder processing task" || fail "Builder not processing (may be async — check manually)"

# 5. Check results stream
echo "[5/7] Checking results..."
$COMPOSE exec -T redis-primary redis-cli XLEN results:review 2>/dev/null | grep -q '[0-9]' && ok "results:review stream exists" || info "results:review stream empty (expected if no review completed yet)"

# 6. Check existing PRs from the builder
echo "[6/7] Checking for builder PRs..."
gh pr list --state open --limit 1 --json number,title --jq '.[0].number // "none"' 2>/dev/null | grep -q '[0-9]' && ok "Open PRs exist" || fail "No PRs found"

# 7. Cleanup
echo "[7/7] Cleanup..."
$COMPOSE down -v 2>/dev/null && ok "Clean shutdown" || fail "Cleanup"

echo ""
echo "=== Results: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
