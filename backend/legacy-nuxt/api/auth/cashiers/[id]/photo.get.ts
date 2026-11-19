export default defineEventHandler(async event=>{
 const result=await serviceClient(event).from('profiles').select('staff_photo_path').eq('id',getRouterParam(event,'id')).eq('role','cashier').eq('staff_status','active').eq('cashier_pin_enabled',true).maybeSingle()
 if(result.error||!result.data)throw createError({statusCode:404,statusMessage:'Foto tidak tersedia.'})
 return staffPhotoResponse(event,result.data.staff_photo_path)
})
