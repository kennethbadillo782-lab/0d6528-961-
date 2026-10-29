$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root '.tools'
New-Item -ItemType Directory -Force $dir | Out-Null
$version = '2.122.0'
$name = "supabase_${version}_windows_amd64.zip"
$expected = '60031fd5bf050fc12a0c6aef68997600d143870f944bf13109c7765dca329af8'
$zip = Join-Path $dir $name
if (!(Test-Path (Join-Path $dir 'supabase.exe'))) {
    Invoke-WebRequest "https://github.com/supabase/cli/releases/download/v$version/$name" -OutFile $zip
    if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'SHA256 de Supabase incorrecto.' }
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
}
& (Join-Path $dir 'supabase.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'Supabase CLI no funciona.' }
Write-Host 'Node 24 y Docker Desktop con contenedores Linux son requisitos adicionales.'
