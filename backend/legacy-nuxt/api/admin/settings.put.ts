export default defineEventHandler(async event=>{
 await sensitiveRequest(event)
 const actor=await requireStaff(event,['superadmin']),b=await readBody<Record<string,unknown>>(event)
 if(!b||Array.isArray(b)||Object.keys(b).some(k=>!['brand_name','tagline','tax_pct','service_pct','require_customer_name','orders_enabled'].includes(k))||typeof b.brand_name!=='string'||!b.brand_name.trim()||b.brand_name.length>50||typeof b.tagline!=='string'||b.tagline.length>100||[b.brand_name,b.tagline].some(v=>/[\u0000-\u001f\u007f]/.test(v))||!['tax_pct','service_pct'].every(k=>typeof b[k]==='number'&&Number.isFinite(b[k])&&Number(b[k])>=0&&Number(b[k])<=100)||typeof b.require_customer_name!=='boolean'||typeof b.orders_enabled!=='boolean')throw createError({statusCode:400,statusMessage:'Isi nama restoran dan tarif 0–100% yang valid.'})
 const {data,error}=await serviceClient(event).rpc('save_restaurant_settings',{p_actor:actor.id,p_brand:b.brand_name,p_tagline:b.tagline,p_tax:b.tax_pct,p_service:b.service_pct,p_name_required:b.require_customer_name,p_enabled:b.orders_enabled})
 if(error)throw createError({statusCode:400,statusMessage:'Pengaturan tidak tersimpan. Periksa tarif dan pastikan ada kasir personal aktif sebelum membuka pesanan.'})
 return data
})
