// =====================================================================
// Servidor MCP de Mi Catálogo para ChatGPT (plugin privado, "solo guardar")
//
// Despliegue:  supabase functions deploy catalog-mcp --no-verify-jwt
// Secretos obligatorios (solo en Supabase, nunca en Git ni en la app):
//   MCP_SIGNING_SECRET    texto aleatorio largo; firma códigos y tokens OAuth.
//                         Cambiarlo revoca al instante todas las conexiones.
//   MCP_CATALOG_API_KEY   clave mc_ de catalog-api con permiso SOLO "create".
//   MCP_OWNER_ID          UID del único usuario de Auth autorizado.
//
// Transporte: MCP Streamable HTTP sin estado (respuestas JSON) en POST /mcp.
// Autorización: OAuth 2.1 con PKCE S256 propio. El usuario aprueba tocando,
// en el mismo navegador, el enlace de acceso que Supabase Auth envía a su correo.
// Solo dos herramientas: listCategories (lectura de categorías) y
// createProduct (alta). No hay lectura del catálogo, edición ni borrado:
// todo pasa por catalog-api con una clave sin permiso de lectura.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2.103.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SECRET = Deno.env.get("MCP_SIGNING_SECRET") ?? "";
const API_KEY = Deno.env.get("MCP_CATALOG_API_KEY") ?? "";
const OWNER = (Deno.env.get("MCP_OWNER_ID") ?? "").toLowerCase();
const PUBLIC_BASE = (SUPABASE_URL.replace("http://", "https://")) + "/functions/v1/catalog-mcp";
const ISSUER = PUBLIC_BASE;
const RESOURCE = PUBLIC_BASE + "/mcp";
const SCOPE = "catalog.create";
const CATALOG_API = SUPABASE_URL + "/functions/v1/catalog-api";
const MAX_BODY = 100_000;
const PROTOCOLS = ["2025-11-25", "2025-06-18", "2025-03-26"];
// Solo ChatGPT puede completar la autorización: cualquier otro destino se rechaza.
const REDIRECT_RE = /^https:\/\/chatgpt\.com\/(connector_platform_oauth_redirect|connector\/oauth\/[A-Za-z0-9_-]{1,128})$/;
const CIMD_RE = /^https:\/\/chatgpt\.com\/oauth\/([A-Za-z0-9_-]{1,128}\/)?client\.json$/;

const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

const BASE_HEADERS = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};
function json(status: number, body: unknown, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, "content-type": "application/json; charset=utf-8", ...extra } });
}
// Supabase convierte text/html en text/plain en *.supabase.co: las respuestas al navegador son texto.
function text(status: number, body: string) {
  return new Response(body + "\n", { status, headers: { ...BASE_HEADERS, "content-type": "text/plain; charset=utf-8" } });
}

// ---------- firma HMAC (tokens sin estado) ----------
const enc = new TextEncoder();
let hmacKey: CryptoKey | undefined;
async function key() {
  hmacKey ??= await crypto.subtle.importKey("raw", enc.encode(SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  return hmacKey;
}
const b64u = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64u = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));
async function sign(payload: Record<string, unknown>) {
  const body = b64u(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await key(), enc.encode(body)));
  return body + "." + b64u(sig);
}
async function verify(token: string, type: string): Promise<Record<string, unknown> | null> {
  if (token.length > 4096) return null;
  const [body, sig, extra] = token.split(".");
  if (!body || !sig || extra !== undefined) return null;
  try {
    if (!await crypto.subtle.verify("HMAC", await key(), unb64u(sig), enc.encode(body))) return null;
    const p = JSON.parse(new TextDecoder().decode(unb64u(body)));
    if (p.t !== type || typeof p.exp !== "number" || p.exp < Date.now() / 1000) return null;
    return p;
  } catch { return null; }
}
const now = () => Math.floor(Date.now() / 1000);
async function sha256b64u(s: string) { return b64u(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)))); }
// Ventanas de uso únicas / límites: reutiliza el contador atómico de catalog-api.
async function consume(bucket: string, windowSeconds: number, max: number) {
  const { data, error } = await db.rpc("api_consume", { p_owner: OWNER, p_bucket: bucket, p_window_seconds: windowSeconds, p_max: max, p_amount: 1 });
  if (error) throw error;
  return data === true;
}

