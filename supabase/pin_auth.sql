-- Two-PIN access (no accounts). PINs are stored hashed; all data access goes through
-- functions that check the PIN on the server. Tables themselves are closed to the public key.
create extension if not exists pgcrypto with schema extensions;

create table if not exists pin_secrets (role text primary key check (role in ('staff','manager')), pin_hash text not null);
create table if not exists pin_attempts (id bigint generated always as identity primary key, ip text not null, at timestamptz not null default now());
create index if not exists pin_attempts_ip_at on pin_attempts (ip, at);

alter table pin_secrets enable row level security;
alter table pin_attempts enable row level security;
revoke all on pin_secrets, pin_attempts, departments, employees, report_projects, task_categories, reports, attendance, app_settings from anon, authenticated;

-- Internal: returns 'staff' | 'manager' | 'locked' | null. Locks an IP after 10 wrong PINs in 10 minutes.
create or replace function pin_role(p text) returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text; r text;
begin
  v_ip := coalesce(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for','unknown'), ',', 1), 'unknown');
  if (select count(*) from pin_attempts a where a.ip = v_ip and a.at > now() - interval '10 minutes') >= 10 then return 'locked'; end if;
  select s.role into r from pin_secrets s where s.pin_hash = crypt(coalesce(p,''), s.pin_hash) order by (s.role='manager') desc limit 1;
  if r is null then
    insert into pin_attempts(ip) values (v_ip);
    delete from pin_attempts a where a.at < now() - interval '1 day';
  end if;
  return r;
end $$;

create or replace function check_pin(p text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is null or r = 'locked' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object('role', r);
end $$;

create or replace function get_options(p text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is null or r = 'locked' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object(
    'departments', (select coalesce(jsonb_agg(name order by name),'[]'::jsonb) from departments),
    'employees',   (select coalesce(jsonb_agg(jsonb_build_object('department',department,'name',name) order by department,name),'[]'::jsonb) from employees),
    'projects',    (select coalesce(jsonb_agg(name order by name),'[]'::jsonb) from report_projects),
    'categories',  (select coalesce(jsonb_agg(jsonb_build_object('main',main,'sub',sub) order by main,sub),'[]'::jsonb) from task_categories),
    'start_time',  (select value from app_settings where key='work_start_time'));
end $$;

create or replace function submit_reports(p text, dept text, emp text, entries jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is null or r = 'locked' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  if jsonb_typeof(entries) is distinct from 'array' or jsonb_array_length(entries) not between 1 and 50 then return jsonb_build_object('error','invalid entries'); end if;
  if not exists (select 1 from employees e where e.department = dept and e.name = emp) then return jsonb_build_object('error','unknown employee'); end if;
  insert into reports(department, employee, project, building, main_category, task, percentage, note)
  select dept, emp, left(x.project,200), left(x.building,200), left(x.main_category,200), left(x.task,200),
         least(100, greatest(0, coalesce(x.percentage,0))), left(coalesce(x.note,''),5000)
  from jsonb_to_recordset(entries) as x(project text, building text, main_category text, task text, percentage int, note text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function get_reports(p text, d date) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object('reports', (select coalesce(jsonb_agg(to_jsonb(x) order by x.department, x.employee, x.id),'[]'::jsonb) from reports x where x.report_date = d));
end $$;

create or replace function get_attendance(p text, d date) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object('records', (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from attendance x where x.att_date = d));
end $$;

create or replace function save_attendance(p text, d date, start_time text, records jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  if start_time !~ '^\d{2}:\d{2}$' then return jsonb_build_object('error','invalid start time'); end if;
  insert into attendance(att_date, department, employee, arrival_time, status, late_minutes, note, updated_at)
  select d, x.department, x.employee, nullif(x.arrival_time,'')::time, x.status, x.late_minutes, left(coalesce(x.note,''),500), now()
  from jsonb_to_recordset(records) as x(department text, employee text, arrival_time text, status text, late_minutes int, note text)
  on conflict (att_date, department, employee) do update
    set arrival_time = excluded.arrival_time, status = excluded.status, late_minutes = excluded.late_minutes, note = excluded.note, updated_at = now();
  update app_settings set value = start_time where key = 'work_start_time';
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function pin_role(text) from public, anon, authenticated;
revoke execute on function check_pin(text), get_options(text), submit_reports(text,text,text,jsonb), get_reports(text,date), get_attendance(text,date), save_attendance(text,date,text,jsonb) from public;
grant execute on function check_pin(text), get_options(text), submit_reports(text,text,text,jsonb), get_reports(text,date), get_attendance(text,date), save_attendance(text,date,text,jsonb) to anon, authenticated;

-- Set your PINs (run once, choose your own values; they are stored hashed):
-- insert into pin_secrets values ('staff',   extensions.crypt('EMPLOYEE_PIN', extensions.gen_salt('bf')));
-- insert into pin_secrets values ('manager', extensions.crypt('MANAGER_PIN',  extensions.gen_salt('bf')));
