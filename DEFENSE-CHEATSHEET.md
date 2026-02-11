# Thesis Defense Cheatsheet

## Quick Reference Commands for Live Demonstration

---

## 1. DATABASE OPERATIONS (PostgreSQL in Docker)

### Connect to PostgreSQL Container
```bash
docker exec -it postgres psql -U postgres -d filemanager
```

### Show All Tables
```sql
\dt
```

### Show Table Structure
```sql
\d+ files
\d+ <table_name>
```

### View Table Contents
```sql
SELECT * FROM files;
SELECT * FROM files LIMIT 10;
```

### Count Records
```sql
SELECT COUNT(*) FROM files;
```

### Show Database Connections
```sql
SELECT pid, usename, application_name, client_addr, state 
FROM pg_stat_activity 
WHERE datname = 'filemanager';
```

### Exit PostgreSQL
```sql
\q
```

---

## 2. DOCKER & CONTAINER MANAGEMENT

### Show All Running Containers
```bash
docker ps
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Show Container Resource Usage
```bash
docker stats --no-stream
docker stats
```

### Check Container Logs
```bash
docker logs golem -n 50
docker logs app1 -n 50
docker logs app2 -n 50
docker logs app3 -n 50
docker logs postgres -n 50
```

### Follow Live Logs (Show Load Balancer in Action)
```bash
docker logs -f golem
```

### Check Container Health Status
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
docker inspect --format='{{.State.Health.Status}}' golem
```

### View Container Resource Limits
```bash
docker inspect app1 | grep -A 10 "Resources"
docker inspect app2 | grep -A 10 "Resources"
docker inspect app3 | grep -A 10 "Resources"
```

---

## 3. LOAD BALANCER DEMONSTRATION

### Show Load Balancer Configuration
```bash
cat golem-config.json
```

### View Load Balancer Metrics
```bash
curl http://localhost:8000/metrics
```

### Test Load Distribution (Single Request)
```bash
curl -s http://localhost:8000/api/health | jq
```

### Test Load Distribution (Multiple Requests - Shows Distribution)
```bash
for i in {1..20}; do 
  curl -s http://localhost:8000/api/health | jq -r '.instance_id'
done | sort | uniq -c
```

### Demonstrate Request Distribution with Timing
```bash
for i in {1..10}; do 
  echo "Request $i:"
  curl -s http://localhost:8000/api/health | jq '.instance_id, .timestamp'
  sleep 0.5
done
```

### Test Direct Backend Access (Bypassing Load Balancer)
```bash
# Direct to app1
curl -s http://localhost:3001/api/health | jq

# Direct to app2
curl -s http://localhost:3002/api/health | jq

# Direct to app3
curl -s http://localhost:3003/api/health | jq
```

---

## 4. LOAD TESTING & PERFORMANCE

### Quick Load Test (10 concurrent requests)
```bash
seq 1 10 | xargs -P 10 -I {} curl -s http://localhost:8000/api/health > /dev/null && echo "10 requests completed"
```

### Load Test with Results (100 requests, 10 concurrent)
```bash
echo "Starting load test..."
for i in {1..100}; do 
  curl -s http://localhost:8000/api/health | jq -r '.instance_id' &
  if (( i % 10 == 0 )); then wait; fi
done | sort | uniq -c
```

### Simple Load Test with Apache Bench (if available)
```bash
ab -n 1000 -c 10 http://localhost:8000/api/health
```

### Using wrk for Advanced Load Testing
```bash
wrk -t4 -c100 -d30s http://localhost:8000/api/health
```

---

## 5. DEMONSTRATE SINGLE INSTANCE vs LOAD BALANCED

### A. Single Instance (Direct Connection - NO Load Balancing)
```bash
echo "=== SINGLE INSTANCE (Direct to app1) ==="
for i in {1..20}; do 
  curl -s http://localhost:3001/api/health | jq -r '.instance_id'
done | sort | uniq -c
echo "Notice: ALL requests go to app1"
```

