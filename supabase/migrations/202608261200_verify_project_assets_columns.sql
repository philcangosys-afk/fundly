-- Ensure all fields used by the current asset forms exist in deployed databases.
alter table if exists public.project_assets
  add column if not exists description text not null default '',
  add column if not exists annexes jsonb not null default '{}'::jsonb,
  add column if not exists units_json text default '[]',
  add column if not exists map_link text,
  add column if not exists quick_add_enabled boolean default false,
  add column if not exists employees_json text default '[]',
  add column if not exists serial_number text,
  add column if not exists license_number text;

alter table if exists public.project_asset_entries
  alter column data set default '{}'::jsonb;