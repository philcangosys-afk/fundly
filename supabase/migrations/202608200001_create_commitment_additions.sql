-- ============================================================================
-- Migration: Create structured tables for commitment additions
-- Date: 2026-08-20
-- Purpose: Replace JSONB storage with proper relational tables for all
--          commitment additions (payments, attachments, appointments, etc.)
-- ============================================================================

-- ============================================================================
-- 1. PAYMENTS TABLE (الدفعات)
-- Purpose: Track all payment transactions related to a commitment
-- Impact: Reduces remaining balance, updates commitment status
-- ============================================================================
create table if not exists public.commitment_payments (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Payment details
  amount numeric(14, 2) not null check (amount > 0),
  payment_date date not null default current_date,
  payment_method text check (payment_method in ('نقدي', 'بنكي', 'بطاقة', 'تحويل', 'شيك', 'أخرى')),
  
  -- Reference and notes
  reference_number text,
  notes text,
  
  -- Metadata
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists commitment_payments_commitment_idx
  on public.commitment_payments (commitment_id, payment_date desc);

create index if not exists commitment_payments_user_idx
  on public.commitment_payments (user_id, created_at desc);

-- ============================================================================
-- 2. ATTACHMENTS TABLE (المرفقات والمستندات)
-- Purpose: Store multiple attachments per commitment (invoices, receipts, docs)
-- Impact: Provides audit trail and proof documentation
-- ============================================================================
create table if not exists public.commitment_attachments (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Attachment details
  attachment_type text not null check (attachment_type in (
    'فاتورة', 'مستند', 'إيصال', 'عقد', 'صورة', 'مرفق آخر'
  )),
  file_name text not null,
  file_url text not null,
  file_size_kb integer,
  mime_type text,
  
  -- Description
  title text not null,
  description text,
  
  -- Metadata
  uploaded_at timestamptz not null default now()
);

create index if not exists commitment_attachments_commitment_idx
  on public.commitment_attachments (commitment_id, uploaded_at desc);

create index if not exists commitment_attachments_type_idx
  on public.commitment_attachments (attachment_type);

-- ============================================================================
-- 3. APPOINTMENTS TABLE (المواعيد والتذكيرات)
-- Purpose: Schedule follow-ups, reminders, and deadlines
-- Impact: Appears in calendar, triggers notifications
-- ============================================================================
create table if not exists public.commitment_appointments (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Appointment details
  appointment_type text not null check (appointment_type in (
    'موعد', 'تذكير', 'موعد دفع', 'موعد تجديد', 'موعد متابعة', 'أخرى'
  )),
  title text not null,
  description text,
  
  -- Date and time
  appointment_date date not null,
  appointment_time time,
  duration_minutes integer,
  
  -- Location (optional)
  location text,
  
  -- Status
  status text not null default 'قادم' check (status in ('قادم', 'تم', 'ملغي', 'مؤجل')),
  completed_at timestamptz,
  
  -- Reminder settings
  reminder_enabled boolean not null default true,
  reminder_minutes_before integer default 60,
  
  -- Metadata
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists commitment_appointments_commitment_idx
  on public.commitment_appointments (commitment_id, appointment_date desc);

create index if not exists commitment_appointments_date_idx
  on public.commitment_appointments (appointment_date, status)
  where status = 'قادم';

create index if not exists commitment_appointments_user_idx
  on public.commitment_appointments (user_id, appointment_date);

-- ============================================================================
-- 4. NOTES TABLE (الملاحظات والتسويات)
-- Purpose: Track administrative updates, settlements, renewals
-- Impact: Appears in activity log, provides audit trail
-- ============================================================================
create table if not exists public.commitment_notes (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Note details
  note_type text not null check (note_type in (
    'ملاحظة', 'تسوية', 'تجديد', 'بيانات إدارية', 'تحديث', 'أخرى'
  )),
  title text not null,
  content text not null,
  
  -- Impact tracking
  impacts_amount boolean not null default false,
  amount_change numeric(14, 2) default 0,
  
  impacts_date boolean not null default false,
  new_due_date date,
  
  -- Metadata
  created_at timestamptz not null default now()
);

create index if not exists commitment_notes_commitment_idx
  on public.commitment_notes (commitment_id, created_at desc);

create index if not exists commitment_notes_type_idx
  on public.commitment_notes (note_type);

-- ============================================================================
-- 5. RELATED PEOPLE TABLE (الأشخاص المرتبطين)
-- Purpose: Link people to commitments (creditors, debtors, witnesses)
-- Impact: Enables person-based filtering and reports
-- ============================================================================
create table if not exists public.commitment_people (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Person details
  person_name text not null,
  role_or_relationship text, -- e.g., 'دائن', 'مدين', 'شاهد', 'طرف ثاني'
  phone_number text,
  email text,
  national_id text,
  
  -- Additional info
  notes text,
  
  -- Metadata
  created_at timestamptz not null default now()
);

create index if not exists commitment_people_commitment_idx
  on public.commitment_people (commitment_id);

create index if not exists commitment_people_name_idx
  on public.commitment_people (person_name);

-- ============================================================================
-- 6. LOCATIONS TABLE (المواقع)
-- Purpose: Store location information for commitments (can be mapped)
-- Impact: Enables geospatial filtering and map visualization
-- ============================================================================
create table if not exists public.commitment_locations (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null references public.personal_entries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Location details
  location_type text not null check (location_type in (
    'عنوان', 'موقع حدث', 'مكتب', 'فرع', 'أخرى'
  )),
  address text not null,
  city text,
  district text,
  postal_code text,
  
  -- Geolocation
  latitude numeric(10, 7),
  longitude numeric(10, 7),
  
  -- Additional info
  notes text,
  
  -- Metadata
  created_at timestamptz not null default now()
);

create index if not exists commitment_locations_commitment_idx
  on public.commitment_locations (commitment_id);

-- ============================================================================
-- 7. COMPUTED VIEWS FOR COMMITMENT SUMMARY
-- Purpose: Calculate totals and remaining balance
-- ============================================================================

-- View: Commitment payment summary
create or replace view public.commitment_payment_summary as
select
  pe.id as commitment_id,
  pe.amount as original_amount,
  coalesce(sum(cp.amount), 0) as paid_amount,
  pe.amount - coalesce(sum(cp.amount), 0) as remaining_amount,
  case
    when pe.amount <= coalesce(sum(cp.amount), 0) then 'مكتمل'
    when coalesce(sum(cp.amount), 0) > 0 then 'جزئي'
    else 'لم يُسدد'
  end as payment_status,
  count(cp.id) as payment_count
from public.personal_entries pe
left join public.commitment_payments cp on cp.commitment_id = pe.id
group by pe.id, pe.amount;

-- View: Commitment summary with all additions
create or replace view public.commitment_full_summary as
select
  pe.id,
  pe.user_id,
  pe.title,
  pe.category,
  pe.entry_type,
  pe.amount as original_amount,
  pe.due_date,
  pe.status,
  pe.created_at,
  pe.updated_at,
  
  -- Payment summary
  ps.paid_amount,
  ps.remaining_amount,
  ps.payment_status,
  ps.payment_count,
  
  -- Counts
  (select count(*) from public.commitment_attachments where commitment_id = pe.id) as attachments_count,
  (select count(*) from public.commitment_appointments where commitment_id = pe.id and status = 'قادم') as upcoming_appointments_count,
  (select count(*) from public.commitment_notes where commitment_id = pe.id) as notes_count,
  (select count(*) from public.commitment_people where commitment_id = pe.id) as related_people_count,
  (select count(*) from public.commitment_locations where commitment_id = pe.id) as locations_count,
  
  -- Next appointment
  (
    select appointment_date
    from public.commitment_appointments
    where commitment_id = pe.id
      and status = 'قادم'
      and appointment_date >= current_date
    order by appointment_date asc
    limit 1
  ) as next_appointment_date
  
from public.personal_entries pe
left join public.commitment_payment_summary ps on ps.commitment_id = pe.id;

-- ============================================================================
-- 8. TRIGGERS FOR AUTOMATIC UPDATES
-- Purpose: Auto-update commitment status when payments are added
-- ============================================================================

-- Function: Update commitment status after payment
create or replace function public.update_commitment_after_payment()
returns trigger as $$
declare
  v_total_paid numeric;
  v_original_amount numeric;
  v_new_status text;
begin
  -- Calculate total paid for this commitment
  select coalesce(sum(amount), 0) into v_total_paid
  from public.commitment_payments
  where commitment_id = coalesce(new.commitment_id, old.commitment_id);
  
  -- Get original amount
  select amount into v_original_amount
  from public.personal_entries
  where id = coalesce(new.commitment_id, old.commitment_id);
  
  -- Determine new status
  if v_total_paid >= v_original_amount then
    v_new_status := 'مكتمل';
  elsif v_total_paid > 0 then
    v_new_status := 'جزئي';
  else
    v_new_status := 'نشطة';
  end if;
  
  -- Update commitment
  update public.personal_entries
  set
    status = v_new_status,
    updated_at = now()
  where id = coalesce(new.commitment_id, old.commitment_id);
  
  return coalesce(new, old);
end;
$$ language plpgsql security definer;

-- Trigger: After payment insert/update/delete
drop trigger if exists trigger_update_commitment_after_payment on public.commitment_payments;
create trigger trigger_update_commitment_after_payment
  after insert or update or delete on public.commitment_payments
  for each row
  execute function public.update_commitment_after_payment();

-- ============================================================================
-- 9. ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Payments
alter table public.commitment_payments enable row level security;

drop policy if exists "Users manage own commitment payments" on public.commitment_payments;
create policy "Users manage own commitment payments"
  on public.commitment_payments for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Attachments
alter table public.commitment_attachments enable row level security;

drop policy if exists "Users manage own commitment attachments" on public.commitment_attachments;
create policy "Users manage own commitment attachments"
  on public.commitment_attachments for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Appointments
alter table public.commitment_appointments enable row level security;

drop policy if exists "Users manage own commitment appointments" on public.commitment_appointments;
create policy "Users manage own commitment appointments"
  on public.commitment_appointments for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Notes
alter table public.commitment_notes enable row level security;

drop policy if exists "Users manage own commitment notes" on public.commitment_notes;
create policy "Users manage own commitment notes"
  on public.commitment_notes for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- People
alter table public.commitment_people enable row level security;

drop policy if exists "Users manage own commitment people" on public.commitment_people;
create policy "Users manage own commitment people"
  on public.commitment_people for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Locations
alter table public.commitment_locations enable row level security;

drop policy if exists "Users manage own commitment locations" on public.commitment_locations;
create policy "Users manage own commitment locations"
  on public.commitment_locations for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ============================================================================
-- 10. STORAGE BUCKET FOR MULTIPLE ATTACHMENTS
-- ============================================================================

-- Update existing bucket or create new one for multiple attachments
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'commitment-attachments',
  'commitment-attachments',
  false,
  10485760, -- 10 MB
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'image/heic']
)
on conflict (id) do update
set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload own commitment attachments" on storage.objects;
create policy "Users upload own commitment attachments"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'commitment-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users read own commitment attachments" on storage.objects;
create policy "Users read own commitment attachments"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'commitment-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Users delete own commitment attachments" on storage.objects;
create policy "Users delete own commitment attachments"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'commitment-attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