### B. Load Balanced (Through Golem)
```bash
echo "=== LOAD BALANCED (Through Golem) ==="
for i in {1..20}; do 
  curl -s http://localhost:8000/api/health | jq -r '.instance_id'
done | sort | uniq -c
echo "Notice: Requests are DISTRIBUTED across app1, app2, app3"
```

### Side-by-Side Comparison
```bash
echo "=== COMPARISON ==="
echo ""
echo "Direct to app1 (NO Load Balancer):"
for i in {1..10}; do curl -s http://localhost:3001/api/health | jq -r '.instance_id'; done | sort | uniq -c
echo ""
echo "Through Golem Load Balancer:"
for i in {1..10}; do curl -s http://localhost:8000/api/health | jq -r '.instance_id'; done | sort | uniq -c
```

---

## 6. MONITORING & METRICS

### Check Prometheus Metrics
```bash
curl http://localhost:9091/api/v1/targets | jq
```

### View Golem Metrics (Prometheus Format)
```bash
curl http://localhost:8000/metrics
```

### Query Request Distribution from Prometheus
```bash
curl -G 'http://localhost:9091/api/v1/query' \
  --data-urlencode 'query=golem_backend_requests_total' | jq
```

### Access Grafana Dashboard
```bash
echo "Grafana: http://localhost:3031"
echo "Username: admin"
echo "Password: admin"
```

### View cAdvisor Container Stats
```bash
curl -s http://localhost:8080/api/v1.3/docker/ | jq '.[] | {name: .name, cpu: .stats[0].cpu.usage.total}'
```

---

## 7. SYSTEM ARCHITECTURE DEMONSTRATION

### Show Network Architecture
```bash
docker network ls
docker network inspect golem-network | jq '.[0].Containers'
```

### Show All Services and Their Relationships
```bash
docker-compose -f docker-compose.prod.yml config --services
```

### Show Service Dependencies
```bash
docker-compose -f docker-compose.prod.yml config | grep -A 5 "depends_on"
```

### Show Volume Mounts (Shared Storage)
```bash
docker volume ls
docker inspect shared-uploads | jq
```

---

## 8. FAILOVER & HIGH AVAILABILITY DEMONSTRATION

### Simulate Backend Failure
```bash
# Stop one backend
docker stop app1

# Test load balancer (should route to app2 and app3)
for i in {1..10}; do 
  curl -s http://localhost:8000/api/health | jq -r '.instance_id'
done | sort | uniq -c

# Restart the backend
docker start app1
```

### Check Health Status During Failure
```bash
curl http://localhost:8000/metrics | grep backend_healthy
```

---

## 9. FILE OPERATIONS DEMONSTRATION

### Upload File Through Load Balancer
```bash
# Create test file
echo "Test content for thesis defense" > test-file.txt

# Upload through load balancer
curl -X POST http://localhost:8000/api/files \
  -F "file=@test-file.txt" \
  -F "description=Thesis defense test" | jq
```

### List Files
```bash
curl -s http://localhost:8000/api/files | jq
```

### Verify File in Database
```bash
docker exec -it postgres psql -U postgres -d filemanager -c "SELECT id, filename, description, created_at FROM files ORDER BY created_at DESC LIMIT 5;"
```

### Check Shared Volume
```bash
docker exec app1 ls -lah /var/www/html/writable/uploads
```

---

## 10. PERFORMANCE COMPARISON

### Measure Response Time - Direct Access
```bash
time curl -s http://localhost:3001/api/health > /dev/null
```

### Measure Response Time - Through Load Balancer
```bash
time curl -s http://localhost:8000/api/health > /dev/null
```

### Concurrent Request Handling
```bash
# Test with load balancer
time (for i in {1..50}; do curl -s http://localhost:8000/api/health > /dev/null & done; wait)

# Test direct (single instance)
time (for i in {1..50}; do curl -s http://localhost:3001/api/health > /dev/null & done; wait)
```

---

## 11. CONFIGURATION INSPECTION

### Show Docker Compose Configuration
```bash
cat docker-compose.prod.yml
```

