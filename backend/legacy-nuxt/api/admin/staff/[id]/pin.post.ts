export default defineEventHandler(async event=>{
 await sensitiveRequest(event,6)
 const actor=await requireStaff(event,['superadmin','admin']),target=getRouterParam(event,'id'),body=await readBody<Record<string,unknown>>(event)
 if(!target||!body||Object.keys(body).some(k=>!['pin','reactivate'].includes(k))||(body.reactivate!==undefined&&typeof body.reactivate!=='boolean'))throw createError({statusCode:400,statusMessage:'Pengaturan PIN tidak valid.'})
 const password=cashierPinPassword(event,target,checkedCashierPin(body.pin)),sb=serviceClient(event)
 const account=await sb.from('profiles').select('role').eq('id',target).maybeSingle()
 if(account.error)throw createError({statusCode:503,statusMessage:'Akun belum dapat diperiksa.'})
 if(account.data?.role!=='cashier')throw createError({statusCode:403,statusMessage:'PIN hanya untuk akun kasir.'})
 const result=await sb.rpc('begin_staff_password',{p_actor:actor.id,p_target:target,p_reactivate:body.reactivate===true})
 if(result.error||!result.data)throw createError({statusCode:result.error?.code==='42501'?403:409,statusMessage:'PIN belum dapat diperbarui. Periksa status akun.'})
 return {profile:await saveStaffPassword(event,actor,result.data,password,'pin')}
})
