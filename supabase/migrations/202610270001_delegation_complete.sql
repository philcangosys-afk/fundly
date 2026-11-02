-- ============================================================
-- fundly — إكمال التفويض
-- ============================================================
-- شغّله بعد 202610260001_delegated_assets. آمن لإعادة التشغيل.
--
-- 1) عزل الوحدة على الخادم: المفوَّض على وحدة بعينها لا يصل إلا إلى
--    عقودها ودفعاتها وحركاتها، ولا يرى من العقار إلا وحدته، ولا يغيّر
--    في العقار إلا بيانات وحدته.
-- 2) الالتزامات الشخصية والمشتركة: المفوَّض يعدّل السجل أو يغيّر حالته أو
--    ينقله للسلة حسب صلاحياته، ويصل للمالك إشعار بكل ذلك.
-- 3) الأفراد والجهات: تظهر للمفوَّض في «البيانات المفوَّضة» (للاطلاع).
-- ============================================================

-- ------------------------------------------------------------
-- ١. الوحدات
-- ------------------------------------------------------------

-- مفتاح الوحدة كما في التطبيق: __key المثبّت، وإلا النوع|الاسم|الرقم.
create or replace function public.fundly_unit_key(p_unit jsonb)
returns text
language sql
immutable
as $$
  select coalesce(
    nullif(trim(coalesce(p_unit -> 'extras' ->> '__key', '')), ''),
    coalesce(p_unit ->> 'type', '') || '|' ||
    coalesce(p_unit ->> 'name', '') || '|' ||
    coalesce(p_unit ->> 'unitNumber', '')
  )
$$;

-- هل الوحدة هي المفوَّض بها؟ المرجع: رقمها، وإلا اسمها، وإلا ترتيبها.
create or replace function public.fundly_unit_allowed(
  p_ref text,
  p_unit jsonb,
  p_idx int
)
returns boolean
language sql
immutable
as $$
  select case
    when trim(coalesce(p_unit ->> 'unitNumber', '')) <> ''
      then trim(p_unit ->> 'unitNumber') = trim(p_ref)
    when trim(coalesce(p_unit ->> 'name', '')) <> ''
      then trim(p_unit ->> 'name') = trim(p_ref)
    else p_idx::text = trim(p_ref)
  end
$$;

-- وحدات العقار من units_json (نص JSON) بترتيبها ومفاتيحها.
create or replace function public.fundly_units_of(p_asset uuid)
returns table (idx int, unit jsonb, ukey text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  raw text;
  arr jsonb;
begin
  select units_json into raw from public.project_assets where id = p_asset;
  begin
    arr := coalesce(nullif(trim(coalesce(raw, '')), ''), '[]')::jsonb;
  exception when others then
    arr := '[]'::jsonb;
  end;
  if jsonb_typeof(arr) <> 'array' then
    return;
  end if;
  return query
    select (e.ord - 1)::int, e.value, public.fundly_unit_key(e.value)
    from jsonb_array_elements(arr) with ordinality as e(value, ord);
end $$;

revoke all on function public.fundly_units_of(uuid) from public, anon;
grant execute on function public.fundly_units_of(uuid) to authenticated;

-- العقار كاملًا فقط (لا يكفي التفويض على وحدة منه): بياناته العامة
-- وصيانته ومستنداته.
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
      and a.unit_ref is null
      and a.permissions && p_perms
  )
$$;

-- العقار كاملًا، أو الوحدة المفوَّض بها نفسها.
create or replace function public.fundly_delegate_can_unit(
  p_asset uuid,
  p_unit_key text,
  p_unit_name text,
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
      and (
        a.unit_ref is null
        or (
          coalesce(p_unit_key, '') <> ''
          and exists (
            select 1 from public.fundly_units_of(p_asset) u
            where u.ukey = p_unit_key
              and public.fundly_unit_allowed(a.unit_ref, u.unit, u.idx)
          )
        )
        or (
          coalesce(trim(p_unit_name), '') <> ''
          and trim(p_unit_name) = trim(a.unit_ref)
        )
      )
  )
$$;

revoke all on function public.fundly_delegate_can_unit(uuid, text, text, text[]) from public, anon;
grant execute on function public.fundly_delegate_can_unit(uuid, text, text, text[]) to authenticated;

