-- ============================================================
-- Kaksha — CSJMU Smart Classroom  |  Supabase schema
-- Paste this whole file into: Supabase Dashboard > SQL Editor > Run
-- ============================================================

create extension if not exists pgcrypto;

-- One classroom per (branch, year). Students and teachers are matched
-- to it automatically, whoever arrives first creates it.
create table if not exists classrooms (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,          -- short join code, e.g. CSE1-7KQ2
  branch     text not null,                 -- branch key, e.g. btech_cse
  year       int  not null check (year between 1 and 6),
  created_at timestamptz not null default now(),
  unique (branch, year)
);

create table if not exists students (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  roll_no      text not null unique,
  branch       text not null,
  year         int  not null,
  classroom_id uuid references classrooms(id) on delete set null,
  created_at   timestamptz not null default now()
);

create table if not exists teachers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  employee_id text not null unique,
  created_at  timestamptz not null default now()
);

-- Weekly recurring schedule slots. day_of_week: 1 = Monday ... 7 = Sunday
create table if not exists schedules (
  id           uuid primary key default gen_random_uuid(),
  teacher_id   uuid not null references teachers(id)   on delete cascade,
  classroom_id uuid not null references classrooms(id) on delete cascade,
  subject      text not null,
  day_of_week  int  not null check (day_of_week between 1 and 7),
  start_time   time not null,
  end_time     time not null,
  created_at   timestamptz not null default now(),
  check (end_time > start_time)
);

-- Smart board slides. Strokes stored as JSON, one row per slide.
create table if not exists board_slides (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  slide_index  int  not null,
  strokes      jsonb not null default '[]'::jsonb,
  updated_at   timestamptz not null default now(),
  unique (classroom_id, slide_index)
);

create index if not exists idx_schedules_classroom on schedules (classroom_id);
create index if not exists idx_schedules_teacher   on schedules (teacher_id);
create index if not exists idx_slides_classroom    on board_slides (classroom_id);

-- ------------------------------------------------------------
-- Row Level Security: open policies for the anon key (prototype).
-- Lock these down before production.
-- ------------------------------------------------------------
alter table classrooms   enable row level security;
alter table students     enable row level security;
alter table teachers     enable row level security;
alter table schedules    enable row level security;
alter table board_slides enable row level security;

drop policy if exists "anon all classrooms"   on classrooms;
drop policy if exists "anon all students"     on students;
drop policy if exists "anon all teachers"     on teachers;
drop policy if exists "anon all schedules"    on schedules;
drop policy if exists "anon all board_slides" on board_slides;

create policy "anon all classrooms"   on classrooms   for all using (true) with check (true);
create policy "anon all students"     on students     for all using (true) with check (true);
create policy "anon all teachers"     on teachers     for all using (true) with check (true);
create policy "anon all schedules"    on schedules    for all using (true) with check (true);
create policy "anon all board_slides" on board_slides for all using (true) with check (true);

-- Realtime for live board updates (safe to re-run)
do $$
begin
  alter publication supabase_realtime add table board_slides;
exception when duplicate_object then null;
end $$;
