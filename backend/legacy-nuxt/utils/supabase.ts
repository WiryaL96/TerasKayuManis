import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'
import type { H3Event } from 'h3'
import type { Profile, StaffRole } from '#shared/types'

export function serviceClient(event: H3Event, signal?: AbortSignal) {
  const config = useRuntimeConfig(event)
  const url = config.supabaseUrl as string
  const key = config.supabaseServiceKey as string
  if (!url || !key) {
    throw createError({ statusCode: 500, statusMessage: 'Server belum dikonfigurasi. Isi env Supabase.' })
  }
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: signal ? (input, options) => staffFetch(input, {...options, signal: options?.signal ? AbortSignal.any([signal, options.signal]) : signal}) : staffFetch } })
}

// Deduplicate identity checks inside one HTTP request only. Never cache across
// requests: disabling a staff account must take effect on the next action.
const staffRequests = new WeakMap<H3Event, Promise<Profile & { email: string }>>()
export async function requireStaff(event: H3Event, roles?: StaffRole[]): Promise<Profile & { email: string }> {
  let pending = staffRequests.get(event)
  if (!pending) { pending = loadStaff(event); staffRequests.set(event, pending) }
  const profile = await pending
  if (roles && !roles.includes(profile.role)) throw createError({ statusCode: 403, statusMessage: 'Anda tidak memiliki akses.' })
  return profile
}
async function loadStaff(event: H3Event): Promise<Profile & { email: string }> {
  const config = useRuntimeConfig(event)
  const sb = createServerClient(config.supabaseUrl as string, config.supabaseAnonKey as string, {
    global: { fetch: staffFetch },
    cookies: {
      getAll: () => Object.entries(parseCookies(event)).map(([name, value]) => ({ name, value })),
      setAll: (list: { name: string; value: string; options?: Parameters<typeof setCookie>[3] }[]) =>
        list.forEach(({ name, value, options }) => setCookie(event, name, value, { ...options, path: options?.path ?? '/' }))
    }
  })
  const { data: { user } } = await sb.auth.getUser()
  if (!user) throw createError({ statusCode: 401, statusMessage: 'Silakan login terlebih dahulu.' })

  const { data: profile } = await serviceClient(event)
    .from('profiles').select('*').eq('id', user.id).single()
  const {data:{session}}=await sb.auth.getSession()
  if (!profile || !['superadmin','admin','cashier'].includes(profile.role) || profile.staff_status!=='active' || !session || staffVersion(session.access_token)!==profile.session_version) {
    throw createError({ statusCode: 403, statusMessage: 'Anda tidak memiliki akses.' })
  }
  return { ...profile, email: user.email ?? '' }
}
