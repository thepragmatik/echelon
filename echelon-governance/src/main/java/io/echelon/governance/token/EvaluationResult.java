package io.echelon.governance.token;

public record EvaluationResult(Verdict verdict, String reason, DeonticToken matchedToken) {
    public enum Verdict { ALLOW, DENY }
    public static EvaluationResult ALLOW(String reason, DeonticToken token) {
        return new EvaluationResult(Verdict.ALLOW, reason, token);
    }
    public static EvaluationResult DENY(String reason, DeonticToken token) {
        return new EvaluationResult(Verdict.DENY, reason, token);
    }
}
