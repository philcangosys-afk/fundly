-- ===================================================================
-- 202608170001_add_property_description_annexes.sql
-- ===================================================================
-- Structured property description introduced by the real-estate annexes flow.
alter table public.project_assets
  add column if not exists description text not null default '',
  add column if not exists annexes jsonb not null default '{}'::jsonb;

comment on column public.project_assets.description is
  'General property description supplied by the owner.';
comment on column public.project_assets.annexes is
  'Annex/facility counts keyed by Arabic label, including optional custom labels.';


-- ===================================================================
-- 202608260818_add_property_units_to_project_assets.sql
-- ===================================================================
-- Adds real-estate "units" support (apartments/shops generated from the
-- new "إضافة عقار" wizard) to the existing project_assets table, plus the
-- map-link and quick-add-toggle fields used by that wizard.
alter table if exists public.project_assets
  add column if not exists units_json text default '[]',
  add column if not exists map_link text,
  add column if not exists quick_add_enabled boolean default false;


-- ===================================================================
-- 202608260930_add_employees_serial_to_project_assets.sql
-- ===================================================================
-- Adds employees list support (for business-activity items) and a serial
-- number field (for equipment items) to project_assets.
alter table if exists public.project_assets
  add column if not exists employees_json text default '[]',
  add column if not exists serial_number text;


-- ===================================================================
-- 202608261200_verify_project_assets_columns.sql
-- ===================================================================
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

-- ===================================================================
-- 202608261230_fix_project_assets_permissions.sql
-- ===================================================================
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


-- ===================================================================
-- 202608261430_create_property_unit_contracts.sql
-- ===================================================================
-- Structured real-estate unit contracts and payment tracking.
-- Keeps compatibility with existing project_assets / project_asset_entries flow.

create table if not exists public.property_unit_contracts (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.project_assets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  unit_key text not null,
  unit_name text,
  tenant_name text,
  lease_type text not null default 'standard' check (lease_type in ('standard', 'multi_unit', 'sublease')),
  annual_rent numeric(14, 2) not null default 0,
  payment_cycle text not null default 'شهري',
  start_date date,
  end_date date,
  status text not null default 'active' check (status in ('active', 'expired', 'pending', 'late')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists property_unit_contracts_asset_idx
  on public.property_unit_contracts(asset_id, created_at desc);

alter table public.property_unit_contracts enable row level security;

drop policy if exists "Users read own unit contracts" on public.property_unit_contracts;
create policy "Users read own unit contracts"
  on public.property_unit_contracts for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own unit contracts" on public.property_unit_contracts;
create policy "Users insert own unit contracts"
  on public.property_unit_contracts for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own unit contracts" on public.property_unit_contracts;
create policy "Users update own unit contracts"
  on public.property_unit_contracts for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own unit contracts" on public.property_unit_contracts;
create policy "Users delete own unit contracts"
  on public.property_unit_contracts for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create table if not exists public.property_unit_payments (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.property_unit_contracts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  due_date date,
  amount_due numeric(14, 2) not null default 0,
  amount_paid numeric(14, 2) not null default 0,
  paid_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'paid', 'late', 'partial')),
  reference_no text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists property_unit_payments_contract_idx
  on public.property_unit_payments(contract_id, due_date desc);

alter table public.property_unit_payments enable row level security;

drop policy if exists "Users read own unit payments" on public.property_unit_payments;
create policy "Users read own unit payments"
  on public.property_unit_payments for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own unit payments" on public.property_unit_payments;
create policy "Users insert own unit payments"
  on public.property_unit_payments for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own unit payments" on public.property_unit_payments;
create policy "Users update own unit payments"
  on public.property_unit_payments for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own unit payments" on public.property_unit_payments;
create policy "Users delete own unit payments"
  on public.property_unit_payments for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete on table public.property_unit_contracts to authenticated;
grant select, insert, update, delete on table public.property_unit_payments to authenticated;


-- ===================================================================
-- 202608261500_add_equipment_category_and_frozen_pinned.sql
-- ===================================================================
-- المعدات كانت تُحفظ سابقًا بنفس قيمة الأنشطة التجارية ('business') في عمود
-- category بسبب قيد check لا يسمح إلا بـ ('real_estate', 'project',
-- 'business')، فتتحول كل معدة إلى نشاط تجاري بشكل دائم بعد أول حفظ. يوسّع
-- هذا الملف القيد ليشمل 'equipment' كقيمة مستقلة، بالإضافة لعمودي "تجميد"
-- و"تثبيت في الرئيسية" اللذين كانا يُطبَّقان محليًا فقط دون أي عمود يحفظهما.

alter table if exists public.project_assets
  drop constraint if exists project_assets_category_check;

alter table if exists public.project_assets
  add constraint project_assets_category_check
  check (category in ('real_estate', 'project', 'business', 'equipment'));

alter table if exists public.project_assets
  add column if not exists is_frozen boolean not null default false,
  add column if not exists is_pinned boolean not null default false;


-- ===================================================================
-- 202608261700_add_sublease_coords_and_unit_contracts.sql
-- ===================================================================
-- Real-estate rebuild: adds a sublease flag + map coordinates to
-- project_assets. property_unit_contracts / property_unit_payments already
-- exist (see 202608261430_create_property_unit_contracts.sql) — this file
-- only extends project_assets with the two new fields the rebuild needs
-- for the list-card "باطن" badge and the static-map header.

alter table if exists public.project_assets
  add column if not exists is_sublease boolean not null default false,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;


-- ===================================================================
-- 202608262000_add_group_key_to_unit_contracts.sql
-- ===================================================================
-- Supports "عقد متعدد الوحدات" (multi-unit contract): one tenant leasing
-- several units under a single agreement, with rent distributed equally.
-- Implemented as one property_unit_contracts row per unit (so each unit
-- keeps its own payment history), all sharing the same group_key so the UI
-- can render them as one consolidated contract.

alter table if exists public.property_unit_contracts
  add column if not exists group_key text;

create index if not exists property_unit_contracts_group_key_idx
  on public.property_unit_contracts (group_key)
  where group_key is not null;


-- ===================================================================
-- 202608262200_add_tenant_phone_to_unit_contracts.sql
-- ===================================================================
-- Adds a real tenant phone number so the unit-details screen can offer
-- functional call/WhatsApp actions (matching the reference screens) instead
-- of decorative icons with no data behind them.

alter table if exists public.property_unit_contracts
  add column if not exists tenant_phone text;




-- ===================================================================
-- 202608262300_add_logs_json_to_project_assets.sql
-- ===================================================================
-- Persists the asset's activity log (e.g. "تمت إضافة وحدة ...", "تم إرسال
-- طلب تفويض ...") so it survives a reload instead of vanishing the moment
-- the asset is re-fetched from Supabase. Stored as a JSON-encoded list of
-- strings, mirroring the existing units_json/employees_json pattern.

alter table if exists public.project_assets
  add column if not exists logs_json text;


-- ===================================================================
-- 202608262400_create_property_unit_transactions.sql
-- ===================================================================
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
