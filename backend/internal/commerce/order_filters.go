package commerce

import (
	"errors"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

type orderListFilter struct {
	Tab, Status, Search, Sort, Date string
	Offset                          int
	Summary                         bool
}

func parseOrderListFilter(query url.Values) (orderListFilter, error) {
	f := orderListFilter{Tab: query.Get("tab"), Status: query.Get("status"), Search: strings.TrimSpace(query.Get("q")), Sort: query.Get("sort"), Date: query.Get("date")}
	if value := query.Get("summary"); value != "" && value != "0" && value != "1" {
		return f, errors.New("Invalid summary option")
	}
	f.Summary = query.Get("summary") == "1"
	if f.Tab == "" {
		f.Tab = "active"
	}
	if f.Sort == "" {
		f.Sort = "newest"
	}
	allowed := map[string]map[string]bool{
		"active":  {"": true, "pending": true, "ready": true, "pos_input": true, "confirmed": true},
		"history": {"": true, "forwarded": true, "completed": true, "expired": true, "cancelled": true},
	}
	if !allowed[f.Tab][f.Status] || (f.Sort != "newest" && f.Sort != "oldest") || utf8.RuneCountInString(f.Search) > 80 || strings.ContainsRune(f.Search, '\x00') {
		return f, errors.New("Invalid filter")
	}
	if f.Date != "" {
		if f.Tab != "history" {
			return f, errors.New("Invalid date filter")
		}
		if _, err := time.Parse("2006-01-02", f.Date); err != nil {
			return f, errors.New("Invalid date filter")
		}
	}
	if raw := query.Get("offset"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 0 || value > 100000 {
			return f, errors.New("Invalid offset")
		}
		f.Offset = value
	}
	return f, nil
}

// Search text is a literal substring, including %, _ and backslash. Parameters
// and fixed sort expressions keep user input out of SQL syntax.
func literalSearchPattern(value string) string {
	return "%" + strings.NewReplacer(`\`, `\\`, "%", `\%`, "_", `\_`).Replace(value) + "%"
}

const orderListSQL = `select coalesce(jsonb_agg(tkm.order_json(id)||jsonb_build_object('cashier',(
 select jsonb_build_object('id',pay.cashier_id,'full_name',pay.cashier_name,'confirmed_at',pay.created_at)
 from public.payments pay join public.profiles staff on staff.id=pay.cashier_id where pay.order_id=matches.id
 )) order by
 case when $5='newest' then created_at end desc,
 case when $5='oldest' then created_at end asc,id),'[]'::jsonb)
 from (
 select o.id,o.created_at from public.orders o
 where (($1='active' and o.status in ('pending','pos_input','confirmed')) or ($1='history' and o.status in ('forwarded','expired','completed','cancelled')))
 and ($2='' or o.status=$2 or ($2='ready' and o.status='pending' and o.payment_status='unpaid' and o.reviewed_version=o.version and o.created_at+interval '15 minutes'>now()))
  and ($3='%%' or o.order_number ilike $3 or coalesce(o.customer_name,'') ilike $3
       or exists(select 1 from public.order_items i where i.order_id=o.id and i.product_name ilike $3))
  and (nullif($6,'') is null or (o.created_at >= (nullif($6,'')::date::timestamp at time zone 'Asia/Jakarta') and o.created_at < ((nullif($6,'')::date+1)::timestamp at time zone 'Asia/Jakarta')))
  order by case when $5='newest' then o.created_at end desc,
  case when $5='oldest' then o.created_at end asc,o.id
  limit 100 offset $4
  ) matches`

// Cards need counts/ownership, not each line/add-on. The default remains full
// for existing web clients. This is a fixed SQL substitution, never user input.
var orderSummaryListSQL = strings.Replace(orderListSQL, "tkm.order_json(id)", `(select to_jsonb(o)||jsonb_build_object(
 'expires_at',o.created_at+interval '15 minutes',
 'item_count',coalesce((select sum(i.quantity) from public.order_items i where i.order_id=o.id),0),
 'order_items','[]'::jsonb,
 'pos_handoff',(select jsonb_build_object('cashier_id',h.cashier_id,'cashier_name',h.cashier_name,'claimed_at',h.claimed_at,'forwarded_at',h.forwarded_at,'pos_reference',h.pos_reference) from public.order_pos_handoffs h where h.order_id=o.id)) from public.orders o where o.id=matches.id)`, 1)
