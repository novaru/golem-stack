# GOLEM Stack - Quick Reference

## Quick Commands

### Start All Services
```bash
cd /home/novaru/projects/golem/golem-stack
./start.sh
```

Or manually:
```bash
docker compose up -d
```

### Stop All Services
```bash
./stop.sh
```

Or manually:
```bash
docker compose down
```

### Check Status
```bash
docker compose ps
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific services
docker compose logs -f app1 app2 app3
docker compose logs -f golem
```

## Service Endpoints

| Service | External Port | Internal | URL |
|---------|---------------|----------|-----|
| **GOLEM** | 8000 | - | http://localhost:8000 |
| **App 1** | 3001 | 3000 | http://localhost:3001 |
| **App 2** | 3002 | 3000 | http://localhost:3002 |
| **App 3** | 3003 | 3000 | http://localhost:3003 |
| **PostgreSQL** | 5433 | 5432 | localhost:5433 |
| **Prometheus** | 9091 | 9090 | http://localhost:9091 |
| **Grafana** | 3031 | 3000 | http://localhost:3031 |
| **cAdvisor** | 8080 | 8080 | http://localhost:8080 |

## Testing Commands

### Test Health Endpoints
```bash
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health
```

### Test Through Load Balancer
```bash
curl http://localhost:8000/health
```

### Check Metrics
```bash
curl http://localhost:8000/metrics | grep golem_
```

### Upload File Test
```bash
echo "test" > test.txt
curl -X POST -F "file=@test.txt" http://localhost:8000/api/files
```

## Troubleshooting

### Rebuild Services
```bash
docker compose up -d --build
```

### Restart Specific Service
```bash
docker compose restart app1
docker compose restart golem
```

### Clean Restart
```bash
docker compose down -v
docker compose up -d --build
```

### View Container Logs
```bash
docker compose logs --tail=50 app1
```

### Execute Commands in Container
```bash
docker compose exec app1 sh
docker compose exec postgres psql -U postgres -d filemanager
```

## Files Modified

- `docker-compose.yml` - Fixed build paths from `file-manager-api` to `example-api`
- `golem-config.json` - Created with Docker network URLs
- `start.sh` - Automated startup script
- `stop.sh` - Automated stop script
- `STARTUP.md` - Complete documentation

## Integration with GOLEM Development

### For Docker Stack (containerized GOLEM)
Uses `golem-config.json` with internal Docker network URLs:
- http://app1:3000
- http://app2:3000
- http://app3:3000

### For Local Development (native GOLEM)
Use `/golem/config.json` with host network URLs:
- http://localhost:3001
- http://localhost:3002
- http://localhost:3003

## Next Steps

1. Start the stack: `./start.sh`
2. Wait for services to be healthy (~30 seconds)
3. Test endpoints: `curl http://localhost:3001/health`
4. Ready for Phase 2 load testing!
