-- ============================================================
-- Kaksha v6 — cached note translations + PDF slide backgrounds
-- Run AFTER schema_v5.sql (SQL Editor > Run)
-- ============================================================

-- Notes are translated once per language and cached here, so opening
-- them again is instant: { "hi": {<translated notes json>}, ... }
alter table class_notes add column if not exists translations
  jsonb not null default '{}'::jsonb;

-- Slides can carry an imported PDF page as their background image;
-- the teacher draws on top of it.
alter table board_slides add column if not exists background_url text;
