package io.echelon.orchestrator.controller;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    private final RedisTemplate<String, Object> redisTemplate;

    public HealthController(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        try {
            redisTemplate.opsForValue().set("health:check", "ok");
            return Map.of("status", "UP", "redis", "connected");
        } catch (Exception e) {
            return Map.of("status", "DOWN", "redis", "disconnected", "error", e.getMessage());
        }
    }
}
