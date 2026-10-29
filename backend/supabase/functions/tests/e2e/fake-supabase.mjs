// Base de datos en memoria que imita lo justo del cliente de Supabase.
import { createHash, randomUUID } from 'node:crypto';
export const DB = { products: [], product_images: [], collections: [], product_collections: [], categories: [], api_audit_log: [], api_keys: [], api_settings: [] };
export const STORAGE = [];
export const USAGE = new Map(); export const FAILS = new Map();
const like = (v, p) => new RegExp('^' + p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*') + '$', 'i').test(String(v ?? ''));
class Q {
  constructor(t) { this.t = t; this.f = []; this.op = 'select'; this.one = null; this.cnt = false; this.rng = null; }
  select(cols, o) { if (this.op === 'select') this.op = 'select'; this.ret = true; if (o?.count) this.cnt = true; return this; }
  eq(k, v) { this.f.push(r => r[k] === v); return this; }
  neq(k, v) { this.f.push(r => r[k] !== v); return this; }
  is(k, v) { this.f.push(r => (r[k] ?? null) === v); return this; }
  ilike(k, p) {
    // PostgreSQL genera search_text; el doble debe representar esa columna también.
    this.f.push(r => like(k === 'search_text'
      ? ['name', 'brand', 'subcategory', 'seller_name', 'platform', 'color', 'notes'].map(c => r[c] ?? '').join(' ').toLowerCase()
      : r[k], p));
    return this;
  }
  in(k, arr) { this.f.push(r => arr.includes(r[k])); return this; }
  order() { return this; } limit(n) { this.lim = n; return this; }
  range(a, b) { this.rng = [a, b]; return this; }
  maybeSingle() { this.one = 'maybe'; return this; } single() { this.one = 'single'; return this; }
  insert(rows) { this.op = 'insert'; this.rows = Array.isArray(rows) ? rows : [rows]; return this; }
  update(v) { this.op = 'update'; this.vals = v; return this; }
  upsert(rows, o) { this.op = 'upsert'; this.rows = rows; this.conf = o.onConflict.split(','); return this; }
  then(res, rej) { return Promise.resolve(this.run()).then(res, rej); }
  run() {
    const T = DB[this.t]; let data;
    if (this.op === 'insert') { data = this.rows.map(r => { const row = { id: randomUUID(), created_at: new Date().toISOString(), deleted_at: null, ...r }; T.push(row); return row; }); }
    else if (this.op === 'upsert') { data = this.rows.map(r => { const ex = T.find(x => this.conf.every(k => x[k] === r[k])); if (ex) return Object.assign(ex, r); T.push({ ...r }); return r; }); }
    else { const m = T.filter(r => this.f.every(fn => fn(r))); if (this.op === 'update') m.forEach(r => Object.assign(r, this.vals)); data = m; }
    const count = data.length;
    if (this.rng) data = data.slice(this.rng[0], this.rng[1] + 1);
    if (this.lim) data = data.slice(0, this.lim);
    if (this.one) { if (this.one === 'single' && data.length !== 1) return { data: null, error: { message: 'not single' } }; data = data[0] ?? null; }
    return { data, error: null, count };
  }
}
export function createClient() {
  return {
    from: t => new Q(t),
    rpc: async (fn, a) => {
      if (fn === 'api_authenticate') { const k = DB.api_keys.find(k => k.key_hash === a.p_key_hash && !k.revoked_at && (!k.expires_at || new Date(k.expires_at) > new Date())); if (!k) return { data: [], error: null }; const s = DB.api_settings.find(s => s.owner_id === k.owner_id) ?? {}; return { data: [{ key_id: k.id, owner_id: k.owner_id, scopes: k.scopes, enabled: s.enabled ?? true, daily_create_limit: s.daily_create_limit ?? 100, daily_write_limit: 400, daily_image_limit: 400, daily_image_mb: s.daily_image_mb ?? 300, max_storage_mb: s.max_storage_mb ?? 2048 }], error: null }; }
      if (fn === 'api_storage_used') return { data: DB.product_images.filter(i => i.owner_id === a.p_owner && !i.deleted_at).reduce((n, i) => n + (i.bytes ?? 0), 0), error: null };
      if (fn === 'api_consume') { const key = a.p_owner + a.p_bucket; const c = (USAGE.get(key) ?? 0) + a.p_amount; USAGE.set(key, c); return { data: c <= a.p_max, error: null }; }
      if (fn === 'api_note_auth_failure') { FAILS.set(a.p_ip_hash, (FAILS.get(a.p_ip_hash) ?? 0) + 1); return { data: 1, error: null }; }
      if (fn === 'api_auth_failures_recent') return { data: FAILS.get(a.p_ip_hash) ?? 0, error: null };
      return { data: null, error: { message: 'rpc ' + fn } };
    },
    storage: { from: () => ({ upload: async (p, b) => { STORAGE.push(p); return { error: null }; }, remove: async () => ({ error: null }) }) },
  };
}
export const sha = s => createHash('sha256').update(s).digest('hex');
