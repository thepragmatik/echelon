# Governance Class Hierarchy — Phase 0

**Status:** Draft  
**Date:** July 2026  
**Author:** Echelon Architecture Team  
**References:** ADR-001 (Deontic Tokens), ADR-002 (Redis Budget Streams), deontic-governance-synthesis.md, agent-types.yaml

---

## 1. High-Level Architecture

Echelon's governance layer implements a **deontic permission model** inspired by ODP-EL pattern #18 (Compliance/Governance) from Milosevic & Rabhi (arXiv:2601.03624). Three sealed token types — `Permit`, `Embargo`, and `Burden` — define what actions each agent role may, must not, or must perform. The Java 21 sealed interface ensures compile-time exhaustiveness: any `switch` over a `DeonticToken` must handle all three variants.

A `PolicyEngine` service evaluates each action dispatch against the loaded tokens using a priority chain: **Embargo > Burden > Permit** with **default-deny** semantics. The engine loads policies from `agent-types.yaml` (the canonical policy source) at application startup via a `PolicyStore` interface, which can be backed by either a file-based `YamlPolicyLoader` (Phase 0) or a future `RedisPolicyStore` (Phase 2+).

Alongside the deontic model, two governance services track resource consumption: `BudgetManager` enforces per-task and per-agent token caps, and `CostTracker` records cost attribution entries. Both are currently in-memory (Phase 0) and will migrate to Redis persistence under ADR-002 in Phase 1. The `BuildManager` orchestrator component is the primary consumer — its `permit()` method (currently a stub returning `true`) will be wired to `PolicyEngine.evaluate()` to enforce actual governance before any task dispatch.

### Current State vs Target

| Component | Phase 0 (current) | Phase 1 (target) |
|-----------|------------------|------------------|
| `DeonticToken` interface | Not yet implemented (ADR-001 specified) | Sealed interface with Permit / Embargo / Burden records |
| `PolicyEngine` | Not yet implemented | Runtime evaluation with priority chain |
| `PolicyStore` | Not yet implemented (YAML schema defined) | `YamlPolicyLoader` at startup |
| `BudgetManager` | In-memory `ConcurrentHashMap<String, Long>` | Redis Strings with TTL |
| `CostTracker` | In-memory `CopyOnWriteArrayList<CostEntry>` | Redis Streams with consumer groups |
| `BuildManager.permit()` | `return true` (unconditional) | `policyEngine.evaluate(role, action)` |

---

## 2. Class Hierarchy (Excalidraw Diagram)

