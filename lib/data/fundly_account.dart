import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_language.dart';
import 'app_session.dart';
import 'app_settings.dart';
import 'custody_sharing.dart';
import 'fundly_auth.dart';
import 'fundly_files.dart';
import 'fundly_notifications.dart';
import 'fundly_push.dart';
import 'home_layout_store.dart';
import 'page_customization_store.dart';

/// خطأ بلغة المستخدم يُعرض كما هو في شاشة الدخول أو الإعدادات.
class FundlyAccountException implements Exception {
  const FundlyAccountException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// طلب وصل من حساب آخر (عهدة، دعوة رحلة أو مشاركة...).
class FundlyInboxItem {
  const FundlyInboxItem({
    required this.id,
    required this.senderName,
    required this.senderFnd,
    required this.source,
    required this.entryType,
    required this.title,
    required this.createdAt,
    this.action = 'invite',
    this.recordId = '',
    this.note = '',
  });

  /// تفاصيل النشاط (JSON): نوعه، اسم المصروف أو العضو، المبلغ، العملة.
  final String note;

  /// نشاط في التزام مشترك: عضو أضاف مصروفًا أو رصيدًا — للاطلاع فقط.
  bool get isActivity => action == 'activity';

  /// للاطلاع بلا قبول أو رفض: الردود والأنشطة.
  bool get isInfo => isResponse || isActivity;

  /// «زين أضاف مصروفًا «غداء» — 500 درهم».
  String get activityText {
    var data = const <dynamic, dynamic>{};
    try {
      final decoded = jsonDecode(note);
      if (decoded is Map) data = decoded;
    } catch (_) {}
    final kind = '${data['kind'] ?? ''}';
    final name = '${data['name'] ?? ''}'.trim();
    final value = double.tryParse('${data['amount'] ?? ''}') ?? 0;
    final amount = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    final currency = '${data['currency'] ?? ''}'.trim();
    final money = value > 0
        ? ' — $amount${currency.isEmpty ? '' : ' ${AppTr.tr(currency)}'}'
        : '';
    final pending = '${data['status'] ?? ''}' == 'بانتظار الموافقة'
        ? ' (${AppTr.tr('بانتظار موافقة المسؤول')})'
        : '';
    // المفوَّض بإدارة عقار/مركبة/نشاط: «فلان أضاف عقدًا «شقة 1 — أحمد» —
    // 50000 · بناية مصفح».
    // تغيير في تفويض: «زين: تمديد التفويض حتى 01/12/2027 · العقارات».
    // سند قبض وقّعه الموظف على جوال صاحب العمل: نسخة للاطلاع.
    if (kind == 'salary') {
      final what = '${data['what'] ?? ''}'.trim();
      return '$sender ${AppTr.tr(what)} · $title';
    }
    if (kind == 'delegation_change') {
      final what = '${data['what'] ?? ''}'.trim();
      final where = title.trim().isEmpty ? '' : ' · $title';
      return '$sender: ${AppTr.tr(what)}$where';
    }
    if (kind == 'delegate') {
      final what = '${data['what'] ?? ''}'.trim();
      final where = title.trim().isEmpty ? '' : ' · $title';
      return '$sender (${AppTr.tr('مفوَّض')}) ${AppTr.tr(what)}'
          '${name.isEmpty ? '' : ' «$name»'}$money$where';
    }
    if (kind == 'contribution') {
      final forWho = name.isEmpty || name == senderName.trim()
          ? ''
          : ' ${AppTr.tr('باسم')} $name';
      return '$sender ${AppTr.tr('أضاف رصيدًا')}$forWho$money$pending';
    }
    return '$sender ${AppTr.tr('أضاف مصروفًا')}'
        '${name.isEmpty ? '' : ' «$name»'}$money$pending';
  }

  /// السجل الذي يخصه الإشعار (للحذف أو الأرشفة عندي من الإشعار نفسه).
  final String recordId;

  /// عضو أرشف الالتزام المشترك أو حذفه من عنده.
  bool get isHideNotice => action == 'archived' || action == 'removed';

  /// invite: طلب جديد لك. accepted / rejected: رد الطرف الآخر على ما أرسلته.
  final String action;

  bool get isResponse => action == 'accepted' || action == 'rejected';

  final String id;
  final String senderName;
  final String senderFnd;

  /// الجدول الذي جاء منه الطلب: personal_entries أو shared_entries.
  final String source;
  final String entryType;
  final String title;
  final DateTime? createdAt;

  /// اسم المرسل، أو رقمه التعريفي إن لم يكتب اسمه.
  String get sender => senderName.trim().isEmpty ? senderFnd : senderName;

  factory FundlyInboxItem.fromJson(Map<String, dynamic> json) =>
      FundlyInboxItem(
        id: '${json['id']}',
        senderName: '${json['sender_name'] ?? ''}',
        senderFnd: '${json['sender_fnd'] ?? ''}',
        source: '${json['source'] ?? ''}',
        entryType: '${json['entry_type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
        action: '${json['action'] ?? 'invite'}',
        recordId: '${json['record_id'] ?? ''}',
        note: '${json['note'] ?? ''}',
      );
}

/// الحساب الحقيقي: الدخول والخروج، الرقم التعريفي من الخادم، صندوق
/// الطلبات، تغيير كلمة المرور، والنسخة السحابية لبيانات الجهاز.
class FundlyAccount {
  FundlyAccount._();

