import type {H3Event} from 'h3'
import type {Profile} from '#shared/types'
import {canManageStaffRole} from '#shared/staff-roles'

export async function saveStaffPassword(event:H3Event,actor:Pick<Profile,'id'|'role'>,profile:any,password:string,method:'pin'|'password'='password',finish='finish_staff_credential',updateEmail=false){
  if(actor.id===profile.id||!canManageStaffRole(actor.role,profile.role))throw createError({statusCode:403,statusMessage:'Anda tidak dapat mengelola akun ini.'})
  const sb=serviceClient(event)
  const identity=await sb.auth.admin.getUserById(profile.id)
  if(identity.error&&identity.error.status!==404)throw createError({statusCode:503,statusMessage:'Identitas akun belum dapat diperiksa. Akun belum diaktifkan.'})
  if(!updateEmail&&identity.data?.user&&identity.data.user.email?.toLowerCase()!==profile.email?.toLowerCase())throw createError({statusCode:409,statusMessage:'Email profil berbeda dari identitas akun. Hubungi superadmin.'})
  const metadata={...identity.data?.user?.app_metadata,staff_session_version:profile.session_version,staff_access_method:method}
  const result=identity.data?.user
    ?await sb.auth.admin.updateUserById(profile.id,{password,...(updateEmail?{email:profile.email}:{}),email_confirm:true,app_metadata:metadata})
    :await sb.auth.admin.createUser({id:profile.id,email:profile.email,password,email_confirm:true,app_metadata:metadata})
  if(result.error||result.data.user?.id!==profile.id){
    // Only discard a brand-new reservation after a definite Auth validation failure.
    if(!identity.data?.user&&profile.session_version===1&&[400,409,422].includes(result.error?.status||0))await sb.rpc('discard_staff_reservation',{p_actor:actor.id,p_target:profile.id})
    throw createError({statusCode:result.error?.status&&result.error.status>=500?503:409,statusMessage:'Akun belum siap. Email mungkin sudah digunakan atau password ditolak. Periksa daftar staf sebelum mencoba lagi.'})
  }
  const completed=await sb.rpc(finish,{p_actor:actor.id,p_target:profile.id,p_version:profile.session_version,p_method:method})
  if(completed.error||!completed.data)throw createError({statusCode:409,statusMessage:'Pengaturan akun belum selesai atau akun berubah. Muat ulang daftar lalu atur password kembali.'})
  const p=completed.data
  return {id:p.id,full_name:p.full_name,email:p.email,username:p.username,role:p.role,staff_status:p.staff_status,cashier_pin_enabled:p.cashier_pin_enabled===true}
}
