package commerce

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"strings"
	"time"
)

type ServerlessOptions struct{ ProxySecret, CronSecret string }

func secureEqual(a, b string) bool {
	return len(b) >= 32 && subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
func NewServerlessHandler(db *pgxpool.Pool, authURL, authKey string, opts ServerlessOptions) http.Handler {
	api := newHandler(db, authURL, authKey, true)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.URL.Path == "/api/cron/maintenance" {
			if r.Method != "GET" || !secureEqual(r.Header.Get("Authorization"), "Bearer "+opts.CronSecret) || len(opts.CronSecret) < 32 {
				http.Error(w, "Forbidden", 403)
				return
			}
			if db == nil {
				http.Error(w, "Not ready", 503)
				return
			}
			ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
			defer cancel()
			if _, err := db.Exec(ctx, "select tkm.serverless_maintenance()"); err != nil {
				http.Error(w, "Maintenance unavailable", 503)
				return
			}
			w.WriteHeader(204)
			return
		}
		if !secureEqual(r.Header.Get("X-TKM-Proxy-Key"), opts.ProxySecret) {
			http.Error(w, "Forbidden", 403)
			return
		}
		api.ServeHTTP(w, r)
	})
}
func (a *API) distributedBudget(w http.ResponseWriter, r *http.Request, lane int) bool {
	// Only called behind a verified private BFF secret; never trust browser headers.
	ip := r.Header.Get("X-TKM-Client-IP")
	if ip == "" {
		writeError(w, 403, "Proxy identity required")
		return false
	}
	hash := sha256.Sum256([]byte(ip))
	key := string(rune('0'+lane)) + ":" + hex.EncodeToString(hash[:])
	identity := r.Header.Get("X-Order-Token")
	if token := r.Header.Get("X-Watch-Token"); token != "" {
		identity = token
	}
	if bearer := r.Header.Get("Authorization"); bearer != "" {
		identity = bearer
	}
	if identity == "" {
		identity = ip
	}
	digest := sha256.Sum256([]byte(identity))
	var allowed bool
	err := a.DB.QueryRow(r.Context(), "select tkm.claim_request_budget($1,2000) and tkm.claim_request_budget($2,300)", key, key+":"+hex.EncodeToString(digest[:])).Scan(&allowed)
	if err != nil {
		writeError(w, 503, "Request guard unavailable")
		return false
	}
	if !allowed {
		w.Header().Set("Retry-After", "60")
		writeError(w, 429, "Too many requests")
		return false
	}
	return true
}
func (a *API) syncOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	token := r.Header.Get("X-Order-Token")
	if !uuidText.MatchString(id) || len(token) < 32 || len(token) > 256 {
		writeError(w, 404, "Order not found")
		return
	}
	hash := sha256.Sum256([]byte(token))
	var version int
	var status string
	err := a.DB.QueryRow(r.Context(), `select o.version,case when o.status='pending' and o.created_at+interval '15 minutes'<=now() then 'expired' else o.status end from public.orders o join tkm.checkout_keys k on k.order_id=o.id where o.id=$1 and k.access_hash=$2 limit 1`, id, hex.EncodeToString(hash[:])).Scan(&version, &status)
	if err != nil {
		dbError(w, err)
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"revision": strings.Join([]string{jsonNumber(version), status}, ":"), "terminal": status == "forwarded" || status == "expired" || status == "cancelled" || status == "completed"})
}
func jsonNumber(n int) string { b, _ := json.Marshal(n); return string(b) }
func (a *API) syncCashier(w http.ResponseWriter, r *http.Request) {
	if _, err := a.staff(r); err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	a.writeCashierSync(w, r)
}
