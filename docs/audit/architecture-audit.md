# Architecture Audit Report

**Issue:** #167 — Java Code Audit + HAProxy Security Review  
**Date:** 2026-07-28  
**Auditor:** hswarm-rsrch  
**Scope:** echelon-governance, echelon-orchestrator, echelon-docker/haproxy.cfg  

---

## Findings Summary

| # | File | Issue | Severity | Recommendation |
|---|------|-------|----------|----------------|
| 1 | `RedisPolicyStore.java` | Thread safety — shared mutable cache fields without synchronization | **HIGH** | Guard `permitCache`/`embargoCache`/`burdenCache`/`lastLoadTime` with `synchronized` or `ReentrantReadWriteLock` |
| 2 | `haproxy.cfg` | `ssl-server-verify none` globally + backend `ssl verify none` | **HIGH** | Enable server cert verification (`ssl verify required`); provide CA bundle |
| 3 | `haproxy.cfg` | Frontend `bind *:8080` — no TLS termination | **HIGH** | Add TLS listener on port 443 with cert; redirect HTTP to HTTPS |
| 4 | `haproxy.cfg` | Stats endpoint `/health` with no auth | **HIGH** | Add `stats auth user:password` or `http-request auth` |
| 5 | `haproxy.cfg` | No rate limiting configured | **MEDIUM** | Add `stick-table` + `http-request track-sc` rules |
| 6 | `haproxy.cfg` | No CORS headers on responses | **MEDIUM** | Add `http-response set-header Access-Control-Allow-Origin *` if browser clients are expected |
| 7 | `PolicyEngine.java` | `refreshPolicies()` uses `instanceof` + downcast to `RedisPolicyStore` | **MEDIUM** | Add `refresh()` to `PolicyStore` interface; call polymorphically |
| 8 | `TaskStreamService.java` | God object — stream ops, state management, locking, heartbeat, audit | **MEDIUM** | Split into `TaskStreamService`, `LockService`, `HeartbeatService` |
| 9 | `AuditService.java` | Swallowed exception — audit failure silently degraded to WARN log | **MEDIUM** | Propagate or allow caller-configured failure mode; consider circuit breaker |
| 10 | `CostTracker.java` | Swallowed exception — `totalCost()` returns 0.0 on error | **MEDIUM** | Return `Optional<Double>` or throw specific checked exception |
| 11 | `SkillDefinition.java` | Swallowed exception — JSON serialization failures silently produce empty strings | **MEDIUM** | Throw `IllegalArgumentException` on parse failure; log at ERROR level |
| 12 | `SemanticCacheService.java` | YAGNI — `isSimilar()` method ignores embedding parameter, duplicates `has()` | **LOW** | Remove unused `isSimilar()` method |
| 13 | `YamlPolicyLoader.java` | YAGNI — `loadedAt` field stored but never exposed | **LOW** | Remove unused field or expose via public getter |
| 14 | `RedisPolicyStore.java` | `parsePermit`/`parseEmbargo`/`parseBurden` ignore Redis value, hardcode role to `"default"` | **MEDIUM** | Parse role/resource from value or extended key format |
| 15 | `YamlPolicyLoader.java` | Raw `Map.class` usage and unchecked casts in constructor | **LOW** | Add proper generics or use Jackson `TypeReference` |
| 16 | `ReviewManager.java` | ProcessBuilder creates shell subprocess with string interpolation | **MEDIUM** | Use `ProcessBuilder` with individual args to avoid shell injection; validate `prUrl` |
| 17 | `haproxy.cfg` | `timeout client 50000ms` / `timeout server 50000ms` — long timeouts | **LOW** | Reduce to 10-30s or configure per-backend timeouts |
| 18 | `haproxy.cfg` | No `maxconn` per frontend; global `maxconn 256` | **LOW** | Add per-frontend `maxconn` for finer-grained limits |
| 19 | `CacheService.java` / `SemanticCacheService.java` | Nearly identical `ConcurrentHashMap` wrappers with no shared interface | **LOW** | Introduce `Cache` interface or unify into a single class |

