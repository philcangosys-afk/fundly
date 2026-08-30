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
