package commerce

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"
)

// Committed checkout events survive changes of tab/status. Staged review orders
// are deleted in the same transaction and never appear in this snapshot.
const cashierSyncSQL = `with recent as (
 select order_id from tkm.outbox_events where event_type='ORDER_CREATED'
 and created_at>now()-interval '15 minutes' order by created_at desc,id limit 1001
) select jsonb_build_object('revision',(select revision::text from tkm.order_clock where id=1),
 'new_orders',coalesce((select jsonb_agg(order_id) from (select order_id from recent limit 1000)x),'[]'::jsonb),
 'overflow',(select count(*)>1000 from recent))`

func (a *API) writeCashierSync(w http.ResponseWriter, r *http.Request) {
	var raw []byte
	if err := a.DB.QueryRow(r.Context(), cashierSyncSQL).Scan(&raw); err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(raw)
}

func (a *API) staffOrder(w http.ResponseWriter, r *http.Request) {
	if _, err := a.staff(r); err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	id := r.PathValue("id")
	if !uuidText.MatchString(id) {
		writeError(w, 400, "Invalid order")
		return
	}
	if _, err := a.DB.Exec(r.Context(), "select tkm.expire_one($1)", id); err != nil {
		dbError(w, err)
		return
	}
	var raw []byte
	if err := a.DB.QueryRow(r.Context(), `select tkm.order_json(o.id)||jsonb_build_object('cashier',(
 select jsonb_build_object('id',p.cashier_id,'full_name',p.cashier_name,'confirmed_at',p.created_at) from public.payments p where p.order_id=o.id))
 from public.orders o where o.id=$1`, id).Scan(&raw); err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(raw)
}

func watchHash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}
func (a *API) issueWatch(w http.ResponseWriter, r *http.Request) {
	actor, err := a.staff(r)
	if err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	var body struct {
		Device string `json:"device_id"`
	}
	if !decode(w, r, &body) {
		return
	}
	if !uuidText.MatchString(body.Device) {
		writeError(w, 400, "Invalid device")
		return
	}
	tokenBytes := make([]byte, 32)
	if _, err = rand.Read(tokenBytes); err != nil {
		writeError(w, 503, "Watch unavailable")
		return
	}
	token := hex.EncodeToString(tokenBytes)
	var expiry time.Time
	err = a.DB.QueryRow(r.Context(), "select tkm.issue_watch($1,$2,$3,$4)", actor, body.Device, staffSessionVersion(r.Header.Get("Authorization")), watchHash(token)).Scan(&expiry)
	if err != nil {
		dbError(w, err)
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"token": token, "expires_at": expiry})
}
func (a *API) watch(w http.ResponseWriter, r *http.Request) {
	token := r.Header.Get("X-Watch-Token")
	if len(token) != 64 {
		writeError(w, 401, "Watch expired")
		return
	}
	hash := watchHash(token)
	if r.Method == http.MethodDelete {
		if _, err := a.DB.Exec(r.Context(), "delete from tkm.watch_leases where token_hash=$1", hash); err != nil {
			dbError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
	var allowed bool
	err := a.DB.QueryRow(r.Context(), `select exists(select 1 from tkm.watch_leases w join public.profiles p on p.id=w.actor where w.token_hash=$1 and w.expires_at>now() and p.staff_status='active' and p.session_version=w.session_version and p.role in ('cashier','admin','superadmin'))`, hash).Scan(&allowed)
	if err != nil {
		dbError(w, err)
		return
	}
	if !allowed {
		writeError(w, 401, "Watch expired")
		return
	}
	a.writeCashierSync(w, r)
}
