package io.echelon.governance.token;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class YamlPolicyLoaderTest {
    @Test void shouldLoadPolicyFromClasspath() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        assertFalse(loader.getPermits("implementer").isEmpty());
        assertEquals("write_source", loader.getPermits("implementer").get(0).action());
    }

    @Test void shouldLoadEmbargoesForImplementer() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        assertEquals(3, loader.getEmbargoes("implementer").size());
        assertEquals("write_to_main", loader.getEmbargoes("implementer").get(0).action());
    }

    @Test void shouldReturnEmptyForUnknownRole() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        assertTrue(loader.getPermits("unknown").isEmpty());
        assertTrue(loader.getEmbargoes("unknown").isEmpty());
    }

    @Test void reviewerHasReadOnlyPermits() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        var permits = loader.getPermits("reviewer");
        assertTrue(permits.stream().noneMatch(p -> p.action().equals("write_source")));
    }

    @Test void orchestratorCanMerge() {
        var loader = new YamlPolicyLoader("policies/agent-types.yaml");
        assertTrue(loader.getPermits("orchestrator").stream()
            .anyMatch(p -> p.action().equals("merge_pr")));
    }
}
