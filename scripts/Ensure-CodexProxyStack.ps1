
[CmdletBinding()]
param(
    [switch]$FullCheck,
    [switch]$Quiet,
    [int]$RepairTimeoutSeconds = 75
)

$ErrorActionPreference = "Stop"
$proxyRoot = $PSScriptRoot
$clashLauncher = Join-Path $proxyRoot "autostart-clash.ps1"
$hybridLauncher = Join-Path $proxyRoot "autostart-hybrid-router.ps1"
$deepseekLauncher = Join-Path $proxyRoot "autostart-deepseek-proxy.ps1"
$logFile = Join-Path $proxyRoot "stack-guard.log"

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

function Test-TcpPort([int]$Port, [int]$TimeoutMs = 800) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Test-Health([int]$Port) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health/liveliness" -TimeoutSec 3
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Wait-Health([int]$Port, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-Health $Port) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Start-ComponentTask([string]$TaskName, [string]$FallbackScript, [int]$Port) {
    Log "$TaskName is unhealthy; starting recovery." "WARN"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        if ($task.State -eq "Running") {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Start-ScheduledTask -TaskName $TaskName
    } else {
        Log "$TaskName is missing; using the direct launcher." "WARN"
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $FallbackScript
        )
    }

    if (Wait-Health $Port $RepairTimeoutSeconds) {
        Log "$TaskName recovered on port $Port."
        return $true
    }

    Log "$TaskName did not recover on port $Port." "ERROR"
    return $false
}

function Test-Upstream {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:4140/v1/models" `
            -Headers @{ Authorization = "Bearer codex-stack-diagnostic-invalid-token" } -TimeoutSec 15
        return $response.StatusCode -in 200, 401, 403, 404
    } catch {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            return $status -in 401, 403, 404
        }
        return $false
    }
}

$clashOk = Test-TcpPort 7897
if (-not $clashOk) {
    Log "Clash port 7897 is unavailable; invoking the Clash recovery launcher." "WARN"
    & $clashLauncher -WaitSeconds $RepairTimeoutSeconds
    $clashExit = $LASTEXITCODE
    $clashOk = ($clashExit -eq 0) -and (Test-TcpPort 7897)
    if (-not $clashOk) { Log "Clash recovery failed with exit code $clashExit." "ERROR" }
}

$deepseekOk = Test-Health 4141
if (-not $deepseekOk) {
    $deepseekOk = Start-ComponentTask "CodexDeepseekProxy" $deepseekLauncher 4141
}

$hybridOk = Test-Health 4140
if ($clashOk -and -not $hybridOk) {
    $hybridOk = Start-ComponentTask "CodexHybridRouter" $hybridLauncher 4140
} elseif (-not $clashOk) {
    $hybridOk = $false
    Log "Hybrid router recovery was deferred because Clash is unavailable." "ERROR"
}

$upstreamOk = $null
if ($FullCheck -and $clashOk -and $hybridOk) {
    $upstreamOk = Test-Upstream
    if (-not $upstreamOk) { Log "Hybrid router is alive but the OpenAI upstream probe failed." "ERROR" }
}

$success = $clashOk -and $hybridOk -and $deepseekOk -and (($upstreamOk -ne $false))
$result = [pscustomobject]@{
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Clash7897 = $clashOk
    Hybrid4140 = $hybridOk
    DeepSeek4141 = $deepseekOk
    OpenAIUpstream = $upstreamOk
    Healthy = $success
}

if (-not $Quiet) { $result | Format-List }
if ($success) { exit 0 }
exit 1

