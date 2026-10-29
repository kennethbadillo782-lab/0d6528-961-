// Ataque XSS a la vista previa: datos maliciosos en todos los campos + navegación aleatoria.
// Uso: (en web-preview/) python3 -m http.server 8765  y luego  node tests/xss-crawl.js http://127.0.0.1:8765/MiCatalogo.html 250 1
// Requiere playwright. Debe terminar con "XSS ejecutados: 0".
const { chromium } = require('playwright');
const FILE = process.argv[2];
const STEPS = +process.argv[3] || 400;
const T = `"'><img src=x onerror=__x('T')><svg onload=__x('S')>`;
const A = `x" onerror="__x('A')" onclick="__x('A')" onpointerdown="__x('A')" onfocus="__x('A')" autofocus y="`;
const U = `javascript:__x('U')`;

function poison(db) {
  const evil = (o) => { for (const k of Object.keys(o)) { if (typeof o[k] === 'string' && !['cur', 'status', 'k'].includes(k)) o[k] = o[k] + (k === 'id' ? A : T); } };
  db.products.forEach((p, i) => {
    evil(p);
    p.url = U; p.agents = [{ n: 'Hipobuy' + T, u: U }, { n: T, u: 'data:text/html,<script>alert(1)</script>' }];
    p.attrs = Object.assign({}, p.attrs, { [T]: T, tamano: T });
    p.imgs = [{ src: A, k: 'manual' }, { ph: A, k: T }].concat(p.imgs || []);
    if (i % 5 === 0) { p.price = T; p.cur = T; p.rating = T; }
  });
  db.collections.forEach((c) => { c.n += T; c.id += A; c.cover = A; });
  db.cats.forEach((c, i) => { c.n += T; if (i % 2) c.ic = A; c.subs = c.subs.concat([T]); c.cover = A; if (i % 3 === 0) c.k += A; });
  db.products.forEach((p) => { p.cols = (p.cols || []).map((x) => x + A); });
  db.logos = { coach: A, gucci: 'javascript:__x("L")', [T]: A };
  db.extraBrands = [T];
  db.settings.rates = { CNY: { v: T, d: T } };
  return db;
}

async function crawl(page, steps, rnd, visits) {
  for (let i = 0; i < steps; i++) {
    const els = await page.$$('[data-a]:not([data-a="resetall"]):not([data-a="export"]):not([data-a="import"]):not([data-a="mpick"]):not([data-a="logoedit"])');
    const vis = [];
    for (const e of els) if (await e.isVisible().catch(() => false)) vis.push(e);
    if (!vis.length) { await page.keyboard.press('Escape'); continue; }
    const e = vis[Math.floor(rnd() * vis.length)];
    visits.add(await e.getAttribute('data-a').catch(() => ''));
    await e.click({ timeout: 800, force: true }).catch(() => {});
    if (rnd() < 0.15) {
      const inp = await page.$('input[type=search]:visible, input[type=text]:visible, textarea:visible');
      if (inp) await inp.fill(T).catch(() => {});
    }
    await page.waitForTimeout(30);
  }
}

(async () => {
  const browser = await chromium.launch({ ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
  const ctx = await browser.newContext({ viewport: { width: 440, height: 956 } });
  await ctx.addInitScript(() => {
    window.__hits = []; window.__x = (n) => window.__hits.push(n);
    window.open = (u) => { window.__opened = (window.__opened || []).concat([String(u)]); return null; };
  });
  const errors = [];
  const first = await ctx.newPage();
  await first.goto(FILE);
  await first.waitForTimeout(800);
  await first.evaluate(() => { const b = document.querySelector('[data-a="fav"]'); b.click(); b.click(); });
  await first.waitForTimeout(500);
  const clean = await first.evaluate(() => localStorage.getItem('micatalogo.preview.v2') || '');
  await first.close();
  if (!clean) { console.log('no se encontró la base de datos local'); process.exit(1); }
  const db = poison(JSON.parse(clean));
  await ctx.addInitScript((raw) => {
    if (!sessionStorage.getItem('poisoned')) { localStorage.setItem('micatalogo.preview.v2', raw); sessionStorage.setItem('poisoned', '1'); }
  }, JSON.stringify(db));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('dialog', (d) => { errors.push('dialog:' + d.message()); d.dismiss(); });
  await page.goto(FILE);
  await page.waitForTimeout(800);
  console.log('datos maliciosos cargados:', await page.evaluate(() => document.body.innerHTML.includes('__x(')));

  let seed = +process.argv[4] || 12345;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const visits = new Set();
  await crawl(page, STEPS, rnd, visits);
  // Importar una copia de seguridad maliciosa
  const evilBackup = JSON.stringify({ products: db.products.map((p, i) => ({ ...p, id: 'imp' + i + A })), collections: db.collections.map((c, i) => ({ ...c, id: 'ic' + i + A })), categories: [{ k: 'evil' + A, n: T, ic: A, subs: [T], g: T }] });
  const input = await page.$('#importpick');
  if (input) {
    await input.setInputFiles({ name: 'copia.json', mimeType: 'application/json', buffer: Buffer.from(evilBackup) });
    await page.waitForTimeout(500);
    await crawl(page, Math.round(STEPS / 2), rnd, visits);
  }
  for (const sel of ['[data-a="agent"]', '[data-a="openurl"]']) {
    for (const e of await page.$$(sel)) await e.click({ force: true, timeout: 500 }).catch(() => {});
  }
  const hits = await page.evaluate(() => window.__hits);
  const opened = await page.evaluate(() => window.__opened || []);
  console.log('acciones probadas:', visits.size, [...visits].join(','));
  console.log('XSS ejecutados:', hits.length, JSON.stringify([...new Set(hits)]));
  console.log('window.open con esquema peligroso:', JSON.stringify(opened.filter((u) => !/^https?:/i.test(u))));
  console.log('errores JS:', JSON.stringify([...new Set(errors)].slice(0, 10)));
  await browser.close();
  process.exitCode = hits.length || opened.some((u) => !/^https?:/i.test(u)) ? 1 : 0;
})();
