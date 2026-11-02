import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// حالة الدخول على هذا الجهاز: مسجَّل بحسابه أو لا.
///
/// المفتاح v2: الحالة القديمة (الحساب المشترك والضيف) لا تُقرأ، فيظهر
/// لكل جهاز شاشة الدخول مرة واحدة ليدخل بحسابه الحقيقي.
class FundlyAuth {
  FundlyAuth._();

  static const String _key = 'fundly_login_mode_v2';
  static const String modeUser = 'user';
  static const String modeGuest = 'guest';

  /// null: لم يدخل بعد، فتظهر شاشة الدخول.
  static String? mode;

  /// اختيار اللغة عند أول فتح للتطبيق على هذا الجوال (مرة واحدة فقط).
  static const String _languageKey = 'fundly_language_chosen';
  static bool languageChosen = false;

  /// يزيد مع كل دخول أو خروج، فيُبنى التطبيق من جديد بلا بقايا الحساب
  /// السابق في الشاشات المفتوحة.
  static final ValueNotifier<int> sessionEpoch = ValueNotifier(0);

  static bool get isGuest => mode == modeGuest;

  /// مسجَّل الدخول فعلًا: حالة محفوظة وجلسة في Supabase.
  static bool get isSignedIn =>
      mode == modeUser && Supabase.instance.client.auth.currentSession != null;

  /// يُعيَّن في main.dart: يعرض «سجّل الدخول للمتابعة» ثم شاشة الدخول،
  /// ويُعيد true إن سجّل الدخول.
  static Future<bool> Function(BuildContext context)? loginPrompt;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode = prefs.getString(_key);
      languageChosen = prefs.getBool(_languageKey) ?? false;
    } catch (_) {
      mode = null;
    }
    if (mode == modeUser && !isSignedIn) mode = null;
    // من دخل بحسابه قبل هذا التحديث: لا يُسأل عن اللغة من جديد.
    if (isSignedIn) languageChosen = true;
    // جلسة قديمة (الحساب المشترك) بلا دخول بالحساب الجديد: تُغلق.
    if (mode == null &&
        Supabase.instance.client.auth.currentSession != null) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // بلا اتصال: شاشة الدخول ستستبدلها بجلسة الحساب الجديد.
      }
    }
  }

  static Future<void> setMode(String value) async {
    mode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value);
    } catch (_) {
      // تعذّر الحفظ لا يمنع الدخول في هذه الجلسة.
    }
  }

  /// بعد اختيار اللغة أول مرة: لا تظهر شاشة اللغة على هذا الجوال بعدها.
  static Future<void> markLanguageChosen() async {
    languageChosen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_languageKey, true);
    } catch (_) {
      // تعذّر الحفظ لا يمنع المتابعة في هذه الجلسة.
    }
  }

  static Future<void> clearMode() async {
    mode = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // يكفي مسحها من الذاكرة لهذه الجلسة.
    }
  }

  /// إعادة بناء التطبيق كاملًا (بعد الخروج يظهر الدخول من جديد).
  static void restartApp() => sessionEpoch.value++;

  /// قبل أي عملية: المسجَّل يمرّ، والضيف يُطلب منه تسجيل الدخول.
  static Future<bool> requireLogin(BuildContext context) async {
    if (!isGuest) return true;
    final prompt = loginPrompt;
    if (prompt == null) return true;
    return prompt(context);
  }
}
