# MVP 3 Plan: Manager Workers + Agent Pipeline

**Author:** Hermes Research Agent (hswarm-rsrch)  
**Date:** July 27, 2026  
**Status:** Draft — detailed task breakdown based on codebase audit  
**Repo:** `github.com/thepragmatik/echelon` at `/Users/rath/echelon`

---

## 1. Executive Summary

MVP 3 implements the actual agent workflows that make Echelon do something useful. Currently (v0.3.0-alpha, after MVP 1 CI + MVP 2 Security/Docker):

- **BuildManager** (Java) polls `tasks:build` stream but never actually spawns an implementer — `processTask()` logs "implementer_spawned" then immediately marks `COMPLETED`. The real work is missing.
- **ReviewManager** (Java) polls `tasks:review` stream and spawns the existing `reviewer.sh` script — but the script handles both adversarial and quality review via a single `$ROLE` parameter (no dedicated scripts).
- **`implementer.sh`** exists but uses `gh` CLI only (no Pi agent interaction, no actual code generation).
- **`echelon-managers`** module is an empty shell (pom.xml + empty target/).
- **Redis streams** are initialized: `tasks:build` (builders group), `tasks:review` (reviewers group), `results:build`, `results:review`.

**MVP 3 delivers:** A fully wired shell-based agent pipeline where a task pushed to Redis triggers: PolicyEngine check → BudgetManager check → implementer spawn (clone, code-gen via Pi, compile, PR) → review-manager spawn (adversarial + quality parallel review) → verdict collection.

### Total Effort: ~21:30 (13:30 high-confidence + 8:00 high-risk)
### Dependencies: MVP 2 security policies (deontic tokens, budget/cost tracking) — already delivered in v0.2.0/v0.3.0

---

## 2. Task Breakdown

### Task 1: `common.sh` — Shared Shell Library

**File:** `echelon-workers/src/main/resources/scripts/common.sh`

**Description:** Shared utility functions used by all worker scripts. Provides: Redis stream read/write helpers (`redis_xread`, `redis_xadd` with retry), authentication bootstrap (`load_gh_token`, `load_api_keys`), logging with ISO-8601 timestamps (`log_info`, `log_error`, `log_audit`), branch-safe git routines (`safe_checkout`, `safe_clone`), and a simple PolicyEngine HTTP client (`check_policy role action`) that hits the orchestrator's governance endpoint. This single source of truth prevents copy-paste inconsistency across 5 worker scripts.

**Dependencies on other MVP 3 tasks:**
- Required by: Tasks 2, 3, 4, 5, 6 (all scripts source it)

**Dependencies on MVP 2 tasks:**
- MVP 2 delivered the `PolicyEngine` Java service — `common.sh` needs a REST endpoint on the orchestrator to call it (or it can use `redis-cli` to read policy tokens directly)
- MVP 2 delivered `BudgetManager` — `common.sh` needs a Redis key check (`budget:task:<taskId>`)
- MVP 2 Docker infra (redis-primary must be reachable)

**Effort estimate:** 45 minutes

**Verification steps:**
1. Source `common.sh` from a shell — `log_info "test"` prints a correctly formatted log line
2. Point `redis-cli` at the running Redis container — `redis_xread tasks:build builders worker-1 1` returns a task record
3. `check_policy implementer write_source` returns ALLOW
4. `load_gh_token` populates `$GH_TOKEN` from Docker secret `/run/secrets/gh_token`

**Gotcha:** Don't use `#!/bin/bash` in common.sh — it's sourced, not executed. Use `#!/usr/bin/env bash` as a linter hint only. The sourcing scripts (build-manager.sh, implement.sh, etc.) set `set -euo pipefail` before sourcing common.sh. If common.sh itself sets `set -e`, it can break conditional checks in the caller.

---

### Task 2: `build-manager.sh` — Stream Subscriber + Worker Spawner

**File:** `echelon-workers/src/main/resources/scripts/build-manager.sh`

