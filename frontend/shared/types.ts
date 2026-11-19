export interface Settings {
  id: number
  brand_name: string
  tagline: string | null
  logo_url: string | null
  tax_pct: number
  service_pct: number
  require_customer_name: boolean
  orders_enabled?: boolean
  pricing_confirmed_at?: string | null
}

export interface Category {
  id: string
  name: string
  slug: string
  sort_order: number
  is_active: boolean
}

export interface Variant {
  id: string
  product_id: string
  group_name: string
  name: string
  price_modifier: number
  is_default: boolean
  is_available: boolean
  sort_order: number
}

export interface Addon {
  id: string
  name: string
  price: number
  price_confirmed?: boolean
  is_available: boolean
}

export interface Product {
  id: string
  category_id: string
  name: string
  slug: string
  description: string | null
  price: number
  price_confirmed?: boolean
  image_url: string | null
  is_available: boolean
  is_featured: boolean
  is_best_seller: boolean
  is_new: boolean
  variants: Variant[]
  addons: Addon[]
}

export interface MenuResponse {
  settings: Settings
  categories: Category[]
  products: Product[]
}

export type OrderStatus = 'expired' | 'pending' | 'pos_input' | 'forwarded' | 'confirmed' | 'preparing' | 'ready' | 'completed' | 'cancelled'
export type PaymentStatus = 'unpaid' | 'pending' | 'paid' | 'failed' | 'refunded'
export type { StaffRole } from './staff-roles'
import type { StaffRole } from './staff-roles'

export interface OrderItemAddon {
  addon_name: string
  price: number
}

export interface OrderItem {
  id: string
  product_id: string
  variant_ids: string[]
  addon_ids: string[]
  product_name: string
  variant_name: string | null
  quantity: number
  unit_price: number
  addons_total: number
  subtotal: number
  notes: string | null
  order_item_addons: OrderItemAddon[]
}

export interface Order {
  id: string
  order_number: string
  version: number
  reviewed_version: number | null
  expires_at: string
  customer_name: string | null
  status: OrderStatus
  subtotal: number
  discount: number
  service_charge: number
  tax: number
  total: number
  payment_status: PaymentStatus
  payment_method: 'cash' | 'qris'
  created_at: string
  tables?: { number: number } | null
  order_items?: OrderItem[]
  pos_handoff?: { cashier_id:string; cashier_name:string; claimed_at:string; forwarded_at:string|null; pos_reference:string|null } | null
  // Staff-only order list: identity comes from the committed payment record.
  cashier?: { id: string; full_name: string | null; confirmed_at: string } | null
}

export interface Profile {
  id: string
  full_name: string | null
  role: StaffRole
  staff_status?: 'invited' | 'active' | 'disabled'
  session_version?: number
}

export interface CartLine {
  key: string
  productId: string
  variantIds: string[]
  addonIds: string[]
  qty: number
  notes: string
}

export interface CreateOrderPayload {
  // Legacy stored checkout attempts may carry this field; new orders omit it.
  table_token?: string
  customer_name: string
  payment_method: 'cash' | 'qris'
  items: {
    product_id: string
    variant_ids: string[]
    addon_ids: string[]
    quantity: number
    notes: string
  }[]
}
