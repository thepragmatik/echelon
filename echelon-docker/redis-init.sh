#!/bin/bash
set -euo pipefail
REDIS_CLI="${REDIS_CLI:-redis-cli}"
WAIT=5

echo "Initializing Echelon Redis streams and consumer groups..."

# Core task streams
$REDIS_CLI XGROUP CREATE tasks:build builders $ MKSTREAM 2>/dev/null || echo "tasks:build already exists"
$REDIS_CLI XGROUP CREATE tasks:review reviewers $ MKSTREAM 2>/dev/null || echo "tasks:review already exists"

# Worker result streams
$REDIS_CLI XGROUP CREATE results:build collectors $ MKSTREAM 2>/dev/null || echo "results:build already exists"
$REDIS_CLI XGROUP CREATE results:review collectors $ MKSTREAM 2>/dev/null || echo "results:review already exists"

# Governance event streams (appended)
$REDIS_CLI XGROUP CREATE events:governance collectors $ MKSTREAM 2>/dev/null || echo "events:governance already exists"
$REDIS_CLI XGROUP CREATE events:budget collectors $ MKSTREAM 2>/dev/null || echo "events:budget already exists"
$REDIS_CLI XGROUP CREATE events:cost collectors $ MKSTREAM 2>/dev/null || echo "events:cost already exists"

echo "Redis initialization complete."

# Verify
echo "=== Streams ==="
$REDIS_CLI XINFO STREAM tasks:build | head -5
$REDIS_CLI XINFO STREAM tasks:review | head -5
$REDIS_CLI XINFO STREAM events:governance | head -5
$REDIS_CLI XINFO STREAM events:budget | head -5
$REDIS_CLI XINFO STREAM events:cost | head -5
