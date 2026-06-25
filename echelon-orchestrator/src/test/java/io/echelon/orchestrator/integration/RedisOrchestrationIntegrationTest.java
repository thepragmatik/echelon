package io.echelon.orchestrator.integration;
import io.echelon.orchestrator.model.Task;
import io.echelon.orchestrator.model.Task.TaskStatus;
import io.echelon.orchestrator.service.TaskStreamService;
import io.echelon.orchestrator.service.AuditService;
import io.echelon.orchestrator.service.TaskStateService;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
@SpringBootTest
@Testcontainers
class RedisOrchestrationIntegrationTest {
    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);
    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.data.redis.host", redis::getHost);
        r.add("spring.data.redis.port", redis::getPort);
    }
    @Autowired private TaskStreamService taskStream;
    @Autowired private AuditService auditService;
    @Autowired private TaskStateService stateService;
    @Autowired private RedisTemplate<String, Object> redisTemplate;
    @Test
    void shouldPushAndConsumeTask() {
        var taskId = "test-" + UUID.randomUUID().toString().substring(0, 8);
        var task = new Task(taskId, "implement", "https://github.com/test", "build", 1, "glm-5.2", 5000,
            TaskStatus.PENDING, Instant.now(), Instant.now(), null, Map.of());
        var recordId = taskStream.pushTask("tasks:build", task);
        assertNotNull(recordId);
        var state = taskStream.getTaskState(taskId);
        assertTrue(state.isPresent());
    }
    @Test
    void shouldValidateStateTransitions() {
        assertTrue(stateService.isValidTransition(TaskStatus.PENDING, TaskStatus.ASSIGNED));
        assertFalse(stateService.isValidTransition(TaskStatus.COMPLETED, TaskStatus.IN_PROGRESS));
    }
    @Test
    void shouldRecordAuditEntries() {
        auditService.log("test_action", Map.of("key", "value"));
        assertDoesNotThrow(() -> auditService.log("another_test", Map.of()));
    }
}
