# Seccomp Profile Audit

**Audit date:** 2026-07-27
**Audit scope:** `default.json`, `reviewer-strict.json`
**Auditor:** hswarm-eng (Issue #73)

---

## 1. Summary

| Profile | Default Action | Blocked Syscalls | Verdict |
|---------|---------------|------------------|---------|
| `default.json` | `SCMP_ACT_ALLOW` | 0 (allow-all) | **Misnamed** — not Docker's default |
| `reviewer-strict.json` | `SCMP_ACT_ALLOW` | 18 blacklisted | **Broken** — blocks syscalls the JVM needs to start |

---

## 2. `default.json` — Audit

### Current content

```json
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
    "syscalls": []
}
```

### Comparison with Docker's built-in default (moby v27.4.1)

| Property | This `default.json` | Docker's real default (moby) |
|---|---|---|
| Default action | `SCMP_ACT_ALLOW` | `SCMP_ACT_ERRNO` |
| Approach | Allow-all (no restrictions) | Deny-by-default, allowlist ~352 syscalls |
| Architecture handling | Flat list | Nested `archMap` with sub-architectures |
| Conditional rules | None | 31 rule groups, many with flag/arg conditions |

Docker's real default is a **deny-by-default whitelist**: it blocks everything except ~352 explicitly allowed syscalls, many with per-syscall flag conditions (e.g., `clone` is allowed only with certain `CLONE_*` flags). This has been hardened through 10+ years of production use across millions of containers.

### ⚠️ Finding: This is NOT Docker's default profile

The filename `default.json` is misleading — it implies Docker's standard profile, but it's actually a **no-op allow-all** profile that imposes zero seccomp restrictions. A container using this profile has the same kernel surface as `--security-opt seccomp=unconfined` or no seccomp flag at all.

**Recommendation:** Rename to `allow-all.json` or replace with a copy of Docker's actual default profile from the [moby project](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json). If the intent is to use Docker's built-in default (not a custom profile), simply omit the `security_opt: [seccomp:...]` line from docker-compose.yml — Docker applies its default automatically.

---

## 3. `reviewer-strict.json` — Audit

### Current content

```json
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
    "syscalls": [
        {
            "names": [
                "socket", "connect", "clone", "clone3", "execveat",
                "ptrace", "process_vm_readv", "process_vm_writev",
                "keyctl", "add_key", "request_key",
                "swapon", "swapoff",
                "mount", "umount2", "pivot_root",
                "kexec_load", "kexec_file_load"
            ],
            "action": "SCMP_ACT_ERRNO",
            "args": [],
            "comment": "Blocked: reviewers only read code and call LLM API"
        }
    ]
}
```

### Verification: blocked syscalls

| Syscall | Blocked? | Correct? | Notes |
|---------|----------|----------|-------|
| `mount` | ✅ | ✅ | Dangerous — container escape vector |
| `umount2` | ✅ | ✅ | Dangerous — container escape vector |
| `pivot_root` | ✅ | ✅ | Dangerous — container escape vector |
| `ptrace` | ✅ | ✅ | Dangerous — privilege escalation |
| `perf_event_open` | ❌ Not blocked | ⚠️ Should be blocked | Information leak / side-channel |
| `bpf` | ❌ Not blocked | ⚠️ Should be blocked | Kernel introspection, container escape |
| `kexec_load` | ✅ | ✅ | Kernel execution |
| `kexec_file_load` | ✅ | ✅ | Kernel execution |
| `swapon`/`swapoff` | ✅ | ✅ | System resource manipulation |
| `keyctl`/`add_key`/`request_key` | ✅ | ✅ | Kernel keyring — container escape vector |
| `process_vm_readv`/`writev` | ✅ | ✅ | Cross-process memory access |

### 🔴 CRITICAL FINDING 1: `clone` + `clone3` blocked — JVM cannot start

The reviewer container uses `FROM eclipse-temulin:21-jdk` and runs `java -jar /app/app.jar` as its ENTRYPOINT. The JVM requires `clone` and/or `clone3` for POSIX thread creation via `pthread_create`. The JVM creates multiple threads at startup:

- Main thread
- Garbage collector threads (parallel/multi-threaded GC)
- JIT compiler threads (C1/C2 compilers)
- Signal dispatcher thread
- Reference handler thread
- Finalizer thread

Blocking `clone`/`clone3` causes the JVM to fail immediately on startup with errors like:

```
# Cannot create GC thread. Out of system resources.
# Unable to create native thread — possibly the process resources exhausted
Error occurred during initialization of VM
java.lang.OutOfMemoryError: unable to create native thread
```

**Impact:** The reviewer container is **completely non-functional**. It cannot even begin its startup sequence.

**Fix:** Remove `clone` and `clone3` from the blocked list. The JVM needs these syscalls. The risk is minimal in a container that already has filesystem read-only mounts, no network access, and no untrusted-code execution.

### 🔴 CRITICAL FINDING 2: `socket` + `connect` blocked — cannot reach Privacy Router

The reviewer container is configured with `LLM_PROXY_URL=http://privacy-router:8080` and is attached to the `echelon-internal` Docker bridge network. To make API calls through the Privacy Router, the Spring Boot app (Apache HttpClient / OkHttp / URLConnection) must call:

1. `socket(AF_INET, SOCK_STREAM, 0)` — create a TCP socket
2. `connect(sockfd, {sa_family=AF_INET, sin_port=8080, ...})` — connect to privacy-router:8080

Blocking `socket` and `connect` prevents ALL TCP/UDP communication, including internal Docker networking. The reviewer's core functionality (calling LLM APIs through the proxy) is impossible.

**Note:** The original design intent was to enforce "no direct outbound internet access," which is a valid goal. However, this should be enforced at the **Docker network layer** (`--network none`), not via seccomp. The reviewer needs internal-cluster communication (Privacy Router, Redis).

**Fix:** Remove `socket` and `connect` from the blocked list. Enforce network restrictions via Docker's `--network` flag and network policies instead.

### ⚠️ Finding 3: `execveat` blocked — breaks subprocess creation

While the reviewer app may not explicitly spawn subprocesses, Spring Boot and the JVM can use `execveat` (or `execve`) for:

- `Runtime.exec()` / `ProcessBuilder` — if any library or framework code spawns a process
- `java` launcher options that rely on forking
- JVM crash handler (HSDB, `jstack`-style tools)

**Impact:** Milder than findings 1 and 2, but could cause silent failures in error paths or library code. If the reviewer app truly never spawns subprocesses, blocking `execveat` is acceptable but fragile.

**Recommendation:** Remove `execveat` from the blocked list unless there's a specific (verified) requirement to block subprocess execution.

### Summary of required fixes

To make `reviewer-strict.json` compatible with the JVM-based reviewer container:

```
REMOVE from blocked list:  clone, clone3, socket, connect, execveat
KEEP blocked:               ptrace, process_vm_readv, process_vm_writev,
                            keyctl, add_key, request_key,
                            swapon, swapoff,
                            mount, umount2, pivot_root,
                            kexec_load, kexec_file_load
ADD to blocked list:        perf_event_open, bpf
```

---

## 4. Architecture comparison

| Concern | `default.json` (current) | Docker default (moby v27.4.1) | `reviewer-strict.json` (current) |
|---------|------------------------|-------------------------------|----------------------------------|
| Approach | Allow-all | Deny-by-default | Allow-all with blacklist |
| Attack surface | Full kernel (~440+ syscalls) | ~88 blocked, 352 allowed | 18 syscalls blocked (but JVM broken) |
| JVM compatible | ✅ Yes | ✅ Yes | 🔴 No (clone blocked) |
| Network blocked | ❌ No | ❌ No (socket/connect allowed) | 🔴 Yes (breaks proxy calls) |
| Threat coverage | None | Standard container hardening | Intent good, execution broken |

---

## 5. Recommendations

### Immediate (blocking Issue #73)

1. **Fix `reviewer-strict.json`**: Remove `clone`, `clone3`, `socket`, `connect`, `execveat` from the blocked list. Add `perf_event_open` and `bpf`. The reviewer still gets meaningful protection from `ptrace`, `process_vm_readv/writev`, `mount`, `keyctl`, `swap*`, `kexec*`, `bpf`, and `perf_event_open`.

2. **Rename `default.json`**: Either rename to `permissive.json` or replace it with Docker's actual default profile. The current name creates false confidence.

### Short-term (follow-up issues)

3. **Network enforcement**: Move network restriction to Docker network layer. The reviewer container should use a separate Docker network without internet gateway (`--network none` or a network with default-deny egress), while allowing internal communication with Privacy Router and Redis.

4. **Consider restrict-to-allowlist approach**: For Phase 2 hardening, consider switching `reviewer-strict.json` to a deny-by-default model (`defaultAction: SCMP_ACT_ERRNO`) with a JVM-tested allowlist (~120-150 syscalls). This dramatically reduces the kernel attack surface.

5. **Add integration test**: Write a Testcontainers test that starts the reviewer container with the seccomp profile and verifies it can:
   - Start the JVM successfully
   - Connect to Privacy Router
   - Process a code-review request

---

## 6. References

- Docker default seccomp profile (moby v27.4.1): https://github.com/moby/moby/blob/master/profiles/seccomp/default.json
- Docker seccomp documentation: https://docs.docker.com/engine/security/seccomp/
- Seccomp man page: `man 2 seccomp`
- JVM syscall requirements: OpenJDK source (os_linux.cpp — pthread_create uses clone with CLONE_THREAD|CLONE_SIGHAND|CLONE_VM|CLONE_SETTLS)
- Gap analysis reference: `gap-analysis.md` lines 310-322 (adversarial correction flagging this issue)
- Original implementation: `swarm/ECH-50-seccomp-hardening` (commit fa758a1)
