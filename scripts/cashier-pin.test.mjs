import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import * as crypto from 'node:crypto'
import ts from 'typescript'
import sharp from 'sharp'
import * as roles from '../frontend/shared/staff-roles.ts'
const createError=e=>Object.assign(new Error(e.statusMessage),e)
function load(path,env={},modules={}){
 const source=readFileSync(new URL('../backend/legacy-nuxt/'+path,import.meta.url),'utf8')
 const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,module={exports:{}}
 new Function('require','module','exports',...Object.keys(env),js)(id=>({'node:crypto':crypto,'#shared/staff-roles':roles,...modules})[id],module,module.exports,...Object.values(env))
 return module.exports
}
const id='11111111-1111-4111-8111-111111111111',secret='synthetic-private-key-for-disposable-tests-only'
const helpers=extra=>load('utils/cashier-pin.ts',{createError,useRuntimeConfig:()=>({cashierPinSecret:secret}),...extra})

test('PIN stays a string, is derived per identity with a private key and never sent raw to Auth',()=>{
 const api=helpers()
 assert.equal(api.checkedCashierPin('001234'),'001234')
 for(const bad of [123456,'12345','1234567','12 456','abcdef'])assert.throws(()=>api.checkedCashierPin(bad),e=>e.statusCode===400)
 const value=api.cashierPinPassword({},id,'001234')
 assert.equal(value,api.cashierPinPassword({},id,'001234'));assert.notEqual(value,'001234');assert.ok(value.length>32)
 assert.notEqual(value,api.cashierPinPassword({},'other','001234'))
 assert.throws(()=>helpers({useRuntimeConfig:()=>({cashierPinSecret:''})}).cashierPinPassword({},id,'001234'),e=>e.statusCode===503)
})

test('cashier directory publishes only display names and photo routes, never emails or internal profile fields',async()=>{
 const chain={select:()=>chain,eq:()=>chain,not:()=>chain,order:async()=>({data:[{id,full_name:'Kasir Test',staff_photo_path:null,email:'private@example.test'}]})}
 const handler=load('api/auth/cashiers.get.ts',{defineEventHandler:fn=>fn,setHeader:()=>{},serviceClient:()=>({from:()=>chain})}).default
 const rows=await handler({});assert.deepEqual(rows,[{id,name:'Kasir Test',photo:null}]);assert.ok(!JSON.stringify(rows).includes('private@example.test'))
})

test('PIN login reserves a shared guess budget, verifies Auth and returns only its verified session',async()=>{
 const calls=[];let blocked=false,wrong=false,mismatch=false
 const api=helpers(),profile={id,full_name:'Kasir Test',role:'cashier',session_version:3}
 const env={createError,...api,defineEventHandler:fn=>fn,sensitiveRequest:()=>{},requireCashierDevice:async()=> 'device-hash',readBody:async()=>({cashier_id:id,pin:'001234'}),useRuntimeConfig:()=>({cashierPinSecret:secret,supabaseUrl:'https://synthetic.example',supabaseAnonKey:'synthetic'}),staffVersion:()=>3,staffFetch:fetch,trustedCashierDevice:()=>null,rememberCashierDevice:()=>{},
 serviceClient:()=>({rpc:async(name,args)=>{calls.push(name);return name==='claim_cashier_pin_attempt'?{data:blocked?null:{id,email:'cashier@example.test',session_version:3},error:blocked?{message:'PIN_ATTEMPTS_EXCEEDED'}:null}:{data:profile}}})}
 const handler=load('api/auth/cashier-pin.post.ts',env,{'@supabase/supabase-js':{createClient:()=>({auth:{signInWithPassword:async input=>{calls.push('auth');assert.notEqual(input.password,'001234');return wrong?{data:{},error:{status:400}}:{data:{user:{id:mismatch?'forged':id},session:{access_token:'synthetic-jwt',refresh_token:'synthetic-refresh'}}}},signOut:async()=>{calls.push('revoke')}}})}}).default
 const result=await handler({});assert.equal(result.profile.id,id);assert.deepEqual(calls,['claim_cashier_pin_attempt','auth','finish_cashier_pin_login']);assert.ok(!JSON.stringify(result).includes('001234'))
 calls.length=0;wrong=true;await assert.rejects(handler({}),e=>e.statusCode===401);assert.deepEqual(calls,['claim_cashier_pin_attempt','auth'])
 calls.length=0;wrong=false;mismatch=true;await assert.rejects(handler({}),e=>e.statusCode===401);assert.deepEqual(calls,['claim_cashier_pin_attempt','auth','revoke'])
 calls.length=0;blocked=true;await assert.rejects(handler({}),e=>e.statusCode===429);assert.deepEqual(calls,['claim_cashier_pin_attempt'])
})

test('PIN account creation requires six digits and cannot provision an admin with a PIN',()=>{
 const api=load('utils/admin-security.ts',{createError,checkedCashierPin:helpers().checkedCashierPin})
 const input={full_name:'Kasir Test',email:'cashier@example.test',username:'cashier.test',pin:'001234',role:'cashier'}
 assert.equal(api.checkedStaffInput(input,'admin').pin,'001234')
 assert.throws(()=>api.checkedStaffInput({...input,role:'admin'},'superadmin'),e=>e.statusCode===400)
 assert.throws(()=>api.checkedStaffInput({...input,password:'ambiguous-password'},'superadmin'),e=>e.statusCode===400)
 assert.throws(()=>api.checkedStaffInput({...input,pin:'1234'},'superadmin'),e=>e.statusCode===400)
})

test('staff photo upload re-encodes actual pixels into private WebP and rejects SVG',async()=>{
 let input=await sharp({create:{width:32,height:32,channels:3,background:'#abc'}}).jpeg().withMetadata().toBuffer(),saved
 const handler=load('api/admin/staff-photo.post.ts',{createError,defineEventHandler:fn=>fn,registerUpload:async()=>{},cleanupUploads:async()=>({}),sensitiveRequest:()=>{},requireStaff:async()=>({id}),getHeader:()=>String(input.length),boundedMultipart:async()=>[{name:'file',data:input}],serviceClient:()=>({storage:{from:bucket=>({upload:async(path,bytes)=>{assert.equal(bucket,'staff-photos');saved=bytes;return{}}})}})},{sharp:{default:sharp}}).default
 const result=await handler({});assert.ok(result.path.startsWith(id+'/'))
 const meta=await sharp(saved).metadata();assert.equal(meta.format,'webp');assert.equal(meta.exif,undefined)
 input=Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>');await assert.rejects(handler({}),e=>e.statusCode===400)
})
