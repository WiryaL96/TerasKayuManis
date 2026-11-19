package commerce

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestMobileWatchAndDetail(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("disposable TEST_DATABASE_URL required")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var actor, device string
	if err = pool.QueryRow(ctx, `insert into public.profiles(id,full_name,role,staff_status) values(gen_random_uuid(),'Mobile test','cashier','active') returning id`).Scan(&actor); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(ctx, "delete from public.profiles where id=$1", actor)
	defer pool.Exec(ctx, "delete from tkm.watch_leases where actor=$1", actor)
	_ = pool.QueryRow(ctx, "select gen_random_uuid()::text").Scan(&device)
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fixture" {
			w.WriteHeader(401)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"id": actor})
	}))
	defer auth.Close()
	runtimeConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	runtimeConfig.ConnConfig.RuntimeParams["role"] = "tkm_runtime"
	runtimePool, err := pgxpool.NewWithConfig(ctx, runtimeConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer runtimePool.Close()
	handler := NewHandler(runtimePool, auth.URL, "anon")
	call := func(method, path, body, bearer, watch string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		if bearer != "" {
			r.Header.Set("Authorization", bearer)
		}
		r.Header.Set("X-Watch-Token", watch)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	issue := call("POST", "/api/v1/admin/watch", `{"device_id":"`+device+`"}`, "Bearer fixture", "")
	if issue.Code != 200 {
		t.Fatal("issue", issue.Code, issue.Body.String())
	}
	var lease struct {
		Token   string    `json:"token"`
		Expires time.Time `json:"expires_at"`
	}
	_ = json.Unmarshal(issue.Body.Bytes(), &lease)
	if len(lease.Token) != 64 || time.Until(lease.Expires) > 6*time.Hour {
		t.Fatal("unbounded watch")
	}
	if w := call("GET", "/api/v1/admin/watch", "", "", lease.Token); w.Code != 200 || strings.Contains(w.Body.String(), "customer_name") {
		t.Fatal("watch snapshot", w.Code)
	}
	if w := call("GET", "/api/v1/admin/orders", "", "", lease.Token); w.Code != 401 {
		t.Fatal("lease authorized full orders")
	}
	if w := call("POST", "/api/v1/orders/00000000-0000-4000-8000-000000000000/claim-pos", `{}`, "", lease.Token); w.Code != 401 {
		t.Fatal("lease authorized mutation")
	}
	if w := call("GET", "/api/v1/admin/orders/not-a-uuid", "", "Bearer fixture", ""); w.Code != 400 {
		t.Fatal("invalid detail id")
	}
	if w := call("DELETE", "/api/v1/admin/watch", "", "", lease.Token); w.Code != 204 {
		t.Fatal("revoke")
	}
	if w := call("GET", "/api/v1/admin/watch", "", "", lease.Token); w.Code != 401 {
		t.Fatal("revoked watch worked")
	}
	if w := call("GET", "/api/v1/admin/orders?tab=history&date=2026-11-15", "", "Bearer fixture", ""); w.Code != 200 {
		t.Fatal("date query", w.Code, w.Body.String())
	}
}
