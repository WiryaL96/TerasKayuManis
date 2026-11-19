-- Product + variant + add-on writes commit together. Only the server service
-- role may call this RPC; the actor's current status/role is checked again.
create function public.save_catalog_product(p_actor uuid, p_id uuid, p_values jsonb,
 p_variants jsonb default null, p_addon_ids jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.products; v jsonb; variant_id uuid; keep uuid[] := '{}'; addon_id uuid;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('superadmin','admin') and staff_status='active') then raise insufficient_privilege;end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or exists(select 1 from jsonb_object_keys(p_values) k where k not in ('category_id','name','slug','description','price','price_confirmed','image_url','is_available','is_featured','is_best_seller','is_new')) then raise check_violation;end if;
 if p_variants is not null and (jsonb_typeof(p_variants)<>'array' or jsonb_array_length(p_variants)>100) then raise check_violation;end if;
 if p_addon_ids is not null and (jsonb_typeof(p_addon_ids)<>'array' or jsonb_array_length(p_addon_ids)>100) then raise check_violation;end if;
 if p_id is null then
  select * into p from jsonb_populate_record(null::public.products,
   '{"price_confirmed":true,"is_available":true,"is_featured":false,"is_best_seller":false,"is_new":false}'::jsonb || p_values);
 else
  select * into p from public.products where id=p_id for update;
  if not found then raise no_data_found;end if;
  select * into p from jsonb_populate_record(p,p_values-'slug');
 end if;
 if p.name is null or length(btrim(p.name)) not between 1 and 100 or p.slug is null or length(p.slug) not between 1 and 160 or length(coalesce(p.description,''))>4000 or length(coalesce(p.image_url,''))>2048 then raise check_violation;end if;
 if p_id is null then
  insert into public.products(category_id,name,slug,description,price,price_confirmed,image_url,is_available,is_featured,is_best_seller,is_new)
   values(p.category_id,btrim(p.name),p.slug,p.description,p.price,p.price_confirmed,p.image_url,p.is_available,p.is_featured,p.is_best_seller,p.is_new) returning * into p;
 else
  update public.products set category_id=p.category_id,name=btrim(p.name),description=p.description,price=p.price,price_confirmed=p.price_confirmed,image_url=p.image_url,is_available=p.is_available,is_featured=p.is_featured,is_best_seller=p.is_best_seller,is_new=p.is_new,updated_at=clock_timestamp() where id=p_id returning * into p;
 end if;
 if p_variants is not null then
  for v in select value from jsonb_array_elements(p_variants) loop
   if jsonb_typeof(v)<>'object' or jsonb_typeof(v->'name')<>'string' or length(btrim(v->>'name')) not between 1 and 100 or length(coalesce(v->>'group_name','Pilihan')) not between 1 and 100 then raise check_violation;end if;
   variant_id:=nullif(v->>'id','')::uuid;
   if variant_id is not null then
    if variant_id=any(keep) or not exists(select 1 from public.product_variants where id=variant_id and product_id=p.id) then raise check_violation;end if;
    update public.product_variants set group_name=coalesce(nullif(v->>'group_name',''),'Pilihan'),name=btrim(v->>'name'),price_modifier=coalesce((v->>'price_modifier')::bigint,0),is_default=coalesce((v->>'is_default')::boolean,false),is_available=coalesce((v->>'is_available')::boolean,true),sort_order=coalesce((v->>'sort_order')::int,0) where id=variant_id;
   else
    insert into public.product_variants(product_id,group_name,name,price_modifier,is_default,is_available,sort_order)
     values(p.id,coalesce(nullif(v->>'group_name',''),'Pilihan'),btrim(v->>'name'),coalesce((v->>'price_modifier')::bigint,0),coalesce((v->>'is_default')::boolean,false),coalesce((v->>'is_available')::boolean,true),coalesce((v->>'sort_order')::int,0)) returning id into variant_id;
   end if;
   keep:=array_append(keep,variant_id);
  end loop;
  delete from public.product_variants where product_id=p.id and not(id=any(keep));
 end if;
 if p_addon_ids is not null then
  delete from public.product_addons where product_id=p.id;
  for addon_id in select value::uuid from jsonb_array_elements_text(p_addon_ids) loop
   insert into public.product_addons(product_id,addon_id) values(p.id,addon_id);
  end loop;
 end if;
 return to_jsonb(p);
end $$;
revoke all on function public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb) from public;
-- Supabase also assigns explicit default EXECUTE grants to both API roles.
revoke all on function public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb) from anon, authenticated;
grant execute on function public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb) to service_role;

create function public.swap_catalog_categories(p_actor uuid,p_first uuid,p_second uuid,p_first_order int,p_second_order int) returns void
language plpgsql security definer set search_path='' as $$
declare first_order int; second_order int;
begin
 if not exists(select 1 from public.profiles where id=p_actor and role in ('superadmin','admin') and staff_status='active') then raise insufficient_privilege;end if;
 if p_first is null or p_second is null or p_first=p_second then raise check_violation;end if;
 -- Stable lock order prevents opposing swaps from deadlocking.
 perform id from public.categories order by id for update;
 select sort_order into first_order from public.categories where id=p_first;
 select sort_order into second_order from public.categories where id=p_second;
 if first_order is null or second_order is null then raise no_data_found;end if;
 if first_order is distinct from p_first_order or second_order is distinct from p_second_order then raise check_violation;end if;
 -- Normalize gaps and historical ties using the same stable ordering as the UI.
 with ranked as(select id,row_number() over(order by sort_order,id)::int n from public.categories),
 positions as(select max(n) filter(where id=p_first) a,max(n) filter(where id=p_second) b from ranked)
 update public.categories c set sort_order=case c.id when p_first then positions.b when p_second then positions.a else ranked.n end
 from ranked cross join positions where c.id=ranked.id;
end $$;
revoke all on function public.swap_catalog_categories(uuid,uuid,uuid,int,int) from public,anon,authenticated;
grant execute on function public.swap_catalog_categories(uuid,uuid,uuid,int,int) to service_role;
