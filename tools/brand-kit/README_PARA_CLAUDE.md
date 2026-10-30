# Biblioteca de marcas de moda para iPhone — 399 marcas

Este ZIP incluye una base de datos real de **399 nombres de marcas** que el usuario quiere explorar en su catálogo personal: lujo, streetwear, ropa, tenis, bolsos, joyería, pantallas, relojes, gafas y outdoor.

**Estado importante:** los 399 registros de marcas están listos, pero **las imágenes no se incluyen todavía**. El script las obtiene de repositorios de logos de acceso público cuando se ejecuta con internet. No afirmar que un icono exista o sea oficial hasta que el script lo descargue y se compruebe visualmente. Algunos nombres ambiguos quedan pendientes a propósito.

## Un solo paso para descargar los SVG

**En Windows:** abrir `DESCARGAR_EN_WINDOWS.bat` con Python 3 instalado, o en una terminal:

```powershell
py -3 descargar_logos.py
```

**En macOS / Linux:**

```bash
python3 descargar_logos.py
```

No se requiere cuenta ni clave de API. Intenta primero theSVG y luego Brands Logo, usando únicamente coincidencias exactas de marca o alias. Al finalizar, organiza:

```
ModaBrandKit/
  marcas.json                 # 399 marcas, categorías, alias y estado de logo
  marcas.csv                  # exportación tabular
  marcas.sqlite              # base de datos SQLite, lista para consultar
  catalogo.html              # vista previa interactiva local
  catalogo_template.html     # plantilla que se actualiza tras descargar
  descargar_logos.py         # descargador masivo de SVG
  logos/
    svg/                     # NOMBRE.svg, uno por marca hallada
    png/                     # NOMBRE.png, cuando esté CairoSVG instalado
  pendientes_revision.csv    # se genera tras la descarga
```

### PNG para SwiftUI

Los SVG son imágenes vectoriales, ideales como fuente principal. Para exportar PNG con transparencia a 512px desde SVG, instalar CairoSVG y volver a ejecutar:

```bash
python -m pip install cairosvg
python descargar_logos.py
```

Si CairoSVG falla en Windows por sus dependencias nativas, Claude puede convertirlos usando un conversor SVG local de su entorno o renderizarlos a PNG dentro de Xcode/SwiftUI. No modificar logos para que parezcan oficiales si no coinciden con la marca. En el diseño oscuro mostrar cada logo sobre un recuadro claro en vez de invertir colores de forma indiscriminada.

### Cómo agregar la biblioteca a la app iOS

1. Importar `marcas.json` como recurso del bundle, decodificar `brands[]` con `Codable`.
2. Mostrar tarjetas con `name`, `category_primary` y la imagen referenciada en `logo_file` (tras descargar). Las etiquetas `categories` sirven para filtros, `aliases` para búsqueda.
3. Copiar `logos/png/*.png` en `Assets.xcassets` o cargar SVG con un renderizador adecuado; `logo_file` usa rutas relativas y no depende de una URL de red.
4. Mantener un fallback tipográfico elegante para logos pendientes.
5. No inventar nombres, versiones de logos o enlaces si no hay recurso verificado.
6. Si se desea actualizar después, ejecutar el descargador e importar solo archivos nuevos. Los logos se cachean.
7. Cuando una imagen no corresponda a la marca, marcar `needs_manual_review` y reemplazarla por la versión correcta desde sus recursos oficiales.

## Recomendaciones de interfaz

- Prioridad en la pantalla Inicio: Coach, Gucci, Louis Vuitton, Dior, Nike, Prada, Chanel, etc. (`featured=true`).
- Las tarjetas de marca muestran el logo **centrado y sin estirar**, sobre fondo blanco o gris muy claro; coincide con el diseño minimalista ya elegido.
- Buscador con búsqueda por nombre y alias (por ejemplo: YSL, LV, CDG, ALD).
- No hacer que los filtros de marca dependan de la disponibilidad de la imagen. Todas las 399 marcas quedan disponibles.

## Fuentes y procedencia

- theSVG: https://thesvg.org/ — https://github.com/glincker/thesvg
- Brands Logo: https://brandslogo.rakibulism.space/docs — https://github.com/rakibulism/brands-logo
- Biblioteca de 55 marcas de moda para revisión manual: https://seekvectors.com/clothing-brand-logos
- Biblioteca de medios oficiales de Kering (solo uso editorial indicado en su sitio): https://www.kering.com/en/press/resources/logo-library/

`logo_source` y `logo_url` se completan con la fuente del SVG descargado. Las marcas y los diseños de logo siguen siendo propiedad de sus titulares. Identificar marcas en una lista de compras personal no implica afiliación ni autorización para fabricar productos o promocionar imitaciones como originales. Para una distribución pública de la app, revisar derechos y directrices de marca.
