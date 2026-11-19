import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
import * as staffRoles from '../frontend/shared/staff-roles.ts'
import { AUDIT_ACTIONS } from '../frontend/shared/staff-audit.ts'
const load=(path,env,require=id=>{if(id==='#shared/staff-roles')return staffRoles;throw Error('Unexpected import')})=>{
 const source=readFileSync(new URL('../backend/legacy-nuxt/'+path,import.meta.url),'utf8')
 const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
 const module={exports:{}};new Function('require','module','exports',...Object.keys(env),js)(require,module,module.exports,...Object.values(env));return module.exports
}
const createError=e=>Object.assign(new Error(e.statusMessage),e)
const jwt=version=>'e30.'+Buffer.from(JSON.stringify({app_metadata:{staff_session_version:version}})).toString('base64url')+'.verified-at-auth-boundary'
const environment=()=>({createError,staffFetch:globalThis.fetch,useRuntimeConfig:()=>({siteUrl:'https://restaurant.example.test',supabaseUrl:'https://project.example.test',supabaseAnonKey:'synthetic-public',supabaseServiceKey:'synthetic-private'}),getHeader:(e,k)=>e.headers[k],getRequestURL:e=>new URL(e.url),getRequestIP:e=>e.ip,setHeader:(e,k,v)=>e.response[k]=v,Buffer})

test('sensitive admin requests require exact origin, never trust forwarded IP, and apply an attempt budget',()=>{
 const api=load('utils/admin-security.ts',environment())
 const event={headers:{origin:'https://evil.example.test'},url:'https://restaurant.example.test/api/admin/staff',ip:'test-client',response:{}}
 assert.throws(()=>api.sensitiveRequest(event),e=>e.statusCode===403)
 event.headers.origin='https://restaurant.example.test'
 for(let i=0;i<12;i++)api.sensitiveRequest(event)
 assert.equal(event.response['Cache-Control'],'no-store')
 assert.throws(()=>api.sensitiveRequest(event),e=>e.statusCode===429)
})
test('development permits loopback aliases only for the configured HTTP port',()=>{
 const env=environment()
 env.process={env:{NODE_ENV:'development'}}
 env.useRuntimeConfig=()=>({siteUrl:'http://127.0.0.1:3000'})
 const api=load('utils/admin-security.ts',env)
 const event={headers:{},url:'http://127.0.0.1:3000/api/auth/staff-login',ip:'local-test',response:{}}
 for(const origin of ['http://localhost:3000','http://[::1]:3000']){
  event.headers.origin=origin
  assert.doesNotThrow(()=>api.sensitiveRequest(event))
 }
 for(const origin of [undefined,'null','not a URL','http://localhost:3001','https://localhost:3000','http://localhost.evil.test:3000','http://192.168.1.2:3000','http://localhost:3000/path','http://user@localhost:3000','http://localhost:3000?x=1']){
  event.headers.origin=origin
  assert.throws(()=>api.sensitiveRequest(event),e=>e.statusCode===403)
 }
 env.useRuntimeConfig=()=>({siteUrl:'http://localhost:3000'})
 const reverse=load('utils/admin-security.ts',env)
 event.headers.origin='http://127.0.0.1:3000'
 assert.doesNotThrow(()=>reverse.sensitiveRequest(event))
})

test('production and public site configuration never accept loopback aliases',()=>{
 for(const mode of ['production','development']){
  const env=environment()
  env.process={env:{NODE_ENV:mode}}
  env.useRuntimeConfig=()=>({siteUrl:mode==='production'?'http://127.0.0.1:3000':'https://restaurant.example.test'})
  const api=load('utils/admin-security.ts',env)
  const event={headers:{origin:'http://localhost:3000'},url:'http://127.0.0.1:3000/api/auth/staff-login',ip:'local-test',response:{}}
  assert.throws(()=>api.sensitiveRequest(event),e=>e.statusCode===403)
 }
})

