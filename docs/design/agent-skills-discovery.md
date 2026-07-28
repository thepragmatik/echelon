# Agent Skills Discovery — Design Document

**Author:** Echelon Architecture Team (hswarm-rsrch)  
**Date:** July 2026  
**Status:** Draft  
**Issue:** #134  
**References:** ADR-004, docs/research/openshell-analysis.md

---

## 1. Overview

The Agent Skills Discovery module provides a centralized, Redis-backed registry for agent skills in the Echelon swarm. It enables distributed workers to discover, register, and query skills at runtime, governed by DeonticToken-based permission checks.

### Design Goals

1. **Centralized discovery** — any worker in the swarm can query available skills without filesystem access.
2. **Zero-trust security** — skill access requires PolicyEngine authorization via DeonticToken checks.
3. **Industry compatibility** — skills are valid [agentskills.io](https://agentskills.io) SKILL.md files, portable to Claude Code, Codex, etc.
4. **Category-based organization** — skills can be discovered by category (e.g., "implementer", "reviewer", "security").
5. **Runtime querying** — workers can discover skills mid-task by name, category, or capability.
6. **Worker shell integration** — bash-based workers can discover skills via a `common.sh` shell function.

### Non-Goals

- Skill execution (orchestration is handled by the orchestrator, not the registry)
- Skill authoring/editing (skills are authored as files, then registered)
- Cross-Echelon federation (Phase 2+)

---

## 2. Data Model

### 2.1 SkillDefinition Record

```yaml
SkillDefinition:
  id: string              # Unique skill ID (e.g., "review-github-pr@1.0.0")
  name: string            # Skill name (lowercase, hyphenated, matches SKILL.md)
  version: string         # Semantic version (e.g., "1.0.0")
  description: string     # Brief description (max 1024 chars, from SKILL.md frontmatter)
  category: string        # Primary category (e.g., "reviewing", "implementing")
  tags: string[]          # Additional searchable tags
  allowedRoles: string[]  # DeonticToken roles permitted to use this skill
  workflow: string[]      # Downstream skills in this workflow chain
  compatibility: string   # Environment requirements (from SKILL.md frontmatter)
  license: string         # License reference (from SKILL.md frontmatter)
  metadata: map           # Arbitrary key-value pairs (from SKILL.md frontmatter)
  contentPath: string     # Path to the skill directory (filesystem reference)
  registeredAt: timestamp # When the skill was registered
  updatedAt: timestamp    # When the skill was last updated
  status: string          # "active", "deprecated", "canary"
```

### 2.2 agentskills.io Compatibility

The `name` and `description` fields map directly to the agentskills.io SKILL.md frontmatter. Echelon extends the standard with additional fields stored under the standard's `metadata` field:

```yaml
---
name: review-github-pr
description: Summarize PR diffs and key design decisions using structured review templates.
metadata:
  echelon:
    version: "1.0.0"
    category: reviewing
    allowedRoles: ["reviewer", "architect"]
    workflow: ["fix-security-issue"]
    tags: ["pr", "review", "github"]
---
```

This ensures that an Echelon skill file loaded by Claude Code or Codex CLI ignores the Echelon-specific metadata (since it's under the standard `metadata` key) while still being fully functional.

---

## 3. Redis Storage Schema

### 3.1 Skill Hashes

Each skill is stored as a Redis hash:

```
Key: skills:{id}
Fields:
  name           -> string   # Skill name
  version        -> string   # Semantic version
  description    -> string   # Brief description
  category       -> string   # Primary category
  tags           -> string   # JSON array
  allowedRoles   -> string   # JSON array
  workflow       -> string   # JSON array
  compatibility  -> string   # Environment requirements
  license        -> string   # License reference
  metadata       -> string   # JSON object
  contentPath    -> string   # Filesystem path to skill directory
  registeredAt   -> string   # ISO 8601 timestamp
  updatedAt      -> string   # ISO 8601 timestamp
  status         -> string   # "active", "deprecated", "canary"
```

**Example:**

```redis
HSET skills:review-github-pr@1.0.0 \
  name "review-github-pr" \
  version "1.0.0" \
  description "Summarize PR diffs and key design decisions" \
  category "reviewing" \
  tags '["pr","review","github"]' \
  allowedRoles '["reviewer","architect"]' \
  workflow '["fix-security-issue"]' \
  compatibility "gh CLI required" \
  license "Apache-2.0" \
  metadata '{"author":"echelon-core"}' \
  contentPath "/etc/echelon/skills/review-github-pr" \
  registeredAt "2026-07-28T12:00:00Z" \
  updatedAt "2026-07-28T12:00:00Z" \
  status "active"
```

### 3.2 Category Index Sets

Skills are indexed by category for efficient lookup:

```
Key: skills:by-category:{category}
Members: skills:{id} (e.g., "skills:review-github-pr@1.0.0")
```

**Example:**

```redis
SADD skills:by-category:reviewing skills:review-github-pr@1.0.0
SADD skills:by-category:reviewing skills:review-security-changes@1.0.0
SADD skills:by-category:implementing skills:build-from-issue@1.0.0
```

### 3.3 All-Skills Index

A complete set of all skill IDs is maintained for `listAll()` queries:

```
Key: skills:all
Members: skills:{id}
```

### 3.4 Name-to-ID Mapping

A lookup by short name (without version) to find the latest active version:

```
Key: skills:name:{name}
Value: skills:{id}  (the latest active skill ID)
```

**Example:**

```redis
SET skills:name:review-github-pr skills:review-github-pr@2.0.0
SET skills:name:build-from-issue skills:build-from-issue@1.2.0
```

### 3.5 TTL Strategy

| Key Pattern | TTL | Rationale |
|------------|-----|-----------|
| `skills:{id}` | No TTL | Persistent — skills persist until explicitly deregistered |
| `skills:by-category:*` | No TTL | Persistent index |
| `skills:all` | No TTL | Persistent index |
| `skills:name:*` | No TTL | Persistent index |

Skills are never auto-expired. Deregistration is explicit via `deregister()`.

---

## 4. SkillRegistry Service API

### 4.1 Java Service Interface

```java
package io.echelon.skills;

@Service
public class SkillRegistry {

    private final RedisTemplate<String, String> redis;
    private final PolicyEngine policyEngine;
    private final YamlPolicyLoader policyLoader;

    /**
     * Register a new skill. Requires SKILL.md to exist at contentPath.
     * Validates the SKILL.md frontmatter before storing.
     *
     * @param skill    the SkillDefinition to register
     * @param callerRole the role of the registering agent
     * @throws SecurityException if callerRole lacks "skills.register" permission
     * @throws ValidationException if SKILL.md is invalid
     */
    public void register(SkillDefinition skill, String callerRole) {
        // 1. DeonticToken permission check
        PolicyResult result = policyEngine.evaluate(callerRole, "skills.register");
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            throw new SecurityException("Caller lacks skills.register permission");
        }

        // 2. Validate SKILL.md file
        validateSkillFile(skill.contentPath());

        // 3. Store hash
        String key = "skills:" + skill.id();
        redis.opsForHash().putAll(key, skill.toMap());

        // 4. Index by category
        redis.opsForSet().add("skills:by-category:" + skill.category(), key);

        // 5. Add to all-skills index
        redis.opsForSet().add("skills:all", key);

        // 6. Update name-to-version mapping
        redis.opsForValue().set("skills:name:" + skill.name(), key);

        // 7. Log the registration event
        audit.log("skills.register", Map.of("skill", skill.id(), "role", callerRole));
    }

    /**
     * Discover skills by category.
     *
     * @param category the category to query
     * @param callerRole the role of the requesting agent
     * @return list of SkillDefinition summaries (name + description + version)
     */
    public List<SkillSummary> discover(String category, String callerRole) {
        // 1. Permission check
        PolicyResult result = policyEngine.evaluate(callerRole, "skills.discover");
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            throw new SecurityException("Caller lacks skills.discover permission");
        }

        // 2. Get skills in category
        Set<String> keys = redis.opsForSet().members("skills:by-category:" + category);

        // 3. Fetch metadata for each (progressive loading — name + description only)
        List<SkillSummary> summaries = new ArrayList<>();
        for (String key : keys) {
            String name = (String) redis.opsForHash().get(key, "name");
            String description = (String) redis.opsForHash().get(key, "description");
            String version = (String) redis.opsForHash().get(key, "version");
            // Filter by allowedRoles
            String rolesJson = (String) redis.opsForHash().get(key, "allowedRoles");
            Set<String> allowedRoles = parseJsonSet(rolesJson);
            if (allowedRoles.contains(callerRole) || allowedRoles.isEmpty()) {
                summaries.add(new SkillSummary(key, name, description, version));
            }
        }
        return summaries;
    }

    /**
     * Find a skill by its short name. Returns the latest active version.
     *
     * @param name the short skill name (e.g., "review-github-pr")
     * @param callerRole the role of the requesting agent
     * @return the full SkillDefinition, or empty if not found or not authorized
     */
    public Optional<SkillDefinition> findByName(String name, String callerRole) {
        // 1. Permission check
        PolicyResult result = policyEngine.evaluate(callerRole, "skills.read");
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            return Optional.empty();
        }

        // 2. Look up latest version
        String key = redis.opsForValue().get("skills:name:" + name);
        if (key == null) return Optional.empty();

        // 3. Get full definition
        Map<Object, Object> fields = redis.opsForHash().entries(key);

        // 4. Permission filter
        String rolesJson = (String) fields.get("allowedRoles");
        Set<String> allowedRoles = parseJsonSet(rolesJson);
        if (!allowedRoles.isEmpty() && !allowedRoles.contains(callerRole)) {
            return Optional.empty(); // Role not authorized
        }

        return Optional.of(SkillDefinition.fromMap(fields));
    }

    /**
     * List all registered skills (metadata only — progressive loading).
     */
    public List<SkillSummary> listAll(String callerRole) {
        PolicyResult result = policyEngine.evaluate(callerRole, "skills.list");
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            throw new SecurityException("Caller lacks skills.list permission");
        }
        // ... iterate skills:all set, filter by allowedRoles, return summaries
    }

    /**
     * Deregister a skill by ID.
     */
    public void deregister(String skillId, String callerRole) {
        PolicyResult result = policyEngine.evaluate(callerRole, "skills.deregister");
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            throw new SecurityException("Caller lacks skills.deregister permission");
        }
        // ... remove hash, remove from category set, remove from all-skills, remove name mapping
    }
}
```

### 4.2 Skill Registration Flow

```
                         ┌──────────────────┐
                         │  SKILL.md file   │
                         │  (filesystem)    │
                         └────────┬─────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │  register() called with  │
                    │  skill path + callerRole │
                    └────────┬────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │ PolicyEngine    │
                    │ .evaluate(role, │
                    │  "skills.register")│
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  GRANTED?       │
                    └────────┬────────┘
                    ┌────────┴────────┐
                    │      YES        │
                    └────────┬────────┘
                             ▼
                    ┌──────────────────┐
                    │ Validate SKILL.md│
                    │ frontmatter      │
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────┐
                    │ Store Redis hash │
                    │ skills:{id}      │
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────────┐
                    │ Index in category set │
                    │ skills:by-category:{} │
                    └────────┬──────────────┘
                             ▼
                    ┌──────────────────────┐
                    │ Add to skills:all    │
                    │ Update name mapping  │
                    └────────┬──────────────┘
                             ▼
                    ┌──────────────────┐
                    │  Log to audit    │
                    │  stream          │
                    └──────────────────┘
```

### 4.3 Skill Discovery Flow

```
Worker wants skills for "reviewing"
              │
              ▼
     ┌─────────────────┐
     │ discover("reviewing",│
     │   "reviewer")    │
     └────────┬─────────┘
              │
              ▼
     ┌─────────────────┐
     │ PolicyEngine    │
     │ .evaluate(      │
     │  "skills.discover")│
     └────────┬─────────┘
              │ GRANTED
              ▼
     ┌───────────────────────────────┐
     │ SMEMBERS skills:by-category: │
     │   reviewing                   │
     └────────┬──────────────────────┘
              │
              ▼
     ┌───────────────────────────────┐
     │ HGET each key for name,      │
     │ description, version,        │
     │ allowedRoles                 │
     └────────┬──────────────────────┘
              │
              ▼
     ┌───────────────────────────────┐
     │ Filter by allowedRoles match │
     │ Return SkillSummary[]        │
     └───────────────────────────────┘
```

---

## 5. Worker Integration — Shell Function

Bash-based workers (e.g., `implement.sh`, `review-manager.sh`) discover skills via a `common.sh` shell function. This requires the `redis-cli` tool to be available.

### 5.1 `skill_discover()` in common.sh

```bash
# common.sh — shared worker library
# Must be sourced by all worker scripts.
# Requires: redis-cli, jq

SKILL_REGISTRY_EVALUATOR="redis-cli"  # or configured Redis endpoint

# Discover skills by category, filtered by agent role.
# Usage: skill_discover <category> <agent_role>
# Returns: JSON array of {name, description, version}
skill_discover() {
    local category="$1"
    local agent_role="$2"
    local redis_cmd="${REDIS_CLI:-redis-cli}"

    # Check if redis is reachable
    $redis_cmd PING > /dev/null 2>&1 || {
        echo "[]"
        return 1
    }

    # Get skill keys in this category
    local keys
    keys=$($redis_cmd SMEMBERS "skills:by-category:${category}") || {
        echo "[]"
        return 1
    }

    # Build JSON output — fetch metadata for each skill
    local first=true
    echo "["
    for key in $keys; do
        local name description version roles_json
        name=$($redis_cmd HGET "$key" "name")
        description=$($redis_cmd HGET "$key" "description")
        version=$($redis_cmd HGET "$key" "version")
        roles_json=$($redis_cmd HGET "$key" "allowedRoles")

        # Check role authorization
        if [ -n "$roles_json" ] && [ "$roles_json" != "[]" ]; then
            if ! echo "$roles_json" | jq -e "contains([\"$agent_role\"])" > /dev/null 2>&1; then
                continue  # Skip — role not authorized
            fi
        fi

        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        jq -n --arg n "$name" --arg d "$description" --arg v "$version" \
            '{name: $n, description: $d, version: $v}'
    done
    echo "]"
}

# Get a full skill definition by name.
# Usage: skill_get <skill_name> <agent_role>
# Returns: JSON object with all fields, or null if not authorized
skill_get() {
    local name="$1"
    local agent_role="$2"
    local redis_cmd="${REDIS_CLI:-redis-cli}"

    # Resolve name to latest key
    local key
    key=$($redis_cmd GET "skills:name:${name}") || {
        echo "null"
        return 1
    }

    [ -z "$key" ] && { echo "null"; return 1; }

    # Check role authorization
    local roles_json
    roles_json=$($redis_cmd HGET "$key" "allowedRoles")
    if [ -n "$roles_json" ] && [ "$roles_json" != "[]" ]; then
        if ! echo "$roles_json" | jq -e "contains([\"$agent_role\"])" > /dev/null 2>&1; then
            echo "null"
            return 1
        fi
    fi

    # Fetch all fields and output as JSON
    $redis_cmd HGETALL "$key" | \
        jq -nR 'reduce inputs as $line ({}; . + {($line): (input | tostring)})'
}

# Register a skill from a directory containing SKILL.md.
# Usage: skill_register <directory> <caller_role>
skill_register() {
    local dir="$1"
    local caller_role="$2"
    local skill_file="${dir}/SKILL.md"

    [ -f "$skill_file" ] || { echo "SKILL.md not found in $dir"; return 1; }

    # Parse SKILL.md frontmatter (requires yq or similar)
    local name description category tags roles version
    if command -v yq > /dev/null 2>&1; then
        name=$(yq eval '.name' "$skill_file")
        description=$(yq eval '.description' "$skill_file")
        category=$(yq eval '.metadata.echelon.category // "uncategorized"' "$skill_file")
        tags=$(yq eval '.metadata.echelon.tags // [] | @json' "$skill_file")
        roles=$(yq eval '.metadata.echelon.allowedRoles // [] | @json' "$skill_file")
        version=$(yq eval '.metadata.echelon.version // "0.1.0"' "$skill_file")
    else
        echo "yq required for SKILL.md parsing"
        return 1
    fi

    local skill_id="${name}@${version}"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Store in Redis
    $redis_cmd HSET "skills:${skill_id}" \
        name "$name" \
        version "$version" \
        description "$description" \
        category "$category" \
        tags "$tags" \
        allowedRoles "$roles" \
        workflow "[]" \
        compatibility "" \
        license "Apache-2.0" \
        metadata "{}" \
        contentPath "$dir" \
        registeredAt "$now" \
        updatedAt "$now" \
        status "active"

    # Index
    $redis_cmd SADD "skills:by-category:${category}" "skills:${skill_id}"
    $redis_cmd SADD "skills:all" "skills:${skill_id}"
    $redis_cmd SET "skills:name:${name}" "skills:${skill_id}"

    echo "Registered: ${skill_id}"
}
```

### 5.2 Worker Usage Example

```bash
# In a review-manager.sh worker:
source /etc/echelon/common.sh

# Discover all reviewing skills available to the "reviewer" role
skills=$(skill_discover "reviewing" "reviewer")

# Get a specific skill definition
skill_data=$(skill_get "review-github-pr" "reviewer")

# Register a new skill (orchestrator-only)
skill_register "/etc/echelon/skills/custom-skill" "orchestrator"
```

---

## 6. Security — DeonticToken Permission Checks

Every SkillRegistry API call goes through the PolicyEngine with DeonticToken authorization:

| Action | Permission Token | Required Role | Effect |
|--------|-----------------|---------------|--------|
| `register()` | `skills.register` | `orchestrator`, `admin` | Register new skill |
| `deregister()` | `skills.deregister` | `orchestrator`, `admin` | Remove skill |
| `discover()` | `skills.discover` | Any authenticated role | List skills by category |
| `findByName()` | `skills.read` | Any authenticated role | Get skill details |
| `listAll()` | `skills.list` | Any authenticated role | List all skills |

### Policy YAML (added to `agent-types.yaml`)

```yaml
roles:
  orchestrator:
    permits:
      - skills.register
      - skills.deregister
      - skills.discover
      - skills.read
      - skills.list
  admin:
    permits:
      - skills.register
      - skills.deregister
      - skills.discover
      - skills.read
      - skills.list
  implementer:
    permits:
      - skills.discover
      - skills.read
      - skills.list
  reviewer:
    permits:
      - skills.discover
      - skills.read
      - skills.list
  architect:
    permits:
      - skills.discover
      - skills.read
      - skills.list
```

### Skill-Level Access Control

In addition to action-level permissions, individual skills define `allowedRoles` in their metadata. A skill with `allowedRoles: ["reviewer", "architect"]` will not appear in `discover()` results for an `implementer` agent, even though that agent has `skills.discover` permission.

---

## 7. Initialization and Bootstrap

Skills are registered at system startup via a bootstrap script:

```bash
# scripts/skill-registry-init.sh
# Called during echelon-orchestrator startup

REDIS_CMD="${REDIS_CLI:-redis-cli}"

# Ensure Redis is available
$REDIS_CMD PING || { echo "Redis not available"; exit 1; }

# Register built-in skills from the skills directory
for skill_dir in /etc/echelon/skills/*/; do
    [ -f "${skill_dir}SKILL.md" ] || continue
    # Source common.sh for skill_register function
    source /etc/echelon/common.sh
    skill_register "$skill_dir" "orchestrator"
done

echo "Skill registry initialized: $(skill_list_all "orchestrator" | jq length) skills registered"
```

---

## 8. Observability

### Audit Events (Stream: `events:skills`)

| Event | Fields | Producer |
|-------|--------|----------|
| `skill.registered` | `skillId`, `name`, `version`, `category`, `callerRole` | SkillRegistry |
| `skill.deregistered` | `skillId`, `name`, `version`, `callerRole` | SkillRegistry |
| `skill.discovered` | `category`, `callerRole`, `resultCount` | SkillRegistry |

### Metrics

- `skills.registered.count` — Counter: total skills registered
- `skills.discovery.latency` — Histogram: time to query skills by category
- `skills.auth.denied.count` — Counter: permission check failures

---

## 9. Redis Keyspace Summary

| Key Pattern | Type | Purpose | TTL |
|-------------|------|---------|-----|
| `skills:{id}` | Hash | Full skill definition | None |
| `skills:by-category:{category}` | Set | Category index | None |
| `skills:all` | Set | All skill IDs | None |
| `skills:name:{name}` | String | Name → latest version mapping | None |
| `events:skills` | Stream | Skill lifecycle audit trail | 90 days |

---

## 10. Implementation Plan

| Phase | Deliverable | Dependencies |
|-------|-------------|--------------|
| **Phase 1** | `SkillRegistry` Java service (register, discover, findByName, listAll) | ADR-001 (PolicyEngine), ADR-002 (Redis config) |
| **Phase 1** | Redis schema initialization (keyspace creation) | Redis running |
| **Phase 1** | `skill_discover()` shell function in `common.sh` | redis-cli on workers |
| **Phase 1** | Bootstrap registration of built-in skills | Phase 1 SkillRegistry |
| **Phase 2** | Workflow chaining (orchestrator routes by `workflow` field) | Phase 1 SkillRegistry |
| **Phase 2** | Semantic versioning (canary/rollback support) | Phase 1 SkillRegistry |
| **Phase 3** | Cross-Echelon federation (sharing skills between instances) | Phase 2 |

---

## References

| Ref | Source |
|-----|--------|
| [D-001] | OpenShell Analysis — docs/research/openshell-analysis.md |
| [D-002] | ADR-001: DeonticToken — docs/architecture/adr-001-deontic-tokens.md |
| [D-003] | ADR-002: Redis Budget/Cost — docs/architecture/adr-002-redis-budget-streams.md |
| [D-004] | ADR-004: Agent Skills Discovery — docs/architecture/adr-004-agent-skills-discovery.md |
| [D-005] | agentskills.io Specification — https://agentskills.io/specification |
