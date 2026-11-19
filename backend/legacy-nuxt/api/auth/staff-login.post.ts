import { createClient } from '@supabase/supabase-js'

export default defineEventHandler(async (event) => {
  await sensitiveRequest(event, 10)
  const body = await readBody<Record<string, unknown>>(event)
  if (!body || typeof body.email !== 'string' || typeof body.password !== 'string' ||
    body.email.length > 254 || !body.email.trim() || !body.password || body.password.length > 128 ||
    typeof body.area !== 'string' || !['cashier', 'admin'].includes(body.area) ||
    Object.keys(body).some(k => !['email', 'password', 'area'].includes(k))) {
    throw createError({ statusCode: 400, statusMessage: 'Isi username/email dan password akun pribadi.' })
  }
  const identifier=body.email.trim().toLowerCase()
  let email=identifier
  if(!identifier.includes('@')){
    if(!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(identifier))throw createError({statusCode:401,statusMessage:'Username/email atau password tidak sesuai.'})
    const lookup=await serviceClient(event).from('profiles').select('email').eq('username',identifier).maybeSingle()
    if(lookup.error)throw createError({statusCode:503,statusMessage:'Login belum tersedia. Coba lagi sebentar.'})
    email=lookup.data?.email||'unknown-staff@invalid.invalid'
  }
  const config = useRuntimeConfig(event)
  const verifier = createClient(String(config.supabaseUrl), String(config.supabaseAnonKey), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: staffFetch },
  })
  const { data, error } = await verifier.auth.signInWithPassword({ email, password: body.password })
  if (error || !data.session || !data.user) {
    throw createError({ statusCode: error?.status && error.status >= 500 ? 503 : 401, statusMessage: 'Login belum berhasil. Periksa username/email, password, dan koneksi lalu coba lagi.' })
  }
  let accepted = false
  try {
    if(data.user.app_metadata?.staff_access_method==='pin')throw createError({statusCode:403,statusMessage:'Gunakan pilihan nama dan PIN untuk masuk ke kasir.'})
    const { data: profile, error: auditError } = await serviceClient(event).rpc('record_staff_signin', {
      p_actor: data.user.id, p_version: staffVersion(data.session.access_token), p_area: body.area,
    })
    if (auditError || !profile) {
      throw createError({ statusCode: auditError?.code === '42501' ? 403 : 503,
        statusMessage: auditError?.code === '42501'
          ? 'Akun belum aktif, nama belum lengkap, atau tidak memiliki akses. Hubungi admin untuk memeriksa akun pribadi.'
          : 'Login belum dapat dicatat. Hubungi admin atau coba lagi sebentar.' })
    }
    accepted = true
    // Tokens go only to this same-origin browser for the normal SDK session.
    // Never persist request bodies, credentials or token responses in audit logs.
    return { profile, session: { access_token: data.session.access_token, refresh_token: data.session.refresh_token } }
  } finally {
    if (!accepted) await verifier.auth.signOut({ scope: 'local' }).catch(() => {})
  }
})
