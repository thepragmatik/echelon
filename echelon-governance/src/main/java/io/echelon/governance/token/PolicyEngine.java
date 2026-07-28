package io.echelon.governance.token;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

public class PolicyEngine {
  private final PolicyStore policyStore;
  private final Counter permitDeniedCounter;
  private final Counter permitAllowedCounter;

  public PolicyEngine(PolicyStore policyStore, MeterRegistry meterRegistry) {
    this.policyStore = policyStore;
    this.permitDeniedCounter =
        Counter.builder("policy.permit.decisions")
            .tag("verdict", "DENY")
            .description("Number of denied policy decisions")
            .register(meterRegistry);
    this.permitAllowedCounter =
        Counter.builder("policy.permit.decisions")
            .tag("verdict", "ALLOW")
            .description("Number of allowed policy decisions")
            .register(meterRegistry);
  }

  public EvaluationResult evaluate(TokenAction action) {
    var effectiveEmbargoes = policyStore.getEmbargoes(action.role());
    for (var embargo : effectiveEmbargoes) {
      if (matches(embargo, action)) {
        permitDeniedCounter.increment();
        return EvaluationResult.DENY("Embargoed: " + embargo.description(), embargo);
      }
    }
    var effectivePermits = policyStore.getPermits(action.role());
    for (var permit : effectivePermits) {
      if (matches(permit, action)) {
        permitAllowedCounter.increment();
        return EvaluationResult.ALLOW("Permitted by: " + permit.description(), permit);
      }
    }
    permitDeniedCounter.increment();
    return EvaluationResult.DENY("No matching permit (default-deny)", null);
  }

  public void refreshPolicies() {
    if (policyStore instanceof RedisPolicyStore) {
      ((RedisPolicyStore) policyStore).refresh();
    }
  }

  private boolean matches(DeonticToken token, TokenAction action) {
    return token.action().equals(action.action()) && token.roles().contains(action.role());
  }
}
