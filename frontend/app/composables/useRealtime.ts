import { createRealtimeController, realtimeURL } from '#shared/realtime'
import type { RealtimeOptions } from '#shared/realtime'
import { versionedSnapshot } from '#shared/versioned-snapshot'

// Created by the page on mount; dispose on unmount. No credentials in URLs,
// persistent stores, or event payloads. Supabase session lookup belongs to subscribe.
export function useRealtime<T>(options: Omit<RealtimeOptions<T>, 'url'> & {snapshotKey?:()=>string}) {
  const polling=typeof useRuntimeConfig==='function'&&useRuntimeConfig().public.syncMode==='polling'
  let terminal=false
  const versioned=versionedSnapshot<T>({key:options.snapshotKey??(()=>JSON.stringify(options.scope)),
    version:async signal=>{
      const sub=await options.subscribe()
      if(!sub)throw Object.assign(new Error('Login diperlukan'),{statusCode:401})
      const path=sub.channel==='cashier'?'/api/core/admin/sync':`/api/core/orders/${sub.order_id}/sync`
      const result=await $fetch<{revision:string;terminal?:boolean}>(path,{signal,retry:0,timeout:10000,headers:sub.channel==='cashier'?{Authorization:`Bearer ${sub.access_token}`}:{'X-Order-Token':sub.order_token}})
      terminal=sub.channel==='order'&&result.terminal===true
      return result
    },fetch:signal=>options.fetchSnapshot({signal}),invalidate:()=>options.onInvalidate?.('event')})
  const controller = createRealtimeController<T>({
    ...options,
    pollingOnly:polling,
    isTerminal:()=>polling&&terminal,
    isVisible:()=>document.visibilityState!=='hidden',
    ...(polling?{fetchSnapshot:({signal}:{signal:AbortSignal})=>versioned.fetch(signal)}:{}),
    url: realtimeURL(window.location.href),
    createSocket: url => new WebSocket(url),
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: id => clearTimeout(id)
  })
  const focus = () => controller.refresh()
  const online = () => controller.refresh()
  const visible = () => { if (document.visibilityState === 'visible') controller.resume();else controller.pause() }
  window.addEventListener('focus', focus)
  window.addEventListener('online', online)
  document.addEventListener('visibilitychange', visible)
  return {
    ...controller,
    refresh(force=false){if(force)versioned.reset();controller.refresh(force)},
    dispose() {
      controller.stop()
      window.removeEventListener('focus', focus)
      window.removeEventListener('online', online)
      document.removeEventListener('visibilitychange', visible)
    }
  }
}
