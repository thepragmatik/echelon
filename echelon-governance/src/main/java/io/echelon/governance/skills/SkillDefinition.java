package io.echelon.governance.skills;

import java.util.Arrays;
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
    String author
) {
    public Map<String, String> toMap() {
        Map<String, String> map = new HashMap<>();
        map.put("id", id);
        map.put("name", name);
        map.put("description", description);
        map.put("category", category);
        map.put("version", version);
        map.put("requiredTools", requiredTools != null ? String.join(",", requiredTools) : "");
        map.put("entryPoint", entryPoint);
        map.put("author", author);
        return map;
    }

    public static SkillDefinition fromMap(Map<String, String> map) {
        String requiredToolsStr = map.getOrDefault("requiredTools", "");
        List<String> tools = requiredToolsStr.isEmpty()
            ? List.of()
            : Arrays.asList(requiredToolsStr.split(","));
        return new SkillDefinition(
            map.get("id"),
            map.get("name"),
            map.get("description"),
            map.get("category"),
            map.get("version"),
            tools,
            map.get("entryPoint"),
            map.get("author")
        );
    }
}
