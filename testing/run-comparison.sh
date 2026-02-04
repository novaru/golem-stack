#!/usr/bin/env bash
#
# GOLEM Load Balancer Algorithm Comparison Test
# Portable script for testing Round Robin, Least Connections, and Weighted algorithms
#
# Usage:
#   Default (5MB files, 90s, 20 connections):
#     ./testing/run-comparison.sh
#
#   Custom configuration:
#     FILE_SIZE=10485760 TEST_DURATION=120s CONNECTIONS=50 ./testing/run-comparison.sh
#

set -euo pipefail

# ===========================
# SECTION 1: CONFIGURATION
# ===========================
FILE_SIZE=${FILE_SIZE:-5242880}              # Default: 5MB (configurable via env)
TEST_DURATION=${TEST_DURATION:-90s}          # Default: 90 seconds
CONNECTIONS=${CONNECTIONS:-20}               # Default: 20 concurrent connections
THREADS=${THREADS:-4}                        # wrk threads

GOLEM_URL=${GOLEM_URL:-"http://localhost:8000"}
RESULTS_DIR="./testing/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_RESULTS="$RESULTS_DIR/$TIMESTAMP"

ALGORITHMS=("roundrobin" "leastconn" "weighted")

# Auto-detect script directory (portable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"

# ===========================
# SECTION 2: HELPER FUNCTIONS
# ===========================
log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }
log_warn() { echo "[WARN] $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Calculate disk space requirement
calculate_disk_requirement() {
    # Conservative estimate: 12 req/s * duration * file_size * 3 algorithms
    local file_size_mb=$((FILE_SIZE / 1024 / 1024))
    local duration_sec=${TEST_DURATION%s}
    local estimated_throughput=12
    
    local total_mb=$((estimated_throughput * duration_sec * file_size_mb * 3))
    echo $total_mb
}

# Check available disk space
check_disk_space() {
    local required_mb=$(calculate_disk_requirement)
    local required_gb=$((required_mb / 1024))
    
    # Get available space on current filesystem
    local available_kb=$(df -P "$STACK_DIR" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    local available_gb=$((available_mb / 1024))
    
    log_info "Disk space check:"
    log_info "  Required: ~${required_gb} GB"
    log_info "  Available: ${available_gb} GB"
    
    if [ $available_mb -lt $required_mb ]; then
        log_error "Insufficient disk space!"
        log_warn "Consider: Delete files after each algorithm (you'll be prompted)"
        return 1
    fi
    
    log_ok "Sufficient disk space available"
    return 0
}

# Delete uploaded files via API
delete_uploaded_files() {
    local uploaded_files_log="$1"
    
    if [ ! -f "$uploaded_files_log" ]; then
        log_warn "No uploaded files log found: $uploaded_files_log"
        return 0
    fi
    
    local file_count=$(wc -l < "$uploaded_files_log" 2>/dev/null || echo "0")
    
    if [ "$file_count" -eq 0 ]; then
        log_info "No files to delete"
        return 0
    fi
    
    log_info "Deleting $file_count uploaded files..."
    
    local deleted=0
    local failed=0
    
    while IFS= read -r filename; do
        if [ -n "$filename" ]; then
            response=$(curl -s -w "\n%{http_code}" -X DELETE "$GOLEM_URL/api/files/$filename" 2>/dev/null)
            http_code=$(echo "$response" | tail -n1)
            
            if [ "$http_code" = "200" ]; then
                ((deleted++))
            else
                ((failed++))
            fi
        fi
    done < "$uploaded_files_log"
    
    log_ok "Deleted: $deleted files"
    if [ $failed -gt 0 ]; then
        log_warn "Failed to delete: $failed files"
    fi
    
    # Clear the log file
    > "$uploaded_files_log"
}

# Ask user if they want to delete files
prompt_cleanup() {
    local uploaded_files_log="$1"
    local algo_name="$2"
    
    echo ""
    read -p "Delete uploaded files from $algo_name test? [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        delete_uploaded_files "$uploaded_files_log"
    else
        log_info "Keeping uploaded files (will take disk space)"
    fi
}

# ===========================
# SECTION 3: PREFLIGHT CHECKS
# ===========================
preflight_checks() {
    log_info "Running preflight checks..."
    
    # Check required commands
    local required_commands=("wrk" "jq" "python3" "curl" "docker")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install with: sudo apt install wrk jq python3 curl docker.io"
        exit 1
    fi
    
    log_ok "All required commands available"
    
    # Check GOLEM is running
    if ! curl -s -f "$GOLEM_URL/health" > /dev/null 2>&1; then
        log_error "GOLEM is not responding at $GOLEM_URL"
        log_info "Please start containers: docker compose -f docker-compose.prod.yml up -d"
        exit 1
    fi
    log_ok "GOLEM is running at $GOLEM_URL"
    
    # Check disk space
    if ! check_disk_space; then
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_ok "Preflight checks passed"
}

# ===========================
# SECTION 4: CLEANUP OLD RESULTS
# ===========================
cleanup_old_results() {
    log_info "Checking for old test results (>7 days)..."
    
    if [ ! -d "$RESULTS_DIR" ]; then
        return 0
    fi
    
    # Find and delete result directories older than 7 days
    local deleted_count=0
    while IFS= read -r -d '' old_dir; do
        log_info "Deleting old results: $(basename "$old_dir")"
        rm -rf "$old_dir"
        ((deleted_count++))
    done < <(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +7 -print0 2>/dev/null)
    
    if [ $deleted_count -gt 0 ]; then
        log_ok "Cleaned up $deleted_count old result directories"
    else
        log_info "No old results to clean up"
    fi
}

# ===========================
# SECTION 5: EMBEDDED LUA SCRIPT
# ===========================
generate_lua_script() {
    local output_file="$1"
    local uploaded_log="$2"
    
    cat > "$output_file" << 'LUA_SCRIPT_END'
-- Unique file generation for GOLEM load balancer testing
-- Generates unique 5MB files to avoid duplicate detection

FILE_SIZE = 5242880
UPLOADED_LOG = "/tmp/uploaded_files.log"

-- Request counter (per thread)
local request_counter = 0
local thread_id = 0

-- Initialize thread ID
function setup(thread)
    thread_id = math.random(1000, 9999)
    thread:set("id", thread_id)
end

function init(args)
    -- Seed random generator with process ID and time
    math.randomseed(os.time() * math.random(1000))
end

-- Generate unique file content
function request()
    request_counter = request_counter + 1
    
    -- Create unique prefix using timestamp, thread ID, and counter
    local unique_id = string.format("%d-%d-%d-", 
        os.time() * 1000 + math.random(1000),
        thread_id,
        request_counter
    )
    
    -- Fill rest with random data to reach FILE_SIZE
    local remaining_size = FILE_SIZE - #unique_id
    local file_content = unique_id .. string.rep("X", remaining_size)
    
    -- Generate unique filename
    local filename = string.format("test-%d-%d.bin", os.time(), math.random(100000))
    
    -- Build multipart/form-data request
    local boundary = "----WebKitFormBoundary" .. tostring(math.random(10000000, 99999999))
    
    local body = "--" .. boundary .. "\r\n"
    body = body .. 'Content-Disposition: form-data; name="file"; filename="' .. filename .. '"\r\n'
    body = body .. "Content-Type: application/octet-stream\r\n\r\n"
    body = body .. file_content
    body = body .. "\r\n--" .. boundary .. "--\r\n"
    
    local headers = {
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
        ["Content-Length"] = tostring(#body)
    }
    
    return wrk.format("POST", "/api/files", headers, body)
end

-- Track successful uploads
function response(status, headers, body)
    if status == 201 then
        -- Parse filename from JSON response
        local filename = string.match(body, '"filename"%s*:%s*"([^"]+)"')
        if filename then
            -- Log to file (for cleanup script)
            local f = io.open(UPLOADED_LOG, "a")
            if f then
                f:write(filename .. "\n")
                f:close()
            end
        end
    end
end
LUA_SCRIPT_END

    # Replace placeholders with actual values
    sed -i "s/FILE_SIZE = 5242880/FILE_SIZE = $FILE_SIZE/" "$output_file"
    sed -i "s|UPLOADED_LOG = \"/tmp/uploaded_files.log\"|UPLOADED_LOG = \"$uploaded_log\"|" "$output_file"
}

# ===========================
# SECTION 6: TEST EXECUTION
# ===========================
run_algorithm_test() {
    local algorithm="$1"
    local output_file="$CURRENT_RESULTS/${algorithm}_results.txt"
    local metrics_file="$CURRENT_RESULTS/${algorithm}_metrics.txt"
    local uploaded_log="$CURRENT_RESULTS/${algorithm}_uploaded.log"
    local lua_script="$CURRENT_RESULTS/${algorithm}_test.lua"
    
    log_info "Testing algorithm: $algorithm"
    
    # Switch algorithm
    if [ -f "$STACK_DIR/switch-algorithm.sh" ]; then
        bash "$STACK_DIR/switch-algorithm.sh" "$algorithm"
        sleep 5  # Wait for config reload
    else
        log_warn "switch-algorithm.sh not found, using current algorithm"
    fi
    
    # Generate Lua script with unique file generation
    generate_lua_script "$lua_script" "$uploaded_log"
    
    # Run wrk test
    log_info "Running wrk test (duration: $TEST_DURATION, connections: $CONNECTIONS)..."
    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$TEST_DURATION" \
        -s "$lua_script" \
        "$GOLEM_URL/api/files" \
        > "$output_file" 2>&1
    
    # Capture Prometheus metrics
    curl -s "$GOLEM_URL/metrics" > "$metrics_file" 2>/dev/null || log_warn "Failed to capture metrics"
    
    log_ok "$algorithm test completed"
    
    # Prompt for cleanup
    prompt_cleanup "$uploaded_log" "$algorithm"
}

# ===========================
# SECTION 7: RESULTS ANALYSIS
# ===========================
analyze_results() {
    log_info "Analyzing results..."
    
    python3 - "$CURRENT_RESULTS" << 'PYTHON_ANALYSIS_END'
import sys
import re
from pathlib import Path

def parse_wrk(filepath):
    with open(filepath) as f:
        text = f.read()
    
    metrics = {}
    if m := re.search(r'Requests/sec:\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    if m := re.search(r'Latency.*?(\d+\.\d+)ms', text):
        metrics['avg_latency'] = float(m.group(1))
    if m := re.search(r'99%\s+([\d.]+)ms', text):
        metrics['p99_latency'] = float(m.group(1))
    
    return metrics

results_dir = Path(sys.argv[1])
algorithms = ['roundrobin', 'leastconn', 'weighted']

print("=" * 70)
print("GOLEM ALGORITHM COMPARISON RESULTS")
print("=" * 70)
print()

for algo in algorithms:
    file = results_dir / f"{algo}_results.txt"
    if file.exists():
        metrics = parse_wrk(file)
        print(f"{algo.upper():15} | ", end="")
        print(f"Throughput: {metrics.get('throughput', 0):6.2f} req/s | ", end="")
        print(f"Avg: {metrics.get('avg_latency', 0):6.2f} ms | ", end="")
        print(f"P99: {metrics.get('p99_latency', 0):6.2f} ms")
    else:
        print(f"{algo.upper():15} | FAILED - results file not found")

print()
print("=" * 70)
PYTHON_ANALYSIS_END

    # Save summary to file
    python3 - "$CURRENT_RESULTS" > "$CURRENT_RESULTS/SUMMARY.txt" << 'PYTHON_SUMMARY_END'
import sys
import re
from pathlib import Path

def parse_wrk(filepath):
    with open(filepath) as f:
        text = f.read()
    
    metrics = {}
    if m := re.search(r'Requests/sec:\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    if m := re.search(r'Latency.*?(\d+\.\d+)ms', text):
        metrics['avg_latency'] = float(m.group(1))
    if m := re.search(r'99%\s+([\d.]+)ms', text):
        metrics['p99_latency'] = float(m.group(1))
    
    return metrics

results_dir = Path(sys.argv[1])
algorithms = ['roundrobin', 'leastconn', 'weighted']

print("GOLEM Algorithm Comparison Results")
print(f"Test Date: {results_dir.name}")
print()

for algo in algorithms:
    file = results_dir / f"{algo}_results.txt"
    if file.exists():
        metrics = parse_wrk(file)
        print(f"{algo}:")
        print(f"  Throughput: {metrics.get('throughput', 0):.2f} req/s")
        print(f"  Avg Latency: {metrics.get('avg_latency', 0):.2f} ms")
        print(f"  P99 Latency: {metrics.get('p99_latency', 0):.2f} ms")
        print()
PYTHON_SUMMARY_END
    
    log_ok "Analysis complete"
}

# ===========================
# SECTION 8: MAIN EXECUTION
# ===========================
main() {
    echo ""
    echo "=========================================="
    echo "GOLEM Algorithm Comparison Test"
    echo "=========================================="
    echo "Configuration:"
    echo "  File size: $((FILE_SIZE / 1024 / 1024)) MB"
    echo "  Duration: $TEST_DURATION per algorithm"
    echo "  Connections: $CONNECTIONS"
    echo "  GOLEM URL: $GOLEM_URL"
    echo "=========================================="
    echo ""
    
    # Preflight checks
    preflight_checks
    
    # Cleanup old results
    cleanup_old_results
    
    # Create results directory
    mkdir -p "$CURRENT_RESULTS"
    log_ok "Results will be saved to: $CURRENT_RESULTS"
    
    # Run tests for each algorithm
    for algo in "${ALGORITHMS[@]}"; do
        run_algorithm_test "$algo"
        echo ""
    done
    
    # Analyze results
    analyze_results
    
    # Final report
    echo ""
    echo "=========================================="
    echo "TEST COMPLETE"
    echo "=========================================="
    echo "Results location: $CURRENT_RESULTS"
    echo ""
    echo "Files created:"
    echo "  - {algorithm}_results.txt  (wrk output)"
    echo "  - {algorithm}_metrics.txt  (Prometheus metrics)"
    echo "  - SUMMARY.txt              (Comparison summary)"
    echo ""
    log_ok "All tests completed successfully!"
}

# Run main function
main "$@"
