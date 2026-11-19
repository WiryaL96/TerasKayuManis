// Real Vue pages + production composable/controller; fake only browser/network/auth boundaries.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'
import * as Vue from 'vue'
import { parse, compileScript } from '@vue/compiler-sfc'
import ts from 'typescript'
import * as flow from '../frontend/shared/order-flow.ts'
import * as realtime from '../frontend/shared/realtime.ts'
import * as versioned from '../frontend/shared/versioned-snapshot.ts'
import {installDashboard,imports as dashboardImports} from './helpers/dashboard-cache.mjs'
const require=createRequire(import.meta.url)
const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();await Vue.nextTick()}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}
const renderer=Vue.createRenderer({createElement:tag=>({tag,children:[],props:{}}),createText:text=>({text}),createComment:text=>({text}),setText:(n,t)=>n.text=t,setElementText:(n,t)=>n.text=t,patchProp:(n,k,o,v)=>n.props[k]=v,insert(n,p,anchor){if(n.parent){const i=n.parent.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)}n.parent=p;const i=p.children.indexOf(anchor);p.children.splice(i<0?p.children.length:i,0,n)},remove(n){const i=n.parent?.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)},parentNode:n=>n.parent,nextSibling:n=>{const siblings=n.parent?.children??[];return siblings[siblings.indexOf(n)+1]??null}})
function targets(){const handlers=new Map();return {location:{href:'https://cafe.test'},visibilityState:'visible',addEventListener(k,fn){if(!handlers.has(k))handlers.set(k,new Set());handlers.get(k).add(fn)},removeEventListener(k,fn){handlers.get(k)?.delete(fn)},fire(k){for(const f of handlers.get(k)??[])f()},get count(){return [...handlers.values()].reduce((n,s)=>n+s.size,0)}}}
const snapshot=(id='A',version=1)=>({id,version,reviewed_version:version,status:'pending',payment_status:'unpaid',total:12000,subtotal:12000,discount:0,tax:0,service_charge:0,created_at:new Date().toISOString(),expires_at:new Date(Date.now()+600000).toISOString(),order_items:[],order_number:id})
async function mount(kind,{fetch:fetcher,syncMode='websocket'}={}){
 const sockets=[],requests=[],saved=new Map([['tkm-order-A','cap-A'],['tkm-order-B','cap-B'],['tkm-table-token','NOT-ORDER-AUTH']]),win=targets(),doc=targets(),timers=new Map()
 let timerId=0,token='staff-first',authCallback,unsubscribed=false
 const auth={getSession:async()=>({data:{session:token?{access_token:token,user:{id:'staff'}}:null}}),signOut:async()=>{token=null;authCallback?.('SIGNED_OUT',null)},onAuthStateChange:fn=>{authCallback=fn;return {data:{subscription:{unsubscribe(){unsubscribed=true}}}}}}
 class WS {onopen;onmessage;onclose;onerror;sent=[];closed=false;constructor(url){this.url=url;sockets.push(this)}send(x){this.sent.push(JSON.parse(x))}close(){this.closed=true;this.onclose?.({})}open(){this.onopen?.({})}message(x){this.onmessage?.({data:JSON.stringify(x)})}}
 const route=Vue.reactive({params:{uuid:'A'},query:{}})
 const env={definePageMeta:()=>{},ref:Vue.ref,reactive:Vue.reactive,computed:Vue.computed,watch:Vue.watch,nextTick:Vue.nextTick,onMounted:Vue.onMounted,onUnmounted:Vue.onUnmounted,window:win,document:doc,WebSocket:WS,AbortController,queueMicrotask,sessionStorage:{getItem:k=>saved.get(k)??null,setItem:(k,v)=>saved.set(k,v),removeItem:k=>saved.delete(k)},
 setInterval:()=>0,clearInterval:()=>{},setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId},clearTimeout:id=>timers.delete(id),
 useRuntimeConfig:()=>({public:{syncMode}}),useRoute:()=>route,useSupabase:()=>({auth}),fmtIDR:n=>'Rp'+n,STATUS_LABEL:{},confirm:()=>true,navigateTo:async()=>{},crypto:globalThis.crypto,
 $fetch:async(url,options)=>{if(url==='/api/core/admin/me')return {id:'staff',full_name:'Kasir Uji',role:'cashier'};if(url==='/api/auth/staff-logout')return{ok:true};requests.push({url,options});return fetcher?fetcher(url,options):url==='/api/core/admin/orders'?[snapshot()]:snapshot(route.params.uuid)}}
 function evaluate(source){const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;const module={exports:{}};new Function('require','module','exports',...Object.keys(env),js)(id=>id==='#shared/order-flow'?flow:id==='#shared/realtime'?realtime:id==='#shared/versioned-snapshot'?versioned:dashboardImports[id]||require(id),module,module.exports,...Object.values(env));return module.exports}
 installDashboard(env)
 env.useAdmin=()=>({reset:()=>env.useDashboardCache().cache.bind('')})
 env.useDashboardPreferences=()=>({collapsed:Vue.ref(true),theme:Vue.ref('light'),toggleCollapsed:()=>{},toggleTheme:()=>{}})
 env.useStaffAuth=evaluate(readFileSync(new URL('../frontend/app/composables/useStaffAuth.ts',import.meta.url),'utf8')).useStaffAuth
 // Missing composable is allowed only for the integration RED before implementation.
 try{env.useRealtime=evaluate(readFileSync(new URL('../frontend/app/composables/useRealtime.ts',import.meta.url),'utf8')).useRealtime}catch(e){if(e.code!=='ENOENT')throw e}
 const path=kind==='cashier'?'cashier.vue':'order/[uuid].vue',expose=kind==='cashier'?'orders,editing,draft,busy,loggedIn,logout,tab,offset,load,posReference,posEntered,posPaid,pendingCount,reviewedCount,processingCount,posAction,search,querySearch,filterStatus,sortOrder,selectedId,selectedOrder,resetFilters,account,hasStaffName,selectionMissing,selectOrder':'order,loadError,now,retryOrder'
 const pageSource=process.env.REALTIME_PAGE_SOURCE==='HEAD'
  ?execFileSync('git',['show','HEAD:frontend/app/pages/'+path],{cwd:new URL('../',import.meta.url),encoding:'utf8'})
  :readFileSync(new URL('../frontend/app/pages/'+path,import.meta.url),'utf8')
 const source=pageSource.replace('</script>',`\ndefineExpose({${expose}})\n</script>`)
 const {descriptor}=parse(source,{filename:path});const compiled=compileScript(descriptor,{id:path,inlineTemplate:true,templateOptions:{compilerOptions:{hoistStatic:false,directiveTransforms:{model:()=>({props:[],needRuntime:false})}}}})
 const app=renderer.createApp(evaluate(compiled.content).default);Object.assign(app.config.globalProperties,{fmtIDR:env.fmtIDR,STATUS_LABEL:{}});for(const name of ['NuxtLink','Icon','OrderEditor','UiSidebar','UiDashboardIcon','DashboardDataStatus'])app.component(name,{render:()=>null})
 const root={children:[]},vm=app.mount(root);await flush()
 return {app,vm,root,route,sockets,requests,win,doc,timers,saved,renew(value){token=value;authCallback?.('TOKEN_REFRESHED',{access_token:value})},get unsubscribed(){return unsubscribed}}
}
function text(node){return [node.text??'',...(node.children??[]).map(text)].join(' ')}
const event=(id='e',order_id='A',version=2)=>({type:'order.changed',event_id:id,order_id,version,event_type:'unrestricted.backend.name'})

