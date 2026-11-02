-- ============================================================
-- fundly — الملفات: نسخة سحابية لملفات الجهاز + مشاركة المرفقات
-- ============================================================
-- شغّله بعد 202610130003. آمن لإعادة التشغيل.
--
-- 1) مخزن fundly-files: كل ملف يُحفظ داخل التطبيق (صور الملاحظات،
--    المستندات، إيصالات المصروفات...) يُرفع إليه، ويُنزَّل عند الدخول
--    من جوال آخر.
-- 2) المرفق المذكور في سجل مشترك (عهدة، رحلة...) يراه الطرف الآخر،
--    سواء رفعه المالك أو الشريك.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('fundly-files', 'fundly-files', false)
on conflict (id) do nothing;

-- اسم الملف الأصلي من مفتاحه في المخزن (Base64 آمن للروابط، لأن المخزن
-- لا يقبل الحروف العربية في أسماء الملفات).
create or replace function public.fundly_file_name(p_key text)
returns text
language plpgsql
immutable
as $$
begin
  return convert_from(
    decode(
      rpad(
        translate(p_key, '-_', '+/'),
        ((length(p_key) + 3) / 4) * 4,
        '='
      ),
      'base64'
    ),
    'UTF8'
  );
exception
  when others then
    return '';
end $$;

-- هل يُذكر هذا الاسم في سجل أراه؟ (تعمل بصلاحيات المستخدم نفسه، فلا ترى
-- إلا سجلاته والسجلات المشتركة معه.)
create or replace function public.fundly_name_visible(p_name text)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(length(p_name), 0) > 3 and (
    exists (
      select 1 from public.personal_entries e
      where strpos(e.details::text, p_name) > 0
    )
    or exists (
      select 1 from public.shared_entries e
      where strpos(e.details::text, p_name) > 0
    )
  )
$$;

grant execute on function public.fundly_file_name(text) to authenticated;
grant execute on function public.fundly_name_visible(text) to authenticated;

-- ------------------------------------------------------------
-- مخزن fundly-files
-- ------------------------------------------------------------
drop policy if exists "Fundly files: upload" on storage.objects;
drop policy if exists "Fundly files: read own or shared" on storage.objects;
drop policy if exists "Fundly files: delete own" on storage.objects;

create policy "Fundly files: upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'fundly-files');

create policy "Fundly files: read own or shared"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'fundly-files'
    and (
      owner_id = (select auth.uid())::text
      or public.fundly_name_visible(public.fundly_file_name(objects.name))
    )
  );

create policy "Fundly files: delete own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'fundly-files'
    and owner_id = (select auth.uid())::text
  );

-- ------------------------------------------------------------
-- مرفقات السجلات (الصورة المرفقة، صور الفواتير والإيصالات): يقرؤها كل
-- من يرى السجل، ومنهم الطرف الآخر في العهدة أو الرحلة.
-- ------------------------------------------------------------
drop policy if exists "Shared rows attachments: read" on storage.objects;
create policy "Shared rows attachments: read"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('personal-entry-attachments', 'shared-entry-attachments')
    and (
      exists (
        select 1 from public.personal_entries e
        where e.attachment_url = objects.name
      )
      or exists (
        select 1 from public.shared_entries e
        where e.attachment_url = objects.name
      )
      or public.fundly_name_visible(objects.name)
    )
  );
