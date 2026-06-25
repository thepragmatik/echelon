package io.echelon.orchestrator.controller;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;
@RestController
public class MetricsController {
    private final MeterRegistry registry;
    public MetricsController(MeterRegistry registry) { this.registry = registry; }
    @GetMapping("/metrics/summary")
    public Map<String, Object> summary() {
        return Map.of(
            "jvm.memory.used", registry.find("jvm.memory.used").gauges().stream().mapToDouble(g -> g.value()).sum(),
            "jvm.threads.live", registry.find("jvm.threads.live").gauge().map(g -> (int)g.value()).orElse(0)
        );
    }
}