// ---------- metadatos OAuth ----------
function protectedResource() {
  return { resource: RESOURCE, authorization_servers: [ISSUER], scopes_supported: [SCOPE], bearer_methods_supported: ["header"], resource_name: "Mi Catálogo" };
}
function authServer() {
  return {
    issuer: ISSUER,
    authorization_endpoint: ISSUER + "/authorize",
    token_endpoint: ISSUER + "/token",
    registration_endpoint: ISSUER + "/register",
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    client_id_metadata_document_supported: true,
    authorization_response_iss_parameter_supported: true,
    scopes_supported: [SCOPE],
  };
}
const unauthorized = (desc: string) => json(401, { error: "invalid_token", error_description: desc }, {
  "www-authenticate": `Bearer resource_metadata="${PUBLIC_BASE}/.well-known/oauth-protected-resource", scope="${SCOPE}", error="invalid_token"`,
});

// ---------- clientes: CIMD de ChatGPT o registro dinámico firmado ----------
async function clientRedirects(clientId: string): Promise<string[] | null> {
  if (CIMD_RE.test(clientId)) {
    const r = await fetch(clientId, { redirect: "error", signal: AbortSignal.timeout(8000) });
    if (!r.ok) return null;
    const text = await r.text();
    if (text.length > 20_000) return null;
    const meta = JSON.parse(text);
    if (meta.client_id !== clientId || !Array.isArray(meta.redirect_uris)) return null;
    return meta.redirect_uris.filter((u: unknown) => typeof u === "string" && REDIRECT_RE.test(u));
  }
  const p = await verify(clientId, "client");
  return p && Array.isArray(p.ru) ? (p.ru as string[]).filter((u) => REDIRECT_RE.test(u)) : null;
}

async function register(req: Request) {
  const body = await req.json().catch(() => null);
  const uris = Array.isArray(body?.redirect_uris) ? body.redirect_uris.filter((u: unknown) => typeof u === "string") : [];
  if (!uris.length || uris.length > 5 || !uris.every((u: string) => REDIRECT_RE.test(u))) {
    return json(400, { error: "invalid_redirect_uri", error_description: "Solo se admiten destinos de ChatGPT." });
  }
  const clientId = await sign({ t: "client", ru: uris, exp: now() + 10 * 365 * 86400 });
  return json(201, { client_id: clientId, redirect_uris: uris, token_endpoint_auth_method: "none", grant_types: ["authorization_code", "refresh_token"], response_types: ["code"] });
}

// ---------- autorización con enlace por correo ----------
// Al conectar, se envía el enlace de acceso de Supabase Auth al correo del propietario.
// Al tocarlo en este mismo navegador, vuelve aquí y redirige a ChatGPT con el código.
async function ownerEmail(): Promise<string | null> {
  const { data, error } = await db.auth.admin.getUserById(OWNER);
  return error || !data.user?.email ? null : data.user.email;
}
function mask(email: string) { const [u, d] = email.split("@"); return u.slice(0, 2) + "•••@" + d; }
// Verificador PKCE de Supabase Auth derivado del nonce: no hace falta guardarlo.
async function authVerifier(n: string) {
  return b64u(new Uint8Array(await crypto.subtle.sign("HMAC", await key(), enc.encode("auth-pkce|" + n))));
}

