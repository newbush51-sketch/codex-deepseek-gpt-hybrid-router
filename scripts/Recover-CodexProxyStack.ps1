
$ErrorActionPreference = "Continue"
$proxyRoot = $PSScriptRoot
$ensureScript = Join-Path $proxyRoot "Ensure-CodexProxyStack.ps1"

Write-Host ""
Write-Host "Codex proxy stack recovery" -ForegroundColor Cyan
Write-Host "--------------------------"

if (-not (Test-Path -LiteralPath $ensureScript)) {
    Write-Host "Recovery script is missing: $ensureScript" -ForegroundColor Red
    exit 10
}

try {
    $guard = Get-ScheduledTask -TaskName "CodexProxyStackGuard" -ErrorAction SilentlyContinue
    if ($guard -and $guard.State -ne "Running") {
        Start-ScheduledTask -TaskName "CodexProxyStackGuard"
        Write-Host "Started the background stack guard."
    }
} catch {
    Write-Host "The guard task could not be started; direct recovery will continue." -ForegroundColor Yellow
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ensureScript -FullCheck
$code = $LASTEXITCODE

if ($code -eq 0) {
    Write-Host ""
    Write-Host "Recovery succeeded. Codex can use the local router again." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Recovery is incomplete. Check these logs:" -ForegroundColor Red
    Write-Host "  $proxyRoot\stack-guard.log"
    Write-Host "  $proxyRoot\autostart-clash.log"
    Write-Host "  $proxyRoot\autostart.log"
    Write-Host "  $proxyRoot\autostart-deepseek.log"
}

exit $code

