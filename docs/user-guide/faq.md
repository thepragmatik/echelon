# Frequently Asked Questions

## General

### What is Echelon?

Echelon is a hierarchical Docker-based zero-trust agent swarm orchestration platform. It coordinates AI agents (implementers, reviewers) to autonomously handle tasks like code generation, review, and deployment — governed by a deontic policy model.

### What tech stack does Echelon use?

Java 21+, Spring Boot 3.4+, Maven, Docker, and Redis. The AI agents use a tiered model routing system with GLM-5.2 as the primary model and DeepSeek V4 Pro as fallback for cost optimization.

### What phase is the project in?

| Phase | Status |
|-------|--------|
| Phase 0 (Foundation) | Complete |
| Phase 1 (Backbone) | Complete |
| Phase 2 (Governance) | Complete |
| Phase 3 (Optimization) | In progress |
| Phase 4 (Documentation) | In progress |

## Setup & Installation

### What are the prerequisites?

- Java 21+ ([Eclipse Temurin](https://adoptium.net/))
- Maven 3.9+
- Docker Desktop
- Git
- GitHub CLI (`gh`) authenticated with a token

### How do I get Echelon running?

```bash
git clone https://github.com/thepragmatik/echelon.git
cd echelon
mvn clean compile
docker compose -f echelon-docker/docker-compose.yml up -d
```

### How do I verify it's working?

```bash
docker compose ps                          # All containers healthy?
curl http://localhost:8080/health          # Privacy Router health
curl http://localhost:8080/actuator/prometheus  # Metrics
docker compose exec redis-primary redis-cli XLEN tasks:build  # Stream check
```

## Architecture

### How does Echelon's architecture work?

Echelon uses Redis stream-based task routing with consumer groups. Durable managers (BuildManager, ReviewManager) orchestrate ephemeral agent workers. The Privacy Router provides credential isolation — it's the only service with access to LLM API keys. See [Architecture Overview](architecture.md) for the full diagram.

### What are the core services?

| Service | Role | Port |
|---------|------|------|
| **Privacy Router** | L7 credential proxy for LLM calls | 8080 |
| **Redis Primary** | Stream bus + state store | 6379 |
| **Redis Replica** | Read replica for metrics | 6380 |
| **Redis Sentinel** | Automatic failover | 26379 |
| **Prometheus** | Metrics collection | 9090 |
| **Builder** | Agent task executor | internal |

### What Redis streams does Echelon use?

| Stream | Purpose |
|--------|---------|
| `tasks:build` | Incoming task requests from users |
| `tasks:review` | PRs requiring review after implementation |
| `results:review` | Review verdicts from adversarial and quality reviewers |
| `events:governance` | Audit trail of policy decisions and token evaluations |
| `events:cost` | Cost entries per LLM call |
| `events:budget` | Budget cap changes |

## Governance

### What is the deontic token model?

Echelon uses three types of deontic tokens to govern every agent action:

| Token | Meaning | Example |
|-------|---------|---------|
| **Permit** | Agent MAY perform this action | `implementer` can `write_source` |
| **Embargo** | Agent MUST NOT perform this action | `reviewer` cannot `write_to_main` |
| **Burden** | Agent MAY perform, but with obligations | `implementer` can `commit_feature_branch` but must `create_pr` and `pass_tests` |

The model follows a default-deny principle: any action not explicitly permitted is denied.

### How does the PolicyEngine evaluate actions?

1. Check Embargoes → if matched, DENY
2. Check Permits → if no match, DENY (default-deny)
3. Check Burdens → collect obligations
4. Return ALLOW with obligations list

### Can policies be updated at runtime?

Policies are defined in `agent-types.yaml` and loaded at application startup. Hot-reload via `RedisPolicyStore` is available for Phase 2+ deployments.

## Task Pipeline

### How does a task flow through the system?

1. User creates a GitHub issue
2. Orchestrator reads the issue via GitHub API
3. BuildManager queues the task on `tasks:build` Redis stream
4. Builder container picks up the task, consults PolicyEngine
5. Implementer agent forks the repo, writes code, creates a PR
6. PR URL pushed to `tasks:review` stream
7. Reviewer containers run adversarial + quality checks
8. Results streamed to `results:review` for merge decision

### How do I push a task manually?

```bash
docker compose exec redis-primary redis-cli XADD tasks:build \
  "*" taskId "task-110" issueUrl "https://github.com/thepragmatik/echelon/issues/110"
```

### How do I watch the pipeline execute?

```bash
docker compose logs -f builder
tail -f /tmp/echelon-pi-output-task-110.log
```

## Review Pipeline

### What checks does the adversarial review perform?

- Injection attacks (command, SQL, prompt injection)
- Credential leaks (hardcoded API keys, tokens, passwords)
- Privilege escalation (auth or role check bypasses)
- Supply chain risks (unvetted new dependencies)

### What checks does the quality review perform?

- Test coverage (new code has corresponding tests)
- Code style (matches Checkstyle conventions)
- Architecture (follows established patterns)
- Documentation (public APIs are documented)

### How do I run reviews manually?

```bash
docker compose exec reviewer adversarial-review \
  --pr https://github.com/thepragmatik/echelon/pull/115

docker compose exec reviewer quality-review \
  --pr https://github.com/thepragmatik/echelon/pull/115
```

## Security

### How does Echelon implement zero-trust security?

Echelon implements defense in depth across five layers:

| Layer | Protection |
|-------|-----------|
| **Layer 0: Governance** | Deontic Tokens (Permit/Embargo/Burden) |
| **Layer 1: System Calls** | Seccomp profiles (blocked: mount, ptrace, bpf) |
| **Layer 2: Filesystem** | Read-only mounts, allowlisted paths |
| **Layer 3: Network** | Default-deny egress, router as sole gateway |
| **Layer 4: Credential Isolation** | Privacy Router — no agent holds API keys |

### What are the zero-trust principles?

| Principle | Implementation |
|-----------|---------------|
| **Verify explicitly** | Every agent action checked by PolicyEngine |
| **Least privilege** | Each agent type has minimal deontic tokens |
| **Assume breach** | Privacy Router isolates credential exposure |
| **Default deny** | No permit → action is denied |

### How does credential isolation work?

The **Privacy Router** is the only service with access to LLM API keys. Agents never see raw credentials — all LLM calls are proxied through the Privacy Router, which injects credentials and logs every request.

## Operations

### How do I check service health?

```bash
docker compose ps
curl http://localhost:8080/actuator/health
curl http://localhost:9090/-/healthy
docker compose exec redis-primary redis-cli INFO replication
docker compose exec redis-sentinel redis-cli SENTINEL masters
```

### What Prometheus metrics are available?

| Metric | Description |
|--------|-------------|
| `echelon_policy_decisions_total` | PolicyEngine decisions by action + verdict |
| `echelon_budget_remaining` | Remaining token budget per agent |
| `echelon_tasks_queued` | Tasks waiting in Redis streams |
| `echelon_tasks_completed` | Tasks completed successfully |
| `echelon_pipeline_duration` | Pipeline execution time in seconds |

### How do I back up Redis data?

```bash
docker compose exec redis-primary redis-cli BGSAVE
# Restore:
docker compose stop redis-primary
cp /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.bak
docker compose start redis-primary
```

### What do I do if the builder won't start?

Check that Redis is reachable: `docker compose ps redis-primary`. If Redis is down, start it with `docker compose up -d redis-primary`.

### Tasks queue but don't execute — why?

The PolicyEngine is likely denying the action. Check the permits in `agent-types.yaml` to ensure the agent role has the required permits.

### A PR wasn't created — what's wrong?

The GitHub token is likely missing or invalid. Check the `PRIVACY_ROUTER_API_KEY` environment variable.

### A review is stalled — what now?

The reviewer container may have run out of memory. Increase the Docker memory limit for the reviewer service.
