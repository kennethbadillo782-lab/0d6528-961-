# Matriz de pruebas nativas — ejecución parcial verificada

Verificado en Actions 40960926235: 5 pruebas de red, 3 de copias/SwiftData y 1 UI de cinco pestañas y relanzamiento. Las filas restantes son un procedimiento pendiente; no equivalen a una auditoría UI completa. Usar una instalación nueva y datos ficticios. Registrar para cada fallo: build, dispositivo/runtime, pasos, esperado, observado, captura/log sin secretos, causa, cambio y resultado de repetición.

| Área | Prueba y resultado esperado |
|---|---|
| Arranque | Abre catálogo vacío sin productos presentados como propios. Cerrar y reabrir mantiene los datos. |
| Inicio | Cada acceso rápido, marca, categoría, Más y campana abre su destino. Búsqueda encuentra por nombre, marca y vendedor; enlace pegado propone agregar. |
| Explorar/Ropa | Categoría y subcategoría correctas; desplazamiento y regreso mantienen estado; tarjeta abre su producto. |
| Pantalones | Combinar corto + negro + marca y confirmar intersección. Verificar tallas numéricas, corte y rango. |
| Carteras | Tipo, tamaño, dimensiones, compartimentos y QC se guardan, editan y filtran. |
| Pantallas | 6.5/7/9 mm se conservan; metal y piedra son independientes; galería y fotos puesto correctas. |
| Agregar | Enlace válido, texto compartido, página bloqueada, foto sin enlace, sin precio, duplicado, confirmar duplicado, cancelar y error de guardado. No perder borrador por interrupción. |
| Detalle | Miniaturas, visor, zoom, favorito, prioridad, estado, notas, edición y eliminar con confirmación. Nunca inventar descuento, valoración ni URL de agente. |
| Guardados | Seis órdenes; categorías/estados; swipe favorito/comprado/eliminar; descartados y comprados conservan su historial. |
| Colecciones | Crear/renombrar/ordenar; seleccionar una foto y producto de portada; agregar/quitar; eliminar solo colección conserva productos; opción destructiva requiere confirmación. |
| Filtros | Cancelar descarta borrador, Aplicar filtra, Limpiar restablece; rango dinámico; sin resultados tiene salida útil. |
| Cuenta | USD/CNY sin inventar tasa; error de red y fecha; editar categorías; cargar/quitar ejemplos sin tocar reales. |
| Copias | Exportar, reinstalar/limpiar instalación de prueba e importar; todas las fotos/asociaciones correctas; repetición sin duplicar ids. Archivo malicioso/grande falla sin cambios parciales. |
| URLs | `javascript:`, `shortcuts:`, credenciales en host y direcciones internas no se abren/descargan; redirección a LAN bloqueada. |
| Red | Modo avión, latencia, DNS fallido, timeout, Wi-Fi→móvil, cancelar a mitad y reintentar; errores claros y sin secretos. |
| Persistencia | Crear/editar/borrar, terminar proceso, relanzar y reiniciar simulador; verificar datos y fotos. Destruir sesión Appetize puede resetear datos: probar persistencia propia del proveedor por separado. |
| Nube (tras implementarla) | Login único, refresco, expiración, logout borra sesión; otra sesión no autorizada rechazada. Nunca confundir sesión local con sesión Auth. |
| Sync (tras implementarla) | Offline→online, import inicial sin demos, conflictos, marca de tiempo, borrado suave, álbumes, fotos, API→iPhone y iPhone→DB. Ningún cambio perdido ni producto resucitado. |
| ChatGPT (tras implementarlo) | Pausa, revocación, permisos separados y restaurar historial; prompt injection no altera lo no solicitado. |
| Física | Galería real, Archivos, enlaces a agentes, permisos/red local, rendimiento con volumen, cierre por memoria y firma en iPhone 17 Pro Max. |

En Appetize confirmar primero las capacidades de galería, portapapeles y archivos del plan contratado. Sign in with Apple, biometría, cámara y escenarios de hardware no quedan aprobados por pasar en un simulador. Las pruebas Node y Chromium de esta entrega no marcan ninguna fila nativa como completada.
