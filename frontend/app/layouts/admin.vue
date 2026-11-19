<script setup lang="ts">
import { STAFF_ROLE_LABELS } from '#shared/staff-roles'
const { me, load, logout, can } = useAdmin()
const route = useRoute()
const prefetch = useDashboardPrefetch()
const { collapsed, theme, toggleCollapsed, toggleTheme } = useDashboardPreferences()
let request = 0
function refreshIdentity() {
  const seq = ++request
  if (route.path === '/admin/login') return
  load().catch(() => {
    if (seq === request && route.path !== '/admin/login') navigateTo('/admin/login')
  })
}
onMounted(refreshIdentity)
// Nuxt keeps this layout mounted while navigating from /admin/login to /admin.
watch(() => route.path, refreshIdentity)
onUnmounted(() => { request++ })
const links = [
  {
    to: '/admin',
    label: 'Dashboard',
    roles: ['superadmin', 'admin'] as const,
  },
  {
    to: '/admin/reports',
    label: 'Laporan',
    roles: ['superadmin', 'admin'] as const,
  },
  {
    to: '/cashier',
    label: 'Buka kasir',
    roles: ['superadmin', 'admin'] as const,
  },
  { to: '/admin/staff', label: 'Staf', roles: ['superadmin', 'admin'] as const },
  { to: '/admin/activity', label: 'Log aktivitas', roles: ['superadmin'] as const },
  {
    to: '/admin/products',
    label: 'Produk',
    roles: ['superadmin', 'admin'] as const,
  },
  {
    to: '/admin/categories',
    label: 'Kategori',
    roles: ['superadmin', 'admin'] as const,
  },
  {
    to: '/admin/addons',
    label: 'Add-on',
    roles: ['superadmin', 'admin'] as const,
  },
  {
    to: '/admin/settings',
    label: 'Pengaturan',
    roles: ['superadmin'] as const,
  },
]
const sidebarLinks = computed(() => links.filter(link => can([...link.roles])).map(link => ({
  id: link.to, to: link.to, label: link.label,
  icon: ({ '/admin': 'dashboard', '/admin/reports': 'chart', '/cashier': 'orders', '/admin/staff': 'users', '/admin/activity': 'activity', '/admin/products': 'utensils', '/admin/categories': 'package', '/admin/addons': 'bag', '/admin/settings': 'settings' } as Record<string, string>)[link.to] || 'dashboard',
  group: ['/admin/products', '/admin/categories', '/admin/addons'].includes(link.to) ? 'Katalog' : ['/admin/activity', '/admin/settings'].includes(link.to) ? 'Kontrol restoran' : 'Ruang kerja',
  active: route.path.replace(/\/$/, '') === link.to,
})))
</script>
<template>
  <slot v-if="route.path === '/admin/login'" />
  <div v-else class="ops-shell tkm-dashboard" :data-dashboard-theme="theme" :data-sidebar-collapsed="collapsed">
    <UiSidebar :links="sidebarLinks" :collapsed="collapsed" :theme="theme" :name="me?.profile.full_name || me?.email" :role="me ? STAFF_ROLE_LABELS[me.profile.role] : ''" @toggle="toggleCollapsed" @theme="toggleTheme" @logout="logout" @prefetch="prefetch" />
    <main class="ops-main"><DashboardBoundary><slot /></DashboardBoundary></main>
  </div>
</template>
