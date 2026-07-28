package io.echelon.governance;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

class BudgetManagerTest {

  private RedisTemplate<String, String> redisTemplate;
  private ValueOperations<String, String> valueOps;
  private BudgetManager budgetManager;

  @BeforeEach
  @SuppressWarnings("unchecked")
  void setUp() {
    redisTemplate = mock(RedisTemplate.class);
    valueOps = mock(ValueOperations.class);
    when(redisTemplate.opsForValue()).thenReturn(valueOps);
    budgetManager = new BudgetManager(redisTemplate);
  }

  @Test
  void deductTokensWithinTaskCapReturnsTrue() {
    when(valueOps.get(anyString())).thenReturn(null);
    assertTrue(budgetManager.deduct("task-1", "agent-1", "project-1", 100));
    verify(valueOps, times(2)).increment(anyString(), anyLong());
  }

  @Test
  void deductExceedsTaskCapReturnsFalse() {
    when(valueOps.get(anyString())).thenReturn(null);
    assertFalse(budgetManager.deduct("task-1", "agent-1", "project-1", 50001));
    verify(valueOps, never()).increment(anyString(), anyLong());
  }

  @Test
  void remainingReturnsCorrectValue() {
    // Mock config keys to return null (defaults: taskCap=50000, agentCap=500000)
    when(valueOps.get(startsWith("config:"))).thenReturn(null);
    when(valueOps.get("budget:task:task-1")).thenReturn("10000");
    when(valueOps.get(startsWith("budget:agent:"))).thenReturn("5000");
    long remaining = budgetManager.remaining("task-1", "agent-1");
    assertEquals(40000, remaining, 0.001); // min(50000-10000, 500000-5000) = min(40000, 495000)
  }

  @Test
  void differentTasksHaveIndependentCaps() {
    when(valueOps.get(anyString())).thenReturn(null);
    assertTrue(budgetManager.deduct("task-1", "agent-1", "project-1", 30000));
    assertTrue(budgetManager.deduct("task-2", "agent-2", "project-1", 30000));
  }

  @Test
  void deductRespectsMonthlyAgentCap() {
    // Simulate 16 prior deductions of 30000 = 480000
    // Config keys return null -> use defaults (taskCap=50000, agentCap=500000)
    when(valueOps.get(startsWith("config:"))).thenReturn(null);
    when(valueOps.get(startsWith("budget:agent:"))).thenReturn("480000");
    when(valueOps.get(startsWith("budget:task:"))).thenReturn(null);
    assertTrue(
        budgetManager.deduct(
            "task-new",
            "agent-1",
            "project-1",
            19999)); // agentUsed=480000, 480000+19999=499999 < 500000
    assertFalse(
        budgetManager.deduct(
            "task-new2", "agent-1", "project-1", 20001)); // 480000+20001=500001 > 500000
  }
}
