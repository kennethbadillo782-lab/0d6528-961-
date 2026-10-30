// Diagnóstico temporal: qué devuelve cada tienda a una petición sin JavaScript desde un servidor.
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const urls = [
  "https://weidian.com/item.html?itemID=7815143816",
  "https://weidian.com/item.html?itemID=7242121077",
  "https://shop1809267573.v.weidian.com/item.html?itemID=7327048497",
  'https://thor.weidian.com/detail/getItemSkuInfo/1.0?param={"itemId":"7815143816"}',
  'https://thor.weidian.com/detail/getDetailDesc/1.0?param={"vItemId":"7815143816"}',
  "https://item.taobao.com/item.htm?id=711566484587",
  "https://detail.1688.com/offer/735474104361.html",
  "https://www.hipobuy.com/product/weidian/7815143816",
  "https://www.kakobuy.com/item/details?url=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D7815143816",
  "https://www.cssbuy.com/item-micro-7815143816.html",
  "https://www.sugargoo.com/#/home/productDetail?productLink=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D7815143816",
];
for (const u of urls) {
  try {
    const r = await fetch(encodeURI(decodeURI(u)), { headers: { "User-Agent": UA, "Accept": "text/html,application/json,*/*" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
    const t = await r.text();
    const imgs = [...new Set(t.match(/(?:si\.geilicdn\.com|img\.alicdn\.com|cbu01\.alicdn\.com|gw\.alicdn\.com|photo\.yupoo\.com)[\\/]+[^"'\s)<>]{6,160}/g) ?? [])];
    console.log(`\n=== ${u}\nstatus=${r.status} final=${r.url} bytes=${t.length} images=${imgs.length} title=${(t.match(/<title[^>]*>([^<]{0,80})/)?.[1] ?? "").trim()}`);
    imgs.slice(0, 25).forEach((i) => console.log("  " + i.slice(0, 140)));
    if (u.includes("thor.")) console.log("  body: " + t.slice(0, 1500));
    if (u.includes("item.html") && u.includes("7815143816")) {
      // Contexto de dónde aparecen las fotos (galería del artículo vs recomendados).
      for (const key of ["itemMainPic", "imgs", "headImg", "picList", "recommend", "__rocker", "itemPics", "imgList"]) {
        const at = t.indexOf(key); if (at >= 0) console.log(`  [${key}] …${t.slice(Math.max(0, at - 80), at + 300).replace(/\s+/g, " ")}…`);
      }
    }
  } catch (e) { console.log(`\n=== ${u}\nERROR ${e}`); }
}
