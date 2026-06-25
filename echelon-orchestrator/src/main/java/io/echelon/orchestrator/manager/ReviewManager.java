package io.echelon.orchestrator.manager;

import io.echelon.orchestrator.model.Task.TaskStatus;
import io.echelon.orchestrator.service.TaskStreamService;
import io.echelon.orchestrator.service.AuditService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.*;

@Service
public class ReviewManager {

    private static final Logger log = LoggerFactory.getLogger(ReviewManager.class);
    private static final String STREAM = "tasks:review";
    private static final String GROUP = "reviewers";
    private static final String CONSUMER = "review-mgr-" + UUID.randomUUID().toString().substring(0, 8);
    private static final int REVIEWER_TIMEOUT_MINUTES = 10;

    private final TaskStreamService taskStream;
    private final AuditService audit;
    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();
    private final ExecutorService reviewerPool = Executors.newFixedThreadPool(4);

    public ReviewManager(TaskStreamService taskStream, AuditService audit) {
        this.taskStream = taskStream;
        this.audit = audit;
    }

    public void start() {
        scheduler.scheduleWithFixedDelay(this::pollAndProcess, 2, 10, TimeUnit.SECONDS);
        log.info("ReviewManager started as {} in group {}", CONSUMER, GROUP);
    }

    void pollAndProcess() {
        try {
            var records = taskStream.readTasks(STREAM, GROUP, CONSUMER, 1);
            for (var record : records) {
                processReview(record);
                taskStream.acknowledge(STREAM, GROUP, record.getId().getValue());
            }
        } catch (Exception e) {
            log.warn("Poll error: {}", e.getMessage());
        }
    }

    void processReview(MapRecord<String, Object, Object> record) {
        var taskId = record.getValue().getOrDefault("taskId", "unknown").toString();
        var prUrl = record.getValue().getOrDefault("prUrl", "").toString();
        log.info("Reviewing task: {} PR: {}", taskId, prUrl);

        taskStream.updateTaskState(taskId, TaskStatus.IN_PROGRESS);
        audit.log("review_started", Map.of("taskId", taskId, "prUrl", prUrl));

        // Spawn 2 parallel reviewers
        var roles = List.of("adversarial", "quality");
        var futures = new ArrayList<Future<Map<String, String>>>();

        for (var role : roles) {
            var r = role;
            futures.add(reviewerPool.submit(() -> runReviewer(prUrl, r)));
        }

        // Collect verdicts with timeout
        var verdicts = new ArrayList<String>();
        var allComments = new StringBuilder();
        for (var future : futures) {
            try {
                var result = future.get(REVIEWER_TIMEOUT_MINUTES, TimeUnit.MINUTES);
                verdicts.add(result.getOrDefault("verdict", "REQUEST_CHANGES"));
                allComments.append(result.getOrDefault("comments", ""));
            } catch (TimeoutException e) {
                log.warn("Reviewer timed out for {}", taskId);
                verdicts.add("REQUEST_CHANGES");
            } catch (Exception e) {
                log.warn("Reviewer failed: {}", e.getMessage());
                verdicts.add("REQUEST_CHANGES");
            }
        }

        // Evaluate verdicts
        var allApproved = verdicts.stream().allMatch(v -> v.equals("APPROVE"));
        if (allApproved) {
            taskStream.updateTaskState(taskId, TaskStatus.COMPLETED);
            audit.log("review_approved", Map.of("taskId", taskId, "verdicts", String.join(",", verdicts)));
            log.info("Review APPROVED for {}", taskId);
        } else {
            taskStream.updateTaskState(taskId, TaskStatus.FAILED);
            audit.log("review_changes_requested", Map.of(
                "taskId", taskId, "verdicts", String.join(",", verdicts),
                "comments", allComments.toString()
            ));
            log.info("Review CHANGES REQUESTED for {}", taskId);
        }
    }

    Map<String, String> runReviewer(String prUrl, String role) {
        try {
            var prNum = prUrl.replaceAll(".*/pull/(\\d+).*", "$1");
            var proc = new ProcessBuilder(
                "bash", "-c",
                String.format("echelon-workers/src/main/resources/scripts/reviewer.sh %s %s", prNum, role)
            ).start();
            var exited = proc.waitFor(REVIEWER_TIMEOUT_MINUTES, TimeUnit.MINUTES);
            var output = new String(proc.getInputStream().readAllBytes());
            return Map.of("verdict", exited && proc.exitValue() == 0 ? "APPROVE" : "REQUEST_CHANGES",
                          "comments", output);
        } catch (Exception e) {
            log.warn("Reviewer {} failed: {}", role, e.getMessage());
            return Map.of("verdict", "REQUEST_CHANGES", "comments", "");
        }
    }

    public void shutdown() {
        scheduler.shutdown();
        reviewerPool.shutdown();
        log.info("ReviewManager shut down");
    }
}