  static const _timeout = Duration(seconds: 20);
  static const _kLastUser = 'fundly_last_user_id';
  static const _kIdNoticePrefix = 'fundly_id_notice_';

  /// إعدادات تخص الجهاز نفسه: لا تُمسح عند تبديل الحساب ولا تُنسخ للسحابة.
  static const _deviceKeys = {
    'settings_language',
    'settings_text_scale',
    'settings_compact_lists',
    'settings_app_lock',
    'settings_app_lock_pin',
    'settings_notifications_enabled',
    'settings_expiry_notifications',
    'settings_user_id',
  };

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  /// مفاتيح داخلية: جلسة الدخول ومفاتيح هذا الملف.
  static bool _isInternal(String key) =>
      key.startsWith('sb-') ||
      key.contains('supabase') ||
      key.startsWith('fundly_');

  /// ما يُعدّ بيانات المستخدم (يُنسخ للسحابة ويُمسح عند تبديل الحساب).
  static bool _isUserData(String key) =>
      !_deviceKeys.contains(key) && !_isInternal(key);

  // ---------------------------------------------------------------
  // الدخول والخروج
  // ---------------------------------------------------------------

  /// [method]: `email` أو `phone` أو `id`.
  static Future<void> signIn({
    required String method,
    required String value,
    required String password,
  }) async {
    final input = value.trim();
    if (input.isEmpty) {
      throw FundlyAccountException(
        switch (method) {
          'phone' => 'أدخل رقم الهاتف',
          'id' => 'أدخل الرقم التعريفي',
          _ => 'أدخل البريد الإلكتروني',
        },
      );
    }
    if (password.isEmpty) {
      throw const FundlyAccountException('أدخل كلمة المرور');
    }
    try {
      final email = await _emailFor(method, input);
      await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(_timeout);
    } on FundlyAccountException {
      rethrow;
    } on AuthException catch (error) {
      throw FundlyAccountException(_authMessage(error));
    } on PostgrestException catch (error) {
      throw FundlyAccountException('خطأ من الخادم: ${error.message}');
    } on TimeoutException {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
    await _afterSignIn();
  }

  /// البريد المرتبط بالحساب: كما هو، أو من الخادم للهاتف والرقم التعريفي.
  static Future<String> _emailFor(String method, String input) async {
    if (method == 'email') return input.trim().toLowerCase();
    final found = await _client
        .rpc('fundly_login_email', params: {'p_identifier': input})
        .timeout(_timeout);
    final email = (found as String? ?? '').trim();
    if (email.isEmpty) {
      throw FundlyAccountException(
        method == 'id'
            ? 'لا يوجد حساب بهذا الرقم التعريفي'
            : 'لا يوجد حساب بهذا الرقم — أضف رقمك في البيانات الشخصية بعد الدخول بالبريد',
      );
    }
    return email;
  }

  /// طريقة الإدخال من شكله: بريد، رقم تعريفي، أو هاتف.
  static String methodOf(String input) {
    final text = input.trim().toUpperCase();
    if (text.contains('@')) return 'email';
    if (text.startsWith('FND')) return 'id';
    return 'phone';
  }

  /// إنشاء حساب جديد. يعيد true إن دخل مباشرة، وfalse إن كان البريد
  /// يحتاج تفعيلًا من الرابط المرسل أولًا.
  static Future<bool> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    if (name.trim().isEmpty) {
      throw const FundlyAccountException('أدخل الاسم أولًا');
    }
    if (!mail.contains('@') || !mail.contains('.')) {
      throw const FundlyAccountException('صيغة البريد الإلكتروني غير صحيحة');
    }
    if (password.length < 6) {
      throw const FundlyAccountException('كلمة المرور قصيرة — 6 أحرف على الأقل');
    }
    AuthResponse response;
    try {
      if (phone.trim().isNotEmpty) {
        final taken = await _client
            .rpc('fundly_login_email', params: {'p_identifier': phone})
            .timeout(_timeout);
        if ('${taken ?? ''}'.trim().isNotEmpty) {
          throw const FundlyAccountException(
            'رقم الهاتف مستخدم في حساب آخر',
          );
        }
      }
      response = await _client.auth
          .signUp(email: mail, password: password, data: {'name': name.trim()})
          .timeout(_timeout);
    } on FundlyAccountException {
      rethrow;
    } on AuthException catch (error) {
      throw FundlyAccountException(_authMessage(error));
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
    if (response.session == null) return false;
    await _afterSignIn();
    final settings = AppSettings.instance;
    await settings.saveProfile(
      name: name.trim(),
      phone: phone.trim(),
      email: mail,
      city: settings.city,
      social: settings.social,
      photo: settings.photo,
    );
    await pushProfile(name: name, phone: phone);
    return true;
  }

  /// نسيت كلمة المرور (1): يُرسل رمز من أرقام إلى البريد المرتبط بالحساب.
  /// يعيد البريد الذي أُرسل إليه.
  static Future<String> sendResetCode(String identifier) async {
    final input = identifier.trim();
    if (input.isEmpty) {
      throw const FundlyAccountException(
        'أدخل البريد أو رقم الهاتف أو الرقم التعريفي',
      );
    }
    try {
      final email = await _emailFor(methodOf(input), input);
      await _client.auth.resetPasswordForEmail(email).timeout(_timeout);
      return email;
    } on FundlyAccountException {
      rethrow;
    } on AuthException catch (error) {
      throw FundlyAccountException(_authMessage(error));
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
  }

  /// نسيت كلمة المرور (2): الرمز ثم كلمة المرور الجديدة، ويدخل مباشرة.
  static Future<void> resetWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final token = code.replaceAll(RegExp(r'\s'), '');
    if (token.length < 6) {
      throw const FundlyAccountException('أدخل الرمز المرسل إلى بريدك');
    }
    if (newPassword.length < 6) {
      throw const FundlyAccountException('كلمة المرور قصيرة — 6 أحرف على الأقل');
    }
    try {
      await _client.auth
          .verifyOTP(email: email, token: token, type: OtpType.recovery)
          .timeout(_timeout);
    } on AuthException {
      throw const FundlyAccountException('الرمز غير صحيح أو انتهت صلاحيته');
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
    try {
      await _client.auth
          .updateUser(UserAttributes(password: newPassword))
          .timeout(_timeout);
    } on AuthException catch (error) {
      throw FundlyAccountException(_authMessage(error));
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
    await _afterSignIn();
  }

  static String _authMessage(AuthException error) {
    final text = error.message.toLowerCase();
    if (text.contains('invalid login') || text.contains('invalid credentials')) {
      return 'بيانات الدخول أو كلمة المرور غير صحيحة';
    }
    if (text.contains('email not confirmed')) {
      return 'البريد غير مفعّل بعد';
    }
    if (text.contains('different from the old')) {
      return 'كلمة المرور الجديدة يجب أن تختلف عن الحالية';
    }
    if (text.contains('at least')) {
      return 'كلمة المرور قصيرة — 6 أحرف على الأقل';
    }
    if (text.contains('already registered') || text.contains('already exists')) {
      return 'هذا البريد مسجّل مسبقًا — سجّل الدخول به';
    }
    if (text.contains('rate limit') || text.contains('too many')) {
      return 'محاولات كثيرة — انتظر قليلًا ثم أعد المحاولة';
    }
    return error.message;
  }

  /// بعد الدخول: بيانات الجهاز لحساب آخر تُمسح، ثم تُنزَّل نسخة الحساب
  /// من السحابة، ويُقرأ الرقم التعريفي والاسم من الخادم.
  static Future<void> _afterSignIn() async {
    final user = currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastUser) != user.id) {
      await _clearUserData(prefs);
      await prefs.setString(_kLastUser, user.id);
    }
    await syncCloud();
    await AppSettings.instance.load();
    await refreshProfile();
    HomeLayoutStore.invalidate();
    await PageCustomizationStore.load();
    await FundlyAuth.setMode(FundlyAuth.modeUser);
    startAutoSync();
    // الملفات: تنزيل ما ليس على الجهاز ثم رفع الجديد، في الخلفية.
    unawaited(
      FundlyFiles.syncDown(force: true).then((_) => FundlyFiles.syncUp()),
    );
  }

  static Future<void> _clearUserData(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().toList()) {
      if (_isUserData(key)) await prefs.remove(key);
    }
    await prefs.remove('settings_user_id');
    // أساس المزامنة لأي حساب سابق يُمسح مع بياناته، وإلا ظنّت المزامنة أن
    // البيانات حُذفت هنا فحذفتها من السحابة.
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_kBasePrefix) || key.startsWith(_kSeenPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// قبل الخروج: رفع آخر التعديلات والملفات. true إن رُفع كل شيء.
  static Future<bool> uploadBeforeSignOut() async {
    try {
      await pushCloud().timeout(_timeout);
      await FundlyFiles.syncUp().timeout(_timeout);
    } catch (_) {
      return false;
    }
    return lastSyncError == null;
  }

  /// خروج: تُرفع آخر التعديلات (إلا إن رُفعت قبلها [uploaded])، ثم تُغلق
  /// الجلسة وتُمسح بيانات الحساب من الجوال — من يتصفّح بعده كضيف لا يرى
  /// شيئًا منها، وتنزل كاملة من السحابة عند الدخول التالي.
  static Future<void> signOut({bool uploaded = false}) async {
    if (!uploaded) {
      try {
        await pushCloud().timeout(_timeout);
        await FundlyFiles.syncUp().timeout(_timeout);
      } catch (_) {
        // بلا اتصال: يُكمل الخروج.
      }
    }
    // تذكيرات هذا الحساب لا تصل بعد خروجه.
    await FundlyNotifications.cancelAll();
    // إشعارات Firebase لهذا الحساب لا تصل لهذا الجهاز بعد خروجه.
    await FundlyPush.unregister();
    await AppSession.signOut();
    await AppIdentity.clear();
    await _clearAfterSignOut();
    await FundlyAuth.clearMode();
    FundlyAuth.restartApp();
  }

  /// بعد إغلاق الجلسة: بيانات الحساب وإعداداته تُمسح من الجوال (اللغة
  /// وإعدادات الجهاز تبقى).
  static Future<void> _clearAfterSignOut() async {
    try {
      final running = _syncing;
      if (running != null) await running;
      final prefs = await SharedPreferences.getInstance();
      await _clearUserData(prefs);
      await prefs.remove(_kLastUser);
      await AppSettings.instance.load();
      HomeLayoutStore.invalidate();
      await PageCustomizationStore.load();
    } catch (_) {
      // لا يوقف الخروج.
    }
  }

  /// تغيير كلمة المرور بعد التحقق من الحالية.
  static Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    final email = currentUser?.email;
    if (email == null || email.isEmpty) {
      throw const FundlyAccountException('سجّل الدخول أولًا');
    }
    if (next.length < 6) {
      throw const FundlyAccountException('كلمة المرور قصيرة — 6 أحرف على الأقل');
    }
    try {
      await _client.auth
          .signInWithPassword(email: email, password: current)
          .timeout(_timeout);
    } on AuthException {
      throw const FundlyAccountException('كلمة المرور الحالية غير صحيحة');
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
    try {
      await _client.auth
          .updateUser(UserAttributes(password: next))
          .timeout(_timeout);
    } on AuthException catch (error) {
      throw FundlyAccountException(_authMessage(error));
    } catch (_) {
      throw const FundlyAccountException('تعذّر الاتصال بالخادم — تحقق من الإنترنت');
    }
  }

  // ---------------------------------------------------------------
  // الملف الشخصي والرقم التعريفي
  // ---------------------------------------------------------------

  /// الاسم الظاهر لصاحب رقم تعريفي (من الخادم)، أو null إن لم يوجد.
  static Future<String?> nameForFnd(String fnd) async {
    if (currentUser == null) return null;
    try {
      final result = await _client
          .rpc('fundly_name_by_fnd', params: {'p_fnd': fnd})
          .timeout(_timeout);
      final name = '${result ?? ''}'.trim();
      return name.isEmpty || name == 'null' ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// يقرأ الرقم التعريفي والاسم والهاتف من الخادم، ويكمل البيانات
  /// الشخصية الفارغة على الجهاز.
  static Future<void> refreshProfile() async {
    final user = currentUser;
    if (user == null) return;
    try {
      final row = await _client
          .from('profiles')
          .select('fnd_id, display_name, phone')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_timeout);
      if (row == null) return;
      final fnd = '${row['fnd_id'] ?? ''}'.trim();
      if (fnd.isNotEmpty) await AppIdentity.setFromServer(fnd);
      final settings = AppSettings.instance;
      final serverName = '${row['display_name'] ?? ''}'.trim();
      final serverPhone = '${row['phone'] ?? ''}'.trim();
      final localName = settings.name == AppSettings.defaultName
          ? ''
          : settings.name;
      final name = localName.isNotEmpty ? localName : serverName;
      final phone = settings.phone.isNotEmpty ? settings.phone : serverPhone;
      final email = settings.email.isNotEmpty
          ? settings.email
          : (user.email ?? '');
      if (name != localName ||
          phone != settings.phone ||
          email != settings.email) {
        await settings.saveProfile(
          name: name,
          phone: phone,
          email: email,
          city: settings.city,
          social: settings.social,
          photo: settings.photo,
        );
      }
    } catch (_) {
      // بلا اتصال: يبقى الرقم المحفوظ على الجهاز.
    }
  }

  /// الاسم والهاتف على الخادم: الاسم يظهر للطرف الآخر في الطلبات،
  /// والهاتف يُستعمل للدخول به.
  static Future<void> pushProfile({
    required String name,
    required String phone,
  }) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await _client
          .from('profiles')
          // ما يراه الآخرون: الاسم الثلاثي أو الأول فقط أو المستعار.
          .update({
            'display_name': AppSettings.instance.publicName.trim().isEmpty
                ? name.trim()
                : AppSettings.instance.publicName.trim(),
            'phone': phone.trim(),
          })
          .eq('id', user.id)
          .timeout(_timeout);
    } catch (_) {
      // يُعاد عند الحفظ التالي.
    }
  }