async function authorizeStart(url: URL) {
  const q = url.searchParams;
  const clientId = q.get("client_id") ?? "", redirect = q.get("redirect_uri") ?? "", challenge = q.get("code_challenge") ?? "";
  const resource = q.get("resource") ?? RESOURCE;
  if (q.get("response_type") !== "code" || q.get("code_challenge_method") !== "S256" || !/^[A-Za-z0-9_-]{43,128}$/.test(challenge)) {
    return text(400, "Solicitud no válida: falta PKCE S256 o el tipo de respuesta no es válido.");
  }
  if (resource !== RESOURCE && resource !== PUBLIC_BASE) return text(400, "Solicitud no válida: recurso desconocido.");
  const allowed = await clientRedirects(clientId).catch(() => null);
  if (!allowed || !allowed.includes(redirect)) return text(400, "Solicitud no válida: este cliente no está autorizado.");
  const n = crypto.randomUUID();
  const reqToken = await sign({ t: "areq", cid: clientId, ru: redirect, cc: challenge, st: (q.get("state") ?? "").slice(0, 512), exp: now() + 900, n });
  const email = await ownerEmail();
  if (!email) return text(500, "El servidor no tiene usuario autorizado.");
  if (!await consume("mcp-link-send", 3600, 6)) return text(429, "Demasiados intentos. Espera un rato y vuelve a conectar desde ChatGPT.");
  const back = ISSUER + "/authorize/callback?req=" + encodeURIComponent(reqToken);
  const r = await fetch(SUPABASE_URL + "/auth/v1/otp?redirect_to=" + encodeURIComponent(back), {
    method: "POST", headers: { apikey: ANON_KEY, "content-type": "application/json" },
    body: JSON.stringify({ email, create_user: false, code_challenge: await sha256b64u(await authVerifier(n)), code_challenge_method: "s256" }) });
  if (!r.ok) return text(429, "No se pudo enviar el correo ahora (Supabase permite uno por minuto). Espera un minuto y vuelve a conectar desde ChatGPT.");
  return text(200, `Mi Catálogo · Conectar ChatGPT

ChatGPT pide permiso para AÑADIR productos a tu catálogo. No podrá leer, editar ni borrar lo que ya tienes.

Enviamos un enlace de acceso a ${mask(email)}.
Ábrelo EN ESTE MISMO NAVEGADOR y toca el enlace: volverás a ChatGPT ya conectado.
El enlace caduca en 15 minutos. Puedes cerrar esta pestaña después.`);
}

// El enlace del correo vuelve aquí con un código PKCE de Supabase Auth.
async function authorizeCallback(url: URL) {
  const reqToken = url.searchParams.get("req") ?? "";
  const p = await verify(reqToken, "areq");
  const code = url.searchParams.get("code") ?? "";
  if (!p || !/^[A-Za-z0-9-]{8,128}$/.test(code)) return text(400, "Enlace no válido o caducado. Vuelve a ChatGPT y conecta otra vez.");
  const r = await fetch(SUPABASE_URL + "/auth/v1/token?grant_type=pkce", { method: "POST", headers: { apikey: ANON_KEY, "content-type": "application/json" },
    body: JSON.stringify({ auth_code: code, code_verifier: await authVerifier(String(p.n)) }) });
  const session = r.ok ? await r.json().catch(() => null) : null;
  const uid = String(session?.user?.id ?? "").toLowerCase();
  if (session?.access_token) {
    // La sesión de Auth solo prueba la identidad; se cierra al momento.
    await fetch(SUPABASE_URL + "/auth/v1/logout?scope=local", { method: "POST", headers: { apikey: ANON_KEY, authorization: "Bearer " + session.access_token } }).catch(() => {});
  }
  if (!uid || uid !== OWNER) return text(400, "No autorizado: el enlace venció, ya se usó o no corresponde a tu cuenta. Conecta otra vez desde ChatGPT.");
  if (!await consume("mcp-issued-" + String(p.n), 86400, 1)) return text(400, "Esta autorización ya se completó.");
  const authCode = await sign({ t: "code", cid: p.cid, ru: p.ru, cc: p.cc, sub: OWNER, exp: now() + 120, j: crypto.randomUUID() });
  const dest = new URL(String(p.ru));
  dest.searchParams.set("code", authCode);
  if (p.st) dest.searchParams.set("state", String(p.st));
  dest.searchParams.set("iss", ISSUER);
  return new Response(null, { status: 302, headers: { ...BASE_HEADERS, location: dest.toString() } });
}

async function tokenEndpoint(req: Request) {
  const form = await req.formData().catch(() => null);
  if (!form) return json(400, { error: "invalid_request" });
  const grant = String(form.get("grant_type") ?? "");
  const resource = String(form.get("resource") ?? RESOURCE);
  if (resource !== RESOURCE && resource !== PUBLIC_BASE) return json(400, { error: "invalid_target" });
  let sub: string, cid: string;
  if (grant === "authorization_code") {
    const p = await verify(String(form.get("code") ?? ""), "code");
    if (!p || p.cid !== String(form.get("client_id") ?? "") || p.ru !== String(form.get("redirect_uri") ?? "")) return json(400, { error: "invalid_grant" });
    const verifier = String(form.get("code_verifier") ?? "");
    if (!/^[A-Za-z0-9._~-]{43,128}$/.test(verifier) || await sha256b64u(verifier) !== p.cc) return json(400, { error: "invalid_grant" });
    // Un código solo vale una vez.
    // Ventana diaria alineada: un código de 120 s no puede caer en dos ventanas salvo a medianoche UTC.
    if (!await consume("mcp-code-" + String(p.j), 86400, 1)) return json(400, { error: "invalid_grant" });
    sub = String(p.sub); cid = String(p.cid);
  } else if (grant === "refresh_token") {
    const p = await verify(String(form.get("refresh_token") ?? ""), "rt");
    if (!p) return json(400, { error: "invalid_grant" });
    sub = String(p.sub); cid = String(p.cid);
  } else return json(400, { error: "unsupported_grant_type" });
  if (sub !== OWNER) return json(400, { error: "invalid_grant" });
  const access = await sign({ t: "at", sub, aud: RESOURCE, scope: SCOPE, cid, exp: now() + 3600 });
  const refresh = await sign({ t: "rt", sub, cid, exp: now() + 30 * 86400, j: crypto.randomUUID() });
  return json(200, { access_token: access, token_type: "Bearer", expires_in: 3600, refresh_token: refresh, scope: SCOPE });
}