The diagram below visualises the full governance class hierarchy. Save this JSON as `governance-class-diagram.excalidraw` and drag it onto [excalidraw.com](https://excalidraw.com) to view or edit.

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "echelon-architecture",
  "elements": [
    {"type":"text","id":"title","x":130,"y":15,"text":"Echelon Governance — Class Hierarchy (Phase 0)","fontSize":24,"fontFamily":1,"strokeColor":"#1e1e1e","originalText":"Echelon Governance — Class Hierarchy (Phase 0)","autoResize":true},
    {"type":"text","id":"subtitle","x":160,"y":45,"text":"Deontic Tokens | Policy Engine | Budget / Cost Tracking","fontSize":16,"fontFamily":1,"strokeColor":"#757575","originalText":"Deontic Tokens | Policy Engine | Budget / Cost Tracking","autoResize":true},

    {"type":"rectangle","id":"bg_gov","x":40,"y":70,"width":420,"height":700,"backgroundColor":"#e5dbff","fillStyle":"solid","roundness":{"type":3},"strokeColor":"#d0bfff","strokeWidth":1,"opacity":30},
    {"type":"text","id":"lb_gov","x":48,"y":74,"text":"Governance Layer","fontSize":16,"fontFamily":1,"strokeColor":"#8b5cf6","originalText":"Governance Layer","autoResize":true},

    {"type":"rectangle","id":"bg_budget","x":520,"y":70,"width":320,"height":420,"backgroundColor":"#d3f9d8","fillStyle":"solid","roundness":{"type":3},"strokeColor":"#b2f2bb","strokeWidth":1,"opacity":30},
    {"type":"text","id":"lb_budget","x":528,"y":74,"text":"Budget / Cost Layer","fontSize":16,"fontFamily":1,"strokeColor":"#15803d","originalText":"Budget / Cost Layer","autoResize":true},

    {"type":"rectangle","id":"dt","x":90,"y":100,"width":310,"height":85,"backgroundColor":"#d0bfff","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_dt","type":"text"},{"id":"a_dt_p","type":"arrow"},{"id":"a_dt_e","type":"arrow"},{"id":"a_dt_b","type":"arrow"}]},
    {"type":"text","id":"t_dt","x":95,"y":115,"width":300,"height":55,"text":"DeonticToken (sealed)\naction(), roles(), resource(), desc","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"dt","originalText":"DeonticToken (sealed)\naction(), roles(), resource(), desc","autoResize":true},

    {"type":"rectangle","id":"permit","x":50,"y":230,"width":140,"height":65,"backgroundColor":"#b2f2bb","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_permit","type":"text"},{"id":"a_dt_p","type":"arrow"}]},
    {"type":"text","id":"t_permit","x":55,"y":247,"width":130,"height":30,"text":"Permit\n(allowed actions)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"permit","originalText":"Permit\n(allowed actions)","autoResize":true},

    {"type":"rectangle","id":"embargo","x":210,"y":230,"width":140,"height":65,"backgroundColor":"#ffc9c9","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_embargo","type":"text"},{"id":"a_dt_e","type":"arrow"}]},
    {"type":"text","id":"t_embargo","x":215,"y":247,"width":130,"height":30,"text":"Embargo\n(denied actions)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"embargo","originalText":"Embargo\n(denied actions)","autoResize":true},

    {"type":"rectangle","id":"burden","x":370,"y":230,"width":140,"height":65,"backgroundColor":"#fff3bf","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_burden","type":"text"},{"id":"a_dt_b","type":"arrow"}]},
    {"type":"text","id":"t_burden","x":375,"y":247,"width":130,"height":30,"text":"Burden\n(with obligations)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"burden","originalText":"Burden\n(with obligations)","autoResize":true},

    {"type":"arrow","id":"a_dt_p","x":160,"y":185,"width":-10,"height":45,"points":[[0,0],[-10,45]],"endArrowhead":"arrow","startBinding":{"elementId":"dt","fixedPoint":[0.225,1]},"endBinding":{"elementId":"permit","fixedPoint":[0.5,0]}},
    {"type":"arrow","id":"a_dt_e","x":245,"y":185,"width":0,"height":45,"points":[[0,0],[0,45]],"endArrowhead":"arrow","startBinding":{"elementId":"dt","fixedPoint":[0.5,1]},"endBinding":{"elementId":"embargo","fixedPoint":[0.5,0]}},
    {"type":"arrow","id":"a_dt_b","x":330,"y":185,"width":10,"height":45,"points":[[0,0],[10,45]],"endArrowhead":"arrow","startBinding":{"elementId":"dt","fixedPoint":[0.775,1]},"endBinding":{"elementId":"burden","fixedPoint":[0.5,0]}},

    {"type":"arrow","id":"a_uses","x":245,"y":295,"width":0,"height":45,"points":[[0,0],[0,45]],"endArrowhead":"arrow","endBinding":{"elementId":"pe","fixedPoint":[0.5,0]}},

    {"type":"rectangle","id":"pe","x":90,"y":340,"width":310,"height":75,"backgroundColor":"#a5d8ff","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_pe","type":"text"},{"id":"a_uses","type":"arrow"},{"id":"a_pe_ps","type":"arrow"},{"id":"a_pe_bm","type":"arrow"}]},
    {"type":"text","id":"t_pe","x":95,"y":355,"width":300,"height":45,"text":"PolicyEngine\nevaluate(role, action) -> PolicyResult","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"pe","originalText":"PolicyEngine\nevaluate(role, action) -> PolicyResult","autoResize":true},

    {"type":"rectangle","id":"ps","x":90,"y":460,"width":310,"height":70,"backgroundColor":"#c3fae8","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_ps","type":"text"},{"id":"a_pe_ps","type":"arrow"},{"id":"a_ps_yl","type":"arrow"},{"id":"a_ps_rp","type":"arrow"}]},
    {"type":"text","id":"t_ps","x":95,"y":472,"width":300,"height":45,"text":"PolicyStore <<interface>>\ngetPermits(), getEmbargoes(), getBurdens()","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"ps","originalText":"PolicyStore <<interface>>\ngetPermits(), getEmbargoes(), getBurdens()","autoResize":true},

    {"type":"arrow","id":"a_pe_ps","x":245,"y":415,"width":0,"height":45,"points":[[0,0],[0,45]],"endArrowhead":"arrow","startBinding":{"elementId":"pe","fixedPoint":[0.5,1]},"endBinding":{"elementId":"ps","fixedPoint":[0.5,0]}},

    {"type":"rectangle","id":"yl","x":90,"y":570,"width":150,"height":55,"backgroundColor":"#a5d8ff","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_yl","type":"text"},{"id":"a_ps_yl","type":"arrow"}]},
    {"type":"text","id":"t_yl","x":95,"y":577,"width":140,"height":40,"text":"YamlPolicyLoader\n(file-based)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"yl","originalText":"YamlPolicyLoader\n(file-based)","autoResize":true},

    {"type":"rectangle","id":"rp","x":260,"y":570,"width":150,"height":55,"backgroundColor":"#ffd8a8","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_rp","type":"text"},{"id":"a_ps_rp","type":"arrow"}]},
    {"type":"text","id":"t_rp","x":265,"y":577,"width":140,"height":40,"text":"RedisPolicyStore\n(future)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"rp","originalText":"RedisPolicyStore\n(future)","autoResize":true},

    {"type":"arrow","id":"a_ps_yl","x":165,"y":530,"width":-15,"height":40,"points":[[0,0],[-15,40]],"endArrowhead":"arrow","strokeStyle":"dashed","startBinding":{"elementId":"ps","fixedPoint":[0.24,1]},"endBinding":{"elementId":"yl","fixedPoint":[0.5,0]}},
    {"type":"arrow","id":"a_ps_rp","x":325,"y":530,"width":15,"height":40,"points":[[0,0],[15,40]],"endArrowhead":"arrow","strokeStyle":"dashed","startBinding":{"elementId":"ps","fixedPoint":[0.76,1]},"endBinding":{"elementId":"rp","fixedPoint":[0.5,0]}},

    {"type":"rectangle","id":"bm","x":90,"y":675,"width":310,"height":65,"backgroundColor":"#a5d8ff","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_bm","type":"text"},{"id":"a_pe_bm","type":"arrow"}]},
    {"type":"text","id":"t_bm","x":95,"y":687,"width":300,"height":40,"text":"BuildManager\npermit() -> PolicyEngine.evaluate()","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"bm","originalText":"BuildManager\npermit() -> PolicyEngine.evaluate()","autoResize":true},

    {"type":"arrow","id":"a_pe_bm","x":400,"y":377,"width":40,"height":298,"points":[[0,0],[40,0],[40,298],[-40,0]],"endArrowhead":"arrow","startBinding":{"elementId":"pe","fixedPoint":[1,0.5]},"endBinding":{"elementId":"bm","fixedPoint":[1,0.5]}},

    {"type":"rectangle","id":"bgt","x":560,"y":110,"width":260,"height":65,"backgroundColor":"#b2f2bb","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_bgt","type":"text"},{"id":"a_bgt_rs","type":"arrow"}]},
    {"type":"text","id":"t_bgt","x":565,"y":122,"width":250,"height":40,"text":"BudgetManager\ndeduct(), remaining(), setCap()","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"bgt","originalText":"BudgetManager\ndeduct(), remaining(), setCap()","autoResize":true},

    {"type":"rectangle","id":"ct","x":560,"y":215,"width":260,"height":65,"backgroundColor":"#b2f2bb","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_ct","type":"text"},{"id":"a_ct_rs","type":"arrow"}]},
    {"type":"text","id":"t_ct","x":565,"y":227,"width":250,"height":40,"text":"CostTracker\nrecord(), byTask(), totalCost()","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"ct","originalText":"CostTracker\nrecord(), byTask(), totalCost()","autoResize":true},

    {"type":"rectangle","id":"rs","x":560,"y":325,"width":260,"height":70,"backgroundColor":"#c3fae8","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_rs","type":"text"},{"id":"a_bgt_rs","type":"arrow"},{"id":"a_ct_rs","type":"arrow"}]},
    {"type":"text","id":"t_rs","x":565,"y":335,"width":250,"height":50,"text":"Redis Streams (Phase 1)\nevents:cost, events:budget\nevents:governance","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"rs","originalText":"Redis Streams (Phase 1)\nevents:cost, events:budget\nevents:governance","autoResize":true},

    {"type":"arrow","id":"a_bgt_rs","x":690,"y":175,"width":0,"height":150,"points":[[0,0],[0,150]],"endArrowhead":"arrow","strokeStyle":"dashed","startBinding":{"elementId":"bgt","fixedPoint":[0.5,1]},"endBinding":{"elementId":"rs","fixedPoint":[0.5,0]}},

    {"type":"arrow","id":"a_ct_rs","x":690,"y":280,"width":0,"height":45,"points":[[0,0],[0,45]],"endArrowhead":"arrow","strokeStyle":"dashed","startBinding":{"elementId":"ct","fixedPoint":[0.5,1]},"endBinding":{"elementId":"rs","fixedPoint":[0.5,0]}},

    {"type":"rectangle","id":"bmr","x":560,"y":440,"width":260,"height":40,"backgroundColor":"#fff3bf","fillStyle":"solid","roundness":{"type":3},"boundElements":[{"id":"t_bmr","type":"text"}]},
    {"type":"text","id":"t_bmr","x":565,"y":445,"width":250,"height":30,"text":"Built on in Phase 1 (ADR-002)","fontSize":16,"fontFamily":1,"strokeColor":"#1e1e1e","textAlign":"center","verticalAlign":"middle","containerId":"bmr","originalText":"Built on in Phase 1 (ADR-002)","autoResize":true}
  ],
  "appState": {
    "viewBackgroundColor": "#ffffff"
  }
}
```

---

## 3. Evaluation Flow Diagram

The `PolicyEngine.evaluate()` method follows a strict priority chain. Below is the logical flow in ASCII:

```
                         ┌───────────────────────┐
                         │  Agent Action Request  │
                         │  (role, action)        │
                         └───────────┬───────────┘
                                     │
                                     ▼
              ┌────────────────────────────────────┐
              │  1.  Evaluate Embargoes            │
              │  For each Embargo token:           │
              │    if role IN embargo.roles AND    │
              │       action == embargo.action     │
              │    → return DENIED                 │
              └───────────┬────────────────────────┘
                          │ no embargo match
                          ▼
              ┌────────────────────────────────────┐
              │  2.  Evaluate Permits (default-deny)│
              │  For each Permit token:             │
              │    if role IN permit.roles AND      │
              │       action == permit.action       │
              │    → match found                    │
              │  If no Permit matches:              │
              │    → return DENIED                  │
              └───────────┬────────────────────────┘
                          │ permit match found
                          ▼
              ┌────────────────────────────────────┐
              │  3.  Evaluate Burdens              │
              │  For each Burden token:             │
              │    if role IN burden.roles AND      │
              │       action == burden.action       │
              │    → collect obligations            │
              └───────────┬────────────────────────┘
                          │
                          ▼
              ┌────────────────────────────────────┐
              │  4.  Return GRANTED                │
              │  PolicyResult(                     │
              │    decision=GRANTED,               │
              │    obligations=[...]   ← from Burdens│
              │  )                                  │
              └────────────────────────────────────┘
