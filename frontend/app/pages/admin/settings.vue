<script setup lang="ts">
import type { Settings } from '#shared/types'
import { money, priceExample, wibTime } from '#shared/operations'
import { normalizeSettings,normalizeBackup } from '#shared/dashboard-data'
const store=useDashboardCache()
const settingsQuery=useDashboardQuery(()=>({key:'settings',url:'/api/admin/crud/settings',staleTime:60000,normalize:(v:unknown)=>{if(!Array.isArray(v)||!v.length)throw Object.assign(new Error('Pengaturan tidak lengkap'),{invalidData:true});return normalizeSettings(v[0])}}))
const backupQuery=useDashboardQuery(()=>({key:'backup',url:'/api/admin/backup-status',staleTime:60000,normalize:normalizeBackup}))
const form = ref<Settings | null>(null),
  busy = ref(false),
  error = ref(''),
  message = ref(''),
  approved = ref(false)
interface BackupStatus {
  last_attempt?: string
  last_success?: string
  result?: string
  restore_verified_at?: string
}
const backup=backupQuery.data
const cleaning=ref(false),cleanupMessage=ref('')
async function cleanupMedia(){
 if(cleaning.value)return;cleaning.value=true;cleanupMessage.value=''
 try{const result=await $fetch<{cleaned:number;failed:number}>('/api/admin/media-cleanup',{method:'POST',retry:0,timeout:25000});cleanupMessage.value=`${result.cleaned} foto tak terpakai dibersihkan.${result.failed?' Sebagian belum berhasil; coba lagi.':' Maksimal 20 per proses.'}`}
 catch(e:any){cleanupMessage.value=e.data?.statusMessage||'Pembersihan belum selesai. Coba kembali.'}
 finally{cleaning.value=false}
}
watch(settingsQuery.data,(value,previous)=>{
  if(value&&(!form.value||JSON.stringify(form.value)===JSON.stringify(previous)))form.value=structuredClone(value)
},{immediate:true})
const preview = computed(() =>
  priceExample(
    100000,
    Number(form.value?.tax_pct) || 0,
    Number(form.value?.service_pct) || 0,
  ),
)
watch(
  () => [
    form.value?.tax_pct,
    form.value?.service_pct,
    form.value?.orders_enabled,
    form.value?.require_customer_name,
  ],
  () => (approved.value = false),
)
async function save() {
  if (!form.value || busy.value || !approved.value) return
  busy.value = true
  error.value = ''
  message.value = ''
  try {
    const saved = await store.mutation(()=>$fetch<Settings>('/api/admin/settings', {
      method: 'PUT',
      body: {
        brand_name: form.value!.brand_name, tagline: form.value!.tagline || '',
        tax_pct: Number(form.value!.tax_pct), service_pct: Number(form.value!.service_pct),
        require_customer_name: form.value!.require_customer_name, orders_enabled: !!form.value!.orders_enabled,
      }, retry:0, timeout:20000,
    }))
    form.value=normalizeSettings(saved)
    store.changed('settings');store.cache.set('settings',structuredClone(saved))
    message.value = 'Tarif dan status penerimaan pesanan tersimpan.'
    approved.value = false
  } catch (e: unknown) {
    error.value =
      (e as { data?: { statusMessage?: string } }).data?.statusMessage ||
      'Pengaturan belum berhasil. Periksa tarif (0–100%) dan akun kasir personal, lalu coba lagi.'
  } finally {
    busy.value = false
  }
}
</script>
<template>
  <div>
    <DashboardDataStatus :updated-at="settingsQuery.updatedAt.value" :loading="settingsQuery.loading.value" :error="settingsQuery.error.value" />
    <header class="ops-heading">
      <div>
        <p class="ops-eyebrow">Superadmin</p>
        <h1>Pengaturan operasional</h1>
        <p>Konfirmasi tarif sebelum menerima pesanan pelanggan.</p>
      </div>
    </header>
    <p v-if="error" class="ops-alert" role="alert">{{ error }}</p>
    <p v-if="settingsQuery.error.value" class="ops-alert" role="alert">{{ settingsQuery.error.value }} <button @click="settingsQuery.refresh()">Coba lagi</button></p>
    <p v-if="backupQuery.error.value" class="ops-alert" role="alert">Statistik backup belum dapat diperbarui. {{ backupQuery.error.value }} <button @click="backupQuery.refresh()">Coba lagi</button></p>
    <p v-if="message" class="ops-success" role="status">{{ message }}</p>
    <form v-if="form" class="ops-card ops-form" @submit.prevent="save">
      <h2>Restoran & tarif</h2>
      <div class="ops-form-row">
        <label
          >Nama restoran<input
            v-model="form.brand_name"
            class="ops-input"
            required
            maxlength="50" /></label
        ><label
          >Tagline<input
            v-model="form.tagline"
            class="ops-input"
            maxlength="100"
        /></label>
      </div>
      <div class="ops-form-row">
        <label
          >Service (%)<input
            v-model.number="form.service_pct"
            class="ops-input"
            type="number"
            min="0"
            max="100"
            step="0.01"
            required /></label
        ><label
          >Pajak (%)<input
            v-model.number="form.tax_pct"
            class="ops-input"
            type="number"
            min="0"
            max="100"
            step="0.01"
            required
        /></label>
      </div>
      <section class="ops-inset">
        <h3>Contoh subtotal {{ money(preview.subtotal) }}</h3>
        <dl class="ops-lines">
          <div>
            <dt>Service</dt>
            <dd>{{ money(preview.service) }}</dd>
          </div>
          <div>
            <dt>Pajak</dt>
            <dd>{{ money(preview.tax) }}</dd>
          </div>
          <div>
            <dt>Total pelanggan</dt>
            <dd>
              <strong>{{ money(preview.total) }}</strong>
            </dd>
          </div>
        </dl>
        <p>
          Keduanya dihitung dari subtotal produk. Pesanan yang sudah dibayar
          tidak berubah.
        </p>
      </section>
      <label class="ops-check"
        ><input v-model="form.require_customer_name" type="checkbox" />Nama
        pelanggan wajib diisi</label
      ><label class="ops-check"
        ><input v-model="form.orders_enabled" type="checkbox" />Terima pesanan
        baru</label
      ><label class="ops-check"
        ><input v-model="approved" type="checkbox" required />Saya sudah
        memeriksa contoh total dan menyetujui tarif serta status operasional
        ini.</label
      >
      <p v-if="form.pricing_confirmed_at">
        Konfirmasi terakhir: {{ wibTime(form.pricing_confirmed_at) }}
      </p>
      <button class="ops-button" :disabled="busy || !approved">
        {{ busy ? 'Menyimpan…' : 'Konfirmasi & simpan' }}
      </button>
    </form>
    <section class="ops-card ops-form"><h2>Foto tak terpakai</h2><p>Foto unggahan yang tidak dirujuk menu atau staf selama minimal 24 jam dibersihkan bertahap. Foto yang masih digunakan tetap disimpan. Pembersihan juga berjalan saat ada unggahan baru.</p><button class="ops-button secondary" :disabled="cleaning" @click="cleanupMedia">{{ cleaning?'Membersihkan…':'Bersihkan foto tak terpakai' }}</button><p v-if="cleanupMessage" role="status">{{ cleanupMessage }}</p></section>
    <section class="ops-card">
      <h2>Backup & pemulihan</h2>
      <dl class="ops-lines">
        <div>
          <dt>Status terakhir</dt>
          <dd>{{ backup?.result || 'Belum dikonfigurasi' }}</dd>
        </div>
        <div>
          <dt>Backup berhasil</dt>
          <dd>
            {{
              backup?.last_success
                ? wibTime(backup.last_success)
                : 'Belum ada bukti'
            }}
          </dd>
        </div>
        <div v-if="backup?.last_attempt">
          <dt>Percobaan terakhir</dt>
          <dd>{{ wibTime(backup.last_attempt) }}</dd>
        </div>
        <div>
          <dt>Uji pemulihan</dt>
          <dd>
            {{
              backup?.restore_verified_at
                ? wibTime(backup.restore_verified_at)
                : 'Belum diverifikasi'
            }}
          </dd>
        </div>
      </dl>
      <p>
        Target kebijakan: backup harian 03.00 WIB, database dan media terpisah, retensi 30 hari. Jadwal aktif harus diverifikasi dari worker; teks ini bukan bukti backup berjalan.
      </p>
    </section>
  </div>
</template>
