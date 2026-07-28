package io.echelon.governance;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.connection.stream.StreamInfo;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StreamOperations;

@SuppressWarnings("unchecked")
class CostTrackerTest {

  private RedisTemplate<String, String> redisTemplate;
  private StreamOperations<String, String, String> streamOps;
  private CostTracker costTracker;

  @BeforeEach
  void setUp() {
    redisTemplate = mock(RedisTemplate.class);
    streamOps = mock(StreamOperations.class);
    doReturn(streamOps).when(redisTemplate).opsForStream();
    costTracker = new CostTracker(redisTemplate);
  }

  @Test
  void totalCostReturnsZeroWhenNoRecords() {
    when(streamOps.info("cost:events")).thenThrow(new RuntimeException("ERR no such key"));
    assertEquals(0.0, costTracker.totalCost(), 0.001);
  }

  @Test
  void recordDoesNotThrow() {
    var entry = new CostAttribution("t1", "a1", "m1", "p1", 100, 0.001, null, Instant.now());
    assertDoesNotThrow(() -> costTracker.record(entry));
  }

  @Test
  void totalCostReturnsPositiveAfterRecords() {
    StreamInfo.XInfoStream streamInfo = mock(StreamInfo.XInfoStream.class);
    when(streamInfo.streamLength()).thenReturn(500L);
    when(streamOps.info("cost:events")).thenReturn(streamInfo);
    assertEquals(0.5, costTracker.totalCost(), 0.001);
  }
}