```

### Priority Rules

| Priority | Token Type | Effect |
|----------|-----------|--------|
| 1 (highest) | **Embargo** | Action is denied regardless of any Permit. Fail-closed. |
| 2 | **Burden** | Action is permitted, but one or more obligations must be executed (e.g., log, notify, require approval). |
| 3 | **Permit** | Action is allowed with no extra obligations. |
| — (fallback) | **Default-deny** | If no token matches the (role, action) pair, the action is denied. |

### Integration with BuildManager

```
BuildManager.processTask()
  │
  ├─ permit("implement", "BuildManager")  ← currently stub, returning true
  │     │
  │     └─ policyEngine.evaluate(role, action)  ← Phase 1 replacement
  │           │
  │           ├─ fails → DENIED → FAILED task, audit log
  │           │
  │           └─ passes → GRANTED → continue with build
  │
  ├─ budgetManager.deduct(taskId, tokens)  ← Phase 1
  ├─ costTracker.record(entry)             ← Phase 1
  └─ ... task execution
```

---

## 4. Key Interfaces and Responsibilities

### 4.1 `DeonticToken` (sealed interface, `io.echelon.governance`)

| Component | Java Type | Purpose |
|-----------|-----------|---------|
| `DeonticToken` | `sealed interface` | Base type for all deontic modalities. Closed set: Permit, Embargo, Burden. |
| `Permit` | `record` | Actions explicitly allowed for a set of roles. Default-deny: anything not listed is forbidden. |
| `Embargo` | `record` | Actions explicitly denied, even if also listed in a Permit. Overrides all other tokens. |
| `Burden` | `record` | Actions permitted but carrying extra obligations (e.g., logging, approval gates). |

```
sealed interface DeonticToken permits Permit, Embargo, Burden {
    String action();
    Set<String> roles();
    String resource();      // optional scope qualifier
    String description();   // human-readable description
}
```

### 4.2 `PolicyEngine` (`@Service`, `io.echelon.governance`)

- **Responsibility:** Evaluate whether a given agent role may perform a given action
- **Evaluation chain:** Embargo → Permit (default-deny) → Burden (obligations)
- **Output:** `PolicyResult` record with `Decision.GRANTED` or `Decision.DENIED` plus list of obligations
- **Startup:** Loads policies via `PolicyStore` at `@PostConstruct`
- **Fail-closed:** If `agent-types.yaml` is missing or malformed, the application fails to start

### 4.3 `PolicyStore` (interface, `io.echelon.governance`)

| Method | Returns | Description |
|--------|---------|-------------|
| `getPermits(role)` | `List<Permit>` | All permits applicable to a given role |
| `getEmbargoes(role)` | `List<Embargo>` | All embargoes applicable to a given role |
| `getBurdens(role)` | `List<Burden>` | All burdens applicable to a given role |

**Implementations:**

| Implementation | Status | Source |
|---------------|--------|--------|
| `YamlPolicyLoader` | Phase 0 (defined) | Parses `agent-types.yaml` at startup |
| `RedisPolicyStore` | Phase 2+ (future) | Loads policies from Redis for hot-reload |

### 4.4 `BudgetManager` (`@Service`, `io.echelon.governance`)

**Current (Phase 0):** In-memory `ConcurrentHashMap<String, Long>` — data lost on restart.

| Method | Purpose |
|--------|---------|
| `deduct(taskId, tokens)` | Deduct tokens from task budget; returns `false` if insufficient |
| `remaining(taskId)` | Return remaining token budget for a task |
| `setCap(taskId, cap)` | Set a per-task token cap |

**Target (Phase 1, ADR-002):** Redis Strings with TTL, shared across container instances.

### 4.5 `CostTracker` (`@Service`, `io.echelon.governance`)

**Current (Phase 0):** In-memory `CopyOnWriteArrayList<CostEntry>` — entries lost on restart.

| Method | Purpose |
|--------|---------|
| `record(CostEntry)` | Append a cost attribution entry |
| `byTask(taskId)` | Query all cost entries for a task |
| `totalCost()` | Sum cost across all entries |
| `totalTokens()` | Sum tokens across all entries |

**Target (Phase 1, ADR-002):** Redis Streams with consumer groups, 90-day retention.

### 4.6 `BuildManager` (`@Service`, `io.echelon.orchestrator.manager`)

- **Responsibility:** Polls the `tasks:build` Redis stream and dispatches build jobs to agent workers
- **Current gate:** `permit()` unconditionally returns `true` (line 82–84)
- **Target gate (Phase 1):** `permit()` calls `PolicyEngine.evaluate(role, action)` and returns `false` on DENIED
- **Additional wiring (Phase 1):** Calls `BudgetManager.deduct()` before task dispatch and `CostTracker.record()` on completion

---

## 5. Relationship Summary

```
 ┌─────────────────────────────────────────────┐
 │             DeonticToken (sealed)            │
 │     ┌─────────┬──────────┬────────────┐     │
 │     │  Permit  │ Embargo  │   Burden   │     │
 │     │ (allow)  │ (deny)   │ (obligate) │     │
 │     └────┬─────┴────┬─────┴─────┬──────┘     │
 │          │          │           │            │
 │          └──────────┼───────────┘            │
 │                     │ uses                   │
 └─────────────────────┼───────────────────────┘
                       │
                       ▼
              ┌─────────────────────┐
              │    PolicyEngine      │─── loads from ─── PolicyStore (interface)
              │  evaluate()          │                    ├── YamlPolicyLoader (file)
              └─────────┬───────────┘                    └── RedisPolicyStore (future)
                        │ used by
                        ▼
              ┌─────────────────────┐
              │    BuildManager      │
              │  permit() → engine   │
              └─────────┬───────────┘
                        │ also uses (Phase 1)
              ┌─────────┴───────────┐
              ▼                     ▼
     ┌────────────────┐  ┌──────────────────┐
     │  BudgetManager  │  │   CostTracker     │
     │ (Redis-backed)  │  │ (Redis Streams)   │
     └────────────────┘  └──────────────────┘
