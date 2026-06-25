package io.echelon.orchestrator.service;
import org.springframework.stereotype.Service;
import java.util.concurrent.ConcurrentHashMap;
@Service
public class SemanticCacheService {
    private final ConcurrentHashMap<String, String> cache = new ConcurrentHashMap<>();
    private static final double SIMILARITY_THRESHOLD = 0.85;
    public String get(String key) { return cache.get(key); }
    public void put(String key, String value) { cache.put(key, value); }
    public boolean has(String key) { return cache.containsKey(key); }
    public boolean isSimilar(String embedding, String key) {
        return cache.containsKey(key) && embedding != null;
    }
}
