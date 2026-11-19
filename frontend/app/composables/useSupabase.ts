import { createBrowserClient } from '@supabase/ssr'

const clients=new WeakMap<object,ReturnType<typeof createBrowserClient>>()

export function useSupabase() {
  const app=useNuxtApp()
  if (useRuntimeConfig().public.previewDemo && app.$previewAuth) return app.$previewAuth
  let client=clients.get(app)
  if (!client) {
    const config = useRuntimeConfig()
    client = createBrowserClient(config.public.supabaseUrl, config.public.supabaseAnonKey, {
      global: { fetch: (input, options) => globalThis.fetch(input, { ...options,
        signal: options?.signal ? AbortSignal.any([options.signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000) }) },
    })
    clients.set(app,client)
  }
  return client
}
