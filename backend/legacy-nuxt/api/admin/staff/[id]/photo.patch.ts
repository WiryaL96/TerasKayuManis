export default defineEventHandler(async event=>{
 await sensitiveRequest(event,12)
 const actor=await requireStaff(event,['superadmin','admin']),body=await readBody<Record<string,unknown>>(event)
 if(!body||Object.keys(body).some(k=>k!=='path')||(body.path!==null&&(typeof body.path!=='string'||!body.path.startsWith(actor.id+'/')||!/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.webp$/.test(body.path))))throw createError({statusCode:400,statusMessage:'Foto staf tidak valid.'})
 const result=await serviceClient(event).rpc('set_staff_photo',{p_actor:actor.id,p_target:getRouterParam(event,'id'),p_path:body.path})
 if(result.error)throw createError({statusCode:result.error.code==='42501'?403:409,statusMessage:'Foto belum dapat diperbarui.'})
 return {ok:true}
})
