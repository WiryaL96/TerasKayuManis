import { createQueryCache, isAccessError } from '#shared/query-cache'
import type { QueryCache } from '#shared/query-cache'
import type { Profile } from '#shared/types'

// WeakMap keys are Nuxt app instances, never shared between server requests.
const clients = new WeakMap<object, { cache: QueryCache; revision: Ref<number> }>()
export function useDashboardCache() {
  const app = useNuxtApp()
  let client = clients.get(app)
  if (!client) {
    const revision = ref(0)
    const cache = createQueryCache({ changed: () => { revision.value++ }, accessDenied: () => {
      app.runWithContext(() => {
        useState('admin-me', () => null).value = null; useState('admin-me-generation', () => 0).value++
        const path=useRoute().path
        if(path==='/admin'||path.startsWith('/admin/'))void Promise.resolve(navigateTo('/admin/login?reason=session')).catch(()=>{})
      })
    } })
    client = { cache, revision }; clients.set(app, client)
  }
  const { cache, revision } = client
  function bind(profile: Pick<Profile, 'id' | 'role' | 'session_version'>) {
    cache.bind(`${profile.id}:${profile.role}:${profile.session_version ?? 0}`)
  }
  function changed(area: 'catalog' | 'staff' | 'orders' | 'settings') {
    const prefixes = area === 'catalog' ? ['catalog', 'cashier-menu', 'dashboard:'] : area === 'staff' ? ['staff', 'activity:', 'dashboard:'] : area === 'settings' ? ['settings', 'catalog', 'cashier-menu', 'dashboard:', 'activity:'] : ['orders:', 'report:', 'receipt:', 'dashboard:', 'activity:']
    prefixes.forEach(prefix => cache.invalidate(prefix))
  }
  async function mutation<T>(action: () => Promise<T>): Promise<T> {
    try { return await action() } catch (error) { if (isAccessError(error)) cache.deny(); throw error }
  }
  return { cache, revision, bind, changed, mutation }
}