// ---------- herramientas MCP ----------
const str = (description?: string, maxLength = 2000) => ({ type: "string", maxLength, ...(description ? { description } : {}) });
const PRODUCT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["name"],
  properties: {
    name: str("Nombre corto y claro del producto", 200),
    brand: str(undefined, 120),
    category_key: str("Clave de listCategories (por ejemplo carteras, camisas, pantalones, pantallas)", 60),
    subcategory: str("Una de las subcategorías de esa categoría", 80),
    description: str(undefined, 5000),
    price_current: { type: "number", minimum: 0, description: "Precio tal como aparece en la tienda, en su moneda original" },
    price_previous: { type: "number", minimum: 0, description: "Solo si la tienda muestra un precio anterior real" },
    currency: { type: "string", enum: ["USD", "CNY", "EUR", "GBP", "JPY", "KRW", "HKD", "MXN", "CAD"] },
    shipping_estimate_usd: { type: "number", minimum: 0 },
    original_url: str("Enlace de la página del producto (tienda o agente)", 2048),
    platform: str("Taobao, Weidian, 1688, Yupoo, etc.", 60),
    agent_links: { type: "array", maxItems: 10, items: { type: "object", additionalProperties: false, required: ["name", "url"],
      properties: { name: str("Agente: Hipobuy, Sugargoo, KakoBuy, CSSBuy, Mulebuy u Otro", 60), url: str("Enlace real del producto en ese agente", 2048) } } },
    seller_name: str(undefined, 200),
    seller_rating: { type: "number", minimum: 0, maximum: 5, description: "Solo si la página muestra una valoración real (0 a 5)" },
    seller_rating_count: str("Número de reseñas tal como aparece, por ejemplo 1.2k", 30),
    seller_rating_source: str(undefined, 120),
    color: str(undefined, 120), size: str(undefined, 120), material: str(undefined, 200),
    attributes: { type: "object", maxProperties: 30, additionalProperties: { type: "string", maxLength: 200 },
      description: "Atributos por categoría. Pantalones: largo, corte, cintura. Carteras: tamano, compartimentos, ancho, alto, profundidad (cm). Pantallas: tamanoMM, piedra, metal, cierre, forma." },
    declared_quality: str("Calidad que afirma el vendedor, por ejemplo 1:1", 120),
    included_accessories: str(undefined, 500),
    notes: str("Notas útiles para el usuario, como por qué se eligió", 5000),
    is_favorite: { type: "boolean" },
    priority: { type: "integer", minimum: 0, maximum: 3 },
    status: { type: "string", enum: ["researching", "favorite", "pending", "ready", "purchased", "discarded"] },
    images: { type: "array", maxItems: 10, items: { type: "object", additionalProperties: false, required: ["url"], properties: {
      url: str("Enlace directo a la imagen (jpg, png o webp), no a la página", 600),
      kind: { type: "string", enum: ["official", "qc", "buyer", "worn", "manual"], description: "official = foto del anuncio, qc = foto de inspección, buyer = foto de comprador, worn = producto puesto" } } } },
    collections: { type: "array", maxItems: 10, items: str(undefined, 120), description: "Nombres o ids de colecciones; las que no existan se crean" },
    allow_duplicate: { type: "boolean", description: "true solo si el usuario pidió guardarlo aunque ya exista" },
  },
};
const SECURITY = [{ type: "oauth2", scopes: [SCOPE] }];
const TOOLS = [
  {
    name: "listCategories",
    title: "Ver categorías del catálogo",
    description: "Solo lectura. Devuelve las claves de categoría y subcategorías válidas para createProduct. No devuelve productos.",
    inputSchema: { type: "object", additionalProperties: false, properties: {} },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    securitySchemes: SECURITY, _meta: { securitySchemes: SECURITY },
  },
  {
    name: "createProduct",
    title: "Guardar producto en el catálogo",
    description: "Acción de escritura: añade un producto nuevo al catálogo personal del usuario. Responde siempre «Recibido», también si ya existía; no puede leer, editar ni borrar productos.",
    inputSchema: PRODUCT_SCHEMA,
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    securitySchemes: SECURITY, _meta: { securitySchemes: SECURITY },
  },
];

