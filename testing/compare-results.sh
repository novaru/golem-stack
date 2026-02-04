#!/usr/bin/env bash
#
# Compare results from multiple GOLEM test runs
# Usage: ./testing/compare-results.sh results/dir1 results/dir2 results/dir3
#
# Examples:
#   # Compare specific test runs
#   ./testing/compare-results.sh \
#     testing/results/20260204_143000_roundrobin \
#     testing/results/20260204_143530_leastconn \
#     testing/results/20260204_144100_weighted
#
#   # Compare all tests from a specific date
#   ./testing/compare-results.sh testing/results/20260204_*
#
#   # Compare latest test for each algorithm
#   ./testing/compare-results.sh \
#     testing/results/*_roundrobin | tail -1 \
#     testing/results/*_leastconn | tail -1 \
#     testing/results/*_weighted | tail -1

set -euo pipefail

log_error() { echo "[ERROR] $1"; }
log_info() { echo "[INFO] $1"; }

# Check if at least one result directory is provided
if [ $# -eq 0 ]; then
    log_error "No result directories provided"
    echo ""
    echo "Usage: $0 <result_dir1> [result_dir2] [result_dir3] ..."
    echo ""
    echo "Example:"
    echo "  $0 testing/results/20260204_143000_roundrobin testing/results/20260204_143530_leastconn"
    exit 1
fi

# Check Python3 is available
if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required but not installed"
    exit 1
fi

# Pass all arguments to Python script for comparison
python3 - "$@" << 'PYTHON_COMPARE_END'
import sys
import re
from pathlib import Path

def parse_wrk(filepath):
    """Parse wrk output file and extract metrics"""
    try:
        with open(filepath) as f:
            text = f.read()
    except FileNotFoundError:
        return None
    
    metrics = {}
    
    # Parse requests/sec
    if m := re.search(r'Requests/sec:\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    
    # Parse latency
    if m := re.search(r'Latency\s+(\d+\.\d+)(\w+)', text):
        value = float(m.group(1))
        unit = m.group(2)
        if unit == 's':
            value *= 1000
        metrics['avg_latency'] = value
    
    # Parse P50
    if m := re.search(r'50%\s+(\d+\.\d+)(\w+)', text):
        value = float(m.group(1))
        unit = m.group(2)
        if unit == 's':
            value *= 1000
        metrics['p50_latency'] = value
    
    # Parse P99
    if m := re.search(r'99%\s+(\d+\.\d+)(\w+)', text):
        value = float(m.group(1))
        unit = m.group(2)
        if unit == 's':
            value *= 1000
        metrics['p99_latency'] = value
    
    # Parse total requests
    if m := re.search(r'(\d+) requests in', text):
        metrics['total_requests'] = int(m.group(1))
    
    # Parse errors
    if m := re.search(r'Non-2xx or 3xx responses: (\d+)', text):
        metrics['errors'] = int(m.group(1))
    else:
        metrics['errors'] = 0
    
    return metrics

def extract_algorithm_name(dir_name):
    """Extract algorithm name from directory name"""
    # Format: 20260204_143000_roundrobin
    parts = dir_name.split('_')
    if len(parts) >= 3:
        return '_'.join(parts[2:])  # Handle multi-word algorithm names
    return dir_name

# Parse all result directories
results = []
for result_path in sys.argv[1:]:
    path = Path(result_path)
    
    if not path.exists():
        print(f"[WARN] Directory not found: {result_path}")
        continue
    
    if not path.is_dir():
        print(f"[WARN] Not a directory: {result_path}")
        continue
    
    # Extract algorithm name from folder name
    algo_name = extract_algorithm_name(path.name)
    
    # Parse test results
    test_results_file = path / "test_results.txt"
    metrics = parse_wrk(test_results_file)
    
    if metrics is None:
        print(f"[WARN] Could not parse results from: {result_path}")
        continue
    
    results.append({
        'algorithm': algo_name,
        'path': str(path),
        'metrics': metrics
    })

if not results:
    print("[ERROR] No valid results found to compare")
    sys.exit(1)

# Display comparison table
print()
print("=" * 90)
print("GOLEM ALGORITHM COMPARISON")
print("=" * 90)
print(f"{'Algorithm':<15} | {'Throughput':>12} | {'Avg Lat':>10} | {'P50 Lat':>10} | {'P99 Lat':>10} | {'Errors':>8}")
print("-" * 90)

for result in results:
    algo = result['algorithm']
    m = result['metrics']
    
    print(f"{algo:<15} | {m.get('throughput', 0):>10.2f} r/s | "
          f"{m.get('avg_latency', 0):>8.2f} ms | "
          f"{m.get('p50_latency', 0):>8.2f} ms | "
          f"{m.get('p99_latency', 0):>8.2f} ms | "
          f"{m.get('errors', 0):>8d}")

print("=" * 90)

# Find best performing algorithm
if len(results) > 1:
    best_throughput = max(results, key=lambda x: x['metrics'].get('throughput', 0))
    best_latency = min(results, key=lambda x: x['metrics'].get('avg_latency', float('inf')))
    
    print()
    print("SUMMARY:")
    print(f"  Best Throughput: {best_throughput['algorithm']} ({best_throughput['metrics']['throughput']:.2f} req/s)")
    print(f"  Best Latency:    {best_latency['algorithm']} ({best_latency['metrics']['avg_latency']:.2f} ms)")
    print()

print()
print("Result directories:")
for result in results:
    print(f"  - {result['path']}")
print()

PYTHON_COMPARE_END
