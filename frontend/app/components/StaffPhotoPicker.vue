<script setup lang="ts">
const props=withDefaults(defineProps<{name:string;src?:string|null;disabled?:boolean}>(),{src:null,disabled:false})
const emit=defineEmits<{uploaded:[path:string|null];uploading:[value:boolean]}>()
const error=ref(''),busy=ref(false),preview=ref(''),removed=ref(false)
let objectUrl='',controller:AbortController|undefined
function cleanup(){if(objectUrl)URL.revokeObjectURL(objectUrl);objectUrl=''}
async function upload(event:Event){
 const input=event.target as HTMLInputElement,file=input.files?.[0];if(!file||busy.value||props.disabled)return
 error.value=''
 if(file.size>2*1024*1024){error.value='Foto maksimal 2 MB.';input.value='';return}
 busy.value=true;emit('uploading',true);controller=new AbortController()
 try{
  const body=new FormData();body.set('file',file)
  const result=await $fetch<{path:string}>('/api/admin/staff-photo',{method:'POST',body,signal:controller.signal,retry:0,timeout:25000})
  if(!result.path||!/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.webp$/.test(result.path))throw Error('Invalid path')
  cleanup();removed.value=false;objectUrl=URL.createObjectURL(file);preview.value=objectUrl;emit('uploaded',result.path)
 }catch(e:any){if(!controller?.signal.aborted)error.value=e.data?.statusMessage||'Foto belum terunggah. Pilih ulang untuk mencoba lagi.'}
 finally{busy.value=false;emit('uploading',false);input.value=''}
}
function remove(){cleanup();removed.value=true;preview.value='';emit('uploaded',null)}
onUnmounted(()=>{controller?.abort();cleanup()})
</script>
<template><div class="staff-photo-picker"><StaffAvatar :name="name||'Staf'" :src="removed?null:preview||src" :size="72"/><div><label>Foto staf (opsional)<input type="file" accept="image/jpeg,image/png,image/webp" :disabled="busy||disabled" @change="upload"></label><small>JPG, PNG, atau WebP, maksimal 2 MB. Tanpa foto memakai inisial.</small><p v-if="busy" role="status">Mengunggah foto…</p><p v-if="error" class="ops-alert" role="alert">{{ error }}</p><button v-if="!removed&&(preview||src)" type="button" class="ops-button secondary" :disabled="busy||disabled" @click="remove">Hapus foto</button></div></div></template>
<style scoped>.staff-photo-picker{display:flex;gap:20px;align-items:flex-start}.staff-photo-picker>div{min-width:0;flex:1}.staff-photo-picker input{max-width:100%;font-size:14px}.staff-photo-picker small{display:block;margin-top:8px;color:#697562}</style>
