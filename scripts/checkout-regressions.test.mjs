// Mount the real SFCs with Vue's renderer; only Nuxt/network/storage boundaries are fakes.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import * as Vue from 'vue'
import { parse, compileScript } from '@vue/compiler-sfc'
import ts from 'typescript'
import * as flow from '../frontend/shared/order-flow.ts'
import {installDashboard,imports as dashboardImports} from './helpers/dashboard-cache.mjs'
import { linePrice } from '../frontend/app/composables/useCart.ts'
const require = createRequire(import.meta.url)
const copy = x => structuredClone(x)
const product = { id:'coffee',slug:'coffee',category_id:'drinks',name:'Coffee',price:12000,is_available:true,variants:[],addons:[] }
const tea = { ...product,id:'tea',name:'Tea',price:8000 }
const payload = (id='coffee',table='A') => ({table_token:table,customer_name:table,payment_method:'cash',items:[{product_id:id,quantity:1,variant_ids:[],addon_ids:[],notes:''}]})
const storage = () => { const m=new Map(); return {getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,v),removeItem:k=>m.delete(k)} }
const renderer=Vue.createRenderer({
 createElement:tag=>({tag,children:[],props:{}}),createText:text=>({text}),createComment:text=>({text}),
 setText:(n,t)=>n.text=t,setElementText:(n,t)=>n.text=t,patchProp:(n,k,o,v)=>n.props[k]=v,
 insert(n,p,anchor){if(n.parent){const i=n.parent.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)}n.parent=p;const i=p.children.indexOf(anchor);p.children.splice(i<0?p.children.length:i,0,n)},
 remove(n){const i=n.parent?.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)},parentNode:n=>n.parent,nextSibling:n=>n.parent?.children[n.parent.children.indexOf(n)+1]
})
function component(path,expose,env){
 const source=readFileSync(new URL('../frontend/app/'+path,import.meta.url),'utf8').replace('</script>',`\ndefineExpose({${expose}})\n</script>`)
 const {descriptor}=parse(source,{filename:path})
 const compiled=compileScript(descriptor,{id:path,inlineTemplate:true,templateOptions:{compilerOptions:{hoistStatic:false,directiveTransforms:{model:()=>({props:[],needRuntime:false})}}}})
 const js=ts.transpileModule(compiled.content,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
 const module={exports:{}}
 const bindings=Object.entries(env).filter(([key])=>/^[A-Za-z_$][\w$]*$/.test(key))
 new Function('require','module','exports',...bindings.map(([key])=>key),js)(id=>id==='#shared/order-flow'?flow:dashboardImports[id]||require(id),module,module.exports,...bindings.map(([,value])=>value))
 return module.exports.default
}
async function mount(kind,{saved,fetch:fetcher,menu=copy({products:[product,tea],settings:{}}),lines=flow.prepareReorder(payload(),[product]).lines,confirm=()=>true}={}){
 const sessionStorage=saved??storage(),states=new Map(),navigations=[]
 const env={...Vue,useCustomerFooter:()=>{},definePageMeta:()=>{},useHead:()=>{},sessionStorage,confirm,crypto:globalThis.crypto,$fetch:async(url,options)=>{if(url==='/api/core/admin/me')return{id:'staff',full_name:'Kasir Uji',role:'cashier'};const result=await(fetcher??(async()=>[]))(url,options);return kind==='cashier'&&url==='/api/core/menu'?{...result,categories:[],settings:{id:1,brand_name:'Test',tax_pct:0,service_pct:0,require_customer_name:false,...result.settings}}:result},fmtIDR:n=>'Rp'+n,STATUS_LABEL:{},linePrice,
 setInterval:()=>0,clearInterval:()=>{},navigateTo:async p=>navigations.push(p),
 useRoute:()=>({query:{}}),useDashboardPreferences:()=>({collapsed:Vue.ref(true),theme:Vue.ref('light'),toggleCollapsed:()=>{},toggleTheme:()=>{}}),
 useState:(key,init)=>{if(!states.has(key))states.set(key,Vue.ref(init()));return states.get(key)},
 useSupabase:()=>({auth:{getSession:async()=>({data:{session:{access_token:'test-only'}}})}}),
 useCart:()=>({lines:cartLines,clear:()=>cartLines.value=[],remove:()=>{},setQty:()=>{}}),
 useTable:()=>table}
 const cartLines=Vue.ref(lines),table={token:Vue.ref('A'),number:Vue.ref(1),resolve:async()=>{}}
 installDashboard(env)
 states.set('cart-lines',cartLines)
 const cartSource=readFileSync(new URL('../frontend/app/composables/useCart.ts',import.meta.url),'utf8').replaceAll('import.meta.client','false')
 const cartJs=ts.transpileModule(cartSource,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
 const cartModule={exports:{}}
 new Function('module','exports','useState',cartJs)(cartModule,cartModule.exports,env.useState)
 env.useCart=cartModule.exports.useCart
 // Execute the production menu cache composable too.
 const menuSource=readFileSync(new URL('../frontend/app/composables/useMenu.ts',import.meta.url),'utf8')
 const js=ts.transpileModule(menuSource,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
 const nuxtApp={}
 const module={exports:{}};new Function('module','exports','useState','$fetch','useNuxtApp',js)(module,module.exports,env.useState,env.$fetch,()=>nuxtApp)
 env.useMenu=module.exports.useMenu
 env.useMenu().menu.value=menu
 env.useState('menu-updated-at',()=>0).value=Date.now()
 const editor=component('components/OrderEditor.vue','items',env)
 const customer=kind==='cart'||kind==='checkout'
 const page=component(customer?'components/CustomerOrderFlow.vue':'pages/'+kind+'.vue',customer?'placeOrder,name,error,submitting,total,expanded,visibleLines,checkoutDisabled,checkoutHint,changeQuantity,removedLine,undoRemoval':'reorder,createAgain,sendAttempt,draft,error,loggedIn',env)
 const app=renderer.createApp(page,kind==='checkout'?{checkout:true}:undefined);Object.assign(app.config.globalProperties,{fmtIDR:env.fmtIDR,linePrice,STATUS_LABEL:{}});app.component('OrderEditor',editor);app.component('NuxtLink',{render:()=>null});app.component('Icon',{render:()=>null})
 app.component('CustomerImage',{render:()=>null})
 app.component('DashboardDataStatus',{render:()=>null});app.component('UiSidebar',{render:()=>null});app.component('UiDashboardIcon',{render:()=>null})
 app.component('CustomerModal',{props:['open'],render(){return this.open?Vue.h('div',this.$slots.default?.()):null}})
 const root={children:[]};const vm=app.mount(root)
 await new Promise(r=>setImmediate(r));await Vue.nextTick()
 return {vm,root,app,sessionStorage,cartLines,table,navigations,menu:env.useMenu().menu}
}
function editorInstance(vnode){if(vnode?.component?.type.__name==='OrderEditor')return vnode.component.exposed;if(vnode?.component){const found=editorInstance(vnode.component.subTree);if(found)return found}for(const child of Array.isArray(vnode?.children)?vnode.children:[]){const found=editorInstance(child);if(found)return found}}

test('collapsed cart still charges and submits every item, including hidden lines',async t=>{
 const draft=payload();draft.items.push({...draft.items[0],product_id:'tea'}, {...draft.items[0],quantity:2,notes:'Separate portion'})
 const lines=flow.prepareReorder(draft,[product,tea]).lines,posts=[]
 const h=await mount('cart',{lines,fetch:async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts.body);return{id:'complete-cart'}}return{products:[product,tea],settings:{}}}})
 t.after(()=>h.app.unmount())
 assert.equal(h.vm.visibleLines.length,2)
 assert.equal(h.vm.total,44000)
 h.vm.expanded=true;await Vue.nextTick()
 assert.equal(h.vm.visibleLines.length,3)
 h.vm.expanded=false;await h.vm.placeOrder()
 assert.equal(posts[0].items.length,3)
 assert.equal(posts[0].items[2].quantity,2)
})