  /// تنبيه «رقمك التعريفي في المزيد» يظهر مرة واحدة لكل حساب.
  static Future<bool> takeIdNotice() async {
    final user = currentUser;
    if (user == null || AppIdentity.id.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kIdNoticePrefix${user.id}';
    if (prefs.getBool(key) ?? false) return false;
    await prefs.setBool(key, true);
    return true;
  }

  // ---------------------------------------------------------------
  // صندوق الطلبات
  // ---------------------------------------------------------------

  static Future<List<FundlyInboxItem>> pendingInbox() async {
    final user = currentUser;
    if (user == null) return const [];
    try {
      final rows = await _client
          .from('fundly_inbox')
          // كل الأعمدة: عمود note يُقرأ إن وُجد، ولا يفشل الطلب قبل إضافته.
          .select()
          .eq('recipient_id', user.id)
          .eq('status', 'new')
          .order('created_at', ascending: false)
          .limit(30)
          .timeout(_timeout);
      return [for (final row in rows) FundlyInboxItem.fromJson(row)];
    } catch (_) {
      return const [];
    }
  }

  /// يزيد عند وصول طلب أو رد جديد — تستمع له الرئيسية فتعرض النافذة.
  static final ValueNotifier<int> inboxArrivals = ValueNotifier<int>(0);

  static const _notifiedKey = 'fundly_inbox_notified';

  /// معرّفات الطلبات التي ظهر إشعارها (مشتركة مع إشعارات Firebase).
  static const notifiedKey = _notifiedKey;

  /// عنوان إشعار الطلب ونصه — للفحص الدوري ولإشعارات Firebase معًا.
  static (String, String) inboxNotice(FundlyInboxItem item) => (
    item.isActivity
        ? '${AppTr.tr('إضافة جديدة')} — ${item.title}'
        : AppTr.tr(
            item.isResponse || item.isHideNotice
                ? 'رد على ما أرسلته'
                : 'وصلك طلب جديد',
          ),
    _inboxText(item),
  );

  /// كل 30 ثانية والتطبيق مفتوح: ما وصل جديدًا يظهر إشعارًا بصوت في
  /// الستارة، وتُفتح نافذة الطلبات داخل التطبيق.
  static Future<void> pollInbox() async {
    if (currentUser == null) return;
    final items = await pendingInbox();
    if (items.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // إشعار Firebase في الخلفية يسجّل من عزلة أخرى: يُقرأ الأحدث.
      await prefs.reload();
      final done = (prefs.getStringList(_notifiedKey) ?? const <String>[])
          .toList();
      final fresh = [
        for (final item in items)
          if (!done.contains(item.id)) item,
      ];
      if (fresh.isEmpty) return;
      for (final item in fresh) {
        final (title, body) = inboxNotice(item);
        await FundlyNotifications.showNow(
          key: 'inbox_${item.id}',
          title: title,
          body: body,
        );
        done.add(item.id);
      }
      if (done.length > 300) done.removeRange(0, done.length - 300);
      await prefs.setStringList(_notifiedKey, done);
      inboxArrivals.value++;
    } catch (_) {
      // يُعاد في الدورة التالية.
    }
  }

  static String _inboxText(FundlyInboxItem item) {
    final who = item.sender;
    final title = item.title.trim().isEmpty ? '' : ' «${item.title}»';
    if (item.isActivity) return item.activityText;
    if (item.isHideNotice) {
      return '$who ${AppTr.tr(item.action == 'removed' ? 'حذف هذا الالتزام من عنده' : 'أرشف هذا الالتزام عنده')}$title';
    }
    if (item.isResponse) {
      return '$who ${AppTr.tr(item.action == 'accepted' ? 'قبِل' : 'رفضَ')} '
          '${AppTr.tr(item.entryType)}$title';
    }
    if (item.source == 'delegations') return '${AppTr.tr('فوّضك')} $who';
    if (item.source == 'shared_entries') {
      return '${AppTr.tr('دعاك')} $who ${AppTr.tr('للمشاركة في')}$title';
    }
    if (item.entryType.contains('عهدة')) {
      return '${AppTr.tr('أسند إليك')} $who ${AppTr.tr('عهدة مالية')}$title';
    }
    return '${AppTr.tr('أرسل إليك')} $who ${AppTr.tr(item.entryType)}$title';
  }

  /// بعد الرد على دعوة من داخل القسم: طلبها في «الطلبات» لم يعد جديدًا،
  /// فلا تعود نافذته عند الفتح التالي.
  static Future<void> markSeenForRecord(String recordId) async {
    final user = currentUser;
    if (user == null || recordId.trim().isEmpty) return;
    try {
      await _client
          .from('fundly_inbox')
          .update({
            'status': 'seen',
            'seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('recipient_id', user.id)
          .eq('record_id', recordId)
          .eq('action', 'invite')
          .eq('status', 'new')
          .timeout(_timeout);
    } catch (_) {}
  }

  static Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client
          .from('fundly_inbox')
          .update({
            'status': 'seen',
            'seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('id', ids)
          .timeout(_timeout);
    } catch (_) {
      // يبقى «جديدًا» ويظهر مرة أخرى عند الفتح التالي.
    }
  }

  // ---------------------------------------------------------------
  // مزامنة بيانات الجهاز مع السحابة (الأفراد، التقويم، التذكيرات...)
  // ---------------------------------------------------------------
  //
  // كل جوال يحفظ «آخر نسخة متفق عليها» لكل مفتاح (الأساس). عند المزامنة:
  // ما تغيّر هنا فقط يُرفع، وما تغيّر في السحابة فقط يُنزَّل، وما تغيّر في
  // الطرفين يُدمج سجلًا سجلًا. كان كل جوال يرفع نسخته كاملة فوق السحابة
  // ولا ينزّل إلا عند الدخول، فيمسح جوالٌ قديم ما أضافه جوال آخر.

  static const _storeTable = 'fundly_user_store';
  static const _kBasePrefix = 'fundly_sync_base_';
  static const _kSeenPrefix = 'fundly_sync_seen_';

  /// يزيد كلما نزلت من السحابة تغييرات إلى هذا الجوال — الشاشات المفتوحة
  /// التي تحفظ قوائمها من الذاكرة تستمع إليه فتعيد القراءة.
  static final ValueNotifier<int> cloudRevision = ValueNotifier<int>(0);

  static Future<void>? _syncing;
  static bool _syncAgain = false;

  /// آخر مزامنة ناجحة، وآخر خطأ حقيقي (كان يُبلع بصمت فلا يُعرف لماذا لا
  /// تظهر البيانات في الجوال الآخر). تُعرض في «الإعدادات ← مزامنة البيانات».
  static DateTime? lastSyncAt;
  static String? lastSyncError;
  static final ValueNotifier<int> syncStatus = ValueNotifier<int>(0);

  /// أعداد سجلات هذا الحساب في الخادم — للمقارنة بين جوالين.
  static Future<Map<String, int>> serverCounts() async {
    final user = currentUser;
    final out = <String, int>{};
    if (user == null) return out;
    for (final table in const [
      'personal_entries',
      'shared_entries',
      'project_assets',
      _storeTable,
    ]) {
      try {
        final rows = await _client
            .from(table)
            .select(table == _storeTable ? 'key' : 'id')
            .eq('user_id', user.id)
            .timeout(_timeout);
        out[table] = rows.length;
      } catch (_) {
        out[table] = -1;
      }
    }
    return out;
  }

  /// عدد مفاتيح بيانات المستخدم على هذا الجوال.
  static Future<int> localKeyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where(_isUserData).length;
  }
  static AppLifecycleListener? _lifecycle;
  static Timer? _timer;

  static String? _encode(Object? value) {
    if (value is String) return jsonEncode({'t': 's', 'v': value});
    if (value is bool) return jsonEncode({'t': 'b', 'v': value});
    if (value is int) return jsonEncode({'t': 'i', 'v': value});
    if (value is double) return jsonEncode({'t': 'd', 'v': value});
    if (value is List) {
      return jsonEncode({'t': 'l', 'v': [for (final v in value) '$v']});
    }
    return null;
  }

  static Future<void> _write(
    SharedPreferences prefs,
    String key,
    String raw,
  ) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final v = decoded['v'];
      switch (decoded['t']) {
        case 's':
          await prefs.setString(key, '$v');
        case 'b':
          if (v is bool) await prefs.setBool(key, v);
        case 'i':
          if (v is num) await prefs.setInt(key, v.toInt());
        case 'd':
          if (v is num) await prefs.setDouble(key, v.toDouble());
        case 'l':
          if (v is List) {
            await prefs.setStringList(key, [for (final e in v) '$e']);
          }
      }
    } catch (_) {
      // قيمة تالفة لا توقف المزامنة.
    }
  }

