import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import ts from 'typescript'
import * as Vue from 'vue'
import * as dashboard from '../frontend/shared/dashboard.ts'
import * as operations from '../frontend/shared/operations.ts'
import {installDashboard,imports as dashboardImports} from './helpers/dashboard-cache.mjs'

function execute(path, environment, imports = {}) {
  const source = readFileSync(new URL('../' + path, import.meta.url), 'utf8')
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText
  const module = { exports: {} }
  const bindings=Object.entries(environment).filter(([key])=>/^[A-Za-z_$][\w$]*$/.test(key))
  new Function('require', 'module', 'exports', ...bindings.map(([key])=>key), js)(id => ({...dashboardImports,...imports})[id], module, module.exports, ...bindings.map(([,value])=>value))
  return module.exports
}
const createError = e => Object.assign(new Error(e.statusMessage), e)

test('daily sales use WIB payment dates, include empty days, and keep exact rupiah sums', () => {
  const payments = [
    { paid_at: '2026-10-30T16:59:59Z', total: 10000 },
    { paid_at: '2026-10-30T17:00:00Z', total: 20000 },
    { paid_at: '2026-10-31T16:59:59Z', total: 5000 },
    { paid_at: '2026-10-31T17:00:00Z', total: 99999 },
  ]
  assert.deepEqual(dashboard.dailySales(payments, '2026-10-29', '2026-10-31'), [
    { date: '2026-10-29', revenue: '0', count: 0 }, { date: '2026-10-30', revenue: '10000', count: 1 }, { date: '2026-10-31', revenue: '25000', count: 2 },
  ])
  assert.equal(dashboard.averageSale('10000000000000000001', 3), '3333333333333333333')
  assert.equal(dashboard.averageSale('0', 0), '0')
  assert.equal(dashboard.sharePercent('0', '0'), 0)
  assert.equal(dashboard.sharePercent('10000000000000000000', '20000000000000000000'), 50)
  assert.deepEqual(dashboard.dashboardPeriod(7, '2026-11-02'), { from: '2026-10-27', to: '2026-11-02' })
  assert.equal(dashboard.dailySales([], '2026-01-01', '2026-03-01').length, 0)
})

test('dashboard navigation reuses each period, aborts old ranges, retains last good data and removes listeners', async () => {
 const pending=[],mounted=[],cleanup=[],listeners=new Map(),timers=new Map()
 const surface={visibilityState:'visible',addEventListener:(k,f)=>listeners.set(k,f),removeEventListener:k=>listeners.delete(k)}
 const env={...Vue,onMounted:fn=>mounted.push(fn),onUnmounted:fn=>cleanup.push(fn),document:surface,window:surface,
 setInterval:fn=>{timers.set(1,fn);return 1},clearInterval:id=>timers.delete(id),$fetch:(_url,options)=>new Promise((resolve,reject)=>pending.push({resolve,reject,options}))}
 installDashboard(env);env.useDashboardCache().cache.bind('root:superadmin:1')
 const api=execute('frontend/app/composables/useRestaurantDashboard.ts',env,{'#shared/dashboard':dashboard,'#shared/operations':operations}).useRestaurantDashboard()
 const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();await Vue.nextTick()}
 const data=(period,revenue)=>({role:'superadmin',period,report:{summary:{count:1,revenue,received:revenue,change:'0'},by_cashier:[],payments:[],popular:[],counts:{},active_total:0,today_total:0},queue:{pending:0,processing:0,orders:[]},catalog:{published:1,draft:0,hidden:0,missing_photo:0},staff:{active:1,invited:0,disabled:0,active_cashiers:1},operation:{orders_enabled:false},generated_at:'2026-10-31T03:00:00Z'})
 mounted.forEach(fn=>fn());await flush();assert.equal(pending.length,1)
 api.range.value=30;await flush();assert.equal(pending[0].options.signal.aborted,true);assert.equal(api.data.value,null)
 pending[1].resolve(data(pending[1].options.query,'20000'));await flush()
 pending[0].resolve(data(pending[0].options.query,'99999'));await flush()
 assert.equal(api.data.value.report.summary.revenue,'20000')
 const hits=pending.length;await api.load();assert.equal(pending.length,hits)
 const refresh=api.refresh();await flush();pending[2].reject({statusCode:400});await refresh
 assert.equal(api.data.value.report.summary.revenue,'20000');assert.match(api.error.value,/Periksa koneksi/)
 surface.visibilityState='hidden';timers.get(1)();assert.equal(pending.length,3)
 cleanup.forEach(fn=>fn());assert.equal(listeners.size,0);assert.equal(timers.size,0)
 await api.refresh();assert.equal(pending.length,3)
})

test('dashboard preferences work with blocked storage and persist sidebar and scoped theme choices', () => {
  const mounted = [], state = new Map(), saved = new Map()
  let blocked = false
  const api = execute('frontend/app/composables/useDashboardPreferences.ts', {
    useState: (key, init) => { if (!state.has(key)) state.set(key, Vue.ref(init())); return state.get(key) },
    onMounted: fn => mounted.push(fn), window: { matchMedia: () => ({ matches: true }) },
    localStorage: { getItem: key => saved.get(key), setItem: (key, value) => { if (blocked) throw Error('blocked'); saved.set(key, value) } },
  }).useDashboardPreferences()
  mounted.forEach(fn => fn()); assert.equal(api.collapsed.value, true)
  api.toggleCollapsed(); api.toggleTheme()
  assert.equal(saved.get('tkm-sidebar'), 'expanded'); assert.equal(saved.get('tkm-dashboard-theme'), 'dark')
  blocked = true; assert.doesNotThrow(() => { api.toggleCollapsed(); api.toggleTheme() })
  assert.equal(api.collapsed.value, true); assert.equal(api.theme.value, 'light')
})

test('dashboard uses one private aggregate RPC, rejects cashiers, and never substitutes failed results',async()=>{
 for(const role of ['superadmin','admin','cashier']){
  let broken=false;const calls=[]
  const response={role,queue:{pending:2},...(role==='superadmin'?{activity:[],backup:{}}:{})}
  const handler=execute('backend/legacy-nuxt/api/admin/dashboard.get.ts',{
   defineEventHandler:fn=>fn,createError,setHeader:()=>{},getQuery:()=>({from:'2026-10-31',to:'2026-10-31',format:'csv'}),
   requireStaff:async(_e,roles)=>{if(!roles.includes(role))throw createError({statusCode:403});return{id:'actor',role}},
   serviceClient:()=>({rpc:async(name,args)=>{calls.push({name,args});return broken?{error:{code:'offline'}}:{data:response}}}),
  },{'#shared/operations':operations}).default
  if(role==='cashier'){await assert.rejects(handler({}),e=>e.statusCode===403);assert.equal(calls.length,0);continue}
  assert.equal(await handler({}),response)
  assert.deepEqual(calls,[{name:'dashboard_snapshot',args:{p_actor:'actor',p_from:'2026-10-31',p_to:'2026-10-31'}}])
  broken=true;await assert.rejects(handler({}),e=>e.statusCode===503)
 }
})
