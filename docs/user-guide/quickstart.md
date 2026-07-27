# Quick Start Guide

Get Echelon running in 10 minutes.

## Prerequisites

- Java 21+ ([Eclipse Temurin](https://adoptium.net/))
- Maven 3.9+
- Docker Desktop
- Git

## Installation

```bash
# Clone the repository
git clone https://github.com/thepragmatik/echelon.git
cd echelon

# Build everything
mvn clean compile

# Run tests
mvn test

# Start the infrastructure
docker compose -f echelon-docker/docker-compose.yml up -d
```

## Verify It's Working

```bash
# Check all containers are healthy
docker compose ps

# Check the Privacy Router
curl http://localhost:8080/health

# Check Prometheus metrics
curl http://localhost:8080/actuator/prometheus

# Check Redis streams
docker compose exec redis-primary redis-cli XLEN tasks:build
```

## What Just Happened

1. **Redis cluster** started (primary + replica + sentinel for HA)
2. **Privacy Router** started (credential proxy for LLM calls)
3. **Governance engine** initialized (PolicyEngine, BudgetManager, CostTracker)
4. **Agent workers** are ready (builder + reviewer containers)