  static Map<String, String> _readMap(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  // ---------------- الدمج ----------------

  /// هوية السجل داخل قائمة: معرّفه، أو اسمه الكامل (الأفراد والجهات)،
  /// وإلا نصّه كله.
  static String _identity(Object? item) {
    if (item is Map) {
      for (final field in const ['id', 'fullName']) {
        final value = item[field];
        if (value != null && '$value'.trim().isNotEmpty) {
          return '$field:$value';
        }
      }
      return jsonEncode(item);
    }
    if (item is String) {
      final text = item.trim();
      if (text.startsWith('{')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) return _identity(decoded);
        } catch (_) {
          // نص عادي.
        }
      }
      return 's:$item';
    }
    return jsonEncode(item);
  }

  static String _text(Object? item) =>
      item is String ? item : jsonEncode(item);

  /// دمج ثلاثي لقائمتين بأساسهما: سجل تغيّر في طرف واحد يأخذ تغييره،
  /// وسجل أُضيف في أي طرف يبقى، والمحذوف في طرف لم يُعدَّل في الآخر يُحذف.
  /// سجل عُدِّل في الطرفين: يبقى تعديل هذا الجوال.
  static List<Object?> _mergeItems(
    List<Object?> local,
    List<Object?> server,
    List<Object?>? base,
  ) {
    var idOf = _identity;
    bool unique(List<Object?> list) =>
        list.map(idOf).toSet().length == list.length;
    // هويات مكررة (اسم مكرر مثلًا): يُقارن بالنص كاملًا حتى لا يضيع سجل.
    if (!unique(local) || !unique(server) || !(base == null || unique(base))) {
      idOf = _text;
    }
    Map<String, Object?> index(List<Object?> list) => {
      for (final item in list) idOf(item): item,
    };
    final li = index(local);
    final si = index(server);
    final bi = base == null ? <String, Object?>{} : index(base);
    final out = <Object?>[];
    for (final id in <String>{...li.keys, ...si.keys}) {
      final lt = li.containsKey(id) ? _text(li[id]) : null;
      final st = si.containsKey(id) ? _text(si[id]) : null;
      final bt = bi.containsKey(id) ? _text(bi[id]) : null;
      String? pick;
      if (lt == st || st == bt) {
        pick = lt;
      } else if (lt == bt) {
        pick = st;
      } else if (base == null) {
        // أول مزامنة بلا أساس: نسخة السحابة هي آخر ما رُفع، فتُقدَّم.
        pick = st ?? lt;
      } else {
        // تغيّر في الطرفين، أو حُذف في طرف وعُدّل في الآخر: لا يضيع.
        pick = lt ?? st;
      }
      if (pick == null) continue;
      out.add(pick == lt ? li[id] : si[id]);
    }
    return out;
  }