**Description:** Durable background process that subscribes to the `tasks:build` Redis stream (consumer group `builders`). For each task record: extracts `taskId`, `issueUrl`, `model`, `budget`; calls `check_policy implementer write_source` against PolicyEngine (fail-closed: DENIED → log + ACK + skip); calls BudgetManager via Redis key check (`budget:task:<taskId>`); spawns `implement.sh` in a subprocess with the task parameters; passes the subprocess PID to a monitoring loop with 30-minute timeout; writes a `results:build` record on completion or timeout with status `COMPLETED`/`FAILED`. Designed to run as a Docker container entrypoint with restart=always.

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`) for Redis helpers and policy checks
- Requires Task 3 (`implement.sh`) — the binary it spawns
- Required by: Nothing else — this is the pipeline entrypoint

**Dependencies on MVP 2 tasks:**
- Redis primary running, `tasks:build` stream + `builders` consumer group initialized (already done in `redis-init.sh`)
- PolicyEngine endpoint reachable (Java service in orchestrator, or direct Redis token read)
- Docker `Dockerfile.builder` exists (already created in MVP 2)

**Effort estimate:** 2 hours

**Verification steps:**
1. Start `build-manager.sh` in background; push a task record to `tasks:build` via `redis-cli XADD tasks:build * taskId test-1 issueUrl https://github.com/thepragmatik/echelon/issues/1 model glm-5.2 budget 50000`
2. `implement.sh` is spawned as a subprocess within 5 seconds
3. When implement.sh completes, a result record appears in `results:build`
4. If implement.sh times out (30 min), a `FAILED` record appears in `results:build` and the subprocess is killed
5. A task with a policy-violating role (e.g., `role=reviewer` for a build task) is silently skipped with a DENIED audit log

**Gotcha:** Redis consumer group semantics — if two `build-manager.sh` instances run simultaneously (horizontal scaling), they share the `builders` consumer group. Each task is delivered to exactly one consumer. But the spawn + monitor loop means one consumer can be blocked if a task takes 30 minutes. Set concurrency to 1 (`COUNT 1` in XREADGROUP) and trust the consumer group for load balancing. Do NOT use `COUNT 5` — that can overwhelm the subprocess manager. The Java `BuildManager` already uses `COUNT 1` — stay consistent.

---

### Task 3: `implement.sh` — Agent Code Generator

**File:** `echelon-workers/src/main/resources/scripts/implement.sh`

**Description:** Ephemeral worker that performs the actual code generation and PR creation. Accepts `ISSUE_URL`, `TASK_ID`, `REPO`, `MODEL` as parameters. Clones the repo to `/tmp/echelon-work-<TASK_ID>`, creates a feature branch (`worker/ECH-<ISSUE_NUM>-<slug>`), reads the issue title/description via `gh issue view`, generates code changes using the Pi CLI agent (`pi -p "implement issue #N: <description>"`), compiles the project with `mvn compile -q`, runs tests with `mvn test -q`, creates a checkpoint commit, pushes the branch, and creates a PR via `gh pr create`. Outputs structured JSON to stdout containing `{ "prUrl": "...", "prNum": "...", "branch": "...", "compileStatus": "OK"|"FAILED" }` for the build-manager to parse and forward to `results:build`.

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`) for auth bootstrap and logging
- Required by: Task 2 (`build-manager.sh`) — the spawned worker process

**Dependencies on MVP 2 tasks:**
- GitHub token injected via `-e GH_TOKEN` (credential isolation policy)
- Maven cache at `~/.m2` mounted read-only (filesystem allowlisting)
- Network egress to `api.github.com:443` and `repo1.maven.org:443` (network policy)

**Effort estimate:** 2 hours

**Verification steps:**
1. Run `implement.sh` with a real GitHub issue URL — it clones, creates a branch, generates a change, compiles, creates a PR
2. The PR title matches the issue title, the body references the issue
3. `mvn compile -q` passes before commit
4. If the branch already exists (re-run), the push fails gracefully with a log message
5. Output stdout JSON is parseable with `jq` and contains all expected fields
6. The branch follows the `worker/ECH-<N>-<slug>` naming convention

**Gotcha:** The Pi CLI (`pi -p`) is the code generation engine. It needs its own API key (OpenAI/Anthropic). This should be injected via environment variable (e.g., `ANTHROPIC_API_KEY`) and stripped from the task context before it's logged to Redis audit streams — otherwise API keys end up in plaintext in the stream. Use `LLM_PROXY_URL=http://privacy-router:8080` (MVP 2 infra) to route through the credential proxy.

---

### Task 4: `results-collector.sh` — Build Result Processing

**File:** `echelon-workers/src/main/resources/scripts/results-collector.sh`