test('customer payment reminder follows status without changing server state',async t=>{
 const start=Date.now()
 const pending={...snapshot(),expires_at:new Date(start+61000).toISOString(),subtotal:12000}
 const h=await mount('order',{fetch:async()=>pending});t.after(()=>h.app.unmount())
 h.vm.now=start;await flush()
 assert.match(text(h.root),/Segera menuju kasir/)
 assert.match(text(h.root),/01:0[12]/)
 h.vm.order={...pending,status:'pos_input',version:2};await flush()
 assert.doesNotMatch(text(h.root),/Segera menuju kasir/)
 assert.match(text(h.root),/Pesanan sedang ditangani kasir/)
 h.vm.order={...pending,expires_at:new Date(start-1000).toISOString()};await flush()
 assert.match(text(h.root),/Batas waktu ke kasir habis/)
 assert.match(text(h.root),/00:00/)
 assert.equal(h.vm.order.status,'pending','local timer must not set expired status')
})

test('cashier shows counter workload and refuses POS completion without manual attestations',async t=>{
 const pending=snapshot(),claimed={...snapshot('B',2),status:'pos_input',pos_handoff:{cashier_id:'staff',cashier_name:'Kasir Uji',claimed_at:new Date().toISOString(),forwarded_at:null,pos_reference:null}}
 const h=await mount('cashier',{fetch:async()=>[pending,claimed]});t.after(()=>h.app.unmount())
 assert.equal(h.vm.pendingCount,1);assert.equal(h.vm.reviewedCount,1);assert.equal(h.vm.processingCount,1)
 const count=h.requests.length
 await h.vm.posAction({...pending,reviewed_version:null},'claim-pos');await flush()
 assert.equal(h.requests.length,count,'unreviewed order must not be claimed')
 await h.vm.posAction(claimed,'forward-pos');await flush()
 assert.equal(h.requests.length,count,'completion requires both manual confirmations')
 assert.ok(!h.requests.some(r=>r.url.includes('confirm-cash')))
})

