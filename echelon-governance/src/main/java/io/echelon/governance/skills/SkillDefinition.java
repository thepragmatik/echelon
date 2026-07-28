package io.echelon.governance.skills;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public record SkillDefinition(
    String id,
    String name,
    String description,
    String category,
    String version,
    List<String> requiredTools,
    String entryPoint,
    String author) {
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

  public Map<String, String> toMap() {
    Map<String, String> map = new HashMap<>();
    map.put("id", id);
    map.put("name", name);
    map.put("description", description);
    map.put("category", category);
    map.put("version", version);
    try {
      map.put(
          "requiredTools",
          requiredTools != null ? OBJECT_MAPPER.writeValueAsString(requiredTools) : "");
    } catch (Exception e) {
      map.put("requiredTools", "");
    }
    map.put("entryPoint", entryPoint);
    map.put("author", author);
    return map;
  }

  public static SkillDefinition fromMap(Map<String, String> map) {
    String requiredToolsStr = map.getOrDefault("requiredTools", "");
    List<String> tools;
    if (requiredToolsStr.isEmpty()) {
      tools = List.of();
    } else {
      try {
        tools =
            OBJECT_MAPPER.readValue(
                requiredToolsStr,
                OBJECT_MAPPER.getTypeFactory().constructCollectionType(List.class, String.class));
      } catch (Exception e) {
        tools = List.of();
      }
    }
    return new SkillDefinition(
        map.get("id"),
        map.get("name"),
        map.get("description"),
        map.get("category"),
        map.get("version"),
        tools,
        map.get("entryPoint"),
        map.get("author"));
  }
}
