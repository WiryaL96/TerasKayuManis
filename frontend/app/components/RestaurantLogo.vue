<script setup lang="ts">
withDefaults(defineProps<{size?:number;alt?:string;eager?:boolean}>(),{
 size:64,alt:'Logo Teras Kayu Manis',eager:false,
})
</script>
<template>
 <img class="restaurant-logo" src="/images/restaurant-logo.webp" :alt="alt" :width="size" :height="size" :loading="eager?'eager':'lazy'" decoding="async" :fetchpriority="eager?'high':'auto'">
</template>
<style scoped>
.restaurant-logo{display:inline-block;max-width:100%;height:auto;object-fit:contain;flex-shrink:0;vertical-align:middle}
</style>
