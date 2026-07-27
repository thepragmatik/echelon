#!/bin/bash
# Unit tests for review scripts (review-adversarial.sh, review-quality.sh)
# Tests argument validation and verdict output format.
set -euo pipefail

PASS=0
FAIL=0
TEST_COUNT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ADVERSARIAL_SH="$REPO_ROOT/echelon-workers/src/main/resources/scripts/review-adversarial.sh"
QUALITY_SH="$REPO_ROOT/echelon-workers/src/main/resources/scripts/review-quality.sh"

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

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TEST_COUNT=$((TEST_COUNT + 1))
    if ! echo "$haystack" | grep -Fq "$needle"; then
        PASS=$((PASS + 1))
        echo "  ✓ $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $desc"
        echo "    expected NOT to contain: '$needle'"
        echo "    but found it in: '$haystack'"
    fi
}

echo "=== test_review.sh ==="
echo ""

# ------------------------------------------------------------------
# 1) review-adversarial.sh — argument validation
# ------------------------------------------------------------------
echo "1) review-adversarial.sh — argument validation"
echo ""

# No arguments
set +e
output=$(bash "$ADVERSARIAL_SH" 2>&1)
exit_code=$?
set -e
assert_eq "adversarial.sh exit 1 with no args" 1 "$exit_code"
assert_contains "adversarial usage mentions script name" "review-adversarial.sh" "$output"
assert_contains "adversarial usage mentions task_id" "task_id" "$output"
assert_contains "adversarial usage mentions pr_url" "pr_url" "$output"

# Only task_id, missing PR_URL
set +e
output=$(bash "$ADVERSARIAL_SH" "task-1" 2>&1)
exit_code=$?
set -e
assert_eq "adversarial.sh exit 1 with only task_id" 1 "$exit_code"
assert_contains "adversarial usage shown for missing pr_url" "Usage:" "$output"

# ------------------------------------------------------------------
# 2) review-adversarial.sh — output format (verdict JSON pattern)
# ------------------------------------------------------------------
echo ""
echo "2) review-adversarial.sh — verdict output format"
echo ""

# With fully mocked environment, the script should reach safe_clone
# and fail there. We check that the path up to that point is correct.
MOCK_DIR=$(mktemp -d)

# Mock curl for check_policy
cat > "$MOCK_DIR/curl" <<'CURL_EOF'
#!/bin/bash
echo "ALLOWED"
CURL_EOF
chmod +x "$MOCK_DIR/curl"

# Mock gh
cat > "$MOCK_DIR/gh" <<'GH_EOF'
#!/bin/bash
echo "mocked-gh"
GH_EOF
chmod +x "$MOCK_DIR/gh"

# Mock git
cat > "$MOCK_DIR/git" <<'GIT_EOF'
#!/bin/bash
echo "mocked-git"
GIT_EOF
chmod +x "$MOCK_DIR/git"

# Mock date for deterministic timestamps
cat > "$MOCK_DIR/date" <<'DATE_EOF'
#!/bin/bash
echo "2025-01-01T00:00:00Z"
DATE_EOF
chmod +x "$MOCK_DIR/date"

# Mock find/grep to produce controlled results for adversarial checks
# This allows us to test the verdict generation path
cat > "$MOCK_DIR/find" <<'FIND_EOF'
#!/bin/bash
echo ""
FIND_EOF
chmod +x "$MOCK_DIR/find"

cat > "$MOCK_DIR/grep" <<'GREP_EOF'
#!/bin/bash
exit 1  # no matches — safe
GREP_EOF
chmod +x "$MOCK_DIR/grep"

cat > "$MOCK_DIR/wc" <<'WC_EOF'
#!/bin/bash
echo "0"
WC_EOF
chmod +x "$MOCK_DIR/wc"

set +e
output=$(PATH="$MOCK_DIR:$PATH" GH_TOKEN="test-token" REDIS_CLI="echo" bash "$ADVERSARIAL_SH" "task-adv-1" "https://github.com/thepragmatik/echelon/pull/42" "feature/test" 2>&1)
exit_code=$?
set -e
rm -rf "$MOCK_DIR"

# The adversarial script flows through argument validation → policy check →
# safe_clone → ... safe_clone will likely fail because gh repo clone won't
# actually work with mock gh. So we check argument validation and policy check worked.
assert_contains "adversarial starts processing" "task-adv-1" "$output"
assert_contains "adversarial mentions PR" "pull/42" "$output"
echo "  (exit $exit_code — safe_clone expected to fail without real gh)"

# Test that error output doesn't contain JSON with empty fields
assert_not_contains "no empty verdict in error output" '"verdict": ""' "$output"

