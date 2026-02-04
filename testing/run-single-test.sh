#!/usr/bin/env bash
#
# GOLEM Single Algorithm Test
# Tests the currently configured algorithm on GOLEM load balancer
#
# Designed for remote testing: Client → VPS
# No algorithm switching - test whatever GOLEM is currently configured with
#
# Usage:
#   Default (5MB files, 90s, 20 connections):
#     GOLEM_URL=http://vps-domain:8000 ./testing/run-single-test.sh
#
#   Specify algorithm name (for results folder):
#     GOLEM_URL=http://vps:8000 ALGORITHM=roundrobin ./testing/run-single-test.sh
#
#   Custom configuration:
#     GOLEM_URL=http://vps:8000 \
#     ALGORITHM=weighted \
#     FILE_SIZE=10485760 \
#     TEST_DURATION=120s \
#     CONNECTIONS=50 \
#     ./testing/run-single-test.sh
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
ALGORITHM=${ALGORITHM:-"current"}            # Algorithm name for results folder
RESULTS_BASE_DIR="./testing/results"

# Auto-detect script directory (portable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Calculate disk space requirement (on client side)
calculate_disk_requirement() {
    local file_size_mb=$((FILE_SIZE / 1024 / 1024))
    local duration_sec=${TEST_DURATION%s}
    local estimated_throughput=12
    
    local total_mb=$((estimated_throughput * duration_sec * file_size_mb))
    echo $total_mb
}

