<script setup lang="ts">
definePageMeta({ layout: 'customer' })

import { remainingSeconds, formatCountdown } from '#shared/order-flow'
import type { CreateOrderPayload, Order, OrderStatus } from '#shared/types'
import type { RealtimeStatus } from '#shared/realtime'

const route = useRoute()
const order = ref<Order | null>(null)
const loadError = ref('')
const lastUpdated = ref('')
const retrying = ref(false)
const reorderError=ref(''),reordering=ref(false),now=ref(Date.now())
async function reorder(){
 if(reordering.value)return;reordering.value=true;reorderError.value=''
 try{
 if(sessionStorage.getItem('tkm-checkout')){reorderError.value='Selesaikan checkout sebelumnya yang belum pasti dahulu.';return}
 const payload=await $fetch<CreateOrderPayload>(`/api/core/orders/${route.params.uuid}/reorder`,{headers:{'X-Order-Token':sessionStorage.getItem('tkm-order-'+route.params.uuid)||''}})
 if(!confirm('Isi keranjang akan diganti pesanan lama. Harga dan menu diperiksa ulang; belum membuat order baru.'))return
 sessionStorage.setItem('tkm-reorder',JSON.stringify(payload))
 await navigateTo('/cart')
 }catch{reorderError.value='Pesanan ulang gagal disiapkan. Coba lagi atau hubungi kasir.'}finally{reordering.value=false}
}

const STEPS: { key: OrderStatus; label: string }[] = [
  { key: 'pending', label: 'Ke kasir' },
  { key: 'pos_input', label: 'Ditangani kasir' },
  { key: 'forwarded', label: 'Konfirmasi selesai' }
]

const realtimeStatus=ref<RealtimeStatus>('polling')
const realtimeLabel=computed(()=>loadError.value?'Koneksi terganggu, mencoba lagi':realtimeStatus.value==='connecting'?'Menghubungkan ke pesanan…':'Status diperbarui otomatis')
let realtime:ReturnType<typeof useRealtime<Order>>|undefined
let mounted=false
function trackOrder(){
 realtime?.dispose();realtime=undefined
 order.value=null;loadError.value='';reorderError.value='';lastUpdated.value='';retrying.value=false
 if(!mounted)return
 const id=String(route.params.uuid)
 realtime=useRealtime<Order>({scope:{channel:'order',order_id:id},
  subscribe:async()=>{const token=sessionStorage.getItem('tkm-order-'+id);return token?{type:'subscribe',channel:'order',order_id:id,order_token:token}:null},
  fetchSnapshot:({signal})=>$fetch<Order>(`/api/core/orders/${id}`,{signal,headers:{'X-Order-Token':sessionStorage.getItem('tkm-order-'+id)||''}}),
  apply:snapshot=>{
   if(String(route.params.uuid)!==id||snapshot.id!==id)return
   if(!order.value||snapshot.version>=order.value.version)order.value=snapshot
   lastUpdated.value=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit'}).format(new Date())+' WIB'
   loadError.value='';retrying.value=false
  },
  onStatus:value=>realtimeStatus.value=value,
  onError:()=>{retrying.value=false;loadError.value='Pesanan tidak dapat dimuat. Periksa koneksi atau hubungi kasir.'}
 })
 realtime.start()
}
function retryOrder(){if(retrying.value||!realtime)return;retrying.value=true;realtime.refresh()}
watch(()=>route.params.uuid,trackOrder,{flush:'sync'})
onMounted(()=>{mounted=true;trackOrder()})
// Server status remains authoritative; local clock only displays remaining time.
let clock:ReturnType<typeof setInterval>|undefined
onMounted(()=>{clock=setInterval(()=>now.value=Date.now(),1000)})
onUnmounted(() => {mounted=false;realtime?.dispose();clearInterval(clock)})

const stepIndex = computed(() => STEPS.findIndex((s) => s.key === order.value?.status))
const secondsLeft = computed(() => order.value ? remainingSeconds(order.value.expires_at, now.value) : 0)
</script>

