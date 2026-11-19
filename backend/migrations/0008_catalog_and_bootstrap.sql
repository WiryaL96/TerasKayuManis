-- Preserve test-order history. Hide the known trial item, never delete it.
update public.products set is_available=false where name='Es Teh Manis (Uji)';
-- Pending-price catalog entries are private drafts. A positive price and an
-- explicit publish operation are required before customers can order them.
alter table public.products add column price_confirmed boolean not null default true;
alter table public.addons add column price_confirmed boolean not null default true;
update public.products set price_confirmed=false,is_available=false where price=0;
update public.addons set price_confirmed=false,is_available=false where price=0;
insert into public.addons(name,price,is_available,price_confirmed)
select m.name,0,false,false from (values('Jalapeno'),('Pineapple'),('Gherkin'),('Extra Mozzarella'),('Parmesan'))m(name)
where not exists(select 1 from public.addons a where lower(a.name)=lower(m.name));
-- Names copied from the supplied menu; zero is a private placeholder, never a
-- sellable price. The owner must supply each price and explicitly publish it.
insert into public.categories(name,slug,is_active) values('Milkshake','milkshake',true) on conflict(slug) do nothing;
insert into public.products(category_id,name,slug,price,is_available,price_confirmed)
select c.id,m.name,m.slug,0,false,false from (values
 ('Vanilla Milkshake','vanilla-milkshake'),('Choco Milkshake','choco-milkshake'),('Strawberry Milkshake','strawberry-milkshake')
) m(name,slug) cross join lateral(select id from public.categories where slug='milkshake' limit 1)c
where not exists(select 1 from public.products p where p.slug=m.slug or lower(p.name)=lower(m.name));
alter table public.products add constraint published_product_price check(not is_available or (price_confirmed and price>0));
alter table public.addons add constraint published_addon_price check(not is_available or (price_confirmed and price>0));

-- Service-role-only, operator CLI only. No HTTP route can create an owner.
create function public.bootstrap_owner(p_id uuid,p_name text,p_email text,p_hash text) returns integer
language plpgsql security definer set search_path='' as $$
declare version integer;
begin
 perform pg_advisory_xact_lock(3820192026);
 if nullif(btrim(p_name),'') is null or length(p_name)>100 or p_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_hash!~'^[a-f0-9]{64}$' then raise check_violation;end if;
 if exists(select 1 from public.profiles where role in ('owner','admin') and (id<>p_id or staff_status<>'invited')) then raise insufficient_privilege;end if;
 if exists(select 1 from public.profiles where id=p_id and role<>'owner') then raise insufficient_privilege;end if;
 insert into public.profiles(id,full_name,email,role,staff_status,session_version) values(p_id,btrim(p_name),lower(p_email),'owner','invited',1)
 on conflict(id) do update set session_version=profiles.session_version+1 returning session_version into version;
 insert into public.staff_access_links(profile_id,token_hash,purpose,session_version,expires_at) values(p_id,p_hash,'activation',version,now()+interval '60 minutes');
 perform tkm.revoke_staff_sessions(p_id);
 insert into public.staff_audit(target_id,action) values(p_id,'owner_bootstrap');
 return version;
end $$;
revoke all on function public.bootstrap_owner(uuid,text,text,text) from public;
do $$begin if exists(select 1 from pg_roles where rolname='service_role') then grant execute on function public.bootstrap_owner(uuid,text,text,text) to service_role;end if;end $$;
