-- ============================================================
-- Kaksha v8 — lecture-video transcription & subtitles
-- SAFE TO RUN STANDALONE: includes everything from v7, so if v7 was
-- skipped this single file sets up both. Re-running is harmless.
-- ============================================================

-- ------------------------------------------------------------
-- (from v7) Live captions during class
-- ------------------------------------------------------------
create table if not exists live_captions (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references board_sessions(id) on delete cascade,
  classroom_id uuid not null references classrooms(id) on delete cascade,
  slide_index  int  not null default 0,
  chunk_index  int  not null default 0,
  start_s      double precision not null default 0,
  end_s        double precision not null default 0,
  text         text not null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_live_captions_session
  on live_captions (session_id, start_s);

-- ------------------------------------------------------------
-- (from v7) Teacher-uploaded encrypted media
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- v8: lecture recordings — subtitles + notes synthesis
-- ------------------------------------------------------------
alter table class_media add column if not exists session_id
  uuid references board_sessions(id) on delete set null;
alter table class_media add column if not exists transcript_status
  text not null default 'none'
  check (transcript_status in ('none','processing','ready','failed'));

-- Slide-change timestamps are kept on the session so a video uploaded
-- later can still be aligned slide-by-slide.
alter table board_sessions add column if not exists slide_marks jsonb;

-- Subtitles for uploaded media, timestamped against playback position.
create table if not exists media_captions (
  id         uuid primary key default gen_random_uuid(),
  media_id   uuid not null references class_media(id) on delete cascade,
  start_s    double precision not null default 0,
  end_s      double precision not null default 0,
  text       text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_media_captions_media
  on media_captions (media_id, start_s);

alter table media_captions enable row level security;
drop policy if exists "anon all media_captions" on media_captions;
create policy "anon all media_captions" on media_captions
  for all using (true) with check (true);
