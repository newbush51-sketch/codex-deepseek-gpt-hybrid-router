
[CmdletBinding(SupportsShouldProcess)]
param([switch]$RemoveDeployedFiles)

$ErrorActionPreference = "Stop"
$taskNames = @("CodexClashProxy", "CodexDeepseekProxy", "CodexHybridRouter", "CodexProxyStackGuard")
foreach ($name in $taskNames) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($name, "Unregister scheduled task")) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
        }
    }
}

if ($RemoveDeployedFiles) {
    $targetRoot = Join-Path $env:USERPROFILE ".codex\deepseek-proxy"
    if ($PSCmdlet.ShouldProcess($targetRoot, "Remove deployed proxy files")) {
        Remove-Item -LiteralPath $targetRoot -Recurse -Force
    }
}