// Validación propia antes de llamar a catalog-api (que vuelve a validar todo).
function checkProduct(args: unknown): string[] {
  const issues: string[] = [];
  if (!args || typeof args !== "object" || Array.isArray(args)) return ["Los argumentos deben ser un objeto"];
  const a = args as Record<string, unknown>;
  const props = PRODUCT_SCHEMA.properties as Record<string, Record<string, unknown>>;
  for (const k of Object.keys(a)) if (!(k in props)) issues.push(`Campo no permitido: ${k.slice(0, 40)}`);
  if (typeof a.name !== "string" || !a.name.trim()) issues.push("name es obligatorio");
  for (const [k, spec] of Object.entries(props)) {
    const v = a[k];
    if (v === undefined || v === null) continue;
    if (spec.type === "string" && (typeof v !== "string" || v.length > Number(spec.maxLength ?? 2000))) issues.push(`${k} no es un texto válido`);
    if (spec.type === "number" && (typeof v !== "number" || !Number.isFinite(v) || v < 0 || (spec.maximum !== undefined && v > Number(spec.maximum)))) issues.push(`${k} debe ser un número válido`);
    if (spec.type === "integer" && (!Number.isInteger(v) || (v as number) < 0 || (v as number) > 3)) issues.push(`${k} debe ser un entero de 0 a 3`);
    if (spec.type === "boolean" && typeof v !== "boolean") issues.push(`${k} debe ser true o false`);
    if (spec.enum && !(spec.enum as unknown[]).includes(v)) issues.push(`${k} no es un valor permitido`);
  }
  const web = (u: unknown) => { try { const x = new URL(String(u)); return (x.protocol === "https:" || x.protocol === "http:") && !x.username && !x.password; } catch { return false; } };
  if (a.original_url !== undefined && !web(a.original_url)) issues.push("original_url debe empezar por https:// o http://");
  if (Array.isArray(a.images)) a.images.forEach((im, i) => { if (!im || typeof im !== "object" || !web((im as Record<string, unknown>).url)) issues.push(`images[${i}].url no es un enlace válido`); });
  else if (a.images !== undefined) issues.push("images debe ser una lista");
  if (Array.isArray(a.agent_links)) a.agent_links.forEach((l, i) => { if (!l || typeof l !== "object" || !web((l as Record<string, unknown>).url)) issues.push(`agent_links[${i}].url no es un enlace válido`); });
  return issues.slice(0, 20);
}

const toolText = (text: string, isError = false) => ({ content: [{ type: "text", text }], isError });
async function callCatalog(method: string, path: string, body?: unknown) {
  const r = await fetch(CATALOG_API + path, { method, headers: { "x-api-key": API_KEY, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(55_000) });
  const data = await r.json().catch(() => ({}));
  return { status: r.status, data: data as Record<string, unknown> };
}
function errorText(status: number, data: Record<string, unknown>) {
  const issues = Array.isArray(data.issues) ? " Detalles: " + (data.issues as unknown[]).slice(0, 10).map(String).join("; ") : "";
  if (status === 400) return "400 Datos no válidos." + issues;
  if (status === 401) return "401 El servidor no pudo autenticarse con el catálogo.";
  if (status === 403) return "403 El acceso de ChatGPT está pausado o no tiene permiso.";
  if (status === 429) return "429 Se alcanzó un límite de uso; inténtalo más tarde.";
  return `${status} No se pudo completar la operación.`;
}

async function callTool(name: string, args: unknown) {
  if (!await consume("mcp-call-minute", 60, 30)) return toolText("429 Demasiadas peticiones; espera un minuto.", true);
  if (name === "listCategories") {
    const r = await callCatalog("GET", "/categories");
    if (r.status !== 200) return toolText(errorText(r.status, r.data), true);
    const cats = Array.isArray(r.data.categories) ? r.data.categories : [];
    return { ...toolText(JSON.stringify(cats)), structuredContent: { categories: cats } };
  }
  if (name === "createProduct") {
    const issues = checkProduct(args);
    if (issues.length) return toolText("400 Datos no válidos. Detalles: " + issues.join("; "), true);
    const r = await callCatalog("POST", "/products", args);
    if (r.status === 202 || r.status === 201) return toolText("Recibido. Lo verás en la app; si ya lo tenías, no se duplica.");
    return toolText(errorText(r.status, r.data), true);
  }
  return null;
}

// ---------- JSON-RPC ----------
type Rpc = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };
const rpcResult = (id: Rpc["id"], result: unknown) => ({ jsonrpc: "2.0", id, result });
const rpcError = (id: Rpc["id"], code: number, message: string) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

