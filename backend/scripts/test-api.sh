#!/usr/bin/env bash
# Prueba rápida de la API desplegada.
# Uso: API_URL=https://xxxx.supabase.co/functions/v1/catalog-api API_KEY=mc_... ./scripts/test-api.sh
set -euo pipefail
: "${API_URL:?Falta API_URL}"; : "${API_KEY:?Falta API_KEY}"
h=(-H "X-API-Key: $API_KEY" -H "Content-Type: application/json")
echo "1) Salud";            curl -sf "$API_URL/health"; echo
echo "2) Sin clave (401)";  curl -s -o /dev/null -w "%{http_code}\n" "$API_URL/categories"
echo "3) Categorías";       curl -sf "${h[@]}" "$API_URL/categories" | head -c 300; echo
echo "4) Crear producto"
RES=$(curl -s "${h[@]}" -X POST "$API_URL/products" -d '{
  "name":"Prueba API — Crossbody negra","brand":"Prueba","category_key":"carteras","subcategory":"Crossbody",
  "price_current":268,"currency":"CNY","original_url":"https://item.taobao.com/item.htm?id=999000111",
  "collections":["Lista principal"],"notes":"Creado por test-api.sh"}')
echo "$RES" | head -c 400; echo
ID=$(echo "$RES" | sed -n 's/.*"id":"\([0-9a-f-]\{36\}\)".*/\1/p' | head -1)
echo "5) Duplicado (409)"; curl -s -o /dev/null -w "%{http_code}\n" "${h[@]}" -X POST "$API_URL/products" -d '{"name":"x","original_url":"https://item.taobao.com/item.htm?spm=1&id=999000111"}'
if [ -n "$ID" ]; then
  echo "6) Favorito";  curl -sf "${h[@]}" -X PUT "$API_URL/products/$ID/favorite" -d '{"is_favorite":true}' | head -c 200; echo
  echo "6b) Cambiar enlace por la API (403)"; curl -s -o /dev/null -w "%{http_code}\n" "${h[@]}" -X PATCH "$API_URL/products/$ID" -d '{"original_url":"https://example.com"}'
  echo "7) Detalle";   curl -sf "${h[@]}" "$API_URL/products/$ID" | head -c 300; echo
fi
echo "8) Host interno bloqueado"; curl -s "${h[@]}" -X POST "$API_URL/products" -d '{"name":"ssrf","images":["http://169.254.169.254/latest/meta-data"],"allow_duplicate":true}' | head -c 300; echo
if [ -n "$ID" ]; then
  echo "9) SSRF con IPv6 mapeada, nombre interno y punto final (las 3 deben fallar)"
  curl -s "${h[@]}" -X POST "$API_URL/products/$ID/images" -d '{"images":["http://[::ffff:169.254.169.254]/x.png","http://db/x.png","http://localhost./x.png"]}' | head -c 400; echo
  echo "10) Foto real (debe guardarse 1; si dice 'No se pudo verificar el servidor', Deno.resolveDns no está disponible)"
  curl -s "${h[@]}" -X POST "$API_URL/products/$ID/images" -d '{"images":["https://cdn.shopify.com/static/shopify-favicon.png"]}' | head -c 300; echo
fi
echo "11) Clave en la URL no sirve (401)"; curl -s -o /dev/null -w "%{http_code}\n" "$API_URL/categories?api_key=$API_KEY"
echo "12) Borrar no existe (405)"; curl -s -o /dev/null -w "%{http_code}\n" "${h[@]}" -X DELETE "$API_URL/products"
echo "13) Formulario web (415)"; curl -s -o /dev/null -w "%{http_code}\n" -H "X-API-Key: $API_KEY" -H "Content-Type: application/x-www-form-urlencoded" -X POST "$API_URL/products" -d 'name=x'
echo "Listo. Borra los productos de prueba (soft delete) desde la app o SQL."
