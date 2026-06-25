#!/bin/bash
echo "Echelon Health Check"
echo "===================="
echo "Redis: $(docker compose exec redis redis-cli ping)"
echo "Tasks pending: $(docker compose exec redis redis-cli XLEN tasks:build)"
echo "Reviews pending: $(docker compose exec redis redis-cli XLEN tasks:review)"
