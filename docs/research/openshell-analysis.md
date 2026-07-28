# OpenShell Analysis — Agent Skills Architecture

**Author:** Echelon Research (hswarm-rsrch)  
**Date:** July 2026  
**Status:** Complete  
**Scope:** OpenShell's agent skills ecosystem, discovery model, data formats, and architectural patterns relevant to Echelon's Agent Skills Discovery module

---

## 1. Overview

OpenShell (by NVIDIA, Apache 2.0) is a safe, private runtime for autonomous AI agents. It provides sandboxed execution environments protected by declarative YAML policies. OpenShell is built **agent-first** — the project ships with over 20 agent skills for everything from gateway troubleshooting to policy generation, and the project team expects all contributors to use them.

The skills system follows the **open Agent Skills specification** maintained at [agentskills.io](https://agentskills.io), which defines a portable SKILL.md format used across Claude Code, Codex CLI, Cursor, Hermes Agent, and other coding agents.

### Key Facts

| Attribute | Value |
|-----------|-------|
| **Repository** | github.com/NVIDIA/OpenShell |
| **License** | Apache 2.0 |
| **Stars** | ~7.8k |
| **Skills shipped** | 22 (as of July 2026) |
| **Skills location** | `.agents/skills/` |
| **Discovery mechanism** | Filesystem scan at startup |
| **Specification** | agentskills.io (open standard) |
| **Skill format** | SKILL.md with YAML frontmatter + Markdown body |

---

## 2. Skill Data Model — The SKILL.md Format

Every OpenShell skill is a directory containing at minimum a `SKILL.md` file. The format follows the agentskills.io open specification:

### Frontmatter Fields

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | 1-64 chars, lowercase alphanumeric + hyphens, matches dir name |
| `description` | Yes | Max 1024 chars, non-empty |
| `license` | No | License name or reference |
| `compatibility` | No | Max 500 chars, environment requirements |
| `metadata` | No | Arbitrary key-value mapping |
| `allowed-tools` | No | Space-separated pre-approved tools (experimental) |

### Example (from OpenShell's `openshell-cli` skill)

```yaml
---
name: openshell-cli
description: Guide agents through using the OpenShell CLI (openshell) for sandbox
  management, gateway registration, provider configuration...
---
```

### Optional Directories

| Directory | Purpose |
|-----------|---------|
| `scripts/` | Executable code (bash, Python, etc.) |
| `references/` | Documentation, spec files, API references |
| `assets/` | Templates, resources, example files |

### Progressive Disclosure

Agents load skills progressively:
1. **Metadata only (~100 tokens):** `name` and `description` are loaded at startup for all skills — this is the discovery surface.
2. **Full body:** Loaded only when the agent decides a skill is relevant to the current task.

This pattern is crucial for efficiency — an agent may have hundreds of skills but only loads the full instructions of the 2-3 it actually needs.

---

## 3. How OpenShell Discovers Skills

OpenShell's discovery mechanism is **filesystem-based**:

1. **Startup scan:** The agent harness scans `.agents/skills/` for subdirectories containing a `SKILL.md` file.
2. **Frontmatter extraction:** The harness parses only the YAML frontmatter (name, description) — this is the lightweight discovery phase.
3. **Context injection:** When the user asks a question matching a skill's description or the conversation context suggests a skill, the agent loads the full SKILL.md body.
4. **Directory convention:** The skill directory name must match the `name` field in the frontmatter.

### What OpenShell Does NOT Do

- **No centralized registry** — skills are purely filesystem-based. There is no database, no API, no runtime registration.
- **No versioning** — skills are always "latest" from the checked-out branch.
- **No access control** — any agent with filesystem access can load any skill.
- **No category indexing** — categories exist in documentation (CONTRIBUTING.md) but are not encoded in the filesystem or frontmatter.
- **No runtime discovery API** — skills are loaded once at startup, not queried dynamically during execution.

---

## 4. OpenShell's Skill Categories

OpenShell organizes its 22 skills into 8 categories (defined in CONTRIBUTING.md):

| Category | Skills | Purpose |
|----------|--------|---------|
| Getting Started | `openshell-cli`, `debug-openshell-cluster`, `debug-inference` | Onboarding and troubleshooting |
| Contributing | `create-spike`, `create-rfc`, `build-from-issue`, `create-github-issue`, `create-github-pr` | Development workflows |
| Reviewing | `review-github-pr`, `review-security-changes`, `review-security-issue`, `fix-security-issue`, `watch-github-actions`, `launch-openshell-gator`, `test-release-canary` | Code review and CI |
| Triage | `triage-issue` | Issue management |
| Platform | `generate-sandbox-policy`, `helm-dev-environment`, `tui-development` | Platform-specific workflows |
| Documentation | `update-docs` | Docs maintenance |
| Maintenance | `sync-agent-infra` | Infrastructure drift |
| Reference | `sbom` | SBOM generation |

### Workflow Chains

Skills connect into pipelines. OpenShell documents these explicitly:

```
Community inflow:   triage-issue → create-spike → build-from-issue
Internal dev:       create-spike → build-from-issue
Security:           review-security-issue → fix-security-issue
Policy iteration:   openshell-cli → generate-sandbox-policy
```

This pattern — chaining skills into workflows — is a key architectural insight for Echelon.

---

## 5. Comparison to Echelon's Current Design

| Aspect | OpenShell | Echelon (Current) | Echelon (Proposed) |
|--------|-----------|-------------------|-------------------|
| **Skill storage** | Filesystem (`.agents/skills/`) | None | Redis hashes + filesystem |
| **Discovery** | Directory scan at startup | None | Redis-based SkillRegistry API |
| **Categories** | Documentation-only | None | Redis sets `skills:by-category:{cat}` |
| **Security** | None (filesystem access only) | DeonticToken (governance) | DeonticToken permission checks |
| **Versioning** | None (always latest) | None | Semantic versioning in datamodel |
| **Runtime discovery** | No (startup-only) | N/A | Redis queries at runtime |
| **Workflow chaining** | Documented in CONTRIBUTING.md | None | Skill metadata includes `workflow` field |
| **Agent-accessible** | Via context injection | N/A | Shell function `skill_discover()` |
| **Standards compliance** | agentskills.io spec | None | agentskills.io spec + Echelon extensions |

### Key Gaps in OpenShell's Approach

1. **No centralized discovery** — agents must have filesystem access to discover skills. In a distributed swarm, this doesn't scale.
2. **No access control** — any agent can load any skill. Echelon's zero-trust model requires permission checks.
3. **No runtime querying** — skills cannot be discovered mid-task by name, category, or capability.
4. **No version management** — skills are always head-of-branch. No canary or staged rollout.
5. **No structured metadata for automation** — categories exist only in human-readable docs.

---

## 6. Architectural Patterns Worth Adopting

### ✅ 6.1 Progressive Loading

**OpenShell's approach:** Load only metadata (name + description, ~100 tokens) at startup. Load full body on demand.

**Echelon adaptation:** The SkillRegistry API returns only metadata for `listAll()` and `discover(category)` queries. Full skill body is loaded only when `getById()` or `findByName()` is called. This maps naturally to Redis: hashes store metadata; full content is loaded from filesystem or Redis on demand.

### ✅ 6.2 SKILL.md Compatibility

**OpenShell's approach:** Follows the agentskills.io open standard.

**Echelon adaptation:** Echelon skills should be valid agentskills.io SKILL.md files. This ensures portability — a skill written for Echelon works in Claude Code, Codex, Cursor, etc. Echelon extends the frontmatter with additional fields (`category`, `workflow`, `allowedRoles`) under the standard's `metadata` field.

### ✅ 6.3 Workflow Chains

**OpenShell's approach:** Skills document their place in workflow pipelines (e.g., `triage-issue → create-spike → build-from-issue`).

**Echelon adaptation:** Each SkillDefinition includes a `workflow` field listing downstream skills, enabling automated workflow routing by the orchestrator.

### ✅ 6.4 Directory-Based Structure

**OpenShell's approach:** Each skill is a self-contained directory with SKILL.md + optional scripts, references, and assets.

**Echelon adaptation:** Same structure, with an added `skill.json` or YAML file for the extended metadata that Redis indexes.

---

## 7. Patterns to Avoid

### ❌ 7.1 Filesystem-Only Discovery

OpenShell's filesystem scan works for a monorepo with a single developer. In Echelon's multi-agent swarm with distributed workers, filesystem-only discovery does not scale:
- Workers in different containers cannot see each other's skills
- No centralized querying
- No access control

**Echelon alternative:** Redis-backed registry as the source of truth, with filesystem as local cache.

### ❌ 7.2 No Security Model

OpenShell has no permission model for skills — any agent can load any skill. Echelon's zero-trust architecture (ADR-001) requires skill access to be governed by DeonticToken checks.

**Echelon alternative:** Every `register()` and `discover()` call passes through the PolicyEngine, which checks the requesting agent's roles against the skill's `allowedRoles`.

### ❌ 7.3 No Versioning

OpenShell skills are always "latest." For a production swarm, skills need versioning to enable canary rollouts, rollbacks, and audit trails.

**Echelon alternative:** Semantic versioning in the SkillDefinition record, with `latest` as a symlink to the current version.

---

## 8. Recommendations for Echelon

| Priority | Recommendation | Rationale |
|----------|---------------|-----------|
| P0 | Implement Redis-backed SkillRegistry | Enables centralized discovery across distributed workers |
| P0 | Use agentskills.io-compatible SKILL.md format | Ensures portability across agent runtimes |
| P0 | Integrate DeonticToken permission checks | Zero-trust governance for skill access |
| P1 | Support categories via Redis sets | Efficient category-based discovery |
| P1 | Add `skill_discover()` shell function for workers | Enables bash-based agents to query skills |
| P2 | Implement workflow chaining metadata | Enables the orchestrator to route through skill pipelines |
| P2 | Add semantic versioning | Canary rollouts, rollbacks, audit trails |
| P3 | OpenSkill registry federation (future) | Cross-Echelon instance skill sharing |

---

## References

| Ref | Source | URL |
|-----|--------|-----|
| [OS-R1] | NVIDIA/OpenShell README | https://github.com/NVIDIA/OpenShell |
| [OS-R2] | OpenShell AGENTS.md | https://github.com/NVIDIA/OpenShell/blob/main/AGENTS.md |
| [OS-R3] | OpenShell CONTRIBUTING.md | https://github.com/NVIDIA/OpenShell/blob/main/CONTRIBUTING.md |
| [OS-R4] | Agent Skills Specification | https://agentskills.io/specification |
| [OS-R5] | NVIDIA/OpenShell skill example | `.agents/skills/openshell-cli/SKILL.md` |
| [OS-R6] | NVIDIA Verified Agent Skills | https://developer.nvidia.com/blog/nvidia-verified-agent-skills-provide-capability-governance-for-ai-agents/ |
| [E-001] | ADR-001: DeonticToken | docs/architecture/adr-001-deontic-tokens.md |
| [E-002] | ADR-002: Redis Budget/Cost | docs/architecture/adr-002-redis-budget-streams.md |
