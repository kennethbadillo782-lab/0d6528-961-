#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p reports
# Firma ad hoc local: sin ella el simulador niega el Llavero (sessionMissing).
# Solo el bundle de PRUEBAS recibe secretos efímeros. Nunca la .app entregada.
python3 - <<'PY'
import os,json
from pathlib import Path
Path('ios/FashionCatalogTests/NativeSecrets.json').write_text(json.dumps({k:os.environ.get(k,'') for k in ['MC_NATIVE_TOKEN_HASH','MC_NATIVE_API_KEY']}))
PY
trap 'rm -f ios/FashionCatalogTests/NativeSecrets.json' EXIT
python3 scripts/configure-cloud.py
(cd ios && xcodegen generate)
# Preferir iPhone 17 Pro Max; dejar registrada cualquier alternativa disponible.
udid=$(xcrun simctl list devices available -j | python3 -c '
import sys,json
ds=[d for v in json.load(sys.stdin)["devices"].values() for d in v if "iPhone" in d["name"]]
if not ds: raise SystemExit("No hay simulador iPhone instalado")
d=next((d for d in ds if d["name"]=="iPhone 17 Pro Max"),ds[0])
print(d["udid"])
')
echo "Destino real: $udid" | tee reports/ios-destination.txt
xcrun simctl boot "$udid" 2>/dev/null || true
python3 - "$udid" <<'PY' 2>&1 | tee reports/ios-boot.log
import subprocess,sys
try: subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=600)
except subprocess.TimeoutExpired: print('Arranque lento del simulador; xcodebuild seguirá esperando.')
PY
xcodebuild -project ios/MiCatalogo.xcodeproj -scheme MiCatalogo -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" -parallel-testing-enabled NO -derivedDataPath build/TestDerivedData \
  -resultBundlePath "reports/ios-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test \
  2>&1 | tee reports/ios-tests.log

# Captura del binario entregado, instalado y lanzado fuera del host XCTest.
xcrun simctl boot "$udid" 2>/dev/null || true
python3 - "$udid" <<'PY' 2>&1 | tee reports/ios-boot.log
import subprocess,sys
try: subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=600)
except subprocess.TimeoutExpired: print('Arranque lento del simulador; xcodebuild seguirá esperando.')
PY
xcrun simctl install "$udid" build/DerivedData/Build/Products/Debug-iphonesimulator/MiCatalogo.app
xcrun simctl launch --terminate-running-process "$udid" com.micatalogo.moda | tee reports/ios-launch.txt
sleep 3
xcrun simctl io "$udid" screenshot reports/ios-launch.png
