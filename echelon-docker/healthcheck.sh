#!/bin/bash
# Privacy Router health check
# Returns 0 if the router responds, 1 otherwise
curl -sf http://localhost:8080/health || exit 1
