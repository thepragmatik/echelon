#!/bin/bash
# Echelon Adversarial Review — security-focused code review
# Examines code changes for security vulnerabilities, not style
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TASK_ID="${1:-}"
PR_URL="${2:-}"
BRANCH="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$PR_URL" ]; then
    log_error "Usage: review-adversarial.sh <task_id> <pr_url> [branch]"
    exit 1
fi

log_info "Starting adversarial review for task $TASK_ID (PR: $PR_URL)"

# Clone the PR branch
WORK_DIR="/tmp/echelon-review-adversarial-${TASK_ID}"
safe_clone "thepragmatik/echelon" "$WORK_DIR" "$BRANCH"

cd "$WORK_DIR"

# Get the diff
DIFF=$(gh pr view "${PR_URL##*/}" --json files --jq '.files[].path' 2>/dev/null || echo "")
log_info "Files to review: $(echo "$DIFF" | wc -l)"

# Adversarial checks
ISSUES=""

# Check for hardcoded secrets
log_info "Checking for hardcoded secrets..."
SECRETS=$(grep -rn 'api_key\|API_KEY\|secret\|SECRET\|password\|PASSWORD\|token=\|ghp_\|sk-' --include="*.java" --include="*.sh" --include="*.yaml" --include="*.yml" --include="*.properties" . 2>/dev/null | grep -v ".git/" | grep -v "test/" | grep -v "/target/" | head -20 || true)
if [ -n "$SECRETS" ]; then
    ISSUES="$ISSUES"$'\n'"- CRITICAL: Hardcoded secrets detected: $SECRETS"
    log_warn "Found potential secrets"
fi

# Check for insecure file permissions
log_info "Checking file permissions..."
PERMS=$(find . -type f -perm /o+w -not -path "./.git/*" 2>/dev/null | head -10 || true)
if [ -n "$PERMS" ]; then
    ISSUES="$ISSUES"$'\n'"- MEDIUM: World-writable files: $PERMS"
fi

# Check for command injection in shell scripts
log_info "Checking for command injection vectors..."
INJECTION=$(grep -rn 'eval\|`[^`]*\$`' --include="*.sh" . 2>/dev/null | grep -v "test/" | grep -v ".git/" | head -10 || true)
if [ -n "$INJECTION" ]; then
    ISSUES="$ISSUES"$'\n'"- HIGH: Potential command injection: $INJECTION"
fi

# Check for unsafe file operations
log_info "Checking for unsafe file operations..."
UNSAFE=$(grep -rn 'rm -rf\|rm -r \|rm -f \|chmod 777\|chmod 666' --include="*.sh" --include="*.java" . 2>/dev/null | grep -v "test/" | grep -v ".git/" | grep -v "/target/" | head -10 || true)
if [ -n "$UNSAFE" ]; then
    ISSUES="$ISSUES"$'\n'"- MEDIUM: Unsafe file operations: $UNSAFE"
fi

# Create GitHub Issues for each finding
if [ -n "$ISSUES" ]; then
    PR_NUMBER="${PR_URL##*/}"
    while IFS= read -r finding; do
        [ -z "$finding" ] && continue
        # Extract severity prefix for the label
        local severity=$(echo "$finding" | grep -oE 'CRITICAL|HIGH|MEDIUM|LOW' | head -1 || echo "bug")
        create_issue \
            "review-adversarial: $(echo "$finding" | sed 's/^[[:space:]]*- //' | cut -c1-80)" \
            "**Source:** Adversarial Review of PR #$PR_NUMBER

**Finding:** $finding

**PR:** $PR_URL

**Action required:** Fix or document rationale. Re-review will verify resolution." \
            "${severity,,}"
    done <<< "$ISSUES"
fi

# Build verdict
if [ -n "$ISSUES" ]; then
    VERDICT="FAIL"
    log_warn "Adversarial review FAILED — $ISSUES"
else
    VERDICT="PASS"
    log_info "Adversarial review PASSED — no security issues found"
fi

# Report
RESULT=$(cat <<EOF
{
  "taskId": "$TASK_ID",
  "reviewer": "adversarial",
  "verdict": "$VERDICT",
  "issues": "$ISSUES",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

log_audit "review:adversarial" "$TASK_ID" "$VERDICT"
echo "$RESULT"
redis_xadd "results:review" verdict "$VERDICT" taskId "$TASK_ID" reviewer "adversarial"

exit 0