  /// دمج نصّين بصيغة JSON (قائمة سجلات أو خريطة)، أو null إن لم يكونا كذلك.
  static String? _mergeJsonText(String local, String server, String? base) {
    final l = local.trim();
    final s = server.trim();
    if (!(l.startsWith('[') || l.startsWith('{'))) return null;
    try {
      final ld = jsonDecode(l);
      final sd = jsonDecode(s);
      Object? bd;
      if (base != null && base.trim().isNotEmpty) {
        try {
          bd = jsonDecode(base);
        } catch (_) {
          bd = null;
        }
      }
      if (ld is List && sd is List) {
        return jsonEncode(
          _mergeItems(
            List<Object?>.of(ld),
            List<Object?>.of(sd),
            bd is List ? List<Object?>.of(bd) : null,
          ),
        );
      }
      if (ld is Map && sd is Map) {
        final Map bm = bd is Map ? bd : const <String, Object?>{};
        final out = <String, Object?>{};
        for (final key in <String>{
          for (final k in ld.keys) '$k',
          for (final k in sd.keys) '$k',
        }) {
          final lt = ld.containsKey(key) ? jsonEncode(ld[key]) : null;
          final st = sd.containsKey(key) ? jsonEncode(sd[key]) : null;
          final bt = bm.containsKey(key) ? jsonEncode(bm[key]) : null;
          if (lt == st || st == bt) {
            if (lt != null) out[key] = ld[key];
          } else if (lt == bt) {
            if (st != null) out[key] = sd[key];
          } else if (ld[key] is List && sd[key] is List) {
            out[key] = _mergeItems(
              List<Object?>.of(ld[key] as List),
              List<Object?>.of(sd[key] as List),
              bm[key] is List ? List<Object?>.of(bm[key] as List) : null,
            );
          } else if (bd == null) {
            out[key] = sd.containsKey(key) ? sd[key] : ld[key];
          } else {
            out[key] = ld.containsKey(key) ? ld[key] : sd[key];
          }
        }
        return jsonEncode(out);
      }
    } catch (_) {
      // ليس JSON صالحًا.
    }
    return null;
  }