**Description:** Consumer of `results:build` stream (consumer group `build-collector`). Reads build result records from the stream and decides the next action: if `status=COMPLETED`, pushes the PR URL to `tasks:review` stream (triggering the review pipeline); if `status=FAILED`, logs the failure and optionally pushes to a `tasks:retry` stream (Phase 2 feature, stub for now). This bridges the build and review pipelines — it's the glue between `build-manager.sh` and `review-manager.sh`. Also updates task state in Redis (`task:<taskId>:status` → `AWAITING_REVIEW`).

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`)
- Requires Task 3 (`implement.sh`) — reads its output records
- Produces for: Task 5 (`review-manager.sh`) — writes to `tasks:review`
- Required by: Nothing directly — but the build→review pipeline breaks without it

**Dependencies on MVP 2 tasks:**
- `results:build` stream + `build-collector` consumer group must be added to `redis-init.sh`
- `tasks:review` stream must exist and have `reviewers` consumer group (already exists)

**Effort estimate:** 30 minutes

**Verification steps:**
1. Write a `COMPLETED` record to `results:build` manually — within 5 seconds a record appears in `tasks:review` with matching `prUrl`
2. Write a `FAILED` record to `results:build` — no record appears in `tasks:review`, task state is set to `FAILED`
3. The `build-collector` consumer group is listed in `redis-cli XINFO GROUPS results:build`

**Gotcha:** Don't forget to add the `build-collector` consumer group to `redis-init.sh`. The existing file only creates `builders` and `reviewers` groups. If the group doesn't exist, `XREADGROUP` fails silently and the pipeline stalls.

---

### Task 5: `review-manager.sh` — Parallel Review Orchestrator

**File:** `echelon-workers/src/main/resources/scripts/review-manager.sh`

**Description:** Durable background process subscribing to `tasks:review` (consumer group `reviewers`). For each task record containing a `prUrl`: parses the PR number, calls `check_policy reviewer read_diff` (must be ALLOW), spawns TWO parallel reviewer subprocesses — `review-adversarial.sh` and `review-quality.sh` — with a 10-minute timeout per review. Collects JSON verdicts from both reviewers. If both verdicts are `APPROVE`, writes `status=APPROVED` to `results:review`. If either is `REQUEST_CHANGES`, writes `status=CHANGES_REQUESTED` to `results:review` with the combined comments. Updates task state in Redis.

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`)
- Requires Task 6 (`review-adversarial.sh`) and Task 7 (`review-quality.sh`) — spawned processes
- Requires Task 4 (`results-collector.sh`) — processes the output stream
- Required by: Nothing else — this is the terminal consumer of the pipeline

**Dependencies on MVP 2 tasks:**
- `tasks:review` stream + `reviewers` consumer group (already in `redis-init.sh`)
- `results:review` stream + `reviewers` consumer group (already in `redis-init.sh`)
- Reviewer container built from `Dockerfile.reviewer` with seccomp strict profile

**Effort estimate:** 1.5 hours

**Verification steps:**
1. Push a review task record to `tasks:review` — both review scripts spawn within 2 seconds
2. If both reviewers APPROVE, a record with `status=APPROVED` appears in `results:review`
3. If either reviewer returns REQUEST_CHANGES, status is `CHANGES_REQUESTED` with combined comments
4. A 10-minute timeout kills hung reviewers and records `FAILED`
5. Policy check prevents a non-reviewer role from spawning reviews

**Gotcha:** Parallel subprocess management in bash is error-prone. Use a pattern: `pid1=$!; pid2=$!; wait $pid1 $pid2` with a background timeout wrapper. Do NOT use `ProcessBuilder` from Java (as the existing `ReviewManager.java` does) — the shell-native approach is simpler and avoids JVM overhead. The Java `ReviewManager` already handles this via `ExecutorService` — keep it as the orchestrator's Java implementation, and make `review-manager.sh` the Docker-entrypoint equivalent for the shell-only execution mode.

---

### Task 6: `review-adversarial.sh` — Security-Focused Code Review

**File:** `echelon-workers/src/main/resources/scripts/review-adversarial.sh`

