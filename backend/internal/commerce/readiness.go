package commerce

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Deployment health fails before serving a release that needs an unapplied
// migration. The release installer can then roll back to the previous version.
type ReadyDatabase struct {
	Pool       *pgxpool.Pool
	Serverless bool
}

const namedCashierReadySQL = `select
 (select count(*)=2 from pg_attribute where attrelid='public.profiles'::regclass and attname in ('staff_status','session_version') and not attisdropped and has_column_privilege(current_user,attrelid,attnum,'SELECT'))
 and to_regprocedure('tkm.confirm_cash_verified(uuid,uuid,bigint,integer,integer)') is not null
 and exists(select 1 from pg_attribute where attrelid='public.products'::regclass and attname='price_confirmed' and not attisdropped)
 and to_regprocedure('public.bootstrap_superadmin(uuid,text,text,text)') is not null
 and to_regprocedure('public.create_staff_account(uuid,uuid,text,text,text)') is not null
 and to_regprocedure('public.manage_staff_account(uuid,uuid,text,text)') is not null
 and to_regprocedure('public.record_staff_signin(uuid,integer,text)') is not null
 and to_regprocedure('public.reserve_staff_account(uuid,uuid,text,text,text,text)') is not null
 and to_regprocedure('public.finish_staff_password(uuid,uuid,integer)') is not null
 and to_regprocedure('public.finish_staff_credential(uuid,uuid,integer,text)') is not null
 and to_regprocedure('public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb)') is not null
 and to_regprocedure('public.begin_staff_edit(uuid,uuid,text,text,text,text)') is not null
 and to_regprocedure('public.claim_unused_media()') is not null
 and to_regprocedure('tkm.issue_watch(uuid,uuid,integer,text)') is not null
 and to_regprocedure('public.claim_cashier_pin_attempt(uuid)') is not null
 and to_regprocedure('tkm.claim_pos_order(uuid,uuid,integer,integer,text)') is not null
 and to_regprocedure('tkm.forward_pos_order(uuid,uuid,integer,integer,text)') is not null
 and coalesce(has_table_privilege(current_user,to_regclass('public.order_pos_handoffs'),'SELECT'),false)
 and exists(select 1 from pg_attribute where attrelid='public.profiles'::regclass and attname='username' and not attisdropped)
 and exists(select 1 from pg_trigger where tgrelid='public.staff_audit'::regclass and tgname='staff_audit_identity' and tgenabled in ('O','A') and tgfoid=to_regprocedure('tkm.snapshot_staff_audit()'))
 and exists(select 1 from pg_trigger where tgrelid='public.staff_audit'::regclass and tgname='staff_audit_immutable' and tgenabled in ('O','A') and tgfoid=to_regprocedure('tkm.immutable_staff_audit()'))
 and exists(select 1 from pg_trigger where tgrelid='public.payments'::regclass and tgname='payment_activity' and tgenabled in ('O','A') and tgfoid=to_regprocedure('tkm.audit_cashier_work()'))
 and exists(select 1 from pg_trigger where tgrelid='tkm.order_reviews'::regclass and tgname='review_activity' and tgenabled in ('O','A') and tgfoid=to_regprocedure('tkm.audit_cashier_work()'))
 and exists(select 1 from pg_trigger where tgrelid='public.order_status_history'::regclass and tgname='completion_activity' and tgenabled in ('O','A') and tgfoid=to_regprocedure('tkm.audit_cashier_work()'))
 and
 has_column_privilege(current_user,'public.profiles','full_name','SELECT')
 and exists(select 1 from pg_attribute where attrelid='public.payments'::regclass and attname='cashier_name' and not attisdropped)
 and exists(select 1 from pg_trigger where tgrelid='public.payments'::regclass and tgname='payment_cashier_name' and tgenabled in ('O','A') and not tgisinternal and tgfoid=to_regprocedure('tkm.snapshot_cashier_name()'))`

func (r ReadyDatabase) Ping(ctx context.Context) error {
	if r.Pool == nil {
		return errors.New("database not configured")
	}
	if err := r.Pool.Ping(ctx); err != nil {
		return err
	}
	var ready bool
	if err := r.Pool.QueryRow(ctx, namedCashierReadySQL).Scan(&ready); err != nil {
		return err
	}
	if !ready {
		return errors.New("staff operations migration required")
	}
	if r.Serverless {
		if err := r.Pool.QueryRow(ctx, `select to_regprocedure('tkm.claim_request_budget(text,integer)') is not null and to_regclass('tkm.order_clock') is not null and to_regprocedure('tkm.serverless_maintenance()') is not null and to_regprocedure('public.dashboard_snapshot(uuid,date,date)') is not null`).Scan(&ready); err != nil {
			return err
		}
		if !ready {
			return errors.New("serverless operations migration required")
		}
	}
	return nil
}
