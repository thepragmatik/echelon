package io.echelon.governance.token;

import java.time.Instant;
import java.util.Set;

public sealed interface DeonticToken {
    String action();
    Set<String> roles();
    String resource();
    String description();
    Instant createdAt();

    record Burden(String action, Set<String> roles, String resource,
                  String description, Instant createdAt) implements DeonticToken {}
    record Permit(String action, Set<String> roles, String resource,
                  String description, Instant createdAt) implements DeonticToken {}
    record Embargo(String action, Set<String> roles, String resource,
                   String description, Instant createdAt) implements DeonticToken {}
}
