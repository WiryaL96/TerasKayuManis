import type { MenuResponse } from '#shared/types'
// Keyed by Nuxt app so SSR requests never share catalog state or cancellation.
const flights = new WeakMap<object, { promise: Promise<void>; controller: AbortController }>()

export function useMenu() {
  const app = useNuxtApp()
  const menu = useState<MenuResponse | null>('menu', () => null)
  const loading = useState('menu-loading', () => false)
  const request = useState('menu-request', () => 0)
  const updatedAt = useState('menu-updated-at', () => 0)
  const focused=()=>{if(document.visibilityState==='visible')void load().catch(()=>{/* retain last catalog */})}
  let refreshTimer:ReturnType<typeof setInterval>|undefined
  if(typeof onMounted==='function'&&typeof onUnmounted==='function'){
    onMounted(()=>{document.addEventListener('visibilitychange',focused);refreshTimer=setInterval(focused,60000)})
    onUnmounted(()=>{document.removeEventListener('visibilitychange',focused);clearInterval(refreshTimer)})
  }

  async function load(force = false) {
    const running = flights.get(app)
    if (!force && running) return running.promise
    if (menu.value && !force && Date.now() - updatedAt.value < 30_000) return
    running?.controller.abort()
    const controller = new AbortController()
    const id = ++request.value
    loading.value = true
    const promise = (async () => { try {
      const result = await $fetch<MenuResponse>('/api/core/menu', { signal: controller.signal, timeout: 10_000, retry: 1, retryDelay: 500 })
      if (id !== request.value) throw new Error('Catalog request superseded')
      menu.value = result
      updatedAt.value = Date.now()
    } finally {
      if (id === request.value) { loading.value = false; flights.delete(app) }
    } })()
    flights.set(app, { promise, controller })
    return promise
  }

  return { menu, loading, load }
}
