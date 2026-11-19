-- Run only inside an isolated migration-test transaction on schema 0010.
create schema if not exists auth;
create table if not exists auth.sessions(id uuid primary key,user_id uuid);
insert into public.profiles(id,full_name,email,role) values
 ('00000000-0011-4000-8000-000000000001','Legacy Owner','legacy-owner@example.test','owner'),
 ('00000000-0011-4000-8000-000000000002','Legacy Manager','legacy-manager@example.test','manager');
insert into auth.sessions values(gen_random_uuid(),'00000000-0011-4000-8000-000000000001'),(gen_random_uuid(),'00000000-0011-4000-8000-000000000002');
update public.settings set orders_enabled=true,pricing_confirmed_at=now() where id=1;
insert into public.orders(id,order_number,total,reviewed_version) values('00000000-0011-4000-8000-000000000003','MIGRATION-ROLE',10000,1);
select tkm.confirm_cash_verified('00000000-0011-4000-8000-000000000003','00000000-0011-4000-8000-000000000002',20000,1,0);
