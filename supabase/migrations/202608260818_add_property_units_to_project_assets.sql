-- Adds real-estate "units" support (apartments/shops generated from the
-- new "إضافة عقار" wizard) to the existing project_assets table, plus the
-- map-link and quick-add-toggle fields used by that wizard.
alter table if exists public.project_assets
  add column if not exists units_json text default '[]',
  add column if not exists map_link text,
  add column if not exists quick_add_enabled boolean default false;
