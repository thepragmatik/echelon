#!/bin/bash
# Echelon Shared Library — sourced by all worker scripts
# Provides: Redis helpers, auth, logging, git routines, policy checks
set -euo pipefail

# ──────────────────────────────────────────────
# Redis Helpers
# ──────────────────────────────────────────────

REDIS_CLI="${REDIS_CLI:-redis-cli}"
REDIS_HOST="${REDIS_HOST:-redis-primary}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Read messages from a Redis stream (blocking)
redis_xread() {
    local stream="$1" count="${2:-1}" block="${3:-5000}"
    $REDIS_CLI -h "$REDIS_HOST" -p "$REDIS_PORT" XREAD COUNT "$count" BLOCK "$block" STREAMS "$stream" ">"
}

# Add a message to a Redis stream
redis_xadd() {
    local stream="$1"
    shift
    $REDIS_CLI -h "$REDIS_HOST" -p "$REDIS_PORT" XADD "$stream" "*" "$@"
}

# Get stream length
redis_xlen() {
    local stream="$1"
    $REDIS_CLI -h "$REDIS_HOST" -p "$REDIS_PORT" XLEN "$stream"
}

# ──────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────

load_gh_token() {
    if [ -z "${GH_TOKEN:-}" ] && [ -f /run/secrets/gh_token ]; then
        read -r GH_TOKEN </run/secrets/gh_token
        export GH_TOKEN
    fi
    if [ -z "${GH_TOKEN:-}" ]; then
        log_error "GH_TOKEN not set and no /run/secrets/gh_token found"
        return 1
    fi
}

load_api_keys() {
    # API keys are injected by Privacy Router at request time
    # Workers should never hold raw API keys
    if [ -n "${LLM_PROXY_URL:-}" ]; then
        export LLM_PROXY_URL
        log_info "LLM proxy configured: $LLM_PROXY_URL"
    fi
}

# ──────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────

log_info()  { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO]  $*"; }
log_warn()  { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [WARN]  $*" >&2; }
log_error() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $*" >&2; }
log_audit() { redis_xadd "events:governance" event "$1" detail "$2" timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; }

# ──────────────────────────────────────────────
# Git Routines
# ──────────────────────────────────────────────

safe_clone() {
    local repo="$1" dir="$2" branch="${3:-main}"
    if [ -d "$dir" ]; then
        log_info "Directory $dir exists, pulling instead of cloning"
        cd "$dir"
        git fetch origin
        git checkout "$branch"
        git pull origin "$branch"
        cd -
    else
        gh repo clone "$repo" "$dir"
        cd "$dir"
        git checkout "$branch" 2>/dev/null || true
        cd -
    fi
}

safe_checkout() {
    local dir="$1" branch="$2"
    cd "$dir"
    git fetch origin "$branch" 2>/dev/null || true
    git checkout "$branch" 2>/dev/null || git checkout -b "$branch"
    cd -
}

# ──────────────────────────────────────────────
# Policy Engine Client
# ──────────────────────────────────────────────

POLICY_ENGINE_URL="${POLICY_ENGINE_URL:-http://localhost:8080}"

check_policy() {
    local role="$1" action="$2"
    local result
    result=$(curl -sf "$POLICY_ENGINE_URL/api/governance/check?role=$role&action=$action" 2>/dev/null || echo "DENIED")
    echo "$result"
}

# Budget check
check_budget() {
    local task_id="$1" agent_id="$2" tokens="$3"
    local result
    result=$(curl -sf "$POLICY_ENGINE_URL/api/governance/budget?taskId=$task_id&agentId=$agent_id&tokens=$tokens" 2>/dev/null || echo "DENIED")
    echo "$result"
}
