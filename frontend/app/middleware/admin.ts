export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/admin/login') return
  const admin = useAdmin()
  try {
    const me = await admin.load()
    if (!['superadmin','admin'].includes(me.profile.role)) return navigateTo('/cashier')
    if (['/admin/settings','/admin/activity'].includes(to.path.replace(/\/$/, '')) && me.profile.role !== 'superadmin') return navigateTo('/admin')
  } catch {
    return navigateTo('/admin/login')
  }
})
