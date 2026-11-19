// UI-only sandbox: no database driver, network credentials, or real API calls.
// State belongs to one browser origin; it does not model cloud concurrency.
import source from '../../data/menu-teraskayumanis-2026-10-12.json' with { type: 'json' }
import photos from '../../data/menu-photo-sources.json' with { type: 'json' }
import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
import type { AdminCatalog } from './dashboard-data'
import type { CreateOrderPayload, Order, Profile } from './types'

interface DemoStaff extends Profile { username: string; email: string; staff_status: 'active' | 'disabled'; cashier_pin_enabled: boolean; staff_photo_path: null }
interface State { schema: 1; catalog: AdminCatalog; staff: DemoStaff[]; orders: Order[]; session: string | null; revision: number; keys: Record<string, string>; tokens: Record<string, string>; activity: Record<string, unknown>[] }
const key = 'tkm-preview-v1'
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const now = () => new Date().toISOString()
function fail(status: number, message: string): never { throw Object.assign(new Error(message), { status }) }
function catalog(): AdminCatalog {
  const photoSlugs = new Set(photos.photos.map(p => p.slug))
  const categories = source.categories.map((c, i) => ({ ...c, id: uuid(i + 1), is_active: true }))
  const addons = new Map<string, AdminCatalog['addons'][number]>()
  const products = source.products.filter(p => p.price > 0).map((p, i) => {
    const id = uuid(i + 100)
    return { ...p, id, category_id: categories.find(c => c.slug === p.category)!.id,
      price_confirmed: true, is_available: true, is_featured: i < 6, is_best_seller: i < 3, is_new: false,
      image_url: photoSlugs.has(p.slug) ? `/images/menu/${p.slug}.webp` : null,
      variants: p.variants.map((v, n) => ({ ...v, id: uuid(1000 + i * 20 + n), product_id: id, is_available: true })),
      addons: p.addons.map(a => { if (!addons.has(a.name)) addons.set(a.name, { ...a, id: uuid(10000 + addons.size), is_available: true, price_confirmed: true }); return addons.get(a.name)! }),
    }
  })
  return { categories, products, addons: [...addons.values()], settings: { id: 1, brand_name: 'TerasKayuManis', tagline: 'Preview dengan data contoh, bukan pemesanan restoran.', logo_url: null,
    tax_pct: 0, service_pct: 0, orders_enabled: true, require_customer_name: true, pricing_confirmed_at: now() } }
}
function staff(): DemoStaff[] {
  return [['superadmin', 'owner.demo', 'Pemilik Contoh'], ['admin', 'admin.demo', 'Admin Contoh'], ['cashier', 'raka.demo', 'Kasir Raka Contoh'], ['cashier', 'sari.demo', 'Kasir Sari Contoh']].map(([role, username, full_name], i) => ({ id: uuid(20000 + i), role: role as Profile['role'], username: username!, full_name: full_name!, email: `${username}@example.test`, staff_status: 'active', session_version: 1, cashier_pin_enabled: role === 'cashier', staff_photo_path: null }))
}
function fresh(): State {
  return { schema: 1, catalog: catalog(), staff: staff(), orders: [], session: null, revision: 1, keys: {}, tokens: {}, activity: [] }
}
function makeOrder(state: State, payload: CreateOrderPayload): Order {
  if (!payload.items?.length || payload.items.length > 50) fail(400, 'Pilih setidaknya satu menu.')
  const items = payload.items.map(item => {
    const p = state.catalog.products.find(p => p.id === item.product_id && p.is_available)
    if (!p || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 50) fail(400, 'Pilihan menu atau jumlah belum sesuai.')
    const variants = p!.variants.filter(v => item.variant_ids.includes(v.id))
    const addons = p!.addons.filter(a => item.addon_ids.includes(a.id))
    const unit_price = p!.price + variants.reduce((sum, v) => sum + v.price_modifier, 0)
    const addons_total = addons.reduce((sum, a) => sum + a.price, 0)
    return { id: crypto.randomUUID(), product_id: p!.id, product_name: p!.name, variant_ids: variants.map(v => v.id), addon_ids: addons.map(a => a.id), variant_name: variants.map(v => v.name).join(', ') || null,
      quantity: item.quantity, notes: String(item.notes || '').slice(0, 500), unit_price, addons_total, subtotal: (unit_price + addons_total) * item.quantity, order_item_addons: addons.map(a => ({ addon_name: a.name, price: a.price })) }
  })
  const subtotal = items.reduce((sum, i) => sum + i.subtotal, 0)
  const tax = Math.round(subtotal * state.catalog.settings.tax_pct / 100), service_charge = Math.round(subtotal * state.catalog.settings.service_pct / 100)
  return { id: crypto.randomUUID(), order_number: `DEMO${String(state.orders.length + 1).padStart(3, '0')}`, customer_name: String(payload.customer_name || 'Pelanggan Contoh').slice(0, 100),
    created_at: now(), expires_at: new Date(Date.now() + 900000).toISOString(), status: 'pending', payment_status: 'unpaid', payment_method: 'cash', version: 1, reviewed_version: null,
    subtotal, tax, service_charge, total: subtotal + tax + service_charge, discount: 0, order_items: items }
}

