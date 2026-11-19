package commerce

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"strings"
	"sync"
	"time"
)

type API struct {
	DB        *pgxpool.Pool
	AuthURL   string
	AuthKey   string
	Client    *http.Client
	menuCache *menuResponseCache
}

func NewHandler(db *pgxpool.Pool, authURL string, keys ...string) http.Handler {
	key := ""
	if len(keys) > 0 {
		key = keys[0]
	}
	return newHandler(db, authURL, key, false)
}
func newHandler(db *pgxpool.Pool, authURL, authKey string, serverless bool) http.Handler {
	a := &API{DB: db, AuthURL: authURL, Client: http.DefaultClient}
	a.AuthKey = authKey
	a.menuCache = &menuResponseCache{}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/menu", a.menu)
	mux.HandleFunc("GET /api/v1/table", a.table)
	mux.HandleFunc("POST /api/v1/orders", a.checkout)
	mux.HandleFunc("GET /api/v1/orders/{id}", a.order)
	mux.HandleFunc("GET /api/v1/admin/orders", a.listOrders)
	mux.HandleFunc("GET /api/v1/admin/orders/{id}", a.staffOrder)
	mux.HandleFunc("POST /api/v1/admin/watch", a.issueWatch)
	mux.HandleFunc("GET /api/v1/admin/watch", a.watch)
	mux.HandleFunc("DELETE /api/v1/admin/watch", a.watch)
	mux.HandleFunc("GET /api/v1/admin/me", a.staffMe)
	mux.HandleFunc("GET /api/v1/admin/sync", a.syncCashier)
	mux.HandleFunc("GET /api/v1/orders/{id}/sync", a.syncOrder)
	mux.HandleFunc("GET /api/v1/admin/reports", a.reports)
	mux.HandleFunc("GET /api/v1/orders/{id}/receipt", a.receipt)
	mux.HandleFunc("POST /api/v1/orders/{id}/confirm-cash", a.confirmCash)
	mux.HandleFunc("POST /api/v1/orders/{id}/complete", a.complete)
	mux.HandleFunc("POST /api/v1/orders/{id}/review", a.review)
	mux.HandleFunc("GET /api/v1/orders/{id}/reorder", a.reorder)
	mux.HandleFunc("POST /api/v1/orders/{id}/{action}", a.posHandoff)
	var budgetMu sync.Mutex
	window := time.Now()
	// Public catalog traffic must not consume the cashier/checkout budget.
	// These are bounded process-local guards, not distributed abuse prevention.
	requests := [4]int{}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		budgetMu.Lock()
		if time.Since(window) >= time.Minute {
			window = time.Now()
			requests = [4]int{}
		}
		lane := 3 // order tracking and unknown routes
		if r.Method == http.MethodGet && (r.URL.Path == "/api/v1/menu" || r.URL.Path == "/api/v1/table") {
			lane = 0
		} else if r.Method == http.MethodPost && r.URL.Path == "/api/v1/orders" {
			lane = 1
		} else if strings.HasPrefix(r.URL.Path, "/api/v1/admin/") || r.Method != http.MethodGet {
			lane = 2
		}
		requests[lane]++
		allowed := requests[lane] <= 300
		budgetMu.Unlock()
		if !serverless && !allowed {
			w.Header().Set("Retry-After", "60")
			writeError(w, 429, "Request budget exceeded")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		r = r.WithContext(ctx)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if a.DB == nil {
			writeError(w, 503, "Database not configured")
			return
		}
		if serverless && !a.distributedBudget(w, r, lane) {
			return
		}
		mux.ServeHTTP(w, r)
	})
}
func writeError(w http.ResponseWriter, code int, message string) {
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}
func (a *API) menu(w http.ResponseWriter, r *http.Request) {
	if a.menuCache != nil {
		a.menuCache.mu.Lock()
		defer a.menuCache.mu.Unlock()
		if time.Now().Before(a.menuCache.until) {
			writeMenu(w, r, a.menuCache.data)
			return
		}
	}
	var data []byte
	err := a.DB.QueryRow(r.Context(), `select jsonb_build_object(
 'settings',(select to_jsonb(s)-'pricing_confirmed_by' from public.settings s where id=1),
 'categories',coalesce((select jsonb_agg(to_jsonb(c) order by sort_order) from public.categories c where is_active),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
 'variants',coalesce((select jsonb_agg(to_jsonb(v) order by sort_order) from public.product_variants v where product_id=p.id and is_available),'[]'::jsonb),
 'addons',coalesce((select jsonb_agg(to_jsonb(a)) from public.addons a join public.product_addons pa on pa.addon_id=a.id where pa.product_id=p.id and a.is_available),'[]'::jsonb)
 )) from public.products p join public.categories c on c.id=p.category_id where c.is_active and p.is_available and p.price_confirmed and p.price > 0),'[]'::jsonb))`).Scan(&data)
	if err != nil {
		writeError(w, 503, "Menu unavailable")
		return
	}
	if a.menuCache != nil {
		a.menuCache.data = data
		a.menuCache.until = time.Now().Add(10 * time.Second)
	}
	writeMenu(w, r, data)
}
