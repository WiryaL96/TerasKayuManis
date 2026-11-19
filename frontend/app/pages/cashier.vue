<script setup lang="ts">
import type { Order, MenuResponse, CreateOrderPayload, Profile } from '#shared/types'
import { canAcceptCash, remainingSeconds, formatCountdown, prepareReorder, isCheckoutRejected } from '#shared/order-flow'
import type { RealtimeStatus } from '#shared/realtime'
import type { AuthChangeEvent, Session } from '@supabase/supabase-js'
import { normalizeOrders,normalizeProfile,normalizeMenu,filterOrders } from '#shared/dashboard-data'
import { isAccessError } from '#shared/query-cache'
const store=useDashboardCache()
const prefetchReceipt=useReceiptPrefetch()
const snapshotAt=computed(()=>{void store.revision.value;return store.cache.peek(orderKey()).updatedAt})
const route = useRoute()
const { collapsed: sidebarCollapsed, theme: dashboardTheme, toggleCollapsed, toggleTheme } = useDashboardPreferences()
const error=ref(''),busy=ref(false),loggedIn=ref(false)
const orders=ref<Order[]>([]),menu=ref<MenuResponse|null>(null)
const detailPane=ref<HTMLElement|null>(null)
const account=ref<Profile|null>(null)
const hasStaffName=computed(()=>!!account.value?.full_name?.trim())
const posReference=reactive<Record<string,string>>({})
const posEntered=ref(false),posPaid=ref(false)
const tab=ref<'active'|'history'>('active'),offset=ref(0),now=ref(Date.now())
const search=ref(''),querySearch=ref(''),filterStatus=ref(''),sortOrder=ref<'newest'|'oldest'>('newest'),selectedId=ref(''),listing=ref(false)
watch(selectedId,()=>{posEntered.value=false;posPaid.value=false})
const pendingAttempt=ref(false)
const selectionMissing=ref(false)
let selectionInitialized=false

