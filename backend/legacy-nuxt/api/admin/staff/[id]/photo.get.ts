import {canManageStaffRole} from '#shared/staff-roles'
export default defineEventHandler(async event=>{
 const actor=await requireStaff(event,['superadmin','admin']),result=await serviceClient(event).from('profiles').select('role,staff_photo_path').eq('id',getRouterParam(event,'id')).maybeSingle()
 if(result.error||!result.data||!canManageStaffRole(actor.role,result.data.role))throw createError({statusCode:403,statusMessage:'Foto tidak tersedia.'})
 return staffPhotoResponse(event,result.data.staff_photo_path)
})