---

## Section 3.2: Java Code Audit Findings

### 1. Thread Safety Issues

#### Finding F1: `RedisPolicyStore` — Unsychronized Shared Mutable State

**File:** `echelon-governance/src/main/java/io/echelon/governance/token/RedisPolicyStore.java`  
**Lines:** 17–22 (fields), 28–35 (`ensureLoaded()`), 87–102 (getters)  

```java
private List<DeonticToken.Permit> permitCache;       // line 18
private List<DeonticToken.Embargo> embargoCache;      // line 19
private List<DeonticToken.Burden> burdenCache;        // line 20
private long lastLoadTime = 0;                        // line 21
```

The four mutable fields above are read and written from `ensureLoaded()` and `loadFromRedis()` without any synchronization. The `RedisPolicyStore` is a singleton bean — multiple threads calling `getPermits()`, `getEmbargoes()`, or `getBurdens()` concurrently can:

- Both see a stale `lastLoadTime` and skip reload when they should reload
- Both trigger `loadFromRedis()` simultaneously, doing redundant Redis work
- See **partially updated state** where one cache list is replaced but another is still stale (non-atomic update of three fields)

**Severity:** HIGH — can cause stale policy enforcement (allowing denied actions or denying allowed ones) and race conditions under concurrent load.

**Recommendation:** Guard the four fields with a `ReentrantReadWriteLock` — readers acquire read lock, `loadFromRedis()` acquires write lock. Alternatively, use `AtomicLong` for `lastLoadTime` and atomically swap immutable copies of the caches.

---

### 2. Swallowed Exceptions

#### Finding F2: `AuditService.log()` — Audit Failure Hidden

**File:** `echelon-orchestrator/src/main/java/io/echelon/orchestrator/service/AuditService.java`  
**Lines:** 37–39

```java
} catch (Exception e) {
    log.warn("Audit log failed: {}", e.getMessage());
}
```

An audit-log failure is silently degraded to a WARN-level message. The caller receives no indication that auditing is down — a critical gap for security and compliance.

**Severity:** MEDIUM — subtle operational blindness.

**Recommendation:** Let `log()` throw a runtime exception (e.g., `AuditException`) when the backing store is unavailable, or wire a circuit breaker so the caller can observe audit health. At minimum, log at ERROR with full stack trace.

---

#### Finding F3: `CostTracker.totalCost()` — Error Swallowed

**File:** `echelon-governance/src/main/java/io/echelon/governance/CostTracker.java`  
**Lines:** 35–41

```java
} catch (Exception e) {
    return 0.0;
}
```

Returns `0.0` on any error — callers can't distinguish "no cost data" from "Redis is down."

**Severity:** MEDIUM

**Recommendation:** Return `Optional<Double>` or throw an explicit exception.

---

#### Finding F4: `SkillDefinition` — JSON Failures Silently Ignored

**File:** `echelon-governance/src/main/java/io/echelon/governance/skills/SkillDefinition.java`  
**Lines:** 30–31 (`toMap()`) and 49–50 (`fromMap()`)

Both methods silently return empty results on JSON parsing failure. Corrupted skill data in Redis would be invisible.

**Severity:** MEDIUM

**Recommendation:** Log at ERROR with full stack trace; throw `IllegalArgumentException` to surface corrupt data.

---

#### Finding F5: Poll Cycles — Exceptions Degraded to WARN

**Files:**
- `BuildManager.java` line 51–53
- `ReviewManager.java` line 45–47

```java
} catch (Exception e) {
    log.warn("Poll cycle error: {}", e.getMessage());
}
```

Both managers catch all exceptions during polling and only log the message. Full stack trace is lost. The record is not acknowledged, which may lead to re-delivery loops.

**Severity:** MEDIUM

**Recommendation:** Log full stack trace on first occurrence; consider circuit breaker to back off on repeated errors.

