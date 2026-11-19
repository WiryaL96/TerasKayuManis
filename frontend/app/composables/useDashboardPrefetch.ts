import { normalizeCatalog, normalizeStaff, normalizeReport, normalizeActivity, normalizeSettings, normalizeDashboard } from '#shared/dashboard-data'
import { dashboardPeriod } from '#shared/dashboard'
import { wibToday } from '#shared/operations'
export function useDashboardPrefetch() {
  const { cache } = useDashboardCache(), { can } = useAdmin()
  let pending = 0
  return async (path: string) => {
    if (!cache.scope || pending >= 2 || typeof navigator === 'undefined') return
    const connection = (navigator as Navigator & { connection?: { saveData?:boolean; effectiveType?:string } }).connection
    if (connection?.saveData || ['slow-2g','2g'].includes(connection?.effectiveType || '')) return
    if (['/admin/activity','/admin/settings'].includes(path) && !can(['superadmin'])) return
    const today = wibToday(), period = dashboardPeriod(7, today)
    const config = ['/admin/products','/admin/categories','/admin/addons'].includes(path)
      ? { key:'catalog',url:'/api/admin/catalog',query:undefined,normalize:normalizeCatalog,staleTime:300000 }
      : path === '/admin/staff' ? { key:'staff',url:'/api/admin/staff',query:undefined,normalize:normalizeStaff,staleTime:60000 }
      : path === '/admin/reports' ? { key:`report:${today}:${today}:`,url:'/api/admin/reports',query:{from:today,to:today,cashier:''},normalize:normalizeReport,staleTime:60000 }
      : path === '/admin/activity' ? { key:`activity:${today}:${today}:::0`,url:'/api/admin/activity',query:{from:today,to:today,actor:'',action:'',offset:0},normalize:normalizeActivity,staleTime:30000 }
      : path === '/admin/settings' ? { key:'settings',url:'/api/admin/crud/settings',query:undefined,normalize:(v:unknown) => { if (!Array.isArray(v) || !v.length) throw Object.assign(new Error('Pengaturan tidak lengkap'),{invalidData:true}); return normalizeSettings(v[0]) },staleTime:60000 }
      : path === '/admin' ? { key:`dashboard:${period.from}:${period.to}`,url:'/api/admin/dashboard',query:period,normalize:normalizeDashboard,staleTime:60000 } : null
    if (!config) return
    pending++
    try { await cache.fetch<unknown>(config.key, async signal => config.normalize(await $fetch(config.url,{query:config.query,signal,timeout:15000,retry:0})),{staleTime:config.staleTime,retries:1}) } catch { /* Destination handles a failed prefetch. */ }
    finally { pending-- }
  }
}
