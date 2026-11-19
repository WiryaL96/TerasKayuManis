<script setup lang="ts">
defineProps<{updatedAt?:number;loading?:boolean;error?:string}>()
const time=(value:number)=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(new Date(value))
</script>
<template><p v-if="updatedAt" class="ops-data-status" role="status">Data terakhir {{ time(updatedAt) }} WIB<span v-if="loading"> · Memperbarui…</span><span v-else-if="error"> · Menampilkan data tersimpan; perubahan perlu koneksi.</span></p></template>
