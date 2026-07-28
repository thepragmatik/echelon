package io.echelon.governance.skills;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ScanOptions;
import org.springframework.stereotype.Service;

@Service
public class SkillRepository {

  private static final String SKILL_KEY_PREFIX = "skills:";
  private static final String CATEGORY_INDEX_PREFIX = "skills:by-category:";

  private final RedisTemplate<String, String> redisTemplate;

  public SkillRepository(RedisTemplate<String, String> redisTemplate) {
    this.redisTemplate = redisTemplate;
  }

  public void save(SkillDefinition skill) {
    String key = SKILL_KEY_PREFIX + skill.id();
    redisTemplate.opsForHash().putAll(key, skill.toMap());
    redisTemplate.opsForSet().add(CATEGORY_INDEX_PREFIX + skill.category(), key);
  }

  public Optional<SkillDefinition> findById(String id) {
    String key = SKILL_KEY_PREFIX + id;
    var entries = redisTemplate.<String, String>opsForHash().entries(key);
    if (entries.isEmpty()) {
      return Optional.empty();
    }
    return Optional.of(SkillDefinition.fromMap(entries));
  }

  public List<SkillDefinition> findByCategory(String category) {
    String categoryKey = CATEGORY_INDEX_PREFIX + category;
    var memberKeys = redisTemplate.opsForSet().members(categoryKey);
    if (memberKeys == null || memberKeys.isEmpty()) {
      return List.of();
    }
    List<SkillDefinition> results = new ArrayList<>();
    for (String memberKey : memberKeys) {
      var entries = redisTemplate.<String, String>opsForHash().entries(memberKey);
      if (!entries.isEmpty()) {
        results.add(SkillDefinition.fromMap(entries));
      }
    }
    return results;
  }

  public List<SkillDefinition> findAll() {
    List<SkillDefinition> results = new ArrayList<>();
    var cursor =
        redisTemplate.scan(
            ScanOptions.scanOptions().match(SKILL_KEY_PREFIX + "*").count(1000).build());
    while (cursor.hasNext()) {
      String key = cursor.next();
      if (isSkillHashKey(key)) {
        var entries = redisTemplate.<String, String>opsForHash().entries(key);
        if (!entries.isEmpty()) {
          results.add(SkillDefinition.fromMap(entries));
        }
      }
    }
    return results;
  }

  public void delete(String id) {
    String key = SKILL_KEY_PREFIX + id;
    var entries = redisTemplate.<String, String>opsForHash().entries(key);
    if (!entries.isEmpty()) {
      String category = entries.get("category");
      if (category != null) {
        redisTemplate.opsForSet().remove(CATEGORY_INDEX_PREFIX + category, key);
      }
    }
    redisTemplate.delete(key);
  }

  private boolean isSkillHashKey(String key) {
    if (key.startsWith(CATEGORY_INDEX_PREFIX)) return false;
    if (key.startsWith("skills:name:")) return false;
    if (key.equals("skills:all")) return false;
    return true;
  }
}
