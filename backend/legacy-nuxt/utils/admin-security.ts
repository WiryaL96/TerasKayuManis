import type { H3Event } from 'h3'
import { canManageStaffRole } from '#shared/staff-roles'

const attempts = new Map<string, { count: number; until: number }>()

function isDevelopmentLoopbackOrigin(configured: string, origin: string | undefined) {
  if (process.env.NODE_ENV !== 'development' || !origin) return false
  try {
    const expected = new URL(configured)
    const requested = new URL(origin)
    const loopback = new Set(['localhost', '127.0.0.1', '[::1]'])
    return expected.origin === configured && requested.origin === origin &&
      expected.protocol === 'http:' && requested.protocol === 'http:' &&
      loopback.has(expected.hostname) && loopback.has(requested.hostname) &&
      expected.port === requested.port
  } catch {
    return false
  }
}

export function sensitiveRequest(event: H3Event, limit = 12) {
  const configured = String(useRuntimeConfig(event).siteUrl || '').replace(
    /\/$/,
    '',
  )
  const origin = getHeader(event, 'origin')
  if (!configured || (origin !== configured && !isDevelopmentLoopbackOrigin(configured, origin)))
    throw createError({
      statusCode: 403,
      statusMessage: 'Permintaan harus berasal dari aplikasi restoran.',
    })
  const key =
      (getRequestIP(event) ?? 'unknown') + ':' + getRequestURL(event).pathname,
    now = Date.now(),
    entry = attempts.get(key)
  if (useRuntimeConfig(event).serverless) {
    setHeader(event,'Cache-Control','no-store')
    setHeader(event,'Referrer-Policy','no-referrer')
    return sensitiveBudget(event,limit)
  }
  if (attempts.size > 2000) {
    for (const [k, v] of attempts) if (v.until <= now) attempts.delete(k)
    if (attempts.size > 2000)
      throw createError({
        statusCode: 429,
        statusMessage: 'Coba lagi sebentar.',
      })
  }
  if (entry && entry.until > now) {
    if (++entry.count > limit)
      throw createError({
        statusCode: 429,
        statusMessage: 'Terlalu banyak percobaan. Tunggu satu menit.',
      })
  } else attempts.set(key, { count: 1, until: now + 60000 })
  setHeader(event, 'Cache-Control', 'no-store')
  setHeader(event, 'Referrer-Policy', 'no-referrer')
}
export function checkedStaffInput(value: unknown, actorRole = 'admin') {
  const b = value as Record<string, unknown>
  if (
    !b ||
    typeof b !== 'object' ||
    Array.isArray(b) ||
    typeof b.full_name !== 'string' ||
    typeof b.email !== 'string' ||
    Object.keys(b).some((k) => !['full_name', 'email', 'role', 'username', 'password', 'pin', 'photo_path'].includes(k))
  )
    throw createError({
      statusCode: 400,
      statusMessage: 'Data akun tidak valid.',
    })
  const name = String(b.full_name ?? '').trim(),
    email = String(b.email ?? '')
      .trim()
      .toLowerCase()
  if (
    name.length < 2 ||
    name.length > 100 ||
    /[\u0000-\u001f\u007f]/.test(name) ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  )
    throw createError({
      statusCode: 400,
      statusMessage: 'Isi nama lengkap dan email yang valid.',
    })
  const role = b.role ?? 'cashier'
  if (typeof role !== 'string' || !['admin', 'cashier'].includes(role))
    throw createError({ statusCode: 400, statusMessage: 'Peran akun harus admin atau kasir.' })
  if (!canManageStaffRole(actorRole, role))
    throw createError({ statusCode: 403, statusMessage: 'Hanya superadmin yang dapat membuat akun admin.' })
  const username=typeof b.username==='string'?b.username.trim().toLowerCase():''
  if(!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(username))throw createError({statusCode:400,statusMessage:'Username 3–32 karakter: huruf, angka, titik, garis bawah, atau tanda hubung.'})
  if(b.pin!==undefined&&(role!=='cashier'||b.password!==undefined))throw createError({statusCode:400,statusMessage:'PIN hanya untuk akun kasir.'})
  const credential=b.pin!==undefined?{pin:checkedCashierPin(b.pin)}:{password:checkedStaffPassword(b.password)}
  if(b.photo_path!==undefined&&(typeof b.photo_path!=='string'||!/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.webp$/.test(b.photo_path)))throw createError({statusCode:400,statusMessage:'Unggah foto staf yang valid.'})
  return { full_name: name, email, role, username, ...credential,...(b.photo_path?{photo_path:b.photo_path as string}:{}) }
}
export function checkedStaffPassword(value:unknown):string {
  if(typeof value!=='string'||value.length<12||value.length>128||!value.trim())throw createError({statusCode:400,statusMessage:'Password harus berisi 12–128 karakter.'})
  return value
}
export function staffVersion(token: string) {
  try {
    const p = token.split('.')
    if (p.length !== 3) return 0
    const n =
      JSON.parse(Buffer.from(p[1]!, 'base64url').toString()).app_metadata
        ?.staff_session_version ?? 0
    return Number.isSafeInteger(n) && n >= 0 ? n : -1
  } catch {
    return -1
  }
}
