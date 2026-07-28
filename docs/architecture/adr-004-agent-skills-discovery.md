# ADR-004: Agent Skills Discovery — Redis-Backed Registry

**Status:** Proposed  
**Date:** July 2026  
**Deciders:** Echelon Architecture Team  
**References:** [D-001] docs/design/agent-skills-discovery.md; [OS-R4] agentskills.io Specification; [E-001] ADR-001: DeonticToken; [E-002] ADR-002: Redis Budget/Cost; gap-analysis.md §§4.5, 6.1

---

## Context

Echelon orchestrates multiple agent roles (implementer, reviewer, architect, orchestrator) that perform actions using agent skills — reusable, composable instructions that guide agent behavior. Currently, Echelon has no skill registry, no discovery mechanism, and no way for workers to query available skills at runtime.

**Current state:** There is no skill abstraction in the codebase. Agent capabilities are hard-coded in worker scripts (`implement.sh`, `review-manager.sh`). Adding a new capability requires modifying worker scripts directly.

OpenShell (research completed in docs/research/openshell-analysis.md) demonstrates a working agent skills ecosystem using SKILL.md files in `.agents/skills/` with filesystem-based discovery. However, OpenShell's approach has critical gaps for Echelon's distributed zero-trust architecture:

1. **No centralized discovery** — filesystem-only scan doesn't work across distributed containers.
2. **No access control** — any agent with filesystem access can load any skill.
3. **No runtime querying** — skills cannot be discovered mid-task by name or category.
4. **No versioning** — skills are always head-of-branch, no canary rollouts.
5. **No structured metadata** — categories exist only in human-readable docs.

The research recommends (P0 priorities) a Redis-backed SkillRegistry with DeonticToken-integrated permission checks, using the agentskills.io SKILL.md format for portability.

**Design problem:** How do we provide centralized, secure, runtime-queryable skill discovery for distributed swarm workers while maintaining compatibility with the open agentskills.io standard?

---

## Decision

### 1. Redis-Backed `SkillRegistry` Service

Introduce a Spring `@Service` in the `io.echelon.skills` package backed by Redis hashes and sets:

```java
@Service
public class SkillRegistry {
    private final RedisTemplate<String, String> redis;
    private final PolicyEngine policyEngine;

    public void register(SkillDefinition skill, String callerRole) { /* ... */ }
    public List<SkillSummary> discover(String category, String callerRole) { /* ... */ }
    public Optional<SkillDefinition> findByName(String name, String callerRole) { /* ... */ }
    public List<SkillSummary> listAll(String callerRole) { /* ... */ }
    public void deregister(String skillId, String callerRole) { /* ... */ }
}
```

**Key design decisions:**

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Storage** | Redis hashes + sets | Existing Redis dependency (ADR-002); hashes for structured skill data, sets for category indexing |
| **Discovery** | SMEMBERS on `skills:by-category:{cat}` | O(1) set membership; no full-table scans |
| **Progressive loading** | Metadata-only on `discover()`/`listAll()`; full body on `findByName()` | Minimizes per-query Redis transfer; matches OpenShell pattern |
| **Version resolution** | `skills:name:{name}` → latest active version | Simple string overwrite on registration; no version negotiation needed in Phase 1 |

### 2. Redis Keyspace Schema

```redis
# Hash — full skill definition
Key: skills:{id}                     # e.g., skills:review-github-pr@1.0.0
Fields: name, version, description, category, tags, allowedRoles,
        workflow, compatibility, license, metadata, contentPath,
        registeredAt, updatedAt, status

# Set — category index
Key: skills:by-category:{category}   # e.g., skills:by-category:reviewing
Members: skills:{id}                 # e.g., skills:review-github-pr@1.0.0

# Set — all skills
Key: skills:all
Members: skills:{id}

# String — name→latest version mapping
Key: skills:name:{name}              # e.g., skills:name:review-github-pr
Value: skills:{id}                   # e.g., skills:review-github-pr@2.0.0
```

All keys are persistent (no TTL). Deregistration is explicit via `deregister()`.

### 3. agentskills.io Compatibility

Echelon skills are valid agentskills.io SKILL.md files. Echelon-specific metadata (version, category, allowedRoles, workflow, tags) is stored under the standard `metadata.echelon` key:

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

This ensures portability — the same SKILL.md file works in Claude Code, Codex CLI, Cursor, and Hermes Agent.

### 4. DeonticToken Permission Model

Every SkillRegistry API call is guarded by a PolicyEngine evaluation using DeonticToken (ADR-001):

