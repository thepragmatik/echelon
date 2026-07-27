# Echelon Feature Roadmap — Comprehensive Audit

**Author:** Hermes Research Agent  
**Date:** July 2026  
**Status:** Draft — critical review follows  
**Sources:** Existing docs (4 files), ADRs (2), gap-analysis.md (1), CHANGELOG, GitHub Issues (8 open, ~40 closed), industry best-practice research, codebase inspection (18 unit tests, 1 integration test suite, 5 modules)

---

## 1. Executive Summary

Echelon has successfully delivered its governance core (DeonticToken, PolicyEngine, Redis-backed budget/cost tracking) in v0.2.0-alpha, but the gap between this Java governance library and a deployable agent-swarm platform remains substantial. The existing gap-analysis.md is a pre-Phase-1 baseline written for an empty repo — it correctly identifies the components needed but dramatically understates how much of that gap remains after PR #63. Eight P5 (Production Hardening) issues are open, none of which address the critical missing infrastructure (Docker containers, Privacy Router, managers, CI/CD). **The immediate priority must be containerizing the governance code into runnable services** — integrating governance into containers that actually orchestrate agents, not just compile-time verification.

---

## 2. Current State Assessment (v0.2.0-alpha, delivered in PR #63)

### 2.1 What Exists (Delivered)

| Component | Status | Lines/Files | Notes |
|-----------|--------|-------------|-------|
| `DeonticToken` sealed interface | ✅ Done | ~50 lines | Permit/Embargo/Burden records, compile-time exhaustiveness |
| `PolicyEngine` | ✅ Done | ~100 lines | Embargo-first, default-deny priority chain |
| `YamlPolicyLoader` | ✅ Done | ~80 lines | Parses agent-types.yaml at startup |
| `PolicyResult` / `TokenAction` / `EvaluationResult` | ✅ Done | Supporting records | Records for engine I/O |
| `BudgetManager` (Redis-backed) | ✅ Done | ~120 lines | Per-task 50k + agent-monthly 500k caps, TTL-based |
| `CostTracker` (Redis stream-backed) | ✅ Done | ~100 lines | CostAttribution records to `events:cost` stream |
| `CostAttribution` record | ✅ Done | ~20 lines | Tags: taskId, agent, model, tokens, cost, project |
| `BuildManager` wired to `PolicyEngine` | ✅ Done | ~200 lines | `permit()` no longer returns unconditional `true` |
| Fixer worker script | ✅ Done | ~50 lines | `scripts/fixer.sh` |
| Agent types policy YAML | ✅ Done | ~80 lines | 4 roles with permits/embargoes/burdens |
| ADR-001, ADR-002 | ✅ Done | 2 docs | Architecture decision records |
| Deontic governance synthesis | ✅ Done | 150 lines | Cross-referenced literature review |
| Class diagram (Excalidraw) | ✅ Done | JSON file | Full governance class hierarchy |
| Unit tests | ✅ Done | 18 tests | DeonticTokenTest (7), PolicyEngineTest (4), YamlPolicyLoaderTest (5), EchelonApplicationTests (2) |
| `GovernanceIntegrationTest` | 🟡 Partial | 12 tests | `@Disabled` — requires Docker, excluded from CI |
| CI | ✅ Done | GitHub Actions | Green on JDK 21 |

### 2.2 What Is Missing (Critical Gaps)

| Category | What's Missing | Impact |
|----------|---------------|--------|
| **Containers** | No `Dockerfile.*`, no `docker-compose.yml`, no `docker/` directory | Governance code exists only in unit tests — cannot deploy |
| **Managers** | No `build-manager.sh`, `review-manager.sh`, `common.sh` | No durable manager processes to subscribe to streams |
| **Workers** | No `implement.sh`, `review-*.sh` (except fixer.sh) | No actual agent execution capability |
| **Privacy Router** | No proxy, no credential injection, no credential stripping | Agents must hold their own API keys (security risk) |
| **CI/CD Pipeline** | No Docker build/push workflow | No image registry, no deployment automation |
| **Monitoring** | No Prometheus metrics, no health checks (beyond basic `/health`) | No observability into production behavior |
| **Security Hardening** | No seccomp profiles, no filesystem allowlisting, no network default-deny | Defence-in-depth is entirely absent |
| **Backup/DR** | No Redis RDB/AOF, no volume snapshots | All state lost on container restart |
| **EU AI Act Compliance** | No human-in-the-loop gate, record-keeping incomplete, transparency untested | Regulatory risk |

