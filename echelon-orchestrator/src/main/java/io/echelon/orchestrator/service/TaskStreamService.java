package io.echelon.orchestrator.service;

import io.echelon.orchestrator.model.Task;
import io.echelon.orchestrator.model.Task.TaskStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.stream.*;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.*;

@Service
public class TaskStreamService {

    private static final Logger log = LoggerFactory.getLogger(TaskStreamService.class);

    private final RedisTemplate<String, Object> redisTemplate;
    private final AuditService auditService;

    public TaskStreamService(RedisTemplate<String, Object> redisTemplate, AuditService auditService) {
        this.redisTemplate = redisTemplate;
        this.auditService = auditService;
    }

    public String pushTask(String stream, Task task) {
        var record = ObjectRecord.create(stream, task);
        var result = redisTemplate.opsForStream().add(record);
        log.info("Task {} pushed to stream {}: {}", task.taskId(), stream, result);
        auditService.log("task_pushed", Map.of("taskId", task.taskId(), "stream", stream));
        return result;
    }

    public List<MapRecord<String, Object, Object>> readTasks(String stream, String consumerGroup, String consumer, int count) {
        var readArgs = StreamReadOptions.empty().count(count);
        var offset = StreamOffset.create(stream, ReadOffset.lastConsumed(consumerGroup));
        return redisTemplate.opsForStream().read(consumerGroup, consumer, readArgs, offset);
    }

    public void acknowledge(String stream, String consumerGroup, String recordId) {
        redisTemplate.opsForStream().acknowledge(consumerGroup, stream, recordId);
        auditService.log("task_acknowledged", Map.of("stream", stream, "recordId", recordId));
    }

    public void updateTaskState(String taskId, TaskStatus status) {
        var stateKey = "task:" + taskId + ":status";
        redisTemplate.opsForValue().set(stateKey, status.name());
        auditService.log("state_changed", Map.of("taskId", taskId, "status", status.name()));
    }

    public Optional<String> getTaskState(String taskId) {
        var stateKey = "task:" + taskId + ":status";
        var val = redisTemplate.opsForValue().get(stateKey);
        return Optional.ofNullable(val).map(Object::toString);
    }

    public void heartbeat(String agentId) {
        var key = "agent:" + agentId + ":heartbeat";
        redisTemplate.opsForValue().set(key, Instant.now().toString());
        redisTemplate.expire(key, java.time.Duration.ofSeconds(30));
    }

    public boolean acquireLock(String lockName, String owner, int ttlSeconds) {
        var key = "lock:" + lockName;
        var acquired = redisTemplate.opsForValue().setIfAbsent(key, owner, java.time.Duration.ofSeconds(ttlSeconds));
        if (Boolean.TRUE.equals(acquired)) {
            auditService.log("lock_acquired", Map.of("lock", lockName, "owner", owner));
            return true;
        }
        return false;
    }

    public void releaseLock(String lockName) {
        redisTemplate.delete("lock:" + lockName);
        auditService.log("lock_released", Map.of("lock", lockName));
    }
}
