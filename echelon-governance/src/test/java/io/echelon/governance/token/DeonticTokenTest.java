package io.echelon.governance.token;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

import java.time.Instant;
import java.util.Set;

class DeonticTokenTest {

    @Test
    void permitRecordHasCorrectFields() {
        var now = Instant.now();
        var permit = new DeonticToken.Permit("write_source", Set.of("implementer"), "echelon-core", "test permit", now);
        assertEquals("write_source", permit.action());
        assertEquals(Set.of("implementer"), permit.roles());
        assertEquals("echelon-core", permit.resource());
        assertEquals("test permit", permit.description());
        assertEquals(now, permit.createdAt());
    }

    @Test
    void embargoRecordHasCorrectFields() {
        var embargo = new DeonticToken.Embargo("write_to_main", Set.of("implementer"), "echelon-core", "test embargo", Instant.now());
        assertEquals("write_to_main", embargo.action());
    }

    @Test
    void burdenRecordHasCorrectFields() {
        var burden = new DeonticToken.Burden("commit_feature_branch", Set.of("implementer"), "echelon-core", "test burden", Instant.now());
        assertEquals("commit_feature_branch", burden.action());
    }

    @Test
    void sealedInterfaceCannotBeExtendedOutside() {
        assertTrue(DeonticToken.class.isSealed());
        assertTrue(DeonticToken.class.isAssignableFrom(DeonticToken.Permit.class));
        assertTrue(DeonticToken.class.isAssignableFrom(DeonticToken.Embargo.class));
        assertTrue(DeonticToken.class.isAssignableFrom(DeonticToken.Burden.class));
    }

    @Test
    void tokenActionRecordIsCreated() {
        var action = new TokenAction("write_source", "implementer", "echelon-core");
        assertEquals("write_source", action.action());
        assertEquals("implementer", action.role());
    }

    @Test
    void evaluationResultAllowCreated() {
        var token = new DeonticToken.Permit("write_source", Set.of("implementer"), "core", "test", Instant.now());
        var result = EvaluationResult.ALLOW("permitted", token);
        assertEquals(EvaluationResult.Verdict.ALLOW, result.verdict());
        assertEquals("permitted", result.reason());
        assertEquals(token, result.matchedToken());
    }

    @Test
    void evaluationResultDenyCreated() {
        var token = new DeonticToken.Embargo("write_to_main", Set.of("implementer"), "core", "test", Instant.now());
        var result = EvaluationResult.DENY("embargoed", token);
        assertEquals(EvaluationResult.Verdict.DENY, result.verdict());
        assertEquals("embargoed", result.reason());
        assertEquals(token, result.matchedToken());
    }
}
