# Echelon Operations Skill

You are operating an Echelon deployment.

## Quick Start
```bash
# Start all services
docker compose -f echelon-docker/docker-compose.yml up -d

# Check health
docker compose ps
curl http://localhost:8080/actuator/health

# View logs
docker compose logs -f builder
docker compose logs -f privacy-router

# Redis streams
docker compose exec redis-primary redis-cli XLEN tasks:build
docker compose exec redis-primary redis-cli XLEN events:governance
```

## Health Checks
- privacy-router: curl http://localhost:8080/health
- Redis: redis-cli ping
- BuildManager: Spring Boot Actuator /actuator/health

## Troubleshooting
- Builder can't reach Privacy Router: check docker network ls, verify echelon-internal network
- Redis connection refused: docker compose logs redis-primary
- Policy denied: check events:governance stream for denial reasons
- Seccomp blocking JVM: check docker inspect reviewer for --security-opt seccomp
