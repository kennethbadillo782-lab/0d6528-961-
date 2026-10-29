$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dockerBin = Join-Path $env:ProgramFiles 'Docker/Docker/resources/bin'
if (Test-Path (Join-Path $dockerBin 'docker.exe')) { $env:PATH = "$dockerBin;$env:PATH" }
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
$binding = & docker network inspect micatalogo-local --format '{{index .Options "com.docker.network.bridge.host_binding_ipv4"}}'
if ($LASTEXITCODE -ne 0 -or $binding.Trim() -ne '127.0.0.1') { throw 'La red micatalogo-local existente no está limitada a loopback. Revisarla antes de arrancar servicios.' }
# start puede imprimir credenciales locales: no se muestran ni se guardan en diagnósticos.
$result = & $cli start --workdir $backend --network-id micatalogo-local 2>&1
$code = $LASTEXITCODE
$safe = ($result | ForEach-Object {
    $line = $_.ToString()
    if ($line -match '(?i)key|secret|token|password|credential|postgres(ql)?://') { '[línea de credenciales omitida]' }
    else { $line -replace 'mc_[a-f0-9]{48}|eyJ[A-Za-z0-9_.-]+', '[secreto omitido]' }
}) -join "`n"
New-Item -ItemType Directory -Force (Join-Path $root 'reports') | Out-Null
Set-Content -LiteralPath (Join-Path $root 'reports/backend-start.log') -Value $safe -Encoding utf8
if ($code -ne 0) { throw 'Supabase no pudo iniciar. Comprueba reports/backend-start.log (credenciales filtradas).' }
Write-Host 'Backend local iniciado. API: http://127.0.0.1:54321; Studio: http://127.0.0.1:54323'
Write-Host 'No es un despliegue público ni es accesible directamente desde Appetize.'
