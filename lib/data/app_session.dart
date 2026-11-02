import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// جلسة التطبيق: حساب المستخدم الحقيقي الذي دخل به من شاشة الدخول.
///
/// لكل مستخدم حسابه وبياناته؛ لا يوجد حساب مشترك. الدخول نفسه في
/// [FundlyAccount.signIn]، وهنا فقط التحقق من صلاحية الجلسة وتجديدها قبل
/// كل طلب للخادم.
class AppSession {
  AppSession._();

  static const _requestTimeout = Duration(seconds: 20);

  /// يمنع تجديدين متوازيين للجلسة عند الإقلاع (كل مستودع يستدعي
  /// [ensureSignedIn] مع أول طلب له، ولو انطلق تجديدان معًا لأبطل الأول
  /// رمز التجديد على الثاني).
  static Future<User>? _pending;

  /// يعيد المستخدم الحالي بجلسة صالحة، ويجدّدها إن انتهت. بلا جلسة يرمي
  /// خطأ «سجّل الدخول» بدل أن تعود الشاشات فارغة بلا سبب.
  static Future<User> ensureSignedIn() {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final current = client.auth.currentUser;
    if (current != null && session != null && !session.isExpired) {
      return Future.value(current);
    }
    return _pending ??= _refresh(client).whenComplete(() => _pending = null);
  }

  static Future<User> _refresh(SupabaseClient client) async {
    final session = client.auth.currentSession;
    if (session == null || session.refreshToken == null) {
      throw const AuthException('لم يتم تسجيل الدخول — سجّل الدخول بحسابك');
    }
    try {
      final refreshed = await client.auth.refreshSession().timeout(
        _requestTimeout,
      );
      final user = refreshed.user;
      if (user != null && refreshed.session != null) return user;
    } catch (error) {
      debugPrint('AppSession: refresh failed ($error)');
    }
    throw const AuthException(
      'انتهت جلسة الدخول — سجّل الخروج ثم ادخل بحسابك من جديد',
    );
  }

  /// وصف الجلسة الحالية بلغة مقروءة — يُعرض حين تعود الاستعلامات فارغة.
  static String describeSession() {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;
    if (user == null || session == null) {
      return 'لا توجد جلسة دخول — الخادم يردّ بلا بيانات.';
    }
    final account = user.email ?? 'بلا بريد';
    return session.isExpired
        ? 'الجلسة منتهية الصلاحية · $account'
        : 'الجلسة سارية · $account';
  }

  /// إغلاق الجلسة على هذا الجهاز.
  static Future<void> signOut() async {
    _pending = null;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // بلا اتصال: تُمسح الجلسة المحلية على الأقل.
    }
  }

  /// تجديد الجلسة الحالية ثم إعادة المحاولة (زر «إعادة الدخول» في شاشات
  /// الأصول). لا يغيّر الحساب.
  static Future<User> forceSignIn() async {
    _pending = null;
    return _refresh(Supabase.instance.client);
  }
}
