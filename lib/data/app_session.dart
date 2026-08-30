import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// جلسة التطبيق الموحّدة - دخول تلقائي بحساب مشترك.
///
/// جميع المستخدمين يدخلون بنفس الحساب (fundly.app.2026@gmail.com).
/// هذا يعني أن **جميع الأجهزة تشارك نفس البيانات** - أي تعديل من أي 
/// جهاز يظهر فوراً على جميع الأجهزة الأخرى.
/// 
/// **مثالي للاستخدام العائلي:** وزع ملف APK على عائلتك، وسيرى الجميع
/// نفس العقارات والالتزامات ويمكنهم التعديل عليها معاً.
///
/// **ملاحظة أمنية:** هذا الحل مناسب للاستخدام الخاص والعائلي فقط.
/// لا تشارك APK مع أشخاص خارج نطاق الثقة لأن الجميع سيصل لنفس البيانات.
class AppSession {
  AppSession._();

  static const _requestTimeout = Duration(seconds: 20);

  /// يمنع تنفيذ عمليتَي دخول متوازيتين عند إقلاع التطبيق (كل مستودع يستدعي
  /// [ensureSignedIn] عند أول طلب له، وقد تنطلق عدة طلبات معًا).
  static Future<User>? _pending;

  /// يضمن وجود جلسة **صالحة** بالحساب المشترك، ويعيد المستخدم الحالي.
  ///
  /// كان هذا التابع يقبل الجلسة المخزَّنة بمجرد تطابق البريد، دون فحص
  /// صلاحيتها. وهذا هو سبب اختفاء البيانات بعد يوم من التثبيت: رمز الدخول
  /// (access token) يعيش ساعة واحدة فقط، ورمز التجديد (refresh token) يُبطَل
  /// إن استُخدم من جهازين على نفس الحساب. وعند انتهاء الصلاحية تُرسَل
  /// الطلبات بلا هوية، فتصبح `auth.uid()` فارغة، فتُرجع سياسات الحماية
  /// (RLS) **صفر صفوف بلا أي رسالة خطأ** — فتبدو الشاشات فارغة كأن البيانات
  /// حُذفت، وهي سليمة في الخادم.
  ///
  /// الترتيب الآن: جلسة صالحة ← تجديدها ← دخول جديد بالحساب المشترك.
  static Future<User> ensureSignedIn() {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final current = client.auth.currentUser;
    // الجلسة القائمة تُقبل فقط إن كانت صالحة وغير منتهية وبالحساب المشترك
    if (current != null && 
        session != null && 
        !session.isExpired &&
        _isAppAccount(current)) {
      return Future.value(current);
    }
    // كل ما عدا ذلك يمر عبر [_pending]: عند الإقلاع تستدعي عدة مستودعات هذا
    // التابع في اللحظة نفسها، ولو انطلق تجديدان متوازيان لأبطل الأول رمز
    // التجديد على الثاني (تدوير الرموز) فصار العلاج سببًا للعطل.
    return _pending ??= _restore(client).whenComplete(() => _pending = null);
  }

  /// يتحقق من أن المستخدم هو الحساب المشترك للتطبيق
  static bool _isAppAccount(User user) {
    return user.email == SupabaseConfig.appAccountEmail;
  }

  /// يستعيد جلسة صالحة: تجديد الجلسة القائمة، وإلا دخول مجهول جديد.
  static Future<User> _restore(SupabaseClient client) async {
    final session = client.auth.currentSession;
    // جلسة موجودة وصالحة: تُجدَّد إن كانت منتهية
    if (session != null && session.refreshToken != null) {
      try {
        final refreshed = await client.auth.refreshSession().timeout(
          _requestTimeout,
        );
        final user = refreshed.user;
        if (user != null && refreshed.session != null) return user;
      } catch (error) {
        // رمز التجديد مبطَل أو الشبكة منقطعة: ننشئ جلسة مجهولة جديدة
        debugPrint('AppSession: refresh failed ($error) — creating anonymous session');
      }
    }
    return _signIn(client);
  }

  static Future<User> _signIn(SupabaseClient client) async {
    // دخول تلقائي بالحساب المشترك - جميع الأجهزة تستخدم نفس الحساب
    // وبالتالي تشارك نفس البيانات
    try {
      final response = await client.auth
          .signInWithPassword(
            email: SupabaseConfig.appAccountEmail,
            password: SupabaseConfig.appAccountPassword,
          )
          .timeout(_requestTimeout);
      final user = response.user;
      if (user != null) {
        debugPrint('AppSession: signed in as ${SupabaseConfig.appAccountEmail}');
        return user;
      }
      throw const AuthException('فشل تسجيل الدخول - لم يُرجع مستخدم');
    } on AuthException catch (error) {
      debugPrint('AppSession: sign-in failed (${error.message})');
      throw AuthException(
        'تعذّر الدخول للتطبيق. تأكد من:\n'
        '1. تفعيل Email Provider في Supabase\n'
        '2. وجود الحساب ${SupabaseConfig.appAccountEmail}\n'
        'الخطأ: ${error.message}',
      );
    }
  }
}
