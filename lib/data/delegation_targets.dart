import 'dart:convert';

import 'package:flutter/widgets.dart' show BuildContext;

import 'app_settings.dart';
import 'people_directory_store.dart';
import 'personal_entries_repository.dart';
import 'project_assets_repository.dart';
import 'shared_entries_repository.dart';

/// عنصر محدد يُفوَّض عليه بدل القسم كاملًا: عهدة بعينها، بناية، مركبة،
/// شخص، رحلة... يُحفظ داخل قائمة الصلاحيات نفسها ببادئة [prefix] (بلا
/// عمود جديد في قاعدة البيانات)، مثل «يتطلب موافقة المالك».
class DelegationTarget {
  const DelegationTarget({
    required this.sub,
    required this.kind,
    required this.id,
    required this.label,
    this.subtitle = '',
  });

  static const prefix = '@target:';

  /// القسم الفرعي الذي ينتمي إليه العنصر (مثل «عهدة مالية»).
  final String sub;

  /// مصدر العنصر: personal / shared / asset / person.
  final String kind;
  final String id;
  final String label;

  /// سطر وصفي يظهر في قائمة الاختيار فقط (لا يُحفظ).
  final String subtitle;

  String get key => '$kind|$id';

  String encode() {
    String clean(String v) => v.replaceAll('|', '/');
    return '$prefix${clean(sub)}|$kind|${clean(id)}|${clean(label)}';
  }

