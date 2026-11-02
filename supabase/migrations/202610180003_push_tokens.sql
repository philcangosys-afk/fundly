-- ============================================================
-- fundly — إشعارات تصل والتطبيق مغلق (Firebase Cloud Messaging)
-- ============================================================
-- شغّله بعد 202610180002. آمن لإعادة التشغيل.
--
-- 1) جدول رموز الأجهزة: كل جوال يسجّل رمزه باسم الحساب الداخل منه.
-- 2) عند كل طلب أو رد أو نشاط جديد في fundly_inbox يستدعي المشغّل دالة
--    fundly-push (Edge Function) فترسل الإشعار لأجهزة المستلم.
--    المفتاح المرسل هو المفتاح العام نفسه الموجود في التطبيق، والدالة لا
--    تثق بما يصلها: تقرأ الطلب من الجدول بمعرّفه.
-- ============================================================

create extension if not exists pg_net with schema extensions;

create table if not exists public.fundly_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists fundly_push_tokens_user_idx
  on public.fundly_push_tokens (user_id);

-- لا قراءة ولا كتابة مباشرة من التطبيق: عبر الدالتين أدناه فقط.
alter table public.fundly_push_tokens enable row level security;
revoke all on public.fundly_push_tokens from anon, authenticated;

-- تسجيل رمز هذا الجهاز للحساب الداخل (وإن كان مسجّلًا لحساب سابق على
-- الجهاز نفسه يُنقل للحساب الحالي).
create or replace function public.fundly_register_push(
  p_token text,
  p_platform text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or coalesce(btrim(p_token), '') = '' then
    return;
  end if;
  insert into public.fundly_push_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, ''), now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end $$;

create or replace function public.fundly_unregister_push(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.fundly_push_tokens
  where token = p_token and user_id = auth.uid();
end $$;

revoke all on function public.fundly_register_push(text, text) from public, anon;
revoke all on function public.fundly_unregister_push(text) from public, anon;
grant execute on function public.fundly_register_push(text, text) to authenticated;
grant execute on function public.fundly_unregister_push(text) to authenticated;

-- كل إدخال جديد في صندوق الطلبات يُرسَل إشعارًا لأجهزة المستلم.
create or replace function public.fundly_inbox_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://pcppwpbaknxflzbqbrxj.supabase.co/functions/v1/fundly-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBjcHB3cGJha254Zmx6YnFicnhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NDkwMDcsImV4cCI6MjEwMDAyNTAwN30.kyUladJf7EUZeVhtjJDfnEPbHPiqKx8ovyRSbBEL0Is'
    ),
    body := jsonb_build_object('id', new.id)
  );
  return new;
exception
  when others then
    -- فشل الإرسال لا يمنع حفظ الطلب؛ يبقى ظاهرًا في التطبيق.
    return new;
end $$;

drop trigger if exists fundly_inbox_push on public.fundly_inbox;
create trigger fundly_inbox_push
  after insert on public.fundly_inbox
  for each row execute function public.fundly_inbox_push();
