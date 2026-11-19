package commerce

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const reportTotalsSQL = `with paid as(select * from public.payments where created_at >= $1 and created_at < $2 and ($3='' or cashier_id::text=$3)),
 handed as(select h.*,o.total from public.order_pos_handoffs h join public.orders o on o.id=h.order_id where h.forwarded_at >= $1 and h.forwarded_at < $2 and ($3='' or h.cashier_id::text=$3))
 select jsonb_build_object('summary',(select jsonb_build_object('count',count(*),'revenue',coalesce(sum(amount_rp),0)::text,'received',coalesce(sum(received_rp),0)::text,'change',coalesce(sum(change_rp),0)::text) from paid),
 'by_cashier',coalesce((select jsonb_agg(to_jsonb(x)) from(select cashier_id id,coalesce(cashier_name,'Nama kasir belum tercatat') name,count(*) count,sum(amount_rp)::text revenue from paid group by cashier_id,cashier_name order by cashier_name,cashier_id)x),'[]'::jsonb),
 'pos_summary',jsonb_build_object('count',(select count(*) from handed),'total',(select coalesce(sum(total),0)::text from handed),'by_cashier',coalesce((select jsonb_agg(to_jsonb(x)) from(select cashier_id id,cashier_name name,count(*) count,sum(total)::text total from handed group by cashier_id,cashier_name order by cashier_name,cashier_id)x),'[]'::jsonb)))`

func (a *API) pagedReport(w http.ResponseWriter, r *http.Request, f reportFilter) {
	offset, err := strconv.Atoi(r.URL.Query().Get("offset"))
	if err != nil || offset < 0 || offset > 1000000 || offset%500 != 0 {
		writeError(w, 400, "Invalid report offset")
		return
	}
	asOf := time.Now().UTC()
	if raw := r.URL.Query().Get("as_of"); raw != "" {
		asOf, err = time.Parse(time.RFC3339Nano, raw)
		if err != nil || asOf.After(time.Now().Add(time.Second)) {
			writeError(w, 400, "Invalid report snapshot")
			return
		}
	}
	if f.To.After(asOf) {
		f.To = asOf
	}
	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		dbError(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(), "set transaction isolation level repeatable read read only"); err != nil {
		dbError(w, err)
		return
	}
	var raw, totals []byte
	query := strings.ReplaceAll(reportSQL, "limit 10001", "limit 501 offset $4")
	if err = tx.QueryRow(r.Context(), query, f.From, f.To, f.Cashier, offset).Scan(&raw); err != nil {
		dbError(w, err)
		return
	}
	if err = tx.QueryRow(r.Context(), reportTotalsSQL, f.From, f.To, f.Cashier).Scan(&totals); err != nil {
		dbError(w, err)
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		dbError(w, err)
		return
	}
	var body, summary map[string]any
	if json.Unmarshal(raw, &body) != nil || json.Unmarshal(totals, &summary) != nil {
		writeError(w, 503, "Invalid report response")
		return
	}
	payments, ok := body["payments"].([]any)
	if !ok {
		writeError(w, 503, "Invalid report payments")
		return
	}
	handoffs, ok := body["handoffs"].([]any)
	if !ok {
		writeError(w, 503, "Invalid report handoffs")
		return
	}
	pagination := map[string]any{"offset": offset, "payment_has_more": len(payments) > 500, "handoff_has_more": len(handoffs) > 500}
	if len(payments) > 500 {
		payments = payments[:500]
	}
	if len(handoffs) > 500 {
		handoffs = handoffs[:500]
	}
	body["payments"] = payments
	body["handoffs"] = handoffs
	body["pagination"] = pagination
	body["as_of"] = asOf.Format(time.RFC3339Nano)
	for k, v := range summary {
		body[k] = v
	}
	_ = json.NewEncoder(w).Encode(body)
}