-- دفعة: عبر عقدها ووحدته.
create or replace function public.fundly_delegate_can_contract(
  p_contract uuid,
  p_perms text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.property_unit_contracts c
    where c.id = p_contract
      and public.fundly_delegate_can_unit(c.asset_id, c.unit_key, c.unit_name, p_perms)
  )
$$;

revoke all on function public.fundly_delegate_can_contract(uuid, text[]) from public, anon;
grant execute on function public.fundly_delegate_can_contract(uuid, text[]) to authenticated;

-- العقود والحركات: بالوحدة.
do $$
declare
  tbl text;
  unit_name_expr text;
begin
  foreach tbl in array array['property_unit_contracts', 'property_unit_transactions'] loop
    unit_name_expr := case tbl when 'property_unit_contracts' then 'unit_name' else 'null' end;
    execute format('drop policy if exists "Delegate reads rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate reads rows" on public.%I for select to authenticated '
      'using (public.fundly_delegate_can_unit(asset_id, unit_key, %s, array[''عرض البيانات'']))',
      tbl, unit_name_expr);
    execute format('drop policy if exists "Delegate adds rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate adds rows" on public.%I for insert to authenticated '
      'with check (public.fundly_delegate_can_unit(asset_id, unit_key, %s, array[''إضافة السجلات'']))',
      tbl, unit_name_expr);
    execute format('drop policy if exists "Delegate edits rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate edits rows" on public.%I for update to authenticated '
      'using (public.fundly_delegate_can_unit(asset_id, unit_key, %s, array[''إضافة السجلات'', ''تعديل السجلات'', ''تنفيذ المدفوعات والتحويلات'']))'
      ' with check (public.fundly_delegate_can_unit(asset_id, unit_key, %s, array[''إضافة السجلات'', ''تعديل السجلات'', ''تنفيذ المدفوعات والتحويلات'']))',
      tbl, unit_name_expr, unit_name_expr);
    execute format('drop policy if exists "Delegate deletes rows" on public.%I', tbl);
    execute format(
      'create policy "Delegate deletes rows" on public.%I for delete to authenticated '
      'using (public.fundly_delegate_can_unit(asset_id, unit_key, %s, array[''حذف السجلات'']))',
      tbl, unit_name_expr);
  end loop;
end $$;

-- الدفعات: بعقدها.
drop policy if exists "Delegate reads rows" on public.property_unit_payments;
create policy "Delegate reads rows"
  on public.property_unit_payments for select to authenticated
  using (public.fundly_delegate_can_contract(contract_id, array['عرض البيانات']));
drop policy if exists "Delegate adds rows" on public.property_unit_payments;
create policy "Delegate adds rows"
  on public.property_unit_payments for insert to authenticated
  with check (public.fundly_delegate_can_contract(contract_id, array['إضافة السجلات']));
drop policy if exists "Delegate edits rows" on public.property_unit_payments;
create policy "Delegate edits rows"
  on public.property_unit_payments for update to authenticated
  using (public.fundly_delegate_can_contract(contract_id,
    array['إضافة السجلات', 'تعديل السجلات', 'تنفيذ المدفوعات والتحويلات']))
  with check (public.fundly_delegate_can_contract(contract_id,
    array['إضافة السجلات', 'تعديل السجلات', 'تنفيذ المدفوعات والتحويلات']));
drop policy if exists "Delegate deletes rows" on public.property_unit_payments;
create policy "Delegate deletes rows"
  on public.property_unit_payments for delete to authenticated
  using (public.fundly_delegate_can_contract(contract_id, array['حذف السجلات']));

-- ما يراه المفوَّض من العقار: كاملًا، أو بوحداته المفوَّضة وحدها.
create or replace function public.fundly_delegated_asset_rows()
returns setof public.project_assets
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rec record;
  row_ public.project_assets;
  arr jsonb;
  kept jsonb;
