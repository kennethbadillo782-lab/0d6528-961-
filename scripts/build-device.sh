#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${IOS_BUNDLE_ID:?Configura tu bundle id en Codemagic y en ios_signing}"
: "${APPLE_TEAM_ID:?Configura el Team ID de Apple, no una contraseña}"
mkdir -p build reports
(cd ios && xcodegen generate)
# use-profiles debe ver el mismo bundle id que el perfil, antes del archive.
python3 - <<'PY'
import os,re
from pathlib import Path
bundle=os.environ['IOS_BUNDLE_ID']
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',bundle): raise SystemExit('Bundle id inválido')
p=Path('ios/MiCatalogo.xcodeproj/project.pbxproj')
p.write_text(p.read_text().replace('com.micatalogo.moda',bundle))
PY
# Codemagic debe haber cargado certificado y perfil. No crea cuentas ni compra planes.
xcode-project use-profiles
xcodebuild -project ios/MiCatalogo.xcodeproj -scheme MiCatalogo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/MiCatalogo.xcarchive \
  PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  archive 2>&1 | tee reports/ios-archive.log
xcodebuild -exportArchive -archivePath build/MiCatalogo.xcarchive \
  -exportOptionsPlist "$HOME/export_options.plist" -exportPath build/device \
  2>&1 | tee reports/ios-export.log
