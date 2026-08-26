-- Persists the asset's activity log (e.g. "تمت إضافة وحدة ...", "تم إرسال
-- طلب تفويض ...") so it survives a reload instead of vanishing the moment
-- the asset is re-fetched from Supabase. Stored as a JSON-encoded list of
-- strings, mirroring the existing units_json/employees_json pattern.

alter table if exists public.project_assets
  add column if not exists logs_json text;
