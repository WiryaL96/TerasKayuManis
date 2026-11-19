-- Local/CI contract fixture only. Actual pg_cron execution is verified on Supabase.
begin;
create schema cron;
create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text,username name default current_user,active boolean default true,unique(jobname,username));
create function cron.schedule(text,text,text) returns bigint language sql as $$
 insert into cron.job(jobname,schedule,command) values($1,$2,$3)
 on conflict(jobname,username) do update set schedule=excluded.schedule,command=excluded.command,active=true returning jobid;
$$;
select cron.schedule('unrelated-job','0 0 * * *','select 1');
\ir ../../deploy/supabase-cron.sql
\ir ../../deploy/supabase-cron.sql
do $$begin
 if (select count(*) from cron.job)<>3 then raise exception 'Duplicate cron jobs';end if;
 if not exists(select 1 from cron.job where jobname='tkm-maintenance' and schedule='* * * * *' and command like '%tkm.serverless_maintenance()%' and active) then raise exception 'Maintenance job missing';end if;
 if not exists(select 1 from cron.job where jobname='unrelated-job' and command='select 1') then raise exception 'Unrelated job modified';end if;
 if not exists(select 1 from cron.job where jobname='tkm-cron-history-cleanup' and command like '%jobid in%') then raise exception 'History cleanup must stay scoped';end if;
end $$;
rollback;
