-- Ensure authenticated app sessions can read/write project assets tables.
-- This is safe to run multiple times.

grant usage on schema public to authenticated;

grant select, insert, update, delete on table public.project_assets to authenticated;
grant select, insert, update, delete on table public.project_asset_entries to authenticated;

-- Keep row-level security enabled and explicitly scoped to the current user.
alter table if exists public.project_assets enable row level security;
alter table if exists public.project_asset_entries enable row level security;

-- Recreate policies idempotently (protects against accidental policy deletion).
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
