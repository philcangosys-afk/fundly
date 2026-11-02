import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'home_pinned_shortcuts_store.dart';
import 'personal_entries_repository.dart';
import 'project_assets_repository.dart';
import 'shared_entries_repository.dart';

class HomePinItemsService {
  HomePinItemsService({
    PersonalEntriesRepository? personalRepository,
    ProjectAssetsRepository? assetsRepository,
    SharedEntriesRepository? sharedRepository,
  }) : _personalRepository = personalRepository,
       _assetsRepository = assetsRepository,
       _sharedRepository = sharedRepository;

  static const moduleIds = ['personal', 'shared', 'people', 'assets'];

  /// تبويبات كل وحدة داخل نافذة التثبيت — بنفس ترتيب شاشتها.
  static const groupsByModule = <String, List<String>>{
    'personal': [
      'مالية',
      'مستند',
      'المتابعة والتخطيط',
      'أدوية وبيانات وكلمات سر',
      'نمط الحياة',
      'مواقع وأماكن',
      'عهدة مالية',
    ],
    'shared': ['مشاركات مشتركة', 'الرحلة / السفر', 'جمعية مالية'],
    'people': ['الأفراد', 'الجهات والشركات'],
    'assets': ['العقارات', 'الأنشطة التجارية', 'المركبات ووسائل النقل'],
  };

  static List<String> groupsFor(String moduleId) =>
      groupsByModule[moduleId] ?? const <String>[];

  /// نوع الالتزام الشخصي ← تبويبه (كما في شاشة الالتزامات الشخصية).
  static const _personalGroupOfType = <String, String>{
    'المصروفات الشخصية': 'مالية',
    'إيراد': 'مالية',
    'تحويل مالي': 'مالية',
    'دين / قرض / سلفة': 'مالية',
    'قسط': 'مالية',
    'غرامة': 'مالية',
    'مصروف': 'مالية',
    'دخل': 'مالية',
    'ديون': 'مالية',
    'مستند': 'مستند',
    'مهمة': 'المتابعة والتخطيط',
    'موعد': 'المتابعة والتخطيط',
    'عادة': 'المتابعة والتخطيط',
    'عادة يومية': 'المتابعة والتخطيط',
    'تذكير': 'المتابعة والتخطيط',
    'ملاحظات': 'المتابعة والتخطيط',
    'تفويض': 'المتابعة والتخطيط',
    'أدوية': 'أدوية وبيانات وكلمات سر',
    'كلمات سر': 'أدوية وبيانات وكلمات سر',
    'مناسبة': 'نمط الحياة',
    'اشتراك': 'نمط الحياة',
    'اشتراكات': 'نمط الحياة',
    'هدية': 'نمط الحياة',
    'مواقع وأماكن': 'مواقع وأماكن',
    'مكان': 'مواقع وأماكن',
    'عهدة مالية': 'عهدة مالية',
  };

  static String _personalGroup(String entryType, String category) {
    final byType = _personalGroupOfType[entryType.trim()];
    if (byType != null) return byType;
    final cat = category.trim() == 'التنظيم والمتابعة'
        ? 'المتابعة والتخطيط'
        : category.trim();
    if (groupsFor('personal').contains(cat)) return cat;
    return 'أخرى';
  }

  /// نوع الالتزام المشترك ← تبويبه (كما في شاشة الالتزامات المشتركة).
  static String _sharedGroup(String entryType) {
    final type = entryType.trim();
    if (type == 'الرحلة / السفر' || type == 'رحلة' || type.contains('سفر')) {
      return 'الرحلة / السفر';
    }
    if (type == 'جمعية مالية' || type == 'جمعية') return 'جمعية مالية';
    return 'مشاركات مشتركة';
  }

  final PersonalEntriesRepository? _personalRepository;
  final ProjectAssetsRepository? _assetsRepository;
  final SharedEntriesRepository? _sharedRepository;

  Future<Map<String, List<HomePinnedShortcut>>> load() async {
    final results = await Future.wait([
      _loadPersonal(),
      _loadShared(),
      _loadPeople(),
      _loadAssets(),
    ]);
    return {
      'personal': results[0],
      'shared': results[1],
      'people': results[2],
      'assets': results[3],
    };
  }