test('checkout selects cash automatically and only requires the configured customer name',async t=>{
 const posts=[],menu={products:[product,tea],settings:{require_customer_name:true}}
 const h=await mount('checkout',{menu,fetch:async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts.body);return{id:'cash-checkout'}}return menu}})
 t.after(()=>h.app.unmount())
 assert.equal(h.vm.checkoutDisabled,true)
 assert.match(h.vm.checkoutHint,/Isi nama/)
 assert.equal(h.vm.checkoutDisabled,true,'missing required name keeps checkout disabled')
 h.vm.name='Budi Santoso';await Vue.nextTick()
 assert.equal(h.vm.checkoutDisabled,false)
 await h.vm.placeOrder()
 assert.equal(posts[0].payment_method,'cash')
 assert.equal(posts[0].customer_name,'Budi Santoso')
})

test('customer can undo removing the last cart item and pending checkout blocks changes',async t=>{
 const catalog={products:[product,tea],settings:{}}
 const h=await mount('cart',{fetch:async()=>catalog});t.after(()=>h.app.unmount())
 h.vm.changeQuantity(h.cartLines.value[0],0);await Vue.nextTick()
 assert.equal(h.cartLines.value.length,0);assert.ok(h.vm.removedLine)
 h.vm.undoRemoval();await Vue.nextTick()
 assert.equal(h.cartLines.value.length,1);assert.equal(h.vm.removedLine,null)
 const saved=storage();saved.setItem('tkm-checkout',JSON.stringify({body:JSON.stringify(payload()),key:'fixed-key',token:'fixed-token'}))
 const recovery=await mount('cart',{saved,fetch:async()=>catalog});t.after(()=>recovery.app.unmount())
 recovery.vm.changeQuantity(recovery.cartLines.value[0],0)
 assert.equal(recovery.cartLines.value.length,1,'unresolved order recovery cannot lose its visible cart items')
})

