
param([int]$Port = 4141)

$ErrorActionPreference = "Stop"
$proxyRoot = $PSScriptRoot
$litellm = Join-Path $proxyRoot ".venv\Scripts\litellm.exe"
$config = Join-Path $proxyRoot "config.yaml"
$logFile = Join-Path $proxyRoot "autostart-deepseek.log"
$stdoutLog = Join-Path $proxyRoot "deepseek-proxy.stdout.log"
$stderrLog = Join-Path $proxyRoot "deepseek-proxy.stderr.log"

function Rotate-Log([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 10MB) {
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

$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:ALL_PROXY = ""
$env:NO_PROXY = "localhost,127.0.0.1,::1,api.deepseek.com,.deepseek.com"

if (Test-Health) {
    Log "DeepSeek proxy already healthy on port $Port; skip."
    exit 0
}

$deepSeekKey = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User")
if ([string]::IsNullOrWhiteSpace($deepSeekKey)) {
    Log "DEEPSEEK_API_KEY is not configured in the Windows user environment." "ERROR"
    exit 10
}
if (-not (Test-Path -LiteralPath $litellm)) {
    Log "LiteLLM executable is missing: $litellm" "ERROR"
    exit 11
}
if (-not (Test-Path -LiteralPath $config)) {
    Log "LiteLLM configuration is missing: $config" "ERROR"
    exit 12
}

$env:DEEPSEEK_API_KEY = $deepSeekKey
Rotate-Log $stdoutLog
Rotate-Log $stderrLog
Log "Starting DeepSeek LiteLLM proxy on port $Port."

try {
    $process = Start-Process -FilePath $litellm -WorkingDirectory $proxyRoot -WindowStyle Hidden -PassThru -Wait `
        -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ArgumentList @(
            "--config", $config,
            "--host", "127.0.0.1",
            "--port", "$Port",
            "--num_workers", "1"
        )
    Log "DeepSeek proxy exited with code $($process.ExitCode)." $(if ($process.ExitCode -eq 0) { "INFO" } else { "ERROR" })
    exit $process.ExitCode
} catch {
    Log "DeepSeek proxy failed to start: $($_.Exception.Message)" "ERROR"
    exit 30
}

