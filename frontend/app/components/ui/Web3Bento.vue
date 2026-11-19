<script setup lang="ts">
// The supplied Web3 layout adapted to actual restaurant operations.
import {
  dailyHandoffs,
  averageSale,
  sharePercent,
  shortDay,
  type DashboardData,
} from "#shared/dashboard";
import { money, wibTime } from "#shared/operations";
import { posReportCSV, summarizeHandoffs } from '#shared/dashboard-data';
import { AUDIT_ACTIONS } from "#shared/staff-audit";
const props = defineProps<{ data: DashboardData }>();
const posSummary=computed(()=>summarizeHandoffs(props.data.report))
const days = computed(() =>
  props.data.report.daily_handoffs??dailyHandoffs(
    props.data.report.handoffs??[],
    props.data.period.from,
    props.data.period.to,
  ),
);
const reportHref = (date?: string, cashier?: string) =>
  "/admin/reports?" +
  new URLSearchParams({
    from: date || props.data.period.from,
    to: date || props.data.period.to,
    ...(cashier ? { cashier } : {}),
  });
const cashierHref = (order: DashboardData["queue"]["orders"][number]) =>
  "/cashier?" +
  new URLSearchParams({
    tab: "active",
    status: "pending",
    q: order.order_number,
    order: order.id,
  });
