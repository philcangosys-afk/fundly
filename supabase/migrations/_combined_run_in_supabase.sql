-- ============================================================
-- 202608271000_ensure_project_assets_columns.sql (يُشغَّل أولًا)
-- ============================================================
-- ============================================================
-- ضمان بنية جدول project_assets كاملة
-- ============================================================
-- السبب الحقيقي لعدم حفظ "النشاط التجاري" و"المعدة": منتقي التاريخ في
-- شاشتيهما كان يكتب التاريخ بصيغة 27/8/2026، فيُرسَل إلى الخادم
-- "27-8-2026" ويرفضه كتاريخ (الشهر 27) فيُرفض الصف كاملًا — بينما
-- العقار يُحفظ لأن تاريخه يُرسل فارغًا. أُصلح ذلك في التطبيق.
--
-- ويعالج هذا الملف الجانب الآخر: جدول project_assets غير منشأ في أي ملف
-- ترحيل داخل المشروع (أُنشئ يدويًا في Supabase)، فأي قاعدة بيانات جديدة
-- لا تملكه أصلًا، وعمودا icon_color و cover_url اللذان يرسلهما التطبيق
-- لا ينشئهما أي ملف. يُنشَأ الجدول هنا إن كان غائبًا، ثم تُضاف كل الأعمدة
-- الناقصة بأمان.

create table if not exists public.project_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table if exists public.project_assets
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists title text not null default '',
  add column if not exists sub_type text not null default '',
  add column if not exists category text not null default 'real_estate',
  add column if not exists status text not null default 'نشط',
  add column if not exists location_or_type text,
  add column if not exists amount_label text,
  add column if not exists followup_note text,
  add column if not exists owner text,
  add column if not exists tenant text,
  add column if not exists rent_value text,
  add column if not exists end_date date,
  add column if not exists annual_yield text,
  add column if not exists occupancy_rate double precision not null default 0,
  add column if not exists contract_progress double precision not null default 0,
  add column if not exists payment_progress double precision not null default 0,
  add column if not exists documents_progress double precision not null default 0,
  add column if not exists needs_attention boolean not null default false,
  -- العمودان الغائبان اللذان كانا يُفشلان كل عملية حفظ:
  add column if not exists icon_color bigint,
  add column if not exists cover_url text,
  add column if not exists description text not null default '',
  add column if not exists annexes jsonb not null default '{}'::jsonb,
  add column if not exists map_link text,
  add column if not exists quick_add_enabled boolean not null default false,
  add column if not exists units_json text default '[]',
  add column if not exists employees_json text default '[]',
  add column if not exists serial_number text,
  add column if not exists is_frozen boolean not null default false,
  add column if not exists is_pinned boolean not null default false,
  add column if not exists is_sublease boolean not null default false,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists logs_json text default '[]';

-- قيد التصنيف: القيم الأربع التي يرسلها التطبيق فعلًا
-- (real_estate = عقار، business = نشاط تجاري، equipment = معدة،
--  project = أخرى).
alter table if exists public.project_assets
  drop constraint if exists project_assets_category_check;

-- not valid: إضافة القيد بلا التحقق من الصفوف القديمة فورًا. بدونها كان
-- صفّ واحد قديم بتصنيف خارج القائمة يُفشل السكربت كله ويتراجع عنه.
alter table if exists public.project_assets
  add constraint project_assets_category_check
  check (category in ('real_estate', 'project', 'business', 'equipment'))
  not valid;

grant select, insert, update, delete on table public.project_assets to authenticated;

create index if not exists project_assets_user_idx
  on public.project_assets (user_id, created_at desc);

alter table if exists public.project_assets enable row level security;

drop policy if exists "Users read own project assets" on public.project_assets;
create policy "Users read own project assets"
  on public.project_assets for select
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own project assets" on public.project_assets;
create policy "Users insert own project assets"
  on public.project_assets for insert
  to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own project assets" on public.project_assets;
create policy "Users update own project assets"
  on public.project_assets for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own project assets" on public.project_assets;
create policy "Users delete own project assets"
  on public.project_assets for delete
  to authenticated using ((select auth.uid()) = user_id);

-- ============================================================
-- الأساس: جدول project_asset_entries
-- ============================================================
-- مُشار إليه في سياسات وصلاحيات أدناه ولم يُنشئه أي ملف ترحيل، فيتوقف
-- السكربت كله على قاعدة بيانات جديدة عند أول grant عليه.

create table if not exists public.project_asset_entries (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.project_assets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'contract',
  data jsonb not null default '{}'::jsonb,
  attachment_url text,
  created_at timestamptz not null default now()
);


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
  check (category in ('real_estate', 'project', 'business', 'equipment'))
  not valid;

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


-- ===================================================================
-- 202608270001_create_wallets.sql
-- ===================================================================
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


-- ===================================================================
-- 202608270002_create_delegations_and_documents.sql
-- ===================================================================
-- ============================================================
-- التفويضات + سجلات المستندات والإيصالات
-- ============================================================
-- التفويضات كانت قائمة في الذاكرة فقط مصحوبة بثلاثة سجلات وهمية: كل إضافة
-- أو تعديل أو حذف يضيع بمجرد الخروج من الصفحة، وتعود البيانات الوهمية.
-- وسجلات المستندات كانت محفوظة محليًا فقط (SharedPreferences)، فتضيع عند
-- حذف التطبيق ولا تظهر على جهاز آخر — بخلاف بقية بيانات التطبيق.

create table if not exists public.delegations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delegate_name text not null,
  -- الجهة/الشخص المفوَّض إليه كما هو مسجَّل في إدارة الأفراد (اختياري)
  delegate_ref text,
  -- نطاق التفويض: يطابق وحدات التطبيق الفعلية
  scope text not null default 'الالتزامات المالية',
  -- الصلاحيات الممنوحة، مخزَّنة كمصفوفة نصية
  permissions text[] not null default '{}',
  start_date date,
  end_date date,
  is_paused boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists delegations_user_idx
  on public.delegations (user_id, end_date desc);

create table if not exists public.document_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- نوع القالب: إيصال أمانة / فاتورة / عقد / إنذار ...
  doc_type text not null,
  -- قيم حقول القالب (اسم المدين، المبلغ، ...) كما ملأها المستخدم
  fields jsonb not null default '{}'::jsonb,
  -- الربط بكيان حقيقي في التطبيق: شخص، عقار/نشاط، محفظة، تفويض
  linked_kind text,
  linked_label text,
  linked_id text,
  doc_number text,
  issued_on date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_records_user_idx
  on public.document_records (user_id, created_at desc);

alter table public.delegations enable row level security;
alter table public.document_records enable row level security;

drop policy if exists "Users read own delegations" on public.delegations;
create policy "Users read own delegations"
  on public.delegations for select
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own delegations" on public.delegations;
create policy "Users insert own delegations"
  on public.delegations for insert
  to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own delegations" on public.delegations;
create policy "Users update own delegations"
  on public.delegations for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own delegations" on public.delegations;
create policy "Users delete own delegations"
  on public.delegations for delete
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users read own document records" on public.document_records;
create policy "Users read own document records"
  on public.document_records for select
  to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own document records" on public.document_records;
create policy "Users insert own document records"
  on public.document_records for insert
  to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own document records" on public.document_records;
create policy "Users update own document records"
  on public.document_records for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own document records" on public.document_records;
create policy "Users delete own document records"
  on public.document_records for delete
  to authenticated using ((select auth.uid()) = user_id);

grant select, insert, update, delete on table public.delegations to authenticated;
grant select, insert, update, delete on table public.document_records to authenticated;