test('cashier shows server identity and retains the original accepting cashier on receipts',async t=>{
 const pending={...snapshot(),expires_at:new Date(Date.now()+600000).toISOString(),reviewed_version:1}
 const paid={...pending,id:'B',status:'confirmed',payment_status:'paid',cashier:{id:'other-staff',full_name:'Sari Putri',confirmed_at:new Date().toISOString()}}
 const h=await mount('cashier',{fetch:async()=>[paid,pending]});t.after(()=>h.app.unmount())
 assert.match(text(h.root),/Kasir:.*Kasir Uji/)
 assert.match(text(h.root),/Konfirmasi oleh.*Sari Putri/)
 h.vm.account={id:'staff',full_name:null,role:'cashier'};await flush()
 const n=h.requests.length;await h.vm.posAction(pending,'claim-pos');await flush()
 assert.equal(h.requests.length,n,'unnamed account must not send a payment')
 assert.match(text(h.root),/Nama akun kasir belum diisi/)
 await h.vm.logout();assert.equal(h.vm.account,null)
})

test('cashier search resets pagination, ignores stale responses and keeps an explicit selection during refresh',async t=>{
 const old=deferred();let late=false
 const h=await mount('cashier',{fetch:async(url,options)=>late?(options.query.q?[snapshot('match')]:old.promise):Array.from({length:100},(_,i)=>snapshot(i===0?'A':i===1?'B':String(i)))});t.after(()=>h.app.unmount())
 h.vm.selectedId='B';h.vm.load();await flush();assert.equal(h.vm.selectedOrder.id,'B')
 late=true;h.vm.load();await flush();const previous=h.requests.at(-1)
 h.vm.offset=100;h.vm.search='  Budi  ';await flush()
 const debounce=[...h.timers.values()].find(t=>t.ms===350);assert.ok(debounce);debounce.fn();await flush()
 assert.equal(h.vm.offset,0);assert.equal(h.requests.at(-1).options.query.q,'Budi')
 assert.equal(previous.options.signal.aborted,true)
 old.resolve([snapshot('stale')]);await flush()
 assert.notEqual(h.vm.selectedOrder?.id,'stale','response for the previous filter cannot populate the new queue')
})

