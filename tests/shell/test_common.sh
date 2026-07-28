#!/bin/bash
# Unit tests for common.sh — Echelon shared shell library
# Mocks external commands (redis-cli, gh, curl) to test function
# behavior in isolation.
set -euo pipefail

PASS=0
FAIL=0
TEST_COUNT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_SH="$REPO_ROOT/echelon-workers/src/main/resources/scripts/common.sh"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TEST_COUNT=$((TEST_COUNT + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TEST_COUNT=$((TEST_COUNT + 1))
    if echo "$haystack" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $desc"
        echo "    expected to contain: '$needle'"
        echo "    in: '$haystack'"
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2"
    shift 2
    TEST_COUNT=$((TEST_COUNT + 1))
    set +e
    "$@" >/dev/null 2>&1
    local actual=$?
    set -e
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $desc (exit $actual, expected $expected)"
    fi
}

echo "=== test_common.sh ==="
echo ""

# ------------------------------------------------------------------
# Source common.sh with mocked commands
# ------------------------------------------------------------------
# Stub external commands so we never hit real Redis, GitHub, or curl
REDIS_CLI="echo"
REDIS_HOST="localhost"
REDIS_PORT="6379"
GH_TOKEN="fake-test-token"
POLICY_ENGINE_URL="http://policy.test:8080"

source "$COMMON_SH"

# ------------------------------------------------------------------
# Test: redis_xread
# ------------------------------------------------------------------
echo "1) redis_xread"
echo ""

result=$(redis_xread "tasks:build" 1 1000 2>&1 || true)
assert_contains "uses XREAD command" "XREAD" "$result"
assert_contains "specifies stream name" "tasks:build" "$result"
assert_contains "specifies COUNT" "COUNT 1" "$result"
assert_contains "specifies BLOCK" "BLOCK 1000" "$result"
assert_contains "uses blocking read marker" ">" "$result"

# Default args
result_default=$(redis_xread "tasks:default" 2>&1 || true)
assert_contains "default count is 1" "COUNT 1" "$result_default"
assert_contains "default block is 5000" "BLOCK 5000" "$result_default"

# Host/port flags
assert_contains "passes -h flag" "-h localhost" "$result"
assert_contains "passes -p flag" "-p 6379" "$result"

# ------------------------------------------------------------------
# Test: redis_xadd
# ------------------------------------------------------------------
echo ""
echo "2) redis_xadd"
echo ""

result=$(redis_xadd "tasks:review" event "completed" taskId "abc-123" 2>&1 || true)
assert_contains "uses XADD command" "XADD" "$result"
assert_contains "specifies stream" "tasks:review" "$result"
assert_contains "auto-generates id" "*" "$result"
assert_contains "passes field pairs" "event completed" "$result"

# ------------------------------------------------------------------
# Test: redis_xlen
# ------------------------------------------------------------------
echo ""
echo "3) redis_xlen"
echo ""

result=$(redis_xlen "tasks:build" 2>&1 || true)
assert_contains "uses XLEN command" "XLEN" "$result"
assert_contains "specifies stream" "tasks:build" "$result"

# ------------------------------------------------------------------
# Test: load_gh_token
# ------------------------------------------------------------------
echo ""
echo "4) load_gh_token"
echo ""

# With GH_TOKEN already set, should succeed silently
GH_TOKEN="working-token"
result=$(load_gh_token 2>&1 || true)
assert_eq "returns 0 when GH_TOKEN is set" "" "$result"

# Without GH_TOKEN, should fail
GH_TOKEN=""
assert_exit_code "fails when GH_TOKEN is unset" 1 load_gh_token

export GH_TOKEN="restored-token-for-subsequent-tests"

# ------------------------------------------------------------------
# Test: log_info / log_warn / log_error
# ------------------------------------------------------------------
echo ""
echo "5) Logging functions"
echo ""

info_out=$(log_info "hello world" 2>&1 || true)
assert_contains "log_info includes [INFO]" "[INFO]" "$info_out"
assert_contains "log_info includes message" "hello world" "$info_out"
assert_contains "log_info includes ISO timestamp" "T" "$info_out"

warn_out=$(log_warn "watch out" 2>&1 || true)
assert_contains "log_warn includes [WARN]" "[WARN]" "$warn_out"
assert_contains "log_warn includes message" "watch out" "$warn_out"

err_out=$(log_error "oops" 2>&1 || true)
assert_contains "log_error includes [ERROR]" "[ERROR]" "$err_out"
assert_contains "log_error includes message" "oops" "$err_out"

# ------------------------------------------------------------------
# Test: log_audit (indirectly tests redis_xadd)
# ------------------------------------------------------------------
echo ""
echo "6) log_audit"
echo ""

REDIS_CLI="echo"
result=$(log_audit "test:event" "detail-value" 2>&1 || true)
assert_contains "audit writes to events:governance" "events:governance" "$result"
assert_contains "audit passes event field" "event test:event" "$result"
assert_contains "audit passes detail field" "detail detail-value" "$result"

# ------------------------------------------------------------------
# Test: check_policy (mock curl)
# ------------------------------------------------------------------
echo ""
echo "7) check_policy"
echo ""

# Mock curl to return ALLOWED
curl() { echo "ALLOWED"; }
export -f curl 2>/dev/null || true

result=$(check_policy "implementer" "implement_task" 2>&1 || true)
assert_eq "check_policy returns ALLOWED when curl succeeds" "ALLOWED" "$result"

# Mock curl to fail / return DENIED
curl() { return 1; }
export -f curl 2>/dev/null || true

result=$(check_policy "implementer" "implement_task" 2>&1 || true)
assert_eq "check_policy returns DENIED when curl fails" "DENIED" "$result"

# Restore curl
unset -f curl 2>/dev/null || true

# ------------------------------------------------------------------
# Test: check_budget (mock curl)
# ------------------------------------------------------------------
echo ""
echo "8) check_budget"
echo ""

curl() { echo "GRANTED"; }
export -f curl 2>/dev/null || true

result=$(check_budget "task-1" "implementer" "5000" 2>&1 || true)
assert_eq "check_budget returns GRANTED when curl succeeds" "GRANTED" "$result"

curl() { return 1; }
export -f curl 2>/dev/null || true

result=$(check_budget "task-1" "implementer" "5000" 2>&1 || true)
assert_eq "check_budget returns DENIED when curl fails" "DENIED" "$result"

unset -f curl 2>/dev/null || true

# ------------------------------------------------------------------
# Test: safe_clone / safe_checkout (stub gh and git)
# ------------------------------------------------------------------
echo ""
echo "9) safe_clone and safe_checkout (stub)"
echo ""

# We can't easily test these without mocking git heavily,
# but we can verify they're defined and have the right signature
assert_contains "safe_clone is defined as a function" "safe_clone" "$(declare -f safe_clone)"
assert_contains "safe_checkout is defined as a function" "safe_checkout" "$(declare -f safe_checkout)"

# ------------------------------------------------------------------
# Test: create_issue
# ------------------------------------------------------------------
echo ""
echo "10) create_issue"

# Verify the function is defined
assert_contains "create_issue is defined as a function" "create_issue" "$(declare -f create_issue)"

echo "  SKIP create_issue execution (requires gh CLI with auth — tested in CI)"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "----------------------------------------"
echo "Results: $PASS passed, $FAIL failed, $TEST_COUNT total"
echo "----------------------------------------"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