```

---

## 6. Source References

| File | Status | What it Defines |
|------|--------|-----------------|
| `docs/research/deontic-governance-synthesis.md` | ✅ Exists | Literature synthesis for deontic token model, cost governance, zero-trust |
| `docs/architecture/adr-001-deontic-tokens.md` | ✅ Exists | Sealed DeonticToken interface + PolicyEngine design |
| `docs/architecture/adr-002-redis-budget-streams.md` | ✅ Exists | Redis-backed BudgetManager + CostTracker design |
| `echelon-governance/src/main/resources/policies/agent-types.yaml` | ✅ Exists | Permit/Embargo/Burden policies for 4 agent roles |
| `echelon-governance/src/main/java/io/echelon/governance/BudgetManager.java` | ✅ Exists | Phase 0 in-memory implementation |
| `echelon-governance/src/main/java/io/echelon/governance/CostTracker.java` | ✅ Exists | Phase 0 in-memory implementation (includes `CostEntry` record) |
| `echelon-orchestrator/src/main/java/io/echelon/orchestrator/manager/BuildManager.java`| ✅ Exists | Phase 0 polling manager with stub `permit()` |

> **Note:** `PolicyEngine`, `DeonticToken`, `Permit`, `Embargo`, `Burden`, `PolicyStore`, `YamlPolicyLoader`, and `RedisPolicyStore` are specified in ADR-001 but have not yet been implemented (Phase 0 → Phase 1 migration).
