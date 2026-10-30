#!/usr/bin/env python3
"""Pasa los SVG descargados por descargar_logos.py a la app iOS.

Para cada marca descargada que aún no tenga logo en la app y esté en aprobados.txt
(revisada a ojo en revision.png: muchas bibliotecas tienen empresas homónimas, por
ejemplo "AP" de Associated Press para Audemars Piguet):
  - convierte el SVG a PNG (sin recolorear) y recorta el margen transparente,
    para que todos los logos ocupen la tarjeta de la misma forma;
  - crea Assets.xcassets/Brands/brand-<id>.imageset;
  - marca "logo": true en ios/FashionCatalog/Resources/brands.json (edición mínima de texto).
También genera revision.png: hoja con cada logo y su nombre para revisarlos a ojo.
Requiere: cairosvg y Pillow.
"""
import io, json, re, sys
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

KIT = Path(__file__).resolve().parent
ROOT = KIT.parent.parent
ASSETS = ROOT / "ios/FashionCatalog/Resources/Assets.xcassets/Brands"
APP_BRANDS = ROOT / "ios/FashionCatalog/Resources/brands.json"


def render(svg: bytes) -> Image.Image | None:
    try:
        png = cairosvg.svg2png(bytestring=svg, output_width=600)
    except Exception as e:
        print("  no se pudo convertir:", e)
        return None
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    box = img.getchannel("A").getbbox()
    if not box:
        return None
    img = img.crop(box)
    # Casi blanco sobre transparente sería invisible en la tarjeta clara.
    px = [p for p in img.getdata() if p[3] > 128]
    if px and sum(p[0] + p[1] + p[2] for p in px) / (3 * len(px)) > 235:
        print("  descartado: logo blanco, no se vería sobre la tarjeta clara")
        return None
    return img


def main() -> None:
    kit = json.loads((KIT / "marcas.json").read_text(encoding="utf-8"))["brands"]
    app = json.loads(APP_BRANDS.read_text(encoding="utf-8"))
    has_logo = {b["id"] for b in app if b["logo"]}
    approved_file = KIT / "aprobados.txt"
    approved = {l.split("#")[0].strip() for l in approved_file.read_text(encoding="utf-8").splitlines()} if approved_file.exists() else set()
    text = APP_BRANDS.read_text(encoding="utf-8")
    added: list[tuple[str, str, Image.Image]] = []
    # Todo lo descargado va a la hoja de revisión; a la app solo lo aprobado.
    candidates: list[tuple[str, str, Image.Image]] = []
    for b in kit:
        bid = b["id"]
        svg = KIT / "logos/svg" / f"{bid}.svg"
        if b.get("logo_status") != "downloaded" or not svg.exists() or bid in has_logo:
            continue
        print(bid, "←", b.get("logo_source"), b.get("logo_url"))
        img = render(svg.read_bytes())
        if img is None:
            continue
        candidates.append((bid, b["name"], img))
        if bid not in approved:
            continue
        folder = ASSETS / f"brand-{bid}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        img.save(folder / f"{bid}.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{bid}.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        }), encoding="utf-8")
        text, n = re.subn(r'(\{"id":"%s",[^{}]*"logo":)false' % re.escape(bid), r"\1true", text)
        if n != 1:
            sys.exit(f"No se pudo marcar {bid} en brands.json")
        added.append((bid, b["name"], img))
    APP_BRANDS.write_text(text, encoding="utf-8")
    json.loads(text)  # sigue siendo JSON válido

    # Hoja de revisión: cada logo en su tarjeta clara, con el nombre debajo.
    cols, cell_w, cell_h = 8, 180, 150
    rows = max(1, (len(candidates) + cols - 1) // cols)
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)
    for i, (bid, name, img) in enumerate(candidates):
        x, y = (i % cols) * cell_w, (i // cols) * cell_h
        draw.rounded_rectangle([x + 10, y + 8, x + cell_w - 10, y + 108], 14, fill=(242, 242, 242))
        thumb = img.copy()
        thumb.thumbnail((cell_w - 44, 76))
        sheet.paste(thumb, (x + (cell_w - thumb.width) // 2, y + 58 - thumb.height // 2), thumb)
        mark = "OK " if bid in approved else ""
        draw.text((x + 12, y + 116), f"{mark}{name} ({bid})"[:28], fill=(255, 255, 255))
    sheet.save(KIT / "revision.png")
    print(f"\nAñadidos a la app: {len(added)} logos. Revisión: tools/brand-kit/revision.png")


if __name__ == "__main__":
    main()
