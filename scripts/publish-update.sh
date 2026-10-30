#!/usr/bin/env bash
# Publica build/MiCatalogo.ipa en el repo público de actualizaciones para SideStore.
# Equivalente en la nube de Publish-Update.ps1: solo sube la IPA y source.json; nunca código, secretos ni datos.
# Requiere GH_TOKEN con permiso de escritura (Contents) en el repo público.
# Uso: bash scripts/publish-update.sh   (después de scripts/build-sideload.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
public='kennethbadillo782-lab/MiCatalogo-updates'
test -f build/MiCatalogo.ipa && test -f build/source.json || { echo 'Falta build/MiCatalogo.ipa o build/source.json'; exit 1; }
version=$(python3 -c "import json;print(json.load(open('build/source.json'))['apps'][0]['versions'][0]['version'])")
build=$(python3 -c "import json;print(json.load(open('build/source.json'))['apps'][0]['versions'][0]['buildVersion'])")
tag="v$version"
if ! gh release view "$tag" --repo "$public" >/dev/null 2>&1; then
  gh release create "$tag" build/MiCatalogo.ipa --repo "$public" --title "Mi Catálogo $version" --notes "Compilación $build" >/dev/null
fi
# Icono para SideStore: el repo privado no es legible, se copia una vez al público.
icon='ios/FashionCatalog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
if ! gh api "repos/$public/contents/icon.png" >/dev/null 2>&1; then
  python3 -c "import base64,json,sys;json.dump({'message':'Icono','content':base64.b64encode(open(sys.argv[1],'rb').read()).decode()},open('build/icon.json','w'))" "$icon"
  gh api --method PUT "repos/$public/contents/icon.png" --input build/icon.json >/dev/null
  rm -f build/icon.json
fi
# La primera vez no existe (404): se publica sin historial.
gh api "repos/$public/contents/source.json" > build/current.json 2>/dev/null || echo '{}' > build/current.json
python3 - "$public" "$tag" <<'PY'
import base64,json,os,sys
public,tag=sys.argv[1:]
src=json.load(open('build/source.json'))
v=src['apps'][0]['versions'][0]
v['downloadURL']=f'https://github.com/{public}/releases/download/{tag}/MiCatalogo.ipa'
v['size']=os.path.getsize('build/MiCatalogo.ipa')
v['localizedDescription']=os.environ.get('NOVEDADES') or f"Compilación {v['buildVersion']}"
src['apps'][0]['iconURL']=f'https://raw.githubusercontent.com/{public}/main/icon.png'
cur=json.load(open('build/current.json'))
if cur.get('content'):
    old=json.loads(base64.b64decode(cur['content']).decode('utf-8'))
    # La fuente conserva el historial: versión nueva primero.
    src['apps'][0]['versions']=[v]+[o for o in old['apps'][0]['versions'] if o['version']!=v['version']]
body={'message':f'Publicar {tag}','content':base64.b64encode(json.dumps(src,ensure_ascii=False,indent=1).encode('utf-8')).decode()}
if cur.get('sha'): body['sha']=cur['sha']
json.dump(body,open('build/body.json','w'))
PY
gh api --method PUT "repos/$public/contents/source.json" --input build/body.json >/dev/null
rm -f build/current.json build/body.json
echo "Publicada $tag. Fuente para SideStore: https://raw.githubusercontent.com/$public/main/source.json"
