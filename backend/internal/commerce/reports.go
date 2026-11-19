package commerce

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
)

type reportFilter struct {
	From, To time.Time
	Cashier  string
}

func parseReportFilter(r *http.Request) (reportFilter, error) {
	loc := time.FixedZone("Asia/Jakarta", 7*3600)
	today := time.Now().In(loc).Format("2006-01-02")
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" {
		from = today
	}
	if to == "" {
		to = from
	}
	a, err := time.ParseInLocation("2006-01-02", from, loc)
	if err != nil {
		return reportFilter{}, fmt.Errorf("Invalid date")
	}
	b, err := time.ParseInLocation("2006-01-02", to, loc)
	if err != nil || b.Before(a) || b.Sub(a) > 30*24*time.Hour {
		return reportFilter{}, fmt.Errorf("Date range must be 1–31 days")
	}
	id := r.URL.Query().Get("cashier")
	if id != "" && !uuidText.MatchString(id) {
		return reportFilter{}, fmt.Errorf("Invalid cashier")
	}
	return reportFilter{a, b.AddDate(0, 0, 1), id}, nil
}
func (a *API) reportingStaff(w http.ResponseWriter, r *http.Request) bool {
	id, err := a.staff(r)
	if err != nil {
		writeError(w, 401, "Staff login required")
		return false
	}
	var allowed bool
	if a.DB.QueryRow(r.Context(), `select role in ('superadmin','admin') from public.profiles where id=$1`, id).Scan(&allowed) != nil || !allowed {
		writeError(w, 403, "Reporting access required")
		return false
	}
	return true
}

const reportSQL = `with selected_payments as (select * from public.payments where created_at >= $1 and created_at < $2 and ($3='' or cashier_id::text=$3) order by created_at desc,id limit 10001),
 selected_handoffs as (select h.*,o.order_number,o.customer_name,o.total from public.order_pos_handoffs h join public.orders o on o.id=h.order_id where h.forwarded_at >= $1 and h.forwarded_at < $2 and ($3='' or h.cashier_id::text=$3) order by h.forwarded_at desc,h.order_id limit 10001)
select jsonb_build_object(
 'handoffs',coalesce((select jsonb_agg(jsonb_build_object('order_id',h.order_id,'order_number',h.order_number,'customer_name',h.customer_name,'forwarded_at',h.forwarded_at,'cashier_id',h.cashier_id,'cashier_name',h.cashier_name,'pos_reference',h.pos_reference,'total',h.total) order by h.forwarded_at desc,h.order_id) from selected_handoffs h),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('order_id',p.order_id,'order_number',o.order_number,'customer_name',o.customer_name,'paid_at',p.created_at,'cashier_id',p.cashier_id,'cashier_name',p.cashier_name,'subtotal',o.subtotal,'service',o.service_charge,'tax',o.tax,'total',p.amount_rp,'received',p.received_rp,'change',p.change_rp) order by p.created_at desc,p.id) from selected_payments p join public.orders o on o.id=p.order_id),'[]'::jsonb),
 'counts',coalesce((select jsonb_object_agg(status,n) from (select status,count(*) n from public.orders where created_at >= $1 and created_at < $2 group by status) c),'{}'::jsonb),
 'active_total',(select count(*) from public.orders where status in ('pending','pos_input','confirmed')),
 'today_total',(select count(*) from public.orders where created_at >= $1 and created_at < $2),
 'popular',coalesce((select jsonb_agg(to_jsonb(p)) from (select i.product_name as name,sum(i.quantity) as qty from public.order_items i join selected_payments pay on pay.order_id=i.order_id group by i.product_name order by qty desc,i.product_name limit 5) p),'[]'::jsonb))`

type reportPayment struct {
	OrderID     string    `json:"order_id"`
	Number      string    `json:"order_number"`
	Customer    *string   `json:"customer_name"`
	PaidAt      time.Time `json:"paid_at"`
	CashierID   string    `json:"cashier_id"`
	CashierName *string   `json:"cashier_name"`
	Total       int64     `json:"total"`
	Received    int64     `json:"received"`
	Change      int64     `json:"change"`
}

