export function bootstrapConfig(values, env) {
  const url = env.SUPABASE_URL || env.NUXT_SUPABASE_URL
  const key = env.SUPABASE_SERVICE_ROLE_KEY || env.NUXT_SUPABASE_SERVICE_KEY
  const site = env.SITE_URL || env.NUXT_SITE_URL
  const name = values.name?.trim(), email = values.email?.trim().toLowerCase()
  if (!url || !key || !site || !values.project || !values.output || !name || name.length < 2 || name.length > 100 || /[\u0000-\u001f\u007f]/.test(name) || !email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Invalid bootstrap configuration')
  const api = new URL(url), origin = new URL(site)
  const cleanOrigin = value => !value.username && !value.password && !value.search && !value.hash && value.pathname === '/'
  const local = values.local === true && origin.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(origin.hostname)
  if (api.protocol !== 'https:' || api.hostname !== values.project + '.supabase.co' || api.port || !cleanOrigin(api) || !cleanOrigin(origin) || (origin.protocol !== 'https:' && !local)) throw new Error('Project or site origin mismatch')
  return { url: api.origin, key, site: origin.origin, name, email }
}