const csv=computed(()=>props.data.report.pos_summary?reportHref():'data:text/csv;charset=utf-8,'+encodeURIComponent(posReportCSV(props.data.report)));
const today = computed(() => days.value[days.value.length - 1]);
const average = computed(() =>
  averageSale(
    posSummary.value.total,
    posSummary.value.count,
  ),
);
const cashiers = computed(() =>
  posSummary.value.by_cashier.map(c=>({...c,revenue:c.total})).sort((a, b) =>
    BigInt(a.revenue) === BigInt(b.revenue)
      ? a.name.localeCompare(b.name)
      : BigInt(a.revenue) > BigInt(b.revenue)
        ? -1
        : 1,
  ),
);
const statuses = [
  { key: "pending", label: "Menunggu kasir", color: "var(--dash-amber)" },
  { key: "pos_input", label: "Ditangani kasir", color: "var(--dash-lilac-ink)" },
  { key: "forwarded", label: "Masuk aplikasi kasir", color: "var(--dash-chart)" },
  { key: "expired", label: "Kedaluwarsa", color: "var(--dash-muted)" },
  { key: "cancelled", label: "Dibatalkan", color: "var(--dash-danger)" },
];
const hasBackupProof = computed(
  () =>
    props.data.backup?.result === "Berhasil" &&
    !!props.data.backup.last_success,
);
function safeTime(value?: string | null) {
  return value && Number.isFinite(Date.parse(value))
    ? wibTime(value)
    : "Belum tercatat";
}
</script>
<template>
  <div class="tkm-bento-grid" aria-label="Ringkasan restoran">
    <UiBentoTile class="tkm-hero-tile">
      <div class="tkm-tile-heading">
        <span class="tkm-eyebrow">Self-order</span
        ><span class="tkm-status-dot"><i></i>Konfirmasi manual POS</span>
      </div>
      <p class="tkm-muted">Konfirmasi input manual. Pendapatan dan struk resmi mengikuti aplikasi kasir restoran.</p>
      <p class="tkm-hero-label">Estimasi nilai pesanan diteruskan</p>
      <p class="tkm-hero-value" data-testid="dashboard-revenue">
        {{ money(posSummary.total) }}
      </p>
      <p class="tkm-muted">
        {{ shortDay(data.period.from) }} – {{ shortDay(data.period.to) }} ·
        waktu konfirmasi input POS (WIB)
      </p>
      <div class="tkm-hero-bottom">
        <div>
          <span>Hari ini</span
          ><strong>{{ money(today?.revenue || "0") }}</strong>
        </div>
        <div>
          <span>Rata-rata nilai pesanan</span><strong>{{ money(average) }}</strong>
        </div>
        <a
          :href="csv"
          class="tkm-round-action"
          :download="data.report.pos_summary?undefined:'teraskayumanis-self-orders.csv'"
          :aria-label="data.report.pos_summary?'Buka laporan dan ekspor CSV':'Ekspor CSV periode dashboard'"
          :title="data.report.pos_summary?'Buka laporan dan ekspor CSV':'Ekspor CSV'"
          ><UiDashboardIcon name="download"
        /></a>
      </div>
    </UiBentoTile>
    <UiBentoTile title="Pesanan diteruskan" class="tkm-payment-tile"
      ><template #action
        ><span class="tkm-tile-icon"><UiDashboardIcon name="cash" /></span
      ></template>
      <p class="tkm-large-number">{{ posSummary.count }}</p>
      <p class="tkm-muted">pesanan dikonfirmasi masuk aplikasi kasir</p>
      <dl class="tkm-mini-lines">
        <div>
          <dt>Estimasi nilai pesanan</dt>
          <dd>{{ money(posSummary.total) }}</dd>
        </div>
        <div>
          <dt>Jumlah pesanan</dt>
          <dd>{{ posSummary.count }}</dd>
        </div>
      </dl>
      <NuxtLink :to="reportHref()" class="tkm-text-link"
        >Rincian self-order<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
    ></UiBentoTile>
    <UiBentoTile title="Antrean saat ini" tone="lilac" class="tkm-live-tile"
      ><template #action><UiDashboardIcon name="orders" /></template>
      <p class="tkm-large-number">
        {{ data.queue.pending + data.queue.processing }}
      </p>
      <p>pesanan aktif</p>
      <div class="tkm-queue-split">
        <NuxtLink to="/cashier?tab=active&status=pending"
          ><strong>{{ data.queue.pending }}</strong
          ><span>Menunggu kasir</span></NuxtLink
        ><NuxtLink to="/cashier?tab=active&status=pos_input"
          ><strong>{{ data.queue.processing }}</strong
          ><span>Ditangani kasir</span></NuxtLink
        >
      </div>
      <NuxtLink to="/cashier" class="tkm-text-link"
        >Buka antrean kasir<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
    ></UiBentoTile>
    <UiBentoTile title="Tren nilai self-order" class="tkm-chart-tile"
      ><template #action
        ><span class="tkm-legend-dot">Estimasi · IDR</span></template
      ><UiSalesChart :days="days" @select="navigateTo(reportHref($event))" />
      <p v-if="!posSummary.count" class="tkm-empty-note">
        Belum ada konfirmasi input ke aplikasi kasir pada periode ini.
      </p></UiBentoTile
    >
    <UiBentoTile title="Katalog menu" class="tkm-catalog-tile"
      ><template #action><UiDashboardIcon name="utensils" /></template>
      <p class="tkm-large-number">
        {{ data.catalog.published }}<span> menu</span>
      </p>
      <p class="tkm-muted">tersedia untuk pelanggan</p>
      <div class="tkm-segment-bar" aria-hidden="true">
        <span
          v-for="(count, i) in [
            data.catalog.published,
            data.catalog.draft,
            data.catalog.hidden,
          ]"
          :key="i"
          :style="{
            flexGrow: count || 0.02,
            background: [
              'var(--dash-chart)',
              'var(--dash-amber)',
              'var(--dash-border)',
            ][i],
          }"
        ></span>
      </div>
      <dl class="tkm-mini-lines">
        <div>
          <dt>Harga belum dikonfirmasi</dt>
          <dd>{{ data.catalog.draft }}</dd>
        </div>
        <div>
          <dt>Disembunyikan</dt>
          <dd>{{ data.catalog.hidden }}</dd>
        </div>
        <div>
          <dt>Menu tersedia tanpa foto</dt>
          <dd>{{ data.catalog.missing_photo }}</dd>
        </div>
      </dl>
      <NuxtLink to="/admin/products" class="tkm-text-link"
        >Kelola katalog<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
    ></UiBentoTile>
    <UiBentoTile title="Tim restoran" tone="accent" class="tkm-team-tile"
      ><template #action><UiDashboardIcon name="users" /></template>
      <p class="tkm-large-number">
        {{ data.staff.active_cashiers }}<span> kasir aktif</span>
      </p>
      <p>Setiap penanganan pesanan tercatat atas nama kasir.</p>
      <div class="tkm-team-status">
        <div>
          <span>Pengaturan belum selesai</span
          ><strong>{{ data.staff.invited }}</strong>
        </div>
        <div>
          <span>Akun nonaktif</span><strong>{{ data.staff.disabled }}</strong>
        </div>
      </div>
      <p class="tkm-team-scope">
        {{
          data.role === "superadmin"
            ? "Cakupan akun admin dan kasir."
            : "Cakupan akun kasir yang Anda kelola."
        }}
      </p>
      <NuxtLink to="/admin/staff" class="tkm-dark-button"
        >Kelola staf<UiDashboardIcon name="arrow" :size="17" /></NuxtLink
    ></UiBentoTile>
    <UiBentoTile title="Menu populer dari transaksi web lama" class="tkm-popular-tile"
      ><ol class="tkm-ranking">
        <li v-for="(product, index) in data.report.popular" :key="product.name">
          <span class="tkm-rank-number">{{ index + 1 }}</span
          ><span>{{ product.name }}</span
          ><strong>{{ product.qty }}×</strong>
        </li>
      </ol>
      <p v-if="!data.report.popular.length" class="tkm-empty-note">
        Belum ada menu yang dibayar pada periode ini.
      </p>
      <p class="tkm-footnote">
        Berdasarkan jumlah item pada pembayaran berhasil.
      </p></UiBentoTile
    >
    <UiBentoTile title="Status operasional" class="tkm-operation-tile"
      ><template #action><UiDashboardIcon name="store" /></template
      ><span
        class="tkm-operation-badge"
        :class="{ paused: !data.operation.orders_enabled }"
        >{{
          data.operation.orders_enabled ? "Pesanan dibuka" : "Pesanan dijeda"
        }}</span
      >
      <p class="tkm-muted">
        {{
          data.operation.pricing_confirmed_at
            ? "Tarif sudah dikonfirmasi."
            : "Tarif memerlukan konfirmasi superadmin."
        }}
      </p>
      <template v-if="data.role === 'superadmin'"
        ><div class="tkm-backup-line">
          <UiDashboardIcon name="database" :size="18" /><span
            >Backup terakhir<strong>{{
              hasBackupProof
                ? safeTime(data.backup?.last_success)
                : data.backup?.result || "Belum dikonfigurasi"
            }}</strong></span
          >
        </div>
        <p class="tkm-footnote">
          {{
            data.backup?.restore_verified_at
              ? "Uji pemulihan: " + safeTime(data.backup.restore_verified_at)
              : "Uji pemulihan belum terverifikasi."
          }}
        </p>
        <NuxtLink to="/admin/settings" class="tkm-text-link"
          >Pengaturan & backup<UiDashboardIcon
            name="arrow"
            :size="16" /></NuxtLink
      ></template>
      <p v-else class="tkm-footnote">
        Hubungi superadmin untuk mengubah tarif atau penerimaan pesanan.
      </p></UiBentoTile
    >
    <UiBentoTile title="Prioritas pelanggan ke kasir" class="tkm-wide-tile"
      ><template #action
        ><NuxtLink
          to="/cashier?tab=active&status=pending&sort=oldest"
          class="tkm-text-link"
          >Lihat semua<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
      ></template>
      <ul class="tkm-queue-preview">
        <li v-for="order in data.queue.orders" :key="order.id">
          <NuxtLink :to="cashierHref(order)"
            ><span class="tkm-queue-avatar"><UiDashboardIcon name="bag" /></span
            ><span
              ><strong
                >{{ order.order_number }} ·
                {{ order.customer_name || "Pelanggan" }}</strong
              ><small>Batas {{ safeTime(order.expires_at) }}</small></span
            ><b>{{ money(order.total) }}</b
            ><UiDashboardIcon name="chevron" :size="16"
          /></NuxtLink>
        </li>
      </ul>
      <p v-if="!data.queue.orders.length" class="tkm-empty-note">
        Semua antrean pelanggan sudah ditangani.
      </p>
      <p class="tkm-footnote">
        Lima pesanan dengan batas konfirmasi ke kasir terdekat, dari seluruh antrean
        aktif.
      </p></UiBentoTile
    >
    <UiBentoTile title="Penanganan per kasir" class="tkm-wide-tile"
      ><template #action><UiDashboardIcon name="chart" /></template>
      <ul class="tkm-cashier-allocation">
        <li
          v-for="(cashier, index) in cashiers.slice(0, 5)"
          :key="cashier.id + cashier.name"
        >
          <NuxtLink :to="reportHref(undefined, cashier.id)"
            ><div>
              <span>{{ cashier.name }}</span
              ><strong>{{ money(cashier.revenue) }}</strong>
            </div>
            <span class="tkm-allocation-track"
              ><i
                :style="{
                  width:
                    sharePercent(cashier.revenue, posSummary.total) +
                    '%',
                  background: [
                    'var(--dash-chart)',
                    'var(--dash-lilac-ink)',
                    'var(--dash-amber)',
                  ][index % 3],
                }"
              ></i></span
            ><small
              >{{ cashier.count }} pesanan ·
              {{
                sharePercent(cashier.revenue, posSummary.total)
              }}%</small
            ></NuxtLink
          >
        </li>
      </ul>
      <p v-if="!cashiers.length" class="tkm-empty-note">
        Belum ada pesanan diteruskan pada periode ini.
      </p>
      <p class="tkm-footnote">
        Nama mengikuti catatan saat penanganan. Pilih kasir untuk melihat
        laporan.
      </p></UiBentoTile
    >
    <UiBentoTile title="Pesanan masuk POS terbaru" class="tkm-wide-tile"
      ><template #action
        ><NuxtLink :to="reportHref()" class="tkm-text-link"
          >Laporan<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
      ></template>
      <ul class="tkm-payment-preview">
        <li
          v-for="payment in (data.report.handoffs??[]).slice(0, 4)"
          :key="payment.order_id"
        >
          <NuxtLink :to="{path:'/cashier',query:{tab:'history',status:'forwarded',q:payment.order_number,order:payment.order_id}}"
            ><span class="tkm-queue-avatar"
              ><UiDashboardIcon name="check" /></span
            ><span
              ><strong>{{ payment.order_number }}</strong
              ><small
                >{{ payment.cashier_name || "Nama kasir belum tercatat" }} ·
                {{ safeTime(payment.forwarded_at) }}</small
              ></span
            ><b>{{ money(payment.total) }}</b
            ><UiDashboardIcon name="chevron" :size="16"
          /></NuxtLink>
        </li>
      </ul>
      <p v-if="!data.report.handoffs?.length" class="tkm-empty-note">
        Belum ada konfirmasi input POS untuk ditampilkan.
      </p></UiBentoTile
    >
    <UiBentoTile
      v-if="data.role === 'superadmin'"
      title="Aktivitas staf"
      class="tkm-wide-tile"
      ><template #action
        ><NuxtLink to="/admin/activity" class="tkm-text-link"
          >Buka log<UiDashboardIcon name="arrow" :size="16" /></NuxtLink
      ></template>
      <ul class="tkm-activity-preview">
        <li v-for="entry in data.activity" :key="entry.id">
          <span class="tkm-activity-dot"></span>
          <div>
            <strong>{{
              AUDIT_ACTIONS[entry.action as keyof typeof AUDIT_ACTIONS] ||
              "Aktivitas staf"
            }}</strong>
            <p>{{ entry.actor_name || "Nama belum tercatat" }}</p>
            <small>{{ safeTime(entry.created_at) }}</small>
          </div>
        </li>
      </ul>
      <p v-if="!data.activity?.length" class="tkm-empty-note">
        Belum ada aktivitas staf tercatat.
      </p></UiBentoTile
    >
    <UiBentoTile v-else title="Pesanan dalam periode" class="tkm-wide-tile"
      ><div class="tkm-segment-bar" aria-hidden="true">
        <span
          v-for="status in statuses"
          :key="status.key"
          :style="{
            flexGrow: data.report.counts[status.key] || 0.02,
            background: status.color,
          }"
        ></span>
      </div>
      <dl class="tkm-order-status-grid">
        <div v-for="status in statuses" :key="status.key">
          <dt>
            <i :style="{ background: status.color }"></i>{{ status.label }}
          </dt>
          <dd>{{ data.report.counts[status.key] || 0 }}</dd>
        </div>
      </dl>
      <p class="tkm-footnote">
        {{ data.report.today_total }} pesanan dibuat dalam periode. Waktu
        pembuatan pesanan berbeda dari waktu konfirmasi input POS.
      </p></UiBentoTile
    >
  </div>
</template>
