-- Read-only, revocable notification leases. No Supabase credentials are stored.
create table tkm.watch_leases (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 actor uuid not null references public.profiles(id),
 device_id uuid not null,
 session_version integer not null,
 expires_at timestamptz not null,
 unique(actor,device_id)
);
alter table tkm.watch_leases enable row level security;
revoke all on tkm.watch_leases from public,anon,authenticated,service_role;
grant select,delete on tkm.watch_leases to tkm_runtime;
create policy runtime_access on tkm.watch_leases for all to tkm_runtime using(true) with check(true);
create index watch_expiry on tkm.watch_leases(expires_at);
create index if not exists mobile_order_created on public.orders(created_at desc,id);
create index if not exists mobile_created_events on tkm.outbox_events(created_at desc) where event_type='ORDER_CREATED';

create function tkm.issue_watch(p_actor uuid,p_device uuid,p_version integer,p_hash text)
returns timestamptz language plpgsql security definer set search_path='' as $$
declare expiry timestamptz:=clock_timestamp()+interval '5 hours 30 minutes';
begin
 -- Serialize issuance and account disable/credential changes on the same profile.
 perform id from public.profiles where id=p_actor for update;
 perform tkm.check_staff_session(p_actor,p_version);
 delete from tkm.watch_leases where expires_at<=clock_timestamp();
 if (select count(*) from tkm.watch_leases where actor=p_actor and device_id<>p_device)>=5 then
  raise check_violation using message='Too many notification devices';
 end if;
 insert into tkm.watch_leases values(p_hash,p_actor,p_device,p_version,expiry)
 on conflict(actor,device_id) do update set token_hash=excluded.token_hash,
 session_version=excluded.session_version,expires_at=excluded.expires_at;
 return expiry;
end $$;
revoke all on function tkm.issue_watch(uuid,uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function tkm.issue_watch(uuid,uuid,integer,text) to tkm_runtime;

create or replace function tkm.serverless_maintenance() returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if not pg_try_advisory_xact_lock(94615) then return 0;end if;
 perform tkm.expire_orders();
 delete from tkm.watch_leases where expires_at<clock_timestamp();
 delete from tkm.request_budgets where until_at<clock_timestamp()-interval '1 hour';
 get diagnostics n=row_count;
 return n;
end $$;
