$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $root '.tools/supabase.exe'
$statusText = & $cli status --workdir (Join-Path $root 'backend') --output json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Primero inicia Supabase local. No se ejecutaron pruebas reales.' }
$status = ($statusText -join "`n") | ConvertFrom-Json
try {
    $env:MC_TEST_URL = $status.API_URL
    $env:MC_TEST_ANON_KEY = $status.ANON_KEY
    $env:MC_TEST_SERVICE_KEY = $status.SERVICE_ROLE_KEY
    node "$PSScriptRoot/test-live.mjs"
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas con Supabase local.' }
} finally {
    Remove-Item Env:MC_TEST_URL,Env:MC_TEST_ANON_KEY,Env:MC_TEST_SERVICE_KEY -ErrorAction SilentlyContinue
}
