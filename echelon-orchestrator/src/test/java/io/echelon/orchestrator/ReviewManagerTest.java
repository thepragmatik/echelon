package io.echelon.orchestrator;

import io.echelon.orchestrator.manager.ReviewManager;
import io.echelon.orchestrator.model.Task.TaskStatus;
import io.echelon.orchestrator.service.TaskStreamService;
import io.echelon.orchestrator.service.AuditService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ReviewManagerTest {

    @Mock TaskStreamService taskStream;
    @Mock AuditService audit;

    @Test
    void shouldCreateManager() {
        var mgr = new ReviewManager(taskStream, audit);
        mgr.start();
        mgr.shutdown();
    }
}
