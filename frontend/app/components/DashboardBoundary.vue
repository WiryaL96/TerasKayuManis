<script setup lang="ts">
const route = useRoute()
const { cache } = useDashboardCache()
const boundary=ref<{error:unknown;clearError:()=>void}|null>(null)
watch(()=>route.path,()=>{if(boundary.value?.error)boundary.value.clearError()})
function recover(clearError: () => void) { cache.invalidate(); clearError() }
const home=computed(()=>route.path.startsWith('/cashier')?'/cashier':route.path.startsWith('/admin')?'/admin':'/')
</script>
<template>
  <NuxtErrorBoundary ref="boundary">
    <slot />
    <template #error="{ clearError }">
      <section class="ops-card" role="alert">
        <h2>Bagian ini belum dapat ditampilkan</h2>
        <p>Coba buka kembali bagian ini. Periksa status pesanan sebelum mengulangi konfirmasi pembayaran.</p>
        <div class="ops-actions"><button class="ops-button" @click="recover(clearError)">Coba lagi</button><NuxtLink :to="home" class="ops-button secondary">Kembali</NuxtLink></div>
      </section>
    </template>
  </NuxtErrorBoundary>
</template>
