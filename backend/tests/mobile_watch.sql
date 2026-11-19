begin;
insert into public.profiles(id,full_name,role,staff_status,session_version)
values('00200000-0000-4000-8000-000000000001','Mobile fixture','cashier','active',0);
set local role tkm_runtime;
select tkm.issue_watch('00200000-0000-4000-8000-000000000001','00200000-0000-4000-8000-000000000002',0,repeat('a',64));
select tkm.issue_watch('00200000-0000-4000-8000-000000000001','00200000-0000-4000-8000-000000000002',0,repeat('b',64));
do $$begin
 if exists(select 1 from tkm.watch_leases where token_hash=repeat('a',64)) then raise exception 'old lease not revoked';end if;
 if not exists(select 1 from tkm.watch_leases where token_hash=repeat('b',64) and expires_at>now() and expires_at<now()+interval '6 hours') then raise exception 'missing bounded lease';end if;
 if has_table_privilege('tkm_runtime','tkm.watch_leases','INSERT') or has_table_privilege('tkm_runtime','tkm.watch_leases','UPDATE') then raise exception 'lease writes bypass issuer';end if;
end $$;
do $$begin
 for i in 1..4 loop
  perform tkm.issue_watch('00200000-0000-4000-8000-000000000001',gen_random_uuid(),0,repeat(i::text,64));
 end loop;
 begin
  perform tkm.issue_watch('00200000-0000-4000-8000-000000000001',gen_random_uuid(),0,repeat('f',64));
  raise exception 'device cap bypassed';
 exception when check_violation then null;
 end;
 if (select count(*) from tkm.watch_leases where actor='00200000-0000-4000-8000-000000000001')<>5 then raise exception 'device cap changed existing leases';end if;
end $$;
reset role;
update public.profiles set staff_status='disabled',session_version=1 where id='00200000-0000-4000-8000-000000000001';
set local role tkm_runtime;
do $$begin
 begin
  perform tkm.issue_watch('00200000-0000-4000-8000-000000000001','00200000-0000-4000-8000-000000000002',0,repeat('c',64));
  raise exception 'disabled actor issued lease';
 exception when insufficient_privilege then null;
 end;
 if exists(select 1 from tkm.watch_leases w join public.profiles p on p.id=w.actor where w.token_hash=repeat('b',64) and p.staff_status='active' and p.session_version=w.session_version) then raise exception 'disabled lease remains authorized';end if;
end $$;
reset role;
do $$declare r text;begin
 foreach r in array array['anon','authenticated','service_role'] loop
 if has_function_privilege(r,'tkm.issue_watch(uuid,uuid,integer,text)','EXECUTE') or has_table_privilege(r,'tkm.watch_leases','SELECT') then raise exception 'API role has watch grant';end if;
 end loop;
end $$;
rollback;
