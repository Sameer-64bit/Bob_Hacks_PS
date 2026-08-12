-- ============================================================
-- Kaksha v3 — AI server discovery
-- Run AFTER schema.sql and schema_v2.sql (SQL Editor > Run)
--
-- The SmolVLM proxy announces its current LAN address here every
-- few seconds; the app looks the address up instead of hardcoding
-- an IP, so requests always reach the server no matter what IP the
-- wifi hands it.
-- ============================================================

create table if not exists ai_servers (
  id         text primary key,          -- 'default' for the main proxy
  url        text not null,             -- e.g. http://192.168.1.7:5000
  updated_at timestamptz not null default now()
);

alter table ai_servers enable row level security;

drop policy if exists "anon all ai_servers" on ai_servers;
create policy "anon all ai_servers" on ai_servers for all using (true) with check (true);
