export default defineEventHandler(async (event) => {
  await sensitiveRequest(event,60)
  await requireStaff(event, ['superadmin', 'admin'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const id = getRouterParam(event, 'id') ?? ''
  const def = CRUD_RESOURCES[resource]
  if(resource==='settings')await requireStaff(event,['superadmin'])
  if (!def || def.fields.length === 0) throw createError({ statusCode: 404, statusMessage: 'Resource tidak ditemukan.' })

  const body = await readBody<Record<string, unknown>>(event)
  const values = checkedCrudValues(resource, body)
  if (Object.keys(values).length === 0) throw createError({ statusCode: 400, statusMessage: 'Tidak ada perubahan.' })

  const rowId = resource === 'settings' ? 1 : id
  const { data, error } = await serviceClient(event).from(resource).update(values).eq('id', rowId).select().single()
  if (error || !data) throw createError({ statusCode: 400, statusMessage: 'Gagal memperbarui data.' })
  return data
})
