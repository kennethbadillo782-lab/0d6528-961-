// Validación de lo que envía ChatGPT. Todo lo que no está aquí se ignora.
// No depende de Deno para poder probarse con Node.

export class ValidationError extends Error {
  issues: string[];
  constructor(issues: string[]) {
    super("Datos no válidos: " + issues.join("; "));
    this.issues = issues;
  }
}

export const STATUSES = ["researching", "favorite", "pending", "ready", "purchased", "discarded"] as const;
export const IMAGE_KINDS = ["official", "qc", "buyer", "worn", "manual"] as const;
export const CURRENCIES = ["USD", "CNY", "EUR", "GBP", "JPY", "KRW", "HKD", "MXN", "CAD"] as const;
export const AGENTS = ["Hipobuy", "Sugargoo", "KakoBuy", "CSSBuy", "Mulebuy", "AllChinaBuy", "Superbuy", "CNFans", "Oopbuy", "LitBuy", "ACBuy", "Hoobuy", "Otro"] as const;

type Json = Record<string, unknown>;

export interface ImageInput { url: string; kind: typeof IMAGE_KINDS[number] }
export interface AgentLink { name: string; url: string }

export interface ProductFields {
  name?: string; brand?: string; category_key?: string; subcategory?: string; description?: string;
  price_current?: number | null; price_previous?: number | null; currency?: string; shipping_estimate_usd?: number | null;
  original_url?: string; platform?: string; agent_links?: AgentLink[];
  seller_name?: string; seller_rating?: number | null; seller_rating_count?: string; seller_rating_source?: string;
  color?: string; size?: string; material?: string; attributes?: Record<string, string>;
  declared_quality?: string; verified_quality?: string; included_accessories?: string;
  notes?: string; is_favorite?: boolean; priority?: number; status?: typeof STATUSES[number];
}

const TEXT_LIMITS: Record<string, number> = {
  name: 300, brand: 120, category_key: 40, subcategory: 60, description: 5000, original_url: 2048, platform: 60,
  seller_name: 120, seller_rating_count: 20, seller_rating_source: 120, color: 60, size: 60, material: 120,
  declared_quality: 120, verified_quality: 120, included_accessories: 200, notes: 5000,
};

export function cleanText(v: unknown): string {
  // Solo texto simple: objetos y listas no se convierten en "[object Object]".
  if (v === null || v === undefined) return "";
  if (typeof v !== "string" && typeof v !== "number" && typeof v !== "boolean") return "";
  let s = String(v);
  if (s.length > 20_000) s = s.slice(0, 20_000);
  // Sustitutos sueltos (rompen Postgres), controles, y caracteres invisibles o de
  // dirección (U+202E...) que sirven para disfrazar nombres y enlaces.
  s = s.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, "");
  s = s.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u00AD\u061C\u180E\u200B-\u200F\u2028-\u202E\u2060-\u206F\uFEFF\uFFF9-\uFFFB]/g, "");
  return s.normalize("NFC").trim();
}

function money(v: unknown, field: string, issues: string[], max = 10_000_000): number | null {
  if (v === null) return null;
  const n = typeof v === "number" ? v : Number(String(v).replace(",", "."));
  if (!Number.isFinite(n) || n < 0 || n > max) { issues.push(`${field} debe ser un número positivo`); return null; }
  return Math.round(n * 100) / 100;
}

function httpURL(v: unknown, field: string, issues: string[]): string {
  const s = cleanText(v);
  if (!s) return "";
  try {
    if (s.length > 2048 || /\s/.test(s)) throw new Error();
    const u = new URL(s);
    if (u.protocol !== "https:" && u.protocol !== "http:") throw new Error();
    if (u.username || u.password) throw new Error(); // https://taobao.com@web-falsa.com
    if (!u.hostname.includes(".") && !u.hostname.startsWith("[")) throw new Error();
    const out = u.toString();
    if (out.length > 2048) throw new Error();
    return out;
  } catch {
    issues.push(`${field} no es un enlace http(s) válido`);
    return "";
  }
}

