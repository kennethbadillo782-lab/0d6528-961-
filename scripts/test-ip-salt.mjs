// Comprueba la huella producida por el handler real, sin divulgar secretos.
import { DB, sha } from '../backend/supabase/functions/tests/e2e/fake-supabase.mjs';
const custom = process.argv.includes('--custom');
let handler;
const service = 'test-service-not-a-real-secret';
const salt = custom ? 'test-custom-salt-not-a-real-secret' : undefined;
globalThis.Deno = {
  env: { get: name => ({ SUPABASE_URL: 'http://test.invalid', SUPABASE_SERVICE_ROLE_KEY: service, API_IP_SALT: salt })[name] },
  serve: fn => { handler = fn; },
};
const owner = '11111111-1111-4111-8111-111111111111';
const key = 'mc_' + 'a'.repeat(48);
DB.api_keys.push({ id: 'salt-test', owner_id: owner, key_hash: sha(key), scopes: ['create'] });
DB.categories.push({ owner_id: owner, key: 'otros' });
await import('../backend/supabase/functions/catalog-api/index.ts');
const response = await handler(new Request('https://test.invalid/functions/v1/catalog-api/products', {
  method: 'POST', headers: { 'content-type': 'application/json', 'x-api-key': key, 'x-forwarded-for': '1.2.3.4' }, body: JSON.stringify({ name: 'Salt regression' }),
}));
const expected = sha((salt || 'derived|' + service) + '|1.2.3.4').slice(0,24);
if (response.status !== 202 || !DB.api_audit_log.length || !DB.api_audit_log.every(e => e.ip_hash === expected)) {
  throw Error('La huella IP no usa la sal esperada.');
}
console.log(`ok - huella IP con ${custom ? 'sal configurada' : 'sal derivada del secreto del servicio'}`);