test('checkout can recover a pending request without a fresh payment choice or catalog',async t=>{
 const saved=storage(),attempt={body:JSON.stringify(payload()),key:'original-key',token:'original-token'},posts=[]
 saved.setItem('tkm-checkout',JSON.stringify(attempt))
 const h=await mount('checkout',{saved,fetch:async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts);return{id:'recovered-checkout'}}throw Error('catalog offline')}})
 t.after(()=>h.app.unmount())
 assert.equal(h.vm.checkoutDisabled,false)
 await h.vm.placeOrder()
 assert.equal(posts[0].headers['Idempotency-Key'],'original-key')
 assert.equal(posts[0].headers['X-Order-Token'],'original-token')
 assert.deepEqual(posts[0].body,JSON.parse(attempt.body))
})

test('paused ordering blocks new checkout while preserving recovery of a committed attempt',async t=>{
 const menu={products:[product,tea],settings:{orders_enabled:false}},posts=[]
 const fetch=async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts);return{id:'already-committed'}}return menu}
 const fresh=await mount('checkout',{menu,fetch});t.after(()=>fresh.app.unmount());await Vue.nextTick()
 assert.equal(fresh.vm.checkoutDisabled,true)
 await fresh.vm.placeOrder();assert.equal(posts.length,0);assert.equal(fresh.sessionStorage.getItem('tkm-checkout'),null)
 const saved=storage(),attempt={body:JSON.stringify(payload()),key:'pending-original',token:'pending-capability'};saved.setItem('tkm-checkout',JSON.stringify(attempt))
 const retry=await mount('checkout',{saved,menu,fetch});t.after(()=>retry.app.unmount())
 assert.equal(retry.vm.checkoutDisabled,false);await retry.vm.placeOrder()
 assert.equal(posts.length,1);assert.equal(posts[0].headers['Idempotency-Key'],attempt.key)
 assert.equal(saved.getItem('tkm-order-already-committed'),attempt.token)
})

test('shared QR checkout submits without a table cookie or table identity',async t=>{
 const posts=[]
 const h=await mount('cart',{fetch:async(url,opts)=>{
  if(url==='/api/core/orders'){posts.push(opts);return {id:'shared-qr-order'}}
  return {products:[product],settings:{}}
 }});t.after(()=>h.app.unmount())
 h.table.token.value=null;h.table.number.value=null
 h.vm.name='Pelanggan QR'
 await h.vm.placeOrder()
 assert.equal(posts.length,1,'generic /menu customer can submit without scanning a table')
 assert.equal(Object.hasOwn(posts[0].body,'table_token'),false)
 assert.equal(posts[0].body.customer_name,'Pelanggan QR')
 assert.deepEqual(h.navigations,['/order/shared-qr-order'])
 assert.equal(h.vm.error,'')
})

test('switching cashier drafts resets editor items and confirms discarding edits',async t=>{
 const posts=[];let allow=true,confirmations=0
 const h=await mount('cashier',{confirm:()=>{confirmations++;return allow},fetch:async(url,opts)=>{
 if(url==='/api/core/menu')return {products:[product,tea],settings:{}}
 if(url.endsWith('/reorder'))return payload(url.includes('/B/')?'tea':'coffee',url.includes('/B/')?'B':'A')
 if(url==='/api/core/orders'){posts.push(opts.body);return {id:'created'}}return []
 }});t.after(()=>h.app.unmount())
 await h.vm.reorder({id:'A'});await Vue.nextTick()
 editorInstance(h.app._instance.subTree).items.value[0].quantity=3
 allow=false;await h.vm.reorder({id:'B'});await Vue.nextTick()
 assert.equal(h.vm.draft.table_token,'A','cancel keeps original draft')
 allow=true;await h.vm.reorder({id:'B'});await Vue.nextTick()
 const items=copy(Vue.toRaw(editorInstance(h.app._instance.subTree).items.value))
 assert.equal(items[0].product_id,'tea');assert.equal(items[0].quantity,1)
 await h.vm.createAgain(items)
 assert.equal(posts[0].table_token,'B');assert.equal(posts[0].customer_name,'B');assert.equal(posts[0].items[0].product_id,'tea');assert.ok(confirmations>=3)
})

