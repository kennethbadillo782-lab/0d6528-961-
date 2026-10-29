"""Genera xcconfig local con URL/clave ANON pública. Nunca admite claves de servicio."""
from pathlib import Path
import json,base64,os
root=Path(__file__).resolve().parent.parent
config=json.loads((root/'ios/Config/cloud-public.json').read_text())
url=os.environ.get('SUPABASE_URL',config['url']);key=os.environ.get('SUPABASE_ANON_KEY',config['anonKey'])
assert url=='https://ddppztnamwmryhamezwy.supabase.co'
claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
assert claims.get('role')=='anon' and claims.get('ref')=='ddppztnamwmryhamezwy'
(root/'ios/Config/Cloud.xcconfig').write_text('SUPABASE_URL = https:/$()/ddppztnamwmryhamezwy.supabase.co\nSUPABASE_ANON_KEY = '+key+'\n',encoding='utf-8')
print('Configuración pública generada; ninguna credencial de servicio incluida.')
