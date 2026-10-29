// Utilidades de enlaces: normalización, detección de duplicados, plataforma/agente
// y protección contra SSRF (no permitir que el servidor visite direcciones internas).
// Este archivo no depende de Deno para poder probarse con Node.

export const KNOWN_AGENTS: Array<[string, string]> = [
  ["Hipobuy", "hipobuy"], ["Sugargoo", "sugargoo"], ["KakoBuy", "kakobuy"], ["CSSBuy", "cssbuy"],
  ["Mulebuy", "mulebuy"], ["AllChinaBuy", "allchinabuy"], ["Superbuy", "superbuy"], ["CNFans", "cnfans"],
  ["Oopbuy", "oopbuy"], ["LitBuy", "litbuy"], ["ACBuy", "acbuy"], ["Hoobuy", "hoobuy"],
];

const PLATFORMS: Array<[string, string]> = [
  ["taobao.com", "Taobao"], ["tmall.com", "Tmall"], ["weidian.com", "Weidian"], ["1688.com", "1688"],
  ["yupoo.com", "Yupoo"], ["goofish.com", "Goofish"], ["aliexpress", "AliExpress"],
  ["instagram.com", "Instagram"], ["tiktok.com", "TikTok"],
];

export const CHINESE_PLATFORMS = new Set(["Taobao", "Tmall", "Weidian", "1688", "Yupoo", "Goofish"]);