test('staff input enforces three roles and only superadmin can create admin accounts',()=>{
 const api=load('utils/admin-security.ts',environment())
 const credentials={username:' Raka.Test ',password:'synthetic-password-only'}
 assert.deepEqual(api.checkedStaffInput({full_name:' Raka Pratama ',email:' RAKA@example.test ',...credentials}),{full_name:'Raka Pratama',email:'raka@example.test',role:'cashier',username:'raka.test',password:credentials.password})
 assert.deepEqual(api.checkedStaffInput({full_name:'Admin Baru',email:'admin@example.test',role:'admin',...credentials},'superadmin'),{full_name:'Admin Baru',email:'admin@example.test',role:'admin',username:'raka.test',password:credentials.password})
 assert.throws(()=>api.checkedStaffInput({full_name:'Admin Baru',email:'admin@example.test',role:'admin'},'admin'),e=>e.statusCode===403)
 assert.throws(()=>api.checkedStaffInput({full_name:'Kasir Baru',email:'cashier@example.test'},'cashier'),e=>e.statusCode===403)
 assert.throws(()=>api.checkedStaffInput({full_name:'Root Baru',email:'root@example.test',role:'superadmin'},'superadmin'),e=>e.statusCode===400)
 for(const input of [{full_name:'Raka',email:'a@example.test',role:'owner'},{full_name:{},email:'a@example.test'},{full_name:'Ra\nka',email:'a@example.test'},{full_name:'Raka',email:'bad'}])assert.throws(()=>api.checkedStaffInput(input),e=>e.statusCode===400)
 assert.equal(api.staffVersion(jwt(3)),3);assert.equal(api.staffVersion(jwt(-1)),-1);assert.equal(api.staffVersion(jwt('3')),-1)
})

test('direct account validation rejects missing credentials, malformed usernames and weak-length passwords',()=>{
 const api=load('utils/admin-security.ts',environment()),valid={full_name:'Raka',email:'raka@example.test',username:'raka.test',password:'synthetic-password-only'}
 for(const username of ['',null,'xy','@raka','x y','x'.repeat(33)])assert.throws(()=>api.checkedStaffInput({...valid,username}),e=>e.statusCode===400)
 for(const password of [null,'','short',' '.repeat(12),'x'.repeat(129)])assert.throws(()=>api.checkedStaffInput({...valid,password}),e=>e.statusCode===400)
 assert.equal(api.checkedStaffPassword('  valid-password  '),'  valid-password  ')
})

test('direct Auth provisioning stores credentials in Auth only, then activates and returns a safe profile',async()=>{
 const calls=[],profile={id:'target',full_name:'Raka',email:'raka@example.test',username:'raka',role:'cashier',staff_status:'invited',session_version:1}
 const sb={auth:{admin:{getUserById:async()=>({data:{user:null},error:{status:404}}),createUser:async input=>{calls.push(['auth',input]);return{data:{user:{id:profile.id}},error:null}}}},rpc:async(name,args)=>{calls.push([name,args]);return{data:{...profile,staff_status:'active'}}}}
 const api=load('utils/direct-staff.ts',{createError,serviceClient:()=>sb})
 const result=await api.saveStaffPassword({}, {id:'root',role:'superadmin'},profile,'synthetic-password-only')
 assert.equal(result.staff_status,'active');assert.equal(result.username,'raka');assert.ok(!('password' in result)&&!('url' in result))
 assert.equal(calls[0][1].password,'synthetic-password-only');assert.equal(calls[0][1].email_confirm,true)
 assert.deepEqual(calls[0][1].app_metadata,{staff_session_version:1,staff_access_method:'password'})
 assert.equal(calls[1][0],'finish_staff_credential');assert.ok(!JSON.stringify(calls[1]).includes('synthetic-password-only'))
})

test('Auth provisioning failures never report active; only definite new-user validation errors discard reservation',async()=>{
 for(const status of [422,503]){
  const calls=[],profile={id:'target',email:'raka@example.test',role:'cashier',session_version:1}
  const sb={auth:{admin:{getUserById:async()=>({data:{user:null},error:{status:404}}),createUser:async()=>({data:{user:null},error:{status}})}},rpc:async name=>{calls.push(name);return{}}}
  const api=load('utils/direct-staff.ts',{createError,serviceClient:()=>sb})
  await assert.rejects(api.saveStaffPassword({},{id:'root',role:'superadmin'},profile,'synthetic-password-only'),e=>[409,503].includes(e.statusCode))
  assert.deepEqual(calls,status===422?['discard_staff_reservation']:[])
 }
})

