package commerce

import "net/http"

const receiptSQL = `select jsonb_build_object('order',tkm.order_json(o.id),'brand',(select brand_name from public.settings where id=1),'payment',jsonb_build_object('paid_at',p.created_at,'cashier_name',p.cashier_name,'total',p.amount_rp,'received',p.received_rp,'change',p.change_rp)) from public.orders o join public.payments p on p.order_id=o.id where o.id=$1`

func (a *API) receipt(w http.ResponseWriter, r *http.Request) {
	if !a.canReadOrder(r) {
		if _, err := a.staff(r); err != nil {
			writeError(w, 404, "Receipt not found")
			return
		}
	}
	var raw []byte
	if err := a.DB.QueryRow(r.Context(), receiptSQL, r.PathValue("id")).Scan(&raw); err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(raw)
}
