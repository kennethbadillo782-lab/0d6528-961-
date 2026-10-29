"""Validación estática; no equivale a compilar ni ejecutar iOS/Supabase."""
from pathlib import Path
import plistlib
import tomllib
import yaml
from jsonschema import Draft202012Validator
ROOT = Path(__file__).resolve().parent.parent
cfg = tomllib.loads((ROOT / 'backend/supabase/config.toml').read_text(encoding='utf-8'))
assert cfg['auth']['enable_signup'] is False
assert cfg['functions']['catalog-api']['verify_jwt'] is False
for p in (ROOT / 'backend/gpt').glob('*.yaml'):
    doc = yaml.safe_load(p.read_text(encoding='utf-8'))
    ids = set()
    def walk(value):
        if isinstance(value, dict):
            assert not any(v is None for k, v in value.items() if k not in ('default', 'example')), f'{p}: campo nulo accidental'
            if 'type' in value and value['type'] != 'apiKey': Draft202012Validator.check_schema(value)
            for v in value.values(): walk(v)
        elif isinstance(value, list):
            for v in value: walk(v)
    walk(doc)
    for endpoint in doc['paths'].values():
        for method, op in endpoint.items():
            if method not in ('get', 'post', 'patch', 'put', 'delete'): continue
            assert op['operationId'] not in ids
            ids.add(op['operationId'])
    if p.name == 'openapi-guardar.yaml':
        assert ids == {'listCategories', 'createProduct'}
        assert '202' in doc['paths']['/products']['post']['responses']
    if p.name == 'openapi-consultar.yaml':
        assert ids == {'listCategories', 'listCollections', 'listProducts', 'getProduct'}
    print(f'PASS {p.name}: {len(ids)} operaciones')
for p in (ROOT / 'ios').rglob('*.plist'): plistlib.loads(p.read_bytes())
for p in (ROOT / 'ios').rglob('*.xcworkspacedata'):
    import xml.etree.ElementTree as ET
    ET.parse(p)
for name in ('codemagic.yaml', 'ios/project.yml'): yaml.safe_load((ROOT / name).read_text(encoding='utf-8'))
print('PASS TOML, YAML, plist y XML; no es una compilación iOS')
