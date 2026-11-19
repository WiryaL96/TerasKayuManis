-- Disposable database only. No real PINs or Auth credentials are provisioned.
begin;
create schema if not exists auth;
create table if not exists auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,encrypted_password text,raw_app_meta_data jsonb);
create table if not exists auth.sessions(id uuid primary key,user_id uuid);
do $$
declare root uuid:=gen_random_uuid();admin_id uuid:=gen_random_uuid();c uuid:=gen_random_uuid();d jsonb;p jsonb;v integer;r text;f regprocedure;
begin
 insert into public.profiles(id,full_name,email,role,staff_status) values(root,'Root PIN','root-pin@example.test','superadmin','active'),(admin_id,'Admin PIN','admin-pin@example.test','admin','active');
 p:=public.reserve_staff_account(admin_id,c,'Kasir PIN','cashier-pin@example.test','pin.test','cashier');
 insert into auth.users(id,email,email_confirmed_at,encrypted_password,raw_app_meta_data) values(c,'cashier-pin@example.test',now(),'isolated-fake-hash','{"staff_session_version":1,"staff_access_method":"pin"}');
 p:=public.finish_staff_credential(admin_id,c,1,'pin');
 if p->>'cashier_pin_enabled'<>'true' then raise exception 'PIN account not enabled';end if;
 perform public.set_staff_photo(root,c,root::text||'/'||gen_random_uuid()::text||'.webp');
 begin perform public.set_staff_photo(admin_id,root,admin_id::text||'/'||gen_random_uuid()::text||'.webp');raise exception 'Admin changed root photo';exception when insufficient_privilege then null;end;
 begin perform public.set_staff_photo(root,c,'https://external.example/image.jpg');raise exception 'External photo accepted';exception when check_violation then null;end;
 for v in 1..5 loop p:=public.claim_cashier_pin_attempt(c);if p->>'id'<>c::text then raise exception 'Wrong identity';end if;end loop;
 begin perform public.claim_cashier_pin_attempt(c);raise exception 'Guess budget bypassed';exception when raise_exception then if sqlerrm<>'PIN_ATTEMPTS_EXCEEDED' then raise;end if;end;
 update tkm.cashier_pin_attempts set window_start=now()-interval '16 minutes' where cashier_id=c;
 p:=public.claim_cashier_pin_attempt(c);
 p:=public.finish_cashier_pin_login(c,1);
 if p->>'id'<>c::text or exists(select 1 from tkm.cashier_pin_attempts where cashier_id=c) then raise exception 'Verified login failed';end if;
 perform public.manage_staff_account(root,c,'disable');
 begin perform public.finish_cashier_pin_login(c,1);raise exception 'Disabled PIN user logged in';exception when insufficient_privilege then null;end;
 p:=public.begin_staff_password(root,c,true);v:=(p->>'session_version')::integer;
 update auth.users set raw_app_meta_data=jsonb_build_object('staff_session_version',v,'staff_access_method','password') where id=c;
 p:=public.finish_staff_credential(root,c,v,'password');
 if p->>'cashier_pin_enabled'<>'false' then raise exception 'Password reset left PIN enabled';end if;
 if public.claim_cashier_pin_attempt(c) is not null then raise exception 'Password user in PIN flow';end if;
 if (select count(*) from public.staff_audit where target_id=c and action='cashier_pin_set')<>1 then raise exception 'PIN setup not audited';end if;
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('finish_staff_credential','set_staff_photo','claim_cashier_pin_attempt','finish_cashier_pin_login') loop
   if has_function_privilege(r,f,'EXECUTE') then raise exception '% can execute %',r,f;end if;
  end loop;
 end loop;
end $$;
rollback;
