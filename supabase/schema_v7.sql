-- ============================================================
-- Kaksha v7 — live lecture captions + encrypted class media
-- Run AFTER schema_v6.sql (SQL Editor > Run)
-- ============================================================

-- Live transcription: the teacher's board sends short audio chunks while
-- recording; the AI proxy transcribes each and inserts caption rows here.
-- Students stream them in realtime (and translate them client-side).
-- "End class" reuses these rows as the lecture transcript.
create table if not exists live_captions (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references board_sessions(id) on delete cascade,
  classroom_id uuid not null references classrooms(id) on delete cascade,
  slide_index  int  not null default 0,
  chunk_index  int  not null default 0,
  start_s      double precision not null default 0,  -- seconds from lecture start
  end_s        double precision not null default 0,
  text         text not null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_live_captions_session
  on live_captions (session_id, start_s);

-- Teacher-uploaded media (compressed + encrypted blobs in the media
-- bucket; only the app can decrypt and play them).
create table if not exists class_media (
  id             uuid primary key default gen_random_uuid(),
  classroom_id   uuid not null references classrooms(id) on delete cascade,
  teacher_id     uuid references teachers(id) on delete set null,
  title          text not null,
  mime           text not null,
  bytes_original bigint not null default 0,
  bytes_stored   bigint not null default 0,
  path           text not null,               -- storage path of the encrypted blob
  iv             text not null,               -- AES IV (hex), unique per file
  created_at     timestamptz not null default now()
);

create index if not exists idx_class_media_classroom
  on class_media (classroom_id, created_at desc);

alter table live_captions enable row level security;
alter table class_media   enable row level security;

drop policy if exists "anon all live_captions" on live_captions;
drop policy if exists "anon all class_media"   on class_media;
create policy "anon all live_captions" on live_captions for all using (true) with check (true);
create policy "anon all class_media"   on class_media   for all using (true) with check (true);

do $$
begin
  alter publication supabase_realtime add table live_captions;
exception when duplicate_object then null;
end $$;
