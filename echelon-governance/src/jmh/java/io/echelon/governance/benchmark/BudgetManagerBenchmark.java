package io.echelon.governance.benchmark;

import io.echelon.governance.BudgetManager;
import org.openjdk.jmh.annotations.*;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import java.util.concurrent.TimeUnit;
import static org.mockito.Mockito.*;

@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@Fork(0)
@State(Scope.Benchmark)
public class BudgetManagerBenchmark {
    private BudgetManager budgetManager;

    @Setup
    @SuppressWarnings("unchecked")
    public void setup() {
        RedisTemplate<String, String> redis = mock(RedisTemplate.class);
        ValueOperations<String, String> ops = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(ops);
        budgetManager = new BudgetManager(redis);
    }

    @Benchmark
    public boolean deduct() {
        return budgetManager.deduct("task-1", "agent-1", "project-1", 100);
    }
}
