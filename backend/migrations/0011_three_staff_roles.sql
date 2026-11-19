-- Exactly three operational roles. Apply as migration owner, outside opening
-- hours after a verified backup. Existing receipts/audit snapshots are untouched.
do $$begin
 if (select count(*) from public.profiles where role='owner')>1 then
  raise check_violation using message='Resolve multiple legacy owners before migrating to superadmin';
 end if;
 if exists(select 1 from public.profiles where role not in ('owner','manager','kitchen','admin','cashier','superadmin')) then
  raise check_violation using message='Unknown staff role; operator review required';
 end if;
end $$;

alter table public.profiles drop constraint profiles_role_check;
do $$declare p record; next_role text; begin
 for p in select id,role from public.profiles where role in ('owner','manager','kitchen') for update loop
  next_role:=case p.role when 'owner' then 'superadmin' when 'manager' then 'admin' else 'cashier' end;
  perform tkm.revoke_staff_sessions(p.id);
  update public.profiles set role=next_role,session_version=session_version+1,
   staff_status=case when staff_status='disabled' or p.role='kitchen' then 'disabled' else 'invited' end where id=p.id;
  insert into public.staff_audit(target_id,action,details) values(p.id,'staff_role_migrated',jsonb_build_object('before_role',p.role,'after_role',next_role));
 end loop;
end $$;
alter table public.profiles add constraint profiles_role_check check(role in ('superadmin','admin','cashier'));
update public.settings set orders_enabled=false where id=1;

-- Preserve the existing authoritative checkout/payment code and its ACLs. Only
-- replace the known role predicates in these explicit, fixed function targets.
do $$declare fn regprocedure; original text; revised text; begin
 foreach fn in array array[
  'tkm.confirm_cash(uuid,uuid,bigint,integer)'::regprocedure,
  'tkm.complete_order(uuid,uuid)'::regprocedure,
  'tkm.review_order(uuid,uuid,integer,jsonb)'::regprocedure,
  'tkm.snapshot_cashier_name()'::regprocedure,
  'tkm.check_staff_session(uuid,integer)'::regprocedure,
  'public.record_staff_signin(uuid,integer,text)'::regprocedure
 ] loop
  original:=pg_get_functiondef(fn);
  revised:=replace(replace(replace(original,
   '(''admin'',''manager'',''cashier'',''owner'')','(''superadmin'',''admin'',''cashier'')'),
   '(''owner'',''admin'',''manager'',''cashier'')','(''superadmin'',''admin'',''cashier'')'),
   '(''owner'',''admin'',''manager'')','(''superadmin'',''admin'')');
  if revised=original then raise check_violation using message='Unexpected role predicate in '||fn::text;end if;
  execute revised;
 end loop;
end $$;

