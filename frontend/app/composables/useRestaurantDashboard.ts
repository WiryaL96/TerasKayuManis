import { dashboardPeriod, type DashboardRange } from '#shared/dashboard'
import { normalizeDashboard } from '#shared/dashboard-data'
import { wibToday } from '#shared/operations'
export function useRestaurantDashboard() {
  const range = useState<DashboardRange>('dashboard-range', () => 7)
  const today=ref(wibToday())
  let midnight:ReturnType<typeof setInterval>|undefined
  const updateDay=()=>{today.value=wibToday()}
  onMounted(()=>{midnight=setInterval(updateDay,60000);window.addEventListener('focus',updateDay)})
  onUnmounted(()=>{clearInterval(midnight);window.removeEventListener('focus',updateDay)})
  const query = useDashboardQuery(() => {
    const period = dashboardPeriod(range.value, today.value)
    return { key:`dashboard:${period.from}:${period.to}`, url:'/api/admin/dashboard', query:period, staleTime:60000, normalize:normalizeDashboard }
  }, { interval:60000 })
  return { range, ...query }
}
