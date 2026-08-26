-- Project assets and their sub-entries (contracts, maintenance, rentals,
-- expenses, revenues, documents). Used by the "إضافة نشاط تجاري" flow.

create table if not exists public.project_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  sub_type text not null,
  category text not null check (category in ('real_estate', 'project', 'business')),
  status text not null default 'نشط',
  location_or_type text,
  amount_label text,
  followup_note text,
  owner text,
  tenant text,
  rent_value text,
  end_date date,
  annual_yield text,
  occupancy_rate numeric(4, 3) not null default 0 check (occupancy_rate >= 0 and occupancy_rate <= 1),
  contract_progress numeric(4, 3) not null default 0 check (contract_progress >= 0 and contract_progress <= 1),
  payment_progress numeric(4, 3) not null default 0 check (payment_progress >= 0 and payment_progress <= 1),
  documents_progress numeric(4, 3) not null default 0 check (documents_progress >= 0 and documents_progress <= 1),
  needs_attention boolean not null default false,
  icon_color integer,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists project_assets_user_created_idx
  on public.project_assets (user_id, created_at desc);

alter table public.project_assets enable row level security;

drop policy if exists "Users read own project assets" on public.project_assets;
create policy "Users read own project assets"
  on public.project_assets for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own project assets" on public.project_assets;
create policy "Users insert own project assets"
  on public.project_assets for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own project assets" on public.project_assets;
create policy "Users update own project assets"
  on public.project_assets for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own project assets" on public.project_assets;
create policy "Users delete own project assets"
  on public.project_assets for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.project_asset_entries (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.project_assets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('contract', 'maintenance', 'rental', 'expense', 'revenue', 'document')),
  data jsonb not null default '{}'::jsonb,
  attachment_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists project_asset_entries_asset_kind_idx
  on public.project_asset_entries (asset_id, kind, created_at desc);

alter table public.project_asset_entries enable row level security;

drop policy if exists "Users read own asset entries" on public.project_asset_entries;
create policy "Users read own asset entries"
  on public.project_asset_entries for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own asset entries" on public.project_asset_entries;
create policy "Users insert own asset entries"
  on public.project_asset_entries for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own asset entries" on public.project_asset_entries;
create policy "Users update own asset entries"
  on public.project_asset_entries for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own asset entries" on public.project_asset_entries;
create policy "Users delete own asset entries"
  on public.project_asset_entries for delete
  to authenticated
  using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('project-asset-attachments', 'project-asset-attachments', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Users upload own project asset attachments" on storage.objects;
create policy "Users upload own project asset attachments"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'project-asset-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users read own project asset attachments" on storage.objects;
create policy "Users read own project asset attachments"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'project-asset-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
