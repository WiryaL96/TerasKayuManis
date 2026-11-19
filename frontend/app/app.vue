<template>
  <PreviewNotice v-if="useRuntimeConfig().public.previewDemo" />
  <DashboardBoundary><NuxtLayout>
    <NuxtPage />
  </NuxtLayout></DashboardBoundary>
</template>
