-- Operator-only. Install pg_cron and apply 0015/0016 first; never run at build time.
-- Named jobs are updated in place, so retrying does not create duplicate workers.
do $$
begin
 if not exists(select 1 from pg_roles where rolname=current_user and (rolsuper or rolcreaterole)) then
  raise insufficient_privilege using message='Run cron provisioning with the private database operator';
 end if;
 if to_regprocedure('tkm.serverless_maintenance()') is null or to_regclass('cron.job') is null then
  raise exception 'Install pg_cron and apply the serverless migrations first';
 end if;
end $$;

select cron.schedule('tkm-maintenance', '* * * * *',
 $job$set statement_timeout='8s'; select tkm.serverless_maintenance();$job$);

-- 03:00 WIB. Retain only our own job history for 30 days; no restaurant data is removed.
select cron.schedule('tkm-cron-history-cleanup', '0 20 * * *',
 $job$set statement_timeout='8s'; delete from cron.job_run_details
 where jobid in (select jobid from cron.job where jobname in ('tkm-maintenance','tkm-cron-history-cleanup'))
 and end_time < now()-interval '30 days';$job$);
