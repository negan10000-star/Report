-- Functions that return data in the same shape as the original Apps Script app.
create or replace function get_all_reports(p text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object('reports', (select coalesce(jsonb_agg(jsonb_build_object(
      'timestamp', x.created_at, 'department', x.department, 'name', x.employee, 'project', x.project, 'building', x.building,
      'mainCategory', x.main_category, 'task', x.task, 'percentage', x.percentage || '%', 'report', x.note) order by x.id), '[]'::jsonb)
    from reports x));
end $$;

create or replace function get_attendance(p text, d date) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object(
    'startTime', (select value from app_settings where key='work_start_time'),
    'records', (select coalesce(jsonb_agg(jsonb_build_object('date', x.att_date, 'department', x.department, 'name', x.employee,
      'arrivalTime', coalesce(to_char(x.arrival_time,'HH24:MI'),''), 'status', x.status, 'lateMinutes', coalesce(x.late_minutes::text,''), 'note', x.note)), '[]'::jsonb)
      from attendance x where x.att_date = d));
end $$;

create or replace function get_attendance_report(p text, start_date date, end_date date, dept text, emp text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p);
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  return jsonb_build_object('records', (select coalesce(jsonb_agg(jsonb_build_object('date', x.att_date, 'department', x.department, 'name', x.employee,
      'arrivalTime', coalesce(to_char(x.arrival_time,'HH24:MI'),''), 'status', x.status, 'lateMinutes', coalesce(x.late_minutes::text,''), 'note', x.note)
      order by x.employee, x.att_date), '[]'::jsonb)
    from attendance x where x.att_date between start_date and end_date
      and (coalesce(dept,'') = '' or x.department = dept) and (coalesce(emp,'') = '' or x.employee = emp)));
end $$;

-- Same rules as the original: vacation / absent / late calculation; rewrites the whole day.
create or replace function save_attendance(p text, d date, start_time text, records jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r text := pin_role(p); start_min int;
begin
  if r is distinct from 'manager' then return jsonb_build_object('error', coalesce(r,'unauthorized')); end if;
  if start_time !~ '^\d{1,2}:\d{2}$' then return jsonb_build_object('error','invalid start time'); end if;
  start_min := split_part(start_time,':',1)::int*60 + split_part(start_time,':',2)::int;
  delete from attendance where att_date = d;
  insert into attendance(att_date, department, employee, arrival_time, status, late_minutes, note, updated_at)
  select d, left(x.department,200), left(x.name,200),
    case when x.vacation or x.absent or coalesce(x."arrivalTime",'') = '' then null else x."arrivalTime"::time end,
    case when x.vacation then 'إجازة' when x.absent then 'غائب'
         when coalesce(x."arrivalTime",'') = '' then 'حاضر'
         when (split_part(x."arrivalTime",':',1)::int*60 + split_part(x."arrivalTime",':',2)::int) > start_min then 'متأخر' else 'حاضر' end,
    case when x.vacation or x.absent or coalesce(x."arrivalTime",'') = '' then null
         else greatest(0, split_part(x."arrivalTime",':',1)::int*60 + split_part(x."arrivalTime",':',2)::int - start_min) end,
    left(coalesce(x.note,''),500), now()
  from jsonb_to_recordset(records) as x(department text, name text, "arrivalTime" text, vacation boolean, absent boolean, note text)
  where x.vacation or x.absent or coalesce(x."arrivalTime",'') <> '' or btrim(coalesce(x.note,'')) <> ''
  on conflict (att_date, department, employee) do nothing;
  insert into app_settings values ('work_start_time', start_time) on conflict (key) do update set value = excluded.value;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function get_all_reports(text), get_attendance_report(text,date,date,text,text) from public;
grant execute on function get_all_reports(text), get_attendance_report(text,date,date,text,text) to anon, authenticated;
