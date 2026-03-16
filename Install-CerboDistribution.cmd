@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "DEPLOY_PS1=%SCRIPT_DIR%Deploy-CerboDistribution.ps1"

if not exist "%DEPLOY_PS1%" (
    echo No se encuentra Deploy-CerboDistribution.ps1 en:
    echo %DEPLOY_PS1%
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DEPLOY_PS1%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo El despliegue ha fallado con codigo %EXIT_CODE%.
) else (
    echo Despliegue finalizado correctamente.
)

pause
exit /b %EXIT_CODE%
