package io.echelon.governance;

import java.util.HashMap;
import java.util.Map;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

@Service
public class CostTracker {
  private final RedisTemplate<String, String> redis;
  private static final String STREAM_KEY = "cost:events";

  public CostTracker(RedisTemplate<String, String> redis) {
    this.redis = redis;
  }

  public void record(CostAttribution entry) {
    Map<String, String> fields = new HashMap<>();
    fields.put("taskId", entry.taskId());
    fields.put("agentId", entry.agentId());
    fields.put("model", entry.model());
    fields.put("provider", entry.provider());
    fields.put("tokens", String.valueOf(entry.tokens()));
    fields.put("cost", String.valueOf(entry.cost()));
    fields.put("timestamp", entry.timestamp().toString());
    if (entry.tags() != null) {
      entry.tags().forEach((k, v) -> fields.put("tag:" + k, v));
    }
    var record = StreamRecords.newRecord().ofMap(fields).withStreamKey(STREAM_KEY);
    redis.opsForStream().add(record);
  }

  public double totalCost() {
    try {
      var info = redis.opsForStream().info(STREAM_KEY);
      return info != null ? info.streamLength() * 0.001 : 0.0;
    } catch (Exception e) {
      return 0.0;
    }
  }
}
