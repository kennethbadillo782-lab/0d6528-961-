// Diagnóstico temporal: estructura de los datos de artículo de Weidian (galería y variantes con foto).
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const ent = (s) => s.replace(/&#34;/g, '"').replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
function walk(o, path, out) {
  if (Array.isArray(o)) { o.forEach((v, i) => walk(v, `${path}[${i}]`, out)); return; }
  if (o && typeof o === "object") { for (const [k, v] of Object.entries(o)) walk(v, path ? `${path}.${k}` : k, out); return; }
  if (typeof o === "string" && /geilicdn\.com/.test(o)) out.push(`${path.replace(/\[\d+\]/g, "[]")}`);
}
for (const id of ["7815143816", "7242121077", "7327048497"]) {
  const r = await fetch(`https://weidian.com/item.html?itemID=${id}`, { headers: { "User-Agent": UA } });
  const t = await r.text();
  const m = t.match(/id="__rocker-render-inject__" data-obj="([^"]*)"/);
  console.log(`\n=== ${id} inject=${!!m}`);
  if (!m) continue;
  const data = JSON.parse(ent(m[1]));
  const paths = []; walk(data, "", paths);
  const counts = {}; for (const p of paths) counts[p] = (counts[p] ?? 0) + 1;
  for (const [p, n] of Object.entries(counts)) console.log(`  ${n}× ${p}`);
  const info = data?.result?.default_model?.item_info ?? {};
  console.log("  item_info keys: " + Object.keys(info).join(","));
  console.log("  title: " + (info.item_name ?? info.itemName ?? info.title ?? "").slice(0, 120));
  for (const k of ["imgs", "item_head", "item_head_thumb", "headImgs", "itemImgs"]) if (info[k]) console.log(`  ${k}: ${JSON.stringify(info[k]).slice(0, 600)}`);
  const sku = data?.result?.default_model?.sku_properties ?? data?.result?.default_model?.sku_info;
  console.log("  sku: " + JSON.stringify(sku ?? {}).slice(0, 900));
}