let searchTimer:ReturnType<typeof setTimeout>|undefined
watch(search,value=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{querySearch.value=value.trim()},350)})
function baseKey(){return `orders:${tab.value}:base`}
function completeListing(){const base=store.cache.peek<Order[]>(baseKey()).data;return base!==null&&base.length<100}
function orderQuery(){
 if(completeListing())return {tab:tab.value,sort:'newest',offset:0,limit:100}
 return {tab:tab.value,status:filterStatus.value||undefined,q:querySearch.value||undefined,sort:sortOrder.value,offset:offset.value,limit:100}
}
function orderKey(query=orderQuery()){return !('status' in query&&query.status)&&!('q' in query&&query.q)&&query.sort==='newest'&&query.offset===0?baseKey():`orders:${tab.value}:${JSON.stringify(query)}`}
async function fetchOrders(signal:AbortSignal){
 const query=orderQuery(),key=orderKey(query)
 const result=await store.cache.fetch(key,async abort=>normalizeOrders(await $fetch('/api/core/admin/orders',{signal:abort,headers:await headers(),query,retry:0,timeout:15000})),{signal,staleTime:5000})
 // A previously complete queue may grow beyond one page while a filter is active.
 const next=orderQuery(),nextKey=orderKey(next)
 if(nextKey!==key)return store.cache.fetch(nextKey,async abort=>normalizeOrders(await $fetch('/api/core/admin/orders',{signal:abort,headers:await headers(),query:next,retry:0,timeout:15000})),{signal,staleTime:5000})
 return result
}
const editing=ref<Order|null>(null),draft=ref<CreateOrderPayload|null>(null)
const draftIdentity=ref(0)
const client=useSupabase()
let generation=0
let realtime:ReturnType<typeof useRealtime<Order[]>>|undefined
let disposed=false
const realtimeStatus=ref<RealtimeStatus>('polling')
const realtimeLabel=computed(()=>realtimeStatus.value==='connected'?'Terhubung':realtimeStatus.value==='connecting'?'Menyambungkan…':'Sinkron berkala')
function applyOrders(data:Order[]){
 const previous=new Map(orders.value.map(o=>[o.id,o]))
 const view=completeListing()?filterOrders(data,{tab:tab.value,status:filterStatus.value,q:querySearch.value,sort:sortOrder.value}):data
 orders.value=view.map(o=>{const old=previous.get(o.id);return old&&old.version>o.version?old:o})
 if(!selectionInitialized&&orders.value.length){selectedId.value=orders.value[0]!.id;selectionInitialized=true}
 selectionMissing.value=!!selectedId.value&&!orders.value.some(o=>o.id===selectedId.value)
 listing.value=false
}
function selectOrder(id:string){selectedId.value=id;selectionInitialized=true;selectionMissing.value=false;void nextTick(()=>detailPane.value?.scrollTo?.({top:0,behavior:'auto'}))}
function startRealtime(){
 if(realtime)return
 if(disposed||!loggedIn.value||typeof window==='undefined')return
 const cached=store.cache.peek<Order[]>(orderKey()).data
 if(cached)applyOrders(cached)
 listing.value=!cached
 realtime=useRealtime<Order[]>({scope:{channel:'cashier'},snapshotKey:()=>orderKey(),
  subscribe:async()=>{const {data}=await client.auth.getSession();return data.session?{type:'subscribe',channel:'cashier',access_token:data.session.access_token}:null},
  fetchSnapshot:({signal})=>fetchOrders(signal),
  onInvalidate:reason=>{if(reason==='event')store.changed('orders');else store.cache.invalidate('orders:')},
  apply:applyOrders,onStatus:value=>realtimeStatus.value=value,
  onError:e=>{listing.value=false;if(isAccessError(e)){clearSession();store.cache.bind('')}error.value='Tidak dapat memperbarui pesanan. Data terakhir tetap terlihat jika tersedia. Periksa login dan koneksi.'}
 })
 realtime.setBusy(busy.value);realtime.start()
}
watch(busy,value=>realtime?.setBusy(value),{flush:'sync'})
watch([tab,filterStatus,querySearch,sortOrder,offset],(values,old)=>{
 if(values.slice(0,4).some((v,i)=>v!==old[i])&&offset.value!==0){offset.value=0;return}
 generation++
 const cached=store.cache.peek<Order[]>(orderKey()).data
 if(cached)applyOrders(cached)
 else{orders.value=[];listing.value=true}
 if(loggedIn.value&&!completeListing())realtime?.refresh(true)
},{flush:'pre'})
async function headers(){
 const {data}=await client.auth.getSession();if(!data.session)throw new Error('Login diperlukan')
 return {Authorization:`Bearer ${data.session.access_token}`}
}
async function load(force=true){
 if(disposed)return
 if(realtime){if(force)store.cache.invalidate('orders:');realtime.refresh(true);return}
 const seq=++generation
 try {
 listing.value=true
 const auth=await headers()
 const identity=normalizeProfile(await $fetch<Profile>('/api/core/admin/me',{headers:auth,retry:0,timeout:15000}))
 if(seq!==generation)return
 store.bind(identity);store.cache.set('cashier-identity',identity)
 account.value=identity;loggedIn.value=true;startRealtime()
 }catch{if(seq===generation){listing.value=false;error.value='Pesanan belum dapat dimuat. Periksa koneksi. Jika akun belum aktif atau sesi dicabut, minta admin memeriksa status akun atau mengatur password baru, lalu login kembali.'}}
}
async function authenticated(){busy.value=true;error.value='';try{await load()}finally{busy.value=false}}
async function edit(o:Order){
 if(busy.value)return;busy.value=true;error.value=''
 try{menu.value=await store.cache.fetch('cashier-menu',async signal=>normalizeMenu(await $fetch('/api/core/menu',{signal,retry:0,timeout:15000})),{staleTime:60000});editing.value=JSON.parse(JSON.stringify(o));draft.value=null}catch{error.value='Menu gagal dimuat.'}finally{busy.value=false}
}
function initial(o:Order):CreateOrderPayload['items']{return (o.order_items??[]).map(i=>({product_id:i.product_id,quantity:i.quantity,variant_ids:i.variant_ids??[],addon_ids:i.addon_ids??[],notes:i.notes??''}))}
async function review(items:CreateOrderPayload['items']){
 const o=editing.value;if(!o||busy.value)return;busy.value=true;error.value=''
 try{
 const auth=await headers()
 const updated=await store.mutation(()=>$fetch<Order>(`/api/core/orders/${o.id}/review`,{method:'POST',headers:auth,body:{expected_version:o.version,items},retry:0,timeout:20000}))
 store.changed('orders')
 editing.value=null;await load()
 }catch{error.value='Review belum tersimpan atau versi berubah/waktu habis. Muat ulang dan periksa lagi sebelum menerima uang.';editing.value=null;await load()}finally{busy.value=false}
}
async function posAction(o:Order,kind:'claim-pos'|'forward-pos',takeover=false){
 if(busy.value||editing.value||draft.value)return
 if(!hasStaffName.value){error.value='Minta admin melengkapi nama akun sebelum menangani pesanan.';return}
 let takeoverReason=''
 if(takeover){
  takeoverReason=prompt('Periksa aplikasi kasir terlebih dahulu agar pesanan tidak diinput dua kali. Tuliskan alasan pengambilalihan (5–200 karakter):')?.trim()||''
  if(takeoverReason.length<5||takeoverReason.length>200)return
 }else if(kind==='claim-pos'&&!canAcceptCash(o,Date.now())){error.value='Periksa menu dahulu; pesanan harus belum kedaluwarsa.';return}
 if(kind==='forward-pos'&&(!posEntered.value||!posPaid.value||o.pos_handoff?.cashier_id!==account.value?.id))return
 if(!confirm(kind==='claim-pos'?'Tangani pesanan '+o.order_number+'? Pesanan akan ditandai atas nama Anda. Periksa apakah sudah ada di aplikasi kasir sebelum input manual.':'Konfirmasi '+o.order_number+' sudah dimasukkan dan pembayaran selesai di aplikasi kasir? Web hanya mencatat konfirmasi manual; struk resmi tetap dari aplikasi kasir.'))return
 busy.value=true;error.value=''
 try{
  const auth=await headers()
  const updated=normalizeOrders([await store.mutation(()=>$fetch<Order>(`/api/core/orders/${o.id}/${kind}`,{method:'POST',headers:auth,body:{expected_version:o.version,...(kind==='forward-pos'?{pos_reference:posReference[o.id]||'',entered_in_pos:true,paid_in_pos:true}:takeover?{takeover_reason:takeoverReason}:{})},retry:0,timeout:20000}))])[0]!
  store.changed('orders');orders.value=orders.value.map(row=>row.id===o.id?updated:row)
  posEntered.value=false;posPaid.value=false
  if(updated.status==='forwarded'){tab.value='history';filterStatus.value='';offset.value=0}
  else{filterStatus.value='';offset.value=0}
  await load()
 }catch{error.value='Konfirmasi belum pasti atau pesanan sedang ditangani kasir lain. Muat ulang dan periksa aplikasi kasir; jangan input atau meminta pembayaran ulang.';await load()}finally{busy.value=false}
}
async function reorder(o:Order){
 if(busy.value)return;busy.value=true;error.value=''
 try{
 if(sessionStorage.getItem('tkm-cashier-checkout')){error.value='Selesaikan percobaan pesanan ulang sebelumnya dahulu.';return}
 if(draft.value&&!confirm('Ganti draft pesanan ulang? Perubahan draft saat ini akan dibuang.'))return
 const [payload,catalog]=await Promise.all([$fetch<CreateOrderPayload>(`/api/core/orders/${o.id}/reorder`,{headers:await headers(),retry:0,timeout:15000}),store.cache.fetch('cashier-menu',async signal=>normalizeMenu(await $fetch('/api/core/menu',{signal,retry:0,timeout:15000})),{staleTime:60000})])
 menu.value=catalog;draft.value=payload;draftIdentity.value++;editing.value=null
 }catch{error.value='Tidak dapat menyiapkan pesanan ulang.'}finally{busy.value=false}
}
async function createAgain(items:CreateOrderPayload['items']){
 if(!draft.value||busy.value)return
 if(sessionStorage.getItem('tkm-cashier-checkout')){error.value='Masih ada pengiriman belum pasti. Gunakan Coba ulang pengiriman.';return}
 if(prepareReorder({...draft.value,items},menu.value?.products??[]).errors.length)return
 if(!confirm('Buat nomor order baru? Order lama tetap expired, pembayaran belum diterima.'))return
 const payload={...draft.value,items}
 const attempt={payload,key:crypto.randomUUID(),token:crypto.randomUUID()+crypto.randomUUID()}
 sessionStorage.setItem('tkm-cashier-checkout',JSON.stringify(attempt))
 pendingAttempt.value=true
 await sendAttempt()
}
async function sendAttempt(){
 if(busy.value)return;busy.value=true;error.value=''
 try{
 const attempt=JSON.parse(sessionStorage.getItem('tkm-cashier-checkout')??'null');if(!attempt)return
 const result=await $fetch<Order>('/api/core/orders',{method:'POST',body:attempt.payload,headers:{'Idempotency-Key':attempt.key,'X-Order-Token':attempt.token}})
 sessionStorage.removeItem('tkm-cashier-checkout');pendingAttempt.value=false;draft.value=null;tab.value='active';filterStatus.value='';search.value='';querySearch.value='';offset.value=0;selectedId.value=result.id;await load();await nextTick();editing.value=JSON.parse(JSON.stringify(result))
 }catch(e){
 if(isCheckoutRejected(e)){
 sessionStorage.removeItem('tkm-cashier-checkout')
 pendingAttempt.value=false
 error.value='Pesanan ulang ditolak dan tidak dibuat. Perbaiki draft atau pilih pesanan ulang lagi.'
 }else{error.value='Pesanan ulang belum pasti. Gunakan Coba ulang pengiriman; jangan membuat percobaan baru.'}
 }finally{busy.value=false}
}
async function changeTab(value:'active'|'history'){if(controlsLocked.value)return;filterStatus.value='';tab.value=value;offset.value=0;error.value=''}
function resetFilters(){search.value='';querySearch.value='';filterStatus.value='';sortOrder.value='newest';offset.value=0}
let clock:ReturnType<typeof setInterval>|undefined
let authSubscription:{unsubscribe:()=>void}|undefined
function clearSession(){generation++;realtime?.dispose();realtime=undefined;clearTimeout(searchTimer);loggedIn.value=false;account.value=null;orders.value=[];menu.value=null;listing.value=false;editing.value=null;draft.value=null;selectedId.value='';selectionInitialized=false;selectionMissing.value=false;for(const id of Object.keys(posReference))delete posReference[id];posEntered.value=false;posPaid.value=false}
watch(store.revision,()=>{if(loggedIn.value&&!store.cache.scope)clearSession()})
onMounted(async()=>{
 applyRouteFilters()
 clock=setInterval(()=>now.value=Date.now(),1000)
 pendingAttempt.value=!!sessionStorage.getItem('tkm-cashier-checkout')
 authSubscription=client.auth.onAuthStateChange?.((event:AuthChangeEvent,session:Session|null)=>{
  if(event==='SIGNED_OUT')clearSession()
  else if(event==='SIGNED_IN'&&account.value&&session?.user.id!==account.value.id){clearSession();queueMicrotask(()=>{if(!disposed)void load()})}
  else if(event==='TOKEN_REFRESHED')realtime?.reconnect()
 })?.data.subscription
 const seq=generation,{data}=await client.auth.getSession()
 if(disposed||seq!==generation)return
 if(data.session)await load()
})
onUnmounted(()=>{disposed=true;generation++;realtime?.dispose();authSubscription?.unsubscribe();clearInterval(clock);clearTimeout(searchTimer)})
async function logout(){if(busy.value)return;busy.value=true;clearSession();try{const recorded=await useStaffAuth().logout();error.value=recorded?'':'Sesi perangkat ditutup. Catatan keluar belum terkonfirmasi; periksa koneksi sebelum login kembali.'}catch{error.value='Keluar belum terkonfirmasi. Periksa koneksi dan coba lagi.'}finally{busy.value=false}}
async function refreshAccount(){
 const seq=generation
 try{const identity=normalizeProfile(await $fetch<Profile>('/api/core/admin/me',{headers:await headers(),retry:0,timeout:15000}));if(disposed||seq!==generation)return;store.bind(identity);account.value=identity;await load()}catch(e){if(isAccessError(e)){store.cache.bind('');clearSession()}if(seq===generation)error.value='Akun kasir tidak dapat diperbarui. Periksa koneksi atau login kembali.'}
}
const editorPane=ref<HTMLElement|null>(null)
watch([editing,draft],async()=>{if(editing.value||draft.value){await nextTick();editorPane.value?.scrollIntoView?.({behavior:'smooth',block:'start'})}})
const pendingCount=computed(()=>orders.value.filter(o=>o.status==='pending').length)
const reviewedCount=computed(()=>orders.value.filter(o=>canAcceptCash(o,now.value)).length)
const processingCount=computed(()=>orders.value.filter(o=>o.status==='pos_input').length)
const controlsLocked=computed(()=>busy.value||!!editing.value||!!draft.value)
const cashierLinks=computed(()=>[
 {id:'active',label:'Pesanan Aktif',icon:'orders',active:tab.value==='active',group:'Pelayanan'},
 {id:'history',label:'Riwayat',icon:'history',active:tab.value==='history',group:'Pelayanan'},
 {id:'priority',label:'Prioritas pelanggan',icon:'clock',group:'Pelayanan'},
 ...(['superadmin','admin'].includes(account.value?.role||'')?[{id:'admin',label:'Administrasi',icon:'dashboard',to:'/admin',group:'Manajemen'}]:[]),
])
function focusStatus(status:string){if(controlsLocked.value)return;search.value='';querySearch.value='';tab.value='active';filterStatus.value=status;offset.value=0}
function sidebarSelect(id:string){if(controlsLocked.value)return;if(id==='priority'){focusStatus('pending');sortOrder.value='oldest'}else if(id==='active'||id==='history')void changeTab(id)}
function applyRouteFilters(){
 if(controlsLocked.value)return
 const q=route.query
 tab.value=q.tab==='history'?'history':'active'
 const allowed=tab.value==='active'?['pending','ready','pos_input','confirmed']:['forwarded','completed','expired','cancelled']
 filterStatus.value=typeof q.status==='string'&&allowed.includes(q.status)?q.status:''
 sortOrder.value=q.sort==='oldest'?'oldest':'newest'
 search.value=typeof q.q==='string'?q.q.slice(0,80):'';querySearch.value=search.value.trim()
 if(typeof q.order==='string'&&/^[a-f0-9-]{36}$/i.test(q.order)){selectedId.value=q.order;selectionInitialized=true}
}
watch(()=>route.query,applyRouteFilters)
const selectedOrder=computed(()=>orders.value.find(o=>o.id===selectedId.value)??null)
watch(()=>selectedOrder.value?.version,()=>{posEntered.value=false;posPaid.value=false})
const statusOptions=computed(()=>tab.value==='active'?[{value:'',label:'Semua'},{value:'pending',label:'Menunggu kasir'},{value:'ready',label:'Siap ditangani'},{value:'pos_input',label:'Input ke aplikasi kasir'}]:[{value:'',label:'Semua'},{value:'forwarded',label:'Masuk aplikasi kasir'},{value:'completed',label:'Transaksi web lama'},{value:'expired',label:'Kedaluwarsa'},{value:'cancelled',label:'Dibatalkan'}])
const hasFilters=computed(()=>!!search.value.trim()||!!filterStatus.value||sortOrder.value!=='newest')
function itemCount(o:Order){return (o.order_items??[]).reduce((sum,i)=>sum+i.quantity,0)}
function paymentLabel(o:Order){return o.status==='forwarded'?'Konfirmasi POS tercatat':o.status==='pos_input'?'Ditangani '+(o.pos_handoff?.cashier_name||'kasir'):o.payment_status==='paid'?'Pembayaran web lama':'Bayar melalui aplikasi kasir'}

