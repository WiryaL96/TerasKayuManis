// Explicit retirement response for older dashboard clients.
export default defineEventHandler(async (event) => {
  await sensitiveRequest(event, 6)
  await requireStaff(event, ['superadmin', 'admin'])
  throw createError({statusCode:410,statusMessage:'Tautan staf tidak digunakan lagi. Atur password langsung di halaman Staf.'})
})
