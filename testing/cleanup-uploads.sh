#!/usr/bin/env bash
#
# Manual cleanup utility for uploaded test files
#
# Usage:
#   ./testing/cleanup-uploads.sh
#
# This script will:
#   1. Fetch all uploaded files from the API
#   2. Ask for confirmation
#   3. Delete all files via DELETE API calls
#

set -euo pipefail

GOLEM_URL=${GOLEM_URL:-"http://localhost:8000"}

log_info() { echo "[INFO] $1"; }
log_ok() { echo "[OK] $1"; }
log_error() { echo "[ERROR] $1"; }

echo "=========================================="
echo "GOLEM File Cleanup Utility"
echo "=========================================="
echo ""

# Check if curl and jq are available
if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required but not installed"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    exit 1
fi

# Check if GOLEM is running
if ! curl -s -f "$GOLEM_URL/health" > /dev/null 2>&1; then
    log_error "GOLEM is not responding at $GOLEM_URL"
    exit 1
fi

log_info "Fetching list of uploaded files from $GOLEM_URL..."

# Get all files from API
files_json=$(curl -s "$GOLEM_URL/api/files?limit=10000")

# Check if request was successful
if [ -z "$files_json" ]; then
    log_error "Failed to fetch file list from API"
    exit 1
fi

# Extract filenames (original_name field)
filenames=$(echo "$files_json" | jq -r '.files[]?.filename // empty' 2>/dev/null)

if [ -z "$filenames" ]; then
    log_info "No files found to delete"
    exit 0
fi

file_count=$(echo "$filenames" | wc -l)

log_info "Found $file_count files"
echo ""
echo "WARNING: This will delete ALL uploaded files from the file service!"
echo ""
read -p "Delete ALL $file_count uploaded files? [y/N]: " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cancelled - no files deleted"
    exit 0
fi

echo ""
log_info "Starting deletion process..."
echo ""

deleted=0
failed=0

while IFS= read -r filename; do
    if [ -n "$filename" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$GOLEM_URL/api/files/$filename" 2>/dev/null)
        
        if [ "$http_code" = "200" ]; then
            ((deleted++))
            if [ $((deleted % 10)) -eq 0 ]; then
                log_info "Deleted $deleted files..."
            fi
        else
            ((failed++))
            log_error "Failed to delete: $filename (HTTP $http_code)"
        fi
    fi
done <<< "$filenames"

echo ""
echo "=========================================="
echo "Cleanup Complete"
echo "=========================================="
log_ok "Successfully deleted: $deleted files"
if [ $failed -gt 0 ]; then
    log_error "Failed to delete: $failed files"
fi
echo "=========================================="
