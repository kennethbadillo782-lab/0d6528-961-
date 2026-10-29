$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File $PSCommandPath
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el lanzador Docker local.' }
    return
}
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root '.tools/loopback/docker.exe'
New-Item -ItemType Directory -Force (Split-Path $output -Parent) | Out-Null
$source = Join-Path $PSScriptRoot 'docker-loopback.cs'
if ((Test-Path $output) -and (Get-Item $output).LastWriteTimeUtc -ge (Get-Item $source).LastWriteTimeUtc) { return }
if (Test-Path $output) { Remove-Item -LiteralPath $output }
Add-Type -TypeDefinition (Get-Content -Raw -Encoding utf8 $source) -OutputAssembly $output -OutputType ConsoleApplication
Write-Host 'Lanzador local de Docker compilado (sin cambios globales en Docker).'