begin
  for rec in
    select a.asset_id,
           bool_or(a.unit_ref is null) as whole,
           array_agg(a.unit_ref) filter (where a.unit_ref is not null) as refs
    from public.fundly_delegated_access() a
    group by a.asset_id
  loop
    select * into row_ from public.project_assets where id = rec.asset_id;
    if not found or row_.status = 'محذوف' then
      continue;
    end if;
    if not rec.whole then
      begin
        arr := coalesce(nullif(trim(coalesce(row_.units_json, '')), ''), '[]')::jsonb;
      exception when others then
        arr := '[]'::jsonb;
      end;
      if jsonb_typeof(arr) <> 'array' then
        arr := '[]'::jsonb;
      end if;
      select coalesce(jsonb_agg(e.value order by e.ord), '[]'::jsonb)
        into kept
      from jsonb_array_elements(arr) with ordinality as e(value, ord)
      where exists (
        select 1 from unnest(rec.refs) as r
        where public.fundly_unit_allowed(r, e.value, (e.ord - 1)::int)
      );
      row_.units_json := kept::text;
    end if;
    return next row_;
  end loop;
end $$;

revoke all on function public.fundly_delegated_asset_rows() from public, anon;
grant execute on function public.fundly_delegated_asset_rows() to authenticated;

