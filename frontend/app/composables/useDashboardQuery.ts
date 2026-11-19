export interface DashboardQuery<T> {
  key: string; url: string; query?: Record<string, string | number | undefined>
  staleTime?: number; normalize: (value: unknown) => T
}
export function useDashboardQuery<T>(definition: () => DashboardQuery<T>, options: { auto?: boolean; interval?: number } = {}) {
  const { cache, revision } = useDashboardCache()
  const key = computed(() => definition().key)
  const snapshot = computed(() => { void revision.value; return cache.peek<T>(key.value) })
  const data = computed(() => snapshot.value.data)
  const loading = computed(() => snapshot.value.fetching)
  const error = computed(() => {
    const e: any = snapshot.value.error
    return e ? e.data?.statusMessage || 'Data belum dapat diperbarui. Periksa koneksi lalu coba lagi.' : ''
  })
  const updatedAt = computed(() => snapshot.value.updatedAt)
  let controller: AbortController | undefined, disposed = false, timer: ReturnType<typeof setInterval> | undefined
  let current: Promise<T|null> | undefined, currentKey=''
  function load(force = false): Promise<T|null> {
    if (disposed) return Promise.resolve(null)
    const config = definition()
    if(current&&currentKey===config.key&&!controller?.signal.aborted&&cache.peek(config.key).fetching)return current
    controller?.abort(); controller = new AbortController()
    const active=controller;currentKey=config.key
    current=(async()=>{
      try {
        return await cache.fetch(config.key, async signal => config.normalize(await $fetch(config.url, { query: config.query, signal, timeout: 15000, retry: 0 })), { signal: active.signal, force, staleTime: config.staleTime })
      } catch { return null }
      finally{if(controller===active)current=undefined}
    })()
    return current
  }
  const refresh = () => load(true)
  const visible = () => { if (document.visibilityState === 'visible'&&(options.auto!==false||data.value!==null)) void load() }
  const online = () => { if(options.auto!==false||data.value!==null)void load() }
  watch(key, () => { controller?.abort(); if (options.auto !== false) void load() }, { flush: 'sync' })
  onMounted(() => {
    if (options.auto !== false) void load()
    document.addEventListener('visibilitychange', visible); window.addEventListener('online', online)
    if (options.interval) timer = setInterval(visible, options.interval)
  })
  onUnmounted(() => { disposed = true; controller?.abort(); clearInterval(timer); document.removeEventListener('visibilitychange', visible); window.removeEventListener('online', online) })
  return { data, loading, error, updatedAt, load, refresh }
}
