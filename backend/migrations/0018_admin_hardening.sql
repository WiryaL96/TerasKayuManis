-- Admin audit remediation. Additive and reversible account archival.
alter table public.profiles add column archived_at timestamptz;
create table tkm.staff_edits(profile_id uuid primary key references public.profiles(id), keep_disabled boolean not null);
revoke all on tkm.staff_edits from public;

create function tkm.guard_archived_staff() returns trigger language plpgsql set search_path='' as $$
begin
 if new.archived_at is not null and new.staff_status<>'disabled' then raise check_violation using message='Archived staff cannot be activated';end if;
 return new;
end $$;
create trigger guard_archived_staff before insert or update on public.profiles for each row execute function tkm.guard_archived_staff();

create function public.begin_staff_edit(p_actor uuid,p_target uuid,p_name text,p_email text,p_username text,p_role text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles; old_role text;
begin
 perform role from public.profiles where id=p_actor and staff_status='active' for share;
 select * into strict p from public.profiles where id=p_target for update;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,p.role) or not tkm.can_manage_staff(p_actor,p_role) then raise insufficient_privilege;end if;
 if p.archived_at is not null then raise check_violation;end if;
 if p_name is null or length(btrim(p_name)) not between 2 and 100 or p_name ~ '[[:cntrl:]]' or p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_username is null or p_username !~ '^[a-z0-9][a-z0-9._-]{2,31}$' then raise check_violation;end if;
 old_role:=p.role;
 insert into tkm.staff_edits values(p_target,p.staff_status='disabled') on conflict(profile_id) do nothing;
 perform tkm.revoke_staff_sessions(p_target);
 update public.staff_access_links set used_at=now() where profile_id=p_target and used_at is null;
 update public.profiles set full_name=btrim(p_name),email=lower(btrim(p_email)),username=p_username,role=p_role,staff_status='invited',session_version=session_version+1,cashier_pin_enabled=false where id=p_target returning * into p;
 insert into public.staff_audit(actor_id,target_id,action,details) values(p_actor,p_target,'staff_edit_started',jsonb_build_object('before_role',old_role,'after_role',p_role));
 return to_jsonb(p);
end $$;

