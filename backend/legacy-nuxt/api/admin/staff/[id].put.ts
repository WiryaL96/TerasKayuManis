export default defineEventHandler(async event => {
 await sensitiveRequest(event)
 const actor=await requireStaff(event,['superadmin','admin']),id=staffId(event)
 const body=await readBody(event)
 if(body&&typeof body==='object'&&'photo_path' in body)throw createError({statusCode:400,statusMessage:'Gunakan formulir foto untuk mengubah foto.'})
 const input=checkedStaffInput(body,actor.role)
 const sb=serviceClient(event)
 const result=await sb.rpc('begin_staff_edit',{p_actor:actor.id,p_target:id,p_name:input.full_name,p_email:input.email,p_username:input.username,p_role:input.role})
 if(result.error||!result.data)throw createError({statusCode:result.error?.code==='42501'?403:409,statusMessage:'Akun belum diubah. Periksa hak akses, username/email yang sudah dipakai, dan status arsip.'})
 const method='pin' in input?'pin':'password'
 const password=method==='pin'?cashierPinPassword(event,id,input.pin!):input.password!
 return {profile:await saveStaffPassword(event,actor,result.data,password,method,'finish_staff_edit',true)}
})
