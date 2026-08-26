# Supabase setup for personal entries

The Flutter application is configured for project `pcppwpbaknxflzbqbrxj`, but the remote project currently has anonymous sign-ins disabled and does not expose the required `personal_entries` table.

## 1. Enable anonymous sign-ins

1. Open the Supabase dashboard.
2. Select the `pcppwpbaknxflzbqbrxj` project.
3. Open **Authentication > Providers > Anonymous Sign-Ins**.
4. Enable anonymous sign-ins and save.

Anonymous users receive a real `auth.users` ID. The row-level security policies use this ID so each installation can only read and modify its own entries.

## 2. Create the table and storage policies

1. Open **SQL Editor** in the same project.
2. Open `supabase/migrations/202607190001_create_personal_entries.sql` from this repository.
3. Run the entire script once.

The script creates:

- `public.personal_entries`
- Private bucket `personal-entry-attachments`
- RLS policies for reading, inserting, updating, and deleting only the current user's records
- Storage policies restricting files to the current user's folder

## 3. Run the application

The checked-in values work for this project. They can be overridden for another environment:

```powershell
flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

Do not put a `service_role` key in the Flutter application. It bypasses RLS and must remain server-side.

## Verification

After completing steps 1 and 2:

1. Open **Personal Commitments**.
2. Add an entry and save it.
3. Restart the app.
4. Confirm that the saved entry is loaded again.
5. Check `Table Editor > personal_entries` to confirm the row exists.