</script>
<template>
 <main class="cashier-ui">
  <CashierLogin v-if="!loggedIn" :message="error" :busy="busy" @authenticated="authenticated" />
  <div v-else class="tkm-dashboard cashier-shell" :data-dashboard-theme="dashboardTheme" :data-sidebar-collapsed="sidebarCollapsed">
   <UiSidebar :links="cashierLinks" :collapsed="sidebarCollapsed" :theme="dashboardTheme" :name="account?.full_name || ''" :role="account?.role==='superadmin'?'Superadmin':account?.role==='admin'?'Admin':'Kasir'" :disabled="controlsLocked" label="Navigasi kasir" @toggle="toggleCollapsed" @theme="toggleTheme" @logout="logout" @select="sidebarSelect" />
   <div class="cashier-dashboard">
   <header class="cashier-topbar">
    <div class="cashier-heading">
     <h1>Dashboard Kasir</h1>
     <p class="cashier-account">Kasir: <strong>{{ account?.full_name || 'Nama belum diisi' }}</strong></p>
    </div>
    <div class="cashier-top-actions">
     <span class="cashier-connection" role="status"><i :class="{ online: realtimeStatus==='connected' }"></i>{{ realtimeLabel }}</span>
     <button class="cashier-button cashier-secondary" :disabled="busy" @click="refreshAccount"><Icon name="refresh" />Muat ulang</button>
    </div>
   </header>
   <p v-if="error" role="alert" class="cashier-alert">{{ error }}</p>
   <DashboardDataStatus :updated-at="snapshotAt" :loading="listing" :error="error" />
   <p v-if="!hasStaffName" class="cashier-alert">Nama akun kasir belum diisi. Minta admin melengkapi nama akun, lalu tekan Muat ulang. Penanganan pesanan belum dapat digunakan.</p>
   <p v-if="selectionMissing" class="cashier-alert" role="status">Pesanan terpilih tidak ada pada daftar ini. Pesanan mungkin sudah ditangani kasir lain atau tidak cocok dengan filter. Pilih pesanan untuk melanjutkan.</p>
   <section v-if="tab==='active'" class="cashier-summary" aria-label="Ringkasan hasil pesanan pada halaman ini"><button type="button" :disabled="controlsLocked" aria-label="Tampilkan pesanan menunggu kasir" @click="focusStatus('pending')"><UiDashboardIcon name="clock"/><span>Menunggu kasir</span><strong>{{ pendingCount }}</strong></button><button type="button" :disabled="controlsLocked" aria-label="Tampilkan pesanan siap ditangani" @click="focusStatus('ready')"><UiDashboardIcon name="cash"/><span>Siap ditangani</span><strong>{{ reviewedCount }}</strong></button><button type="button" :disabled="controlsLocked" aria-label="Tampilkan pesanan ditangani kasir" @click="focusStatus('pos_input')"><UiDashboardIcon name="utensils"/><span>Input ke aplikasi kasir</span><strong>{{ processingCount }}</strong></button></section>
   <div class="cashier-controls">
   <div class="cashier-toolbar"><div class="cashier-tabs"><button :disabled="controlsLocked" :aria-pressed="tab==='active'" @click="changeTab('active')">Pesanan Aktif</button><button :disabled="controlsLocked" :aria-pressed="tab==='history'" @click="changeTab('history')">Riwayat</button></div></div>
   <section class="cashier-search-tools" aria-label="Cari dan filter pesanan">
    <div class="cashier-search"><Icon name="search" :size="22"/><input v-model="search" type="search" aria-label="Cari pesanan" maxlength="80" placeholder="Cari nomor, pelanggan, atau menu" :disabled="controlsLocked"><button v-if="search" type="button" aria-label="Hapus pencarian" :disabled="controlsLocked" @click="search='';querySearch=''">×</button></div>
    <label class="cashier-sort">Urutkan<select v-model="sortOrder" aria-label="Urutkan pesanan" :disabled="controlsLocked"><option value="newest">Terbaru</option><option value="oldest">Terlama</option></select></label>
   </section>
   </div>
   <div class="cashier-filter-row"><div class="cashier-status-filters" aria-label="Status pesanan"><button v-for="option in statusOptions" :key="option.value" :aria-pressed="filterStatus===option.value" :disabled="controlsLocked" @click="filterStatus=option.value">{{ option.label }}</button></div><button v-if="hasFilters" class="cashier-reset" :disabled="controlsLocked" @click="resetFilters">Reset filter</button></div>
   <p v-if="pendingAttempt" class="cashier-recovery">Ada pengiriman pesanan yang belum pasti.<button class="cashier-button cashier-secondary" :disabled="busy" @click="sendAttempt">Coba ulang pengiriman</button></p>
   <div class="cashier-workspace">
    <aside class="cashier-queue" aria-label="Daftar pesanan"><div class="cashier-queue-heading"><h2>{{ tab==='active' ? 'Pesanan Aktif' : 'Riwayat' }}</h2><span>{{ orders.length }} pesanan</span></div><p class="cashier-queue-caption">{{ hasFilters ? 'Hasil pencarian / filter' : 'Pilih pesanan untuk melihat detail' }}</p>
     <div class="cashier-queue-list"><p v-if="listing&&!orders.length" class="cashier-queue-empty" role="status">Memuat pesanan…</p><p v-else-if="!orders.length" class="cashier-queue-empty">{{ hasFilters ? 'Tidak ada pesanan yang cocok. Coba kata lain atau reset filter.' : 'Belum ada pesanan pada daftar ini.' }}</p>
      <button v-for="o in orders" :key="o.id" class="cashier-queue-card" :class="{ selected: selectedOrder?.id===o.id, urgent: o.status==='pending'&&remainingSeconds(o.expires_at,now)<=180 }" :aria-pressed="selectedOrder?.id===o.id" :aria-label="'Lihat pesanan '+o.order_number" :disabled="controlsLocked" @click="selectOrder(o.id)"><div><strong>{{ o.order_number }}</strong><b>{{ fmtIDR(o.total) }}</b></div><p>{{ o.customer_name || 'Pelanggan' }} · {{ itemCount(o) }} item</p><div class="cashier-queue-meta"><span class="cashier-status" :class="'cashier-status-'+o.status">{{ STATUS_LABEL[o.status]??o.status }}</span><span v-if="o.status==='pending'" class="cashier-queue-clock"><Icon name="clock" :size="15" />{{ formatCountdown(remainingSeconds(o.expires_at,now)) }}</span><span v-else class="cashier-payment-status" :class="{paid:o.payment_status==='paid'}">{{ paymentLabel(o) }}</span></div></button>
     </div>
     <nav class="cashier-pagination" aria-label="Halaman pesanan"><button :disabled="controlsLocked||listing||offset===0" @click="offset=Math.max(0,offset-100)" aria-label="Halaman sebelumnya"><Icon name="chevron-left" /></button><span>Hal. {{ Math.floor(offset/100)+1 }}</span><button :disabled="controlsLocked||listing||orders.length<100" @click="offset+=100" aria-label="Halaman berikutnya"><Icon name="chevron-right" /></button></nav>
    </aside>
    <div ref="detailPane" class="cashier-detail" aria-label="Detail pesanan terpilih">
   <section v-if="draft&&menu" ref="editorPane" class="cashier-editor"><h2>Pesan ulang</h2><p>Nomor dan batas waktu baru. Pesanan lama tetap tersimpan.</p><OrderEditor :key="draftIdentity" :products="menu.products" :initial="draft.items" :disabled="busy" @save="createAgain"/><button class="cashier-button cashier-secondary" :disabled="busy" @click="draft=null">Tutup draft</button></section>
   <section v-if="editing&&menu" ref="editorPane" class="cashier-editor"><h2>Periksa pesanan {{ editing.order_number }}</h2><p>Periksa menu dengan pelanggan. Nilai akhir dan pembayaran diproses di aplikasi kasir mereka.</p><OrderEditor :key="editing.id+':'+editing.version" :products="menu.products" :initial="initial(editing)" :disabled="busy" @save="review"/><button class="cashier-button cashier-secondary" :disabled="busy" @click="editing=null">Tutup revisi</button></section>
   <div v-if="!editing&&!draft" class="cashier-order-grid">
    <article v-for="o in selectedOrder ? [selectedOrder] : []" :key="o.id" class="cashier-order" :class="{ 'cashier-order-urgent': o.status==='pending'&&remainingSeconds(o.expires_at,now)<=180 }">
     <header class="cashier-order-header"><div><span class="cashier-eyebrow">NOMOR PESANAN</span><h2>{{ o.order_number }}</h2><p>{{ o.customer_name || 'Pelanggan' }} · {{ itemCount(o) }} item</p><p v-if="o.cashier" class="cashier-approved-by">Konfirmasi oleh <strong>{{ o.cashier.full_name || 'Kasir (nama belum tercatat)' }}</strong></p></div><div class="cashier-statuses"><span class="cashier-status" :class="'cashier-status-'+o.status">{{ STATUS_LABEL[o.status]??o.status }}</span><span class="cashier-payment-status" :class="{ paid: o.payment_status==='paid' }">{{ paymentLabel(o) }}</span></div></header>
     <div v-if="o.status==='pending'" class="cashier-deadline"><span><Icon name="clock" :size="20" />{{ remainingSeconds(o.expires_at,now)>0 ? 'Batas konfirmasi ke kasir' : 'Menunggu status kedaluwarsa' }}</span><strong>{{ formatCountdown(remainingSeconds(o.expires_at,now)) }}</strong></div>
     <div class="cashier-order-body"><section class="cashier-items"><h3>Detail Pesanan</h3><ul><li v-for="i in o.order_items" :key="i.id"><strong class="cashier-item-quantity">{{ i.quantity }}×</strong><div><h4>{{ i.product_name }}</h4><p v-if="i.variant_name">{{ i.variant_name }}</p><p v-for="a in i.order_item_addons" :key="a.addon_name">+ {{ a.addon_name }}</p><p v-if="i.notes" class="cashier-item-note">Catatan: {{ i.notes }}</p></div><strong>{{ fmtIDR(i.subtotal) }}</strong></li></ul></section>
      <section class="cashier-payment"><p class="cashier-muted">Estimasi nilai pesanan</p><strong class="cashier-order-total">{{ fmtIDR(o.total) }}</strong>
       <template v-if="o.status==='pending'">
        <p class="cashier-next-step">Cocokkan nomor dan menu dengan pelanggan. Tangani pesanan sebelum input manual ke aplikasi kasir.</p>
        <button class="cashier-button cashier-secondary" :disabled="busy||remainingSeconds(o.expires_at,now)===0" @click="edit(o)"><Icon name="pencil" />Cek menu / revisi</button>
        <button v-if="canAcceptCash(o,now)" class="cashier-button cashier-primary" :disabled="busy||!hasStaffName" @click="posAction(o,'claim-pos')">Tangani pesanan ini</button>
        <small>Batas waktu berhenti setelah kasir menangani pesanan. Periksa POS sebelum menginput agar tidak ganda.</small>
       </template>
       <template v-else-if="o.status==='pos_input'">
        <p v-if="o.pos_handoff&&now-Date.parse(o.pos_handoff.claimed_at)>10*60*1000" class="ops-alert" role="status">Pesanan ini sudah ditangani lebih dari 10 menit. Periksa transaksi di aplikasi kasir sebelum melanjutkan atau meminta admin mengambil alih.</p>
        <p class="cashier-next-step">Ditangani <strong>{{ o.pos_handoff?.cashier_name }}</strong>. Masukkan menu ke aplikasi kasir, selesaikan pembayaran di sana, lalu pelanggan mengambil nomor meja.</p>
        <template v-if="o.pos_handoff?.cashier_id===account?.id">
         <label :for="'pos-ref-'+o.id">Nomor transaksi aplikasi kasir (opsional)</label><input :id="'pos-ref-'+o.id" v-model="posReference[o.id]" class="ops-input" maxlength="80" placeholder="Nomor struk / transaksi POS" :disabled="busy">
         <label class="cashier-pos-check"><input v-model="posEntered" type="checkbox" :disabled="busy">Semua menu sudah dimasukkan ke aplikasi kasir</label>
         <label class="cashier-pos-check"><input v-model="posPaid" type="checkbox" :disabled="busy">Pembayaran pelanggan sudah selesai di aplikasi kasir</label>
         <button class="cashier-button cashier-primary" :disabled="busy||!posEntered||!posPaid" @click="posAction(o,'forward-pos')">Sudah masuk aplikasi kasir</button>
        </template>
        <template v-else><p class="cashier-next-step">Jangan input ulang. Hubungi kasir yang menangani pesanan ini.</p><button v-if="account?.role==='superadmin'||account?.role==='admin'" class="cashier-button cashier-secondary" :disabled="busy" @click="posAction(o,'claim-pos',true)">Ambil alih setelah periksa POS</button></template>
       </template>
       <template v-else-if="o.status==='forwarded'"><p class="cashier-next-step">Konfirmasi manual masuk aplikasi kasir oleh <strong>{{ o.pos_handoff?.cashier_name }}</strong>. Struk resmi dan pelayanan berikutnya melalui aplikasi kasir.</p><p v-if="o.pos_handoff?.pos_reference">Referensi POS: {{ o.pos_handoff.pos_reference }}</p></template>
       <template v-else-if="o.status==='expired'"><p class="cashier-next-step">Batas konfirmasi ke kasir habis. Periksa POS dahulu sebelum membuat nomor pesanan baru.</p><button class="cashier-button cashier-secondary" :disabled="busy" @click="reorder(o)">Buat ulang pesanan</button></template>
       <p v-else class="cashier-next-step">{{ o.payment_status==='paid' ? 'Riwayat transaksi web lama dipertahankan. Bukan konfirmasi input POS.' : 'Pesanan tidak memerlukan tindakan.' }}</p>
       <NuxtLink v-if="o.payment_status==='paid'" :to="`/receipt/${o.id}`" class="cashier-button cashier-secondary" @pointerenter="prefetchReceipt(o.id)" @focus="prefetchReceipt(o.id)">Lihat struk web lama</NuxtLink>
      </section>
     </div>
    </article>
   </div>
   <div v-if="!selectedOrder&&!editing&&!draft" class="cashier-empty"><Icon name="bag" :size="40" /><h2>{{ listing ? 'Memuat pesanan…' : orders.length ? 'Pilih pesanan' : hasFilters ? 'Pesanan tidak ditemukan' : 'Belum ada pesanan' }}</h2><p>{{ orders.length ? 'Pilih nomor pesanan dari daftar untuk melihat detail dan langkah input ke aplikasi kasir.' : hasFilters ? 'Ubah pencarian atau filter untuk menemukan pesanan.' : 'Pesanan baru muncul otomatis setelah pelanggan checkout.' }}</p><button v-if="hasFilters" class="cashier-button cashier-secondary" :disabled="controlsLocked" @click="resetFilters">Reset filter</button></div>
    </div>
   </div>
   </div>
  </div>
 </main>
</template>
