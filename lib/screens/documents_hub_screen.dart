import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text, Align;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_reminders_store.dart';
import '../data/document_store.dart';
import '../data/fundly_auth.dart';
import 'note_and_sign_screens.dart';
import '../data/personal_entries_repository.dart';
import '../data/project_assets_repository.dart';
import '../data/shared_entries_repository.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/plan_gate.dart';
import '../widgets/shared/search_matching.dart';

// =============================================================================
// المستندات: كل ما فيه مستند في التطبيق، مجمّعًا حسب القسم ثم حسب النوع.
// القراءة فقط من البيانات الموجودة (لا جداول جديدة): مستندات الالتزامات
// ومرفقاتها، وثائق الأفراد والجهات، ومستندات العقارات والأنشطة والمركبات
// وشهاداتها.
// =============================================================================

/// أقسام صفحة المستندات بترتيبها.
const kDocumentModules = <String>[
  'الالتزامات الشخصية',
  'الالتزامات المشتركة',
  'الأفراد والجهات',
  'العقارات',
  'الأنشطة التجارية',
  'المركبات ووسائل النقل',
];

const _moduleIcons = <String, IconData>{
  'الالتزامات الشخصية': Icons.person_outline_rounded,
  'الالتزامات المشتركة': Icons.groups_2_outlined,
  'الأفراد والجهات': Icons.badge_outlined,
  'العقارات': Icons.apartment_rounded,
  'الأنشطة التجارية': Icons.storefront_rounded,
  'المركبات ووسائل النقل': Icons.directions_car_rounded,
};

const _moduleColors = <String, Color>{
  'الالتزامات الشخصية': Color(0xFF0E7161),
  'الالتزامات المشتركة': Color(0xFF178F7B),
  'الأفراد والجهات': Color(0xFF0A5A50),
  'العقارات': Color(0xFFCE8422),
  'الأنشطة التجارية': Color(0xFFA6691A),
  'المركبات ووسائل النقل': Color(0xFF0E7161),
};

/// مستند واحد أيًّا كان مصدره.
class AppDocument {
  const AppDocument({
    required this.module,
    required this.group,
    required this.title,
    this.owner = '',
    this.number = '',
    this.expiry,
    this.localPath = '',
    this.storageBucket = '',
    this.storagePath = '',
    this.section = '',
    this.ownerId = '',
  });

  final String module;

  /// التقسيم الأعلى داخل القسم (وثائق شخصية، رحلة وسفر، الأفراد...).
  final String section;

  /// معرّف العنصر صاحب المستند (التزام، شخص، أصل) — للتجميع تحته.
  final String ownerId;

  /// النوع الذي يُجمَّع تحته (هوية، جواز سفر، عقد، شهادة...).
  final String group;
  final String title;

  /// صاحب المستند: الالتزام أو الشخص أو العقار/المركبة.
  final String owner;
  final String number;
  final DateTime? expiry;

  /// ملف محفوظ على الجهاز.
  final String localPath;

  /// ملف مرفوع إلى الخادم.
  final String storageBucket;
  final String storagePath;

  bool get hasFile => localPath.isNotEmpty || storagePath.isNotEmpty;

  /// الأيام المتبقية حتى الانتهاء (سالب = منتهٍ).
  int? get daysLeft {
    final date = expiry;
    if (date == null) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    return DateUtils.dateOnly(date).difference(today).inDays;
  }

  bool get isExpired => (daysLeft ?? 1) < 0;
  bool get isExpiringSoon {
    final days = daysLeft;
    return days != null && days >= 0 && days <= 30;
  }
}

DateTime? _parseDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final parts = text.split(RegExp(r'[/\-.]'));
  if (parts.length == 3) {
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    if (a != null && b != null && c != null) {
      // yyyy/mm/dd أو dd/mm/yyyy.
      if (a > 999) return DateTime(a, b, c);
      if (c > 999) return DateTime(c, b, a);
    }
  }
  return DateTime.tryParse(text);
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// يجمع المستندات من كل الأقسام. أي مصدر يفشل لا يُسقط البقية.
class DocumentsHub {
  DocumentsHub._();

  static const _trash = 'محذوف';
  static const _peopleStorageKey = 'people_management_records_v1';
  static const _personalBucket = 'personal-entry-attachments';
  static const _sharedBucket = 'shared-entry-attachments';
  static const _identityDocs = ['الهوية', 'جواز السفر', 'الضمان الصحي'];

  /// المستندات الشخصية: ثلاثة تقسيمات وأنواع كلٍّ منها.
  static const personalTypes = <String, List<String>>{
    'وثائق شخصية': [
      'هوية',
      'جواز سفر',
      'اقامة وتأشيرة',
      'رخصة قيادة',
      'ملكية سيارة',
      'تأمين سيارة',
      'تأمين صحي',
    ],
    'الضمانات': ['ضمانات'],
    'الوثائق العامة': [
      'مستند دراسي',
      'مستند سفر',
      'مستند بنكي',
      'تقرير طبي',
      'تصاريح',
      'فواتير',
      'ايصالات',
    ],
  };

  static String personalSection(String type) {
    final text = type.trim();
    for (final entry in personalTypes.entries) {
      if (entry.value.contains(text)) return entry.key;
    }
    return 'الوثائق العامة';
  }

  static const sharedSections = [
    'مشاركات مشتركة',
    'رحلة وسفر',
    'تحديد أدوار',
  ];

  static String sharedSection(String entryType) => switch (entryType.trim()) {
    'مشاركات مشتركة' || 'اللقاءات' => 'مشاركات مشتركة',
    'الرحلة / السفر' => 'رحلة وسفر',
    'جمعية مالية' => 'تحديد أدوار',
    '' => 'أخرى',
    final other => other,
  };

  static const peopleSections = ['الأفراد', 'الجهات'];

  static String personSection(Map person) =>
      '${person['typeKey'] ?? ''}'.startsWith('entity_') ? 'الجهات' : 'الأفراد';

  static const vehicleSections = ['مركبات برية', 'مركبات بحرية'];

  /// العقار والنشاط بتصنيفهما، والمركبات برية أو بحرية.
  static String assetSection(ProjectAssetRecord asset) {
    if (asset.category == 'equipment') {
      final vehicleClass = _metaOf(asset)['تصنيف المركبة'] ?? '';
      return vehicleClass == 'مركبات بحرية' ? vehicleClass : 'مركبات برية';
    }
    final sub = asset.subType.trim();
    return sub.isEmpty ? 'أخرى' : sub;
  }

  /// التقسيمات الثابتة لكل قسم (تظهر ولو فارغة).
  static List<String> fixedSections(String module) => switch (module) {
    'الالتزامات الشخصية' => personalTypes.keys.toList(growable: false),
    'الالتزامات المشتركة' => sharedSections,
    'الأفراد والجهات' => peopleSections,
    'المركبات ووسائل النقل' => vehicleSections,
    _ => const <String>[],
  };

  static Future<List<AppDocument>> loadAll() async {
    final results = await Future.wait([
      _personal(),
      _shared(),
      _people(),
      _assets(),
    ]);
    return [for (final list in results) ...list];
  }

  static Future<List<AppDocument>> _personal() async {
    try {
      final rows = await SupabasePersonalEntriesRepository().fetchAll();
      final out = <AppDocument>[];
      for (final row in rows) {
        if (row.status == _trash) continue;
        final d = row.details;
        final file = (row.attachmentUrl ?? '').trim();
        // المستندات الإضافية، وفواتير صرف العهدة، وفواتير الدفعات والسداد:
        // تظهر هنا كلها، كما تظهر داخل صفحة الالتزام نفسه.
        out.addAll(_personalInnerFiles(row));
        if (row.entryType == 'مستند') {
          final type = (d['نوع المستند'] ?? '').trim();
          out.add(
            AppDocument(
              module: 'الالتزامات الشخصية',
              group: type.isEmpty ? 'مستندات أخرى' : type,
              section: personalSection(type),
              ownerId: row.id ?? '',
              title: row.title,
              owner: (d['الجهة المصدرة'] ?? '').trim(),
              number: (d['رقم المستند'] ?? '').trim(),
              expiry: _parseDate(d['تاريخ الانتهاء'] ?? row.dueDate),
              storageBucket: _personalBucket,
              storagePath: file,
            ),
          );
        } else if (file.isNotEmpty) {
          // مرفق داخل التزام آخر (فاتورة، إيصال، مستند مضاف...).
          final name = (d['اسم المرفق الإضافي'] ?? '').trim();
          out.add(
            AppDocument(
              module: 'الالتزامات الشخصية',
              group: 'مرفقات: ${row.entryType.isEmpty ? 'أخرى' : row.entryType}',
              section: 'الوثائق العامة',
              ownerId: row.id ?? '',
              title: name.isEmpty ? row.title : name,
              owner: row.title,
              expiry: _parseDate(d['تاريخ انتهاء المرفق']),
              storageBucket: _personalBucket,
              storagePath: file,
            ),
          );
        }
      }
      return out;
    } catch (error) {
      debugPrint('DocumentsHub personal failed: $error');
      return const [];
    }
  }

  static List<Map<String, String>> _jsonRows(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final row in decoded.whereType<Map>())
          row.map((k, v) => MapEntry('$k', v is Map ? jsonEncode(v) : '${v ?? ''}')),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// ملفات داخل سجل شخصي: مستندات إضافية، فواتير صرف العهدة، فواتير
  /// الدفعات والسداد.
  static List<AppDocument> _personalInnerFiles(PersonalEntryRecord row) {
    final out = <AppDocument>[];
    final type = row.entryType.isEmpty ? 'أخرى' : row.entryType;
    for (final extra in _jsonRows(row.details['مرفقات إضافية'])) {
      final path = (extra['path'] ?? '').trim();
      if (path.isEmpty) continue;
      out.add(
        AppDocument(
          module: 'الالتزامات الشخصية',
          group: 'مرفقات: $type',
          section: 'الوثائق العامة',
          ownerId: row.id ?? '',
          title: (extra['name'] ?? '').trim().isEmpty
              ? row.title
              : extra['name']!.trim(),
          owner: row.title,
          expiry: _parseDate(extra['expiry']),
          storageBucket: _personalBucket,
          storagePath: path,
        ),
      );
    }
    for (final (key, group) in const [
      ('سجل صرفيات العهدة', 'فواتير صرف العهدة'),
      ('سجل دفعات الالتزام', 'فواتير الدفعات والسداد'),
    ]) {
      for (final payment in _jsonRows(row.details[key])) {
        final path = (payment['مرفق الفاتورة'] ?? '').trim();
        if (path.isEmpty) continue;
        final purpose = (payment['الغرض'] ?? payment['البيان'] ?? '').trim();
        out.add(
          AppDocument(
            module: 'الالتزامات الشخصية',
            group: group,
            section: 'الوثائق العامة',
            ownerId: row.id ?? '',
            title: [
              if (purpose.isNotEmpty) purpose,
              (payment['المبلغ'] ?? '').trim(),
              (payment['التاريخ'] ?? '').trim(),
            ].where((s) => s.isNotEmpty).join(' • '),
            owner: row.title,
            storageBucket: _personalBucket,
            storagePath: path,
          ),
        );
      }
    }
    return out;
  }

