-- ============================================================
-- fundly — إشعار كل الأعضاء عند إضافة مصروف أو رصيد
-- ============================================================
-- شغّله بعد 202610180001. آمن لإعادة التشغيل.
--
-- في الرحلة والمشاركة المشتركة: حين يضيف أي عضو مصروفًا أو رصيدًا
-- (ميزانية إضافية) ويحفظ، يصل لبقية الأعضاء وللمالك إشعار
-- «فلان أضاف مصروفًا ...». لا يصل لمن أضافه ولا لمن حذف الالتزام من عنده.
--
-- action في fundly_inbox: activity، وتفاصيله في عمود note (JSON):
-- kind (expense / contribution)، name، amount، currency، status.
-- ============================================================

alter table public.fundly_inbox
  add column if not exists note text not null default '';

create or replace function public.fundly_shared_activity_notices()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  removed_list jsonb;
  list_key text;
  kind text;
  old_rows jsonb;
  new_rows jsonb;
  row_item jsonb;
  msg jsonb;
  rid uuid;
begin
  if actor is null then
    return new;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  removed_list := public.fundly_try_jsonb(new.details ->> 'محذوف عند');
  if removed_list is null or jsonb_typeof(removed_list) <> 'array' then
    removed_list := '[]'::jsonb;
  end if;

  foreach list_key in array array['سجل المصروفات المشتركة', 'سجل المساهمات'] loop
    kind := case list_key when 'سجل المساهمات' then 'contribution' else 'expense' end;

    old_rows := public.fundly_try_jsonb(old.details ->> list_key);
    if old_rows is null or jsonb_typeof(old_rows) <> 'array' then
      old_rows := '[]'::jsonb;
    end if;
    new_rows := public.fundly_try_jsonb(new.details ->> list_key);
    if new_rows is null or jsonb_typeof(new_rows) <> 'array' then
      continue;
    end if;

    for row_item in select value from jsonb_array_elements(new_rows) loop
      -- الجديد فقط: معرّف لم يكن في النسخة السابقة.
      if coalesce(row_item ->> 'id', '') = '' then
        continue;
      end if;
      if exists (
        select 1 from jsonb_array_elements(old_rows) o
        where o ->> 'id' = row_item ->> 'id'
      ) then
        continue;
      end if;

      msg := jsonb_build_object(
        'kind', kind,
        'name', coalesce(
          case kind when 'contribution' then row_item ->> 'member'
               else row_item ->> 'description' end, ''),
        'amount', coalesce(row_item ->> 'amount', ''),
        'currency', coalesce(new.details ->> 'العملة', ''),
        'status', coalesce(row_item ->> 'status', '')
      );

      for rid in
        select p.id
        from public.profiles p
        where (p.id = new.user_id
               or p.fnd_id = any(coalesce(new.shared_ids, '{}'::text[])))
          and p.id <> actor
          and not (removed_list ? coalesce(p.fnd_id, ''))
      loop
        insert into public.fundly_inbox (
          recipient_id, sender_id, sender_name, sender_fnd,
          source, record_id, entry_type, title, action, note
        ) values (
          rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
          tg_table_name, new.id, coalesce(new.entry_type, ''),
          coalesce(new.title, ''), 'activity', msg::text
        );
      end loop;
    end loop;
  end loop;

  return new;
end $$;

drop trigger if exists fundly_shared_activity_notices on public.shared_entries;
create trigger fundly_shared_activity_notices
  after update on public.shared_entries
  for each row execute function public.fundly_shared_activity_notices();
