-- إلغاء عقد الإيجار يكتب الحالة 'cancelled'، وقيد الحالة القديم لا يقبلها
-- (active / expired / pending / late فقط) فيفشل الإلغاء برسالة «تعذر».
-- يُضاف 'cancelled' و'ended' إلى القيم المسموحة، والباقي كما هو.
alter table public.property_unit_contracts
  drop constraint if exists property_unit_contracts_status_check;

alter table public.property_unit_contracts
  add constraint property_unit_contracts_status_check
  check (status in ('active', 'expired', 'pending', 'late', 'cancelled', 'ended'));
