# ADR-004: Agent Skills Discovery via Redis-Backed Registry

**Status:** Proposed  
**Date:** July 2026  
**Deciders:** Echelon Architecture Team  
**References:** ADR-001 (DeonticToken), ADR-002 (Redis Budget/Cost), openshell-analysis.md, design/agent-skills-discovery.md, agentskills.io specification

---

## Context

Echelon orchestrates a distributed swarm of agent workers (implementers, reviewers, architects, orchestrators) that need to discover and load reusable, composable capabilities at runtime. Currently, there is no mechanism for workers to discover what skills are available, what they do, or whether they are authorized to use them.

**Current state:** No skill registry exists. Skills exist only as informal knowledge in agent prompting and Hermes Agent skills files stored in `.hermes/skills/`. There is no:
- Centralized catalog of available skills
- Category-based organization
- Permission model for skill access
- Runtime discovery mechanism for distributed workers
- Version management or canary rollout capability

The research analysis (openshell-analysis.md) examined NVIDIA OpenShell's skill architecture and the agentskills.io open specification. OpenShell uses filesystem-based discovery (`.agents/skills/` directories scanned at startup) with no centralized registry, no access control, and no runtime querying. While this works for a monorepo with a single developer, Echelon's multi-agent, multi-container swarm architecture requires a fundamentally different approach.

**Design problem:** How do we provide a centralized, permission-aware skill discovery mechanism that works across distributed containers, supports category-based and name-based queries, integrates with Echelon's existing DeonticToken governance model, and remains compatible with the industry-standard agentskills.io SKILL.md format?

### Key Requirements

1. **Distributed discovery** — workers in different containers must discover skills without shared filesystem access.
2. **Zero-trust security** — skill access must be governed by DeonticToken permission checks (ADR-001), not just filesystem access.
3. **Category indexing** — workers must be able to discover skills by category (e.g., "reviewing", "implementing").
4. **Name-based lookup** — workers must be able to fetch a specific skill's full definition by name.
5. **Progressive loading** — metadata (name + description) loaded at query time; full body loaded on demand.
6. **Industry compatibility** — skills must be valid agentskills.io SKILL.md files, portable to other agent runtimes.
7. **Existing infrastructure reuse** — Redis is already deployed for budget/cost tracking (ADR-002). The skill registry should leverage it.

---

## Decision

### 1. Redis-Backed Skill Registry

Skills are stored in Redis as hashes, indexed by category via sets, and resolvable by name via string keys. The registry is implemented as a `SkillRegistry` Spring service in the `echelon-governance` module.

#### Redis Keyspace

| Key Pattern | Type | Purpose |
|-------------|------|---------|
| `skills:{id}` | Hash | Full skill definition (name, version, description, category, tags, allowedRoles, workflow, contentPath, status, timestamps) |
| `skills:by-category:{category}` | Set | Category membership — efficient `SMEMBERS` queries |
| `skills:all` | Set | Complete set of all registered skill IDs |
| `skills:name:{name}` | String | Resolves short name to latest active skill ID |

#### SkillDefinition Record

```java
public record SkillDefinition(
    String id,              // "review-github-pr@1.0.0"
    String name,            // "review-github-pr"
    String version,         // "1.0.0"
    String description,     // From SKILL.md frontmatter
    String category,        // "reviewing"
    List<String> tags,      // ["pr", "review", "github"]
    List<String> allowedRoles, // ["reviewer", "architect"]
    List<String> workflow,  // ["fix-security-issue"]
    String compatibility,   // From SKILL.md frontmatter
    String license,         // License reference
    String contentPath,     // Filesystem path to skill directory
    Instant registeredAt,
    Instant updatedAt,
    String status           // "active", "deprecated", "canary"
) {}
```

**Rationale for Redis:**
- Redis is already a dependency in the stack (ADR-002) — no new infrastructure.
- Redis hashes map directly to skill records — single round-trip for full definition.
- Redis sets provide O(1) membership checks and efficient category queries.
- Redis strings provide atomic name→version resolution.
- No schema migration needed — hashes are schemaless.

### 2. Category-Based Discovery

Skills are organized into categories matching Echelon's agent role taxonomy:

- `infrastructure` — Docker, Redis, networking setup
- `implementing` — Build-from-issue, code generation
- `reviewing` — PR review, security review
- `governance` — Policy management, audit
- `operations` — Monitoring, deployment
- `general` — Uncategorized utility skills

Categories are indexed via Redis sorted sets (`skills:by-category:{category}`), enabling efficient `SMEMBERS` queries without a full table scan.

### 3. SKILL.md Compatibility

Skills follow the agentskills.io open specification. Echelon extends the standard `metadata` field with an `echelon` key:

```yaml
---
name: review-github-pr
description: Summarize PR diffs and key design decisions.
metadata:
  echelon:
    version: "1.0.0"
    category: reviewing
    allowedRoles: ["reviewer", "architect"]
    workflow: ["fix-security-issue"]
    tags: ["pr", "review", "github"]
---
```

This ensures:
- **Portability:** The same SKILL.md works in Claude Code, Codex, Cursor, Hermes Agent.
- **Discoverability:** Standalone agents see `name` and `description`; ignore Echelon-specific metadata.
- **Integrity:** Echelon's extended metadata lives under the standard `metadata` key, so no spec violation.

### 4. SkillRegistry Service API

```java
@Service
public class SkillRegistry {
    public void register(SkillDefinition skill, String callerRole);
    public void deregister(String skillId, String callerRole);
    public List<SkillSummary> discover(String category, String callerRole);
    public Optional<SkillDefinition> findByName(String name, String callerRole);
    public List<SkillSummary> listAll(String callerRole);
}
```

Every method performs a DeonticToken permission check via `PolicyEngine.evaluate()` before executing. The permission action names are:

| Method | DeonticAction |
|--------|---------------|
| `register()` | `skills.register` |
| `deregister()` | `skills.deregister` |
| `discover()` | `skills.discover` |
| `findByName()` | `skills.read` |
| `listAll()` | `skills.list` |

### 5. Worker Shell Integration

Bash-based worker scripts source `common.sh`, which provides:

```bash
skill_discover()   # Query skills by category + role filter
skill_get()        # Get full skill definition by name
skill_register()   # Register a skill from a directory containing SKILL.md
```

These functions use `redis-cli` to query the Redis registry directly, bypassing the Java service for low-latency shell integration. This is acceptable because:
- The Redis ACL system enforces read-only access for worker scripts.
- Write operations (register/deregister) call through the Java API, which enforces DeonticToken checks.

### 6. Security Model

Two layers of access control:

1. **Action-level (PolicyEngine):** Determines whether an agent role can call `skills.discover`, `skills.read`, etc.
2. **Record-level (allowedRoles):** Determines which skills are visible to an agent role. A skill with `allowedRoles: ["reviewer"]` is invisible to an `implementer` agent, even if the implementer has `skills.list` permission.

Default-deny: unknown roles have no skill permissions.

### 7. Bootstrap Initialization

A `scripts/skill-registry-init.sh` script registers all built-in skills at orchestrator startup. This script:
1. Iterates `/etc/echelon/skills/*/` directories containing SKILL.md.
2. Parses frontmatter with `yq`.
3. Calls Redis HSET/SADD/SET for each skill.
4. Logs registration count.

---

## Consequences

### Positive

1. **Centralized discovery across containers** — any worker in the swarm can query skills without shared filesystem access, using Redis as a single source of truth.
2. **Zero-trust access control** — every registry API call goes through DeonticToken permission checks. Skill-level role filtering prevents unauthorized skill visibility.
3. **Industry compatibility** — skills are valid agentskills.io SKILL.md files. A skill authored for Echelon works in Claude Code, Codex, Cursor, and Hermes Agent.
4. **Efficient queries** — Redis SMEMBERS for category queries is O(1). Name resolution via Redis GET is O(1). Full skill definition via HGETALL is a single round-trip.
5. **Progressive loading** — `discover()` and `listAll()` return only metadata (name + description). Full body is loaded only for `findByName()`.
6. **Reuses existing Redis** — no new infrastructure dependency. Redis is already deployed for budget/cost tracking (ADR-002).
7. **Shell worker integration** — bash scripts can query skills without Java dependency via `redis-cli`.
8. **Foundation for workflow chaining** — the `workflow` field enables the orchestrator to route skills into pipelines.

