-- Staff names are read only by the authenticated staff API. No account writes
-- are granted to the runtime. Existing unnamed receipts remain historical.
grant select(full_name) on public.profiles to tkm_runtime;
alter table public.payments add column if not exists cashier_name text;

create or replace function tkm.snapshot_cashier_name() returns trigger
language plpgsql set search_path='' as $$
begin
 select nullif(btrim(p.full_name),'') into new.cashier_name
 from public.profiles p where p.id=new.cashier_id
 and p.role in ('admin','manager','cashier','owner');
 if new.cashier_name is null then
  raise check_violation using message='Cashier full name is required before accepting payment';
 end if;
 return new;
end $$;
revoke all on function tkm.snapshot_cashier_name() from public;
grant execute on function tkm.snapshot_cashier_name() to tkm_runtime;
drop trigger if exists payment_cashier_name on public.payments;
create trigger payment_cashier_name before insert on public.payments
for each row execute function tkm.snapshot_cashier_name();
