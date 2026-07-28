# Quick Start Guide

Get Echelon running and process your first task in 10 minutes.

## Prerequisites

- Java 21+ ([Eclipse Temurin](https://adoptium.net/))
- Maven 3.9+
- Docker Desktop
- Git

## 1. Clone and Build

```bash
git clone https://github.com/thepragmatik/echelon.git
cd echelon
mvn test
```

Expected output: `BUILD SUCCESS`

## 2. Configure

```bash
cp .env.example .env
# Edit .env and set your GH_TOKEN
```

See the [Configuration Guide](../reference/configuration.md) for details.

## 3. Start Services

```bash
docker compose -f echelon-docker/docker-compose.yml --profile managers up -d
```

Verify: `curl http://localhost:8080/health` should return 200.

## 4. Run Verification

```bash
bash scripts/dogfood.sh
```

Expected: All PASS, gate passes.

## 5. Submit Your First Task

```bash
# Push a task to the build stream
docker compose -f echelon-docker/docker-compose.yml exec -T redis-primary redis-cli \
  XADD tasks:build '*' taskId "my-first-task" issueUrl "https://github.com/YOUR_USER/YOUR_REPO/issues/1" priority "5"
```

## 6. Check Results

```bash
# Check the results stream
docker compose -f echelon-docker/docker-compose.yml exec -T redis-primary redis-cli \
  XLEN results:review
```

## Next Steps

- [Operations Guide](operations.md) — full setup reference
- [Architecture Whitepaper](../whitepaper/echelon-architecture.md) — design philosophy
- [Quality Case](../quality-case.md) — why Echelon is production-ready
