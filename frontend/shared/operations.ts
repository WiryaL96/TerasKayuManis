export const wibToday = () =>
  new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10)
export const money = (value: number | string) =>
  new Intl.NumberFormat('id-ID', {
    style: 'currency',
    currency: 'IDR',
    maximumFractionDigits: 0,
  }).format(typeof value === 'string' ? BigInt(value) : value)
export const wibTime = (value: string) =>
  new Intl.DateTimeFormat('id-ID', {
    timeZone: 'Asia/Jakarta',
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
export interface ReportData {
  as_of?:string
  pagination?:{offset:number;payment_has_more:boolean;handoff_has_more:boolean}
  pos_summary?: {count:number;total:string;by_cashier:{id:string;name:string;count:number;total:string}[]}
  daily_handoffs?: {date:string;count:number;revenue:string}[]
  handoffs?: {order_id:string;order_number:string;customer_name:string|null;forwarded_at:string;cashier_id:string;cashier_name:string;pos_reference:string|null;total:number}[]
  summary: { count: number; revenue: string; received: string; change: string }
  by_cashier: { id: string; name: string; count: number; revenue: string }[]
  counts: Record<string, number>
  active_total: number
  today_total: number
  popular: { name: string; qty: number }[]
  payments: {
    order_id: string
    order_number: string
    customer_name: string | null
    paid_at: string
    cashier_id: string
    cashier_name: string | null
    total: number
    received: number
    change: number
  }[]
}
// Both charges use the item subtotal, matching database checkout.
export function priceExample(subtotal: number, tax: number, service: number) {
  const serviceAmount = Math.round((subtotal * service) / 100),
    taxAmount = Math.round((subtotal * tax) / 100)
  return {
    subtotal,
    service: serviceAmount,
    tax: taxAmount,
    total: subtotal + serviceAmount + taxAmount,
  }
}
