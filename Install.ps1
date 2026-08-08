
[CmdletBinding()]
param(
    [string]$ClashVergeDir = "",
    [switch]$SkipDependencies,
    [switch]$SkipScheduledTasks
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$targetRoot = Join-Path $env:USERPROFILE ".codex\deepseek-proxy"
$codexRoot = Join-Path $env:USERPROFILE ".codex"
$python = Join-Path $targetRoot ".venv\Scripts\python.exe"
$powerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

function Copy-Required([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { throw "Required source is missing: $Source" }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function New-LogonTask(
    [string]$Name,
    [string]$Script,
    [int]$DelaySeconds,
    [string]$Description,
    [int]$RestartCount = 20
) {
    $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument (
        '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Script + '"'
    )
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
    $trigger.Delay = "PT${DelaySeconds}S"
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RestartCount $RestartCount -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description $Description -Force | Out-Null
}

New-Item -ItemType Directory -Force $targetRoot | Out-Null
New-Item -ItemType Directory -Force (Join-Path $targetRoot "bin") | Out-Null

Copy-Required (Join-Path $repoRoot "src\hybrid_router.py") (Join-Path $targetRoot "hybrid_router.py")
Copy-Required (Join-Path $repoRoot "config\config.yaml") (Join-Path $targetRoot "config.yaml")
Copy-Required (Join-Path $repoRoot "catalog\models.json") (Join-Path $targetRoot "models.json")
Copy-Required (Join-Path $repoRoot "tools\build_hybrid_catalog.py") (Join-Path $targetRoot "build_hybrid_catalog.py")
Get-ChildItem -LiteralPath (Join-Path $repoRoot "scripts") -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetRoot $_.Name) -Force
}

if (-not [string]::IsNullOrWhiteSpace($ClashVergeDir)) {
    if (-not (Test-Path -LiteralPath $ClashVergeDir)) { throw "Clash directory does not exist: $ClashVergeDir" }
    [Environment]::SetEnvironmentVariable("CLASH_VERGE_DIR", $ClashVergeDir, "User")
}
$configuredClashDir = [Environment]::GetEnvironmentVariable("CLASH_VERGE_DIR", "User")
if (-not [string]::IsNullOrWhiteSpace($configuredClashDir)) {
    $primaryCore = Join-Path $configuredClashDir "verge-mihomo.exe"
    if (Test-Path -LiteralPath $primaryCore) {
        Copy-Item -LiteralPath $primaryCore -Destination (Join-Path $targetRoot "bin\verge-mihomo.exe") -Force
    }
}

if (-not $SkipDependencies) {
    if (-not (Test-Path -LiteralPath $python)) {
        & python -m venv (Join-Path $targetRoot ".venv")
    }
    & $python -m pip install -U -r (Join-Path $repoRoot "requirements.txt")
}

$modelCache = Join-Path $codexRoot "models_cache.json"
if (Test-Path -LiteralPath $modelCache) {
    & $python (Join-Path $targetRoot "build_hybrid_catalog.py") `
        --codex-catalog $modelCache `
        --deepseek-catalog (Join-Path $targetRoot "models.json") `
        --output (Join-Path $targetRoot "hybrid-models.json")
} else {
    Write-Warning "Codex models_cache.json was not found. Start Codex once, then rerun Install.ps1."
}

if (-not $SkipScheduledTasks) {
    New-LogonTask "CodexClashProxy" (Join-Path $targetRoot "autostart-clash.ps1") 5 `
        "Ensures the local Clash proxy is available for Codex." 20
    New-LogonTask "CodexDeepseekProxy" (Join-Path $targetRoot "autostart-deepseek-proxy.ps1") 10 `
        "Runs the local DeepSeek LiteLLM proxy with automatic restart." 50
    New-LogonTask "CodexHybridRouter" (Join-Path $targetRoot "autostart-hybrid-router.ps1") 20 `
        "Runs the Codex hybrid router after Clash is ready." 50
    New-LogonTask "CodexProxyStackGuard" (Join-Path $targetRoot "Watch-CodexProxyStack.ps1") 35 `
        "Continuously checks and repairs the complete Codex proxy stack." 999
    Start-ScheduledTask -TaskName "CodexProxyStackGuard"
}

Write-Host "Installed to $targetRoot" -ForegroundColor Green
Write-Host "Next: merge config/config.toml.snippet into $codexRoot\config.toml, replacing YOUR_NAME."
Write-Host "Then run: powershell -File `"$targetRoot\Ensure-CodexProxyStack.ps1`" -FullCheck"


