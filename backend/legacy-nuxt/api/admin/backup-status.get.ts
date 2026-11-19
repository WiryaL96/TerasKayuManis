export default defineEventHandler(async (event) => {
  await requireStaff(event, ['superadmin'])
  setHeader(event, 'Cache-Control', 'no-store')
  return readBackupStatus(event)
})
