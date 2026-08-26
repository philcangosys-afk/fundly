-- Migrate public.personal_entries.category from the old 3-value taxonomy
-- ('financial' | 'administrative' | 'accounts') to the new 7-category
-- taxonomy used by the restructured "الالتزامات الشخصية" screen:
--   financial | document | organization | medical_accounts | lifestyle | location | custody
--
-- Safe to run even if the table currently has no rows (backfill is a no-op then).

alter table public.personal_entries
  drop constraint if exists personal_entries_category_check;

-- Backfill existing rows based on entry_type, mirroring the mapping in
-- _entryTypeCategorySlug inside personal_commitments_screen.dart.
update public.personal_entries
set category = case
  when entry_type in (
    'مصروف', 'إيراد', 'تحويل مالي', 'دين / قرض / سلفة', 'قسط', 'غرامة'
  ) then 'financial'
  when entry_type = 'مستند' then 'document'
  when entry_type in (
    'مهمة', 'موعد', 'عادة', 'ملاحظات', 'متابعة', 'تسجيل / تخطيط'
  ) then 'organization'
  when entry_type in (
    'حسابات', 'أدوية وبياناتها', 'الحسابات والبيانات',
    'كلمات السر', 'الإيميلات', 'الحسابات البنكية'
  ) then 'medical_accounts'
  when entry_type in (
    'مناسبة', 'اشتراك', 'اشتراكات', 'هدية', 'عطاء', 'جمعية'
  ) then 'lifestyle'
  when entry_type = 'مواقع وأماكن' then 'location'
  when entry_type = 'عهدة مالية' then 'custody'
  -- fallback for any legacy/unknown entry_type: keep it under "organization"
  else 'organization'
end
where category not in (
  'financial', 'document', 'organization', 'medical_accounts', 'lifestyle',
  'location', 'custody'
);

alter table public.personal_entries
  add constraint personal_entries_category_check
  check (category in (
    'financial', 'document', 'organization', 'medical_accounts', 'lifestyle',
    'location', 'custody'
  ));