test('cashier filters and sorts a complete cached listing without API hits or new sockets',async t=>{
 const h=await mount('cashier',{fetch:async()=>[snapshot('A'),{...snapshot('B'),customer_name:'Budi'}]});t.after(()=>h.app.unmount())
 const hits=h.requests.length,sockets=h.sockets.length
 h.vm.search='Budi';await flush();[...h.timers.values()].find(t=>t.ms===350).fn();await flush()
 assert.deepEqual(h.vm.orders.map(o=>o.id),['B'])
 h.vm.sortOrder='oldest';h.vm.filterStatus='pending';await flush()
 assert.equal(h.requests.length,hits);assert.equal(h.sockets.length,sockets)
})

test('customer exact capability, ready snapshot, REST versions, focus/online and cleanup',async t=>{
 let version=1;const h=await mount('order',{fetch:async()=>snapshot('A',version)});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');const ws=h.sockets[0];assert.equal(ws.url,'wss://cafe.test/ws');assert.match(text(h.root),/Menghubungkan ke pesanan/)
 ws.open();assert.deepEqual(ws.sent,[{type:'subscribe',channel:'order',order_id:'A',order_token:'cap-A'}]);assert.doesNotMatch(text(h.root),/Status diperbarui otomatis/)
 version=3;ws.message({type:'ready'});await flush();assert.equal(h.vm.order.version,3);assert.match(text(h.root),/Status diperbarui otomatis/)
 version=2;ws.message(event('older','A',1000));await flush();assert.equal(h.vm.order.version,3,'REST lower version cannot regress displayed order; event not authoritative')
 version=4;h.win.fire('focus');await flush();assert.equal(h.vm.order.version,4)
 version=5;h.win.fire('online');await flush();assert.equal(h.vm.order.version,5)
 ws.close();await flush();assert.match(text(h.root),/Status diperbarui otomatis/)
 h.app.unmount();assert.equal(ws.closed,true);assert.equal(h.win.count+h.doc.count,0);assert.equal(h.timers.size,0)
})

test('route reuse aborts and rejects old response/event; new scope uses new exact capability',async t=>{
 const a=deferred();const h=await mount('order',{fetch:async(url)=>url.endsWith('/A')?a.promise:snapshot('B',2)});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');const old=h.sockets[0];old.open();const late=old.onmessage
 h.route.params.uuid='B';await flush();assert.equal(old.closed,true);assert.equal(h.requests[0].options.signal.aborted,true)
 const ws=h.sockets[1];ws.open();assert.equal(ws.sent[0].order_token,'cap-B');assert.equal(h.vm.order.id,'B')
 a.resolve(snapshot('A',99));late?.({data:JSON.stringify(event())});await flush();assert.equal(h.vm.order.id,'B');assert.equal(h.vm.order.version,2)
 const n=h.requests.length;ws.message({type:'ready'});await flush();ws.message(event('wrong','A',99));await flush();assert.equal(h.requests.length,n+1)
})

test('cashier events preserve editor/draft/received, busy trails, fresh auth reconnect and logout cleanup',async t=>{
 let version=1;const h=await mount('cashier',{fetch:async()=>[snapshot('A',version)]});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');let ws=h.sockets[0];ws.open();assert.equal(ws.sent[0].access_token,'staff-first');ws.message({type:'ready'});await flush()
 h.vm.editing=snapshot('A',1);h.vm.draft={customer_name:'unsaved',items:[]};h.vm.posReference.A='POS-draft'
 h.vm.busy=true;version=4;const n=h.requests.length;ws.message(event());await flush();assert.equal(h.requests.length,n)
 h.vm.busy=false;await flush();assert.equal(h.requests.length,n+1);assert.equal(h.vm.orders[0].version,4);assert.equal(h.vm.editing.version,1);assert.equal(h.vm.draft.customer_name,'unsaved');assert.equal(h.vm.posReference.A,'POS-draft')
 h.renew('fresh-token');await flush();assert.equal(ws.closed,true);ws=h.sockets.at(-1);ws.open();assert.equal(ws.sent[0].access_token,'fresh-token')
 await h.vm.logout();await flush();assert.equal(ws.closed,true);assert.equal(h.vm.loggedIn,false);assert.deepEqual(h.vm.orders,[]);assert.equal(h.timers.size,0)
 h.app.unmount();assert.equal(h.unsubscribed,true);assert.equal(h.win.count+h.doc.count,0)
})