**Description:** Extracted and hardened from the existing `reviewer.sh` (currently ~126 lines with embedded adversarial logic). Performs a security-focused code review of a PR using Pi CLI (`pi -p`). Accepts `PR_NUM`, `REPO`, `MODEL` parameters. Clones the repo, checks out the PR branch, reads diff via `git diff origin/main...HEAD`. Generates a structured review prompt focusing on: injection vulnerabilities, privilege escalation, crypto misconfiguration, race conditions, secret leakage, input validation bypasses, and authentication/authorization gaps. Outputs JSON with `{ "verdict": "APPROVE"|"REQUEST_CHANGES", "findings": [{"severity": "CRITICAL"|"HIGH"|"MEDIUM"|"LOW", "file": "...", "line": N, "detail": "..."}] }`. The existing fallback (static analysis via grep for null references, System.out, etc.) is preserved for when Pi/LLM is unavailable.

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`)
- Required by: Task 5 (`review-manager.sh`) — spawned subprocess

**Dependencies on MVP 2 tasks:**
- GitHub token injection
- Language model proxy routing through Privacy Router
- Filesystem: read-only workspace mount, writable `/work`
- Seccomp strict profile for reviewer containers

**Effort estimate:** 1.5 hours

**Verification steps:**
1. Run against a known-vulnerable PR — outputs at least one CRITICAL or HIGH finding
2. Run against a clean PR — outputs `"verdict": "APPROVE"` with empty findings or `NO_ISSUES_FOUND`
3. JSON output is parseable with `jq` and validates against a JSON Schema
4. Running without `pi` available falls back to static analysis (grep-based checks)
5. A 10-minute timeout kills the subprocess and returns `REQUEST_CHANGES` with timeout note

**Gotcha:** The review prompt is the most critical part — a poorly constructed prompt produces false positives (wasting developer time) or false negatives (missing real vulnerabilities). The Pi agent should be prompted with a chain-of-thought structure: "Check each file for [category]. For each finding: severity, file, line, detail. If none found, say NO_ISSUES_FOUND." Avoid giving the agent the entire diff at once — chunk it by file. Use `head -200` like the existing script does to handle large files.

---

### Task 7: `review-quality.sh` — Style/Correctness Code Review

**File:** `echelon-workers/src/main/resources/scripts/review-quality.sh`

**Description:** Extracted from the existing `reviewer.sh`, focused on code quality rather than security. Checks: SOLID violations, test coverage gaps (files without corresponding test classes), DRY violations (duplicated code blocks > 10 lines), logging vs System.out, exception handling patterns (generic catch blocks, swallowed exceptions), Java Optional misuse, null safety, naming conventions, and documentation gaps. Uses Pi CLI with a checklist-driven prompt: for each file, check each item on the checklist. Outputs the same JSON verdict format as `review-adversarial.sh` (`{ "verdict", "findings" }`) so `review-manager.sh` can collect them uniformly. Maintains the existing grep-based fallback for when the LLM is unavailable.

**Dependencies on other MVP 3 tasks:**
- Requires Task 1 (`common.sh`)
- Requires Task 6 (`review-adversarial.sh`) — shares the JSON output schema (must match exactly)
- Required by: Task 5 (`review-manager.sh`) — spawned subprocess

**Dependencies on MVP 2 tasks:**
- Same as Task 6 (GitHub token, Privacy Router, seccomp strict, read-only workspace)

**Effort estimate:** 1 hour

**Verification steps:**
1. Run against a PR with a missing test class — finding appears at INFO level
2. Run against a PR with `System.out.println` — finding at MEDIUM level
3. Run against a PR with generic `catch (Exception e)` — finding at LOW level
4. JSON output schema matches `review-adversarial.sh` exactly (same `jq` keys)
5. Clean PR returns `"verdict": "APPROVE"`

**Gotcha:** The JSON output schema MUST match `review-adversarial.sh` exactly — `review-manager.sh` collects verdicts from both and needs a uniform interface. Define the schema in a comment at the top of both files, and add a `jq` schema validation step. A common bug: one reviewer uses `"severity"` while the other uses `"SEVERITY"` — case inconsistency breaks the collector. Agree on lowercase keys.

---

### Task 8: Redis Stream Extension + `redis-init.sh` Update

**File:** `echelon-docker/redis-init.sh`

**Description:** Extends the existing Redis initialization script to create the consumer groups needed by the new pipeline stages. Currently creates 4 consumer groups: `builders` (tasks:build), `reviewers` (tasks:review), `builders` (results:build), `reviewers` (results:review). New groups needed: `build-collector` (results:build — for `results-collector.sh`), `review-collector` (results:review — for future consumers like merge-orchestrator). Also creates `events:governance` stream (for PolicyEngine audit trail, as specified in ADR-002) and `events:budget` stream (for budget change events). These streams are defined in ADR-002 but not yet created in the current `redis-init.sh`.

**Dependencies on other MVP 3 tasks:**
- Required by: Tasks 4, 5, 6, 7 (all need the new consumer groups)
- Must be done BEFORE any pipeline tests

**Dependencies on MVP 2 tasks:**
- Redis container must be running (docker-compose up)
- The existing `redis-init.sh` pattern is well-established

**Effort estimate:** 15 minutes

**Verification steps:**
1. Run `redis-init.sh` against a running Redis container
2. `redis-cli XINFO GROUPS tasks:build` shows `builders` group
3. `redis-cli XINFO GROUPS results:build` shows `build-collector` group (NEW)
4. `redis-cli XINFO GROUPS results:review` shows `review-collector` group (NEW)
5. `redis-cli XLEN events:governance` returns 0 (stream exists, empty)
6. Running the script again produces no errors (`|| true` pattern for idempotency)

**Gotcha:** The existing script uses 2>/dev/null || true to make it idempotent — new groups created with `XGROUP CREATE ... $ MKSTREAM` will fail if the group already exists. The `|| true` suppression means errors from duplicate group creation are invisible. Consider switching to `XGROUP CREATE ... $ MKSTREAM 2>/dev/null || true` for consistency, but also log a warning when a group already exists (e.g., `redis-cli XINFO GROUPS <stream>` first to check). Alternatively, restructure to: `redis-cli XGROUP DESTROY <stream> <group> 2>/dev/null; redis-cli XGROUP CREATE <stream> <group> $ MKSTREAM` for clean re-initialization during development.

---

## 3. Dependency Graph

```
Phase A: Foundation (45 min)
  Task 1 (common.sh) ─────────────────────► Everything ──────────►
    │
