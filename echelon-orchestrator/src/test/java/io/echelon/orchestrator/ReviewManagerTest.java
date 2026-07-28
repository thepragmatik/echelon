package io.echelon.orchestrator;

import static org.mockito.Mockito.*;

import io.echelon.orchestrator.manager.ReviewManager;
import io.echelon.orchestrator.service.AuditService;
import io.echelon.orchestrator.service.TaskStreamService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
@EnabledIfSystemProperty(named = "java.version", matches = "21.*")
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
