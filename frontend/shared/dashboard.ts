import type { ReportData } from "./operations";
import type { StaffRole } from "./staff-roles";

export interface BackupStatus {
  result?: string;
  last_attempt?: string;
  last_success?: string;
  restore_verified_at?: string;
}
export interface DashboardData {
  role: StaffRole;
  period: { from: string; to: string };
  report: ReportData;
  queue: {
    pending: number;
    processing: number;
    orders: {
      id: string;
      order_number: string;
      customer_name: string | null;
      total: number;
      created_at: string;
      expires_at: string;
      status: string;
    }[];
  };
  catalog: {
    published: number;
    draft: number;
    hidden: number;
    missing_photo: number;
  };
  staff: {
    active: number;
    invited: number;
    disabled: number;
    active_cashiers: number;
  };
  operation: { orders_enabled: boolean; pricing_confirmed_at: string | null };
  backup?: BackupStatus;
  activity?: {
    id: string;
    actor_name: string | null;
    action: string;
    created_at: string;
  }[];
  generated_at: string;
}
export interface SalesDay {
  date: string;
  revenue: string;
  count: number;
}
export type DashboardRange = 7 | 14 | 30;

export function dashboardPeriod(days: DashboardRange, today: string) {
  const date = new Date(today + "T00:00:00Z");
  date.setUTCDate(date.getUTCDate() - days + 1);
  return { from: date.toISOString().slice(0, 10), to: today };
}
// Use the payment timestamp, rather than order creation time. BigInt keeps
// aggregation exact in rupiah; chart coordinates are only a visual projection.
export function dailySales(
  payments: ReportData["payments"],
  from: string,
  to: string,
): SalesDay[] {
  const days = new Map<string, { revenue: bigint; count: number }>();
  const first = new Date(from + "T00:00:00Z"),
    last = new Date(to + "T00:00:00Z");
  if (
    !Number.isFinite(+first) ||
    !Number.isFinite(+last) ||
    last < first ||
    +last - +first > 30 * 86400000
  )
    return [];
  for (let time = +first; time <= +last; time += 86400000)
    days.set(new Date(time).toISOString().slice(0, 10), {
      revenue: 0n,
      count: 0,
    });
  for (const payment of payments) {
    const time = new Date(payment.paid_at).getTime();
    if (!Number.isFinite(time)) continue;
    const date = new Date(time + 7 * 3600000).toISOString().slice(0, 10),
      day = days.get(date);
    if (day) {
      day.revenue += BigInt(payment.total);
      day.count++;
    }
  }
  return [...days].map(([date, day]) => ({
    date,
    revenue: String(day.revenue),
    count: day.count,
  }));
}
export function averageSale(revenue: string, count: number) {
  return count > 0 ? String(BigInt(revenue) / BigInt(count)) : "0";
}
// Handoff time is a manual operational event, not a POS payment timestamp.
export function dailyHandoffs(handoffs:NonNullable<ReportData['handoffs']>,from:string,to:string):SalesDay[]{
 const days=dailySales([],from,to),byDate=new Map(days.map(day=>[day.date,day]))
 for(const h of handoffs){const time=Date.parse(h.forwarded_at);if(!Number.isFinite(time))continue;const day=byDate.get(new Date(time+7*3600000).toISOString().slice(0,10));if(day){day.revenue=String(BigInt(day.revenue)+BigInt(h.total));day.count++}}
 return days
}
export function sharePercent(value: string | number, total: string | number) {
  const denominator = BigInt(total),
    numerator = BigInt(value);
  return denominator > 0n
    ? Number((numerator * 10000n) / denominator) / 100
    : 0;
}
export function shortDay(date: string) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    timeZone: "Asia/Jakarta",
  }).format(new Date(date + "T00:00:00Z"));
}
