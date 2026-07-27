#!/bin/bash
# Echelon Quality Review — code quality checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TASK_ID="${1:-}"
PR_URL="${2:-}"
BRANCH="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$PR_URL" ]; then
    log_error "Usage: review-quality.sh <task_id> <pr_url> [branch]"
    exit 1
fi

log_info "Starting quality review for task $TASK_ID"

WORK_DIR="/tmp/echelon-review-quality-${TASK_ID}"
safe_clone "thepragmatik/echelon" "$WORK_DIR" "$BRANCH"
cd "$WORK_DIR"

ISSUES=""

# Check test coverage
log_info "Checking test coverage..."
TEST_FILES=$(find . -name "*Test.java" -not -path "./.git/*" 2>/dev/null | wc -l)
SOURCE_FILES=$(find . -name "*.java" -not -path "./test/*" -not -path "./.git/*" -not -path "*/target/*" 2>/dev/null | wc -l)
if [ "$SOURCE_FILES" -gt 0 ] && [ "$TEST_FILES" -eq 0 ]; then
    ISSUES="$ISSUES"$'\n'"- MEDIUM: No test files found for $SOURCE_FILES source files"
fi

# Check for TODOs
log_info "Checking for TODO/FIXME..."
TODOS=$(grep -rn 'TODO\|FIXME\|XXX' --include="*.java" --include="*.sh" . 2>/dev/null | grep -v ".git/" | grep -v "/target/" | head -10 || true)
if [ -n "$TODOS" ]; then
    ISSUES="$ISSUES"$'\n'"- LOW: Unresolved TODOs: $TODOS"
fi

# Check file size
log_info "Checking for oversized files..."
OVERSIZE=$(find . -name "*.java" -size +500k -not -path "./.git/*" -not -path "*/target/*" 2>/dev/null | head -5 || true)
if [ -n "$OVERSIZE" ]; then
    ISSUES="$ISSUES"$'\n'"- LOW: Oversized files (>500KB): $OVERSIZE"
fi

VERDICT="PASS"
[ -n "$ISSUES" ] && VERDICT="PASS_WITH_SUGGESTIONS"

RESULT=$(cat <<EOF
{
  "taskId": "$TASK_ID",
  "reviewer": "quality",
  "verdict": "$VERDICT",
  "issues": "$ISSUES",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

log_audit "review:quality" "$TASK_ID" "$VERDICT"
echo "$RESULT"
redis_xadd "results:review" verdict "$VERDICT" taskId "$TASK_ID" reviewer "quality"
exit 0
