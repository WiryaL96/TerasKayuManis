begin;
create schema if not exists auth;
create table if not exists auth.sessions(id uuid primary key,user_id uuid);
do $$
declare root_id uuid:=gen_random_uuid();adm uuid:=gen_random_uuid();cash uuid:=gen_random_uuid();other uuid:=gen_random_uuid();link jsonb;role_name text;fn regprocedure;
begin
 insert into public.profiles(id,full_name,email,role) values(root_id,'Superadmin Uji','root-three@example.test','superadmin');
 perform public.create_staff_account(root_id,adm,'Admin Uji','admin-three@example.test','admin');
 if (select staff_status from public.profiles where id=adm)<>'invited' then raise exception 'Admin bypassed activation';end if;
 link:=public.issue_staff_access(root_id,adm,repeat('7',64),'activation');
 link:=public.claim_staff_access(repeat('7',64));
 if not public.finish_staff_access(adm,(link->>'session_version')::int) then raise exception 'Admin activation failed';end if;
 perform public.record_staff_signin(adm,(link->>'session_version')::int,'admin');
 perform public.create_staff_account(adm,cash,'Kasir Uji','cash-three@example.test','cashier');
 begin perform public.create_staff_account(adm,other,'Forbidden','no-admin@example.test','admin');raise exception 'Admin created admin';exception when insufficient_privilege then null;end;
 begin perform public.create_staff_account(root_id,other,'Forbidden','no-root@example.test','superadmin');raise exception 'Public operation created superadmin';exception when insufficient_privilege then null;end;
 begin perform public.manage_staff_account(adm,root_id,'disable');raise exception 'Admin disabled superadmin';exception when insufficient_privilege then null;end;
 begin perform public.issue_staff_access(adm,root_id,repeat('8',64),'recovery');raise exception 'Admin recovered superadmin';exception when insufficient_privilege then null;end;
 begin perform public.manage_staff_account(root_id,root_id,'disable');raise exception 'Superadmin disabled self';exception when insufficient_privilege then null;end;
 begin perform public.confirm_restaurant_pricing(adm,0,0,true,false);raise exception 'Admin approved global settings';exception when insufficient_privilege then null;end;
 perform public.confirm_restaurant_pricing(root_id,0,0,true,false);
 perform public.manage_staff_account(adm,cash,'rename','Kasir Baru');
 begin perform public.create_staff_account(cash,other,'Forbidden','cash-creates@example.test','cashier');raise exception 'Cashier created staff';exception when insufficient_privilege then null;end;
 insert into auth.sessions values(gen_random_uuid(),adm);
 perform public.manage_staff_account(root_id,adm,'disable');
 if exists(select 1 from auth.sessions where user_id=adm) then raise exception 'Disabled admin retained refresh sessions';end if;
 begin perform tkm.check_staff_session(adm,(link->>'session_version')::int);raise exception 'Disabled admin retained access';exception when insufficient_privilege then null;end;
 foreach role_name in array array['owner','manager','kitchen'] loop
  begin insert into public.profiles(id,role) values(gen_random_uuid(),role_name);raise exception 'Obsolete operational role accepted';exception when check_violation then null;end;
 end loop;
 if to_regprocedure('public.bootstrap_owner(uuid,text,text,text)') is not null then raise exception 'Obsolete owner bootstrap remains callable';end if;
 foreach role_name in array array['anon','authenticated','tkm_runtime'] loop
  if exists(select 1 from pg_roles where rolname=role_name) then
   for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_staff_account','manage_staff_account','bootstrap_superadmin') loop
    if has_function_privilege(role_name,fn,'EXECUTE') then raise exception 'Untrusted role can call privileged staff RPC';end if;
   end loop;
  end if;
 end loop;
end $$;
rollback;