  Future<List<HomePinnedShortcut>> _loadPersonal() async {
    try {
      final repository =
          _personalRepository ?? SupabasePersonalEntriesRepository();
      final records = await repository.fetchAll();
      return records
          .map(
            (record) => HomePinnedShortcut(
              id: 'personal:${record.id ?? record.title}',
              title: record.title.isEmpty ? record.entryType : record.title,
              moduleId: 'personal',
              subtitle: record.entryType,
              group: _personalGroup(record.entryType, record.category),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// الالتزامات المشتركة الحقيقية (مشاركات، رحلات، جمعيات).
  Future<List<HomePinnedShortcut>> _loadShared() async {
    try {
      final repository = _sharedRepository ?? SupabaseSharedEntriesRepository();
      final records = await repository.fetchAll();
      return records
          .map(
            (record) => HomePinnedShortcut(
              id: 'shared:${record.id ?? record.title}',
              title: record.title.isEmpty ? record.entryType : record.title,
              moduleId: 'shared',
              subtitle: record.entryType,
              group: _sharedGroup(record.entryType),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<HomePinnedShortcut>> _loadPeople() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('people_management_records_v1');
    if (raw == null || raw.isEmpty) return _defaultPeople;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _defaultPeople;
      return decoded
          .whereType<Map>()
          .map((item) {
            final data = Map<String, dynamic>.from(item);
            final title = data['fullName']?.toString() ?? '';
            final isEntity = (data['typeKey'] ?? '').toString().startsWith(
              'entity_',
            );
            return HomePinnedShortcut(
              id: 'people:${data['id'] ?? title}',
              title: title,
              moduleId: 'people',
              subtitle:
                  data['categoryName']?.toString() ??
                  data['roleTitle']?.toString() ??
                  '',
              group: isEntity ? 'الجهات والشركات' : 'الأفراد',
            );
          })
          .where((item) => item.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return _defaultPeople;
    }
  }

  Future<List<HomePinnedShortcut>> _loadAssets() async {
    try {
      final repository = _assetsRepository ?? SupabaseProjectAssetsRepository();
      final records = await repository.fetchAssets();
      if (records.isEmpty) return _defaultAssets;
      return records
          .map(
            (record) => HomePinnedShortcut(
              id: 'assets:${record.id ?? record.title}',
              title: record.title,
              moduleId: 'assets',
              subtitle: record.subType,
              group: switch (record.category) {
                'real_estate' => 'العقارات',
                'activity' => 'الأنشطة التجارية',
                _ => 'المركبات ووسائل النقل',
              },
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return _defaultAssets;
    }
  }

  static const _defaultPeople = [
    HomePinnedShortcut(
      id: 'people:ahmed-salem',
      title: 'أحمد محمد سالم',
      moduleId: 'people',
      subtitle: 'موظف',
      group: 'الأفراد',
    ),
    HomePinnedShortcut(
      id: 'people:rashid-khaled',
      title: 'راشد خالد',
      moduleId: 'people',
      subtitle: 'موظف',
      group: 'الأفراد',
    ),
    HomePinnedShortcut(
      id: 'people:mohammed-salem',
      title: 'محمد سالم',
      moduleId: 'people',
      subtitle: 'قريب',
      group: 'الأفراد',
    ),
  ];

  static const _defaultAssets = [
    HomePinnedShortcut(
      id: 'assets:villa-yasmina',
      title: 'فيلا الياسمينة',
      moduleId: 'assets',
      subtitle: 'فيلا',
      group: 'العقارات',
    ),
    HomePinnedShortcut(
      id: 'assets:al-safa',
      title: 'مشروع الصفا',
      moduleId: 'assets',
      subtitle: 'مشروع سكني',
      group: 'العقارات',
    ),
    HomePinnedShortcut(
      id: 'assets:rose-bella',
      title: 'مطعم روز بيلا',
      moduleId: 'assets',
      subtitle: 'نشاط تجاري',
      group: 'الأنشطة التجارية',
    ),
  ];
}
