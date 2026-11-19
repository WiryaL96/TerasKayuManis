export default defineEventHandler(async event => {
 await sensitiveRequest(event)
 const actor=await requireStaff(event,['superadmin','admin']),id=staffId(event)
 const {error}=await serviceClient(event).rpc('archive_staff_account',{p_actor:actor.id,p_target:id,p_restore:false})
 if(error)throw createError({statusCode:error.code==='42501'?403:409,statusMessage:'Akun belum dapat diarsipkan. Muat ulang daftar staf.'})
 return {ok:true}
})
