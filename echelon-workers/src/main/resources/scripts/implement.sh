#!/bin/bash
# Echelon Implementer Worker — generates code changes via Pi agent
# Clones repo, applies changes, compiles, commits, creates PR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TASK_ID="${1:-}"
ISSUE_URL="${2:-}"
BRANCH_NAME="${3:-feature/ech-${TASK_ID}}"
PROMPT="${4:-}"

if [ -z "$TASK_ID" ] || [ -z "$ISSUE_URL" ]; then
    log_error "Usage: implement.sh <task_id> <issue_url> [branch_name] [prompt]"
    exit 1
fi

# Check that jq is available for JSON processing
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    exit 1
fi

log_info "Starting implementation for task $TASK_ID (issue: $ISSUE_URL)"

# Discover available coding skills
log_info "Discovering available coding skills..."
CODING_SKILLS=$(skill_discover "coding" "implementer" 2>/dev/null || echo "[]")
SKILL_COUNT=$(echo "$CODING_SKILLS" | jq 'length' 2>/dev/null || echo "0")
if [ "$SKILL_COUNT" -gt 0 ]; then
    SELECTED_SKILL=$(echo "$CODING_SKILLS" | jq -r '.[0].name // "none"' 2>/dev/null || echo "none")
    log_info "Found $SKILL_COUNT coding skill(s) — selected: $SELECTED_SKILL"
else
    log_info "No coding skills discovered — proceeding without skill registry"
fi

# Check policy
log_info "Checking policy for implementer role..."
POLICY=$(check_policy "implementer" "implement_task" 2>/dev/null || echo "DENIED")
if [ "$POLICY" = "DENIED" ]; then
    log_error "Policy denied: implementer role cannot implement_task"
    redis_xadd "events:governance" event "implementer:denied" taskId "$TASK_ID" reason "policy"
    exit 1
fi

# Check budget
log_info "Checking budget..."
BUDGET=$(check_budget "$TASK_ID" "implementer" "5000" 2>/dev/null || echo "DENIED")
if [ "$BUDGET" = "DENIED" ]; then
    log_error "Budget denied: insufficient tokens for task $TASK_ID"
    redis_xadd "events:governance" event "implementer:budget_denied" taskId "$TASK_ID"
    exit 1
fi

# Clone and setup branch
WORK_DIR="/tmp/echelon-implement-${TASK_ID}"
safe_clone "thepragmatik/echelon" "$WORK_DIR" "main"
cd "$WORK_DIR"
safe_checkout "$WORK_DIR" "$BRANCH_NAME"

log_info "Working on branch $BRANCH_NAME"

# Determine prompt
if [ -z "$PROMPT" ]; then
    PROMPT=$(gh issue view "${ISSUE_URL##*/}" --json title,body --jq '.title + "\n\n" + .body' 2>/dev/null || echo "Implement the changes described in $ISSUE_URL")
fi

log_info "Prompt: ${PROMPT:0:100}..."

# Run Pi agent to implement changes
if command -v pi &>/dev/null; then
    log_info "Running Pi agent for code generation..."
    PI_OUTPUT=$(pi -p "Work in $WORK_DIR. Implement the following task:\n\n$PROMPT\n\nAfter implementing:\n1. Run mvn compile -q 2>&1\n2. Run all relevant tests\n3. Report what was done" --thinking medium 2>&1 || true)
    echo "$PI_OUTPUT" > "/tmp/echelon-pi-output-${TASK_ID}.log"
    log_info "Pi agent output saved to /tmp/echelon-pi-output-${TASK_ID}.log"
else
    log_warn "Pi CLI not available — creating placeholder commit"
    echo "# Implementation for $TASK_ID" >> "/tmp/echelon-implement-${TASK_ID}.md"
fi

# Check for compilation issues
log_info "Verifying compilation..."
if mvn compile -q 2>/dev/null; then
    log_info "Compilation succeeded"
else
    log_warn "Compilation had issues — committing anyway for review"
fi

# Create PR
log_info "Creating pull request..."
git add -A
git commit -m "feat: implement $TASK_ID" 2>/dev/null || true
git push origin "$BRANCH_NAME" 2>/dev/null || true

PR_URL=""
PR_URL=$(gh pr create --base main --head "$BRANCH_NAME" --title "feat: $TASK_ID — implementation" --body "Closes ${ISSUE_URL##*/}" 2>/dev/null || echo "")

if [ -n "$PR_URL" ]; then
    log_info "PR created: $PR_URL"
    redis_xadd "tasks:review" taskId "$TASK_ID" prUrl "$PR_URL" branch "$BRANCH_NAME"
fi

# Audit trail
log_audit "implementer:completed" "$TASK_ID" "$PR_URL"

echo "{\"taskId\":\"$TASK_ID\",\"branch\":\"$BRANCH_NAME\",\"prUrl\":\"$PR_URL\"}"
exit 0
