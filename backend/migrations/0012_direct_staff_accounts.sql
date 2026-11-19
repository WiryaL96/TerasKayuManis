-- Additive: existing staff continue using their email; no passwords or histories change.
alter table public.profiles add column username text;
alter table public.profiles add constraint profiles_username_check check(username is null or (username=lower(btrim(username)) and username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'));
create unique index profiles_username_unique on public.profiles(username) where username is not null;

create function public.reserve_staff_account(p_actor uuid,p_id uuid,p_name text,p_email text,p_username text,p_role text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 if p_username is null or p_username !~ '^[a-z0-9][a-z0-9._-]{2,31}$' then raise check_violation;end if;
 perform public.create_staff_account(p_actor,p_id,p_name,p_email,p_role);
 update public.profiles set username=p_username,session_version=1 where id=p_id returning * into p;
 return to_jsonb(p);
end $$;

create function public.begin_staff_password(p_actor uuid,p_target uuid,p_reactivate boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 if p_actor=p_target then raise insufficient_privilege;end if;
 select * into strict p from public.profiles where id=p_target for update;
 if not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if nullif(btrim(p.full_name),'') is null or nullif(p.email,'') is null or (p.staff_status='disabled' and p_reactivate is distinct from true) then raise check_violation;end if;
 perform tkm.revoke_staff_sessions(p_target);
 update public.staff_access_links set used_at=now() where profile_id=p_target and used_at is null;
 update public.profiles set staff_status='invited',session_version=session_version+1 where id=p_target returning * into p;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_password_started');
 return to_jsonb(p);
end $$;

create function public.finish_staff_password(p_actor uuid,p_target uuid,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 if p_actor=p_target then raise insufficient_privilege;end if;
 select * into strict p from public.profiles where id=p_target for update;
 if not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if p.staff_status<>'invited' or p.session_version is distinct from p_version then raise check_violation;end if;
 -- Confirm that Auth really stored credentials for this exact profile/version.
 if not exists(select 1 from auth.users u where u.id=p_target and lower(u.email)=lower(p.email)
  and u.email_confirmed_at is not null and length(u.encrypted_password)>0
  and u.raw_app_meta_data->>'staff_session_version'=p_version::text) then raise check_violation;end if;
 perform tkm.revoke_staff_sessions(p_target);
 update public.profiles set staff_status='active' where id=p_target returning * into p;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_password_set');
 return to_jsonb(p);
end $$;

create function public.discard_staff_reservation(p_actor uuid,p_target uuid) returns void
language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into strict p from public.profiles where id=p_target for update;
 if p_actor=p_target or not tkm.can_manage_staff(p_actor,p.role) then raise insufficient_privilege;end if;
 if p.staff_status<>'invited' or p.session_version<>1 or exists(select 1 from auth.users where id=p_target) then raise check_violation;end if;
 insert into public.staff_audit(actor_id,target_id,action) values(p_actor,p_target,'staff_creation_failed');
 delete from public.profiles where id=p_target;
end $$;

revoke all on function public.reserve_staff_account(uuid,uuid,text,text,text,text),public.begin_staff_password(uuid,uuid,boolean),public.finish_staff_password(uuid,uuid,integer),public.discard_staff_reservation(uuid,uuid) from public;
do $$declare r text; f regprocedure; begin
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
  if to_regrole(r) is not null then
   foreach f in array array['public.reserve_staff_account(uuid,uuid,text,text,text,text)'::regprocedure,'public.begin_staff_password(uuid,uuid,boolean)'::regprocedure,'public.finish_staff_password(uuid,uuid,integer)'::regprocedure,'public.discard_staff_reservation(uuid,uuid)'::regprocedure] loop
    execute format('revoke all on function %s from %I',f,r);
   end loop;
  end if;
 end loop;
 if to_regrole('service_role') is not null then
  grant execute on function public.reserve_staff_account(uuid,uuid,text,text,text,text),public.begin_staff_password(uuid,uuid,boolean),public.finish_staff_password(uuid,uuid,integer),public.discard_staff_reservation(uuid,uuid) to service_role;
 end if;
end $$;
