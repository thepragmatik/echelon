package io.echelon.governance.token;

import static org.junit.jupiter.api.Assertions.*;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;

class PolicyEngineTest {

  private static final Instant NOW = Instant.now();

  private final PolicyStore testStore =
      new PolicyStore() {
        @Override
        public List<DeonticToken.Permit> getPermits(String role) {
          if ("implementer".equals(role)) {
            return List.of(
                new DeonticToken.Permit(
                    "write_source", Set.of("implementer"), "core", "test", NOW));
          }
          return List.of();
        }

        @Override
        public List<DeonticToken.Embargo> getEmbargoes(String role) {
          if ("implementer".equals(role)) {
            return List.of(
                new DeonticToken.Embargo(
                    "write_to_main", Set.of("implementer"), "core", "test", NOW));
          }
          return List.of();
        }

        @Override
        public List<DeonticToken.Burden> getBurdens(String role) {
          return List.of();
        }
      };

  private final PolicyEngine engine = new PolicyEngine(testStore, new SimpleMeterRegistry());

  @Test
  void embargoOverridesPermit() {
    // write_to_main is embargoed for implementer
    var action = new TokenAction("write_to_main", "implementer", "core");
    var result = engine.evaluate(action);
    assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
  }

  @Test
  void permittedActionReturnsAllow() {
    var action = new TokenAction("write_source", "implementer", "core");
    var result = engine.evaluate(action);
    assertEquals(EvaluationResult.Verdict.ALLOW, result.verdict());
  }

  @Test
  void defaultDenyForUnknownAction() {
    var action = new TokenAction("delete_production", "implementer", "core");
    var result = engine.evaluate(action);
    assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
  }

  @Test
  void defaultDenyForUnknownRole() {
    var action = new TokenAction("write_source", "unknown_role", "core");
    var result = engine.evaluate(action);
    assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
  }
}
