-- ============================================================
-- Kaksha v8 — lecture-video transcription & subtitles
-- Run AFTER schema_v7.sql (SQL Editor > Run)
--
-- The teacher uploads the class lecture recording after class; its
-- audio is transcribed once and becomes (a) player subtitles in each
-- student's language and (b) the transcript used to synthesise class
-- notes together with the session's slides.
-- ============================================================

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
