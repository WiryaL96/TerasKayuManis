-- Disposable database ONLY. Covers account states, one-use tickets, session
-- revocation, price approval and immutable historical payment attribution.
begin;
create schema if not exists auth;
create table if not exists auth.sessions(id uuid primary key,user_id uuid);
do $$
declare owner_id uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();manager_id uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();link jsonb;hash text:=repeat('a',64);n integer;
begin
 update public.settings set orders_enabled=false,pricing_confirmed_at=null where id=1;
 begin insert into public.orders(order_number) values('blocked');raise exception 'Ordering without approval accepted';exception when check_violation then null;end;
 perform public.bootstrap_superadmin(owner_id,'Pemilik Uji','owner@example.test',repeat('b',64));
 link:=public.claim_staff_access(repeat('b',64));
 if link is null or not public.finish_staff_access(owner_id,(link->>'session_version')::int) then raise exception 'Owner activation failed';end if;
 begin perform public.confirm_restaurant_pricing(owner_id,10,5,true,true);raise exception 'Ordering enabled without personal cashier';exception when check_violation then null;end;
 begin perform public.bootstrap_superadmin(gen_random_uuid(),'Other','other@example.test',repeat('c',64));raise exception 'Second bootstrap accepted';exception when insufficient_privilege then null;end;
 insert into public.profiles(id,full_name,email,role,staff_status) values(a,'Raka','raka@example.test','cashier','invited'),(b,'Sari','sari@example.test','cashier','active'),(manager_id,'Manager','manager@example.test','admin','active');
 begin perform public.issue_staff_access(manager_id,owner_id,hash,'activation');raise exception 'Manager created staff access';exception when insufficient_privilege then null;end;
 begin perform public.manage_cashier(owner_id,owner_id,'disable');raise exception 'Self owner disabled';exception when insufficient_privilege then null;end;
 insert into auth.sessions values(gen_random_uuid(),a);
 link:=public.issue_staff_access(owner_id,a,hash,'activation');
 if exists(select 1 from auth.sessions where user_id=a) then raise exception 'Old refresh session retained';end if;
 begin perform tkm.check_staff_session(a,(link->>'session_version')::int);raise exception 'Invited account accepted';exception when insufficient_privilege then null;end;
 link:=public.claim_staff_access(hash);
 if link is null or public.claim_staff_access(hash) is not null then raise exception 'Ticket not single use';end if;
 insert into auth.sessions values(gen_random_uuid(),a);
 if not public.finish_staff_access(a,(link->>'session_version')::int) then raise exception 'Activation failed';end if;
 if exists(select 1 from auth.sessions where user_id=a) then raise exception 'Password setup session retained';end if;
 n:=(link->>'session_version')::int;perform tkm.check_staff_session(a,n);
 perform public.confirm_restaurant_pricing(owner_id,10,5,true,true);
 insert into public.orders(id,order_number,total,reviewed_version) values(oid,oid::text,10000,1);
 perform tkm.confirm_cash_verified(oid,a,20000,1,n);
 perform public.manage_cashier(owner_id,a,'rename','Raka Baru');
 if (select cashier_name from public.payments where order_id=oid)<>'Raka' then raise exception 'Historic name changed';end if;
 perform public.manage_cashier(owner_id,a,'disable');
 begin perform tkm.check_staff_session(a,n);raise exception 'Disabled old JWT accepted';exception when insufficient_privilege then null;end;
 perform public.manage_cashier(owner_id,a,'enable');
 link:=public.issue_staff_access(owner_id,a,repeat('d',64),'recovery');
 update public.staff_access_links set expires_at=now()-interval '1 second' where token_hash=repeat('d',64);
 if public.claim_staff_access(repeat('d',64)) is not null then raise exception 'Expired link accepted';end if;
 link:=public.issue_staff_access(owner_id,a,repeat('e',64),'recovery');
 link:=public.claim_staff_access(repeat('e',64));
 perform public.finish_staff_access(a,(link->>'session_version')::int);
 begin perform tkm.check_staff_session(a,n);raise exception 'Old JWT survived reactivation';exception when insufficient_privilege then null;end;
 perform tkm.check_staff_session(a,(link->>'session_version')::int);
 if has_function_privilege('tkm_runtime','public.bootstrap_superadmin(uuid,text,text,text)','EXECUTE') then raise exception 'Runtime can bootstrap owner';end if;
 if has_function_privilege('tkm_runtime','public.manage_cashier(uuid,uuid,text,text)','EXECUTE') then raise exception 'Runtime manages staff';end if;
 begin insert into public.products(category_id,name,slug,price,is_available,price_confirmed) select id,'Unpriced','unpriced',0,true,false from public.categories limit 1;exception when check_violation then null;end;
end $$;
rollback;
