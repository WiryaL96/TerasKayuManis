package commerce

import (
	"net/http/httptest"
	"testing"
)

func TestRateLimitBoundedCatalog(t *testing.T) {
	h := NewHandler(nil, "")
	limited := false
	for i := 0; i < 301; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/menu", nil))
		if w.Code == 429 {
			limited = true
		}
	}
	if !limited {
		t.Fatal("missing request budget")
	}
}

func TestCatalogFloodDoesNotConsumeStaffCheckoutOrTrackingBudget(t *testing.T) {
	h := NewHandler(nil, "")
	for i := 0; i < 301; i++ {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/v1/menu", nil))
	}
	for _, route := range []struct{ method, path string }{
		{"GET", "/api/v1/admin/me"},
		{"POST", "/api/v1/orders"},
		{"GET", "/api/v1/orders/example"},
	} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(route.method, route.path, nil))
		if w.Code != 503 { // no database fixture; request must reach the DB guard
			t.Fatalf("%s blocked by catalog traffic: %d", route.path, w.Code)
		}
	}
}
