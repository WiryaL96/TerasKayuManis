import { test, expect } from '@playwright/test'
import assert from 'node:assert/strict'
import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'
import { randomBytes, randomUUID } from 'node:crypto'

const base = process.env.E2E_BASE_URL, api = process.env.SUPABASE_URL
if (process.env.TKM_E2E_ALLOW_LOCAL !== '1' || base !== 'http://127.0.0.1:3218' || api !== 'http://127.0.0.1:54321')
  throw new Error('Refusing to test accounts outside the disposable local stack')
const boundedFetch = (url, options) => fetch(url, { ...options, signal: AbortSignal.timeout(20000) })
const admin = createClient(api, process.env.E2E_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: boundedFetch } })
async function bounded(promise, stage) {
  let timer
  try { return await Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`Timed out: ${stage} (credentials withheld)`)), 30000) })]) }
  finally { clearTimeout(timer) }
}
const password = () => randomBytes(24).toString('base64url')
const accounts = { superadmin: { name: 'Superadmin E2E', email: 'superadmin-e2e@example.test', password: password(), role: 'superadmin' },
  admin: { name: 'Admin E2E', username: 'admin.e2e', email: 'admin-e2e@example.test', password: password(), role: 'admin' },
  a: { name: 'Raka E2E', username: 'raka.e2e', email: 'raka-e2e@example.test', password: password() },
  b: { name: 'Sari E2E', username: 'sari.e2e', email: 'sari-e2e@example.test', password: password() } }

