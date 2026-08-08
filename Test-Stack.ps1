
$ErrorActionPreference = "Stop"
$targetRoot = Join-Path $env:USERPROFILE ".codex\deepseek-proxy"
$check = Join-Path $targetRoot "Ensure-CodexProxyStack.ps1"
if (-not (Test-Path -LiteralPath $check)) {
    throw "The stack is not installed. Run .\Install.ps1 first."
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -FullCheck
exit $LASTEXITCODE


