-- Disposable database only; fake Auth rows never leave this rolled-back test.
begin;
create schema if not exists auth;
create table if not exists auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,encrypted_password text,raw_app_meta_data jsonb);
create table if not exists auth.sessions(id uuid primary key,user_id uuid);
do $$
declare root uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); cashier uuid:=gen_random_uuid(); other uuid:=gen_random_uuid();
 p jsonb; version integer; audit_count integer; r text; f regprocedure;
begin
 insert into public.profiles(id,full_name,email,role,staff_status) values
 (root,'Root Test','direct-root@example.test','superadmin','active'),(admin_id,'Admin Test','direct-admin@example.test','admin','active');
 p:=public.reserve_staff_account(admin_id,cashier,'Kasir Test','direct-cashier@example.test','kasir.test','cashier');
 if p->>'staff_status'<>'invited' or p->>'username'<>'kasir.test' then raise exception 'Reservation activated prematurely';end if;
 begin perform tkm.check_staff_session(cashier,1);raise exception 'Unprovisioned account accepted';exception when insufficient_privilege then null;end;
 begin perform public.finish_staff_password(admin_id,cashier,1);raise exception 'Missing Auth credentials accepted';exception when check_violation then null;end;
 begin perform public.reserve_staff_account(root,other,'Duplicate','duplicate@example.test','kasir.test','cashier');raise exception 'Duplicate username accepted';exception when unique_violation then null;end;
 begin perform public.reserve_staff_account(root,other,'Uppercase','upper@example.test','Bad.User','cashier');raise exception 'Noncanonical username accepted';exception when check_violation then null;end;
 begin perform public.reserve_staff_account(admin_id,other,'Forbidden','forbidden@example.test','forbidden','admin');raise exception 'Admin elevated role';exception when insufficient_privilege then null;end;
 begin perform public.begin_staff_password(root,root);raise exception 'Self reset accepted';exception when insufficient_privilege then null;end;
 insert into auth.users(id,email,email_confirmed_at,encrypted_password,raw_app_meta_data) values(cashier,'direct-cashier@example.test',now(),'isolated-fake-hash','{"staff_session_version":1}');
 p:=public.finish_staff_password(admin_id,cashier,1);
 if p->>'staff_status'<>'active' then raise exception 'Provisioned account not active';end if;
 perform tkm.check_staff_session(cashier,1);
 insert into auth.sessions(id,user_id) values(gen_random_uuid(),cashier);
 insert into public.staff_access_links(profile_id,token_hash,purpose,session_version,expires_at) values(cashier,repeat('f',64),'recovery',1,now()+interval '1 hour');
 p:=public.begin_staff_password(admin_id,cashier); version:=(p->>'session_version')::integer;
 if exists(select 1 from auth.sessions where user_id=cashier) or exists(select 1 from public.staff_access_links where profile_id=cashier and used_at is null) then raise exception 'Old sessions or links survived reset';end if;
 begin perform tkm.check_staff_session(cashier,1);raise exception 'Old JWT accepted';exception when insufficient_privilege then null;end;
 begin perform public.finish_staff_password(admin_id,cashier,version);raise exception 'Old Auth version accepted';exception when check_violation then null;end;
 update auth.users set raw_app_meta_data=jsonb_build_object('staff_session_version',version) where id=cashier;
 perform public.manage_staff_account(root,cashier,'disable');
 begin perform public.finish_staff_password(admin_id,cashier,version);raise exception 'Concurrent disable bypassed';exception when check_violation then null;end;
 begin perform public.begin_staff_password(admin_id,cashier,false);raise exception 'Disabled account silently reactivated';exception when check_violation then null;end;
 p:=public.begin_staff_password(admin_id,cashier,true); version:=(p->>'session_version')::integer;
 update auth.users set raw_app_meta_data=jsonb_build_object('staff_session_version',version) where id=cashier;
 update public.profiles set staff_status='disabled' where id=admin_id;
 begin perform public.finish_staff_password(admin_id,cashier,version);raise exception 'Disabled actor completed reset';exception when insufficient_privilege then null;end;
 perform public.finish_staff_password(root,cashier,version);perform tkm.check_staff_session(cashier,version);
 p:=public.reserve_staff_account(root,other,'Incomplete','incomplete@example.test','incomplete','admin');
 perform public.discard_staff_reservation(root,other);
 if exists(select 1 from public.profiles where id=other) then raise exception 'Failed reservation not discarded';end if;
 begin perform public.discard_staff_reservation(root,cashier);raise exception 'Active identity discarded';exception when check_violation then null;end;
 select count(*) into audit_count from public.staff_audit where actor_id in(root,admin_id) and action='staff_password_set';
 if audit_count<>2 then raise exception 'Password changes not audited';end if;
 if exists(select 1 from public.staff_audit where actor_id in(root,admin_id) and details::text like '%isolated-fake-hash%') then raise exception 'Credentials leaked to audit';end if;
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
  foreach f in array array['public.reserve_staff_account(uuid,uuid,text,text,text,text)'::regprocedure,'public.begin_staff_password(uuid,uuid,boolean)'::regprocedure,'public.finish_staff_password(uuid,uuid,integer)'::regprocedure,'public.discard_staff_reservation(uuid,uuid)'::regprocedure] loop
   if has_function_privilege(r,f,'EXECUTE') then raise exception '% can manage staff through %',r,f;end if;
  end loop;
 end loop;
end $$;
rollback;
