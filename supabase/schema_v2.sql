-- ============================================================
-- Kaksha v2 — attendance, assignments, doubt tickets, live class
-- Run AFTER schema.sql:  Supabase Dashboard > SQL Editor > Run
-- ============================================================

-- Preferred UI / translation language per user
alter table students add column if not exists language text not null default 'en';
alter table teachers add column if not exists language text not null default 'en';

-- ------------------------------------------------------------
-- Attendance (rows arrive from an external source later;
-- the app only reads them)
-- ------------------------------------------------------------
create table if not exists attendance (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references students(id)   on delete cascade,
  classroom_id uuid not null references classrooms(id) on delete cascade,
  day          date not null,
  status       text not null default 'present' check (status in ('present','absent','late')),
  created_at   timestamptz not null default now(),
  unique (student_id, day)
);

-- ------------------------------------------------------------
-- Assignments & submissions
-- ------------------------------------------------------------
create table if not exists assignments (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  teacher_id   uuid not null references teachers(id)   on delete cascade,
  title        text not null,
  description  text not null default '',
  due_at       timestamptz,
  max_score    int  not null default 100,
  created_at   timestamptz not null default now()
);

create table if not exists submissions (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id) on delete cascade,
  student_id    uuid not null references students(id)    on delete cascade,
  content       text not null default '',
  submitted_at  timestamptz not null default now(),
  score         int,          -- null until the teacher evaluates
  feedback      text,
  unique (assignment_id, student_id)
);

-- ------------------------------------------------------------
-- Doubt tickets: 1-to-1 student <-> teacher threads
-- ------------------------------------------------------------
create table if not exists tickets (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  student_id   uuid not null references students(id)   on delete cascade,
  title        text not null,
  status       text not null default 'open' check (status in ('open','resolved')),
  created_at   timestamptz not null default now()
);

create table if not exists ticket_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references tickets(id) on delete cascade,
  sender_role text not null check (sender_role in ('student','teacher')),
  sender_name text not null default '',
  kind        text not null default 'text' check (kind in ('text','image','voice','meeting')),
  body        text not null default '',   -- text, or the meeting URL for kind='meeting'
  media_path  text,                       -- storage path for image / voice
  created_at  timestamptz not null default now()
);

-- Scheduled 1-to-1 video calls (kept also as a ticket message)
create table if not exists meetings (
  id           uuid primary key default gen_random_uuid(),
  ticket_id    uuid not null references tickets(id) on delete cascade,
  scheduled_at timestamptz not null,
  url          text not null,
  created_at   timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Live classroom events: raised hands + chat popups on the board
-- ------------------------------------------------------------
create table if not exists class_events (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  student_id   uuid references students(id) on delete set null,
  student_name text not null default '',
  kind         text not null check (kind in ('hand','chat')),
  slide_index  int  not null default 0,
  body         text not null default '',
  created_at   timestamptz not null default now()
);

create index if not exists idx_attendance_classroom on attendance (classroom_id, day);
create index if not exists idx_assignments_classroom on assignments (classroom_id, created_at);
create index if not exists idx_submissions_assignment on submissions (assignment_id);
create index if not exists idx_tickets_classroom on tickets (classroom_id, status);
create index if not exists idx_ticket_messages_ticket on ticket_messages (ticket_id, created_at);
create index if not exists idx_class_events_classroom on class_events (classroom_id, created_at);

-- ------------------------------------------------------------
-- RLS: open anon policies (prototype)
-- ------------------------------------------------------------
alter table attendance      enable row level security;
alter table assignments     enable row level security;
alter table submissions     enable row level security;
alter table tickets         enable row level security;
alter table ticket_messages enable row level security;
alter table meetings        enable row level security;
alter table class_events    enable row level security;

drop policy if exists "anon all attendance"      on attendance;
drop policy if exists "anon all assignments"     on assignments;
drop policy if exists "anon all submissions"     on submissions;
drop policy if exists "anon all tickets"         on tickets;
drop policy if exists "anon all ticket_messages" on ticket_messages;
drop policy if exists "anon all meetings"        on meetings;
drop policy if exists "anon all class_events"    on class_events;

create policy "anon all attendance"      on attendance      for all using (true) with check (true);
create policy "anon all assignments"     on assignments     for all using (true) with check (true);
create policy "anon all submissions"     on submissions     for all using (true) with check (true);
create policy "anon all tickets"         on tickets         for all using (true) with check (true);
create policy "anon all ticket_messages" on ticket_messages for all using (true) with check (true);
create policy "anon all meetings"        on meetings        for all using (true) with check (true);
create policy "anon all class_events"    on class_events    for all using (true) with check (true);

-- ------------------------------------------------------------
-- Realtime: live assignments, chats, tickets and board updates
-- (board_slides was added in schema.sql; re-adding is a no-op)
-- ------------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table assignments;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table submissions;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table tickets;         exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table ticket_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table class_events;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table board_slides;    exception when duplicate_object then null; end;
end $$;

-- ------------------------------------------------------------
-- Storage: public 'media' bucket for ticket images & voice notes
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

drop policy if exists "anon read media"   on storage.objects;
drop policy if exists "anon insert media" on storage.objects;

create policy "anon read media"   on storage.objects for select using (bucket_id = 'media');
create policy "anon insert media" on storage.objects for insert with check (bucket_id = 'media');
