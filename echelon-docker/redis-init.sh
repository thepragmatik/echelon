#!/bin/sh
echo "Creating Redis streams..."
redis-cli -h localhost XGROUP CREATE tasks:build builders $ MKSTREAM 2>/dev/null || true
redis-cli -h localhost XGROUP CREATE tasks:review reviewers $ MKSTREAM 2>/dev/null || true
redis-cli -h localhost XGROUP CREATE results:build builders $ MKSTREAM 2>/dev/null || true
redis-cli -h localhost XGROUP CREATE results:review reviewers $ MKSTREAM 2>/dev/null || true
echo "Streams initialized"
