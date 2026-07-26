package io.echelon.governance.token;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import java.io.InputStream;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

public class YamlPolicyLoader implements PolicyStore {
    private final Map<String, RolePolicy> policies;
    private final Instant loadedAt = Instant.now();

    @SuppressWarnings("unchecked")
    public YamlPolicyLoader(String classpathResource) {
        var mapper = new ObjectMapper(new YAMLFactory());
        try (InputStream is = getClass().getClassLoader().getResourceAsStream(classpathResource)) {
            if (is == null) throw new RuntimeException("Policy file not found: " + classpathResource);
            var raw = mapper.readValue(is, Map.class);
            Map<String, Map<String, List<Map<String, Object>>>> roles =
                (Map<String, Map<String, List<Map<String, Object>>>>) raw.get("roles");
            this.policies = roles.entrySet().stream()
                .collect(Collectors.toMap(Map.Entry::getKey, e -> new RolePolicy(
                    toPermits(e.getValue(), "permits", e.getKey()),
                    toEmbargoes(e.getValue(), "embargoes", e.getKey()),
                    toBurdens(e.getValue(), "burdens", e.getKey())
                )));
        } catch (Exception e) {
            throw new RuntimeException("Failed to load policy: " + classpathResource, e);
        }
    }

    @Override public List<DeonticToken.Permit> getPermits(String role) {
        var p = policies.get(role);
        return p != null ? p.permits : List.of();
    }
    @Override public List<DeonticToken.Embargo> getEmbargoes(String role) {
        var p = policies.get(role);
        return p != null ? p.embargoes : List.of();
    }
    @Override public List<DeonticToken.Burden> getBurdens(String role) {
        var p = policies.get(role);
        return p != null ? p.burdens : List.of();
    }

    private List<DeonticToken.Permit> toPermits(
            Map<String, List<Map<String, Object>>> sections, String key, String roleName) {
        var items = sections.get(key);
        if (items == null) return List.of();
        return items.stream()
            .map(m -> new DeonticToken.Permit(
                (String) m.get("action"), Set.of(roleName), "default", "", loadedAt))
            .collect(Collectors.toList());
    }

    private List<DeonticToken.Embargo> toEmbargoes(
            Map<String, List<Map<String, Object>>> sections, String key, String roleName) {
        var items = sections.get(key);
        if (items == null) return List.of();
        return items.stream()
            .map(m -> new DeonticToken.Embargo(
                (String) m.get("action"), Set.of(roleName), "default",
                (String) m.getOrDefault("reason", ""), loadedAt))
            .collect(Collectors.toList());
    }

    private List<DeonticToken.Burden> toBurdens(
            Map<String, List<Map<String, Object>>> sections, String key, String roleName) {
        var items = sections.get(key);
        if (items == null) return List.of();
        return items.stream()
            .map(m -> new DeonticToken.Burden(
                (String) m.get("action"),
                Set.of(roleName),
                "default",
                String.valueOf(m.getOrDefault("obligations", "")),
                loadedAt))
            .collect(Collectors.toList());
    }

    private record RolePolicy(List<DeonticToken.Permit> permits, List<DeonticToken.Embargo> embargoes, List<DeonticToken.Burden> burdens) {}
}
