# Glossary

A --- [A](#a) · [B](#b) · [D](#d) · [E](#e) · [G](#g) · [H](#h) · [L](#l) · [M](#m) · [O](#o) · [P](#p) · [R](#r) · [S](#s) · [T](#t) · [Z](#z)

---

## A

### Adversarial Review
A security-focused code review that checks for injection attacks, credential leaks, privilege escalation, and supply chain risks. Runs in parallel with Quality Review.

### Agent
An ephemeral worker container spawned by a manager (BuildManager or ReviewManager) to perform a specific task (implement, review, etc.). Agents are stateless, short-lived, and governed by deontic tokens.

### Agent Types
Pre-defined agent roles: **implementer**, **reviewer** (adversarial + quality), **architect**, and **orchestrator**. Each type has a defined set of deontic tokens governing what actions it may perform.

### Auto-Merge
A workflow flag that automatically merges a PR when both adversarial and quality reviews pass, skipping the manual merge step.

## B

### BudgetManager
A Spring service that tracks and enforces per-task token budgets. Uses Redis-backed storage (Strings with TTL) to persist budgets across restarts.

### Burden
A type of deontic token that permits an action but attaches obligations. For example, an implementer may commit to a feature branch but must create a PR and pass tests. See also: Permit, Embargo.

### BuildManager
The durable Java service that polls `tasks:build`, validates actions against the PolicyEngine, and spawns implementer agents.

## C

### Checkpoint Commit
A crash-resilience pattern where intermediate work (e.g., after `mvn compile`) is committed to a branch before continuing. Prevents total loss of work if a container dies mid-task.

### CostTracker
A Spring service that records LLM call costs as append-only entries to the `events:cost` Redis stream. Enables aggregate cost queries and audit trails.

### Credential Isolation
A security pattern where the Privacy Router is the only service with access to LLM API keys. Agents never see raw credentials — all LLM calls are proxied.

## D

### Default-Deny
The security principle that any action not explicitly permitted is denied. No permit token matching an action → the action is blocked.

### Deontic Token
A sealed Java interface (`Permit`, `Embargo`, `Burden`) representing a governance rule for agent actions. All three modalities are enforced at compile time via Java's pattern matching exhaustiveness.

### Docker Compose
Used to orchestrate Echelon's infrastructure services: Redis cluster, Privacy Router, Prometheus, and agent worker containers.

## E

### Embargo
A type of deontic token that prohibits an action. If an embargo matches, the action is unconditionally denied. See also: Permit, Burden.

### Events Streams
Redis streams prefixed with `events:` that carry governance and operational data:

| Stream | Content | Retention |
|--------|---------|-----------|
| `events:cost` | Cost entries per LLM call | 90 days |
| `events:budget` | Budget cap changes | 30 days |
| `events:governance` | Deontic permit/deny decisions | Permanent |

## G

### GLM-5.2
The primary LLM model used by Echelon agents. Falls back to DeepSeek V4 Pro when cost optimization is needed.

### Governance
The system of deontic token rules that define what each agent type may, must not, and must-do when performing actions. Enforced by the PolicyEngine at dispatch time.

## H

### Health Check
Endpoints for verifying service status: `GET /health` on the Privacy Router (port 8080) and Prometheus at port 9090.

## L

### L7 Enforcement
Layer 7 (application-level) policy enforcement via the Privacy Router: implementers can POST (write code), reviewers/architects are GET-only (read-only), orchestrators can merge PRs.

## M

### Maven
The build tool for Echelon's Java services. All services are built with `mvn clean compile` and tested with `mvn test`.

### Model Tiering
A cost optimization strategy that uses a primary model (GLM-5.2) for most tasks and a cheaper fallback (DeepSeek V4 Pro) for simpler operations, achieving 70-80% cost savings vs frontier-only deployments.

## O

### Obligation
A required side-effect attached to a Burden token. E.g., "must create PR", "must pass tests", "must log decision". Obligations are collected during policy evaluation and executed after the action is permitted.

## P

### Permit
A type of deontic token that allows an agent to perform a specific action. Without a matching permit, default-deny blocks the action. See also: Embargo, Burden.

### PolicyEngine
The Spring service that evaluates every agent action against the deontic token rules. Follows a priority chain: Embargo → Permit → Burden, with default-deny semantics.

### Policy Result
The output of `PolicyEngine.evaluate()`, containing a `Decision` (GRANTED or DENIED) and an optional list of obligations.

### Privacy Router
An L7 credential proxy (port 8080) that is the only service with access to LLM API keys. Also enforces HTTP-level deontic rules (e.g., which agent types can POST vs GET).

### Prometheus
Metrics collection infrastructure exposed at port 9090, with Echelon-specific metrics like `echelon_policy_decisions_total` and `echelon_budget_remaining`.

## Q

### Quality Review
A code quality-focused review that checks test coverage, code style (Checkstyle), architectural patterns, and documentation. Runs in parallel with Adversarial Review.

## R

### Redis
The central nervous system of Echelon, providing stream-based task routing, state persistence, budget tracking, and audit trails. Deployed as a cluster (primary + replica + sentinel).

### Redis Streams
Append-only data structures used for all task and event routing: `tasks:build`, `tasks:review`, `results:review`, and the `events:*` governance streams.

### ReviewManager
The durable Java service that polls `tasks:review`, spawns adversarial and quality reviewer agents, and collects verdicts on the `results:review` stream.

## S

### Sealed Interface
A Java 21 feature used by `DeonticToken` to enforce compile-time exhaustiveness — every switch or pattern match must handle all three token types (Permit, Embargo, Burden).

### Sentinel
Redis Sentinel provides automatic failover for the Redis cluster, ensuring availability of the stream bus and state store.

## T

### Task Streams
Redis streams carrying operational task data: `tasks:build` (incoming tasks), `tasks:review` (PRs for review), `results:review` (review verdicts).

### TTL (Time-To-Live)
Applied to budget keys in Redis so that budgets for completed or abandoned tasks expire automatically after `max(30 min, 2 × expected task duration)`.

## Z

### Zero-Trust
A security model where no agent is implicitly trusted. Every action is verified by the PolicyEngine, credentials are isolated, and network access is default-deny with explicit allowlisting.
