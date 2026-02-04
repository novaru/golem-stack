# GOLEM Testing Suite

Portable testing scripts for comparing load balancing algorithms.

## 📋 Overview

This directory contains testing tools for evaluating GOLEM's load balancing algorithms:
- **Round Robin** - Sequential distribution
- **Least Connections** - Adaptive based on active connections
- **Weighted Round Robin** - Proportional distribution based on backend capacity

## 🎯 Two Testing Workflows

### **Workflow 1: Automated Testing (On VPS)** 🤖
Best for: Running all tests automatically in one go

**Use Case**: You're SSH'd into the VPS and want to test all algorithms at once

**Script**: `run-comparison.sh`

**Requirements**: `wrk`, `curl`, `python3`, `jq`, `docker` (on VPS)

---

### **Workflow 2: Remote Testing (From Client)** 🌐
Best for: Testing from any machine, manual algorithm switching

**Use Case**: VPS is deployed, clients can test remotely without SSH

**Script**: `run-single-test.sh`

**Requirements**: `wrk`, `curl`, `python3`, `jq` (on client - NO docker needed!)

---

## 🚀 Quick Start

### Prerequisites

**On VPS** (for both workflows):
```bash
sudo apt update
sudo apt install wrk jq python3 curl docker.io -y
```

**On Client Machine** (for remote testing only):
```bash
sudo apt update
sudo apt install wrk jq python3 curl -y
# Note: NO docker needed on client!
```

---

## 📖 Workflow 1: Automated Testing (On VPS)

### Use When:
- Running tests directly on the VPS
- Want all 3 algorithms tested automatically
- Have direct access to GOLEM container

### Step 1: SSH to VPS
```bash
dalang shell vps-cf9deb75  # Or your SSH command
cd golem-stack
```

### Step 2: Run Automated Test
```bash
# Default (5MB files, 90s per algorithm, 20 connections)
./testing/run-comparison.sh

# Custom configuration
FILE_SIZE=10485760 TEST_DURATION=120s CONNECTIONS=50 ./testing/run-comparison.sh
```

### Step 3: View Results
```bash
# Results are in testing/results/TIMESTAMP/
ls -la testing/results/

# View summary
cat testing/results/20260204_143000/SUMMARY.txt
```

### What It Does:
1. Tests **Round Robin** (90s)
2. Prompts to delete uploaded files
3. Tests **Least Connections** (90s)
4. Prompts to delete uploaded files
5. Tests **Weighted Round Robin** (90s)
6. Prompts to delete uploaded files
7. Generates comparison table

### Output:
```
======================================================================
GOLEM ALGORITHM COMPARISON RESULTS
======================================================================

ROUNDROBIN      | Throughput:  12.45 req/s | Avg:  1605.23 ms | P99:  2134.56 ms
LEASTCONN       | Throughput:  13.21 req/s | Avg:  1514.78 ms | P99:  2012.34 ms
WEIGHTED        | Throughput:  14.87 req/s | Avg:  1345.12 ms | P99:  1823.45 ms

======================================================================
```

---

## 🌐 Workflow 2: Remote Testing (From Client)

### Use When:
- Testing from your laptop/desktop
- VPS is deployed and accessible
- Want to test one algorithm at a time
- Demonstrating to others (they just need the client script)

### Step 1: Clone Repository (On Client)
```bash
git clone https://github.com/novaru/golem-stack.git
cd golem-stack
```

### Step 2: Test Round Robin
```bash
# SSH to VPS and set algorithm
ssh vps-cf9deb75
cd golem-stack
bash switch-algorithm.sh roundrobin
docker compose -f docker-compose.prod.yml restart golem
exit

# Back on client, run test
GOLEM_URL=http://cf9deb75-ebc2-48aa-af29-966c7ad302d4.svc.dalang.io:8000 \
ALGORITHM=roundrobin \
./testing/run-single-test.sh
```

### Step 3: Test Least Connections
```bash
# SSH to VPS and switch algorithm
ssh vps-cf9deb75
cd golem-stack
bash switch-algorithm.sh leastconn
docker compose -f docker-compose.prod.yml restart golem
exit

# Back on client, run test
GOLEM_URL=http://cf9deb75-ebc2-48aa-af29-966c7ad302d4.svc.dalang.io:8000 \
ALGORITHM=leastconn \
./testing/run-single-test.sh
```

### Step 4: Test Weighted Round Robin
```bash
# SSH to VPS and switch algorithm
ssh vps-cf9deb75
cd golem-stack
bash switch-algorithm.sh weighted
docker compose -f docker-compose.prod.yml restart golem
exit

# Back on client, run test
GOLEM_URL=http://cf9deb75-ebc2-48aa-af29-966c7ad302d4.svc.dalang.io:8000 \
ALGORITHM=weighted \
./testing/run-single-test.sh
```

### Step 5: Compare Results
```bash
./testing/compare-results.sh \
  testing/results/*_roundrobin \
  testing/results/*_leastconn \
  testing/results/*_weighted
```

