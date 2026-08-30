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
