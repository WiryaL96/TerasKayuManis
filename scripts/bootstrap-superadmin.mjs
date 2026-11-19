// Operator only. Read credentials from a private environment, never CLI args.
import { createClient } from '@supabase/supabase-js'
import { randomBytes, createHash } from 'node:crypto'
import { parseArgs } from 'node:util'
import { reservePrivateOutput } from './private-output.mjs'
import { bootstrapConfig } from './bootstrap-superadmin-config.mjs'
const { values } = parseArgs({
  options: {
    name: { type: 'string' },
    email: { type: 'string' },
    project: { type: 'string' },
    output: { type: 'string' },
    'resume-id': { type: 'string' },
    local: { type: 'boolean', default: false },
  },
})
let handle
try {
  const { url, key, site, name, email } = bootstrapConfig(values, process.env)
  // Reserve a private file before changing remote state; never overwrite one.
  handle = await reservePrivateOutput(values.output)
  const sb = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: (input, options) => fetch(input, { ...options, signal: options?.signal ? AbortSignal.any([options.signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000) }) },
  })
  // These null arguments are rejected before any row changes by the migrated
  // function. Check its presence/ACL before creating a new Auth identity.
  const schema = await sb.from('profiles').select('id,role,staff_status,session_version,email').limit(0)
  const probe = await sb.rpc('bootstrap_superadmin', { p_id: null, p_name: null, p_email: null, p_hash: null })
  if (schema.error || probe.error?.code !== '23514') throw Error()
  const roots = await sb.from('profiles').select('id,staff_status').eq('role', 'superadmin').limit(2)
  if (roots.error || (roots.data || []).some(p => p.id !== values['resume-id'] || p.staff_status !== 'invited')) throw Error()
  let id,
    created = false
  if (values['resume-id']) {
    const existing = await sb
      .from('profiles')
      .select('id,full_name,email,role,staff_status')
      .eq('id', values['resume-id'])
      .single()
    const identity = await sb.auth.admin.getUserById(values['resume-id'])
    if (
      existing.error ||
      identity.error ||
      existing.data.role !== 'superadmin' ||
      existing.data.staff_status !== 'invited' ||
      existing.data.full_name !== name ||
      existing.data.email?.toLowerCase() !== email ||
      identity.data.user?.email?.toLowerCase() !== email
    )
      throw Error()
    id = existing.data.id
  } else {
    // A new bootstrap never adopts an existing customer/Auth identity.
    const { data, error } = await sb.auth.admin.createUser({
      email,
      email_confirm: true,
    })
    if (error || !data.user) throw Error()
    id = data.user.id
    created = true
  }
  const ticket = randomBytes(32).toString('hex')
  const boot = await sb.rpc('bootstrap_superadmin', {
    p_id: id,
    p_name: name,
    p_email: email,
    p_hash: createHash('sha256').update(ticket).digest('hex'),
  })
  if (boot.error) {
    // Clean up only this run's new identity after a definite SQL rollback.
    // A network failure may have committed: preserve it for operator inspection.
    if (created && ['42501', '23514', '23505', '42883', 'PGRST202'].includes(boot.error.code))
      await sb.auth.admin.deleteUser(id)
    throw Error()
  }
  const generated = await sb.auth.admin.generateLink({
    type: 'recovery',
    email,
  })
  if (
    generated.error ||
    generated.data.user?.id !== id ||
    !generated.data.properties?.hashed_token
  )
    throw Error()
  const fragment = new URLSearchParams({
    ticket,
    token_hash: generated.data.properties.hashed_token,
    purpose: 'activation',
  })
  await handle.writeFile(
    site.replace(/\/$/, '') + '/auth/activate#' + fragment + '\n',
  )
  await handle.sync()
  await handle.close()
  handle = undefined
  process.stdout.write(
    'Superadmin reserved. Private one-use activation link saved to the requested file (60 minutes).\n',
  )
} catch {
  if (handle) await handle.close()
  process.stderr.write(
    'Bootstrap failed. Check private configuration and superadmin profile state before retrying; no credentials are logged.\n',
  )
  process.exitCode = 1
}
