package io.echelon.orchestrator.model;

import java.time.Instant;
import java.util.Map;

public record Task(
    String taskId,
    String type,
    String issueUrl,
    String manager,
    int priority,
    String model,
    int budget,
    TaskStatus status,
    Instant createdAt,
    Instant updatedAt,
    String assignedAgent,
    Map<String, String> metadata
) {
    public enum TaskStatus {
        PENDING, ASSIGNED, IN_PROGRESS, COMPLETED, FAILED
    }
}
