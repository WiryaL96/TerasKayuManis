import type { StaffRole, Profile } from '#shared/types'
import { normalizeProfile } from '#shared/dashboard-data'
import { isAccessError } from '#shared/query-cache'
interface AdminMe { email: string; profile: Profile }
const requests = new WeakMap<object, { generation: number; promise: Promise<AdminMe> }>()
export function useAdmin() {
  const app = useNuxtApp(), store = useDashboardCache()
  const me = useState<AdminMe | null>('admin-me', () => null)
  const generation = useState<number>('admin-me-generation', () => 0)
  const checkedAt = useState<number>('admin-me-checked', () => 0)
  function reset() { generation.value++; me.value = null; checkedAt.value = 0; store.cache.bind('') }
  async function load(force = false): Promise<AdminMe> {
    if (!force && me.value && Date.now() - checkedAt.value < 60000) return me.value
    const running = requests.get(app)
    if (running?.generation === generation.value) return running.promise
    const seq = generation.value
    const promise = (async () => {
      try {
        const result = await $fetch<AdminMe>('/api/admin/me', { timeout: 15000, retry: 0 })
        const identity = { email:result.email, profile:normalizeProfile(result.profile) }
        if (seq === generation.value) { store.bind(identity.profile); me.value = identity; checkedAt.value = Date.now() }
        return identity
      } catch (error) {
        if (seq === generation.value) {
          if (isAccessError(error)) reset()
          else if (me.value) return me.value
        }
        throw error
      } finally { if (requests.get(app)?.generation === seq) requests.delete(app) }
    })()
    requests.set(app, { generation:seq, promise })
    return promise
  }
  async function logout() { await useStaffAuth().logout(); await navigateTo('/admin/login') }
  const can = (roles: StaffRole[]) => !!me.value && roles.includes(me.value.profile.role)
  return { me, load, logout, can, reset }
}
