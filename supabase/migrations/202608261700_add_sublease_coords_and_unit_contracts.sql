-- Real-estate rebuild: adds a sublease flag + map coordinates to
-- project_assets. property_unit_contracts / property_unit_payments already
-- exist (see 202608261430_create_property_unit_contracts.sql) — this file
-- only extends project_assets with the two new fields the rebuild needs
-- for the list-card "باطن" badge and the static-map header.

alter table if exists public.project_assets
  add column if not exists is_sublease boolean not null default false,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;
