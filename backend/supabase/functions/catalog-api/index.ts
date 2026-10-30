// =====================================================================
// API de Mi Catálogo para ChatGPT (GPT personalizado con Actions)
//
// Despliegue:  supabase functions deploy catalog-api --no-verify-jwt
// Secretos opcionales:
//   API_IP_SALT       texto aleatorio para anonimizar IPs en el historial
//                     (si falta, se deriva de la clave de servicio: nunca es público)
//   ALLOWED_IP_CIDRS  lista separada por comas; si se define, solo se aceptan esas IPs
//   CLIENT_IP_HEADER  encabezado fiable con la IP real (p. ej. cf-connecting-ip). Si
//                     falta, se usa la ÚLTIMA entrada de x-forwarded-for (la que añade
//                     el proxy de Supabase), nunca la primera, que la inventa el cliente.
//
// Defensas:
//   - Claves en base de datos, guardadas solo como huella SHA-256, con permisos
//     (read / write), caducidad y revocación. Interruptor de pausa desde la app.
//   - Bloqueo por IP tras intentos fallidos y límites de uso por minuto y por día.
//   - Validación estricta de todo lo que entra; nunca se puede borrar.
//   - Los enlaces de un producto ya guardado no se pueden cambiar por la API
//     (evita que una página maliciosa redirija tus enlaces a otra web).
//   - Cada cambio guarda una versión anterior (se puede deshacer desde la app).
//   - Descargas de fotos protegidas contra SSRF y comprobadas por contenido.
//   - Respuestas mínimas: sin rutas internas ni enlaces firmados a tus fotos.
// =====================================================================
// Versión exacta fijada (cadena de suministro): actualízala a propósito, no por accidente.
import { createClient } from "npm:@supabase/supabase-js@2.103.2";
import { agentOf, CHINESE_PLATFORMS, cleanURL, duplicateKey, embeddedOriginal, guessCategory, ipInCidrs, platformOf } from "../_shared/links.ts";
import { cleanText, parseImages, parseNameList, parseProductFields, STATUSES, type ImageInput, type ProductFields, ValidationError } from "../_shared/validation.ts";
import { allowlistFor, downloadImage, ImageError, weidianPageImages } from "../_shared/images.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_SALT = Deno.env.get("API_IP_SALT") || ("derived|" + SERVICE_KEY);
const IP_HEADER = (Deno.env.get("CLIENT_IP_HEADER") ?? "").trim().toLowerCase();
const ALLOWED_CIDRS = (Deno.env.get("ALLOWED_IP_CIDRS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
// Una lista mal escrita (p. ej. "1.2.3.4/") no puede abrir la puerta a todos: si hay un error, se bloquea todo.
const CIDR_RE = /^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}(\/(3[0-2]|[12]?\d))?$|^[0-9a-f:]+$/i;
// Y solo se acepta junto a CLIENT_IP_HEADER: sin una cabecera de IP fiable, filtrar por IP sería falsa seguridad.
const CIDRS_INVALID = ALLOWED_CIDRS.some((c) => !CIDR_RE.test(c) || /\/0$/.test(c)) || (ALLOWED_CIDRS.length > 0 && !IP_HEADER);
const BUCKET = "product-images";
const MAX_AUTH_FAILURES = 25;         // por IP cada 30 minutos
const MAX_GLOBAL_AUTH_FAILURES = 300; // entre todas las IPs cada 30 minutos (por si alguien rota IPs)
const MAX_BODY_BYTES = 100_000;

// El encabezado x-catalog-source permite que el historial de versiones sepa que el cambio vino de ChatGPT.
const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { headers: { "x-catalog-source": "chatgpt" } },
});

const HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
};
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KEY_RE = /^mc_[0-9a-f]{48}$/;
const SUMMARY = "id,name,brand,category_key,subcategory,price_current,price_previous,currency,platform,is_favorite,status,original_url,created_at";
const LINK_FIELDS = ["original_url", "agent_links", "platform"] as const;

interface Ctx {
  owner: string;
  keyId: string;
  scopes: Set<string>;
  ipHash: string;
  limits: { create: number; write: number; image: number; imageMb: number; storageMb: number };
}