test('password update preserves trusted metadata and refuses identity mismatch or unauthorized roles',async()=>{
 let writes=0,email='raka@example.test',finishError=null
 const profile={id:'target',full_name:'Raka',email,username:'raka',role:'cashier',session_version:4}
 const sb={auth:{admin:{getUserById:async()=>({data:{user:{email,app_metadata:{provider:'email'}}}}),updateUserById:async(id,input)=>{writes++;assert.equal(id,profile.id);assert.deepEqual(input.app_metadata,{provider:'email',staff_session_version:4,staff_access_method:'password'});return{data:{user:{id}}}}}},rpc:async()=>({data:finishError?null:{...profile,staff_status:'active'},error:finishError})}
 const api=load('utils/direct-staff.ts',{createError,serviceClient:()=>sb})
 assert.equal((await api.saveStaffPassword({},{id:'admin',role:'admin'},profile,'synthetic-password-only')).staff_status,'active')
 email='different@example.test';await assert.rejects(api.saveStaffPassword({},{id:'root',role:'superadmin'},profile,'synthetic-password-only'),e=>e.statusCode===409);assert.equal(writes,1)
 await assert.rejects(api.saveStaffPassword({},{id:'cashier',role:'cashier'},profile,'synthetic-password-only'),e=>e.statusCode===403)
 await assert.rejects(api.saveStaffPassword({},{id:'target',role:'superadmin'},profile,'synthetic-password-only'),e=>e.statusCode===403)
 email=profile.email;finishError={code:'23514'};await assert.rejects(api.saveStaffPassword({},{id:'root',role:'superadmin'},profile,'synthetic-password-only'),e=>e.statusCode===409)
})

test('create endpoint reserves username before Auth and never returns activation links',async()=>{
 const calls=[],security=load('utils/admin-security.ts',environment()),body={full_name:'Raka',email:'raka@example.test',username:'RAKA',password:'synthetic-password-only',role:'cashier'}
 const env={...security,createError,defineEventHandler:fn=>fn,sensitiveRequest:()=>{},requireStaff:async()=>({id:'root',role:'superadmin'}),readBody:async()=>body,
  serviceClient:()=>({rpc:async(name,args)=>{calls.push([name,args]);return{data:{id:args.p_id}}}}),saveStaffPassword:async(_e,_a,p,pw)=>{assert.equal(pw,body.password);return{...p,staff_status:'active'}}}
 const handler=load('api/admin/staff/index.post.ts',env,id=>id==='node:crypto'?{randomUUID:()=> 'synthetic-id'}:staffRoles).default
 const result=await handler({});assert.equal(result.profile.staff_status,'active');assert.equal(calls[0][1].p_username,'raka')
 assert.ok(!JSON.stringify(calls).includes(body.password));assert.ok(!('url' in result))
})

test('password endpoint validates before revoking and uses a new account version for reactivation',async()=>{
 const calls=[],security=load('utils/admin-security.ts',environment());let body={password:'short',reactivate:true}
 const handler=load('api/admin/staff/[id]/password.post.ts',{...security,createError,defineEventHandler:fn=>fn,sensitiveRequest:()=>{},requireStaff:async()=>({id:'root',role:'superadmin'}),getRouterParam:()=> 'target',readBody:async()=>body,
  serviceClient:()=>({rpc:async(name,args)=>{calls.push([name,args]);return{data:{id:'target',session_version:5}}}}),saveStaffPassword:async(_e,_a,p)=>{assert.equal(p.session_version,5);return{staff_status:'active'}}}).default
 await assert.rejects(handler({}),e=>e.statusCode===400);assert.equal(calls.length,0)
 body={password:'synthetic-password-only',reactivate:true};assert.equal((await handler({})).profile.staff_status,'active')
 assert.deepEqual(calls[0],['begin_staff_password',{p_actor:'root',p_target:'target',p_reactivate:true}])
})

