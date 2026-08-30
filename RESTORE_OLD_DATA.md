# استعادة البيانات القديمة إلى الحساب المجهول الجديد

## 📋 المشكلة:
- البيانات القديمة كانت مرتبطة بحساب `fundly.app.2026@gmail.com`
- التطبيق الآن يستخدم حساب مجهول جديد
- البيانات القديمة غير ظاهرة

## ✅ الحل (3 خطوات):

---

### الخطوة 1️⃣: معرفة معرّف المستخدم الحالي

1. **افتح التطبيق**
2. اذهب إلى **"حالة البيانات"** (من الشاشة الرئيسية)
3. انظر إلى **"المعرّف:"** - سترى شيء مثل:
   ```
   905559e1-6b99-4fe6-8e7a-f9567f8160c9
   ```
4. **انسخه**

---

### الخطوة 2️⃣: تحديث السكريبت

1. **افتح الملف:**
   ```
   supabase/migrations/_migrate_to_current_user.sql
   ```

2. **ابحث عن السطر:**
   ```sql
   current_user_id uuid := 'PASTE_YOUR_CURRENT_USER_ID_HERE';
   ```

3. **استبدل `PASTE_YOUR_CURRENT_USER_ID_HERE` بالمعرّف المنسوخ:**
   ```sql
   current_user_id uuid := '905559e1-6b99-4fe6-8e7a-f9567f8160c9';
   ```
   *(استخدم المعرّف الذي نسخته من التطبيق)*

4. **احفظ الملف**

---

### الخطوة 3️⃣: تشغيل السكريبت

1. **افتح SQL Editor في Supabase Dashboard**
2. **انسخ محتويات الملف المحدّث ونفّذه**
3. يجب أن ترى:
   ```
   ✓ project_assets : 8 صف
   ✓ personal_entries : 21 صف
   ✓ shared_entries : 7 صف
   ✓✓✓ اكتمل النقل بنجاح ✓✓✓
   ```

---

## 🚀 بعد التنفيذ:

1. **أغلق التطبيق تماماً**
2. **أعد فتحه**
3. **يجب أن تظهر جميع البيانات القديمة!**
   - 8 عقارات
   - 21 التزام شخصي
   - 7 التزامات مشتركة

---

## ✨ بديل أسرع (إذا كنت متأكد من المعرّف):

يمكنك تنفيذ هذا SQL مباشرة (استبدل `YOUR_USER_ID` بمعرّفك):

```sql
do $$
declare
  current_user_id uuid := 'YOUR_USER_ID';  -- ضع معرّفك هنا
  old_user_id uuid;
begin
  select id into old_user_id from auth.users where email = 'fundly.app.2026@gmail.com';
  
  update public.project_assets set user_id = current_user_id where user_id = old_user_id;
  update public.personal_entries set user_id = current_user_id where user_id = old_user_id;
  update public.shared_entries set user_id = current_user_id where user_id = old_user_id;
  update public.wallets set user_id = current_user_id where user_id = old_user_id;
  update public.delegations set user_id = current_user_id where user_id = old_user_id;
end $$;
```

---

## 📸 أخبرني:
بعد نسخ المعرّف من التطبيق، أرسله لي وسأحضّر السكريبت الجاهز لك!
