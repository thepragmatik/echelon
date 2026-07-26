# ADR-001: DeonticToken Sealed Interface for Agent Governance

**Status:** Proposed  
**Date:** July 2026  
**Deciders:** Echelon Architecture Team  
**References:** [P1] Milosevic & Rabhi, arXiv:2601.03624; [P6] Deontic Policies, arXiv:2606.19464; gap-analysis.md §§4.5, 6.1  

---

## Context

Echelon orchestrates multiple agent roles (implementer, reviewer, architect, orchestrator) that perform actions on a shared codebase. Without a governance model, any agent can perform any action — violating the zero-trust principle (CSA Rule 3, [R1]) and the ODP-EL deontic pattern (Access Control #19, [P1]).

**Current state:** `BuildManager.permit()` unconditionally returns `true` (line 82–84 of `BuildManager.java`). There is no permission check, no embargo enforcement, and no obligation tracking anywhere in the codebase.

```
// Current — no governance
boolean permit(String action, String role) {
    return true;
}
```

The gap-analysis.md (§4.5) rates the deontic permission model as **P0 — must exist before any task dispatch** (Gate 0). Without it, agents have unbounded authority: an implementer could write to `main`, an orchestrator could modify source code, and a reviewer could merge without approval.

**Design problem:** How do we represent agent permissions, prohibitions, and obligations in the Java type system so that the compiler enforces exhaustive handling of all three modalities, and a `PolicyEngine` can evaluate them at task-dispatch time?

---

## Decision

### 1. Sealed `DeonticToken` Interface

Introduce a sealed interface in the `io.echelon.governance` package:

```java
public sealed interface DeonticToken
    permits Permit, Embargo, Burden {}

public record Permit(String action, Set<String> roles) implements DeonticToken {}
public record Embargo(String action, Set<String> roles) implements DeonticToken {}
public record Burden(String action, Set<String> roles, List<String> obligations) implements DeonticToken {}
```

**Rationale for sealed:** Java 21 sealed classes enable exhaustive `switch`/`pattern matching` — the compiler rejects any switch that doesn't handle all three token types. This prevents a new modality from being added without updating every evaluation point.

**Rationale for records:** Immutable value semantics — tokens are loaded once from YAML at startup and never mutated.

### 2. `PolicyEngine` — Runtime Evaluation

```java
@Service
public class PolicyEngine {
    private List<DeonticToken> tokens;

    @PostConstruct
    public void loadPolicies() {
        // Parse agent-types.yaml → List<DeonticToken>
    }

    /**
     * Evaluate whether role can perform action.
     * Priority chain: Embargo > Burden > Permit
     * Default-deny: anything not explicitly permitted is denied.
     */
    public PolicyResult evaluate(String role, String action) {
        // 1. If any Embargo matches → DENIED
        // 2. If no Permit matches → DENIED (default-deny)
        // 3. If any Burden matches → add obligations
        // 4. Return GRANTED [with obligations list]
    }
}

public record PolicyResult(
    Decision decision,
    List<String> obligations  // non-empty if any Burden matched
) {
    public enum Decision { GRANTED, DENIED }
}
```

### 3. Integration with `BuildManager`

The stub `BuildManager.permit()` is replaced with a real call to `PolicyEngine.evaluate()`:

```java
@Service
public class BuildManager {
    private final PolicyEngine policyEngine;

    boolean permit(String action, String role) {
        var result = policyEngine.evaluate(role, action);
        if (result.decision() != PolicyResult.Decision.GRANTED) {
            audit.log("permit_denied", Map.of("action", action, "role", role));
            return false;
        }
        // Execute obligations (e.g., log, require approval)
        result.obligations().forEach(o -> ...);
        return true;
    }
}
```

### 4. Policy Source — YAML Configuration

Policies are loaded from `echelon-governance/src/main/resources/policies/agent-types.yaml` at application startup. The YAML schema (defined in ADR-001 companion document `agent-types.yaml`) maps agent roles to their three deontic modalities.

---

## Consequences

### Positive

1. **Default-deny security model** — any action not explicitly permitted is denied. Eliminates the class of vulnerabilities where an agent performs an unexpected action.
2. **Compile-time exhaustiveness** — sealed interface ensures all three token types are handled in every evaluation context.
3. **Audit trail** — every permit decision is logged, including denials (immutable stream in Redis).
4. **Policy-as-code** — YAML policies live in Git, version-controlled, reviewed via PR.
5. **Obligation enforcement** — burdens allow attaching side-effects (logging, approval gates) to permits.

### Negative

1. **Startup dependency** — application will not start if `agent-types.yaml` is missing or malformed (intentional: fail-fast on policy errors).
2. **No hot-reload** — Phase 1 loads policies at startup only. Dynamic policy updates require restart or OpenShell-style hot-reload (Phase 3+).
3. **No formal verification** — runtime checks only. Formal safety properties (e.g., "no agent can bypass all checks") are Phase 3+.

### Neutral

1. **Policy schema churn expected** — initial `agent-types.yaml` defines four roles (implementer, reviewer, architect, orchestrator). New roles will be added.
2. **YAML parsing cost** — negligible (single parse at startup, ~200 lines).

---

## Compliance

- **ODP-EL pattern #18 (Compliance/Governance):** ✅ — three-token sealed interface matches [P1] Figure 7.
- **CSA Rule 3 (Permission boundaries):** ✅ — default-deny with explicit permit list.
- **CSA Rule 2 (Immutable audit trails):** 🟡 — permit decisions logged, but audit stream wiring (G-02) still missing.
- **EU AI Act Art. 12 (Record-keeping):** 🟡 — deontic evaluations logged, but full record-keeping requires completion of audit infrastructure.
- **Reference: gap-analysis.md §§4.5, 6.1 (G-01):** ✅ — addresses the "no permission model" gap.

---

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Spring Security annotations (`@PreAuthorize`) | Annotations on every method don't scale to dynamic actions (agent actions are determined at runtime, not compile-time) |
| OAuth2/RBAC with JWT tokens | Heavyweight for in-process agent governance; JWT verification adds latency to every action |
| Unsealed interface with enum discriminator | Loses compile-time exhaustiveness checking — a new modality could be added without updating evaluation code |
| Hard-coded permission matrix in Java | Not policy-as-code; changes require recompilation and redeployment |
