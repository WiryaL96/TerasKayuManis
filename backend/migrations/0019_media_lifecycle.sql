-- Track uploads independently of forms; deletion never races a new reference.
create table tkm.media_uploads(bucket text not null check(bucket in('media','staff-photos')),path text not null,public_url text,updated_at timestamptz not null default now(),state text not null default 'pending' check(state in('pending','attached','deleting')),primary key(bucket,path));
revoke all on tkm.media_uploads from public;
create function public.register_media_upload(p_bucket text,p_path text,p_url text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if (p_bucket='media' and (p_path!~'^products/[a-f0-9-]{36}\.webp$' or p_url is null)) or (p_bucket='staff-photos' and p_path!~'^[a-f0-9-]{36}/[a-f0-9-]{36}\.webp$') then raise check_violation;end if;
 insert into tkm.media_uploads(bucket,path,public_url) values(p_bucket,p_path,p_url);
end $$;
create function tkm.media_reference_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare old_value text;new_value text; asset tkm.media_uploads;
begin
 if tg_table_name='products' then
  if tg_op<>'INSERT' then old_value:=old.image_url;end if;
  if tg_op<>'DELETE' then new_value:=new.image_url;end if;
  if old_value is distinct from new_value then update tkm.media_uploads set updated_at=now() where bucket='media' and (public_url=old_value or split_part(old_value,'?',1) like '%/storage/v1/object/public/media/'||path);end if;
  select * into asset from tkm.media_uploads where bucket='media' and (public_url=new_value or split_part(new_value,'?',1) like '%/storage/v1/object/public/media/'||path) for update;
 else
  if tg_op<>'INSERT' then old_value:=old.staff_photo_path;end if;
  if tg_op<>'DELETE' then new_value:=new.staff_photo_path;end if;
  if old_value is distinct from new_value then update tkm.media_uploads set updated_at=now() where bucket='staff-photos' and path=old_value;end if;
  select * into asset from tkm.media_uploads where bucket='staff-photos' and path=new_value for update;
 end if;
 if found then
  if asset.state='deleting' then raise check_violation using message='Image expired; upload it again';end if;
  update tkm.media_uploads set state='attached',updated_at=now() where bucket=asset.bucket and path=asset.path;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger product_media_reference before insert or update of image_url or delete on public.products for each row execute function tkm.media_reference_guard();
create trigger staff_media_reference before insert or update of staff_photo_path or delete on public.profiles for each row execute function tkm.media_reference_guard();
create function public.claim_unused_media() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 with candidates as (
 select u.bucket,u.path from tkm.media_uploads u
 where u.updated_at<now()-interval '24 hours'
 and not exists(select 1 from public.products p where u.bucket='media' and (p.image_url=u.public_url or split_part(p.image_url,'?',1) like '%/storage/v1/object/public/media/'||u.path))
 and not exists(select 1 from public.profiles p where u.bucket='staff-photos' and p.staff_photo_path=u.path)
 order by u.updated_at limit 20 for update of u skip locked
 ), marked as(update tkm.media_uploads u set state='deleting' from candidates c where u.bucket=c.bucket and u.path=c.path returning u.bucket,u.path)
 select coalesce(jsonb_agg(to_jsonb(marked)),'[]'::jsonb) into result from marked;
 return result;
end $$;
create function public.finish_media_cleanup(p_bucket text,p_path text) returns void language plpgsql security definer set search_path='' as $$
-- Keep a tombstone so stale forms cannot attach a deleted image.
begin update tkm.media_uploads set updated_at='infinity'::timestamptz where bucket=p_bucket and path=p_path and state='deleting';end $$;

-- Import generated UUID uploads only. Named menu assets are excluded.
-- Public URLs are compared by their exact storage path when the origin is unknown.
do $$begin
 if to_regclass('storage.objects') is not null then
 execute $q$insert into tkm.media_uploads(bucket,path,updated_at)
 select bucket_id,name,coalesce(updated_at,created_at,now()) from storage.objects
 where (bucket_id='staff-photos' and name~'^[a-f0-9-]{36}/[a-f0-9-]{36}\.webp$') or (bucket_id='media' and name~'^products/[a-f0-9-]{36}\.webp$') on conflict do nothing$q$;
 end if;
end $$;

create function public.finish_media_cleanup_batch(p_bucket text,p_paths text[]) returns void language plpgsql security definer set search_path='' as $$
begin
 if cardinality(p_paths)>20 then raise check_violation;end if;
 update tkm.media_uploads set updated_at='infinity'::timestamptz where bucket=p_bucket and path=any(p_paths) and state='deleting';
end $$;

do $$declare f regprocedure;r text;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in('register_media_upload','claim_unused_media','finish_media_cleanup','finish_media_cleanup_batch')) or (n.nspname='tkm' and p.proname='media_reference_guard') loop
 execute format('revoke all on function %s from public',f);
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
 if to_regrole(r) is not null then execute format('revoke all on function %s from %I',f,r);end if;end loop;
 if to_regrole('service_role') is not null then execute format('grant execute on function %s to service_role',f);end if;
 end loop;
 foreach r in array array['anon','authenticated','tkm_runtime'] loop
 if to_regrole(r) is not null then execute format('revoke all on tkm.media_uploads from %I',r);end if;end loop;
end $$;
