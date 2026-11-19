import test from 'node:test'
import assert from 'node:assert/strict'
import { createQueryCache } from '../frontend/shared/query-cache.ts'
import { normalizeCatalog,normalizeDashboard,normalizeOrders,normalizeSettings,normalizeCategories,reportForCashier,reportCSV } from '../frontend/shared/dashboard-data.ts'
const tick=async()=>{for(let i=0;i<12;i++)await Promise.resolve()}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return{promise,resolve,reject}}
const store=options=>{const cache=createQueryCache(options);cache.bind('staff:cashier:1');return cache}

test('navigation and prefetch share fresh cache and one in-flight request, and SWR retains the last success',async()=>{
 let now=1000,hits=0;const cache=store({now:()=>now}),pending=deferred()
 const loader=()=>{hits++;return pending.promise}
 const a=cache.fetch('catalog',loader),b=cache.fetch('catalog',loader)
 await tick();assert.equal(hits,1)
 pending.resolve({products:['real']});assert.deepEqual(await a,await b)
 await cache.fetch('catalog',loader);assert.equal(hits,1)
 now+=61000
 const read=cache.fetch('catalog',async()=>{throw{statusCode:503}},{retries:0})
 assert.deepEqual(cache.peek('catalog').data,{products:['real']})
 await assert.rejects(read);assert.equal(cache.peek('catalog').error.statusCode,503)
 assert.deepEqual(cache.peek('catalog').data,{products:['real']})
})
test('retry backoff is bounded; access/input errors and invalid responses never retry',async()=>{
 const delays=[];const cache=store({random:()=>0.5,sleep:async ms=>delays.push(ms)})
 let hits=0
 await assert.rejects(cache.fetch('offline',async()=>{hits++;throw{statusCode:503}}))
 assert.equal(hits,3);assert.deepEqual(delays,[500,1000])
 for(const error of [{statusCode:400},{invalidData:true},{statusCode:403}]){
  cache.bind('staff:cashier:1');hits=0
  await assert.rejects(cache.fetch('bad',async()=>{hits++;throw error}))
  assert.equal(hits,1)
 }
 assert.equal(cache.scope,'');assert.equal(cache.size,0)
})
test('shared cancellation keeps another consumer alive; final cancellation and invalidation reject late responses',async()=>{
 const cache=store(),pending=deferred(),a=new AbortController(),b=new AbortController();let signal
 const load=s=>{signal=s;return pending.promise}
 const one=cache.fetch('orders',load,{signal:a.signal}),two=cache.fetch('orders',load,{signal:b.signal})
 await tick();a.abort();await assert.rejects(one,{name:'AbortError'});assert.equal(signal.aborted,false)
 b.abort();await assert.rejects(two,{name:'AbortError'});assert.equal(signal.aborted,true)
 const old=deferred(),flight=cache.fetch('orders',()=>old.promise);await tick()
 cache.invalidate('orders');cache.set('orders',{version:2});old.resolve({version:1})
 await assert.rejects(flight,{name:'AbortError'});assert.equal(cache.peek('orders').data.version,2)
})
test('account changes purge all private snapshots and pending results cannot repopulate them',async()=>{
 const cache=store(),old=deferred()
 cache.set('staff',[{name:'private'}]);const read=cache.fetch('report',()=>old.promise);await tick()
 cache.bind('another:admin:2');old.resolve({private:true})
 await assert.rejects(read,{name:'AbortError'});assert.equal(cache.size,0);assert.equal(cache.peek('staff').data,null)
})
test('optimistic rollback is immediate and cannot overwrite a newer mutation or different account',async()=>{
 const cache=store();cache.set('catalog',{name:'original'})
 const pending=deferred(),mutation=cache.optimistic('catalog',v=>({...v,name:'draft'}),()=>pending.promise)
 assert.equal(cache.peek('catalog').data.name,'draft')
 pending.reject(Error('offline'));await assert.rejects(mutation);assert.equal(cache.peek('catalog').data.name,'original')
 const next=deferred(),older=cache.optimistic('catalog',v=>({...v,name:'older'}),()=>next.promise)
 cache.set('catalog',{name:'newer'});next.reject(Error('late'));await assert.rejects(older)
 assert.equal(cache.peek('catalog').data.name,'newer')
})
test('cache bounds evict old datasets and schema validation rejects malformed financial payloads',()=>{
 const cache=store({maxEntries:2});cache.set('a',{});cache.set('b',{});cache.set('c',{})
 assert.equal(cache.size,2);assert.equal(cache.peek('a').data,null)
 for(const normalize of [normalizeCatalog,normalizeDashboard,normalizeOrders])for(const value of [null,{},[null]])assert.throws(()=>normalize(value))
})
test('cashier report filter and CSV use loaded payments, exact rupiah and spreadsheet-safe text',()=>{
 const report={summary:{},payments:[{cashier_id:'a',order_number:'=HYPERLINK("bad")',paid_at:'2026-10-31T17:01:00Z',total:12000,received:20000,change:8000,cashier_name:'Raka'},{cashier_id:'b',total:5000,received:5000,change:0}],by_cashier:[{id:'a'},{id:'b'}]}
 const filtered=reportForCashier(report,'a')
 assert.deepEqual(filtered.summary,{count:1,revenue:'12000',received:'20000',change:'8000'})
 const csv=reportCSV(filtered);assert.match(csv,/'=HYPERLINK/);assert.match(csv,/2026-11-01 00:01:00/)
 assert.equal(filtered.payments.length,1);assert.equal(report.payments.length,2)
})
test('invalid tariffs cannot silently become zero and valid negative category positions remain readable',()=>{
 const settings={id:1,brand_name:'Test',tax_pct:'10.00',service_pct:'0.00',require_customer_name:false}
 assert.equal(normalizeSettings(settings).tax_pct,10)
 for(const value of [null,false,'',undefined,'bad'])assert.throws(()=>normalizeSettings({...settings,tax_pct:value}))
 assert.equal(normalizeCategories([{id:'a',name:'Priority',slug:'priority',is_active:true,sort_order:-10}])[0].sort_order,-10)
})
