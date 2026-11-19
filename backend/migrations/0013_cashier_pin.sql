-- Additive. Existing staff keep their credentials until an admin sets a PIN.
alter table public.profiles add column cashier_pin_enabled boolean not null default false;
alter table public.profiles add column staff_photo_path text;
alter table public.profiles add constraint staff_photo_path_check check(staff_photo_path is null or staff_photo_path ~ '^[a-f0-9-]{36}/[a-f0-9-]{36}\.webp$');

create table tkm.cashier_pin_attempts(
 cashier_id uuid primary key references public.profiles(id), attempts integer not null,
 window_start timestamptz not null default now()
);
revoke all on tkm.cashier_pin_attempts from public;

create function public.finish_staff_credential(p_actor uuid,p_target uuid,p_version integer,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into strict p from public.profiles where id=p_target for update;
 if p_method is null or p_method not in('pin','password') or (p_method='pin' and p.role<>'cashier') then raise check_violation;end if;
 if not exists(select 1 from auth.users u where u.id=p_target and u.raw_app_meta_data->>'staff_access_method'=p_method) then raise check_violation;end if;
 perform public.finish_staff_password(p_actor,p_target,p_version);
 update public.profiles set cashier_pin_enabled=(p_method='pin') where id=p_target returning * into p;
 delete from tkm.cashier_pin_attempts where cashier_id=p_target;
 if p_method='pin' then insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'cashier_pin_set');end if;
 return to_jsonb(p);
end $$;

create function public.set_staff_photo(p_actor uuid,p_target uuid,p_path text) returns void
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into strict p from public.profiles where id=p_target for update;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if p_path is not null and (p_path!~'^[a-f0-9-]{36}/[a-f0-9-]{36}\.webp$' or split_part(p_path,'/',1)<>p_actor::text) then raise check_violation;end if;
 update public.profiles set staff_photo_path=p_path where id=p_target;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_photo_updated');
end $$;

-- Reserve a guess before calling Auth. Shared across IPs, workers and devices.
create function public.claim_cashier_pin_attempt(p_cashier uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles; used integer;
begin
 select * into p from public.profiles where id=p_cashier and role='cashier' and staff_status='active' and cashier_pin_enabled and nullif(btrim(full_name),'') is not null for share;
 if not found then return null;end if;
 insert into tkm.cashier_pin_attempts(cashier_id,attempts) values(p_cashier,1)
 on conflict(cashier_id) do update set
 attempts=case when cashier_pin_attempts.window_start<=now()-interval '15 minutes' then 1 else cashier_pin_attempts.attempts+1 end,
 window_start=case when cashier_pin_attempts.window_start<=now()-interval '15 minutes' then now() else cashier_pin_attempts.window_start end
 where cashier_pin_attempts.attempts<5 or cashier_pin_attempts.window_start<=now()-interval '15 minutes'
 returning attempts into used;
 if not found then raise exception using errcode='P0001',message='PIN_ATTEMPTS_EXCEEDED';end if;
 return jsonb_build_object('id',p.id,'email',p.email,'session_version',p.session_version);
end $$;

create function public.finish_cashier_pin_login(p_actor uuid,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role='cashier' and cashier_pin_enabled) then raise insufficient_privilege;end if;
 p:=public.record_staff_signin(p_actor,p_version,'cashier');
 delete from tkm.cashier_pin_attempts where cashier_id=p_actor;
 return p||jsonb_build_object('session_version',p_version);
end $$;

-- Staff photographs never share the public product-media bucket.
do $$begin
 if to_regclass('storage.buckets') is not null then
  insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('staff-photos','staff-photos',false,2097152,array['image/webp']) on conflict(id) do nothing;
  if exists(select 1 from storage.buckets where id='staff-photos' and public) then raise check_violation using message='Staff photo bucket must be private';end if;
 end if;
end $$;

revoke all on function public.finish_staff_credential(uuid,uuid,integer,text),public.set_staff_photo(uuid,uuid,text),public.claim_cashier_pin_attempt(uuid),public.finish_cashier_pin_login(uuid,integer) from public;
do $$declare r text; f regprocedure;begin
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
  if to_regrole(r) is not null then
   execute format('revoke all on tkm.cashier_pin_attempts from %I',r);
   for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('finish_staff_credential','set_staff_photo','claim_cashier_pin_attempt','finish_cashier_pin_login') loop
    execute format('revoke all on function %s from %I',f,r);
   end loop;
  end if;
 end loop;
 if to_regrole('service_role') is not null then
  grant execute on function public.finish_staff_credential(uuid,uuid,integer,text),public.set_staff_photo(uuid,uuid,text),public.claim_cashier_pin_attempt(uuid),public.finish_cashier_pin_login(uuid,integer) to service_role;
 end if;
end $$;
