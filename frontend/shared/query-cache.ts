// Per-app, memory-only SWR cache. No tokens, persistent storage or shared SSR data.
export interface QuerySnapshot<T> {
  data: T | null
  updatedAt: number
  error: unknown
  fetching: boolean
  invalidated: boolean
}
type Entry = QuerySnapshot<unknown> & { revision: number; bytes: number }
type Flight = { controller: AbortController; promise: Promise<unknown>; users: number }
export const statusOf = (error: any): number => Number(error?.statusCode || error?.status || error?.response?.status || 0)
export const isAccessError = (error: unknown) => [401, 403].includes(statusOf(error))
export const isAbort = (error: any) => error?.name === 'AbortError'
const aborted = () => Object.assign(new Error('Request cancelled'), { name: 'AbortError' })

export function createQueryCache(options: {
  changed?: () => void; now?: () => number; random?: () => number
  sleep?: (ms: number, signal: AbortSignal) => Promise<void>
  accessDenied?: () => void; maxEntries?: number; maxBytes?: number
} = {}) {
  const entries = new Map<string, Entry>(), flights = new Map<string, Flight>()
  const now = options.now || Date.now, changed = () => options.changed?.()
  let scope = '', epoch = 0, revision = 0
  const sleep = options.sleep || ((ms: number, signal: AbortSignal) => new Promise<void>((resolve, reject) => {
    if (signal.aborted) return reject(aborted())
    const stop = () => { clearTimeout(timer); reject(aborted()) }
    const timer = setTimeout(() => { signal.removeEventListener('abort', stop); resolve() }, ms)
    signal.addEventListener('abort', stop, { once: true })
  }))
  function clear() {
    epoch++
    for (const flight of flights.values()) flight.controller.abort()
    flights.clear(); entries.clear(); changed()
  }
  function bind(next: string) { if (scope !== next) { scope = next; clear() } }
  function deny() { scope='';clear();options.accessDenied?.() }
  function peek<T>(key: string): QuerySnapshot<T> {
    const entry=entries.get(key)
    return entry ? { ...entry } as QuerySnapshot<T> : { data: null, updatedAt: 0, error: null, fetching: false, invalidated: true }
  }
  function trim() {
    const max = options.maxEntries ?? 64, maxBytes = options.maxBytes ?? 12 * 1024 * 1024
    let bytes = [...entries.values()].reduce((sum, e) => sum + e.bytes, 0)
    for (const [key, entry] of entries) {
      if (entries.size <= max && bytes <= maxBytes) break
      if (!flights.has(key)) { bytes -= entry.bytes; entries.delete(key) }
    }
  }
  function set<T>(key: string, data: T, stale = false) {
    if (!scope) return
    const bytes = JSON.stringify(data).length * 2
    if (bytes > (options.maxBytes ?? 12 * 1024 * 1024)) throw new Error('Dataset terlalu besar. Persempit filter.')
    entries.delete(key)
    entries.set(key, { data, updatedAt: now(), error: null, fetching: flights.has(key), invalidated: stale, revision: ++revision, bytes })
    trim(); changed()
  }
  function invalidate(prefix = '') {
    for (const [key, entry] of entries) if (key.startsWith(prefix)) {
      entry.invalidated = true; entry.revision = ++revision
      flights.get(key)?.controller.abort(); flights.delete(key); entry.fetching = false
    }
    changed()
  }
  function join<T>(flight: Flight, signal?: AbortSignal): Promise<T> {
    flight.users++
    return new Promise<T>((resolve, reject) => {
      let finished = false
      const finish = () => {
        if (finished) return false
        finished = true; signal?.removeEventListener('abort', stop)
        if (--flight.users === 0 && !finishedFlight) flight.controller.abort()
        return true
      }
      let finishedFlight = false
      const stop = () => { if (finish()) reject(aborted()) }
      if (signal?.aborted) { stop(); return }
      signal?.addEventListener('abort', stop, { once: true })
      flight.promise.then(value => { finishedFlight = true; if (finish()) resolve(value as T) }, error => { finishedFlight = true; if (finish()) reject(error) })
    })
  }
  function fetch<T>(key: string, loader: (signal: AbortSignal) => Promise<T>, config: {
    staleTime?: number; force?: boolean; signal?: AbortSignal; retries?: number
  } = {}): Promise<T> {
    if (!scope || config.signal?.aborted) return Promise.reject(aborted())
    const running = flights.get(key)
    if (running && !running.controller.signal.aborted) return join<T>(running, config.signal)
    const current = entries.get(key)
    if (!config.force && current?.data != null && !current.invalidated && now() - current.updatedAt < (config.staleTime ?? 60000)) {
      entries.delete(key); entries.set(key, current)
      return Promise.resolve(current.data as T)
    }
    const entry = current || { data: null, updatedAt: 0, error: null, fetching: false, invalidated: true, revision: ++revision, bytes: 0 }
    entries.set(key, entry)
    entry.fetching = true; entry.error = null
    const startEpoch = epoch, startRevision = entry.revision, controller = new AbortController()
    const flight: Flight = { controller, users: 0, promise: Promise.resolve() }
    flights.set(key, flight)
    const valid = () => epoch === startEpoch && entry.revision === startRevision && !controller.signal.aborted && flights.get(key) === flight
    flight.promise = (async () => {
      // Start after attaching the first consumer, so immediate failures are handled.
      await Promise.resolve()
      try {
        for (let attempt = 0; ; attempt++) {
          if (controller.signal.aborted) throw aborted()
          try {
            const data = await loader(controller.signal)
            if (!valid()) throw aborted()
            set(key, data)
            return data
          } catch (error) {
            if (!valid() || isAbort(error)) throw aborted()
            if (isAccessError(error)) { deny(); throw error }
            const status = statusOf(error)
            const retryable = status === 0 || status === 408 || status === 429 || status >= 500
            if (!retryable || attempt >= (config.retries ?? 2) || (error as any)?.invalidData) throw error
            await sleep(Math.min(8000, 500 * 2 ** attempt) * (0.75 + (options.random || Math.random)() * 0.5), controller.signal)
          }
        }
      } catch (error) {
        if (valid() && !isAbort(error)) entry.error = error
        throw error
      } finally {
        if (flights.get(key) === flight) { flights.delete(key); const latest = entries.get(key); if (latest) latest.fetching = false; trim(); changed() }
      }
    })()
    changed()
    return join<T>(flight, config.signal)
  }
  async function optimistic<T, R>(key: string, transform: (data: T) => T, action: () => Promise<R>) {
    const old = entries.get(key), startEpoch = epoch
    invalidate(key)
    if (old?.data != null) set(key, transform(structuredClone(old.data) as T), true)
    const token = entries.get(key)?.revision
    try { return await action() }
    catch (error) {
      if (startEpoch === epoch && entries.get(key)?.revision === token && old) { entries.set(key, { ...old, fetching: false, invalidated: true, error }); changed() }
      throw error
    }
  }
  return { bind, clear, deny, peek, set, invalidate, fetch, optimistic, get scope() { return scope }, get size() { return entries.size } }
}
export type QueryCache = ReturnType<typeof createQueryCache>
