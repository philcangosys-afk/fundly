create table if not exists public.personal_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('financial', 'administrative', 'accounts')),
  entry_type text not null,
  title text not null,
  amount numeric(14, 2) not null default 0 check (amount >= 0),
  due_date date,
  status text not null default 'نشطة',
  details jsonb not null default '{}'::jsonb,
  attachment_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists personal_entries_user_created_idx
  on public.personal_entries (user_id, created_at desc);

alter table public.personal_entries enable row level security;

drop policy if exists "Users read own personal entries" on public.personal_entries;
create policy "Users read own personal entries"
  on public.personal_entries for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own personal entries" on public.personal_entries;
create policy "Users insert own personal entries"
  on public.personal_entries for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own personal entries" on public.personal_entries;
create policy "Users update own personal entries"
  on public.personal_entries for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users delete own personal entries" on public.personal_entries;
create policy "Users delete own personal entries"
  on public.personal_entries for delete
  to authenticated
  using ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('personal-entry-attachments', 'personal-entry-attachments', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "Users upload own personal entry attachments" on storage.objects;
create policy "Users upload own personal entry attachments"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'personal-entry-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users read own personal entry attachments" on storage.objects;
create policy "Users read own personal entry attachments"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'personal-entry-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
