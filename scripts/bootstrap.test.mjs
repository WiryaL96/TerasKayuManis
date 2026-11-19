import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile, unlink, stat, mkdir } from 'node:fs/promises'
import { resolve, join } from 'node:path'
import { execFileSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { bootstrapConfig } from './bootstrap-superadmin-config.mjs'
import { reservePrivateOutput } from './private-output.mjs'

const values = { project: 'syntheticproject', name: ' Owner Test ', email: ' OWNER@example.test ', output: '.cache/test-activation.txt' }
const env = { NUXT_SUPABASE_URL: 'https://syntheticproject.supabase.co', NUXT_SUPABASE_SERVICE_KEY: 'synthetic-only', NUXT_SITE_URL: 'https://restaurant.example.test' }
test('bootstrap validates the explicit project and identity, and requires an explicit flag for loopback HTTP', () => {
  assert.deepEqual(bootstrapConfig(values, env), { url: env.NUXT_SUPABASE_URL, key: 'synthetic-only', site: env.NUXT_SITE_URL, name: 'Owner Test', email: 'owner@example.test' })
  for (const site of ['http://127.0.0.1:3000', 'http://localhost:3000', 'http://[::1]:3000']) {
    assert.throws(() => bootstrapConfig(values, { ...env, NUXT_SITE_URL: site }))
    assert.equal(bootstrapConfig({ ...values, local: true }, { ...env, NUXT_SITE_URL: site }).site, site)
  }
  for (const site of ['http://restaurant.example.test', 'http://127.0.0.1.evil.test:3000', 'https://name:secret@restaurant.example.test', 'https://restaurant.example.test/path', 'https://restaurant.example.test/#fragment'])
    assert.throws(() => bootstrapConfig({ ...values, local: true }, { ...env, NUXT_SITE_URL: site }))
  for (const url of ['https://otherproject.supabase.co', 'http://syntheticproject.supabase.co', 'https://syntheticproject.supabase.co/rest/v1'])
    assert.throws(() => bootstrapConfig(values, { ...env, NUXT_SUPABASE_URL: url }))
  for (const patch of [{ name: '' }, { name: 'Bad\nName' }, { email: 'invalid' }, { project: '' }, { output: '' }]) assert.throws(() => bootstrapConfig({ ...values, ...patch }, env))
})

test('private output is exclusive and restricted before a token is written, including Windows ACLs', async () => {
  await mkdir(resolve('.cache'), { recursive: true })
  const file = resolve('.cache', `operator-file [${randomUUID()}] $literal.txt`)
  let handle
  try {
    handle = await reservePrivateOutput(file)
    await handle.writeFile('synthetic activation data only')
    await handle.close(); handle = undefined
    if (process.platform === 'win32') {
      const script = `$ErrorActionPreference='Stop'; $a=[System.IO.File]::GetAccessControl($env:TKM_OPERATOR_FILE); $s=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $r=@($a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])); @{protected=$a.AreAccessRulesProtected;users=@($r|ForEach-Object {$_.IdentityReference.Value});expected=$s} | ConvertTo-Json -Compress`
      const result = JSON.parse(execFileSync(join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script], { env: { ...process.env, TKM_OPERATOR_FILE: file }, windowsHide: true, encoding: 'utf8', timeout: 10000 }))
      assert.equal(result.protected, true); assert.deepEqual(result.users, [result.expected])
      await assert.rejects(reservePrivateOutput('\\\\invalid-host\\share\\activation.txt'), /local Windows drive/)
    } else assert.equal((await stat(file)).mode & 0o777, 0o600)
    await assert.rejects(reservePrivateOutput(file), e => e.code === 'EEXIST')
    assert.equal(await readFile(file, 'utf8'), 'synthetic activation data only')
  } finally { await handle?.close(); await unlink(file).catch(() => {}) }
})
