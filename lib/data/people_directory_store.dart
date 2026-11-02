import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// دليل «الأفراد والجهات» المشترك.
///
/// شاشة إدارة الأشخاص تحفظ سجلاتها في SharedPreferences تحت مفتاح واحد.
/// هذا الملف هو الباب الرسمي لذلك المخزن من بقية التطبيق: أي شخص يُسجَّل
/// في أي مكان (مؤجر أو مستأجر أو ممثل مستأجر في عقد إيجار مثلًا) يُكتب
/// هنا فورًا فيظهر في «الأفراد والجهات»، وأي نموذج يحتاج شخصًا يقرأ من
/// هنا بدل إعادة كتابة البيانات يدويًا.
///
/// الشكل المكتوب مطابق تمامًا لـ `_PersonItem.toMap()` في شاشة الأشخاص،
/// فلا يحتاج الأمر أي تعديل على قاعدة البيانات ولا على تلك الشاشة.
class PeopleDirectoryEntry {
  const PeopleDirectoryEntry({
    required this.fullName,
    required this.typeKey,
    required this.categoryName,
    required this.roleTitle,
    required this.details,
  });

  final String fullName;
  final String typeKey;
  final String categoryName;
  final String roleTitle;
  final Map<String, String> details;

  bool get isEntity => typeKey.startsWith('entity_');

  String detail(String key) => details[key] ?? '';

  /// أول قيمة غير فارغة من عدة مفاتيح محتملة (الهاتف قد يكون «رقم الجوال»
  /// في سجل و«رقم الهاتف» في آخر).
  String firstOf(List<String> keys) {
    for (final key in keys) {
      final value = details[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}

class PeopleDirectoryStore {
  const PeopleDirectoryStore._();

  /// نفس مفتاح شاشة «الأفراد والجهات» — لا تغيّره.
  static const storageKey = 'people_management_records_v1';

  /// تصنيفات جاهزة تُستعمل عند التسجيل التلقائي من نماذج أخرى.
  static const typeLandlord = 'person_landlord';
  static const typeTenant = 'person_tenant';
  static const typeRepresentative = 'person_representative';
  static const typeCompany = 'entity_company';

  static const categoryLandlord = 'مؤجر';
  static const categoryTenant = 'مستأجر';
  static const categoryRepresentative = 'مندوب';
  static const categoryCompany = 'الشركات';

  static String _todayStamp() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static Future<List<Map<String, dynamic>>> _readRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: true);
    } catch (_) {
      // مخزون تالف: لا نكتب فوقه ولا نُسقط الشاشة — نتصرف كأنه فارغ.
      return <Map<String, dynamic>>[];
    }
  }

  /// كل السجلات المحفوظة، للاختيار منها في أي نموذج.
  static Future<List<PeopleDirectoryEntry>> load() async {
    final rows = await _readRaw();
    return rows.map((row) {
      final details = <String, String>{};
      final rawDetails = row['details'];
      if (rawDetails is Map) {
        rawDetails.forEach((key, value) {
          details['$key'] = '${value ?? ''}';
        });
      }
      return PeopleDirectoryEntry(
        fullName: row['fullName']?.toString() ?? '',
        typeKey: row['typeKey']?.toString() ?? 'person_other',
        categoryName: row['categoryName']?.toString() ?? 'أخرى',
        roleTitle: row['roleTitle']?.toString() ?? '',
        details: details,
      );
    }).where((entry) => entry.fullName.trim().isNotEmpty).toList();
  }

  /// يضيف شخصًا/جهة إلى الدليل، أو يدمج بياناته إن كان الاسم مسجّلًا.
  ///
  /// الدمج لا يمسح شيئًا: القيم الجديدة غير الفارغة تحدّث القديمة فقط،
  /// وتُضاف سطر إلى سجل النشاط يوضح مصدر التسجيل (عقد الإيجار مثلًا).
  static Future<void> upsert({
    required String fullName,
    required String typeKey,
    required String categoryName,
    Map<String, String> details = const {},
    String roleTitle = '',
    String sourceNote = '',
  }) async {
    final name = fullName.trim();
    if (name.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = await _readRaw();
      final index = rows.indexWhere(
        (row) => _normalize(row['fullName']?.toString() ?? '') ==
            _normalize(name),
      );
      final cleanDetails = <String, String>{};
      details.forEach((key, value) {
        if (value.trim().isNotEmpty) cleanDetails[key] = value.trim();
      });

      if (index == -1) {
        rows.add(<String, dynamic>{
          'fullName': name,
          'nickName': '',
          'roleTitle': roleTitle,
          'badge': categoryName,
          'badgeColor': 0xFF0A5A50,
          'statusNote': '',
          'extraNote': sourceNote,
          'typeKey': typeKey,
          'categoryName': categoryName,
          'additionalCategoryNames': <String>[],
          'activityLog': <String>[
            if (sourceNote.trim().isNotEmpty)
              '${_todayStamp()} · $sourceNote',
          ],
          'dueToYou': 0,
          'dueOnYou': 0,
          'openTasks': 0,
          'documentsCount': 0,
          'lastUpdate': _todayStamp(),
          'createdAt': _todayStamp(),
          'sharedCommitments': <String>[],
          'documents': <String>[],
          'details': cleanDetails,
          'isPinned': false,
          'isFrozen': false,
        });
      } else {
        final row = rows[index];
        final merged = <String, String>{};
        final existing = row['details'];
        if (existing is Map) {
          existing.forEach((key, value) {
            merged['$key'] = '${value ?? ''}';
          });
        }
        merged.addAll(cleanDetails);
        row['details'] = merged;
        row['lastUpdate'] = _todayStamp();

        // تصنيف إضافي بدل استبدال تصنيفه الأصلي: شخص مسجّل «قريب» ثم صار
        // مستأجرًا يبقى قريبًا ويُضاف له «مستأجر».
        final currentCategory = row['categoryName']?.toString() ?? '';
        if (currentCategory != categoryName) {
          final extras = <String>[];
          final rawExtras = row['additionalCategoryNames'];
          if (rawExtras is List) {
            extras.addAll(rawExtras.map((e) => '$e'));
          }
          if (!extras.contains(categoryName)) extras.add(categoryName);
          row['additionalCategoryNames'] = extras;
        }

        if (sourceNote.trim().isNotEmpty) {
          final log = <String>[];
          final rawLog = row['activityLog'];
          if (rawLog is List) log.addAll(rawLog.map((e) => '$e'));
          log.add('${_todayStamp()} · $sourceNote');
          row['activityLog'] = log;
        }
        rows[index] = row;
      }

      await prefs.setString(storageKey, jsonEncode(rows));
    } catch (_) {
      // التسجيل في الدليل خدمة مساعدة: فشلها لا يُفشل حفظ العقد نفسه.
    }
  }
}