async function handleRpc(msg: Rpc) {
  const id = msg.id;
  if (msg.jsonrpc !== "2.0" || typeof msg.method !== "string") return rpcError(id, -32600, "Solicitud no válida");
  if (id === undefined) return null; // notificaciones (initialized, cancelled…)
  switch (msg.method) {
    case "initialize": {
      const asked = String(msg.params?.protocolVersion ?? "");
      return rpcResult(id, {
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "mi-catalogo", title: "Mi Catálogo", version: "1.0.0" },
        instructions: "Usa listCategories para conocer las claves válidas y createProduct para guardar productos. No puedes leer, editar ni borrar el catálogo.",
      });
    }
    case "ping": return rpcResult(id, {});
    case "tools/list": return rpcResult(id, { tools: TOOLS });
    case "tools/call": {
      const res = await callTool(String(msg.params?.name ?? ""), msg.params?.arguments ?? {});
      return res ? rpcResult(id, res) : rpcError(id, -32602, "Herramienta desconocida");
    }
    default: return rpcError(id, -32601, "Método no disponible");
  }
}

async function mcp(req: Request) {
  if (req.method === "GET" || req.method === "DELETE") return json(405, { error: "Usa POST" }, { allow: "POST" });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.match(/^Bearer\s+(.+)$/i)?.[1] ?? "";
  if (!token) return unauthorized("Falta autorización");
  const p = await verify(token, "at");
  if (!p || p.aud !== RESOURCE || p.sub !== OWNER || p.scope !== SCOPE) return unauthorized("Token no válido o vencido");
  const text = await req.text();
  if (text.length > MAX_BODY) return json(413, rpcError(null, -32600, "Petición demasiado grande"));
  let msg: unknown;
  try { msg = JSON.parse(text); } catch { return json(400, rpcError(null, -32700, "JSON no válido")); }
  if (Array.isArray(msg)) return json(400, rpcError(null, -32600, "Lotes no admitidos"));
  const out = await handleRpc(msg as Rpc);
  return out ? json(200, out) : new Response(null, { status: 202, headers: BASE_HEADERS });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*\/catalog-mcp/, "") || "/";
  if (!SECRET || SECRET.length < 32 || !API_KEY || !OWNER || !SERVICE_KEY || !ANON_KEY) return json(503, { error: "El servidor no está configurado." });
  try {
    if (req.method === "GET" && (path === "/.well-known/oauth-protected-resource" || path === "/.well-known/oauth-protected-resource/mcp" || path === "/mcp/.well-known/oauth-protected-resource")) return json(200, protectedResource());
    if (req.method === "GET" && (path === "/.well-known/oauth-authorization-server" || path === "/.well-known/openid-configuration")) return json(200, authServer());
    if (path === "/mcp") return await mcp(req);
    if (path === "/register" && req.method === "POST") return await register(req);
    if (path === "/authorize" && req.method === "GET") return await authorizeStart(url);
    if (path === "/authorize/callback" && req.method === "GET") return await authorizeCallback(url);
    if (path === "/token" && req.method === "POST") return await tokenEndpoint(req);
    if (path === "/health") return json(200, { ok: true });
    return json(404, { error: "No encontrado" });
  } catch (e) {
    console.error("catalog-mcp error", e instanceof Error ? e.message : "desconocido");
    return json(500, { error: "Error interno" });
  }
});
