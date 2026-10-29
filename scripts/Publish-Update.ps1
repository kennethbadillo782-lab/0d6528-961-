# Publica la última IPA compilada en el repo público de actualizaciones para SideStore.
# Solo sube MiCatalogo.ipa y source.json; nunca código, secretos ni datos.
# Uso: ./scripts/Publish-Update.ps1 [-RunId <id>]
param([string]$RunId)
$ErrorActionPreference = 'Stop'
$private = 'kennethbadillo782-lab/MiCatalogo'
$public = 'kennethbadillo782-lab/MiCatalogo-updates'
if (-not $RunId) {
    $RunId = (gh run list --repo $private --workflow ios-sideload.yml --status success --limit 1 --json databaseId | ConvertFrom-Json).databaseId
}
if (-not $RunId) { throw 'No hay compilación iOS SideStore IPA exitosa.' }
$work = Join-Path $env:TEMP "micatalogo-update-$RunId"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
gh run download $RunId --repo $private --dir $work | Out-Null
$ipa = Get-ChildItem $work -Recurse -Filter MiCatalogo.ipa | Select-Object -First 1
$sourceFile = Get-ChildItem $work -Recurse -Filter source.json | Select-Object -First 1
if (-not $ipa -or -not $sourceFile) { throw 'El artefacto no contiene IPA y source.json.' }
$source = Get-Content -Raw -Encoding UTF8 $sourceFile.FullName | ConvertFrom-Json
$v = $source.apps[0].versions[0]
$tag = "v$($v.version)"
$ErrorActionPreference = 'Continue'
gh release view $tag --repo $public 2>$null | Out-Null
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    gh release create $tag $ipa.FullName --repo $public --title "Mi Catálogo $($v.version)" --notes "Compilación $($v.buildVersion)" | Out-Null
}
$v.downloadURL = "https://github.com/$public/releases/download/$tag/MiCatalogo.ipa"
$v.size = $ipa.Length
# La fuente conserva el historial: versión nueva primero.
$current = $null
# La primera vez no existe (404): PowerShell 5.1 lo volvería fatal con Stop.
$ErrorActionPreference = 'Continue'
$raw = gh api "repos/$public/contents/source.json" 2>$null
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -eq 0) { $current = $raw | ConvertFrom-Json }
if ($current) {
    $old = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($current.content)) | ConvertFrom-Json
    $source.apps[0].versions = @($v) + @($old.apps[0].versions | Where-Object { $_.version -ne $v.version })
}
$json = $source | ConvertTo-Json -Depth 8
$body = @{ message = "Publicar $tag"; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)) }
if ($current) { $body.sha = $current.sha }
# Archivo sin BOM: la tubería de PowerShell 5.1 corrompe el JSON (HTTP 400).
$bodyFile = Join-Path $work 'body.json'
[IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
gh api --method PUT "repos/$public/contents/source.json" --input $bodyFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'No se pudo publicar source.json.' }
Remove-Item -Recurse -Force $work
Write-Output "Publicada $tag. Fuente para SideStore: https://raw.githubusercontent.com/$public/main/source.json"
