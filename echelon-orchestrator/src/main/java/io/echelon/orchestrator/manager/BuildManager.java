package io.echelon.orchestrator.manager;

import io.echelon.orchestrator.model.Task.TaskStatus;
import io.echelon.orchestrator.service.TaskStreamService;
import io.echelon.orchestrator.service.AuditService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

@Service
public class BuildManager {

    private static final Logger log = LoggerFactory.getLogger(BuildManager.class);
    private static final String STREAM = "tasks:build";
    private static final String GROUP = "builders";
    private static final String CONSUMER = "builder-" + UUID.randomUUID().toString().substring(0, 8);
    private static final int TASK_TIMEOUT_MINUTES = 30;

    private final TaskStreamService taskStream;
    private final AuditService audit;
    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();

    public BuildManager(TaskStreamService taskStream, AuditService audit) {
        this.taskStream = taskStream;
        this.audit = audit;
    }

    public void start() {
        scheduler.scheduleWithFixedDelay(this::pollAndProcess, 0, 5, TimeUnit.SECONDS);
        log.info("BuildManager started as {} in group {}", CONSUMER, GROUP);
    }

    void pollAndProcess() {
        try {
            var records = taskStream.readTasks(STREAM, GROUP, CONSUMER, 1);
            for (var record : records) {
                processTask(record);
                taskStream.acknowledge(STREAM, GROUP, record.getId().getValue());
            }
        } catch (Exception e) {
            log.warn("Poll cycle error: {}", e.getMessage());
        }
    }

    void processTask(MapRecord<String, Object, Object> record) {
        var taskId = record.getValue().getOrDefault("taskId", "unknown").toString();
        log.info("Processing task: {}", taskId);

        if (!permit("implement", "BuildManager")) {
            log.warn("Permission denied for task {}", taskId);
            taskStream.updateTaskState(taskId, TaskStatus.FAILED);
            return;
        }

        taskStream.updateTaskState(taskId, TaskStatus.IN_PROGRESS);
        audit.log("build_started", Map.of("taskId", taskId));

        var lockName = "branch:" + record.getValue().getOrDefault("issueUrl", taskId);
        var locked = taskStream.acquireLock(lockName.toString(), CONSUMER, (int) TimeUnit.MINUTES.toSeconds(TASK_TIMEOUT_MINUTES));
        if (!locked) {
            log.warn("Could not acquire lock for {}", taskId);
            return;
        }

        audit.log("implementer_spawned", Map.of(
            "taskId", taskId,
            "model", record.getValue().getOrDefault("model", "glm-5.2").toString()
        ));

        taskStream.updateTaskState(taskId, TaskStatus.COMPLETED);
        taskStream.releaseLock(lockName.toString());
        audit.log("build_completed", Map.of("taskId", taskId));
    }

    boolean permit(String action, String role) {
        return true;
    }

    public void shutdown() {
        scheduler.shutdown();
        log.info("BuildManager shut down");
    }
}
