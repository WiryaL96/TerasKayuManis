package commerce

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestReportWIBBoundaries(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/admin/reports?from=2026-10-25&to=2026-10-25", nil)
	f, err := parseReportFilter(r)
	if err != nil {
		t.Fatal(err)
	}
	if f.From.UTC().Format(time.RFC3339) != "2026-10-24T17:00:00Z" || f.To.UTC().Format(time.RFC3339) != "2026-10-25T17:00:00Z" {
		t.Fatal(f)
	}
	for _, query := range []string{"from=bad", "from=2026-10-25&to=2026-10-24", "from=2026-01-01&to=2026-02-01", "cashier=forged"} {
		if _, err := parseReportFilter(httptest.NewRequest("GET", "/api/v1/admin/reports?"+query, nil)); err == nil {
			t.Fatal("accepted", query)
		}
	}
}
func TestReportUsesAmountsAndHistoricalNames(t *testing.T) {
	before, after := "Raka", "Raka Baru"
	summary, groups := summarizePayments([]reportPayment{{CashierID: "a", CashierName: &before, Total: 10000, Received: 20000, Change: 10000}, {CashierID: "a", CashierName: &after, Total: 15000, Received: 15000}, {CashierID: "legacy", Total: 5000, Received: 10000, Change: 5000}})
	if summary["revenue"] != "30000" || summary["received"] != "45000" || summary["change"] != "15000" || summary["count"] != 3 {
		t.Fatal(summary)
	}
	if len(groups) != 3 || groups[0].Name != "Nama kasir belum tercatat" {
		t.Fatal(groups)
	}
	for _, value := range []string{"=SUM(A1:A2)", " +1", "\t@SUM(A1)", "-2"} {
		if csvText(value) != "'"+value {
			t.Fatal(value)
		}
	}
	if csvText("Raka") != "Raka" {
		t.Fatal("ordinary CSV label changed")
	}
}