create function tkm.can_manage_staff(p_actor uuid,p_role text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor_role text;
begin
 select role into actor_role from public.profiles where id=p_actor and staff_status='active' for share;
 return coalesce((actor_role='superadmin' and p_role in ('admin','cashier')) or (actor_role='admin' and p_role='cashier'),false);
end $$;

create function public.create_staff_account(p_actor uuid,p_id uuid,p_name text,p_email text,p_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not tkm.can_manage_staff(p_actor,p_role) then raise insufficient_privilege;end if;
 if p_name is null or length(btrim(p_name)) not between 2 and 100 or p_name ~ '[[:cntrl:]]' or p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise check_violation;end if;
 insert into public.profiles(id,full_name,email,role,staff_status) values(p_id,btrim(p_name),lower(btrim(p_email)),p_role,'invited');
 insert into public.staff_audit(actor_id,target_id,action,details) values(p_actor,p_id,p_role||'_created',jsonb_build_object('role',p_role));
end $$;

create function public.manage_staff_account(p_actor uuid,p_target uuid,p_command text,p_name text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare before_row public.profiles; after_row public.profiles;
begin
 perform role from public.profiles where id=p_actor and staff_status='active' for share;
 select * into strict before_row from public.profiles where id=p_target;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,before_row.role) then raise insufficient_privilege;end if;
 select * into strict before_row from public.profiles where id=p_target for update;
 if not tkm.can_manage_staff(p_actor,before_row.role) then raise insufficient_privilege;end if;
 if p_command='rename' then
  if p_name is null or length(btrim(p_name)) not between 2 and 100 or p_name ~ '[[:cntrl:]]' then raise check_violation;end if;
  update public.profiles set full_name=btrim(p_name) where id=p_target;
 elsif p_command in ('disable','enable') then
  perform tkm.revoke_staff_sessions(p_target);
  update public.profiles set staff_status=case when p_command='disable' then 'disabled' else 'invited' end,session_version=session_version+1 where id=p_target;
 else raise check_violation;end if;
 select * into after_row from public.profiles where id=p_target;
 insert into public.staff_audit(actor_id,target_id,action,details) values(p_actor,p_target,p_command,jsonb_build_object('before',to_jsonb(before_row),'after',to_jsonb(after_row)));
 return to_jsonb(after_row);
end $$;

-- Backward-compatible cashier-only RPCs never create/promote an administrator.
create or replace function public.create_cashier(p_actor uuid,p_id uuid,p_name text,p_email text) returns void
language plpgsql security definer set search_path='' as $$
begin perform public.create_staff_account(p_actor,p_id,p_name,p_email,'cashier');end $$;
create or replace function public.manage_cashier(p_actor uuid,p_target uuid,p_command text,p_name text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_target and role='cashier') then raise insufficient_privilege;end if;
 return public.manage_staff_account(p_actor,p_target,p_command,p_name);
end $$;

create or replace function public.issue_staff_access(p_actor uuid,p_target uuid,p_hash text,p_purpose text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 perform role from public.profiles where id=p_actor and staff_status='active' for share;
 select * into strict p from public.profiles where id=p_target;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 select * into strict p from public.profiles where id=p_target for update;
 if not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if p.staff_status='disabled' or p_purpose not in ('activation','recovery') or p_purpose is null or p_hash is null or p_hash!~'^[a-f0-9]{64}$' then raise check_violation;end if;
 perform tkm.revoke_staff_sessions(p_target);
 update public.profiles set staff_status='invited',session_version=session_version+1 where id=p_target returning * into p;
 insert into public.staff_access_links(profile_id,token_hash,purpose,session_version,expires_at,created_by) values(p.id,p_hash,p_purpose,p.session_version,now()+interval '60 minutes',p_actor);
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p.id,'access_link_'||p_purpose);
 return to_jsonb(p);
end $$;

-- Pricing is a superadmin approval, rather than an admin/catalog operation.
do $$declare original text; begin
 original:=pg_get_functiondef('public.confirm_restaurant_pricing(uuid,numeric,numeric,boolean,boolean)'::regprocedure);
 if position('role in (''owner'',''admin'')' in original)=0 then raise check_violation;end if;
 execute replace(original,'role in (''owner'',''admin'')','role=''superadmin''');
end $$;

create function public.bootstrap_superadmin(p_id uuid,p_name text,p_email text,p_hash text) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer;
begin
 perform pg_advisory_xact_lock(hashtext('tkm-bootstrap-superadmin'));
 if p_id is null or p_name is null or length(btrim(p_name)) not between 2 and 100 or p_name ~ '[[:cntrl:]]' or p_email is null or p_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_hash is null or p_hash!~'^[a-f0-9]{64}$' then raise check_violation;end if;
 if exists(select 1 from public.profiles where role='superadmin' and (id<>p_id or staff_status<>'invited')) then raise insufficient_privilege;end if;
 if exists(select 1 from public.profiles where id=p_id and role<>'superadmin') then raise insufficient_privilege;end if;
 insert into public.profiles(id,full_name,email,role,staff_status,session_version) values(p_id,btrim(p_name),lower(p_email),'superadmin','invited',1)
 on conflict(id) do update set session_version=profiles.session_version+1 returning session_version into version;
 insert into public.staff_access_links(profile_id,token_hash,purpose,session_version,expires_at) values(p_id,p_hash,'activation',version,now()+interval '60 minutes');
 perform tkm.revoke_staff_sessions(p_id);
 insert into public.staff_audit(target_id,action) values(p_id,'superadmin_bootstrap');
 return version;
end $$;
drop function public.bootstrap_owner(uuid,text,text,text);

revoke all on function tkm.can_manage_staff(uuid,text),public.create_staff_account(uuid,uuid,text,text,text),public.manage_staff_account(uuid,uuid,text,text),public.bootstrap_superadmin(uuid,text,text,text) from public;
do $$declare api_role text; fn regprocedure; begin
 foreach api_role in array array['anon','authenticated','tkm_runtime'] loop
  if exists(select 1 from pg_roles where rolname=api_role) then
   for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='public' and p.proname in ('create_staff_account','manage_staff_account','bootstrap_superadmin')) or (n.nspname='tkm' and p.proname='can_manage_staff') loop
    execute format('revoke all on function %s from %I',fn,api_role);
   end loop;
  end if;
 end loop;
 if exists(select 1 from pg_roles where rolname='service_role') then
  grant execute on function public.create_staff_account(uuid,uuid,text,text,text),public.manage_staff_account(uuid,uuid,text,text),public.bootstrap_superadmin(uuid,text,text,text) to service_role;
 end if;
end $$;