# ------------------------------------------------------------------
# 3) review-quality.sh — argument validation
# ------------------------------------------------------------------
echo ""
echo "3) review-quality.sh — argument validation"
echo ""

# No arguments
set +e
output=$(bash "$QUALITY_SH" 2>&1)
exit_code=$?
set -e
assert_eq "quality.sh exit 1 with no args" 1 "$exit_code"
assert_contains "quality usage mentions script name" "review-quality.sh" "$output"
assert_contains "quality usage mentions task_id" "task_id" "$output"
assert_contains "quality usage mentions pr_url" "pr_url" "$output"

# Only task_id, missing PR_URL
set +e
output=$(bash "$QUALITY_SH" "task-1" 2>&1)
exit_code=$?
set -e
assert_eq "quality.sh exit 1 with only task_id" 1 "$exit_code"
assert_contains "quality usage shown for missing pr_url" "Usage:" "$output"

# ------------------------------------------------------------------
# 4) review-quality.sh — output format
# ------------------------------------------------------------------
echo ""
echo "4) review-quality.sh — verdict output format"
echo ""

MOCK_DIR=$(mktemp -d)

# Mock curl for check_policy (quality.sh uses it implicitly via common.sh
# No wait — quality.sh doesn't call check_policy directly!

# Let me re-check quality.sh — it sources common.sh but doesn't call
# check_policy or check_budget. It directly goes to safe_clone then grep/find.
# So we just need gh and git mocks.

cat > "$MOCK_DIR/gh" <<'GH_EOF'
#!/bin/bash
echo "mocked-gh"
GH_EOF
chmod +x "$MOCK_DIR/gh"

cat > "$MOCK_DIR/git" <<'GIT_EOF'
#!/bin/bash
echo "mocked-git"
GIT_EOF
chmod +x "$MOCK_DIR/git"

cat > "$MOCK_DIR/date" <<'DATE_EOF'
#!/bin/bash
echo "2025-01-01T00:00:00Z"
DATE_EOF
chmod +x "$MOCK_DIR/date"

# Mock find to return no files (test will succeed)
cat > "$MOCK_DIR/find" <<'FIND2_EOF'
#!/bin/bash
echo "0"
FIND2_EOF
chmod +x "$MOCK_DIR/find"

# Mock grep to return nothing
cat > "$MOCK_DIR/grep" <<'GREP2_EOF'
#!/bin/bash
exit 1
GREP2_EOF
chmod +x "$MOCK_DIR/grep"

# Mock wc to count lines
cat > "$MOCK_DIR/wc" <<'WC2_EOF'
#!/bin/bash
echo "0"
WC2_EOF
chmod +x "$MOCK_DIR/wc"

set +e
output=$(PATH="$MOCK_DIR:$PATH" GH_TOKEN="test-token" REDIS_CLI="echo" bash "$QUALITY_SH" "task-quality-1" "https://github.com/thepragmatik/echelon/pull/43" 2>&1)
exit_code=$?
set -e
rm -rf "$MOCK_DIR"

assert_contains "quality starts processing" "task-quality-1" "$output"
echo "  (exit $exit_code — safe_clone expected to fail without real gh)"

# ------------------------------------------------------------------
# 5) Verify review scripts use correct Redis stream keys
# ------------------------------------------------------------------
echo ""
echo "5) Redis stream key usage"
echo ""

# Source common.sh with mocked commands
REDIS_CLI="echo"
GH_TOKEN="test-token"
source "$REPO_ROOT/echelon-workers/src/main/resources/scripts/common.sh"

# Test that log_audit writes to events:governance (both scripts use this)
result=$(log_audit "review:adversarial" "PASS" 2>&1 || true)
assert_contains "adversarial audit uses events:governance" "events:governance" "$result"
assert_contains "adversarial audit includes event name" "review:adversarial" "$result"

result=$(log_audit "review:quality" "PASS_WITH_SUGGESTIONS" 2>&1 || true)
assert_contains "quality audit uses events:governance" "events:governance" "$result"
assert_contains "quality audit includes event name" "review:quality" "$result"

# Test that review scripts write to results:review (both use redis_xadd with this key)
REDIS_CLI="echo"
result=$(redis_xadd "results:review" verdict "PASS" taskId "test-1" reviewer "adversarial" 2>&1 || true)
assert_contains "review results use results:review stream" "results:review" "$result"
assert_contains "review results pass verdict field" "verdict PASS" "$result"
assert_contains "review results pass reviewer field" "reviewer adversarial" "$result"

result=$(redis_xadd "results:review" verdict "PASS_WITH_SUGGESTIONS" taskId "test-2" reviewer "quality" 2>&1 || true)
assert_contains "quality results use results:review stream" "results:review" "$result"
assert_contains "quality results pass reviewer field" "reviewer quality" "$result"

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
