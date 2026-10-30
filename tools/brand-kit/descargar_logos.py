#!/usr/bin/env python3
"""Descarga los logos verificables de las marcas del catálogo.
Fuentes: theSVG (thesvg.org) y Brands Logo (rakibulism/brands-logo).
Solo se acepta coincidencia exacta de nombre/alias, sin logotipos inventados.
No necesita API key ni librerías externas para SVG.
"""
import argparse, csv, json, re, sys, time, unicodedata, urllib.error, urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from xml.etree import ElementTree

BASE=Path(__file__).resolve().parent
SOURCES=[
 ('theSVG', 'https://thesvg.org/api/registry.json'),
 ('Brands Logo', 'https://cdn.jsdelivr.net/gh/rakibulism/brands-logo@master/assets/logos.json'),
]
UA='MiCatalogoModa/1.0 personal brand identification logo downloader (https://github.com/glincker/thesvg)'

def key(v):
    v=unicodedata.normalize('NFKD',str(v)).encode('ascii','ignore').decode('ascii').lower()
    v=v.replace('&',' and ').replace('’','').replace("'",'').replace('™','').replace('®','')
    return re.sub('[^a-z0-9]','',v)

def get(url,timeout=25):
    req=urllib.request.Request(url,headers={'User-Agent':UA,'Accept':'application/json,image/svg+xml,*/*'})
    with urllib.request.urlopen(req,timeout=timeout) as r:
        b=r.read(5_000_000+1)
        if len(b)>5_000_000:raise ValueError('Archivo demasiado grande')
        return b,r.headers.get('Content-Type','')

def get_manifest(url):
    print('Descargando índice:',url,flush=True)
    data,_=get(url,timeout=50)
    return json.loads(data)

def svg_is_safe(raw):
    if len(raw)>3_000_000:return False
    s=raw.decode('utf-8','replace')
    if re.search(r'<script\b|\bon\w+\s*=|<foreignObject\b|<!ENTITY\b',s,re.I):return False
    if re.search(r'(?:href|src)\s*=\s*["\']\s*(?:https?:|javascript:|data:)',s,re.I):return False
    try:root=ElementTree.fromstring(s)
    except Exception:return False
    return root.tag.endswith('svg') and ('viewBox' in root.attrib or 'width' in root.attrib)

def make_indexes(thesvg,brandslogo):
    t={}; b={}
    if isinstance(thesvg,dict):
        icons=thesvg.get('icons',[])
        if isinstance(icons,dict):icons=list(icons.values())
    else: icons=thesvg
    for item in icons:
        if not isinstance(item,dict):continue
        name=item.get('title') or item.get('name')
        slug=item.get('slug')
        if not slug or not name:continue
        for candidate in [name]+list(item.get('aliases') or []):
            if isinstance(candidate,str):t.setdefault(key(candidate),item)
    if isinstance(brandslogo,dict):
        logo_items=brandslogo.get('logos',[])
        raw_base=brandslogo.get('rawBase','https://cdn.jsdelivr.net/gh/rakibulism/brands-logo@master/logos/')
    else:logo_items=brandslogo; raw_base='https://cdn.jsdelivr.net/gh/rakibulism/brands-logo@master/logos/'
    for item in logo_items:
        name=item.get('n') if isinstance(item,dict) else None
        if name:b.setdefault(key(name),name)
    return t,b,raw_base

def lookup(brand,t,b,raw_base):
    if brand['id'] in {'jordan','on','market','express','theory','frame'}:
        # Nombres compartidos por otras empresas: revisar la identidad manualmente.
        return []
    names=[brand['name']]+brand.get('aliases',[])
    # Prefer exact title/alias matches, do NOT do fuzzy substring matches.
    for n in names:
        item=t.get(key(n))
        if item:
            slug=item.get('slug')
            var=item.get('variants') or {}
            variants=['wordmark','default','light','mono']
            found=[]
            if isinstance(var,dict):
                for v in variants:
                    if var.get(v):
                        p=var[v]
                        if isinstance(p,str) and p.startswith('http'):u=p
                        elif isinstance(p,str) and p.startswith('/'):u='https://thesvg.org'+p
                        else:u=f'https://thesvg.org/icons/{slug}/{v}.svg'
                        found.append((u,'theSVG',slug,v))
            if not found:found=[(f'https://thesvg.org/icons/{slug}/default.svg','theSVG',slug,'default')]
            for v in ['default','wordmark']:
                found.append((f'https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/{slug}/{v}.svg','theSVG mirror',slug,v))
            return found
    for n in names:
        slug=b.get(key(n))
        if slug:return [(raw_base+slug+'.svg','Brands Logo',slug,'default')]
    return []

