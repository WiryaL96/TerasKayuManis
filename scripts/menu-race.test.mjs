import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
test('shared catalog ignores stale response across composable callers',async()=>{
 const states=new Map(),pending=[]
 const source=readFileSync(new URL('../frontend/app/composables/useMenu.ts',import.meta.url),'utf8')
 const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
 const module={exports:{}}
 const app={}
 new Function('module','exports','useState','$fetch','useNuxtApp',code)(module,module.exports,(key,init)=>{if(!states.has(key))states.set(key,{value:init()});return states.get(key)},()=>new Promise(resolve=>pending.push(resolve)),()=>app)
 const a=module.exports.useMenu(),b=module.exports.useMenu()
 const first=a.load(true).catch(()=>{}),second=b.load(true)
 pending[1]({products:['new']});await second
 pending[0]({products:['old']});await first
 assert.deepEqual(a.menu.value,{products:['new']})
 assert.equal(a.loading.value,false)
})

test('concurrent catalog readers share one request and fresh catalog avoids refetch',async()=>{
 const states=new Map(),app={},pending=[]
 const source=readFileSync(new URL('../frontend/app/composables/useMenu.ts',import.meta.url),'utf8')
 const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
 const module={exports:{}}
 new Function('module','exports','useState','$fetch','useNuxtApp',code)(module,module.exports,(key,init)=>{if(!states.has(key))states.set(key,{value:init()});return states.get(key)},()=>new Promise(resolve=>pending.push(resolve)),()=>app)
 const a=module.exports.useMenu(),b=module.exports.useMenu()
 const first=a.load(),second=b.load()
 assert.equal(pending.length,1)
 pending[0]({products:[]});await Promise.all([first,second])
 await b.load();assert.equal(pending.length,1)
 states.get('menu-updated-at').value=Date.now()-31000
 const next=b.load();assert.equal(pending.length,2)
 pending[1]({products:['updated']});await next
 assert.deepEqual(a.menu.value.products,['updated'])
})
