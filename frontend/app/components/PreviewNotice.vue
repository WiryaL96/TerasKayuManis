<script setup lang="ts">
const expanded = ref(false)
function reset() {
  if (!confirm('Reset semua data simulasi di browser ini?')) return
  localStorage.removeItem('tkm-preview-v1')
  localStorage.removeItem('cart')
  for (const key of Object.keys(sessionStorage)) if (key.startsWith('tkm-')) sessionStorage.removeItem(key)
  location.assign('/')
}
</script>
<template>
  <aside class="preview-notice" aria-label="Informasi preview">
    <button type="button" :aria-expanded="expanded" @click="expanded = !expanded"><strong>PREVIEW UI</strong> · Data simulasi di browser ini <span aria-hidden="true">{{ expanded ? '−' : '+' }}</span></button>
    <div v-if="expanded" class="preview-notice-details">
      <p>Bukan layanan pemesanan restoran. Tidak terhubung database, POS, atau pembayaran asli. Data tidak tersinkron ke perangkat lain. Jangan masukkan data pribadi atau password asli.</p>
      <p>Superadmin: <code>owner.demo</code> · Admin: <code>admin.demo</code> · Password contoh: <code>preview123</code>. Pilih kasir contoh dengan PIN <code>123456</code>.</p>
      <nav><NuxtLink to="/">Customer</NuxtLink><NuxtLink to="/cashier">Kasir</NuxtLink><NuxtLink to="/admin/login">Admin</NuxtLink><button type="button" @click="reset">Reset simulasi</button></nav>
    </div>
  </aside>
</template>
<style>
.preview-notice{position:relative;z-index:100;background:#fff0c2;color:#553600;font:12px/1.5 Inter,sans-serif;border-bottom:1px solid #e5c879}.preview-notice>button{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:36px;padding:7px 12px;border:0;background:transparent;color:inherit;cursor:pointer}.preview-notice-details{max-width:1000px;margin:auto;padding:0 16px 14px}.preview-notice-details p{margin:6px 0}.preview-notice nav{display:flex;flex-wrap:wrap;gap:14px;margin-top:10px}.preview-notice nav a,.preview-notice nav button{color:inherit;text-decoration:underline;background:none;border:0;cursor:pointer}.preview-notice code{font-weight:700}.preview-notice button:focus-visible,.preview-notice a:focus-visible{outline:2px solid currentColor;outline-offset:2px}@media print{.preview-notice{display:none}}
</style>
