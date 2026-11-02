import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ترتيب أقسام الصفحة الرئيسية وإخفاؤها — يختاره المستخدم من «المزيد».
/// يُحفظ محليًا في SharedPreferences (بلا أي تعديل على قاعدة البيانات).
class HomeLayout {
  const HomeLayout({required this.order, required this.hidden});

  /// معرّفات الأقسام بالترتيب الظاهر.
  final List<String> order;

  /// معرّفات الأقسام المخفية.
  final Set<String> hidden;

  bool isVisible(String id) => !hidden.contains(id);
}

class HomeLayoutStore {
  HomeLayoutStore._();

  static const personal = 'personal';
  static const shared = 'shared';
  static const people = 'people';
  static const assets = 'assets';

  /// الترتيب الافتراضي كما كان في التطبيق.
  static const defaultOrder = [personal, shared, people, assets];

  /// أسماء الأقسام كما تظهر في شاشة التخصيص.
  static const titles = {
    personal: 'الالتزامات الشخصية',
    shared: 'الالتزامات المشتركة',
    people: 'الأفراد والجهات',
    assets: 'العقارات والأنشطة والمركبات',
  };

  static const _orderKey = 'home_layout_order_v1';
  static const _hiddenKey = 'home_layout_hidden_v1';

  static final ValueNotifier<HomeLayout> notifier = ValueNotifier(
    const HomeLayout(order: defaultOrder, hidden: {}),
  );

  static bool _loaded = false;

  /// بعد تبديل الحساب: يُقرأ الترتيب من جديد في التحميل التالي.
  static void invalidate() => _loaded = false;

  static Future<HomeLayout> load() async {
    if (_loaded) return notifier.value;
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_orderKey) ?? const <String>[];
    final hidden = (prefs.getStringList(_hiddenKey) ?? const <String>[])
        .where(defaultOrder.contains)
        .toSet();
    notifier.value = HomeLayout(order: _normalize(savedOrder), hidden: hidden);
    _loaded = true;
    return notifier.value;
  }

  static Future<void> save(List<String> order, Set<String> hidden) async {
    final normalized = _normalize(order);
    final cleanHidden = hidden.where(defaultOrder.contains).toSet();
    notifier.value = HomeLayout(order: normalized, hidden: cleanHidden);
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, normalized);
    await prefs.setStringList(_hiddenKey, cleanHidden.toList());
  }

  static Future<void> reset() =>
      save(List<String>.of(defaultOrder), <String>{});

  /// يحذف المعرّفات المجهولة ويُلحق أي قسم ناقص في آخر القائمة.
  static List<String> _normalize(List<String> order) {
    final result = <String>[];
    for (final id in order) {
      if (defaultOrder.contains(id) && !result.contains(id)) result.add(id);
    }
    for (final id in defaultOrder) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }
}
