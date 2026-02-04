#!/bin/bash

set -e

COMPOSE_CMD="docker compose"
if ! command -v docker &> /dev/null; then
    echo "Docker not found!"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
fi

echo "Starting GOLEM Stack..."
echo ""

cd /home/novaru/projects/golem/golem-stack

echo "1. Starting services..."
$COMPOSE_CMD up -d

echo ""
echo "2. Waiting for services to be ready..."
sleep 10

echo ""
echo "3. Checking service status..."
$COMPOSE_CMD ps

echo ""
echo "4. Service URLs:"
echo "   GOLEM Load Balancer: http://localhost:8000"
echo "   App 1 (direct):      http://localhost:3001"
echo "   App 2 (direct):      http://localhost:3002"
echo "   App 3 (direct):      http://localhost:3003"
echo "   Prometheus:          http://localhost:9091"
echo "   Grafana:             http://localhost:3031"
echo "   cAdvisor:            http://localhost:8080"
echo ""
echo "5. Testing endpoints..."

if curl -s http://localhost:3001/health > /dev/null 2>&1; then
    echo "   ✓ App 1 is healthy"
else
    echo "   ✗ App 1 not responding yet (may need more time)"
fi

if curl -s http://localhost:3002/health > /dev/null 2>&1; then
    echo "   ✓ App 2 is healthy"
else
    echo "   ✗ App 2 not responding yet (may need more time)"
fi

if curl -s http://localhost:3003/health > /dev/null 2>&1; then
    echo "   ✓ App 3 is healthy"
else
    echo "   ✗ App 3 not responding yet (may need more time)"
fi

echo ""
echo "Stack started! View logs with: $COMPOSE_CMD logs -f"
