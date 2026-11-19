export default defineEventHandler(async (event) => {
  await sensitiveRequest(event)
  const actor = await requireStaff(event, ['superadmin', 'admin']),
    target = getRouterParam(event, 'id'),
    body = await readBody<Record<string, unknown>>(event)
  if (
    !target ||
    !body ||
    Object.keys(body).some((k) => !['command', 'full_name'].includes(k)) ||
    !['rename', 'disable', 'enable'].includes(String(body.command))
  )
    throw createError({
      statusCode: 400,
      statusMessage: 'Perubahan staf tidak valid.',
    })
  if (body.command === 'rename' && (typeof body.full_name !== 'string' || body.full_name.trim().length < 2 || body.full_name.length > 100 || /[\u0000-\u001f\u007f]/.test(body.full_name)))
    throw createError({ statusCode: 400, statusMessage: 'Isi nama lengkap 2–100 karakter.' })
  const { data, error } = await serviceClient(event).rpc('manage_staff_account', {
    p_actor: actor.id,
    p_target: target,
    p_command: body.command,
    p_name: body.full_name ?? null,
  })
  if (error)
    throw createError({
      statusCode: error.code === '42501' ? 403 : 409,
      statusMessage: 'Akun tidak dapat diperbarui. Muat ulang dan coba lagi.',
    })
  return data
})