  /// ملفات داخل رحلة أو مشاركة: فواتير المصروفات (من أي عضو)، إيصالات
  /// التسوية والمساهمات، ومستندات تبويب «مستندات».
  static List<AppDocument> _sharedInnerFiles(SharedEntryRecord row) {
    final out = <AppDocument>[];
    final section = sharedSection(row.entryType);
    void add(String group, String title, String path, {String expiry = ''}) {
      out.add(
        AppDocument(
          module: 'الالتزامات المشتركة',
          section: section,
          ownerId: row.id ?? '',
          group: group,
          title: title.trim().isEmpty ? row.title : title,
          owner: row.title,
          expiry: _parseDate(expiry),
          localPath: path,
        ),
      );
    }

    for (final e in _jsonRows(row.details['سجل المصروفات المشتركة'])) {
      final path = (e['receipt'] ?? '').trim();
      if (path.isEmpty) continue;
      add(
        'فواتير المصروفات',
        [
          (e['description'] ?? '').trim(),
          (e['payer'] ?? '').trim(),
          (e['date'] ?? '').trim(),
        ].where((s) => s.isNotEmpty).join(' • '),
        path,
      );
    }
    for (final (key, group) in const [
      ('سجل التسويات', 'إيصالات التسوية'),
      ('سجل المساهمات', 'إيصالات المساهمات'),
    ]) {
      for (final r in _jsonRows(row.details[key])) {
        final path = (r['receipt'] ?? '').trim();
        if (path.isEmpty) continue;
        add(
          group,
          [
            (r['from'] ?? r['member'] ?? '').trim(),
            (r['date'] ?? '').trim(),
          ].where((s) => s.isNotEmpty).join(' • '),
          path,
        );
      }
    }
    for (final doc in _jsonRows(row.details['مستندات'])) {
      final extra = _jsonExtra(doc['extra']);
      final path = (extra['المرفق'] ?? '').trim();
      final date = (doc['date'] ?? '').trim();
      if (path.isEmpty && date.isEmpty) continue;
      add(
        (doc['kind'] ?? '').trim().isEmpty ? 'مستندات' : doc['kind']!.trim(),
        (doc['title'] ?? '').trim(),
        path,
        expiry: date,
      );
    }
    return out;
  }

  static Map<String, String> _jsonExtra(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry('$k', '${v ?? ''}'));
    } catch (_) {
      return const {};
    }
  }

  static Future<List<AppDocument>> _shared() async {
    try {
      final rows = await SupabaseSharedEntriesRepository().fetchAll();
      return [
        for (final row in rows)
          if (row.status != _trash) ..._sharedInnerFiles(row),
        for (final row in rows)
          if (row.status != _trash &&
              (row.attachmentUrl ?? '').trim().isNotEmpty)
            AppDocument(
              module: 'الالتزامات المشتركة',
              section: sharedSection(row.entryType),
              ownerId: row.id ?? '',
              group: (row.details['نوع المستند المرفق'] ?? '').trim().isNotEmpty
                  ? row.details['نوع المستند المرفق']!.trim()
                  : (row.entryType.isEmpty ? 'أخرى' : row.entryType),
              title: (row.details['اسم المستند المرفق'] ?? '').trim().isNotEmpty
                  ? row.details['اسم المستند المرفق']!.trim()
                  : row.title,
              owner: row.title,
              expiry: _parseDate(
                row.details['تاريخ انتهاء المستند'] ?? row.dueDate,
              ),
              storageBucket: _sharedBucket,
              storagePath: row.attachmentUrl!.trim(),
            ),
      ];
    } catch (error) {
      debugPrint('DocumentsHub shared failed: $error');
      return const [];
    }
  }

  static Future<List<AppDocument>> _people() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_peopleStorageKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <AppDocument>[];
      var index = -1;
      for (final person in decoded.whereType<Map>()) {
        index++;
        final section = personSection(person);
        final ownerId = 'person:$index';
        final name = '${person['fullName'] ?? ''}'.trim();
        final rawDetails = person['details'];
        if (rawDetails is! Map) continue;
        final details = {
          for (final entry in rawDetails.entries)
            '${entry.key}': '${entry.value ?? ''}'.trim(),
        };
        // أسماء الوثائق: «مرفق X» و«انتهاء X»، و«رقم X» لوثائق الهوية فقط
        // (فـ«رقم الهاتف» ليس مستندًا).
        final names = <String>{};
        for (final key in details.keys) {
          if (key.startsWith('مرفق ') && key != 'مرفقات أخرى') {
            names.add(key.substring('مرفق '.length));
          } else if (key.startsWith('انتهاء ')) {
            names.add(key.substring('انتهاء '.length));
          }
        }
        for (final doc in _identityDocs) {
          if ((details['رقم $doc'] ?? '').isNotEmpty) names.add(doc);
        }
        for (final doc in names) {
          final number = details['رقم $doc'] ?? '';
          final expiry = details['انتهاء $doc'] ?? '';
          final file = details['مرفق $doc'] ?? '';
          if (number.isEmpty && expiry.isEmpty && file.isEmpty) continue;
          out.add(
            AppDocument(
              module: 'الأفراد والجهات',
              section: section,
              ownerId: ownerId,
              group: doc,
              title: doc,
              owner: name,
              number: number,
              expiry: _parseDate(expiry),
              localPath: file,
            ),
          );
        }
        for (final path in (details['مرفقات أخرى'] ?? '').split('|')) {
          if (path.trim().isEmpty) continue;
          out.add(
            AppDocument(
              module: 'الأفراد والجهات',
              section: section,
              ownerId: ownerId,
              group: 'مرفقات أخرى',
              title: DocumentStore.fileName(path.trim()),
              owner: name,
              localPath: path.trim(),
            ),
          );
        }
      }
      return out;
    } catch (error) {
      debugPrint('DocumentsHub people failed: $error');
      return const [];
    }
  }

  static String _assetModule(String category) => switch (category) {
    'real_estate' => 'العقارات',
    'activity' => 'الأنشطة التجارية',
    _ => 'المركبات ووسائل النقل',
  };

  /// البيانات الرسمية المحفوظة في سجل الأصل (سطر «##meta##»).
  static Map<String, String> _metaOf(ProjectAssetRecord record) {
    const prefix = '##meta##';
    final raw = record.logsJson;
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      for (final line in decoded) {
        final text = '$line';
        if (!text.startsWith(prefix)) continue;
        final map = jsonDecode(text.substring(prefix.length));
        if (map is! Map) continue;
        return {
          for (final entry in map.entries)
            '${entry.key}': '${entry.value ?? ''}'.trim(),
        };
      }
    } catch (_) {}
    return const {};
  }

  static Future<List<AppDocument>> _assets() async {
    try {
      final repository = SupabaseProjectAssetsRepository();
      final assets = [
        for (final asset in await repository.fetchAssets())
          if (asset.status != _trash) asset,
      ];
      final byId = {
        for (final asset in assets)
          if (asset.id != null) asset.id!: asset,
      };
      final out = <AppDocument>[];
      try {
        for (final entry in await repository.fetchAllEntries()) {
          if (entry.kind != ProjectAssetEntryRecord.kindDocument) continue;
          final asset = byId[entry.assetId];
          if (asset == null) continue;
          final data = entry.data;
          final type = (data['نوع المستند'] ?? '').trim();
          final name = (data['اسم المستند'] ?? '').trim();
          out.add(
            AppDocument(
              module: _assetModule(asset.category),
              section: assetSection(asset),
              ownerId: asset.id ?? '',
              group: type.isEmpty ? 'مستندات' : type,
              title: name.isEmpty ? (type.isEmpty ? 'مستند' : type) : name,
              owner: asset.title,
              number: (data['رقم المستند'] ?? '').trim(),
              expiry: _parseDate(data['تاريخ الانتهاء']),
              localPath: (data[DocumentStore.kFileField] ?? '').trim(),
            ),
          );
        }
      } catch (error) {
        debugPrint('DocumentsHub asset entries failed: $error');
      }
      // شهادات المركبات والمعدات وتواريخها من بياناتها الرسمية.
      const certificates = [
        ('شهادة سلامة المعدة', 'انتهاء شهادة السلامة'),
        ('شهادة الضمان', 'انتهاء شهادة الضمان'),
        ('شهادة مشغل المعدة', 'انتهاء شهادة المشغل'),
        ('التأمين', 'تاريخ انتهاء التأمين'),
        ('الملكية', 'تاريخ انتهاء الملكية'),
      ];
      for (final asset in assets) {
        if (asset.category != 'equipment') continue;
        final meta = _metaOf(asset);
        for (final (label, expiryKey) in certificates) {
          final value = meta[label] ?? '';
          final expiry = meta[expiryKey] ?? '';
          if (value.isEmpty && expiry.isEmpty) continue;
          final isFile = value.contains('/') || value.contains(r'\');
          out.add(
            AppDocument(
              module: 'المركبات ووسائل النقل',
              section: assetSection(asset),
              ownerId: asset.id ?? '',
              group: label,
              title: label,
              owner: asset.title,
              number: label == 'الملكية'
                  ? (meta['رقم اللوحة'] ?? meta['رقم التسجيل البحري'] ?? '')
                  : '',
              expiry: _parseDate(expiry),
              localPath: isFile ? value : '',
            ),
          );
        }
        for (final line in (meta['مستندات أخرى'] ?? '').split('\n')) {
          final path = line.trim();
          if (path.isEmpty) continue;
          out.add(
            AppDocument(
              module: 'المركبات ووسائل النقل',
              section: assetSection(asset),
              ownerId: asset.id ?? '',
              group: 'مستندات أخرى',
              title: DocumentStore.fileName(path),
              owner: asset.title,
              localPath: path,
            ),
          );
        }
      }
      return out;
    } catch (error) {
      debugPrint('DocumentsHub assets failed: $error');
      return const [];
    }
  }

  /// يفتح ملف المستند: المحفوظ على الجهاز مباشرة، والمرفوع برابط مؤقت.
  static Future<String?> open(AppDocument doc) async {
    if (doc.localPath.isNotEmpty) return DocumentStore.open(doc.localPath);
    if (doc.storagePath.isEmpty) return 'لا يوجد ملف مرفق';
    try {
      final url = await Supabase.instance.client.storage
          .from(doc.storageBucket)
          .createSignedUrl(doc.storagePath, 3600);
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      return ok ? null : 'تعذّر فتح الملف';
    } catch (_) {
      return 'تعذّر فتح الملف';
    }
  }
}

// ============================== الواجهة ==============================

/// تبويب «المستندات» في الشريط السفلي: ستة مستطيلات ثابتة للأقسام (لا
/// تُحذف)، وتحتها «عام» — ما تضيفه بنفسك من + (مجلد، ملف، صورة من المعرض،
/// التقاط صورة) يظهر مربعات جنب بعض.
class DocumentsHubPage extends StatefulWidget {
  const DocumentsHubPage({super.key});

  @override
  State<DocumentsHubPage> createState() => _DocumentsHubPageState();
}

class _DocumentsHubPageState extends State<DocumentsHubPage> {
  static const _accent = Color(0xFF0A5A50);
  late Future<List<AppDocument>> _future = DocumentsHub.loadAll();
  final GlobalKey<_GeneralDocsGridState> _generalKey = GlobalKey();