# Check available disk space
check_disk_space() {
    local required_mb=$(calculate_disk_requirement)
    local required_gb=$((required_mb / 1024))
    
    # Get available space on current filesystem
    local available_kb=$(df -P "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    local available_gb=$((available_mb / 1024))
    
    log_info "Disk space check (client-side):"
    log_info "  Required: ~${required_gb} GB"
    log_info "  Available: ${available_gb} GB"
    
    if [ $available_mb -lt $required_mb ]; then
        log_error "Insufficient disk space on client!"
        log_warn "Consider: Delete files after test (you'll be prompted)"
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
    
    log_info "Deleting $file_count uploaded files from VPS..."
    
    local deleted=0
    local failed=0
    
    while IFS= read -r filename; do
        if [ -n "$filename" ]; then
            response=$(curl -s -w "\n%{http_code}" -X DELETE "$GOLEM_URL/api/files/$filename" 2>/dev/null)
            http_code=$(echo "$response" | tail -n1)
            
            if [ "$http_code" = "200" ]; then
                ((deleted++))
                # Show progress every 50 files
                if [ $((deleted % 50)) -eq 0 ]; then
                    log_info "Deleted $deleted files..."
                fi
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
    
    echo ""
    read -p "Delete uploaded files from VPS? [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        delete_uploaded_files "$uploaded_files_log"
    else
        log_info "Keeping uploaded files on VPS (will take disk space)"
    fi
}

# ===========================
# SECTION 3: PREFLIGHT CHECKS
# ===========================
preflight_checks() {
    log_info "Running preflight checks..."
    
    # Check required commands (NO DOCKER - client doesn't need it)
    local required_commands=("wrk" "jq" "python3" "curl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Install with: sudo apt install wrk jq python3 curl"
        exit 1
    fi
    
    log_ok "All required commands available"
    
    # Check GOLEM is responding
    if ! curl -s -f "$GOLEM_URL/health" > /dev/null 2>&1; then
        log_error "GOLEM is not responding at $GOLEM_URL"
        log_info "Check:"
        log_info "  1. Is GOLEM_URL correct?"
        log_info "  2. Is GOLEM running on the VPS?"
        log_info "  3. Is the port accessible from this client?"
        exit 1
    fi
    log_ok "GOLEM is responding at $GOLEM_URL"
    
    # Check disk space (on client side)
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
# SECTION 4: EMBEDDED LUA SCRIPT
# ===========================
generate_lua_script() {
    local output_file="$1"
    local uploaded_log="$2"
    
    cat > "$output_file" << 'LUA_SCRIPT_END'
-- Unique file generation for GOLEM load balancer testing
-- Generates unique files to avoid duplicate detection

FILE_SIZE = 5242880
UPLOADED_LOG = "/tmp/uploaded_files.log"

-- Request counter (per thread)
local request_counter = 0

-- Initialize
function setup(thread)
    thread:set("id", request_counter)
end

function init(args)
    -- Seed random generator
    math.randomseed(os.time() + wrk.thread.id * 10000)
end

-- Generate unique file content
function request()
    request_counter = request_counter + 1
    
    -- Create unique prefix using timestamp, thread ID, and counter
    local unique_id = string.format("%d-%d-%d-", 
        os.time() * 1000 + math.random(1000),
        wrk.thread.id,
        request_counter
    )
    
    -- Fill rest with data to reach FILE_SIZE
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
# SECTION 5: TEST EXECUTION
# ===========================
run_test() {
    local algorithm="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local results_dir="$RESULTS_BASE_DIR/${timestamp}_${algorithm}"
    
    local output_file="$results_dir/test_results.txt"
    local metrics_file="$results_dir/metrics.txt"
    local uploaded_log="$results_dir/uploaded_files.log"
    local lua_script="$results_dir/test.lua"
    
    # Create results directory
    mkdir -p "$results_dir"
    log_ok "Results will be saved to: $results_dir"
    
    log_info "Testing algorithm: $algorithm"
    log_info "Configuration: ${FILE_SIZE} bytes, ${TEST_DURATION}, ${CONNECTIONS} connections"
    
    # Generate Lua script with unique file generation
    generate_lua_script "$lua_script" "$uploaded_log"
    
    # Run wrk test
    log_info "Running wrk test..."
    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$TEST_DURATION" \
        -s "$lua_script" \
        "$GOLEM_URL/api/files" \
        > "$output_file" 2>&1
    
    # Capture Prometheus metrics
    log_info "Capturing Prometheus metrics..."
    curl -s "$GOLEM_URL/metrics" > "$metrics_file" 2>/dev/null || log_warn "Failed to capture metrics"
    
    log_ok "Test completed"
    
    # Parse and display results
    display_results "$output_file" "$results_dir"
    
    # Prompt for cleanup
    prompt_cleanup "$uploaded_log"
    
    echo ""
    log_ok "Results saved to: $results_dir"
}

# ===========================
# SECTION 6: RESULTS DISPLAY
# ===========================
display_results() {
    local output_file="$1"
    local results_dir="$2"
    
    log_info "Analyzing results..."
    
    # Parse wrk output and display
    python3 - "$output_file" "$results_dir" << 'PYTHON_ANALYSIS_END'
import sys
import re
from pathlib import Path

def parse_wrk(filepath):
    with open(filepath) as f:
        text = f.read()
    
    metrics = {}
    
    # Parse requests/sec
    if m := re.search(r'Requests/sec:\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    
    # Parse latency
    if m := re.search(r'Latency\s+(\d+\.\d+)(\w+)', text):
        value = float(m.group(1))
        unit = m.group(2)
        # Convert to ms if needed
        if unit == 's':
            value *= 1000
        metrics['avg_latency'] = value
    
    # Parse percentiles
    if m := re.search(r'50%\s+(\d+\.\d+)(\w+)', text):
        value = float(m.group(1))
        unit = m.group(2)
        if unit == 's':
            value *= 1000
        metrics['p50_latency'] = value
    
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

output_file = Path(sys.argv[1])
results_dir = Path(sys.argv[2])

if not output_file.exists():
    print("[ERROR] Results file not found")
    sys.exit(1)

metrics = parse_wrk(output_file)

# Display results
print()
print("=" * 70)
print("TEST RESULTS")
print("=" * 70)
print(f"Throughput:       {metrics.get('throughput', 0):8.2f} req/s")
print(f"Avg Latency:      {metrics.get('avg_latency', 0):8.2f} ms")
print(f"P50 Latency:      {metrics.get('p50_latency', 0):8.2f} ms")
print(f"P99 Latency:      {metrics.get('p99_latency', 0):8.2f} ms")
print(f"Total Requests:   {metrics.get('total_requests', 0):8d}")
print(f"Errors:           {metrics.get('errors', 0):8d}")
print("=" * 70)

# Save summary to file
summary_file = results_dir / "SUMMARY.txt"
with open(summary_file, 'w') as f:
    f.write("GOLEM Load Balancer Test Results\n")
    f.write(f"Test Date: {results_dir.name}\n")
    f.write("\n")
    f.write(f"Throughput:       {metrics.get('throughput', 0):.2f} req/s\n")
    f.write(f"Avg Latency:      {metrics.get('avg_latency', 0):.2f} ms\n")
    f.write(f"P50 Latency:      {metrics.get('p50_latency', 0):.2f} ms\n")
    f.write(f"P99 Latency:      {metrics.get('p99_latency', 0):.2f} ms\n")
    f.write(f"Total Requests:   {metrics.get('total_requests', 0)}\n")
    f.write(f"Errors:           {metrics.get('errors', 0)}\n")

print()
print(f"[OK] Summary saved to: {summary_file}")
PYTHON_ANALYSIS_END
}

# ===========================
# SECTION 7: MAIN EXECUTION
# ===========================
main() {
    echo ""
    echo "=========================================="
    echo "GOLEM Single Algorithm Test"
    echo "=========================================="
    echo "Target:       $GOLEM_URL"
    echo "Algorithm:    $ALGORITHM"
    echo "File size:    $((FILE_SIZE / 1024 / 1024)) MB"
    echo "Duration:     $TEST_DURATION"
    echo "Connections:  $CONNECTIONS"
    echo "=========================================="
    echo ""
    
    # Preflight checks
    preflight_checks
    
    # Run test
    run_test "$ALGORITHM"
    
    # Final message
    echo ""
    echo "=========================================="
    echo "TEST COMPLETE"
    echo "=========================================="
    echo ""
    echo "To test other algorithms:"
    echo "  1. SSH to VPS and switch algorithm:"
    echo "     ssh vps && cd golem-stack && bash switch-algorithm.sh leastconn"
    echo "  2. Run this script again with new algorithm name:"
    echo "     ALGORITHM=leastconn GOLEM_URL=$GOLEM_URL $0"
    echo ""
    echo "To compare results:"
    echo "  ./testing/compare-results.sh testing/results/*_roundrobin testing/results/*_leastconn testing/results/*_weighted"
    echo ""
}

# Run main function
main "$@"
