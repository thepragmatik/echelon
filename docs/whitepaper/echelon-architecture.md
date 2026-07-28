# Echelon: Zero-Trust Agent Swarm Orchestration — Architecture Whitepaper

**Version:** 1.0  
**Date:** July 2026  
**Status:** Published  
**References:** ADR-001, ADR-002, ADR-004; [P1] arXiv:2601.03624; [P6] arXiv:2606.19464

---

## 1. Design Philosophy

Echelon is built on three architectural pillars:

### Zero-Trust Agent Orchestration

Every inter-container interaction is authenticated, authorized, and audited. No agent is trusted by default — whether it runs in a builder container, a reviewer container, or the orchestrator itself. The zero-trust model is enforced through four layered controls: **container isolation** (separate Dockerfiles with role-specific seccomp profiles), **network default-deny** (the Privacy Router is the sole egress point, holding all LLM API keys), **filesystem allowlisting** (read-only workspace mounts, typed per-container read/write/block policies), and **credential isolation** (agents never hold their own credentials — all API calls go through the Privacy Router proxy).

### Deontic Token Governance

Inspired by Milosevic & Rabhi's ODP-EL pattern #18 (arXiv:2601.03624), Echelon implements a three-token sealed interface — `Permit`, `Embargo`, and `Burden` — that governs every action dispatch in the system. The `PolicyEngine` evaluates each action against these tokens with an **embargo-first, default-deny** priority chain: any actively prohibited action is denied regardless of permissions, any action without an explicit permit is denied, and any permitted action with attached obligations must execute those obligations before completion. The Java 21 sealed interface guarantees compile-time exhaustiveness — the compiler rejects any switch that fails to handle all three token types. Every dispatch is **policy-driven**, meaning no agent can perform an action without a matching policy explicitly granting it permission.

### Defense-in-Depth

Security is layered, not monolithic. The container runtime enforces seccomp profiles (default for builders, strict for reviewers), the orchestrator enforces deontic policy, the Privacy Router enforces credential isolation, and Redis Streams provide an immutable audit trail. A compromise at any single layer is contained by the remaining layers.

---

## 2. Key Architectural Decisions

### ADR-001: Sealed DeonticToken Interface

| Decision | Rationale |
|----------|-----------|
| Sealed Java 21 interface with three record implementations | Compile-time exhaustiveness — new modalities cannot be added without updating every evaluation point |
| `PolicyEngine` with embargo-first priority chain | Embargoes are fail-closed by nature; a prohibited action must be denied regardless of any conflicting permit |
| YAML policy files as the policy source | Policy-as-code — changes are version-controlled, reviewed via PR, and deployed through CI/CD |
| Default-deny semantics | Any action not explicitly permitted is denied; eliminates the unbounded-authority vulnerability class |

### ADR-002: Redis-Backed Budget and Cost Tracking

| Decision | Rationale |
|----------|-----------|
| Redis Strings with TTL for budget caps | Persistent across container restarts; shared across multiple orchestrator instances; abandoned task budgets expire automatically |
| Redis Streams for cost entries | Append-only semantics match audit trail requirements (CSA Rule 2); consumer groups enable separate consumers for alerting, dashboards, and long-term storage |
| 90-day retention policy | Balances storage cost against audit requirements; tunable per deployment |
| Fail-closed on Redis unavailability | Without budget enforcement, costs are unbounded; without policy evaluation, agents have unbounded authority |

### ADR-004: Redis-Backed SkillRegistry

| Decision | Rationale |
|----------|-----------|
| Redis hashes + sets for skill storage | Existing Redis dependency (ADR-002); O(1) category queries via SMEMBERS |
| agentskills.io compatible SKILL.md format | Skills are portable to Claude Code, Codex CLI, Cursor, and Hermes Agent |
| DeonticToken-guarded API | Every `register()`, `discover()`, and `findByName()` call is authorized by `PolicyEngine.evaluate()` |
| Progressive loading (metadata-only on discovery, full body on read) | Minimizes per-query Redis transfer; matches OpenShell pattern |

---

## 3. Agent Pipeline

The Echelon agent pipeline follows a deterministic, checkpointed workflow:

```
GitHub Issue
    │
    ▼
BuildManager ──► PolicyEngine.evaluate(role="implementer", action="write_source")
    │                   │
    │                   └── BudgetManager.deduct(taskId, tokens)
    │                   └── CostTracker.record(entry)
    │
    ▼
implement.sh (Pi-agent driven)
    │  - Checkpoint commit on each file write
    │
    ▼
Git PR (draft → ready)
    │
    ▼
ReviewManager
    │
    ├── Adversarial Review (review-security.sh)
    │     - Seccomp-strict container
    │     - Security-focused prompt, deontic evaluation
    │
    ├── Quality Review (review-quality.sh)
    │     - CodeQL scan, Spotless checkstyle, SpotBugs
    │     - Architecture coherence check
    │
    ▼
PolicyEngine Verdict
    │
    ├── APPROVE → ReviewManager merges PR via GitHub API
    │
    └── DENY → Creates a fix issue and re-enters the pipeline
```

