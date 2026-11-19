<script setup lang="ts">
import { STAFF_ROLE_LABELS } from '#shared/staff-roles'
import { normalizeStaff, type StaffRow } from '#shared/dashboard-data'
const {can}=useAdmin(),store=useDashboardCache()
const staffQuery=useDashboardQuery(()=>({key:'staff',url:'/api/admin/staff',staleTime:60000,normalize:normalizeStaff}))
const name=ref(''),username=ref(''),email=ref(''),password=ref(''),confirmation=ref(''),role=ref<'admin'|'cashier'>('cashier')
const pin=ref(''),photoPath=ref<string|null>(null),photoKey=ref(0),uploading=ref(false)
const createOpen=ref(false),statusFilter=ref('current'),roleFilter=ref('all'),page=ref(1)
const busy=ref(false),error=ref(''),message=ref(''),showPassword=ref(false)
const search=ref(''),debouncedSearch=useDebouncedValue(search)
const filteredStaff=computed(()=>(staffQuery.data.value??[]).filter(s=>
 (statusFilter.value==='archived'?!!s.archived_at:!s.archived_at&&(statusFilter.value==='current'||s.staff_status===statusFilter.value)) &&
 (roleFilter.value==='all'||s.role===roleFilter.value) &&
 `${s.full_name||''} ${s.username||''} ${s.email||''}`.toLocaleLowerCase('id').includes(debouncedSearch.value.trim().toLocaleLowerCase('id'))))
