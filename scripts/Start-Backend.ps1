$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!(Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Falta Docker Desktop. Instalarlo, habilitar WSL2 y arrancar contenedores Linux antes de continuar.' }
& docker info --format '{{.OSType}}' 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker no está arrancado.' }
& "$PSScriptRoot/Install-Tools.ps1"
$cli = Join-Path $root '.tools/supabase.exe'
$backend = Join-Path $root 'backend'
# Solo loopback; los contenedores permanecen activos al cerrar PowerShell.
& docker network inspect micatalogo-local *> $null
if ($LASTEXITCODE -ne 0) {
    & docker network create -o 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1' micatalogo-local | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la red local.' }
}
# start puede imprimir credenciales locales: no se muestran ni se guardan en diagnósticos.
$result = & $cli start --workdir $backend --network-id micatalogo-local 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Supabase no pudo iniciar. Comprueba Docker, recursos, puertos y descargas. No publiques la salida sin ocultar credenciales.' }
Write-Host 'Backend local iniciado. API: http://127.0.0.1:54321; Studio: http://127.0.0.1:54323'
Write-Host 'No es un despliegue público ni es accesible directamente desde Appetize.'
