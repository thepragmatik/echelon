#!/bin/bash
echo "=== Echelon Load Test ==="
echo "Dispatching 5 concurrent tasks..."
for i in $(seq 1 5); do
  echo "  Task $i: Pushing to tasks:build"
  redis-cli -h localhost XADD tasks:build * taskId "load-${i}" type "implement" priority 1 &
done
wait
echo "Tasks dispatched. Check: redis-cli XLEN tasks:build"
