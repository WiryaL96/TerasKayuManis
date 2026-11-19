<script setup lang="ts">
import {
  Activity,
  ArrowDownToLine,
  ArrowUpRight,
  Banknote,
  ChartNoAxesCombined,
  Check,
  ChevronRight,
  Clock,
  Database,
  History,
  LayoutDashboard,
  ListChecks,
  LogOut,
  Moon,
  Package,
  PanelLeftClose,
  PanelLeftOpen,
  RefreshCw,
  Settings2,
  ShieldCheck,
  ShoppingBag,
  SlidersHorizontal,
  Sun,
  Users,
  Utensils,
  CircleAlert,
  Store,
} from "@lucide/vue";
withDefaults(defineProps<{ name: string; size?: number }>(), { size: 20 });
const icons = {
  activity: Activity,
  download: ArrowDownToLine,
  arrow: ArrowUpRight,
  cash: Banknote,
  chart: ChartNoAxesCombined,
  check: Check,
  chevron: ChevronRight,
  clock: Clock,
  database: Database,
  history: History,
  dashboard: LayoutDashboard,
  orders: ListChecks,
  logout: LogOut,
  moon: Moon,
  package: Package,
  collapse: PanelLeftClose,
  expand: PanelLeftOpen,
  refresh: RefreshCw,
  settings: Settings2,
  shield: ShieldCheck,
  bag: ShoppingBag,
  filter: SlidersHorizontal,
  sun: Sun,
  users: Users,
  utensils: Utensils,
  alert: CircleAlert,
  store: Store,
};
</script>
<template>
  <component
    :is="icons[name as keyof typeof icons] || icons.dashboard"
    :size="size"
    :stroke-width="1.8"
    aria-hidden="true"
    focusable="false"
  />
</template>
