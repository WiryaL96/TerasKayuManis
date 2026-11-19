-- Apply as database owner after 0006, outside opening hours.
do $$begin
 if to_regclass('auth.sessions') is not null and not has_table_privilege(current_user,'auth.sessions','DELETE') then
  raise insufficient_privilege using message='Migration owner needs permission to revoke Supabase Auth sessions';
 end if;
end $$;
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists staff_status text not null default 'active' check(staff_status in ('invited','active','disabled'));
alter table public.profiles add column if not exists session_version integer not null default 0 check(session_version>=0);
create unique index if not exists profiles_email_unique on public.profiles(lower(email)) where email is not null;
grant select(staff_status,session_version) on public.profiles to tkm_runtime;
alter table public.settings add column if not exists pricing_confirmed_at timestamptz;
alter table public.settings add column if not exists pricing_confirmed_by uuid references public.profiles(id);
alter table public.settings add column if not exists orders_enabled boolean not null default false;
create index if not exists payments_created_at_idx on public.payments(created_at);

create table if not exists public.staff_audit (
 id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id),
 target_id uuid, action text not null, details jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.staff_access_links (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.profiles(id),
 token_hash text not null unique, purpose text not null check(purpose in ('activation','recovery')),
 session_version integer not null, expires_at timestamptz not null, used_at timestamptz,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
alter table public.staff_audit enable row level security;
alter table public.staff_access_links enable row level security;
revoke all on public.staff_audit,public.staff_access_links from public;

-- Version checks reject old access tokens; removing Auth sessions also prevents
-- old refresh tokens from obtaining the new version after reactivation.
create function tkm.revoke_staff_sessions(p_target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if to_regclass('auth.sessions') is null then raise insufficient_privilege using message='Supabase Auth session store required';end if;
 execute 'delete from auth.sessions where user_id=$1' using p_target;
end $$;
revoke all on function tkm.revoke_staff_sessions(uuid) from public;

create or replace function public.manage_cashier(p_actor uuid,p_target uuid,p_command text,p_name text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare before_row public.profiles; after_row public.profiles;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('owner','admin') and staff_status='active') then raise insufficient_privilege;end if;
 select * into strict before_row from public.profiles where id=p_target for update;
 if before_row.role<>'cashier' or p_actor=p_target then raise insufficient_privilege;end if;
 if p_command='rename' then
  if nullif(btrim(p_name),'') is null or length(p_name)>100 then raise check_violation;end if;
  update public.profiles set full_name=btrim(p_name) where id=p_target;
 elsif p_command in ('disable','enable') then
  perform tkm.revoke_staff_sessions(p_target);
  update public.profiles set staff_status=case when p_command='disable' then 'disabled' else 'invited' end,session_version=session_version+1 where id=p_target;
 else raise check_violation;
 end if;
 select * into after_row from public.profiles where id=p_target;
 insert into public.staff_audit(actor_id,target_id,action,details) values(p_actor,p_target,p_command,jsonb_build_object('before',to_jsonb(before_row),'after',to_jsonb(after_row)));
 return to_jsonb(after_row);
end $$;

create or replace function public.issue_staff_access(p_actor uuid,p_target uuid,p_hash text,p_purpose text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('owner','admin') and staff_status='active') then raise insufficient_privilege;end if;
 select * into strict p from public.profiles where id=p_target for update;
 if p.role<>'cashier' or p.staff_status='disabled' or p_purpose not in ('activation','recovery') or p_hash!~'^[a-f0-9]{64}$' then raise check_violation;end if;
 perform tkm.revoke_staff_sessions(p_target);
 update public.profiles set staff_status='invited',session_version=session_version+1 where id=p_target returning * into p;
 insert into public.staff_access_links(profile_id,token_hash,purpose,session_version,expires_at,created_by) values(p.id,p_hash,p_purpose,p.session_version,now()+interval '60 minutes',p_actor);
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p.id,'access_link_'||p_purpose);
 return to_jsonb(p);
end $$;

create or replace function public.claim_staff_access(p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare link public.staff_access_links; p public.profiles;
begin
 select * into link from public.staff_access_links where token_hash=p_hash for update;
 if not found or link.used_at is not null or link.expires_at<=now() then return null;end if;
 select * into p from public.profiles where id=link.profile_id for update;
 if p.staff_status<>'invited' or p.session_version<>link.session_version then return null;end if;
 update public.staff_access_links set used_at=now() where id=link.id;
 return jsonb_build_object('profile_id',p.id,'purpose',link.purpose,'session_version',link.session_version);
end $$;

create or replace function public.finish_staff_access(p_target uuid,p_version integer) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 update public.profiles set staff_status='active' where id=p_target and staff_status='invited' and session_version=p_version;
 if not found then return false;end if;
 perform tkm.revoke_staff_sessions(p_target);
 insert into public.staff_audit(actor_id,target_id,action) values(p_target,p_target,'access_activated');
 return true;
end $$;

create or replace function public.confirm_restaurant_pricing(p_actor uuid,p_tax numeric,p_service numeric,p_name_required boolean,p_enabled boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result public.settings;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('owner','admin') and staff_status='active') then raise insufficient_privilege;end if;
 if p_tax not between 0 and 100 or p_service not between 0 and 100 or p_tax is null or p_service is null then raise check_violation;end if;
 if p_enabled and not exists(select 1 from public.profiles where role='cashier' and staff_status='active' and nullif(btrim(full_name),'') is not null and nullif(email,'') is not null) then raise check_violation using message='Activate a personal cashier before accepting orders';end if;
 update public.settings set tax_pct=p_tax,service_pct=p_service,require_customer_name=p_name_required,pricing_confirmed_at=now(),pricing_confirmed_by=p_actor,orders_enabled=p_enabled where id=1 returning * into result;
 insert into public.staff_audit(actor_id,action,details) values(p_actor,'pricing_confirmed',jsonb_build_object('tax',p_tax,'service',p_service,'orders_enabled',p_enabled));
 return to_jsonb(result);
end $$;

create or replace function tkm.check_staff_session(p_actor uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into p from public.profiles where id=p_actor for share;
 if not found or p.staff_status<>'active' or p.role not in ('owner','admin','manager','cashier') or p.session_version is distinct from p_version then raise insufficient_privilege;end if;
end $$;
create or replace function tkm.confirm_cash_verified(oid uuid,actor uuid,received bigint,version integer,session_version integer) returns jsonb language plpgsql set search_path='' as $$
begin perform tkm.check_staff_session(actor,session_version);return tkm.confirm_cash(oid,actor,received,version);end $$;
create or replace function tkm.review_order_verified(oid uuid,actor uuid,version integer,items jsonb,session_version integer) returns jsonb language plpgsql set search_path='' as $$
begin perform tkm.check_staff_session(actor,session_version);return tkm.review_order(oid,actor,version,items);end $$;
create or replace function tkm.complete_order_verified(oid uuid,actor uuid,session_version integer) returns jsonb language plpgsql set search_path='' as $$
begin perform tkm.check_staff_session(actor,session_version);return tkm.complete_order(oid,actor);end $$;
revoke all on function tkm.check_staff_session(uuid,integer),tkm.confirm_cash_verified(uuid,uuid,bigint,integer,integer),tkm.review_order_verified(uuid,uuid,integer,jsonb,integer),tkm.complete_order_verified(uuid,uuid,integer) from public;
grant execute on function tkm.check_staff_session(uuid,integer),tkm.confirm_cash_verified(uuid,uuid,bigint,integer,integer),tkm.review_order_verified(uuid,uuid,integer,jsonb,integer),tkm.complete_order_verified(uuid,uuid,integer) to tkm_runtime;

-- Existing checkout validates orders atomically. Preserve committed retries even
-- while ordering is paused; only a genuinely new order reaches this trigger.
create or replace function tkm.require_ordering_ready() returns trigger language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from public.settings where id=1 and orders_enabled and pricing_confirmed_at is not null) then raise check_violation using message='Restaurant is not accepting new orders';end if;
 return new;
end $$;
create trigger ordering_ready before insert on public.orders for each row execute function tkm.require_ordering_ready();
revoke all on function tkm.require_ordering_ready() from public;
grant execute on function tkm.require_ordering_ready() to tkm_runtime;

revoke all on function public.manage_cashier(uuid,uuid,text,text),public.issue_staff_access(uuid,uuid,text,text),public.claim_staff_access(text),public.finish_staff_access(uuid,integer),public.confirm_restaurant_pricing(uuid,numeric,numeric,boolean,boolean) from public;
do $$begin
 if exists(select 1 from pg_roles where rolname='service_role') then
  grant all on public.staff_audit,public.staff_access_links to service_role;
  grant execute on function public.manage_cashier(uuid,uuid,text,text),public.issue_staff_access(uuid,uuid,text,text),public.claim_staff_access(text),public.finish_staff_access(uuid,integer),public.confirm_restaurant_pricing(uuid,numeric,numeric,boolean,boolean) to service_role;
 end if;
end $$;
