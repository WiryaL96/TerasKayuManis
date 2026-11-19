import { isIP } from 'node:net'
import { createHash } from 'node:crypto'
import type { H3Event } from 'h3'
export function trustedClientIP(event:H3Event):string {
 const raw=process.env.VERCEL==='1'?getHeader(event,'x-vercel-forwarded-for'):getRequestIP(event)
 if(!raw||!isIP(raw))throw createError({statusCode:403,statusMessage:'Identitas koneksi tidak valid.'})
 return raw
}
export function backendProxyHeaders(event:H3Event):Record<string,string> {
 const cfg=useRuntimeConfig(event)
 if(!cfg.serverless)return {}
 if(String(cfg.backendProxySecret).length<32)throw createError({statusCode:503,statusMessage:'Koneksi backend belum dikonfigurasi.'})
 return {'x-tkm-proxy-key':String(cfg.backendProxySecret),'x-tkm-client-ip':trustedClientIP(event)}
}
export async function sensitiveBudget(event:H3Event,limit:number){
 const scope=getRequestURL(event).pathname.replace(/[a-f0-9]{8}-[a-f0-9-]{27}/gi,':id')
 const key=createHash('sha256').update(trustedClientIP(event)+':'+scope).digest('hex')
 const {data,error}=await serviceClient(event).rpc('claim_sensitive_budget',{p_key:key,p_limit:limit})
 if(error)throw createError({statusCode:503,statusMessage:'Pemeriksaan akses belum tersedia. Coba lagi.'})
  if(data!==true){setHeader(event,'Retry-After',60);throw createError({statusCode:429,statusMessage:'Terlalu banyak percobaan. Tunggu satu menit.'})}
}
