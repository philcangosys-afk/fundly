-- المعدات كانت تُحفظ سابقًا بنفس قيمة الأنشطة التجارية ('business') في عمود
-- category بسبب قيد check لا يسمح إلا بـ ('real_estate', 'project',
-- 'business')، فتتحول كل معدة إلى نشاط تجاري بشكل دائم بعد أول حفظ. يوسّع
-- هذا الملف القيد ليشمل 'equipment' كقيمة مستقلة، بالإضافة لعمودي "تجميد"
-- و"تثبيت في الرئيسية" اللذين كانا يُطبَّقان محليًا فقط دون أي عمود يحفظهما.

alter table if exists public.project_assets
  drop constraint if exists project_assets_category_check;

alter table if exists public.project_assets
  add constraint project_assets_category_check
  check (category in ('real_estate', 'project', 'business', 'equipment'));

alter table if exists public.project_assets
  add column if not exists is_frozen boolean not null default false,
  add column if not exists is_pinned boolean not null default false;
