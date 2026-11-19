// Shared-QR checkout requires an idempotency key and an order access token.
export default defineEventHandler(()=>{
 throw createError({statusCode:410,statusMessage:'Gunakan /api/core/orders untuk membuat pesanan.'})
})
