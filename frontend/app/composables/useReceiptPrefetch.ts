import { normalizeReceipt } from '#shared/dashboard-data'
export function useReceiptPrefetch() {
  const {cache}=useDashboardCache(),client=useSupabase()
  return async(id:string)=>{
    if(!cache.scope||!id)return null
    const {data}=await client.auth.getSession()
    if(!data.session||!cache.scope.startsWith(data.session.user.id+':'))return null
    try{return await cache.fetch(`receipt:${id}`,async signal=>normalizeReceipt(await $fetch(`/api/core/orders/${id}/receipt`,{signal,headers:{Authorization:`Bearer ${data.session!.access_token}`},retry:0,timeout:15000})),{staleTime:300000,retries:1})}
    catch{return null}
  }
}
