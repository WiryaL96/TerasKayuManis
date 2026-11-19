<script setup lang="ts">
import { STAFF_ROLE_LABELS } from '#shared/staff-roles'
import type { StaffRole } from '#shared/staff-roles'
import { AUDIT_ACTIONS } from '#shared/staff-audit'
import type { StaffActivityPage, StaffActivity } from '#shared/staff-audit'
import { wibToday, wibTime, money } from '#shared/operations'
import { normalizeActivity } from '#shared/dashboard-data'

const from=ref(wibToday()),to=ref(wibToday()),actor=ref(''),action=ref(''),offset=ref(0)
const raw=computed(()=>({from:from.value,to:to.value,actor:actor.value,action:action.value})),filters=useDebouncedValue(raw)
const resource=useDashboardQuery(()=>({key:`activity:${filters.value.from}:${filters.value.to}:${filters.value.actor}:${filters.value.action}:${offset.value}`,url:'/api/admin/activity',query:{...filters.value,offset:offset.value},staleTime:30000,normalize:normalizeActivity}))
const result=resource.data,busy=resource.loading,error=resource.error
const staff=ref<StaffActivityPage['staff']>([])
watch(result,value=>{if(value)staff.value=value.staff},{immediate:true})
watch(filters,()=>offset.value=0,{flush:'sync'})
function load(nextOffset=0){
  const changed=JSON.stringify(raw.value)!==JSON.stringify(filters.value)
  if(changed){filters.value={...raw.value};offset.value=nextOffset}
  else if(offset.value!==nextOffset)offset.value=nextOffset
  else return resource.refresh()
  return resource.load()
}
function description(entry: StaffActivity) {
  const d = entry.details, parts: string[] = []
  if (d.area) parts.push(d.area === 'cashier' ? 'Area kasir' : 'Area admin')
  if (entry.target_name) parts.push(`Staf: ${entry.target_name}`)
  if (d.before_full_name && d.after_full_name) parts.push(`${d.before_full_name} → ${d.after_full_name}`)
  if (d.total !== undefined) parts.push(`Total ${money(String(d.total))}`)
  if (d.received !== undefined) parts.push(`Tunai ${money(String(d.received))}`, `Kembalian ${money(String(d.change ?? 0))}`)
  if (d.tax !== undefined) parts.push(`Pajak ${d.tax}%`, `Service ${d.service}%`, d.orders_enabled ? 'Pesanan dibuka' : 'Pesanan dijeda')
  return parts.join(' · ') || 'Perubahan akses staf tercatat.'
}
const labels: Record<string, string> = AUDIT_ACTIONS
</script>
<template>
  <div>
    <DashboardDataStatus :updated-at="resource.updatedAt.value" :loading="busy" :error="error" />
    <header class="ops-heading"><div><p class="ops-eyebrow">Superadmin</p><h1>Log aktivitas</h1><p>Telusuri akses akun, pembayaran, dan pekerjaan staf. Semua waktu dalam WIB.</p></div><button class="ops-button secondary" :disabled="busy" @click="load(0)">Muat ulang</button></header>
    <form class="ops-card ops-form" @submit.prevent="load(0)">
      <div class="ops-form-row">
        <label>Dari tanggal<input v-model="from" class="ops-input" type="date" required :disabled="busy"></label>
        <label>Sampai tanggal<input v-model="to" class="ops-input" type="date" :min="from" required :disabled="busy"></label>
        <label>Staf<select v-model="actor" class="ops-input" :disabled="busy"><option value="">Semua staf</option><option v-for="person in staff" :key="person.id" :value="person.id">{{ person.full_name || 'Nama belum tercatat' }} ({{ STAFF_ROLE_LABELS[person.role as StaffRole] || 'Peran lama' }})</option></select></label>
        <label>Aktivitas<select v-model="action" class="ops-input" :disabled="busy"><option value="">Semua aktivitas</option><option v-for="(label, key) in AUDIT_ACTIONS" :key="key" :value="key">{{ label }}</option></select></label>
        <button class="ops-button" :disabled="busy">Terapkan filter</button>
      </div><p>Maksimal 31 hari per pencarian. Nama disimpan saat aktivitas terjadi; catatan lama dapat belum memiliki nama.</p>
    </form>
    <p v-if="error" class="ops-alert" role="alert">{{ error }}</p>
    <section class="ops-card ops-table-wrap" :aria-busy="busy" aria-label="Riwayat aktivitas staf">
      <p v-if="busy&&!result" role="status">Memuat aktivitas…</p>
      <template v-else-if="result">
        <h2>{{ result.total }} aktivitas ditemukan</h2>
        <table class="ops-table ops-activity-table"><thead><tr><th>Waktu (WIB)</th><th>Pelaku</th><th>Aktivitas</th><th>Rincian</th></tr></thead><tbody>
          <tr v-for="entry in result.entries" :key="entry.id"><td>{{ wibTime(entry.created_at) }}</td><td><strong>{{ entry.actor_name || 'Nama belum tercatat' }}</strong><small>{{ STAFF_ROLE_LABELS[entry.actor_role as StaffRole] || 'Peran historis' }}</small></td><td><span class="ops-badge" :class="{ active: entry.action === 'cash_payment_confirmed' }">{{ labels[entry.action] || 'Aktivitas staf' }}</span><small v-if="entry.details.order_number">Pesanan {{ entry.details.order_number }}</small></td><td>{{ description(entry) }}</td></tr>
          <tr v-if="!result.entries.length"><td colspan="4">Tidak ada aktivitas pada filter ini. Coba ubah tanggal, staf, atau jenis aktivitas.</td></tr>
        </tbody></table>
        <div class="ops-actions ops-activity-pagination"><button class="ops-button secondary" :disabled="!offset" @click="load(Math.max(0, offset - result.limit))">Sebelumnya</button><span role="status">{{ result.total ? offset + 1 : 0 }}–{{ offset + result.entries.length }} dari {{ result.total }}</span><button class="ops-button secondary" :disabled="offset + result.entries.length >= result.total" @click="load(offset + result.limit)">Berikutnya</button></div>
      </template>
    </section>
    <p class="ops-activity-note">Log masuk mencatat login melalui aplikasi. Permintaan keluar dicatat sebelum sesi dihapus di perangkat; menutup tab bukan logout. Pembayaran dan penyelesaian tercatat otomatis dari transaksi.</p>
  </div>
</template>