create function public.finish_staff_edit(p_actor uuid,p_target uuid,p_version integer,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles; disabled boolean;
begin
 select * into strict p from public.profiles where id=p_target for update;
 select keep_disabled into strict disabled from tkm.staff_edits where profile_id=p_target;
 perform public.finish_staff_credential(p_actor,p_target,p_version,p_method);
 if disabled then update public.profiles set staff_status='disabled' where id=p_target;end if;
 delete from tkm.staff_edits where profile_id=p_target;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_updated');
 select * into p from public.profiles where id=p_target;
 return to_jsonb(p);
end $$;

create function public.archive_staff_account(p_actor uuid,p_target uuid,p_restore boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 perform role from public.profiles where id=p_actor and staff_status='active' for share;
 select * into strict p from public.profiles where id=p_target for update;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 perform tkm.revoke_staff_sessions(p_target);
 update public.staff_access_links set used_at=now() where profile_id=p_target and used_at is null;
 update public.profiles set archived_at=case when p_restore then null else coalesce(archived_at,now()) end,staff_status='disabled',session_version=session_version+1 where id=p_target returning * into p;
 delete from tkm.staff_edits where profile_id=p_target;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,case when p_restore then 'staff_restored' else 'staff_archived' end);
 return to_jsonb(p);
end $$;

create function public.save_restaurant_settings(p_actor uuid,p_brand text,p_tagline text,p_tax numeric,p_service numeric,p_name_required boolean,p_enabled boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if p_brand is null or length(btrim(p_brand)) not between 1 and 50 or p_brand ~ '[[:cntrl:]]' or p_tagline is null or length(p_tagline)>100 or p_tagline ~ '[[:cntrl:]]' then raise check_violation;end if;
 perform public.confirm_restaurant_pricing(p_actor,p_tax,p_service,p_name_required,p_enabled);
 update public.settings set brand_name=btrim(p_brand),tagline=btrim(p_tagline) where id=1 returning to_jsonb(settings.*) into result;
 return result;
end $$;

-- Trusted browsers have an independent guess budget. The server validates a signed,
-- HttpOnly device token; raw caller-supplied device IDs never reach this RPC.
create table tkm.cashier_device_attempts(cashier_id uuid references public.profiles(id), device_hash text, attempts integer not null, window_start timestamptz not null default now(),primary key(cashier_id,device_hash));
revoke all on tkm.cashier_device_attempts from public;
create function public.claim_trusted_cashier_attempt(p_cashier uuid,p_device text,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles; used integer;
begin
 select * into p from public.profiles where id=p_cashier and role='cashier' and staff_status='active' and cashier_pin_enabled and archived_at is null and session_version=p_version for share;
 if not found or p_device is null or p_device!~'^[a-f0-9]{64}$' then return public.claim_cashier_pin_attempt(p_cashier);end if;
 delete from tkm.cashier_device_attempts where window_start<now()-interval '1 day';
 insert into tkm.cashier_device_attempts(cashier_id,device_hash,attempts) values(p_cashier,p_device,1)
 on conflict(cashier_id,device_hash) do update set
 attempts=case when cashier_device_attempts.window_start<=now()-interval '15 minutes' then 1 else cashier_device_attempts.attempts+1 end,
 window_start=case when cashier_device_attempts.window_start<=now()-interval '15 minutes' then now() else cashier_device_attempts.window_start end
 where cashier_device_attempts.attempts<5 or cashier_device_attempts.window_start<=now()-interval '15 minutes' returning attempts into used;
 if not found then raise exception using errcode='P0001',message='PIN_ATTEMPTS_EXCEEDED';end if;
 return jsonb_build_object('id',p.id,'email',p.email,'session_version',p.session_version);
end $$;

do $$declare f regprocedure;r text;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in('begin_staff_edit','finish_staff_edit','archive_staff_account','save_restaurant_settings','claim_trusted_cashier_attempt')) or (n.nspname='tkm' and p.proname='guard_archived_staff') loop
 execute format('revoke all on function %s from public',f);
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
 if to_regrole(r) is not null then execute format('revoke all on function %s from %I',f,r);end if;end loop;
 if to_regrole('service_role') is not null then execute format('grant execute on function %s to service_role',f);end if;
 end loop;
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
 if to_regrole(r) is not null then execute format('revoke all on tkm.staff_edits,tkm.cashier_device_attempts from %I',r);end if;end loop;
end $$;
create function public.finish_trusted_cashier_login(p_actor uuid,p_version integer,p_device text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=public.finish_cashier_pin_login(p_actor,p_version);
 delete from tkm.cashier_device_attempts where cashier_id=p_actor and device_hash=p_device;
 return result;
end $$;
revoke all on function public.finish_trusted_cashier_login(uuid,integer,text) from public;
do $$declare r text;begin
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
 if to_regrole(r) is not null then execute format('revoke all on function public.finish_trusted_cashier_login(uuid,integer,text) from %I',r);end if;end loop;
 if to_regrole('service_role') is not null then grant execute on function public.finish_trusted_cashier_login(uuid,integer,text) to service_role;end if;
end $$;
-- An explicit credential reset supersedes an unfinished identity edit. Otherwise
-- its saved disabled flag could incorrectly affect a later, unrelated edit.
create or replace function public.begin_staff_password(p_actor uuid,p_target uuid,p_reactivate boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 if p_actor=p_target then raise insufficient_privilege;end if;
 select * into strict p from public.profiles where id=p_target for update;
 if not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if p.archived_at is not null or nullif(btrim(p.full_name),'') is null or nullif(p.email,'') is null or (p.staff_status='disabled' and p_reactivate is distinct from true) then raise check_violation;end if;
 delete from tkm.staff_edits where profile_id=p_target;
 perform tkm.revoke_staff_sessions(p_target);
 update public.staff_access_links set used_at=now() where profile_id=p_target and used_at is null;
 update public.profiles set staff_status='invited',session_version=session_version+1 where id=p_target returning * into p;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_password_started');
 return to_jsonb(p);
end $$;
