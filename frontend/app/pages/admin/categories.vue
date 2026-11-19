<script setup lang="ts">
import type { Category } from '#shared/types'
import type { AdminCatalog } from '#shared/dashboard-data'
const catalog=useAdminCatalog(), store=useDashboardCache()
const rows=computed(()=>catalog.data.value?.categories??[])
const sheet=ref(false),busy=ref(false),error=ref('')
const form=ref<{id?:string;name:string}>({name:''})
const search=ref(''),debouncedSearch=useDebouncedValue(search)
const orderedRows=computed(()=>[...rows.value].sort((a,b)=>a.sort_order-b.sort_order||a.id.localeCompare(b.id)))
const sortedRows=computed(()=>orderedRows.value.filter(c=>c.name.toLocaleLowerCase('id').includes(debouncedSearch.value.trim().toLocaleLowerCase('id'))))
async function run(transform:(catalog:AdminCatalog)=>AdminCatalog, action:()=>Promise<unknown>) {
  if(busy.value)return
  busy.value=true;error.value=''
  try{await store.cache.optimistic('catalog',transform,()=>store.mutation(action));sheet.value=false}
  catch(e:any){error.value=e.data?.statusMessage||'Perubahan belum terkonfirmasi. Periksa daftar sebelum mencoba lagi.'}
  finally{store.changed('catalog');await catalog.refresh();busy.value=false}
}
function save(){
  const name=form.value.name.trim();if(!name||busy.value)return
  const id=form.value.id,slug=name.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'')
  void run(c=>({...c,categories:c.categories.map(row=>row.id===id?{...row,name}:row)}),()=> $fetch<unknown>(id?`/api/admin/crud/categories/${id}`:'/api/admin/crud/categories',{method:id?'PATCH':'POST',body:id?{name}:{name,slug:slug+'-'+crypto.randomUUID().slice(0,8),sort_order:Math.max(0,...rows.value.map(c=>c.sort_order))+1},retry:0,timeout:15000}))
}
function toggleActive(c:Category){void run(data=>({...data,categories:data.categories.map(row=>row.id===c.id?{...row,is_active:!c.is_active}:row)}),()=> $fetch<unknown>(`/api/admin/crud/categories/${c.id}`,{method:'PATCH',body:{is_active:!c.is_active},retry:0,timeout:15000}))}
async function move(c:Category,dir:-1|1){
  const sorted=orderedRows.value,i=sorted.findIndex(row=>row.id===c.id),a=sorted[i],b=sorted[i+dir]
  if(!a||!b)return
  await run(data=>({...data,categories:data.categories.map(row=>row.id===a.id?{...row,sort_order:b.sort_order}:row.id===b.id?{...row,sort_order:a.sort_order}:row)}),()=>
    $fetch<unknown>('/api/admin/categories/reorder',{method:'POST',body:{first:a.id,second:b.id,first_order:a.sort_order,second_order:b.sort_order},retry:0,timeout:15000}))
}
function remove(c:Category){if(confirm(`Hapus kategori "${c.name}"?`))void run(data=>({...data,categories:data.categories.filter(row=>row.id!==c.id)}),()=> $fetch<unknown>(`/api/admin/crud/categories/${c.id}`,{method:'DELETE',retry:0,timeout:15000}))}
</script>

<template>
  <div>
    <DashboardDataStatus :updated-at="catalog.updatedAt.value" :loading="catalog.loading.value" :error="catalog.error.value" />
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Kategori</h1>
      <button class="btn btn-primary btn-sm" @click="form = { name: '' }; sheet = true"><Icon name="plus" :size="16" /> Tambah</button>
    </div>

    <div class="ops-card mt-5"><label>Cari kategori<input v-model="search" type="search" class="ops-input"></label></div>
    <p v-if="error||catalog.error.value" class="ops-alert" role="alert">{{ error||catalog.error.value }} <button @click="catalog.refresh()">Coba lagi</button></p>
    <p v-if="catalog.loading.value&&!catalog.data.value" role="status">Memuat kategori…</p>
    <div class="card mt-5 divide-y divide-brand-50" :inert="busy">
      <p v-if="!sortedRows.length" class="p-5">Tidak ada kategori yang cocok.</p>
      <div v-for="c in sortedRows" :key="c.id" class="flex items-center gap-2 px-4 py-3">
        <div class="flex flex-col">
          <button class="btn btn-ghost btn-sm !h-6 !px-1.5" :aria-label="`Naikkan ${c.name}`" :disabled="orderedRows[0]?.id === c.id" @click="move(c, -1)"><Icon name="chevron-up" :size="14" /></button>
          <button class="btn btn-ghost btn-sm !h-6 !px-1.5" :aria-label="`Turunkan ${c.name}`" :disabled="orderedRows[orderedRows.length - 1]?.id === c.id" @click="move(c, 1)"><Icon name="chevron-down" :size="14" /></button>
        </div>
        <div class="min-w-0 flex-1">
          <p class="font-medium">{{ c.name }}</p>
          <p class="text-xs text-brand-400">/{{ c.slug }}</p>
        </div>
        <button
          class="badge cursor-pointer"
          :class="c.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-500'"
          @click="toggleActive(c)"
        >
          {{ c.is_active ? 'Aktif' : 'Nonaktif' }}
        </button>
        <button class="btn btn-ghost btn-sm" :aria-label="`Edit ${c.name}`" @click="form = { id: c.id, name: c.name }; sheet = true"><Icon name="pencil" :size="15" /></button>
        <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus ${c.name}`" @click="remove(c)"><Icon name="trash" :size="15" /></button>
      </div>
    </div>

    <AppSheet :open="sheet" :title="form.id ? 'Edit Kategori' : 'Tambah Kategori'" @close="!busy && (sheet = false)">
      <p v-if="error" class="ops-alert" role="alert">{{ error }}</p>
      <div>
        <label class="label" for="cat-name">Nama</label>
        <input id="cat-name" v-model="form.name" class="input" maxlength="50" @keyup.enter="save">
        <button class="btn btn-primary mt-4 w-full" :disabled="busy" @click="save">{{ busy?'Menyimpan…':'Simpan' }}</button>
      </div>
    </AppSheet>
  </div>
</template>
