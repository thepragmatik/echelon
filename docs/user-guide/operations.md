# Operations Guide

Day-to-day management of an Echelon deployment.

## Health Checks

```bash
# Check all services
docker compose ps

# Check individual service health
curl http://localhost:8080/actuator/health
curl http://localhost:9090/-/healthy

# Check Redis cluster status
docker compose exec redis-primary redis-cli INFO replication
docker compose exec redis-sentinel redis-cli SENTINEL masters
```

## Logging

```bash
# Follow all logs
docker compose logs -f

# Follow a specific service
docker compose logs -f builder
docker compose logs -f privacy-router

# Check implementer output
tail -f /tmp/echelon-pi-output-*.log
```

## Monitoring

Echelon exposes Prometheus metrics at `/actuator/prometheus`:

| Metric | Description |
|--------|-------------|
| `echelon_policy_decisions_total` | PolicyEngine decisions by action + verdict |
| `echelon_budget_remaining` | Remaining token budget per agent |
| `echelon_tasks_queued` | Tasks waiting in Redis streams |
| `echelon_tasks_completed` | Tasks completed successfully |
| `echelon_pipeline_duration` | Pipeline execution time in seconds |

## Backup and Recovery

```bash
# Backup Redis data (AOF persistence is on)
docker compose exec redis-primary redis-cli BGSAVE

# Restore from snapshot
docker compose stop redis-primary
cp /var/lib/redis/dump.rdb /var/lib/redis/dump.rdb.bak
docker compose start redis-primary

# Full system restart
docker compose down
docker compose up -d
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Builder won't start | Redis unreachable | Check `docker compose ps redis-primary` |
| Tasks queue but don't execute | PolicyEngine denying action | Check `agent-types.yaml` permits |
| PR not created | GitHub token missing | Check `PRIVACY_ROUTER_API_KEY` env var |
| Review stalled | Reviewer container OOM | Increase Docker memory limit |
