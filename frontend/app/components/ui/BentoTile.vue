<script setup lang="ts">
import { cn } from "~/lib/utils";
withDefaults(
  defineProps<{
    title?: string;
    tone?: "default" | "accent" | "lilac";
    class?: string;
  }>(),
  { tone: "default" },
);
</script>
<template>
  <section :class="cn('tkm-tile', 'tkm-tile-' + tone, $props.class)">
    <header v-if="title || $slots.action" class="tkm-tile-heading">
      <h2>{{ title }}</h2>
      <slot name="action" />
    </header>
    <slot />
  </section>
</template>
