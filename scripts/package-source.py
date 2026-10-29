"""Empaqueta FUENTES y evidencias; nunca binarios iOS ficticios ni secretos locales."""
from pathlib import Path
import hashlib, json, zipfile
ROOT = Path(__file__).resolve().parent.parent
target = ROOT.parent / 'MiCatalogo-preparado.zip'
excluded = {'.git', '.tools', '.local', '.venv', '__pycache__', 'DerivedData', 'build', 'node_modules', 'xcuserdata'}
def allowed(path):
    rel = path.relative_to(ROOT)
    return (path.is_file() and not any(part in excluded for part in rel.parts)
        and path.suffix not in {'.pyc', '.p12', '.p8', '.mobileprovision', '.xcconfig'}
        and (not path.name.startswith('.env') or path.name == '.env.example')
        and rel.as_posix() != 'reports/source-manifest.json')
files = sorted(p for p in ROOT.rglob('*') if allowed(p))
manifest = [{'file': p.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
manifest_path = ROOT / 'reports/source-manifest.json'
manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for p in [*files, manifest_path]: archive.write(p, 'MiCatalogo/'+p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert not any(set(Path(name).parts) & excluded for name in archive.namelist())
checksum = hashlib.sha256(target.read_bytes()).hexdigest()
target.with_suffix('.zip.sha256').write_text(checksum+'  '+target.name+'\n',encoding='ascii')
print(f'ZIP de fuentes verificado: {len(files)+1} archivos, {target.stat().st_size} bytes.')
