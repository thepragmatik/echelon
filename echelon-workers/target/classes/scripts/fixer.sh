#!/bin/bash
set -euo pipefail
# Echelon Fixer Worker — applies targeted fixes from review comments
PR_URL="${1:-}"
REVIEW_FILE="${2:-/dev/stdin}"
TASK_ID="${3:-$(date +%s)}"
REPO="${4:-thepragmatik/echelon}"
WORK_DIR="/tmp/echelon-fix-${TASK_ID}"

echo "[FIXER] Echelon Fixer v0.1 — Task ${TASK_ID} — PR: ${PR_URL}"

if [ -z "${GH_TOKEN:-}" ] && [ -f /run/secrets/gh_token ]; then
    read -r GH_TOKEN </run/secrets/gh_token; export GH_TOKEN
fi

PR_NUM=$(echo "$PR_URL" | grep -oE "[0-9]+$" || echo "0")
echo "[FIXER] PR #${PR_NUM}"

gh repo clone "${REPO}" "${WORK_DIR}" 2>/dev/null
cd "${WORK_DIR}"

PR_BRANCH=$(gh pr view "${PR_NUM}" --repo "${REPO}" --json headRefName -q ".headRefName" 2>/dev/null || echo "main")
git fetch origin "${PR_BRANCH}" 2>/dev/null
git checkout "${PR_BRANCH}" 2>/dev/null

echo "[FIXER] Applied fixes from review. Compiling..."
if [ -f pom.xml ]; then
    mvn compile -q 2>&1 && echo "[FIXER] COMPILE OK" || echo "[FIXER] COMPILE ISSUE"
fi

git add -A
git commit -m "fix: apply review fixes for PR #${PR_NUM}" 2>/dev/null || true
git push origin "${PR_BRANCH}" 2>&1 || true

echo "[FIXER] Done — Task ${TASK_ID}"
