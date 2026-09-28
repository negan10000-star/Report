-- Daily Progress Report: Supabase schema (replaces Google Sheets tabs)
-- Run in Supabase SQL editor, or as a migration.

create table departments (name text primary key);
create table employees (
  id bigint generated always as identity primary key,
  department text not null references departments(name),
  name text not null,
  unique (department, name)
);
create table projects (name text primary key);
create table task_categories (           -- the old "Tasks" sheet
  main text not null,                    -- main category (a department name or اجتماع/عام/...)
  sub  text not null,
  primary key (main, sub)
);

-- Append-only event log: no update/delete policies exist, so past reports can't be edited.
-- Corrections are new rows (use the note field).
create table reports (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  report_date date not null default (now() at time zone 'Asia/Damascus')::date,
  submitted_by uuid not null default auth.uid() references auth.users(id),
  department text not null,
  employee text not null,
  project text not null,
  building text not null,
  main_category text not null,
  task text not null,
  percentage smallint not null check (percentage between 0 and 100),
  note text not null default '' check (length(note) <= 5000)
);
create index on reports (report_date);

create table attendance (
  att_date date not null,
  department text not null,
  employee text not null,
  arrival_time time,
  status text not null check (status in ('حاضر','متأخر','غائب','إجازة')),
  late_minutes int,
  note text not null default '',
  updated_at timestamptz not null default now(),
  primary key (att_date, department, employee)
);

create table app_settings (key text primary key, value text not null);
insert into app_settings values ('work_start_time','08:00');

-- Roles: replaces the two shared PIN codes with real accounts
create table profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'staff' check (role in ('staff','manager'))
);
create function handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin insert into public.profiles(user_id) values (new.id); return new; end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

create function is_manager() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'manager') $$;

-- Row Level Security
alter table departments enable row level security;
alter table employees enable row level security;
alter table projects enable row level security;
alter table task_categories enable row level security;
alter table reports enable row level security;
alter table attendance enable row level security;
alter table app_settings enable row level security;
alter table profiles enable row level security;

create policy "read ref" on departments for select to authenticated using (true);
create policy "read ref" on employees for select to authenticated using (true);
create policy "read ref" on projects for select to authenticated using (true);
create policy "read ref" on task_categories for select to authenticated using (true);
create policy "read settings" on app_settings for select to authenticated using (true);
create policy "manager edits ref" on employees for all to authenticated using (is_manager()) with check (is_manager());
create policy "manager edits projects" on projects for all to authenticated using (is_manager()) with check (is_manager());

create policy "staff insert reports" on reports for insert to authenticated with check (submitted_by = auth.uid());
create policy "manager reads reports" on reports for select to authenticated using (is_manager());
create policy "staff read own reports" on reports for select to authenticated using (submitted_by = auth.uid());

create policy "manager attendance" on attendance for all to authenticated using (is_manager()) with check (is_manager());
create policy "manager settings" on app_settings for update to authenticated using (is_manager());
create policy "read own profile" on profiles for select to authenticated using (user_id = auth.uid());

-- Sample data
insert into departments values ('مدني'),('معماري'),('كهرباء'),('ميكانيك');
insert into employees(department,name) values ('مدني','موظف 1'),('كهرباء','موظف 2'),('ميكانيك','موظف 3');
insert into projects values ('مشروع تجريبي أ'),('مشروع تجريبي ب');
insert into task_categories values ('مدني','حفر'),('مدني','صب خرسانة'),('كهرباء','تمديد كابلات'),('ميكانيك','تركيب مضخات'),('اجتماع','اجتماع تنسيق'),('عام','مهمة عامة');

-- To make someone a manager (after they sign up):
-- update profiles set role='manager' where user_id = (select id from auth.users where email='you@company.com');
