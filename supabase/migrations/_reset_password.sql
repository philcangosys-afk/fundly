-- ============================================================
-- إعادة تعيين كلمة مرور حساب app@fundly.local
-- ============================================================
-- لحل مشكلة "تعذّر الدخول إلى حساب التطبيق"
-- ============================================================

-- 1️⃣ التحقق من حالة الحساب
select 
  email,
  email_confirmed_at as "مفعّل؟",
  banned_until as "محظور؟",
  last_sign_in_at as "آخر دخول"
from auth.users
where email = 'app@fundly.local';

-- 2️⃣ إعادة تعيين كلمة المرور إلى: Fundly-Shared-2026!
-- قم بتشغيل هذا في Supabase SQL Editor:

-- ⚠️ ملاحظة: لا يمكن تعيين كلمة المرور مباشرة من SQL
-- بدلاً من ذلك، استخدم Supabase Dashboard:
--
-- 1. اذهب إلى: Authentication > Users
-- 2. ابحث عن: app@fundly.local
-- 3. اضغط على النقاط الثلاث (⋮) بجانب الحساب
-- 4. اختر "Reset Password"
-- 5. أدخل: Fundly-Shared-2026!
-- 6. اضغط "Update User"
--
-- أو احذف الحساب وأعد إنشاءه:

-- 3️⃣ حذف الحساب القديم (إذا لزم الأمر)
-- ⚠️ تحذير: هذا سيحذف بيانات المستخدم!
-- delete from auth.users where email = 'app@fundly.local';

-- 4️⃣ إنشاء حساب جديد
-- اذهب إلى: Authentication > Users > Add User
-- Email: app@fundly.local
-- Password: Fundly-Shared-2026!
-- ✅ تأكد من تفعيل: "Auto Confirm User"
