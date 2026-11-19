import type { StaffActivityPage, StaffActivity } from '#shared/staff-audit'

export default defineEventHandler(async (event): Promise<StaffActivityPage> => {
  await requireStaff(event, ['superadmin'])
  setHeader(event, 'Cache-Control', 'no-store')
  const filter = auditQuery(getQuery(event)), sb = serviceClient(event)
  let request = sb.from('staff_audit')
    .select('id,actor_id,actor_name,actor_role,target_name,order_id,action,details,created_at', { count: 'exact' })
    .gte('created_at', filter.from).lt('created_at', filter.to)
    .order('created_at', { ascending: false }).order('id', { ascending: false })
  if (filter.actor) request = request.eq('actor_id', filter.actor)
  if (filter.action) request = request.eq('action', filter.action)
  const [activities, staff] = await Promise.all([
    request.range(filter.offset, filter.offset + filter.limit - 1),
    completeRows((a,b)=>sb.from('profiles').select('id,full_name,role',{count:'exact'}).in('role', ['superadmin', 'admin', 'cashier']).order('full_name').order('id').range(a,b)),
  ])
  if (activities.error)
    throw createError({ statusCode: 503, statusMessage: 'Log belum dapat dimuat. Periksa koneksi atau hubungi pengelola server.' })
  return { entries: (activities.data ?? []).map(row => ({ ...row, details: safeAuditDetails(row.details) })) as StaffActivity[],
    total: activities.count ?? 0, limit: filter.limit, staff }
})