class HttpError extends Error {
  status: number;
  extra: Record<string, unknown>;
  constructor(status: number, message: string, extra: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: HEADERS });

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function clientIP(req: Request): string {
  if (IP_HEADER) {
    // Si se configuró una cabecera fiable y no llega, no se adivina: IP vacía (y con ALLOWED_IP_CIDRS, rechazo).
    const v = (req.headers.get(IP_HEADER) ?? "").split(",").map((x) => x.trim()).filter(Boolean);
    return v.length ? v[v.length - 1].slice(0, 64) : "";
  }
  // El cliente puede escribir lo que quiera al principio de x-forwarded-for;
  // solo la última entrada la añade un proxy de confianza.
  const fwd = (req.headers.get("x-forwarded-for") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
  return (fwd[fwd.length - 1] ?? req.headers.get("x-real-ip") ?? "").trim().slice(0, 64);
}

/** Lee el cuerpo sin pasar del límite (no se carga en memoria un cuerpo gigante). */
async function readBody(req: Request): Promise<string | null> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) { await reader.cancel(); return null; }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { all.set(c, off); off += c.byteLength; }
  return new TextDecoder("utf-8", { fatal: true }).decode(all);
}

async function audit(ctx: Ctx, operation: string, productId: string | null, detail: Record<string, unknown> = {}) {
  const { error } = await db.from("api_audit_log").insert({ owner_id: ctx.owner, key_id: ctx.keyId, ip_hash: ctx.ipHash, operation, product_id: productId, detail });
  if (error) console.error("audit log failed", operation, error.message);
}

async function consume(ctx: Ctx, bucket: string, windowSeconds: number, max: number, amount = 1) {
  const { data, error } = await db.rpc("api_consume", { p_owner: ctx.owner, p_bucket: bucket, p_window_seconds: windowSeconds, p_max: max, p_amount: amount });
  if (error) throw error;
  if (data !== true) {
    await audit(ctx, "limit_reached", null, { bucket });
    throw new HttpError(429, windowSeconds >= 86400 ? "Se alcanzó el límite diario de la API." : "Demasiadas peticiones; espera un minuto.");
  }
}

// Permisos: read = consultar; create = guardar productos nuevos; write = create + modificar lo existente.
// "meta" = categorías (lo necesita cualquier clave para guardar bien). Las colecciones son datos tuyos: read.
type Need = "read" | "create" | "write" | "meta";
const can = (ctx: Ctx, s: Need) =>
  s === "meta" ? ctx.scopes.size > 0 :
  s === "create" ? ctx.scopes.has("create") || ctx.scopes.has("write") :
  ctx.scopes.has(s);
const MSG: Record<Need, string> = {
  read: "Esta clave no permite consultar el catálogo.",
  create: "Esta clave no permite guardar productos.",
  write: "Esta clave no permite modificar productos ya guardados.",
  meta: "Clave sin permisos.",
};
function need(ctx: Ctx, scope: Need) {
  if (!can(ctx, scope)) throw new HttpError(403, MSG[scope], { permission: scope });
}

/** Qué permiso exige cada ruta. Lo que no está aquí no existe. */
function requiredScope(method: string, seg: string[]): Need | null {
  if (method === "GET" && seg.length === 1 && seg[0] === "categories") return "meta";
  if (method === "GET" && seg.length === 1 && seg[0] === "collections") return "read";
  if (method === "POST" && seg.length === 1 && seg[0] === "collections") return "create";
  if (seg[0] !== "products") return null;
  if (method === "GET" && seg.length <= 2) return "read";
  if (method === "POST" && seg.length === 1) return "create";
  if (method === "POST" && seg.length === 2 && seg[1] === "check-duplicate") return "read";
  if (method === "PATCH" && seg.length === 2) return "write";
  if (seg.length === 3 && ((method === "POST" && (seg[2] === "images" || seg[2] === "collections")) || ((method === "PUT" || method === "POST") && seg[2] === "favorite"))) return "write";
  return null;
}

// ---------------------------------------------------------------------
// Ayudantes de datos (siempre filtrados por el dueño de la clave)
// ---------------------------------------------------------------------

async function categoryKeys(ctx: Ctx): Promise<Set<string>> {
  const { data, error } = await db.from("categories").select("key").eq("owner_id", ctx.owner).is("deleted_at", null);
  if (error) throw error;
  return new Set((data ?? []).map((r) => r.key as string));
}