/** `partial` = true para PATCH: solo se validan los campos presentes. */
export function parseProductFields(body: Json, partial: boolean): ProductFields {
  const issues: string[] = [];
  const out: ProductFields = {};
  const has = (k: string) => Object.prototype.hasOwnProperty.call(body, k) && body[k] !== undefined;

  for (const [k, max] of Object.entries(TEXT_LIMITS)) {
    if (!has(k)) continue;
    if (k === "original_url") { out.original_url = httpURL(body[k], k, issues); continue; }
    if (body[k] !== null && typeof body[k] === "object") { issues.push(`${k} debe ser texto`); continue; }
    const v = cleanText(body[k]);
    if (v.length > max) issues.push(`${k} supera ${max} caracteres`);
    (out as Json)[k] = v.slice(0, max);
  }
  if (out.category_key !== undefined) {
    out.category_key = out.category_key.toLowerCase();
    if (out.category_key && !/^[a-z0-9-]{1,40}$/.test(out.category_key)) issues.push("category_key no es válido");
  }
  if (has("price_current")) out.price_current = money(body.price_current, "price_current", issues);
  if (has("price_previous")) out.price_previous = money(body.price_previous, "price_previous", issues);
  if (has("shipping_estimate_usd")) out.shipping_estimate_usd = money(body.shipping_estimate_usd, "shipping_estimate_usd", issues, 100_000);
  if (has("currency")) {
    const c = cleanText(body.currency).toUpperCase();
    if (!(CURRENCIES as readonly string[]).includes(c)) issues.push("currency debe ser uno de " + CURRENCIES.join(", "));
    else out.currency = c;
  }
  if (has("seller_rating")) {
    if (body.seller_rating === null) out.seller_rating = null;
    else {
      const r = Number(body.seller_rating);
      if (!Number.isFinite(r) || r < 0 || r > 5) issues.push("seller_rating debe estar entre 0 y 5");
      else out.seller_rating = Math.round(r * 100) / 100;
    }
  }
  if (has("is_favorite")) {
    if (typeof body.is_favorite !== "boolean") issues.push("is_favorite debe ser true o false");
    else out.is_favorite = body.is_favorite;
  }
  if (has("priority")) {
    const p = Number(body.priority);
    if (!Number.isInteger(p) || p < 0 || p > 3) issues.push("priority debe ser 0, 1, 2 o 3");
    else out.priority = p;
  }
  if (has("status")) {
    const s = cleanText(body.status);
    if (!(STATUSES as readonly string[]).includes(s)) issues.push("status debe ser uno de " + STATUSES.join(", "));
    else out.status = s as ProductFields["status"];
  }
  if (has("attributes")) {
    const a = body.attributes;
    if (!a || typeof a !== "object" || Array.isArray(a)) issues.push("attributes debe ser un objeto");
    else {
      const entries = Object.entries(a as Json).slice(0, 30);
      const attrs = new Map<string, string>();
      for (const [k, v] of entries) {
        const key = cleanText(k).slice(0, 40);
        const val = cleanText(v).slice(0, 120);
        if (key && val && key !== "__proto__" && key !== "constructor" && key !== "prototype") attrs.set(key, val);
      }
      out.attributes = Object.fromEntries(attrs);
    }
  }
  if (has("agent_links")) {
    const list = body.agent_links;
    if (!Array.isArray(list)) issues.push("agent_links debe ser una lista");
    else {
      out.agent_links = list.slice(0, 10).flatMap((x) => {
        if (!x || typeof x !== "object") return [];
        const o = x as Json;
        const url = httpURL(o.url, "agent_links.url", issues);
        const name = cleanText(o.name ?? "Otro").slice(0, 40) || "Otro";
        return url ? [{ name, url }] : [];
      });
    }
  }
  if (!partial && !out.name && !out.original_url) issues.push("Hace falta al menos name u original_url");
  if (issues.length) throw new ValidationError(issues);
  return out;
}

export function parseImages(v: unknown, max = 10): ImageInput[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) throw new ValidationError(["images debe ser una lista"]);
  const issues: string[] = [];
  const out: ImageInput[] = [];
  for (const item of v.slice(0, max)) {
    const o = (typeof item === "string" ? { url: item } : item) as Json;
    const url = httpURL(o?.url, "images.url", issues);
    if (url.length > 600) { issues.push("images.url demasiado largo (usa el enlace directo a la foto)"); continue; }
    const kind = cleanText(o?.kind ?? "official");
    if (!(IMAGE_KINDS as readonly string[]).includes(kind)) { issues.push("images.kind no es válido"); continue; }
    if (url) out.push({ url, kind: kind as ImageInput["kind"] });
  }
  if (issues.length) throw new ValidationError(issues);
  return out;
}

export function parseNameList(v: unknown, field: string, max = 10): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) throw new ValidationError([`${field} debe ser una lista`]);
  return [...new Set(v.slice(0, max).map((x) => cleanText(x).slice(0, 80)).filter(Boolean))];
}
