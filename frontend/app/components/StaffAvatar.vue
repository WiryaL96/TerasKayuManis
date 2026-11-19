<script setup lang="ts">
const props=withDefaults(defineProps<{name:string;src?:string|null;size?:number}>(),{src:null,size:64})
const broken=ref(false)
watch(()=>props.src,()=>broken.value=false)
const initials=computed(()=>props.name.trim().split(/\s+/).filter(Boolean).filter((_,i,a)=>i===0||i===a.length-1).map(s=>s.slice(0,1)).join('').toLocaleUpperCase('id')||'?')
</script>
<template><span class="staff-avatar" :style="{width:size+'px',height:size+'px',fontSize:Math.round(size*.34)+'px'}" aria-hidden="true"><img v-if="src&&!broken" :src="src" alt="" loading="lazy" decoding="async" @error="broken=true"><span v-else>{{ initials }}</span></span></template>
<style scoped>.staff-avatar{display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;border-radius:50%;overflow:hidden;background:#e5ead7;color:#29372c;font-weight:750}.staff-avatar img{width:100%;height:100%;object-fit:cover}</style>