async function deriveFields(ctx: Ctx, f: ProductFields, isCreate: boolean): Promise<Record<string, unknown>> {
  const row: Record<string, unknown> = { ...f };
  if (f.original_url) {
    const u = cleanURL(f.original_url);
    if (u) {
      const agent = agentOf(u);
      if (agent) {
        const links = [...(f.agent_links ?? [])];
        if (!links.some((l) => l.url === u.toString())) links.unshift({ name: agent, url: u.toString() });
        row.agent_links = links;
        const inner = embeddedOriginal(u);
        row.original_url = inner ? inner.toString() : "";
        if (!f.platform) row.platform = inner ? platformOf(inner) : agent;
      } else if (!f.platform) {
        row.platform = platformOf(u);
      }
    }
  }
  const firstAgent = ((row.agent_links as { url: string }[] | undefined) ?? [])[0]?.url ?? "";
  row.normalized_url = duplicateKey(String(row.original_url ?? "") || firstAgent);
  if (isCreate) {
    if (!row.currency) {
      const chinese = CHINESE_PLATFORMS.has(String(row.platform ?? "")) || firstAgent !== "";
      row.currency = chinese ? "CNY" : "USD";
    }
    const keys = await categoryKeys(ctx);
    const wanted = (row.category_key as string | undefined) || guessCategory(String(row.name ?? "")) || "otros";
    row.category_key = keys.has(wanted) ? wanted : "otros";
  } else {
    delete row.normalized_url;
    if (row.category_key !== undefined) {
      const keys = await categoryKeys(ctx);
      if (!keys.has(String(row.category_key))) throw new ValidationError([`La categoría "${row.category_key}" no existe. Usa listCategories.`]);
    }
  }
  return row;
}

async function findDuplicate(ctx: Ctx, key: string) {
  if (!key) return null;
  const { data, error } = await db.from("products").select("id,name,created_at").eq("owner_id", ctx.owner).eq("normalized_url", key).is("deleted_at", null).limit(1);
  if (error) throw error;
  return data?.[0] ?? null;
}

async function getOwnedProduct(ctx: Ctx, id: string) {
  if (!UUID_RE.test(id)) throw new HttpError(400, "id no válido");
  const { data, error } = await db.from("products").select("*").eq("owner_id", ctx.owner).eq("id", id).is("deleted_at", null).maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(404, "Producto no encontrado");
  return data;
}

/**
 * Para claves sin lectura: si el producto ya existía, se descargan igualmente las fotos (y se descartan),
 * consumiendo el mismo cupo. Así un servidor de fotos del atacante ve lo mismo exista o no el producto.
 */
async function probeImages(ctx: Ctx, images: ImageInput[]) {
  if (!images.length) return;
  const { data: ok } = await db.rpc("api_consume", { p_owner: ctx.owner, p_bucket: "image-day", p_window_seconds: 86400, p_max: ctx.limits.image, p_amount: images.length });
  if (ok !== true) return;
  const { data: usedBytes } = await db.rpc("api_storage_used", { p_owner: ctx.owner });
  if (Number(usedBytes ?? 0) >= ctx.limits.storageMb * 1024 * 1024) return; // igual que saveImages con el espacio lleno
  const deadline = Date.now() + 45_000;
  for (const img of images) {
    if (Date.now() > deadline) break;
    try { await downloadImage(img.url, fetch, allowlistFor(false)); } catch { /* se descarta igual que un fallo normal */ }
  }
}

/** Fotos fallidas en el historial del propietario: solo el sitio y el motivo, nunca la dirección completa. */
async function noteImageErrors(ctx: Ctx, productId: string, errors: { url: string; error: string }[]) {
  if (!errors.length) return;
  const items = errors.slice(0, 10).map((e) => {
    let host = "";
    try { host = new URL(e.url).hostname; } catch { /* enlace no válido */ }
    return { host, error: e.error.slice(0, 120) };
  });
  await audit(ctx, "image_errors", productId, { count: errors.length, items });
}

