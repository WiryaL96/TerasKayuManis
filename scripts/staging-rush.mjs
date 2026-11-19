// HTTP -> Nuxt BFF -> Go -> real Supabase Auth/Postgres. Synthetic staging only.
import {createClient} from '@supabase/supabase-js'
import {randomBytes,randomUUID} from 'node:crypto'
import {mkdir,writeFile} from 'node:fs/promises'
import {resolve} from 'node:path'
import {fileURLToPath} from 'node:url'
import {setTimeout as delay} from 'node:timers/promises'

export function validateTarget(env){
 const site=new URL(env.STAGING_BASE_URL),auth=new URL(env.STAGING_SUPABASE_URL)
 const production='aiptdjypuccoakyfvdyl'
 if(env.STAGING_PROJECT_REF===production||auth.hostname===production+'.supabase.co')throw Error('Production database is forbidden')
 const local=site.hostname==='127.0.0.1'&&site.port==='3218'&&auth.hostname==='127.0.0.1'&&auth.port==='54321'
 if(!local&&(site.protocol!=='https:'||!site.hostname.includes('staging')||auth.hostname!==env.STAGING_PROJECT_REF+'.supabase.co'||env.STAGING_ALLOW_WRITES!==env.STAGING_PROJECT_REF))throw Error('Explicit isolated staging project required')
 if(!env.STAGING_SUPABASE_SERVICE_KEY||!env.STAGING_SUPABASE_ANON_KEY)throw Error('Private staging configuration missing')
 return {site:site.origin,auth:auth.origin,local}
}

