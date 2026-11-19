// The migration middleware already retires this URL; keep the handler safe too.
export default defineEventHandler(()=>{
 throw createError({statusCode:410,statusMessage:'Gunakan /api/core/orders untuk melihat pesanan.'})
})
