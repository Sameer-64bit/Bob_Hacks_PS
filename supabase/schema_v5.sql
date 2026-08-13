-- ============================================================
-- Kaksha v5 — board sessions (one whiteboard per class period)
-- Run AFTER schema_v4.sql (SQL Editor > Run)
--
-- Every teaching period gets its own board tied to date & time.
-- "End class" closes the session; "New board" opens a fresh one
-- under the same classroom code. Students (and the teacher) can
-- browse every past board by date, and class notes remember which
-- session they came from.
-- ============================================================

create table if not exists board_sessions (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  started_at   timestamptz not null default now(),
  ended_at     timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists idx_board_sessions_classroom
  on board_sessions (classroom_id, started_at desc);

alter table board_slides add column if not exists session_id
  uuid references board_sessions(id) on delete cascade;
alter table class_notes add column if not exists session_id
  uuid references board_sessions(id) on delete set null;

-- Migrate pre-session slides: one legacy session per classroom.
insert into board_sessions (classroom_id)
select distinct classroom_id from board_slides where session_id is null;

update board_slides bs
   set session_id = s.id
  from board_sessions s
 where bs.session_id is null
   and s.classroom_id = bs.classroom_id;

-- Slides are now unique per session, not per classroom.
alter table board_slides
  drop constraint if exists board_slides_classroom_id_slide_index_key;
create unique index if not exists uq_board_slides_session_slide
  on board_slides (session_id, slide_index);

alter table board_sessions enable row level security;
drop policy if exists "anon all board_sessions" on board_sessions;
create policy "anon all board_sessions" on board_sessions
  for all using (true) with check (true);

do $$
begin
  alter publication supabase_realtime add table board_sessions;
exception when duplicate_object then null;
end $$;
