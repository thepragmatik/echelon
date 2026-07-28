package io.echelon.governance.skills;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.HashOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ScanOptions;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.Cursor;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@SuppressWarnings("unchecked")
class SkillRepositoryTest {

    private RedisTemplate<String, String> redisTemplate;
    private HashOperations<String, String, String> hashOps;
    private SetOperations<String, String> setOps;
    private Cursor<String> cursor;
    private SkillRepository skillRepository;

    private SkillDefinition reviewSkill;
    private SkillDefinition buildSkill;
    private SkillDefinition securitySkill;

    @BeforeEach
    void setUp() {
        redisTemplate = mock(RedisTemplate.class);
        hashOps = mock(HashOperations.class);
        setOps = mock(SetOperations.class);
        cursor = mock(Cursor.class);
        doReturn(hashOps).when(redisTemplate).opsForHash();
        when(redisTemplate.opsForSet()).thenReturn(setOps);
        skillRepository = new SkillRepository(redisTemplate);

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
        securitySkill = new SkillDefinition(
            "scan-secrets@1.0.0",
            "scan-secrets",
            "Scan for secrets in codebase",
            "security",
            "1.0.0",
            List.of("gitleaks"),
            "/skills/scan-secrets/entry.sh",
            "security-team"
        );
    }

    @Test
    void testSaveAndFindById() {
        when(hashOps.entries("skills:review-github-pr@1.0.0"))
            .thenReturn(reviewSkill.toMap());

        skillRepository.save(reviewSkill);
        var result = skillRepository.findById("review-github-pr@1.0.0");

        assertTrue(result.isPresent());
        assertEquals("review-github-pr@1.0.0", result.get().id());
        assertEquals("review-github-pr", result.get().name());
        assertEquals("Summarize PR diffs", result.get().description());
        assertEquals("reviewing", result.get().category());
        assertEquals("1.0.0", result.get().version());
        assertEquals(List.of("gh", "jq"), result.get().requiredTools());
        assertEquals("/skills/review-github-pr/entry.sh", result.get().entryPoint());
        assertEquals("echelon-core", result.get().author());

        verify(hashOps).putAll(eq("skills:review-github-pr@1.0.0"), eq(reviewSkill.toMap()));
        verify(setOps).add("skills:by-category:reviewing", "skills:review-github-pr@1.0.0");
    }

    @Test
    void testFindByIdReturnsEmptyWhenNotFound() {
        when(hashOps.entries("skills:nonexistent")).thenReturn(Map.of());

        var result = skillRepository.findById("nonexistent");

        assertTrue(result.isEmpty());
    }

    @Test
    void testFindByCategory() {
        when(setOps.members("skills:by-category:reviewing"))
            .thenReturn(Set.of("skills:review-github-pr@1.0.0"));
        when(hashOps.entries("skills:review-github-pr@1.0.0"))
            .thenReturn(reviewSkill.toMap());

        skillRepository.save(reviewSkill);
        skillRepository.save(buildSkill);

        var result = skillRepository.findByCategory("reviewing");

        assertEquals(1, result.size());
        assertEquals("review-github-pr@1.0.0", result.get(0).id());
    }

    @Test
    void testFindByCategoryReturnsEmptyForUnknownCategory() {
        when(setOps.members("skills:by-category:unknown")).thenReturn(Set.of());

        var result = skillRepository.findByCategory("unknown");

        assertTrue(result.isEmpty());
    }

    @Test
    void testFindAll() {
        when(redisTemplate.scan(any(ScanOptions.class))).thenReturn(cursor);
        when(cursor.hasNext()).thenReturn(true, true, true, false);
        when(cursor.next())
            .thenReturn("skills:review-github-pr@1.0.0")
            .thenReturn("skills:build-from-issue@1.0.0")
            .thenReturn("skills:scan-secrets@1.0.0");
        when(hashOps.entries("skills:review-github-pr@1.0.0"))
            .thenReturn(reviewSkill.toMap());
        when(hashOps.entries("skills:build-from-issue@1.0.0"))
            .thenReturn(buildSkill.toMap());
        when(hashOps.entries("skills:scan-secrets@1.0.0"))
            .thenReturn(securitySkill.toMap());

        var result = skillRepository.findAll();

        assertEquals(3, result.size());
        var ids = result.stream().map(SkillDefinition::id).toList();
        assertTrue(ids.containsAll(List.of(
            "review-github-pr@1.0.0",
            "build-from-issue@1.0.0",
            "scan-secrets@1.0.0"
        )));
    }

    @Test
    void testFindAllFiltersIndexKeys() {
        when(redisTemplate.scan(any(ScanOptions.class))).thenReturn(cursor);
        when(cursor.hasNext()).thenReturn(true, true, true, false);
        when(cursor.next())
            .thenReturn("skills:review-github-pr@1.0.0")
            .thenReturn("skills:by-category:reviewing")
            .thenReturn("skills:all");
        when(hashOps.entries("skills:review-github-pr@1.0.0"))
            .thenReturn(reviewSkill.toMap());
        when(hashOps.entries("skills:by-category:reviewing"))
            .thenReturn(Map.of());
        when(hashOps.entries("skills:all"))
            .thenReturn(Map.of());

        var result = skillRepository.findAll();

        assertEquals(1, result.size());
        assertEquals("review-github-pr@1.0.0", result.get(0).id());
    }

    @Test
    void testDelete() {
        Map<String, String> skillData = new HashMap<>(reviewSkill.toMap());
        skillData.put("category", "reviewing");
        when(hashOps.entries("skills:review-github-pr@1.0.0"))
            .thenReturn(skillData);

        skillRepository.save(reviewSkill);
        skillRepository.delete("review-github-pr@1.0.0");

        verify(setOps).remove("skills:by-category:reviewing", "skills:review-github-pr@1.0.0");
        verify(redisTemplate).delete("skills:review-github-pr@1.0.0");
    }

    @Test
    void testDeleteNonExistentSkillDoesNotThrow() {
        when(hashOps.entries("skills:nonexistent")).thenReturn(Map.of());

        assertDoesNotThrow(() -> skillRepository.delete("nonexistent"));
        verify(redisTemplate).delete("skills:nonexistent");
    }
}
