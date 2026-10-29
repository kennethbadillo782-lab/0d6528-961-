param([Parameter(Mandatory=$true)][string]$PgBin)
$ErrorActionPreference = 'Stop'
python "$PSScriptRoot/test-database.py" --pg-bin $PgBin
if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas SQL. Ver reports/database.json.' }
