-- ============================================================
-- Kaksha v9 — media belongs to a subject, not the whole classroom
-- Run AFTER schema_v8.sql (SQL Editor > Run)
--
-- A classroom can host several subjects (schedule entries). Uploaded
-- media is now tagged with the schedule entry it belongs to, so an ML
-- video never shows up under the Data Training class sheet.
-- ============================================================

alter table class_media add column if not exists schedule_id
  uuid references schedules(id) on delete set null;

create index if not exists idx_class_media_schedule
  on class_media (schedule_id);