test('username login resolves email server-side and retains generic credential failure',async()=>{
 let identifier=' RAKA.Test ',email='raka@example.test',lookupError=null;const calls=[]
 const handler=load('api/auth/staff-login.post.ts',{...environment(),defineEventHandler:fn=>fn,sensitiveRequest:()=>{},readBody:async()=>({email:identifier,password:'synthetic-password-only',area:'cashier'}),staffVersion:()=>1,
  serviceClient:()=>({from:()=>({select:()=>({eq:(key,value)=>{calls.push([key,value]);return{maybeSingle:async()=>({data:email?{email}:null,error:lookupError})}}})}),rpc:async()=>({data:{id:'raka',role:'cashier'}})})},()=>({createClient:()=>({auth:{signInWithPassword:async input=>{calls.push(['verify',input.email]);return email?{data:{user:{id:'raka'},session:{access_token:jwt(1),refresh_token:'synthetic'}}}:{data:{},error:{status:400}}},signOut:async()=>({})}})})).default
 assert.equal((await handler({})).profile.id,'raka');assert.deepEqual(calls.slice(0,2),[['username','raka.test'],['verify','raka@example.test']])
 email=null;await assert.rejects(handler({}),e=>e.statusCode===401);assert.equal(calls.at(-1)[1],'unknown-staff@invalid.invalid')
 lookupError={code:'offline'};await assert.rejects(handler({}),e=>e.statusCode===503)
})
test('Nitro checks authenticated profile role, disabled state and the exact session version',async()=>{
 let verified=true,version=2,target,checks=0
 let profile={id:'auth-user',role:'cashier',full_name:'Raka',staff_status:'active',session_version:2}
 const env=environment(),security=load('utils/admin-security.ts',env)
 const sb={auth:{getUser:async()=>{checks++;return({data:{user:verified?{id:'auth-user',email:'raka@example.test'}:null}})},getSession:async()=>({data:{session:{access_token:jwt(version)}}})},from:()=>({select:()=>({eq:(_key,id)=>{target=id;return{single:async()=>({data:profile})}}})})}
 const api=load('utils/supabase.ts',{...env,staffVersion:security.staffVersion,parseCookies:()=>({}),setCookie:()=>{}},id=>id==='@supabase/ssr'?{createServerClient:()=>sb}:{createClient:()=>sb})
 const event={}
 assert.equal((await api.requireStaff(event,['cashier'])).full_name,'Raka');assert.equal(target,'auth-user')
 await assert.rejects(api.requireStaff(event,['superadmin','admin']),e=>e.statusCode===403)
 assert.equal(checks,1); // roles still checked on every call within the same request
 profile={...profile,staff_status:'disabled'};await assert.rejects(api.requireStaff({}),e=>e.statusCode===403)
 profile={...profile,staff_status:'active',session_version:3};await assert.rejects(api.requireStaff({}),e=>e.statusCode===403)
 version=3;assert.equal((await api.requireStaff({})).id,'auth-user')
 verified=false;await assert.rejects(api.requireStaff({}),e=>e.statusCode===401)
})

test('activity filters use inclusive WIB days, bound pagination and reject forged inputs',()=>{
 const api=load('utils/staff-audit.ts',{createError},()=>({AUDIT_ACTIONS}))
 assert.deepEqual(api.auditQuery({from:'2026-10-31',to:'2026-10-31'}),{from:'2026-10-30T17:00:00.000Z',to:'2026-10-31T17:00:00.000Z',actor:'',action:'',offset:0,limit:50})
 for(const invalid of [{from:'2026-02-30',to:'2026-03-01'},{from:'2026-10-31',to:'2026-10-30'},{from:'2026-01-01',to:'2026-02-01'},{from:['2026-10-31'],to:'2026-10-31'}])assert.throws(()=>api.auditQuery(invalid),e=>e.statusCode===400)
 for(const invalid of [{action:'__proto__'},{actor:'a)or(id.eq.other)'},{offset:'-1'},{offset:'100001'},{action:['staff_login']}])assert.throws(()=>api.auditQuery({from:'2026-10-31',to:'2026-10-31',...invalid}),e=>e.statusCode===400)
 assert.equal(api.auditQuery({from:'2026-10-01',to:'2026-10-31',action:'staff_login'}).action,'staff_login')
 const safe=api.safeAuditDetails({area:'cashier',total:10000,token:'secret',password:'secret',url:'private-link',before:{full_name:'Raka',email:'private@example.test',session_version:1},after:{full_name:'Raka Baru',staff_status:'disabled'}})
 assert.deepEqual(safe,{area:'cashier',total:10000,before_full_name:'Raka',after_full_name:'Raka Baru',after_staff_status:'disabled'})
})

