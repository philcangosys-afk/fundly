# تحديث شاشات Onboarding لاستخدام الصور

## الخطوة الحالية

التطبيق يستخدم حالياً **رسوميات مخصصة** (Illustrations) بدلاً من صور خارجية.

---

## كيفية التبديل إلى الصور

عندما تضع الصور في `assets/images/`، اتبع هذه الخطوات:

### 1️⃣ في ملف `lib/screens/onboarding_screen.dart`

ابحث عن السطر:
```dart
final List<OnboardingPage> pages = [
```

وستجد 3 كائنات `OnboardingPage` - كل واحد يستخدم دالة `_build*Illustration()`.

### 2️⃣ استبدل كل رسوميات برسومة صورة

**المثال - الصفحة الأولى:**

❌ **قبل:**
```dart
OnboardingPage(
  title: 'نظم التزاماتك\nبكل سهولة',
  description: 'كل مهامك والتزاماتك المالية والشخصية\nفي مكان واحد، مرتب ومنظمة.',
  iconWidget: _buildWalletIllustration(),  // ← رسوميات مخصصة
  dotColor: Color(0xFF7C3AED),
),
```

✅ **بعد:**
```dart
OnboardingPage(
  title: 'نظم التزاماتك\nبكل سهولة',
  description: 'كل مهامك والتزاماتك المالية والشخصية\nفي مكان واحد، مرتب ومنظمة.',
  iconWidget: Image.asset(
    'assets/images/splash_1.png',
    width: 400,
    height: 320,
    fit: BoxFit.contain,
  ),
  dotColor: Color(0xFF7C3AED),
),
```

### 3️⃣ الصفحات الثلاث

| الصفحة | قبل | بعد |
|-------|-----|-----|
| 1 | `_buildWalletIllustration()` | `Image.asset('assets/images/splash_1.png', ...)` |
| 2 | `_buildPeopleIllustration()` | `Image.asset('assets/images/splash_2.png', ...)` |
| 3 | `_buildSecurityIllustration()` | `Image.asset('assets/images/splash_3.png', ...)` |

---

## الكود الكامل (بعد التحديث)

```dart
final List<OnboardingPage> pages = [
  // الصفحة الأولى
  OnboardingPage(
    title: 'نظم التزاماتك\nبكل سهولة',
    description: 'كل مهامك والتزاماتك المالية والشخصية\nفي مكان واحد، مرتب ومنظمة.',
    iconWidget: Image.asset(
      'assets/images/splash_1.png',
      width: 400,
      height: 320,
      fit: BoxFit.contain,
    ),
    dotColor: Color(0xFF7C3AED),
  ),
  // الصفحة الثانية
  OnboardingPage(
    title: 'شارك وادفع\nمع أصدقائك',
    description: 'قسم المصاريف، تابع الدفعات المشتركة،\nوادر التزاماتك مع الآخرين بذكاء.',
    iconWidget: Image.asset(
      'assets/images/splash_2.png',
      width: 400,
      height: 320,
      fit: BoxFit.contain,
    ),
    dotColor: Color(0xFF3B82F6),
  ),
  // الصفحة الثالثة
  OnboardingPage(
    title: 'ثقة وشفافية\nمطلقة',
    description: 'كن العضو الأكثر موثوقية\nوتابع نمو التزاماتك بكل أمان.',
    iconWidget: Image.asset(
      'assets/images/splash_3.png',
      width: 400,
      height: 320,
      fit: BoxFit.contain,
    ),
    dotColor: Color(0xFF7C3AED),
  ),
];
```

---

## يمكنك أيضاً حذف الدوال الرسوميات

إذا استخدمت الصور، يمكنك حذف هذه الدوال (اختياري):
- `_buildWalletIllustration()`
- `_buildPeopleIllustration()`
- `_buildSecurityIllustration()`

لكن من الأفضل الاحتفاظ بها كـ "fallback" في حالة عدم توفر الصور.

---

## الحالة الحالية

✅ **مجلد assets تم إنشاؤه**
✅ **pubspec.yaml تم تحديثه**
⏳ **في انتظار إضافة الصور**
⏳ **يمكنك تحديث onboarding_screen.dart متى أردت**

---

## أسئلة شائعة

**س: هل يجب حذف الدوال الرسوميات؟**
ج: لا، يمكنك الاحتفاظ بها كخطة احتياطية.

**س: هل يمكن استخدام الصور + الرسوميات معاً؟**
ج: نعم! يمكنك استخدام الصور لبعض الشاشات والرسوميات للأخرى.

**س: ماذا لو كانت الصور بصيغ مختلفة؟**
ج: Flutter يدعم: PNG, JPEG, WebP, GIF

---

**هل تريد تحديث الملف الآن؟** 🚀
