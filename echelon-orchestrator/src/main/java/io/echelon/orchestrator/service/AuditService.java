package io.echelon.orchestrator.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.stream.ObjectRecord;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

@Service
public class AuditService {

    private static final Logger log = LoggerFactory.getLogger(AuditService.class);
    private static final String AUDIT_STREAM = "audit:orchestrator";

    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    public AuditService(RedisTemplate<String, Object> redisTemplate, ObjectMapper objectMapper) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
    }

    public void log(String action, Map<String, String> details) {
        var entry = new HashMap<>();
        entry.put("action", action);
        entry.put("timestamp", Instant.now().toString());
        entry.putAll(details);

        try {
            var record = StreamRecords.objectBacked(entry).withStreamKey(AUDIT_STREAM);
            redisTemplate.opsForStream().add(record);
            log.debug("Audit: {} {}", action, details);
        } catch (Exception e) {
            log.warn("Audit log failed: {}", e.getMessage());
        }
    }
}
