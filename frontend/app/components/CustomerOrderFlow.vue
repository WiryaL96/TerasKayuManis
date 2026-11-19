<script setup lang="ts">

import { prepareReorder, isCheckoutRejected } from '#shared/order-flow'
import type { CartLine, CreateOrderPayload } from '#shared/types'

const { menu, load } = useMenu()
const { lines, setQty, clear, restore } = useCart()
const expanded = ref(false)
const props = withDefaults(defineProps<{ checkout?: boolean }>(), { checkout: false })
const nameTouched = ref(false)
const removedLine = ref<{ line: CartLine; index: number } | null>(null)
const visibleLines = computed(() => expanded.value ? lines.value : lines.value.slice(0, 2))

const name = useState<string>('checkout-customer-name', () => '')
const payment = ref<'cash'>('cash')
const submitting = ref(false)
const error = ref('')
const pendingCheckout = ref(false)
const catalogReady = ref(false)
const refreshing = ref(false)
const fixedFooter=ref<HTMLElement|null>(null)
useCustomerFooter(fixedFooter)

async function loadCart() {
  if(refreshing.value)return
  refreshing.value=true;catalogReady.value=false
  try {
  const saved=sessionStorage.getItem('tkm-reorder')
  // An unresolved checkout takes priority over importing a different order.
  if(saved&&!pendingCheckout.value){
      const draft=JSON.parse(saved) as CreateOrderPayload
      await load(true)
      name.value=draft.customer_name
      const prepared=prepareReorder(draft,menu.value?.products??[])
      lines.value=prepared.lines
      sessionStorage.removeItem('tkm-reorder')
      error.value=prepared.errors.length?prepared.errors.join(' '):'Pesanan lama masuk keranjang. Periksa harga terbaru lalu konfirmasi untuk membuat nomor baru.'
  }
  await load()
  catalogReady.value=true
  }catch{error.value='Menu atau draft pesanan ulang tidak bisa dimuat. Muat ulang harga sebelum memesan.'}
  finally{refreshing.value=false}
}
onMounted(async () => {
  pendingCheckout.value=!!sessionStorage.getItem('tkm-checkout')
  await loadCart()
})

const productOf = (id: string) => menu.value?.products.find((p) => p.id === id)

const subtotal = computed(() =>
  lines.value.reduce((s, line) => s + linePrice(line, productOf(line.productId)) * line.qty, 0)
)
const service = computed(() => Math.round(subtotal.value * (Number(menu.value?.settings.service_pct) || 0) / 100))
const tax = computed(() => Math.round(subtotal.value * (Number(menu.value?.settings.tax_pct) || 0) / 100))
const total = computed(() => subtotal.value + service.value + tax.value)

const recommendations = computed(() => (menu.value?.products ?? []).filter(p => p.is_available && !lines.value.some(line => line.productId === p.id)).slice(0, 6))
const nameMissing = computed(() => !!menu.value?.settings.require_customer_name && !name.value.trim())
const orderingPaused = computed(() => menu.value?.settings.orders_enabled === false)
const checkoutDisabled = computed(() => submitting.value || (!pendingCheckout.value && (orderingPaused.value || !catalogReady.value || !lines.value.length || nameMissing.value)))
const checkoutHint = computed(() => pendingCheckout.value ? 'Pengiriman sebelumnya akan diperiksa kembali. Jangan membuat pesanan baru.' : orderingPaused.value ? 'Pemesanan belum dibuka. Silakan hubungi kasir.' : !catalogReady.value ? 'Menunggu harga terbaru.' : nameMissing.value ? 'Isi nama untuk melanjutkan pesanan.' : 'Pembayaran dilakukan tunai di kasir setelah pesanan dibuat.')
function changeQuantity(line: CartLine, qty: number) {
  if (submitting.value || pendingCheckout.value) return
  if (qty < 1) removedLine.value = { line: { ...line, variantIds: [...line.variantIds], addonIds: [...line.addonIds] }, index: lines.value.findIndex(l => l.key === line.key) }
  setQty(line.key, qty)
}
function undoRemoval() {
  if (!removedLine.value || submitting.value || pendingCheckout.value) return
  if (!restore(removedLine.value.line, removedLine.value.index)) { error.value = 'Jumlah menu ini sudah mencapai batas 50. Kurangi jumlah sebelum mengembalikan item.'; return }
  removedLine.value = null
}
useHead(() => ({ title: props.checkout ? 'Pesan · TerasKayuManis' : 'Keranjang · TerasKayuManis' }))