async function saveImages(ctx: Ctx, productId: string, images: ImageInput[]) {
  if (!images.length) return { saved: 0, errors: [] as { url: string; error: string }[] };
  await consume(ctx, "image-day", 86400, ctx.limits.image, images.length);
  const { data: existing } = await db.from("product_images").select("position, source_url").eq("product_id", productId).eq("owner_id", ctx.owner).is("deleted_at", null);
  if ((existing?.length ?? 0) + images.length > 30) throw new ValidationError(["Un producto puede tener como máximo 30 fotos"]);
  let position = Math.max(-1, ...(existing ?? []).map((r) => r.position as number)) + 1;
  const already = new Set((existing ?? []).map((r) => r.source_url as string));
  const saved: string[] = [];
  const errors: { url: string; error: string }[] = [];
  // Presupuesto: espacio total de la cuenta (incluye archivos huérfanos) y MB por día.
  const { data: usedBytes, error: usedErr } = await db.rpc("api_storage_used", { p_owner: ctx.owner });
  if (usedErr) throw usedErr;
  let used = Number(usedBytes ?? 0);
  const maxBytes = ctx.limits.storageMb * 1024 * 1024;
  const deadline = Date.now() + 45_000; // una petición nunca se alarga más de ~45 s por fotos
  for (const img of images) {
    if (already.has(img.url)) { errors.push({ url: img.url, error: "Ya estaba guardada" }); continue; }
    if (Date.now() > deadline) { errors.push({ url: img.url.slice(0, 300), error: "Tiempo agotado; vuelve a intentarlo con menos fotos" }); continue; }
    if (used >= maxBytes) { errors.push({ url: img.url.slice(0, 300), error: "Se alcanzó el espacio máximo para fotos (ajústalo en la app)" }); continue; }
    try {
      const file = await downloadImage(img.url, fetch, allowlistFor(can(ctx, "read")));
      if (used + file.bytes.byteLength > maxBytes) throw new ImageError("Se alcanzó el espacio máximo para fotos (ajústalo en la app)");
      const mb = Math.max(1, Math.ceil(file.bytes.byteLength / (1024 * 1024)));
      const { data: okMb, error: mbErr } = await db.rpc("api_consume", { p_owner: ctx.owner, p_bucket: "image-mb-day", p_window_seconds: 86400, p_max: ctx.limits.imageMb, p_amount: mb });
      if (mbErr) throw mbErr;
      if (okMb !== true) throw new ImageError("Se alcanzó el límite diario de MB de fotos");
      const path = `${ctx.owner}/${productId}/${crypto.randomUUID()}.${file.ext}`;
      const up = await db.storage.from(BUCKET).upload(path, file.bytes, { contentType: file.contentType, upsert: false });
      if (up.error) throw up.error;
      const { error } = await db.from("product_images").insert({
        product_id: productId, owner_id: ctx.owner, storage_path: path, source_url: img.url,
        kind: img.kind, position: position++, content_type: file.contentType, bytes: file.bytes.byteLength,
      });
      if (error) { await db.storage.from(BUCKET).remove([path]); throw error; }
      saved.push(img.url);
      already.add(img.url);
      used += file.bytes.byteLength;
    } catch (e) {
      // Solo se devuelven mensajes propios: nunca detalles internos de la base de datos o del storage.
      if (!(e instanceof ImageError)) console.error("image save failed", e instanceof Error ? e.message : e);
      errors.push({ url: img.url.slice(0, 300), error: e instanceof ImageError ? e.message : "No se pudo guardar la imagen" });
    }
  }
  return { saved: saved.length, errors };
}

async function resolveCollections(ctx: Ctx, refs: string[], createMissing: boolean) {
  if (!refs.length) return [] as { id: string; name: string }[];
  const { data, error } = await db.from("collections").select("id,name").eq("owner_id", ctx.owner).is("deleted_at", null);
  if (error) throw error;
  const all = (data ?? []) as { id: string; name: string }[];
  const out: { id: string; name: string }[] = [];
  for (const ref of refs) {
    const found = all.find((c) => c.id === ref || c.name.toLowerCase() === ref.toLowerCase());
    if (found) { if (!out.includes(found)) out.push(found); continue; }
    if (!createMissing || UUID_RE.test(ref)) continue;
    if (all.length >= 200) throw new ValidationError(["Ya hay 200 colecciones; no se crean más desde la API"]);
    const { data: created, error: e2 } = await db.from("collections").insert({ owner_id: ctx.owner, name: ref, sort_order: all.length }).select("id,name").single();
    if (e2) throw e2;
    all.push(created as { id: string; name: string });
    out.push(created as { id: string; name: string });
  }
  return out;
}

async function addToCollections(ctx: Ctx, productId: string, cols: { id: string }[]) {
  if (!cols.length) return;
  const rows = cols.map((c) => ({ owner_id: ctx.owner, product_id: productId, collection_id: c.id, deleted_at: null }));
  const { error } = await db.from("product_collections").upsert(rows, { onConflict: "product_id,collection_id" });
  if (error) throw error;
}

