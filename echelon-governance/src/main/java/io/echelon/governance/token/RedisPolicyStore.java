package io.echelon.governance.token;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.data.redis.core.RedisTemplate;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

public class RedisPolicyStore implements PolicyStore {

    private final RedisTemplate<String, String> redis;
    private final String policyHashKey = "policies:active";
    private final ObjectMapper mapper = new ObjectMapper();

    // Cache for parsed policies, refreshed on each call
    // (policies are small — ~20 entries — so no need for complex caching)
    private List<DeonticToken.Permit> permitCache;
    private List<DeonticToken.Embargo> embargoCache;
    private List<DeonticToken.Burden> burdenCache;
    private long lastLoadTime = 0;
    private static final long CACHE_TTL_MS = 5000; // 5 second cache

    public RedisPolicyStore(RedisTemplate<String, String> redis) {
        this.redis = redis;
    }

    private void ensureLoaded() {
        long now = System.currentTimeMillis();
        if (now - lastLoadTime < CACHE_TTL_MS && permitCache != null) {
            return; // Cache is fresh
        }
        loadFromRedis();
        lastLoadTime = now;
    }

    private void loadFromRedis() {
        var raw = redis.opsForHash().entries(policyHashKey);
        if (raw.isEmpty()) {
            permitCache = List.of();
            embargoCache = List.of();
            burdenCache = List.of();
            return;
        }

        permitCache = raw.entrySet().stream()
            .filter(e -> e.getKey().toString().startsWith("permit:"))
            .map(e -> parsePermit(e.getKey().toString(), e.getValue().toString()))
            .collect(Collectors.toList());

        embargoCache = raw.entrySet().stream()
            .filter(e -> e.getKey().toString().startsWith("embargo:"))
            .map(e -> parseEmbargo(e.getKey().toString(), e.getValue().toString()))
            .collect(Collectors.toList());

        burdenCache = raw.entrySet().stream()
            .filter(e -> e.getKey().toString().startsWith("burden:"))
            .map(e -> parseBurden(e.getKey().toString(), e.getValue().toString()))
            .collect(Collectors.toList());
    }

    private DeonticToken.Permit parsePermit(String key, String value) {
        var parts = key.split(":");
        var action = parts.length > 1 ? parts[1] : value;
        return new DeonticToken.Permit(action, Set.of("default"), "redis", "Hot-reloaded from Redis", Instant.now());
    }

    private DeonticToken.Embargo parseEmbargo(String key, String value) {
        var parts = key.split(":");
        var action = parts.length > 1 ? parts[1] : value;
        return new DeonticToken.Embargo(action, Set.of("default"), "redis", "Hot-reloaded from Redis", Instant.now());
    }

    private DeonticToken.Burden parseBurden(String key, String value) {
        var parts = key.split(":");
        var action = parts.length > 1 ? parts[1] : value;
        return new DeonticToken.Burden(action, Set.of("default"), "redis", "Hot-reloaded", Instant.now());
    }

    @Override public List<DeonticToken.Permit> getPermits(String role) {
        ensureLoaded();
        return permitCache;
    }
    @Override public List<DeonticToken.Embargo> getEmbargoes(String role) {
        ensureLoaded();
        return embargoCache;
    }
    @Override public List<DeonticToken.Burden> getBurdens(String role) {
        ensureLoaded();
        return burdenCache;
    }

    // Force refresh — called by admin endpoint or polling
    public void refresh() {
        lastLoadTime = 0;
        ensureLoaded();
    }
}
