# Ejecutar como administrador. No reinicia el equipo automáticamente.
$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Este paso requiere una consola como administrador de Windows.' }
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force (Join-Path $root 'reports') | Out-Null
$ErrorActionPreference = 'Continue'
& wsl.exe --install --no-distribution --no-launch 2>&1 | Out-File (Join-Path $root 'reports/wsl-install.log') -Encoding utf8
$code = $LASTEXITCODE
Set-Content -LiteralPath (Join-Path $root 'reports/wsl-install-exit.txt') -Value $code
exit $code
