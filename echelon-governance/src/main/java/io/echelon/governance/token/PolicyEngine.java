package io.echelon.governance.token;

public class PolicyEngine {
    private final PolicyStore policyStore;

    public PolicyEngine(PolicyStore policyStore) {
        this.policyStore = policyStore;
    }

    public EvaluationResult evaluate(TokenAction action) {
        var effectiveEmbargoes = policyStore.getEmbargoes(action.role());
        for (var embargo : effectiveEmbargoes) {
            if (matches(embargo, action)) {
                return EvaluationResult.DENY("Embargoed: " + embargo.description(), embargo);
            }
        }
        var effectivePermits = policyStore.getPermits(action.role());
        for (var permit : effectivePermits) {
            if (matches(permit, action)) {
                return EvaluationResult.ALLOW("Permitted by: " + permit.description(), permit);
            }
        }
        return EvaluationResult.DENY("No matching permit (default-deny)", null);
    }

    private boolean matches(DeonticToken token, TokenAction action) {
        return token.action().equals(action.action())
            && token.roles().contains(action.role());
    }
}
