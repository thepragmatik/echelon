# Seccomp Profiles

## Builder containers
Uses Docker default seccomp profile (no custom restriction). Maven, Gradle, sbt need:
- `socket`+`connect` — dependency downloads
- `clone`+`clone3` — forked processes
- `execve`+`execveat` — compiler invocations
- `futex`+`epoll_wait` — thread synchronization

## Reviewer containers
Uses `reviewer-strict.json` which blocks:
- `socket`, `connect` — no direct network (API calls go through Privacy Router)
- `clone`, `clone3`, `execveat` — no forking or executing binaries
- `ptrace`, `process_vm_readv` — privilege escalation vectors
- Filesystem-related dangerous syscalls (mount, pivot_root, swapon)
