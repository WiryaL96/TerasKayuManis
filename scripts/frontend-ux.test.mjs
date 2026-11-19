import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import * as Vue from 'vue'
import ts from 'typescript'
import * as selections from '../frontend/shared/product-selection.ts'
import {installDashboard,imports as dashboardImports} from './helpers/dashboard-cache.mjs'
import * as operations from '../frontend/shared/operations.ts'

// Execute production code; replace only Nuxt/browser/network boundaries.
function evaluate(path, exposed, bindings = {}, composable = false) {
  let source = readFileSync(new URL('../frontend/app/' + path, import.meta.url), 'utf8')
  if (!composable) source = source.match(/<script setup lang="ts">([\s\S]*?)<\/script>/)[1]
  source = source.replace(/^import .*$/gm, '').replace(/^export /gm, '').replaceAll('import.meta.client', bindings.document ? 'true' : 'false')
  const script = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText
  const env = { ...Vue, useCustomerFooter:()=>{}, definePageMeta: () => {}, useHead: () => {}, onMounted: () => {}, onUnmounted: () => {}, ...dashboardImports['#shared/dashboard-data'],...dashboardImports['#shared/query-cache'],useRoute:()=>({query:{}}),useSupabase:()=>({auth:{getSession:async()=>({data:{session:null}})}}),...bindings }
  installDashboard(env)
  if(path.startsWith('pages/admin/'))env.useDashboardCache().cache.bind('root:superadmin:1')
  const keys = Object.keys(env).filter(key => /^[\w$]+$/.test(key))
  return new Function(...keys, script + ';return {' + exposed + '}')(...keys.map(key => env[key]))
}
function cart() {
  const states = new Map()
  return evaluate('composables/useCart.ts', 'useCart', { useState(key, init) {
    if (!states.has(key)) states.set(key, Vue.ref(init()))
    return states.get(key)
  } }, true).useCart()
}
const product = { id: 'coffee', price: 10000, is_available: true, variants: [], addons: [] }
const item = (notes = '', qty = 1) => ({ productId: product.id, variantIds: [], addonIds: [], qty, notes })

test('cart edits replace one line, merge matching choices, and preserve quantities at the limit', () => {
  const c = cart()
  c.add(item('less sugar', 2)); c.add(item('normal', 3))
  assert.equal(c.update(c.lines.value[0].key, item('normal', 2)), true)
  assert.equal(c.lines.value.length, 1); assert.equal(c.lines.value[0].qty, 5)
  c.add(item('different', 49))
  assert.equal(c.update(c.lines.value[0].key, item('different', 2)), false)
  assert.equal(c.lines.value.length, 2); assert.equal(c.lines.value[0].qty, 5)
  assert.equal(c.update('deleted-item', item()), false)
})

test('cart deletion can be undone, including when matching items were added afterwards', () => {
  const c = cart(); c.add(item('same', 2))
  const removed = structuredClone(Vue.toRaw(c.lines.value[0]))
  c.setQty(removed.key, 0); assert.equal(c.lines.value.length, 0)
  c.add(item('same', 1)); assert.equal(c.restore(removed, 0), true)
  assert.equal(c.lines.value[0].qty, 3)
  c.setQty(removed.key, 50); assert.equal(c.restore(removed, 0), false)
  assert.equal(c.lines.value[0].qty, 50)
})

test('editing a cart item restores its choices and returns to the cart without duplication', async () => {
  const c = cart(); c.add(item('original note', 3))
  const route = Vue.reactive({ params: { id: 'coffee' }, query: { edit: c.lines.value[0].key, returnTo: '/cart' } })
  const destinations = [], scope = Vue.effectScope()
  const page = scope.run(() => evaluate('pages/menu/[id].vue', 'refresh,selection,submit,error', {
    ...selections, useRoute: () => route, useCart: () => c,
    useMenu: () => ({ menu: Vue.ref({ products: [product] }), loading: Vue.ref(false), load: async () => {} }),
    sessionStorage: { getItem: () => null }, navigateTo: async path => destinations.push(path),
  }))
  try {
    await page.refresh(); assert.equal(page.selection.value.qty, 3); assert.equal(page.selection.value.notes, 'original note')
    page.selection.value.notes = 'updated'; await page.submit()
    assert.equal(c.lines.value.length, 1); assert.equal(c.lines.value[0].notes, 'updated')
    assert.deepEqual(destinations, ['/cart'])
  } finally { scope.stop() }
})