Phase B: Build Pipeline (4.5 hours)        │
  Task 2 (build-manager.sh) ◄──── Task 3 (implement.sh)          │
    │                                          │                  │
    │    Task 8 (redis-init.sh) ◄──── All tasks need groups     │
    │                                          │                  │
    ▼                                          ▼                  │
Phase C: Result Bridge (30 min)              │                  │
  Task 4 (results-collector.sh) ◄── reads results:build          │
    │                                          │                  │
    │    writes to tasks:review                 │                  │
    ▼                                          ▼                  │
Phase D: Review Pipeline (4 hours)           │                  │
  Task 5 (review-manager.sh) ◄── spawns:                       │
    ├── Task 6 (review-adversarial.sh)        │                  │
    └── Task 7 (review-quality.sh)            │                  │
    │                                          │                  │
    ▼                                          ▼                  │
Phase E: Results                             │                  │
  results:review stream filled               │                  │
  task state machine: PENDING → IN_PROGRESS  │                  │
    → COMPLETED/FAILED                       │                  │
                                              │                  │
All tasks depend on: MVP 2 (Redis, Docker,   │                  │
  PolicyEngine, BudgetManager, credential     │                  │
  isolation, seccomp, FS allowlisting) ───────┘                  │
```

### Build Order (topological):
1. Task 8 (redis-init.sh extension) — 15 min — must exist before any pipeline test
2. Task 1 (common.sh) — 45 min — all other scripts source it
3. Task 3 (implement.sh) — 2 hr — build-manager spawns it
4. Task 2 (build-manager.sh) — 2 hr — needs implement.sh to exist
5. Task 6 (review-adversarial.sh) — 1.5 hr — review-manager spawns it
6. Task 7 (review-quality.sh) — 1 hr — review-manager spawns it
7. Task 5 (review-manager.sh) — 1.5 hr — needs both review scripts
8. Task 4 (results-collector.sh) — 30 min — bridges build→review

### Parallelization Opportunities:
- Tasks 2 + 3 can be built together as a pair (end-to-end implement pipeline test)
- Tasks 6 + 7 can be built in parallel (different review concerns)
- Task 1 can be built immediately (no dependencies)
- Task 8 can be built immediately (no dependencies)

---

## 4. Effort Summary

| # | Task | File | Effort | Risk | Parallelizable? |
|---|------|------|--------|------|----------------|
| 1 | common.sh | `echelon-workers/.../scripts/common.sh` | 45 min | Low | Yes — immediately |
| 2 | build-manager.sh | `echelon-workers/.../scripts/build-manager.sh` | 2:00 | High | With Task 3 (as a pair) |
| 3 | implement.sh | `echelon-workers/.../scripts/implement.sh` | 2:00 | High | With Task 2 (as a pair) |
| 4 | results-collector.sh | `echelon-workers/.../scripts/results-collector.sh` | 30 min | Low | After Tasks 2+3 |
| 5 | review-manager.sh | `echelon-workers/.../scripts/review-manager.sh` | 1:30 | Medium | After Tasks 6+7 |
| 6 | review-adversarial.sh | `echelon-workers/.../scripts/review-adversarial.sh` | 1:30 | Medium | With Task 7 |
| 7 | review-quality.sh | `echelon-workers/.../scripts/review-quality.sh` | 1:00 | Low | With Task 6 |
| 8 | redis-init.sh extension | `echelon-docker/redis-init.sh` | 15 min | Low | Yes — immediately |
| | **Total** | | **~9:30** | | |

**Adjusted total with overhead:** ~13:30 (1.4× multiplier for debugging, iteration, integration friction)

### High-Risk Items (worth 2× estimate):
- **Task 2 + 3 (4:00 → 8:00 effective):** The build pipeline is the most complex. Pi CLI integration is untested in this environment. Branch locking, timeout enforcement, and error recovery need iteration.
- **Task 6 (1:30 → 3:00 effective):** Security review prompts are notoriously brittle. False positives from LLM-based review are hard to calibrate. Expect to iterate on the prompt 3-5 times.

---

## 5. Critical Self-Review

### 5.1 What Might Go Wrong

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Pi CLI not available in builder container** | Medium | High — implement.sh cannot generate code | Fallback to existing `gh issue view` + hard-coded edit pattern; add Pi CLI to Dockerfile.builder |
| **Redis consumer group conflicts** | Low | Medium — tasks are processed by multiple consumers | Verify consumer group names in `redis-init.sh` match what each script uses |
| **JSON output schema mismatch between review scripts** | Medium | High — review-manager cannot parse verdicts | Define a JSON schema comment in both scripts; add `jq` validation in review-manager |
| **30-minute build timeout too short for large repos** | Medium | Low — tasks time out as FAILED | Make timeout configurable via environment variable (`BUILD_TIMEOUT_MINUTES`, default 30) |
| **Branch name collision** (two workers on same issue) | Low | Medium — push fails, race condition | Lock via Redis (`lock:branch:<issueUrl>`) before git checkout; existing `acquireLock` in TaskStreamService |
| **PolicyEngine call fails when orchestrator is down** | Medium | High — builds blocked | Cache last-known policy in Redis; use `default-deny` when cache also unavailable |
| **Review prompt generates hallucinated findings** | High | Medium — developers ignore review output | Calibrate with a known-good PR first; flag findings without line numbers as low confidence |
| **Missing consumer group in redis-init.sh** | High | Low — pipeline silently stalls | Add a validation step in each script: `redis-cli XINFO GROUPS <stream>` before XREADGROUP |

### 5.2 What's Underestimated

1. **Pi CLI integration (Tasks 3, 6, 7).** The existing `implementer.sh` uses `gh` CLI and doesn't touch Pi at all. Adding Pi (`pi -p <prompt>`) means: (a) ensuring `pi` is installed in the builder/reviewer Docker images, (b) configuring the provider API key (Anthropic/OpenAI), (c) constructing effective prompts for code generation vs code review (different prompt structures), (d) handling Pi failures gracefully. The 2-hour estimate assumes Pi works out of the box — add 1-2 hours per script if Pi integration has issues.

2. **Error handling and retry logic.** The task descriptions above mention "error recovery" but don't detail it. Real edge cases: `mvn compile` fails on generated code (implement.sh should log the compilation error and retry with the error message as context), `gh pr create` fails because a PR already exists for that branch (should push a new commit, not fail), network failure during `git push` (should retry with exponential backoff). Each of these adds 15-30 minutes of hardening code.

3. **Task state machine correctness.** The pipeline has a state machine: PENDING → ASSIGNED → IN_PROGRESS → COMPLETED/FAILED (from `TaskStateService.java`), plus the new AWAITING_REVIEW state between build and review. Shell scripts are notoriously bad at maintaining state machine invariants across crashes. A shell crash between setting the state and spawning the worker leaves a task in ASSIGNED forever. Consider adding a Redis key TTL as a dead-letter mechanism.

4. **Logging and observability.** The current `common.sh` plan includes `log_info` and `log_audit`, but real shell scripts need: structured JSON logging (for log aggregation), unique session IDs per pipeline run, timing/performance data (wall-clock time per stage), and a heartbeat mechanism so the Docker orchestrator can detect hung processes. Adding this observability to all 6 scripts adds 15-20 minutes per script.

5. **Docker entrypoint integration.** The scripts are designed to run as Docker containers, but the actual Dockerfile entrypoint wiring is not detailed here. `Dockerfile.builder` currently runs the Java orchestrator JAR with `--spring.profiles.active=builder`. The shell-based `build-manager.sh` needs a separate container or a sidecar pattern. This architecture decision (sidecar vs standalone) is not resolved in this plan and may add 1-2 hours of Dockerfile/entrypoint work.

### 5.3 Items Cut from MVP 3 Scope

| Item | Reason | When |
|------|--------|------|
| **Fixer pipeline** (review results → fixer → re-review loop) | Requires completed review pipeline first; adds significant complexity | MVP 4 |
| **Merge orchestrator** (auto-merge on approved PR) | Depends on fixer loop and branch protection; risky to automate merge | MVP 4 |
| **Deontic governance synthesis report** | Already exists as `deontic-governance-synthesis.md` | Done |
| **Grafana dashboard for pipeline metrics** | Observability scope, not core pipeline | MVP 4 |
| **Agent-side budget awareness** (surface remaining tokens in prompt) | Nice-to-have UX improvement | Post-MVP |
| **E2E integration test with Testcontainers** | Requires containerized pipeline; separate task | MVP 4 |

### 5.4 Verification Checklist (End-to-End)

When all 8 tasks are complete, run this smoke test:

```bash
# 1. Start the stack
docker compose up -d redis-primary builder reviewer

