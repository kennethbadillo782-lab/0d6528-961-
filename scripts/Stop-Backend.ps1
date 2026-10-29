$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root '.tools/supabase.exe') stop --workdir (Join-Path $root 'backend')
if ($LASTEXITCODE -ne 0) { throw 'No se pudo detener Supabase.' }
