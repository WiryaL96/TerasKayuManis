-- Serverless coordination contains no credentials, customer payloads or tokens.
create table tkm.order_clock(id integer primary key check(id=1),revision bigint not null default 0);
insert into tkm.order_clock values(1,0);
create function tkm.bump_order_clock() returns trigger language plpgsql security definer set search_path='' as $$
begin update tkm.order_clock set revision=revision+1 where id=1; return null; end $$;
create trigger order_sync_clock after insert or update or delete on public.orders for each row execute function tkm.bump_order_clock();
revoke all on tkm.order_clock from public;
grant select on tkm.order_clock to tkm_runtime;
revoke all on function tkm.bump_order_clock() from public;
create index if not exists checkout_capability_lookup on tkm.checkout_keys(order_id,access_hash);
create index if not exists order_addon_lookup on public.order_item_addons(order_item_id);
create index if not exists pending_expiry_lookup on public.orders(created_at) where status='pending' and payment_status='unpaid';

create table tkm.request_budgets(key text primary key,used integer not null,until_at timestamptz not null);
revoke all on tkm.request_budgets from public;
create function tkm.claim_request_budget(k text,capacity integer) returns boolean
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if length(k)>200 or capacity not between 1 and 2000 then raise invalid_parameter_value;end if;
 insert into tkm.request_budgets values(k,1,clock_timestamp()+interval '1 minute')
 on conflict(key) do update set used=case when tkm.request_budgets.until_at<=clock_timestamp() then 1 else least(tkm.request_budgets.used+1,2001) end,
 until_at=case when tkm.request_budgets.until_at<=clock_timestamp() then clock_timestamp()+interval '1 minute' else tkm.request_budgets.until_at end
 returning used into n;
 return n<=capacity;
end $$;
revoke all on function tkm.claim_request_budget(text,integer) from public;
grant execute on function tkm.claim_request_budget(text,integer) to tkm_runtime;
create function public.claim_sensitive_budget(p_key text,p_limit integer) returns boolean language sql security definer set search_path='' as $$
 select tkm.claim_request_budget('sensitive:'||p_key,p_limit)
$$;
revoke all on function public.claim_sensitive_budget(text,integer) from public;
grant execute on function public.claim_sensitive_budget(text,integer) to service_role;

create function tkm.serverless_maintenance() returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if not pg_try_advisory_xact_lock(94615) then return 0;end if;
 perform tkm.expire_orders();
 delete from tkm.request_budgets where until_at<clock_timestamp()-interval '1 hour';
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function tkm.serverless_maintenance() from public;
grant execute on function tkm.serverless_maintenance() to tkm_runtime;

create table tkm.backup_status(id integer primary key check(id=1),result text not null,last_attempt timestamptz not null,last_success timestamptz,restore_verified_at timestamptz);
revoke all on tkm.backup_status from public;
create function public.read_backup_status(p_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_actor and role='superadmin' and staff_status='active') then raise insufficient_privilege;end if;
 return coalesce((select to_jsonb(b)-'id' from tkm.backup_status b where id=1),'{}'::jsonb);
end $$;
create function public.record_backup_status(p_result text,p_restore_verified boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_result not in ('success','failed') then raise invalid_parameter_value;end if;
 insert into tkm.backup_status values(1,p_result,now(),case when p_result='success' then now() end,case when p_restore_verified then now() end)
 on conflict(id) do update set result=excluded.result,last_attempt=excluded.last_attempt,last_success=coalesce(excluded.last_success,tkm.backup_status.last_success),restore_verified_at=coalesce(excluded.restore_verified_at,tkm.backup_status.restore_verified_at);
end $$;
revoke all on function public.read_backup_status(uuid),public.record_backup_status(text,boolean) from public;
grant execute on function public.read_backup_status(uuid),public.record_backup_status(text,boolean) to service_role;
