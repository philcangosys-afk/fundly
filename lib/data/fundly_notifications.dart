import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_language.dart';
import 'app_settings.dart';
import 'home_dashboard_service.dart';
import 'install_guard.dart';

/// إشعارات الجوال (بصوت) للتذكيرات والمواعيد.
///
/// كانت «التنبيهات» داخل التطبيق فقط (مركز التنبيهات والنقطة الحمراء)، فلا
/// يصل شيء والتطبيق مغلق. هنا تُجدوَل إشعارات النظام من المصدر نفسه الذي
/// يعرضه مركز التنبيهات (HomeDashboardService)، وتُعاد جدولتها بعد كل حفظ،
/// وعند فتح التطبيق، وعند الرجوع إليه.
///
/// لكل عنصر مفتوح:
/// - إشعار يوم موعده في الساعة المسجّلة معه (الوقت / وقت التذكير)، وإلا
///   الساعة 9 صباحًا.
/// - وإشعار قبله بمدة التذكير (قبل يوم، أسبوع...) في الساعة نفسها.
/// - المتكرر (يومي، أسبوعي، شهري) يُجدوَل موعده القادم.
class FundlyNotifications {
  FundlyNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'fundly_reminders';

  /// قناة الطلبات والردود (عهدة، دعوة، تفويض، قبول/رفض): فورية بصوت.
  static const String _requestsChannelId = 'fundly_requests';
  static const String _exactAskedKey = 'fundly_exact_alarm_asked';

  /// أقصى عدد مُجدوَل (حد iOS 64 إشعارًا).
  static const int _maxScheduled = 60;

  /// أبعد موعد يُجدوَل الآن؛ ما بعده يُجدوَل عند فتح التطبيق لاحقًا.
  static const int _horizonDays = 45;

  static bool _ready = false;
  static bool _started = false;
  static bool _exact = false;
  static Timer? _debounce;
  static Future<void>? _running;
  static bool _again = false;