test('staff login verifies credentials then records the verified account before returning tokens',async()=>{
 const calls=[];let authError=null,auditError=null,body={email:' raka@example.test ',password:'test-password',area:'cashier'}
 const auth={signInWithPassword:async input=>{calls.push(['verify',input.email]);return{data:authError?{}:{user:{id:'verified-raka'},session:{access_token:jwt(2),refresh_token:'synthetic-refresh'}},error:authError}},signOut:async options=>{calls.push(['revoke',options.scope]);return{error:null}}}
 const env={...environment(),defineEventHandler:fn=>fn,sensitiveRequest:()=>calls.push(['origin-rate']),readBody:async()=>body,staffVersion:()=>2,
 serviceClient:()=>({rpc:async(name,args)=>{calls.push([name,args]);return{data:auditError?null:{id:args.p_actor,full_name:'Raka',role:'cashier'},error:auditError}}})}
 const handler=load('api/auth/staff-login.post.ts',env,()=>({createClient:()=>({auth})})).default
 const result=await handler({})
 assert.equal(result.profile.id,'verified-raka');assert.equal(result.session.refresh_token,'synthetic-refresh')
 assert.deepEqual(calls.map(c=>c[0]),['origin-rate','verify','record_staff_signin'])
 assert.deepEqual(calls[2][1],{p_actor:'verified-raka',p_version:2,p_area:'cashier'})
 calls.length=0;auditError={code:'42501'}
 await assert.rejects(handler({}),e=>e.statusCode===403);assert.equal(calls.at(-1)[0],'revoke')
 calls.length=0;auditError={code:'db-offline'}
 await assert.rejects(handler({}),e=>e.statusCode===503);assert.equal(calls.at(-1)[0],'revoke')
 calls.length=0;authError={status:400}
 await assert.rejects(handler({}),e=>e.statusCode===401);assert.ok(!calls.some(c=>c[0]==='record_staff_signin'))
 body={...body,actor_id:'forged'}
 await assert.rejects(handler({}),e=>e.statusCode===400)
})

test('activity endpoint denies cashier and admin before accessing the private database',async()=>{
 for(const role of ['cashier','admin']){
  let accessed=false
  const handler=load('api/admin/activity.get.ts',{defineEventHandler:fn=>fn,requireStaff:async(_e,roles)=>{assert.deepEqual(roles,['superadmin']);if(!roles.includes(role))throw createError({statusCode:403})},serviceClient:()=>{accessed=true}}).default
  await assert.rejects(handler({}),e=>e.statusCode===403);assert.equal(accessed,false)
 }
})

test('superadmin activity results are paginated, filtered and scrubbed before reaching the browser',async()=>{
 const calls=[],env=environment(),audit=load('utils/staff-audit.ts',{createError},()=>({AUDIT_ACTIONS}))
 const row={id:'entry',actor_name:'Raka',details:{total:10000,password:'never-expose',before:{full_name:'Raka',email:'private@example.test'}}}
 const chain={select:()=>chain,gte:(k,v)=>{calls.push([k,v]);return chain},lt:(k,v)=>{calls.push([k,v]);return chain},order:()=>chain,eq:(k,v)=>{calls.push([k,v]);return chain},range:async(a,b)=>{calls.push(['range',a,b]);return{data:[row],count:125}}}
 const handler=load('api/admin/activity.get.ts',{...env,...audit,completeRows:async()=>[],defineEventHandler:fn=>fn,requireStaff:async()=>({id:'owner'}),getQuery:()=>({from:'2026-10-31',to:'2026-10-31',offset:'50',action:'staff_login'}),serviceClient:()=>({from:table=>table==='staff_audit'?chain:{select:()=>({in:()=>({order:async()=>({data:[]})})})}})}).default
 const result=await handler({response:{}})
 assert.equal(result.total,125);assert.equal(result.limit,50)
 assert.deepEqual(result.entries[0].details,{total:10000,before_full_name:'Raka'})
 assert.ok(calls.some(c=>c[0]==='range'&&c[1]===50&&c[2]===99))
 assert.ok(calls.some(c=>c[0]==='action'&&c[1]==='staff_login'))
})
