package io.echelon.orchestrator.service;

import io.echelon.orchestrator.model.Task.TaskStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.EnumMap;
import java.util.Map;
import java.util.Set;

@Service
public class TaskStateService {

    private static final Logger log = LoggerFactory.getLogger(TaskStateService.class);

    private static final Map<TaskStatus, Set<TaskStatus>> VALID_TRANSITIONS = new EnumMap<>(TaskStatus.class);

    static {
        VALID_TRANSITIONS.put(TaskStatus.PENDING, Set.of(TaskStatus.ASSIGNED, TaskStatus.FAILED));
        VALID_TRANSITIONS.put(TaskStatus.ASSIGNED, Set.of(TaskStatus.IN_PROGRESS, TaskStatus.FAILED));
        VALID_TRANSITIONS.put(TaskStatus.IN_PROGRESS, Set.of(TaskStatus.COMPLETED, TaskStatus.FAILED));
        VALID_TRANSITIONS.put(TaskStatus.COMPLETED, Set.of());
        VALID_TRANSITIONS.put(TaskStatus.FAILED, Set.of(TaskStatus.PENDING));
    }

    public boolean isValidTransition(TaskStatus from, TaskStatus to) {
        var allowed = VALID_TRANSITIONS.get(from);
        return allowed != null && allowed.contains(to);
    }

    public TaskStatus transition(TaskStatus from, TaskStatus to) {
        if (!isValidTransition(from, to)) {
            log.warn("Invalid state transition: {} -> {}", from, to);
            throw new IllegalStateException("Invalid transition from " + from + " to " + to);
        }
        log.info("State transition: {} -> {}", from, to);
        return to;
    }
}
