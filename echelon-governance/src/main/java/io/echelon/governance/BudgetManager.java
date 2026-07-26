package io.echelon.governance;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;
import java.time.Duration;
import java.time.YearMonth;

@Service
public class BudgetManager {
    private final RedisTemplate<String, String> redis;

    public BudgetManager(RedisTemplate<String, String> redis) {
        this.redis = redis;
    }

    private static final long DEFAULT_TASK_CAP = 50000;
    private static final long DEFAULT_AGENT_MONTHLY_CAP = 500000;
    private static final Duration DEFAULT_TTL = Duration.ofDays(30);

    public boolean deduct(String taskId, String agentId, String projectId, long tokens) {
        var month = YearMonth.now().toString();
        var taskKey = "budget:task:" + taskId;
        var agentKey = "budget:agent:" + agentId + ":" + month;

        var taskCap = getConfig("config:budget:task:default", DEFAULT_TASK_CAP);
        var agentCap = getConfig("config:budget:agent:default", DEFAULT_AGENT_MONTHLY_CAP);

        var taskUsed = getLong(taskKey);
        if (taskUsed + tokens > taskCap) return false;

        var agentUsed = getLong(agentKey);
        if (agentUsed + tokens > agentCap) return false;

        incrementAndExpire(taskKey, tokens, DEFAULT_TTL);
        incrementAndExpire(agentKey, tokens, DEFAULT_TTL);
        return true;
    }

    public long remaining(String taskId, String agentId) {
        var month = YearMonth.now().toString();
        var taskCap = getConfig("config:budget:task:default", DEFAULT_TASK_CAP);
        var agentCap = getConfig("config:budget:agent:default", DEFAULT_AGENT_MONTHLY_CAP);
        var taskUsed = getLong("budget:task:" + taskId);
        var agentUsed = getLong("budget:agent:" + agentId + ":" + month);
        return Math.min(taskCap - taskUsed, agentCap - agentUsed);
    }

    private long getConfig(String key, long defaultVal) {
        var val = redis.opsForValue().get(key);
        return val != null ? Long.parseLong(val) : defaultVal;
    }

    private long getLong(String key) {
        var val = redis.opsForValue().get(key);
        return val != null ? Long.parseLong(val) : 0L;
    }

    private void incrementAndExpire(String key, long tokens, Duration ttl) {
        redis.opsForValue().increment(key, tokens);
        redis.expire(key, ttl);
    }
}