async function productDetail(ctx: Ctx, id: string) {
  const p = await getOwnedProduct(ctx, id);
  const [{ data: imgs }, { data: mem }] = await Promise.all([
    db.from("product_images").select("id,source_url,kind,position").eq("product_id", id).eq("owner_id", ctx.owner).is("deleted_at", null).order("position"),
    db.from("product_collections").select("collection_id, collections(name)").eq("product_id", id).eq("owner_id", ctx.owner).is("deleted_at", null),
  ]);
  const images = (imgs ?? []).map((i) => ({ id: i.id, kind: i.kind, source_url: i.source_url }));
  const collections = (mem ?? []).map((m) => ({ id: m.collection_id, name: (m as { collections?: { name?: string } }).collections?.name ?? "" }));
  const { owner_id: _o, deleted_at: _d, normalized_url: _n, search_text: _s, ...rest } = p;
  return { ...rest, images, collections };
}

// ---------------------------------------------------------------------
// Rutas
// ---------------------------------------------------------------------

type Body = Record<string, unknown>;

async function route(ctx: Ctx, method: string, path: string, params: URLSearchParams, body: Body): Promise<Response> {
  const seg = path.split("/").filter(Boolean);
  const isWrite = method !== "GET";
  const scope = requiredScope(method, seg);
  if (!scope) throw new HttpError(404, "Ruta no encontrada");
  need(ctx, scope);
  await consume(ctx, "minute", 60, 120);
  if (isWrite) {
    await consume(ctx, "write-minute", 60, 40);
    await consume(ctx, "write-day", 86400, ctx.limits.write);
  }

  if (method === "GET" && path === "/categories") {
    const { data, error } = await db.from("categories").select("key,name,group_key,subcategories").eq("owner_id", ctx.owner).is("deleted_at", null).order("sort_order");
    if (error) throw error;
    return json(200, { categories: data });
  }

  if (path === "/collections") {
    if (method === "GET") {
      const [{ data: cols, error }, { data: mem }] = await Promise.all([
        db.from("collections").select("id,name,sort_order").eq("owner_id", ctx.owner).is("deleted_at", null).order("sort_order"),
        db.from("product_collections").select("collection_id").eq("owner_id", ctx.owner).is("deleted_at", null),
      ]);
      if (error) throw error;
      const counts = new Map<string, number>();
      for (const m of mem ?? []) counts.set(m.collection_id as string, (counts.get(m.collection_id as string) ?? 0) + 1);
      return json(200, { collections: (cols ?? []).map((c) => ({ id: c.id, name: c.name, product_count: counts.get(c.id as string) ?? 0 })) });
    }
    if (method === "POST") {
      const name = parseNameList([body.name], "name", 1)[0];
      if (!name) throw new ValidationError(["name es obligatorio"]);
      if (!can(ctx, "read")) {
        // Sin lectura no se dice si ya existía (ni cómo se escribe): misma respuesta siempre.
        try { await resolveCollections(ctx, [name], true); } catch (e) { if (!(e instanceof ValidationError)) throw e; }
        await audit(ctx, "create_collection", null, { name });
        return json(202, { ok: true, message: "Recibido." });
      }
      const [col] = await resolveCollections(ctx, [name], true);
      await audit(ctx, "create_collection", null, { name });
      return json(201, { collection: col });
    }
  }

  if (seg[0] !== "products") throw new HttpError(404, "Ruta no encontrada");

  if (seg.length === 1 && method === "GET") {
    const limit = Math.min(Math.max(Number(params.get("limit") ?? 20) || 20, 1), 50);
    const offset = Math.min(Math.max(Number(params.get("offset") ?? 0) || 0, 0), 10_000);
    let q = db.from("products").select(SUMMARY, { count: "exact" }).eq("owner_id", ctx.owner).is("deleted_at", null);
    const text = cleanText(params.get("q") ?? "").replace(/[^\p{L}\p{N}\s.\-']/gu, " ").trim().slice(0, 80);
    for (const word of text.toLowerCase().split(/\s+/).filter(Boolean).slice(0, 6)) q = q.ilike("search_text", `%${word.replace(/[%_]/g, "")}%`);
    const category = params.get("category"); if (category && /^[a-z0-9-]{1,40}$/.test(category)) q = q.eq("category_key", category);
    // Comodines (% _ *) y escapes se quitan: un filtro nunca puede convertirse en "todo".
    const brand = cleanText(params.get("brand") ?? "").replace(/[%_*\\]/g, "").slice(0, 120); if (brand) q = q.ilike("brand", brand);
    const status = params.get("status");
    if (status) {
      if (!(STATUSES as readonly string[]).includes(status)) throw new ValidationError(["status debe ser uno de " + STATUSES.join(", ")]);
      q = q.eq("status", status);
    }
    const fav = params.get("favorite"); if (fav === "true" || fav === "false") q = q.eq("is_favorite", fav === "true");
    const { data, error, count } = await q.order("created_at", { ascending: false }).range(offset, offset + limit - 1);
    if (error) throw error;
    return json(200, { total: count ?? 0, offset, limit, products: data });
  }

  if (seg.length === 1 && method === "POST") {
    await consume(ctx, "create-day", 86400, ctx.limits.create);
    const fields = parseProductFields(body, false);
    const given = parseImages(body.images);
    const collectionRefs = parseNameList(body.collections, "collections");
    const row = await deriveFields(ctx, fields, true);
    // Sin fotos de ChatGPT: se intentan sacar de la página del artículo (Weidian las carga con JavaScript).
    const images: ImageInput[] = given.length ? given
      : (await weidianPageImages(String(row.original_url ?? ""))).map((url) => ({ url, kind: "official" as const }));
    // Clave sin lectura ("solo guardar"): la respuesta es SIEMPRE la misma, exista o no el producto,
    // tenga o no fotos válidas. Así no se puede usar para averiguar qué hay en tu catálogo.
    const quiet = !can(ctx, "read");
    const RECEIVED = { ok: true, message: "Recibido. Lo verás en tu app; si ya lo tenías, no se duplica." };
    if (body.allow_duplicate !== true) {
      const dup = await findDuplicate(ctx, String(row.normalized_url ?? ""));
      // Sin permiso de lectura no se revela qué producto era (evita usar el 409 para espiar el catálogo).
      if (dup && quiet) {
        await audit(ctx, "duplicate_ignored", dup.id as string, {});
        // Si el que ya tenías se guardó sin fotos, se completan; la respuesta es la misma en ambos casos.
        const { count } = await db.from("product_images").select("id", { count: "exact", head: true })
          .eq("product_id", dup.id as string).eq("owner_id", ctx.owner).is("deleted_at", null);
        if (images.length && (count ?? 0) === 0) {
          const r = await saveImages(ctx, dup.id as string, images).catch(() => ({ saved: 0, errors: [] as { url: string; error: string }[] }));
          if (r.saved) await audit(ctx, "add_images", dup.id as string, { saved: r.saved });
          await noteImageErrors(ctx, dup.id as string, r.errors);
        } else await probeImages(ctx, images);
        return json(202, RECEIVED);
      }
      if (dup) throw new HttpError(409, "Este producto ya está guardado", { existing: dup });
    }
    const { data: created, error } = await db.from("products").insert({ ...row, owner_id: ctx.owner, source: "chatgpt" }).select(SUMMARY).single();
    if (error) throw error;
    // Carrera: dos peticiones simultáneas con el mismo enlace pasan la comprobación a la vez.
    // Tras insertar, gana siempre el más antiguo; el resto se retira y responde 409.
    if (body.allow_duplicate !== true && row.normalized_url) {
      const { data: same, error: e2 } = await db.from("products").select("id,name,created_at").eq("owner_id", ctx.owner)
        .eq("normalized_url", String(row.normalized_url)).is("deleted_at", null)
        .order("created_at", { ascending: true }).order("id", { ascending: true }).limit(1);
      if (e2) throw e2;
      const first = same?.[0];
      if (first && first.id !== created.id) {
        await db.from("products").update({ deleted_at: new Date().toISOString() }).eq("owner_id", ctx.owner).eq("id", created.id);
        await audit(ctx, "duplicate_race_removed", created.id as string, {});
        if (quiet) { await probeImages(ctx, images); return json(202, RECEIVED); }
        throw new HttpError(409, "Este producto ya está guardado", { existing: first });
      }
    }
    // El historial se escribe nada más crear: aunque lo siguiente falle, queda constancia.
    await audit(ctx, "create_product", created.id as string, { name: created.name });
    let cols: { id: string; name: string }[] = [];
    try {
      cols = await resolveCollections(ctx, collectionRefs.length ? collectionRefs : ["Lista principal"], true);
    } catch (e) {
      if (!(quiet && e instanceof ValidationError)) throw e; // sin lectura, el límite de colecciones no se delata
      cols = await resolveCollections(ctx, ["Lista principal"], false);
    }
    await addToCollections(ctx, created.id as string, cols);
    let imageResult: { saved: number; errors: { url: string; error: string }[] };
    try {
      imageResult = await saveImages(ctx, created.id as string, images);
    } catch (e) {
      const msg = e instanceof HttpError || e instanceof ValidationError ? (e instanceof ValidationError ? e.issues[0] : e.message) : "No se pudieron guardar las fotos";
      if (!(e instanceof HttpError) && !(e instanceof ValidationError)) console.error("create images failed", e instanceof Error ? e.message : e);
      imageResult = { saved: 0, errors: images.map((i) => ({ url: i.url.slice(0, 300), error: msg })) };
    }
    if (imageResult.saved) await audit(ctx, "add_images", created.id as string, { saved: imageResult.saved });
    await noteImageErrors(ctx, created.id as string, imageResult.errors);
    if (quiet) return json(202, RECEIVED);
    return json(201, { product: created, images_saved: imageResult.saved, image_errors: imageResult.errors, collections: cols.map((c) => c.name) });
  }

  if (seg.length === 2 && seg[1] === "check-duplicate" && method === "POST") {
    const key = duplicateKey(String(body.url ?? "").slice(0, 2048));
    if (!key) throw new ValidationError(["url no es válido"]);
    const dup = await findDuplicate(ctx, key);
    return json(200, { duplicate: !!dup, existing: dup });
  }

  const id = seg[1] ?? "";

  if (seg.length === 2 && method === "GET") return json(200, { product: await productDetail(ctx, id) });

  if (seg.length === 2 && method === "PATCH") {
    await getOwnedProduct(ctx, id);
    await consume(ctx, "product-day:" + id, 86400, 20); // máx. 20 cambios por producto y día desde la API
    const blocked = LINK_FIELDS.filter((k) => Object.prototype.hasOwnProperty.call(body, k));
    if (blocked.length) {
      throw new HttpError(403, "Por seguridad, los enlaces de un producto guardado solo se cambian desde la app.", { fields: blocked });
    }
    const fields = parseProductFields(body, true);
    if (!Object.keys(fields).length) throw new ValidationError(["No hay campos para actualizar"]);
    const row = await deriveFields(ctx, fields, false);
    const { data, error } = await db.from("products").update(row).eq("owner_id", ctx.owner).eq("id", id).select(SUMMARY).single();
    if (error) throw error;
    await audit(ctx, "update_product", id, { fields: Object.keys(fields) });
    return json(200, can(ctx, "read") ? { product: data } : { ok: true, id });
  }

  if (seg.length === 3 && seg[2] === "images" && method === "POST") {
    await getOwnedProduct(ctx, id);
    await consume(ctx, "product-day:" + id, 86400, 20); // máx. 20 cambios por producto y día desde la API
    const images = parseImages(body.images);
    if (!images.length) throw new ValidationError(["images está vacío"]);
    const result = await saveImages(ctx, id, images);
    await audit(ctx, "add_images", id, { saved: result.saved });
    return json(200, { images_saved: result.saved, image_errors: result.errors });
  }

  if (seg.length === 3 && seg[2] === "favorite" && (method === "PUT" || method === "POST")) {
    await getOwnedProduct(ctx, id);
    await consume(ctx, "product-day:" + id, 86400, 20); // máx. 20 cambios por producto y día desde la API
    if (typeof body.is_favorite !== "boolean") throw new ValidationError(["is_favorite debe ser true o false"]);
    const { data, error } = await db.from("products").update({ is_favorite: body.is_favorite }).eq("owner_id", ctx.owner).eq("id", id).select(SUMMARY).single();
    if (error) throw error;
    await audit(ctx, "set_favorite", id, { is_favorite: body.is_favorite });
    return json(200, can(ctx, "read") ? { product: data } : { ok: true, id });
  }

  if (seg.length === 3 && seg[2] === "collections" && method === "POST") {
    await getOwnedProduct(ctx, id);
    await consume(ctx, "product-day:" + id, 86400, 20); // máx. 20 cambios por producto y día desde la API
    const add = await resolveCollections(ctx, parseNameList(body.add, "add"), true);
    const remove = await resolveCollections(ctx, parseNameList(body.remove, "remove"), false);
    await addToCollections(ctx, id, add);
    if (remove.length) {
      const { error } = await db.from("product_collections").update({ deleted_at: new Date().toISOString() })
        .eq("owner_id", ctx.owner).eq("product_id", id).in("collection_id", remove.map((c) => c.id));
      if (error) throw error;
    }
    await audit(ctx, "update_collections", id, { add: add.map((c) => c.name), remove: remove.map((c) => c.name) });
    return json(200, { added: add.map((c) => c.name), removed: remove.map((c) => c.name) });
  }

  throw new HttpError(404, "Ruta no encontrada");
}

// ---------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.url.length > 4096) return json(414, { error: "Dirección demasiado larga" });
  const path = url.pathname.replace(/^\/(functions\/v1\/)?catalog-api/, "").replace(/\/+$/, "") || "/";
  if (path === "/health" && req.method === "GET") return json(200, { ok: true });
  if (!["GET", "POST", "PATCH", "PUT"].includes(req.method)) return json(405, { error: "Método no permitido" });
  if (!SERVICE_KEY) return json(500, { error: "El servidor no está configurado." });

  const ip = clientIP(req);
  if (CIDRS_INVALID) { console.error("ALLOWED_IP_CIDRS no es válido; se rechaza todo hasta corregirlo"); return json(503, { error: "El servidor no está configurado correctamente." }); }
  if (ALLOWED_CIDRS.length && !ipInCidrs(ip, ALLOWED_CIDRS)) return json(403, { error: "Origen no permitido" });
  const ipHash = (await sha256Hex(IP_SALT + "|" + ip)).slice(0, 24);

  try {
    // 1) Clave: solo se acepta el formato exacto y se busca por su huella.
    //    El bloqueo por IP solo afecta a peticiones con clave inválida: ChatGPT comparte IPs
    //    con otros usuarios, así que un atacante no puede dejar fuera a tu GPT.
    const provided = (req.headers.get("x-api-key") ?? req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "").trim();
    let auth: { key_id: string; owner_id: string; scopes: string[]; enabled: boolean; daily_create_limit: number; daily_write_limit: number; daily_image_limit: number; daily_image_mb: number; max_storage_mb: number } | undefined;
    if (KEY_RE.test(provided)) {
      const { data, error } = await db.rpc("api_authenticate", { p_key_hash: await sha256Hex(provided) });
      if (error) throw error;
      auth = (data ?? [])[0];
    }
    if (!auth) {
      const [{ data: fails }, { data: globalFails }] = await Promise.all([
        db.rpc("api_auth_failures_recent", { p_ip_hash: ipHash }),
        db.rpc("api_auth_failures_recent", { p_ip_hash: "global" }),
      ]);
      await new Promise((r) => setTimeout(r, 300 + Math.random() * 400)); // frena la fuerza bruta
      if ((fails ?? 0) >= MAX_AUTH_FAILURES || (globalFails ?? 0) >= MAX_GLOBAL_AUTH_FAILURES) {
        return json(429, { error: "Demasiados intentos. Prueba más tarde." });
      }
      await Promise.all([
        db.rpc("api_note_auth_failure", { p_ip_hash: ipHash }),
        db.rpc("api_note_auth_failure", { p_ip_hash: "global" }),
      ]);
      return json(401, { error: "Clave de API no válida" });
    }
    if (!auth.enabled) return json(403, { error: "El acceso de ChatGPT está pausado desde la app." });

    const ctx: Ctx = {
      owner: auth.owner_id, keyId: auth.key_id, scopes: new Set(auth.scopes), ipHash,
      limits: { create: auth.daily_create_limit, write: auth.daily_write_limit, image: auth.daily_image_limit, imageMb: auth.daily_image_mb ?? 300, storageMb: auth.max_storage_mb ?? 2048 },
    };

    // 3) Cuerpo: tipo, tamaño y forma.
    let body: Body = {};
    if (req.method !== "GET") {
      const type = req.headers.get("content-type") ?? "";
      if (!type.toLowerCase().includes("application/json")) return json(415, { error: "Usa Content-Type: application/json" });
      let text: string | null;
      try { text = await readBody(req); } catch { return json(400, { error: "El cuerpo no es texto UTF-8 válido" }); }
      if (text === null) return json(413, { error: "Petición demasiado grande" });
      if (text) {
        try {
          const parsed = JSON.parse(text);
          if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json(400, { error: "El cuerpo debe ser un objeto JSON" });
          body = parsed as Body;
        } catch {
          return json(400, { error: "JSON no válido" });
        }
      }
    }

    return await route(ctx, req.method, path, url.searchParams, body);
  } catch (e) {
    if (e instanceof ValidationError) return json(400, { error: "Datos no válidos", issues: e.issues.slice(0, 20) });
    if (e instanceof HttpError) return json(e.status, { error: e.message, ...e.extra });
    console.error("catalog-api error", e instanceof Error ? e.message : e);
    return json(500, { error: "Error interno" });
  }
});
