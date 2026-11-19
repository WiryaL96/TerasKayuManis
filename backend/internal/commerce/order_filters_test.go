package commerce

import (
	"net/url"
	"strings"
	"testing"
)

func TestOrderListFilters(t *testing.T) {
	for _, raw := range []string{"", "tab=active&status=pending", "tab=active&status=ready&q=A128", "tab=active&status=confirmed&sort=oldest", "tab=history&offset=100&date=2026-11-15", "tab=history&status=expired", "tab=history&status=cancelled", "q=" + url.QueryEscape("  Budi Santoso  ")} {
		values, _ := url.ParseQuery(raw)
		f, err := parseOrderListFilter(values)
		if err != nil {
			t.Fatalf("valid query %q: %v", raw, err)
		}
		if f.Tab == "" || f.Sort == "" || f.Search != strings.TrimSpace(f.Search) {
			t.Fatal("missing normalized defaults")
		}
	}
	for _, raw := range []string{"tab=history&status=pending", "tab=active&status=completed", "tab=active&date=2026-11-15", "tab=history&date=2026-02-30", "tab=other", "sort=desc%3Bdrop", "offset=-1", "offset=100001", "offset=bad", "q=" + strings.Repeat("x", 81), "q=%00"} {
		values, _ := url.ParseQuery(raw)
		if _, err := parseOrderListFilter(values); err == nil {
			t.Fatalf("invalid query accepted: %s", raw)
		}
	}
	f, err := parseOrderListFilter(url.Values{"q": {strings.Repeat("茶", 80)}})
	if err != nil || len([]rune(f.Search)) != 80 {
		t.Fatal("limit should count characters")
	}
	if actual := literalSearchPattern(`50%_\`); actual != `%50\%\_\\%` {
		t.Fatalf("literal wildcard escape: %q", actual)
	}
}
