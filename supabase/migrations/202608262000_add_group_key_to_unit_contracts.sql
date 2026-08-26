-- Supports "عقد متعدد الوحدات" (multi-unit contract): one tenant leasing
-- several units under a single agreement, with rent distributed equally.
-- Implemented as one property_unit_contracts row per unit (so each unit
-- keeps its own payment history), all sharing the same group_key so the UI
-- can render them as one consolidated contract.

alter table if exists public.property_unit_contracts
  add column if not exists group_key text;

create index if not exists property_unit_contracts_group_key_idx
  on public.property_unit_contracts (group_key)
  where group_key is not null;
