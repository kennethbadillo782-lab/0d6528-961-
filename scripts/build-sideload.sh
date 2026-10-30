#!/usr/bin/env bash
# IPA de dispositivo SIN firmar para SideStore/AltStore: ellos la firman con el Apple ID gratuito.
# Uso: bash scripts/build-sideload.sh <build_number> [download_url]
set -euo pipefail
cd "$(dirname "$0")/.."
build="${1:?número de compilación}"; url="${2:-}"
version="1.0.$build"
mkdir -p build reports
python3 scripts/configure-cloud.py
(cd ios && xcodegen generate)
xcodebuild -project ios/MiCatalogo.xcodeproj -scheme MiCatalogo -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DeviceDerivedData \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build 2>&1 | tee reports/ios-sideload-build.log
app='build/DeviceDerivedData/Build/Products/Release-iphoneos/MiCatalogo.app'
test -d "$app"
# SideStore rechaza la IPA si su CFBundleVersion no coincide con la fuente.
actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")
[ "$actual" = "$build" ] || { echo "CFBundleVersion $actual != $build"; exit 1; }
rm -rf build/Payload build/MiCatalogo.ipa; mkdir -p build/Payload; cp -R "$app" build/Payload/
(cd build && zip -qry MiCatalogo.ipa Payload)
# Nada secreto en el binario entregado: solo URL y clave pública.
if strings -a "$app/MiCatalogo" | grep -E 'service_role|sb_secret_[A-Za-z0-9_-]{8,}' ; then echo 'Secreto en el binario'; exit 1; fi
python3 - "$version" "$build" "$url" <<'PY'
import json,os,sys,datetime
version,build,url=sys.argv[1:]
size=os.path.getsize('build/MiCatalogo.ipa')
src={"name":"MiCatalogo privado","identifier":"com.micatalogo.source","apps":[{
 "name":"Mi Catálogo","bundleIdentifier":"com.micatalogo.moda","developerName":"Personal",
 "localizedDescription":"Catálogo personal de moda.","iconURL":"","versions":[{
  "version":version,"buildVersion":build,"date":datetime.date.today().isoformat(),
  "downloadURL":url,"size":size,"minOSVersion":"17.0"}]}]}
json.dump(src,open('build/source.json','w'),ensure_ascii=False,indent=1)
PY
echo "IPA $version lista: build/MiCatalogo.ipa"
