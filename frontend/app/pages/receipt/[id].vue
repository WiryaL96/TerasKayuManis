<script setup lang="ts">
definePageMeta({ layout: 'customer' })
import {normalizeReceipt,type ReceiptData} from '#shared/dashboard-data'
import { money, wibTime } from '#shared/operations'
useHead({
  title: 'Struk · TerasKayuManis',
  meta: [
    { name: 'robots', content: 'noindex,nofollow' },
    { name: 'referrer', content: 'no-referrer' },
  ],
})
const route = useRoute(),
  data = ref<ReceiptData | null>(null),
  error = ref('')
const store=useDashboardCache(),client=useSupabase()
const cachedReceipt=useReceiptPrefetch()
let disposed=false,controller:AbortController|undefined
onUnmounted(()=>{disposed=true;controller?.abort()})
watch(store.revision,()=>{if(!store.cache.scope&&!sessionStorage.getItem('tkm-order-'+String(route.params.id)))data.value=null})
onMounted(async () => {
  try {
    const id = String(route.params.id),
      token = sessionStorage.getItem('tkm-order-' + id)
    const headers: Record<string, string> = {}
    if (token) headers['X-Order-Token'] = token
    else {
      const {
        data: { session },
      } = await client.auth.getSession()
      if (session) headers.Authorization = 'Bearer ' + session.access_token
    }
    controller=new AbortController()
    const receipt=!token&&store.cache.scope?await cachedReceipt(id):normalizeReceipt(await $fetch(`/api/core/orders/${id}/receipt`,{headers,signal:controller.signal,retry:0,timeout:15000}))
    if(!receipt)throw new Error('Struk belum dapat dimuat')
    if(!disposed)data.value=receipt
  } catch {
    error.value =
      'Struk belum tersedia atau akses tidak valid. Pesanan harus sudah lunas. Buka dari halaman pesanan atau login staf.'
  }
})
function print() {
  window.print()
}
</script>
<template>
  <main class="customer-shell receipt-shell">
    <div class="receipt-actions">
      <button class="ops-button secondary" @click="$router.back()">
        Kembali</button
      ><button v-if="data" class="ops-button" @click="print">
        Cetak struk
      </button>
    </div>
    <p v-if="error" role="alert" class="ops-alert">{{ error }}</p>
    <article v-else-if="data" class="receipt-paper">
      <header>
        <RestaurantLogo :size="96" eager class="receipt-logo" />
        <p>{{ data.brand }}</p>
        <h1>Struk pembayaran</h1>
        <strong>{{ data.order.order_number }}</strong
        ><small>{{ wibTime(data.payment.paid_at) }} WIB</small>
      </header>
      <p v-if="data.order.customer_name">
        Pelanggan: {{ data.order.customer_name }}
      </p>
      <table>
        <thead>
          <tr>
            <th>Item</th>
            <th>Jumlah</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in data.order.order_items" :key="i.id">
            <td>
              <strong>{{ i.quantity }}× {{ i.product_name }}</strong
              ><small>{{ i.variant_name }}</small
              ><small v-for="a in i.order_item_addons" :key="a.addon_name"
                >+ {{ a.addon_name }} ({{ money(a.price) }})</small
              ><small
                >{{ money(i.unit_price) }} / item<span v-if="i.addons_total">
                  + add-on {{ money(i.addons_total) }}</span
                ></small
              >
            </td>
            <td>{{ money(i.subtotal) }}</td>
          </tr>
        </tbody>
      </table>
      <dl>
        <div>
          <dt>Subtotal</dt>
          <dd>{{ money(data.order.subtotal) }}</dd>
        </div>
        <div v-if="data.order.discount">
          <dt>Diskon</dt>
          <dd>−{{ money(data.order.discount) }}</dd>
        </div>
        <div>
          <dt>Service</dt>
          <dd>{{ money(data.order.service_charge) }}</dd>
        </div>
        <div>
          <dt>Pajak</dt>
          <dd>{{ money(data.order.tax) }}</dd>
        </div>
        <div class="receipt-total">
          <dt>Total</dt>
          <dd>{{ money(data.payment.total) }}</dd>
        </div>
        <div>
          <dt>Tunai diterima</dt>
          <dd>{{ money(data.payment.received) }}</dd>
        </div>
        <div>
          <dt>Kembalian</dt>
          <dd>{{ money(data.payment.change) }}</dd>
        </div>
      </dl>
      <footer>
        <p>
          Kasir:
          <strong>{{
            data.payment.cashier_name || 'Nama kasir belum tercatat'
          }}</strong>
        </p>
        <p>Terima kasih sudah berkunjung.</p>
        <small
          >Salinan pembayaran · cetak ulang tidak membuat transaksi baru</small
        >
      </footer>
    </article>
    <p v-else role="status">Memuat struk…</p>
  </main>
</template>
<style>
.receipt-shell {
  max-width: 672px;
  margin: auto;
  padding: 20px;
}
.receipt-actions {
  display: flex;
  justify-content: space-between;
  margin-bottom: 20px;
}
.receipt-paper {
  background: white;
  padding: clamp(16px, 5vw, 32px);
  border: 1px solid #ddd;
  color: #222;
}
.receipt-paper header {
  text-align: center;
  margin-bottom: 24px;
}
.receipt-paper header p {
  font-size: 24px;
  font-weight: 800;
}
.receipt-paper .receipt-logo {
  display: block;
  margin: 0 auto 12px;
}
.receipt-paper h1 {
  font-size: 16px;
  margin: 8px;
}
.receipt-paper header strong {
  font-size: 22px;
}
.receipt-paper small {
  display: block;
  color: #666;
  font-size: 12px;
  margin-top: 4px;
}
.receipt-paper table {
  width: 100%;
  border-collapse: collapse;
  margin: 20px 0;
}
.receipt-paper td,
.receipt-paper th {
  border-bottom: 1px dashed #ddd;
  padding: 14px 0;
  text-align: left;
  vertical-align: top;
}
.receipt-paper td:last-child,
.receipt-paper th:last-child {
  text-align: right;
  white-space: nowrap;
}
.receipt-paper dl > div {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  padding: 7px 0;
}
.receipt-total {
  border-top: 1px solid #333;
  font-size: 20px;
  font-weight: 800;
  margin-top: 10px;
  padding-top: 15px !important;
}
.receipt-paper footer {
  border-top: 1px dashed #ddd;
  margin-top: 20px;
  padding-top: 20px;
  text-align: center;
}
.receipt-paper footer p {
  margin: 10px 0;
}
@media print {
  @page {
    margin: 12mm;
  }
  body {
    background: white !important;
  }
  .receipt-actions {
    display: none !important;
  }
  .receipt-shell {
    padding: 0;
    max-width: none;
  }
  .receipt-paper {
    border: 0;
    padding: 0;
    font-size: 12px;
  }
  a {
    color: inherit !important;
  }
  .receipt-paper tr {
    break-inside: avoid;
  }
}
</style>
