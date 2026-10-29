import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
await mkdir(path.join(root, 'reports'), { recursive: true });
const suites = [
  ['utilities', 'backend/supabase/functions', ['--experimental-strip-types', 'tests/shared.test.ts']],
  ['api-flow-mocked-db', 'backend/supabase/functions/tests/e2e', ['--experimental-strip-types', '--import', './register.mjs', 'run.mjs']],
  ['api-security-mocked-db', 'backend/supabase/functions/tests/e2e', ['--experimental-strip-types', '--import', './register.mjs', 'attack.mjs']],
];
const results = [];
for (const [name, cwd, args] of suites) {
  console.log(`Iniciando ${name}`);
  const started = Date.now();
  const child = spawn(process.execPath, args, { cwd: path.join(root, cwd), stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.on('data', d => { output += d; process.stdout.write(d); });
  child.stderr.on('data', d => { output += d; process.stderr.write(d); });
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
  await writeFile(path.join(root, 'reports', `${name}.log`), output);
  results.push({ name, exitCode: code, elapsedMs: Date.now() - started, checks: (output.match(/^ok\s*-/gm) || []).length });
}
await writeFile(path.join(root, 'reports', 'node-tests.json'), JSON.stringify({ at: new Date().toISOString(), node: process.version, results, excluded: ['PostgreSQL: Test-Database.ps1', 'Supabase real: test-live.mjs', 'iOS: macOS/Xcode', 'XSS: Playwright'] }, null, 2));
if (results.some(r => r.exitCode !== 0)) process.exitCode = 1;
