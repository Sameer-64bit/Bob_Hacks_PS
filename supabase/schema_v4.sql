-- ============================================================
-- Kaksha v4 — class notes generated after "End class"
-- Run AFTER schema_v3.sql (SQL Editor > Run)
--
-- The teacher's board uploads slides + optional lecture audio to the
-- AI proxy, which writes progress into this table while it works.
-- Students watch the row in realtime: progress bar fills, then the
-- notes appear.
-- ============================================================

create table if not exists class_notes (
  id           uuid primary key default gen_random_uuid(),
  classroom_id uuid not null references classrooms(id) on delete cascade,
  status       text not null default 'processing'
               check (status in ('processing','ready','failed')),
  progress     int  not null default 0 check (progress between 0 and 100),
  stage        text not null default 'Starting…',
  language     text not null default 'en',
  notes        jsonb,                    -- structured notes JSON when ready
  error        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_class_notes_classroom
  on class_notes (classroom_id, created_at desc);

alter table class_notes enable row level security;
drop policy if exists "anon all class_notes" on class_notes;
create policy "anon all class_notes" on class_notes for all using (true) with check (true);

do $$
begin
  alter publication supabase_realtime add table class_notes;
exception when duplicate_object then null;
end $$;
