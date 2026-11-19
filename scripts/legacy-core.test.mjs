import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'

function load(path,env){
 env={backendProxyHeaders:()=>({}),...env}
 const source=readFileSync(new URL('../backend/legacy-nuxt/'+path,import.meta.url),'utf8')
 const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
 const module={exports:{}}
 new Function('module','exports',...Object.keys(env),js)(module,module.exports,...Object.values(env))
 return module.exports.default
}
const createError=value=>Object.assign(new Error(value.statusMessage),value)

test('legacy menu uses the current public projection and strips private credentials at the proxy boundary',async()=>{
 const event={headers:{authorization:'Bearer private-staff-token',cookie:'private-session'}}
 const result={products:[{id:'published-product'}]}
 let calls=0
 const handler=load('api/menu.get.ts',{
  createError,defineEventHandler:fn=>fn,useRuntimeConfig:()=>({goApiUrl:'http://127.0.0.1:8080/'}),
  proxyRequest:async(e,url,options)=>{
   calls++;assert.equal(e,event);assert.equal(url,'http://127.0.0.1:8080/api/v1/menu')
   assert.deepEqual(options.headers,{'x-order-token':'',cookie:'',authorization:''})
   assert.equal(options.fetchOptions.redirect,'error')
   assert.ok(options.fetchOptions.signal instanceof AbortSignal)
   return result
  },
 })
 assert.equal(await handler(event),result);assert.equal(calls,1)
})

test('legacy menu fails closed without Go configuration and preserves upstream errors',async()=>{
 let base='',calls=0
 const handler=load('api/menu.get.ts',{
  createError,defineEventHandler:fn=>fn,useRuntimeConfig:()=>({goApiUrl:base}),
  proxyRequest:async()=>{calls++;throw createError({statusCode:503})},
 })
 assert.throws(()=>handler({}),e=>e.statusCode===503);assert.equal(calls,0)
 base='http://127.0.0.1:8080'
 await assert.rejects(handler({}),e=>e.statusCode===503);assert.equal(calls,1)
})

test('migration middleware continues to retire legacy order URLs and allows the core API',()=>{
 const handler=load('middleware/order-migration.ts',{createError,defineEventHandler:fn=>fn,getRequestURL:e=>new URL(e.url)})
 for(const path of ['/api/orders','/api/orders/test','/api/admin/orders','/api/admin/orders/test']){
  assert.throws(()=>handler({url:'https://restaurant.example.test'+path}),e=>e.statusCode===410)
 }
 for(const path of ['/api/core/orders','/api/core/orders/test','/api/menu'])assert.doesNotThrow(()=>handler({url:'https://restaurant.example.test'+path}))
})

test('retired legacy order handlers cannot expose data or create orders even without middleware',()=>{
 for(const path of ['api/orders/[uuid].get.ts','api/orders/index.post.ts']){
  const handler=load(path,{createError,defineEventHandler:fn=>fn})
  assert.throws(()=>handler({}),e=>e.statusCode===410)
 }
})