const totalPages=computed(()=>Math.max(1,Math.ceil(filteredStaff.value.length/20)))
const visibleStaff=computed(()=>filteredStaff.value.slice((page.value-1)*20,page.value*20))
watch([debouncedSearch,statusFilter,roleFilter],()=>page.value=1)
watch(totalPages,value=>{if(page.value>value)page.value=value})
const editing=ref<StaffRow|null>(null),editError=ref('')
const editForm=ref({full_name:'',username:'',email:'',role:'cashier' as 'admin'|'cashier',credential:'',confirmation:''})
function editAccount(s:StaffRow){editing.value=s;editError.value='';editForm.value={full_name:s.full_name||'',username:s.username||'',email:s.email||'',role:s.role,credential:'',confirmation:''}}
function closeEdit(){if(busy.value)return;editing.value=null;editForm.value.credential='';editForm.value.confirmation=''}
async function saveAccount(){
 const s=editing.value;if(!s||busy.value)return
 const f=editForm.value
 if(f.credential!==f.confirmation){editError.value='Konfirmasi belum sama.';return}
 busy.value=true;editError.value=''
 try{await store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}`,{method:'PUT',body:{full_name:f.full_name,username:f.username,email:f.email,role:f.role,...(f.role==='cashier'?{pin:f.credential}:{password:f.credential})},retry:0,timeout:35000}));editing.value=null;message.value='Identitas dan akses tersimpan. Sesi lama dicabut; akun yang sebelumnya nonaktif tetap nonaktif.'}
 catch(e:any){editError.value=e.data?.statusMessage||'Pembaruan belum selesai. Akun tetap tidak dapat login jika kredensial belum tersimpan. Muat ulang lalu simpan edit akun kembali.'}
 finally{f.credential='';f.confirmation='';await reload();busy.value=false}
}
const archiveTarget=ref<StaffRow|null>(null),archiveError=ref('')
async function archiveAccount(){
 const s=archiveTarget.value;if(!s||busy.value)return;busy.value=true;archiveError.value=''
 try{await store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}`,{method:'DELETE',retry:0,timeout:15000}));archiveTarget.value=null;message.value='Akun diarsipkan dan sesi dicabut. Riwayat tetap tersimpan.'}
 catch(e:any){archiveError.value=e.data?.statusMessage||'Arsip belum terkonfirmasi. Muat ulang daftar sebelum mencoba lagi.'}
 finally{await reload();busy.value=false}
}
async function restoreAccount(s:StaffRow){if(busy.value)return;busy.value=true;error.value=''
 try{await store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}/restore`,{method:'POST',retry:0,timeout:15000}));message.value='Akun dipulihkan dalam status nonaktif. Atur PIN/password untuk mengaktifkannya.'}
 catch(e:any){error.value=e.data?.statusMessage||'Pemulihan belum terkonfirmasi.'}
 finally{await reload();busy.value=false}
}
const labels={active:'Aktif',invited:'Pengaturan belum selesai',disabled:'Nonaktif'}
const renaming=ref<StaffRow|null>(null),renameValue=ref(''),renameError=ref('')
const editingPhoto=ref<StaffRow|null>(null),replacementPhoto=ref<string|null>(null),photoChanged=ref(false),photoError=ref('')
const changingPassword=ref<StaffRow|null>(null),newPassword=ref(''),repeatPassword=ref(''),passwordError=ref(''),showNewPassword=ref(false)
watch(role,()=>{password.value='';pin.value='';confirmation.value='';showPassword.value=false})
const isPin=computed(()=>changingPassword.value?.role==='cashier')
function closeCreate(){if(busy.value||uploading.value)return;createOpen.value=false;password.value='';pin.value='';confirmation.value='';showPassword.value=false}
function photoSrc(s:StaffRow){return s.staff_photo_path?`/api/admin/staff/${s.id}/photo?v=${s.staff_photo_path.split('/').at(-1)}`:null}
async function reload(){store.changed('staff');await staffQuery.refresh()}
async function create(){
 if(busy.value||uploading.value)return
 error.value='';message.value=''
 if((role.value==='cashier'?pin.value:password.value)!==confirmation.value){error.value='Konfirmasi belum sama.';return}
 busy.value=true
 try{
  const result=await store.mutation(()=>$fetch<{profile:StaffRow}>('/api/admin/staff',{method:'POST',body:{full_name:name.value,username:username.value,email:email.value,...(role.value==='cashier'?{pin:pin.value}:{password:password.value}),...(photoPath.value?{photo_path:photoPath.value}:{}),role:can(['superadmin'])?role.value:'cashier'},retry:0,timeout:35000}))
  message.value=`Akun ${result.profile.username} berhasil dibuat dan langsung dapat login.`
  name.value='';username.value='';email.value='';photoPath.value=null;photoKey.value++;createOpen.value=false
 }catch(e:any){error.value=e.data?.statusMessage||'Pembuatan akun belum terkonfirmasi. Periksa daftar staf sebelum mencoba lagi.'}
 finally{password.value='';pin.value='';confirmation.value='';showPassword.value=false;await reload();busy.value=false}
}
async function disable(s:StaffRow){
 if(busy.value||!confirm('Nonaktifkan akun ini? Sesi lama langsung ditolak.'))return
 busy.value=true;error.value='';message.value=''
 try{await store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}`,{method:'PATCH',body:{command:'disable'},retry:0,timeout:15000}));message.value='Akun dinonaktifkan.'}
 catch(e:any){error.value=e.data?.statusMessage||'Status akun belum dapat diperbarui.'}
 finally{await reload();busy.value=false}
}
function rename(s:StaffRow){renaming.value=s;renameValue.value=s.full_name||'';renameError.value=''}
async function saveName(){
 const s=renaming.value;if(!s||busy.value)return
 busy.value=true;renameError.value=''
 try{
  const full_name=renameValue.value.trim()
  await store.cache.optimistic<StaffRow[],unknown>('staff',rows=>rows.map(row=>row.id===s.id?{...row,full_name}:row),()=>store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}`,{method:'PATCH',body:{command:'rename',full_name},retry:0,timeout:15000})))
  renaming.value=null
 }catch(e:any){renameError.value=e.data?.statusMessage||'Nama belum tersimpan.'}
 finally{await reload();busy.value=false}
}
function passwordDialog(s:StaffRow){changingPassword.value=s;newPassword.value='';repeatPassword.value='';passwordError.value='';showNewPassword.value=false}
function closePassword(){if(busy.value)return;changingPassword.value=null;newPassword.value='';repeatPassword.value='';passwordError.value='';showNewPassword.value=false}
async function savePassword(){
 const s=changingPassword.value;if(!s||busy.value)return
 passwordError.value=''
 if(newPassword.value!==repeatPassword.value){passwordError.value='Konfirmasi belum sama.';return}
 busy.value=true;message.value=''
 try{
  await store.mutation(()=>$fetch<unknown>(`/api/admin/staff/${s.id}/${isPin.value?'pin':'password'}`,{method:'POST',body:{...(isPin.value?{pin:newPassword.value}:{password:newPassword.value}),reactivate:s.staff_status==='disabled'},retry:0,timeout:35000}))
  message.value=`${isPin.value?'PIN':'Password'} ${s.full_name||s.username||'staf'} tersimpan. Akun aktif dan dapat login; sesi lama dicabut.`
  changingPassword.value=null
 }catch(e:any){passwordError.value=e.data?.statusMessage||'Password belum terkonfirmasi. Periksa status akun sebelum mencoba lagi.'}
 finally{newPassword.value='';repeatPassword.value='';showNewPassword.value=false;await reload();busy.value=false}
}
function editPhoto(s:StaffRow){editingPhoto.value=s;replacementPhoto.value=null;photoChanged.value=false;photoError.value=''}
async function savePhoto(){
 const s=editingPhoto.value;if(!s||busy.value||uploading.value||!photoChanged.value)return;busy.value=true;photoError.value=''
 try{await store.mutation(()=>$fetch<{ok:boolean}>(`/api/admin/staff/${s.id}/photo`,{method:'PATCH',body:{path:replacementPhoto.value},retry:0,timeout:15000}));editingPhoto.value=null;await reload()}
 catch(e:any){photoError.value=e.data?.statusMessage||'Foto belum tersimpan.'}
 finally{busy.value=false}
}
</script>
<template>
 <div>
  <DashboardDataStatus :updated-at="staffQuery.updatedAt.value" :loading="staffQuery.loading.value" :error="staffQuery.error.value" />
  <header class="ops-heading"><div><p class="ops-eyebrow">Akses tim</p><h1>Kelola staf</h1><p>{{ can(['superadmin'])?'Buat dan kelola akun admin serta kasir.':'Buat dan kelola akun kasir pribadi.' }}</p></div><button class="ops-button" @click="error='';createOpen=true">Tambah staf</button></header>
  <p v-if="error&&!createOpen" class="ops-alert" role="alert">{{ error }}</p>
  <p v-if="message" class="ops-success" role="status">{{ message }}</p>
  <p v-if="staffQuery.error.value" class="ops-alert" role="alert">{{ staffQuery.error.value }} <button @click="staffQuery.refresh()">Coba lagi</button></p>
  <AppSheet :open="createOpen" title="Buat akun staf" @close="closeCreate"><form class="ops-form staff-account-form" @submit.prevent="create"><p v-if="error" class="ops-alert" role="alert">{{ error }}</p>
   <div><h2>Buat akun staf</h2><p>Kasir memakai PIN pribadi. Admin memakai password. Akun langsung aktif setelah tersimpan.</p></div>
   <div class="ops-form-row">
    <label>Nama lengkap<input v-model.trim="name" class="ops-input" required minlength="2" maxlength="100" autocomplete="off" :disabled="busy"></label>
    <label>Username<input v-model.trim="username" class="ops-input" required minlength="3" maxlength="32" pattern="[a-zA-Z0-9][a-zA-Z0-9._-]{2,31}" autocomplete="off" spellcheck="false" autocapitalize="none" :disabled="busy"><small>3–32 karakter: huruf, angka, titik, _ atau -.</small></label>
   </div>
   <div class="ops-form-row">
    <label>Email<input v-model.trim="email" class="ops-input" type="email" required maxlength="254" autocomplete="off" :disabled="busy"><small>Gunakan email staf yang berbeda untuk setiap akun.</small></label>
    <label v-if="can(['superadmin'])">Peran<select v-model="role" aria-label="Peran" class="ops-input" :disabled="busy"><option value="cashier">Kasir</option><option value="admin">Admin</option></select></label>
   </div>
   <StaffPhotoPicker :key="photoKey" :name="name" :disabled="busy" @uploaded="photoPath=$event" @uploading="uploading=$event" />
   <div v-if="role==='cashier'" class="ops-form-row"><label>PIN kasir<input v-model="pin" type="password" inputmode="numeric" pattern="[0-9]{6}" minlength="6" maxlength="6" class="ops-input" required autocomplete="off" :disabled="busy"><small>6 angka untuk akses layar kasir.</small></label><label>Konfirmasi PIN<input v-model="confirmation" type="password" inputmode="numeric" pattern="[0-9]{6}" minlength="6" maxlength="6" class="ops-input" required autocomplete="off" :disabled="busy"></label></div>
   <div v-else class="ops-form-row">
    <label>Password<input v-model="password" class="ops-input" :type="showPassword?'text':'password'" required minlength="12" maxlength="128" autocomplete="new-password" :disabled="busy"><small>Minimal 12 karakter.</small></label>
    <label>Konfirmasi password<input v-model="confirmation" class="ops-input" :type="showPassword?'text':'password'" required minlength="12" maxlength="128" autocomplete="new-password" :disabled="busy"></label>
   </div>
   <div class="ops-actions"><button v-if="role==='admin'" type="button" class="ops-button secondary" :aria-pressed="showPassword" :disabled="busy" @click="showPassword=!showPassword">{{ showPassword?'Sembunyikan password':'Tampilkan password' }}</button><button class="ops-button" :disabled="busy||uploading">{{ busy?'Menyimpan…':'Buat akun' }}</button></div>
  </form></AppSheet>
  <section class="ops-card ops-table-wrap">
   <div class="staff-toolbar"><label>Cari staf<input v-model="search" type="search" class="ops-input" placeholder="Nama, username, atau email"></label><label>Status akun<select v-model="statusFilter" class="ops-input"><option value="current">Semua akun saat ini</option><option value="active">Aktif</option><option value="invited">Pengaturan belum selesai</option><option value="disabled">Nonaktif</option><option value="archived">Arsip</option></select></label><label v-if="can(['superadmin'])">Filter peran<select v-model="roleFilter" class="ops-input"><option value="all">Semua peran</option><option value="admin">Admin</option><option value="cashier">Kasir</option></select></label></div><p class="staff-result" role="status">{{ filteredStaff.length }} akun ditemukan</p>
   <p v-if="staffQuery.loading.value&&!staffQuery.data.value" role="status">Memuat staf…</p>
   <table class="ops-table staff-table"><thead><tr><th>Staf / username</th><th>Status</th><th>Kelola akun</th></tr></thead><tbody>
    <tr v-for="s in visibleStaff" :key="s.id"><td><div class="staff-identity"><StaffAvatar :name="s.full_name||'Staf'" :src="photoSrc(s)" :size="44"/><div><strong>{{ s.full_name||'Nama belum diisi' }}</strong><small>{{ STAFF_ROLE_LABELS[s.role] }} · {{ s.username?'@'+s.username:'Login dengan email' }}</small><small>{{ s.email||'Email akun lama belum tercatat' }}</small><small v-if="s.role==='cashier'">{{ s.cashier_pin_enabled?'Akses dengan PIN':'PIN belum diatur' }}</small></div></div></td><td><span class="ops-badge" :class="s.staff_status">{{ s.archived_at?'Diarsipkan':labels[s.staff_status] }}</span></td><td><div class="ops-actions staff-row-actions"><button v-if="s.archived_at" class="ops-button secondary" :disabled="busy" @click="restoreAccount(s)">Pulihkan akun</button><template v-else><button class="ops-button" :disabled="busy" @click="editAccount(s)">Edit akun</button><button class="ops-button secondary" :disabled="busy" @click="rename(s)">Ubah nama</button><button v-if="s.email" class="ops-button secondary" :disabled="busy" @click="passwordDialog(s)">{{ s.role==='cashier'?(s.staff_status==='disabled'?'Aktifkan & atur PIN':'Atur PIN'):(s.staff_status==='disabled'?'Aktifkan & atur password':'Atur password') }}</button><button class="ops-button secondary" :disabled="busy" @click="editPhoto(s)">Ubah foto</button><button v-if="s.staff_status!=='disabled'" class="ops-button secondary" :disabled="busy" @click="disable(s)">Nonaktifkan</button><button class="ops-button secondary danger" :disabled="busy" @click="archiveTarget=s;archiveError=''">Arsipkan</button></template></div></td></tr>
    <tr v-if="!visibleStaff.length"><td colspan="3">Tidak ada staf yang cocok.</td></tr>
   </tbody></table><div class="ops-actions staff-pagination"><button class="ops-button secondary" :disabled="page<=1" @click="page--">Sebelumnya</button><span>Halaman {{ page }} dari {{ totalPages }}</span><button class="ops-button secondary" :disabled="page>=totalPages" @click="page++">Berikutnya</button></div>
  </section>
  <AppSheet :open="!!editing" title="Edit akun staf" @close="closeEdit"><form class="ops-form" @submit.prevent="saveAccount">
   <p>Perubahan mencabut sesi lama. Masukkan PIN/password baru untuk menyelesaikan perubahan email atau peran. Akun nonaktif tetap nonaktif.</p><p v-if="editError" class="ops-alert" role="alert">{{ editError }}</p>
   <div class="ops-form-row"><label>Nama lengkap<input v-model.trim="editForm.full_name" class="ops-input" required minlength="2" maxlength="100" :disabled="busy"></label><label>Username<input v-model.trim="editForm.username" class="ops-input" required minlength="3" maxlength="32" pattern="[a-zA-Z0-9][a-zA-Z0-9._-]{2,31}" :disabled="busy"></label></div>
   <div class="ops-form-row"><label>Email<input v-model.trim="editForm.email" type="email" class="ops-input" required maxlength="254" :disabled="busy"></label><label v-if="can(['superadmin'])">Peran akun<select v-model="editForm.role" class="ops-input" :disabled="busy" @change="editForm.credential='';editForm.confirmation=''"><option value="cashier">Kasir</option><option value="admin">Admin</option></select></label></div>
   <div class="ops-form-row"><label>{{ editForm.role==='cashier'?'PIN baru':'Password baru' }}<input v-model="editForm.credential" class="ops-input" type="password" required :inputmode="editForm.role==='cashier'?'numeric':'text'" :pattern="editForm.role==='cashier'?'[0-9]{6}':undefined" :minlength="editForm.role==='cashier'?6:12" :maxlength="editForm.role==='cashier'?6:128" autocomplete="new-password" :disabled="busy"></label><label>Konfirmasi kredensial<input v-model="editForm.confirmation" class="ops-input" type="password" required autocomplete="new-password" :disabled="busy"></label></div>
   <button class="ops-button" :disabled="busy">{{ busy?'Menyimpan…':'Simpan akun' }}</button>
  </form></AppSheet>
  <AppSheet :open="!!archiveTarget" title="Arsipkan akun staf" @close="!busy&&(archiveTarget=null)"><div class="ops-form"><p>Arsipkan <strong>{{ archiveTarget?.full_name }}</strong>? Akun tidak dapat login. Riwayat transaksi dan log tetap tersimpan. Superadmin/admin yang berwenang dapat memulihkannya dari filter Arsip.</p><p v-if="archiveError" class="ops-alert" role="alert">{{ archiveError }}</p><button class="ops-button danger" :disabled="busy" @click="archiveAccount">Ya, arsipkan akun</button></div></AppSheet>
  <AppSheet :open="!!editingPhoto" title="Ubah foto staf" @close="!busy&&!uploading&&(editingPhoto=null)"><form class="ops-form" @submit.prevent="savePhoto"><StaffPhotoPicker v-if="editingPhoto" :key="editingPhoto.id" :name="editingPhoto.full_name||'Staf'" :src="photoSrc(editingPhoto)" :disabled="busy" @uploaded="replacementPhoto=$event;photoChanged=true" @uploading="uploading=$event"/><p v-if="photoError" class="ops-alert" role="alert">{{ photoError }}</p><button class="ops-button" :disabled="busy||uploading||!photoChanged">Simpan foto</button></form></AppSheet>
  <AppSheet :open="!!renaming" title="Ubah nama staf" @close="!busy&&(renaming=null)"><form class="ops-form" @submit.prevent="saveName"><p>Struk lama tetap memakai nama kasir saat transaksi.</p><p v-if="renameError" class="ops-alert" role="alert">{{ renameError }}</p><label>Nama staf<input v-model="renameValue" class="ops-input" required minlength="2" maxlength="100" :disabled="busy"></label><button class="ops-button" :disabled="busy">Simpan nama</button></form></AppSheet>
  <AppSheet :open="!!changingPassword" :title="isPin?'Atur PIN kasir':'Atur password staf'" @close="closePassword"><form class="ops-form" @submit.prevent="savePassword"><p>{{ changingPassword?.full_name }} · {{ changingPassword?.username||changingPassword?.email }}</p><p>Akses baru langsung berlaku dan sesi lama dicabut. Kasir masuk dengan pilihan nama dan PIN.</p><p v-if="passwordError" class="ops-alert" role="alert">{{ passwordError }}</p><label>{{ isPin?'PIN baru':'Password baru' }}<input v-model="newPassword" class="ops-input" :type="showNewPassword?'text':'password'" :inputmode="isPin?'numeric':undefined" :pattern="isPin?'[0-9]{6}':undefined" required :minlength="isPin?6:12" :maxlength="isPin?6:128" autocomplete="new-password" :disabled="busy"></label><label>{{ isPin?'Konfirmasi PIN baru':'Konfirmasi password baru' }}<input v-model="repeatPassword" class="ops-input" :type="showNewPassword?'text':'password'" :inputmode="isPin?'numeric':undefined" :pattern="isPin?'[0-9]{6}':undefined" required :minlength="isPin?6:12" :maxlength="isPin?6:128" autocomplete="new-password" :disabled="busy"></label><div class="ops-actions"><button type="button" class="ops-button secondary" :disabled="busy" @click="showNewPassword=!showNewPassword">{{ showNewPassword?(isPin?'Sembunyikan PIN':'Sembunyikan password'):(isPin?'Tampilkan PIN':'Tampilkan password') }}</button><button class="ops-button" :disabled="busy">{{ busy?'Menyimpan…':isPin?'Simpan PIN & aktifkan':'Simpan password & aktifkan' }}</button></div></form></AppSheet>
 </div>
</template>
<style scoped>
.staff-account-form .ops-form-row { align-items: start; }
</style>