  static Future<void> _init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          AppTr.tr('التذكيرات والمواعيد'),
          description: AppTr.tr('تذكيرات الالتزامات والمواعيد والمستندات'),
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _requestsChannelId,
          AppTr.tr('الطلبات والردود'),
          description: AppTr.tr(
            'طلبات العهدة والدعوات والتفويضات والردود عليها',
          ),
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      _ready = true;
    } catch (error) {
      debugPrint('FundlyNotifications init failed: $error');
    }
  }

  /// بعد الدخول: يطلب إذن الإشعارات (أندرويد 13+) مرة، ثم يجدول.
  static Future<void> start() async {
    await _init();
    if (!_ready) return;
    if (!_started) {
      _started = true;
      AppSettings.instance.addListener(scheduleSoon);
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.requestNotificationsPermission();
        _exact = await android?.canScheduleExactNotifications() ?? false;
        if (android != null && !_exact) {
          // أندرويد 14: التذكير بالدقيقة يحتاج إذن «المنبهات والتذكيرات».
          // يُطلب مرة واحدة؛ وبدونه يصل الإشعار بتأخير دقائق قليلة.
          // مرة لكل تثبيت: بعد حذف التطبيق وتثبيته يُطلب الإذن من جديد.
          final prefs = await SharedPreferences.getInstance();
          final askedKey =
              '${_exactAskedKey}_${InstallGuard.firstInstallTime ?? 0}';
          if (!(prefs.getBool(askedKey) ?? false)) {
            await prefs.setBool(askedKey, true);
            await android.requestExactAlarmsPermission();
            _exact = await android.canScheduleExactNotifications() ?? false;
          }
        }
      } catch (error) {
        debugPrint('FundlyNotifications permission failed: $error');
      }
    }
    await reschedule();
  }

  /// إشعار فوري بصوت (يظهر في الستارة وفوق التطبيق وهو مفتوح): طلب جديد
  /// أو رد عليه. [key] يميّزه فلا يتكرر الإشعار نفسه.
  static Future<void> showNow({
    required String key,
    required String title,
    required String body,
  }) async {
    await _init();
    if (!_ready) return;
    try {
      await _plugin.show(
        // نطاق مستقل عن معرّفات التذكيرات المجدولة.
        (_idFor('now_$key') & 0x3fffffff) | 0x40000000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _requestsChannelId,
            AppTr.tr('الطلبات والردود'),
            channelDescription: AppTr.tr(
              'طلبات العهدة والدعوات والتفويضات والردود عليها',
            ),
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            ticker: title,
            styleInformation: BigTextStyleInformation(body),
            category: AndroidNotificationCategory.message,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: key,
      );
    } catch (error) {
      debugPrint('FundlyNotifications show failed: $error');
    }
  }

  /// بعد حفظ أو حذف: إعادة جدولة بعد لحظات (تُجمع عدة حفظات في مرة).
  static void scheduleSoon() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      reschedule();
    });
  }

  /// عند الخروج من الحساب: لا تبقى إشعارات الحساب السابق.
  static Future<void> cancelAll() async {
    _debounce?.cancel();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> reschedule() async {
    // جدولة واحدة في كل مرة؛ وما حُفظ أثناءها يُعاد له بعدها.
    if (_running != null) {
      _again = true;
      return;
    }
    do {
      _again = false;
      _running = _reschedule();
      try {
        await _running;
      } finally {
        _running = null;
      }
    } while (_again);
  }

  static Future<void> _reschedule() async {
    if (!_ready) return;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        _exact = await android.canScheduleExactNotifications() ?? _exact;
      }
    } catch (_) {}
    final settings = AppSettings.instance;
    if (!settings.notificationsEnabled) {
      await cancelAll();
      return;
    }
    final HomeDashboardMetrics metrics;
    try {
      metrics = await HomeDashboardService().loadMetrics();
    } catch (error) {
      debugPrint('FundlyNotifications load failed: $error');
      return;
    }
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: _horizonDays));
    final planned = <_Planned>[];
    for (final item in metrics.calendarItems) {
      if (item.remindBeforeDays == HomeDashboardService.noReminder) continue;
      if (HomeDashboardService.closedStatuses.contains(item.status.trim())) {
        continue;
      }
      if (item.isExpiry && !settings.expiryNotifications) continue;
      final clock = _parseClock(item.time) ?? (9, 0);
      final lead = item.remindBeforeDays >= 0
          ? item.remindBeforeDays
          : settings.leadTimeDays;
      var day = DateTime(item.date.year, item.date.month, item.date.day);
      var at = DateTime(day.year, day.month, day.day, clock.$1, clock.$2);
      // المتكرر الذي فات وقته اليوم: موعده التالي.
      if (!at.isAfter(now) && item.repeat.isNotEmpty) {
        final next = HomeDashboardService.nextOccurrence(
          day,
          item.repeat,
          day.add(const Duration(days: 1)),
        );
        if (next.isAfter(day)) {
          day = next;
          at = DateTime(day.year, day.month, day.day, clock.$1, clock.$2);
        }
      }
      final title = item.title.trim().isEmpty ? item.type : item.title.trim();
      final timeText = _clockText(clock);
      if (at.isAfter(now) && !at.isAfter(horizon)) {
        planned.add(
          _Planned(
            key: '${item.module}|${item.sourceId}|due',
            at: at,
            title: title,
            body: item.isExpiry
                ? '${AppTr.tr('ينتهي اليوم')} — ${AppTr.tr(item.module)}'
                : '${AppTr.tr('موعده الآن')} $timeText — ${AppTr.tr(item.module)}',
          ),
        );
      }
      if (item.leadMinutes > 0) {
        // «وقت التذكير»: قبل الموعد بساعة/12 ساعة/يوم أو مخصص.
        final before = at.subtract(Duration(minutes: item.leadMinutes));
        if (before.isAfter(now) && !before.isAfter(horizon)) {
          final m = item.leadMinutes;
          final span = m % 1440 == 0
              ? '${m ~/ 1440} ${AppTr.tr(m ~/ 1440 == 1 ? 'يوم' : 'أيام')}'
              : '${(m / 60).round()} ${AppTr.tr('ساعة')}';
          planned.add(
            _Planned(
              key: '${item.module}|${item.sourceId}|lead',
              at: before,
              title: title,
              body: '${AppTr.tr('موعده بعد')} $span — $timeText',
            ),
          );
        }
      } else if (lead > 0) {
        final before = at.subtract(Duration(days: lead));
        if (before.isAfter(now) && !before.isAfter(horizon)) {
          planned.add(
            _Planned(
              key: '${item.module}|${item.sourceId}|lead',
              at: before,
              title: title,
              body:
                  '${AppTr.tr(item.isExpiry ? 'ينتهي بعد' : 'موعده بعد')} '
                  '$lead ${AppTr.tr(lead == 1 ? 'يوم' : 'أيام')} — '
                  '${day.day}/${day.month}/${day.year}',
            ),
          );
        }
      }
    }
    planned.sort((a, b) => a.at.compareTo(b.at));
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        AppTr.tr('التذكيرات والمواعيد'),
        channelDescription: AppTr.tr('تذكيرات الالتزامات والمواعيد والمستندات'),
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    try {
      // المجدولة فقط: الإشعارات الظاهرة (طلبات وصلت) تبقى في الستارة.
      for (final pending in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(pending.id);
      }
      final used = <int>{};
      for (final p in planned.take(_maxScheduled)) {
        var id = _idFor(p.key);
        while (!used.add(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        await _plugin.zonedSchedule(
          id,
          p.title,
          p.body,
          tz.TZDateTime.from(p.at, tz.UTC),
          details,
          androidScheduleMode: _exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: p.key,
        );
      }
    } catch (error) {
      debugPrint('FundlyNotifications schedule failed: $error');
    }
  }

  /// معرّف ثابت للإشعار من مفتاحه (FNV-1a، 31 بت).
  static int _idFor(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  /// «13:36» أو «1:36 PM» أو «١:٣٦ م».
  static (int, int)? _parseClock(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < arabic.length; i++) {
      text = text.replaceAll(arabic[i], '$i');
    }
    final match = RegExp(r'(\d{1,2})\s*[:٫.]\s*(\d{2})').firstMatch(text);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final lower = text.toLowerCase();
    final pm = lower.contains('pm') || RegExp(r'(^|[\s\d])م').hasMatch(text);
    final am = lower.contains('am') || RegExp(r'(^|[\s\d])ص').hasMatch(text);
    if (pm && hour < 12) hour += 12;
    if (am && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return (hour, minute);
  }

  static String _clockText((int, int) clock) =>
      '${clock.$1.toString().padLeft(2, '0')}:'
      '${clock.$2.toString().padLeft(2, '0')}';
}

class _Planned {
  const _Planned({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
  });

  final String key;
  final DateTime at;
  final String title;
  final String body;
}
