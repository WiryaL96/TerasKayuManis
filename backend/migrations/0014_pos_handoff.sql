-- Self-order is a companion to the restaurant's separate POS. Do not create
-- payments, cash received/change, or rewrite historical payment records.
alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check
 check(status in ('pending','pos_input','forwarded','confirmed','completed','cancelled','expired'));

create table public.order_pos_handoffs(
 order_id uuid primary key references public.orders(id),
 cashier_id uuid not null references public.profiles(id),
 cashier_name text not null check(length(btrim(cashier_name))>0),
 claimed_at timestamptz not null default clock_timestamp(),
 claimed_version integer not null,
 forwarded_at timestamptz,
 reassign_reason text,
 pos_reference text check(length(pos_reference)<=80 and pos_reference !~ '[[:cntrl:]]')
);
create index pos_handoffs_time on public.order_pos_handoffs(forwarded_at,cashier_id) where forwarded_at is not null;
alter table public.order_pos_handoffs enable row level security;
revoke all on public.order_pos_handoffs from public;
grant select,insert,update on public.order_pos_handoffs to tkm_runtime;
create policy runtime_access on public.order_pos_handoffs for all to tkm_runtime using(true) with check(true);

create function tkm.audit_pos_handoff() returns trigger
language plpgsql security definer set search_path='' as $$
declare action_name text;
begin
 if tg_op='UPDATE' and old.forwarded_at is not null then raise insufficient_privilege using message='POS handoff is immutable';end if;
 if tg_op='INSERT' or old.cashier_id is distinct from new.cashier_id then
  select full_name into new.cashier_name from public.profiles where id=new.cashier_id;
  if nullif(btrim(new.cashier_name),'') is null then raise check_violation using message='Cashier name required';end if;
  action_name:=case when tg_op='INSERT' then 'pos_claimed' else 'pos_reassigned' end;
 else
  new.cashier_name:=old.cashier_name;
  action_name:='pos_forwarded';
 end if;
 insert into public.staff_audit(actor_id,order_id,action,details)
 values(new.cashier_id,new.order_id,action_name,jsonb_build_object('order_number',(select order_number from public.orders where id=new.order_id),'pos_reference',new.pos_reference,'previous_cashier_id',case when tg_op='UPDATE' then old.cashier_id else null end,'reason',new.reassign_reason));
 return new;
end $$;
create trigger pos_handoff_audit before insert or update on public.order_pos_handoffs for each row execute function tkm.audit_pos_handoff();

