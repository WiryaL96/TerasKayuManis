import { createFetch } from 'ofetch'
import type { createBrowserClient } from '@supabase/ssr'

export default defineNuxtPlugin({
  name: 'preview-demo',
  enforce: 'pre',
  async setup() {
    if (!useRuntimeConfig().public.previewDemo) return { provide: { previewAuth: undefined } }
    const { createPreview } = await import('#shared/preview-demo')
    const preview = createPreview(window.localStorage)
    const nativeFetch = globalThis.fetch.bind(globalThis)
    const localFetch: typeof fetch = async (input, options) => {
      const url = new URL(input instanceof Request ? input.url : String(input), window.location.origin)
      if (url.origin === window.location.origin && url.pathname.startsWith('/api/')) {
        const request = input instanceof Request ? new Request(input, options) : new Request(url, options)
        return preview.fetch(request)
      }
      return nativeFetch(input, options)
    }
    globalThis.fetch = localFetch
    globalThis.$fetch = createFetch({ fetch: localFetch }) as typeof globalThis.$fetch
    return { provide: { previewAuth: preview.client as unknown as ReturnType<typeof createBrowserClient> } }
  },
})
