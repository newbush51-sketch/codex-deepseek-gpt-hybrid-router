
param([int]$IntervalSeconds = 60)

$ErrorActionPreference = "Continue"
$proxyRoot = $PSScriptRoot
$ensureScript = Join-Path $proxyRoot "Ensure-CodexProxyStack.ps1"
$heartbeatFile = Join-Path $proxyRoot "stack-guard-heartbeat.txt"
$watchLog = Join-Path $proxyRoot "stack-watch.log"
$created = $false
$mutex = [Threading.Mutex]::new($true, "Local\CodexProxyStackGuard-$env:USERNAME", [ref]$created)

if (-not $created) { exit 0 }

try {
    while ($true) {
        try {
            $check = Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -PassThru -Wait -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ensureScript, "-Quiet"
            )
            $heartbeat = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') exit=$($check.ExitCode)"
            [IO.File]::WriteAllText($heartbeatFile, $heartbeat, [Text.UTF8Encoding]::new($false))
            if ($check.ExitCode -ne 0) {
                "$heartbeat stack check remained unhealthy" | Out-File -FilePath $watchLog -Append -Encoding utf8
            }
        } catch {
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') watcher error: $($_.Exception.Message)" |
                Out-File -FilePath $watchLog -Append -Encoding utf8
        }
        Start-Sleep -Seconds ([Math]::Max(30, $IntervalSeconds))
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

