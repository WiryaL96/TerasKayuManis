<script setup lang="ts">
import {money,wibTime,wibToday} from '#shared/operations'
import {normalizeReport,normalizeStaff,reportCSV,posReportCSV,summarizeHandoffs,reportForCashier} from '#shared/dashboard-data'
import type {ReportData} from '#shared/operations'
definePageMeta({layout:'admin',middleware:'admin'})
const route=useRoute(),from=ref(typeof route.query.from==='string'?route.query.from:wibToday()),to=ref(typeof route.query.to==='string'?route.query.to:wibToday()),cashier=ref(typeof route.query.cashier==='string'?route.query.cashier:'')
const mode=ref<'pos'|'legacy'>('pos'),page=ref(0),epoch=ref(0);let snapshot=''
const serverMode=ref(false)
const filters=computed(()=>({from:from.value,to:to.value,cashier:serverMode.value?cashier.value:''})),applied=useDebouncedValue(filters)
watch(cashier,()=>page.value=0)
watch(applied,()=>{page.value=0;snapshot='';epoch.value++});watch(mode,()=>page.value=0)
const chunk=computed(()=>Math.floor(page.value/10)*500)
const staffChoices=useDashboardQuery(()=>({key:'staff',url:'/api/admin/staff',staleTime:60000,normalize:normalizeStaff}))
const resource=useDashboardQuery(()=>({key:`report:${JSON.stringify(applied.value)}:${chunk.value}:${epoch.value}`,url:'/api/admin/reports',query:{...applied.value,paged:'1',offset:chunk.value,...(snapshot?{as_of:snapshot}:{})},staleTime:60000,normalize:normalizeReport}))
watch(resource.data,value=>{if(value?.as_of&&!snapshot)snapshot=value.as_of;if(value?.pagination?.handoff_has_more||value?.pagination?.payment_has_more)serverMode.value=true})
const data=computed(()=>resource.data.value?(serverMode.value?resource.data.value:reportForCashier(resource.data.value,cashier.value)):null),summary=computed(()=>summarizeHandoffs(data.value??{})),choices=computed(()=>staffChoices.data.value??[])
const within=computed(()=>page.value%10),handoffs=computed(()=>(data.value?.handoffs??[]).slice(within.value*50,(within.value+1)*50)),payments=computed(()=>data.value?.payments.slice(within.value*50,(within.value+1)*50)??[])
const count=computed(()=>mode.value==='pos'?(data.value?.handoffs?.length??0):(data.value?.payments.length??0))
const more=computed(()=>mode.value==='pos'?data.value?.pagination?.handoff_has_more:data.value?.pagination?.payment_has_more)
const hasNext=computed(()=>(within.value+1)*50<count.value||(within.value===9&&more.value))
const filtersChanged=computed(()=>JSON.stringify(filters.value)!==JSON.stringify(applied.value))
function load(){page.value=0;snapshot='';epoch.value++;if(filtersChanged.value)applied.value={...filters.value};return resource.refresh()}
const exporting=ref(false),exportError=ref('');let exportController:AbortController|undefined
const csv=computed(()=>data.value&&chunk.value===0&&!more.value?'data:text/csv;charset=utf-8,'+encodeURIComponent(mode.value==='pos'?posReportCSV(data.value):reportCSV(data.value)):null)
onUnmounted(()=>exportController?.abort())
async function exportCSV(){
 if(exporting.value)return
 if(csv.value){const a=document.createElement('a');a.href=csv.value;a.download=mode.value==='pos'?'teraskayumanis-self-orders.csv':'teraskayumanis-legacy-payments.csv';a.click();return}
 exporting.value=true;exportError.value='';exportController=new AbortController()
 const selected=mode.value,query={...applied.value,cashier:serverMode.value?applied.value.cashier:cashier.value};let offset=0,asOf=snapshot,first:ReportData|undefined
 const rows:ReportData['payments']=[],handoffRows:NonNullable<ReportData['handoffs']>=[]
 try{
  for(;;){
   const report=normalizeReport(await $fetch('/api/admin/reports',{query:{...query,paged:'1',offset,...(asOf?{as_of:asOf}:{})},signal:exportController.signal,timeout:20000,retry:0}))
   first??=report;asOf=report.as_of??asOf
   rows.push(...report.payments);handoffRows.push(...(report.handoffs??[]))
   if(!(selected==='pos'?report.pagination?.handoff_has_more:report.pagination?.payment_has_more))break
   offset+=500;if(offset>=50000)throw new Error('Ekspor terlalu besar. Persempit rentang tanggal.')
  }
  const ids=(selected==='pos'?handoffRows:rows).map(r=>r.order_id),expected=selected==='pos'?first!.pos_summary!.count:first!.summary.count
  if(new Set(ids).size!==expected||ids.length!==expected)throw new Error('Data berubah saat ekspor. Muat ulang laporan lalu coba lagi.')
  const text=selected==='pos'?posReportCSV({handoffs:handoffRows}):reportCSV({...first!,payments:rows})
  const url=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download=selected==='pos'?'teraskayumanis-self-orders.csv':'teraskayumanis-legacy-payments.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
 }catch(e){exportError.value=(e as Error).message||'Ekspor belum berhasil. Coba lagi.'}finally{exporting.value=false}
}
const prefetchReceipt=useReceiptPrefetch()
</script>
<template>
 <div>
  <DashboardDataStatus :updated-at="resource.updatedAt.value" :loading="resource.loading.value" :error="resource.error.value"/>
  <header class="ops-heading"><div><p class="ops-eyebrow">Monitoring self-order</p><h1>Laporan pesanan</h1><p>Input POS dikonfirmasi manual oleh kasir. Penjualan, pembayaran dan struk resmi tetap mengikuti aplikasi kasir restoran.</p></div><button v-if="data" class="ops-button secondary" :disabled="exporting||filtersChanged||resource.loading.value" @click="exportCSV">{{ exporting?'Menyiapkan CSV…':'Ekspor semua CSV' }}</button></header>
  <div class="ops-actions" role="group" aria-label="Jenis laporan"><button class="ops-button" :aria-pressed="mode==='pos'" @click="mode='pos'">Pesanan self-order</button><button class="ops-button secondary" :aria-pressed="mode==='legacy'" @click="mode='legacy'">Riwayat pembayaran web lama</button></div>
  <form class="ops-card ops-form-row" @submit.prevent="load"><label>Dari tanggal<input v-model="from" class="ops-input" type="date" required></label><label>Sampai tanggal<input v-model="to" class="ops-input" type="date" :min="from" required></label><label>Kasir<select v-model="cashier" class="ops-input"><option value="">Semua kasir</option><option v-for="c in choices" :key="c.id" :value="c.id">{{ c.full_name||c.email }}</option></select></label><button class="ops-button" :disabled="resource.loading.value">{{ resource.loading.value?'Memuat…':'Tampilkan' }}</button></form>
  <p v-if="exportError" role="alert" class="ops-alert">{{ exportError }}</p><p v-if="data?.as_of" class="customer-muted">Data hingga {{ wibTime(data.as_of) }}</p><p v-if="resource.error.value" role="alert" class="ops-alert">{{ resource.error.value }}</p>
  <p v-if="filtersChanged" role="status" class="ops-alert">Memperbarui rentang tanggal. Ekspor mengikuti laporan yang sedang terlihat.</p>
  <p class="ops-report-period">Hasil {{ applied.from }} sampai {{ applied.to }} (WIB) · {{ cashier?choices.find(c=>c.id===cashier)?.full_name||'Kasir terpilih':'Semua kasir' }}</p>
  <template v-if="data">
   <template v-if="mode==='pos'">
    <p class="ops-alert" role="note">Nilai berikut adalah estimasi pesanan dari web, bukan pendapatan POS. Jangan dijumlahkan lagi dengan laporan penjualan aplikasi kasir.</p>
    <div class="ops-metrics"><section class="ops-card"><p>Masuk aplikasi kasir</p><strong>{{ summary.count }}</strong><small>konfirmasi manual</small></section><section class="ops-card"><p>Estimasi nilai pesanan</p><strong>{{ money(summary.total) }}</strong></section></div>
    <section class="ops-card"><h2>Penanganan per kasir</h2><dl class="ops-lines"><div v-for="c in summary.by_cashier" :key="c.id+c.name"><dt>{{ c.name }} · {{ c.count }} pesanan</dt><dd>{{ money(c.total) }}</dd></div></dl><p v-if="!summary.count">Belum ada konfirmasi masuk aplikasi kasir pada rentang ini.</p></section>
    <section class="ops-card ops-table-wrap"><h2>Pesanan diteruskan ke aplikasi kasir</h2><table class="ops-table"><thead><tr><th>Pesanan / waktu WIB</th><th>Kasir</th><th>Referensi POS</th><th>Estimasi nilai</th><th>Detail</th></tr></thead><tbody><tr v-for="h in handoffs" :key="h.order_id"><td><strong>{{ h.order_number }}</strong><small>{{ wibTime(h.forwarded_at) }}</small></td><td>{{ h.cashier_name }}</td><td>{{ h.pos_reference||'Tidak diisi' }}</td><td>{{ money(h.total) }}</td><td><NuxtLink :to="{path:'/cashier',query:{tab:'history',status:'forwarded',q:h.order_number,order:h.order_id}}" class="ops-button secondary">Lihat pesanan</NuxtLink></td></tr></tbody></table></section>
   </template>
   <template v-else>
    <p class="ops-alert">Riwayat pembayaran yang pernah dicatat langsung di web. Dipertahankan untuk audit; bukan hasil sinkronisasi aplikasi kasir. Tanggal berdasarkan waktu pembayaran WIB.</p>
    <div class="ops-metrics"><section class="ops-card"><p>Total pembayaran web lama</p><strong>{{ money(data.summary.revenue) }}</strong><small>{{ data.summary.count }} pembayaran</small></section><section class="ops-card"><p>Uang diterima</p><strong>{{ money(data.summary.received) }}</strong></section><section class="ops-card"><p>Kembalian</p><strong>{{ money(data.summary.change) }}</strong></section></div>
    <section class="ops-card ops-table-wrap"><h2>Rincian pembayaran web lama</h2><table class="ops-table"><thead><tr><th>Pesanan / waktu WIB</th><th>Kasir</th><th>Total</th><th>Struk web lama</th></tr></thead><tbody><tr v-for="p in payments" :key="p.order_id"><td><strong>{{ p.order_number }}</strong><small>{{ wibTime(p.paid_at) }}</small></td><td>{{ p.cashier_name||'Nama kasir belum tercatat' }}</td><td>{{ money(p.total) }}</td><td><NuxtLink :to="`/receipt/${p.order_id}`" @pointerenter="prefetchReceipt(p.order_id)" @focus="prefetchReceipt(p.order_id)" class="ops-button secondary">Lihat struk web lama</NuxtLink></td></tr></tbody></table></section>
   </template>
   <nav class="ops-pagination" aria-label="Halaman laporan"><button class="ops-button secondary" :disabled="page===0" @click="page--">Sebelumnya</button><span>Halaman {{ page+1 }}</span><button class="ops-button secondary" :disabled="!hasNext||resource.loading.value" @click="page++">Berikutnya</button></nav>
  </template>
 </div>
</template>
