package io.echelon.governance.skills;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class SkillRegistryTest {

    private SkillRepository skillRepository;
    private SkillRegistry skillRegistry;

    private SkillDefinition reviewSkill;
    private SkillDefinition buildSkill;

    @BeforeEach
    void setUp() {
        skillRepository = mock(SkillRepository.class);
        skillRegistry = new SkillRegistry(skillRepository);

        reviewSkill = new SkillDefinition(
            "review-github-pr@1.0.0",
            "review-github-pr",
            "Summarize PR diffs",
            "reviewing",
            "1.0.0",
            List.of("gh", "jq"),
            "/skills/review-github-pr/entry.sh",
            "echelon-core"
        );
        buildSkill = new SkillDefinition(
            "build-from-issue@1.0.0",
            "build-from-issue",
            "Build from GitHub issues",
            "implementing",
            "1.0.0",
            List.of("mvn"),
            "/skills/build-from-issue/entry.sh",
            "echelon-core"
        );
    }

    @Test
    void testRegister() {
        skillRegistry.register(reviewSkill);

        verify(skillRepository).save(reviewSkill);
    }

    @Test
    void testDiscover() {
        when(skillRepository.findByCategory("reviewing"))
            .thenReturn(List.of(reviewSkill));

        var result = skillRegistry.discover("reviewing");

        assertEquals(1, result.size());
        assertEquals("review-github-pr", result.get(0).name());
        verify(skillRepository).findByCategory("reviewing");
    }

    @Test
    void testDiscoverReturnsEmptyForNoMatch() {
        when(skillRepository.findByCategory("unknown"))
            .thenReturn(List.of());

        var result = skillRegistry.discover("unknown");

        assertTrue(result.isEmpty());
    }

    @Test
    void testFindByName() {
        when(skillRepository.findAll())
            .thenReturn(List.of(reviewSkill, buildSkill));

        var result = skillRegistry.findByName("review-github-pr");

        assertTrue(result.isPresent());
        assertEquals("review-github-pr@1.0.0", result.get().id());
    }

    @Test
    void testFindByNameReturnsEmptyWhenNotFound() {
        when(skillRepository.findAll())
            .thenReturn(List.of(reviewSkill));

        var result = skillRegistry.findByName("nonexistent-skill");

        assertTrue(result.isEmpty());
    }

    @Test
    void testListAll() {
        when(skillRepository.findAll())
            .thenReturn(List.of(reviewSkill, buildSkill));

        var result = skillRegistry.listAll();

        assertEquals(2, result.size());
        verify(skillRepository).findAll();
    }

    @Test
    void testListAllReturnsEmptyWhenNoSkills() {
        when(skillRepository.findAll()).thenReturn(List.of());

        var result = skillRegistry.listAll();

        assertTrue(result.isEmpty());
    }
}
