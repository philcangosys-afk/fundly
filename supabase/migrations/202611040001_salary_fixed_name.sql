-- ============================================================
-- fundly — اسم الموظف في سند الراتب يكتبه المرسل ويبقى ثابتًا
-- ============================================================
-- شغّله بعد 202611030001. آمن لإعادة التشغيل.
--
-- المرسل يكتب اسم الموظف (اسمين أو أكثر) عند إصدار السند، في التوقيع على
-- جواله وفي الإرسال للاعتماد. الموظف يرى الاسم ولا يعدّله: الاعتماد لم
-- يعد يطلب الاسم الثلاثي ولا يغيّر الاسم المكتوب في السند.
-- (المعامل p_name باقٍ لتوافق النسخ القديمة من التطبيق، ولا يُستعمل.)
-- ============================================================

create or replace function public.fundly_salary_respond(
  p_id uuid,
  p_accept boolean,
  p_signature text default '',
  p_reason text default '',
  p_name text default ''
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  me_fnd text;
  me_name text;
  r public.fundly_salary_receipts;
begin
  if actor is null then
    return 'not_signed_in';
  end if;
  select fnd_id, display_name into me_fnd, me_name
  from public.profiles where id = actor;
  select * into r from public.fundly_salary_receipts where id = p_id for update;
  if not found then
    return 'not_found';
  end if;
  if r.employee_fnd is distinct from me_fnd then
    return 'not_yours';
  end if;
  if r.status <> 'بانتظار الاعتماد' then
    return 'answered';
  end if;
  if p_accept and coalesce(btrim(p_signature), '') = '' then
    return 'no_signature';
  end if;

  -- الاسم كما كتبه المرسل لا يتغيّر.
  update public.fundly_salary_receipts set
    status = case when p_accept then 'معتمد' else 'مرفوض' end,
    signature = case when p_accept then p_signature else '' end,
    signed_at = now(),
    reject_reason = case when p_accept then '' else coalesce(p_reason, '') end
  where id = p_id;

  insert into public.fundly_inbox (
    recipient_id, sender_id, sender_name, sender_fnd,
    source, record_id, entry_type, title, action
  ) values (
    r.user_id, actor,
    coalesce(nullif(btrim(r.employee_name), ''), me_name, ''),
    coalesce(me_fnd, ''),
    'salary_receipts', r.id,
    case when r.kind = 'راتب' then 'سند قبض راتب' else 'سند قبض' end,
    public.fundly_salary_title(r)
      || case when not p_accept and coalesce(btrim(p_reason), '') <> ''
        then ' — ' || btrim(p_reason) else '' end,
    case when p_accept then 'accepted' else 'rejected' end
  );
  return 'ok';
end $$;

grant execute on function public.fundly_salary_respond(uuid, boolean, text, text, text)
  to authenticated;