---

## 3. Feature Inventory — Prioritized by Phase

### 3.1 Phase A: Containerization & Deployability (MVP) — 0:30-0:45 effort

The governance code must run in containers before any other feature is valuable. This is the real "Phase 2" despite not being labelled as such in the issue tracker.

| # | Feature | Est. Effort | Dependencies | Risk | Notes |
|---|---------|-------------|--------------|------|-------|
| A1 | `Dockerfile.echelon` for governance module | 0:30 | Completed governance code | Low | Single JAR with Spring Boot + embedded governance. Use `mvn package -DskipTests` for now. |
| A2 | `docker-compose.yml` w/ Redis + orchestrator | 1:00 | A1 | Low | Start simple: one orchestrator, one Redis. Governance integration tests already prove the Redis pattern. |
| A3 | `scripts/redis-init.sh` — stream/group creation | 0:15 | A2 | Low | Straightforward: `XGROUP CREATE` for `events:cost`, `events:budget`, `events:governance` |
| A4 | Build `Dockerfile.builder` (JDK 21 + Maven + agents) | 1:00 | A1, A2 | Medium | Base image + GLM-5.2 config. Must decide which agent runtime to embed (HERMES? Pi? Custom?). |
| A5 | `build-manager.sh` — stream subscriber + worker spawn | 2:00 | A4, governance code | High | Core orchestration logic. State machine for task lifecycle. Must wire PolicyEngine at dispatch. |
| A6 | `implement.sh` — clone → code → compile → commit → PR | 3:00 | A5 | High | Most complex worker. Checkpoint commit pattern, branch locking, timeout enforcement. |
| A7 | Fix `GovernanceIntegrationTest` for CI | 1:00 | A2 | Medium | Currently `@Disabled`. Needs Testcontainers + Docker-in-Docker or Testcontainers Cloud for GitHub Actions. Use `testcontainers-junit-jupiter` with reusable containers. |
| | **Phase A subtotal** | **~8:45** | | | |

### 3.2 Phase B: Review Pipeline & Privacy Router — 0:30-0:50

| # | Feature | Est. Effort | Dependencies | Risk | Notes |
|---|---------|-------------|--------------|------|-------|
| B1 | `Dockerfile.reviewer` (JDK + DeepSeek + review tools) | 1:00 | A2 | Medium | Lighter image than builder. Needs only review tools, not build toolchain. |
| B2 | `review-manager.sh` — subscribe, spawn parallel reviewers, collect verdicts | 2:00 | B1, governance code | High | Verdict collection + timeout logic. 2-3 parallel reviewers. |
| B3 | `review-adversarial.sh` — adversarial code review | 1:30 | B2 | Medium | Structured verdict output. Focus on finding bugs, not style. |
| B4 | `review-quality.sh` — code quality review | 1:00 | B2 | Medium | SOP-driven checklists. Lower thinking=low acceptable. |
| B5 | Privacy Router — credential proxy + model routing | 3:00 | A2 | High | **Highest-leverage security + cost component.** Proxy (haproxy/nginx/squid) for all LLM calls. Strips agent credentials, injects backend creds, logs every request, routes by role (GLM-5.2 primary, DeepSeek fallback). |
| B6 | Cost attribution wiring (Privacy Router → Redis) | 1:00 | B5 | Medium | Every LLM call tagged with taskId, agent, model, tokens, cost. Feeds `CostTracker` stream. |
| B7 | Token budget enforcement gate | 0:30 | B6, BudgetManager | Medium | Block dispatch if per-agent monthly budget exceeded. |
| B8 | Semantic caching (Redis embedding-based) | 2:00 | A2, B5 | High | 60-88% savings [R5]. Embedding generation + similarity search. Requires embedding model or external API. |
| B9 | Prompt caching configuration | 0:30 | A2 | Low | Provider-native prompt caching. Configure system prompt caching headers. |
| | **Phase B subtotal** | **~12:30** | | | |

### 3.3 Phase C: CI/CD & Production Readiness — 0:30-0:60

