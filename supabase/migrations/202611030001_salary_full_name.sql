-- ============================================================
-- fundly — الاسم الثلاثي عند اعتماد سند الراتب
-- ============================================================
-- شغّله بعد 202611020001. آمن لإعادة التشغيل.
--
-- الموظف يوافق على سند الراتب ويوقّع، ثم يكتب اسمه الثلاثي (الأول
-- والثاني والأخير) — بدونه لا يكتمل الاعتماد. الاسم يُكتب في السند ويظهر
-- لصاحب العمل.
-- ============================================================

drop function if exists public.fundly_salary_respond(uuid, boolean, text, text);

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
  full_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
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
  -- الراتب: الاسم الثلاثي على الأقل.
  if p_accept and r.kind = 'راتب'
     and coalesce(array_length(
       array_remove(string_to_array(full_name, ' '), ''), 1), 0) < 3 then
    return 'no_name';
  end if;

  update public.fundly_salary_receipts set
    status = case when p_accept then 'معتمد' else 'مرفوض' end,
    signature = case when p_accept then p_signature else '' end,
    signed_at = now(),
    reject_reason = case when p_accept then '' else coalesce(p_reason, '') end,
    employee_name = case
      when p_accept and full_name <> '' then full_name
      when coalesce(me_name, '') <> '' then me_name
      else employee_name end
  where id = p_id;

  insert into public.fundly_inbox (
    recipient_id, sender_id, sender_name, sender_fnd,
    source, record_id, entry_type, title, action
  ) values (
    r.user_id, actor,
    case when p_accept and full_name <> '' then full_name
      else coalesce(me_name, '') end,
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
