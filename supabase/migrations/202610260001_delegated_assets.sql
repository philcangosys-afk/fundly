-- ============================================================
-- fundly — إدارة العقار/المركبة/النشاط المفوَّض
-- ============================================================
-- شغّله بعد 202610220001. آمن لإعادة التشغيل.
--
-- 1) المفوَّض (بعد القبول وأثناء المدة وغير موقوف) يرى العقار أو المركبة
--    أو النشاط المفوَّض به في قائمته — وعقوده ودفعاته وسجلاته.
-- 2) يضيف/يعدّل/يحذف حسب صلاحياته فقط:
--    عرض البيانات ← قراءة. إضافة السجلات ← إضافة وتسجيل دفعات.
--    تعديل السجلات ← تعديل. حذف السجلات ← حذف السجلات (لا حذف العقار نفسه).
-- 3) كل ما يُكتب يبقى باسم المالك (user_id = مالك العقار) فيراه عنده.
-- 4) كل عملية للمفوَّض يصل بها إشعار للمالك: «فلان أضاف عقدًا…».
-- ============================================================

-- ------------------------------------------------------------
-- ما فُوِّضتُ به الآن: عقار كامل (unit_ref فارغ) أو وحدة بعينها.
-- ------------------------------------------------------------
create or replace function public.fundly_delegated_access()
returns table (
  delegation_id uuid,
  owner_id uuid,
  asset_id uuid,
  unit_ref text,
  permissions text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me text := public.fundly_my_fnd();
begin
  if me is null then
    return;
  end if;
  return query
  with d as (
    select x.*
    from public.delegations x
    where me = any(x.shared_ids)
      and '@accept:accepted' = any(x.permissions)
      and not x.is_paused
      and (x.start_date is null or x.start_date <= current_date)
      and (x.end_date is null or x.end_date >= current_date)
      and trim(split_part(x.scope, ' — ', 1))
          in ('كل الأقسام', 'العقارات والأنشطة والمركبات')
  ),
  t as (
    select d.id as did, d.user_id as uid, d.permissions as perms,
           split_part(substr(p, 9), '|', 2) as kind,
           split_part(substr(p, 9), '|', 3) as ref
    from d, unnest(d.permissions) as p
    where p like '@target:%'
      and split_part(substr(p, 9), '|', 2) in ('asset', 'unit')
  )
  -- عناصر بعينها: عقار/مركبة/نشاط كامل، أو وحدة داخل عقار.
  select t.did, t.uid, a.id,
         case when t.kind = 'unit'
              then nullif(split_part(t.ref, '#', 2), '')
              else null end,
         t.perms
  from t
  join public.project_assets a
    on a.id::text = split_part(t.ref, '#', 1) and a.user_id = t.uid
  where split_part(t.ref, '#', 1) ~ '^[0-9a-f-]{36}$'
  union all
  -- القسم كاملًا أو فئة منه (بلا عناصر محددة).
  select d.id, d.user_id, a.id, null::text, d.permissions
  from d
  join public.project_assets a on a.user_id = d.user_id
  where a.status <> 'محذوف'
    and not exists (
      select 1 from unnest(d.permissions) as p
      where p like '@target:%'
    )
    and (
      trim(split_part(d.scope, ' — ', 1)) = 'كل الأقسام'
      or trim(split_part(d.scope, ' — ', 2)) = ''
      or a.category = any(array(
        select case trim(s)
          when 'العقارات' then 'real_estate'
          when 'الأنشطة التجارية' then 'business'
          when 'المركبات ووسائل النقل' then 'equipment'
          else trim(s) end
        from unnest(string_to_array(split_part(d.scope, ' — ', 2), '،')) as s
      ))
    );
end $$;

revoke all on function public.fundly_delegated_access() from public, anon;
grant execute on function public.fundly_delegated_access() to authenticated;

-- هل لي على هذا الأصل إحدى هذه الصلاحيات (عبر تفويض ساري)؟
create or replace function public.fundly_delegate_can(
  p_asset uuid,
  p_perms text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_asset is not null and exists (
    select 1
    from public.fundly_delegated_access() a
    where a.asset_id = p_asset
      and a.permissions && p_perms
  )
$$;

revoke all on function public.fundly_delegate_can(uuid, text[]) from public, anon;
grant execute on function public.fundly_delegate_can(uuid, text[]) to authenticated;

-- أصل العقد (للدفعات التي لا تحمل معرّف الأصل).
create or replace function public.fundly_contract_asset(p_contract uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select asset_id from public.property_unit_contracts where id = p_contract
$$;

revoke all on function public.fundly_contract_asset(uuid) from public, anon;
grant execute on function public.fundly_contract_asset(uuid) to authenticated;

-- قائمة المفوَّض: الأصل ومالكه وصلاحياته (للتطبيق).
create or replace function public.fundly_my_delegated_assets()
returns table (
  asset_id uuid,
  owner_id uuid,
  owner_name text,
  owner_fnd text,
  delegation_id uuid,
  permissions text[],
  unit_ref text
)
language sql
stable
security definer
set search_path = public
as $$
  select a.asset_id, a.owner_id,
         coalesce(p.display_name, ''), coalesce(p.fnd_id, ''),
         a.delegation_id, a.permissions, a.unit_ref
  from public.fundly_delegated_access() a
  left join public.profiles p on p.id = a.owner_id
$$;

revoke all on function public.fundly_my_delegated_assets() from public, anon;
grant execute on function public.fundly_my_delegated_assets() to authenticated;

-- ------------------------------------------------------------
-- الصلاحيات (تُضاف إلى صلاحيات المالك ولا تغيّرها)
-- ------------------------------------------------------------
drop policy if exists "Delegate reads asset" on public.project_assets;
create policy "Delegate reads asset"
  on public.project_assets for select to authenticated
  using (public.fundly_delegate_can(id, array['عرض البيانات']));

drop policy if exists "Delegate updates asset" on public.project_assets;
create policy "Delegate updates asset"
  on public.project_assets for update to authenticated
  using (public.fundly_delegate_can(id, array['إضافة السجلات', 'تعديل السجلات']))
  with check (public.fundly_delegate_can(id, array['إضافة السجلات', 'تعديل السجلات']));

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'project_asset_entries',
    'property_unit_contracts',
    'property_unit_transactions'
  ] loop
    execute format('drop policy if exists "Delegate reads rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate reads rows" on public.%I for select to authenticated '
      'using (public.fundly_delegate_can(asset_id, array[''عرض البيانات'']))', tbl);
    execute format('drop policy if exists "Delegate adds rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate adds rows" on public.%I for insert to authenticated '
      'with check (public.fundly_delegate_can(asset_id, array[''إضافة السجلات'']))', tbl);
    execute format('drop policy if exists "Delegate edits rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate edits rows" on public.%I for update to authenticated '
      'using (public.fundly_delegate_can(asset_id, array[''إضافة السجلات'', ''تعديل السجلات'', ''تنفيذ المدفوعات والتحويلات'']))'
      ' with check (public.fundly_delegate_can(asset_id, array[''إضافة السجلات'', ''تعديل السجلات'', ''تنفيذ المدفوعات والتحويلات'']))', tbl);
    execute format('drop policy if exists "Delegate deletes rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate deletes rows" on public.%I for delete to authenticated '
      'using (public.fundly_delegate_can(asset_id, array[''حذف السجلات'']))', tbl);
  end loop;
end $$;

drop policy if exists "Delegate reads rows" on public.property_unit_payments;
create policy "Delegate reads rows"
  on public.property_unit_payments for select to authenticated
  using (public.fundly_delegate_can(
    public.fundly_contract_asset(contract_id), array['عرض البيانات']));
drop policy if exists "Delegate adds rows" on public.property_unit_payments;
create policy "Delegate adds rows"
  on public.property_unit_payments for insert to authenticated
  with check (public.fundly_delegate_can(
    public.fundly_contract_asset(contract_id), array['إضافة السجلات']));
drop policy if exists "Delegate edits rows" on public.property_unit_payments;
create policy "Delegate edits rows"
  on public.property_unit_payments for update to authenticated
  using (public.fundly_delegate_can(
    public.fundly_contract_asset(contract_id),
    array['إضافة السجلات', 'تعديل السجلات', 'تنفيذ المدفوعات والتحويلات']))
  with check (public.fundly_delegate_can(
    public.fundly_contract_asset(contract_id),
    array['إضافة السجلات', 'تعديل السجلات', 'تنفيذ المدفوعات والتحويلات']));
drop policy if exists "Delegate deletes rows" on public.property_unit_payments;
create policy "Delegate deletes rows"
  on public.property_unit_payments for delete to authenticated
  using (public.fundly_delegate_can(
    public.fundly_contract_asset(contract_id), array['حذف السجلات']));

-- ------------------------------------------------------------
-- ما يكتبه المفوَّض يبقى باسم المالك
-- ------------------------------------------------------------
create or replace function public.fundly_keep_asset_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_table_name = 'project_assets' then
    if tg_op = 'UPDATE' then
      new.user_id := old.user_id;
    end if;
    return new;
  end if;
  if tg_table_name = 'property_unit_payments' then
    select c.user_id into owner
    from public.property_unit_contracts c where c.id = new.contract_id;
  else
    select a.user_id into owner
    from public.project_assets a where a.id = new.asset_id;
  end if;
  if owner is not null then
    new.user_id := owner;
  end if;
  return new;
end $$;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'project_assets',
    'project_asset_entries',
    'property_unit_contracts',
    'property_unit_payments',
    'property_unit_transactions'
  ] loop
    execute format('drop trigger if exists fundly_keep_asset_owner on public.%I', tbl);
    execute format(
      'create trigger fundly_keep_asset_owner before insert or update on public.%I '
      'for each row execute function public.fundly_keep_asset_owner()', tbl);
  end loop;
end $$;

-- ------------------------------------------------------------
-- إشعار المالك بكل ما يفعله المفوَّض
-- ------------------------------------------------------------
create or replace function public.fundly_delegate_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  r jsonb;
  o jsonb;
  owner uuid;
  asset uuid;
  asset_title text := '';
  asset_cat text := '';
  what text := '';
  item text := '';
  amount numeric := 0;
  actor_name text;
  actor_fnd text;
  msg jsonb;
  kind_label text;
begin
  if actor is null then
    return null;
  end if;
  if tg_op = 'DELETE' then
    r := to_jsonb(old);
  else
    r := to_jsonb(new);
  end if;
  if tg_op = 'UPDATE' then
    o := to_jsonb(old);
  end if;

  owner := (r ->> 'user_id')::uuid;
  if owner is null or owner = actor then
    return null;
  end if;

  if tg_table_name = 'project_assets' then
    asset := (r ->> 'id')::uuid;
    what := 'عدّل البيانات';
  elsif tg_table_name = 'property_unit_payments' then
    select c.asset_id, coalesce(c.unit_name, '')
      into asset, item
    from public.property_unit_contracts c
    where c.id = (r ->> 'contract_id')::uuid;
    if tg_op = 'INSERT' then
      what := 'أضاف دفعة';
      amount := coalesce((r ->> 'amount_due')::numeric, 0);
    elsif tg_op = 'DELETE' then
      what := 'حذف دفعة';
      amount := coalesce((r ->> 'amount_due')::numeric, 0);
    elsif coalesce((r ->> 'amount_paid')::numeric, 0)
          > coalesce((o ->> 'amount_paid')::numeric, 0) then
      what := 'سجّل تحصيل دفعة';
      amount := coalesce((r ->> 'amount_paid')::numeric, 0)
              - coalesce((o ->> 'amount_paid')::numeric, 0);
    else
      what := 'عدّل دفعة';
      amount := coalesce((r ->> 'amount_due')::numeric, 0);
    end if;
  else
    asset := (r ->> 'asset_id')::uuid;
    if tg_table_name = 'property_unit_contracts' then
      item := trim(concat_ws(' — ',
        nullif(r ->> 'unit_name', ''), nullif(r ->> 'tenant_name', '')));
      if tg_op = 'INSERT' then
        what := 'أضاف عقدًا';
      elsif tg_op = 'DELETE' then
        what := 'حذف عقدًا';
      elsif coalesce(r ->> 'status', '') = 'cancelled'
            and coalesce(o ->> 'status', '') <> 'cancelled' then
        what := 'ألغى عقدًا';
      else
        what := 'عدّل عقدًا';
      end if;
      amount := coalesce((r ->> 'annual_rent')::numeric, 0);
    elsif tg_table_name = 'property_unit_transactions' then
      kind_label := case r ->> 'kind' when 'income' then 'دخلًا' else 'مصروفًا' end;
      what := case tg_op
        when 'INSERT' then 'أضاف ' || kind_label
        when 'DELETE' then 'حذف ' || kind_label
        else 'عدّل ' || kind_label end;
      item := coalesce(r ->> 'category', '');
      amount := coalesce((r ->> 'amount')::numeric, 0);
    else
      kind_label := case r ->> 'kind'
        when 'maintenance' then 'صيانة'
        when 'document' then 'مستندًا'
        when 'contract' then 'عقدًا'
        when 'rental' then 'إيجارًا'
        when 'expense' then 'مصروفًا'
        when 'revenue' then 'إيرادًا'
        else 'سجلًا' end;
      what := case tg_op
        when 'INSERT' then 'أضاف ' || kind_label
        when 'DELETE' then 'حذف ' || kind_label
        else 'عدّل ' || kind_label end;
      item := coalesce(
        nullif(r -> 'data' ->> 'الوصف', ''),
        nullif(r -> 'data' ->> 'اسم المستند', ''),
        nullif(r -> 'data' ->> 'العنوان', ''),
        '');
      amount := coalesce(
        nullif(regexp_replace(coalesce(r -> 'data' ->> 'المبلغ', ''), '[^0-9.]', '', 'g'), '')::numeric,
        0);
    end if;
  end if;

  if asset is null then
    return null;
  end if;
  select coalesce(title, ''), coalesce(category, '')
    into asset_title, asset_cat
  from public.project_assets where id = asset;

  msg := jsonb_build_object(
    'kind', 'delegate',
    'what', what,
    'name', item,
    'amount', amount::text,
    'currency', ''
  );

  -- نفس الإشعار خلال دقيقتين لا يتكرر (الحفظ المتتابع للبند نفسه).
  if exists (
    select 1 from public.fundly_inbox i
    where i.recipient_id = owner
      and i.sender_id = actor
      and i.record_id = asset
      and i.note = msg::text
      and i.created_at > now() - interval '2 minutes'
  ) then
    return null;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  insert into public.fundly_inbox (
    recipient_id, sender_id, sender_name, sender_fnd,
    source, record_id, entry_type, title, action, note
  ) values (
    owner, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
    'project_assets', asset,
    case asset_cat
      when 'real_estate' then 'العقارات'
      when 'business' then 'الأنشطة التجارية'
      when 'equipment' then 'المركبات ووسائل النقل'
      else asset_cat end,
    asset_title, 'activity', msg::text
  );
  return null;
end $$;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'project_assets',
    'project_asset_entries',
    'property_unit_contracts',
    'property_unit_payments',
    'property_unit_transactions'
  ] loop
    execute format('drop trigger if exists fundly_delegate_activity on public.%I', tbl);
    execute format(
      'create trigger fundly_delegate_activity after insert or update or delete on public.%I '
      'for each row execute function public.fundly_delegate_activity()', tbl);
  end loop;
end $$;
