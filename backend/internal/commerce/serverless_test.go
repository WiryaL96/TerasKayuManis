package commerce

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"
)

func TestServerlessSecretsFailClosed(t *testing.T) {
	h := NewServerlessHandler(nil, "", "", ServerlessOptions{ProxySecret: "test-proxy-secret-at-least-32-characters", CronSecret: "test-cron-secret-at-least-32-characters"})
	for _, path := range []string{"/api/v1/menu", "/api/cron/maintenance"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 403 {
			t.Fatal(path, w.Code)
		}
	}
}
func TestServerlessReportPagesKeepFullTotals(t *testing.T) {
	a, _, _, _ := realtimeFixture(t)
	db := a.DB
	ctx := context.Background()
	var cashier, admin string
	for _, entry := range []struct {
		role string
		id   *string
	}{{"cashier", &cashier}, {"superadmin", &admin}} {
		if err := db.QueryRow(ctx, "insert into public.profiles(id,full_name,role,staff_status) values(gen_random_uuid(),'Report Page Fixture',$1,'active') returning id", entry.role).Scan(entry.id); err != nil {
			t.Fatal(err)
		}
	}
	var ids []string
	rows, err := db.Query(ctx, "insert into public.orders(total,subtotal,status) select 10000,10000,'forwarded' from generate_series(1,601) returning id")
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	rows.Close()
	t.Cleanup(func() {
		for _, id := range ids {
			db.Exec(ctx, "delete from public.order_pos_handoffs where order_id=$1", id)
			db.Exec(ctx, "delete from public.orders where id=$1", id)
		}
		db.Exec(ctx, "delete from public.profiles where id in ($1,$2)", cashier, admin)
	})
	if _, err = db.Exec(ctx, "insert into public.order_pos_handoffs(order_id,cashier_id,cashier_name,claimed_version,forwarded_at) select id,$2,'Report Page Fixture',1,clock_timestamp() from public.orders where id=any($1::uuid[])", ids, cashier); err != nil {
		t.Fatal(err)
	}
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprintf(w, `{"id":%q}`, admin) }))
	defer auth.Close()
	handler := NewHandler(db, auth.URL)
	call := func(offset int, asOf string) map[string]any {
		t.Helper()
		w := httptest.NewRecorder()
		r := httptest.NewRequest("GET", fmt.Sprintf("/api/v1/admin/reports?paged=1&offset=%d&cashier=%s&as_of=%s", offset, cashier, url.QueryEscape(asOf)), nil)
		r.Header.Set("Authorization", "Bearer page-fixture")
		handler.ServeHTTP(w, r)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		var data map[string]any
		if json.Unmarshal(w.Body.Bytes(), &data) != nil {
			t.Fatal("invalid JSON")
		}
		return data
	}
	first := call(0, "")
	second := call(500, first["as_of"].(string))
	if len(first["handoffs"].([]any)) != 500 || len(second["handoffs"].([]any)) != 101 {
		t.Fatal("pagination dropped rows")
	}
	for _, page := range []map[string]any{first, second} {
		if page["pos_summary"].(map[string]any)["count"] != float64(601) || page["pos_summary"].(map[string]any)["total"] != "6010000" {
			t.Fatal("page totals were truncated")
		}
	}
	if !first["pagination"].(map[string]any)["handoff_has_more"].(bool) || second["pagination"].(map[string]any)["handoff_has_more"].(bool) {
		t.Fatal("incorrect next page")
	}
	if _, err := time.Parse(time.RFC3339Nano, first["as_of"].(string)); err != nil {
		t.Fatal(err)
	}
}
