#!/bin/bash
set -euo pipefail
# Echelon Implementer Worker — ephemeral task executor
ISSUE_URL="${1:-}"
TASK_ID="${2:-$(date +%s)}"
REPO="${3:-thepragmatik/echelon}"
WORK_DIR="/tmp/echelon-work-${TASK_ID}"
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$' || echo "0")
echo "[WORKER] Echelon Worker v0.1 — Task ${TASK_ID} — Issue #${ISSUE_NUM}"
if [ -z "${GH_TOKEN:-}" ] && [ -f /run/secrets/gh_token ]; then read -r GH_TOKEN </run/secrets/gh_token; export GH_TOKEN; fi
gh repo clone "${REPO}" "${WORK_DIR}" 2>/dev/null; cd "${WORK_DIR}"
ISSUE_TITLE=$(gh issue view "${ISSUE_NUM}" --repo "${REPO}" --json title -q '.title' 2>/dev/null || echo "task-${TASK_ID}")
BS=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40)
BRANCH="worker/ECH-${ISSUE_NUM}-${BS}"; git checkout -b "${BRANCH}"
echo "[WORKER] Branch: ${BRANCH}"
if [ -f pom.xml ]; then mvn compile -q 2>&1 && echo "[WORKER] COMPILE OK" || echo "[WORKER] COMPILE ISSUE"; fi
git add -A; git commit -m "feat: implement issue #${ISSUE_NUM}" 2>/dev/null || true
git push origin "${BRANCH}" 2>&1 || true
gh pr create --repo "${REPO}" --base main --head "${BRANCH}" \
  --title "feat: ${ISSUE_TITLE}" --body "Implements #${ISSUE_NUM}" 2>&1 || true
echo "[WORKER] Done — Task ${TASK_ID}"
