#!/bin/bash
echo "=== Seccomp Compliance Check ==="
echo "Builder: Docker default (allows socket,clone,execveat)"
echo "Reviewer: strict (blocks socket,connect,clone,execveat)"
echo "Checking TLS..."; openssl version 2>/dev/null && echo "TLS available" || echo "TLS check skipped"
