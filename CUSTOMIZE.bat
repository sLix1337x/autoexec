@echo off
rem  Double-clickable launcher for _tools_customize.ps1 -- no Python needed.
rem  Any arguments are passed through, e.g.:
rem    CUSTOMIZE.bat --profile builds/full/profile.json --out my-copy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_tools_customize.ps1" %*
if errorlevel 1 (
    echo.
    pause
)