---

### 3. Missing Interfaces / Tight Coupling

#### Finding F6: `PolicyEngine.refreshPolicies()` — `instanceof` Downcast

**File:** `echelon-governance/src/main/java/io/echelon/governance/token/PolicyEngine.java`  
**Lines:** 44–47

```java
public void refreshPolicies() {
    if (policyStore instanceof RedisPolicyStore) {
        ((RedisPolicyStore) policyStore).refresh();
    }
}
```

The `refresh()` method exists only on `RedisPolicyStore`, not on the `PolicyStore` interface. The `PolicyEngine` must check types and downcast — a clear violation of the Liskov Substitution Principle.

**Severity:** MEDIUM — adding a new `PolicyStore` implementation requires modifying `PolicyEngine`.

**Recommendation:** Add `default void refresh() {}` to the `PolicyStore` interface. `RedisPolicyStore` overrides it; `YamlPolicyLoader` gets the no-op default.

---

#### Finding F7: `TaskStreamService` — God Object

**File:** `echelon-orchestrator/src/main/java/io/echelon/orchestrator/service/TaskStreamService.java`  
**Responsibilities:**  
- Stream push/read/acknowledge
- Task state CRUD (`updateTaskState`, `getTaskState`)
- Distributed locking (`acquireLock`, `releaseLock`)
- Agent heartbeat (`heartbeat`)
- Audit logging (via injected `AuditService`)

**Severity:** MEDIUM — violates Single Responsibility Principle; hard to test, mock, or evolve independently.

**Recommendation:** Extract:
- `TaskStreamService` — pure Redis stream operations
- `TaskStateService` (exists but underused — `TaskStreamService` duplicates state logic)
- `LockService` — distributed lock operations
- `HeartbeatService` — agent heartbeat

---

### 4. YAGNI Violations

#### Finding F8: `SemanticCacheService.isSimilar()` — Unused Parameter

**File:** `echelon-orchestrator/src/main/java/io/echelon/orchestrator/service/SemanticCacheService.java`  
**Lines:** 23–25

```java
public boolean isSimilar(String embedding, String key) {
    return cache.containsKey(key) && embedding != null;
}
```

The `embedding` parameter is never used in the body beyond a null check. The method behaves identically to `has()` with an extra no-op null check.

**Severity:** LOW

**Recommendation:** Remove `isSimilar()` if unused, or implement actual semantic similarity comparison if the feature is planned.

---

#### Finding F9: `YamlPolicyLoader.loadedAt` — Dead Store

**File:** `echelon-governance/src/main/java/io/echelon/governance/token/YamlPolicyLoader.java`  
**Line:** 14

```java
private final Instant loadedAt = Instant.now();
```

This field is set once in the constructor and never read or exposed anywhere.

**Severity:** LOW

**Recommendation:** Remove or expose via a `getLoadedAt()` method if the metadata is useful for monitoring.

---

### 5. God Objects

#### Finding F10: `TaskStreamService` (see Finding F7 above)

#### Finding F11: `RedisPolicyStore` — Cache Logic + Policy Parsing + Redis I/O

**File:** `echelon-governance/src/main/java/io/echelon/governance/token/RedisPolicyStore.java` (109 lines)

Combines: Redis hash operations, key parsing (`permit:`/`embargo:`/`burden:` prefix logic), caching with TTL, and policy materialization. Hard to unit test without Redis.

**Severity:** LOW-MEDIUM

**Recommendation:** Extract policy parsing into a separate `PolicyParser` class; keep `RedisPolicyStore` as a thin data access layer.

---

### 6. Overly Complex Methods

No method in the audited codebase exceeds 50 lines. The longest methods are:

- `ReviewManager.processReview()` — ~44 lines (under threshold)
- `RedisPolicyStore.loadFromRedis()` — ~26 lines
- `YamlPolicyLoader` constructor — ~20 lines

**Verdict:** No complexity violations found.

---

