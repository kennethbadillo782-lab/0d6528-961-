// Descarga segura de fotos de producto y guardado en Supabase Storage.
import { isBlockedHost, isPrivateIPv4, isPrivateIPv6 } from "./links.ts";

const MAX_BYTES = 12 * 1024 * 1024;
const TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 3;
const ALLOWED_TYPES: Record<string, string> = {
  "image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/heic": "heic",
};
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

/** Identifica el formato por sus primeros bytes. */
export function sniffImageType(h: Uint8Array): { type: string; ext: string } | null {
  if (h[0] === 0xff && h[1] === 0xd8 && h[2] === 0xff) return { type: "image/jpeg", ext: "jpg" };
  if (h[0] === 0x89 && h[1] === 0x50 && h[2] === 0x4e && h[3] === 0x47) return { type: "image/png", ext: "png" };
  if (h[0] === 0x47 && h[1] === 0x49 && h[2] === 0x46 && h[3] === 0x38) return { type: "image/gif", ext: "gif" };
  if (h[0] === 0x52 && h[1] === 0x49 && h[2] === 0x46 && h[3] === 0x46 && h[8] === 0x57 && h[9] === 0x45 && h[10] === 0x42 && h[11] === 0x50) return { type: "image/webp", ext: "webp" };
  if (h[4] === 0x66 && h[5] === 0x74 && h[6] === 0x79 && h[7] === 0x70) {
    // Contenedor ISO-BMFF: solo marcas de imagen HEIF/HEIC (no vídeos MP4/MOV).
    const brand = String.fromCharCode(h[8], h[9], h[10], h[11]);
    if (["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"].includes(brand)) return { type: "image/heic", ext: "heic" };
  }
  return null;
}

export interface Downloaded { bytes: Uint8Array; contentType: string; ext: string; finalUrl: string }

export class ImageError extends Error {}
/** Tras conectar, todos los fallos dan el mismo mensaje: así el servidor no sirve para "escanear" lo que hay detrás de un enlace. */
const IMAGE_FAILED = "No se pudo usar esa imagen (usa el enlace directo a una foto pública .jpg, .png o .webp)";

/**
 * Modo máximo (opcional): si existe el secreto IMAGE_HOST_ALLOWLIST (dominios separados por comas,
 * p. ej. "alicdn.com,geilicdn.com,yupoo.com"), solo se descargan fotos de esos dominios y sus
 * subdominios. Cierra también el DNS rebinding salvo que el atacante controle uno de esos dominios.
 */
let allowOverride: string[] | undefined;

/**
 * Sitios de fotos que se usan por defecto cuando la clave puede LEER el catálogo (así una
 * página que manipule a ChatGPT no puede sacar tus datos escondidos en el enlace de una foto).
 * Se cambia con el secreto IMAGE_HOST_ALLOWLIST; "*" la desactiva (no recomendado con lectura).
 */
export const DEFAULT_IMAGE_HOSTS = [
  // Solo CDNs de imágenes (sin páginas, proxies ni redirecciones de terceros). Ajustable con IMAGE_HOST_ALLOWLIST.
  "alicdn.com", "tbcdn.cn", "taobaocdn.com", "geilicdn.com", "photo.yupoo.com",
  "cdn.shopify.com", "static.nike.com", "images.stockx.com", "image.goat.com", "static.zara.net", "image.hm.com",
  "media-amazon.com", "ebayimg.com", "ssensemedia.com", "farfetch-contents.com",
]

