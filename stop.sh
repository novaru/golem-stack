#!/bin/bash

set -e

COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
fi

echo "Stopping GOLEM Stack..."

cd /home/novaru/projects/golem/golem-stack

$COMPOSE_CMD down

echo "Stack stopped!"
echo ""
echo "To remove volumes as well: $COMPOSE_CMD down -v"
