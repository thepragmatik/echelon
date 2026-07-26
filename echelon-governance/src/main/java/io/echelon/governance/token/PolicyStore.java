package io.echelon.governance.token;

import java.util.List;

public interface PolicyStore {
    List<DeonticToken.Permit> getPermits(String role);
    List<DeonticToken.Embargo> getEmbargoes(String role);
    List<DeonticToken.Burden> getBurdens(String role);
}
