<script setup lang="ts">
useHead({
  meta: [
    { name: 'referrer', content: 'no-referrer' },
    { name: 'robots', content: 'noindex,nofollow' },
  ],
})
const ticket = ref(''),
  token = ref(''),
  purpose = ref(''),
  password = ref(''),
  repeat = ref(''),
  busy = ref(false),
  ready = ref(false),
  done = ref(false),
  error = ref('')
onMounted(() => {
  const p = new URLSearchParams(location.hash.slice(1))
  ticket.value = p.get('ticket') || ''
  token.value = p.get('token_hash') || ''
  purpose.value = p.get('purpose') || ''
  history.replaceState(null, '', location.pathname)
  ready.value = !!ticket.value && !!token.value
  if (!ready.value)
    error.value = 'Tautan tidak lengkap. Minta tautan baru ke admin.'
})
async function submit() {
  if (busy.value) return
  if (password.value !== repeat.value) {
    error.value = 'Konfirmasi password belum sama.'
    return
  }
  busy.value = true
  error.value = ''
  try {
    await $fetch('/api/auth/staff-activate', {
      method: 'POST',
      body: {
        ticket: ticket.value,
        token_hash: token.value,
        purpose: purpose.value,
        password: password.value,
      },
    })
    done.value = true
  } catch (e: any) {
    error.value =
      e.data?.statusMessage ||
      'Aktivasi belum berhasil. Minta tautan baru ke admin.'
    ready.value = false
  } finally {
    busy.value = false
    password.value = ''
    repeat.value = ''
    ticket.value = ''
    token.value = ''
  }
}
</script>
<template>
  <main class="ops-auth">
    <section class="ops-card">
      <RestaurantLogo :size="80" eager class="mb-4 rounded-xl" />
      <h1>{{ done ? 'Akun siap digunakan' : 'Atur password akun' }}</h1>
      <p v-if="done">
        Password tersimpan. Login memakai email akun dan password barumu.
      </p>
      <p v-else>
        Tautan privat ini berlaku satu kali. Gunakan password minimal 12
        karakter.
      </p>
      <p v-if="error" class="ops-alert" role="alert">{{ error }}</p>
      <form v-if="ready && !done" class="ops-form" @submit.prevent="submit">
        <label
          >Password baru<input
            v-model="password"
            type="password"
            minlength="12"
            maxlength="128"
            required
            autocomplete="new-password"
            class="ops-input" /></label
        ><label
          >Ulangi password<input
            v-model="repeat"
            type="password"
            minlength="12"
            maxlength="128"
            required
            autocomplete="new-password"
            class="ops-input" /></label
        ><button class="ops-button" :disabled="busy">
          {{ busy ? 'Menyimpan…' : 'Simpan password' }}
        </button>
      </form>
      <div v-if="done" class="ops-actions">
        <NuxtLink to="/cashier" class="ops-button">Login kasir</NuxtLink
        ><NuxtLink to="/admin/login" class="ops-button secondary"
          >Login admin</NuxtLink
        >
      </div>
    </section>
  </main>
</template>
