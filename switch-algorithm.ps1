<#
.SYNOPSIS
    Quick algorithm switcher for GOLEM Load Balancer

.DESCRIPTION
    Switches the load balancing algorithm in GOLEM configuration

.PARAMETER Algorithm
    The load balancing algorithm to use (roundrobin, leastconn, or weighted)

.EXAMPLE
    .\switch-algorithm.ps1 roundrobin

.EXAMPLE
    .\switch-algorithm.ps1 leastconn
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("roundrobin", "leastconn", "weighted")]
    [string]$Algorithm
)

$ErrorActionPreference = "Stop"

# Script paths
$ScriptDir = $PSScriptRoot
$ConfigFile = Join-Path $ScriptDir "golem-config.json"
$ComposeFile = Join-Path $ScriptDir "docker-compose.prod.yml"

# Helper functions
function Write-Header { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Error2 { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Config { param([string]$Message) Write-Host "[CONFIG] $Message" -ForegroundColor Yellow }
function Write-Action { param([string]$Message) Write-Host "[ACTION] $Message" -ForegroundColor Yellow }
function Write-Wait { param([string]$Message) Write-Host "[WAIT] $Message" -ForegroundColor Yellow }

Write-Host ""
Write-Header "======================================"
Write-Header "GOLEM Algorithm Switcher"
Write-Header "======================================"
Write-Host ""

# Check if config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Error2 "Config file not found: $ConfigFile"
    exit 1
}

# Backup current config
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $ScriptDir ".golem-config.backup.$timestamp.json"
Copy-Item $ConfigFile $backupFile
Write-Info "Backed up config to: $(Split-Path $backupFile -Leaf)"

# Update config
Write-Config "Updating algorithm to: $Algorithm"

try {
    # Read JSON config
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    
    # Update method
    $config.method = $Algorithm
    
    # Write back to file
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
    
    Write-Host ""
    Write-Host "Updated configuration:" -ForegroundColor Cyan
    Write-Host "  Method: $($config.method)" -ForegroundColor White
    Write-Host "  Backends:" -ForegroundColor White
    foreach ($backend in $config.backends) {
        Write-Host "    - $($backend.url) (weight: $($backend.weight))" -ForegroundColor White
    }
    Write-Host ""
    
} catch {
    Write-Error2 "Failed to update config: $_"
    Write-Info "Restoring backup..."
    Copy-Item $backupFile $ConfigFile -Force
    exit 1
}

# Restart GOLEM
Write-Action "Restarting GOLEM load balancer..."

try {
    if (Test-Path $ComposeFile) {
        docker compose -f $ComposeFile restart golem 2>&1 | Out-Null
    } else {
        docker compose restart golem 2>&1 | Out-Null
    }
} catch {
    Write-Error2 "Failed to restart GOLEM: $_"
    exit 1
}

# Wait for GOLEM to be ready
Write-Wait "Waiting for GOLEM to be ready..."
Start-Sleep -Seconds 5

# Verify
$maxRetries = 6
$retryCount = 0
$golemReady = $false

while ($retryCount -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8000/metrics" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        $golemReady = $true
        break
    } catch {
        $retryCount++
        Write-Host "Waiting... (attempt $retryCount/$maxRetries)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

Write-Host ""

if ($golemReady) {
    Write-Success "GOLEM is ready with algorithm: $Algorithm"
    Write-Host ""
    Write-Header "======================================"
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Test the load balancer:" -ForegroundColor White
    Write-Host "   curl http://localhost:8000/api/files" -ForegroundColor Blue
    Write-Host ""
    Write-Host "2. View metrics:" -ForegroundColor White
    Write-Host "   curl http://localhost:8000/metrics | Select-String golem_balancer_info" -ForegroundColor Blue
    Write-Host ""
    Write-Host "3. Send test traffic:" -ForegroundColor White
    Write-Host "   bombardier -c 20 -d 30s http://localhost:8000" -ForegroundColor Blue
    Write-Host ""
    Write-Host "4. View Grafana dashboard:" -ForegroundColor White
    Write-Host "   http://localhost:3031" -ForegroundColor Blue
    Write-Host ""
    Write-Header "======================================"
    Write-Host ""
    Write-Host "To restore previous config:" -ForegroundColor Yellow
    Write-Host "  Copy-Item $backupFile $ConfigFile" -ForegroundColor Gray
    Write-Host "  docker compose restart golem" -ForegroundColor Gray
} else {
    Write-Error2 "GOLEM might not be ready yet. Check logs:"
    Write-Host "  docker compose logs golem" -ForegroundColor Gray
    exit 1
}