-- حفظ بيانات الوحدات من المفوَّض على وحدة: تُستبدل وحدته فقط، وبقية
-- الوحدات وبيانات العقار كما هي. رقم الوحدة واسمها ونوعها لا تتغير.
create or replace function public.fundly_save_delegated_units(
  p_asset uuid,
  p_units text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  whole boolean;
  refs text[];
  old_arr jsonb;
  new_arr jsonb;
  result jsonb := '[]'::jsonb;
  e record;
  incoming jsonb;
  raw text;
begin
  select bool_or(a.unit_ref is null),
         array_agg(a.unit_ref) filter (where a.unit_ref is not null)
    into whole, refs
  from public.fundly_delegated_access() a
  where a.asset_id = p_asset
    and a.permissions && array['إضافة السجلات', 'تعديل السجلات'];

  if whole is null then
    raise exception 'لا صلاحية لتعديل هذا العقار';
  end if;

  begin
    new_arr := coalesce(nullif(trim(coalesce(p_units, '')), ''), '[]')::jsonb;
  exception when others then
    raise exception 'بيانات الوحدات غير صالحة';
  end;
  if jsonb_typeof(new_arr) <> 'array' then
    raise exception 'بيانات الوحدات غير صالحة';
  end if;

  if whole then
    update public.project_assets set units_json = new_arr::text where id = p_asset;
    return;
  end if;

  select units_json into raw from public.project_assets where id = p_asset;
  begin
    old_arr := coalesce(nullif(trim(coalesce(raw, '')), ''), '[]')::jsonb;
  exception when others then
    old_arr := '[]'::jsonb;
  end;
  if jsonb_typeof(old_arr) <> 'array' then
    old_arr := '[]'::jsonb;
  end if;

  for e in
    select value, (ord - 1)::int as idx
    from jsonb_array_elements(old_arr) with ordinality as x(value, ord)
    order by ord
  loop
    incoming := null;
    if exists (
      select 1 from unnest(refs) as r
      where public.fundly_unit_allowed(r, e.value, e.idx)
    ) then
      select n.value into incoming
      from jsonb_array_elements(new_arr) as n(value)
      where public.fundly_unit_key(n.value) = public.fundly_unit_key(e.value)
      limit 1;
    end if;
    if incoming is null or jsonb_typeof(incoming) <> 'object' then
      result := result || jsonb_build_array(e.value);
    else
      -- هوية الوحدة ثابتة: النوع والاسم والرقم والمفتاح المثبّت.
      incoming := incoming || jsonb_build_object(
        'type', e.value -> 'type',
        'name', e.value -> 'name',
        'unitNumber', e.value -> 'unitNumber'
      );
      if e.value -> 'extras' ? '__key' then
        incoming := jsonb_set(
          incoming,
          '{extras}',
          coalesce(incoming -> 'extras', '{}'::jsonb)
            || jsonb_build_object('__key', e.value -> 'extras' -> '__key')
        );
      end if;
      result := result || jsonb_build_array(incoming);
    end if;
  end loop;

  update public.project_assets set units_json = result::text where id = p_asset;
end $$;

revoke all on function public.fundly_save_delegated_units(uuid, text) from public, anon;
grant execute on function public.fundly_save_delegated_units(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- ٢. سجلات المالك في نطاق التفويض — ومعها الأفراد والجهات
-- ------------------------------------------------------------
create or replace function public.fundly_delegated_records(p_delegation uuid)
returns table (
  source text,
  id uuid,
  title text,
  kind text,
  amount numeric,
  due text,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d public.delegations%rowtype;
  me text := public.fundly_my_fnd();
  main text;
  subs text[];
  personal_ids uuid[];
  shared_ids_ uuid[];
  asset_ids uuid[];
  person_ids text[];
  has_targets boolean;
  slugs text[];
  asset_cats text[];
  shared_types text[];
  people_raw text;
  people jsonb;
begin
  select * into d from public.delegations where delegations.id = p_delegation;
  if not found or me is null or not (me = any(d.shared_ids)) then
    return;
  end if;
  if not ('@accept:accepted' = any(d.permissions))
     or not ('عرض البيانات' = any(d.permissions))
     or d.is_paused
     or (d.start_date is not null and d.start_date > current_date)
     or (d.end_date is not null and d.end_date < current_date) then
    return;
  end if;

  main := trim(split_part(d.scope, ' — ', 1));
  subs := array(
    select trim(s)
    from unnest(string_to_array(split_part(d.scope, ' — ', 2), '،')) as s
    where trim(s) <> ''
  );

  -- عناصر بعينها: @target:الفرع|النوع|المعرّف|الاسم
  personal_ids := array(
    select split_part(substr(p, 9), '|', 3)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%' and split_part(substr(p, 9), '|', 2) = 'personal'
      and split_part(substr(p, 9), '|', 3) ~ '^[0-9a-f-]{36}$'
  );
  shared_ids_ := array(
    select split_part(substr(p, 9), '|', 3)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%' and split_part(substr(p, 9), '|', 2) = 'shared'
      and split_part(substr(p, 9), '|', 3) ~ '^[0-9a-f-]{36}$'
  );
  asset_ids := array(
    select split_part(split_part(substr(p, 9), '|', 3), '#', 1)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%'
      and split_part(substr(p, 9), '|', 2) in ('asset', 'unit')
      and split_part(split_part(substr(p, 9), '|', 3), '#', 1) ~ '^[0-9a-f-]{36}$'
  );
  person_ids := array(
    select trim(split_part(substr(p, 9), '|', 3))
    from unnest(d.permissions) as p
    where p like '@target:%' and split_part(substr(p, 9), '|', 2) = 'person'
  );
  has_targets := exists (
    select 1 from unnest(d.permissions) as p where p like '@target:%'
  );

  slugs := array(
    select case s
      when 'مالية' then 'financial'
      when 'مستند' then 'document'
      when 'المتابعة والتخطيط' then 'organization'
      when 'أدوية وبيانات وكلمات سر' then 'medical_accounts'
      when 'نمط الحياة' then 'lifestyle'
      when 'مواقع وأماكن' then 'location'
      when 'عهدة مالية' then 'custody'
      else s end
    from unnest(subs) as s
  );
  asset_cats := array(
    select case s
      when 'العقارات' then 'real_estate'
      when 'الأنشطة التجارية' then 'business'
      when 'المركبات ووسائل النقل' then 'equipment'
      else s end
    from unnest(subs) as s
  );
  shared_types := subs;

  if main in ('كل الأقسام', 'الالتزامات الشخصية') then
    return query
      select 'personal_entries'::text, e.id, e.title, e.entry_type,
             e.amount, coalesce(e.due_date::text, ''), e.status
      from public.personal_entries e
      where e.user_id = d.user_id
        and e.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and e.id = any(personal_ids))
          or (not has_targets and (
            cardinality(subs) = 0
            or e.category = any(slugs)
            or ('custody' = any(slugs) and e.entry_type = 'عهدة مالية')
          ))
        )
      order by e.created_at desc
      limit 300;
  end if;

  if main in ('كل الأقسام', 'الالتزامات المشتركة') then
    return query
      select 'shared_entries'::text, e.id, e.title, e.entry_type,
             e.amount, coalesce(e.due_date::text, ''), e.status
      from public.shared_entries e
      where e.user_id = d.user_id
        and e.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and e.id = any(shared_ids_))
          or (not has_targets and (
            cardinality(subs) = 0
            or e.entry_type = any(shared_types)
            or (e.entry_type = 'اللقاءات' and 'مشاركات مشتركة' = any(shared_types))
          ))
        )
      order by e.created_at desc
      limit 300;
  end if;

  if main in ('كل الأقسام', 'العقارات والأنشطة والمركبات') then
    return query
      select 'project_assets'::text, a.id, a.title, a.sub_type,
             0::numeric, coalesce(a.end_date::text, ''), a.status
      from public.project_assets a
      where a.user_id = d.user_id
        and a.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and a.id = any(asset_ids))
          or (not has_targets and (
            cardinality(subs) = 0 or a.category = any(asset_cats)
          ))
        )
      order by a.created_at desc
      limit 300;
  end if;

  -- الأفراد والجهات: من مزامنة المالك السحابية (للاطلاع).
  if main in ('كل الأقسام', 'الأفراد والجهات') then
    select s.value into people_raw
    from public.fundly_user_store s
    where s.user_id = d.user_id and s.key = 'people_management_records_v1';
    begin
      people := (people_raw::jsonb ->> 'v')::jsonb;
    exception when others then
      people := null;
    end;
    if people is not null and jsonb_typeof(people) = 'array' then
      return query
        select 'people'::text, null::uuid,
               coalesce(x ->> 'fullName', ''),
               coalesce(x ->> 'categoryName', ''),
               0::numeric,
               coalesce(
                 x -> 'details' ->> 'رقم الهاتف',
                 x -> 'details' ->> 'رقم الجوال',
                 x -> 'details' ->> 'الرقم التعريفي',
                 ''),
               coalesce(x ->> 'roleTitle', '')
        from jsonb_array_elements(people) as x
        where trim(coalesce(x ->> 'fullName', '')) <> ''
          and (
            main = 'كل الأقسام'
            or (cardinality(person_ids) > 0
                and trim(x ->> 'fullName') = any(person_ids))
            or (cardinality(person_ids) = 0 and (
              not ('الأفراد' = any(subs) or 'الجهات والشركات' = any(subs))
              or ('الأفراد' = any(subs)
                  and coalesce(x ->> 'typeKey', '') like 'person%')
              or ('الجهات والشركات' = any(subs)
                  and coalesce(x ->> 'typeKey', '') like 'entity%')
            ))
          )
        limit 500;
    end if;
  end if;
