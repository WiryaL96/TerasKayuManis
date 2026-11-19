-- Disposable test DB only. Payment identity is captured in the same transaction.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();blank uuid:=gen_random_uuid();
 oa uuid:=gen_random_uuid();ob uuid:=gen_random_uuid();oc uuid:=gen_random_uuid();
 saved text;actor uuid;
begin
 if not has_column_privilege('tkm_runtime','public.profiles','full_name','SELECT') or has_any_column_privilege('tkm_runtime','public.profiles','UPDATE') then raise exception 'Unexpected staff profile access';end if;
 insert into public.profiles(id,full_name,role) values(a,'Budi Santoso','cashier'),(b,'Sari Putri','cashier'),(blank,null,'cashier');
 insert into public.orders(id,order_number,total,reviewed_version) values(oa,oa::text,10000,1),(ob,ob::text,20000,1),(oc,oc::text,10000,1);
 perform tkm.confirm_cash(oa,a,10000,1);perform tkm.confirm_cash(ob,b,20000,1);
 select cashier_name,cashier_id into saved,actor from public.payments where order_id=oa;
 if saved is distinct from 'Budi Santoso' or actor is distinct from a then raise exception 'Wrong first cashier';end if;
 select cashier_name,cashier_id into saved,actor from public.payments where order_id=ob;
 if saved is distinct from 'Sari Putri' or actor is distinct from b then raise exception 'Wrong second cashier';end if;
 update public.profiles set full_name='Budi Baru' where id=a;
 perform tkm.confirm_cash(oa,b,10000,1);
 if (select cashier_name from public.payments where order_id=oa) is distinct from 'Budi Santoso' then raise exception 'Retry or renamed profile changed receipt';end if;
 begin
  perform tkm.confirm_cash(oc,blank,10000,1);
  raise exception 'Unnamed cashier accepted';
 exception when check_violation then null;
 end;
 if exists(select 1 from public.payments where order_id=oc) or (select payment_status from public.orders where id=oc)<>'unpaid' then raise exception 'Unnamed payment was not atomic';end if;
end $$;
rollback;