/** Lista efectiva para una petición: [] = sin restricción de sitio (siguen todas las demás comprobaciones). */
export function allowlistFor(canRead: boolean): string[] {
  if (allowOverride !== undefined) return allowOverride;
  const raw = ((globalThis as { Deno?: { env?: { get?: (k: string) => string | undefined } } }).Deno?.env?.get?.("IMAGE_HOST_ALLOWLIST") ?? "").trim();
  if (raw === "*") return [];
  if (raw) return imageHostAllowlist();
  return canRead ? DEFAULT_IMAGE_HOSTS : [];
}
export function setImageAllowlistForTests(list: string[] | undefined) { allowOverride = list; }
function imageHostAllowlist(): string[] {
  if (allowOverride !== undefined) return allowOverride;
  const raw = (globalThis as { Deno?: { env?: { get?: (k: string) => string | undefined } } }).Deno?.env?.get?.("IMAGE_HOST_ALLOWLIST") ?? "";
  if (!raw) return [];
  const list = raw.split(",").map((d) => d.trim().toLowerCase().replace(/^\*?\./, "")).filter((d) => /^[a-z0-9.-]+\.[a-z]{2,}$/.test(d));
  // Una lista mal escrita (p. ej. "alicdn" sin .com) NO desactiva la protección: no deja pasar nada.
  if (!list.length) { console.error("IMAGE_HOST_ALLOWLIST no tiene ningún dominio válido; no se descargará ninguna foto"); return ["lista-invalida.invalid"]; }
  return list;
}

type Resolver = (h: string, t: "A" | "AAAA") => Promise<string[]>;
let resolverOverride: Resolver | null | undefined;
/** Solo para pruebas: sustituye la resolución DNS. */
export function setResolverForTests(r: Resolver | null | undefined) { resolverOverride = r; }

/**
 * Comprueba que el host no apunte a la red interna, también tras resolver el DNS.
 * Si no se puede resolver o verificar, NO se descarga (falla cerrado).
 */
export async function assertPublicHost(u: URL, allowlist?: string[]): Promise<void> {
  if (u.protocol !== "https:" && u.protocol !== "http:") throw new ImageError("Protocolo no permitido");
  if (u.username || u.password) throw new ImageError("Enlace con usuario o contraseña no permitido");
  if (u.port && u.port !== "80" && u.port !== "443") throw new ImageError("Puerto no permitido");
  if (isBlockedHost(u.hostname)) throw new ImageError("Host no permitido");
  const allow = allowlist ?? imageHostAllowlist();
  if (allow.length) {
    const h = u.hostname.toLowerCase().replace(/\.+$/, "");
    if (!allow.some((d) => h === d || h.endsWith("." + d))) throw new ImageError("Ese sitio no está en la lista de sitios de fotos permitidos");
  }
  const host = u.hostname.replace(/^\[|\]$/g, "").replace(/\.+$/, "");
  if (/^[\d.]+$/.test(host) || host.includes(":")) return; // IP literal ya comprobada
  const resolve = resolverOverride !== undefined ? resolverOverride
    : (globalThis as { Deno?: { resolveDns?: Resolver } }).Deno?.resolveDns;
  // Mismo mensaje para "no resuelve", "resuelve a interna" o "no se puede verificar": no revela qué existe dentro.
  const unverifiable = "No se pudo verificar el servidor de la imagen";
  if (!resolve) throw new ImageError(unverifiable);
  const results = await Promise.allSettled([resolve(host, "A"), resolve(host, "AAAA")]);
  const ips = results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
  if (!ips.length) throw new ImageError(unverifiable);
  if (ips.some((ip) => (ip.includes(":") ? isPrivateIPv6(ip) : isPrivateIPv4(ip)))) {
    throw new ImageError(unverifiable);
  }
}

/**
 * Fotos de un artículo de Weidian cuando ChatGPT no pudo verlas (la página las carga con JavaScript).
 * Solo se pide la dirección fija https://weidian.com/item.html?itemID=<número>: nunca un host recibido.
 * Devuelve enlaces de su CDN de producto (si.geilicdn.com/weidian…), que luego pasan por downloadImage.
 */