### 7. Additional Findings

#### Finding F12: `ReviewManager.runReviewer()` — Shell Injection Risk

**File:** `echelon-orchestrator/src/main/java/io/echelon/orchestrator/manager/ReviewManager.java`  
**Lines:** 106–127

```java
var proc = new ProcessBuilder(
    "bash", "-c",
    String.format("echelon-workers/src/main/resources/scripts/reviewer.sh %s %s", prNum, role))
    .start();
```

The `prNum` is extracted from `prUrl` via regex (`prUrl.replaceAll(".*/pull/(\\d+).*", "$1")`), which limits injection risk. However, `role` comes directly from the code (List.of("adversarial", "quality")) so is safe today. The pattern is fragile — any future change to pass user-controlled values through this codepath creates a shell injection vector.

**Severity:** MEDIUM (latent)

**Recommendation:** Use `new ProcessBuilder("bash", "echelon-workers/.../reviewer.sh", prNum, role)` — no shell wrapping, each arg is passed separately to the process.

---

#### Finding F13: `RedisPolicyStore` — Hot-Reloaded Policies Lose Role Data

**File:** `echelon-governance/src/main/java/io/echelon/governance/token/RedisPolicyStore.java`  
**Lines:** 65–83

All three `parse*` methods hardcode `Set.of("default")` for roles and ignore the actual Redis value. Hot-reloaded policies via the admin endpoint will have their role assignments lost.

**Severity:** MEDIUM — hot-reload feature is effectively broken for role-scoped policies.

**Recommendation:** Encode role in the Redis hash key (e.g., `permit:<role>:<action>`) or parse a JSON/structured value from the hash entry.

---

## Section 3.4: HAProxy Security Audit

**File:** `echelon-docker/haproxy.cfg` (60 lines)

### Current Configuration Summary

```haproxy
global
  daemon
  maxconn 256
  ssl-server-verify none

defaults
  mode http
  timeout connect 5000ms
  timeout client 50000ms
  timeout server 50000ms

frontend llm-proxy
  bind *:8080
  stats enable
  stats uri /health
  stats hide-version
  stats realm "Echelon Privacy Router"
  ... ACLs for role-based routing ...
  use_backend deepseek if { path_beg /v1/chat/completions } { hdr(X-Provider) -i deepseek }
  use_backend glm if ...
  default_backend deepseek

backend deepseek
  server api api.deepseek.com:443 ssl verify none

backend glm
  server api pass.wafer.ai:443 ssl verify none
```

### Findings

#### Finding H1: TLS Server Verification Disabled (HIGH)

**Lines:** 4 (global), 57, 60 (backends)

```haproxy
ssl-server-verify none               # global — disables for ALL backends
server api api.deepseek.com:443 ssl verify none   # per-server override
server api pass.wafer.ai:443 ssl verify none       # per-server override
```

HAProxy will connect to backend LLM providers without verifying their TLS certificates. This permits man-in-the-middle attacks between HAProxy and the upstream API.

**Recommendation:** Remove `ssl-server-verify none` from global. Set `ssl verify required` with an explicit CA file (`ca-file /etc/ssl/certs/ca-certificates.crt`) on each backend server line.

---

#### Finding H2: No TLS on Frontend (HIGH)

**Line:** 13

```haproxy
bind *:8080
```

All traffic between clients and HAProxy is plain HTTP. API keys, tokens, and prompts are transmitted in cleartext.

**Recommendation:** Add a TLS listener:

```haproxy
bind *:443 ssl crt /etc/haproxy/certs/echelon.pem
bind *:8080  # HTTP redirect -> HTTPS
http-request redirect scheme https if !{ ssl_fc }
```

---

#### Finding H3: Stats Endpoint Exposed Without Auth (HIGH)

**Lines:** 14–17

```haproxy
stats enable
stats uri /health
stats hide-version
stats realm "Echelon Privacy Router"
```

