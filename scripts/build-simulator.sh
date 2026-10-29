#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Se necesita macOS con Xcode 16 o posterior.'; exit 1; }
command -v xcodegen >/dev/null || { echo 'Instala XcodeGen: brew install xcodegen'; exit 1; }
mkdir -p build reports
python3 - <<'PY'
from pathlib import Path
for p in Path('reports').glob('ios-*'):
    if p.is_file(): p.unlink()
PY
xcodebuild -version
python3 scripts/configure-cloud.py
(cd ios && xcodegen generate)
# Appetize recomienda ARM simulator; una .ipa de dispositivo no sirve aquí.
xcodebuild -project ios/MiCatalogo.xcodeproj -scheme MiCatalogo \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tee reports/ios-build.log
app='build/DerivedData/Build/Products/Debug-iphonesimulator/MiCatalogo.app'
test -d "$app"
file "$app/MiCatalogo" | tee reports/ios-binary.txt
xcrun vtool -show-build "$app/MiCatalogo" | tee -a reports/ios-binary.txt
ditto -c -k --sequesterRsrc --keepParent "$app" build/MiCatalogo-simulator.zip
echo 'Compilación terminada; consultar los resultados de pruebas de sincronización.'
