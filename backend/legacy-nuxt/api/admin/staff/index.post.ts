import { randomUUID } from 'node:crypto'
export default defineEventHandler(async (event) => {
  await sensitiveRequest(event)
  const actor = await requireStaff(event, ['superadmin', 'admin']),
    body = checkedStaffInput(await readBody(event), actor.role),
    sb = serviceClient(event)
  const id = randomUUID()
  const credential=body.pin!==undefined?cashierPinPassword(event,id,body.pin):body.password!
  if(body.photo_path&&!body.photo_path.startsWith(actor.id+'/'))throw createError({statusCode:400,statusMessage:'Foto harus berasal dari unggahan akun Anda.'})
  const { data:profile,error: insertError } = await sb.rpc('reserve_staff_account', {
    p_actor: actor.id, p_id: id, p_name: body.full_name, p_email: body.email, p_username:body.username,p_role: body.role,
  })
  if (insertError)
    throw createError({
      statusCode: insertError.code === '42501' ? 403 : 409,
      statusMessage:
        'Username/email sudah digunakan atau akun belum dapat dibuat. Periksa daftar staf.',
    })
  if(body.photo_path){
    const photo=await sb.rpc('set_staff_photo',{p_actor:actor.id,p_target:id,p_path:body.photo_path})
    if(photo.error)throw createError({statusCode:409,statusMessage:'Foto belum tersimpan. Periksa daftar staf lalu lengkapi foto dan akses akun.'})
  }
  return {profile:await saveStaffPassword(event,actor,profile,credential,body.pin!==undefined?'pin':'password')}
})
