<script setup lang="ts">
import type { Addon } from '#shared/types'
import type { AdminCatalog } from '#shared/dashboard-data'
const catalog=useAdminCatalog(),store=useDashboardCache()
const search=ref(''),debouncedSearch=useDebouncedValue(search)
const rows=computed(()=>(catalog.data.value?.addons??[]).filter(a=>a.name.toLocaleLowerCase('id').includes(debouncedSearch.value.trim().toLocaleLowerCase('id'))))
const sheet=ref(false),error=ref(''),busy=ref(false)
const form=ref<{id?:string;name:string;price:number}>({name:'',price:0})
async function run(transform:(catalog:AdminCatalog)=>AdminCatalog, action:()=>Promise<unknown>){
 if(busy.value)return;busy.value=true;error.value=''
 try{await store.cache.optimistic('catalog',transform,()=>store.mutation(action));sheet.value=false}
 catch(e:any){error.value=e.data?.statusMessage||'Perubahan belum terkonfirmasi. Periksa daftar sebelum mencoba lagi.'}
 finally{store.changed('catalog');await catalog.refresh();busy.value=false}
}
function save(){
 error.value=''
 if(!form.value.name.trim()||!Number.isInteger(form.value.price)||form.value.price<=0){error.value='Isi nama dan harga rupiah utuh di atas nol sebelum menerbitkan add-on.';return}
 const id=form.value.id,fields={name:form.value.name.trim(),price:form.value.price,price_confirmed:true}
 void run(c=>({...c,addons:c.addons.map(a=>a.id===id?{...a,...fields}:a)}),()=> $fetch<unknown>(id?`/api/admin/crud/addons/${id}`:'/api/admin/crud/addons',{method:id?'PATCH':'POST',body:fields,retry:0,timeout:15000}))
}
function toggle(a:Addon){
 if(!a.is_available&&(a.price<=0||a.price_confirmed===false)){error.value='Isi harga dan simpan add-on dahulu sebelum mengaktifkannya.';return}
 void run(c=>({...c,addons:c.addons.map(row=>row.id===a.id?{...row,is_available:!a.is_available}:row)}),()=> $fetch<unknown>(`/api/admin/crud/addons/${a.id}`,{method:'PATCH',body:{is_available:!a.is_available},retry:0,timeout:15000}))
}
function remove(a:Addon){if(confirm(`Hapus add-on "${a.name}"?`))void run(c=>({...c,addons:c.addons.filter(row=>row.id!==a.id)}),()=> $fetch<unknown>(`/api/admin/crud/addons/${a.id}`,{method:'DELETE',retry:0,timeout:15000}))}
</script>

<template>
  <div>
    <DashboardDataStatus :updated-at="catalog.updatedAt.value" :loading="catalog.loading.value" :error="catalog.error.value" />
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Add-on</h1>
      <button class="btn btn-primary btn-sm" @click="form = { name: '', price: 0 }; sheet = true"><Icon name="plus" :size="16" /> Tambah</button>
    </div>

    <p v-if="error&&!sheet" class="ops-alert mt-5" role="alert">{{error}}</p>
    <div class="ops-card mt-5"><label>Cari add-on<input v-model="search" type="search" class="ops-input"></label></div>
    <p v-if="catalog.error.value" class="ops-alert" role="alert">{{ catalog.error.value }} <button @click="catalog.refresh()">Coba lagi</button></p>
    <p v-if="catalog.loading.value&&!catalog.data.value" role="status">Memuat add-on…</p>
    <div class="card mt-5 divide-y divide-brand-50" :inert="busy">
      <p v-if="!rows.length" class="p-5">Tidak ada add-on yang cocok.</p>
      <div v-for="a in rows" :key="a.id" class="flex items-center gap-3 px-4 py-3">
        <div class="min-w-0 flex-1">
          <p class="font-medium">{{ a.name }}</p>
          <p class="text-xs text-brand-500">{{a.price_confirmed===false?'Harga belum dikonfirmasi':fmtIDR(a.price)}}</p>
        </div>
        <button
          class="badge cursor-pointer"
          :class="a.is_available ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-500'"
          @click="toggle(a)"
        >
          {{ a.is_available ? 'Aktif' : 'Nonaktif' }}
        </button>
        <button class="btn btn-ghost btn-sm" :aria-label="`Edit ${a.name}`" @click="form = { id: a.id, name: a.name, price: a.price }; sheet = true"><Icon name="pencil" :size="15" /></button>
        <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus ${a.name}`" @click="remove(a)"><Icon name="trash" :size="15" /></button>
      </div>
    </div>

    <AppSheet :open="sheet" :title="form.id ? 'Edit Add-on' : 'Tambah Add-on'" @close="!busy && (sheet = false)">
      <p v-if="error" class="ops-alert" role="alert">{{error}}</p>
      <div class="space-y-4">
        <div>
          <label class="label" for="addon-name">Nama</label>
          <input id="addon-name" v-model="form.name" class="input" maxlength="50">
        </div>
        <div>
          <label class="label" for="addon-price">Harga (Rp)</label>
          <input id="addon-price" v-model.number="form.price" type="number" min="0" step="500" class="input">
        </div>
        <button class="btn btn-primary w-full" :disabled="busy" @click="save">{{ busy?'Menyimpan…':'Simpan' }}</button>
      </div>
    </AppSheet>
  </div>
</template>
