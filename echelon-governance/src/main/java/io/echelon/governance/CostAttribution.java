package io.echelon.governance;

import java.time.Instant;
import java.util.Map;

public record CostAttribution(
    String taskId,
    String agentId,
    String model,
    String provider,
    long tokens,
    double cost,
    Map<String, String> tags,
    Instant timestamp
) {}
