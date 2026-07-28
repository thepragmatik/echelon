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

# ──────────────────────────────────────────────
# Skill Registry Client
# ──────────────────────────────────────────────

SKILL_REGISTRY_URL="${SKILL_REGISTRY_URL:-http://localhost:8080}"

# Discover skills by category, filtered by agent role.
# Usage: skill_discover <category> <caller_role>
# Returns: JSON array of {name, description, version}
skill_discover() {
    local category="$1"
    local caller_role="$2"
    local result
    result=$(curl -sf "${SKILL_REGISTRY_URL}/api/skills/discover?category=${category}&role=${caller_role}" 2>/dev/null || echo "[]")
    echo "$result"
}

# List all registered skills (summary metadata).
# Usage: skill_list <caller_role>
# Returns: JSON array of {name, description, version}
skill_list() {
    local caller_role="$1"
    local result
    result=$(curl -sf "${SKILL_REGISTRY_URL}/api/skills?role=${caller_role}" 2>/dev/null || echo "[]")
    echo "$result"
}

# Register a skill from a directory containing SKILL.md.
# Reads SKILL.md frontmatter and POSTs the parsed definition to the registry API.
# Requires: yq for YAML parsing, jq for JSON construction.
# Usage: skill_register <directory> <caller_role>
# Returns: JSON response from the registry API
skill_register() {
    local dir="$1"
    local caller_role="$2"
    local skill_file="${dir}/SKILL.md"

    [ -f "$skill_file" ] || {
        log_error "SKILL.md not found in $dir"
        return 1
    }

    # Parse SKILL.md frontmatter (requires yq)
    local name description category tags roles version
    if command -v yq >/dev/null 2>&1; then
        name=$(yq eval '.name' "$skill_file")
        description=$(yq eval '.description' "$skill_file")
        category=$(yq eval '.metadata.echelon.category // "uncategorized"' "$skill_file")
        tags=$(yq eval '.metadata.echelon.tags // [] | @json' "$skill_file")
        roles=$(yq eval '.metadata.echelon.allowedRoles // [] | @json' "$skill_file")
        version=$(yq eval '.metadata.echelon.version // "0.1.0"' "$skill_file")
    else
        log_error "yq required for SKILL.md parsing"
        return 1
    fi

    local skill_id="${name}@${version}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON payload using jq
    local payload
    payload=$(jq -n \
        --arg id "$skill_id" \
        --arg name "$name" \
        --arg version "$version" \
        --arg description "$description" \
        --arg category "$category" \
        --arg tags "$tags" \
        --arg roles "$roles" \
        --arg registeredAt "$now" \
        '{
            id: $id,
            name: $name,
            version: $version,
            description: $description,
            category: $category,
            tags: ($tags | fromjson),
            allowedRoles: ($roles | fromjson),
            registeredAt: $registeredAt,
            status: "active"
        }')

    local result
    result=$(curl -sf -X POST "${SKILL_REGISTRY_URL}/api/skills" \
        -H "Content-Type: application/json" \
        -H "X-Caller-Role: ${caller_role}" \
        -d "$payload" 2>/dev/null || echo "FAILED")

    if [ "$result" = "FAILED" ]; then
        log_error "Failed to register skill $skill_id"
        return 1
    fi

    log_info "Registered skill: ${skill_id}"
    echo "$result"
}
