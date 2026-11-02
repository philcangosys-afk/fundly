import 'package:shared_preferences/shared_preferences.dart';

/// فئة في صفحة، وعناصرها (الأنواع) التي يمكن إخفاؤها منفردة.
class PageCategoryDef {
  const PageCategoryDef(this.title, [this.items = const <String>[]]);

  final String title;
  final List<String> items;
}

/// تخصيص الصفحات الأربع: إخفاء فئة كاملة، أو عناصر محددة داخلها.
///
/// الإخفاء يُخفي الفئة/العنصر من شريط الفئات وقوائم الإضافة، ويُخفي
/// سجلاته من القوائم والعدّادات — والبيانات نفسها لا تُحذف، وتعود بمجرد
/// إظهارها من «تخصيص الصفحات».
class PageCustomizationStore {
  PageCustomizationStore._();

  static const String personal = 'personal';
  static const String shared = 'shared';
  static const String people = 'people';
  static const String assets = 'assets';

  static const List<String> pages = [personal, shared, people, assets];

  static const Map<String, String> pageTitles = {
    personal: 'الالتزامات الشخصية',
    shared: 'الالتزامات المشتركة',
    people: 'الأفراد / الجهات',
    assets: 'العقارات / الأنشطة التجارية / المركبات ووسائل النقل',
  };

  /// فئات العقارات بمفاتيحها في السجلات.
  static const Map<String, String> assetCategoryTitles = {
    'real_estate': 'العقارات',
    'activity': 'الأنشطة التجارية',
    'equipment': 'المركبات ووسائل النقل',
  };

  /// فئات كل صفحة وعناصرها — بنفس أسمائها في الصفحة.
  /// فئات كل صفحة — بنفس أسمائها في الصفحة. الإخفاء للفئة كاملة، إلا
  /// المركبات: تصنيفاها (برية / بحرية) يُخفى كلٌّ منهما وحده.
  static const Map<String, List<PageCategoryDef>> catalog = {
    personal: [
      PageCategoryDef('مالية'),
      PageCategoryDef('مستند'),
      PageCategoryDef('المتابعة والتخطيط'),
      PageCategoryDef('أدوية وبيانات وكلمات سر'),
      PageCategoryDef('نمط الحياة'),
      PageCategoryDef('مواقع وأماكن'),
      PageCategoryDef('عهدة مالية'),
    ],
    shared: [
      PageCategoryDef('مشاركات مشتركة'),
      PageCategoryDef('الرحلة / السفر'),
      PageCategoryDef('جمعية مالية'),
    ],
    people: [
      PageCategoryDef('الأفراد'),
      PageCategoryDef('الجهات'),
    ],
    assets: [
      PageCategoryDef('العقارات'),
      PageCategoryDef('الأنشطة التجارية'),
      PageCategoryDef('المركبات ووسائل النقل', [
        'مركبات برية',
        'مركبات بحرية',
      ]),
    ],
  };

  /// عنصر له مفتاح إخفاء في الفهرس الحالي — ما أُخفي قديمًا من عناصر
  /// لم تعد قابلة للإخفاء يُتجاهل، فلا يبقى مخفيًا بلا طريقة لإظهاره.
  static bool _isItem(String page, String category, String item) {
    for (final def in catalog[page] ?? const <PageCategoryDef>[]) {
      if (def.title == category) return def.items.contains(item);
    }
    return false;
  }

  static bool _validKey(String page, String key) {
    for (final def in catalog[page] ?? const <PageCategoryDef>[]) {
      if (key == def.title) return true;
      for (final item in def.items) {
        if (key == _itemKey(def.title, item)) return true;
      }
    }
    return false;
  }

  static final Map<String, Set<String>> _hidden = {};

  static String _storageKey(String page) => 'page_custom_hidden_v1_$page';
  static String _itemKey(String category, String item) => '$category › $item';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final page in pages) {
        _hidden[page] = (prefs.getStringList(_storageKey(page)) ?? const [])
            .toSet();
      }
    } catch (_) {
      // تعذّر القراءة: كل شيء ظاهر.
    }
  }

  static Future<void> _save(String page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _storageKey(page),
        (_hidden[page] ?? const <String>{}).toList(growable: false),
      );
    } catch (_) {}
  }

  static bool categoryHidden(String page, String category) =>
      _hidden[page]?.contains(category) ?? false;

  /// العنصر مخفي إن أُخفي وحده أو أُخفيت فئته كلها.
  static bool itemHidden(String page, String category, String item) =>
      categoryHidden(page, category) ||
      (_isItem(page, category, item) &&
          (_hidden[page]?.contains(_itemKey(category, item)) ?? false));

  /// عنصر مخفي وحده (لا بسبب فئته) — لمفتاح الإعدادات.
  static bool itemHiddenAlone(String page, String category, String item) =>
      _hidden[page]?.contains(_itemKey(category, item)) ?? false;

  static Future<void> setCategoryHidden(
    String page,
    String category,
    bool hidden,
  ) async {
    final set = _hidden.putIfAbsent(page, () => <String>{});
    hidden ? set.add(category) : set.remove(category);
    await _save(page);
  }

  static Future<void> setItemHidden(
    String page,
    String category,
    String item,
    bool hidden,
  ) async {
    final set = _hidden.putIfAbsent(page, () => <String>{});
    final key = _itemKey(category, item);
    hidden ? set.add(key) : set.remove(key);
    await _save(page);
  }

  static Future<void> reset(String page) async {
    _hidden[page] = <String>{};
    await _save(page);
  }

  /// عدد المخفي في صفحة (فئات + عناصر) — يظهر في قائمة «تخصيص الصفحات».
  static int hiddenCount(String page) =>
      (_hidden[page] ?? const <String>{})
          .where((key) => _validKey(page, key))
          .length;
}
