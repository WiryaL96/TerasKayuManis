export default defineEventHandler(async (event) => {
  const me = await requireStaff(event,['superadmin','admin'])
  setHeader(event, 'Cache-Control', 'no-store')
  return { email: me.email, profile: { id: me.id, full_name: me.full_name, role: me.role, session_version: me.session_version } }
})
