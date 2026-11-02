import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fundly_account.dart';
import 'fundly_notifications.dart';

/// يصل من Firebase والتطبيق في الخلفية أو مغلق: يُعرض إشعار الطلب بصوت.
/// دالة عليا مستقلة لأن أندرويد يشغّلها في عزلة منفصلة عن الواجهة.
@pragma('vm:entry-point')
Future<void> fundlyPushBackground(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await FundlyPush.showFromData(message.data);
}

/// إشعارات تصل والتطبيق مغلق: كل طلب أو رد أو نشاط جديد في fundly_inbox
/// يُرسله الخادم (دالة fundly-push) إلى رموز أجهزة المستلم عبر Firebase.
/// والتطبيق مفتوح يبقى الفحص الدوري كل 30 ثانية احتياطًا، ولا يتكرر
/// الإشعار نفسه لأن المعروض يُسجَّل بمعرّفه.
class FundlyPush {
  FundlyPush._();

  static bool _ready = false;
  static bool _listening = false;
  static String? _token;

  /// عند الإقلاع قبل بناء الواجهة.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(fundlyPushBackground);
      _ready = true;
    } catch (error) {
      // بلا إعداد Firebase (iOS مثلًا): يبقى الفحص الدوري وحده.
      debugPrint('FundlyPush init failed: $error');
    }
  }

  /// بعد الدخول: إذن الإشعارات، ثم حفظ رمز هذا الجهاز باسم الحساب.
  static Future<void> registerDevice() async {
    if (!_ready) return;
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) await _save(token);
      if (_listening) return;
      _listening = true;
      messaging.onTokenRefresh.listen((fresh) => unawaited(_save(fresh)));
      // التطبيق مفتوح: يُعرض الإشعار فورًا وتُفتح نافذة الطلبات.
      FirebaseMessaging.onMessage.listen((message) async {
        await showFromData(message.data);
        FundlyAccount.inboxArrivals.value++;
      });
    } catch (error) {
      debugPrint('FundlyPush register failed: $error');
    }
  }

  static Future<void> _save(String token) async {
    _token = token;
    try {
      await Supabase.instance.client.rpc(
        'fundly_register_push',
        params: {'p_token': token, 'p_platform': defaultTargetPlatform.name},
      );
    } catch (_) {
      // يُعاد عند الفتح التالي.
    }
  }

  /// عند الخروج من الحساب: لا تصل إشعاراته لهذا الجهاز بعد ذلك.
  static Future<void> unregister() async {
    if (!_ready) return;
    final token = _token;
    try {
      if (token != null) {
        await Supabase.instance.client.rpc(
          'fundly_unregister_push',
          params: {'p_token': token},
        );
      }
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }

  /// يعرض إشعار الطلب من بيانات الرسالة (نفس أعمدة fundly_inbox)، مرة
  /// واحدة لكل طلب حتى لو وصل أيضًا من الفحص الدوري.
  static Future<void> showFromData(Map<String, dynamic> data) async {
    final id = '${data['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // قد تكون عزلة أخرى سجّلته للتو.
      await prefs.reload();
      final done =
          (prefs.getStringList(FundlyAccount.notifiedKey) ?? const <String>[])
              .toList();
      if (done.contains(id)) return;
      final item = FundlyInboxItem.fromJson(Map<String, dynamic>.of(data));
      final (title, body) = FundlyAccount.inboxNotice(item);
      await FundlyNotifications.showNow(
        key: 'inbox_$id',
        title: title,
        body: body,
      );
      done.add(id);
      if (done.length > 300) done.removeRange(0, done.length - 300);
      await prefs.setStringList(FundlyAccount.notifiedKey, done);
    } catch (error) {
      debugPrint('FundlyPush show failed: $error');
    }
  }
}
