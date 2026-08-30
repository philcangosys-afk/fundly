# Quick Fix: Data Not Showing or Saving

## Problem
After running `flutter build apk --release`, the app:
- ✅ Works without errors
- ❌ Doesn't show old data
- ❌ Doesn't save new data

## Root Cause
The app switched from **anonymous sign-in** to a **fixed account** (`app@fundly.local`).
Old data is still in Supabase but under an old anonymous account.

## Quick Solution (5 minutes)

### 1️⃣ Open Supabase
<https://supabase.com/dashboard>
→ Select project `pcppwpbaknxflzbqbrxj`
→ Open **SQL Editor**

### 2️⃣ Quick Diagnosis
Copy and paste this query:

```sql
select
  coalesce(u.email, '(anonymous)') as email,
  (select count(*) from public.personal_entries t where t.user_id = u.id) as entries
from auth.users u
order by u.created_at;
```

**Expected result:**
- `app@fundly.local` → 0 rows (new empty account)
- `(anonymous)` → large numbers (your old data is here)

### 3️⃣ Create App Account (if not found)

If you **don't** see `app@fundly.local` in the results:

1. In Supabase, open **Authentication** > **Users**
2. Click **Add user** > **Create new user**
3. Fill in:
   - Email: `app@fundly.local`
   - Password: `Fundly-Shared-2026!`
   - ✅ **Auto Confirm User** (important!)
4. Click **Create user**

### 4️⃣ Migrate Data

1. Open file: `supabase/migrations/_quick_fix_data_recovery.sql`
2. Follow the instructions in the file (3 simple steps)
3. Restart the app

## Verify Success

### In the app:
1. Completely close the app (remove from background)
2. Open it again
3. Go to **Settings** > **Data Status and Connection**
4. Verify:
   - Account = `app@fundly.local` ✅
   - Record count > 0 ✅

### Test saving:
1. Add a new commitment in **Personal Commitments**
2. Close and reopen the app
3. The commitment should appear ✅

---

## Helper Files

| File | Description |
|------|-------------|
| `حل_مشكلة_البيانات.md` | Complete detailed guide (Arabic) |
| `QUICK_FIX.md` | Quick fix guide (Arabic) |
| `supabase/migrations/_quick_fix_data_recovery.sql` | Ready-to-run SQL script |
| `supabase/migrations/_diagnose_missing_data.sql` | Advanced diagnostics |
| `supabase/migrations/_recover_old_data.sql` | Step-by-step manual recovery |

---

## Important Notes

### ⚠️ Security
The fixed account (`app@fundly.local`) means **everyone with a copy of the app accesses the same data**.
- ✅ Suitable for personal use
- ✅ Suitable for trusted circle (family, small team)
- ❌ Not suitable for public distribution

### 🔐 Change Password (Optional)
For better security, you can change the default password:

1. In `lib/config/supabase_config.dart`, edit:
   ```dart
   static const appAccountPassword = 'your-new-strong-password';
   ```

2. In Supabase > Authentication > Users > `app@fundly.local`:
   - Click user > Update password
   - Set the same new password

3. Rebuild the app:
   ```bash
   flutter build apk --release
   ```

---

**Last updated**: August 28, 2026
