# Echelon — Issue Dependency DAG

## Critical Path (Must Be Built Sequentially)
#1 [Scaffold] -> #2 [Docker] -> #4 [Redis] -> #5 [Build Mgr] -> #6 [Implementer] -> #7 [Review Mgr] -> #8 [Reviewer]

## Phase 0 (Foundation)
#1 [Project Scaffold] ---> #2 [Docker Infrastructure] ---> #4
                            |
#3 [Git Workflow] -----------+

## Phase 1 (Backbone)
#4 [Redis Orchestration] ---> #5 [Build Manager] ---> #6 [Implementer Worker]
                                |
#7 [Review Manager] <-----------+
    |
    +---> #8 [Reviewer Worker]

## Phase 2 (Governance) — parallelizable after P1 stable
#9 [Seccomp]  #10 [FS Allowlist]  #11 [Network Deny]  #12 [Credential Isolation]  #13 [Deontic Tokens]

## Phase 3 (Optimization) — depends on P2
#14 [Token Budget]  #15 [Prompt Cache]  #16 [Semantic Cache]  #17 [Budget Awareness]  #18 [Attribution]

## Phase 4 (Documentation) — parallel with P2/P3
#19 [README]  #20 [Whitepaper]  #21 [Dev Guide]  #22 [Runbook]
