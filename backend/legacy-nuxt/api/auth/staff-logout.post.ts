export default defineEventHandler(async (event) => {
  await sensitiveRequest(event, 30)
  const bearer = getHeader(event, 'authorization')
  let actor: {id:string}
  if (bearer) {
    if (!bearer.startsWith('Bearer ') || bearer.length > 8192) throw createError({statusCode:401})
    const sb = serviceClient(event)
    const token = bearer.slice(7)
    const {data:{user},error:authError} = await sb.auth.getUser(token)
    if (authError || !user) throw createError({statusCode:401})
    const {data:profile,error:profileError} = await sb.from('profiles').select('id,role,staff_status,session_version').eq('id',user.id).single()
    if(profileError || !profile || profile.staff_status!=='active' || !['cashier','admin','superadmin'].includes(profile.role) || staffVersion(token)!==profile.session_version) throw createError({statusCode:403})
    actor = profile
  } else actor = await requireStaff(event)
  const { error } = await serviceClient(event).from('staff_audit').insert({
    actor_id: actor.id, action: 'staff_logout_requested',
  })
  if (error) throw createError({ statusCode: 503, statusMessage: 'Catatan keluar belum tersimpan.' })
  return { ok: true }
})