| Action | Permission Token | Required Role |
|--------|-----------------|---------------|
| `register()` | `skills.register` | orchestrator, admin |
| `deregister()` | `skills.deregister` | orchestrator, admin |
| `discover()` | `skills.discover` | Any authenticated role |
| `findByName()` | `skills.read` | Any authenticated role |
| `listAll()` | `skills.list` | Any authenticated role |

In addition to action-level permissions, individual skills define `allowedRoles` in their metadata for fine-grained access control. A skill with `allowedRoles: ["reviewer", "architect"]` will not appear in `discover()` results for an `implementer` agent.

### 5. Worker Integration via Shell Function

Bash-based workers discover skills via a `common.sh` shell function `skill_discover()`:

```bash
# common.sh — sourced by all worker scripts
skill_discover() {
    local category="$1"
    local agent_role="$2"
    # Calls redis-cli SMEMBERS + HGET with role filtering
    # Returns: JSON array of {name, description, version}
}
```

This enables bash-based workers (implement.sh, review-manager.sh, review-security.sh) to query skills without Java dependency.

### 6. Registry Initialization

Skills are registered at startup via a bootstrap script:

```bash
# scripts/skill-registry-init.sh
# Walks /etc/echelon/skills/*/SKILL.md and calls skill_register()
```

---

## Consequences

### Positive

1. **Centralized discovery across distributed workers** — any container can query available skills without filesystem access to the skill repository.
2. **Zero-trust security model** — every skill access is authorized by PolicyEngine DeonticToken checks (per ADR-001).
3. **Industry-standard skill format** — agentskills.io compatibility ensures skills are portable to other agent runtimes.
4. **Category-based organization** — Redis sets provide efficient O(1) category queries.
5. **Runtime querying** — workers can discover skills mid-task by name, category, or capability.
6. **Worker shell integration** — `skill_discover()` enables bash-based workers to participate in skill discovery.
7. **Progressive loading** — metadata-only queries keep Redis transfer costs low; full skill bodies are loaded on demand.

### Negative

1. **Redis dependency** — if Redis is unavailable, skill discovery fails. The system must fail-closed (deny all task dispatch) when Redis is unreachable.
2. **Increased startup latency** — `skill-registry-init.sh` must run before any worker can discover skills. At ~50ms per skill registration, all 22 skills register in ~1 second.
3. **No hot-reload for skills** — Phase 1 requires a restart or explicit `deregister()`/`register()` to update a skill. Dynamic reload is Phase 2+.
4. **Shell performance** — `skill_discover()` makes N+1 Redis calls (1 SMEMBERS + N HGETs). For large category sets (>50 skills), caching is needed.

### Neutral

1. **Existing Redis dependency** — ADR-002 already requires Redis for budget/cost tracking. No new infrastructure dependency.
2. **Skill authoring is out of scope** — this ADR covers discovery only. Skill authoring, validation, and testing are separate concerns.
3. **Schema versioning expected** — initial schema supports Phase 1 requirements. Workflow chaining and federation will add keys.

---

## Compliance

- **agentskills.io specification:** ✅ — SKILL.md format is fully compatible; Echelon extensions are under the standard `metadata` key.
- **CSA Rule 3 (Permission boundaries):** ✅ — default-deny with explicit `allowedRoles` per skill.
- **CSA Rule 2 (Immutable audit trails):** 🟡 — `events:skills` stream logs all registration, deregistration, and discovery events.
- **EU AI Act Art. 12 (Record-keeping):** 🟡 — skill lifecycle events are tracked, but audit stream wiring (G-02) must be completed.
- **Reference: gap-analysis.md §§4.5, 6.1 (G-01):** ✅ — addresses the "no skill abstraction" gap identified in the architecture review.

---

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| **Filesystem-only** (OpenShell model) | Doesn't work across distributed containers; no access control; no runtime querying; no versioning |
| **API Gateway service** (dedicated REST service for skills) | Over-engineered for Phase 1; adds another service to deploy; Redis-backed SkillRegistry in the orchestrator is sufficient |
| **PostgreSQL for skill metadata** | Heavier dependency for key-value/metadata workload; Redis hashes are purpose-built; PostgreSQL would require schema migrations for flexible metadata fields |
| **Flat JSON file served by HTTP** | No indexing; no query support; requires loading entire file for every discovery call; no access control |
| **gRPC-based skill registry** | Adds protobuf compilation and gRPC server dependency; Redis is already in the stack for ADR-002 |
| **Etcd/Consul for service-style registration** | Same functionality as Redis sets with more operational complexity; Redis is already present |
| **No skill abstraction** (current state) | Hard-coded capabilities in worker scripts don't scale; every new skill requires modifying multiple worker scripts |
