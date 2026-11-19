import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import * as crypto from 'node:crypto'
import * as http from 'node:http'
import * as h3 from 'h3'
import {evaluate} from './helpers/dashboard-cache.mjs'
const require=createRequire(import.meta.url)
const load=(path,env={},modules={})=>evaluate(readFileSync(new URL('../backend/legacy-nuxt/'+path,import.meta.url),'utf8'),{...h3,...env},{'node:crypto':crypto,h3,...modules})

test('multipart bounds real chunked requests before parsing, and validates prebuffered adapters',async()=>{
 const {boundedMultipart}=load('utils/bounded-multipart.ts')
 const app=h3.createApp().use(h3.eventHandler(async e=>({parts:(await boundedMultipart(e,1024))?.length})))
 const server=http.createServer(h3.toNodeListener(app));await new Promise(r=>server.listen(0,'127.0.0.1',r))
 const send=body=>new Promise((resolve,reject)=>{
  const request=http.request({host:'127.0.0.1',port:server.address().port,path:'/',method:'POST',headers:{'content-type':'multipart/form-data; boundary=fixture','transfer-encoding':'chunked'}},res=>{let text='';res.on('data',c=>text+=c);res.on('end',()=>resolve({status:res.statusCode,text}))})
  request.on('error',reject);for(let i=0;i<body.length;i+=128)request.write(body.slice(i,i+128));request.end()
 })
 try{
  const form='--fixture\r\nContent-Disposition: form-data; name="file"; filename="a.txt"\r\n\r\nx\r\n--fixture--\r\n'
  assert.equal((await send(form)).status,200)
  assert.equal((await send(form+'x'.repeat(4096))).status,413)
  const event={node:{req:{headers:{},rawBody:Buffer.alloc(1025)}}}
  await assert.rejects(boundedMultipart(event,1024),{statusCode:413})
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r))}
})

test('trusted cashier cookies are signed, scoped, stable, and cannot be forged',()=>{
 const cookies=new Map(),writes=[]
 const env={useRuntimeConfig:()=>({cashierPinSecret:'synthetic-only-'.repeat(5),siteUrl:'https://restaurant.example'}),getCookie:(_,name)=>cookies.get(name),setCookie:(_,name,value,options)=>{cookies.set(name,value);writes.push(options)}}
 const api=load('utils/trusted-cashier.ts',env),id=crypto.randomUUID()
 api.rememberCashierDevice({},id,4);const first=api.trustedCashierDevice({},id)
 assert.equal(first.version,4);assert.match(first.device,/^[a-f0-9]{64}$/)
 api.rememberCashierDevice({},id,4);assert.deepEqual(api.trustedCashierDevice({},id),first)
 assert.deepEqual(writes[0],{path:'/api/auth',httpOnly:true,secure:true,sameSite:'strict',maxAge:2592000})
 const name='tkm-cashier-'+id,token=cookies.get(name);cookies.set(name,token.slice(0,-4)+'bad!')
 assert.equal(api.trustedCashierDevice({},id),null)
 cookies.set(name,token);assert.equal(api.trustedCashierDevice({},crypto.randomUUID()),null)
 api.rememberCashierDevice({},id,5);assert.notEqual(api.trustedCashierDevice({},id).device,first.device)
})

test('complete listing handles a server row cap, changes and oversized collections without truncating',async()=>{
 const {completeRows}=load('utils/complete-rows.ts'),all=Array.from({length:1250},(_,id)=>({id:String(id)}));let calls=0
 const result=await completeRows(async(a,b)=>{calls++;return{data:all.slice(a,Math.min(a+37,b+1)),count:all.length,error:null}})
 assert.equal(result.length,1250);assert.equal(calls,34)
 await assert.rejects(completeRows(async()=>({data:[],count:4,error:null})),{statusCode:503})
 await assert.rejects(completeRows(async()=>({data:[],count:10001,error:null})),{statusCode:503})
 await assert.rejects(completeRows(async offset=>({data:all.slice(offset,offset+1),count:offset?9:10,error:null})),{statusCode:503})
 await assert.rejects(completeRows(async()=>({data:[{id:'same'}],count:2,error:null})),{statusCode:503})
})

test('refresh cookie options, including removal, survive the SSR adapter',async()=>{
 let options;const writes=[]
 const api=load('utils/supabase.ts',{useRuntimeConfig:()=>({supabaseUrl:'https://synthetic.test',supabaseAnonKey:'synthetic'}),staffFetch:fetch,parseCookies:()=>({}),setCookie:(_e,n,v,o)=>writes.push({n,v,o})},{'@supabase/ssr':{createServerClient:(_u,_k,o)=>{options=o;return{auth:{getUser:async()=>({data:{user:null}})}}}},'@supabase/supabase-js':{createClient:()=>{throw Error('not reached')}}})
 await assert.rejects(api.requireStaff({}),{statusCode:401})
 const attrs={secure:true,sameSite:'lax',maxAge:0,httpOnly:false,path:'/'}
 options.cookies.setAll([{name:'session',value:'',options:attrs}])
 assert.deepEqual(writes,[{n:'session',v:'',o:attrs}])
})

