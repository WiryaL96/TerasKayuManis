<script setup lang="ts">
const props = withDefaults(defineProps<{ src?: string | null; alt: string; logo?: boolean; eager?: boolean }>(), { logo: false, eager: false })
const failed = ref(false)
watch(() => props.src, () => { failed.value = false })
</script>

<template>
  <div class="customer-image" :class="{ 'customer-logo': logo }">
    <RestaurantLogo v-if="logo" :alt="alt" :eager="eager" :size="120" />
    <img v-else-if="src && !failed" :src="src" :alt="alt" :loading="eager ? 'eager' : 'lazy'" @error="failed = true">
    <div v-else class="customer-placeholder" role="img" :aria-label="`Foto ${alt} belum tersedia`">
      <Icon name="image" :size="30" /><span>Foto belum tersedia</span>
    </div>
  </div>
</template>
