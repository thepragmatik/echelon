# Deontic Governance Synthesis — Literature Review

**Author:** Echelon Research
**Date:** July 2026
**Status:** Draft — cross-referenced against gap-analysis.md
**Scope:** Deontic token model, cost-aware routing, zero-trust security, EU regulatory compliance, runtime policy enforcement

---

## 1. Core Design Pattern — ODP-EL Deontic Tokens

**Source:** [P1] Milosevic & Rabhi — *Architecting Agentic Communities using Design Patterns* (arXiv:2601.03624)
**URL:** https://arxiv.org/abs/2601.03624

| Element | Description | Echelon Mapping |
|---------|-------------|-----------------|
| **Burden** (obligation) | Agent MUST perform action X | e.g., `burden(compile_before_commit, BuildManager)` |
| **Permit** (permission) | Agent MAY perform action X | e.g., `permit(write_source, Implementer)` |
| **Embargo** (prohibition) | Agent MUST NOT perform action X | e.g., `embargo(write_to_main, ALL_AGENTS)` |

**Key contributions to Echelon:**
- Sealed `DeonticToken` interface pattern (§6, Figure 7) — the three token types form a closed set, enabling exhaustive pattern matching in Java 21 sealed classes
- Five governance-relevant patterns from the 46-pattern catalogue: Compliance/Governance (#18), Access Control (#19), Audit Trail (#20), Composable DSLs (#44), Federated Privacy (#46)
- Formal proofs verified on a clinical trial system: safety, authority, prohibition, and accountability properties all verifiable at runtime
- **Cited in gap-analysis.md §4.5** — deontic permission model identified as critical dependency for all task dispatch (Gate 0)

**Caveat:** Formal verification requires model-checking infrastructure not planned for Phase 1. Phase 1 implements runtime enforcement only; formal verification is Phase 3+.

---

## 2. Cost Optimization — Budget-Aware Agent Routing

**Source:** [R4] NiteAgent — *AI Agent Cost Optimization in 2026*
**URL:** https://www.niteagent.com/blog/ai-agent-cost-optimization-2026

| Statistic | Value | Risk |
|-----------|-------|------|
| LLM API = % of operating cost | 70–85% | Unbounded spend |
| Agentic LLM calls per task | 10–20 | Multiplier vs chatbot |
| Enterprises exceeding cost projections | 96% | Systemic |
| Real runaway incident | $47K (2 agents, 11 days) | Critical |
| Monthly spend per engineer | $200–$2,000+ | Variable |

**Key contributions to Echelon:**
- Per-task token caps as primary cost control mechanism — implemented in `BudgetManager` (currently in-memory, ADR-002 proposes Redis persistence)
- Per-agent monthly spend limits with alerting at 50%/80%/100%
- Model routing to cheaper models when budget is exceeded
- Agent-side budget awareness: surface remaining tokens in task context so the LLM can self-regulate
- **Cited in gap-analysis.md §4.6, §8** — token budget governance rated P0

**Source:** [R5] AI Workflow Lab — *LLM Cost Optimization: Save Up to 88%*
**URL:** https://www.aiworkflowlab.com/blog/llm-cost-optimization

| Layer | Savings | Echelon Status |
|-------|---------|----------------|
| Semantic caching (Redis) | 60–88% | 🔴 Not implemented (requires ADR-002 Redis persistence) |
| Model routing | 70–80% | 🟡 Partial (MCP Server manual tiering only) |
| Prompt caching | 90% on cached inputs | 🔴 Not implemented |
| Batch processing | 20–40% | 🔴 Not implemented |

**Caveat:** Semantic caching is high-effort (embedding generation, similarity search) and blocked on ADR-002 (Redis persistence for cost data). Phase 2 target.

---

## 3. Zero-Trust Security — Multi-Agent Systems

**Source:** [P4] Schroeder de Witt et al. — *Open Challenges in Multi-Agent Security* (arXiv:2505.02077)
**URL:** https://arxiv.org/abs/2505.02077

| Threat | Vector | Echelon Mitigation |
|--------|--------|-------------------|
| Secret collusion | Two agents communicate steganographically | Container isolation prevents network-level coordination |
| Swarm jailbreaks | One compromised agent infects others via shared context | Deontic tokens restrict permitted actions per role |
| Prompt injection hijack | Malicious input redirects agent behaviour | Seccomp + filesystem allowlisting + network default-deny |
| Data exfiltration | Agent reads sensitive files, sends externally | Read-only mounts + Privacy Router as only egress |

**Key contributions to Echelon:**
- Zero-trust architecture: every inter-container interaction must be authenticated via deontic token validation
- Container isolation is the baseline; seccomp + filesystem allowlisting + network default-deny stack for defence-in-depth
- Privacy Router as credential proxy: agents never hold their own API keys
- **Cited in gap-analysis.md §4.2, §4.7–4.10** — security hardening stack spans 5 gap items

---

## 4. EU Regulatory Compliance

**Source:** [R6] *Regulating autonomous AI: A comprehensive analysis of the EU AI Act's framework for autonomous AI systems* (arXiv:2607.21345)
**URL:** https://arxiv.org/abs/2607.21345

| EU AI Act Requirement | Echelon Mapping | Gap |
|-----------------------|-----------------|-----|
| Risk classification | Tiered agent roles with bounded capabilities | 🟡 Roles defined in policy but no formal risk tiering |
| Human oversight (Art. 14) | Human release gate on production deployments | 🔴 Gate not implemented (G-03) |
| Transparency obligations | Audit trail for every agent action | 🔴 Streams defined but audit wiring incomplete |
| Technical documentation | ADR series + architecture docs | 🟡 ADR-001/002 being written |
| Record-keeping (Art. 12) | Redis append-only streams for all governance events | 🔴 Stream definitions exist, producer code missing |
| Conformity assessment | Formal verification of deontic policy safety properties | 🔴 Phase 3+ |

**Key contributions to Echelon:**
- EU AI Act is the primary regulatory driver for the deontic governance model
- Burden/Permit/Embargo tokens map directly to auditability requirements (Art. 12)
- Human-in-the-loop gate (G-03) addresses Art. 14 oversight requirement
- Price-of-Anarchy (PoA) analysis from the paper (§4) validates hierarchical coordination over flat architectures

---

## 5. Real-Time Deontic Logic — Runtime Governance

**Source:** [P6] *Deontic Policies for Runtime Governance of Agentic AI Systems* (arXiv:2606.19464)
**URL:** https://arxiv.org/abs/2606.19464

| Concept | Description | Echelon Application |
|---------|-------------|---------------------|
| Runtime policy evaluation | Evaluate deontic constraints at action-dispatch time | `BuildManager.permit()` — currently returns `true` (no governance) |
| Policy conflict resolution | Embargo overrides Permit; Burden adds obligations on top of Permit | Priority chain: Embargo > Burden > Permit |
| Temporal deontic logic | Obligations with time bounds (e.g., "must respond within 5s") | Phase 3 — not yet modelled |
| Dynamic policy updates | Policies changeable without restarting agents | Phase 3 — OpenShell aspirational pattern |

**Key contributions to Echelon:**
- Provides the formal semantics for the sealed `DeonticToken` interface — embargoes supersede permits, burdens add obligations
- Real-time policy evaluation at action granularity (not just at task dispatch)
- Policy conflict resolution rules directly inform `PolicyEngine` design in ADR-001
- **Cited in gap-analysis.md §4.5** — token registry and runtime evaluation are the two missing sub-components

---

## 6. Cross-Cutting Synthesis — Research Consensus Map

| Concern | Papers | Echelon Gap | Priority |
|---------|--------|-------------|----------|
| Deontic token model | [P1], [P6] | 🔴 No sealed interface (ADR-001) | P0 — Gate 0 |
| Cost governance | [R4], [R5] | 🔴 In-memory only (ADR-002) | P0 — before first live task |
| Zero-trust isolation | [P4] | 🔴 No seccomp/network/fs hardening | P1 — Phase 1 |
| EU AI Act compliance | [R6] | 🟡 Design exists, implementation missing | P2 — Phase 2 |
| Runtime policy engine | [P6] | 🔴 No PolicyEngine class | P1 — blocks all dispatch |
| Semantic caching | [R5] | 🔴 Not designed | P2 — Phase 2 |
| Formal verification | [P1] | ⭕ Not researched | P3 — Phase 3+ |

---

## References

| ID | Citation | URL |
|----|----------|-----|
| [P1] | Milosevic, Z., & Rabhi, F. "Architecting Agentic Communities using Design Patterns." arXiv:2601.03624. | https://arxiv.org/abs/2601.03624 |
| [P4] | Schroeder de Witt, S., et al. "Open Challenges in Multi-Agent Security." arXiv:2505.02077. | https://arxiv.org/abs/2505.02077 |
| [P6] | "Deontic Policies for Runtime Governance of Agentic AI Systems." arXiv:2606.19464. | https://arxiv.org/abs/2606.19464 |
| [R4] | NiteAgent. "AI Agent Cost Optimization in 2026." | https://www.niteagent.com/blog/ai-agent-cost-optimization-2026 |
| [R5] | AI Workflow Lab. "LLM Cost Optimization: Save Up to 88%." | https://www.aiworkflowlab.com/blog/llm-cost-optimization |
| [R6] | "Regulating autonomous AI: EU AI Act framework." arXiv:2607.21345. | https://arxiv.org/abs/2607.21345 |
