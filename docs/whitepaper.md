# Echelon: Hierarchical Zero-Trust Agent Swarm Orchestration

## Abstract

Echelon is a Docker-based hierarchical agent swarm orchestration platform that implements zero-trust security, deontic token governance, and cost-optimized model routing. Built on 10+ research papers and 7 industry reports.

## Architecture Highlights

- **Redis stream-based task routing** with consumer groups for durable, replayable task dispatch
- **Durable managers** (Build, Review) with ephemeral workers for fault-tolerant execution
- **Privacy Router** for credential isolation and model routing
- **Model tiering** — GLM-5.2 primary, DeepSeek V4 Pro fallback for cost optimization (70-80% savings)

## Key Differentiators

1. Docker-only isolation (no custom sandbox)
2. Model tiering saves 70-80% vs frontier-only
3. Gated 2-reviewer pipeline (adversarial + quality)
4. Checkpoint commit pattern for crash resilience

## Research Basis

| Ref | Paper | Contribution |
|-----|-------|-------------|
| P1 | Agentic Communities — deontic governance model (ODP-EL) | Three-token deontic model |
| P2 | MAS Empirical — real cost benchmarks (84% savings) | Model tiering cost validation |
| P3 | MetaGPT — SOP-driven deterministic workflows | Structured agent pipelines |
| P4 | Multi-Agent Security — zero-trust architecture | Defense-in-depth security layers |

## Detailed Documentation

| Topic | Document |
|-------|---------|
| Full architecture with diagrams | [Architecture Overview](user-guide/architecture.md) |
| Deontic token governance | [Governance Model](user-guide/governance.md) |
| Security model | [Security](user-guide/security.md) |
| Task lifecycle walkthrough | [Running Your First Task](user-guide/first-task.md) |
| Review pipeline | [Review Pipeline](user-guide/review-pipeline.md) |
| ADR-001: Deontic Tokens | [ADR-001](architecture/adr-001-deontic-tokens.md) |
| ADR-002: Redis Budget/Cost | [ADR-002](architecture/adr-002-redis-budget-streams.md) |
