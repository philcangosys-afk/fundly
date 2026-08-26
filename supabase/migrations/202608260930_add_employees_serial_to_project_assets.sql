-- Adds employees list support (for business-activity items) and a serial
-- number field (for equipment items) to project_assets.
alter table if exists public.project_assets
  add column if not exists employees_json text default '[]',
  add column if not exists serial_number text,
  add column if not exists license_number text;
