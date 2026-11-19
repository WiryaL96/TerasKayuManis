-- Disposable database only. Manual POS handoff must never manufacture payment.
begin;
update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();admin_id uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();expired_id uuid:=gen_random_uuid();v integer;before_payments bigint;result jsonb;
begin
 insert into public.profiles(id,full_name,role,staff_status) values(a,'Kasir Pertama','cashier','active'),(b,'Kasir Kedua','cashier','active'),(admin_id,'Admin POS','admin','active');
 insert into public.orders(id,table_id,total,subtotal,reviewed_version) values(oid,null,12000,12000,null),(expired_id,null,12000,12000,1);
 update public.orders set created_at=now()-interval '20 minutes' where id=expired_id;
 select count(*) into before_payments from public.payments;
 begin perform tkm.claim_pos_order(oid,a,1,0);raise exception 'unreviewed claim accepted';exception when check_violation then null;end;
 update public.orders set reviewed_version=version where id=oid;
 begin perform tkm.claim_pos_order(expired_id,a,1,0);raise exception 'expired claim accepted';exception when check_violation then null;end;
 begin perform tkm.claim_pos_order(oid,a,99,0);raise exception 'stale claim accepted';exception when check_violation then null;end;
 result:=tkm.claim_pos_order(oid,a,1,0);
 if result->>'status'<>'pos_input' or result->'pos_handoff'->>'cashier_name'<>'Kasir Pertama' then raise exception 'claim invalid';end if;
 if tkm.claim_pos_order(oid,a,1,0) is distinct from result then raise exception 'claim retry changed order';end if;
 begin perform tkm.claim_pos_order(oid,b,2,0);raise exception 'second cashier stole claim';exception when insufficient_privilege then null;end;
 begin perform tkm.forward_pos_order(oid,b,2,0,'');raise exception 'second cashier finalized';exception when insufficient_privilege then null;end;
 -- A customer already at the counter must not expire while the POS is entered.
 update public.orders set created_at=now()-interval '20 minutes' where id=oid;
 perform tkm.expire_one(oid);
 if (select status from public.orders where id=oid)<>'pos_input' then raise exception 'counter order expired';end if;
 update public.profiles set full_name='Nama diubah kemudian' where id=a;
 result:=tkm.forward_pos_order(oid,a,2,0,'POS-123');
 if result->>'status'<>'forwarded' or result->>'payment_status'<>'unpaid' or result->'pos_handoff'->>'cashier_name'<>'Kasir Pertama' then raise exception 'handoff snapshot invalid';end if;
 if (select count(*) from public.payments)<>before_payments then raise exception 'handoff created payment';end if;
 if tkm.forward_pos_order(oid,a,2,0,'POS-123') is distinct from result then raise exception 'handoff retry changed order';end if;
 if (select count(*) from public.staff_audit where order_id=oid and action='pos_forwarded')<>1 then raise exception 'duplicate activity';end if;
 begin perform tkm.forward_pos_order(oid,a,2,0,'OTHER');raise exception 'reference conflict accepted';exception when check_violation then null;end;
 begin update public.order_pos_handoffs set cashier_name='Forged' where order_id=oid;raise exception 'handoff editable';exception when insufficient_privilege then null;end;
 begin perform tkm.confirm_cash_verified(oid,a,12000,3,0);raise exception 'forwarded order paid twice';exception when check_violation then null;end;
 -- Only a named administrator may take over, after checking the external POS.
 insert into public.orders(id,table_id,total,subtotal,reviewed_version) values(gen_random_uuid(),null,10000,10000,1) returning id into oid;
 perform tkm.claim_pos_order(oid,b,1,0);
 begin perform tkm.claim_pos_order(oid,admin_id,2,0,'');raise exception 'takeover without reason';exception when insufficient_privilege then null;end;
 perform tkm.claim_pos_order(oid,admin_id,2,0,'Sudah memeriksa POS, kasir berganti');
 begin perform tkm.forward_pos_order(oid,b,3,0,'');raise exception 'old assignee finalized';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='disabled',session_version=1 where id=admin_id;
 begin perform tkm.forward_pos_order(oid,admin_id,3,0,'');raise exception 'disabled token accepted';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='active' where id=admin_id;
 perform tkm.forward_pos_order(oid,admin_id,3,1,'');
 if not exists(select 1 from public.staff_audit where order_id=oid and action='pos_reassigned' and details->>'reason'='Sudah memeriksa POS, kasir berganti') then raise exception 'takeover not audited';end if;
 if has_table_privilege('anon','public.order_pos_handoffs','SELECT') or has_function_privilege('authenticated','tkm.forward_pos_order(uuid,uuid,integer,integer,text)','EXECUTE') then raise exception 'handoff API exposed to public';end if;
end $$;
rollback;
