package io.echelon.orchestrator.config;

import io.echelon.governance.token.PolicyEngine;
import io.echelon.governance.token.PolicyStore;
import io.echelon.governance.token.YamlPolicyLoader;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GovernanceConfig {

  @Bean
  public PolicyStore policyStore() {
    return new YamlPolicyLoader("policies/agent-types.yaml");
  }

  @Bean
  public PolicyEngine policyEngine(PolicyStore policyStore, MeterRegistry meterRegistry) {
    return new PolicyEngine(policyStore, meterRegistry);
  }
}