test('CSP uses per-response nonces and enforces framing, object and origin restrictions',()=>{
 const headers={},event={context:{}}
 const {securityHeaders}=load('utils/security-headers.ts',{useRuntimeConfig:()=>({supabaseUrl:'https://project.supabase.co'}),setHeader:(_e,n,v)=>headers[n]=v})
 securityHeaders(event);const nonce=event.context.cspNonce
 assert.match(headers['Content-Security-Policy'],/frame-ancestors 'none'/)
 assert.match(headers['Content-Security-Policy'],/script-src 'self' 'nonce-/)
 assert.ok(!headers['Content-Security-Policy'].split(';').find(p=>p.includes('script-src')).includes('unsafe-inline'))
 assert.equal(headers['X-Frame-Options'],'DENY');assert.equal(headers['X-Content-Type-Options'],'nosniff')
 securityHeaders(event);assert.notEqual(event.context.cspNonce,nonce)
 let hook
 load('plugins/csp.ts',{defineNitroPlugin:fn=>fn({hooks:{hook:(_name,fn)=>hook=fn}})})
 const html={head:['<script src="/app.js"></script>'],body:['<script>window.ok=true</script>'],bodyPrepend:[],bodyAppend:[]}
 hook(html,{event});assert.ok(html.head[0].includes('nonce="'+event.context.cspNonce+'"'));assert.ok(html.body[0].includes('nonce="'))
})

test('deepmerge backport blocks dangerous own keys on either input and nested values',()=>{
 for(const module of ['deepmerge','deepmerge/dist/umd.js']){
  const merge=require(module),poison=JSON.parse('{"__proto__":{"polluted":true},"constructor":{"prototype":{"polluted":true}},"safe":{"x":1}}')
  for(const result of [merge(poison,{}),merge({},poison),merge({nest:poison},{nest:{y:2}}).nest]){
   assert.equal(Object.getPrototypeOf(result),Object.prototype)
   assert.equal(result.polluted,undefined);assert.equal(Object.hasOwn(result,'constructor'),false);assert.deepEqual(result.safe,{x:1})
  }
 }
 assert.equal({}.polluted,undefined)
})

test('cleanup only marks objects removed after Storage confirms deletion and tolerates retries',async()=>{
 const finished=[];let fail=true
 const {cleanupUploads}=load('utils/media-lifecycle.ts',{serviceClient:()=>({rpc:async(name,args)=>{if(name==='claim_unused_media')return{data:[{bucket:'staff-photos',path:'synthetic.webp'}]};finished.push(args);return{}},storage:{from:()=>({remove:async()=>({error:fail?{message:'offline'}:null})})}})})
 assert.equal((await cleanupUploads({})).failed,1);assert.equal(finished.length,0)
 fail=false;assert.equal((await cleanupUploads({})).cleaned,1);assert.equal(finished.length,1)
})

test('staff edit synchronizes email and credentials before activation, with partial Auth failure held inactive',async()=>{
 const calls=[],profile={id:'target',email:'new@example.test',role:'cashier',session_version:9,staff_status:'invited'}
 let fail=false
 const sb={auth:{admin:{getUserById:async()=>({data:{user:{id:'target',email:'old@example.test',app_metadata:{provider:'email'}}}}),updateUserById:async(id,input)=>{calls.push({id,input});return fail?{data:{},error:{status:503}}:{data:{user:{id}}}}}},rpc:async(name,args)=>{calls.push({name,args});return{data:{...profile,staff_status:'active',cashier_pin_enabled:true}}}}
 const {canManageStaffRole}=await import('../frontend/shared/staff-roles.ts')
 const {saveStaffPassword}=load('utils/direct-staff.ts',{serviceClient:()=>sb},{'#shared/staff-roles':{canManageStaffRole}})
 await saveStaffPassword({},{id:'root',role:'superadmin'},profile,'synthetic-derived-pin','pin','finish_staff_edit',true)
 assert.equal(calls[0].input.email,'new@example.test');assert.equal(calls[0].input.email_confirm,true)
 assert.deepEqual(calls[0].input.app_metadata,{provider:'email',staff_session_version:9,staff_access_method:'pin'})
 assert.equal(calls[1].name,'finish_staff_edit')
 calls.length=0;fail=true
 await assert.rejects(saveStaffPassword({},{id:'root',role:'superadmin'},profile,'synthetic','pin','finish_staff_edit',true),{statusCode:503})
 assert.equal(calls.length,1,'partial Auth failure activated an account')
})

test('settings route validates before one database transaction, and rejects privilege failures',async()=>{
 let writes=0,body={brand_name:'Cafe',tagline:'',tax_pct:0,service_pct:0,require_customer_name:false,orders_enabled:false},denied=false
 const handler=load('api/admin/settings.put.ts',{defineEventHandler:fn=>fn,sensitiveRequest:async()=>{},requireStaff:async()=>{if(denied)throw h3.createError({statusCode:403});return{id:'root'}},readBody:async()=>body,serviceClient:()=>({rpc:async(name,args)=>{writes++;assert.equal(name,'save_restaurant_settings');return{data:{...body,id:1}}}})}).default
 await handler({});assert.equal(writes,1)
 body={...body,tax_pct:101};await assert.rejects(handler({}),{statusCode:400});assert.equal(writes,1)
 denied=true;await assert.rejects(handler({}),{statusCode:403});assert.equal(writes,1)
})

test('opportunistic media cleanup has a total deadline and aborts its upstream request',async()=>{
 let observed
 const {cleanupUploads}=load('utils/media-lifecycle.ts',{serviceClient:(_e,signal)=>({rpc:()=>new Promise((_,reject)=>{observed=signal;signal.addEventListener('abort',()=>reject(Error('cancelled')),{once:true})})})})
 await assert.rejects(cleanupUploads({},10),/cancelled/);assert.equal(observed.aborted,true)
})
