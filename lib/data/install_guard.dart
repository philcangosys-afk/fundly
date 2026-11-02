import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'custody_sharing.dart';
import 'fundly_auth.dart';

/// حذف التطبيق ثم تثبيته يجب أن يُظهر شاشة الدخول.
///
/// بعض الجوالات تُبقي بيانات التطبيق بعد حذفه (خيار «الاحتفاظ بالبيانات»
/// أو «أرشفة التطبيق» أو استعادة نسخة احتياطية)، فتعود الجلسة القديمة
/// ويدخل مباشرة. هنا يُقارَن وقت التثبيت الأول للتطبيق بالمحفوظ على الجهاز:
/// إن اختلف فهذا تثبيت جديد، فتُغلق الجلسة القديمة. التحديث فوق النسخة
/// القائمة لا يغيّر وقت التثبيت الأول، فلا يخرج المستخدم عند التحديث.
class InstallGuard {
  InstallGuard._();

  static const _channel = MethodChannel('fundly/install');
  static const _key = 'fundly_install_first_time';

  /// وقت التثبيت الأول لهذه النسخة المثبّتة (يتغيّر بعد حذف التطبيق
  /// وتثبيته من جديد) — تُربط به أذونات الإشعارات لتُطلب بعد كل تثبيت.
  static int? firstInstallTime;

  static Future<void> check() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final times = await _channel.invokeMapMethod<String, dynamic>(
        'installTimes',
      );
      final first = times?['first'];
      final last = times?['last'];
      if (first is! int) return;
      firstInstallTime = first;
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key);
      if (saved == first) return;
      await prefs.setInt(_key, first);
      // لا وقت محفوظ: إما أول تشغيل لهذه النسخة بعد تحديث (يبقى داخلًا)،
      // أو تثبيت جديد بلا تحديث بعده (وقت التحديث = وقت التثبيت).
      if (saved == null && last is int && last != first) return;
      await _closeOldSession();
    } catch (error) {
      debugPrint('InstallGuard: $error');
    }
  }

  static Future<void> _closeOldSession() async {
    await FundlyAuth.clearMode();
    await AppIdentity.clear();
    try {
      await Supabase.instance.client.auth.signOut().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      // بلا اتصال: بلا «وضع الدخول» تظهر شاشة الدخول على أي حال.
    }
  }
}
