export default defineEventHandler(async event => {
  await sensitiveRequest(event, 60)
  const actor = await requireStaff(event, ['superadmin', 'admin'])
  const body = await readBody(event)
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  if (!body || !uuid.test(body.first) || !uuid.test(body.second) || !Number.isSafeInteger(body.first_order) || !Number.isSafeInteger(body.second_order))
    throw createError({ statusCode: 400, statusMessage: 'Urutan kategori tidak valid.' })
  const { error } = await serviceClient(event).rpc('swap_catalog_categories', {
    p_actor: actor.id, p_first: body.first, p_second: body.second,
    p_first_order: body.first_order, p_second_order: body.second_order,
  })
  if (error) throw createError({ statusCode: error.code === '42501' ? 403 : 409, statusMessage: 'Urutan berubah atau belum dapat disimpan. Muat ulang daftar lalu coba lagi.' })
  return { ok: true }
})
