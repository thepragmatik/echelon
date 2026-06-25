package io.echelon.orchestrator;

import io.echelon.orchestrator.model.Task.TaskStatus;
import io.echelon.orchestrator.service.TaskStateService;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class TaskStateServiceTest {

    private final TaskStateService service = new TaskStateService();

    @Test
    void shouldAllowPendingToAssigned() {
        assertTrue(service.isValidTransition(TaskStatus.PENDING, TaskStatus.ASSIGNED));
    }

    @Test
    void shouldAllowInProgressToCompleted() {
        assertTrue(service.isValidTransition(TaskStatus.IN_PROGRESS, TaskStatus.COMPLETED));
    }

    @Test
    void shouldBlockCompletedToInProgress() {
        assertFalse(service.isValidTransition(TaskStatus.COMPLETED, TaskStatus.IN_PROGRESS));
    }

    @Test
    void shouldBlockInvalidTransition() {
        assertThrows(IllegalStateException.class,
            () -> service.transition(TaskStatus.COMPLETED, TaskStatus.IN_PROGRESS));
    }
}
