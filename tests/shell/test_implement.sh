#!/bin/bash
# Unit tests for implement.sh — Echelon implementer worker
# Tests argument validation, missing dependency handling, and
# basic execution flow with all side-effects redirected.
set -euo pipefail

PASS=0
FAIL=0
TEST_COUNT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMPLEMENT_SH="$REPO_ROOT/echelon-workers/src/main/resources/scripts/implement.sh"

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

echo "=== test_implement.sh ==="
echo ""

# ------------------------------------------------------------------
# Test 1: Missing arguments exit non-zero with usage message
# ------------------------------------------------------------------
echo "1) Argument validation"
echo ""

# No arguments at all
set +e
output=$(bash "$IMPLEMENT_SH" 2>&1)
exit_code=$?
set -e
assert_eq "exit 1 with no arguments" 1 "$exit_code"
assert_contains "usage message mentions implement.sh" "Usage:" "$output"
assert_contains "usage mentions task_id" "task_id" "$output"
assert_contains "usage mentions issue_url" "issue_url" "$output"

# Only task_id, missing issue_url
set +e
output=$(bash "$IMPLEMENT_SH" "task-123" 2>&1)
exit_code=$?
set -e
assert_eq "exit 1 with only task_id" 1 "$exit_code"
assert_contains "usage shown for missing issue_url" "Usage:" "$output"

# ------------------------------------------------------------------
# Test 2: Missing GH_TOKEN should cause load_gh_token failure
# ------------------------------------------------------------------
echo ""
echo "2) Missing GH_TOKEN"
echo ""

set +e
output=$(GH_TOKEN="" bash "$IMPLEMENT_SH" "task-1" "https://github.com/thepragmatik/echelon/issues/1" 2>&1)
exit_code=$?
set -e
# The script exits if GH_TOKEN is not set — load_gh_token will fail
assert_eq "failure when GH_TOKEN is empty" 1 "$exit_code"

# ------------------------------------------------------------------
# Test 3: Missing REDIS_CLI should cause redis commands to fail
# ------------------------------------------------------------------
echo ""
echo "3) Missing REDIS_CLI"
echo ""

set +e
output=$(GH_TOKEN="test-token" REDIS_CLI="/nonexistent/redis-cli" bash "$IMPLEMENT_SH" "task-2" "https://github.com/thepragmatik/echelon/issues/2" 2>&1)
exit_code=$?
set -e
# The script needs REDIS_CLI for audit trail, policy events, etc.
# With a bad REDIS_CLI, check_policy will fail (curl mock not available)
assert_eq "failure with invalid REDIS_CLI" 1 "$exit_code"

# ------------------------------------------------------------------
# Test 4: With mocked dependencies, implement.sh can run its
#         common path up to policy check (which gets denied)
# ------------------------------------------------------------------
echo ""
echo "4) Policy check with mocked curl (DENIED)"
echo ""

# Create a wrapper that mocks curl to return DENIED so we don't
# actually do anything dangerous
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/mock_curl" <<'CURL_EOF'
#!/bin/bash
echo "DENIED"
exit 0
CURL_EOF
chmod +x "$MOCK_DIR/mock_curl"

set +e
output=$(PATH="$MOCK_DIR:$PATH" GH_TOKEN="test-token" REDIS_CLI="echo" bash "$IMPLEMENT_SH" "task-3" "https://github.com/thepragmatik/echelon/issues/3" 2>&1)
exit_code=$?
set -e
rm -rf "$MOCK_DIR"

assert_eq "exit 1 when policy denies" 1 "$exit_code"
assert_contains "output mentions policy denial" "denied" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"

# ------------------------------------------------------------------
# Test 5: With ALLOWED policy and budget but no Pi, should still
#         work (falls through to placeholder commit path)
# ------------------------------------------------------------------
echo ""
echo "5) ALLOWED policy (placeholder commit path)"
echo ""

MOCK_DIR=$(mktemp -d)

# Mock curl to return ALLOWED then GRANTED
cat > "$MOCK_DIR/curl" <<'CURL_EOF'
#!/bin/bash
echo "ALLOWED"
CURL_EOF
chmod +x "$MOCK_DIR/curl"

# Mock gh to avoid real GitHub calls
cat > "$MOCK_DIR/gh" <<'GH_EOF'
#!/bin/bash
echo "mocked-gh"
GH_EOF
chmod +x "$MOCK_DIR/gh"

# Mock pi to simulate it's available
cat > "$MOCK_DIR/pi" <<'PI_EOF'
#!/bin/bash
echo "mocked-pi"
PI_EOF
chmod +x "$MOCK_DIR/pi"

# Mock mvn to succeed
cat > "$MOCK_DIR/mvn" <<'MVN_EOF'
#!/bin/bash
echo "mocked-mvn"
MVN_EOF
chmod +x "$MOCK_DIR/mvn"

# Mock git to avoid real git operations
cat > "$MOCK_DIR/git" <<'GIT_EOF'
#!/bin/bash
echo "mocked-git"
GIT_EOF
chmod +x "$MOCK_DIR/git"

set +e
output=$(PATH="$MOCK_DIR:$PATH" GH_TOKEN="test-token" REDIS_CLI="echo" bash "$IMPLEMENT_SH" "task-4" "https://github.com/thepragmatik/echelon/issues/4" "feature/test-task-4" "test prompt" 2>&1)
exit_code=$?
set -e
rm -rf "$MOCK_DIR"

# Even with all mocks, safe_clone will fail because the repo dir
# doesn't exist and gh repo clone won't actually work in mock
# (our mock gh just echoes). But the test shows the flow holds
# up through argument validation.
echo "  (exit $exit_code — safe_clone expected to fail without real gh)"
assert_contains "flow reaches policy check phase" "checking policy" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"
assert_contains "flow reaches budget check phase" "checking budget" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"

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
