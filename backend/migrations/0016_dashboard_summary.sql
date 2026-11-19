create function public.dashboard_snapshot(p_actor uuid,p_from date,p_to date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_role text; result jsonb; start_at timestamptz; end_at timestamptz;
begin
 select role into actor_role from public.profiles where id=p_actor and staff_status='active' and role in ('superadmin','admin');
 if actor_role is null then raise insufficient_privilege;end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>30 then raise invalid_parameter_value;end if;
 start_at:=p_from::timestamp at time zone 'Asia/Jakarta';end_at:=(p_to+1)::timestamp at time zone 'Asia/Jakarta';
 with handoffs as (select h.*,o.total from public.order_pos_handoffs h join public.orders o on o.id=h.order_id where h.forwarded_at>=start_at and h.forwarded_at<end_at),
 paid as(select * from public.payments where created_at>=start_at and created_at<end_at),
 daily as(select (forwarded_at at time zone 'Asia/Jakarta')::date as day,count(*) n,sum(total) total from handoffs group by 1),
 visible_staff as(select * from public.profiles where role='cashier' or (actor_role='superadmin' and role='admin'))
 select jsonb_build_object('role',actor_role,'period',jsonb_build_object('from',p_from,'to',p_to),'generated_at',clock_timestamp(),
 'report',jsonb_build_object('payments','[]'::jsonb,'handoffs','[]'::jsonb,
 'summary',(select jsonb_build_object('count',count(*),'revenue',coalesce(sum(amount_rp),0)::text,'received',coalesce(sum(received_rp),0)::text,'change',coalesce(sum(change_rp),0)::text) from paid),
 'by_cashier','[]'::jsonb,'popular',coalesce((select jsonb_agg(to_jsonb(x)) from(select i.product_name name,sum(i.quantity) qty from public.order_items i join paid p on p.order_id=i.order_id group by i.product_name order by sum(i.quantity) desc limit 5)x),'[]'::jsonb),
 'counts',coalesce((select jsonb_object_agg(status,n) from(select status,count(*) n from public.orders where created_at>=start_at and created_at<end_at group by status)x),'{}'::jsonb),
 'today_total',(select count(*) from public.orders where created_at>=start_at and created_at<end_at),
 'active_total',(select count(*) from public.orders where status in ('pos_input','confirmed') or (status='pending' and created_at>now()-interval '15 minutes')),
 'pos_summary',jsonb_build_object('count',(select count(*) from handoffs),'total',(select coalesce(sum(total),0)::text from handoffs),'by_cashier',coalesce((select jsonb_agg(to_jsonb(x)) from(select cashier_id id,cashier_name name,count(*) count,sum(total)::text total from handoffs group by cashier_id,cashier_name order by cashier_name,cashier_id)x),'[]'::jsonb)),
 'daily_handoffs',(select jsonb_agg(jsonb_build_object('date',p_from+g.n,'count',coalesce(d.n,0),'revenue',coalesce(d.total,0)::text) order by g.n) from generate_series(0,p_to-p_from)g(n) left join daily d on d.day=p_from+g.n)),
 'queue',jsonb_build_object('pending',(select count(*) from public.orders where status='pending' and created_at>now()-interval '15 minutes'),'processing',(select count(*) from public.orders where status='pos_input'),
 'orders',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,order_number,customer_name,total,created_at,status,created_at+interval '15 minutes' expires_at from public.orders where status='pending' and created_at>now()-interval '15 minutes' order by created_at limit 5)x),'[]'::jsonb)),
 'catalog',(select jsonb_build_object('published',count(*) filter(where p.is_available and p.price_confirmed and p.price>0 and c.is_active),'draft',count(*) filter(where not p.price_confirmed or p.price<=0),'hidden',count(*) filter(where p.price_confirmed and p.price>0 and (not p.is_available or not c.is_active)),'missing_photo',count(*) filter(where p.is_available and p.price_confirmed and p.price>0 and c.is_active and nullif(p.image_url,'') is null)) from public.products p join public.categories c on c.id=p.category_id),
 'staff',(select jsonb_build_object('active',count(*) filter(where staff_status='active'),'invited',count(*) filter(where staff_status='invited'),'disabled',count(*) filter(where staff_status='disabled'),'active_cashiers',count(*) filter(where role='cashier' and staff_status='active' and nullif(btrim(full_name),'') is not null)) from visible_staff),
 'operation',(select jsonb_build_object('orders_enabled',orders_enabled,'pricing_confirmed_at',pricing_confirmed_at) from public.settings where id=1)) into result;
 if actor_role='superadmin' then
 result:=result||jsonb_build_object('activity',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,actor_name,action,created_at from public.staff_audit order by created_at desc,id desc limit 4)x),'[]'::jsonb),'backup',coalesce((select to_jsonb(b)-'id' from tkm.backup_status b where id=1),'{}'::jsonb));
 end if;
 return result;
end $$;
revoke all on function public.dashboard_snapshot(uuid,date,date) from public;
grant execute on function public.dashboard_snapshot(uuid,date,date) to service_role;
do $$declare r text;f regprocedure;begin
 foreach r in array array['anon','authenticated'] loop
 if to_regrole(r) is not null then
 foreach f in array array['public.dashboard_snapshot(uuid,date,date)'::regprocedure,'public.claim_sensitive_budget(text,integer)'::regprocedure,'public.read_backup_status(uuid)'::regprocedure,'public.record_backup_status(text,boolean)'::regprocedure] loop
 execute format('revoke all on function %s from %I',f,r);
 end loop;end if;end loop;
end $$;
