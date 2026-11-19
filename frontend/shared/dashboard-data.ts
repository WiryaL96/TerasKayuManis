import type { Addon, Category, MenuResponse, Order, Profile, Settings } from './types'
import type { DashboardData } from './dashboard'
import type { ReportData } from './operations'
import type { StaffActivityPage } from './staff-audit'

export interface AdminCatalog extends MenuResponse { addons: Addon[] }
export interface StaffRow { archived_at?:string|null; username?: string | null; cashier_pin_enabled?:boolean;staff_photo_path?:string|null;id: string; full_name: string | null; email: string | null; role: 'admin' | 'cashier'; staff_status: 'active' | 'invited' | 'disabled' }
export interface ReceiptData { brand:string; order:Order; payment:{paid_at:string;cashier_name:string|null;total:number;received:number;change:number} }
const invalid = (): never => { throw Object.assign(new Error('Respons data tidak lengkap. Coba muat ulang.'), { invalidData: true }) }
const object = (v: any): Record<string, any> => v && typeof v === 'object' && !Array.isArray(v) ? v : invalid()
const string = (v: any): string => typeof v === 'string' ? v : invalid()
const number = (v: any): number => Number.isSafeInteger(v) && v >= 0 ? v : invalid()
const bool = (v: any): boolean => typeof v === 'boolean' ? v : invalid()
const array = (v: any): any[] => Array.isArray(v) ? v : invalid()
const date = (v: any): string => Number.isFinite(Date.parse(string(v))) ? v : invalid()
const nullable = (v: any) => v == null ? null : string(v)
const amount = (v: any): string => typeof v === 'string' && /^\d+$/.test(v) ? v : invalid()
export function normalizeProfile(value: unknown): Profile {
  const v = object(value)
  if (!['superadmin','admin','cashier'].includes(v.role)) invalid()
  return { ...v, id: string(v.id), full_name: nullable(v.full_name), role: v.role } as Profile
}
export function normalizeCategories(value: unknown): Category[] {
  return array(value).map(v => ({ ...object(v), id:string(v.id), name:string(v.name), slug:string(v.slug), sort_order:Number.isSafeInteger(v.sort_order)?v.sort_order:invalid(), is_active:bool(v.is_active) })) as Category[]
}
export function normalizeAddons(value: unknown): Addon[] {
  return array(value).map(v => ({ ...object(v), id:string(v.id), name:string(v.name), price:number(v.price), is_available:bool(v.is_available) })) as Addon[]
}
export function normalizeSettings(value: unknown): Settings {
  const v = object(value)
  for (const k of ['tax_pct','service_pct']) if ((typeof v[k]!=='number'&&(typeof v[k]!=='string'||!/^\d+(\.\d+)?$/.test(v[k]))) || !Number.isFinite(Number(v[k])) || Number(v[k]) < 0 || Number(v[k]) > 100) invalid()
  if (v.pricing_confirmed_at != null) date(v.pricing_confirmed_at)
  return { ...v, id:number(v.id), brand_name:string(v.brand_name), tagline:nullable(v.tagline), tax_pct:Number(v.tax_pct), service_pct:Number(v.service_pct), require_customer_name:bool(v.require_customer_name) } as Settings
}
export function normalizeMenu(value: unknown): MenuResponse {
  const v = object(value)
  return { settings:normalizeSettings(v.settings), categories:normalizeCategories(v.categories), products:array(v.products).map(p => ({
    ...object(p), id:string(p.id), name:string(p.name), category_id:string(p.category_id), slug:string(p.slug),
    price:number(p.price), is_available:bool(p.is_available), image_url:nullable(p.image_url), description:nullable(p.description),
    variants:array(p.variants ?? []).map(x => ({ ...object(x), id:string(x.id), name:string(x.name), group_name:string(x.group_name), price_modifier:number(x.price_modifier), is_available:bool(x.is_available) })),
    addons:normalizeAddons(p.addons ?? []),
  })) } as MenuResponse
}
export function normalizeCatalog(value: unknown): AdminCatalog {
  return { ...normalizeMenu(value), addons:normalizeAddons(object(value).addons) }
}
export function normalizeOrders(value: unknown): Order[] {
  return array(value).map(v => {
    object(v)
    if (!['pending','pos_input','forwarded','confirmed','completed','expired','cancelled'].includes(v.status) || !['unpaid','paid'].includes(v.payment_status)) invalid()
    if(v.pos_handoff!=null){const h=object(v.pos_handoff);string(h.cashier_id);string(h.cashier_name);date(h.claimed_at);nullable(h.pos_reference);if(h.forwarded_at!=null)date(h.forwarded_at)}
    if(['pos_input','forwarded'].includes(v.status)&&(!v.pos_handoff||(v.status==='forwarded'&&!v.pos_handoff.forwarded_at)))invalid()
    for (const field of ['subtotal','discount','tax','service_charge','total','version']) number(v[field])
    const items = array(v.order_items ?? []).map(i => {
      object(i); string(i.id); string(i.product_name); number(i.quantity); number(i.subtotal); number(i.unit_price)
      return { ...i, variant_ids:array(i.variant_ids ?? []).map(string), addon_ids:array(i.addon_ids ?? []).map(string), order_item_addons:array(i.order_item_addons ?? []).map(a => ({ addon_name:string(a.addon_name), price:number(a.price) })) }
    })
    return { ...v, id:string(v.id), order_number:string(v.order_number), customer_name:nullable(v.customer_name), created_at:date(v.created_at), expires_at:date(v.expires_at), order_items:items } as Order
  })
}
export function normalizeReport(value: unknown): ReportData {
  const v = object(value), s = object(v.summary)
  number(s.count); amount(s.revenue); amount(s.received); amount(s.change)
  object(v.counts); Object.values(v.counts).forEach(number); number(v.active_total); number(v.today_total)
  array(v.by_cashier).forEach(c => { object(c); string(c.id); string(c.name); number(c.count); amount(c.revenue) })
  array(v.popular).forEach(p => { object(p); string(p.name); number(p.qty) })
  array(v.payments).forEach(p => { object(p); string(p.order_id); string(p.order_number); string(p.cashier_id); nullable(p.cashier_name); date(p.paid_at); number(p.total); number(p.received); number(p.change) })
  if(v.handoffs!=null)array(v.handoffs).forEach(h=>{object(h);string(h.order_id);string(h.order_number);string(h.cashier_id);string(h.cashier_name);date(h.forwarded_at);number(h.total);nullable(h.pos_reference)})
  if(v.pos_summary!=null){const s=object(v.pos_summary);number(s.count);amount(s.total);array(s.by_cashier).forEach(c=>{object(c);string(c.id);string(c.name);number(c.count);amount(c.total)})}
  if(v.pagination!=null){const p=object(v.pagination);number(p.offset);bool(p.payment_has_more);bool(p.handoff_has_more)}
  if(v.as_of!=null)date(v.as_of)
  if(v.daily_handoffs!=null)array(v.daily_handoffs).forEach(d=>{object(d);date(d.date);number(d.count);amount(d.revenue)})
  return v as ReportData
}
export function reportForCashier(report: ReportData, id: string): ReportData {
  if (!id) return report
  const payments=report.payments.filter(p=>p.cashier_id===id)
  const sum=(field:'total'|'received'|'change')=>payments.reduce((total,p)=>total+BigInt(p[field]),0n).toString()
  const handoffs=(report.handoffs??[]).filter(h=>h.cashier_id===id)
  return {...report,payments,handoffs,...(report.pos_summary?{pos_summary:summarizeHandoffs({handoffs})}:{}),by_cashier:report.by_cashier.filter(c=>c.id===id),summary:{count:payments.length,revenue:sum('total'),received:sum('received'),change:sum('change')}}
}
export function summarizeHandoffs(report:Pick<ReportData,'handoffs'|'pos_summary'>){
 if(report.pos_summary)return report.pos_summary
 const rows=report.handoffs??[],groups=new Map<string,{id:string;name:string;count:number;total:bigint}>()
 let total=BigInt(0)
 for(const h of rows){total+=BigInt(h.total);const key=h.cashier_id+'\0'+h.cashier_name,g=groups.get(key)??{id:h.cashier_id,name:h.cashier_name,count:0,total:BigInt(0)};g.count++;g.total+=BigInt(h.total);groups.set(key,g)}
 return {count:rows.length,total:String(total),by_cashier:[...groups.values()].map(g=>({...g,total:String(g.total)}))}
}
export function posReportCSV(report:Pick<ReportData,'handoffs'>){
 const cell=(v:unknown)=>{let text=String(v??'');if(/^\s*[=+@\-]/.test(text))text="'"+text;return '"'+text.replaceAll('"','""')+'"'}
 const rows:unknown[][]=[['Nomor self-order','Pelanggan','Diteruskan ke POS (WIB)','Kasir','Referensi POS','Estimasi nilai pesanan (bukan pendapatan POS)']]
 for(const h of report.handoffs??[])rows.push([h.order_number,h.customer_name,new Date(h.forwarded_at).toLocaleString('sv-SE',{timeZone:'Asia/Jakarta'}),h.cashier_name,h.pos_reference,h.total])
 return '\uFEFF'+rows.map(row=>row.map(cell).join(',')).join('\r\n')
}
export function reportCSV(report: ReportData) {
  const cell=(v:unknown)=>{let text=String(v??'');if(/^\s*[=+@\-]/.test(text))text="'"+text;return '"'+text.replaceAll('"','""')+'"'}
  const rows:unknown[][]=[['Nomor order','Pelanggan','Waktu pembayaran (WIB)','Kasir','Total','Uang diterima','Kembalian']]
  for(const p of report.payments)rows.push([p.order_number,p.customer_name,new Date(p.paid_at).toLocaleString('sv-SE',{timeZone:'Asia/Jakarta'}),p.cashier_name||'Nama kasir belum tercatat',p.total,p.received,p.change])
  return '\uFEFF'+rows.map(row=>row.map(cell).join(',')).join('\r\n')
}
export function normalizeDashboard(value: unknown): DashboardData {
  const v = object(value)
  if (!['superadmin','admin'].includes(v.role)) invalid()
  date(v.period?.from); date(v.period?.to); normalizeReport(v.report)
  number(v.queue?.pending); number(v.queue?.processing)
  array(v.queue.orders).forEach(o => { string(o.id); string(o.order_number); number(o.total); date(o.created_at); date(o.expires_at); string(o.status) })
  for (const k of ['published','draft','hidden','missing_photo']) number(v.catalog?.[k])
  for (const k of ['active','invited','disabled','active_cashiers']) number(v.staff?.[k])
  bool(v.operation?.orders_enabled); date(v.generated_at)
  if (v.activity != null) array(v.activity).forEach(a => { string(a.id); string(a.action); date(a.created_at) })
  if (v.backup) for (const k of ['last_attempt','last_success','restore_verified_at']) if (v.backup[k]) date(v.backup[k])
  return v as DashboardData
}
export function normalizeStaff(value: unknown): StaffRow[] {
  return array(value).map(v => {
    object(v)
    if (!['admin','cashier'].includes(v.role) || !['active','invited','disabled'].includes(v.staff_status)) invalid()
    return { id:string(v.id), full_name:nullable(v.full_name), email:nullable(v.email), username:nullable(v.username),role:v.role, staff_status:v.staff_status,cashier_pin_enabled:v.cashier_pin_enabled===true,staff_photo_path:nullable(v.staff_photo_path),archived_at:nullable(v.archived_at) }
  })
}
export function normalizeActivity(value: unknown): StaffActivityPage {
  const v = object(value)
  number(v.total); number(v.limit)
  array(v.staff).forEach(s => { string(s.id); nullable(s.full_name); string(s.role) })
  array(v.entries).forEach(e => { string(e.id); string(e.action); date(e.created_at); object(e.details) })
  return v as StaffActivityPage
}
export function normalizeBackup(value: unknown) {
  const v=object(value)
  for(const key of ['last_attempt','last_success','restore_verified_at'])if(v[key])date(v[key])
  return v as {result?:string;last_attempt?:string;last_success?:string;restore_verified_at?:string}
}
export function normalizeReceipt(value: unknown): ReceiptData {
  const v=object(value),payment=object(v.payment),order=normalizeOrders([v.order])[0]!
  string(v.brand);date(payment.paid_at);nullable(payment.cashier_name)
  for(const key of ['total','received','change'])number(payment[key])
  if(order.payment_status!=='paid'||payment.total!==order.total||payment.received-payment.change!==payment.total)invalid()
  return {brand:v.brand,order,payment:payment as ReceiptData['payment']}
}
export function filterOrders(rows: Order[], filters: { tab: string; status?: string; q?: string; sort?: string }, now = Date.now()) {
  const q = (filters.q || '').toLocaleLowerCase('id')
  return rows.filter(o => {
    if (filters.status === 'ready' ? !(o.status === 'pending' && o.payment_status === 'unpaid' && o.reviewed_version === o.version && Date.parse(o.expires_at) > now) : filters.status && o.status !== filters.status) return false
    return !q || [o.order_number, o.customer_name || '', ...(o.order_items || []).map(i => i.product_name)].some(text => text.toLocaleLowerCase('id').includes(q))
  }).sort((a,b) => (Date.parse(b.created_at) - Date.parse(a.created_at) || b.id.localeCompare(a.id)) * (filters.sort === 'oldest' ? -1 : 1))
}
