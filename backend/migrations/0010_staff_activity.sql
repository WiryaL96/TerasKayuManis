-- Apply as migration owner after 0009. Historical identities stay unknown.
alter table public.staff_audit add column actor_name text;
alter table public.staff_audit add column actor_role text;
alter table public.staff_audit add column target_name text;
alter table public.staff_audit add column order_id uuid;
-- Keep the original actor UUID even if an operator removes a profile later.
-- No cascade or SET NULL may mutate an immutable historical event.
alter table public.staff_audit drop constraint if exists staff_audit_actor_id_fkey;
create index staff_audit_time on public.staff_audit(created_at desc,id desc);
create index staff_audit_actor_time on public.staff_audit(actor_id,created_at desc);
create index staff_audit_action_time on public.staff_audit(action,created_at desc);

create function tkm.snapshot_staff_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 select full_name,role into new.actor_name,new.actor_role from public.profiles where id=new.actor_id;
 select full_name into new.target_name from public.profiles where id=new.target_id;
 new.created_at:=clock_timestamp();
 return new;
end $$;
create trigger staff_audit_identity before insert on public.staff_audit for each row execute function tkm.snapshot_staff_audit();

create function tkm.immutable_staff_audit() returns trigger language plpgsql set search_path='' as $$
begin raise insufficient_privilege using message='Activity records cannot be edited or deleted';end $$;
create trigger staff_audit_immutable before update or delete on public.staff_audit for each row execute function tkm.immutable_staff_audit();
create trigger staff_audit_no_truncate before truncate on public.staff_audit for each statement execute function tkm.immutable_staff_audit();

-- All event inserts are part of the business transaction. A retry that makes no
-- payment/status/review insert cannot produce a duplicate activity entry.
create function tkm.audit_cashier_work() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='payments' then
  insert into public.staff_audit(actor_id,order_id,action,details)
  values(new.cashier_id,new.order_id,'cash_payment_confirmed',jsonb_build_object('order_number',(select order_number from public.orders where id=new.order_id),'total',new.amount_rp,'received',new.received_rp,'change',new.change_rp));
 elsif tg_table_name='order_reviews' then
  insert into public.staff_audit(actor_id,order_id,action,details)
  values(new.actor,new.order_id,'order_reviewed',jsonb_build_object('order_number',new.after_order->>'order_number','before_total',new.before_order->'total','total',new.after_order->'total'));
 elsif new.new_status='completed' and new.changed_by is not null then
  insert into public.staff_audit(actor_id,order_id,action,details)
  values(new.changed_by,new.order_id,'order_completed',jsonb_build_object('order_number',(select order_number from public.orders where id=new.order_id)));
 end if;
 return new;
end $$;
create trigger payment_activity after insert on public.payments for each row execute function tkm.audit_cashier_work();
create trigger review_activity after insert on tkm.order_reviews for each row execute function tkm.audit_cashier_work();
create trigger completion_activity after insert on public.order_status_history for each row execute function tkm.audit_cashier_work();

create function public.create_cashier(p_actor uuid,p_id uuid,p_name text,p_email text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('owner','admin') and staff_status='active') then raise insufficient_privilege;end if;
 if length(btrim(p_name)) not between 2 and 100 or p_name is null or p_name ~ '[[:cntrl:]]' or p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise check_violation;end if;
 insert into public.profiles(id,full_name,email,role,staff_status) values(p_id,btrim(p_name),lower(btrim(p_email)),'cashier','invited');
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_id,'cashier_created');
end $$;

-- Called only by the server after verifying the exact Supabase credentials.
create function public.record_staff_signin(p_actor uuid,p_version integer,p_area text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into p from public.profiles where id=p_actor for share;
 if not found or p.staff_status<>'active' or p.session_version is distinct from p_version or nullif(btrim(p.full_name),'') is null
 or p_area not in ('cashier','admin') or p_area is null
 or (p_area='cashier' and p.role not in ('owner','admin','manager','cashier'))
 or (p_area='admin' and p.role not in ('owner','admin','manager')) then raise insufficient_privilege;end if;
 insert into public.staff_audit(actor_id,action,details) values(p_actor,'staff_login',jsonb_build_object('area',p_area));
 return jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role);
end $$;

revoke all on function tkm.snapshot_staff_audit(),tkm.immutable_staff_audit(),tkm.audit_cashier_work(),public.create_cashier(uuid,uuid,text,text),public.record_staff_signin(uuid,integer,text) from public;
-- Supabase projects may have explicit default function grants to API roles;
-- revoking PUBLIC alone does not remove those grants. Protect older staff RPCs too.
do $$declare api_role text; fn regprocedure; begin
 foreach api_role in array array['anon','authenticated'] loop
  if exists(select 1 from pg_roles where rolname=api_role) then
   for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('manage_cashier','issue_staff_access','claim_staff_access','finish_staff_access','confirm_restaurant_pricing','bootstrap_owner','create_cashier','record_staff_signin') loop
    execute format('revoke all on function %s from %I',fn,api_role);
   end loop;
  end if;
 end loop;
 if exists(select 1 from pg_roles where rolname='anon') then revoke all on public.staff_audit,public.staff_access_links from anon;end if;
 if exists(select 1 from pg_roles where rolname='authenticated') then revoke all on public.staff_audit,public.staff_access_links from authenticated;end if;
 revoke all on public.staff_audit from tkm_runtime;
 if exists(select 1 from pg_roles where rolname='service_role') then
  revoke update,delete,truncate on public.staff_audit from service_role;
  grant select,insert on public.staff_audit to service_role;
  grant execute on function public.create_cashier(uuid,uuid,text,text),public.record_staff_signin(uuid,integer,text) to service_role;
 end if;
end $$;
