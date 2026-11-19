import type { DashboardData } from '#shared/dashboard'
import { wibToday } from '#shared/operations'
export default defineEventHandler(async(event):Promise<DashboardData>=>{
 const actor=await requireStaff(event,['superadmin','admin'])
 setHeader(event,'Cache-Control','no-store')
 const query=getQuery(event),from=query.from??wibToday(),to=query.to??from
 if(typeof from!=='string'||typeof to!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to))throw createError({statusCode:400,statusMessage:'Pilih tanggal yang valid.'})
 const {data,error}=await serviceClient(event).rpc('dashboard_snapshot',{p_actor:actor.id,p_from:from,p_to:to})
 if(error||!data)throw createError({statusCode:error?.code==='22023'?400:503,statusMessage:error?.code==='PGRST202'?'Pembaruan database untuk dashboard ini belum diterapkan. Hubungi pengelola sebelum mengaktifkan rilis baru.':'Ringkasan belum dapat diperbarui. Periksa rentang tanggal dan koneksi.'})
 return data as DashboardData
})