<template>
  <main class="customer-shell customer-order">
    <header class="customer-header"><NuxtLink to="/menu" class="customer-icon" aria-label="Kembali ke menu"><Icon name="arrow-left" /></NuxtLink><h1>Pesanan Saya</h1><RestaurantLogo :size="40" eager /></header>
    <div class="customer-order-content">
      <p class="customer-order-connection" role="status"><span :class="{ connected: realtimeStatus === 'connected' }"></span>{{ realtimeLabel }}</p>
      <div v-if="loadError" class="customer-order-state" role="alert"><h2>{{ order ? 'Status belum diperbarui' : 'Pesanan belum dapat dimuat' }}</h2><p>{{ loadError }}</p><p v-if="order">Informasi terakhir diperbarui {{ lastUpdated }}. Pastikan status terbaru ke kasir sebelum membayar atau memesan ulang.</p><button class="customer-button" :disabled="retrying" @click="retryOrder">{{ retrying ? 'Memeriksa…' : 'Coba lagi' }}</button><a class="customer-text-button" href="https://wa.me/6282246851927" target="_blank" rel="noopener noreferrer">Hubungi restoran</a></div>
      <template v-if="order">
        <div class="customer-order-layout">
        <div class="customer-order-status">
        <section class="customer-order-number" aria-label="Nomor pesanan"><p>Nomor Pesanan</p><h2>{{ order.order_number }}</h2><p v-if="order.customer_name">{{ order.customer_name }}</p><small>Tunjukkan nomor ini kepada kasir</small></section>
        <section v-if="order.status === 'pending'" class="customer-order-notice" :class="{ urgent: secondsLeft <= 180 }" aria-label="Petunjuk pembayaran">
          <div class="customer-order-notice-title"><Icon name="clock" :size="22" /><h2>{{ secondsLeft > 0 ? 'Segera menuju kasir' : 'Batas waktu ke kasir habis' }}</h2></div>
          <p v-if="secondsLeft > 0">Tunjukkan nomor pesanan sebelum waktu habis. Kasir memeriksa menu dan memproses pembayaran. Setelah bayar, ambil nomor meja di kasir.</p>
          <p v-else>Status pesanan sedang diperbarui. Hubungi kasir sebelum melakukan pembayaran.</p>
          <div class="customer-order-timer"><span>Sisa waktu ke kasir<small>menit : detik</small></span><strong>{{ formatCountdown(secondsLeft) }}</strong></div>
          <small>Harga di web adalah estimasi. Tagihan akhir dan struk resmi mengikuti aplikasi kasir. Revisi tidak menambah batas waktu ke kasir.</small>
        </section>
        <section v-else-if="order.status === 'expired'" class="customer-order-notice urgent"><h2>Batas waktu ke kasir habis</h2><p>Batas konfirmasi 15 menit sudah lewat. Silakan buat pesanan baru atau hubungi kasir.</p><button class="customer-button" :disabled="reordering" @click="reorder">{{ reordering ? 'Menyiapkan…' : 'Pesan ulang' }}</button><p v-if="reorderError" role="alert">{{ reorderError }}</p></section>
        <section v-else-if="order.status === 'cancelled'" class="customer-order-notice urgent"><h2>Pesanan dibatalkan</h2><p>Silakan hubungi kasir untuk informasi lebih lanjut.</p></section>
        <section v-else-if="order.status==='pos_input'" class="customer-order-notice"><h2>Pesanan sedang ditangani kasir</h2><p>Selesaikan konfirmasi menu dan pembayaran di kasir, lalu ambil nomor meja.</p></section>
        <section v-else-if="order.status==='forwarded'" class="customer-order-notice customer-order-success"><h2>Pesanan sudah dikonfirmasi kasir</h2><p>Terima kasih. Ambil nomor meja di kasir dan ikuti petunjuk staf. Struk resmi serta informasi hidangan diberikan oleh kasir restoran.</p><small>Untuk perubahan pesanan atau informasi hidangan, hubungi kasir.</small></section>
        <section v-else class="customer-order-notice customer-order-success"><h2>Riwayat transaksi web</h2><p>Catatan transaksi lama tetap tersimpan. Hubungi kasir untuk informasi pesanan.</p></section>
        <ol v-if="order.status !== 'expired' && order.status !== 'cancelled'" class="customer-order-steps" aria-label="Tahapan pesanan">
          <li v-for="(step, i) in STEPS" :key="step.key" :class="{ done: i < stepIndex, current: i === stepIndex }" :aria-current="i === stepIndex ? 'step' : undefined"><span><Icon v-if="i < stepIndex" name="check" :size="14" /><template v-else>{{ i + 1 }}</template></span><p>{{ step.label }}</p></li>
        </ol>
        </div>
        <div class="customer-order-summary">
        <section class="customer-order-card"><h2>Detail Pesanan</h2><ul class="customer-order-items"><li v-for="item in order.order_items" :key="item.id"><span class="customer-order-qty">{{ item.quantity }}×</span><div><h3>{{ item.product_name }}</h3><p v-if="item.variant_name">{{ item.variant_name }}</p><p v-for="a in item.order_item_addons" :key="a.addon_name">+ {{ a.addon_name }}</p><p v-if="item.notes" class="customer-order-note">Catatan: {{ item.notes }}</p></div><strong>{{ fmtIDR(item.subtotal) }}</strong></li></ul>
          <dl class="customer-order-totals"><div><dt>Subtotal</dt><dd>{{ fmtIDR(order.subtotal) }}</dd></div><div v-if="order.discount"><dt>Diskon</dt><dd>−{{ fmtIDR(order.discount) }}</dd></div><div v-if="order.service_charge"><dt>Service</dt><dd>{{ fmtIDR(order.service_charge) }}</dd></div><div v-if="order.tax"><dt>Pajak</dt><dd>{{ fmtIDR(order.tax) }}</dd></div><div class="customer-order-total"><dt>Total</dt><dd>{{ fmtIDR(order.total) }}</dd></div></dl>
        </section>
        <section class="customer-order-card customer-order-payment"><h2>Pembayaran melalui kasir</h2><p>Tagihan akhir dan struk resmi tersedia di aplikasi kasir restoran.</p><div><span>{{ order.pos_handoff ? 'Konfirmasi input POS' : 'Catatan web' }}</span><strong :class="{ paid: order.payment_status === 'paid' }">{{ order.status==='forwarded' ? 'Tercatat' : order.payment_status === 'paid' ? 'Transaksi web lama' : 'Konfirmasi ke kasir' }}</strong></div></section>
        <NuxtLink v-if="order.payment_status==='paid'" :to="`/receipt/${order.id}`" class="customer-button customer-button-outline customer-order-back">Lihat / cetak struk</NuxtLink>
        <NuxtLink to="/menu" class="customer-button customer-button-outline customer-order-back">Kembali ke Menu</NuxtLink>
        </div>
        </div>
      </template>
      <div v-else-if="!loadError" class="customer-order-state" role="status"><Icon name="bag" :size="32" /><p>Memuat pesananmu…</p></div>
    </div>
  </main>
</template>
