<script setup lang="ts">
import { wibTime } from '#shared/operations'
import type { DashboardRange } from '#shared/dashboard'
import { STAFF_ROLE_LABELS } from '#shared/staff-roles'
const { me } = useAdmin()
const { range, data, loading, error, refresh } = useRestaurantDashboard()
const ranges: DashboardRange[] = [7, 14, 30]
const firstName = computed(() => me.value?.profile.full_name?.trim().split(/\s+/)[0] || 'tim restoran')
</script>
<template>
  <div class="tkm-overview">
    <header class="tkm-page-heading"><div><p class="tkm-eyebrow">{{ me ? STAFF_ROLE_LABELS[me.profile.role] : 'Ruang kerja' }} / Dashboard</p><h1>Ringkasan restoran<span class="tkm-heading-dot">.</span></h1><p>Halo, {{ firstName }}. Pantau antrean dan konfirmasi input ke aplikasi kasir.</p></div><div class="tkm-page-actions"><span class="tkm-period-switch" role="group" aria-label="Periode dashboard"><button v-for="days in ranges" :key="days" type="button" :aria-pressed="range === days" @click="range = days">{{ days }} hari</button></span><button type="button" class="tkm-icon-button tkm-refresh" aria-label="Muat ulang dashboard" :disabled="loading" @click="refresh()"><UiDashboardIcon name="refresh" :class="{ 'tkm-spinning': loading }" /></button></div></header>
    <div class="tkm-overview-toolbar"><p><UiDashboardIcon name="clock" :size="14"/>{{ data ? 'Diperbarui ' + wibTime(data.generated_at) : 'Memuat data restoran' }}<span>· WIB</span></p><NuxtLink to="/cashier" class="tkm-text-link">Buka kasir<UiDashboardIcon name="arrow" :size="16" /></NuxtLink></div>
    <div v-if="error" class="tkm-dashboard-alert" role="alert"><UiDashboardIcon name="alert"/><div><p>{{ error }}</p><small v-if="data">Menampilkan data terakhir yang berhasil dimuat.</small></div><button type="button" class="tkm-small-button" :disabled="loading" @click="refresh()">Coba lagi</button></div>
    <div v-if="!data && loading" class="tkm-bento-skeleton" role="status"><span>Memuat ringkasan restoran…</span><div v-for="n in 6" :key="n"></div></div>
    <UiWeb3Bento v-if="data" :data="data" :aria-busy="loading" />
    <p class="tkm-dashboard-footer">TerasKayuManis · Diperbarui otomatis setiap 60 detik saat halaman aktif.</p>
  </div>
</template>