export function cleanURL(raw: string): URL | null {
  let s = String(raw ?? "").trim();
  if (!s) return null;
  const m = s.match(/https?:\/\/[^\s"'<>]+/i);
  if (m) s = m[0];
  if (!/^https?:\/\//i.test(s)) s = "https://" + s;
  try {
    const u = new URL(s);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (!u.hostname.includes(".") && !u.hostname.includes(":")) return null;
    if (u.username || u.password) return null;
    return u;
  } catch {
    return null;
  }
}

export function agentOf(u: URL): string | null {
  const h = u.hostname.toLowerCase();
  const found = KNOWN_AGENTS.find(([, host]) => h.includes(host));
  return found ? found[0] : null;
}

/** Algunos agentes incluyen el enlace de la tienda en un parámetro. Solo se usa si existe. */
export function embeddedOriginal(u: URL): URL | null {
  for (const key of ["url", "link", "productUrl", "producturl", "goodsUrl", "itemUrl"]) {
    const v = u.searchParams.get(key);
    if (v) {
      const inner = cleanURL(v);
      if (inner && inner.hostname !== u.hostname) return inner;
    }
  }
  return null;
}

export function platformOf(u: URL): string {
  const h = u.hostname.toLowerCase();
  const p = PLATFORMS.find(([host]) => h.includes(host));
  if (p) return p[1];
  return agentOf(u) ?? stripHostPrefixes(h);
}

function stripHostPrefixes(host: string): string {
  return host.toLowerCase().replace(/^(www|m|h5|mobile)\./, "");
}

/** Clave estable para detectar el mismo producto aunque cambien parámetros de seguimiento. */
export function duplicateKey(raw: string): string {
  const u0 = cleanURL(raw);
  if (!u0) return "";
  const u = embeddedOriginal(u0) ?? u0;
  let key = stripHostPrefixes(u.hostname) + u.pathname.replace(/\/+$/, "");
  const idKeys = new Set(["id", "itemid", "item_id", "offerid", "productid", "goodsid"]);
  for (const [name, value] of u.searchParams) {
    if (idKeys.has(name.toLowerCase()) && value) { key += "?id=" + value; break; }
  }
  return key.toLowerCase().slice(0, 2048);
}

// ---------- SSRF ----------

function ipv4ToInt(ip: string): number | null {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  let n = 0;
  for (const p of parts) {
    if (!/^\d{1,3}$/.test(p)) return null;
    const v = Number(p);
    if (v > 255) return null;
    n = n * 256 + v;
  }
  return n;
}

const PRIVATE_V4: Array<[string, number]> = [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16],
  ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.88.99.0", 24], ["192.168.0.0", 16],
  ["198.18.0.0", 15], ["198.51.100.0", 24], ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
];

export function isPrivateIPv4(ip: string): boolean {
  const n = ipv4ToInt(ip);
  if (n === null) return true; // lo que no se entiende se bloquea
  return PRIVATE_V4.some(([base, bits]) => {
    const b = ipv4ToInt(base)!;
    const size = 2 ** (32 - bits);
    return n >= b && n < b + size;
  });
}

/** Convierte una IPv6 (cualquier notación, con o sin IPv4 al final) en 8 grupos de 16 bits. */
export function parseIPv6(ip: string): number[] | null {
  let v = ip.toLowerCase().replace(/^\[|\]$/g, "");
  const zone = v.indexOf("%");
  if (zone >= 0) v = v.slice(0, zone);
  const tail = v.match(/(\d+\.\d+\.\d+\.\d+)$/);
  if (tail) {
    const n = ipv4ToInt(tail[1]);
    if (n === null) return null;
    v = v.slice(0, -tail[1].length) + ((n >>> 16) & 0xffff).toString(16) + ":" + (n & 0xffff).toString(16);
  }
  const halves = v.split("::");
  if (halves.length > 2) return null;
  const part = (x: string) => (x ? x.split(":") : []);
  const head = part(halves[0]);
  const rest = halves.length === 2 ? part(halves[1]) : [];
  const missing = 8 - head.length - rest.length;
  if (halves.length === 1 ? missing !== 0 : missing < 1) return null;
  const groups = [...head, ...Array(halves.length === 2 ? missing : 0).fill("0"), ...rest];
  const out: number[] = [];
  for (const g of groups) {
    if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
    out.push(parseInt(g, 16));
  }
  return out.length === 8 ? out : null;
}

function v4From(g: number[], i: number): string {
  return [g[i] >> 8, g[i] & 255, g[i + 1] >> 8, g[i + 1] & 255].join(".");
}

/** Solo se permite unicast global (2000::/3) sin redes especiales; las que llevan una IPv4 dentro se juzgan por esa IPv4. */
export function isPrivateIPv6(ip: string): boolean {
  const g = parseIPv6(ip);
  if (!g) return true;
  const zeros5 = g.slice(0, 5).every((x) => x === 0);
  if (zeros5 && g[5] === 0xffff) return isPrivateIPv4(v4From(g, 6));           // ::ffff:a.b.c.d (mapeada)
  if (zeros5 && g[5] === 0) return true;                                      // ::, ::1, ::a.b.c.d (obsoleta)
  if (g[0] === 0x64 && g[1] === 0xff9b) return true;                          // NAT64 64:ff9b::/96 y /48
  if (g[0] === 0x2002) return isPrivateIPv4(v4From(g, 1));                    // 6to4
  if (g[0] === 0x2001 && g[1] < 0x200) return true;                           // Teredo, ORCHID, benchmarking...
  if (g[0] === 0x2001 && g[1] === 0x0db8) return true;                        // documentación
  if ((g[0] & 0xe000) !== 0x2000) return true;                                // fuera de 2000::/3 (fc00, fe80, ff00...)
  return false;
}

const BLOCKED_SUFFIXES = [".localhost", ".local", ".internal", ".home.arpa", ".lan", ".intranet", ".corp", ".localdomain", ".svc", ".cluster.local", ".consul", ".arpa"];

/** Comprueba el nombre de host antes de descargar. La resolución DNS se valida aparte. */
export function isBlockedHost(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.+$/, "");
  if (!h) return true;
  if (h.includes(":")) return isPrivateIPv6(h);
  if (/^[\d.]+$/.test(h)) return isPrivateIPv4(h);
  if (/^0x/i.test(h) || /^[\d]+$/.test(h)) return true;                          // formas numéricas raras
  if (!h.includes(".")) return true;                                           // "db", "kong", "localhost"...
  if (h === "localhost" || BLOCKED_SUFFIXES.some((s) => h.endsWith(s))) return true;
  if (!/^[a-z0-9.-]+$/.test(h)) return true;                                   // solo nombres ASCII ya normalizados
  return false;
}

export function guessCategory(text: string): string | null {
  const t = text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const rules: Array<[string, string[]]> = [
    ["pantallas", ["earring", "stud", "arete", "pantalla", "耳"]],
    ["carteras", ["bag", "wallet", "backpack", "tote", "crossbody", "messenger", "cartera", "bolso", "包"]],
    ["zapatos", ["shoe", "sneaker", "boot", "zapato", "tenis", "鞋"]],
    ["gorras", ["cap", "hat", "gorra", "帽"]],
    ["relojes", ["watch", "reloj", "表"]],
    ["gafas", ["sunglass", "glasses", "gafas", "lentes"]],
    ["joyeria", ["necklace", "chain", "bracelet", "ring", "cadena", "collar", "pulsera"]],
    ["abrigos", ["hoodie", "jacket", "sweater", "sudadera", "chaqueta"]],
    ["pantalones", ["jeans", "pants", "shorts", "cargo", "pantalon", "裤"]],
    ["camisas", ["shirt", "tee", "polo", "camisa", "camiseta"]],
  ];
  for (const [k, words] of rules) if (words.some((w) => t.includes(w))) return k;
  return null;
}

/** true si la IP está en alguna de las redes indicadas (IPv4 en formato CIDR; IPv6 por coincidencia exacta). */
export function ipInCidrs(ip: string, cidrs: string[]): boolean {
  const n = ipv4ToInt(ip);
  for (const c of cidrs) {
    const [base, bitsRaw] = c.split("/");
    if (n !== null) {
      const b = ipv4ToInt(base);
      if (bitsRaw !== undefined && !/^\d{1,2}$/.test(bitsRaw)) continue; // "1.2.3.4/" no es /0
      const bits = bitsRaw === undefined ? 32 : Number(bitsRaw);
      if (b === null || !Number.isInteger(bits) || bits < 0 || bits > 32) continue;
      const size = 2 ** (32 - bits);
      const start = Math.floor(b / size) * size;
      if (n >= start && n < start + size) return true;
    } else if (ip && base.toLowerCase() === ip.toLowerCase()) {
      return true;
    }
  }
  return false;
}