export function createPreview(storage: Pick<Storage, 'getItem' | 'setItem'>) {
  let memory: State | null = null
  const listeners = new Set<(event: AuthChangeEvent, session: Session | null) => void>()
  function load(): State {
    try { const saved = JSON.parse(storage.getItem(key) || 'null'); if (saved?.schema === 1 && Array.isArray(saved.staff) && Array.isArray(saved.orders) && saved.catalog?.products) return memory = saved }
    catch { /* Private browsing or an invalid local draft must not blank the UI. */ }
    if (!memory) {
      memory = fresh()
      for (let i = 0; i < 3; i++) memory.orders.push(makeOrder(memory, { customer_name: `Pelanggan Contoh ${i + 1}`, payment_method: 'cash', items: [{ product_id: memory.catalog.products[i]!.id, quantity: i + 1, notes: '', variant_ids: [], addon_ids: [] }] }))
      save(memory)
    }
    return memory
  }
  function save(state: State) { memory = state; try { storage.setItem(key, JSON.stringify(state)) } catch { /* Continue in memory if browser storage is unavailable. */ } }
  function identity(s: State, roles?: Profile['role'][]) {
    const p = s.staff.find(p => p.id === s.session && p.staff_status === 'active')
    if (!p) fail(401, 'Masuk memakai akun contoh terlebih dahulu.')
    if (roles && !roles.includes(p!.role)) fail(403, 'Peran contoh ini tidak memiliki akses.')
    return p!
  }
  function session(): Session | null {
    const s = load(), p = s.staff.find(p => p.id === s.session && p.staff_status === 'active')
    if (!p) return null
    return { access_token: `preview:${p.id}`, refresh_token: 'preview-only', token_type: 'bearer', expires_in: 3600,
      user: { id: p.id, email: p.email, aud: 'authenticated', role: 'authenticated', created_at: now(), app_metadata: { staff_session_version: p.session_version }, user_metadata: {} } }
  }
  const emit = (event: AuthChangeEvent) => queueMicrotask(() => listeners.forEach(fn => fn(event, session())))
  const client = { auth: {
    async getSession() { return { data: { session: session() }, error: null } },
    async setSession(input: { access_token: string }) { const s = load(); s.session = input.access_token.replace(/^preview:/, ''); save(s); emit('SIGNED_IN'); return { data: { session: session() }, error: session() ? null : new Error('Akun contoh tidak aktif.') } },
    async signOut() { const s = load(); s.session = null; save(s); emit('SIGNED_OUT'); return { error: null } },
    onAuthStateChange(fn: (event: AuthChangeEvent, session: Session | null) => void) { listeners.add(fn); queueMicrotask(() => fn('INITIAL_SESSION', session())); return { data: { subscription: { unsubscribe: () => listeners.delete(fn) } } } },
  } }
  function audit(s: State, action: string, p: DemoStaff) { s.activity.unshift({ id: crypto.randomUUID(), actor_id: p.id, actor_name: p.full_name, actor_role: p.role, action, created_at: now(), details: { preview: true } }); s.activity = s.activity.slice(0, 100) }
  function report(s: State, url: URL) {
    const from = url.searchParams.get('from') || '2000-01-01', to = url.searchParams.get('to') || '2100-01-01', cashier = url.searchParams.get('cashier')
    const handoffs = s.orders.filter(o => o.pos_handoff?.forwarded_at).map(o => ({ order_id: o.id, order_number: o.order_number, customer_name: o.customer_name, total: o.total, ...o.pos_handoff! }))
      .filter(h => { const day = new Date(h.forwarded_at!).toLocaleDateString('sv-SE', { timeZone: 'Asia/Jakarta' }); return day >= from && day <= to && (!cashier || h.cashier_id === cashier) })
    const groups = new Map<string, { id: string; name: string; count: number; total: string }>()
    for (const h of handoffs) { const g = groups.get(h.cashier_id) || { id: h.cashier_id, name: h.cashier_name, count: 0, total: '0' }; g.count++; g.total = String(Number(g.total) + h.total); groups.set(g.id, g) }
    return { payments: [], handoffs, summary: { count: 0, revenue: '0', received: '0', change: '0' }, by_cashier: [], popular: [], counts: Object.fromEntries(['pending', 'pos_input', 'forwarded', 'expired', 'cancelled'].map(status => [status, s.orders.filter(o => o.status === status).length])),
      active_total: s.orders.filter(o => ['pending', 'pos_input'].includes(o.status)).length, today_total: s.orders.length,
      pos_summary: { count: handoffs.length, total: String(handoffs.reduce((sum, h) => sum + h.total, 0)), by_cashier: [...groups.values()] }, as_of: now(), pagination: { offset: 0, payment_has_more: false, handoff_has_more: false } }
  }
  async function dispatch(req: Request) {
    const s = load(), url = new URL(req.url), path = url.pathname, method = req.method
    const body = method === 'GET' || method === 'HEAD' ? {} : await req.json().catch(() => ({}))
    let changed = false
    for (const o of s.orders) if (o.status === 'pending' && Date.parse(o.expires_at) < Date.now()) { o.status = 'expired'; o.version++; changed = true }
    if (changed) { s.revision++; save(s) }
    if (path === '/api/core/menu' || path === '/api/menu') return { ...s.catalog, products: s.catalog.products.filter(p => p.is_available && s.catalog.categories.some(c => c.id === p.category_id && c.is_active)) }
    if (path === '/api/auth/cashiers') return s.staff.filter(p => p.role === 'cashier' && p.staff_status === 'active').map(p => ({ id: p.id, name: p.full_name, photo: null }))
    if (path === '/api/auth/staff-login' || path === '/api/auth/cashier-pin') {
      const p = s.staff.find(p => path.endsWith('cashier-pin') ? p.role === 'cashier' && p.id === body.cashier_id : [p.username, p.email].includes(String(body.email).toLowerCase()))
      if (!p || p.staff_status !== 'active' || (path.endsWith('cashier-pin') ? body.pin !== '123456' : body.password !== 'preview123')) fail(401, 'Gunakan akun contoh dengan password preview123 atau PIN 123456.')
      audit(s, 'auth.login', p!); save(s)
      return { profile: p, session: { access_token: `preview:${p!.id}`, refresh_token: 'preview-only' } }
    }
    if (path === '/api/auth/staff-logout') return { ok: true }
    if (path === '/api/core/orders' && method === 'POST') {
      if (!s.catalog.settings.orders_enabled) fail(409, 'Penerimaan pesanan simulasi sedang dijeda.')
      const idempotency = req.headers.get('Idempotency-Key'), token = req.headers.get('X-Order-Token')
      if (!idempotency || !token) fail(400, 'Identitas percobaan diperlukan.')
      if (s.keys[idempotency]) return s.orders.find(o => o.id === s.keys[idempotency])
      if (s.orders.length >= 200) fail(409, 'Batas 200 pesanan simulasi tercapai. Reset preview untuk mencoba lagi.')
      const o = makeOrder(s, body); s.orders.unshift(o); s.keys[idempotency] = o.id; s.tokens[o.id] = token; s.revision++; save(s); return o
    }
    const match = path.match(/^\/api\/core\/orders\/([^/]+)(?:\/([^/]+))?$/)
    if (match) {
      const o = s.orders.find(o => o.id === match[1]); if (!o) fail(404, 'Pesanan contoh tidak ditemukan.')
      if (!s.tokens[o!.id] || req.headers.get('X-Order-Token') !== s.tokens[o!.id]) identity(s)
      const action = match[2]
      if (method === 'GET') {
        if (action === 'sync') return { revision: String(o!.version), terminal: ['expired', 'cancelled', 'forwarded', 'completed'].includes(o!.status) }
        if (action === 'receipt') fail(409, 'Struk resmi diterbitkan POS. Preview tidak menghasilkan pembayaran atau struk asli.')
        if (action === 'reorder') return { customer_name: o!.customer_name, payment_method: 'cash', items: o!.order_items?.map(i => ({ product_id: i.product_id, variant_ids: i.variant_ids, addon_ids: i.addon_ids, quantity: i.quantity, notes: i.notes || '' })) }
        return o
      }
      const p = identity(s)
      if (body.expected_version !== o!.version) fail(409, 'Pesanan sudah berubah. Muat ulang untuk melihat data terbaru.')
      if (action === 'review') {
        if (o!.status !== 'pending') fail(409, 'Pesanan sudah diproses.')
        const revised = makeOrder(s, { customer_name: o!.customer_name || '', payment_method: 'cash', items: body.items })
        Object.assign(o!, { order_items: revised.order_items, subtotal: revised.subtotal, total: revised.total, tax: revised.tax, service_charge: revised.service_charge, version: o!.version + 1, reviewed_version: o!.version + 1 })
      } else if (action === 'claim-pos') {
        if (o!.status !== 'pending' || o!.reviewed_version !== o!.version) fail(409, 'Periksa dan simpan menu terlebih dahulu.')
        o!.status = 'pos_input'; o!.version++; o!.pos_handoff = { cashier_id: p.id, cashier_name: p.full_name!, claimed_at: now(), forwarded_at: null, pos_reference: null }
      } else if (action === 'forward-pos') {
        if (o!.status !== 'pos_input' || o!.pos_handoff?.cashier_id !== p.id || !body.entered_in_pos || !body.paid_in_pos) fail(409, 'Ambil pesanan dan centang kedua konfirmasi simulasi terlebih dahulu.')
        o!.status = 'forwarded'; o!.version++; o!.pos_handoff!.forwarded_at = now(); o!.pos_handoff!.pos_reference = String(body.pos_reference || '').slice(0, 120) || null
      } else fail(501, 'Tindakan ini memerlukan backend operasional dan tidak tersedia pada preview UI.')
      audit(s, `order.${action}`, p); s.revision++; save(s); return o
    }
    const p = identity(s)
    if (path === '/api/core/admin/me') return p
    if (path === '/api/admin/me') return { email: p.email, profile: p }
    if (path === '/api/core/admin/sync') return { revision: String(s.revision) }
    if (path === '/api/core/admin/orders') return s.orders.filter(o => url.searchParams.get('tab') === 'history' ? !['pending', 'pos_input'].includes(o.status) : ['pending', 'pos_input'].includes(o.status))
    identity(s, ['superadmin', 'admin'])
    if (path === '/api/admin/catalog') return s.catalog
    if (path === '/api/admin/backup-status') return { result: 'Tidak berlaku — data simulasi lokal' }
    if (path === '/api/admin/reports') return report(s, url)
    if (path === '/api/admin/dashboard') {
      const visible = s.staff.filter(row => row.role === 'cashier' || p.role === 'superadmin' && row.role === 'admin')
      return { role: p.role, period: { from: url.searchParams.get('from'), to: url.searchParams.get('to') }, generated_at: now(), report: report(s, url),
        queue: { pending: s.orders.filter(o => o.status === 'pending').length, processing: s.orders.filter(o => o.status === 'pos_input').length, orders: s.orders.filter(o => o.status === 'pending').slice(0, 5) },
        catalog: { published: s.catalog.products.filter(p => p.is_available).length, draft: 0, hidden: s.catalog.products.filter(p => !p.is_available).length, missing_photo: s.catalog.products.filter(p => !p.image_url).length },
        staff: { active: visible.filter(p => p.staff_status === 'active').length, disabled: visible.filter(p => p.staff_status === 'disabled').length, invited: 0, active_cashiers: visible.filter(p => p.role === 'cashier' && p.staff_status === 'active').length },
        operation: s.catalog.settings, ...(p.role === 'superadmin' ? { activity: s.activity.slice(0, 4), backup: { result: 'Tidak berlaku — preview lokal' } } : {}) }
    }
    if (path === '/api/admin/activity') { identity(s, ['superadmin']); return { entries: s.activity, staff: s.staff, limit: 100, total: s.activity.length } }
    if (path === '/api/admin/staff' && method === 'GET') return s.staff.filter(row => row.role === 'cashier' || p.role === 'superadmin' && row.role === 'admin')
    if (path === '/api/admin/staff' && method === 'POST') {
      fail(501, 'Preview hanya memakai akun contoh. Pembuatan akun dan penyimpanan password/PIN membutuhkan backend operasional.')
    }
    const target = path.match(/^\/api\/admin\/staff\/([^/]+)(?:\/(pin|password|photo))?$/)
    if (target) {
      if (target[2]) fail(501, 'Password, PIN, dan foto akun tidak diubah pada preview UI. Gunakan akun contoh yang tercantum pada penanda preview.')
      const row = s.staff.find(row => row.id === target[1] && (row.role === 'cashier' || p.role === 'superadmin' && row.role === 'admin'))
      if (!row) fail(404, 'Staf contoh tidak ditemukan.')
      if (body.command === 'disable') row!.staff_status = 'disabled'
      if (body.command === 'rename') row!.full_name = String(body.full_name).slice(0, 100)
      if (body.reactivate) row!.staff_status = 'active'
      // User-entered passwords and PINs are deliberately never persisted.
      audit(s, 'staff.updated', p); save(s); return target[2] ? { profile: row } : row
    }
    if (path === '/api/admin/pricing') { identity(s, ['superadmin']); Object.assign(s.catalog.settings, { tax_pct: Number(body.tax_pct), service_pct: Number(body.service_pct), pricing_confirmed_at: now() }); save(s); return s.catalog.settings }
    const resource = path.match(/^\/api\/admin\/(?:crud\/)?(settings|categories|addons|products)(?:\/([^/]+))?$/)
    if (resource) {
      const name = resource[1] as 'settings' | 'categories' | 'addons' | 'products', id = resource[2]
      if (name === 'settings') { identity(s, ['superadmin']); if (method !== 'GET') { Object.assign(s.catalog.settings, body); save(s) } return method === 'GET' ? [s.catalog.settings] : s.catalog.settings }
      const rows = s.catalog[name] as unknown as Record<string, unknown>[]
      if (method === 'GET') return rows
      let row = rows.find(row => row.id === id)
      if (method === 'DELETE') { if (row) rows.splice(rows.indexOf(row), 1) }
      else if (row) Object.assign(row, body)
      else { row = { ...body, id: crypto.randomUUID(), is_active: true, is_available: true, variants: [], addons: [] }; rows.push(row!) }
      audit(s, `${name}.updated`, p); save(s); return row || { ok: true }
    }
    fail(501, 'Fitur ini memerlukan layanan production. Upload foto, backup, dan pemulihan akun asli tidak dijalankan pada preview UI.')
  }
  return { client, async fetch(req: Request): Promise<Response> {
    if (req.signal.aborted) throw new DOMException('Aborted', 'AbortError')
    try { return Response.json(await dispatch(req)) }
    catch (error) { const e = error as { status?: number; message?: string }; return Response.json({ statusMessage: e.message || 'Simulasi belum dapat diproses. Reset preview dan coba lagi.' }, { status: e.status || 500 }) }
  } }
}
