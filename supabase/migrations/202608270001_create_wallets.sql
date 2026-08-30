-- ============================================================
-- المحافظ وحركاتها المالية
-- ============================================================
-- كانت شاشة "المحافظ" واجهة ثابتة بالكامل: الرصيد الكلي وعدد البطاقات
-- وعدد الدفعات ونسبة الالتزام والاشتراكات كلها أرقام مكتوبة في الكود ولا
-- تتغيّر أبدًا، ولا يوجد فيها أي زر أو أي ارتباط بقاعدة بيانات.
-- هذان الجدولان يجعلانها شاشة حقيقية.

create table if not exists public.wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  -- نقدية / حساب بنكي / بطاقة / محفظة إلكترونية
  kind text not null default 'cash'
    check (kind in ('cash', 'bank', 'card', 'digital')),
  issuer text,                     -- اسم البنك أو مزوّد المحفظة
  last4 text,                      -- آخر أربعة أرقام للبطاقة
  opening_balance numeric(14, 2) not null default 0,
  currency text not null default 'درهم',
  color int,                       -- لون البطاقة في الواجهة (ARGB)
  is_archived boolean not null default false,
  is_default boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wallets_user_idx
  on public.wallets (user_id, created_at desc);

-- ============================================================
-- حركات المحفظة
-- ============================================================
-- transfer_group يربط طرفَي التحويل (خصم من محفظة + إيداع في أخرى) بحيث
-- يبقيان متسقين ويُحذفان معًا — وهو جوهر "منطق الربط" بين المحافظ.
create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  kind text not null
    check (kind in ('income', 'expense', 'transfer_in', 'transfer_out')),
  amount numeric(14, 2) not null default 0 check (amount >= 0),
  occurred_on date,
  category text,
  note text,
  transfer_group text,             -- يجمع طرفَي التحويل
  counterparty_wallet_id uuid references public.wallets(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists wallet_transactions_wallet_idx
  on public.wallet_transactions (wallet_id, occurred_on desc);

create index if not exists wallet_transactions_user_idx
  on public.wallet_transactions (user_id, occurred_on desc);

create index if not exists wallet_transactions_group_idx
  on public.wallet_transactions (transfer_group)
  where transfer_group is not null;

alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;

drop policy if exists "Users read own wallets" on public.wallets;
create policy "Users read own wallets"
  on public.wallets for select
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own wallets" on public.wallets;
create policy "Users insert own wallets"
  on public.wallets for insert
  to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own wallets" on public.wallets;
create policy "Users update own wallets"
  on public.wallets for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own wallets" on public.wallets;
create policy "Users delete own wallets"
  on public.wallets for delete
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users read own wallet transactions" on public.wallet_transactions;
create policy "Users read own wallet transactions"
  on public.wallet_transactions for select
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own wallet transactions" on public.wallet_transactions;
create policy "Users insert own wallet transactions"
  on public.wallet_transactions for insert
  to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own wallet transactions" on public.wallet_transactions;
create policy "Users update own wallet transactions"
  on public.wallet_transactions for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own wallet transactions" on public.wallet_transactions;
create policy "Users delete own wallet transactions"
  on public.wallet_transactions for delete
  to authenticated using ((select auth.uid()) = user_id);

grant select, insert, update, delete on table public.wallets to authenticated;
grant select, insert, update, delete on table public.wallet_transactions to authenticated;
