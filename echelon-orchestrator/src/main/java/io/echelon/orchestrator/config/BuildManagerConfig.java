package io.echelon.orchestrator.config;

import io.echelon.orchestrator.manager.BuildManager;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.springframework.context.annotation.Configuration;

@Configuration
public class BuildManagerConfig {

    private final BuildManager buildManager;

    public BuildManagerConfig(BuildManager buildManager) {
        this.buildManager = buildManager;
    }

    @PostConstruct
    public void startManager() {
        buildManager.start();
    }

    @PreDestroy
    public void stopManager() {
        buildManager.shutdown();
    }
}
