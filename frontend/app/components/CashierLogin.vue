<script setup lang="ts">
import {isAccessError} from '#shared/query-cache'
interface Choice{id:string;name:string;photo:string|null}
const props=defineProps<{message?:string;busy?:boolean}>(),emit=defineEmits<{authenticated:[]}>()
const cached=useState<{rows:Choice[];at:number}>('cashier-access-roster',()=>({rows:[],at:0}))
const selectedId=ref(''),pin=ref(''),error=ref(''),loading=ref(false),signing=ref(false),legacy=ref(false)
const selected=computed(()=>cached.value.rows.find(c=>c.id===selectedId.value)??null)
const username=ref(''),password=ref(''),pinInput=ref<HTMLInputElement|null>(null)
const locked=computed(()=>signing.value||props.busy)
let controller:AbortController|undefined,disposed=false
async function load(force=false){
 if(loading.value)return
 if(!force&&cached.value.at>Date.now()-60000)return
 controller?.abort();controller=new AbortController();loading.value=true;error.value=''
 try{
  let retries=0
  const rows=await $fetch<unknown>('/api/auth/cashiers',{signal:controller.signal,timeout:15000,retry:2,retryDelay:()=>350*2**retries++})
  if(disposed)return
  if(!Array.isArray(rows)||rows.some(r=>!r||typeof r.id!=='string'||typeof r.name!=='string'||(r.photo!==null&&(typeof r.photo!=='string'||!/^\/api\/auth\/cashiers\/[a-f0-9-]{36}\/photo\?v=[a-f0-9-]{36}\.webp$/i.test(r.photo)))))throw Error('Invalid roster')
  cached.value={rows:rows as Choice[],at:Date.now()}
  if(selectedId.value&&!selected.value)selectedId.value=''
 }catch(e:any){if(disposed)return;if(isAccessError(e)){cached.value={rows:[],at:0};selectedId.value=''}error.value=e.data?.statusMessage||'Daftar kasir belum dapat diperbarui. Periksa koneksi lalu coba lagi.'}
 finally{loading.value=false}
}
watch(selectedId,()=>{pin.value='';error.value='';if(selected.value)void nextTick(()=>pinInput.value?.focus())},{flush:'sync'})
async function loginPin(){
 if(locked.value||!selected.value||!/^\d{6}$/.test(pin.value))return
 signing.value=true;error.value=''
 try{await useStaffAuth().loginPin(selected.value.id,pin.value);if(!disposed)emit('authenticated')}
 catch(e:any){if(!disposed)error.value=e.data?.statusMessage||'Belum berhasil masuk. Periksa PIN dan koneksi, lalu coba kembali.'}
 finally{pin.value='';signing.value=false}
}
async function loginLegacy(){
 if(locked.value)return;signing.value=true;error.value=''
 try{await useStaffAuth().login(username.value,password.value,'cashier');if(!disposed)emit('authenticated')}
 catch(e:any){if(!disposed)error.value=e.data?.statusMessage||'Login belum berhasil. Periksa akun dan koneksi.'}
 finally{password.value='';signing.value=false}
}
const online=()=>{void load()}
onMounted(()=>{void load();window.addEventListener('online',online)})
onUnmounted(()=>{disposed=true;controller?.abort();pin.value='';password.value='';window.removeEventListener('online',online)})
</script>
<template>
 <section class="cashier-access">
  <header><RestaurantLogo :size="64" eager /><div><p class="cashier-eyebrow">AREA STAF</p><h1>Masuk ke Kasir</h1><p class="cashier-muted">Pilih akun dan masukkan PIN.</p></div></header>
  <p v-if="error||message" class="cashier-alert" role="alert">{{ error||message }}</p>
  <form v-if="!legacy" class="cashier-login-form" @submit.prevent="loginPin">
   <div class="cashier-form-heading"><h2>Akun kasir</h2><button type="button" class="cashier-reload" :disabled="loading||locked" @click="load(true)">{{ loading?'Memuat…':'Muat ulang' }}</button></div>
   <p v-if="loading&&!cached.at" role="status">Memuat daftar kasir…</p>
   <label for="cashier-profile">Pilih kasir</label>
   <select id="cashier-profile" v-model="selectedId" required :disabled="locked||!cached.rows.length">
    <option disabled value="">{{ loading&&!cached.at?'Memuat daftar kasir…':'Pilih akun kasir' }}</option>
    <option v-for="c in cached.rows" :key="c.id" :value="c.id">{{ c.name }}</option>
   </select>
   <div v-if="selected" class="cashier-selected"><StaffAvatar :name="selected.name" :src="selected.photo" :size="48"/><div><strong>{{ selected.name }}</strong><span>Kasir</span></div></div>
   <label for="cashier-pin">PIN kasir</label>
   <input id="cashier-pin" ref="pinInput" v-model="pin" type="password" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" minlength="6" autocomplete="off" placeholder="Masukkan PIN 6 angka" aria-describedby="cashier-pin-help" required :disabled="locked||!selected" @input="pin=pin.replace(/\D/g,'').slice(0,6)">
   <small id="cashier-pin-help" class="cashier-muted">Gunakan PIN pribadi yang diberikan admin.</small>
   <button class="cashier-button cashier-primary" :disabled="locked||!selected||pin.length!==6">{{ locked?'Memeriksa…':'Masuk ke Kasir' }}</button>
   <div v-if="!cached.rows.length&&!loading&&!error" class="cashier-roster-empty"><p>Belum ada kasir yang siap. Minta admin membuat akun atau mengatur PIN kasir.</p><NuxtLink to="/admin/staff">Buka halaman Staf</NuxtLink></div>
  </form>
  <form v-else class="cashier-legacy-form" @submit.prevent="loginLegacy"><h2>Masuk dengan akun</h2><p class="cashier-muted">Untuk admin atau akun kasir yang belum diatur PIN-nya.</p><label for="cashier-email">Username atau email</label><input id="cashier-email" v-model="username" autocomplete="username" required :disabled="locked"><label for="cashier-password">Password</label><input id="cashier-password" v-model="password" type="password" autocomplete="current-password" required :disabled="locked"><button class="cashier-button cashier-primary" :disabled="locked">{{ locked?'Memeriksa…':'Login kasir' }}</button></form>
  <footer><button class="cashier-access-switch" :disabled="locked" @click="legacy=!legacy;pin='';password='';error=''">{{ legacy?'Kembali ke pilihan kasir':'Masuk akun lama / admin' }}</button><NuxtLink to="/" class="cashier-login-back">← Halaman pelanggan</NuxtLink></footer>
 </section>