### Output (Single Test):
```
========================================
TEST RESULTS
========================================
Throughput:         12.45 req/s
Avg Latency:      1605.23 ms
P50 Latency:      1520.11 ms
P99 Latency:      2134.56 ms
Total Requests:       1120
Errors:                  0
========================================
```

### Output (Comparison):
```
==================================================================================
GOLEM ALGORITHM COMPARISON
==================================================================================
Algorithm       |   Throughput | Avg Lat    | P50 Lat    | P99 Lat    | Errors
----------------------------------------------------------------------------------
roundrobin      |    12.45 r/s |  1605.23 ms|  1520.11 ms|  2134.56 ms|       0
leastconn       |    13.21 r/s |  1514.78 ms|  1450.22 ms|  2012.34 ms|       0
weighted        |    14.87 r/s |  1345.12 ms|  1280.45 ms|  1823.45 ms|       0
==================================================================================

SUMMARY:
  Best Throughput: weighted (14.87 req/s)
  Best Latency:    weighted (1345.12 ms)
```

---

## 📁 Results Structure

### Automated Test (run-comparison.sh)
```
testing/results/
└── 20260204_143000/           # Single timestamp for all algorithms
    ├── roundrobin_results.txt
    ├── roundrobin_metrics.txt
    ├── leastconn_results.txt
    ├── leastconn_metrics.txt
    ├── weighted_results.txt
    ├── weighted_metrics.txt
    └── SUMMARY.txt            # Comparison table
```

### Remote Test (run-single-test.sh)
```
testing/results/
├── 20260204_143000_roundrobin/    # Algorithm name in folder
│   ├── test_results.txt
│   ├── metrics.txt
│   ├── uploaded_files.log
│   ├── test.lua
│   └── SUMMARY.txt
├── 20260204_143530_leastconn/
│   └── ...
└── 20260204_144100_weighted/
    └── ...
```

---

## 💾 Disk Space Management

### File Cleanup Prompt

After each test, you'll be prompted:
```
Delete uploaded files from VPS? [y/N]:
```

**Options:**
- **y** - Delete all uploaded files via API (frees ~5GB per test)
- **N** - Keep files (useful for inspection)

### Recommended Strategy

**For 20GB VPS:**
```
Round Robin test:  DELETE → Frees ~5.3GB
Least Conn test:   DELETE → Frees ~5.3GB  
Weighted test:     KEEP   → Uses ~5.3GB (inspect final state)
```

**For larger VPS:**
```
Keep all files → Compare file distribution across backends
```

### Disk Space Estimates

| File Size | Duration | Connections | Est. Throughput | Upload Size |
|-----------|----------|-------------|-----------------|-------------|
| 1MB       | 90s      | 20          | ~15 req/s       | ~1.4 GB     |
| 5MB       | 90s      | 20          | ~12 req/s       | ~5.4 GB     |
| 10MB      | 120s     | 50          | ~10 req/s       | ~12 GB      |

---

## 🛠️ Available Scripts

### 1. `run-comparison.sh` - Automated Testing
**Purpose**: Test all 3 algorithms automatically (on VPS)

**Usage**:
```bash
./testing/run-comparison.sh
FILE_SIZE=1048576 TEST_DURATION=60s CONNECTIONS=10 ./testing/run-comparison.sh
```

**Requires**: Local access to GOLEM container (SSH to VPS)

---

### 2. `run-single-test.sh` - Remote Single Algorithm Test
**Purpose**: Test current algorithm from any client

**Usage**:
```bash
GOLEM_URL=http://vps:8000 ALGORITHM=roundrobin ./testing/run-single-test.sh

# Custom configuration
GOLEM_URL=http://vps:8000 \
ALGORITHM=weighted \
FILE_SIZE=10485760 \
TEST_DURATION=120s \
CONNECTIONS=50 \
./testing/run-single-test.sh
```

**Requires**: Network access to GOLEM, NO docker needed

---

### 3. `compare-results.sh` - Compare Test Results
**Purpose**: Generate comparison table from multiple test runs

**Usage**:
```bash
# Compare specific runs
./testing/compare-results.sh \
  testing/results/20260204_143000_roundrobin \
  testing/results/20260204_143530_leastconn \
  testing/results/20260204_144100_weighted

# Compare all from specific date
./testing/compare-results.sh testing/results/20260204_*
```

---

### 4. `cleanup-uploads.sh` - Manual File Cleanup
**Purpose**: Delete all uploaded files from VPS

**Usage**:
```bash
GOLEM_URL=http://vps:8000 ./testing/cleanup-uploads.sh
```

---

## 📊 Understanding Results

### Metrics Explained

- **Throughput (req/s)**: Requests per second - **higher is better**
- **Avg Latency (ms)**: Average response time - **lower is better**
- **P50 Latency (ms)**: 50th percentile (median) - **lower is better**
- **P99 Latency (ms)**: 99th percentile (worst-case) - **lower is better**
- **Total Requests**: Number of successful requests
- **Errors**: Failed requests (should be 0)

