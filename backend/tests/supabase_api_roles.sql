-- Disposable test databases only. Match Supabase's API roles and explicit
-- default grants before applying migrations, so privilege checks are meaningful.
do $$begin
 if to_regrole('anon') is null then create role anon nologin;end if;
 if to_regrole('authenticated') is null then create role authenticated nologin;end if;
 if to_regrole('service_role') is null then create role service_role nologin bypassrls;end if;
end $$;
alter default privileges grant execute on functions to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
