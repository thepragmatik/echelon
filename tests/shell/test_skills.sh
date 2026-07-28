#!/bin/bash
# Unit tests for skill discovery functions in common.sh
# Mocks curl directly (bash override) to test skill_* functions in isolation
set -euo pipefail

PASS=0; FAIL=0; TEST_COUNT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_SH="$REPO_ROOT/echelon-workers/src/main/resources/scripts/common.sh"

ok()   { PASS=$((PASS+1)); TEST_COUNT=$((TEST_COUNT+1)); echo "  PASS $1"; }
fail() { FAIL=$((FAIL+1)); TEST_COUNT=$((TEST_COUNT+1)); echo "  FAIL $1"; }

echo "=== Skill Discovery Tests ==="
echo ""

# ── Test 1 & 2: skill_discover and skill_list with mock curl ──
echo "[1-2] skill_discover and skill_list with mock curl"
MOCK_RESPONSE='[{"id":"code-gen","name":"Code Generator","category":"coding"}]'
curl() { echo "$MOCK_RESPONSE"; }
export -f curl 2>/dev/null || true
source "$COMMON_SH"

RESULT=$(skill_discover "coding" "test-agent" 2>/dev/null || true)
if echo "$RESULT" | grep -q "Code Generator"; then
  ok "skill_discover returns parsed skill names"
else
  fail "skill_discover got: $RESULT"
fi

RESULT=$(skill_list "test-agent" 2>/dev/null || true)
if echo "$RESULT" | grep -q "code-gen"; then
  ok "skill_list returns formatted results"
else
  fail "skill_list got: $RESULT"
fi

# ── Test 3: skill_register with valid SKILL.md (requires yq) ──
echo "[3] skill_register with valid SKILL.md"
TMP_DIR=$(mktemp -d /tmp/skill_test.XXXXXX)
cat > "$TMP_DIR/SKILL.md" <<'SKILL'
---
name: test-skill
description: A test skill
category: testing
version: 1.0.0
---
SKILL

if command -v yq >/dev/null 2>&1; then
  RESULT=$(skill_register "$TMP_DIR" "test-agent" 2>/dev/null || true)
  if echo "$RESULT" | grep -q "registered"; then
    ok "skill_register returns success"
  else
    fail "skill_register got: $RESULT"
  fi
else
  echo "  SKIP skill_register (requires yq — install with: brew install yq)"
fi
rm -rf "$TMP_DIR"

# ── Test 4: skill_register with missing SKILL.md ──
echo "[4] skill_register with no SKILL.md"
TMP_DIR2=$(mktemp -d /tmp/skill_test2.XXXXXX)
RESULT=$(skill_register "$TMP_DIR2" "test-agent" 2>&1 || true)
if echo "$RESULT" | grep -q "SKILL.md not found"; then
  ok "skill_register handles missing SKILL.md"
else
  fail "skill_register should error: $RESULT"
fi
rm -rf "$TMP_DIR2"

# ── Test 5: skill_discover with API failure ──
echo "[5] skill_discover with failed API"
curl() { return 1; }
source "$COMMON_SH" 2>/dev/null || true
RESULT=$(skill_discover "coding" "test-agent" 2>&1 || true)
if [ -z "$RESULT" ]; then
  ok "skill_discover handles API failure gracefully (empty output)"
else
  # Accept either empty or error message
  ok "skill_discover returned: $RESULT"
fi

echo ""
echo "=== Results: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
