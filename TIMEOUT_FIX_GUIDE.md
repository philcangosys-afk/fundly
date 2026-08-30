# دليل إصلاح مشكلة Timeout في تسجيل الدخول

## 🔍 المشكلة
```
خطأ الجلسة: TimeoutException after 0:00:20.000000: Future not completed
```

التطبيق لا يستطيع تسجيل الدخول إلى حساب `fundly.app.2026@gmail.com`.

---

## ✅ الحلول (جرّبها بالترتيب)

### الحل 1: تحديث كلمة المرور وتفعيل الحساب (SQL)

1. افتح **SQL Editor** في Supabase Dashboard
2. نفّذ الملف: `supabase/migrations/_fix_account_and_password.sql`
3. تحقق من النتائج - يجب أن ترى:
   - ✅ مفعّل؟ = `true`
   - ✅ رمز التأكيد فارغ؟ = `true`
   - ✅ Aud صحيح؟ = `true`
   - ✅ Role صحيح؟ = `true`

### الحل 2: إعادة إنشاء الحساب من Dashboard

إذا لم ينجح الحل 1:

1. **حذف الحساب القديم:**
   - اذهب إلى **Authentication → Users**
   - ابحث عن `fundly.app.2026@gmail.com`
   - اضغط على الحساب ← **Delete user**

2. **إنشاء حساب جديد:**
   - اضغط **Add user → Create new user**
   - **Email:** `fundly.app.2026@gmail.com`
   - **Password:** `Fundly-Shared-2026!`
   - ✅ فعّل **Auto Confirm User** ← **مهم جداً!**
   - اضغط **Create user**

3. **نقل البيانات للحساب الجديد:**
   - نفّذ `supabase/migrations/_migrate_data_to_fundly_app.sql`

### الحل 3: التحقق من إعدادات Authentication

1. اذهب إلى **Authentication → Settings**
2. تحقق من:
   - ✅ **Enable email confirmations** = `OFF` (أو إيقاف تشغيله)
   - ✅ **Secure email change** = `OFF` (أو إيقاف تشغيله)

### الحل 4: اختبار الاتصال

نفّذ هذا SQL لاختبار الحساب:

```sql
-- اختبار وجود الحساب وحالته
select 
  email,
  email_confirmed_at,
  confirmation_token,
  aud,
  role,
  encrypted_password is not null as "كلمة المرور موجودة؟"
from auth.users
where email = 'fundly.app.2026@gmail.com';
```

النتيجة المطلوبة:
- `email_confirmed_at`: تاريخ (ليس NULL)
- `confirmation_token`: فارغ أو NULL
- `aud`: `authenticated`
- `role`: `authenticated`
- `كلمة المرور موجودة؟`: `true`

---

## 🔧 بعد تطبيق الحل

1. أعد تشغيل التطبيق
2. انتظر قليلاً (10-15 ثانية)
3. راقب شاشة "حالة البيانات"
4. يجب أن ترى:
   - ✅ الحساب: `fundly.app.2026@gmail.com`
   - ✅ المعرّف: `905559e1-...`
   - ✅ أرقام البيانات تظهر بشكل صحيح

---

## ⚠️ إذا استمرت المشكلة

أرسل لي:
1. نتيجة الاستعلام من "الحل 4"
2. رسالة الخطأ الكاملة من التطبيق (إن وجدت)
3. لقطة شاشة من Authentication → Users