### Show Resource Limits
```bash
docker inspect app1 | jq '.[0].HostConfig.Memory'
docker inspect app1 | jq '.[0].HostConfig.NanoCpus'
```

### Show Environment Variables
```bash
docker exec app1 env | grep -E "INSTANCE_ID|APP_NAME|DB_"
docker exec app2 env | grep -E "INSTANCE_ID|APP_NAME|DB_"
docker exec app3 env | grep -E "INSTANCE_ID|APP_NAME|DB_"
```

---

## 12. QUICK DEMO SCRIPT

### Complete Demonstration in One Command
```bash
#!/bin/bash

echo "=== THESIS DEFENSE DEMONSTRATION ==="
echo ""

echo "1. CONTAINER STATUS:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""

echo "2. LOAD BALANCER CONFIG:"
cat golem-config.json
echo ""

echo "3. DATABASE CONNECTION TEST:"
docker exec postgres psql -U postgres -d filemanager -c "SELECT COUNT(*) as total_files FROM files;"
echo ""

echo "4. LOAD DISTRIBUTION TEST (20 requests):"
for i in {1..20}; do 
  curl -s http://localhost:8000/api/health | jq -r '.instance_id'
done | sort | uniq -c
echo ""

echo "5. SINGLE INSTANCE vs LOAD BALANCED:"
echo "   Direct to app1:"
for i in {1..10}; do curl -s http://localhost:3001/api/health | jq -r '.instance_id'; done | sort | uniq -c
echo ""
echo "   Through Load Balancer:"
for i in {1..10}; do curl -s http://localhost:8000/api/health | jq -r '.instance_id'; done | sort | uniq -c
echo ""

echo "6. RESOURCE USAGE:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""

echo "=== DEMONSTRATION COMPLETE ==="
```

Save as `demo.sh`, make executable with `chmod +x demo.sh`, and run with `./demo.sh`

---

## 13. TROUBLESHOOTING COMMANDS

### Check if Services are Responding
```bash
curl -I http://localhost:8000/api/health
curl -I http://localhost:3001/api/health
curl -I http://localhost:3002/api/health
curl -I http://localhost:3003/api/health
```

### Check Database Connectivity
```bash
docker exec postgres pg_isready -U postgres
```

### View Full System Logs
```bash
docker-compose -f docker-compose.prod.yml logs --tail=50
```

### Restart All Services
```bash
docker-compose -f docker-compose.prod.yml restart
```

---

## 14. KEY TALKING POINTS

1. **Scalability**: Show how adding more backend instances improves capacity
2. **High Availability**: Demonstrate failover when one instance goes down
3. **Load Distribution**: Prove requests are distributed evenly
4. **Resource Efficiency**: Show different resource allocations (app1: 2GB, app2: 1GB, app3: 512MB)
5. **Monitoring**: Real-time metrics with Prometheus and Grafana
6. **Shared State**: Database and file storage shared across all instances

---

## 15. COMMON QUESTIONS & ANSWERS

**Q: How do you prove the load balancer is working?**
```bash
for i in {1..30}; do curl -s http://localhost:8000/api/health | jq -r '.instance_id'; done | sort | uniq -c
```

**Q: What happens if one backend fails?**
```bash
docker stop app1
curl http://localhost:8000/metrics | grep backend_healthy
docker start app1
```

**Q: How do you ensure data consistency?**
```bash
docker exec postgres psql -U postgres -d filemanager -c "\dt"
docker exec postgres psql -U postgres -d filemanager -c "SELECT * FROM files LIMIT 5;"
```

**Q: What's the overhead of load balancing?**
```bash
# Measure both and compare
time curl -s http://localhost:3001/api/health > /dev/null
time curl -s http://localhost:8000/api/health > /dev/null
```

---

## EMERGENCY COMMANDS

### Restart Everything
```bash
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d
```

### Check All Health Statuses
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Quick System Reset
```bash
docker-compose -f docker-compose.prod.yml restart golem app1 app2 app3
```

---

Good luck with your defense!