test('cashier tab/query reuse cannot apply an old fetch and logout cannot resurrect session',async t=>{
 const pending=deferred();let initial=true
 const h=await mount('cashier',{fetch:async()=>{if(initial){initial=false;return [snapshot()]};return pending.promise}});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');h.vm.load();await flush();const old=h.requests.at(-1)
 h.vm.tab='history';await flush();h.vm.offset=100;await flush();assert.equal(old.options.signal.aborted,true)
 assert.equal(h.requests.at(-1).options.query.tab,'history');assert.equal(h.requests.at(-1).options.query.offset,100)
 await h.vm.logout();pending.resolve([snapshot('old',90)]);await flush();assert.deepEqual(h.vm.orders,[]);assert.equal(h.vm.loggedIn,false)
})


test('cashier preserves explicit selection and resets POS confirmations when the order version changes',async t=>{
 let queue=[snapshot('A')]
 const h=await mount('cashier',{fetch:async()=>queue});t.after(()=>h.app.unmount())
 assert.equal(h.vm.selectedOrder.id,'A');h.vm.posReference.A='POS-draft';h.vm.posEntered=true;h.vm.posPaid=true
 queue=[snapshot('B'),snapshot('A',2)];h.vm.load();await flush()
 assert.equal(h.vm.selectedOrder.id,'A');assert.equal(h.vm.posReference.A,'POS-draft')
 assert.equal(h.vm.posEntered,false);assert.equal(h.vm.posPaid,false)
 queue=[snapshot('B')];h.vm.load();await flush()
 assert.equal(h.vm.selectedOrder,null);assert.equal(h.vm.selectionMissing,true)
 assert.match(text(h.root),/Pilih pesanan untuk melanjutkan/)
 h.vm.selectOrder('B');await flush();assert.equal(h.vm.selectedOrder.id,'B')
 const n=h.requests.length;await h.vm.posAction(queue[0],'forward-pos');await flush()
 assert.equal(h.requests.length,n,'unclaimed order cannot be forwarded')
})

test('serverless customer skips unchanged snapshots and pauses while hidden without sockets',async t=>{
 let revision='1',snapshots=0
 const h=await mount('order',{syncMode:'polling',fetch:async url=>url.endsWith('/sync')?{revision,terminal:false}:(snapshots++,snapshot('A',Number(revision)))})
 t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,0);assert.equal(snapshots,1)
 h.win.fire('online');await flush();assert.equal(snapshots,1)
 revision='2';h.win.fire('online');await flush();assert.equal(snapshots,2);assert.equal(h.vm.order.version,2)
 h.doc.visibilityState='hidden';h.doc.fire('visibilitychange');const count=h.requests.length
 h.win.fire('online');await flush();assert.equal(h.requests.length,count)
 h.doc.visibilityState='visible';h.doc.fire('visibilitychange');await flush();assert.ok(h.requests.length>count)
})

test('customer keeps the last known order during a network failure and retries the same capability',async t=>{
 let fail=false
 const h=await mount('order',{fetch:async()=>{if(fail)throw Error('offline');return snapshot('A',2)}});t.after(()=>h.app.unmount())
 fail=true;h.win.fire('online');await flush()
 assert.equal(h.vm.order.id,'A');assert.ok(h.vm.loadError)
 assert.match(text(h.root),/Status belum diperbarui/)
 assert.match(text(h.root),/Informasi terakhir diperbarui/)
 assert.match(text(h.root),/Detail Pesanan/)
 fail=false;h.vm.retryOrder();await flush()
 assert.equal(h.vm.loadError,'');assert.equal(h.vm.order.id,'A')
 assert.equal(h.requests.at(-1).options.headers['X-Order-Token'],'cap-A')
})