The `/health` endpoint exposes HAProxy statistics with no authentication. While the intent may have been a health check, `stats enable` exposes connection counts, backend status, and cluster topology.

**Recommendation:** Either (a) add `stats auth admin:<strong-password>`, or (b) replace `stats enable` with a dedicated health check listener or use `monitor-uri` for health probes instead:

```haproxy
frontend health
  bind *:8404
  monitor-uri /health
```

---

#### Finding H4: No Rate Limiting (MEDIUM)

No `stick-table`, `http-request track-sc`, or rate-limit directives exist anywhere in the configuration. An attacker can flood the proxy with requests, exhausting the 256-connection pool and causing denial of service to legitimate clients.

**Recommendation:** Add a stick-table with per-IP rate limiting:

```haproxy
frontend llm-proxy
  stick-table type ip size 10k expire 30s store http_req_rate(10s)
  http-request track-sc0 src
  http-request deny deny_status 429 content-type "application/json" \
    string '{"error":"rate_limited"}' if { sc_http_req_rate(0) gt 100 }
```

---

#### Finding H5: No CORS Headers (MEDIUM)

If browser-based clients (e.g., web UIs, dashboard) consume this proxy, cross-origin requests will be blocked. No `Access-Control-Allow-Origin` headers are set.

**Recommendation:** If browser clients are expected:

```haproxy
http-response set-header Access-Control-Allow-Origin "*"
http-response set-header Access-Control-Allow-Methods "GET, POST, OPTIONS"
http-response set-header Access-Control-Allow-Headers "Content-Type, Authorization, X-Echelon-Role, X-Echelon-Action, X-Provider"
```

---

#### Finding H6: No Request Size Limits (MEDIUM)

No `http-request deny` for oversized payloads. An attacker could POST extremely large prompts, consuming memory and triggering resource exhaustion.

**Recommendation:**

```haproxy
http-request deny deny_status 413 content-type "application/json" \
  string '{"error":"payload_too_large"}' if { req_len gt 1000000 }
```

(Adjust limit based on actual max prompt size.)

---

#### Finding H7: Long Client/Server Timeouts (LOW)

**Lines:** 8–10

```haproxy
timeout client 50000ms
timeout server 50000ms
```

50-second timeouts are generous. Slowloris-style attacks can hold connections open for 50 seconds, consuming connection pool slots.

**Recommendation:** Reduce to 10–30 seconds, or set more aggressive timeouts per-backend. Add `timeout http-request 10s` to limit time-to-first-byte.

---

#### Finding H8: No Syslog / Structured Logging (LOW)

**Comment lines 19–20:**

```
# Logging — no syslog target configured
# Logging is handled by Docker container logs
```

Container stdout logs are ephemeral and not structured for security analysis. No audit trail for denied requests, policy violations, or other security events.

**Recommendation:** Configure `log` directive with a syslog endpoint; forward logs to a centralized logging solution for security monitoring.

---

## Overall Assessment

| Category | Severity Count |
|----------|----------------|
| **HIGH** | 4 (2 Java, 2 HAProxy) |
| **MEDIUM** | 8 (7 Java, 1 HAProxy) |
| **LOW** | 7 (5 Java, 2 HAProxy) |
| **Total** | 19 findings |

### Critical Path Recommendations

1. **Immediate:** Add TLS frontend + backend certificate verification in HAProxy (H1, H2)
2. **Immediate:** Secure or replace the HAProxy stats endpoint (H3)
3. **Immediate:** Fix thread safety in `RedisPolicyStore` (F1)
4. **Short-term:** Add `refresh()` to `PolicyStore` interface (F6), fix hot-reload role handling (F13)
5. **Short-term:** Address swallowed exceptions in audit and cost-tracking paths (F2, F3, F4)
6. **Medium-term:** Refactor `TaskStreamService` into focused services (F7/F10); harden process execution pattern (F12)
7. **Medium-term:** Add rate limiting, CORS, and request size limits to HAProxy (H4, H5, H6)
