package io.echelon.governance;
import java.util.concurrent.ConcurrentHashMap;
public class BudgetManager {
    private final ConcurrentHashMap<String, Long> budgets = new ConcurrentHashMap<>();
    private static final long DEFAULT_CAP = 5000;
    public boolean deduct(String taskId, long tokens) {
        long remaining = budgets.getOrDefault(taskId, DEFAULT_CAP);
        if (remaining < tokens) return false;
        budgets.put(taskId, remaining - tokens);
        return true;
    }
    public long remaining(String taskId) { return budgets.getOrDefault(taskId, DEFAULT_CAP); }
    public void setCap(String taskId, long cap) { budgets.put(taskId, cap); }
}
