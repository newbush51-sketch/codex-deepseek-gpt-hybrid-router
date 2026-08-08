
@echo off
title Codex Proxy Stack Recovery
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codex\deepseek-proxy\Recover-CodexProxyStack.ps1"
set "RECOVERY_EXIT=%ERRORLEVEL%"
echo.
if "%RECOVERY_EXIT%"=="0" (
  echo Codex proxy stack is healthy.
) else (
  echo Recovery failed with exit code %RECOVERY_EXIT%.
)
echo.
pause
exit /b %RECOVERY_EXIT%

