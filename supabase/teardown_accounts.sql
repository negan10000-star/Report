-- Only needed if you applied the earlier account-based version.
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists handle_new_user() cascade;
drop function if exists is_manager() cascade;
do $$ declare x record; begin
  for x in select policyname, tablename from pg_policies where schemaname='public'
    and tablename in ('departments','employees','report_projects','task_categories','reports','attendance','app_settings','profiles')
  loop execute format('drop policy %I on public.%I', x.policyname, x.tablename); end loop; end $$;
drop table if exists profiles;
alter table reports drop column if exists submitted_by;