end $$;

revoke all on function public.fundly_delegated_records(uuid) from public, anon;
grant execute on function public.fundly_delegated_records(uuid) to authenticated;

-- ------------------------------------------------------------
-- ٣. المفوَّض يدير سجلًا شخصيًا أو مشتركًا
-- ------------------------------------------------------------
-- p_title / p_amount / p_due: بصلاحية «تعديل السجلات» فقط.
-- p_status و p_note: بأي صلاحية عمل (إضافة / تعديل / تنفيذ المدفوعات).
create or replace function public.fundly_delegate_edit_entry(
  p_delegation uuid,
  p_source text,
  p_id uuid,
  p_title text,
  p_amount numeric,
  p_due text,
  p_status text,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.delegations%rowtype;
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  can_edit boolean;
  owner uuid;
  old_title text;
  old_status text;
  etype text;
  details_ jsonb;
  what text;
  new_status text;
begin
  if p_source not in ('personal_entries', 'shared_entries') then
    raise exception 'نوع السجل غير مدعوم';
  end if;
  if not exists (
    select 1 from public.fundly_delegated_records(p_delegation) r
    where r.source = p_source and r.id = p_id
  ) then
    raise exception 'السجل خارج نطاق التفويض';
  end if;
  select * into d from public.delegations where id = p_delegation;
  if not (d.permissions &&
          array['إضافة السجلات', 'تعديل السجلات', 'تنفيذ المدفوعات والتحويلات']) then
    raise exception 'لا صلاحية';
  end if;
  can_edit := 'تعديل السجلات' = any(d.permissions);

  execute format(
    'select user_id, title, status, entry_type, details from public.%I where id = $1',
    p_source)
    into owner, old_title, old_status, etype, details_
    using p_id;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  new_status := coalesce(nullif(trim(coalesce(p_status, '')), ''), old_status);
  details_ := coalesce(details_, '{}'::jsonb) || jsonb_build_object(
    'آخر تعديل من المفوَّض',
    coalesce(actor_name, '') || ' — ' || to_char(now(), 'DD/MM/YYYY HH24:MI')
  );
  if trim(coalesce(p_note, '')) <> '' then
    details_ := details_ || jsonb_build_object('ملاحظة المفوَّض', trim(p_note));
  end if;

  if can_edit then
    execute format(
      'update public.%I set '
      'title = coalesce(nullif(trim(coalesce($2, '''')), ''''), title), '
      'amount = coalesce($3, amount), '
      'due_date = case when $4 is null then due_date '
      '  when trim($4) = '''' then null else $4::date end, '
      'status = $5, details = $6, updated_at = now() '
      'where id = $1', p_source)
      using p_id, p_title, p_amount, p_due, new_status, details_;
  else
    execute format(
      'update public.%I set status = $2, details = $3, updated_at = now() '
      'where id = $1', p_source)
      using p_id, new_status, details_;
  end if;

  what := case
    when new_status is distinct from old_status
      then 'غيّر الحالة إلى ' || new_status
    else 'عدّل السجل' end;

  if owner is not null and owner <> actor then
    insert into public.fundly_inbox (
      recipient_id, sender_id, sender_name, sender_fnd,
      source, record_id, entry_type, title, action, note
    ) values (
      owner, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
      p_source, p_id, coalesce(etype, ''),
      coalesce(
        case when can_edit then nullif(trim(coalesce(p_title, '')), '') end,
        old_title, ''),
      'activity',
      jsonb_build_object(
        'kind', 'delegate',
        'what', what,
        'name', trim(coalesce(p_note, '')),
        'amount', '0',
        'currency', ''
      )::text
    );
  end if;
end $$;

revoke all on function public.fundly_delegate_edit_entry(uuid, text, uuid, text, numeric, text, text, text) from public, anon;
grant execute on function public.fundly_delegate_edit_entry(uuid, text, uuid, text, numeric, text, text, text) to authenticated;

-- نقل السجل إلى سلة المالك (يستعيده المالك منها) — بصلاحية «حذف السجلات».
create or replace function public.fundly_delegate_trash_entry(
  p_delegation uuid,
  p_source text,
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  d public.delegations%rowtype;
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  owner uuid;
  old_title text;
  old_status text;
  etype text;
  details_ jsonb;
begin
  if p_source not in ('personal_entries', 'shared_entries') then
    raise exception 'نوع السجل غير مدعوم';
  end if;
  if not exists (
    select 1 from public.fundly_delegated_records(p_delegation) r
    where r.source = p_source and r.id = p_id
  ) then
    raise exception 'السجل خارج نطاق التفويض';
  end if;
  select * into d from public.delegations where id = p_delegation;
  if not ('حذف السجلات' = any(d.permissions)) then
    raise exception 'لا صلاحية';
  end if;

  execute format(
    'select user_id, title, status, entry_type, details from public.%I where id = $1',
    p_source)
    into owner, old_title, old_status, etype, details_
    using p_id;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  details_ := coalesce(details_, '{}'::jsonb) || jsonb_build_object(
    'الحالة قبل الحذف', coalesce(old_status, ''),
    'تاريخ الحذف', to_char(now(), 'YYYY/MM/DD HH24:MI'),
    'مصدر السجل', case p_source
      when 'shared_entries' then 'الالتزامات المشتركة'
      else 'الالتزامات الشخصية' end,
    'حذفه المفوَّض', coalesce(actor_name, '')
  );
  execute format(
    'update public.%I set status = ''محذوف'', details = $2, updated_at = now() '
    'where id = $1', p_source)
    using p_id, details_;

  if owner is not null and owner <> actor then
    insert into public.fundly_inbox (
      recipient_id, sender_id, sender_name, sender_fnd,
      source, record_id, entry_type, title, action, note
    ) values (
      owner, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
      p_source, p_id, coalesce(etype, ''), coalesce(old_title, ''),
      'activity',
      jsonb_build_object(
        'kind', 'delegate',
        'what', 'نقل السجل إلى سلة المهملات',
        'name', '',
        'amount', '0',
        'currency', ''
      )::text
    );
  end if;
end $$;

revoke all on function public.fundly_delegate_trash_entry(uuid, text, uuid) from public, anon;
grant execute on function public.fundly_delegate_trash_entry(uuid, text, uuid) to authenticated;
