package commerce

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestOrderListSearchPaginationAndStatus(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required: use disposable test database")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var prefix string
	if err = tx.QueryRow(ctx, `select gen_random_uuid()::text`).Scan(&prefix); err != nil {
		t.Fatal(err)
	}
	_, err = tx.Exec(ctx, `insert into public.orders(order_number,customer_name,total,created_at)
 select $1||'-'||g,$1||' Customer '||g,10000,now()-g*interval '1 second' from generate_series(1,110) g`, prefix)
	if err != nil {
		t.Fatal(err)
	}
	query := func(tab, status, search, sort string, offset int) []map[string]any {
		t.Helper()
		var raw []byte
		if err := tx.QueryRow(ctx, orderListSQL, tab, status, literalSearchPattern(search), offset, sort, "").Scan(&raw); err != nil {
			t.Fatal(err)
		}
		var result []map[string]any
		if err := json.Unmarshal(raw, &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	if rows := query("active", "", prefix, "newest", 0); len(rows) != 100 || rows[0]["order_number"] != prefix+"-1" {
		t.Fatal("newest page", len(rows))
	}
	if rows := query("active", "", prefix, "newest", 100); len(rows) != 10 {
		t.Fatal("second page", len(rows))
	}
	if rows := query("active", "", prefix+"-110", "newest", 0); len(rows) != 1 {
		t.Fatal("search before pagination", len(rows))
	}
	if rows := query("active", "", prefix, "oldest", 0); rows[0]["order_number"] != prefix+"-110" {
		t.Fatal("oldest sort")
	}
	_, err = tx.Exec(ctx, `update public.orders set customer_name=$2,version=2,reviewed_version=2 where order_number=$1`, prefix+"-110", prefix+" 50%_Offer")
	if err != nil {
		t.Fatal(err)
	}
	if rows := query("active", "ready", prefix, "newest", 0); len(rows) != 1 {
		t.Fatal("ready filter", len(rows))
	}
	if rows := query("active", "", prefix+" 50%_", "newest", 0); len(rows) != 1 {
		t.Fatal("literal wildcard search", len(rows))
	}
	if rows := query("active", "", prefix+" 50X_", "newest", 0); len(rows) != 0 {
		t.Fatal("wildcard cannot widen search")
	}
	if rows := query("active", "", prefix+" Customer 20", "newest", 0); len(rows) != 1 {
		t.Fatal("customer search")
	}
	_, err = tx.Exec(ctx, `update public.orders set status='completed',payment_status='paid' where order_number=$1`, prefix+"-1")
	if err != nil {
		t.Fatal(err)
	}
	if rows := query("history", "completed", prefix, "newest", 0); len(rows) != 1 {
		t.Fatal("completed history filter")
	}
	for _, row := range query("active", "", prefix+"-1", "newest", 0) {
		if row["order_number"] == prefix+"-1" {
			t.Fatal("completed order leaked into active list")
		}
	}
	if rows := query("active", "", `' OR 1=1 --`, "newest", 0); len(rows) != 0 {
		t.Fatal("search must remain a parameter")
	}
	var category, product string
	if err = tx.QueryRow(ctx, `insert into public.categories(name,slug) values($1,$1) returning id`, prefix).Scan(&category); err != nil {
		t.Fatal(err)
	}
	if err = tx.QueryRow(ctx, `insert into public.products(category_id,name,slug,price) values($1,$2,$3,10000) returning id`, category, "Menu "+prefix, prefix).Scan(&product); err != nil {
		t.Fatal(err)
	}
	_, err = tx.Exec(ctx, `insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal) select id,$2,$3,1,10000,10000 from public.orders where order_number=$1`, prefix+"-110", product, "Menu "+prefix)
	if err != nil {
		t.Fatal(err)
	}
	if rows := query("active", "", "menu "+prefix, "newest", 0); len(rows) != 1 {
		t.Fatal("case-insensitive item search")
	}
	_, err = tx.Exec(ctx, `update public.orders set status='expired',created_at='2026-11-14T17:00:00Z' where order_number=$1`, prefix+"-110")
	if err != nil {
		t.Fatal(err)
	}
	var dated []byte
	if err = tx.QueryRow(ctx, orderListSQL, "history", "expired", literalSearchPattern(prefix), 0, "newest", "2026-11-15").Scan(&dated); err != nil {
		t.Fatal(err)
	}
	var rows []map[string]any
	_ = json.Unmarshal(dated, &rows)
	if len(rows) != 1 || rows[0]["order_number"] != prefix+"-110" {
		t.Fatal("WIB date boundary", string(dated))
	}
	if err = tx.QueryRow(ctx, orderSummaryListSQL, "history", "expired", literalSearchPattern(prefix), 0, "newest", "2026-11-15").Scan(&dated); err != nil {
		t.Fatal(err)
	}
	_ = json.Unmarshal(dated, &rows)
	if len(rows) != 1 || rows[0]["item_count"] != float64(1) || len(rows[0]["order_items"].([]any)) != 0 {
		t.Fatal("summary includes lines or loses count", string(dated))
	}
}
