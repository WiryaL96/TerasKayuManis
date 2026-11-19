-- Disposable database only. Every fixture and write is rolled back.
begin;
do $$
declare actor uuid:=gen_random_uuid(); cashier uuid:=gen_random_uuid(); category uuid; category2 uuid; addon uuid; product uuid; variant uuid; other uuid; before_data jsonb; result jsonb; n bigint;
begin
 insert into public.profiles(id,full_name,role,staff_status) values(actor,'Catalog Admin','admin','active'),(cashier,'Catalog Cashier','cashier','active');
 insert into public.categories(name,slug) values('Catalog CRUD',gen_random_uuid()::text) returning id into category;
 insert into public.categories(name,slug,sort_order) values('Catalog CRUD 2',gen_random_uuid()::text,1) returning id into category2;
 perform public.swap_catalog_categories(actor,category,category2,0,1);
 if (select sort_order from public.categories where id=category)<=(select sort_order from public.categories where id=category2) then raise exception 'category swap failed';end if;
 begin perform public.swap_catalog_categories(actor,category,category2,0,1);raise exception 'stale reorder accepted';exception when check_violation then null;end;
 select to_jsonb(c) into before_data from public.categories c where id=category;
 begin perform public.swap_catalog_categories(actor,category,category2,0,1);exception when check_violation then null;end;
 if (select to_jsonb(c) from public.categories c where id=category) is distinct from before_data then raise exception 'stale swap partly committed';end if;
 insert into public.addons(name,price) values('Catalog Addon',2000) returning id into addon;
 result:=public.save_catalog_product(actor,null,jsonb_build_object('category_id',category,'name','Coffee CRUD','slug',gen_random_uuid(),'price',10000),
  '[{"name":"Large","group_name":"Size","price_modifier":3000}]',jsonb_build_array(addon));
 product:=(result->>'id')::uuid;
 select id into variant from public.product_variants where product_id=product;
 if variant is null or not exists(select 1 from public.product_addons where product_id=product and addon_id=addon) then raise exception 'extras not created';end if;
 perform public.save_catalog_product(actor,product,'{"price":12000}',jsonb_build_array(jsonb_build_object('id',variant,'name','Extra Large','price_modifier',4000)),null);
 if (select price from public.products where id=product)<>12000 or (select name from public.product_variants where id=variant)<>'Extra Large' then raise exception 'update lost';end if;
 select to_jsonb(p) into before_data from public.products p where id=product;
 -- Invalid add-on happens after updating the product and variants: ALL roll back.
 begin
  perform public.save_catalog_product(actor,product,'{"price":99999}', '[]',jsonb_build_array(gen_random_uuid()));
  raise exception 'missing addon accepted';
 exception when foreign_key_violation then null;end;
 if (select to_jsonb(p) from public.products p where id=product) is distinct from before_data or not exists(select 1 from public.product_variants where id=variant) or not exists(select 1 from public.product_addons where product_id=product and addon_id=addon) then raise exception 'partial catalog write';end if;
 select count(*) into n from public.products;
 begin
  perform public.save_catalog_product(actor,null,jsonb_build_object('category_id',category,'name','Invalid','slug',gen_random_uuid(),'price',10000),'[{"name":"Bad","price_modifier":-1}]',null);
  raise exception 'invalid variant accepted';
 exception when check_violation then null;end;
 if (select count(*) from public.products)<>n then raise exception 'failed create left orphan';end if;
 result:=public.save_catalog_product(actor,null,jsonb_build_object('category_id',category,'name','Other','slug',gen_random_uuid(),'price',1000),null,null);other:=(result->>'id')::uuid;
 begin
  perform public.save_catalog_product(actor,other,'{}',jsonb_build_array(jsonb_build_object('id',variant,'name','Stolen')),null);
  raise exception 'foreign variant accepted';
 exception when check_violation then null;end;
 begin perform public.save_catalog_product(cashier,product,'{"price":1}',null,null);raise exception 'cashier modified catalog';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='disabled' where id=actor;
 begin perform public.save_catalog_product(actor,product,'{"price":1}',null,null);raise exception 'disabled admin modified catalog';exception when insufficient_privilege then null;end;
 update public.profiles set staff_status='active' where id=actor;
 begin perform public.save_catalog_product(actor,gen_random_uuid(),'{}',null,null);raise exception 'missing product accepted';exception when no_data_found then null;end;
 perform public.save_catalog_product(actor,product,'{"is_available":false}','[]','[]');
 if exists(select 1 from public.product_variants where product_id=product) or exists(select 1 from public.product_addons where product_id=product) then raise exception 'extras not removed';end if;
 delete from public.products where id in(product,other);
 delete from public.addons where id=addon;
 delete from public.categories where id in(category,category2);
 if has_function_privilege('anon','public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb)','EXECUTE') or has_function_privilege('authenticated','public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb)','EXECUTE') or has_function_privilege('tkm_runtime','public.save_catalog_product(uuid,uuid,jsonb,jsonb,jsonb)','EXECUTE') then raise exception 'catalog RPC publicly exposed';end if;
end $$;
rollback;
