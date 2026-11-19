begin;
update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;
do $$
declare root uuid:=gen_random_uuid(); cash uuid:=gen_random_uuid(); oid uuid; before_data jsonb;after_data jsonb;revision_before bigint;key text:=gen_random_uuid()::text;
begin
 insert into public.profiles(id,full_name,role,staff_status) values(root,'Summary Owner','superadmin','active'),(cash,'Summary Cashier','cashier','active');
 before_data:=public.dashboard_snapshot(root,(now() at time zone 'Asia/Jakarta')::date,(now() at time zone 'Asia/Jakarta')::date);
 insert into public.orders(id,total,subtotal,reviewed_version) values(gen_random_uuid(),10000,10000,1) returning id into oid;
 perform tkm.claim_pos_order(oid,cash,1,0,'');
 perform tkm.forward_pos_order(oid,cash,2,0,'LOCAL-SQL');
 after_data:=public.dashboard_snapshot(root,(now() at time zone 'Asia/Jakarta')::date,(now() at time zone 'Asia/Jakarta')::date);
 if (after_data#>>'{report,pos_summary,count}')::bigint<>(before_data#>>'{report,pos_summary,count}')::bigint+1 then raise exception 'summary count mismatch';end if;
 if (after_data#>>'{report,pos_summary,total}')::bigint<>(before_data#>>'{report,pos_summary,total}')::bigint+10000 then raise exception 'summary amount mismatch';end if;
 if after_data#>'{report,handoffs}'<>'[]'::jsonb or after_data#>'{report,payments}'<>'[]'::jsonb then raise exception 'summary leaked raw history';end if;
 begin perform public.dashboard_snapshot(cash,current_date,current_date);raise exception 'cashier accessed summary';exception when insufficient_privilege then null;end;
 select revision into revision_before from tkm.order_clock where id=1;
 update public.orders set total=0 where false;
 if (select revision from tkm.order_clock where id=1)<>revision_before then raise exception 'no-op write invalidated all clients';end if;
 if not tkm.claim_request_budget(key,2) or not tkm.claim_request_budget(key,2) or tkm.claim_request_budget(key,2) then raise exception 'shared budget not atomic';end if;
 if has_function_privilege('anon','public.claim_sensitive_budget(text,integer)','EXECUTE') or has_function_privilege('authenticated','public.dashboard_snapshot(uuid,date,date)','EXECUTE') then raise exception 'private RPC exposed';end if;
end $$;
rollback;