  Future<void> _reload() async {
    final next = DocumentsHub.loadAll();
    setState(() => _future = next);
    await next;
    await _generalKey.currentState?._load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text(
            'المستندات',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppTheme.title,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        // زر + عائم يبقى ظاهرًا مع التمرير.
        floatingActionButton: FloatingActionButton(
          heroTag: 'general-docs-add',
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          tooltip: AppTr.tr('إضافة'),
          onPressed: () => _generalKey.currentState?._openAddMenu(),
          child: const Icon(Icons.add_rounded),
        ),
        body: RefreshIndicator(
          color: _accent,
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _header(),
              const SizedBox(height: 16),
              FutureBuilder<List<AppDocument>>(
                future: _future,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState != ConnectionState.done;
                  final docs = snapshot.data ?? const <AppDocument>[];
                  return GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    // مربعات صغيرة: أيقونة واسم وعدد في سطرين.
                    childAspectRatio: 1.55,
                    children: [
                      for (final module in kDocumentModules)
                        _moduleTile(
                          module,
                          docs
                              .where((doc) => doc.module == module)
                              .toList(growable: false),
                          loading,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              _GeneralDocsGrid(
                key: _generalKey,
                parentId: null,
                showAdd: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFF022E2A), Color(0xFF0A5A50), Color(0xFF0E7161)],
        ),
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: const Row(
        children: [
          Icon(Icons.folder_copy_rounded, color: Colors.white, size: 26),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كل مستنداتك في مكان واحد',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'كل المستندات منظّمة ومرتّبة حسب القسم',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// مستطيل قسم ثابت: أيقونته واسمه وعدد مستنداته.
  Widget _moduleTile(String module, List<AppDocument> docs, bool loading) {
    final color = _moduleColors[module] ?? _accent;
    final alerts = docs
        .where((doc) => doc.isExpired || doc.isExpiringSoon)
        .length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ModuleDocumentsScreen(
              module: module,
              documents: docs,
              onRefresh: DocumentsHub.loadAll,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _moduleIcons[module] ?? Icons.folder_outlined,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module,
                      maxLines: 4,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // عدد المستندات، وكم منها منتهٍ أو ينتهي خلال 30 يومًا.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        loading
                            ? '…'
                            : alerts > 0
                            ? '${docs.length} ${AppTr.tr('مستند')} · $alerts ${AppTr.tr('تنبيه')}'
                            : '${docs.length} ${AppTr.tr('مستند')}',
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: alerts > 0
                              ? const Color(0xFFC4392E)
                              : AppTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================ «عام» ============================

/// عنصر أضافه المستخدم بنفسه في «عام»: مجلد، ملف، أو صورة.
class GeneralDocItem {
  const GeneralDocItem({
    required this.id,
    required this.type,
    required this.name,
    this.path = '',
    this.parentId,
    this.createdAt = '',
    this.expiry = '',
    this.remindDays = -1,
    this.data = '',
  });

  static const folder = 'folder';
  static const file = 'file';
  static const image = 'image';
  static const note = 'note';

  /// «ملف» مكتوب من صفحة الكتابة (مثل الملاحظة) — يُحفظ في المكان الحالي.
  static const doc = 'doc';

  final String id;
  final String type;
  final String name;
  final String path;
  final String? parentId;
  final String createdAt;

  /// تاريخ الانتهاء «يوم/شهر/سنة» (اختياري).
  final String expiry;

  /// التذكير قبل الانتهاء بالأيام؛ -1 = بلا تذكير.
  final int remindDays;

  /// محتوى الملاحظة (JSON): نص، قائمة بعلامات صح، صور، جدول.
  final String data;

  /// منتهٍ أو ينتهي خلال 30 يومًا.
  bool get hasAlert {
    final date = AppRemindersStore.parseDisplayDate(expiry);
    if (date == null) return false;
    return date.isBefore(DateTime.now().add(const Duration(days: 30)));
  }

  GeneralDocItem copyWith({
    String? name,
    String? expiry,
    int? remindDays,
    String? data,
  }) => GeneralDocItem(
    id: id,
    type: type,
    name: name ?? this.name,
    path: path,
    parentId: parentId,
    createdAt: createdAt,
    expiry: expiry ?? this.expiry,
    remindDays: remindDays ?? this.remindDays,
    data: data ?? this.data,
  );

  /// نسخة منه في مكان آخر (نقل) أو باسم آخر.
  GeneralDocItem movedTo(String? parent, {String? name}) => GeneralDocItem(
    id: id,
    type: type,
    name: name ?? this.name,
    path: path,
    parentId: parent,
    createdAt: createdAt,
    expiry: expiry,
    remindDays: remindDays,
    data: data,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'name': name,
    'path': path,
    'parentId': parentId,
    'createdAt': createdAt,
    if (expiry.isNotEmpty) 'expiry': expiry,
    if (remindDays >= 0) 'remindDays': remindDays,
    if (data.isNotEmpty) 'data': data,
  };

  factory GeneralDocItem.fromMap(Map<String, dynamic> map) => GeneralDocItem(
    id: '${map['id'] ?? ''}',
    type: '${map['type'] ?? file}',
    name: '${map['name'] ?? ''}',
    path: '${map['path'] ?? ''}',
    parentId: map['parentId'] == null ? null : '${map['parentId']}',
    createdAt: '${map['createdAt'] ?? ''}',
    expiry: '${map['expiry'] ?? ''}',
    remindDays: int.tryParse('${map['remindDays'] ?? ''}') ?? -1,
    data: '${map['data'] ?? ''}',
  );
}

/// تخزين «عام» على الجهاز (الملفات نفسها في مجلد التطبيق).
class GeneralDocsStore {
  GeneralDocsStore._();

  static const _key = 'general_documents_v1';

  /// مجلد «ملاحظات» الثابت في «عام»: لا يُحذف ولا يُنقل، وكل ملاحظة جديدة
  /// تُحفظ فيه.
  static const notesFolderId = 'general-notes-folder';

  static const notesFolder = GeneralDocItem(
    id: notesFolderId,
    type: GeneralDocItem.folder,
    name: 'ملاحظات',
    createdAt: '2000-01-01T00:00:00.000',
  );

  static Future<List<GeneralDocItem>> loadAll() async {
    final items = await _loadRaw();
    if (!items.any((item) => item.id == notesFolderId)) {
      items.insert(0, notesFolder);
    }
    return items;
  }

  static Future<List<GeneralDocItem>> _loadRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final entry in decoded.whereType<Map>())
          GeneralDocItem.fromMap(Map<String, dynamic>.from(entry)),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<GeneralDocItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in items) item.toMap()]),
    );
  }
}

/// شبكة «عام» (أو محتوى مجلد): العنوان وزر +، ثم المربعات ثلاثة في السطر.
class _GeneralDocsGrid extends StatefulWidget {
  const _GeneralDocsGrid({
    super.key,
    required this.parentId,
    this.title,
    this.showAdd = true,
  });

  /// زر + بجانب العنوان (في الصفحة العامة زر عائم بدلًا منه).
  final bool showAdd;

  /// null = الجذر («عام»)، وإلا معرّف المجلد المفتوح.
  final String? parentId;
  final String? title;

  @override
  State<_GeneralDocsGrid> createState() => _GeneralDocsGridState();
}

class _GeneralDocsGridState extends State<_GeneralDocsGrid> {
  static const _accent = Color(0xFF0A5A50);
  List<GeneralDocItem> _all = const [];
  bool _loading = true;

  /// وضع التحديد (من ⋮ بجانب العنوان): نقل أو نسخ عدة عناصر.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// البحث بالاسم في كل «عام» (المجلدات وما بداخلها).
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static bool _isFixed(GeneralDocItem item) =>
      item.id == GeneralDocsStore.notesFolderId;

  /// العرض: مربعات (3 جنب بعض) أو مستطيلات تحت بعض — يُحفظ الاختيار.
  bool _listView = false;
  static const _listViewKey = 'general_docs_list_view';

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getBool(_listViewKey) ?? false;
      if (mounted && list != _listView) setState(() => _listView = list);
    } catch (_) {}
  }

  Future<void> _toggleViewMode() async {
    setState(() => _listView = !_listView);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_listViewKey, _listView);
    } catch (_) {}
  }

  void _tapItem(GeneralDocItem item) {
    if (!_selecting) {
      _open(item);
      return;
    }
    if (_isFixed(item)) return;
    setState(() {
      if (!_selected.remove(item.id)) _selected.add(item.id);
    });
  }

  /// سطر واحد في عرض المستطيلات: الأيقونة، الاسم، والتنبيه أو الانتهاء.
  Widget _row(GeneralDocItem item) {
    final fixed = _isFixed(item);
    final selected = _selected.contains(item.id);
    final isFolder = item.type == GeneralDocItem.folder;
    final isImage = item.type == GeneralDocItem.image;
    final count = isFolder
        ? _all.where((entry) => entry.parentId == item.id).length
        : 0;
    final inside = isFolder ? _descendantsOf(item.id) : const <String>{};
    final alerts = isFolder
        ? _all
              .where(
                (entry) =>
                    entry.id != item.id &&
                    inside.contains(entry.id) &&
                    entry.hasAlert,
              )
              .length
        : (item.hasAlert ? 1 : 0);
    final icon = fixed
        ? Icons.folder_special_rounded
        : _selecting && selected
        ? Icons.check_circle_rounded
        : isFolder
        ? Icons.folder_rounded
        : item.type == GeneralDocItem.note
        ? Icons.sticky_note_2_rounded
        : item.type == GeneralDocItem.doc
        ? Icons.description_rounded
        : isImage
        ? Icons.image_outlined
        : Icons.insert_drive_file_rounded;
    final iconColor = fixed || item.type == GeneralDocItem.note
        ? const Color(0xFFE0B400)
        : _selecting && selected
        ? _accent
        : isFolder
        ? const Color(0xFFCE8422)
        : _accent;
    final subtitle = alerts > 0
        ? (isFolder
              ? '$alerts ${AppTr.tr('تنبيه')}'
              : AppTr.tr('يوجد تنبيه'))
        : item.expiry.isNotEmpty
        ? '${AppTr.tr('ينتهي')} ${item.expiry}'
        : isFolder
        ? '$count ${AppTr.tr('عنصر')}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x140A5A50) : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _tapItem(item),
          // الضغطة المطوّلة للسحب والترتيب (وبلا سحب تفتح الخيارات).
          onLongPress: _selecting || _canReorder ? null : () => _itemMenu(item),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(
                color: selected ? _accent : AppTheme.hairline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: isImage &&
                            !_selecting &&
                            DocumentStore.existsSync(item.path)
                        ? Image.file(
                            File(DocumentStore.localPathFor(item.path)),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(icon, color: iconColor, size: 26),
                          )
                        : ColoredBox(
                            color: iconColor.withValues(alpha: 0.1),
                            child: Icon(icon, color: iconColor, size: 26),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fixed ? AppTr.tr(item.name) : item.name,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.title,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: alerts > 0
                                ? const Color(0xFFC4392E)
                                : AppTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!_selecting && !fixed)
                  IconButton(
                    tooltip: AppTr.tr('خيارات'),
                    onPressed: () => _itemMenu(item),
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppTheme.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadViewMode();
    _loadOrder();
  }

  // ===== الترتيب اليدوي: ضغطة مطوّلة ثم سحب العنصر إلى مكانه =====

  /// ترتيب كل مكان (الجذر أو مجلد) — معرّفات العناصر بالترتيب.
  Map<String, List<String>> _order = {};
  static const _orderKey = 'general_docs_order_v1';

  /// مسافة السحب: ضغطة مطوّلة بلا سحب تفتح خيارات العنصر كما كانت.
  double _dragDistance = 0;

  bool get _canReorder =>
      !_selecting && !(_searching && _searchCtrl.text.trim().isNotEmpty);

  Future<void> _loadOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_orderKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final order = <String, List<String>>{
        for (final e in decoded.entries)
          if (e.value is List)
            '${e.key}': [for (final id in e.value as List) '$id'],
      };
      if (mounted) setState(() => _order = order);
    } catch (_) {}
  }

  Future<void> _saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_orderKey, jsonEncode(_order));
    } catch (_) {}
  }

  /// يضع العنصر المسحوب مكان العنصر الذي أُفلت عليه.
  Future<void> _moveTo(String dragId, String targetId) async {
    final ids = [
      for (final item in _children)
        if (!_isFixed(item)) item.id,
    ];
    final from = ids.indexOf(dragId);
    if (from < 0) return;
    ids.removeAt(from);
    final to = targetId == GeneralDocsStore.notesFolderId
        ? 0
        : ids.indexOf(targetId);
    if (to < 0) {
      ids.add(dragId);
    } else {
      // للأمام: بعد الهدف؛ للخلف: قبله — فيأخذ مكانه.
      ids.insert(from <= to ? to + 1 : to, dragId);
    }
    setState(() => _order[widget.parentId ?? ''] = ids);
    await _saveOrder();
  }

  /// غلاف السحب والإفلات لعنصر واحد (مستطيل أو مربع).
  Widget _reorderable(GeneralDocItem item, Widget child) {
    if (!_canReorder) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != item.id,
          onAcceptWithDetails: (details) => _moveTo(details.data, item.id),
          builder: (context, candidate, _) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: candidate.isNotEmpty
                  ? Border.all(color: _accent, width: 2)
                  : null,
            ),
            child: child,
          ),
        );
        // مجلد «ملاحظات» ثابت أولًا: لا يُسحب، ويُفلت عليه للأول.
        if (_isFixed(item)) return target;
        return LongPressDraggable<String>(
          data: item.id,
          onDragStarted: () => _dragDistance = 0,
          onDragUpdate: (details) => _dragDistance += details.delta.distance,
          onDraggableCanceled: (_, __) {
            if (_dragDistance < 12) _itemMenu(item);
          },
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
              child: Opacity(opacity: 0.85, child: child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: child),
          child: target,
        );
      },
    );
  }

  Future<void> _load() async {
    final items = await GeneralDocsStore.loadAll();
    if (!mounted) return;
    setState(() {
      _all = items;
      _loading = false;
    });
  }

  List<GeneralDocItem> get _children {
    final list = _all
        .where((item) => item.parentId == widget.parentId)
        .toList();
    // مجلد «ملاحظات» أولًا، ثم المجلدات، ثم الأحدث.
    list.sort((a, b) {
      if (_isFixed(a) != _isFixed(b)) return _isFixed(a) ? -1 : 1;
      final folderA = a.type == GeneralDocItem.folder ? 0 : 1;
      final folderB = b.type == GeneralDocItem.folder ? 0 : 1;
      if (folderA != folderB) return folderA.compareTo(folderB);
      return b.createdAt.compareTo(a.createdAt);
    });
    // ترتيب يدوي محفوظ لهذا المكان: الجديد أولًا ثم المرتّب بالسحب.
    final order = _order[widget.parentId ?? ''];
    if (order == null || order.isEmpty) return list;
    final rest = [
      for (final item in list)
        if (!_isFixed(item)) item,
    ];
    return [
      for (final item in list)
        if (_isFixed(item)) item,
      for (final item in rest)
        if (!order.contains(item.id)) item,
      for (final id in order)
        for (final item in rest)
          if (item.id == id) item,
    ];
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<String?> _askName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textDirection: AppTr.uiDir,
            decoration: InputDecoration(hintText: AppTr.tr('الاسم')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 600), controller.dispose);
    return name;
  }

  static const _reminderChoices = <String, int>{
    'بلا تذكير': -1,
    'في يوم الانتهاء': 0,
    'قبل يوم': 1,
    'قبل أسبوع': 7,
    'قبل شهر': 30,
    'مخصص': -2,
  };

  /// الاسم، ثم تاريخ الانتهاء، والتذكير في الأسفل (اختياري).
  /// الأسماء الموجودة في هذا المكان (للتنبيه على الاسم المتكرر).
  Set<String> _takenNames({String? exceptId}) =>
      _namesIn(widget.parentId, exceptId: exceptId);

  /// الأسماء الموجودة داخل مجلد [parentId] (null = «عام»).
  Set<String> _namesIn(String? parentId, {String? exceptId}) => {
    for (final item in _all)
      if (item.parentId == parentId && item.id != exceptId)
        item.name.trim().toLowerCase(),
  };

  /// اسم غير مكرر في المكان: الاسم، ثم «الاسم (2)»…
  String _uniqueName(String name, Set<String> taken) {
    var candidate = name;
    var n = 2;
    while (taken.contains(candidate.trim().toLowerCase())) {
      candidate = '$name ($n)';
      n++;
    }
    return candidate;
  }

  /// مسار المجلد للعرض: «عام › مجلد › مجلد».
  String _pathOf(String? folderId) {
    final names = <String>[];
    var current = folderId;
    var guard = 0;
    while (current != null && guard++ < 50) {
      final match = _all.where((item) => item.id == current);
      if (match.isEmpty) break;
      names.insert(0, AppTr.tr(match.first.name));
      current = match.first.parentId;
    }
    return [AppTr.tr('عام'), ...names].join(' › ');
  }

  /// اختيار مجلد الوجهة للنقل أو النسخ. يُعيد (id) أو null عند الإلغاء.
  Future<({String? id})?> _pickFolder(String title, Set<String> exclude) {
    final folders =
        _all
            .where(
              (item) =>
                  item.type == GeneralDocItem.folder &&
                  !exclude.contains(item.id),
            )
            .toList()
          ..sort((a, b) => _pathOf(a.id).compareTo(_pathOf(b.id)));
    return showModalBottomSheet<({String? id})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home_work_outlined, color: _accent),
                  title: const Text('عام'),
                  onTap: () => Navigator.pop(sheetContext, (id: null)),
                ),
                for (final folder in folders)
                  ListTile(
                    leading: Icon(
                      _isFixed(folder)
                          ? Icons.folder_special_rounded
                          : Icons.folder_rounded,
                      color: _isFixed(folder)
                          ? const Color(0xFFE0B400)
                          : const Color(0xFFCE8422),
                    ),
                    title: Text(_pathOf(folder.id)),
                    onTap: () =>
                        Navigator.pop(sheetContext, (id: folder.id)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// نقل عناصر إلى مجلد آخر (الاسم المكرر يُرقَّم تلقائيًا).
  Future<void> _moveItems(List<GeneralDocItem> items) async {
    final movable = items.where((item) => !_isFixed(item)).toList();
    if (movable.isEmpty) return;
    final exclude = <String>{};
    for (final item in movable) {
      if (item.type == GeneralDocItem.folder) {
        exclude.addAll(_descendantsOf(item.id));
      }
    }
    final target = await _pickFolder(AppTr.tr('نقل إلى'), exclude);
    if (target == null || !mounted) return;
    final ids = {for (final item in movable) item.id};
    final taken = {
      for (final item in _all)
        if (item.parentId == target.id && !ids.contains(item.id))
          item.name.trim().toLowerCase(),
    };
    final renamed = <String, String>{};
    for (final item in movable) {
      final name = _uniqueName(item.name, taken);
      taken.add(name.trim().toLowerCase());
      renamed[item.id] = name;
    }
    final all = await GeneralDocsStore.loadAll();
    await GeneralDocsStore.saveAll([
      for (final entry in all)
        ids.contains(entry.id)
            ? entry.movedTo(target.id, name: renamed[entry.id])
            : entry,
    ]);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    await _load();
    _toast('${AppTr.tr('تم النقل إلى')} «${_pathOf(target.id)}»');
  }

  /// نسخ عناصر (والمجلد بكل ما بداخله) إلى مجلد — الملفات تُنسخ فعليًا.
  Future<void> _copyItems(List<GeneralDocItem> items) async {
    final copyable = items.where((item) => !_isFixed(item)).toList();
    if (copyable.isEmpty) return;
    final exclude = <String>{};
    for (final item in copyable) {
      if (item.type == GeneralDocItem.folder) {
        exclude.addAll(_descendantsOf(item.id));
      }
    }
    final target = await _pickFolder(AppTr.tr('نسخ إلى'), exclude);
    if (target == null || !mounted) return;
    final all = await GeneralDocsStore.loadAll();
    final snapshot = List<GeneralDocItem>.of(all);
    final copies = <GeneralDocItem>[];
    var seq = DateTime.now().microsecondsSinceEpoch;
    final now = DateTime.now().toIso8601String();
    Future<void> copyTree(
      GeneralDocItem source,
      String? parent,
      String name,
    ) async {
      var path = source.path;
      if (path.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        path =
            await DocumentStore.copyIntoApp(
              path,
              DocumentStore.fileName(
                path,
              ).replaceFirst(RegExp(r'^\d+_'), ''),
            ) ??
            '';
      }
      final copy = GeneralDocItem(
        id: '${seq++}',
        type: source.type,
        name: name,
        path: path,
        parentId: parent,
        createdAt: now,
        expiry: source.expiry,
        remindDays: source.remindDays,
        data: source.data,
      );
      copies.add(copy);
      for (final child in snapshot.where((e) => e.parentId == source.id)) {
        await copyTree(child, copy.id, child.name);
      }
    }

    final taken = {
      for (final item in _all)
        if (item.parentId == target.id) item.name.trim().toLowerCase(),
    };
    for (final item in copyable) {
      final base = taken.contains(item.name.trim().toLowerCase())
          ? '${item.name} (${AppTr.tr('نسخة')})'
          : item.name;
      final name = _uniqueName(base, taken);
      taken.add(name.trim().toLowerCase());
      await copyTree(item, target.id, name);
    }
    await GeneralDocsStore.saveAll([...all, ...copies]);
    for (final copy in copies) {
      if (copy.expiry.isNotEmpty) await _syncReminder(copy);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    await _load();
    _toast('${AppTr.tr('تم النسخ إلى')} «${_pathOf(target.id)}»');
  }

  Future<({String name, String expiry, int remindDays, String path})?>
  _askDetails(
    String title,
    String initial, {
    bool withExpiry = true,
    bool pickFile = false,
  }) async {
    final nameCtrl = TextEditingController(text: initial);
    final daysCtrl = TextEditingController();
    final taken = _takenNames();
    DateTime? expiry;
    var reminder = 'بلا تذكير';
    var filePath = '';
    String? nameError;
    final result = await showModalBottomSheet<
      ({String name, String expiry, int remindDays, String path})
    >(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppTheme.page,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.rCard),
            ),
          ),
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheet) {
              InputDecoration deco(String label, IconData icon) =>
                  InputDecoration(
                    isDense: true,
                    labelText: AppTr.tr(label),
                    prefixIcon: Icon(icon, size: 19),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                  );
              return Directionality(
                textDirection: AppTr.uiDir,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.title,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: AppTr.tr('إغلاق'),
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textDirection: AppTr.uiDir,
                        onChanged: (_) {
                          if (nameError != null) {
                            setSheet(() => nameError = null);
                          }
                        },
                        decoration: deco(
                          'الاسم',
                          Icons.title_rounded,
                        ).copyWith(errorText: nameError),
                      ),
                      // الملف: صفحة الاسم والتذكير أولًا، ثم إرفاق الملف هنا.
                      if (pickFile) ...[
                        const SizedBox(height: 10),
                        AppRemovableAttachment(
                          attached: filePath.isNotEmpty,
                          onRemove: () => setSheet(() => filePath = ''),
                          child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await DocumentStore.pickAndStore(context: context);
                            if (picked == null) return;
                            setSheet(() {
                              filePath = picked;
                              if (nameCtrl.text.trim().isEmpty) {
                                nameCtrl.text = _baseName(picked);
                              }
                            });
                          },
                          icon: Icon(
                            filePath.isEmpty
                                ? Icons.attach_file_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            filePath.isEmpty
                                ? 'إرفاق الملف'
                                : DocumentStore.shortName(filePath, max: 24),
                            maxLines: 3,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                        ),
                      ],
                      if (withExpiry) ...[
                      const SizedBox(height: 10),
                      // تاريخ الانتهاء والتذكير جنب بعض.
                      Row(
                        children: [
                      Expanded(
                        child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: sheetContext,
                            initialDate: expiry ?? now,
                            firstDate: DateTime(now.year - 10),
                            lastDate: DateTime(now.year + 40),
                            helpText: AppTr.tr('تاريخ الانتهاء'),
                          );
                          if (picked != null) setSheet(() => expiry = picked);
                        },
                        icon: const Icon(Icons.event_busy_outlined, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            expiry == null
                                ? 'تاريخ الانتهاء'
                                : _formatDate(expiry!),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _accent,
                          minimumSize: const Size.fromHeight(50),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      ),
                      // بعد الاختيار: × يمسح تاريخ الانتهاء.
                      if (expiry != null)
                        IconButton(
                          tooltip: AppTr.tr('مسح التاريخ'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setSheet(() => expiry = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: reminder,
                          isExpanded: true,
                          decoration: deco(
                            'التذكير',
                            Icons.notifications_active_outlined,
                          ),
                          items: [
                            for (final label in _reminderChoices.keys)
                              DropdownMenuItem(
                                value: label,
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                  label,
                                  maxLines: 1,
                                )),
                              ),
                          ],
                          onChanged: (value) =>
                              setSheet(() => reminder = value ?? 'بلا تذكير'),
                        ),
                      ),
                        ],
                      ),
                      if (reminder == 'مخصص') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: daysCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: AppTr.uiDir,
                          decoration: deco(
                            'عدد الأيام قبل الانتهاء',
                            Icons.timelapse_rounded,
                          ),
                        ),
                      ],
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          final typed = nameCtrl.text.trim().isEmpty
                              ? initial.trim()
                              : nameCtrl.text.trim();
                          // لا يتكرر الاسم في المكان نفسه.
                          if (taken.contains(typed.toLowerCase())) {
                            setSheet(
                              () => nameError =
                                  'الاسم موجود في هذا المكان — اختر اسمًا آخر',
                            );
                            return;
                          }
                          if (pickFile && filePath.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('أرفق الملف أولًا'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          var days = _reminderChoices[reminder] ?? -1;
                          if (days == -2) {
                            days = int.tryParse(daysCtrl.text.trim()) ?? -1;
                          }
                          if (days >= 0 && expiry == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('اختر تاريخ الانتهاء للتذكير'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(sheetContext, (
                            name: typed,
                            expiry: expiry == null ? '' : _formatDate(expiry!),
                            remindDays: days,
                            path: filePath,
                          ));
                        },
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: const Text(
                          'حفظ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    Future.delayed(const Duration(milliseconds: 600), () {
      nameCtrl.dispose();
      daysCtrl.dispose();
    });
    return result;
  }

  Future<void> _addItem(
    String type,
    String path,
    String suggestedName, {
    bool pickFile = false,
  }) async {
    final isFolder = type == GeneralDocItem.folder;
    final details = await _askDetails(
      isFolder ? 'مجلد جديد' : (pickFile ? 'ملف جديد' : 'اسم الملف'),
      suggestedName,
      // المجلد بلا تذكير: داخله ملفات وصور لكلٍّ تذكيره.
      withExpiry: !isFolder,
      pickFile: pickFile,
    );
    if (details == null || !mounted) return;
    if (pickFile) path = details.path;
    var name = details.name;
    if (name.isEmpty) {
      // اسم افتراضي غير مكرر: مجلد جديد، مجلد جديد 2…
      final base = isFolder || suggestedName.isEmpty
          ? AppTr.tr(isFolder ? 'مجلد جديد' : 'ملف جديد')
          : suggestedName;
      final taken = _takenNames();
      name = base;
      var n = 2;
      while (taken.contains(name.toLowerCase())) {
        name = '$base $n';
        n++;
      }
    }
    final now = DateTime.now();
    final item = GeneralDocItem(
      id: now.microsecondsSinceEpoch.toString(),
      type: type,
      name: name,
      path: path,
      parentId: widget.parentId,
      createdAt: now.toIso8601String(),
      expiry: details.expiry,
      remindDays: details.remindDays,
    );
    final all = await GeneralDocsStore.loadAll()
      ..add(item);
    await GeneralDocsStore.saveAll(all);
    await _syncReminder(item);
    await _load();
  }

  /// تذكير الانتهاء (أو موعد الملاحظة) في التنبيهات.
  Future<void> _syncReminder(GeneralDocItem item) async {
    final date = AppRemindersStore.parseDisplayDate(item.expiry);
    if (date == null || item.remindDays < 0) {
      await AppRemindersStore.remove('general_doc_${item.id}');
      return;
    }
    await AppRemindersStore.upsert(
      AppReminder(
        id: 'general_doc_${item.id}',
        title: item.type == GeneralDocItem.note
            ? '${AppTr.tr('ملاحظة')}: ${item.name}'
            : '${AppTr.tr('انتهاء')} «${item.name}»',
        module: 'المستندات',
        expiryDate: date,
        remindBeforeDays: item.remindDays,
      ),
    );
  }

  /// ملاحظة جديدة أو تعديل ملاحظة.
  Future<void> _editNote([
    GeneralDocItem? existing,
    bool asFile = false,
  ]) async {
    final isFile = existing == null
        ? asFile
        : existing.type == GeneralDocItem.doc;
    Map<String, dynamic> data = const {};
    if (existing != null && existing.data.isNotEmpty) {
      try {
        final decoded = jsonDecode(existing.data);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final result = await Navigator.of(context).push<NoteEditorResult>(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          asFile: isFile,
          title: existing?.name ?? '',
          data: data,
          expiry: existing?.expiry ?? '',
          remindDays: existing?.remindDays ?? -1,
          // الملاحظة الجديدة تُحفظ في مجلد «ملاحظات».
          takenNames: existing == null
              ? _namesIn(
                  isFile ? widget.parentId : GeneralDocsStore.notesFolderId,
                )
              : _namesIn(existing.parentId, exceptId: existing.id),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final all = await GeneralDocsStore.loadAll();
    late GeneralDocItem saved;
    if (existing == null) {
      final now = DateTime.now();
      saved = GeneralDocItem(
        id: now.microsecondsSinceEpoch.toString(),
        type: isFile ? GeneralDocItem.doc : GeneralDocItem.note,
        name: result.title,
        parentId: isFile ? widget.parentId : GeneralDocsStore.notesFolderId,
        createdAt: now.toIso8601String(),
        expiry: result.expiry,
        remindDays: result.remindDays,
        data: jsonEncode(result.data),
      );
      all.add(saved);
    } else {
      saved = existing.copyWith(
        name: result.title,
        expiry: result.expiry,
        remindDays: result.remindDays,
        data: jsonEncode(result.data),
      );
      for (var i = 0; i < all.length; i++) {
        if (all[i].id == existing.id) all[i] = saved;
      }
    }
    await GeneralDocsStore.saveAll(all);
    await _syncReminder(saved);
    await _load();
    if (existing == null && !isFile && mounted) {
      _toast(AppTr.tr('تم حفظ الملاحظة في مجلد «ملاحظات»'));
    }
  }

  /// توقيع أو ختم صورة/ملف PDF: تُحفظ نسخة موقّعة بجانب الأصل.
  Future<void> _signItem(GeneralDocItem item) async {
    final stored = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SignDocumentScreen(path: item.path)),
    );
    if (stored == null || !mounted) return;
    final isPdf = stored.toLowerCase().endsWith('.pdf');
    final now = DateTime.now();
    var name = '${item.name} (${AppTr.tr('موقّع')})';
    final taken = _takenNames();
    var n = 2;
    while (taken.contains(name.toLowerCase())) {
      name = '${item.name} (${AppTr.tr('موقّع')} $n)';
      n++;
    }
    final all = await GeneralDocsStore.loadAll()
      ..add(
        GeneralDocItem(
          id: now.microsecondsSinceEpoch.toString(),
          type: isPdf ? GeneralDocItem.file : GeneralDocItem.image,
          name: name,
          path: stored,
          parentId: widget.parentId,
          createdAt: now.toIso8601String(),
        ),
      );
    await GeneralDocsStore.saveAll(all);
    await _load();
    if (mounted) _toast('${AppTr.tr('حُفظت نسخة موقّعة')}: $name');
  }

  String _baseName(String path) {
    final name = DocumentStore.fileName(path);
    final dot = name.lastIndexOf('.');
    // الاسم المحفوظ يبدأ بختم زمني «123_الاسم» — يُعرض بلا الختم.
    final clean = name.replaceFirst(RegExp(r'^\d+_'), '');
    final cleanDot = clean.lastIndexOf('.');
    if (cleanDot > 0) return clean.substring(0, cleanDot);
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 88,
      );
      if (picked == null) return;
      final stored = await DocumentStore.copyIntoApp(picked.path, picked.name);
      if (stored == null) {
        _toast('تعذّر حفظ الصورة');
        return;
      }
      await _addItem(
        GeneralDocItem.image,
        stored,
        source == ImageSource.camera ? 'صورة' : _baseName(stored),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('تعذّر فتح الصور على هذا الجهاز');
    }
  }

  /// زر +: مجلد، ملف، استيراد من الصور، التقاط صورة.
  Future<void> _openAddMenu() async {
    if (!await FundlyAuth.requireLogin(context)) return;
    if (!mounted) return;
    // داخل مجلد «ملاحظات»: + يفتح صفحة الملاحظة مباشرة بلا خيارات.
    if (widget.parentId == GeneralDocsStore.notesFolderId) {
      await _editNote();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إضافة',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final (value, label, icon) in const [
                      ('folder', 'مجلد', Icons.create_new_folder_rounded),
                      ('file', 'ملف', Icons.upload_file_rounded),
                      ('note', 'ملاحظة', Icons.sticky_note_2_outlined),
                      ('gallery', 'استيراد من الصور', Icons.photo_library_rounded),
                      ('camera', 'التقاط صورة', Icons.photo_camera_rounded),
                    ])
                      InkWell(
                        onTap: () => Navigator.pop(sheetContext, value),
                        borderRadius: BorderRadius.circular(AppTheme.rInner),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              AppTheme.rInner,
                            ),
                            border: Border.all(color: AppTheme.hairline),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, color: _accent, size: 24),
                              const SizedBox(height: 5),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.title,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'folder':
        await _addItem(GeneralDocItem.folder, '', 'مجلد جديد');
      case 'file':
        // صفحة كتابة مثل الملاحظة؛ عند ✓ الاسم وتاريخ التذكير والتذكير.
        await _editNote(null, true);
      case 'note':
        await _editNote();
      case 'gallery':
        await _pickImage(ImageSource.gallery);
      case 'camera':
        await _pickImage(ImageSource.camera);
    }
  }

  Future<void> _open(GeneralDocItem item) async {
    if (item.type == GeneralDocItem.note || item.type == GeneralDocItem.doc) {
      await _editNote(item);
      return;
    }
    if (item.type == GeneralDocItem.folder) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _GeneralFolderScreen(folder: item)),
      );
      await _load();
      return;
    }
    // الصورة تُعرض داخل التطبيق وتحتها: توقيع / ختم / شعار.
    if (DocumentPreviewScreen.isImage(item.path)) {
      final choice = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              DocumentPreviewScreen(path: item.path, title: item.name),
        ),
      );
      if (!mounted) return;
      if (choice == 'sign') {
        await _signItem(item);
        return;
      }
      if (choice != 'external') return;
    } else if (SignDocumentScreen.supports(item.path)) {
      // ملف PDF: فتحه أو توقيعه/ختمه.
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('فتح الملف'),
                  onTap: () => Navigator.pop(sheetContext, 'open'),
                ),
                ListTile(
                  leading: const Icon(Icons.draw_outlined),
                  title: const Text('توقيع / ختم / شعار'),
                  onTap: () => Navigator.pop(sheetContext, 'sign'),
                ),
              ],
            ),
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'sign') {
        await _signItem(item);
        return;
      }
    }
    final error = await DocumentStore.open(item.path);
    if (error != null && mounted) _toast(error);
  }

  /// كل ما داخل المجلد (وما داخل مجلداته) لحذفه معه.
  Set<String> _descendantsOf(String id) {
    final out = <String>{id};
    var added = true;
    while (added) {
      added = false;
      for (final item in _all) {
        if (item.parentId != null &&
            out.contains(item.parentId) &&
            out.add(item.id)) {
          added = true;
        }
      }
    }
    return out;
  }

  Future<void> _itemMenu(GeneralDocItem item) async {
    if (_isFixed(item)) {
      _toast(AppTr.tr('مجلد «ملاحظات» ثابت — لا يُحذف ولا يُنقل'));
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('إعادة تسمية'),
                onTap: () => Navigator.pop(sheetContext, 'rename'),
              ),
              if (item.type != GeneralDocItem.folder &&
                  item.type != GeneralDocItem.note &&
                  SignDocumentScreen.supports(item.path))
                ListTile(
                  leading: const Icon(Icons.draw_outlined),
                  title: const Text('توقيع / ختم / شعار'),
                  onTap: () => Navigator.pop(sheetContext, 'sign'),
                ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('نقل إلى مجلد'),
                onTap: () => Navigator.pop(sheetContext, 'move'),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('نسخ إلى مجلد'),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.danger,
                ),
                title: const Text(
                  'حذف',
                  style: TextStyle(color: AppTheme.danger),
                ),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'sign') {
      await _signItem(item);
      return;
    }
    if (action == 'move') {
      await _moveItems([item]);
      return;
    }
    if (action == 'copy') {
      await _copyItems([item]);
      return;
    }
    if (action == 'rename') {
      final name = await _askName('إعادة تسمية', item.name);
      if (name == null || name.isEmpty || !mounted) return;
      if (_takenNames(exceptId: item.id).contains(name.toLowerCase())) {
        _toast(AppTr.tr('الاسم موجود في هذا المكان — اختر اسمًا آخر'));
        return;
      }
      final all = await GeneralDocsStore.loadAll();
      await GeneralDocsStore.saveAll([
        for (final entry in all)
          entry.id == item.id ? entry.copyWith(name: name) : entry,
      ]);
      await _load();
      return;
    }
    final isFolder = item.type == GeneralDocItem.folder;
    final ok = await confirmAction(
      context,
      title: 'حذف',
      message: isFolder
          ? 'سيُحذف المجلد «${item.name}» وكل ما بداخله. هل تريد المتابعة؟'
          : 'سيُحذف «${item.name}». هل تريد المتابعة؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok) return;
    final removed = _descendantsOf(item.id);
    final all = await GeneralDocsStore.loadAll();
    for (final entry in all) {
      if (removed.contains(entry.id) && entry.path.isNotEmpty) {
        await DocumentStore.delete(entry.path);
      }
      if (removed.contains(entry.id)) {
        await AppRemindersStore.remove('general_doc_${entry.id}');
      }
    }
    await GeneralDocsStore.saveAll(
      all.where((entry) => !removed.contains(entry.id)).toList(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    // البحث يشمل كل «عام» بما داخل المجلدات.
    final children = _searching && query.isNotEmpty
        ? _all
              .where((item) => item.name.toLowerCase().contains(query))
              .toList()
        : _children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title ?? 'عام',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
            ),
            // مستطيلات تحت بعض أو مربعات جنب بعض.
            IconButton(
              tooltip: AppTr.tr(
                _listView ? 'عرض مربعات' : 'عرض مستطيلات',
              ),
              onPressed: _toggleViewMode,
              icon: Icon(
                _listView
                    ? Icons.grid_view_rounded
                    : Icons.view_agenda_outlined,
                color: _accent,
              ),
            ),
            // ⋮ بجانب العنوان: تحديد (نقل / نسخ) وبحث بالاسم.
            PopupMenuButton<String>(
              tooltip: AppTr.tr('خيارات'),
              icon: const Icon(Icons.more_vert_rounded, color: _accent),
              onSelected: (value) => setState(() {
                if (value == 'select') {
                  _selecting = true;
                  _selected.clear();
                  _searching = false;
                  _searchCtrl.clear();
                } else {
                  _searching = true;
                  _selecting = false;
                  _selected.clear();
                }
              }),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'select',
                  // مجلد فارغ: لا شيء يُحدَّد.
                  enabled: children.isNotEmpty,
                  child: const Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('تحديد للنقل أو النسخ'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 19),
                      SizedBox(width: 10),
                      Text('بحث بالاسم'),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.showAdd)
            Material(
              color: _accent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _openAddMenu,
                child: const SizedBox(
                  width: 42,
                  height: 38,
                  child: Icon(Icons.add_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        if (_searching) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            textDirection: AppTr.uiDir,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: AppTr.tr('ابحث بالاسم في كل المجلدات'),
              prefixIcon: const Icon(Icons.search_rounded, color: _accent),
              suffixIcon: IconButton(
                tooltip: AppTr.tr('إغلاق'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _searching = false;
                  _searchCtrl.clear();
                }),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                borderSide: const BorderSide(color: AppTheme.hairline),
              ),
            ),
          ),
        ],
        if (_selecting && children.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: const Color(0x120A5A50),
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selected.isEmpty
                        ? AppTr.tr('اختر العناصر بالضغط عليها')
                        : '${AppTr.tr('المحدد')}: ${_selected.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _moveItems(
                          _all
                              .where((item) => _selected.contains(item.id))
                              .toList(),
                        ),
                  icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                  label: const Text('نقل'),
                ),
                TextButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _copyItems(
                          _all
                              .where((item) => _selected.contains(item.id))
                              .toList(),
                        ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                ),
                IconButton(
                  tooltip: AppTr.tr('إلغاء'),
                  onPressed: () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (children.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: const Text(
              'اضغط + لإضافة مجلد أو ملف أو صورة — يظهر هنا مربعًا.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          )
        else if (_listView)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in children) _reorderable(item, _row(item)),
            ],
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final item in children) _reorderable(item, _square(item)),
            ],
          ),
      ],
    );
  }

  /// مربع واحد: مجلد أو ملف أو صورة (معاينة الصورة نفسها).
  Widget _square(GeneralDocItem item) {
    final isImage = item.type == GeneralDocItem.image;
    final isFolder = item.type == GeneralDocItem.folder;
    final isNote = item.type == GeneralDocItem.note;
    final count = isFolder
        ? _all.where((entry) => entry.parentId == item.id).length
        : 0;
    // التنبيهات: للعنصر نفسه، وللمجلد ما بداخله.
    final inside = isFolder ? _descendantsOf(item.id) : const <String>{};
    final alerts = isFolder
        ? _all
              .where(
                (entry) =>
                    entry.id != item.id &&
                    inside.contains(entry.id) &&
                    entry.hasAlert,
              )
              .length
        : (item.hasAlert ? 1 : 0);
    final fixed = _isFixed(item);
    final selected = _selected.contains(item.id);
    return Material(
      color: selected ? const Color(0x140A5A50) : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (!_selecting) {
            _open(item);
            return;
          }
          if (fixed) return;
          setState(() {
            if (!_selected.remove(item.id)) _selected.add(item.id);
          });
        },
        // الضغطة المطوّلة للسحب والترتيب (وبلا سحب تفتح الخيارات).
          onLongPress: _selecting || _canReorder ? null : () => _itemMenu(item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(
              color: selected ? _accent : AppTheme.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: isImage && DocumentStore.existsSync(item.path)
                    ? SizedBox.expand(
                        child: Image.file(
                          File(DocumentStore.localPathFor(item.path)),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_outlined,
                            color: _accent,
                            size: 30,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          fixed
                              ? Icons.folder_special_rounded
                              : _selecting && selected
                              ? Icons.check_circle_rounded
                              : isFolder
                              ? Icons.folder_rounded
                              : isNote
                              ? Icons.sticky_note_2_rounded
                              : item.type == GeneralDocItem.doc
                              ? Icons.description_rounded
                              : isImage
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_rounded,
                          color: fixed
                              ? const Color(0xFFE0B400)
                              : _selecting && selected
                              ? _accent
                              : isFolder
                              ? const Color(0xFFCE8422)
                              : isNote
                              ? const Color(0xFFE0B400)
                              : _accent,
                          size: 36,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Column(
                  children: [
                    Text(
                      isFolder && count > 0
                          ? '${fixed ? AppTr.tr(item.name) : item.name} ($count)'
                          : (fixed ? AppTr.tr(item.name) : item.name),
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.title,
                      ),
                    ),
                    if (alerts > 0)
                      Text(
                        isFolder
                            ? '$alerts ${AppTr.tr('تنبيه')}'
                            : AppTr.tr('يوجد تنبيه'),
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFC4392E),
                        ),
                      )
                    else if (item.expiry.isNotEmpty)
                      Text(
                        '${AppTr.tr('ينتهي')} ${item.expiry}',
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مجلد من «عام»: محتواه مربعات، وزر + يضيف داخله.
class _GeneralFolderScreen extends StatelessWidget {
  const _GeneralFolderScreen({required this.folder});

  final GeneralDocItem folder;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: Text(
            folder.name,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppTheme.title,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _GeneralDocsGrid(parentId: folder.id, title: folder.name),
          ],
        ),
      ),
    );
  }
}

/// مستندات قسم واحد: مجمّعة حسب النوع، كل مستند مربع. زر «إضافة مستند»
/// يختار عنصرًا من القسم (التزام، شخص، عقار...) ويضيف له مستندًا بتاريخ
/// انتهاء وملف — يُحفظ في مكان العنصر نفسه فيظهر هنا وهناك.
class ModuleDocumentsScreen extends StatefulWidget {
  const ModuleDocumentsScreen({
    super.key,
    required this.module,
    required this.documents,
    required this.onRefresh,
  });

  final String module;
  final List<AppDocument> documents;
  final Future<List<AppDocument>> Function() onRefresh;

  @override
  State<ModuleDocumentsScreen> createState() => _ModuleDocumentsScreenState();
}

/// عنصر يمكن إضافة مستند له.
class _DocTarget {
  const _DocTarget(
    this.label,
    this.subtitle,
    this.save, {
    this.id = '',
    this.section = '',
  });

  final String label;
  final String subtitle;

  /// معرّف العنصر — يطابق [AppDocument.ownerId].
  final String id;

  /// تقسيمه داخل القسم.
  final String section;

  /// يحفظ المستند في مكان العنصر: (الاسم، النوع، تاريخ الانتهاء، مسار الملف).
  final Future<void> Function(
    String name,
    String type,
    DateTime? expiry,
    String filePath,
  )
  save;
}

String _dmy(DateTime date) => '${date.day}/${date.month}/${date.year}';

class _ModuleDocumentsScreenState extends State<ModuleDocumentsScreen> {
  final TextEditingController _search = TextEditingController();
  late List<AppDocument> _docs = widget.documents;
  bool _busy = false;

  /// عناصر القسم (التزام، شخص، أصل) بتقسيماتها — للتصفح والإضافة.
  List<_DocTarget> _items = const [];
  late bool _itemsLoading = !_isPersonal;

  /// المستوى المفتوح: التقسيم، ثم العنصر داخله.
  String? _section;
  _DocTarget? _item;

  bool get _isPersonal => widget.module == 'الالتزامات الشخصية';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (_isPersonal) return;
    try {
      final items = await _targets();
      if (!mounted) return;
      setState(() {
        _items = items;
        _itemsLoading = false;
        final open = _item;
        if (open != null) {
          for (final item in items) {
            if (item.id == open.id) _item = item;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _itemsLoading = false);
    }
  }

  /// التقسيمات: الثابتة أولًا، ثم ما ظهر في العناصر والمستندات.
  List<String> _sections() {
    final out = <String>[...DocumentsHub.fixedSections(widget.module)];
    for (final section in [
      ..._items.map((item) => item.section),
      ..._docs.map((doc) => doc.section),
    ]) {
      if (section.isNotEmpty && !out.contains(section)) out.add(section);
    }
    return out;
  }

  List<_DocTarget> _itemsIn(String section) => _items
      .where((item) => item.section == section)
      .toList(growable: false);

  List<AppDocument> _docsInSection(String section) =>
      _docs.where((doc) => doc.section == section).toList(growable: false);

  List<AppDocument> _docsOf(_DocTarget item) => _docs
      .where((doc) => doc.ownerId.isNotEmpty && doc.ownerId == item.id)
      .toList(growable: false);

  static const _sectionIcons = <String, IconData>{
    'وثائق شخصية': Icons.badge_outlined,
    'الضمانات': Icons.verified_user_outlined,
    'الوثائق العامة': Icons.folder_open_rounded,
    'مشاركات مشتركة': Icons.diversity_3_rounded,
    'رحلة وسفر': Icons.flight_takeoff_rounded,
    'تحديد أدوار': Icons.assignment_ind_outlined,
    'الأفراد': Icons.person_rounded,
    'الجهات': Icons.apartment_rounded,
    'مركبات برية': Icons.directions_car_rounded,
    'مركبات بحرية': Icons.directions_boat_rounded,
  };

  IconData _sectionIcon(String section) =>
      _sectionIcons[section] ??
      _moduleIcons[widget.module] ??
      Icons.folder_outlined;

  /// الرجوع داخل الصفحة: من العنصر إلى التقسيم، ومن التقسيم إلى الأعلى.
  void _back() {
    setState(() {
      if (_item != null) {
        _item = null;
      } else {
        _section = null;
      }
      _search.clear();
    });
  }

  Color get _color =>
      _moduleColors[widget.module] ?? const Color(0xFF0A5A50);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final all = await widget.onRefresh();
    if (!mounted) return;
    setState(
      () => _docs = all
          .where((doc) => doc.module == widget.module)
          .toList(growable: false),
    );
    await _loadItems();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _open(AppDocument doc) async {
    final error = await DocumentsHub.open(doc);
    if (error == null || !mounted) return;
    _toast(error);
  }

  // ---------------- العناصر التي يُضاف لها مستند ----------------

  Future<List<_DocTarget>> _targets() async {
    switch (widget.module) {
      case 'الالتزامات الشخصية':
        {
          final repo = SupabasePersonalEntriesRepository();
          final rows = await repo.fetchAll();
          return [
            // مستند شخصي مستقل (هوية، جواز...) يُحفظ في الالتزامات الشخصية.
            _DocTarget(
              'مستند شخصي جديد',
              'يُحفظ في الالتزامات الشخصية ← مستند',
              (name, type, expiry, path) async {
                await repo.create(
                  PersonalEntryRecord(
                    category: 'document',
                    entryType: 'مستند',
                    title: name,
                    amount: 0,
                    dueDate: expiry == null ? '' : _dmy(expiry),
                    status: 'نشطة',
                    details: {
                      'اسم المستند': name,
                      if (type.isNotEmpty) 'نوع المستند': type,
                      if (expiry != null) 'تاريخ الانتهاء': _dmy(expiry),
                    },
                  ),
                  attachment: path.isEmpty ? null : XFile(path),
                );
              },
            ),
            for (final row in rows)
              if (row.status != 'محذوف')
                _DocTarget(
                  row.title,
                  row.entryType,
                  (name, type, expiry, path) async {
                    await repo.update(
                      row.copyWith(
                        details: {
                          ...row.details,
                          'نوع المرفق الإضافي': 'مستند',
                          'اسم المرفق الإضافي': name,
                          if (expiry != null)
                            'تاريخ انتهاء المرفق': _dmy(expiry),
                        },
                      ),
                      attachment: path.isEmpty ? null : XFile(path),
                    );
                  },
                ),
          ];
        }
      case 'الالتزامات المشتركة':
        {
          final repo = SupabaseSharedEntriesRepository();
          final rows = await repo.fetchAll();
          return [
            for (final row in rows)
              if (row.status != 'محذوف')
                _DocTarget(
                  row.title,
                  row.entryType,
                  id: row.id ?? '',
                  section: DocumentsHub.sharedSection(row.entryType),
                  (name, type, expiry, path) async {
                    await repo.update(
                      row.copyWith(
                        details: {
                          ...row.details,
                          'اسم المستند المرفق': name,
                          if (type.isNotEmpty) 'نوع المستند المرفق': type,
                          if (expiry != null)
                            'تاريخ انتهاء المستند': _dmy(expiry),
                        },
                      ),
                      attachment: path.isEmpty ? null : XFile(path),
                    );
                  },
                ),
          ];
        }
      case 'الأفراد والجهات':
        {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(DocumentsHub._peopleStorageKey);
          final decoded = raw == null || raw.trim().isEmpty
              ? const <dynamic>[]
              : jsonDecode(raw);
          final people = decoded is List
              ? decoded.whereType<Map>().toList()
              : const <Map>[];
          return [
            for (var i = 0; i < people.length; i++)
              _DocTarget(
                '${people[i]['fullName'] ?? ''}',
                '${people[i]['categoryName'] ?? ''}',
                id: 'person:$i',
                section: DocumentsHub.personSection(people[i]),
                (name, type, expiry, path) async {
                  // نفس مفاتيح شاشة الأفراد: «انتهاء الاسم» و«مرفق الاسم».
                  final fresh = await SharedPreferences.getInstance();
                  final current = jsonDecode(
                    fresh.getString(DocumentsHub._peopleStorageKey) ?? '[]',
                  );
                  if (current is! List || i >= current.length) return;
                  final person = Map<String, dynamic>.from(current[i] as Map);
                  final details = Map<String, dynamic>.from(
                    person['details'] is Map ? person['details'] as Map : {},
                  );
                  if (expiry != null) details['انتهاء $name'] = _dmy(expiry);
                  details['مرفق $name'] = path;
                  final documents = [
                    ...(person['documents'] is List
                        ? (person['documents'] as List).map((e) => '$e')
                        : const <String>[]),
                    if (expiry == null) name else '$name · ينتهي ${_dmy(expiry)}',
                  ];
                  person
                    ..['details'] = details
                    ..['documents'] = documents
                    ..['documentsCount'] = documents.length;
                  current[i] = person;
                  await fresh.setString(
                    DocumentsHub._peopleStorageKey,
                    jsonEncode(current),
                  );
                },
              ),
          ];
        }
      default:
        {
          final category = switch (widget.module) {
            'العقارات' => 'real_estate',
            'الأنشطة التجارية' => 'activity',
            _ => 'equipment',
          };
          final repo = SupabaseProjectAssetsRepository();
          final assets = await repo.fetchAssets();
          return [
            for (final asset in assets)
              if (asset.category == category &&
                  asset.status != 'محذوف' &&
                  asset.id != null)
                _DocTarget(
                  asset.title,
                  asset.subType,
                  id: asset.id!,
                  section: DocumentsHub.assetSection(asset),
                  (name, type, expiry, path) async {
                    await repo.upsertEntry(
                      ProjectAssetEntryRecord(
                        assetId: asset.id!,
                        kind: ProjectAssetEntryRecord.kindDocument,
                        data: {
                          'اسم المستند': name,
                          if (type.isNotEmpty) 'نوع المستند': type,
                          if (expiry != null) 'تاريخ الانتهاء': _dmy(expiry),
                          if (path.isNotEmpty) DocumentStore.kFileField: path,
                        },
                      ),
                    );
                  },
                ),
          ];
        }
    }
  }

  /// زر «إضافة مستند»: التقسيم ← العنصر ← بيانات المستند والملف ← حفظ.
  /// داخل تقسيم أو عنصر مفتوح تُختصر الخطوات المعروفة.
  Future<void> _addDocument() async {
    if (!await FundlyAuth.requireLogin(context)) return;
    if (!mounted) return;
    if (!PlanGate.canAdd(context, PlanModules.documents, _docs.length)) {
      return;
    }
    if (_isPersonal) {
      await _addPersonal();
      return;
    }
    if (_itemsLoading) {
      _toast('جارٍ تحميل العناصر…');
      return;
    }
    var item = _item;
    if (item == null) {
      final section = _section ?? await _pickSection();
      if (section == null || !mounted) return;
      final inSection = _itemsIn(section);
      if (inSection.isEmpty) {
        _toast('لا توجد عناصر في «$section» بعد');
        return;
      }
      item = await _pickTarget(inSection);
      if (item == null || !mounted) return;
    }
    final saved = await _documentForm(item);
    if (saved == true) await _reload();
  }

  /// مستند شخصي: يُختار التقسيم (إن لم يُحدَّد) ثم نوعه من أنواعه.
  Future<void> _addPersonal([String? section]) async {
    if (!PlanGate.canAdd(context, PlanModules.documents, _docs.length)) {
      return;
    }
    final chosen = section ?? await _pickSection();
    if (chosen == null || !mounted) return;
    final repo = SupabasePersonalEntriesRepository();
    final target = _DocTarget(
      chosen,
      '',
      section: chosen,
      (name, type, expiry, path) async {
        await repo.create(
          PersonalEntryRecord(
            category: 'document',
            entryType: 'مستند',
            title: name,
            amount: 0,
            dueDate: expiry == null ? '' : _dmy(expiry),
            status: 'نشطة',
            details: {
              'اسم المستند': name,
              if (type.isNotEmpty) 'نوع المستند': type,
              if (expiry != null) 'تاريخ الانتهاء': _dmy(expiry),
            },
          ),
          attachment: path.isEmpty ? null : XFile(path),
        );
      },
    );
    final saved = await _documentForm(
      target,
      typeOptions: DocumentsHub.personalTypes[chosen] ?? const <String>[],
    );
    if (saved == true) await _reload();
  }

  /// اختيار التقسيم عند الإضافة.
  Future<String?> _pickSection() {
    final sections = _sections();
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أين تضيف المستند؟',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 8),
                for (final section in sections)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_sectionIcon(section), color: _color),
                    title: Text(
                      section,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: _isPersonal
                        ? null
                        : Text(
                            '${_itemsIn(section).length} عنصر',
                            style: const TextStyle(fontSize: 11),
                          ),
                    trailing: const AppChevron(),
                    onTap: () => Navigator.pop(sheetContext, section),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<_DocTarget?> _pickTarget(List<_DocTarget> targets) {
    var query = '';
    return showModalBottomSheet<_DocTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final visible = targets
              .where(
                (t) =>
                    query.trim().isEmpty ||
                    t.label.contains(query.trim()) ||
                    t.subtitle.contains(query.trim()),
              )
              .toList(growable: false);
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'لمن المستند؟',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    textDirection: AppTr.uiDir,
                    onChanged: (value) => setSheet(() => query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppTr.tr('ابحث'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppTheme.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 340,
                    child: ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.line),
                      itemBuilder: (context, index) {
                        final target = visible[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _moduleIcons[widget.module] ??
                                Icons.description_outlined,
                            color: _color,
                          ),
                          title: Text(
                            target.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: target.subtitle.isEmpty
                              ? null
                              : Text(
                                  target.subtitle,
                                  style: const TextStyle(fontSize: 11),
                                ),
                          onTap: () => Navigator.pop(sheetContext, target),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool?> _documentForm(
    _DocTarget target, {
    List<String> typeOptions = const <String>[],
  }) async {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    DateTime? expiry;
    var path = '';
    var saving = false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          InputDecoration deco(String hint, IconData icon) => InputDecoration(
            isDense: true,
            hintText: AppTr.tr(hint),
            prefixIcon: Icon(icon, size: 19),
            filled: true,
            fillColor: AppTheme.field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rField),
              borderSide: BorderSide.none,
            ),
          );
          Future<void> save() async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اكتب اسم المستند')),
              );
              return;
            }
            if (typeOptions.isNotEmpty && typeCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اختر نوع المستند')),
              );
              return;
            }
            setSheet(() => saving = true);
            try {
              await target.save(name, typeCtrl.text.trim(), expiry, path);
              if (sheetContext.mounted) Navigator.pop(sheetContext, true);
            } catch (error) {
              setSheet(() => saving = false);
              if (!mounted) return;
              _toast('تعذّر حفظ المستند: $error');
            }
          }

          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مستند لـ «${target.label}»',
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textDirection: AppTr.uiDir,
                    decoration: deco('اسم المستند *', Icons.title_rounded),
                  ),
                  const SizedBox(height: 10),
                  if (typeOptions.isEmpty)
                    TextField(
                      controller: typeCtrl,
                      textDirection: AppTr.uiDir,
                      decoration: deco(
                        'نوع المستند (عقد، هوية، شهادة...)',
                        Icons.category_outlined,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final option in typeOptions)
                          ChoiceChip(
                            label: Text(
                              option,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: typeCtrl.text == option,
                            selectedColor: _color.withValues(alpha: 0.16),
                            onSelected: (_) => setSheet(() {
                              typeCtrl.text = option;
                              if (nameCtrl.text.trim().isEmpty) {
                                nameCtrl.text = option;
                              }
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: expiry ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 40),
                              helpText: AppTr.tr('تاريخ انتهاء المستند'),
                            );
                            if (picked != null) {
                              setSheet(() => expiry = picked);
                            }
                          },
                          icon: const Icon(Icons.event_busy_outlined, size: 18),
                          label: Text(
                            expiry == null
                                ? 'تاريخ الانتهاء'
                                : _formatDate(expiry!),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _color,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                      ),
                      // بعد الاختيار: × يمسح تاريخ الانتهاء.
                      if (expiry != null)
                        IconButton(
                          tooltip: AppTr.tr('مسح التاريخ'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setSheet(() => expiry = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppRemovableAttachment(
                          attached: path.isNotEmpty,
                          onRemove: () => setSheet(() => path = ''),
                          child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await DocumentStore.pickAndStore(context: context);
                            if (picked != null) setSheet(() => path = picked);
                          },
                          icon: Icon(
                            path.isEmpty
                                ? Icons.upload_file_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            path.isEmpty
                                ? 'رفع الملف'
                                : DocumentStore.shortName(path, max: 14),
                            maxLines: 3,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _color,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 19),
                    label: const Text(
                      'حفظ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      nameCtrl.dispose();
      typeCtrl.dispose();
    });
    if (result == true && mounted) _toast('حُفظ المستند');
    return result;
  }

  // ---------------- العرض ----------------

  /// حالة المستند: النص واللون.
  (String, Color) _status(AppDocument doc) {
    final days = doc.daysLeft;
    if (days == null) return ('بلا تاريخ', AppTheme.muted);
    if (days < 0) return ('منتهٍ', const Color(0xFFC4392E));
    if (days == 0) return ('ينتهي اليوم', const Color(0xFFA6691A));
    if (days <= 30) return ('بعد $days يوم', const Color(0xFFA6691A));
    return ('ساري', const Color(0xFF1C7A55));
  }

  Future<void> _showDetails(AppDocument doc) async {
    final (label, color) = _status(doc);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 10),
                for (final (key, value) in [
                  ('النوع', doc.group),
                  ('صاحب المستند', doc.owner),
                  ('الرقم', doc.number),
                  (
                    'تاريخ الانتهاء',
                    doc.expiry == null ? '' : _formatDate(doc.expiry!),
                  ),
                  ('الحالة', label),
                ])
                  if (value.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              key,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: key == 'الحالة' ? color : AppTheme.title,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: doc.hasFile
                      ? () {
                          Navigator.pop(sheetContext);
                          _open(doc);
                        }
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(doc.hasFile ? 'فتح الملف' : 'لا يوجد ملف مرفق'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// تسلسل العنوان: القسم › التقسيم › العنصر — كل جزء يرجع إليه.
  Widget _breadcrumb(Color color) {
    final parts = <(String, VoidCallback?)>[
      (
        widget.module,
        () => setState(() {
          _item = null;
          _section = null;
          _search.clear();
        }),
      ),
      if (_section != null)
        (
          _section!,
          _item == null
              ? null
              : () => setState(() {
                  _item = null;
                  _search.clear();
                }),
        ),
      if (_item != null) (_item!.label, null),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.rField),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Icon(Icons.folder_open_rounded, size: 16, color: color),
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Icon(
                AppTr.isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 16,
                color: AppTheme.muted,
              ),
            InkWell(
              onTap: parts[i].$2,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                child: Text(
                  parts[i].$1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == parts.length - 1
                        ? FontWeight.w900
                        : FontWeight.w700,
                    color: i == parts.length - 1 ? color : AppTheme.body,
                    decoration: parts[i].$2 == null
                        ? null
                        : TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _matches(AppDocument doc, String query) =>
      query.isEmpty ||
      matchesSearchQuery(
        query: query,
        fields: [doc.title, doc.group, doc.owner, doc.number],
      );

  List<AppDocument> _sorted(Iterable<AppDocument> docs) {
    final list = docs.toList()
      ..sort((a, b) {
        final da = a.expiry;
        final db = b.expiry;
        if (da == null && db == null) return a.title.compareTo(b.title);
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    return list;
  }

  Widget _grid(List<AppDocument> docs, Color color) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 0.9,
    children: [for (final doc in _sorted(docs)) _docSquare(doc, color)],
  );

  /// المستندات مجمّعة بنوعها (للبحث ولمستندات عنصر واحد).
  List<Widget> _byGroup(List<AppDocument> docs, Color color) {
    final groups = <String, List<AppDocument>>{};
    for (final doc in docs) {
      groups.putIfAbsent(doc.group, () => []).add(doc);
    }
    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return [
      for (final entry in ordered) ...[
        _groupHeader(
          entry.key,
          entry.value.length,
          color,
          alerts: _alertsIn(entry.value),
        ),
        _grid(entry.value, color),
        const SizedBox(height: 16),
      ],
    ];
  }

  /// المنتهي أو الذي ينتهي خلال 30 يومًا.
  static int _alertsIn(Iterable<AppDocument> docs) =>
      docs.where((doc) => doc.isExpired || doc.isExpiringSoon).length;

  /// «N تنبيه» بالأحمر: يدلّ على طريق المستند الذي يحتاج متابعة.
  Widget _alertPill(int alerts) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFC4392E).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppTheme.rPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFC4392E),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$alerts ${AppTr.tr('تنبيه')}',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFFC4392E),
          ),
        ),
      ],
    ),
  );

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int alerts = 0,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (alerts > 0) ...[
                _alertPill(alerts),
                const SizedBox(width: 4),
              ],
              const AppChevron(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _hint(String message) => Padding(
    padding: const EdgeInsets.only(bottom: 4, right: 12, left: 12),
    child: Text(
      message,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
    ),
  );

  /// الشخصية: التقسيمات الثلاثة ومستنداتها تحتها، ولكلٍّ «إضافة».
  List<Widget> _personalView(Color color) => [
    for (final section in _sections()) ...[
      _groupHeader(
        section,
        _docsInSection(section).length,
        color,
        onAdd: () => _addPersonal(section),
        alerts: _alertsIn(_docsInSection(section)),
      ),
      if (_docsInSection(section).isEmpty)
        _hint('لا توجد مستندات')
      else
        _grid(_docsInSection(section), color),
      const SizedBox(height: 16),
    ],
  ];

  /// التقسيمات: مربعات تفتح عناصرها.
  List<Widget> _sectionsView(Color color) {
    if (_itemsLoading) {
      return [
        Padding(
          padding: const EdgeInsets.all(30),
          child: Center(child: CircularProgressIndicator(color: color)),
        ),
      ];
    }
    return [
      for (final section in _sections())
        _navTile(
          icon: _sectionIcon(section),
          title: section,
          subtitle:
              '${_itemsIn(section).length} عنصر · '
              '${_docsInSection(section).length} مستند',
          color: color,
          alerts: _alertsIn(_docsInSection(section)),
          onTap: () => setState(() {
            _section = section;
            _search.clear();
          }),
        ),
    ];
  }

  /// عناصر التقسيم المفتوح، ثم مستنداته التي بلا عنصر معروف.
  List<Widget> _itemsView(String section, Color color) {
    final items = _itemsIn(section);
    final known = items.map((item) => item.id).toSet();
    final orphans = _docsInSection(section)
        .where((doc) => !known.contains(doc.ownerId))
        .toList(growable: false);
    return [
      if (items.isEmpty && orphans.isEmpty)
        _empty('لا توجد عناصر في هذا القسم بعد.'),
      for (final item in items)
        _navTile(
          icon: _sectionIcon(section),
          title: item.label,
          subtitle: [
            if (item.subtitle.trim().isNotEmpty &&
                item.subtitle.trim() != section &&
                DocumentsHub.sharedSection(item.subtitle) != section)
              item.subtitle.trim(),
            '${_docsOf(item).length} مستند',
          ].join(' · '),
          color: color,
          alerts: _alertsIn(_docsOf(item)),
          onTap: () => setState(() {
            _item = item;
            _search.clear();
          }),
        ),
      if (orphans.isNotEmpty) ...[
        const SizedBox(height: 6),
        _groupHeader(
          'مستندات أخرى',
          orphans.length,
          color,
          alerts: _alertsIn(orphans),
        ),
        _grid(orphans, color),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final query = _search.text.trim();
    final item = _item;
    final section = _section;
    final nested = item != null || section != null;

    // نطاق البحث: العنصر المفتوح، أو التقسيم، أو القسم كله.
    final scope = item != null
        ? _docsOf(item)
        : (section != null ? _docsInSection(section) : _docs);
    final found = scope
        .where((doc) => _matches(doc, query))
        .toList(growable: false);

    final List<Widget> content;
    if (query.isNotEmpty) {
      content = found.isEmpty
          ? [_empty('لا توجد مستندات تطابق البحث.')]
          : _byGroup(found, color);
    } else if (_isPersonal) {
      content = _personalView(color);
    } else if (item != null) {
      final docs = _docsOf(item);
      content = docs.isEmpty
          ? [_empty('لا توجد مستندات بعد — اضغط «إضافة مستند».')]
          : _byGroup(docs, color);
    } else if (section != null) {
      content = _itemsView(section, color);
    } else {
      content = _sectionsView(color);
    }

    return PopScope(
      canPop: !nested,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: Scaffold(
          backgroundColor: AppTheme.page,
          appBar: AppBar(
            title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
              item?.label ?? section ?? 'مستندات ${widget.module}',
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            )),
            centerTitle: true,
            backgroundColor: AppTheme.page,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppTheme.title,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _addDocument,
            backgroundColor: color,
            foregroundColor: Colors.white,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text(
              'إضافة مستند',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: RefreshIndicator(
            color: color,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (nested) ...[
                  _breadcrumb(color),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _search,
                  textDirection: AppTr.uiDir,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: AppTr.tr('ابحث بالاسم أو الرقم أو صاحب المستند'),
                    hintStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppTheme.muted,
                    ),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(String message) => Container(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rField),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.folder_off_outlined,
          size: 32,
          color: Color(0xFFD5DEDB),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
          ),
        ),
      ],
    ),
  );

  Widget _groupHeader(
    String group,
    int count,
    Color color, {
    VoidCallback? onAdd,
    int alerts = 0,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 17,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            group,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF022E2A),
            ),
          ),
        ),
        if (alerts > 0) ...[
          _alertPill(alerts),
          const SizedBox(width: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.rPill),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    'إضافة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  /// مستند واحد مربعًا: الأيقونة، الاسم، صاحبه، وحالة الانتهاء.
  Widget _docSquare(AppDocument doc, Color color) {
    final (label, statusColor) = _status(doc);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(doc),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.description_rounded, color: color, size: 32),
                  if (doc.hasFile)
                    const Positioned(
                      bottom: -2,
                      left: -4,
                      child: Icon(
                        Icons.attach_file_rounded,
                        size: 14,
                        color: AppTheme.muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                doc.title,
                maxLines: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              if (doc.owner.isNotEmpty && doc.owner != doc.title)
                Text(
                  doc.owner,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
