export default defineEventHandler(async(event)=>{
 await requireStaff(event,['superadmin','admin']);setHeader(event,'Cache-Control','no-store')
 const sb=serviceClient(event)
 const [settings,categories,products,addons]=await Promise.all([
 sb.from('settings').select('*').eq('id',1).single(),
 completeRows((a,b)=>sb.from('categories').select('*',{count:'exact'}).order('sort_order').order('id').range(a,b)),
 completeRows((a,b)=>sb.from('products').select('*,variants:product_variants(*),product_addons(addons(*))',{count:'exact'}).order('name').order('id').range(a,b)),
 completeRows((a,b)=>sb.from('addons').select('*',{count:'exact'}).order('name').order('id').range(a,b))])
 if(settings.error||!settings.data)throw createError({statusCode:503,statusMessage:'Katalog gagal dimuat.'})
 return {settings:settings.data,categories,addons,products:products.map(p=>({...p,addons:p.product_addons.map((a:any)=>a.addons),product_addons:undefined}))}
})
