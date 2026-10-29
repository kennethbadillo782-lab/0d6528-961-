param([string]$PgBin, [switch]$Live)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$PgBin) { $PgBin = Join-Path $root '.tools/pgsql/bin' }
$python = Join-Path $root '.venv/Scripts/python.exe'
if (!(Test-Path $python)) { $python = (Get-Command python -ErrorAction Stop).Source }
$failed = @()
& $python "$PSScriptRoot/check-configs.py"
if ($LASTEXITCODE -ne 0) { $failed += 'configuraciones (instalar requirements-checks.txt)' }
node "$PSScriptRoot/test-all.mjs"
if ($LASTEXITCODE -ne 0) { $failed += 'Node/API simulada' }
if (Test-Path (Join-Path $PgBin 'postgres.exe')) {
    & $python "$PSScriptRoot/test-database.py" --pg-bin $PgBin
    if ($LASTEXITCODE -ne 0) { $failed += 'PostgreSQL real' }
} else { $failed += 'PostgreSQL no instalado: scripts/Install-Postgres.ps1' }
if ($Live) { & "$PSScriptRoot/Test-Live.ps1" }
else { Write-Host 'OMITIDO: Supabase completo. Usar -Live tras Start-Backend.ps1.' }
Write-Host 'iOS y XSS tienen comandos separados; no se declaran verificados con este comando.'
if ($failed.Count) { throw ($failed -join '; ') }
