// Pruebas de lógica pura. Ejecutar con: deno test supabase/functions/tests
// (también funcionan con: node --experimental-strip-types --test)
import { cleanURL, duplicateKey, isBlockedHost, agentOf, embeddedOriginal, guessCategory } from "../_shared/links.ts";
import { parseProductFields, parseImages, ValidationError } from "../_shared/validation.ts";

function assert(cond: unknown, msg: string) { if (!cond) throw new Error("Falló: " + msg); }
function throws(fn: () => unknown, msg: string) { try { fn(); } catch (e) { if (e instanceof ValidationError) return; throw e; } throw new Error("Debía fallar: " + msg); }

let chain: Promise<void> = Promise.resolve();
const t = (globalThis as { Deno?: { test: (n: string, f: () => unknown) => void } }).Deno?.test
  ?? ((name: string, fn: () => unknown) => {
    // En Node las pruebas se ejecutan una detrás de otra, también las asíncronas.
    chain = chain.then(async () => { await fn(); console.log("ok -", name); }).catch((e) => { console.error("FALLO -", name, e); process.exitCode = 1; });
  });

t("duplicados ignoran parámetros de seguimiento", () => {
  const a = duplicateKey("https://item.taobao.com/item.htm?id=123&spm=abc");
  const b = duplicateKey("item.taobao.com/item.htm?spm=zzz&id=123");
  assert(a === b && a.endsWith("?id=123"), `${a} vs ${b}`);
});
t("enlace de agente usa el original incrustado", () => {
  const u = cleanURL("https://www.hipobuy.com/product?url=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D77")!;
  assert(agentOf(u) === "Hipobuy", "agente");
  assert(embeddedOriginal(u)?.hostname === "weidian.com", "original");
  assert(duplicateKey(u.toString()) === "weidian.com/item.html?id=77", duplicateKey(u.toString()));
});
t("texto compartido con enlace dentro", () => {
  assert(cleanURL("Mira esto 【淘宝】 https://m.tb.cn/h.abc?tk=1 ¡chévere!")?.hostname === "m.tb.cn", "share text");
});
t("bloquea hosts internos", () => {
  for (const h of ["localhost", "127.0.0.1", "10.2.3.4", "192.168.1.1", "169.254.169.254", "[::1]", "fd00::1", "2130706433", "printer.local"]) assert(isBlockedHost(h), h);
  for (const h of ["img.alicdn.com", "8.8.8.8", "si.geilicdn.com"]) assert(!isBlockedHost(h), h);
});
t("categoría sugerida", () => {
  assert(guessCategory("Coach crossbody bag black") === "carteras", "bag");
  assert(guessCategory("Moissanite stud earrings 6mm") === "pantallas", "earrings");
});
t("validación de producto", () => {
  const f = parseProductFields({ name: "  Bolso  ", price_current: "268", currency: "cny", status: "ready", attributes: { tamano: "Mini" } }, false);
  assert(f.name === "Bolso" && f.price_current === 268 && f.currency === "CNY" && f.status === "ready", JSON.stringify(f));
  throws(() => parseProductFields({ price_current: -1, name: "x" }, false), "precio negativo");
  throws(() => parseProductFields({ seller_rating: 9, name: "x" }, false), "valoración");
  throws(() => parseProductFields({ original_url: "javascript:alert(1)" }, false), "protocolo");
  throws(() => parseProductFields({}, false), "vacío");
  const p = parseProductFields({ notes: "hola" }, true);
  assert(Object.keys(p).length === 1, "parcial");
});
t("imágenes", () => {
  const imgs = parseImages(["https://img.alicdn.com/a.jpg", { url: "https://x.com/b.png", kind: "qc" }]);
  assert(imgs.length === 2 && imgs[1].kind === "qc", "imgs");
  throws(() => parseImages([{ url: "https://x.com/a.jpg", kind: "foto" }]), "tipo");
});
import { ipInCidrs } from "../_shared/links.ts";
import { sniffImageType } from "../_shared/images.ts";
t("lista de IPs permitidas", () => {
  assert(ipInCidrs("23.102.140.115", ["23.102.140.112/28"]), "dentro");
  assert(!ipInCidrs("23.102.140.200", ["23.102.140.112/28"]), "fuera");
  assert(!ipInCidrs("", ["0.0.0.0/0"]), "vacía");
});
t("detecta imágenes reales por contenido", () => {
  assert(sniffImageType(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))?.type === "image/jpeg", "jpg");
  assert(sniffImageType(new TextEncoder().encode("<html><script>x")) === null, "html no");
});
t("SSRF: formas trucadas de direcciones internas", () => {
  const blocked = ["[::ffff:7f00:1]", "[::ffff:a9fe:a9fe]", "[::7f00:1]", "[64:ff9b::a9fe:a9fe]", "[2002:a9fe:a9fe::]", "[fec0::1]", "[ff02::1]",
    "[2001:db8::1]", "[2001::1]", "localhost.", "metadata.google.internal.", "db", "kong", "supabase_kong", "kubernetes.default.svc", "router.lan", "0x7f.1"];
  for (const h of blocked) assert(isBlockedHost(h), h);
  for (const h of ["[2a00:1450:4001:80b::200e]", "[::ffff:8.8.8.8]", "[2002:808:808::1]", "img.alicdn.com", "xn--fiqs8s.com"]) assert(!isBlockedHost(h), h);
});
t("texto: quita caracteres invisibles y de dirección", () => {
  const f = parseProductFields({ name: "Polo‮gpj.exe​ \uD800x", notes: "línea 1\nlínea 2" }, false);
  assert(f.name === "Pologpj.exe x", f.name ?? "");
  assert(f.notes === "línea 1\nlínea 2", "conserva saltos de línea");
  throws(() => parseProductFields({ original_url: "https://taobao.com@evil.com/" }, false), "usuario@host");
  throws(() => parseProductFields({ name: { $gt: "" } }, false), "objeto como texto");
});
t("lista opcional de sitios de fotos permitidos", async () => {
  const { assertPublicHost, setImageAllowlistForTests, setResolverForTests } = await import("../_shared/images.ts");
  setResolverForTests(async (_h: string, t: string) => (t === "A" ? ["47.246.1.1"] : []));
  setImageAllowlistForTests(["alicdn.com"]);
  await assertPublicHost(new URL("https://img.alicdn.com/x.jpg"));
  let blocked = false;
  try { await assertPublicHost(new URL("https://evil-alicdn.com/x.jpg")); } catch { blocked = true; }
  assert(blocked, "evil-alicdn.com no es subdominio de alicdn.com");
  setImageAllowlistForTests(undefined); setResolverForTests(undefined);
});
t("lista de IPs mal escrita no abre a todos", () => {
  assert(!ipInCidrs("8.8.8.8", ["1.2.3.4/"]), "1.2.3.4/ no es /0");
  assert(!ipInCidrs("8.8.8.8", ["1.2.3.4/abc"]), "máscara no numérica");
});
t("HEIC: solo imágenes, no vídeos MP4", () => {
  const mk = (brand: string) => { const h = new Uint8Array(16); h.set([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]); h.set([...brand].map((c) => c.charCodeAt(0)), 8); return h; };
  assert(sniffImageType(mk("heic"))?.type === "image/heic", "heic");
  assert(sniffImageType(mk("isom")) === null && sniffImageType(mk("qt  ")) === null && sniffImageType(mk("mp42")) === null, "mp4/mov");
});
t("lista de sitios por defecto según el permiso de la clave", async () => {
  const { allowlistFor, DEFAULT_IMAGE_HOSTS } = await import("../_shared/images.ts");
  assert(allowlistFor(true).length === DEFAULT_IMAGE_HOSTS.length, "con lectura: lista por defecto");
  assert(allowlistFor(false).length === 0, "solo guardar: sin lista");
});
