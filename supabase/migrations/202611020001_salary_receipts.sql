-- ============================================================
-- fundly — سندات القبض (الراتب الشهري وسند القبض العام)
-- ============================================================
-- شغّله بعد 202611010001. آمن لإعادة التشغيل.
--
-- • صاحب العمل يسجّل سند قبض لموظف برقمه التعريفي (راتب شهر أو سند
--   عام)، ثم إما يوقّع الموظف على جوال صاحب العمل (معتمد مباشرة)، أو
--   يُرسل له للاعتماد والتوقيع (بانتظار الاعتماد).
-- • الموظف يرى ما أُرسل إليه فقط، ويرد عبر fundly_salary_respond: يوافق
--   ويوقّع، أو يرفض بسبب. يصل الرد لصاحب العمل إشعارًا.
-- ============================================================

create table if not exists public.fundly_salary_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  kind text not null default 'راتب' check (kind in ('راتب', 'عام')),
  employee_fnd text not null default '',
  employee_name text not null default '',
  owner_name text not null default '',
  period text not null default '',          -- راتب: 2026-03
  receipt_date text not null default '',    -- 01/03/2026
  basic numeric not null default 0,
  allowances numeric not null default 0,
  overtime numeric not null default 0,
  loan numeric not null default 0,
  deductions numeric not null default 0,
  total numeric not null default 0,
  paid numeric not null default 0,
  currency text not null default '',
  description text not null default '',
  notes text not null default '',
  sign_mode text not null default 'here' check (sign_mode in ('here', 'remote')),
  status text not null default 'بانتظار الاعتماد'
    check (status in ('بانتظار الاعتماد', 'معتمد', 'مرفوض')),
  signature text not null default '',
  signed_at timestamptz,
  reject_reason text not null default '',
  expense_id text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fundly_salary_receipts_owner_idx
  on public.fundly_salary_receipts (user_id, period desc);
create index if not exists fundly_salary_receipts_employee_idx
  on public.fundly_salary_receipts (employee_fnd, status);

alter table public.fundly_salary_receipts enable row level security;

drop policy if exists "Salary: owner reads" on public.fundly_salary_receipts;
drop policy if exists "Salary: employee reads" on public.fundly_salary_receipts;
drop policy if exists "Salary: owner inserts" on public.fundly_salary_receipts;
drop policy if exists "Salary: owner updates" on public.fundly_salary_receipts;
drop policy if exists "Salary: owner deletes" on public.fundly_salary_receipts;

create policy "Salary: owner reads"
  on public.fundly_salary_receipts for select to authenticated
  using (user_id = (select auth.uid()));
-- الموظف يرى ما أُرسل إلى رقمه التعريفي فقط.
create policy "Salary: employee reads"
  on public.fundly_salary_receipts for select to authenticated
  using (
    employee_fnd <> ''
    and employee_fnd = (
      select p.fnd_id from public.profiles p where p.id = (select auth.uid())
    )
  );
create policy "Salary: owner inserts"
  on public.fundly_salary_receipts for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Salary: owner updates"
  on public.fundly_salary_receipts for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Salary: owner deletes"
  on public.fundly_salary_receipts for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.fundly_salary_receipts
  to authenticated;

-- عنوان السند في الإشعارات: «راتب 2026-03 — 3000 درهم».
create or replace function public.fundly_salary_title(r public.fundly_salary_receipts)
returns text
language sql
immutable
as $$
  select case when r.kind = 'راتب'
    then 'راتب ' || r.period
    else coalesce(nullif(r.description, ''), 'سند قبض') end
    || ' — ' || case when round(r.paid, 2) = trunc(r.paid)
      then trunc(r.paid)::text
      else rtrim(round(r.paid, 2)::text, '0') end
    || case when r.currency = '' then '' else ' ' || r.currency end;
$$;

-- إرسال السند للموظف: طلب اعتماد وتوقيع في صندوقه.
create or replace function public.fundly_salary_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  rid uuid;
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
  end if;
  -- وقّع على جوال صاحب العمل: وقت التوقيع من الخادم.
  if new.status = 'معتمد' and new.signature <> '' and new.signed_at is null then
    new.signed_at := now();
  end if;
  if actor is null or actor <> new.user_id or new.employee_fnd = '' then
    return new;
  end if;
  select id into rid from public.profiles where fnd_id = new.employee_fnd;
  if rid is null or rid = actor then
    return new;
  end if;
  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  if new.status = 'بانتظار الاعتماد' and (
    tg_op = 'INSERT'
    or old.status is distinct from new.status
    or old.employee_fnd is distinct from new.employee_fnd
  ) then
    insert into public.fundly_inbox (
      recipient_id, sender_id, sender_name, sender_fnd,
      source, record_id, entry_type, title
    ) values (
      rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
      'salary_receipts', new.id,
      case when new.kind = 'راتب' then 'سند قبض راتب' else 'سند قبض' end,
      public.fundly_salary_title(new)
    );
  elsif tg_op = 'INSERT' and new.status = 'معتمد' then
    -- وقّع على جوال صاحب العمل: نسخة للاطلاع عند الموظف.
    insert into public.fundly_inbox (
      recipient_id, sender_id, sender_name, sender_fnd,
      source, record_id, entry_type, title, action, note
    ) values (
      rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
      'salary_receipts', new.id,
      case when new.kind = 'راتب' then 'سند قبض راتب' else 'سند قبض' end,
      public.fundly_salary_title(new), 'activity',
      jsonb_build_object(
        'kind', 'salary',
        'what', 'سجّل سند قبض موقّعًا منك على جواله'
      )::text
    );
  end if;
  return new;
end $$;

drop trigger if exists fundly_salary_row on public.fundly_salary_receipts;
create trigger fundly_salary_row
  before insert or update on public.fundly_salary_receipts
  for each row execute function public.fundly_salary_row();

-- رد الموظف: موافقة مع توقيع، أو رفض بسبب.
create or replace function public.fundly_salary_respond(
  p_id uuid,
  p_accept boolean,
  p_signature text default '',
  p_reason text default ''
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

  update public.fundly_salary_receipts set
    status = case when p_accept then 'معتمد' else 'مرفوض' end,
    signature = case when p_accept then p_signature else '' end,
    signed_at = now(),
    reject_reason = case when p_accept then '' else coalesce(p_reason, '') end,
    employee_name = case
      when coalesce(me_name, '') <> '' then me_name else employee_name end
  where id = p_id;

  insert into public.fundly_inbox (
    recipient_id, sender_id, sender_name, sender_fnd,
    source, record_id, entry_type, title, action
  ) values (
    r.user_id, actor, coalesce(me_name, ''), coalesce(me_fnd, ''),
    'salary_receipts', r.id,
    case when r.kind = 'راتب' then 'سند قبض راتب' else 'سند قبض' end,
    public.fundly_salary_title(r)
      || case when not p_accept and coalesce(btrim(p_reason), '') <> ''
        then ' — ' || btrim(p_reason) else '' end,
    case when p_accept then 'accepted' else 'rejected' end
  );
  return 'ok';
end $$;

grant execute on function public.fundly_salary_respond(uuid, boolean, text, text)
  to authenticated;