### Negative

1. **Redis dependency for skill discovery** — if Redis is down, workers cannot discover skills. The system degrades gracefully: workers fall back to locally cached skill lists (loaded at startup).
2. **Two sources of truth** — skills exist both as files (SKILL.md) and as Redis records. Registration must keep them in sync. The bootstrap script ensures initial synchronization.
3. **Shell function bypasses PolicyEngine** — `skill_discover()` in `common.sh` queries Redis directly without DeonticToken checks. Redis ACLs restrict writes but read queries are unfiltered at the Redis level. Mitigation: the shell function performs client-side role filtering.
4. **Increased Redis keyspace** — expected: ~20-50 skills × ~15 fields each = ~300-750 hash fields. Negligible at current scale.

### Neutral

1. **agentskills.io compliance limits metadata** — Echelon-specific fields go under the `metadata.echelon` key. Standalone agents that don't understand the nested structure simply ignore it.
2. **Versioning is advisory** — the `version` field exists in the data model, but there is no automatic version resolution or dependency management yet. That's Phase 2.
3. **Skill registration is a startup step** — skills must be registered before workers can discover them. This adds one more step to the bootstrap sequence but is automated by `skill-registry-init.sh`.

---

## Compliance

| Requirement | Status | Notes |
|-------------|--------|-------|
| Distributed discovery | ✅ | Redis accessible across containers via hostname |
| Zero-trust security | ✅ | PolicyEngine check on every API method |
| Category indexing | ✅ | Redis sets `skills:by-category:{category}` |
| Name-based lookup | ✅ | Redis string `skills:name:{name}` |
| Progressive loading | ✅ | Metadata-only on list; full body on demand |
| agentskills.io compatibility | ✅ | SKILL.md frontmatter + body |
| Existing Redis reuse | ✅ | Same Redis instance as ADR-002 |
| Shell worker integration | ✅ | `common.sh` functions with redis-cli |
| Audit trail | 🟡 | Events logged to `events:skills` stream (G-02 pending) |
| Version management | 🟡 | Data model supports versions; canary/rollback is Phase 2 |
| Federation | ❌ | Cross-Echelon sharing is Phase 3 |

---

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| **Filesystem-only discovery** (OpenShell model) | Doesn't work across containers in a distributed swarm. Workers in different containers can't see each other's filesystems. |
| **PostgreSQL for skill registry** | Heavier dependency for what is fundamentally a key-value workload. Redis hashes + sets are purpose-built for this pattern. PostgreSQL would require schema migrations and add query latency. |
| **Etcd for skill registry** | Good for distributed discovery but adds an entirely new infrastructure dependency. Redis is already in the stack. |
| **gRPC service for skill registry** | Would require a new service deployment, service discovery, and RPC handling. Redis is already deployed and simpler to query from both Java and shell. |
| **Embedded H2/HSQLDB** | In-process database wouldn't be shared across containers. Defeats the purpose of centralized discovery. |
| **Hermes Agent skill framework only** | Hermes skills are per-agent and filesystem-local. No centralized catalog, no category queries, no access control. |
| **JSON files on shared volume** | No querying, no indexing, no atomic updates. Race conditions on concurrent write. No access control. |

---

## Future Considerations

1. **Canary rollouts** — Phase 2: register a skill version with `status: "canary"` for a subset of agents; promote to `"active"` after verification.
2. **Workflow routing** — Phase 2: the orchestrator uses the `workflow` field to automatically route through skill pipelines (e.g., `triage-issue` → `create-spike` → `build-from-issue`).
3. **Cross-Echelon federation** — Phase 3: share skill registries between Echelon instances via Redis replication or a federation API.
4. **Skill dependency management** — Phase 3: skills may declare dependencies on other skills, enabling automated dependency resolution during registration.
5. **Skill version rollback** — Phase 2: `skills:name:{name}` points to the latest version; rollback is a `SET` operation to the previous version key.
6. **Hot-reload of skill registry** — Phase 2: Redis keyspace notifications trigger cache invalidation in workers without restart.
