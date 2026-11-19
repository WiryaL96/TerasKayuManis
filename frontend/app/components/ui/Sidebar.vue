<script setup lang="ts">
import { cn } from "~/lib/utils";
export interface SidebarLink {
  id: string;
  label: string;
  icon: string;
  to?: string;
  group?: string;
  badge?: string | number;
  active?: boolean;
  disabled?: boolean;
}
const props = withDefaults(
  defineProps<{
    links: SidebarLink[];
    collapsed?: boolean;
    name?: string;
    role?: string;
    theme?: "light" | "dark";
    disabled?: boolean;
    label?: string;
  }>(),
  {
    collapsed: false,
    name: "",
    role: "",
    theme: "light",
    disabled: false,
    label: "Administrasi",
  },
);
const emit = defineEmits<{
  toggle: [];
  theme: [];
  logout: [];
  select: [id: string];
  prefetch: [to: string];
}>();
const navId = useId(),
  scrolling = ref(false);
let scrollTimer: ReturnType<typeof setTimeout> | undefined;
const groups = computed(() => [
  ...new Set(props.links.map((link) => link.group || "Ruang kerja")),
]);
const initials = computed(
  () =>
    props.name
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((p) => p[0])
      .join("")
      .toUpperCase() || "TK",
);
function onScroll() {
  scrolling.value = true;
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(() => (scrolling.value = false), 650);
}
onUnmounted(() => clearTimeout(scrollTimer));
</script>
<template>
  <aside
    class="tkm-sidebar"
    data-slot="sidebar"
    :data-collapsed="collapsed"
    :aria-label="label"
  >
    <header class="tkm-sidebar-header">
      <NuxtLink
        to="/"
        class="tkm-workspace-mark"
        :title="collapsed ? 'TerasKayuManis' : undefined"
        aria-label="TerasKayuManis · halaman pelanggan"
        ><RestaurantLogo class="tkm-logo-mark" :size="44" alt="" eager />
        <span v-show="!collapsed" class="tkm-workspace-name"
          >TerasKayuManis<small>Restaurant workspace</small></span
        ></NuxtLink
      >
      <button
        v-if="!collapsed"
        type="button"
        class="tkm-icon-button"
        aria-label="Ciutkan sidebar"
        :aria-controls="navId"
        :aria-expanded="true"
        @click="emit('toggle')"
      >
        <UiDashboardIcon name="collapse" />
      </button>
      <button
        v-else
        type="button"
        class="tkm-icon-button"
        aria-label="Perluas sidebar"
        :aria-controls="navId"
        :aria-expanded="false"
        @click="emit('toggle')"
      >
        <UiDashboardIcon name="expand" />
      </button>
    </header>
    <nav
      :id="navId"
      :aria-label="label"
      :class="cn('tkm-sidebar-nav', scrolling && 'is-scrolling')"
      @scroll.passive="onScroll"
    >
      <section
        v-for="group in groups"
        :key="group"
        class="tkm-sidebar-section"
        :aria-label="group"
      >
        <p class="tkm-sidebar-label" :aria-hidden="collapsed">
          {{ collapsed ? "·" : group }}
        </p>
        <template
          v-for="link in links.filter(
            (item) => (item.group || 'Ruang kerja') === group,
          )"
          :key="link.id"
        >
          <NuxtLink
            v-if="link.to && !disabled && !link.disabled"
            :to="link.to"
            :class="cn('tkm-sidebar-item', link.active && 'is-active')"
            :aria-current="link.active ? 'page' : undefined"
            :aria-label="link.label"
            :title="collapsed ? link.label : undefined"
            @pointerenter="emit('prefetch', link.to)"
            @focus="emit('prefetch', link.to)"
            ><UiDashboardIcon :name="link.icon" /><span
              v-show="!collapsed"
              class="tkm-sidebar-item-label"
              >{{ link.label }}</span
            ><span
              v-if="link.badge !== undefined && !collapsed"
              class="tkm-nav-badge"
              >{{ link.badge }}</span
            ></NuxtLink
          >
          <button
            v-else
            type="button"
            :disabled="disabled || link.disabled"
            :class="cn('tkm-sidebar-item', link.active && 'is-active')"
            :aria-pressed="!!link.active"
            :aria-label="link.label"
            :title="collapsed ? link.label : undefined"
            @click="emit('select', link.id)"
          >
            <UiDashboardIcon :name="link.icon" /><span
              v-show="!collapsed"
              class="tkm-sidebar-item-label"
              >{{ link.label }}</span
            ><span
              v-if="link.badge !== undefined && !collapsed"
              class="tkm-nav-badge"
              >{{ link.badge }}</span
            >
          </button>
        </template>
      </section>
    </nav>
    <footer class="tkm-sidebar-footer">
      <button
        type="button"
        class="tkm-sidebar-item tkm-theme-button"
        :aria-label="
          theme === 'dark' ? 'Gunakan tema terang' : 'Gunakan tema gelap'
        "
        :title="collapsed ? 'Ubah tema' : undefined"
        @click="emit('theme')"
      >
        <UiDashboardIcon :name="theme === 'dark' ? 'sun' : 'moon'" /><span
          v-show="!collapsed"
          >{{ theme === "dark" ? "Tema terang" : "Tema gelap" }}</span
        >
      </button>
      <div class="tkm-sidebar-profile">
        <span class="tkm-avatar" :title="name">{{ initials }}</span>
        <div v-show="!collapsed">
          <strong>{{ name || "Memuat akun…" }}</strong
          ><small>{{ role }}</small>
        </div>
      </div>
      <button
        type="button"
        class="tkm-sidebar-item tkm-logout"
        :disabled="disabled"
        aria-label="Keluar"
        :title="collapsed ? 'Keluar' : undefined"
        @click="emit('logout')"
      >
        <UiDashboardIcon name="logout" /><span v-show="!collapsed">Keluar</span>
      </button>
    </footer>
  </aside>
</template>