def main():
    a=argparse.ArgumentParser(description='Descargar logos SVG de marcas de moda para catálogo personal')
    a.add_argument('--solo-destacadas',action='store_true',help='Descarga solo las marcas de inicio')
    a.add_argument('--sin-png',action='store_true',help='No crear PNG')
    a.add_argument('--solo-previsualizacion',action='store_true')
    a.add_argument('--trabajadores',type=int,default=4,help='Máximo 1-8 descargas paralelas')
    args=a.parse_args()
    brands_path=BASE/'marcas.json'
    if not brands_path.exists():sys.exit('No se encuentra marcas.json')
    data=json.loads(brands_path.read_text(encoding='utf-8'))
    out=BASE/'logos';svg_dir=out/'svg'; png_dir=out/'png';svg_dir.mkdir(parents=True,exist_ok=True);png_dir.mkdir(parents=True,exist_ok=True)
    if args.solo_previsualizacion:
        generate_html(data);return
    indexes={}
    for source,url in SOURCES:
        try:indexes[source]=get_manifest(url)
        except Exception as e:
            print('ADVERTENCIA: no se pudo leer',source,':',str(e),flush=True)
    if not indexes:
        print('No hubo conexión a las fuentes. Comprueba internet e inténtalo de nuevo.')
        generate_html(data);return
    t,b,raw_base=make_indexes(indexes.get('theSVG',{}),indexes.get('Brands Logo',{}))
    print('Fuentes indexadas:',len(t),'theSVG;',len(b),'Brands Logo',flush=True)
    todo=[br for br in data['brands'] if not args.solo_destacadas or br['featured']]
    def download_one(br):
        id=br['id']
        dest=svg_dir/f'{id}.svg'
        if dest.exists() and svg_is_safe(dest.read_bytes()):
            return id,True,None,br.get('logo_source') or 'caché local',br.get('logo_url'),br.get('logo_variant')
        candidates=lookup(br,t,b,raw_base)
        if not candidates:return id,False,'No se encontró coincidencia EXACTA en las bibliotecas',None,None,None
        for url,source,slug,variant in candidates:
            try:
                content,content_type=get(url,timeout=25)
                if not svg_is_safe(content):continue
                dest.write_bytes(content)
                return id,True,None,source,url,variant
            except Exception:continue
        return id,False,'Coincidencia encontrada, pero no se pudo descargar SVG válido',None,None,None
    results={}
    workers=max(1,min(8,args.trabajadores))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        tasks=[ex.submit(download_one,br) for br in todo]
        for i,f in enumerate(as_completed(tasks),1):
            id,ok,reason,source,url,variant=f.result()
            results[id]=(ok,reason,source,url,variant)
            if i%20==0 or i==len(todo):print(f'Procesadas: {i}/{len(todo)} | descargadas: {sum(v[0] for v in results.values())}',flush=True)
    # PNG optional; do not recolor trademark marks; transparent originals + white tile in UI.
    cairosvg=None
    if not args.sin_png:
        try:import cairosvg
        except ImportError:
            print('Para PNG instala CairoSVG: python -m pip install cairosvg')
    count=0; pending=[]
    for br in data['brands']:
        id=br['id']
        if id not in results:
            if (svg_dir/f'{id}.svg').exists():br['logo_file']=f'logos/svg/{id}.svg';br['logo_status']='downloaded';count+=1
            continue
        ok,reason,source,url,variant=results[id]
        if ok:
            br.update(logo_file=f'logos/svg/{id}.svg',logo_status='downloaded',logo_source=source,logo_url=url,logo_variant=variant,official_verified=False)
            count+=1
            if cairosvg:
                try:
                    cairosvg.svg2png(bytestring=(svg_dir/f'{id}.svg').read_bytes(),write_to=str(png_dir/f'{id}.png'),output_width=512,output_height=512)
                    br['image_dark_file']=f'logos/png/{id}.png'
                except Exception:br['image_dark_file']=None
        else:
            br['logo_status']='needs_manual_review';br['logo_file']=None;br['download_note']=reason;pending.append(br)
    data['downloaded_images']=count
    brands_path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    # Sincronizar formatos adicionales de la base de datos tras cada descarga.
    import sqlite3
    db=BASE/'marcas.sqlite'
    if db.exists():
        with sqlite3.connect(db) as conn:
            for br in data['brands']:
                conn.execute('UPDATE brands SET logo_file=?, logo_status=? WHERE id=?',
                            (br.get('logo_file'), br.get('logo_status'), br['id']))
    with (BASE/'marcas.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.writer(f)
        w.writerow(['id','marca','categoria','categorias','alias','destacado','archivo_logo','estado_logo','fuente_url'])
        for br in data['brands']:
            w.writerow([br['id'],br['name'],br['category_primary'],
                        '; '.join(br['categories']),'; '.join(br['aliases']),
                        br['featured'],br.get('logo_file') or '',br['logo_status'],br.get('logo_url') or ''])
    with (BASE/'pendientes_revision.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.writer(f);w.writerow(['nombre','categoria','motivo','busqueda_recomendada'])
        for b in pending:w.writerow([b['name'],b['category_primary'],b.get('download_note'),f'https://brandfetch.com/search?q={urllib.parse.quote(b["name"])}'])
    generate_html(data)
    print('\nTERMINADO:',count,'SVG descargados de',len(data['brands']),'marcas. Pendientes:',len(pending))
    print('Carpeta:',out.resolve())
    print('Vista previa: ',(BASE/'catalogo.html').resolve())
    print('Los logos son marcas registradas; revisa visualmente cada uno antes de publicar la app.')

def generate_html(data):
    template=(BASE/'catalogo_template.html').read_text(encoding='utf-8')
    safe_json=json.dumps(data,ensure_ascii=False).replace('</','<\\/')
    (BASE/'catalogo.html').write_text(template.replace('/*__DATA__*/',f'const DATA={safe_json};'),encoding='utf-8')

if __name__=='__main__':
    main()
