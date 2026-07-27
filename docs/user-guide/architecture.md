# Architecture Overview

Echelon is a hierarchical Docker-based agent swarm orchestration platform built on zero-trust principles.

## System Components

```text
┌─────────────────────────────────────┐
│          Orchestrator               │
│  ┌──────────┐  ┌─────────────────┐  │
│  │ Build    │  │ Review          │  │
│  │ Manager  │  │ Manager         │  │
│  └────┬─────┘  └───────┬─────────┘  │
│       │                │            │
│  ┌────▼────────────────▼─────────┐  │
│  │     Redis Stream Bus          │  │
│  │  tasks:build  tasks:review    │  │
│  │  results:build results:review │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Core Services

| Service | Role | Port |
|---------|------|------|
| **Privacy Router** | L7 credential proxy for LLM calls | 8080 |
| **Redis Primary** | Stream bus + state store | 6379 |
| **Redis Replica** | Read replica for metrics | 6380 |
| **Redis Sentinel** | Automatic failover | 26379 |
| **Prometheus** | Metrics collection | 9090 |
| **Builder** | Agent task executor | internal |

## Communication Flow

1. User creates a GitHub issue
2. Orchestrator reads issue via GitHub API
3. BuildManager queues task on `tasks:build` Redis stream
4. Builder container picks up task, consults PolicyEngine
5. Implementer agent forks repo, writes code, creates PR
6. PR URL pushed to `tasks:review` stream
7. Reviewer containers run adversarial + quality checks
8. Results streamed to `results:review` for merge decision
