package io.echelon.orchestrator.service;
import org.springframework.stereotype.Service;
import java.util.concurrent.ConcurrentHashMap;
@Service
public class CacheService {
    private final ConcurrentHashMap<String, String> cache = new ConcurrentHashMap<>();
    public String get(String key) { return cache.get(key); }
    public void put(String key, String value) { cache.put(key, value); }
    public boolean has(String key) { return cache.containsKey(key); }
    public void clear() { cache.clear(); }
}
