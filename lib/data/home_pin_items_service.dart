import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'home_pinned_shortcuts_store.dart';
import 'personal_entries_repository.dart';
import 'project_assets_repository.dart';

class HomePinItemsService {
  HomePinItemsService({
    PersonalEntriesRepository? personalRepository,
    ProjectAssetsRepository? assetsRepository,
  }) : _personalRepository = personalRepository,
       _assetsRepository = assetsRepository;

  static const moduleIds = ['personal', 'shared', 'people', 'assets'];

  final PersonalEntriesRepository? _personalRepository;
  final ProjectAssetsRepository? _assetsRepository;

  Future<Map<String, List<HomePinnedShortcut>>> load() async {
    final results = await Future.wait([
      _loadPersonal(),
      _loadPeople(),
      _loadAssets(),
    ]);
    return {
      'personal': results[0],
      'shared': _sharedItems,
      'people': results[1],
      'assets': results[2],
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
            return HomePinnedShortcut(
              id: 'people:${data['id'] ?? title}',
              title: title,
              moduleId: 'people',
              subtitle:
                  data['categoryName']?.toString() ??
                  data['roleTitle']?.toString() ??
                  '',
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
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return _defaultAssets;
    }
  }

  static const _sharedItems = [
    HomePinnedShortcut(
      id: 'shared:dubai-trip',
      title: 'الرحلة إلى دبي',
      moduleId: 'shared',
      subtitle: 'الرحلات / السفر',
    ),
    HomePinnedShortcut(
      id: 'shared:group-dinner',
      title: 'عشاء جماعي في مطعم',
      moduleId: 'shared',
      subtitle: 'اللقاءات',
    ),
  ];

  static const _defaultPeople = [
    HomePinnedShortcut(
      id: 'people:ahmed-salem',
      title: 'أحمد محمد سالم',
      moduleId: 'people',
      subtitle: 'موظف',
    ),
    HomePinnedShortcut(
      id: 'people:rashid-khaled',
      title: 'راشد خالد',
      moduleId: 'people',
      subtitle: 'موظف',
    ),
    HomePinnedShortcut(
      id: 'people:mohammed-salem',
      title: 'محمد سالم',
      moduleId: 'people',
      subtitle: 'قريب',
    ),
  ];

  static const _defaultAssets = [
    HomePinnedShortcut(
      id: 'assets:villa-yasmina',
      title: 'فيلا الياسمينة',
      moduleId: 'assets',
      subtitle: 'فيلا',
    ),
    HomePinnedShortcut(
      id: 'assets:al-safa',
      title: 'مشروع الصفا',
      moduleId: 'assets',
      subtitle: 'مشروع سكني',
    ),
    HomePinnedShortcut(
      id: 'assets:rose-bella',
      title: 'مطعم روز بيلا',
      moduleId: 'assets',
      subtitle: 'نشاط تجاري',
    ),
  ];
}
