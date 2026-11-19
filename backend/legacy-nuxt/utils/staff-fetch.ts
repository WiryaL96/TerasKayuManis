// Every Auth/Data API call has a deadline, including cleanup after a failed
// activation. Preserve caller cancellation as well as the server's own limit.
export const staffFetch: typeof globalThis.fetch = (input, options) =>
  globalThis.fetch(input, { ...options, signal: options?.signal
    ? AbortSignal.any([options.signal, AbortSignal.timeout(15000)])
    : AbortSignal.timeout(15000) })
