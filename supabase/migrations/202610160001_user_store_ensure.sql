-- ============================================================
-- fundly — التأكد من جدول المزامنة السحابية (fundly_user_store)
-- ============================================================
-- آمن لإعادة التشغيل، ولا يمسّ أي جدول أو بيانات أخرى.
-- يُنشئ الجدول إن لم يكن موجودًا، ويعطي كل حساب صلاحية بياناته فقط.
-- ============================================================

create table if not exists public.fundly_user_store (
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  key text not null,
  value text not null default '',
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

alter table public.fundly_user_store enable row level security;

drop policy if exists "Owner full access" on public.fundly_user_store;
create policy "Owner full access" on public.fundly_user_store
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke all on public.fundly_user_store from anon;
grant select, insert, update, delete on public.fundly_user_store to authenticated;
