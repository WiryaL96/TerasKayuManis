export default defineEventHandler(async (event) => {
  await sensitiveRequest(event,60)
  await requireStaff(event, ['superadmin', 'admin'])
  throw createError({statusCode:410,statusMessage:'Restoran memakai satu QR bersama. Buka /menu.'})
})
