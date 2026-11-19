package commerce

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestStaffIdentityIncludesCacheScopeAndRejectsRevokedSession(t *testing.T) {
	a, _, _, staff := realtimeFixture(t)
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprintf(w, `{"id":%q}`, staff) }))
	defer auth.Close()
	h := NewHandler(a.DB, auth.URL)
	call := func() *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		r := httptest.NewRequest("GET", "/api/v1/admin/me", nil)
		r.Header.Set("Authorization", "Bearer identity-fixture")
		h.ServeHTTP(w, r)
		return w
	}
	w := call()
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var profile map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &profile); err != nil {
		t.Fatal(err)
	}
	if profile["id"] != staff || profile["session_version"] != float64(0) || profile["staff_status"] != "active" {
		t.Fatal("cache scope missing", profile)
	}
	if _, err := a.DB.Exec(context.Background(), "update public.profiles set session_version=session_version+1 where id=$1", staff); err != nil {
		t.Fatal(err)
	}
	if w := call(); w.Code != 401 {
		t.Fatal("old session accepted", w.Code)
	}
}
