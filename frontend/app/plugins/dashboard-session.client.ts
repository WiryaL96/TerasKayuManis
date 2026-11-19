import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
export default defineNuxtPlugin(nuxtApp => {
  const client = useSupabase(), admin = useAdmin(), store = useDashboardCache()
  let previous: string | null = null
  const { data } = client.auth.onAuthStateChange((event: AuthChangeEvent, session: Session | null) => {
    const next = session?.user.id || null
    if (event === 'SIGNED_OUT' || (previous && next !== previous)) admin.reset()
    previous = next
    if (!next) store.cache.bind('')
  })
  nuxtApp.vueApp.onUnmount(() => data.subscription.unsubscribe())
})
