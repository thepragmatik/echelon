package io.echelon.governance;

import io.echelon.governance.token.*;
import org.junit.jupiter.api.*;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import static org.junit.jupiter.api.Assertions.*;

import java.time.Instant;
import java.util.Map;
import java.util.Set;

@Testcontainers
class GovernanceIntegrationTest {

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);

    private static RedisTemplate<String, String> redisTemplate;
    private static BudgetManager budgetManager;
    private static CostTracker costTracker;
    private static PolicyEngine policyEngine;

    @BeforeAll
    static void setup() {
        var host = redis.getHost();
        var port = redis.getMappedPort(6379);
        var config = new RedisStandaloneConfiguration(host, port);
        var factory = new LettuceConnectionFactory(config);
        factory.afterPropertiesSet();

        redisTemplate = new RedisTemplate<>();
        redisTemplate.setConnectionFactory(factory);
        redisTemplate.setKeySerializer(new StringRedisSerializer());
        redisTemplate.setValueSerializer(new StringRedisSerializer());
        redisTemplate.afterPropertiesSet();

        budgetManager = new BudgetManager(redisTemplate);
        costTracker = new CostTracker(redisTemplate);

        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        policyEngine = new PolicyEngine(loader);
    }

    @AfterEach
    void cleanRedis() {
        redisTemplate.getConnectionFactory().getConnection().serverCommands().flushAll();
    }

    @Nested
    class BudgetManagerTests {

        @Test
        void deductTokensSuccessfully() {
            assertTrue(budgetManager.deduct("task-1", "agent-1", "project-1", 100));
        }

        @Test
        void deductExceedsTaskCap() {
            // Deduct 50001 from 50000 cap
            assertFalse(budgetManager.deduct("task-1", "agent-1", "project-1", 50001));
        }

        @Test
        void deductExceedsMonthlyAgentCap() {
            budgetManager.deduct("task-1", "agent-1", "project-1", 250000);
            budgetManager.deduct("task-2", "agent-1", "project-1", 250000);
            // Third deduct should exceed the 500k monthly cap
            assertFalse(budgetManager.deduct("task-3", "agent-1", "project-1", 1));
        }

        @Test
        void remainingReturnsCorrectValue() {
            budgetManager.deduct("task-1", "agent-1", "project-1", 10000);
            long remaining = budgetManager.remaining("task-1", "agent-1");
            assertTrue(remaining > 0);
            assertTrue(remaining <= 50000);
        }

        @Test
        void differentAgentsHaveIndependentCaps() {
            budgetManager.deduct("task-1", "agent-1", "project-1", 250000);
            // Agent-2 should still have full cap
            assertTrue(budgetManager.deduct("task-2", "agent-2", "project-1", 250000));
        }
    }

    @Nested
    class CostTrackerTests {

        @Test
        void recordCostAttribution() {
            var entry = new CostAttribution(
                "task-1", "agent-1", "GLM-5.2", "wafer",
                1000, 0.002, Map.of("project", "echelon"), Instant.now()
            );
            assertDoesNotThrow(() -> costTracker.record(entry));
        }

        @Test
        void totalCostIncreasesAfterRecords() {
            double before = costTracker.totalCost();
            costTracker.record(new CostAttribution(
                "task-1", "agent-1", "GLM-5.2", "wafer",
                1000, 0.002, Map.of(), Instant.now()
            ));
            double after = costTracker.totalCost();
            assertTrue(after >= before);
        }
    }

    @Nested
    class PolicyEngineTests {

        @Test
        void implementerCanWriteSource() {
            var result = policyEngine.evaluate(new TokenAction("write_source", "implementer", "build"));
            assertEquals(EvaluationResult.Verdict.ALLOW, result.verdict());
        }

        @Test
        void implementerCannotWriteToMain() {
            var result = policyEngine.evaluate(new TokenAction("write_to_main", "implementer", "build"));
            assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
        }

        @Test
        void reviewerCannotWriteSource() {
            var result = policyEngine.evaluate(new TokenAction("write_source", "reviewer", "build"));
            assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
        }

        @Test
        void orchestratorCanMerge() {
            var result = policyEngine.evaluate(new TokenAction("merge_pr", "orchestrator", "build"));
            assertEquals(EvaluationResult.Verdict.ALLOW, result.verdict());
        }

        @Test
        void defaultDenyForUnknownRole() {
            var result = policyEngine.evaluate(new TokenAction("write_source", "unknown", "build"));
            assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
        }
    }
}
