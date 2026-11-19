package commerce

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"io"
	"net/http"
	"strings"
	"time"
)

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 32768)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if d.Decode(v) != nil {
		writeError(w, 400, "Invalid request")
		return false
	}
	if d.Decode(new(any)) != io.EOF {
		writeError(w, 400, "Invalid request")
		return false
	}
	return true
}
func dbError(w http.ResponseWriter, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, 404, "Order not found")
		return
	}
	var e *pgconn.PgError
	if errors.As(err, &e) {
		switch e.Code {
		case "23514", "23505":
			writeError(w, 409, "Order conflict or invalid request")
			return
		case "42501":
			writeError(w, 403, "Forbidden")
			return
		case "22P02", "22023":
			writeError(w, 400, "Invalid request")
			return
		case "P0002":
			writeError(w, 404, "Order not found")
			return
		}
	}
	writeError(w, 503, "Service unavailable")
}
func (a *API) checkout(w http.ResponseWriter, r *http.Request) {
	var p struct {
		// Compatibility only: do not add omitempty or normalize this field.
		// Existing idempotency payloads include its serialized empty/nonempty value.
		TableToken string `json:"table_token"`
		Name       string `json:"customer_name"`
		Method     string `json:"payment_method"`
		Items      []struct {
			Product  string   `json:"product_id"`
			Quantity int      `json:"quantity"`
			Variants []string `json:"variant_ids"`
			Addons   []string `json:"addon_ids"`
			Notes    string   `json:"notes"`
		} `json:"items"`
	}
	if !decode(w, r, &p) {
		return
	}
	if p.Method != "cash" {
		writeError(w, 400, "Cash only")
		return
	}
	if len(p.Items) < 1 || len(p.Items) > 50 {
		writeError(w, 400, "Invalid items")
		return
	}
	payload, _ := json.Marshal(p)
	var data []byte
	err := a.DB.QueryRow(r.Context(), "select tkm.checkout($1,$2,$3::jsonb)", r.Header.Get("Idempotency-Key"), r.Header.Get("X-Order-Token"), string(payload)).Scan(&data)
	if err != nil {
		checkoutError(w, err)
		return
	}
	w.WriteHeader(201)
	_, _ = w.Write(data)
}
func checkoutError(w http.ResponseWriter, err error) {
	var e *pgconn.PgError
	if errors.As(err, &e) && e.Code == "23514" {
		code := ""
		switch e.Message {
		case "Idempotency conflict":
			code = "idempotency_conflict"
		// These validations run only AFTER the existing-key recovery branch.
		// PostgreSQL's failed statement rolls back the new order AND key.
		// Do not classify pre-key validation, unknown constraints or IO errors.
		case "Restaurant is not accepting new orders", "Invalid table", "Customer name required", "Invalid quantity", "Product unavailable", "Invalid choices", "Too many choices", "Invalid variant", "Missing variant group", "Duplicate addon", "Invalid addon":
			code = "checkout_rejected"
		}
		if code != "" {
			w.WriteHeader(http.StatusConflict)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "Checkout conflict or invalid request", "code": code})
			return
		}
	}
	dbError(w, err)
}

func (a *API) staff(r *http.Request) (string, error) {
	if a.AuthURL == "" {
		return "", errors.New("auth not configured")
	}
	bearer := r.Header.Get("Authorization")
	if !strings.HasPrefix(bearer, "Bearer ") || len(bearer) > 8192 {
		return "", errors.New("unauthorized")
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", a.AuthURL+"/auth/v1/user", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", bearer)
	req.Header.Set("apikey", a.AuthKey)
	res, err := a.Client.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return "", errors.New("unauthorized")
	}
	var user struct {
		ID string `json:"id"`
	}
	if json.NewDecoder(io.LimitReader(res.Body, 32768)).Decode(&user) != nil || user.ID == "" {
		return "", errors.New("unauthorized")
	}
	var id string
	err = a.DB.QueryRow(ctx, "select id from public.profiles where id=$1 and role in ('superadmin','admin','cashier') and staff_status='active' and session_version=$2", user.ID, staffSessionVersion(bearer)).Scan(&id)
	return id, err
}

// Retired writes fail closed even for a cached pre-POS client. Historical
// payments/receipts remain readable; only the operator's legacy SQL is retained.
func (a *API) confirmCash(w http.ResponseWriter, r *http.Request) {
	if _, err := a.staff(r); err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	writeError(w, http.StatusGone, "Pembayaran diproses di aplikasi kasir restoran. Muat ulang web dan gunakan alur input POS.")
}
func (a *API) complete(w http.ResponseWriter, r *http.Request) {
	if _, err := a.staff(r); err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	writeError(w, http.StatusGone, "Pelayanan hidangan ditangani restoran. Gunakan konfirmasi input POS pada web self-order.")
}
func (a *API) order(w http.ResponseWriter, r *http.Request) {
	if !a.canReadOrder(r) {
		writeError(w, 404, "Order not found")
		return
	}
	if _, err := a.DB.Exec(r.Context(), "select tkm.expire_one($1)", r.PathValue("id")); err != nil {
		dbError(w, err)
		return
	}
	token := r.Header.Get("X-Order-Token")
	hash := sha256.Sum256([]byte(token))
	var data []byte
	err := a.DB.QueryRow(r.Context(), "select tkm.order_json(order_id) from tkm.checkout_keys where order_id=$1 and access_hash=$2", r.PathValue("id"), hex.EncodeToString(hash[:])).Scan(&data)
	if err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(data)
}
func (a *API) listOrders(w http.ResponseWriter, r *http.Request) {
	if _, err := a.staff(r); err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	var data []byte
	filter, err := parseOrderListFilter(r.URL.Query())
	if err != nil {
		writeError(w, 400, err.Error())
		return
	}
	if _, err := a.DB.Exec(r.Context(), "select tkm.expire_orders()"); err != nil {
		dbError(w, err)
		return
	}
	query := orderListSQL
	if filter.Summary {
		query = orderSummaryListSQL
	}
	err = a.DB.QueryRow(r.Context(), query, filter.Tab, filter.Status, literalSearchPattern(filter.Search), filter.Offset, filter.Sort, filter.Date).Scan(&data)
	if err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(data)
}
func (a *API) table(w http.ResponseWriter, r *http.Request) {
	var n int
	err := a.DB.QueryRow(r.Context(), "select number from public.tables where qr_token=$1 and is_active", r.URL.Query().Get("t")).Scan(&n)
	if err != nil {
		writeError(w, 404, "Invalid QR")
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]int{"number": n})
}
