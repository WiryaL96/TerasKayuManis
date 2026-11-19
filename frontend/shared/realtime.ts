// WebSocket messages only invalidate REST snapshots. Event versions are never UI data.
export type RealtimeStatus = 'connecting' | 'connected' | 'polling'
export type RealtimeScope = { channel: 'cashier' } | { channel: 'order'; order_id: string }
export type Subscription = { type: 'subscribe'; channel: 'cashier'; access_token: string }
  | { type: 'subscribe'; channel: 'order'; order_id: string; order_token: string }
export interface RealtimeSocket {
  onopen: ((event: any) => void) | null
  onmessage: ((event: MessageEvent) => void) | null
  onclose: ((event: any) => void) | null
  onerror: ((event: any) => void) | null
  send(data: string): void
  close(): void
}
export interface RealtimeOptions<T> {
  url: string | null
  scope: RealtimeScope
  subscribe: () => Promise<Subscription | null>
  fetchSnapshot: (context: { signal: AbortSignal }) => Promise<T>
  apply: (snapshot: T) => void
  onError?: (error: unknown) => void
  onStatus?: (status: RealtimeStatus) => void
  onInvalidate?: (reason: 'ready' | 'event') => void
  createSocket?: (url: string) => RealtimeSocket
  setTimeout?: (fn: () => void, ms: number) => any
  clearTimeout?: (id: any) => void
  random?: () => number
  dedupLimit?: number
  pollingOnly?: boolean
  isVisible?: () => boolean
  pollInterval?: number
  isTerminal?: () => boolean
}
export function realtimeURL(location: string): string | null {
  const url = new URL(location)
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && local)) return null
  return `${url.protocol === 'https:' ? 'wss:' : 'ws:'}//${url.host}/ws`
}
export function createRealtimeController<T>(options: RealtimeOptions<T>) {
  let active = false, generation = 0, busy = false, dirty = false, queued = false
  let request: AbortController | undefined, socket: RealtimeSocket | undefined
  const later = options.setTimeout ?? globalThis.setTimeout
  const cancel = options.clearTimeout ?? globalThis.clearTimeout
  let retry: any, deadline: any, poll: any, failures = 0
  let connected = false
  let fetchFailures=0
  function reconcile() {
    cancel(poll)
    const base=connected?30000:(options.pollInterval??(options.scope.channel==='cashier'?5000:15000))
    const delay=Math.min(60000,base*2**Math.min(fetchFailures,3)*(0.85+(options.random??Math.random)()*0.3))
    if (active&&!options.isTerminal?.()) poll = later(() => { if(options.isVisible?.()!==false)refresh(); reconcile() }, delay)
  }
  function retryConnection() {
    cancel(deadline)
    connected = false; status('polling'); reconcile()
    const delay = Math.min(30000, 1000 * 2 ** Math.min(failures++, 5) * (0.5 + (options.random ?? Math.random)()))
    cancel(retry)
    if (active) retry = later(() => { void connect() }, delay)
  }
  const seen = new Map<string, true>()
  const limit = Math.max(1, options.dedupLimit ?? 256)
  const status = (value: RealtimeStatus) => options.onStatus?.(value)
  function remember(key: string) {
    seen.set(key, true)
    while (seen.size > limit) seen.delete(seen.keys().next().value!)
  }
  function schedule() {
    if (!active || busy || request || queued || !dirty || options.isVisible?.()===false) return
    queued = true
    const gen = generation
    queueMicrotask(async () => {
      if (gen !== generation) return
      queued = false
      if (!active || busy || request || !dirty) return
      dirty = false
      const abort = new AbortController()
      request = abort
      try {
        const snapshot = await options.fetchSnapshot({ signal: abort.signal })
        fetchFailures=0
        if (!active || gen !== generation || abort.signal.aborted || request !== abort) return
        if (busy) dirty = true
        else options.apply(snapshot)
        if(options.isTerminal?.())cancel(poll)
      } catch (error) {
        fetchFailures++
        if (active && gen === generation && !abort.signal.aborted && (error as any)?.name !== 'AbortError') options.onError?.(error)
      } finally {
        if (gen === generation && request === abort) { request = undefined; schedule() }
      }
    })
  }
  function refresh(cancelCurrent = false) {
    if (active) {
      if (cancelCurrent) { request?.abort(); request = undefined }
      dirty = true; schedule()
    }
  }
  async function connect() {
    if(options.pollingOnly){status('polling');return}
    const gen = generation
    status('connecting')
    try {
      const subscription = await options.subscribe()
      if (!active || gen !== generation) return
      if (!subscription || !options.url) { retryConnection(); return }
      const ws = (options.createSocket ?? (url => new WebSocket(url)))(options.url)
      socket = ws
      const current = () => active && gen === generation && socket === ws
      let ready = false
      const disconnected = () => {
        if (!current()) return
        socket = undefined
        ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null
        ws.close(); retryConnection()
      }
      // Browsers answer server ping frames. Server heartbeat closes silent peers;
      // this deadline additionally covers connections that never reach ready.
      deadline = later(disconnected, 8000)
      ws.onopen = () => {
        if (current()) { try { ws.send(JSON.stringify(subscription)) } catch { disconnected() } }
      }
      ws.onmessage = event => {
        if (!current()) return
        let message: any
        try { message = JSON.parse(event.data) } catch { return }
        if (message?.type === 'ready' && !ready) {
          ready = true; connected = true; failures = 0; cancel(deadline)
          status('connected'); options.onInvalidate?.('ready'); reconcile(); refresh(); return
        }
        if (!ready || message?.type !== 'order.changed' || typeof message.event_id !== 'string'
          || typeof message.order_id !== 'string' || !Number.isSafeInteger(message.version)) return
        if (options.scope.channel === 'order' && message.order_id !== options.scope.order_id) return
        const id = `id:${message.event_id}`, version = `version:${message.order_id}:${message.version}`
        if (seen.has(id) || seen.has(version)) return
        remember(id); remember(version); options.onInvalidate?.('event'); refresh()
      }
      ws.onclose = disconnected
      ws.onerror = disconnected
    } catch { if (active && gen === generation) retryConnection() }
  }
  function start() {
    if (active) return
    active = true; generation++; refresh(); reconcile(); void connect()
  }
  function stop() {
    active = false; generation++; dirty = false; queued = false; seen.clear()
    connected = false; cancel(retry); cancel(deadline); cancel(poll)
    request?.abort(); request = undefined
    const old = socket; socket = undefined
    if (old) { old.onopen = old.onmessage = old.onclose = old.onerror = null; old.close() }
    status('polling')
  }
  return { start, stop, refresh, reconnect() { if (active) { stop(); start() } },
    pause() { request?.abort();request=undefined;cancel(poll) },
    resume() { if(active){reconcile();refresh()} },
    setBusy(value: boolean) { busy = value; schedule() } }
}
