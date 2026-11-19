import { createServerClient } from '@supabase/ssr'
import type { H3Event } from 'h3'
export async function reportingRequest(event: H3Event, queryOverride?: Record<string, string>): Promise<unknown> {
  await requireStaff(event, ['superadmin', 'admin'])
  const config = useRuntimeConfig(event)
  const sb = createServerClient(
    config.supabaseUrl as string,
    config.supabaseAnonKey as string,
    {
      cookies: {
        getAll: () =>
          Object.entries(parseCookies(event)).map(([name, value]) => ({
            name,
            value,
          })),
        setAll: (list: { name: string; value: string; options?: Parameters<typeof setCookie>[3] }[]) =>
          list.forEach(({ name, value, options }) =>
            setCookie(event, name, value, { ...options, path: options?.path ?? '/' }),
          ),
      },
    },
  )
  const {
    data: { session },
  } = await sb.auth.getSession()
  if (!session) throw createError({ statusCode: 401 })
  const source = queryOverride ?? getQuery(event) ?? {},
    query = Object.fromEntries(
      ['from', 'to', 'cashier', 'format', 'paged', 'offset', 'as_of']
        .filter((k) => typeof source[k] === 'string')
        .map((k) => [k, source[k]]),
    )
  setHeader(event, 'Cache-Control', 'no-store')
  const options = {
      timeout: 15000,
      retry: 0,
      query,
      headers: { ...backendProxyHeaders(event), Authorization: `Bearer ${session.access_token}` },
    },
    url = String(config.goApiUrl).replace(/\/$/, '') + '/api/v1/admin/reports'
  if (query.format === 'csv') {
    setHeader(event, 'Content-Type', 'text/csv; charset=utf-8')
    setHeader(
      event,
      'Content-Disposition',
      'attachment; filename="teraskayumanis-payments.csv"',
    )
    return await $fetch(url, { ...options, responseType: 'text' })
  }
  return await $fetch<unknown>(url, options)
}
