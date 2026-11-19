export default defineEventHandler(async event=>{
 setHeader(event,'Cache-Control','no-store')
 const {data,error}=await serviceClient(event).from('profiles').select('id,full_name,staff_photo_path').eq('role','cashier').eq('staff_status','active').eq('cashier_pin_enabled',true).not('full_name','is',null).order('full_name')
 if(error)throw createError({statusCode:503,statusMessage:'Daftar kasir belum dapat dimuat. Coba lagi.'})
 return (data||[]).map(p=>({id:p.id,name:p.full_name,photo:p.staff_photo_path?`/api/auth/cashiers/${p.id}/photo?v=${p.staff_photo_path.split('/').at(-1)}`:null}))
})
