// Diagnóstico temporal: precio por modelo en los datos de Weidian.
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const ent = (s) => s.replace(/&#34;/g, '"').replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&#39;/g, "'");
for (const id of ["7815143816", "7242121077", "7327048497"]) {
  const t = await (await fetch(`https://weidian.com/item.html?itemID=${id}`, { headers: { "User-Agent": UA } })).text();
  const d = JSON.parse(ent(t.match(/id="__rocker-render-inject__" data-obj="([^"]*)"/)[1]));
  const sp = d.result.default_model.sku_properties;
  console.log(`\n=== ${id} keys=${Object.keys(sp)}`);
  console.log("attr_list[0].attr_values[0]=" + JSON.stringify(sp.attr_list?.[0]?.attr_values?.[0]));
  console.log("attr titles=" + JSON.stringify(sp.attr_list?.map((a) => a.attr_title + ":" + a.attr_values.length)));
  const skus = Object.entries(sp.sku ?? {});
  console.log("sku count=" + skus.length + " first=" + JSON.stringify(skus.slice(0, 2)));
  const info = d.result.default_model.item_info;
  console.log("item price fields: " + JSON.stringify({ itemLowPrice: info.itemLowPrice, origin_price: info.origin_price, special: info.special_price_type }));
}
