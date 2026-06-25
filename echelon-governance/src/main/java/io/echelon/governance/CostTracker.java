package io.echelon.governance;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
public record CostEntry(String taskId, String agent, String model, long tokens, double cost, Instant timestamp) {}
public class CostTracker {
    private final List<CostEntry> entries = new CopyOnWriteArrayList<>();
    public void record(CostEntry entry) { entries.add(entry); }
    public List<CostEntry> byTask(String taskId) { return entries.stream().filter(e -> e.taskId().equals(taskId)).toList(); }
    public double totalCost() { return entries.stream().mapToDouble(CostEntry::cost).sum(); }
    public long totalTokens() { return entries.stream().mapToLong(CostEntry::tokens).sum(); }
}
