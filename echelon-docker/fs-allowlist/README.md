# Echelon Filesystem Allowlisting Policies

This directory contains per-container filesystem allowlisting policies for the Echelon Docker deployment. Each policy file defines which paths a container can read, write, or is blocked from accessing.

## Purpose

Docker containers in Echelon run with read-only root filesystems by default. The policies here complement the `:ro` mount options in `docker-compose.yml` by providing a machine- and human-readable specification of the intended filesystem access matrix.

These policies serve as:
- **Documentation** of the access model for security reviews
- **Ground truth** for runtime enforcement (e.g., seccomp profiles, AppArmor, or custom sandboxing)
- **Audit trail** for changes to filesystem permissions over time

## Policy Format

Each policy is a YAML file with three sections:

| Section      | Description                                                |
|--------------|------------------------------------------------------------|
| `writable`   | Paths where the container may create, modify, or delete files |
| `readonly`   | Paths the container can read but not write                 |
| `blocked`    | Paths the container is denied access to entirely           |

## Container Policies

| Policy File                                 | Container       | Writable Paths              | Read-only Paths                       |
|---------------------------------------------|-----------------|-----------------------------|---------------------------------------|
| `builder-policy.yaml`                       | builder         | `/work`, `/root/.m2`        | `/workspace`, `/usr/share/echelon`    |
| `reviewer-policy.yaml`                      | reviewer        | `/work`                     | `/workspace`, `/usr/share/echelon`    |
| `privacy-router-policy.yaml`                | privacy-router  | _(none)_                    | `/usr/local/etc/haproxy`              |

## Adding or Modifying a Path

1. Identify which container(s) need the change.
2. Edit the corresponding policy YAML file.
3. Add the path to the appropriate section (`writable`, `readonly`, or `blocked`).
4. If the path requires a new Docker volume mount, update `echelon-docker/docker-compose.yml` as well.
5. Commit both files together so the policy and its runtime mount stay in sync.

### Guidelines

- **Prefer read-only** whenever possible. Write access should be the exception, not the default.
- **Block system paths** (`/etc`, `/proc`, `/sys`, `/dev`) for all containers to prevent container escape or privilege escalation.
- **Keep policies narrow** — the minimum set of paths needed for the container to function.
- **Document the rationale** in the YAML file header when adding unusual paths.

## Related

- `echelon-docker/docker-compose.yml` — Volume mount definitions
- `echelon-docker/seccomp/` — Seccomp profiles for additional sandboxing