Each stage produces a **checkpoint commit** so no work is lost on container restart. The `common.sh` shell library provides `skill_discover()` for bash-based workers to query available skills at runtime.

---

## 4. Clean Room Build

Echelon's clean room build ensures reproducible, auditable artifact generation. The canonical build command is:

```bash
docker compose -f echelon-docker/docker-compose.yml --profile managers build
```

This builds four container images from source — `builder`, `reviewer`, `privacy-router`, and `redis-sentinel` — without relying on any pre-built artifacts. The `--profile managers` flag activates only the manager-tier services, keeping the build focused on the orchestration layer. Each build is self-contained: Maven dependencies are cached locally but verified on every build; the Dockerfiles pin base images by digest.

---

## 5. Performance Benchmarks

Echelon includes JMH (Java Microbenchmark Harness) benchmarks in `echelon-governance/src/jmh/` that measure throughput and latency for critical governance paths:

- **PolicyEngineBenchmark**: Measures `PolicyEngine.evaluate()` throughput (operations/second) for deontic token evaluation. Tests the full embargo-first priority chain against a realistic policy set loaded from `agent-types.yaml`.
- **BudgetManagerBenchmark**: Measures `BudgetManager.deduct()` throughput for Redis-backed budget enforcement. Uses mocked Redis to isolate the benchmark from network latency.

Benchmarks are run as part of the CI pipeline and results are tracked for regression detection. The evaluation path is designed to complete in under 1ms (local Redis) or 3–5ms (network Redis), ensuring governance overhead remains negligible compared to LLM inference latency (~1–30s per call).

---

## 6. Infrastructure Topology

```
┌──────────────────────────────────────────────────────────┐
│                    Docker Host                            │
│                                                           │
│  ┌──────────┐   ┌──────────┐   ┌───────────────────┐    │
│  │  Builder  │   │ Reviewer │   │  Privacy Router   │    │
│  │ (seccomp  │   │ (seccomp │   │ (credential proxy │    │
│  │  default) │   │  strict) │   │  + model router)  │    │
│  └─────┬─────┘   └─────┬─────┘   └────────┬──────────┘   │
│        │               │                   │              │
│        └───────┬───────┘                   │              │
│                │                           │              │
│        ┌───────┴────────┐       ┌──────────┴──────────┐  │
│        │  Redis Streams  │       │  LLM API Providers  │  │
│        │  (cost, budget, │       │  (DeepSeek, Wafer)  │  │
│        │   governance)   │       └─────────────────────┘  │
│        └───────┬────────┘                                 │
│                │                                           │
│        ┌───────┴────────┐                                 │
│        │   Echelon       │                                 │
│        │   Orchestrator  │                                 │
│        │ (BuildManager,  │                                 │
│        │  ReviewManager, │                                 │
│        │  PolicyEngine)  │                                 │
│        └────────────────┘                                 │
└──────────────────────────────────────────────────────────┘
```

The orchestrator runs as a Java 21 Spring Boot application, polling Redis Streams for task events. Managers (Build, Review) are Spring `@Service` components within the same JVM, communicating via in-process method calls. Worker scripts run as Docker containers with role-specific security profiles. All external LLM calls are proxied through the Privacy Router, which is the only container with network egress access.

---

## References

| ID | Reference |
|----|-----------|
| ADR-001 | [DeonticToken Sealed Interface](https://thepragmatik.github.io/echelon/architecture/adr-001-deontic-tokens/) |
| ADR-002 | [Redis Budget/Cost Tracking](https://thepragmatik.github.io/echelon/architecture/adr-002-redis-budget-streams/) |
| ADR-004 | [Agent Skills Discovery](https://thepragmatik.github.io/echelon/architecture/adr-004-agent-skills-discovery/) |
| [P1] | Milosevic & Rabhi, *Architecting Agentic Communities using Design Patterns*, arXiv:2601.03624 |
| [P6] | *Deontic Policies for Runtime Governance of Agentic AI Systems*, arXiv:2606.19464 |
| [P4] | Schroeder de Witt et al., *Open Challenges in Multi-Agent Security*, arXiv:2505.02077 |
| [R4] | NiteAgent, *AI Agent Cost Optimization in 2026* |
