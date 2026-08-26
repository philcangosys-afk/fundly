-- Adds a real tenant phone number so the unit-details screen can offer
-- functional call/WhatsApp actions (matching the reference screens) instead
-- of decorative icons with no data behind them.

alter table if exists public.property_unit_contracts
  add column if not exists tenant_phone text;