| # | Feature | Est. Effort | Dependencies | Risk | Notes |
|---|---------|-------------|--------------|------|-------|
| C1 | GitHub Actions: build + test workflow | 1:00 | A1 | Low | Already exists basic — needs Docker-based integration test support |
| C2 | GitHub Actions: GHCR image build + push on merge | 1:00 | A4, B1, C1 | Low | Multi-arch build for linux/amd64. Tag with git SHA + semver. |
| C3 | Health checks across all containers | 0:30 | A2, B5 | Low | Spring Boot Actuator `/health` + Docker HEALTHCHECK |
| C4 | Prometheus metrics via Micrometer | 1:00 | A2 | Medium | Add `micrometer-registry-prometheus` to POMs. Expose `/actuator/prometheus`. Custom metrics: permit decisions, budget remaining, cost attribution rate, task lifecycle duration. |
| C5 | Redis backup/DR (AOF + volume snapshots) | 1:00 | A2 | Low | Multi-line config: `appendonly yes`, `save 900 1`. Document restore procedure. |
| C6 | Seccomp profiles (Docker default for builders, strict for reviewers) | 0:30 | A4, B1 | Low | No custom profile needed for builders — Docker default proven with JVM. Strict profile for reviewers blocks socket/connect/clone (no-build justification). |
| C7 | Filesystem allowlisting (read-only root, explicit mounts) | 0:15 | A4, B1 | Low | `:ro` on workspace mount, `:rw` only on scratch. Document in docker-compose. |
| C8 | Network default-deny | 0:15 | B5 | Low | `--network none` for reviewers. Custom bridge for builders. Privacy Router as sole egress. |
| C9 | Branch protection + dual-review requirement | 0:15 | C1 | Low | GitHub branch protection: require CI + 2 reviewers. Document PR template. |
| C10 | Spotless / palantir-java-format JDK 25 fix | 0:30 | — | Low | Pin palantir-java-format version or upgrade to JDK 25-compatible formatter. |
| | **Phase C subtotal** | **~6:15** | | | |

### 3.4 Phase D: EU AI Act Compliance — 0:00-0:30 parallel

| # | Feature | Est. Effort | Dependencies | Risk | Notes |
|---|---------|-------------|--------------|------|-------|
| D1 | Human-in-the-loop release gate (Art. 14) | 1:00 | B2 | Medium | Block production deploy without human approval. Signal via GitHub or dedicated API. |
| D2 | Record-keeping completeness (Art. 12) | 1:00 | B5, A2 | Medium | All governance events flow to Redis streams. Verify: deontic checks, budget decisions, task dispatch, LLM calls. |
| D3 | Transparency obligations documentation (Art. 13) | 1:00 | — | Low | Document what the system does, how decisions are made, which agents have which permissions. |
| D4 | Risk tiering for agent roles | 0:30 | governance code | Low | Map existing roles to EU AI Act risk tiers (limited → high). Document rationale for each. |
| | **Phase D subtotal** | **~3:30** | | | |

### 3.5 Phase E: Observability & Hardening — 0:30-0:90

