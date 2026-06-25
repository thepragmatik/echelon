package io.echelon.orchestrator.config;

import io.echelon.orchestrator.manager.ReviewManager;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ReviewManagerConfig {

    private final ReviewManager reviewManager;

    public ReviewManagerConfig(ReviewManager reviewManager) {
        this.reviewManager = reviewManager;
    }

    @PostConstruct
    public void start() { reviewManager.start(); }

    @PreDestroy
    public void stop() { reviewManager.shutdown(); }
}
