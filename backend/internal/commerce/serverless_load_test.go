package commerce

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// Opt-in, disposable loopback DB only. Never exercise restaurant data.
func TestServerlessRushHour(t *testing.T) {
	seconds, _ := strconv.Atoi(os.Getenv("TKM_RUSH_SECONDS"))
	if seconds == 0 {
		t.Skip("opt-in rush-hour test")
	}
	if seconds < 30 || seconds > 1800 {
		t.Fatal("duration must be 30..1800 seconds")
	}
	cfg, err := pgxpool.ParseConfig(os.Getenv("TEST_DATABASE_URL"))
	if err != nil || cfg == nil {
		t.Fatal("test DSN required")
	}
	if cfg.ConnConfig.Host != "127.0.0.1" && cfg.ConnConfig.Host != "localhost" {
		t.Fatal("load test refuses non-loopback database")
	}
	ctx := context.Background()
	owner, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	_, err = owner.Exec(ctx, "update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1")
	must(err)
	var category, product string
	must(owner.QueryRow(ctx, "insert into public.categories(name,slug) values('RUSH',gen_random_uuid()::text) returning id").Scan(&category))
	must(owner.QueryRow(ctx, "insert into public.products(category_id,name,slug,price,price_confirmed,is_available) values($1,'RUSH',gen_random_uuid()::text,10000,true,true) returning id", category).Scan(&product))
	actors := map[string]string{}
	for i := 0; i < 5; i++ {
		var id string
		must(owner.QueryRow(ctx, "insert into public.profiles(id,full_name,role,staff_status) values(gen_random_uuid(),$1,'cashier','active') returning id", fmt.Sprint("Rush Cashier ", i)).Scan(&id))
		actors[fmt.Sprint("Bearer rush-", i)] = id
	}
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := actors[r.Header.Get("Authorization")]
		if id == "" {
			w.WriteHeader(401)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"id": id})
	}))
	defer auth.Close()
	secret := "isolated-rush-proxy-secret-32-bytes-minimum"
	cron := "isolated-rush-cron-secret-32-bytes-minimum"
	handlers := make([]http.Handler, 2)
	pools := make([]*pgxpool.Pool, 2)
	for i := range pools {
		c := cfg.Copy()
		c.MaxConns = 2
		c.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeExec
		c.AfterConnect = func(ctx context.Context, c *pgx.Conn) error {
			_, err := c.Exec(ctx, "set role tkm_runtime")
			return err
		}
		pools[i], err = pgxpool.NewWithConfig(ctx, c)
		must(err)
		defer pools[i].Close()
		handlers[i] = NewServerlessHandler(pools[i], auth.URL, "synthetic-anon", ServerlessOptions{ProxySecret: secret, CronSecret: cron})
	}
	var turn atomic.Uint64
	var onlySecond atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		i := int(turn.Add(1) % 2)
		if onlySecond.Load() {
			i = 1
		}
		handlers[i].ServeHTTP(w, r)
	}))
	defer server.Close()
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.MaxIdleConns = 250
	transport.MaxIdleConnsPerHost = 250
	defer transport.CloseIdleConnections()
	client := &http.Client{Timeout: 10 * time.Second, Transport: transport}
	type metric struct {
		Latencies []float64
		Errors    int
		Requests  int
		Bytes     int64
	}
	metrics := map[string]*metric{}
	var mu sync.Mutex
	call := func(label, method, path, token, ip, key string, body any) (int, []byte) {
		raw, _ := json.Marshal(body)
		req, _ := http.NewRequest(method, server.URL+path, bytes.NewReader(raw))
		req.Header.Set("X-TKM-Proxy-Key", secret)
		req.Header.Set("X-TKM-Client-IP", ip)
		req.Header.Set("Content-Type", "application/json")
		if len(token) > 7 && token[:7] == "Bearer " {
			req.Header.Set("Authorization", token)
		} else if token != "" {
			req.Header.Set("X-Order-Token", token)
		}
		if key != "" {
			req.Header.Set("Idempotency-Key", key)
		}
		start := time.Now()
		res, e := client.Do(req)
		status := 0
		var data []byte
		if e == nil {
			status = res.StatusCode
			data, _ = io.ReadAll(res.Body)
			res.Body.Close()
		}
		mu.Lock()
		m := metrics[label]
		if m == nil {
			m = &metric{}
			metrics[label] = m
		}
		m.Requests++
		m.Bytes += int64(len(data))
		m.Latencies = append(m.Latencies, float64(time.Since(start).Microseconds())/1000)
		if status < 200 || status >= 400 {
			m.Errors++
		}
		mu.Unlock()
		return status, data
	}
	type customer struct {
		ID, Token string
		Index     int
	}
	customers := make([]customer, 200)
	var customersMu sync.RWMutex
	orders := make(chan customer, 500)
	payload := map[string]any{"customer_name": "Isolated Rush Customer", "payment_method": "cash", "items": []any{map[string]any{"product_id": product, "quantity": 1, "variant_ids": []string{}, "addon_ids": []string{}, "notes": ""}}}
	seed := func(from, to int) {
		var wg sync.WaitGroup
		for i := from; i < to; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				b := make([]byte, 32)
				rand.Read(b)
				token := hex.EncodeToString(b)
				ip := "192.0.2.1"
				code, data := call("checkout", "POST", "/api/v1/orders", token, ip, token, payload)
				if code != 201 {
					t.Errorf("checkout status=%d body=%s", code, data)
					return
				}
				var order struct{ ID string }
				json.Unmarshal(data, &order)
				c := customer{order.ID, token, i}
				customersMu.Lock()
				customers[i] = c
				customersMu.Unlock()
				orders <- c
			}(i)
		}
		wg.Wait()
	}
	var paymentBefore int
	must(owner.QueryRow(ctx, "select count(*) from public.payments").Scan(&paymentBefore))
	started := time.Now()
	seed(0, 100)
	if t.Failed() {
		return
	}
	end := time.Now().Add(time.Duration(seconds) * time.Second)
	var wg sync.WaitGroup
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			time.Sleep(time.Duration(i%30) * 50 * time.Millisecond)
			previous := ""
			for time.Now().Before(end) {
				if i < 100 || time.Until(end) < time.Duration(seconds/3)*time.Second {
					customersMu.RLock()
					c := customers[i]
					customersMu.RUnlock()
					if c.ID != "" {
						ip := "192.0.2.1"
						code, raw := call("sync_order", "GET", "/api/v1/orders/"+c.ID+"/sync", c.Token, ip, "", nil)
						var v struct{ Revision string }
						json.Unmarshal(raw, &v)
						if code == 200 && previous != v.Revision {
							call("order_snapshot", "GET", "/api/v1/orders/"+c.ID, c.Token, ip, "", nil)
							previous = v.Revision
						}
					}
				}
				time.Sleep(15 * time.Second)
			}
		}(i)
	}
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			token := fmt.Sprint("Bearer rush-", i)
			ip := fmt.Sprint("198.51.100.", i+1)
			next := time.Now()
			previous := ""
			for time.Now().Before(end) {
				code, raw := call("sync_cashier", "GET", "/api/v1/admin/sync", token, ip, "", nil)
				var v struct{ Revision string }
				json.Unmarshal(raw, &v)
				if code == 200 && previous != v.Revision {
					call("cashier_listing", "GET", "/api/v1/admin/orders", token, ip, "", nil)
					previous = v.Revision
				}
				if time.Now().After(next) {
					select {
					case c := <-orders:
						review := map[string]any{"expected_version": 1, "items": payload["items"]}
						code, _ := call("review", "POST", "/api/v1/orders/"+c.ID+"/review", token, ip, "", review)
						if code == 200 {
							code, _ = call("claim", "POST", "/api/v1/orders/"+c.ID+"/claim-pos", token, ip, "", map[string]any{"expected_version": 2})
							if code == 200 {
								p := map[string]any{"expected_version": 3, "entered_in_pos": true, "paid_in_pos": true, "pos_reference": "isolated-pos-" + c.ID}
								call("forward", "POST", "/api/v1/orders/"+c.ID+"/forward-pos", token, ip, "", p)
								call("forward_retry", "POST", "/api/v1/orders/"+c.ID+"/forward-pos", token, ip, "", p)
							}
						}
					default:
					}
					next = time.Now().Add(15 * time.Second)
				}
				time.Sleep(5 * time.Second)
			}
		}(i)
	}
	// Cold catalog burst while operational staff continue independently.
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			call("menu", "GET", "/api/v1/menu", "", fmt.Sprint("203.0.113.", i+1), "", nil)
		}(i)
	}
	time.Sleep(time.Duration(seconds*2/3) * time.Second)
	seed(100, 200)
	onlySecond.Store(true) // remove one instance without sticky sessions
	wg.Wait()
	var paymentAfter, duplicates, wrongNames int
	must(owner.QueryRow(ctx, "select count(*) from public.payments").Scan(&paymentAfter))
	must(owner.QueryRow(ctx, "select count(*) from(select order_id from public.staff_audit where action='pos_forwarded' group by order_id having count(*)>1)x").Scan(&duplicates))
	must(owner.QueryRow(ctx, "select count(*) from public.order_pos_handoffs h join public.profiles p on p.id=h.cashier_id where p.full_name like 'Rush Cashier %' and h.cashier_name<>p.full_name").Scan(&wrongNames))
	report := map[string]any{"duration_seconds": time.Since(started).Seconds(), "active_customers": 100, "burst_customers": 200, "cashiers": 5, "instances": 2, "pool_connections_per_instance": 2, "auth": "local fake Supabase Auth; real restricted PostgreSQL SQL and HTTP handlers", "environment": "loopback disposable database; not Vercel/network capacity", "duplicate_handoffs": duplicates, "wrong_cashier_names": wrongNames, "new_payments": paymentAfter - paymentBefore, "failover": "second instance only during final third", "routes": map[string]any{}}
	total, errors := 0, 0
	for name, m := range metrics {
		sort.Float64s(m.Latencies)
		q := func(p float64) float64 { return m.Latencies[int(float64(len(m.Latencies)-1)*p)] }
		report["routes"].(map[string]any)[name] = map[string]any{"requests": m.Requests, "errors": m.Errors, "p50_ms": q(.5), "p95_ms": q(.95), "p99_ms": q(.99), "bytes": m.Bytes}
		total += m.Requests
		errors += m.Errors
	}
	report["requests"] = total
	report["errors"] = errors
	report["error_rate"] = float64(errors) / float64(total)
	raw, _ := json.MarshalIndent(report, "", "  ")
	path := os.Getenv("TKM_RUSH_REPORT")
	if path != "" {
		must(os.WriteFile(path, raw, 0600))
	}
	t.Log(string(raw))
	if errors > 0 || duplicates > 0 || wrongNames > 0 || paymentAfter != paymentBefore {
		t.Fatal("rush-hour correctness or availability gate failed")
	}
	for _, m := range metrics {
		if m.Latencies[int(float64(len(m.Latencies)-1)*.95)] > 1000 {
			t.Fatal("local p95 exceeded 1000ms")
		}
	}
}