| # | Feature | Est. Effort | Dependencies | Risk | Notes |
|---|---------|-------------|--------------|------|-------|
| E1 | Load testing harness (Issue #51) | 2:00 | A5, B2 | High | Concurrent agent simulation. Measure throughput, latency, cost under load. |
| E2 | Staging environment (Issue #53) | 1:00 | C2 | Medium | docker-compose override with scaled-down config. Pre-prod validation. |
| E3 | Monitoring dashboard (Grafana) | 2:00 | C4 | Medium | Cost trends, token usage per role, permit denial rate, task success rate, container health. |
| E4 | Seccomp/network hardening validation (Issue #50) | 1:00 | C6, C8 | Medium | Automated checks: verify seccomp profile is loaded, verify network default-deny, verify no unexpected binds. |
| E5 | Alerting rules | 1:00 | C4 | Medium | Alert on: budget near-limit, permit denial spike, task failure rate >10%, Redis latency >50ms. |
| E6 | Release Manager automation | 2:00 | C2 | Medium | Automated version bump, CHANGELOG generation, tag creation, release notes. |
| E7 | Agent-side budget awareness | 1:00 | B7 | Medium | Surface remaining tokens in task context so agent can self-regulate (e.g., "use cheap model, you only have 2000 tokens left"). |
| | **Phase E subtotal** | **~10:00** | | | |

---

## 4. Open Issues Analysis (8 Open Issues on GitHub)

All 8 open issues are labelled **P5 (Production Hardening)** and were opened Jun 25, 2026. None have any assignees or comments beyond the issue body.

| # | Title | Phase in This Audit | Est. Effort | Priority | Notes |
|---|-------|--------------------|-------------|----------|-------|
| #53 | P5-009: Staging environment — docker-compose override | E2 | 1:00 | Medium | Blocked on C2 (GHCR pipeline). Pre-prod validation. |
| #52 | P5-008: Backup and DR — Redis AOF + volume snapshots | C5 | 1:00 | Medium | Low effort, high value for data safety. Can do independently. |
| #51 | P5-007: Load testing harness — concurrent agent simulation | E1 | 2:00 | Low | Blocked on A5 (build-manager) and B2 (review-manager). Cannot load-test what doesn't exist. |
| #50 | P5-006: Seccomp and network hardening validation | E4 | 1:00 | Low | Blocked on C6/C8. Validation of hardening that itself blocks on Phase A. |
| #49 | P5-005: Monitoring stack — Prometheus metrics + alerts | C4 + E3 | 3:00 | Medium | C4 (Micrometer) can be done independently. Alerts block on defining meaningful thresholds. |
| #48 | P5-004: Docker image registry pipeline — GHCR auto-build | C2 | 1:00 | High | **Should be moved to Phase A.** Without image registry, no containers can be deployed. |
| #47 | P5-003: Privacy Router validation — verify LLM routing | B5 + B6 | 1:00 | High | **Should be moved to Phase B.** Validation of the most critical security component. |
| #46 | P5-002: Integration test suite — full e2e with Testcontainers | A7 | 1:00 | High | **Should be moved to Phase A.** Currently `@Disabled` and excluded from CI. |

### 4.1 Re-labelling Recommendation

The P5 label is misleading — these aren't "production hardening" tasks for a near-finished system. They range from foundational infrastructure (GHCR pipeline, integration testing) through critical security (Privacy Router) to aspirational (load testing). Recommend splitting into new labels:

- **P2-Infra** — #48 (GHCR), #46 (integration tests), #52 (backup/DR)
- **P2-Security** — #47 (Privacy Router validation)
- **P3-Monitoring** — #49 (monitoring stack)
- **P4-Staging** — #53 (staging environment)
- **P4-QA** — #50 (hardening validation), #51 (load testing)

---

## 5. Dependency Graph (Updated for v0.2.0-alpha Reality)

```
Phase A ─────────────────────────────────────────────────────────►
  A1 (Dockerfile.echelon)
    └─► A2 (docker-compose.yml)
          ├─► A3 (redis-init.sh)
          ├─► A4 (Dockerfile.builder) ──► A5 (build-manager.sh) ──► A6 (implement.sh)
          └─► A7 (fix integration tests)

Phase B ─────────────────────────────────────────────────────────►
  A2 ──► B1 (Dockerfile.reviewer) ──► B2 (review-manager.sh)
                                       ├─► B3 (review-adversarial.sh)
                                       └─► B4 (review-quality.sh)
  A2 ──► B5 (Privacy Router) ──► B6 (cost attribution)
                                  └─► B7 (budget gate)
  A2 ──► B8 (semantic caching)
  A2 ──► B9 (prompt caching)

Phase C ─────────────────────────────────────────────────────────►
  A2 ──► C1 (CI build+test)
  A4+B1 ──► C2 (GHCR pipeline)
  A2 ──► C3 (health checks)
  A2 ──► C4 (Prometheus metrics)
  A2 ──► C5 (backup/DR)
  A4+B1 ──► C6 (seccomp profiles)
  A4+B1 ──► C7 (filesystem allowlisting)
  B5 ──► C8 (network default-deny)
  C1 ──► C9 (branch protection)
  — ──► C10 (Spotless fix)

Phase D (parallel, low infra dependency) ─────────────────────────
  B2 ──► D1 (HITL gate)
  B5 ──► D2 (record-keeping)
  — ──► D3 (transparency docs)
  governance code ──► D4 (risk tiering)

Phase E ─────────────────────────────────────────────────────────►
  A5+B2 ──► E1 (load testing)
  C2 ──► E2 (staging env)
  C4 ──► E3 (Grafana dashboard)
  C6+C8 ──► E4 (hardening validation)
  C4 ──► E5 (alerting rules)
  C2 ──► E6 (release manager)
  B7 ──► E7 (agent-side budget awareness)
```

---

## 6. Effort Summary by Phase

| Phase | Feature Count | Est. Total Effort | Parallelizable? | Key Dependency |
|-------|--------------|-------------------|-----------------|---------------|
| **A: Containerization** | 7 items | ~8:45 | Partially (A1+A3 parallel) | Governance code (done) |
| **B: Review + Router** | 9 items | ~12:30 | Partially (B1+B2 parallel B5) | Phase A completion |
| **C: CI/CD + Production** | 10 items | ~6:15 | Partially (C4+C5+C10 parallel) | Phase A completion |
| **D: EU AI Act** | 4 items | ~3:30 | Fully parallel | Phase B2/B5 |
| **E: Observability** | 7 items | ~10:00 | Partially (E3+E5 parallel) | Phases A-C completion |
| **Total** | **37 items** | **~41:00** | | |

### 6.1 MVP Cut (Phase A + C7/C9/C10 + A7)

If 4:00 of focused effort before a demo:
1. A1 (Dockerfile.echelon) — 0:30
2. A2 (docker-compose.yml) — 1:00
3. A3 (redis-init.sh) — 0:15
4. A7 (fix integration tests for CI) — 1:00
5. C10 (Spotless fix) — 0:30
6. C7 (filesystem allowlisting) — 0:15
7. C9 (branch protection) — 0:15
**Total: ~3:45** → Runnable governance + integration tests in CI

---

## 7. Specific Research Findings

### 7.1 Docker Seccomp for JVM Build Containers

- Docker's default seccomp profile (moby/default.json) blocks ~44 dangerous syscalls (ptrace, process_vm_readv, mount, keyctl, add_key, kexec_file_load) while allowing everything Maven/Gradle/sbt need (clone, socket, connect, execve, futex, epoll_wait) [Docker docs].
- 10+ years of production hardening in the default profile.
- **No custom profile needed for builder containers** — Docker default is correct and tested.
- For reviewer containers (no build tools), a strict profile blocking `socket`, `connect`, `clone`, `execveat`, `mount` provides meaningful defence-in-depth without the maintenance burden of a full custom profile.
- **Reference:** gap-analysis.md §4.7 (Corrections §1), Docker Seccomp docs

### 7.2 Spring Boot Micrometer + Prometheus

- Spring Boot 3.4.x bundles Micrometer 1.14.x — adding `io.micrometer:micrometer-registry-prometheus` exposes `/actuator/prometheus` automatically.
- Custom metrics via `MeterRegistry.counter(...)`, `.counter(...)`, `.gauge(...)`, `.timer(...)`.
- Echelon should instrument: `policy.permit.decisions` (counter with `verdict=ALLOW|DENY`), `budget.remaining` (gauge per task/agent), `cost.attribution.total` (counter), `task.lifecycle.duration` (timer with phase tags).
- **Reference:** Baeldung, Uptrace.dev, javathinking.com — Spring Boot Micrometer guides

### 7.3 Testcontainers in GitHub Actions

- Testcontainers works natively in GitHub Actions runners because Docker is pre-installed on `ubuntu-latest`.
- Key patterns: (1) Use `testcontainers-junit-jupiter` with `@Testcontainers`, (2) Configure `redis:7-alpine` GenericContainer, (3) Do NOT use Testcontainers Cloud unless local Docker daemon is unavailable.
- Current issue: `GovernanceIntegrationTest` is `@Disabled` because CI was failing on Docker availability. The fix is to ensure the GitHub Actions runner has Docker (it does by default) and remove the `@Disabled` annotation with proper conditional test activation.
- **Reference:** Docker Blog (testcontainers-github-actions), testcontainers.org docs

### 7.4 EU AI Act (Articles 12-14)

- **Art. 12 (Record-keeping):** Automated logging of all system operations — Echelon's Redis streams (`events:cost`, `events:budget`, `events:governance`) provide the infrastructure but need producers for every governance decision.
- **Art. 13 (Transparency):** Deployers must understand the system's capabilities and limitations. Requires: system documentation (ADR series), capability descriptions per agent role, known limitations.
- **Art. 14 (Human Oversight):** Decisions that cannot be fully automated require human review before taking effect. The human release gate (G-03 in gap-analysis) addresses this but is not yet built.
- **Risk Tiering:** Echelon's agent roles should be mapped: Orchestrator (Limited Risk - transparent processing), Build Manager/Implementer (Limited Risk - code generation), Review Manager (High Risk - code quality decisions affecting safety).
- **Reference:** arXiv:2607.21345, EU AI Act text

### 7.5 Gap-Analysis.md vs Current Reality

The existing `gap-analysis.md` was written when the repo was empty. Major deltas:

| Area | gap-analysis.md Claim | Current Reality | Audit Assessment |
|------|----------------------|----------------|------------------|
| Deontic permission model | 🔴 Missing (G-01) | ✅ Delivered in ADR-001 + code | Gap closed |
| Token budget governance | 🔴 Missing (C-02) | ✅ Delivered in ADR-002 + code | Gap closed |
| Redis orchestration backbone | 🔴 Missing (D-02) | 🟡 Partial — Redis config exists in test scope but not in production Docker | Half-gap remains |
| Build Manager container | 🔴 Missing (M-01) | 🔴 Still missing — governance code exists but no container to run it | Gap unchanged |
| Privacy Router | 🔴 Missing | 🔴 Still missing | Gap unchanged |
| CI/CD pipeline | 🔴 Missing (O-01) | 🟡 Partial — basic GitHub Actions for compile exists, no Docker push | Half-gap |
| Seccomp profiles | 🔴 Missing (S-01) | 🔴 Still missing | Gap unchanged |

---

## 8. CRITICAL REVIEW

### 8.1 Flaws in This Analysis

1. **Effort estimates are uncalibrated.** The ~41:00 total estimate is based on single-developer greenfield time and does not account for debugging, iteration, or integration friction. Real-world multiplier is likely 2-3x (80-120 hours). The gap-analysis.md's original Phase 1 estimate ("Days 4-14") was similarly optimistic.

2. **Priority inversion risk.** This document groups Phase A as "containerization first," but the existing `GovernanceIntegrationTest` is `@Disabled` because it requires Docker — the tests already exist but cannot run in CI. A more honest priority is: fix the integration test CI first (A7), then containerize. A7 has no dependency on A1-A6; it can be done immediately.

3. **Privacy Router underestimation.** B5 is estimated at 3:00, but a production-grade credential proxy involves: (a) selecting the proxy server (haproxy/nginx/envoy), (b) configuring TLS termination, (c) implementing credential stripping + injection, (d) request logging, (e) provider routing logic, (f) cost attribution tagging, (g) rate limiting, (h) failover. Realistic estimate: 6-10 hours for a first iteration, 15-20 for production readiness.

4. **Missing CI/CD pre-work.** The entire pipeline (C1, C2, C9) assumes GitHub Actions works out of the box with Docker-based integration tests. The current test code uses `@Disabled` — the actual CI fix (A7) may require Testcontainers configuration changes, Docker-in-Docker setup, or a Testcontainers Cloud account. If none of these work, the CI gap is bigger than estimated.

5. **No dependency on existing PR #63 structure.** The governance code in PR #63 is a Java library, not a service. Containerizing it (A1) requires either: (a) a Spring Boot executable JAR with a main class that wires governance into a service, or (b) embedding the governance library into the orchestrator module. Either approach needs a non-trivial wiring step that this document glosses over.

### 8.2 Items to Defer or Cut

1. **Semantic caching (B8, 2:00)** — Promises 60-88% savings but requires embedding generation infrastructure. Defer to Phase E unless cost data from Phase B operations shows a clear need. Prompt caching (B9, 0:30 — provider-native, trivial) should be done first, and the cache-hit ratio measured before investing in embeddings.

2. **Load testing harness (E1, 2:00)** — Cannot be built until managers and workers exist (Phase A/B). Even then, it's a quality-of-measurement tool, not a production feature. Cut from roadmap entirely; manual load testing with a few shell scripts is sufficient until the system is stable.

3. **Agent-side budget awareness (E7, 1:00)** — Interesting UX improvement but low ROI. The system-enforced budget caps (B7) already prevent the $47K runaway scenario. Notifying the agent helps but doesn't change the safety outcome. Defer to post-MVP.

4. **E5 Alerting rules (1:00)** — Alerting without meaningful baselines is noise. Measure first (C4), establish baselines from 2-4 weeks of operation, then define alert thresholds. Move to a separate post-MVP phase.

### 8.3 Dependency Traps

- **Stage-gate ordering:** A5 (build-manager.sh) cannot be tested without A6 (implement.sh) and vice versa. These must be built and tested together as a pair. Estimate them as a unit (5:00) rather than separately (2:00 + 3:00).
- **Privacy Router vs network default-deny:** C8 depends on B5 — you can't deny network access without defining the egress point. These must be sequenced: B5 → C8, not parallel.
- **CI block on integration tests:** C1 (CI workflow) currently compiles but does not run integration tests. Fixing A7 may require changing the CI workflow itself (C1). These are coupled.
- **GHCR pipeline (C2, Issue #48) depends on Dockerfiles existing (A4, B1).** Cannot auto-build images before defining them.

### 8.4 Risk Concentration Map

```
High Risk / High Impact ─────────────────────────────────────►
  B5 (Privacy Router)       A5 (build-manager.sh)
  A6 (implement.sh)         B2 (review-manager.sh)
  
  C4 (Prometheus metrics)   C2 (GHCR pipeline)
  B8 (semantic caching)     E1 (load testing)
  
Low Risk / High Impact ──────────────────────────────────────►
  C5 (backup/DR)            A7 (fix integration tests)
  C6 (seccomp profiles)     C7 (filesystem allowlisting)
  C9 (branch protection)    D3 (transparency docs)
  
Low Risk / Low Impact ───────────────────────────────────────►
  B9 (prompt caching)       C10 (Spotless fix)
  D4 (risk tiering)         E7 (budget awareness)
```

### 8.5 Recommended Immediate Actions (Next 2 Sprints)

**Sprint 1 (0:30 — fix CI + Dockerize):**
1. A7: Fix `GovernanceIntegrationTest` — remove `@Disabled`, configure for GitHub Actions Docker environment. **Verification:** `mvn verify` passes with Testcontainers in CI. (1:00)
2. C10: Fix Spotless/palantir-java-format for JDK 25 compatibility. **Verification:** `mvn compile` on JDK 25. (0:30)
3. A1 + A2: Create `Dockerfile.echelon` and `docker-compose.yml` for the orchestrator module. **Verification:** `docker compose up` starts both Redis and Echelon orchestrator. (1:30)

**Sprint 2 (0:30 — build pipeline + security basics):**
4. C2: GHCR auto-build workflow. **Verification:** PR merge triggers Docker image build and push to GHCR. (1:00)
5. C6 + C7 + C8: Seccomp defaults + filesystem allowlisting + network default-deny in docker-compose. **Verification:** `docker inspect` shows `--security-opt seccomp=...`, `:ro` mounts, `--network none` on reviewers. (1:00)
6. C5: Redis AOF + volume snapshot config. **Verification:** `redis-cli CONFIG GET appendonly` returns `yes`. (1:00)

---

## 9. Source References

| ID | Source | Key Insight |
|----|--------|-------------|
| [P1] | Milosevic & Rabhi — arXiv:2601.03624 | Deontic token model, 5 governance patterns |
| [P4] | Schroeder de Witt — arXiv:2505.02077 | Multi-agent security, zero-trust |
| [P6] | Deontic Policies — arXiv:2606.19464 | Runtime policy evaluation, conflict resolution |
| [R4] | NiteAgent — Cost Optimization 2026 | Token budgets, $47K runaway incident |
| [R5] | AI Workflow Lab — LLM Cost Optimization | 4-layer cost optimization, 60-88% caching savings |
| [R6] | EU AI Act analysis — arXiv:2607.21345 | Art. 12/13/14 compliance mapping |
| ADR-001 | Echelon ADR | DeonticToken sealed interface + PolicyEngine |
| ADR-002 | Echelon ADR | Redis-backed BudgetManager + CostTracker |
| gap-analysis.md | Echelon repo | Pre-v0.2.0 baseline gap inventory |
| Docker docs | docs.docker.com | Default seccomp profile analysis |
| Testcontainers | testcontainers.org | CI integration patterns |
| Micrometer | micrometer.io | Spring Boot metrics facade |

---

*This roadmap audit was generated by researching the echelon repository at `/Users/rath/echelon`, reading all 7 documentation files, the gap-analysis.md, CHANGELOG, 8 open GitHub issues, ~40 closed issues, and searching industry best practices for Docker seccomp, Spring Boot Micrometer, Testcontainers CI patterns, and EU AI Act compliance. All estimates are in hours:minutes and assume a single experienced developer working without unblocked dependencies.*
