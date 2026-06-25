#!/bin/bash
BACKUP_DIR=${1:-/backups}
DATE=$(date +%Y%m%d-%H%M%S)
echo "Backing up Redis to ${BACKUP_DIR}/${DATE}.rdb"
docker exec echelon-redis-primary redis-cli SAVE
docker cp echelon-redis-primary:/data/dump.rdb ${BACKUP_DIR}/${DATE}.rdb
echo "Redis RDB snapshot: ${BACKUP_DIR}/${DATE}.rdb ($(wc -c < ${BACKUP_DIR}/${DATE}.rdb) bytes)"
