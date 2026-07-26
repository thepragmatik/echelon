# ADR-002: Redis-Persistent Budget and Cost Tracking

**Status:** Proposed  
**Date:** July 2026  
**Deciders:** Echelon Architecture Team  
**References:** [R4] NiteAgent Cost Optimization; gap-analysis.md §§4.6, 8, C-01, C-02  

---

## Context

Echelon currently has two governance classes in `echelon-governance`:

- **`BudgetManager`** — in-memory `ConcurrentHashMap<String, Long>` storing per-task token budgets. Data is lost on JVM restart. Not shared across container instances.
- **`CostTracker`** — in-memory `CopyOnWriteArrayList<CostEntry>` storing cost records. No persistence, no querying across sessions, no aggregation.

```java
// Current — in-memory, no persistence
public class BudgetManager {
    private final ConcurrentHashMap<String, Long> budgets = new ConcurrentHashMap<>();
    // budgets lost on restart
}

public class CostTracker {
    private final List<CostEntry> entries = new CopyOnWriteArrayList<>();
    // entries lost on restart, no cross-instance visibility
}
```

**Problems:**
1. **No persistence** — restarting the echelon-orchestrator container resets all budget and cost data.
2. **No sharing across containers** — if multiple orchestrator instances run (horizontal scaling), each has its own budget state.
3. **No retention for auditing** — cost entries disappear when the JVM exits.
4. **No aggregate queries** — cannot ask "what was total spend last week?" without external logging.
5. **$47K runaway risk** — [R4] documents a real incident where two agents in an infinite loop burned $47K in 11 days without budget enforcement.

The gap-analysis.md (§4.6, item C-01/C-02) rates persistent cost tracking and token budget caps as **P0** — must exist before first live task.

---

## Decision

### 1. Redis-Persistent `BudgetManager`

Replace the in-memory `ConcurrentHashMap` with Redis Strings with TTL:

```java
@Service
public class BudgetManager {
    private final RedisTemplate<String, String> redis;

    private static final String KEY_PREFIX = "budget:task:";
    private static final long DEFAULT_CAP = 5000;  // tokens

    public boolean deduct(String taskId, long tokens) {
        String key = KEY_PREFIX + taskId;
        String remaining = redis.opsForValue().get(key);
        if (remaining == null) return false;  // no budget set → deny
        long rem = Long.parseLong(remaining);
        if (rem < tokens) return false;
        redis.opsForValue().set(key, String.valueOf(rem - tokens));
        return true;
    }

    public void setCap(String taskId, long cap, Duration ttl) {
        String key = KEY_PREFIX + taskId;
        redis.opsForValue().set(key, String.valueOf(cap), ttl);
    }

    public long remaining(String taskId) {
        String val = redis.opsForValue().get(KEY_PREFIX + taskId);
        return val == null ? 0 : Long.parseLong(val);
    }
}
```

**TTL strategy:** Task budgets expire after `max(30 min, 2 × expected task duration)`. This automatically cleans up budgets for completed or abandoned tasks.

### 2. Redis Streams for `CostTracker`

Replace the `CopyOnWriteArrayList` with Redis Streams:

```java
@Service
public class CostTracker {
    private final RedisTemplate<String, Object> redis;

    private static final String STREAM = "events:cost";

    public void record(CostEntry entry) {
        var map = Map.of(
            "taskId",       entry.taskId(),
            "agent",        entry.agent(),
            "model",        entry.model(),
            "tokens",       String.valueOf(entry.tokens()),
            "cost",         String.valueOf(entry.cost()),
            "timestamp",    entry.timestamp().toString()
        );
        redis.opsForStream().add(STREAM, map);
    }

    public List<CostEntry> byTask(String taskId) {
        // Read stream, filter by taskId
    }

    public double totalCost() {
        // Aggregate over stream entries
    }
}
```

**Why Redis Streams and not Redis Strings:**
- Append-only semantics match audit trail requirements (CSA Rule 2)
- Consumer groups enable separate consumers (e.g., a "cost aggregator" worker, an "alerting" worker, a "dashboard" consumer)
- Stream entries can have retention policies (`TRIM`) — keep cost data for 90 days, then trim
- No race conditions on concurrent writes (multiple agents recording costs simultaneously)

