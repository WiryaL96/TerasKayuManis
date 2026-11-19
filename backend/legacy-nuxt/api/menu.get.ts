// Keep the compatibility URL on the same public projection as /api/core/menu.
export default defineEventHandler(event=>{
 const base=String(useRuntimeConfig(event).goApiUrl||'').replace(/\/$/,'')
 if(!base)throw createError({statusCode:503,statusMessage:'Backend Go belum dikonfigurasi.'})
 return proxyRequest(event,`${base}/api/v1/menu`,{
  fetchOptions:{redirect:'error',signal:AbortSignal.timeout(15000)},
  headers:{...backendProxyHeaders(event),'x-order-token':'',cookie:'',authorization:''},
 })
})