async function placeOrder() {
  if (submitting.value) return
  error.value = ''
  submitting.value = true
  try {
    // Recovery uses the original identity and payload, even if the cart, table,
    // name or catalog changed. Never validate or create a NEW attempt first.
    let pending = JSON.parse(sessionStorage.getItem('tkm-checkout') || 'null') as { body: string; key: string; token: string } | null
    if (!pending) {
    if (orderingPaused.value) { error.value='Restoran belum menerima pesanan baru. Silakan hubungi kasir.';return }
    if (!catalogReady.value || sessionStorage.getItem('tkm-reorder')) {
      error.value = 'Muat ulang harga dan periksa pesanan ulang sebelum memesan.'
      return
    }
    if (menu.value?.settings.require_customer_name && !name.value.trim()) {
      error.value = 'Mohon isi nama Anda.'
      return
    }
    const payload: CreateOrderPayload = {
      customer_name: name.value.trim(),
      payment_method: payment.value,
      items: lines.value.map((l) => ({
        product_id: l.productId,
        variant_ids: l.variantIds,
        addon_ids: l.addonIds,
        quantity: l.qty,
        notes: l.notes
      }))
    }
    const validation=prepareReorder(payload,menu.value?.products??[])
    if(!payload.items.length||validation.errors.length){error.value=validation.errors.join(' ')||'Keranjang kosong.';return}
    pending = { body: JSON.stringify(payload), key: crypto.randomUUID(), token: crypto.randomUUID() + crypto.randomUUID() }
    sessionStorage.setItem('tkm-checkout', JSON.stringify(pending))
    }
    pendingCheckout.value = true
    const res = await $fetch<{ id: string }>('/api/core/orders', { method: 'POST', body: JSON.parse(pending.body), headers: { 'Idempotency-Key': pending.key, 'X-Order-Token': pending.token } })
    sessionStorage.setItem('tkm-order-' + res.id, pending.token)
    sessionStorage.removeItem('tkm-checkout')
    pendingCheckout.value = false
    clear()
    await navigateTo(`/order/${res.id}`)
  } catch (e: unknown) {
    if(isCheckoutRejected(e)){
      sessionStorage.removeItem('tkm-checkout')
      pendingCheckout.value=false
      error.value='Pesanan ditolak dan tidak dibuat. Perbaiki keranjang sebelum memesan lagi.'
      return
    }
    error.value = 'Pesanan belum dapat dipastikan. Periksa koneksi lalu coba ulang pengiriman yang sama. Jika masih bermasalah, hubungi kasir sebelum memesan lagi.'
    // Retain the attempt on ambiguous responses; retry must use the same key.
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <main class="customer-shell" :class="checkout ? 'customer-checkout' : 'customer-cart'">
    <p v-if="orderingPaused" class="ops-alert" role="status">Restoran belum menerima pesanan baru. Hubungi kasir untuk informasi lebih lanjut.</p>
    <header class="customer-header customer-cart-header">
      <NuxtLink :to="checkout ? '/cart' : '/menu'" class="customer-icon" :aria-label="checkout ? 'Kembali ke keranjang' : 'Kembali ke menu'"><Icon name="arrow-left" :size="20" /></NuxtLink>
      <h1>{{ checkout ? 'Pesan' : 'Keranjang' }}</h1>
      <RestaurantLogo :size="40" eager />
    </header>

    <div v-if="error" class="customer-cart-notice customer-cart-error" role="alert">{{ error }}</div>
    <div v-if="removedLine" class="customer-cart-notice customer-cart-undo" role="status"><span>{{ productOf(removedLine.line.productId)?.name || 'Item' }} dihapus.</span><button type="button" class="customer-text-button" :disabled="submitting||pendingCheckout" @click="undoRemoval">Urungkan</button></div>
    <div v-if="pendingCheckout" class="customer-cart-notice">
      <p>Checkout sebelumnya belum pasti. Coba ulang pengiriman yang sama; perubahan keranjang tidak dikirim dan tidak membuat pesanan baru.</p>
      <button class="customer-button" :disabled="submitting" @click="placeOrder">Coba ulang pengiriman</button>
    </div>
    <div v-if="!catalogReady" class="customer-state" role="status">
      <p>Harga belum diperbarui. Muat ulang sebelum mengonfirmasi pesanan.</p>
      <button class="customer-button customer-button-outline" :disabled="refreshing||submitting" @click="loadCart">Muat ulang harga</button>
    </div>
    <div v-else-if="!lines.length" class="customer-state customer-cart-empty">
      <Icon name="bag" :size="40" />
      <h2>Keranjang Anda masih kosong</h2>
      <NuxtLink to="/menu" class="customer-button">Lihat Menu</NuxtLink>
    </div>

    <template v-else-if="!checkout">
      <div class="customer-cart-layout">
      <div class="customer-cart-primary">
      <section class="customer-cart-items" aria-label="Item dalam keranjang">
      <ul id="cart-items" class="customer-cart-list">
        <li v-for="line in visibleLines" :key="line.key" class="customer-cart-row">
          <CustomerImage :src="productOf(line.productId)?.image_url" :alt="productOf(line.productId)?.name ?? 'Menu tidak tersedia'" />
          <div class="customer-cart-copy">
              <h2>{{ productOf(line.productId)?.name ?? 'Menu tidak tersedia' }}</h2>
              <p v-if="line.variantIds.length" class="customer-cart-options">
                {{ line.variantIds.map((id) => productOf(line.productId)?.variants.find((v) => v.id === id)?.name).filter(Boolean).join(' · ') }}
              </p>
              <p v-if="line.addonIds.length" class="customer-cart-options">
                + {{ line.addonIds.map((id) => productOf(line.productId)?.addons.find((a) => a.id === id)?.name).filter(Boolean).join(', ') }}
              </p>
              <p v-if="line.notes" class="customer-cart-options customer-cart-note">{{ line.notes }}</p>
              <NuxtLink v-if="!pendingCheckout&&!submitting" :to="{path: `/menu/${line.productId}`, query: {edit: line.key, returnTo: '/cart'}}" class="customer-cart-edit" :aria-label="`Ubah ${productOf(line.productId)?.name || 'item'}`">Ubah pilihan / catatan</NuxtLink>
            <div class="customer-cart-actions">
              <strong>{{ fmtIDR(linePrice(line, productOf(line.productId)) * line.qty) }}</strong>
              <div class="customer-cart-quantity" :aria-label="`Jumlah ${productOf(line.productId)?.name}`">
                <button :aria-label="line.qty === 1 ? `Hapus ${productOf(line.productId)?.name} dari keranjang` : `Kurangi ${productOf(line.productId)?.name}`" :disabled="submitting||pendingCheckout" @click="changeQuantity(line, line.qty - 1)"><span><Icon name="minus" :size="18" /></span></button>
                <output :aria-label="`Jumlah ${productOf(line.productId)?.name}`">{{ line.qty }}</output>
                <button :aria-label="`Tambah ${productOf(line.productId)?.name}`" :disabled="line.qty >= 50||submitting||pendingCheckout" @click="changeQuantity(line, line.qty + 1)"><span><Icon name="plus" :size="18" /></span></button>
              </div>
            </div>
          </div>
        </li>
      </ul>
      <button v-if="lines.length > 2" class="customer-cart-expand" :aria-expanded="expanded" aria-controls="cart-items" @click="expanded = !expanded">{{ expanded ? 'Lihat lebih sedikit' : 'Lihat semua' }}<Icon name="chevron-down" :size="12" :class="{ expanded }" /></button>
      </section>
      <NuxtLink to="/menu" class="customer-cart-add">+ Tambah</NuxtLink>
      </div>
      <section v-if="recommendations.length" class="customer-checkout-section customer-checkout-recommendations customer-cart-recommendations" aria-labelledby="checkout-recommendations-title">
        <h2 id="checkout-recommendations-title">Rekomendasi</h2>
        <div class="customer-recommendation-strip">
          <NuxtLink v-for="product in recommendations" :key="product.id" :to="{path: `/menu/${product.id}`, query: {returnTo: '/cart'}}" :aria-label="`Tambah ${product.name}`">
            <CustomerImage :src="product.image_url" :alt="product.name" />
            <div><h3>{{ product.name }}</h3><strong>{{ fmtIDR(product.price) }}</strong></div>
            <span class="customer-checkout-recommendation-plus"><Icon name="plus" :size="14" /></span>
          </NuxtLink>
        </div>
      </section>
      </div>

      <footer ref="fixedFooter" class="customer-cart-footer">
        <div class="customer-cart-total">
          <span>Total</span>
          <strong>{{ fmtIDR(total) }}</strong>
        </div>
        <button class="customer-button customer-cart-submit" :disabled="submitting||pendingCheckout" @click="navigateTo('/checkout')">{{ submitting ? 'Memproses...' : 'Pesan' }}</button>
      </footer>

    </template>

    <template v-else>
      <div class="customer-checkout-layout">
      <section class="customer-checkout-section" aria-labelledby="checkout-products-title">
        <h2 id="checkout-products-title">Produk</h2>
        <ul id="checkout-products" class="customer-checkout-products">
          <li v-for="line in visibleLines" :key="line.key">
            <CustomerImage :src="productOf(line.productId)?.image_url" :alt="productOf(line.productId)?.name ?? 'Menu tidak tersedia'" />
            <div class="customer-checkout-product-copy">
              <h3>{{ productOf(line.productId)?.name ?? 'Menu tidak tersedia' }}</h3>
              <p v-if="line.variantIds.length" class="customer-cart-options">{{ line.variantIds.map(id => productOf(line.productId)?.variants.find(v => v.id === id)?.name).filter(Boolean).join(' · ') }}</p>
              <p v-if="line.addonIds.length" class="customer-cart-options">+ {{ line.addonIds.map(id => productOf(line.productId)?.addons.find(a => a.id === id)?.name).filter(Boolean).join(', ') }}</p>
              <p v-if="line.notes" class="customer-cart-options customer-cart-note">{{ line.notes }}</p>
              <span>x{{ line.qty }}</span>
            </div>
            <span class="customer-checkout-product-price">{{ fmtIDR(linePrice(line, productOf(line.productId)) * line.qty) }}</span>
          </li>
        </ul>
        <button v-if="lines.length > 2" class="customer-checkout-expand" :aria-expanded="expanded" aria-controls="checkout-products" @click="expanded = !expanded">{{ expanded ? 'Lihat lebih sedikit' : 'Lihat semua' }}<Icon name="chevron-down" :size="12" /></button>
        <dl class="customer-checkout-totals">
          <div><dt>Subtotal</dt><dd>{{ fmtIDR(subtotal) }}</dd></div>
          <div v-if="service"><dt>Service {{ menu?.settings.service_pct }}%</dt><dd>{{ fmtIDR(service) }}</dd></div>
          <div v-if="tax"><dt>Pajak {{ menu?.settings.tax_pct }}%</dt><dd>{{ fmtIDR(tax) }}</dd></div>
          <div class="customer-checkout-grand-total"><dt>Estimasi total</dt><dd>{{ fmtIDR(total) }}</dd></div>
        </dl>
      </section>
      <form id="customer-checkout-form" class="customer-checkout-section customer-checkout-form" @submit.prevent="!checkoutDisabled && placeOrder()">
        <div class="customer-section-heading"><h2>Data pemesan</h2><p>Lengkapi sebelum membuat pesanan.</p></div>
        <div class="customer-checkout-field">
          <label for="cust-name">Nama <span v-if="menu?.settings.require_customer_name" class="customer-required">*</span><span v-else class="customer-muted">(opsional)</span></label>
          <input id="cust-name" v-model="name" placeholder="Contoh: Budi Santoso" autocomplete="name" maxlength="100" :required="!!menu?.settings.require_customer_name" :disabled="submitting||pendingCheckout" :aria-invalid="nameTouched && nameMissing" :aria-describedby="nameTouched && nameMissing ? 'checkout-name-error' : undefined" @blur="nameTouched = true">
          <p v-if="nameTouched && nameMissing" id="checkout-name-error" class="customer-checkout-field-error">Nama belum diisi</p>
        </div>
        <div class="customer-checkout-order-type"><h2>Tipe Pesanan</h2><p>Makan di Tempat</p></div>
        <p class="customer-checkout-instructions">Tunjukkan nomor pesanan kepada kasir, selesaikan pembayaran, lalu ambil nomor meja. Total di web adalah estimasi; tagihan akhir dan struk resmi dari kasir.</p>
      </form>
      </div>
      <footer ref="fixedFooter" class="customer-checkout-footer">
        <p class="customer-checkout-cash"><Icon name="cash" :size="22" /><span><strong>Bayar tunai di kasir</strong><small>Tunjukkan nomor pesanan setelah memesan.</small></span></p>
        <p id="checkout-hint" class="customer-checkout-hint" role="status">{{ checkoutHint }}</p>
        <button type="submit" form="customer-checkout-form" aria-describedby="checkout-hint" class="customer-button customer-cart-submit" :disabled="checkoutDisabled">{{ submitting ? 'Memproses...' : pendingCheckout ? 'Coba ulang pengiriman' : `Pesan Sekarang · ${fmtIDR(total)}` }}</button>
      </footer>

    </template>
  </main>
</template>
