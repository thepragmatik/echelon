# Changelog

## [0.2.0-alpha] — 2026-07-26

### Added
- **DeonticToken sealed interface** (`io.echelon.governance.token`) — Permit, Embargo, Burden records with compile-time exhaustiveness via Java 21 sealed types
- **PolicyEngine** — runtime evaluation with embargo-first, default-deny priority chain
- **PolicyStore interface + YamlPolicyLoader** — parses `agent-types.yaml` at startup
- **Redis-backed BudgetManager** — per-task (50k) and per-agent-monthly (500k) token caps with configurable TTL
- **Redis stream-backed CostTracker + CostAttribution record** — durable cost event store
- **BuildManager wired to PolicyEngine** — `permit()` no longer returns unconditional `true`
- **Fixer worker script** (`echelon-workers/src/main/resources/scripts/fixer.sh`) — auto-applies review fixes
- **Policy schema** (`echelon-governance/src/main/resources/policies/agent-types.yaml`) — 4 agent roles with permits, embargoes, burdens
- **ADR-001: DeonticToken Sealed Interface** — architecture decision record
- **ADR-002: Redis-Persistent Budget and Cost Tracking** — architecture decision record
- **Governance class diagram** — Excalidraw diagram of full class hierarchy
- **Deontic governance synthesis** — literature review cross-referencing 14 sources
- **Unit tests:** DeonticTokenTest (7), PolicyEngineTest (4), YamlPolicyLoaderTest (5)
- **Integration test:** GovernanceIntegrationTest (12 tests, Docker/Testcontainers-based)

### Changed
- `echelon-governance/pom.xml` — added spring-boot-starter-data-redis, -test, jackson-dataformat-yaml, testcontainers
- `echelon-orchestrator/pom.xml` — added echelon-governance dependency
- `.gitignore` — added target/, .classpath, .project, .settings/ exclusion patterns

### Fixed
- `pier_delegate`/`pier_session` UnboundLocalError — walrus-operator scoping bug in handler lambdas

## [0.3.0-alpha] — 2026-07-27

### Added
- **Maven profile for integration tests** — `mvn test -DrunITs=true` activates integration tests via `<profile><id>integration</id>`. Replaces hardcoded surefire exclusion.
- **CI integration test job** — New `integration` job on GitHub Actions (ubuntu-latest, Docker) runs after `build` passes.
- **GitHub Issue traceability** — Issues #67, #68, #69 created for all MVP 1 tasks.

### Fixed
- **GovernanceIntegrationTest CI failures** — Fixed 3 root causes: @Nested test isolation (moved cleanRedis to @BeforeEach), CostTracker stream serialization (switched from ObjectRecord to MapRecord).
- **@Tag("integration") annotation** — Tests tagged for profile-based activation.

### Changed
- `.github/workflows/ci.yml` — Added `integration` job with `-DrunITs=true`.
- `echelon-governance/pom.xml` — Removed `<exclude>**/*IntegrationTest.java</exclude>`, replaced with Maven profile.
- `CostTracker.java` — Switched from ObjectRecord to MapRecord for Redis Streams.

## [0.3.1] — 2026-07-27

### Added (MVP 2 — Security + Docker)
- **Governance JAR wired into containers** — Builder/reviewer Dockerfiles now run the governance-enabled uber-JAR with Spring Boot entrypoint (PR #78)
- **Seccomp audit** — default.json (Docker default, no changes needed) and reviewer-strict.json (verified JVM-compatible) audited (PR #85)
- **Filesystem allowlisting** — Per-container write/read/block policies for builder, reviewer, and privacy-router (PR #88)
- **Network default-deny policy** — Explicit ingress/egress rules. Privacy Router is sole egress point (PR #87)
- **Privacy Router health check** — docker-compose healthcheck + credential scoping policy per container type (PR #89)
- **GitHub Pages docs site** — MkDocs Material theme, auto-published on merge (PR #86)

### Closed Issues
- #72 Wire governance JAR
- #73 Seccomp audit
- #74 Filesystem allowlisting
- #75 Network default-deny
- #76 Privacy Router health
- #77 GitHub Pages + docs

### MVP 3 (In Progress)
- #79 common.sh shared library
- #80 Fix BuildManager stub
- #81 implement.sh with Pi agent
- #82 review-adversarial.sh
- #83 review-quality.sh
- #84 Redis stream setup