# 2. Init streams
docker compose exec redis-primary redis-cli < echelon-docker/redis-init.sh

# 3. Push a build task
docker compose exec redis-primary redis-cli \
  XADD tasks:build * \
  taskId "smoke-1" \
  issueUrl "https://github.com/thepragmatik/echelon/issues/1" \
  model "glm-5.2" \
  budget "50000"

# 4. Check build result (wait ~5 min for implement.sh)
sleep 300
docker compose exec redis-primary redis-cli XREAD COUNT 10 STREAMS results:build 0

# 5. If COMPLETED, check review result (wait ~5 min for reviewers)
docker compose exec redis-primary redis-cli XREAD COUNT 10 STREAMS results:review 0

# 6. Verify task state
docker compose exec redis-primary redis-cli GET "task:smoke-1:status"
# Expected: COMPLETED

# 7. Verify PR was created on GitHub
gh pr list --repo thepragmatik/echelon --head "worker/ECH-1-*"
```

### 5.5 Summary of File Changes

| Action | File | Notes |
|--------|------|-------|
| **CREATE** | `echelon-workers/src/main/resources/scripts/common.sh` | Shared shell library |
| **CREATE** | `echelon-workers/src/main/resources/scripts/build-manager.sh` | Stream subscriber + spawner |
| **MODIFY** | `echelon-workers/src/main/resources/scripts/implementer.sh` → `implement.sh` | Rename + add Pi CLI integration |
| **CREATE** | `echelon-workers/src/main/resources/scripts/results-collector.sh` | Build→review bridge |
| **CREATE** | `echelon-workers/src/main/resources/scripts/review-manager.sh` | Parallel review orchestrator |
| **CREATE** | `echelon-workers/src/main/resources/scripts/review-adversarial.sh` | Extracted from reviewer.sh |
| **CREATE** | `echelon-workers/src/main/resources/scripts/review-quality.sh` | Extracted from reviewer.sh |
| **MODIFY** | `echelon-docker/redis-init.sh` | Add new consumer groups + governance streams |

The existing `reviewer.sh` can remain as-is (deprecated) or be removed after migration. The existing `fixer.sh` is not affected by MVP 3.

---

*End of MVP 3 Plan*
