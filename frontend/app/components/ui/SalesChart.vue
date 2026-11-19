<script setup lang="ts">
import { money } from "#shared/operations";
import { shortDay, sharePercent, type SalesDay } from "#shared/dashboard";
const props = defineProps<{ days: SalesDay[] }>();
const emit = defineEmits<{ select: [date: string] }>();
const hovered = ref<number | null>(null);
const uid = useId().replace(/[^a-zA-Z0-9_-]/g, "");
const maximum = computed(() =>
  props.days.reduce(
    (max, d) => (BigInt(d.revenue) > max ? BigInt(d.revenue) : max),
    0n,
  ),
);
const points = computed(() =>
  props.days.map((d, i) => [
    props.days.length > 1 ? (i / (props.days.length - 1)) * 640 : 320,
    184 - sharePercent(d.revenue, String(maximum.value || 1n)) * 1.6,
  ]),
);
const path = computed(() =>
  points.value.map(([x, y], i) => `${i ? "L" : "M"} ${x} ${y}`).join(" "),
);
const selected = computed(
  () => props.days[hovered.value ?? props.days.length - 1],
);
watch(
  () => props.days,
  () => (hovered.value = null),
);
function move(event: PointerEvent) {
  const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
  if (rect.width)
    hovered.value = Math.max(
      0,
      Math.min(
        props.days.length - 1,
        Math.round(
          ((event.clientX - rect.left) / rect.width) * (props.days.length - 1),
        ),
      ),
    );
}
</script>
<template>
  <div v-if="days.length" class="tkm-sales-chart">
    <div class="tkm-chart-caption">
      <span>{{ selected ? shortDay(selected.date) : "" }}</span
      ><strong>{{ money(selected?.revenue || "0") }}</strong
      ><small>{{ selected?.count || 0 }} pesanan diteruskan</small>
    </div>
    <div
      class="tkm-chart-plot"
      role="img"
      :aria-label="
        'Grafik estimasi nilai self-order harian dari ' +
        days[0]?.date +
        ' sampai ' +
        days[days.length - 1]?.date
      "
      @pointermove="move"
      @pointerleave="hovered = null"
    >
      <svg viewBox="0 0 640 210" preserveAspectRatio="none" aria-hidden="true">
        <defs>
          <linearGradient :id="uid" x1="0" x2="0" y1="0" y2="1">
            <stop
              offset="0"
              stop-color="var(--dash-chart)"
              stop-opacity=".28"
            />
            <stop offset="1" stop-color="var(--dash-chart)" stop-opacity="0" />
          </linearGradient>
        </defs>
        <line
          v-for="y in [24, 104, 184]"
          :key="y"
          x1="0"
          x2="640"
          :y1="y"
          :y2="y"
          stroke="var(--dash-border)"
          stroke-dasharray="2 6"
        />
        <path
          :d="
            path +
            ' L ' +
            (points[points.length - 1]?.[0] || 640) +
            ' 210 L ' +
            (points[0]?.[0] || 0) +
            ' 210 Z'
          "
          :fill="`url(#${uid})`"
        />
        <path
          :d="path"
          fill="none"
          stroke="var(--dash-chart)"
          stroke-width="3"
          stroke-linecap="round"
          vector-effect="non-scaling-stroke"
        />
        <circle
          v-if="hovered !== null && points[hovered]"
          :cx="points[hovered]?.[0]"
          :cy="points[hovered]?.[1]"
          r="5"
          fill="var(--dash-chart)"
          stroke="var(--dash-card)"
          stroke-width="3"
        />
      </svg>
    </div>
    <div
      class="tkm-chart-bars"
      aria-label="Pilih tanggal untuk membuka laporan harian"
    >
      <button
        v-for="(day, index) in days"
        :key="day.date"
        type="button"
        :aria-label="
          shortDay(day.date) + ': ' + money(day.revenue) + ', buka laporan'
        "
        :title="shortDay(day.date) + ' · ' + money(day.revenue)"
        @focus="hovered = index"
        @blur="hovered = null"
        @click="emit('select', day.date)"
      >
        <span
          :style="{
            height:
              Math.max(6, sharePercent(day.revenue, String(maximum || 1n))) +
              '%',
          }"
        ></span>
      </button>
    </div>
    <div class="tkm-chart-axis" aria-hidden="true">
      <span>{{ shortDay(days[0]!.date) }}</span
      ><span>Pilih batang untuk rincian</span
      ><span>{{ shortDay(days[days.length - 1]!.date) }}</span>
    </div>
  </div>
</template>