### Expected Results

For **heterogeneous backends** (app1: 2 CPU, app2: 1 CPU, app3: 0.5 CPU):

- **Round Robin**: Fair distribution but may overload weaker backends
- **Least Connections**: Adaptive, should avoid overloaded backends
- **Weighted (3:2:1)**: Should show best throughput/latency
  - App1 receives ~50% of requests
  - App2 receives ~33% of requests
  - App3 receives ~17% of requests

---

## 🛠️ Troubleshooting

### "GOLEM is not responding"
```bash
# Check if GOLEM is running
curl http://vps:8000/health

# If not, start it
ssh vps
cd golem-stack
docker compose -f docker-compose.prod.yml up -d
```

### "wrk: command not found"
```bash
# Ubuntu/Debian
sudo apt install wrk

# Or build from source
git clone https://github.com/wg/wrk.git
cd wrk && make && sudo cp wrk /usr/local/bin/
```

### Algorithm not switching
```bash
# SSH to VPS and check current algorithm
ssh vps
cd golem-stack
cat golem-config.json | jq '.method'

# Manually switch
bash switch-algorithm.sh weighted
docker compose -f docker-compose.prod.yml restart golem

# Verify
curl http://localhost:8000/health
```

### Cleanup not working
```bash
# Check API is accessible
curl -X GET http://vps:8000/api/files

# Manual cleanup
GOLEM_URL=http://vps:8000 ./testing/cleanup-uploads.sh
```

---

## 📝 For Thesis Use

### Collecting Data

**Option 1: Automated (On VPS)**
```bash
ssh vps
cd golem-stack
./testing/run-comparison.sh  # Run once
# Results in testing/results/TIMESTAMP/SUMMARY.txt
```

**Option 2: Remote (From Client)**
```bash
# Test each algorithm separately (follow Workflow 2)
# Then compare
./testing/compare-results.sh testing/results/*_roundrobin testing/results/*_leastconn testing/results/*_weighted
```

### Recommended: Multiple Runs for Consistency
```bash
# Run 3 times, average the results
./testing/run-single-test.sh  # Run 1
sleep 300  # Cool down
./testing/run-single-test.sh  # Run 2
sleep 300
./testing/run-single-test.sh  # Run 3
```

### Graphs for BAB 5

From the results, create:
- **Bar chart**: Throughput comparison (req/s)
- **Bar chart**: P99 Latency comparison (ms)
- **Pie chart**: Load distribution per backend (from Prometheus metrics)

### Prometheus Queries

To analyze load distribution:
```promql
# Total requests per backend
sum by (backend) (golem_requests_total)

# Request rate per backend
sum by (backend) (rate(golem_requests_total[5m]))

# File operations
sum by (operation) (golem_file_operations_total)
```

---

## 📄 Environment Variables

### Both Scripts
| Variable       | Default              | Description                        |
|----------------|----------------------|------------------------------------|
| `FILE_SIZE`    | 5242880 (5MB)        | File size in bytes                 |
| `TEST_DURATION`| 90s                  | Test duration                      |
| `CONNECTIONS`  | 20                   | Concurrent connections             |
| `THREADS`      | 4                    | wrk threads                        |
| `GOLEM_URL`    | http://localhost:8000| GOLEM base URL                     |

### run-single-test.sh Only
| Variable       | Default              | Description                        |
|----------------|----------------------|------------------------------------|
| `ALGORITHM`    | current              | Algorithm name (for results folder)|

---

## ⚠️ Important Notes

1. **Unique Files**: Scripts generate files with unique content (timestamp + thread ID + counter) to avoid duplicate detection

2. **Remote Testing**: `run-single-test.sh` does NOT switch algorithms - you must do it manually via SSH

3. **Cleanup**: Remember to delete uploaded files if VPS disk space is limited

4. **Network Latency**: Remote testing includes network latency between client and VPS (this is expected)

5. **Results Location**: Results are saved locally on the machine running the script

---

## 📚 Examples

### Example 1: Quick Demo (Remote)
```bash
# One-liner for quick test
GOLEM_URL=http://vps:8000 ALGORITHM=roundrobin FILE_SIZE=1048576 TEST_DURATION=30s CONNECTIONS=5 ./testing/run-single-test.sh
```

### Example 2: Thesis Testing (Automated on VPS)
```bash
ssh vps
cd golem-stack
FILE_SIZE=5242880 TEST_DURATION=90s CONNECTIONS=20 ./testing/run-comparison.sh
```

### Example 3: Multiple File Sizes (Remote)
```bash
# Test with 1MB, 5MB, 10MB files
for size in 1048576 5242880 10485760; do
  GOLEM_URL=http://vps:8000 ALGORITHM=weighted FILE_SIZE=$size ./testing/run-single-test.sh
  sleep 60
done
```

---

**Created for**: Febriyan Andriansyah Novaru (@novaru)  
**Thesis**: Load Balancer Architecture for File Service Using Go with Prometheus Monitoring  
**Last Updated**: 2026-02-04
