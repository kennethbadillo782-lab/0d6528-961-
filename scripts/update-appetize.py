"""Actualiza una app EXISTENTE; requiere autorización y cuenta ya configurada.
No imprime tokens, respuesta del proveedor ni claves de acceso a la app.
"""
import base64, json, os, re, sys, urllib.request, urllib.error, uuid, zipfile
from pathlib import Path
token = os.environ.get('APPETIZE_API_TOKEN', '')
app = os.environ.get('APPETIZE_APP_PUBLIC_KEY', '')
if not token or not re.fullmatch(r'[A-Za-z0-9_-]+', app):
    raise SystemExit('Configura APPETIZE_API_TOKEN y APPETIZE_APP_PUBLIC_KEY en el gestor de secretos.')
p = Path(sys.argv[1] if len(sys.argv)>1 else 'build/MiCatalogo-simulator.zip')
with zipfile.ZipFile(p) as z:
    if not any(n.endswith('.app/Info.plist') for n in z.namelist()): raise SystemExit('El ZIP no contiene un bundle .app.')
boundary = uuid.uuid4().hex
body = (f'--{boundary}\r\nContent-Disposition: form-data; name="platform"\r\n\r\nios\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="MiCatalogo-simulator.zip"\r\nContent-Type: application/zip\r\n\r\n').encode()+p.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
request = urllib.request.Request(f'https://api.appetize.io/v1/apps/{app}', data=body, method='POST', headers={
    'Authorization':'Basic '+base64.b64encode((token+':').encode()).decode(),
    'Content-Type':f'multipart/form-data; boundary={boundary}',
})
try:
    with urllib.request.urlopen(request, timeout=180) as response:
        if response.status not in (200,201): raise SystemExit('Appetize rechazó la actualización.')
        json.load(response)
    print('Appetize actualizado. Abre la app desde tu panel privado y revisa su control de acceso.')
except urllib.error.HTTPError as error:
    raise SystemExit(f'Appetize devolvió HTTP {error.code}; revisa permisos y configuración en tu panel.') from None
except urllib.error.URLError:
    raise SystemExit('No se pudo conectar a Appetize.') from None
