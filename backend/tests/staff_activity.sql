-- Disposable database only; transaction is rolled back, including audit rows.
begin;
do $$
declare own uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();bid uuid:=gen_random_uuid();cat uuid;prod uuid;before_count integer;after_count integer;args jsonb;api_role text;fn regprocedure;
begin
 insert into public.profiles(id,full_name,role) values(own,'Owner Uji','superadmin');
 perform public.create_cashier(own,a,'Raka','raka-activity@example.test');
 perform public.create_cashier(own,b,'Sari','sari-activity@example.test');
 if not exists(select 1 from public.staff_audit where target_id=a and actor_name='Owner Uji' and target_name='Raka' and action='cashier_created') then raise exception 'Creation audit absent';end if;
 begin perform public.record_staff_signin(a,0,'cashier');raise exception 'Invitation logged in';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='active' where id in(a,b);
 perform public.record_staff_signin(a,0,'cashier');
 perform public.record_staff_signin(b,0,'cashier');
 begin perform public.record_staff_signin(a,0,'admin');raise exception 'Cashier admin login accepted';exception when insufficient_privilege then null;end;
 begin perform public.create_cashier(a,gen_random_uuid(),'Forged','forged@example.test');raise exception 'Cashier created staff';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='disabled' where id=a;
 begin perform public.record_staff_signin(a,0,'cashier');raise exception 'Disabled login accepted';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='active',session_version=1 where id=a;
 begin perform public.record_staff_signin(a,0,'cashier');raise exception 'Old session accepted';exception when insufficient_privilege then null;end;
 perform public.record_staff_signin(a,1,'cashier');
 update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;
 insert into public.categories(name,slug) values('Audit fixture',gen_random_uuid()::text) returning id into cat;
 insert into public.products(category_id,name,slug,price) values(cat,'Teh',gen_random_uuid()::text,10000) returning id into prod;
 args:=jsonb_build_array(jsonb_build_object('product_id',prod,'quantity',1,'variant_ids','[]'::jsonb,'addon_ids','[]'::jsonb,'notes',''));
 insert into public.orders(id,order_number,total) values(oid,oid::text,10000),(bid,bid::text,10000);
 perform tkm.review_order_verified(oid,a,1,args,1);
 perform tkm.review_order_verified(bid,b,1,args,0);
 perform tkm.confirm_cash_verified(oid,a,20000,2,1);
 perform tkm.confirm_cash_verified(bid,b,10000,2,0);
 select count(*) into before_count from public.staff_audit where order_id=oid;
 perform tkm.confirm_cash_verified(oid,b,20000,2,0);
 select count(*) into after_count from public.staff_audit where order_id=oid;
 if after_count<>before_count then raise exception 'Payment retry duplicated activity';end if;
 perform tkm.complete_order_verified(oid,b,0);
 perform tkm.complete_order_verified(oid,b,0);
 if (select count(*) from public.staff_audit where order_id=oid and action='order_completed')<>1 then raise exception 'Completion activity duplicated';end if;
 if not exists(select 1 from public.staff_audit where order_id=oid and action='cash_payment_confirmed' and actor_id=a and actor_name='Raka' and details->>'received'='20000' and details->>'change'='10000') then raise exception 'Raka payment activity incorrect';end if;
 if not exists(select 1 from public.staff_audit where order_id=bid and action='cash_payment_confirmed' and actor_id=b and actor_name='Sari') then raise exception 'Sari attribution incorrect';end if;
 if not exists(select 1 from public.staff_audit where order_id=oid and action='order_reviewed' and actor_id=a) then raise exception 'Review attribution incorrect';end if;
 if not exists(select 1 from public.staff_audit where order_id=oid and action='order_completed' and actor_id=b) then raise exception 'Completion actor incorrect';end if;
 perform public.manage_cashier(own,a,'rename','Raka Baru');
 if (select actor_name from public.staff_audit where order_id=oid and action='cash_payment_confirmed')<>'Raka' then raise exception 'Historical identity changed';end if;
 begin update public.staff_audit set actor_name='Forged' where actor_id=a;raise exception 'Audit was editable';exception when insufficient_privilege then null;end;
 begin delete from public.staff_audit where actor_id=a;raise exception 'Audit was deletable';exception when insufficient_privilege then null;end;
 begin truncate public.staff_audit;raise exception 'Audit was truncatable';exception when insufficient_privilege then null;end;
 if has_function_privilege('tkm_runtime','public.record_staff_signin(uuid,integer,text)','EXECUTE') then raise exception 'Runtime forged signin';end if;
 if has_table_privilege('tkm_runtime','public.staff_audit','SELECT') then raise exception 'Cash runtime reads private audit';end if;
 if has_table_privilege('tkm_runtime','public.staff_audit','INSERT') then raise exception 'Cash runtime forges audit';end if;
 foreach api_role in array array['anon','authenticated'] loop
  if exists(select 1 from pg_roles where rolname=api_role) then
   for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('manage_cashier','issue_staff_access','claim_staff_access','finish_staff_access','confirm_restaurant_pricing','bootstrap_owner','create_cashier','record_staff_signin') loop
    if has_function_privilege(api_role,fn,'EXECUTE') then raise exception 'API role can spoof staff RPC: %',fn;end if;
   end loop;
   if has_table_privilege(api_role,'public.staff_audit','SELECT') or has_table_privilege(api_role,'public.staff_audit','INSERT') or has_table_privilege(api_role,'public.staff_audit','TRUNCATE') then raise exception 'API role can access private audit';end if;
  end if;
 end loop;
 if exists(select 1 from pg_roles where rolname='service_role') then
  if has_table_privilege('service_role','public.staff_audit','UPDATE') or has_table_privilege('service_role','public.staff_audit','DELETE') or has_table_privilege('service_role','public.staff_audit','TRUNCATE') then raise exception 'Service can erase activity';end if;
  if not has_function_privilege('service_role','public.record_staff_signin(uuid,integer,text)','EXECUTE') then raise exception 'Service cannot record login';end if;
 end if;
end $$;
insert into public.profiles(id,full_name,role) values('00000000-0010-4000-8000-000000000003','Removed Test Profile','cashier');
select public.record_staff_signin('00000000-0010-4000-8000-000000000003',0,'cashier');
delete from public.profiles where id='00000000-0010-4000-8000-000000000003';
do $$begin
 if not exists(select 1 from public.staff_audit where actor_id='00000000-0010-4000-8000-000000000003' and actor_name='Removed Test Profile') then raise exception 'Profile removal destroyed audit identity';end if;
end $$;
-- Prove actual restricted runtime payment triggers work, not just the owner.
insert into public.profiles(id,full_name,role) values('00000000-0010-4000-8000-000000000001','Runtime Cashier','cashier');
update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;
insert into public.orders(id,order_number,total,reviewed_version) values('00000000-0010-4000-8000-000000000002','AUDIT-RUNTIME',10000,1);
set local role tkm_runtime;
select tkm.confirm_cash_verified('00000000-0010-4000-8000-000000000002','00000000-0010-4000-8000-000000000001',20000,1,0);
reset role;
do $$begin
 if not exists(select 1 from public.staff_audit where order_id='00000000-0010-4000-8000-000000000002' and actor_name='Runtime Cashier') then raise exception 'Runtime audit failed';end if;
end $$;
rollback;
