# Mi Catálogo de Moda — iPhone (SwiftUI + SwiftData)

Catálogo personal de ropa, carteras, joyería y accesorios. Sin pagos ni tienda: solo guardar, organizar y filtrar.

## Cómo abrirlo y probarlo

Necesitas una **Mac con Xcode 26** (o Xcode 16 o superior).

1. Descomprime la carpeta y abre `MiCatalogo.xcodeproj`.
2. Selecciona el target **MiCatalogo** › pestaña *Signing & Capabilities* › en **Team** elige tu Apple ID.
   Si Xcode se queja del identificador, cambia `com.micatalogo.moda` por algo único (por ejemplo `com.tunombre.micatalogo`).
3. Elige el simulador **iPhone 17 Pro Max** y pulsa ▶︎.
4. Para tu iPhone real: conéctalo por cable, actívale el *Modo desarrollador* (Ajustes › Privacidad y seguridad) y selecciónalo como destino.
   - Con un Apple ID gratuito la app caduca a los 7 días y hay que volver a instalarla desde Xcode.
   - Con la cuenta de desarrollador de Apple (99 USD/año) dura un año y puedes usar TestFlight.

Si el proyecto no abre, instala XcodeGen (`brew install xcodegen`) y ejecuta `xcodegen` en esta carpeta: genera el proyecto desde `project.yml`.

Para ver la app con contenido sin cargar nada tuyo: **Cuenta › Cargar productos de ejemplo** (llevan la etiqueta “Ejemplo” y se quitan con un toque).

## Qué incluye esta versión

| Pantalla | Funciona |
|---|---|
| Inicio | Búsqueda en lo guardado, detecta enlaces pegados, accesos rápidos, marcas (de tus productos), categorías con portada automática, “Más”. Campana con productos listos para comprar. |
| Ropa / Accesorios | Chips Camisas, Pantalones, Hoodies, Chaquetas… y subcategorías. |
| Pantalones | Tarjetas de estilo (Largos, Cortos, Cargo, Jeans…), chips rápidos y filtros de largo, corte, cintura y tallas numéricas. |
| Carteras | Tipos, tamaño, compartimentos, dimensiones (ancho/alto/profundidad), fotos QC. |
| Pantallas | Estilos, tamaño en mm (admite 6.5, 7, 9…), color, y piedra separada del metal. |
| Detalle | Galería con miniaturas y zoom a pantalla completa, tipos de foto (oficial, QC, comprador, puesto, manual), descuento solo si es real, calidad del vendedor marcada como “declarada”, vendedor, agentes (solo enlaces reales), estado, prioridad y notas. |
| Agregar producto | Pegar enlace (lee Open Graph y JSON-LD y descarga fotos), subir fotos de la galería, buscar en lo guardado, colecciones, detección de duplicados. Todo editable a mano. |
| Guardados | Lista compacta, filtros por categoría y estado, 6 órdenes, deslizar para favorito/comprado/eliminar. |
| Colecciones | Crear, renombrar, portada (automática, de galería o de un producto), reordenar, eliminar con o sin productos. Favoritos. |
| Filtros | Panel por categoría con Cancelar/Aplicar/Limpiar, marcas, tallas, colores, atributos, vendedor, agente, estado y rango de precio dinámico. |
| Cuenta | Moneda USD, tasas CNY→USD (en línea o a mano, con fecha), ocultar descartados, categorías editables, exportar/importar JSON, estado de sincronización. |

Los datos viven en el iPhone (SwiftData) y funcionan sin conexión. Las fotos se guardan localmente para no depender de los enlaces de las tiendas.

## Lo que todavía no está (fases siguientes)

- Sincronización en la nube y la API para que ChatGPT agregue productos (el formato de exportación ya es la base de esa API).
- Búsqueda en tiendas externas y seguimiento automático de precios.
- Muchas páginas de Taobao/Weidian bloquean la lectura automática; en esos casos la app avisa y permite completar los datos a mano.

## Estructura

```
FashionCatalog/
├── App/            Arranque, pestañas, rutas y apariencia
├── Models/         Product, ProductImage, ProductCollection, CatalogCategory, filtros por categoría
├── Services/       Importación de enlaces, imágenes, monedas, copia de seguridad, datos de ejemplo
├── Components/     Tarjetas, chips, búsqueda, botones, deslizador de rango
├── Views/          Home, Explore, Categories, ProductDetail, AddProduct, Saved, Collections, Filters, Account
└── Resources/      Assets (icono y color)
```

Para añadir una categoría con filtros propios: créala en **Cuenta › Categorías** y, si quieres atributos especiales, añade un `case` en `CategorySchema.forCategory` (`Models/ProductAttributes.swift`).
