import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createPreview } from '../frontend/shared/preview-demo.ts'

function sandbox() {
  const storage = new Map()
  const app = createPreview({ getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value) })
  const request = async (path, body, headers = {}) => {
    const response = await app.fetch(new Request('https://preview.example' + path, { method: body ? 'POST' : 'GET', ...(body ? { body: JSON.stringify(body) } : {}), headers: { 'Content-Type': 'application/json', ...headers } }))
    return { status: response.status, data: await response.json() }
  }
  const login = async () => {
    const result = await request('/api/auth/staff-login', { email: 'owner.demo', password: 'preview123' })
    await app.client.auth.setSession(result.data.session)
    return result.data.profile
  }
  return { app, request, login, storage }
}
test('preview isolates two browsers, requires sample credentials, and never stores submitted passwords', async () => {
  const a = sandbox(), b = sandbox()
  assert.equal((await a.request('/api/admin/me')).status, 401)
  assert.equal((await a.request('/api/auth/staff-login', { email: 'owner.demo', password: 'wrong' })).status, 401)
  await a.login()
  assert.equal((await a.request('/api/admin/me')).data.profile.role, 'superadmin')
  assert.equal((await b.request('/api/admin/me')).status, 401)
  assert.equal((await a.request('/api/admin/staff', { full_name: 'Contoh', username: 'contoh', email: 'contoh@example.test', role: 'cashier', pin: '876543', password: 'do-not-save-me' })).status, 501)
  assert.equal([...a.storage.values()].join('').includes('do-not-save-me'), false)
  assert.equal([...a.storage.values()].join('').includes('876543'), false)
})
test('preview checkout retries create one order and cashier review/claim/forward updates the same browser report', async () => {
  const { request, login } = sandbox()
  const menu = (await request('/api/core/menu')).data
  const headers = { 'Idempotency-Key': 'checkout-1', 'X-Order-Token': 'example-capability' }
  const payload = { customer_name: 'Pelanggan Contoh', payment_method: 'cash', items: [{ product_id: menu.products[0].id, quantity: 2, variant_ids: [], addon_ids: [], notes: '' }] }
  const order = (await request('/api/core/orders', payload, headers)).data
  assert.equal((await request('/api/core/orders', payload, headers)).data.id, order.id)
  assert.equal((await request(`/api/core/orders/${order.id}`)).status, 401)
  await login()
  assert.equal((await request(`/api/core/orders/${order.id}/claim-pos`, { expected_version: 1 })).status, 409)
  const reviewed = (await request(`/api/core/orders/${order.id}/review`, { expected_version: 1, items: payload.items })).data
  assert.equal(reviewed.reviewed_version, reviewed.version)
  const claimed = (await request(`/api/core/orders/${order.id}/claim-pos`, { expected_version: reviewed.version })).data
  assert.equal(claimed.status, 'pos_input')
  const forwarded = await request(`/api/core/orders/${order.id}/forward-pos`, { expected_version: claimed.version, entered_in_pos: true, paid_in_pos: true, pos_reference: 'DEMO-POS-1' })
  assert.equal(forwarded.data.status, 'forwarded')
  assert.equal((await request(`/api/core/orders/${order.id}/forward-pos`, { expected_version: claimed.version, entered_in_pos: true, paid_in_pos: true })).status, 409)
  const report = (await request('/api/admin/reports')).data
  assert.equal(report.pos_summary.count, 1)
  assert.equal(report.pos_summary.total, String(order.total))
  assert.deepEqual(report.payments, [])
  assert.equal((await request(`/api/core/orders/${order.id}/receipt`)).status, 409)
})
test('preview can recover when browser storage is broken and does not forward unsupported requests', async () => {
  const app = createPreview({ getItem() { throw Error('blocked') }, setItem() { throw Error('blocked') } })
  assert.equal((await app.fetch(new Request('https://preview.example/api/core/menu'))).status, 200)
  const aborted = new AbortController(); aborted.abort()
  await assert.rejects(app.fetch(new Request('https://preview.example/api/core/menu', { signal: aborted.signal })), { name: 'AbortError' })
  assert.equal((await app.fetch(new Request('https://preview.example/api/admin/upload'))).status, 401)
})
test('demo is gated to preview builds and real server APIs fail closed in that mode', () => {
  const config = readFileSync(new URL('../frontend/nuxt.config.ts', import.meta.url), 'utf8')
  assert.match(config, /process\.env\.VERCEL_ENV === 'preview' && process\.env\.TKM_PREVIEW_DEMO === '1'/)
  const middleware = readFileSync(new URL('../backend/legacy-nuxt/middleware/preview.ts', import.meta.url), 'utf8')
  assert.match(middleware, /previewDemo && event\.path\.startsWith\('\/api\/'\)/)
  assert.match(middleware, /statusCode: 503/)
})
