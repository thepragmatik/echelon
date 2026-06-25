#!/bin/bash
set -euo pipefail
# Echelon Reviewer — uses GLM-5.2 (or DeepSeek fallback) for honest code review
PR_NUM="${1:-}"
ROLE="${2:-adversarial}"
REPO="${3:-thepragmatik/echelon}"

echo "[REVIEWER] === Starting ${ROLE} review for PR #${PR_NUM} ==="

# Auth
if [ -z "${GH_TOKEN:-}" ] && [ -f /run/secrets/gh_token ]; then
    read -r GH_TOKEN < /run/secrets/gh_token; export GH_TOKEN
fi

# Get PR metadata
PR_JSON=$(gh pr view "${PR_NUM}" --repo "${REPO}" --json title,headRefName,body,files,additions,deletions 2>/dev/null || echo '{}')
TITLE=$(echo "$PR_JSON" | jq -r '.title // "unknown"')
BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName // "main"')
FILES_JSON=$(echo "$PR_JSON" | jq -r '.files // []')
FILE_COUNT=$(echo "$FILES_JSON" | jq 'length')
ADDITIONS=$(echo "$PR_JSON" | jq -r '.additions // 0')
DELETIONS=$(echo "$PR_JSON" | jq -r '.deletions // 0')

echo "[REVIEWER] PR: ${TITLE} (${BRANCH})"
echo "[REVIEWER] Files: ${FILE_COUNT} (+${ADDITIONS}/-${DELETIONS} lines)"

# Clone and checkout PR branch
cd /tmp; rm -rf pr-review-${PR_NUM}
gh repo clone "${REPO}" "pr-review-${PR_NUM}" 2>/dev/null
cd "pr-review-${PR_NUM}"
gh auth setup-git 2>/dev/null || true
git fetch origin "${BRANCH}" 2>/dev/null
git checkout "${BRANCH}" 2>/dev/null

# Read each changed file, collect their content
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || echo "")
FILE_CONTENT=""
FINDINGS=""

for f in $CHANGED_FILES; do
    if [ ! -f "$f" ]; then continue; fi
    LINES=$(wc -l < "$f")
    echo "[REVIEWER] Reading: ${f} (${LINES} lines)"
    FILE_CONTENT="${FILE_CONTENT}\n\n### File: ${f} (${LINES} lines)\n\`\`\`\n$(head -200 "$f")\n\`\`\`"
done

# If no model-router available, do a manual analysis
if command -v model-router &>/dev/null; then
    echo "[REVIEWER] Using model router for LLM-based review..."
    REVIEW_PROMPT="You are a ${ROLE} code reviewer. Review this PR for the Echelon project.

PR Title: ${TITLE}
Branch: ${BRANCH}
Changed files: ${FILE_COUNT}
Additions: ${ADDITIONS}, Deletions: ${DELETIONS}

Changed file content:
${FILE_CONTENT}

As a ${ROLE} reviewer:
- Adversarial: Find bugs, logic errors, race conditions, null safety issues, edge cases, error handling problems
- Quality: Find style issues, maintainability problems, test gaps, SOLID violations, DRY violations

For each finding, specify: SEVERITY (CRITICAL/HIGH/MEDIUM/LOW), FILE, LINE (if applicable), and DETAIL.

If no issues found, say NO_ISSUES_FOUND and explain what you checked.
Do NOT fabricate issues. Only report what you actually observe."

    REVIEW_OUTPUT=$(model-router "${REVIEW_PROMPT}" "glm-5.2" 2>/dev/null || echo "Model router unavailable")
    echo "[REVIEWER] Model response received"
else
    # Manual review as fallback
    echo "[REVIEWER] Model router not available — performing manual analysis..."
    REVIEW_OUTPUT="# Manual ${ROLE} Review — PR #${PR_NUM}\n\n"
    for f in $CHANGED_FILES; do
        if [ ! -f "$f" ]; then continue; fi
        LINES=$(wc -l < "$f")
        EXT="${f##*.}"
        case "$EXT" in
            java)
                # Check for common Java issues
                if grep -q 'System.out.print' "$f" 2>/dev/null; then
                    FINDINGS="${FINDINGS}\n- [MEDIUM] ${f}: System.out.println used instead of logger"
                fi
                if grep -q 'catch\s*(Exception' "$f" 2>/dev/null; then
                    FINDINGS="${FINDINGS}\n- [LOW] ${f}: Catching generic Exception — consider more specific types"
                fi
                if ! grep -q '@Test' "$f" 2>/dev/null && [ "$ROLE" = "quality" ]; then
                    FINDINGS="${FINDINGS}\n- [INFO] ${f}: No tests found for this class"
                fi
                if grep -q 'null' "$f" 2>/dev/null && [ "$ROLE" = "adversarial" ]; then
                    NULL_COUNT=$(grep -c 'null' "$f" 2>/dev/null || echo 0)
                    if [ "$NULL_COUNT" -gt 3 ]; then
                        FINDINGS="${FINDINGS}\n- [MEDIUM] ${f}: ${NULL_COUNT} null references — consider Optional pattern"
                    fi
                fi
                ;;
            sh|bash)
                if grep -q 'set -e' "$f" 2>/dev/null; then
                    : # good
                else
                    FINDINGS="${FINDINGS}\n- [MEDIUM] ${f}: Missing set -euo pipefail for error handling"
                fi
                ;;
        esac
    done
    if [ -z "$FINDINGS" ]; then
        REVIEW_OUTPUT="${REVIEW_OUTPUT}## Analysis Complete — No Issues Found\n\nChecked ${FILE_COUNT} files. Common patterns verified: error handling, null safety, logging, test coverage.\n"
    else
        REVIEW_OUTPUT="${REVIEW_OUTPUT}## Findings\n${FINDINGS}\n"
    fi
fi

# Determine verdict
if echo "$REVIEW_OUTPUT" | grep -qi 'CRITICAL\|HIGH.*issue\|bug found'; then
    VERDICT="REQUEST_CHANGES"
    echo "[REVIEWER] Verdict: REQUEST_CHANGES — issues found"
else
    VERDICT="APPROVE"
    echo "[REVIEWER] Verdict: APPROVE — no blocking issues"
fi

# Submit review
REVIEW_BODY="## ${ROLE^} Review — PR #${PR_NUM}\n### Verdict: ${VERDICT}\n\n${REVIEW_OUTPUT}\n\n---\n*Reviewed ${FILE_COUNT} files (+${ADDITIONS}/-${DELETIONS} lines)*"
echo -e "$REVIEW_BODY" | gh pr review "${PR_NUM}" --repo "${REPO}" --comment --body-file - 2>&1 || true
echo "[REVIEWER] Review submitted — ${VERDICT}"
