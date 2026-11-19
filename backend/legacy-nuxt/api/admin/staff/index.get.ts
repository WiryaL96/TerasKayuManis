export default defineEventHandler(async event=>{
 const actor=await requireStaff(event,['superadmin','admin']);setHeader(event,'Cache-Control','no-store')
 return completeRows((a,b)=>serviceClient(event).from('profiles').select('id,full_name,email,username,role,staff_status,created_at,cashier_pin_enabled,staff_photo_path,archived_at',{count:'exact'}).in('role',actor.role==='superadmin'?['admin','cashier']:['cashier']).order('created_at',{ascending:false}).order('id').range(a,b))
})
