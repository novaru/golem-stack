#!/bin/bash
# Quick algorithm switcher for GOLEM Load Balancer
# Usage: ./switch-algorithm.sh <algorithm>
# Algorithms: roundrobin, leastconn, weighted

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/golem-config.json"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validate input
if [ $# -eq 0 ]; then
    echo -e "${RED}[ERROR] Error: Algorithm not specified${NC}"
    echo ""
    echo "Usage: $0 <algorithm>"
    echo ""
    echo "Available algorithms:"
    echo "  ${BLUE}roundrobin${NC}  - Distributes requests in round-robin fashion"
    echo "  ${BLUE}leastconn${NC}   - Routes to backend with fewest active connections"
    echo "  ${BLUE}weighted${NC}    - Weighted distribution based on backend capacity"
    echo ""
    echo "Example:"
    echo "  $0 leastconn"
    exit 1
fi

ALGORITHM=$1

# Validate algorithm
case $ALGORITHM in
    roundrobin|leastconn|weighted)
        ;;
    *)
        echo -e "${RED}[ERROR] Invalid algorithm: $ALGORITHM${NC}"
        echo "Valid options: roundrobin, leastconn, weighted"
        exit 1
        ;;
esac

echo "======================================"
echo "[SWITCHING] GOLEM Algorithm Switcher"
echo "======================================"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}[ERROR] Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Backup current config
BACKUP_FILE="$SCRIPT_DIR/.golem-config.backup.$(date +%Y%m%d_%H%M%S).json"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${YELLOW}[INFO] Backed up config to: $(basename $BACKUP_FILE)${NC}"

# Update config
echo -e "${YELLOW}[CONFIG] Updating algorithm to: ${BLUE}$ALGORITHM${NC}"
if command -v jq &> /dev/null; then
    # Use jq if available (better JSON handling)
    jq ".method = \"$ALGORITHM\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
    # Fallback to sed
    sed -i "s/\"method\": \".*\"/\"method\": \"$ALGORITHM\"/" "$CONFIG_FILE"
fi

# Show updated config
echo ""
echo "Updated configuration:"
if command -v jq &> /dev/null; then
    jq '{method: .method, backends: .backends}' "$CONFIG_FILE"
else
    cat "$CONFIG_FILE"
fi
echo ""

# Restart GOLEM
echo -e "${YELLOW}[SWITCHING] Restarting GOLEM load balancer...${NC}"

# Check if using prod or regular compose file
if [ -f "$COMPOSE_FILE" ]; then
    docker compose -f "$COMPOSE_FILE" restart golem
else
    # Fallback to docker-compose.yml
    docker compose restart golem
fi

# Wait for GOLEM to be ready
echo -e "${YELLOW}[WAIT] Waiting for GOLEM to be ready...${NC}"
sleep 5

# Verify
MAX_RETRIES=6
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:8000/metrics > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] GOLEM is ready with algorithm: ${BLUE}$ALGORITHM${NC}"
        echo ""
        echo "======================================"
        echo "Next steps:"
        echo ""
        echo "1. Test the load balancer:"
        echo "   ${BLUE}curl http://localhost:8000/api/files${NC}"
        echo ""
        echo "2. View metrics:"
        echo "   ${BLUE}curl http://localhost:8000/metrics | grep golem_balancer_info${NC}"
        echo ""
        echo "3. Send test traffic:"
        echo "   ${BLUE}wrk -t2 -c20 -d30s http://localhost:8000${NC}"
        echo ""
        echo "4. View Grafana dashboard:"
        echo "   ${BLUE}http://localhost:3031${NC} (or https://grafana.novaru.my.id)"
        echo ""
        echo "======================================"
        echo ""
        echo "To restore previous config:"
        echo "  cp $BACKUP_FILE $CONFIG_FILE"
        echo "  docker compose restart golem"
        exit 0
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

echo -e "${RED}[WARNING]  GOLEM might not be ready yet. Check logs:${NC}"
echo "  docker compose logs golem"
exit 1
