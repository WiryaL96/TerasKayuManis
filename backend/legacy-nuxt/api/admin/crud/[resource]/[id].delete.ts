export default defineEventHandler(async (event) => {
  await sensitiveRequest(event,60)
  await requireStaff(event, ['superadmin', 'admin'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const id = getRouterParam(event, 'id') ?? ''
  if (!CRUD_RESOURCES[resource] || resource === 'settings') {
    throw createError({ statusCode: 404, statusMessage: 'Tidak dapat menghapus data ini.' })
  }
  const { data, error } = await serviceClient(event).from(resource).delete().eq('id', id).select('id')
  if (error) throw createError({ statusCode: 400, statusMessage: 'Gagal menghapus. Data mungkin masih dipakai.' })
  if (!data?.length) throw createError({ statusCode: 404, statusMessage: 'Data tidak ditemukan. Muat ulang daftar.' })
  return { ok: true }
})
