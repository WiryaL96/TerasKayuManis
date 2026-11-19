import type {H3Event} from 'h3'
import {randomBytes} from 'node:crypto'
export function securityHeaders(event:H3Event){
 const config=useRuntimeConfig(event),nonce=randomBytes(18).toString('base64')
 event.context.cspNonce=nonce
 const hosts=new Set<string>()
 for(const value of [config.supabaseUrl,config.public?.supabaseUrl]){try{const u=new URL(String(value));if(u.protocol==='https:'||(u.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(u.hostname)))hosts.add(u.origin)}catch{}}
 const dev=process.env.NODE_ENV==='development'
 const policy=["default-src 'self'",`script-src 'self' 'nonce-${nonce}'${dev?" 'unsafe-eval'":''}`,"style-src 'self' 'unsafe-inline' https://fonts.googleapis.com","font-src 'self' https://fonts.gstatic.com data:","img-src 'self' data: blob: https:",`connect-src 'self' ${[...hosts].join(' ')} ${[...hosts].map(h=>h.replace('https:','wss:').replace('http:','ws:')).join(' ')}${dev?' ws: http://localhost:* http://127.0.0.1:*':''}`,"frame-ancestors 'none'","object-src 'none'","base-uri 'self'","form-action 'self'"].join('; ')
 setHeader(event,'Content-Security-Policy',policy)
 setHeader(event,'X-Frame-Options','DENY')
 setHeader(event,'X-Content-Type-Options','nosniff')
 setHeader(event,'Referrer-Policy','strict-origin-when-cross-origin')
 setHeader(event,'Permissions-Policy','camera=(), microphone=(), geolocation=(self)')
}
