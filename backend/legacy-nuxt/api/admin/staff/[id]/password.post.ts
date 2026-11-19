export default defineEventHandler(async event=>{
 await sensitiveRequest(event,6)
 const actor=await requireStaff(event,['superadmin','admin']),target=getRouterParam(event,'id'),body=await readBody<Record<string,unknown>>(event)
 if(!target||!body||Object.keys(body).some(k=>!['password','reactivate'].includes(k))||(body.reactivate!==undefined&&typeof body.reactivate!=='boolean'))throw createError({statusCode:400,statusMessage:'Pengaturan password tidak valid.'})
 const password=checkedStaffPassword(body.password),sb=serviceClient(event)
 const {data:profile,error}=await sb.rpc('begin_staff_password',{p_actor:actor.id,p_target:target,p_reactivate:body.reactivate===true})
 if(error||!profile)throw createError({statusCode:error?.code==='42501'?403:409,statusMessage:'Akun tidak dapat diperbarui. Periksa peran, nama dan email staf.'})
 return {profile:await saveStaffPassword(event,actor,profile,password)}
})
