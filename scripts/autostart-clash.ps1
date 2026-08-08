
param(
    [int]$WaitSeconds = 60,
    [switch]$ForceRestart
)

$ErrorActionPreference = "Stop"
$proxyRoot = $PSScriptRoot
$clashDir = [Environment]::GetEnvironmentVariable("CLASH_VERGE_DIR", "User")
if ([string]::IsNullOrWhiteSpace($clashDir)) {
    $clashDir = Join-Path $env:LOCALAPPDATA "Programs\Clash Verge"
}
$appExe = Join-Path $clashDir "clash-verge.exe"
$primaryCoreExe = Join-Path $clashDir "verge-mihomo.exe"
$fallbackCoreExe = Join-Path $proxyRoot "bin\verge-mihomo.exe"
$coreCandidates = @(
    if (Test-Path -LiteralPath $primaryCoreExe) { $primaryCoreExe }
    if (Test-Path -LiteralPath $fallbackCoreExe) { $fallbackCoreExe }
)
$configRoot = Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev"
$coreConfig = Join-Path $configRoot "clash-verge.yaml"
$logFile = Join-Path $proxyRoot "autostart-clash.log"
$port = 7897

function Rotate-Log([string]$Path) {
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 2MB) {
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

function Test-TcpPort([int]$TcpPort, [int]$TimeoutMs = 800) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect("127.0.0.1", $TcpPort, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-ForPort([int]$TcpPort, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-TcpPort $TcpPort) { return $true }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Stop-ClashProcesses {
    Get-Process -Name "clash-verge", "verge-mihomo" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Start-StandaloneCore {
    param([string]$Reason)

    if (-not (Test-Path -LiteralPath $coreConfig)) {
        Log "Mihomo configuration is missing: $coreConfig" "ERROR"
        return $false
    }

    foreach ($candidate in $coreCandidates) {
        try {
            Stop-ClashProcesses
            Log "$Reason; trying standalone Mihomo core: $candidate" "WARN"
            Start-Process -FilePath $candidate -WorkingDirectory (Split-Path -Parent $candidate) `
                -WindowStyle Hidden -ArgumentList @(
                    "-d", $configRoot,
                    "-f", $coreConfig,
                    "-ext-ctl-pipe", "\\.\pipe\verge-mihomo"
                )
            if (Wait-ForPort $port 30) {
                Log "Standalone Mihomo core is serving port ${port}: $candidate" "WARN"
                return $true
            }
            Log "Standalone Mihomo candidate did not open port ${port}: $candidate" "ERROR"
        } catch {
            Log "Standalone Mihomo candidate failed ($candidate): $($_.Exception.Message)" "ERROR"
        }
    }

    Stop-ClashProcesses
    return $false
}

if ((Test-TcpPort $port) -and -not $ForceRestart) {
    Log "Clash mixed port $port is already available; skip."
    exit 0
}

if (-not (Test-Path -LiteralPath $appExe)) {
    Log "Clash Verge app is unavailable at $appExe; attempting the local core fallback." "WARN"
    if (Start-StandaloneCore "The configured Clash app is unavailable") { exit 0 }
    Log "Neither the Clash app nor a working local core fallback is available." "ERROR"
    exit 10
}

try {
    if ($ForceRestart) { Stop-ClashProcesses }

    $app = Get-Process -Name "clash-verge" -ErrorAction SilentlyContinue
    if (-not $app) {
        Log "Starting Clash Verge from $appExe"
        Start-Process -FilePath $appExe -WorkingDirectory $clashDir -WindowStyle Hidden
    } else {
        Log "Clash Verge is running but port $port is not ready; waiting before recovery."
    }

    if (Wait-ForPort $port ([Math]::Max(15, $WaitSeconds))) {
        Log "Clash mixed port $port is ready."
        exit 0
    }

    Log "First Clash startup attempt did not open port $port; restarting the app and core." "WARN"
    Stop-ClashProcesses
    Start-Process -FilePath $appExe -WorkingDirectory $clashDir -WindowStyle Hidden
    if (Wait-ForPort $port 45) {
        Log "Clash recovered after a clean app restart."
        exit 0
    }

    # Emergency availability fallback. The GUI stays stopped so it cannot race
    # the standalone core for the same listening port.
    if (Start-StandaloneCore "Clash app recovery failed") { exit 0 }

    Log "Unable to restore Clash port $port." "ERROR"
    exit 20
} catch {
    Log "Unhandled Clash recovery error: $($_.Exception.Message)" "ERROR"
    exit 30
}