async function request(path, { body, cookie, token, method = body ? 'POST' : 'GET', expected = 200 } = {}) {
  let response = await fetch(base + path, { method, signal: AbortSignal.timeout(20000),
    headers: { Origin: base, ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(cookie ? { Cookie: cookie() } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined })
  // Keep real rate limiting enabled; several negative tests deliberately share
  // one loopback IP. Wait for its fixed minute budget rather than bypassing it.
  if (response.status === 429 && expected !== 429) {
    await new Promise(resolve => setTimeout(resolve, 61000))
    return request(path, { body, cookie, token, method, expected })
  }
  assert.equal(response.status, expected, `${method} ${path.split('?')[0]}: unexpected HTTP status (body withheld)`)
  return response.headers.get('content-type')?.includes('json') ? response.json() : response.text()
}
async function login(account, area = 'cashier') {
  const data = await request('/api/auth/staff-login', { body: { email: account.username || account.email, password: account.password, area } })
  const jar = new Map()
  const client = createServerClient(api, process.env.SUPABASE_ANON_KEY, { auth: { autoRefreshToken: false }, global: { fetch: boundedFetch }, cookies: {
    getAll: () => [...jar].map(([name, value]) => ({ name, value })), setAll: cookies => cookies.forEach(c => jar.set(c.name, c.value)),
  } })
  const { error } = await bounded(client.auth.setSession(data.session), 'install test session cookies')
  assert.equal(error?.name, undefined, 'Test session could not be installed')
  return { token: data.session.access_token, refresh: data.session.refresh_token, client,
    cookie: () => [...jar].map(([name, value]) => `${name}=${encodeURIComponent(value)}`).join('; ') }
}
async function provision(account) {
  const { data, error } = await admin.auth.admin.createUser({ email: account.email, password: account.password, email_confirm: true, app_metadata: { staff_session_version: 0 } })
  assert.equal(error?.name, undefined, 'Auth seed failed')
  account.id = data.user.id
  const inserted = await admin.from('profiles').insert({ id: account.id, full_name: account.name, email: account.email, role: account.role, staff_status: 'active' })
  assert.equal(inserted.error?.code, undefined, 'Profile seed failed')
}

test('three staff roles, real Auth lifecycle, two cashiers, audit and tablet layouts', async ({ browser }, info) => {
  console.log('E2E stage: provision isolated superadmin and managed admin')
  await provision(accounts.superadmin)
  const owner = await login(accounts.superadmin, 'admin')
  const invitedAdmin = await request('/api/admin/staff', { cookie: owner.cookie, body: { full_name: accounts.admin.name, email: accounts.admin.email, username: accounts.admin.username, password: accounts.admin.password, role: 'admin' } })
  accounts.admin.id = invitedAdmin.profile.id
  assert.equal(invitedAdmin.profile.staff_status, 'active')
  assert.ok(!('url' in invitedAdmin))
  const administrator = await login(accounts.admin, 'admin')
  await request('/api/admin/staff', { cookie: administrator.cookie, body: { full_name: 'Forbidden Admin', email: 'forbidden-admin@example.test', role: 'admin' }, expected: 403 })
  await request('/api/admin/staff', { cookie: owner.cookie, body: { full_name: 'Forbidden Root', email: 'forbidden-root@example.test', role: 'superadmin' }, expected: 400 })
  console.log('E2E stage: directly create two personal cashier accounts')
  for (const account of [accounts.a, accounts.b]) {
    const created = await request('/api/admin/staff', { cookie: account === accounts.a ? administrator.cookie : owner.cookie, body: { full_name: account.name, email: account.email, username: account.username, password: account.password, role: 'cashier' } })
    account.id = created.profile.id
    assert.equal(created.profile.staff_status, 'active')
    assert.equal(created.profile.username, account.username)
    assert.ok(!('url' in created) && !('password' in created.profile))
  }
  let a = await login(accounts.a), b = await login(accounts.b)
  console.log('E2E stage: verify role boundaries and cash transactions')
  const date = new Date(Date.now() + 7 * 3600000).toISOString().slice(0, 10)
  const activityPath = `/api/admin/activity?from=${date}&to=${date}`
  await request(activityPath, { cookie: a.cookie, expected: 403 })
  await request(activityPath, { cookie: administrator.cookie, expected: 403 })
  await request(activityPath, { expected: 401 })
  await request('/api/admin/backup-status', { cookie: administrator.cookie, expected: 403 })
  await request('/api/admin/crud/settings', { cookie: administrator.cookie, expected: 403 })
  await request('/api/admin/crud/settings/1', { method: 'PATCH', cookie: administrator.cookie, body: { brand_name: 'Forbidden edit' }, expected: 403 })
  await request('/api/admin/pricing', { cookie: administrator.cookie, body: { tax_pct: 0, service_pct: 0, require_customer_name: true, orders_enabled: false }, expected: 403 })
  await request(`/api/admin/staff/${accounts.superadmin.id}`, { method: 'PATCH', cookie: administrator.cookie, body: { command: 'disable' }, expected: 403 })
  await request(`/api/admin/staff/${accounts.superadmin.id}/password`, { cookie: administrator.cookie, body: { password: password() }, expected: 403 })
  const adminStaff = await request('/api/admin/staff', { cookie: administrator.cookie })
  const allStaff = await request('/api/admin/staff', { cookie: owner.cookie })
  assert.ok(adminStaff.length === 2 && adminStaff.every(p => p.role === 'cashier'), 'Admin could list higher-role accounts')
  assert.ok(allStaff.some(p => p.id === accounts.admin.id && p.role === 'admin'), 'Superadmin cannot list managed admins')
  const exposed = await createClient(api, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false }, global: { fetch: boundedFetch } }).rpc('manage_cashier', { p_actor: accounts.superadmin.id, p_target: accounts.a.id, p_command: 'disable' })
  assert.ok(exposed.error, 'Anonymous client could call staff management RPC')

  const cat = await admin.from('categories').insert({ name: 'E2E', slug: `e2e-${randomUUID()}` }).select('id').single()
  assert.ok(cat.data?.id, 'Test category unavailable')
  const prod = await admin.from('products').insert({ category_id: cat.data.id, name: 'Teh E2E', slug: `teh-${randomUUID()}`, price: 10000, is_available: true, price_confirmed: true }).select('id').single()
  assert.ok(prod.data?.id, 'Test menu unavailable')
  await request('/api/admin/pricing', { cookie: owner.cookie, body: { tax_pct: 0, service_pct: 0, require_customer_name: true, orders_enabled: true } })
  const items = [{ product_id: prod.data.id, quantity: 1, variant_ids: [], addon_ids: [], notes: '' }]
  const createOrder = async name => {
    const response = await fetch(base + '/api/core/orders', { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': randomUUID(), 'X-Order-Token': randomUUID() + randomUUID() }, body: JSON.stringify({ customer_name: name, payment_method: 'cash', items }) })
    assert.equal(response.status, 201, 'Customer checkout failed'); return response.json()
  }
  const orders = [await createOrder('Pelanggan A'), await createOrder('Pelanggan B'), await createOrder('Pelanggan Bersamaan')]
  for (const [i, order] of orders.entries()) await request(`/api/core/orders/${order.id}/review`, { token: i === 1 ? b.token : a.token, body: { expected_version: 1, items } })
  await Promise.all(orders.slice(0,2).map((order,i)=>request(`/api/core/orders/${order.id}/claim-pos`,{token:i?b.token:a.token,body:{expected_version:2}})))
  const race=await Promise.all([a,b].map(async session=>({session,response:await fetch(base+`/api/core/orders/${orders[2].id}/claim-pos`,{method:'POST',headers:{Authorization:'Bearer '+session.token,'Content-Type':'application/json'},body:JSON.stringify({expected_version:2})})})))
  assert.deepEqual(race.map(r=>r.response.status).sort(),[200,409],'Two cashiers could claim the same order')
  const winner=race.find(r=>r.response.status===200).session
  await Promise.all(orders.map((order,i)=>request(`/api/core/orders/${order.id}/forward-pos`,{token:i===2?winner.token:i?b.token:a.token,body:{expected_version:3,entered_in_pos:true,paid_in_pos:true,pos_reference:'POS-'+i}})))
  const payments=await admin.from('payments').select('order_id').in('order_id',orders.map(o=>o.id))
  assert.equal(payments.data?.length,0,'Manual POS handoff created local payments')
  const handoffs=await admin.from('order_pos_handoffs').select('*').in('order_id',orders.map(o=>o.id))
  assert.equal(handoffs.data?.length,3)
  for(const [i,account] of [accounts.a,accounts.b].entries()){
   const h=handoffs.data.find(h=>h.order_id===orders[i].id)
   assert.equal(h.cashier_id,account.id);assert.equal(h.cashier_name,account.name)
  }
  await request(`/api/admin/staff/${accounts.a.id}`,{method:'PATCH',cookie:owner.cookie,body:{command:'rename',full_name:'Raka Nama Baru'}})
  const historical=await admin.from('order_pos_handoffs').select('cashier_name').eq('order_id',orders[0].id).single()
  assert.equal(historical.data.cashier_name,'Raka E2E')
  await request(`/api/core/orders/${orders[0].id}/receipt`,{token:a.token,expected:404})
  const logs=await request(activityPath,{cookie:owner.cookie})
  assert.equal(logs.entries.filter(e=>e.action==='pos_forwarded').length,3)
  assert.equal(logs.entries.find(e=>e.order_id===orders[0].id&&e.action==='pos_forwarded').actor_name,'Raka E2E')
  for(const event of logs.entries)assert.ok(!JSON.stringify(event).includes('token_hash'),'Private token leaked in activity response')

  const awaitingPayment = await createOrder('Pelanggan UI')
  await request(`/api/core/orders/${awaitingPayment.id}/review`, { token: a.token, body: { expected_version: 1, items } })
  await request('/api/admin/dashboard', { cookie: a.cookie, expected: 403 })
  const rootDashboard = await request('/api/admin/dashboard', { cookie: owner.cookie })
  const adminDashboard = await request('/api/admin/dashboard', { cookie: administrator.cookie })
  assert.equal(rootDashboard.report.summary.revenue, '0')
  assert.equal(Number(rootDashboard.report.pos_summary.count),3)
  assert.equal(rootDashboard.report.pos_summary.total,'30000')
  assert.equal(rootDashboard.report.handoffs.length,0, 'Dashboard summary must not load raw transaction history')
  assert.equal(rootDashboard.queue.pending, 1)
  assert.equal(Date.parse(rootDashboard.queue.orders[0].expires_at), Date.parse(awaitingPayment.expires_at), 'Dashboard deadline diverged from the transaction API')
  assert.ok(rootDashboard.activity.length && rootDashboard.backup)
  assert.ok(!('activity' in adminDashboard) && !('backup' in adminDashboard), 'Admin dashboard exposed superadmin-only data')

  console.log('E2E stage: real browser login and tablet layouts')
  for (const [width, height] of [[1024, 768], [768, 1024]]) {
    const context = await browser.newContext({ baseURL: base, viewport: { width, height } })
    // Layout must remain usable when the external font CDN is unavailable.
    await context.route(/^https:\/\/fonts\.(googleapis|gstatic)\.com\//, route => route.abort())
    context.setDefaultTimeout(15000)
    context.setDefaultNavigationTimeout(30000)
    const page = await context.newPage()
    await page.goto('/cashier'); await page.getByRole('button', {name:'Masuk akun lama / admin'}).click(); await page.getByLabel('Username atau email').fill(accounts.b.username)
    await page.getByLabel('Password', { exact: true }).fill(accounts.b.password)
    await page.getByRole('button', { name: 'Login kasir' }).click()
    await expect(page.getByRole('heading', { name: /^Dashboard Kasir\.?$/ })).toBeVisible()
    await expect(page.locator('.cashier-account')).toContainText('Sari E2E')
    await expect(page.locator('.cashier-connection')).toContainText('Terhubung')
    if (width === 1024) {
      await page.getByRole('button', { name: 'Perluas sidebar', exact: true }).click()
      await expect(page.locator('[data-slot="sidebar"]')).toHaveAttribute('data-collapsed', 'false')
      await page.getByRole('button', { name: 'Ciutkan sidebar', exact: true }).click()
      await page.getByRole('button', { name: 'Gunakan tema gelap', exact: true }).click()
      await expect(page.locator('.cashier-shell')).toHaveAttribute('data-dashboard-theme', 'dark')
      await page.getByRole('button', { name: 'Gunakan tema terang', exact: true }).click()
      await page.getByRole('button', { name: 'Tampilkan pesanan menunggu kasir', exact: true }).click()
      await page.getByRole('button', { name: 'Lihat pesanan ' + awaitingPayment.order_number, exact: true }).click()
      page.once('dialog',dialog=>dialog.accept())
      await page.getByRole('button',{name:'Tangani pesanan ini',exact:true}).click()
      await expect(page.getByLabel('Semua menu sudah dimasukkan ke aplikasi kasir')).toBeVisible()
      await page.getByLabel('Semua menu sudah dimasukkan ke aplikasi kasir').check()
      await page.getByLabel('Pembayaran pelanggan sudah selesai di aplikasi kasir').check()
      page.once('dialog',dialog=>dialog.accept())
      await page.getByRole('button',{name:'Sudah masuk aplikasi kasir',exact:true}).click()
      await expect(page.getByText('Konfirmasi manual masuk aplikasi kasir oleh',{exact:false})).toBeVisible()
      await expect(page.locator('.cashier-payment')).toContainText('Sari E2E')
    }
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Cashier page overflows tablet width')
    await page.screenshot({ animations: 'disabled', path: info.outputPath(`cashier-${width}x${height}.png`), fullPage: true, timeout: 15000 })
    await page.getByRole('button', { name: 'Keluar', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Masuk ke Kasir' })).toBeVisible()
    await page.getByRole('button', {name:'Masuk akun lama / admin'}).click()
    await expect(page.getByRole('button', { name: 'Login kasir' })).toBeEnabled()
    await page.goto('/admin/login'); await page.getByLabel('Username atau email', { exact: true }).fill(accounts.superadmin.email)
    await page.getByLabel('Password', { exact: true }).fill(accounts.superadmin.password)
    await page.getByRole('button', { name: 'Masuk', exact: true }).click()
    await expect(page.getByTestId('dashboard-revenue')).toContainText(/40\.000/)
    await expect(page.locator('.tkm-chart-bars > button')).toHaveCount(7)
    const periodResponse = page.waitForResponse(response => response.url().includes('/api/admin/dashboard?') && response.status() === 200)
    await page.getByRole('button', { name: '30 hari', exact: true }).click()
    await periodResponse
    await expect(page.locator('.tkm-chart-bars > button')).toHaveCount(30)
    await expect(page.getByTestId('dashboard-revenue')).toContainText(/40\.000/)
    if (width === 1024) {
      const exportLink = page.getByRole('link', { name: 'Buka laporan dan ekspor CSV', exact: true })
      const reportURL = new URL(await exportLink.getAttribute('href'), base)
      await exportLink.click()
      await expect(page.getByRole('heading', { name: 'Laporan pesanan', exact: true })).toBeVisible()
      await expect(page.getByLabel('Dari tanggal', { exact: true })).toHaveValue(reportURL.searchParams.get('from'))
      await expect(page.getByLabel('Sampai tanggal', { exact: true })).toHaveValue(reportURL.searchParams.get('to'))
      const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Ekspor semua CSV', exact: true }).click()])
      assert.match(download.suggestedFilename(), /\.csv$/)
      const stream = await download.createReadStream(); let exported = ''
      for await (const chunk of stream) exported += chunk.toString()
      assert.match(exported, /Diteruskan ke POS \(WIB\)/)
      assert.match(exported, /Sari E2E/)
      await page.goto('/admin')
      await page.getByRole('button', { name: '30 hari', exact: true }).click()
      await expect(page.locator('.tkm-chart-bars > button')).toHaveCount(30)
    }
    await page.screenshot({ animations: 'disabled', path: info.outputPath(`dashboard-${width}x${height}.png`), fullPage: true, timeout: 15000 })
    await page.getByRole('button', { name: 'Gunakan tema gelap', exact: true }).click()
    await expect(page.locator('.ops-shell')).toHaveAttribute('data-dashboard-theme', 'dark')
    await page.screenshot({ animations: 'disabled', path: info.outputPath(`dashboard-dark-${width}x${height}.png`), fullPage: true, timeout: 15000 })
    await page.getByRole('button', { name: 'Gunakan tema terang', exact: true }).click()
    await page.locator('.tkm-chart-bars > button').last().click()
    await expect(page.getByRole('heading', { name: 'Laporan pesanan', exact: true })).toBeVisible()
    await expect(page.getByLabel('Dari tanggal', { exact: true })).toHaveValue(date)
    await expect(page.getByLabel('Sampai tanggal', { exact: true })).toHaveValue(date)
    await page.getByRole('link', { name: 'Staf', exact: true }).click()
    await page.getByRole('button',{name:'Tambah staf',exact:true}).click()
    await expect(page.getByLabel('Peran', { exact: true })).toBeVisible()
    await expect(page.getByLabel('Peran', { exact: true }).locator('option')).toHaveCount(2)
    await page.getByRole('dialog').getByRole('button',{name:'Tutup',exact:true}).click()
    await page.getByRole('link', { name: 'Log aktivitas', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Log aktivitas', exact: true })).toBeVisible()
    await expect(page.locator('.ops-table')).toContainText('Pesanan dikonfirmasi masuk aplikasi kasir')
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Admin page overflows tablet width')
    await page.screenshot({ animations: 'disabled', path: info.outputPath(`activity-${width}x${height}.png`), fullPage: true, timeout: 15000 })
    await context.close()
  }

  const adminContext = await browser.newContext({ baseURL: base, viewport: { width: 1024, height: 768 } })
  await adminContext.addCookies(administrator.cookie().split('; ').map(part => {
    const split = part.indexOf('=')
    return { name: part.slice(0, split), value: part.slice(split + 1), domain: '127.0.0.1', path: '/', httpOnly: false, secure: false, sameSite: 'Lax' }
  }))
  await adminContext.route(/^https:\/\/fonts\.(googleapis|gstatic)\.com\//, route => route.abort())
  const adminPage = await adminContext.newPage()
  await adminPage.goto('/admin')
  await expect(adminPage.getByTestId('dashboard-revenue')).toContainText(/40\.000/)
  await expect(adminPage.getByRole('heading', { name: 'Aktivitas staf', exact: true })).toHaveCount(0)
  await expect(adminPage.getByRole('link', { name: 'Pengaturan & backup', exact: true })).toHaveCount(0)
  await adminPage.screenshot({ animations: 'disabled', path: info.outputPath('admin-dashboard-1024x768.png'), fullPage: true, timeout: 15000 })
  await adminPage.goto('/admin/staff')
  await expect(adminPage.getByRole('heading', { name: 'Kelola staf' })).toBeVisible()
  await expect(adminPage.getByRole('link', { name: 'Log aktivitas', exact: true })).toHaveCount(0)
  await expect(adminPage.getByRole('link', { name: 'Pengaturan', exact: true })).toHaveCount(0)
  await expect(adminPage.getByLabel('Peran', { exact: true })).toHaveCount(0)
  await expect(adminPage.locator('.ops-table')).toContainText('Sari E2E')
  await adminPage.screenshot({ animations: 'disabled', path: info.outputPath('admin-staff-1024x768.png'), fullPage: true, timeout: 15000 })
  await adminContext.close()

  console.log('E2E stage: direct password reset, reactivation and revoked sessions')
  await request(`/api/admin/staff/${accounts.a.id}`, { method: 'PATCH', cookie: owner.cookie, body: { command: 'disable' } })
  await request('/api/core/admin/me', { token: a.token, expected: 401 })
  await request('/api/auth/staff-login', { body: { email: accounts.a.email, password: accounts.a.password, area: 'cashier' }, expected: 403 })
  const refresh = createClient(api, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: boundedFetch } })
  const oldRefresh = await refresh.auth.refreshSession({ refresh_token: a.refresh })
  assert.ok(oldRefresh.error, 'Disabled account retained old refresh session')
  const oldPassword = accounts.a.password
  accounts.a.password = password()
  const reset = await request(`/api/admin/staff/${accounts.a.id}/password`, { cookie: owner.cookie, body: { password: accounts.a.password, reactivate: true } })
  assert.equal(reset.profile.staff_status, 'active')
  assert.ok(!('password' in reset.profile) && !('url' in reset))
  await request('/api/core/admin/me', { token: a.token, expected: 401 })
  await request('/api/auth/staff-login', { body: { email: accounts.a.username, password: oldPassword, area: 'cashier' }, expected: 401 })
  a = await login(accounts.a); await request('/api/core/admin/me', { token: a.token })
  accounts.b.password = password()
  await request(`/api/admin/staff/${accounts.b.id}/password`, { cookie: administrator.cookie, body: { password: accounts.b.password } })
  await request('/api/core/admin/me', { token: b.token, expected: 401 })
  b = await login(accounts.b); await request('/api/core/admin/me', { token: b.token })
  await request(`/api/admin/staff/${accounts.b.id}/links`, { cookie: owner.cookie, body: { purpose: 'recovery' }, expected: 410 })
  const finalLogs = await request(activityPath, { cookie: owner.cookie })
  assert.ok(finalLogs.entries.some(e => e.action === 'staff_password_set'))
  console.log('E2E stage: cashier PIN with real isolated Auth')
  const pin = '005678'
  const pinAccount = await request(`/api/admin/staff/${accounts.b.id}/pin`, {cookie: owner.cookie, body: {pin}})
  assert.equal(pinAccount.profile.cashier_pin_enabled, true)
  const roster = await request('/api/auth/cashiers')
  assert.ok(roster.some(p => p.id === accounts.b.id && p.name === accounts.b.name))
  assert.ok(roster.every(p => !('email' in p) && !('username' in p)))
  await request('/api/auth/cashier-pin', {body: {cashier_id: accounts.b.id, pin: '000001'}, expected: 401})
  const pinSession = await request('/api/auth/cashier-pin', {body: {cashier_id: accounts.b.id, pin}})
  assert.equal(pinSession.profile.id, accounts.b.id)
  await request('/api/core/admin/me', {token: pinSession.session.access_token})
  await request('/api/core/admin/me', {token: b.token, expected: 401})
  const pinLogs = await request(activityPath, {cookie: owner.cookie})
  assert.ok(pinLogs.entries.some(e => e.action === 'cashier_pin_set' && e.actor_id === accounts.superadmin.id))
  console.log('E2E stage: edit email/role, archive/restore and trusted PIN browser')
  const editor={name:'Edit lifecycle',username:'edit.lifecycle',email:'edit-lifecycle@example.test',password:password(),role:'admin'}
  const createdEdit=await request('/api/admin/staff',{cookie:owner.cookie,body:{full_name:editor.name,username:editor.username,email:editor.email,password:editor.password,role:'admin'}})
  const editId=createdEdit.profile.id,oldEditor=await login(editor,'admin')
  const editInput={full_name:'Kasir Edited',username:'edited.cashier',email:'edited-cashier@example.test',role:'cashier',pin:'246810'}
  await request(`/api/admin/staff/${editId}`,{method:'PUT',cookie:administrator.cookie,body:editInput,expected:403})
  const edited=await request(`/api/admin/staff/${editId}`,{method:'PUT',cookie:owner.cookie,body:editInput})
  assert.equal(edited.profile.email,editInput.email);assert.equal(edited.profile.role,'cashier')
  await request('/api/core/admin/me',{token:oldEditor.token,expected:401})
  const pinLogin=await fetch(base+'/api/auth/cashier-pin',{method:'POST',headers:{Origin:base,'Content-Type':'application/json'},body:JSON.stringify({cashier_id:editId,pin:editInput.pin}),signal:AbortSignal.timeout(20000)})
  assert.equal(pinLogin.status,200)
  const remembered=pinLogin.headers.getSetCookie().find(c=>c.startsWith('tkm-cashier-')).split(';')[0]
  const editedSession=await pinLogin.json()
  for(let guess=0;guess<5;guess++)await request('/api/auth/cashier-pin',{body:{cashier_id:editId,pin:'000002'},expected:401})
  await request('/api/auth/cashier-pin',{body:{cashier_id:editId,pin:editInput.pin},expected:429})
  const protectedLogin=await request('/api/auth/cashier-pin',{cookie:()=>remembered,body:{cashier_id:editId,pin:editInput.pin}})
  assert.equal(protectedLogin.profile.id,editId)
  await request(`/api/admin/staff/${editId}`,{method:'DELETE',cookie:owner.cookie})
  await request('/api/core/admin/me',{token:editedSession.session.access_token,expected:401})
  const archived=(await request('/api/admin/staff',{cookie:owner.cookie})).find(p=>p.id===editId)
  assert.ok(archived.archived_at);assert.equal(archived.staff_status,'disabled')
  await request(`/api/admin/staff/${editId}/restore`,{cookie:owner.cookie,body:{}})
  const restored=(await request('/api/admin/staff',{cookie:owner.cookie})).find(p=>p.id===editId)
  assert.equal(restored.archived_at,null);assert.equal(restored.staff_status,'disabled')
  await request(`/api/admin/staff/${editId}/pin`,{cookie:owner.cookie,body:{pin:'135790',reactivate:true}})
  const reactivated=await request('/api/auth/cashier-pin',{body:{cashier_id:editId,pin:'135790'}})
  assert.equal(reactivated.profile.id,editId)
  const editLog=await request(activityPath,{cookie:owner.cookie})
  for(const action of ['staff_edit_started','staff_updated','staff_archived','staff_restored'])assert.ok(editLog.entries.some(e=>e.action===action))
  console.log('Real isolated Auth, session revocation, cash ledger, immutable activity and tablet checks passed')
})
