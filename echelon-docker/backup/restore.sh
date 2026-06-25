#!/bin/bash
SNAPSHOT=$1
echo "Restoring Redis from ${SNAPSHOT}"
docker cp ${SNAPSHOT} echelon-redis-primary:/data/dump.rdb
docker exec echelon-redis-primary redis-cli CONFIG SET dir /data
docker exec echelon-redis-primary redis-cli DEBUG CHANGE-REPL-ID
echo "Restore complete. Restart Redis: docker compose restart redis-primary"
