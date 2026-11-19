import type { CartLine, Product } from '#shared/types'

const CART_KEY = 'cart'

export function lineKey(productId: string, variantIds: string[], addonIds: string[], notes: string) {
  return [productId, [...variantIds].sort().join(','), [...addonIds].sort().join(','), notes.trim()].join('|')
}

export function useCart() {
  const lines = useState<CartLine[]>('cart-lines', () => [])

  if (import.meta.client) {
    onMounted(() => {
      try {
        const raw = localStorage.getItem(CART_KEY)
        if (raw) lines.value = JSON.parse(raw)
      } catch { lines.value = [] }
    })
    watch(lines, (v) => localStorage.setItem(CART_KEY, JSON.stringify(v)), { deep: true })
  }

  function add(line: Omit<CartLine, 'key'>) {
    const key = lineKey(line.productId, line.variantIds, line.addonIds, line.notes)
    const existing = lines.value.find((l) => l.key === key)
    if (existing) existing.qty = Math.min(existing.qty + line.qty, 50)
    else lines.value.push({ ...line, key })
  }
  function remove(key: string) {
    lines.value = lines.value.filter((l) => l.key !== key)
  }
  function update(key: string, line: Omit<CartLine, 'key'>) {
    const index = lines.value.findIndex(l => l.key === key)
    if (index < 0) return false
    const nextKey = lineKey(line.productId, line.variantIds, line.addonIds, line.notes)
    const duplicate = lines.value.find(l => l.key === nextKey && l.key !== key)
    if (duplicate && duplicate.qty + line.qty > 50) return false
    const replacement = { ...line, variantIds: [...line.variantIds], addonIds: [...line.addonIds], key: nextKey }
    if (duplicate) {
      duplicate.qty += line.qty
      remove(key)
    } else lines.value.splice(index, 1, replacement)
    return true
  }
  function restore(line: CartLine, index: number) {
    const existing = lines.value.find(l => l.key === line.key)
    if (existing && existing.qty + line.qty > 50) return false
    if (existing) existing.qty += line.qty
    else lines.value.splice(Math.min(index, lines.value.length), 0, { ...line, variantIds: [...line.variantIds], addonIds: [...line.addonIds] })
    return true
  }
  function setQty(key: string, qty: number) {
    const line = lines.value.find((l) => l.key === key)
    if (!line) return
    if (qty < 1) remove(key)
    else line.qty = Math.min(qty, 50)
  }
  function clear() {
    lines.value = []
  }

  return { lines, add, remove, setQty, clear, update, restore }
}

export function linePrice(line: CartLine, product?: Product) {
  if (!product) return 0
  const variants = product.variants.filter((v) => line.variantIds.includes(v.id))
  const addons = product.addons.filter((a) => line.addonIds.includes(a.id))
  return product.price + variants.reduce((s, v) => s + v.price_modifier, 0) + addons.reduce((s, a) => s + a.price, 0)
}
