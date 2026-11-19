package commerce

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPOSHandoffOwnershipConcurrencyAndNoPayment(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required: disposable database only")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var a, b, oid string
	for _, fixture := range []struct {
		name string
		id   *string
	}{{"POS Kasir A", &a}, {"POS Kasir B", &b}} {
		if err = db.QueryRow(ctx, "insert into public.profiles(id,full_name,role) values(gen_random_uuid(),$1,'cashier') returning id", fixture.name).Scan(fixture.id); err != nil {
			t.Fatal(err)
		}
	}
	if err = db.QueryRow(ctx, "insert into public.orders(table_id,total,subtotal,reviewed_version) values(null,15000,15000,1) returning id").Scan(&oid); err != nil {
		t.Fatal(err)
	}
	defer func() {
		db.Exec(ctx, "delete from public.order_pos_handoffs where order_id=$1", oid)
		db.Exec(ctx, "delete from tkm.outbox_events where order_id=$1", oid)
		db.Exec(ctx, "delete from public.orders where id=$1", oid)
		db.Exec(ctx, "delete from public.profiles where id in ($1,$2)", a, b)
	}()
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := ""
		if r.Header.Get("Authorization") == "Bearer pos-a" {
			id = a
		}
		if r.Header.Get("Authorization") == "Bearer pos-b" {
			id = b
		}
		if id == "" {
			w.WriteHeader(401)
			return
		}
		fmt.Fprintf(w, `{"id":%q}`, id)
	}))
	defer auth.Close()
	cfg := db.Config()
	cfg.AfterConnect = func(ctx context.Context, c *pgx.Conn) error {
		_, err := c.Exec(ctx, "set role tkm_runtime")
		return err
	}
	runtimeDB, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer runtimeDB.Close()
	handler := NewHandler(runtimeDB, auth.URL)
	call := func(action, token, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		r := httptest.NewRequest("POST", "/api/v1/orders/"+oid+"/"+action, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		handler.ServeHTTP(w, r)
		return w
	}
	if w := call("claim-pos", "wrong", `{"expected_version":1}`); w.Code != 401 {
		t.Fatal("anonymous claim", w.Code)
	}
	var wg sync.WaitGroup
	wg.Add(2)
	results := make([]*httptest.ResponseRecorder, 2)
	for i, token := range []string{"pos-a", "pos-b"} {
		go func(i int, token string) {
			defer wg.Done()
			results[i] = call("claim-pos", token, `{"expected_version":1}`)
		}(i, token)
	}
	wg.Wait()
	winner, loser := "pos-a", "pos-b"
	if results[1].Code == 200 {
		winner, loser = loser, winner
	}
	if !((results[0].Code == 200 && results[1].Code == 409) || (results[1].Code == 200 && results[0].Code == 409)) {
		t.Fatalf("claim race: %d %d", results[0].Code, results[1].Code)
	}
	if w := call("forward-pos", winner, `{"expected_version":2}`); w.Code != 400 {
		t.Fatal("missing manual attestations", w.Code)
	}
	body := `{"expected_version":2,"entered_in_pos":true,"paid_in_pos":true,"pos_reference":"POS-HTTP"}`
	if w := call("forward-pos", loser, body); w.Code != 403 {
		t.Fatal("other cashier completed", w.Code)
	}
	for i := 0; i < 2; i++ {
		if w := call("forward-pos", winner, body); w.Code != 200 {
			t.Fatal("handoff/retry", w.Code, w.Body.String())
		}
	}
	var count int
	if err = db.QueryRow(ctx, "select count(*) from public.payments where order_id=$1", oid).Scan(&count); err != nil || count != 0 {
		t.Fatal("handoff created payment", count, err)
	}
	if err = db.QueryRow(ctx, "select count(*) from public.staff_audit where order_id=$1 and action='pos_forwarded'", oid).Scan(&count); err != nil || count != 1 {
		t.Fatal("duplicate handoff activity", count, err)
	}
	var raw []byte
	if err = db.QueryRow(ctx, reportSQL, time.Now().Add(-time.Hour), time.Now().Add(time.Hour), "").Scan(&raw); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "POS-HTTP") {
		t.Fatal("handoff missing from report")
	}
}
