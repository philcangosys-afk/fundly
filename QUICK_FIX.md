# 🚨 حل سريع: البيانات لا تظهر ولا تُحفظ

## المشكلة
بعد تشغيل `flutter build apk --release`، التطبيق:
- ✅ يعمل بدون أخطاء
- ❌ لا يعرض البيانات القديمة
- ❌ لا يحفظ بيانات جديدة

## السبب
التطبيق تحول من **دخول مجهول** إلى **حساب ثابت** `app@fundly.local`.
البيانات القديمة مازالت في Supabase لكنها تحت حساب مجهول قديم.

## الحل السريع (5 دقائق)

### 1️⃣ افتح Supabase
<https://supabase.com/dashboard>
→ اختر المشروع `pcppwpbaknxflzbqbrxj`
→ افتح **SQL Editor**

### 2️⃣ تشخيص سريع
انسخ والصق هذا الاستعلام:

```sql
select
  coalesce(u.email, '(مجهول)') as email,
  (select count(*) from public.personal_entries t where t.user_id = u.id) as entries
from auth.users u
order by u.created_at;
```

**النتيجة المتوقعة:**
- `app@fundly.local` → 0 صفوف (حساب جديد فارغ)
- `(مجهول)` → أرقام كبيرة (بياناتك القديمة هنا)

### 3️⃣ الحل

#### إذا لم تجد `app@fundly.local` في النتائج:
1. في Supabase، افتح **Authentication** > **Users**
2. اضغط **Add user** > **Create new user**
3. املأ:
   - Email: `app@fundly.local`
   - Password: `Fundly-Shared-2026!`
   - ✅ **Auto Confirm User** (مهم!)
4. اضغط **Create user**

#### نقل البيانات:
1. افتح ملف: `supabase/migrations/_quick_fix_data_recovery.sql`
2. اتبع التعليمات في الملف (3 خطوات بسيطة)
3. أعد تشغيل التطبيق

## التحقق من النجاح

### في التطبيق:
1. أغلق التطبيق تمامًا من الخلفية
2. افتحه من جديد
3. افتح **الإعدادات** > **حالة البيانات والاتصال**
4. تحقق:
   - الحساب = `app@fundly.local` ✅
   - عدد السجلات > 0 ✅

### اختبار الحفظ:
1. أضف التزامًا جديدًا في **الالتزامات الشخصية**
2. أغلق التطبيق وأعد فتحه
3. يجب أن يظهر الالتزام ✅

---

## ملفات مساعدة

| الملف | الوصف |
|------|-------|
| `حل_مشكلة_البيانات.md` | دليل تفصيلي كامل |
| `supabase/migrations/_quick_fix_data_recovery.sql` | سكريبت سريع للتنفيذ المباشر |
| `supabase/migrations/_diagnose_missing_data.sql` | تشخيص متقدم |
| `supabase/migrations/_recover_old_data.sql` | استرجاع يدوي خطوة بخطوة |

---

## ملاحظات مهمة

### ⚠️ الأمان
الحساب الثابت (`app@fundly.local`) يعني أن **كل من لديه نسخة من التطبيق يصل لنفس البيانات**.
- ✅ مناسب للاستخدام الشخصي
- ✅ مناسب لدائرة موثوقة (عائلة، فريق صغير)
- ❌ غير مناسب للتوزيع العام

### 🔐 تغيير كلمة المرور (اختياري)
لحماية أفضل، يمكنك تغيير كلمة المرور الافتراضية:

1. في `lib/config/supabase_config.dart`، عدّل:
   ```dart
   static const appAccountPassword = 'كلمة-مرور-جديدة-قوية';
   ```

2. في Supabase > Authentication > Users > `app@fundly.local`:
   - اضغط على المستخدم > Update password
   - ضع نفس كلمة المرور الجديدة

3. أعد بناء التطبيق:
   ```bash
   flutter build apk --release
   ```

---

**آخر تحديث**: 28 أغسطس 2026
