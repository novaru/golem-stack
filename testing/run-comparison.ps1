<#
.SYNOPSIS
    GOLEM Load Balancer Algorithm Comparison Test (Windows PowerShell version)

.DESCRIPTION
    Tests Round Robin, Least Connections, and Weighted algorithms using Bombardier
    
.PARAMETER FileSize
    Size of test files in bytes (default: 5MB)
    
.PARAMETER TestDuration
    Test duration per algorithm (default: 90s)
    
.PARAMETER Connections
    Number of concurrent connections (default: 20)
    
.PARAMETER GolemUrl
    GOLEM server URL (default: http://localhost:8000)

.EXAMPLE
    .\testing\run-comparison.ps1
    
.EXAMPLE
    .\testing\run-comparison.ps1 -FileSize 10485760 -TestDuration "120s" -Connections 50
#>

param(
    [int]$FileSize = 5242880,          # 5MB default
    [string]$TestDuration = "90s",     # 90 seconds default
    [int]$Connections = 20,            # 20 concurrent connections
    [string]$GolemUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"

# ===========================
# SECTION 1: CONFIGURATION
# ===========================
$ResultsDir = Join-Path $PSScriptRoot "results"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$CurrentResults = Join-Path $ResultsDir $Timestamp
$Algorithms = @("roundrobin", "leastconn", "weighted")

# Auto-detect script and stack directories
$ScriptDir = $PSScriptRoot
$StackDir = Split-Path $ScriptDir -Parent

# ===========================
# SECTION 2: HELPER FUNCTIONS
# ===========================
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-OK { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check if command exists
function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Install Bombardier if not present
function Install-Bombardier {
    Write-Info "Checking for Bombardier..."
    
    if (Test-CommandExists "bombardier") {
        Write-OK "Bombardier is already installed"
        return
    }
    
    Write-Warn "Bombardier not found. Installing..."
    
    try {
        $tempDir = Join-Path $env:TEMP "bombardier_install"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        
        # Determine architecture
        $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
        $downloadUrl = "https://github.com/codesenberg/bombardier/releases/latest/download/bombardier-windows-$arch.exe"
        
        Write-Info "Downloading Bombardier from $downloadUrl..."
        $bombardierPath = Join-Path $tempDir "bombardier.exe"
        
        Invoke-WebRequest -Uri $downloadUrl -OutFile $bombardierPath -UseBasicParsing
        
        # Move to a location in PATH (prefer current user's local bin)
        $installDir = Join-Path $env:LOCALAPPDATA "Programs\Bombardier"
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        
        $finalPath = Join-Path $installDir "bombardier.exe"
        Move-Item -Force $bombardierPath $finalPath
        
        # Add to PATH if not already there
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$installDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
            $env:Path += ";$installDir"
        }
        
        Remove-Item -Recurse -Force $tempDir
        
        Write-OK "Bombardier installed successfully to $finalPath"
        Write-Info "You may need to restart your terminal for PATH changes to take effect"
        
    } catch {
        Write-Err "Failed to install Bombardier: $_"
        Write-Info "Please install manually from: https://github.com/codesenberg/bombardier/releases"
        exit 1
    }
}

# Calculate disk space requirement
function Get-DiskRequirement {
    $fileSizeMB = [math]::Floor($FileSize / 1024 / 1024)
    $durationSec = [int]($TestDuration -replace 's', '')
    $estimatedThroughput = 12
    
    $totalMB = $estimatedThroughput * $durationSec * $fileSizeMB * 3
    return $totalMB
}

# Check available disk space
function Test-DiskSpace {
    $requiredMB = Get-DiskRequirement
    $requiredGB = [math]::Floor($requiredMB / 1024)
    
    $drive = (Get-Item $StackDir).PSDrive.Name
    $driveInfo = Get-PSDrive $drive
    $availableMB = [math]::Floor($driveInfo.Free / 1MB)
    $availableGB = [math]::Floor($availableMB / 1024)
    
    Write-Info "Disk space check:"
    Write-Info "  Required: ~$requiredGB GB"
    Write-Info "  Available: $availableGB GB"
    
    if ($availableMB -lt $requiredMB) {
        Write-Err "Insufficient disk space!"
        Write-Warn "Consider: Delete files after each algorithm (you'll be prompted)"
        return $false
    }
    
    Write-OK "Sufficient disk space available"
    return $true
}

# Delete uploaded files via API
function Remove-UploadedFiles {
    param([string]$UploadedFilesLog)
    
    if (-not (Test-Path $UploadedFilesLog)) {
        Write-Warn "No uploaded files log found: $UploadedFilesLog"
        return
    }
    
    $files = Get-Content $UploadedFilesLog | Where-Object { $_.Trim() -ne "" }
    $fileCount = $files.Count
    
    if ($fileCount -eq 0) {
        Write-Info "No files to delete"
        return
    }
    
    Write-Info "Deleting $fileCount uploaded files..."
    
    $deleted = 0
    $failed = 0
    
    foreach ($filename in $files) {
        try {
            $response = Invoke-WebRequest -Uri "$GolemUrl/api/files/$filename" -Method DELETE -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                $deleted++
            } else {
                $failed++
            }
        } catch {
            $failed++
        }
    }
    
    Write-OK "Deleted: $deleted files"
    if ($failed -gt 0) {
        Write-Warn "Failed to delete: $failed files"
    }
    
    # Clear the log file
    Clear-Content $UploadedFilesLog
}

# Ask user if they want to delete files
function Request-Cleanup {
    param(
        [string]$UploadedFilesLog,
        [string]$AlgoName
    )
    
    Write-Host ""
    $response = Read-Host "Delete uploaded files from $AlgoName test? [y/N]"
    
    if ($response -match '^[Yy]$') {
        Remove-UploadedFiles $UploadedFilesLog
    } else {
        Write-Info "Keeping uploaded files (will take disk space)"
    }
}

# ===========================
# SECTION 3: PREFLIGHT CHECKS
# ===========================
function Test-Prerequisites {
    Write-Info "Running preflight checks..."
    
    # Check required commands
    $requiredCommands = @("python", "curl", "docker")
    $missingCommands = @()
    
    foreach ($cmd in $requiredCommands) {
        if (-not (Test-CommandExists $cmd)) {
            $missingCommands += $cmd
        }
    }
    
    if ($missingCommands.Count -gt 0) {
        Write-Err "Missing required commands: $($missingCommands -join ', ')"
        Write-Info "Install Python: https://www.python.org/downloads/"
        Write-Info "Install Docker: https://docs.docker.com/desktop/install/windows-install/"
        Write-Info "Install curl: Included in Windows 10+ or use chocolatey"
        exit 1
    }
    
    Write-OK "All required commands available"
    
    # Install Bombardier if needed
    Install-Bombardier
    
    # Check GOLEM is running
    try {
        $response = Invoke-WebRequest -Uri "$GolemUrl/health" -UseBasicParsing -TimeoutSec 5
        Write-OK "GOLEM is running at $GolemUrl"
    } catch {
        Write-Err "GOLEM is not responding at $GolemUrl"
        Write-Info "Please start containers: docker compose -f docker-compose.prod.yml up -d"
        exit 1
    }
    
    # Check disk space
    if (-not (Test-DiskSpace)) {
        $response = Read-Host "Continue anyway? [y/N]"
        if ($response -notmatch '^[Yy]$') {
            exit 1
        }
    }
    
    Write-OK "Preflight checks passed"
}

# ===========================
# SECTION 4: CLEANUP OLD RESULTS
# ===========================
function Remove-OldResults {
    Write-Info "Checking for old test results (>7 days)..."
    
    if (-not (Test-Path $ResultsDir)) {
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-7)
    $oldDirs = Get-ChildItem $ResultsDir -Directory | Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    $deletedCount = 0
    foreach ($dir in $oldDirs) {
        Write-Info "Deleting old results: $($dir.Name)"
        Remove-Item -Recurse -Force $dir.FullName
        $deletedCount++
    }
    
    if ($deletedCount -gt 0) {
        Write-OK "Cleaned up $deletedCount old result directories"
    } else {
        Write-Info "No old results to clean up"
    }
}

# ===========================
# SECTION 5: TEST FILE GENERATION
# ===========================
function New-TestFile {
    param(
        [string]$OutputPath,
        [int]$RequestNumber
    )
    
    # Create unique file content
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $randomId = Get-Random -Maximum 99999
    $uniquePrefix = "$timestamp-$env:COMPUTERNAME-$RequestNumber-"
    
    # Fill rest with random data to reach FILE_SIZE
    $remainingSize = $FileSize - $uniquePrefix.Length
    $padding = "X" * $remainingSize
    $content = $uniquePrefix + $padding
    
    # Save to file
    [System.IO.File]::WriteAllText($OutputPath, $content)
    
    return $OutputPath
}

# ===========================
# SECTION 6: TEST EXECUTION
# ===========================
function Invoke-AlgorithmTest {
    param([string]$Algorithm)
    
    $outputFile = Join-Path $CurrentResults "${Algorithm}_results.txt"
    $metricsFile = Join-Path $CurrentResults "${Algorithm}_metrics.txt"
    $uploadedLog = Join-Path $CurrentResults "${Algorithm}_uploaded.log"
    
    Write-Info "Testing algorithm: $Algorithm"
    
    # Switch algorithm
    $switchScript = Join-Path $StackDir "switch-algorithm.sh"
    if (Test-Path $switchScript) {
        if (Test-CommandExists "bash") {
            bash $switchScript $Algorithm
            Start-Sleep -Seconds 5
        } else {
            Write-Warn "bash not found, cannot switch algorithm. Using current algorithm"
        }
    } else {
        Write-Warn "switch-algorithm.sh not found, using current algorithm"
    }
    
    # Prepare test file directory
    $testFilesDir = Join-Path $CurrentResults "${Algorithm}_files"
    New-Item -ItemType Directory -Force -Path $testFilesDir | Out-Null
    
    Write-Info "Running Bombardier test (duration: $TestDuration, connections: $Connections)..."
    
    # Create a temporary file to upload
    $testFile = Join-Path $testFilesDir "test-file.bin"
    New-TestFile -OutputPath $testFile -RequestNumber 1 | Out-Null
    
    # Run bombardier test
    $durationArg = $TestDuration
    $bombardierArgs = @(
        "-c", $Connections,
        "-d", $durationArg,
        "-m", "POST",
        "-f", $testFile,
        "-H", "Content-Type: application/octet-stream",
        "--print", "r",
        "--format", "plain-text",
        "$GolemUrl/api/files"
    )
    
    try {
        # Run bombardier and capture output
        $output = & bombardier @bombardierArgs 2>&1
        $output | Out-File -FilePath $outputFile -Encoding utf8
        
        # Parse output to log uploaded files (simplified - bombardier doesn't track individual files like wrk+lua)
        # For cleanup purposes, we'll track the expected number of successful uploads
        Write-Info "Note: File tracking for cleanup is approximate with Bombardier"
        
    } catch {
        Write-Err "Bombardier test failed: $_"
    }
    
    # Capture Prometheus metrics
    try {
        $metrics = Invoke-WebRequest -Uri "$GolemUrl/metrics" -UseBasicParsing
        $metrics.Content | Out-File -FilePath $metricsFile -Encoding utf8
    } catch {
        Write-Warn "Failed to capture metrics"
    }
    
    # Cleanup test files
    Remove-Item -Recurse -Force $testFilesDir -ErrorAction SilentlyContinue
    
    Write-OK "$Algorithm test completed"
    
    # Prompt for cleanup (though bombardier doesn't track individual files)
    # Request-Cleanup $uploadedLog $Algorithm
}

# ===========================
# SECTION 7: RESULTS ANALYSIS
# ===========================
function Invoke-ResultsAnalysis {
    Write-Info "Analyzing results..."
    
    $pythonScript = @"
import sys
import re
from pathlib import Path

def parse_bombardier(filepath):
    with open(filepath, encoding='utf-8') as f:
        text = f.read()
    
    metrics = {}
    
    # Bombardier output format:
    # Statistics        Avg      Stdev        Max
    # Reqs/sec      123.45      12.34     234.56
    # Latency       12.34ms     1.23ms    45.67ms
    
    if m := re.search(r'Reqs/sec\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    else:
        metrics['throughput'] = 0.0
    
    # Parse latency - look for patterns like "Latency    12.34ms"
    if m := re.search(r'Latency\s+([\d.]+)(ms|s)', text):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['avg_latency'] = value if unit == 'ms' else value * 1000
    else:
        metrics['avg_latency'] = 0.0
    
    # Try to find percentile data (50th, 75th, 90th, 95th, 99th)
    if m := re.search(r'99th percentile.*?([\d.]+)(ms|s)', text, re.IGNORECASE):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['p99_latency'] = value if unit == 'ms' else value * 1000
    elif m := re.search(r'Latency.*?Max.*?([\d.]+)(ms|s)', text):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['p99_latency'] = value if unit == 'ms' else value * 1000
    else:
        metrics['p99_latency'] = 0.0
    
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
        metrics = parse_bombardier(file)
        print(f"{algo.upper():15} | ", end="")
        print(f"Throughput: {metrics.get('throughput', 0):6.2f} req/s | ", end="")
        print(f"Avg: {metrics.get('avg_latency', 0):6.2f} ms | ", end="")
        print(f"P99: {metrics.get('p99_latency', 0):6.2f} ms")
    else:
        print(f"{algo.upper():15} | FAILED - results file not found")

print()
print("=" * 70)
"@
    
    $pythonScript | python - $CurrentResults
    
    # Save summary to file
    $summaryScript = @"
import sys
import re
from pathlib import Path

def parse_bombardier(filepath):
    with open(filepath, encoding='utf-8') as f:
        text = f.read()
    
    metrics = {}
    
    if m := re.search(r'Reqs/sec\s+([\d.]+)', text):
        metrics['throughput'] = float(m.group(1))
    else:
        metrics['throughput'] = 0.0
    
    if m := re.search(r'Latency\s+([\d.]+)(ms|s)', text):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['avg_latency'] = value if unit == 'ms' else value * 1000
    else:
        metrics['avg_latency'] = 0.0
    
    if m := re.search(r'99th percentile.*?([\d.]+)(ms|s)', text, re.IGNORECASE):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['p99_latency'] = value if unit == 'ms' else value * 1000
    elif m := re.search(r'Latency.*?Max.*?([\d.]+)(ms|s)', text):
        value = float(m.group(1))
        unit = m.group(2)
        metrics['p99_latency'] = value if unit == 'ms' else value * 1000
    else:
        metrics['p99_latency'] = 0.0
    
    return metrics

results_dir = Path(sys.argv[1])
algorithms = ['roundrobin', 'leastconn', 'weighted']

print("GOLEM Algorithm Comparison Results")
print(f"Test Date: {results_dir.name}")
print()

for algo in algorithms:
    file = results_dir / f"{algo}_results.txt"
    if file.exists():
        metrics = parse_bombardier(file)
        print(f"{algo}:")
        print(f"  Throughput: {metrics.get('throughput', 0):.2f} req/s")
        print(f"  Avg Latency: {metrics.get('avg_latency', 0):.2f} ms")
        print(f"  P99 Latency: {metrics.get('p99_latency', 0):.2f} ms")
        print()
"@
    
    $summaryFile = Join-Path $CurrentResults "SUMMARY.txt"
    $summaryScript | python - $CurrentResults | Out-File -FilePath $summaryFile -Encoding utf8
    
    Write-OK "Analysis complete"
}

# ===========================
# SECTION 8: MAIN EXECUTION
# ===========================
function Start-ComparisonTest {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "GOLEM Algorithm Comparison Test" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Configuration:"
    Write-Host "  File size: $([math]::Floor($FileSize / 1024 / 1024)) MB"
    Write-Host "  Duration: $TestDuration per algorithm"
    Write-Host "  Connections: $Connections"
    Write-Host "  GOLEM URL: $GolemUrl"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Preflight checks
    Test-Prerequisites
    
    # Cleanup old results
    Remove-OldResults
    
    # Create results directory
    New-Item -ItemType Directory -Force -Path $CurrentResults | Out-Null
    Write-OK "Results will be saved to: $CurrentResults"
    
    # Run tests for each algorithm
    foreach ($algo in $Algorithms) {
        Invoke-AlgorithmTest $algo
        Write-Host ""
    }
    
    # Analyze results
    Invoke-ResultsAnalysis
    
    # Final report
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "TEST COMPLETE" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Results location: $CurrentResults"
    Write-Host ""
    Write-Host "Files created:"
    Write-Host "  - {algorithm}_results.txt  (bombardier output)"
    Write-Host "  - {algorithm}_metrics.txt  (Prometheus metrics)"
    Write-Host "  - SUMMARY.txt              (Comparison summary)"
    Write-Host ""
    Write-OK "All tests completed successfully!"
}

# Run main function
Start-ComparisonTest
