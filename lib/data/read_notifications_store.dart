import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_dashboard_service.dart';

/// التنبيهات التي وضعها المستخدم "مقروءة".
///
/// التنبيهات في التطبيق ليست سجلات في قاعدة البيانات، بل تُحسب في كل مرة
/// من تواريخ الاستحقاق. فلا يوجد صف نضع فيه "مقروء". لذلك تُحفظ هنا
/// مفاتيح التنبيهات المقروءة محليًا على الجهاز، ويُبنى المفتاح من مصدر
/// التنبيه وتاريخه: فإذا تجدّد الاستحقاق (تاريخ جديد) عاد التنبيه غير
/// مقروء تلقائيًا، وهو السلوك الصحيح — لا يُخفى تنبيه العام القادم لأن
/// المستخدم قرأ تنبيه هذا العام.
class ReadNotificationsStore extends ChangeNotifier {
  ReadNotificationsStore._();

  static final ReadNotificationsStore instance = ReadNotificationsStore._();

  static const _prefsKey = 'read_notifications_keys';

  Set<String> _readKeys = <String>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// مفتاح ثابت لتنبيه واحد.
  static String keyFor(HomeCalendarItem item) {
    final date = '${item.date.year}-${item.date.month}-${item.date.day}';
    return '${item.sourceId}|${item.module}|${item.title}|$date';
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _readKeys = (prefs.getStringList(_prefsKey) ?? const <String>[]).toSet();
    _loaded = true;
    notifyListeners();
  }

  bool isRead(HomeCalendarItem item) => _readKeys.contains(keyFor(item));

  int unreadCount(Iterable<HomeCalendarItem> items) =>
      items.where((item) => !isRead(item)).length;

  Future<void> markRead(HomeCalendarItem item, {bool read = true}) async {
    final key = keyFor(item);
    if (read) {
      if (!_readKeys.add(key)) return;
    } else {
      if (!_readKeys.remove(key)) return;
    }
    await _persist();
  }

  Future<void> markAllRead(Iterable<HomeCalendarItem> items) async {
    final before = _readKeys.length;
    _readKeys.addAll(items.map(keyFor));
    if (_readKeys.length == before) return;
    await _persist();
  }

  Future<void> markAllUnread(Iterable<HomeCalendarItem> items) async {
    final before = _readKeys.length;
    _readKeys.removeAll(items.map(keyFor));
    if (_readKeys.length == before) return;
    await _persist();
  }

  Future<void> _persist() async {
    // تنظيف: لا تنمُ القائمة بلا حدّ مع مرور السنين (يحتفظ بالأحدث).
    if (_readKeys.length > 500) {
      _readKeys = _readKeys.skip(_readKeys.length - 500).toSet();
    }
    // الإشعار أولًا ثم الكتابة: الواجهة تتغيّر في الإطار نفسه بدل انتظار
    // القرص، فلا تبدو الضغطة بطيئة.
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _readKeys.toList(growable: false));
  }
}