  /// قيمة تغيّرت هنا وفي السحابة معًا (بصيغة التخزين المشفّرة).
  static String? _merge(String? local, String? server, String? base) {
    // حُذف في طرف وعُدّل في الآخر: يبقى المعدَّل.
    if (local == null) return server;
    if (server == null) return local;
    try {
      final ld = jsonDecode(local) as Map;
      final sd = jsonDecode(server) as Map;
      final bd = base == null ? null : jsonDecode(base) as Map;
      final type = ld['t'];
      if (type != sd['t']) return base == null ? server : local;
      final sameBase = bd != null && bd['t'] == type;
      if (type == 'l') {
        final merged = _mergeItems(
          List<Object?>.of(ld['v'] as List),
          List<Object?>.of(sd['v'] as List),
          sameBase ? List<Object?>.of(bd!['v'] as List) : null,
        );
        return jsonEncode({
          't': 'l',
          'v': [for (final item in merged) '$item'],
        });
      }
      if (type == 's') {
        final merged = _mergeJsonText(
          '${ld['v']}',
          '${sd['v']}',
          sameBase ? '${bd!['v']}' : null,
        );
        if (merged != null) return jsonEncode({'t': 's', 'v': merged});
      }
    } catch (_) {
      // يبقى تعديل هذا الجوال.
    }
    // قيمة مفردة تغيّرت في الطرفين: يبقى تعديل هذا الجوال، إلا في أول
    // مزامنة بلا أساس فنسخة السحابة (آخر ما رُفع).
    return base == null ? server : local;
  }