export async function run(env=process.env){
 const target=validateTarget(env)
 const seconds=Number(env.STAGING_RUSH_SECONDS||300)
 if(!Number.isInteger(seconds)||seconds<60||seconds>900)throw Error('Duration must be 60..900 seconds')
 const active=Number(env.STAGING_RUSH_CUSTOMERS||100),burst=active*2
 if(!Number.isInteger(active)||active<10||active>200)throw Error('Customers must be 10..200')
 const boundedFetch=(input,options)=>fetch(input,{...options,signal:options?.signal?AbortSignal.any([options.signal,AbortSignal.timeout(20000)]):AbortSignal.timeout(20000)})
 const admin=createClient(target.auth,env.STAGING_SUPABASE_SERVICE_KEY,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:boundedFetch}})
 const tag='rush-'+randomUUID().slice(0,12),cashiers=[],customers=[],queue=[],metrics=new Map(),checks={}
 const started=Date.now()
 let category,product,basePayments,report
 const requireResult=({data,error})=>{if(error)throw Error('Staging fixture or verification failed');return data}
 const exactCount=async table=>{const r=await admin.from(table).select('id',{count:'exact',head:true});if(r.error)throw Error('Staging count failed');return r.count}
 async function call(name,path,{method='GET',actor,token,key,body,statuses=[200]}={}){
  const before=performance.now();let status=0,data=null
  try{
   const response=await fetch(target.site+'/api/core/'+path,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{Origin:target.site,'Content-Type':'application/json',...(actor?{Authorization:'Bearer '+actor.token}:{}),...(token?{'X-Order-Token':token}:{}),...(key?{'Idempotency-Key':key}:{})},body:body===undefined?undefined:JSON.stringify(body)})
   status=response.status;data=await response.json().catch(()=>null)
  }catch{}
  const metric=metrics.get(name)||{latencies:[],errors:0,requests:0,statuses:{}}
  metric.latencies.push(performance.now()-before);metric.requests++;metric.statuses[status]=(metric.statuses[status]||0)+1
  if(!statuses.includes(status))metric.errors++
  metrics.set(name,metric);return {status,data}
 }
 async function seedCashiers(){
  for(let i=0;i<5;i++){
   const email=tag+'-'+i+'@example.test',password=randomBytes(32).toString('base64url'),name='Staging Cashier '+i
   const user=requireResult(await admin.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{staff_session_version:1}})).user
   cashiers.push({id:user.id,name,email,token:''})
   requireResult(await admin.from('profiles').upsert({id:user.id,full_name:name,role:'cashier',staff_status:'active',session_version:1}))
   const client=createClient(target.auth,env.STAGING_SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:boundedFetch}})
   const session=requireResult(await client.auth.signInWithPassword({email,password})).session
   cashiers[i].token=session.access_token
   // Verify the BFF/Go DB sees this fresh staging identity BEFORE any checkout.
   const probe=await call('staff_identity','admin/me',{actor:cashiers[i]})
   if(probe.status!==200||probe.data?.id!==user.id)throw Error('BFF does not point to the isolated staging database')
  }
 }
 const mapLimit=async(items,limit,worker)=>{let index=0;await Promise.all(Array.from({length:Math.min(items.length,limit)},async()=>{while(index<items.length){const i=index++;await worker(items[i],i)}}))}
 async function seedCustomers(from,to){
  await mapLimit(Array.from({length:to-from},(_,i)=>from+i),25,async i=>{
   const token=randomBytes(32).toString('hex'),key=randomUUID()
   const body={customer_name:tag+'-'+i,payment_method:'cash',items:[{product_id:product.id,quantity:1,variant_ids:[],addon_ids:[],notes:'Synthetic staging load'}]}
   const response=await call('checkout','orders',{method:'POST',token,key,body,statuses:[200,201]})
   if(response.data?.id){customers[i]={id:response.data.id,token,key,body};queue.push(customers[i])}
  })
 }
 async function processOrder(customer,actor){
  const review=await call('review','orders/'+customer.id+'/review',{method:'POST',actor,body:{expected_version:1,items:customer.body.items}})
  if(review.status!==200)return
  const claim=await call('claim','orders/'+customer.id+'/claim-pos',{method:'POST',actor,body:{expected_version:2}})
  if(claim.status!==200)return
  const body={expected_version:3,entered_in_pos:true,paid_in_pos:true,pos_reference:tag+'-'+customer.id}
  const forwarded=await call('forward','orders/'+customer.id+'/forward-pos',{method:'POST',actor,body})
  if(forwarded.status===200){
   customer.cashier=actor.id
   await call('forward_retry','orders/'+customer.id+'/forward-pos',{method:'POST',actor,body})
  }
 }
 try{
  await seedCashiers()
  basePayments=await exactCount('payments')
  requireResult(await admin.from('settings').update({orders_enabled:true,pricing_confirmed_at:new Date().toISOString()}).eq('id',1))
  category=requireResult(await admin.from('categories').insert({name:tag,slug:tag,is_active:true,sort_order:999}).select().single())
  product=requireResult(await admin.from('products').insert({category_id:category.id,name:'Synthetic Rush Item',slug:tag,price:10000,price_confirmed:true,is_available:true}).select().single())
  await seedCustomers(0,active)
  if(customers.filter(Boolean).length!==active)throw Error('Initial checkout burst failed')
  const raced=queue.shift()
  const reviewed=await call('race_review','orders/'+raced.id+'/review',{method:'POST',actor:cashiers[0],body:{expected_version:1,items:raced.body.items}})
  if(reviewed.status!==200)throw Error('Race fixture review failed')
  const claims=await Promise.all(cashiers.slice(0,2).map(actor=>call('race_claim','orders/'+raced.id+'/claim-pos',{method:'POST',actor,body:{expected_version:2},statuses:[200,409]})))
  const winner=claims.findIndex(response=>response.status===200)
  checks.single_winner_on_concurrent_claim=claims.filter(response=>response.status===200).length===1&&claims.filter(response=>response.status===409).length===1
  if(checks.single_winner_on_concurrent_claim){
   const actor=cashiers[winner],body={expected_version:3,entered_in_pos:true,paid_in_pos:true,pos_reference:tag+'-race'}
   const forwarded=await call('race_forward','orders/'+raced.id+'/forward-pos',{method:'POST',actor,body})
   if(forwarded.status===200)raced.cashier=actor.id
   await call('race_forward_retry','orders/'+raced.id+'/forward-pos',{method:'POST',actor,body})
  }
  const until=Date.now()+seconds*1000
  const loops=Array.from({length:burst},async(_,i)=>{
   await delay(i%20*50);let revision=''
   while(Date.now()<until){
    const customer=customers[i]
    if(!customer){await delay(Math.min(1000,Math.max(0,until-Date.now())));continue}
    const r=await call('customer_sync','orders/'+customer.id+'/sync',{token:customer.token})
    if(r.status===200&&revision!==r.data?.revision){revision=r.data?.revision;await call('order_detail','orders/'+customer.id,{token:customer.token})}
    await delay(Math.min(15000,Math.max(0,until-Date.now())))
   }
  })
  for(const actor of cashiers)loops.push((async()=>{
   let revision=''
   while(Date.now()<until){
    const r=await call('cashier_sync','admin/sync',{actor})
    if(r.status===200&&revision!==r.data?.revision){revision=r.data?.revision;await call('cashier_listing','admin/orders',{actor})}
    const customer=queue.shift();if(customer)await processOrder(customer,actor)
    await delay(Math.min(5000,Math.max(0,until-Date.now())))
   }
  })())
  loops.push((async()=>{await delay(seconds*500);await seedCustomers(active,burst)})())
  await Promise.all(loops)
  // A lost response/retry must still resolve to the same order.
  const first=customers[0]
  const retry=await call('checkout_retry','orders',{method:'POST',token:first.token,key:first.key,body:first.body,statuses:[200,201]})
  checks.idempotent_checkout=retry.data?.id===first.id
  requireResult(await admin.from('profiles').update({full_name:'Changed after transaction'}).eq('id',cashiers[0].id))
  const verified=[],ids=customers.filter(Boolean).map(c=>c.id)
  for(let offset=0;offset<ids.length;offset+=100)verified.push(...requireResult(await admin.from('order_pos_handoffs').select('order_id,cashier_id,cashier_name').in('order_id',ids.slice(offset,offset+100))))
  const names=new Map(cashiers.map(actor=>[actor.id,actor.name]))
  checks.no_duplicate_handoffs=new Set(verified.map(item=>item.order_id)).size===verified.length
  checks.cashier_identity_correct=verified.every(item=>names.get(item.cashier_id)===item.cashier_name&&customers.find(c=>c?.id===item.order_id)?.cashier===item.cashier_id)
  checks.no_web_payments=(await exactCount('payments'))===basePayments
  checks.all_checkouts_created=customers.filter(Boolean).length===burst
  checks.no_duplicate_orders=new Set(customers.filter(Boolean).map(c=>c.id)).size===burst
  checks.handoffs_completed=verified.length>0
  // Real Auth token must stop working immediately when the DB profile is disabled.
  requireResult(await admin.from('profiles').update({staff_status:'disabled'}).eq('id',cashiers[0].id))
  const disabled=await call('disabled_token','admin/me',{actor:cashiers[0],statuses:[401,403]})
  checks.old_token_revoked=[401,403].includes(disabled.status)
  const routes=Object.fromEntries([...metrics].map(([name,m])=>{m.latencies.sort((a,b)=>a-b);const percentile=p=>Math.round(m.latencies[Math.floor((m.latencies.length-1)*p)]);return [name,{requests:m.requests,errors:m.errors,statuses:m.statuses,p50_ms:percentile(.5),p95_ms:percentile(.95),p99_ms:percentile(.99)}]}))
  const total=[...metrics.values()].reduce((n,m)=>n+m.requests,0),errors=[...metrics.values()].reduce((n,m)=>n+m.errors,0)
  report={tag,environment:target.local?'local full stack with real Supabase Auth':'remote staging, Nuxt BFF + Go + real Supabase',origin:target.site,duration_seconds:Math.round((Date.now()-started)/1000),active_customers:active,burst_customers:burst,cashiers:5,checkout_concurrency:25,total_requests:total,errors,error_rate:errors/total,checks,routes,passed:errors===0&&Object.values(checks).every(Boolean)&&Object.entries(routes).every(([name,m])=>m.p95_ms<=Number(env.STAGING_P95_LIMIT_MS||2000)||name==='disabled_token')}
 }finally{
  // Fixture accounts remain unusable after a run, including a failed run.
  let clean=true
  for(const actor of cashiers){const profile=await admin.from('profiles').update({staff_status:'disabled',session_version:2}).eq('id',actor.id);const auth=await admin.auth.admin.deleteUser(actor.id);if(profile.error||auth.error)clean=false}
  if(report){report.checks.fixture_accounts_disabled=clean;report.passed&&=clean;const path=resolve(env.STAGING_RUSH_REPORT||'.cache/staging-rush-result.json');await mkdir(resolve(path,'..'),{recursive:true});await writeFile(path,JSON.stringify(report,null,2),'utf8');console.log(JSON.stringify({report:path,passed:report.passed,requests:report.total_requests,errors:report.errors,checks:report.checks}))}
 }
 return report
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const report=await run();if(!report.passed)process.exitCode=1}catch{console.error('Staging load test failed. Production is excluded; inspect sanitized metrics.');process.exitCode=1}
}
