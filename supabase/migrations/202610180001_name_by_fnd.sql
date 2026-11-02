-- اسم صاحب الرقم التعريفي: عند كتابة الرقم في دعوة أو إسناد يظهر الاسم
-- المرتبط به قبل الإرسال، ليتأكد المستخدم أنه الشخص الصحيح.
-- يعيد الاسم الظاهر فقط (لا هاتف ولا بريد)، ولمن سجّل الدخول فقط.

create or replace function public.fundly_name_by_fnd(p_fnd text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(p.display_name), '')
  from public.profiles p
  where p_fnd ~ '^FND-[A-Z2-9]{4}-[A-Z2-9]{4}$'
    and p.fnd_id = p_fnd
  limit 1
$$;

revoke all on function public.fundly_name_by_fnd(text) from public, anon;
grant execute on function public.fundly_name_by_fnd(text) to authenticated;
