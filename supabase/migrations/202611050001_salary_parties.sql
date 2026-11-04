-- ============================================================
-- fundly — صفة الطرفين في سند القبض
-- ============================================================
-- شغّله بعد 202611040001. آمن لإعادة التشغيل.
--
-- السند إما بين «صاحب العمل والموظف» (الافتراضي) أو بين «المسلّم
-- والمستلم» (من صديق لصديقه مثلًا). تظهر الصفة في السند ونسخته PDF.
-- ============================================================

alter table public.fundly_salary_receipts
  add column if not exists parties text not null default 'employer';

alter table public.fundly_salary_receipts
  drop constraint if exists fundly_salary_receipts_parties_check;
alter table public.fundly_salary_receipts
  add constraint fundly_salary_receipts_parties_check
  check (parties in ('employer', 'handover'));

notify pgrst, 'reload schema';
