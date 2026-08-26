-- Structured property description introduced by the real-estate annexes flow.
alter table public.project_assets
  add column if not exists description text not null default '',
  add column if not exists annexes jsonb not null default '{}'::jsonb;

comment on column public.project_assets.description is
  'General property description supplied by the owner.';
comment on column public.project_assets.annexes is
  'Annex/facility counts keyed by Arabic label, including optional custom labels.';
