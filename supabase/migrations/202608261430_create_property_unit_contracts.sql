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
