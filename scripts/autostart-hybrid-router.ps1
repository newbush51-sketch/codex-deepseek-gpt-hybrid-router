
param([int]$Port = 4140)

$ErrorActionPreference = "Stop"
$proxyRoot = $PSScriptRoot
$python = Join-Path $proxyRoot ".venv\Scripts\python.exe"
$router = Join-Path $proxyRoot "hybrid_router.py"
$clashLauncher = Join-Path $proxyRoot "autostart-clash.ps1"
$logFile = Join-Path $proxyRoot "autostart.log"
$stdoutLog = Join-Path $proxyRoot "hybrid-router.stdout.log"
$stderrLog = Join-Path $proxyRoot "hybrid-router.stderr.log"

function Rotate-Log([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 5MB) {
        $old = "$Path.old"
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
        Move-Item -LiteralPath $Path -Destination $old
    }
}

function Log([string]$Message, [string]$Level = "INFO") {
    Rotate-Log $logFile
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message" |
        Out-File -FilePath $logFile -Append -Encoding utf8
}

function Test-Health {
    try {
        $health = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health/liveliness" -TimeoutSec 3
        return $health.StatusCode -eq 200
    } catch {
        return $false
    }
}

$env:HTTP_PROXY = "http://127.0.0.1:7897"
$env:HTTPS_PROXY = "http://127.0.0.1:7897"
$env:ALL_PROXY = "http://127.0.0.1:7897"
$env:NO_PROXY = "localhost,127.0.0.1,::1"

if (Test-Health) {
    Log "Router already healthy on port $Port; skip."
    exit 0
}

if (-not (Test-Path -LiteralPath $python)) {
    Log "Python is missing: $python" "ERROR"
    exit 10
}
if (-not (Test-Path -LiteralPath $router)) {
    Log "Hybrid router source is missing: $router" "ERROR"
    exit 11
}
if (-not (Test-Path -LiteralPath $clashLauncher)) {
    Log "Clash launcher is missing: $clashLauncher" "ERROR"
    exit 12
}

Log "Ensuring Clash is ready before starting the hybrid router."
& $clashLauncher -WaitSeconds 60
if ($LASTEXITCODE -ne 0) {
    Log "Clash prerequisite failed with exit code $LASTEXITCODE." "ERROR"
    exit 20
}

Rotate-Log $stdoutLog
Rotate-Log $stderrLog
Log "Starting hybrid router on port $Port."

try {
    $process = Start-Process -FilePath $python -WorkingDirectory $proxyRoot -WindowStyle Hidden -PassThru -Wait `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ArgumentList @(
            "-m", "uvicorn", "hybrid_router:app",
            "--host", "127.0.0.1",
            "--port", "$Port",
            "--log-level", "warning",
            "--no-access-log",
            "--app-dir", $proxyRoot
        )
    Log "Hybrid router exited with code $($process.ExitCode)." $(if ($process.ExitCode -eq 0) { "INFO" } else { "ERROR" })
    exit $process.ExitCode
} catch {
    Log "Hybrid router failed to start: $($_.Exception.Message)" "ERROR"
    exit 30
}

