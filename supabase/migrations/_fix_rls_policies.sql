-- ============================================================
-- إصلاح سياسات RLS للسماح بالحفظ
-- ============================================================
-- إذا كان التطبيق يفشل في الحفظ رغم نجاح تسجيل الدخول،
-- المشكلة غالباً في سياسات Row Level Security
-- ============================================================

-- ============================================================
-- 1. التحقق من حالة RLS على الجداول الرئيسية
-- ============================================================
select 
  schemaname,
  tablename,
  rowsecurity as "RLS مفعّل؟"
from pg_tables
where schemaname = 'public'
  and tablename in (
    'personal_entries',
    'shared_entries', 
    'project_assets',
    'wallets',
    'delegations'
  )
order by tablename;


-- ============================================================
-- 2. عرض السياسات الحالية
-- ============================================================
select 
  tablename as "الجدول",
  policyname as "اسم السياسة",
  cmd as "العملية",
  qual as "الشرط"
from pg_policies
where schemaname = 'public'
  and tablename in (
    'personal_entries',
    'shared_entries',
    'project_assets', 
    'wallets',
    'delegations'
  )
order by tablename, cmd;


-- ============================================================
-- 3. إنشاء/تحديث سياسات RLS للجداول الرئيسية
-- ============================================================

-- personal_entries
drop policy if exists "Users can view own entries" on public.personal_entries;
drop policy if exists "Users can insert own entries" on public.personal_entries;
drop policy if exists "Users can update own entries" on public.personal_entries;
drop policy if exists "Users can delete own entries" on public.personal_entries;

create policy "Users can view own entries"
  on public.personal_entries for select
  using (auth.uid() = user_id);

create policy "Users can insert own entries"
  on public.personal_entries for insert
  with check (auth.uid() = user_id);

create policy "Users can update own entries"
  on public.personal_entries for update
  using (auth.uid() = user_id);

create policy "Users can delete own entries"
  on public.personal_entries for delete
  using (auth.uid() = user_id);


-- shared_entries
drop policy if exists "Users can view own shared entries" on public.shared_entries;
drop policy if exists "Users can insert own shared entries" on public.shared_entries;
drop policy if exists "Users can update own shared entries" on public.shared_entries;
drop policy if exists "Users can delete own shared entries" on public.shared_entries;

create policy "Users can view own shared entries"
  on public.shared_entries for select
  using (auth.uid() = user_id);

create policy "Users can insert own shared entries"
  on public.shared_entries for insert
  with check (auth.uid() = user_id);

create policy "Users can update own shared entries"
  on public.shared_entries for update
  using (auth.uid() = user_id);

create policy "Users can delete own shared entries"
  on public.shared_entries for delete
  using (auth.uid() = user_id);


-- project_assets
drop policy if exists "Users can view own assets" on public.project_assets;
drop policy if exists "Users can insert own assets" on public.project_assets;
drop policy if exists "Users can update own assets" on public.project_assets;
drop policy if exists "Users can delete own assets" on public.project_assets;

create policy "Users can view own assets"
  on public.project_assets for select
  using (auth.uid() = user_id);

create policy "Users can insert own assets"
  on public.project_assets for insert
  with check (auth.uid() = user_id);

create policy "Users can update own assets"
  on public.project_assets for update
  using (auth.uid() = user_id);

create policy "Users can delete own assets"
  on public.project_assets for delete
  using (auth.uid() = user_id);


-- wallets
drop policy if exists "Users can view own wallets" on public.wallets;
drop policy if exists "Users can insert own wallets" on public.wallets;
drop policy if exists "Users can update own wallets" on public.wallets;
drop policy if exists "Users can delete own wallets" on public.wallets;

create policy "Users can view own wallets"
  on public.wallets for select
  using (auth.uid() = user_id);

create policy "Users can insert own wallets"
  on public.wallets for insert
  with check (auth.uid() = user_id);

create policy "Users can update own wallets"
  on public.wallets for update
  using (auth.uid() = user_id);

create policy "Users can delete own wallets"
  on public.wallets for delete
  using (auth.uid() = user_id);


-- ============================================================
-- 4. تفعيل RLS على كل الجداول
-- ============================================================
alter table public.personal_entries enable row level security;
alter table public.shared_entries enable row level security;
alter table public.project_assets enable row level security;
alter table public.wallets enable row level security;
alter table public.delegations enable row level security;


-- ============================================================
-- 5. التحقق النهائي
-- ============================================================
-- أعد تشغيل الاستعلام 1 و 2 للتأكد من السياسات
