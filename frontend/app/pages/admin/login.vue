<script setup lang="ts">
const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)
const route=useRoute()

async function submit() {
  error.value = ''
  loading.value = true
  try {
    await useStaffAuth().login(email.value, password.value, 'admin')
    password.value = ''
    await navigateTo('/admin')
  } catch (e: any) {
    password.value = ''
    error.value = e.data?.statusMessage || 'Login gagal. Periksa akun dan koneksi lalu coba lagi.'
  } finally { loading.value = false }
}
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center bg-cream px-4">
    <div class="card w-full max-w-sm p-8">
      <RestaurantLogo :size="80" eager class="mb-4 rounded-xl" />
      <h1 class="font-display text-2xl font-bold text-brand-950">Masuk ke Admin</h1>
      <p class="mt-1 text-sm text-brand-500">Masuk untuk mengelola cafe Anda.</p>
      <p v-if="route.query.reason==='session'" class="ops-alert mt-4" role="alert">Sesi berakhir atau izin akun berubah. Login kembali dengan akun pribadi yang aktif.</p>

      <form class="mt-6 space-y-4" @submit.prevent="submit">
        <div>
          <label class="label" for="email">Username atau email</label>
          <input id="email" v-model="email" type="text" class="input" required autocomplete="username" :disabled="loading">
        </div>
        <div>
          <label class="label" for="password">Password</label>
          <input id="password" v-model="password" type="password" class="input" required autocomplete="current-password" :disabled="loading">
        </div>
        <div v-if="error" class="rounded-xl bg-red-50 px-4 py-2.5 text-sm text-red-700" role="alert">{{ error }}</div>
        <button type="submit" class="btn btn-primary w-full" :disabled="loading">
          {{ loading ? 'Memeriksa...' : 'Masuk' }}
        </button>
      </form>
    </div>
  </div>
</template>