export async function weidianPageImages(originalUrl: string, fetcher: typeof fetch = fetch, max = 9): Promise<string[]> {
  let u: URL;
  try { u = new URL(originalUrl); } catch { return []; }
  const host = u.hostname.toLowerCase();
  if (host !== "weidian.com" && !host.endsWith(".weidian.com")) return [];
  const item = (u.searchParams.get("itemID") ?? u.searchParams.get("itemId") ?? "").trim();
  if (!/^\d{4,20}$/.test(item)) return [];
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetcher(`https://weidian.com/item.html?itemID=${item}`, { redirect: "manual", signal: ctrl.signal, headers: { "User-Agent": UA, "Accept": "text/html" } });
    if (res.status !== 200 || !res.body) return [];
    const reader = res.body.getReader();
    const chunks: Uint8Array[] = []; let size = 0;
    while (size < 3_000_000) {
      const { done, value } = await reader.read();
      if (done || !value) break;
      chunks.push(value); size += value.byteLength;
    }
    await reader.cancel().catch(() => {});
    const all = new Uint8Array(size); let at = 0;
    for (const c of chunks) { all.set(c, at); at += c.byteLength; }
    const html = new TextDecoder().decode(all);
    const seen = new Set<string>(); const out: string[] = [];
    for (const m of html.matchAll(/si\.geilicdn\.com\\?\/(weidian[A-Za-z0-9_-]{8,120}\.(?:jpg|jpeg|png|webp)(?:\.webp)?)/g)) {
      if (seen.has(m[1])) continue;
      seen.add(m[1]);
      out.push(`https://si.geilicdn.com/${m[1]}?w=750&h=750&cp=1`);
      if (out.length >= max) break;
    }
    return out;
  } catch { return []; } finally { clearTimeout(timer); }
}

export async function downloadImage(rawUrl: string, fetcher: typeof fetch = fetch, allowlist?: string[]): Promise<Downloaded> {
  let url: URL;
  try { url = new URL(rawUrl); } catch { throw new ImageError("Enlace no válido"); }
  // Un solo plazo para todo (redirecciones + descarga del cuerpo): evita conexiones lentas eternas.
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    return await fetchImage(url, ctrl.signal, fetcher, allowlist);
  } catch (e) {
    if (e instanceof ImageError) throw e;
    throw new ImageError(IMAGE_FAILED);
  } finally {
    clearTimeout(timer);
  }
}

async function fetchImage(start: URL, signal: AbortSignal, fetcher: typeof fetch, allowlist?: string[]): Promise<Downloaded> {
  let url = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (hop === 0) await assertPublicHost(url, allowlist);
    else await assertPublicHost(url, allowlist).catch(() => { throw new ImageError(IMAGE_FAILED); });
    const res = await fetcher(url, {
      redirect: "manual",
      signal,
      headers: { "User-Agent": UA, "Accept": "image/avif,image/webp,image/*;q=0.9,*/*;q=0.5", "Referer": `${url.protocol}//${url.host}/` },
    });
    if (res.status >= 300 && res.status < 400) {
      const loc = res.headers.get("location");
      await res.body?.cancel();
      if (!loc) throw new ImageError(IMAGE_FAILED);
      try { url = new URL(loc, url); } catch { throw new ImageError(IMAGE_FAILED); }
      continue;
    }
    if (!res.ok) { await res.body?.cancel(); throw new ImageError(IMAGE_FAILED); }
    const type = (res.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
    const ext = ALLOWED_TYPES[type];
    if (!ext) { await res.body?.cancel(); throw new ImageError(IMAGE_FAILED); }
    const declared = Number(res.headers.get("content-length") ?? "0");
    if (declared > MAX_BYTES) { await res.body?.cancel(); throw new ImageError(IMAGE_FAILED); }
    const reader = res.body?.getReader();
    if (!reader) throw new ImageError(IMAGE_FAILED);
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BYTES) { await reader.cancel(); throw new ImageError(IMAGE_FAILED); }
      chunks.push(value);
    }
    if (total < 200) throw new ImageError(IMAGE_FAILED);
    const head = new Uint8Array(16);
    let filled = 0;
    for (const c of chunks) { const take = Math.min(16 - filled, c.byteLength); head.set(c.subarray(0, take), filled); filled += take; if (filled >= 16) break; }
    const real = sniffImageType(head);
    if (!real) throw new ImageError(IMAGE_FAILED);
    const bytes = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) { bytes.set(c, off); off += c.byteLength; }
    return { bytes, contentType: real.type, ext: real.ext, finalUrl: url.toString() };
  }
  throw new ImageError(IMAGE_FAILED);
}
