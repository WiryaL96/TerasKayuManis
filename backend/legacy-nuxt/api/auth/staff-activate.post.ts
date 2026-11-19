import { createHash } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
export default defineEventHandler(async (event) => {
  await sensitiveRequest(event, 6)
  const b = await readBody<{
    ticket?: string
    token_hash?: string
    password?: string
    purpose?: string
  }>(event)
  if (
    !b ||
    typeof b.ticket !== 'string' ||
    !/^[a-f0-9]{64}$/.test(b.ticket) ||
    typeof b.token_hash !== 'string' ||
    b.token_hash.length > 512 ||
    typeof b.password !== 'string' ||
    b.password.length < 12 ||
    b.password.length > 128 ||
    !['activation', 'recovery'].includes(b.purpose ?? '')
  )
    throw createError({
      statusCode: 400,
      statusMessage:
        'Tautan tidak valid atau password kurang dari 12 karakter.',
    })
  const sb = serviceClient(event),
    { data: claim, error } = await sb.rpc('claim_staff_access', {
      p_hash: createHash('sha256').update(b.ticket).digest('hex'),
    })
  if (error || !claim || claim.purpose !== b.purpose)
    throw createError({
      statusCode: 400,
      statusMessage:
        'Tautan kedaluwarsa atau sudah digunakan. Minta tautan baru ke admin.',
    })
  const config = useRuntimeConfig(event)
  const verifier = createClient(
    config.supabaseUrl as string,
    config.supabaseAnonKey as string,
    { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: staffFetch } },
  )
  const { data: verified, error: otpError } = await verifier.auth.verifyOtp({
    token_hash: b.token_hash,
    type: 'recovery',
  })
  if (
    otpError ||
    !verified.session ||
    !verified.user ||
    verified.user.id !== claim.profile_id
  )
    throw createError({
      statusCode: 400,
      statusMessage:
        'Tautan tidak dapat diverifikasi. Minta tautan baru ke admin.',
    })
  const { error: versionError } = await sb.auth.admin.updateUserById(
    claim.profile_id,
    {
      password: b.password,
      app_metadata: {
        ...verified.user.app_metadata,
        staff_session_version: claim.session_version,
      },
    },
  )
  if (versionError)
    throw createError({
      statusCode: 503,
      statusMessage: 'Aktivasi belum selesai. Minta tautan baru ke admin.',
    })
  const { data: ok, error: finishError } = await sb.rpc('finish_staff_access', {
    p_target: claim.profile_id,
    p_version: claim.session_version,
  })
  if (finishError || !ok)
    throw createError({
      statusCode: 409,
      statusMessage: 'Akun berubah atau dinonaktifkan. Hubungi admin.',
    })
  // Do not return the privileged or OTP session. Staff signs in with their new password.
  return { ok: true }
})