func csvText(s string) string {
	trim := strings.TrimLeft(s, " \t\r\n")
	if trim != "" && strings.ContainsAny(trim[:1], "=+-@") {
		return "'" + s
	}
	return s
}
func (a *API) reports(w http.ResponseWriter, r *http.Request) {
	if !a.reportingStaff(w, r) {
		return
	}
	f, err := parseReportFilter(r)
	if err != nil {
		writeError(w, 400, err.Error())
		return
	}
	if r.URL.Query().Get("paged") == "1" {
		a.pagedReport(w, r, f)
		return
	}
	var raw []byte
	if err = a.DB.QueryRow(r.Context(), reportSQL, f.From, f.To, f.Cashier).Scan(&raw); err != nil {
		dbError(w, err)
		return
	}
	var result struct {
		Payments []reportPayment   `json:"payments"`
		Handoffs []json.RawMessage `json:"handoffs"`
	}
	if json.Unmarshal(raw, &result) != nil {
		writeError(w, 503, "Report unavailable")
		return
	}
	if len(result.Payments) > 10000 || len(result.Handoffs) > 10000 {
		writeError(w, 422, "Terlalu banyak transaksi. Persempit tanggal atau pilih kasir.")
		return
	}
	if len(raw) > 3*1024*1024 {
		writeError(w, 422, "Laporan terlalu besar. Persempit rentang tanggal atau pilih kasir.")
		return
	}
	if r.URL.Query().Get("format") != "csv" {
		var body map[string]any
		if json.Unmarshal(raw, &body) != nil {
			writeError(w, 503, "Report unavailable")
			return
		}
		body["summary"], body["by_cashier"] = summarizePayments(result.Payments)
		_ = json.NewEncoder(w).Encode(body)
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="teraskayumanis-payments.csv"`)
	out := csv.NewWriter(w)
	_ = out.Write([]string{"Pesanan", "Pelanggan", "Waktu bayar (WIB)", "Kasir", "Total", "Uang diterima", "Kembalian"})
	loc := time.FixedZone("Asia/Jakarta", 7*3600)
	for _, p := range result.Payments {
		customer, name := "", "Nama kasir belum tercatat"
		if p.Customer != nil {
			customer = *p.Customer
		}
		if p.CashierName != nil {
			name = *p.CashierName
		}
		_ = out.Write([]string{csvText(p.Number), csvText(customer), p.PaidAt.In(loc).Format("2006-01-02 15:04:05"), csvText(name), fmt.Sprint(p.Total), fmt.Sprint(p.Received), fmt.Sprint(p.Change)})
	}
	out.Flush()
}

type cashierSummary struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Count   int    `json:"count"`
	Revenue string `json:"revenue"`
}

func summarizePayments(payments []reportPayment) (map[string]any, []cashierSummary) {
	var total, received, change int64
	groups := map[string]*cashierSummary{}
	sums := map[string]int64{}
	for _, p := range payments {
		total += p.Total
		received += p.Received
		change += p.Change
		name := "Nama kasir belum tercatat"
		if p.CashierName != nil && strings.TrimSpace(*p.CashierName) != "" {
			name = *p.CashierName
		}
		key := p.CashierID + "\x00" + name
		if groups[key] == nil {
			groups[key] = &cashierSummary{ID: p.CashierID, Name: name}
		}
		groups[key].Count++
		sums[key] += p.Total
	}
	rows := make([]cashierSummary, 0, len(groups))
	for key, g := range groups {
		g.Revenue = fmt.Sprint(sums[key])
		rows = append(rows, *g)
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Name == rows[j].Name {
			return rows[i].ID < rows[j].ID
		}
		return rows[i].Name < rows[j].Name
	})
	return map[string]any{"count": len(payments), "revenue": fmt.Sprint(total), "received": fmt.Sprint(received), "change": fmt.Sprint(change)}, rows
}