create or replace function tkm.order_json(oid uuid) returns jsonb language sql stable set search_path='' as $$
 select to_jsonb(o)||jsonb_build_object('expires_at',o.created_at+interval '15 minutes',
 'tables',case when t.id is null then null else jsonb_build_object('number',t.number) end,
 'pos_handoff',(select jsonb_build_object('cashier_id',h.cashier_id,'cashier_name',h.cashier_name,'claimed_at',h.claimed_at,'forwarded_at',h.forwarded_at,'pos_reference',h.pos_reference) from public.order_pos_handoffs h where h.order_id=o.id),
 'order_items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('order_item_addons',coalesce((select jsonb_agg(to_jsonb(a)) from public.order_item_addons a where a.order_item_id=i.id),'[]'::jsonb))) from public.order_items i where i.order_id=o.id),'[]'::jsonb))
 from public.orders o left join public.tables t on t.id=o.table_id where o.id=oid
$$;

create function tkm.claim_pos_order(oid uuid,actor uuid,expected integer,session_version integer,takeover_reason text default '') returns jsonb
language plpgsql set search_path='' as $$
declare o public.orders; h public.order_pos_handoffs; actor_role text; actor_name text;
begin
 perform tkm.check_staff_session(actor,session_version);
 select role,full_name into actor_role,actor_name from public.profiles where id=actor;
 if nullif(btrim(actor_name),'') is null then raise check_violation using message='Cashier name required';end if;
 select * into o from public.orders where id=oid for update;
 if not found then raise no_data_found;end if;
 select * into h from public.order_pos_handoffs where order_id=oid;
 if o.status='pos_input' and h.cashier_id=actor and expected in (o.version,o.version-1) then return tkm.order_json(oid);end if;
 if expected is distinct from o.version or o.payment_status<>'unpaid' then raise check_violation using message='Stale order';end if;
 if o.status='pos_input' then
  if actor_role not in ('superadmin','admin') or takeover_reason is null or length(btrim(takeover_reason)) not between 5 and 200 or takeover_reason ~ '[[:cntrl:]]' then raise insufficient_privilege;end if;
  update public.order_pos_handoffs set cashier_id=actor,cashier_name=actor_name,claimed_at=clock_timestamp(),claimed_version=o.version+1,reassign_reason=btrim(takeover_reason) where order_id=oid;
 elsif o.status='pending' and o.reviewed_version=o.version and o.created_at+interval '15 minutes'>clock_timestamp() then
  insert into public.order_pos_handoffs(order_id,cashier_id,cashier_name,claimed_version) values(oid,actor,actor_name,o.version+1);
 else raise check_violation using message='Review an unexpired pending order first';end if;
 update public.orders set status='pos_input',version=version+1,updated_at=clock_timestamp() where id=oid;
 insert into public.order_status_history(order_id,old_status,new_status,changed_by) values(oid,o.status,'pos_input',actor);
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_POS_CLAIMED',o.version+1);
 return tkm.order_json(oid);
end $$;

create function tkm.forward_pos_order(oid uuid,actor uuid,expected integer,session_version integer,reference text default '') returns jsonb
language plpgsql set search_path='' as $$
declare o public.orders; h public.order_pos_handoffs; ref text:=nullif(btrim(reference),'');
begin
 perform tkm.check_staff_session(actor,session_version);
 if reference is null or length(reference)>80 or reference ~ '[[:cntrl:]]' then raise check_violation using message='Invalid POS reference';end if;
 select * into o from public.orders where id=oid for update;
 if not found then raise no_data_found;end if;
 select * into h from public.order_pos_handoffs where order_id=oid;
 if h.cashier_id is distinct from actor then raise insufficient_privilege;end if;
 if o.status='forwarded' and h.claimed_version=expected and h.pos_reference is not distinct from ref then return tkm.order_json(oid);end if;
 if o.status<>'pos_input' or expected is distinct from o.version or o.payment_status<>'unpaid' then raise check_violation using message='Stale or already handled order';end if;
 update public.order_pos_handoffs set forwarded_at=clock_timestamp(),pos_reference=ref where order_id=oid;
 update public.orders set status='forwarded',version=version+1,updated_at=clock_timestamp() where id=oid;
 insert into public.order_status_history(order_id,old_status,new_status,changed_by) values(oid,'pos_input','forwarded',actor);
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_POS_FORWARDED',o.version+1);
 return tkm.order_json(oid);
end $$;

revoke all on function tkm.audit_pos_handoff(),tkm.claim_pos_order(uuid,uuid,integer,integer,text),tkm.forward_pos_order(uuid,uuid,integer,integer,text) from public;
do $$declare r text; fn regprocedure;begin
 foreach r in array array['anon','authenticated','service_role'] loop
  if to_regrole(r) is not null then
   execute format('revoke all on public.order_pos_handoffs from %I',r);
   foreach fn in array array['tkm.audit_pos_handoff()'::regprocedure,'tkm.claim_pos_order(uuid,uuid,integer,integer,text)'::regprocedure,'tkm.forward_pos_order(uuid,uuid,integer,integer,text)'::regprocedure] loop
    execute format('revoke all on function %s from %I',fn,r);
   end loop;
  end if;
 end loop;
 if to_regrole('service_role') is not null then grant select on public.order_pos_handoffs to service_role;end if;
end $$;
grant execute on function tkm.claim_pos_order(uuid,uuid,integer,integer,text),tkm.forward_pos_order(uuid,uuid,integer,integer,text) to tkm_runtime;
