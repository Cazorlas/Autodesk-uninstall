@echo off
setlocal
net session >nul 2>&1
if %errorlevel% equ 0 goto run
set "ADSK_CLEANER_LAUNCHER=%~f0"
set "ADSK_CLEANER_ARGS=%*"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = @{FilePath=$env:ADSK_CLEANER_LAUNCHER; Verb='RunAs'; Wait=$true; ErrorAction='Stop'}; if ($env:ADSK_CLEANER_ARGS) {$p.ArgumentList=$env:ADSK_CLEANER_ARGS}; try {Start-Process @p} catch {Write-Host $_; exit 1}"
if errorlevel 1 pause
exit /b
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutodeskCleaner.ps1" %*
set "ADSK_CLEANER_EXIT=%errorlevel%"
pause
exit /b %ADSK_CLEANER_EXIT%
