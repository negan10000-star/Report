-- Daily Progress Report: Supabase schema (replaces Google Sheets tabs)
-- Run in Supabase SQL editor, or as a migration.

create table departments (name text primary key);
create table employees (
  id bigint generated always as identity primary key,
  department text not null references departments(name),
  name text not null,
  unique (department, name)
);
create table report_projects (name text primary key);
create table task_categories (           -- the old "Tasks" sheet
  main text not null,                    -- main category (a department name or اجتماع/عام/...)
  sub  text not null,
  primary key (main, sub)
);

-- Append-only event log: the app only exposes an insert function, so past reports can't be edited.
-- Corrections are new rows (use the note field).
create table reports (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  report_date date not null default (now() at time zone 'Asia/Damascus')::date,
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


alter table departments enable row level security;
alter table employees enable row level security;
alter table report_projects enable row level security;
alter table task_categories enable row level security;
alter table reports enable row level security;
alter table attendance enable row level security;
alter table app_settings enable row level security;

-- Then run pin_auth.sql and set your two PINs.

-- Sample data
insert into departments values ('مدني'),('معماري'),('كهرباء'),('ميكانيك');
insert into employees(department,name) values ('مدني','موظف 1'),('كهرباء','موظف 2'),('ميكانيك','موظف 3');
insert into report_projects values ('مشروع تجريبي أ'),('مشروع تجريبي ب');
insert into task_categories values ('مدني','حفر'),('مدني','صب خرسانة'),('كهرباء','تمديد كابلات'),('ميكانيك','تركيب مضخات'),('اجتماع','اجتماع تنسيق'),('عام','مهمة عامة');

