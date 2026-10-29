$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root '.tools'
New-Item -ItemType Directory -Force $dir | Out-Null
$zip = Join-Path $dir 'postgresql-16.15.zip'
if (!(Test-Path (Join-Path $dir 'pgsql/bin/postgres.exe'))) {
    # EDB es el proveedor enlazado por postgresql.org para Windows.
    Invoke-WebRequest 'https://sbp.enterprisedb.com/getfile.jsp?fileid=1260623' -OutFile $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($hash -ne '43BB45F173A6F08CF1D29A97A6D8DEB119E8E8093A24C00D2D1001A0CCAA8281') { throw 'Archivo de PostgreSQL distinto del verificado.' }
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
}
& (Join-Path $dir 'pgsql/bin/postgres.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL no funciona.' }