test('definitive cashier rejection releases attempt for correction, not a generic 409',async t=>{
 for(const code of ['checkout_rejected','idempotency_conflict',undefined]){
 const saved=storage(),attempt={payload:payload(),key:'original-key',token:'original-token'};saved.setItem('tkm-cashier-checkout',JSON.stringify(attempt))
 let reject=true;const posts=[]
 const h=await mount('cashier',{saved,fetch:async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts);if(reject)throw {status:409,data:{code}};return {id:'new'}}if(url==='/api/core/menu')return {products:[product,tea],settings:{}};if(url.endsWith('/reorder'))return payload('tea','B');return []}});t.after(()=>h.app.unmount())
 await h.vm.sendAttempt()
 if(code==='checkout_rejected'){
 assert.equal(saved.getItem('tkm-cashier-checkout'),null)
 reject=false;await h.vm.reorder({id:'B'});await h.vm.createAgain(payload('tea','B').items)
 assert.equal(posts.length,2);assert.notEqual(posts[1].headers['Idempotency-Key'],attempt.key)
 }else{
 assert.deepEqual(JSON.parse(saved.getItem('tkm-cashier-checkout')),attempt)
 await h.vm.reorder({id:'B'});assert.equal(h.vm.draft,null)
 reject=false;await h.vm.sendAttempt();assert.equal(posts[1].headers['Idempotency-Key'],attempt.key);assert.deepEqual(posts[1].body,attempt.payload)
 }
 }
})

test('customer recovers committed lost response after reload and catalog/cart/table/name changes',async t=>{
 const saved=storage(),posts=[];let lose=true
 const fetch=async(url,opts)=>{if(url==='/api/core/orders'){posts.push(opts);if(lose)throw new Error('lost response after commit');return {id:'committed'}}return {products:[],settings:{}}}
 const first=await mount('cart',{saved,fetch});await first.vm.placeOrder();const pending=JSON.parse(saved.getItem('tkm-checkout'));assert.ok(pending);first.app.unmount()
 lose=false
 const h=await mount('cart',{saved,fetch,menu:{products:[{...product,is_available:false}],settings:{require_customer_name:true}},lines:[]});t.after(()=>h.app.unmount());h.table.token.value=''
 await h.vm.placeOrder()
 assert.equal(posts.length,2,'retry bypasses validation for NEW submissions')
 assert.deepEqual(posts[1].body,JSON.parse(pending.body));assert.equal(posts[1].headers['Idempotency-Key'],pending.key);assert.equal(posts[1].headers['X-Order-Token'],pending.token)
 assert.equal(saved.getItem('tkm-checkout'),null);assert.equal(saved.getItem('tkm-order-committed'),pending.token);assert.deepEqual(h.navigations,['/order/committed'])
})

test('customer definitive rejection permits correction; conflict and server/network errors retain identity',async t=>{
 for(const failure of [{status:409,data:{code:'checkout_rejected'}},{status:409,data:{code:'idempotency_conflict'}},{status:409},{status:503},new Error('offline')]){
 const h=await mount('cart',{fetch:async()=>{throw failure}});t.after(()=>h.app.unmount());await h.vm.placeOrder()
 assert.equal(h.sessionStorage.getItem('tkm-checkout')===null,failure.data?.code==='checkout_rejected')
 }
})

test('reorder import refreshes cached prices and availability before confirmation',async t=>{
 const saved=storage();saved.setItem('tkm-reorder',JSON.stringify(payload()));let calls=0
 const h=await mount('cart',{saved,fetch:async()=>{calls++;return {products:[{...product,price:19000,is_available:false}],settings:{}}}});t.after(()=>h.app.unmount())
 assert.equal(calls,1);assert.equal(h.vm.total,19000);assert.match(h.vm.error,/tidak tersedia/);assert.equal(saved.getItem('tkm-reorder'),null)
})

test('failed reorder refresh preserves draft and blocks stale-price submission until refreshed',async t=>{
 const saved=storage();saved.setItem('tkm-reorder',JSON.stringify(payload()));let posts=0
 const h=await mount('cart',{saved,fetch:async(url)=>{if(url==='/api/core/orders'){posts++;return {id:'wrong'}}throw new Error('offline')}});t.after(()=>h.app.unmount())
 assert.ok(saved.getItem('tkm-reorder'));assert.match(h.vm.error,/tidak bisa|gagal/i)
 await h.vm.placeOrder();assert.equal(posts,0);assert.equal(saved.getItem('tkm-checkout'),null)
})
