# Echelon — Issue Dependency DAG

## Critical Path (Must Be Built Sequentially)
P0-Scaffold -> P0-Docker -> P1-Redis -> P1-BuildManager -> P1-Implementer -> P1-ReviewManager -> P1-Reviewer

## Phase 0 (Foundation)
P0-001 [Project Scaffold] ---> P0-002 [Docker Infrastructure] ---> P1-001
                                |
P0-003 [Git Workflow] ----------+

## Phase 1 (Backbone)
P1-001 [Redis Orchestration] ---> P1-002 [Build Manager] ---> P1-003 [Implementer Worker]
                                    |
P1-004 [Review Manager] <-----------+
    |
    +---> P1-005 [Reviewer Worker]

## Phase 2 (Governance) — parallelizable after P1 stable
P2-001 [Seccomp] P2-002 [FS Allowlist] P2-003 [Network Deny] P2-004 [Credential Isolation] P2-005 [Deontic Tokens]

## Phase 3 (Optimization) — depends on P2
P3-001 [Token Budget] P3-002 [Prompt Cache] P3-003 [Semantic Cache] P3-004 [Budget Awareness] P3-005 [Attribution]

## Phase 4 (Documentation) — parallel with P2/P3
P4-001 [README] P4-002 [Whitepaper] P4-003 [Dev Guide] P4-004 [Runbook]
