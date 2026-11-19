do $$begin
 if not exists(select 1 from public.profiles where id='00000000-0011-4000-8000-000000000001' and role='superadmin' and staff_status='invited' and session_version=1) then raise exception 'Owner migration failed closed';end if;
 if not exists(select 1 from public.profiles where id='00000000-0011-4000-8000-000000000002' and role='admin' and staff_status='invited' and session_version=1) then raise exception 'Manager migration failed closed';end if;
 if exists(select 1 from auth.sessions where user_id in ('00000000-0011-4000-8000-000000000001','00000000-0011-4000-8000-000000000002')) then raise exception 'Old role refresh sessions retained';end if;
 if (select orders_enabled from public.settings where id=1) then raise exception 'Migration did not pause ordering';end if;
 if not exists(select 1 from public.payments where order_id='00000000-0011-4000-8000-000000000003' and cashier_name='Legacy Manager') then raise exception 'Payment history mutated';end if;
 if not exists(select 1 from public.staff_audit where order_id='00000000-0011-4000-8000-000000000003' and actor_role='manager' and actor_name='Legacy Manager') then raise exception 'Historical audit identity mutated';end if;
end $$;
