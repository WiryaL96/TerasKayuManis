export default defineEventHandler(async(event)=>{
 await requireStaff(event)
 throw createError({statusCode:405,statusMessage:'Gunakan review, konfirmasi tunai, dan penyelesaian melalui API kasir.'})
})
