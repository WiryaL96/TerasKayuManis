import type {H3Event} from 'h3'
import {createHmac,randomBytes,timingSafeEqual,createHash} from 'node:crypto'
function deviceKey(event:H3Event){const key=String(useRuntimeConfig(event).cashierPinSecret||'');if(key.length<32)throw createError({statusCode:503,statusMessage:'Akses PIN belum dikonfigurasi.'});return key}
function mac(event:H3Event,value:string){return createHmac('sha256',deviceKey(event)).update('trusted-cashier-v1:'+value).digest('base64url')}
const cookieName=(id:string)=>'tkm-cashier-'+id
export function trustedCashierDevice(event:H3Event,id:string):{device:string;version:number}|null{
 const token=getCookie(event,cookieName(id));if(!token||token.length>700)return null
 try{const [encoded,signature]=token.split('.');if(!encoded||!signature)return null
 const expected=mac(event,encoded),a=Buffer.from(signature),b=Buffer.from(expected)
 if(a.length!==b.length||!timingSafeEqual(a,b))return null
 const p=JSON.parse(Buffer.from(encoded,'base64url').toString())
 if(p.id!==id||!Number.isSafeInteger(p.version)||p.exp<Date.now()||typeof p.device!=='string'||!/^[a-f0-9]{64}$/.test(p.device))return null
 return {device:p.device,version:p.version}
 }catch{return null}
}
export function rememberCashierDevice(event:H3Event,id:string,version:number){
 const old=trustedCashierDevice(event,id),device=old?.version===version?old.device:createHash('sha256').update(randomBytes(32)).digest('hex')
 const encoded=Buffer.from(JSON.stringify({id,device,version,exp:Date.now()+30*86400000})).toString('base64url')
 setCookie(event,cookieName(id),encoded+'.'+mac(event,encoded),{path:'/api/auth',httpOnly:true,secure:String(useRuntimeConfig(event).siteUrl).startsWith('https:'),sameSite:'strict',maxAge:30*86400})
}