  // ---------------- المزامنة ----------------

  /// مزامنة واحدة في كل مرة؛ طلب أثناء مزامنة جارية يعيدها بعدها.
  static Future<void> syncCloud() {
    final running = _syncing;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    Future<void> loop() async {
      do {
        _syncAgain = false;
        await _sync();
      } while (_syncAgain);
    }

    final future = loop().whenComplete(() => _syncing = null);
    _syncing = future;
    return future;
  }

  /// الاسم القديم — رفع التعديلات صار جزءًا من المزامنة نفسها.
  static Future<void> pushCloud() => syncCloud();

  static Future<void> _sync() async {
    final user = currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final baseKey = '$_kBasePrefix${user.id}';
    final seenKey = '$_kSeenPrefix${user.id}';
    final base = _readMap(prefs, baseKey);
    final seen = _readMap(prefs, seenKey);
    var pulled = false;
    try {
      // 1) السحابة: المفاتيح وتواريخ تعديلها (خفيف)، ثم قيم ما تغيّر فقط.
      final stamps = <String, String>{};
      final stampRows = await _client
          .from(_storeTable)
          .select('key, updated_at')
          .eq('user_id', user.id)
          .timeout(_timeout);
      for (final row in stampRows) {
        final key = '${row['key']}';
        if (!_isUserData(key)) continue;
        stamps[key] = '${row['updated_at'] ?? ''}';
      }
      final fetched = <String, String>{};
      final stale = [
        for (final entry in stamps.entries)
          if (seen[entry.key] != entry.value || !base.containsKey(entry.key))
            entry.key,
      ];
      for (var i = 0; i < stale.length; i += 50) {
        final chunk = stale.sublist(
          i,
          i + 50 > stale.length ? stale.length : i + 50,
        );
        final rows = await _client
            .from(_storeTable)
            .select('key, value, updated_at')
            .eq('user_id', user.id)
            .inFilter('key', chunk)
            .timeout(_timeout);
        for (final row in rows) {
          final key = '${row['key']}';
          fetched[key] = '${row['value']}';
          stamps[key] = '${row['updated_at'] ?? ''}';
        }
      }
      // مفتاح لم يتغيّر تاريخه في السحابة = قيمته هي الأساس نفسه.
      String? serverOf(String key) {
        if (!stamps.containsKey(key)) return null;
        return fetched.containsKey(key) ? fetched[key] : base[key];
      }

      // 2) الجوال.
      final local = <String, String>{};
      for (final key in prefs.getKeys()) {
        if (!_isUserData(key)) continue;
        final encoded = _encode(prefs.get(key));
        if (encoded != null) local[key] = encoded;
      }

      // 3) لكل مفتاح: نتيجة واحدة تُكتب هنا وفي السحابة.
      final now = DateTime.now().toUtc().toIso8601String();
      final upserts = <Map<String, dynamic>>[];
      final deletes = <String>[];
      final nextBase = Map<String, String>.of(base);
      final keys = <String>{
        ...local.keys,
        ...stamps.keys,
        ...base.keys.where(_isUserData),
      };
      for (final key in keys) {
        final l = local[key];
        final s = serverOf(key);
        final b = base[key];
        final String? result;
        if (l == s) {
          result = l;
        } else if (l == b) {
          result = s; // تغيّر في السحابة فقط (أو حُذف منها)
        } else if (s == b) {
          result = l; // تغيّر هنا فقط (أو حُذف هنا)
        } else {
          result = _merge(l, s, b); // تغيّر في الطرفين
        }
        if (result != l) {
          // تعديل حصل على الجوال أثناء المزامنة لا يُكتب فوقه؛ يُدمج في
          // المرة التالية.
          if (_encode(prefs.get(key)) != l) continue;
          if (result == null) {
            await prefs.remove(key);
          } else {
            await _write(prefs, key, result);
          }
          pulled = true;
        }
        if (result != s) {
          if (result == null) {
            deletes.add(key);
          } else {
            upserts.add({
              'user_id': user.id,
              'key': key,
              'value': result,
              'updated_at': now,
            });
          }
        }
        if (result == null) {
          nextBase.remove(key);
        } else {
          nextBase[key] = result;
        }
      }

      // 4) السحابة. دفعة فشلت (قيمة كبيرة كصورة الختم، أو انقطاع) تُرفع
      // سطرًا سطرًا، وما فشل يبقى بلا أساس فيُعاد في المرة التالية — بدل
      // أن يُوقف خطأ واحد رفع كل البيانات إلى الأبد.
      final failed = <String>{};
      String? uploadError;
      for (var i = 0; i < upserts.length; i += 20) {
        final chunk = upserts.sublist(
          i,
          i + 20 > upserts.length ? upserts.length : i + 20,
        );
        try {
          await _client
              .from(_storeTable)
              .upsert(chunk, onConflict: 'user_id,key')
              .timeout(_timeout);
        } catch (_) {
          for (final row in chunk) {
            try {
              await _client
                  .from(_storeTable)
                  .upsert(row, onConflict: 'user_id,key')
                  .timeout(const Duration(seconds: 60));
            } catch (error) {
              failed.add('${row['key']}');
              uploadError = '$error';
            }
          }
        }
      }
      for (final key in failed) {
        final old = base[key];
        if (old == null) {
          nextBase.remove(key);
        } else {
          nextBase[key] = old;
        }
      }
      if (deletes.isNotEmpty) {
        await _client
            .from(_storeTable)
            .delete()
            .eq('user_id', user.id)
            .inFilter('key', deletes)
            .timeout(_timeout);
      }

      // 5) الأساس الجديد، وتواريخ ما يطابقه في السحابة (ما رُفع الآن يُقرأ
      // تاريخه في المرة التالية).
      final written = <String>{
        for (final row in upserts) '${row['key']}',
        ...deletes,
      };
      final nextSeen = <String, String>{
        for (final entry in stamps.entries)
          if (!written.contains(entry.key) &&
              nextBase[entry.key] != null &&
              nextBase[entry.key] == serverOf(entry.key))
            entry.key: entry.value,
      };
      await prefs.setString(baseKey, jsonEncode(nextBase));
      await prefs.setString(seenKey, jsonEncode(nextSeen));
      lastSyncAt = DateTime.now();
      lastSyncError = failed.isEmpty
          ? null
          : 'تعذّر رفع ${failed.length} عنصر: $uploadError';
    } catch (error) {
      // بلا اتصال: تبقى بيانات الجهاز، وتُزامَن في المرة التالية.
      lastSyncError = '$error';
    }
    syncStatus.value++;
    if (pulled) await _afterPull();
  }

