import { AUDIT_ACTIONS } from '#shared/staff-audit'

// Dates are inclusive calendar dates in WIB; database bounds are UTC instants.
export function auditQuery(query: Record<string, unknown>) {
  const validDay = (value: unknown) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value
  if (!validDay(query.from) || !validDay(query.to))
    throw createError({ statusCode: 400, statusMessage: 'Pilih tanggal awal dan akhir yang valid.' })
  const start = Date.parse(String(query.from)), end = Date.parse(String(query.to))
  if (end < start || end - start > 30 * 86400_000)
    throw createError({ statusCode: 400, statusMessage: 'Pilih rentang maksimal 31 hari.' })
  const actor = query.actor ?? '', action = query.action ?? '', offset = query.offset ?? '0'
  if (typeof actor !== 'string' || (actor && !/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(actor)) ||
    typeof action !== 'string' || (action && !Object.hasOwn(AUDIT_ACTIONS, action)) ||
    typeof offset !== 'string' || !/^\d{1,6}$/.test(offset) || Number(offset) > 100000) {
    throw createError({ statusCode: 400, statusMessage: 'Filter aktivitas tidak valid.' })
  }
  return { from: new Date(start - 7 * 3600_000).toISOString(),
    to: new Date(end + 17 * 3600_000).toISOString(), actor, action, offset: Number(offset), limit: 50 }
}

export function safeAuditDetails(value: unknown) {
  const source = value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
  const result: Record<string, string | number | boolean | null> = {}
  // Explicitly whitelist values: no tokens, private links, emails or raw snapshots.
  for (const key of ['order_number', 'area', 'total', 'received', 'change', 'before_total', 'tax', 'service', 'orders_enabled', 'role', 'before_role', 'after_role']) {
    const v = source[key]
    if (['total', 'received', 'change', 'before_total'].includes(key) &&
      !(typeof v === 'number' && Number.isSafeInteger(v) && v >= 0) &&
      !(typeof v === 'string' && /^\d{1,16}$/.test(v))) continue
    if (v === null || typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v)) ||
      (typeof v === 'string' && v.length <= 100)) result[key] = v
  }
  for (const side of ['before', 'after']) {
    const row = source[side] as Record<string, unknown> | undefined
    if (!row || typeof row !== 'object') continue
    for (const key of ['full_name', 'staff_status']) {
      const v = row[key]
      if (typeof v === 'string' && v.length <= 100) result[`${side}_${key}`] = v
    }
  }
  return result
}