test('recommendation return destinations are restricted and unfinished checkout blocks cart changes', async () => {
  for (const [destination, expected] of [['/checkout', '/checkout'], ['/cart', '/cart'], ['https://evil.test', '/menu']]) {
    const c = cart(), route = { params: { id: 'coffee' }, query: { returnTo: destination } }
    let pending = false
    const destinations = [], scope = Vue.effectScope()
    const page = scope.run(() => evaluate('pages/menu/[id].vue', 'refresh,submit,error', {
      ...selections, useRoute: () => route, useCart: () => c,
      useMenu: () => ({ menu: Vue.ref({ products: [product] }), loading: Vue.ref(false), load: async () => {} }),
      sessionStorage: { getItem: () => pending ? 'unresolved attempt' : null }, navigateTo: async path => destinations.push(path),
    }))
    try {
      await page.refresh(); pending = true; await page.submit()
      assert.equal(c.lines.value.length, 0); assert.deepEqual(destinations, [])
      pending = false; await page.submit(); assert.deepEqual(destinations, [expected])
    } finally { scope.stop() }
  }
})

test('report export follows the displayed cached period and local cashier filter without additional API calls', async () => {
 let resolve,query,hits=0
 const scope=Vue.effectScope()
 const page=scope.run(()=>evaluate('pages/admin/reports.vue','from,to,cashier,load,csv,applied,filtersChanged',{
  ...operations,$fetch:async(_url,options)=>{hits++;query={...options.query};return new Promise(r=>resolve=r)}
 }))
 const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();await Vue.nextTick()}
 try{
  page.from.value='2026-10-01';page.to.value='2026-10-01';const loading=page.load();await flush()
  page.from.value='2026-10-02';page.to.value='2026-10-02';page.cashier.value='second'
  const payment=id=>({cashier_id:id,cashier_name:id,order_id:id,order_number:id,paid_at:'2026-10-01T03:00:00Z',total:10000,received:10000,change:0})
  resolve({summary:{count:2,revenue:'20000',received:'20000',change:'0'},payments:[payment('first'),payment('second')],handoffs:['first','second'].map(id=>({...payment(id),forwarded_at:'2026-10-01T03:00:00Z',pos_reference:null})),by_cashier:[{id:'first',name:'first',count:1,revenue:'10000'},{id:'second',name:'second',count:1,revenue:'10000'}],counts:{},active_total:0,today_total:0,popular:[]});await loading;await flush()
  assert.equal(page.applied.value.from,query.from);assert.equal(page.applied.value.to,query.to);assert.equal(query.paged,'1');assert.equal(query.offset,0)
  const csv=decodeURIComponent(page.csv.value.split(',').slice(1).join(','))
  assert.match(csv,/second/);assert.doesNotMatch(csv,/first/);assert.equal(hits,1)
  assert.equal(page.filtersChanged.value,true)
 }finally{scope.stop()}
})

test('admin sheet opens as a native modal and restores focus and scrolling on close or unmount', async () => {
  for (const unmount of [false, true]) {
    const props = Vue.reactive({ open: true, title: 'Edit' }), cleanup = []
    let focused = '', modalCalls = 0
    const trigger = { isConnected: true, focus() { focused = 'trigger' } }
    const document = { body: { style: { overflow: 'auto' } }, activeElement: trigger }
    const element = { open: false, showModal() { this.open = true; modalCalls++ }, close() { this.open = false }, querySelector() { return { focus() { focused = 'input' } } } }
    const scope = Vue.effectScope()
    const sheet = scope.run(() => evaluate('components/AppSheet.vue', 'dialog', {
      document, useRoute:()=>({path:'/admin/staff'}), defineProps: () => props, defineEmits: () => () => {},
      onBeforeUnmount: fn => cleanup.push(fn), matchMedia: () => ({ matches: true }),
      getComputedStyle: () => ({ transform: 'none', opacity: '1' }),
    }))
    sheet.dialog.value = element
    try {
      await Vue.nextTick(); await Vue.nextTick()
      assert.equal(modalCalls, 1); assert.equal(focused, 'input'); assert.equal(document.body.style.overflow, 'hidden')
      if (unmount) cleanup.forEach(fn => fn())
      else { props.open = false; await Vue.nextTick(); await Vue.nextTick() }
      assert.equal(element.open, false); assert.equal(focused, 'trigger'); assert.equal(document.body.style.overflow, 'auto')
    } finally { cleanup.forEach(fn => fn()); scope.stop() }
  }
})