  /// بعد نزول تغييرات من جوال آخر: الإعدادات والصفحات والتذكيرات تُقرأ من
  /// جديد، والشاشات المفتوحة تُبلَّغ.
  static Future<void> _afterPull() async {
    try {
      await AppSettings.instance.load();
      HomeLayoutStore.invalidate();
      await PageCustomizationStore.load();
      FundlyNotifications.scheduleSoon();
    } catch (_) {
      // لا يوقف المزامنة.
    }
    cloudRevision.value++;
  }

  /// مزامنة تلقائية: عند فتح التطبيق وعند الرجوع إليه (ينزل ما أضافه جوال
  /// آخر)، وعند مغادرته وكل دقيقتين أثناء استعماله.
  static void startAutoSync() {
    if (currentUser == null) return;
    void upload() {
      unawaited(syncCloud());
      unawaited(FundlyFiles.syncUp());
    }

    _lifecycle ??= AppLifecycleListener(
      onInactive: upload,
      onHide: upload,
      onResume: () {
        unawaited(syncCloud());
        unawaited(FundlyFiles.syncDown());
      },
    );
    // كل 30 ثانية: ما يُضاف في جوال يظهر في الآخر خلال نصف دقيقة
    // (الطلب خفيف: المفاتيح وتواريخها فقط، والقيم المتغيرة وحدها).
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(syncCloud());
      unawaited(pollInbox());
    });
    unawaited(syncCloud());
    unawaited(pollInbox());
    // إشعارات تصل والتطبيق مغلق: رمز هذا الجهاز باسم الحساب.
    unawaited(FundlyPush.registerDevice());
  }
}