</template>
<style scoped>
.cashier-access{width:100%;max-width:520px;margin:auto;padding:40px 24px}
.cashier-access>header{display:flex;align-items:center;gap:16px;margin-bottom:24px}
.cashier-access>header>div{min-width:0}
.cashier-access h1{font-size:30px;letter-spacing:-.04em;margin:10px 0}
.cashier-access h2{font-size:18px;margin:0}
.cashier-login-form,.cashier-legacy-form{display:grid;gap:12px;border:1px solid #dce1d8;border-radius:20px;padding:28px;background:#fff}
.cashier-form-heading{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:8px}
.cashier-reload{min-height:44px;padding:8px 0 8px 12px;border:0;background:transparent;color:#52604b;font-size:13px;font-weight:600}
.cashier-selected{display:flex;align-items:center;gap:12px;padding:12px;border:1px solid #e4e9dc;border-radius:10px;background:#f8faf5}
.cashier-selected>div{display:grid;gap:2px;min-width:0}
.cashier-selected strong{font-size:15px;overflow-wrap:anywhere}
.cashier-selected span{font-size:12px;color:#67705f}
.cashier-login-form label,.cashier-legacy-form label{font-size:14px}
.cashier-login-form small{font-size:12px}
.cashier-login-form>.cashier-button,.cashier-legacy-form>.cashier-button{margin-top:8px}
.cashier-roster-empty{font-size:13px;color:#67705f}
.cashier-roster-empty p{margin:4px 0 10px}
.cashier-roster-empty a{color:#52604b;text-decoration:underline}
.cashier-access footer{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:4px 16px;margin-top:16px}
.cashier-access-switch{min-height:44px;background:none;border:0;padding:0;text-decoration:underline;color:#52604b;font-size:13px}
@media(max-width:600px){.cashier-access{padding:28px 18px}.cashier-login-form,.cashier-legacy-form{padding:22px}}
</style>