  static DelegationTarget? decode(String raw) {
    if (!raw.startsWith(prefix)) return null;
    final parts = raw.substring(prefix.length).split('|');
    if (parts.length < 4) return null;
    return DelegationTarget(
      sub: parts[0],
      kind: parts[1],
      id: parts[2],
      label: parts.sublist(3).join('|'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DelegationTarget && other.key == key && other.sub == sub;

  @override
  int get hashCode => Object.hash(sub, key);
}

/// يُعيَّن في main.dart: «تفويض جديد» معبّأ بالقسم والعنصر المحدد (عقار،
/// وحدة بعينها، مركبة، نشاط) — من «تفويض آخرين» في صفحة العنصر.
Future<void> Function(
  BuildContext context, {
  required String sub,
  required DelegationTarget target,
})?
openDelegationForTarget;

class DelegationTargets {
  DelegationTargets._();

  /// القسم الفرعي لفئة الأصل: العقارات / الأنشطة التجارية / المركبات.
  static String subOfCategory(String category) => switch (category) {
    'real_estate' => 'العقارات',
    'activity' || 'business' => 'الأنشطة التجارية',
    _ => 'المركبات ووسائل النقل',
  };

  /// العنصر «العقار/المركبة/النشاط كاملًا» — بنفس صيغة قائمة الاختيار.
  static DelegationTarget asset({
    required String category,
    required String assetId,
    required String title,
  }) => DelegationTarget(
    sub: subOfCategory(category),
    kind: 'asset',
    id: assetId,
    label: title,
  );

  /// وحدة بعينها داخل البناية — بنفس معرّف [_unitsOf] فيُطابق الاختيار.
  static DelegationTarget unit({
    required String assetId,
    required String building,
    required String name,
    required String number,
    required String type,
    int index = 0,
  }) {
    final unitLabel = [
      if (name.trim().isNotEmpty) name.trim() else if (type.trim().isNotEmpty) type.trim(),
      if (number.trim().isNotEmpty) number.trim(),
    ].join(' ');
    return DelegationTarget(
      sub: 'العقارات',
      kind: 'unit',
      id: '$assetId#${number.trim().isNotEmpty ? number.trim() : (name.trim().isNotEmpty ? name.trim() : '$index')}',
      label: '$building — ${unitLabel.isEmpty ? 'وحدة ${index + 1}' : unitLabel}',
    );
  }

  /// الأقسام الفرعية التي يمكن التفويض فيها على عناصر بعينها.
  static const _personalSlugs = {
    'مالية': 'financial',
    'مستند': 'document',
    'المتابعة والتخطيط': 'organization',
    'أدوية وبيانات وكلمات سر': 'medical_accounts',
    'نمط الحياة': 'lifestyle',
    'مواقع وأماكن': 'location',
    'عهدة مالية': 'custody',
  };

  static const _sharedTypes = {
    'مشاركات مشتركة',
    'الرحلة / السفر',
    'جمعية مالية',
  };

  static const _assetCategories = {
    'العقارات': 'real_estate',
    'الأنشطة التجارية': 'business',
    'المركبات ووسائل النقل': 'equipment',
  };

  static bool supports(String main, String sub) => switch (main) {
    'الالتزامات الشخصية' => _personalSlugs.containsKey(sub),
    'الالتزامات المشتركة' => _sharedTypes.contains(sub),
    'الأفراد والجهات' => sub == 'الأفراد' || sub == 'الجهات والشركات',
    'العقارات والأنشطة والمركبات' => _assetCategories.containsKey(sub),
    _ => false,
  };

  /// اسم الجمع المستخدم في العناوين: «كل العهد»، «كل العقارات»...
  static String pluralOf(String sub) => switch (sub) {
    'عهدة مالية' => 'العهد المالية',
    'مستند' => 'المستندات',
    'مالية' => 'السجلات المالية',
    'مواقع وأماكن' => 'المواقع والأماكن',
    'الرحلة / السفر' => 'الرحلات',
    'جمعية مالية' => 'الجمعيات المالية',
    _ => sub,
  };

  static String _money(int value) =>
      AppSettings.maskAmount('$value ${AppSettings.currencySuffix}');

  static String _join(Iterable<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' • ');

  static List<DelegationTarget> _unitsOf(
    String sub,
    String assetId,
    String building,
    String? unitsJson,
  ) {
    if (unitsJson == null || unitsJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(unitsJson);
      if (decoded is! List) return const [];
      final units = <DelegationTarget>[];
      for (var i = 0; i < decoded.length; i++) {
        final unit = decoded[i];
        if (unit is! Map) continue;
        final name = '${unit['name'] ?? ''}'.trim();
        final number = '${unit['unitNumber'] ?? ''}'.trim();
        final type = '${unit['type'] ?? ''}'.trim();
        final unitLabel = [
          if (name.isNotEmpty) name else if (type.isNotEmpty) type,
          if (number.isNotEmpty) number,
        ].join(' ');
        units.add(
          DelegationTarget(
            sub: sub,
            kind: 'unit',
            id: '$assetId#${number.isNotEmpty ? number : (name.isNotEmpty ? name : '$i')}',
            label: '$building — ${unitLabel.isEmpty ? 'وحدة ${i + 1}' : unitLabel}',
            subtitle: _join(['وحدة داخل $building', type, '${unit['status'] ?? ''}']),
          ),
        );
      }
      return units;
    } catch (_) {
      return const [];
    }
  }

  /// يجلب عناصر القسم الفرعي من مصدرها الفعلي.
  static Future<List<DelegationTarget>> load(String main, String sub) async {
    switch (main) {
      case 'الالتزامات الشخصية':
        {
          final slug = _personalSlugs[sub];
          if (slug == null) return const [];
          final rows = await SupabasePersonalEntriesRepository().fetchAll();
          return [
            for (final row in rows)
              if (row.id != null &&
                  row.status != 'محذوف' &&
                  (row.category == slug ||
                      (slug == 'custody' && row.entryType == 'عهدة مالية')))
                DelegationTarget(
                  sub: sub,
                  kind: 'personal',
                  id: row.id!,
                  label: row.title.trim().isEmpty ? row.entryType : row.title,
                  subtitle: _join([
                    if (row.title.trim().isNotEmpty) row.entryType,
                    row.details['اسم المستلم'] ?? '',
                    if (row.amount != 0) _money(row.amount),
                    row.status,
                  ]),
                ),
          ];
        }
      case 'الالتزامات المشتركة':
        {
          final rows = await SupabaseSharedEntriesRepository().fetchAll();
          String canonical(String t) => t == 'اللقاءات' ? 'مشاركات مشتركة' : t;
          return [
            for (final row in rows)
              if (row.id != null &&
                  row.status != 'محذوف' &&
                  canonical(row.entryType) == sub)
                DelegationTarget(
                  sub: sub,
                  kind: 'shared',
                  id: row.id!,
                  label: row.title.trim().isEmpty ? row.entryType : row.title,
                  subtitle: _join([
                    if (row.amount != 0) _money(row.amount),
                    row.dueDate,
                    row.status,
                  ]),
                ),
          ];
        }
      case 'الأفراد والجهات':
        {
          final wantEntities = sub == 'الجهات والشركات';
          final entries = await PeopleDirectoryStore.load();
          return [
            for (final entry in entries)
              if (entry.isEntity == wantEntities &&
                  entry.fullName.trim().isNotEmpty)
                DelegationTarget(
                  sub: sub,
                  kind: 'person',
                  id: entry.fullName.trim(),
                  label: entry.fullName.trim(),
                  subtitle: _join([entry.categoryName, entry.roleTitle]),
                ),
          ];
        }
      case 'العقارات والأنشطة والمركبات':
        {
          final category = _assetCategories[sub];
          if (category == null) return const [];
          final assets = await SupabaseProjectAssetsRepository().fetchAssets();
          final result = <DelegationTarget>[];
          for (final asset in assets) {
            if (asset.id == null ||
                asset.category != category ||
                asset.status == 'محذوف') {
              continue;
            }
            result.add(
              DelegationTarget(
                sub: sub,
                kind: 'asset',
                id: asset.id!,
                label: asset.title,
                subtitle: _join([
                  asset.subType,
                  asset.locationOrType ?? '',
                  asset.status,
                ]),
              ),
            );
            // وحدات البناية تحتها مباشرة: تفويض على شقة/محل بعينه.
            if (category == 'real_estate') {
              result.addAll(_unitsOf(sub, asset.id!, asset.title, asset.unitsJson));
            }
          }
          return result;
        }
    }
    return const [];
  }
}