### 3. Stream Topology

| Stream | Key | Producer | Consumers | Retention |
|--------|-----|----------|-----------|-----------|
| `events:cost` | Cost entries per LLM call | Privacy Router / agents | Cost aggregator, alerting, dashboard | 90 days |
| `events:budget` | Budget cap changes | Build/Review Managers | Budget monitor | 30 days |
| `events:governance` | Deontic permit/deny decisions | PolicyEngine | Audit trail | Permanent |

### 4. Initialization

Redis Streams are created during `redis-init.sh` (item D-06 in gap-analysis):

```bash
#!/bin/sh
redis-cli XGROUP CREATE events:cost cost-aggregators $ MKSTREAM
redis-cli XGROUP CREATE events:cost alerting $ MKSTREAM
redis-cli XGROUP CREATE events:budget budget-monitor $ MKSTREAM
redis-cli XGROUP CREATE events:governance audit $ MKSTREAM
```

### 5. Migration Path

| Phase | BudgetManager | CostTracker |
|-------|--------------|-------------|
| **Phase 0 (current)** | In-memory `ConcurrentHashMap` | In-memory `CopyOnWriteArrayList` |
| **Phase 1 (this ADR)** | Redis Strings + TTL | Redis Streams |
| **Phase 2+** | Add Sentinel HA for Redis | Add stream consumer workers |

Phase 0 → Phase 1 is a drop-in replacement: the `BudgetManager` and `CostTracker` interfaces remain the same, only the backing store changes.

---

## Consequences

### Positive

1. **Persistent state across restarts** — budget and cost data survive container restarts.
2. **Shared across containers** — multiple orchestrator instances see the same budget and cost state.
3. **Immutable audit trail** — Redis Streams provide append-only semantics for cost events.
4. **Consumer group fan-out** — separate consumers for alerting, dashboards, and long-term storage can read the same stream independently.
5. **TTL-based cleanup** — abandoned task budgets expire automatically, preventing manual cleanup burden.
6. **Foundation for cost dashboards** — stream data feeds real-time spend visualizations.

### Negative

1. **Redis dependency** — if Redis is down, cost tracking and budget enforcement are unavailable. The system must fail-closed (deny all dispatch) when Redis is unavailable.
2. **Increased network round-trips** — every `deduct()` call now crosses the network instead of an in-memory HashMap. Expected latency: <1ms per call (local Redis), ~3-5ms (network Redis).
3. **Stream storage cost** — cost events accumulate. At 10-20 LLM calls per task and 1000 tasks/day, expect ~20K events/day. At ~200 bytes/event, ~4MB/day. Negligible.

### Neutral

1. **Existing `RedisConfig.java` already sets up `RedisTemplate`** — no new Spring configuration needed for connectivity.
2. **`redis-init.sh` must run before any service starts** — streams must exist before producers write to them.
3. **Stream trimming policy needs tuning** — 90-day retention is a starting estimate; adjust based on actual storage usage.

---

## Compliance

- **CSA Rule 2 (Immutable audit trails):** ✅ — Redis Streams are append-only by design.
- **CSA Rule 4 (HITL gates):** 🟡 — Budget overrides require HITL, but the override mechanism (G-03) is not yet implemented.
- **EU AI Act Art. 12 (Record-keeping):** ✅ — cost and governance streams provide auditable records.
- **Reference: gap-analysis.md §4.6 (C-01/C-02):** ✅ — directly addresses "no cost tracking" and "no budget enforcement" gaps.

---

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| PostgreSQL for cost tracking | Heavier dependency for what is fundamentally a stream-of-events workload; Redis Streams are purpose-built |
| Kafka for cost events | Overkill for a single-node dev/test deployment; Redis Streams provide consumer groups with simpler operations |
| In-memory with periodic snapshots to disk | Cross-instance sharing still broken; snapshot recovery adds complexity without solving the multi-container problem |
| Prometheus/OpenTelemetry metrics | Good for dashboards, but not for per-task budget enforcement (need read-modify-write atomicity) |
