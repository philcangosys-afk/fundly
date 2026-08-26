-- Unit-level (and property-level) financial movement: real income/revenue
-- and expense records for a property or one of its units, powering the
-- "الحركة المالية" tab's "إيراد" / "مصروف" buttons.
--
-- unit_key is nullable on purpose:
--   * not null  -> the entry belongs to that specific unit (شقة/محل/استديو)
--   * null      -> the entry belongs to the property as a whole
-- This lets one table serve both the property-details screen and the
-- unit-details screen without duplicating logic.

create table if not exists public.property_unit_transactions (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.project_assets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  unit_key text,
  kind text not null check (kind in ('income', 'expense')),
  amount numeric(14, 2) not null default 0,
  occurred_on date,
  category text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists property_unit_transactions_asset_idx
  on public.property_unit_transactions(asset_id, occurred_on desc);

create index if not exists property_unit_transactions_unit_idx
  on public.property_unit_transactions(asset_id, unit_key)
  where unit_key is not null;

alter table public.property_unit_transactions enable row level security;

drop policy if exists "Users read own unit transactions" on public.property_unit_transactions;
create policy "Users read own unit transactions"
  on public.property_unit_transactions for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own unit transactions" on public.property_unit_transactions;
create policy "Users insert own unit transactions"
  on public.property_unit_transactions for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own unit transactions" on public.property_unit_transactions;
create policy "Users update own unit transactions"
  on public.property_unit_transactions for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own unit transactions" on public.property_unit_transactions;
create policy "Users delete own unit transactions"
  on public.property_unit_transactions for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on table public.property_unit_transactions to authenticated;
