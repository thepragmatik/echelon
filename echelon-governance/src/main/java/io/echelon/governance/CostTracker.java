package io.echelon.governance;

import org.springframework.data.redis.connection.stream.ObjectRecord;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.Map;

@Service
public class CostTracker {
    private final RedisTemplate<String, String> redis;
    private static final String STREAM_KEY = "cost:events";

    public CostTracker(RedisTemplate<String, String> redis) {
        this.redis = redis;
    }

    public void record(CostAttribution entry) {
        var record = StreamRecords.newRecord()
            .ofObject(entry)
            .withStreamKey(STREAM_KEY);
        redis.opsForStream().add(record);
    }

    public double totalCost() {
        var info = redis.opsForStream().info(STREAM_KEY);
        return info != null ? info.streamLength() * 0.001 : 0.0;
    }
}
