import 'dart:convert';

import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/entry_status.dart';
import '../data/app_settings.dart';
import '../widgets/shared/clear_date_suffix.dart';
import '../widgets/shared/fnd_lookup.dart';
import 'salary_receipts_screen.dart';
import '../data/salary_receipts.dart';
import '../widgets/shared/follow_filters.dart';
import '../data/fundly_account.dart';
import '../data/fundly_auth.dart';
import '../data/app_reminders_store.dart';
import '../data/page_customization_store.dart';
import '../data/delegations_repository.dart';
import '../data/document_store.dart';
import '../data/personal_entries_repository.dart';
import '../data/custody_sharing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:url_launcher/url_launcher.dart';
import 'personal_commitments_screen.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/followup_center_card.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/archive_sheet.dart';
import '../widgets/shared/app_filter_sheet.dart';
import 'global_summary_screen.dart';
import '../widgets/shared/followup_center_sheet.dart';
import 'smart_calendar_screen.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/plan_gate.dart';

/// تاريخ اليوم بصيغة d/M/yyyy — تُخزَّن التواريخ كنص بهذه الصيغة في سجلات
/// الأشخاص. كانت تُكتب سابقًا بالكلمة الثابتة 'اليوم'، فيظل سجل أُنشئ قبل
/// أشهر يعرض "اليوم"، والأسوأ أن الترتيب كان يقارن هذه النصوص حرفيًا.
/// خيارات التذكير — بنفس مسمّيات AppRemindersStore حتى تُقرأ مباشرة،
/// ومشتركة بين نموذج الإنشاء ونوافذ الإضافة داخل السجل.
/// الأنواع التي يُسأل فيها «مستحق له أم عليه» — وهي وحدها ما يُنشئ دَينًا.
/// الراتب والمصروف لا معنى لسؤالهم «له أم عليه».
const List<String> _directionKinds = [
  'المصروفات الشخصية',
  'إيراد',
  'دين / قرض / سلفة',
  'قسط',
  'غرامة',
];

/// نوع العهدة وحالاتها — منقولتان حرفيًا من نموذج «عهدة مالية» في
/// الالتزامات الشخصية، فلا يختلف النموذجان في الشاشتين. كانت القائمة هنا
/// «فئة العهدة» بقيم لا وجود لها هناك.
const List<String> _custodyTypes = ['مؤقتة', 'مستديمة'];

const List<String> _custodyStates = [
  'مستلمة',
  'قيد الاستخدام',
  'تمت التسوية',
  'معادة',
  'متأخرة',
];

const String _kReminderNone = 'بلا تذكير';
const String _kReminderCustom = 'مخصص';
const List<String> _kReminderOptions = [
  _kReminderNone,
  'قبل يوم',
  'قبل 3 أيام',
  'قبل أسبوع',
  'قبل أسبوعين',
  'قبل شهر',
  _kReminderCustom,
];

/// الوثائق الرسمية التي يُسأل عنها عند إنشاء الفرد: لكل واحدة رقم وتاريخ
/// انتهاء وتذكير ومرفق، بمفاتيح ثابتة داخل خانة التفاصيل.
class _IdentityDoc {
  const _IdentityDoc(this.title, this.icon);
  final String title;
  final IconData icon;

  String get numberKey => 'رقم $title';
  String get expiryKey => 'انتهاء $title';
  String get reminderKey => 'تذكير $title';
  String get fileKey => 'مرفق $title';

  static const List<_IdentityDoc> all = [
    _IdentityDoc('الهوية', Icons.badge_outlined),
    _IdentityDoc('جواز السفر', Icons.travel_explore_outlined),
    _IdentityDoc('الضمان الصحي', Icons.health_and_safety_outlined),
  ];
}

/// وثيقة جهة: اسم حر وتاريخ انتهاء وتذكير ومرفق. الجهة لا هوية لها ولا
/// جواز، فقوائم الأفراد الثابتة لا تناسبها.
class _EntityDoc {
  final TextEditingController name = TextEditingController();
  final TextEditingController expiry = TextEditingController();
  String reminder = _kReminderNone;
  String file = '';

  void dispose() {
    name.dispose();
    expiry.dispose();
  }
}

/// الجهة (شركة/مؤسسة) تبدأ مفاتيحها بـ entity_، وما عداها فرد.
bool _isEntityKind(String key) => key.startsWith('entity_');

/// مستحقات تحتاج متابعة: «له» و«عليه» إن وُجد أيّهما.
int _dueFollowUpCount(_PersonItem person) =>
    (person.dueToYou > 0 ? 1 : 0) + (person.dueOnYou > 0 ? 1 : 0);

/// مستندات الفرد المنتهية ([expired]) أو التي تنتهي خلال 30 يومًا — من
/// تواريخ انتهاء وثائقه الفعلية، لا من نص محفوظ.
int _personDocsCount(_PersonItem person, bool expired) {
  var count = 0;
  for (final doc in _IdentityDoc.all) {
    final days = _daysFromToday(person.details[doc.expiryKey] ?? '');
    if (days == null) continue;
    if (expired ? days < 0 : days >= 0 && days <= 30) count++;
  }
  for (final line in person.activityLog) {
    if (!line.startsWith('مستندات')) continue;
    final due = _PeopleManagementScreenState._entryDueDate(line);
    if (due == null) continue;
    final days = DateUtils.dateOnly(due)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    if (expired ? days < 0 : days >= 0 && days <= 30) count++;
  }
  return count;
}

/// مستندات تحتاج متابعة — نفس تعريف «وثائق للمتابعة» في مركز المتابعة،
/// فلا يختلف رقم البطاقة عن رقم المركز.
int _docsFollowUpCount(_PersonItem person) =>
    _personDocsCount(person, true) + _personDocsCount(person, false);

/// سطر التصنيف بلا تكرار: سجل تصنيفه «قريب» ودوره «قريب» كان يظهر
/// «قريب · قريب».
String _personTypeLine(_PersonItem person, {bool withRole = true}) {
  final parts = <String>[
    person.categoryName,
    ...person.additionalCategoryNames,
    if (withRole) person.roleTitle,
  ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  return parts.join(' · ');
}

String _todayStamp() {
  final now = DateTime.now();
  return '${now.day}/${now.month}/${now.year}';
}

/// يحوّل تاريخ السجل النصي إلى DateTime حقيقي للمقارنة والترتيب.
/// يتسامح مع القيمة القديمة 'اليوم' المخزَّنة من نسخ سابقة فيعدّها تاريخ
/// اليوم، ومع أي نص غير صالح فيضعه في أقدم نقطة حتى لا يتصدّر القائمة.
DateTime _parsePersonDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
  if (text == 'اليوم') return DateTime.now();
  final parts = text.split('/');
  if (parts.length == 3) {
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d != null && m != null && y != null) return DateTime(y, m, d);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// فلتر الأفراد والجهات — لفلتر الصفحة الرئيسية.
AppFilterModuleConfig peopleFilterModuleConfig() =>
    _PeopleManagementScreenState.moduleConfig();

class PeopleManagementScreen extends StatefulWidget {
  /// فلتر يُطبَّق عند الفتح (من فلتر الصفحة الرئيسية).
  final AppFilterValues? initialFilter;

  /// فتح نموذج «إضافة فرد/جهة» مباشرة بهذا النوع (مفتاحه مثل
  /// person_employee)، ثم الرجوع بعد إغلاقه — يُستعمل من العقارات
  /// والأنشطة والمركبات لتكون الإضافة واحدة في التطبيق.
  /// [kAddAnyType]: النموذج نفسه والنوع يُختار داخله من كل الأنواع.
  final String? openAddForType;

  /// قيمة [openAddForType]: النوع يُختار داخل النموذج (أفراد وجهات معًا).
  static const String kAddAnyType = 'any';

  /// تفاصيل تُحفظ مع السجل الجديد (ربطه بالأصل الذي أُضيف منه).
  final Map<String, String> linkDetails;

  /// فتح تفاصيل فرد/جهة بالاسم مباشرة (من المثبّت في الرئيسية) ثم الرجوع.
  final String? openPersonName;

  const PeopleManagementScreen({
    super.key,
    this.initialFilter,
    this.openPersonName,
    this.openAddForType,
    this.linkDetails = const {},
  });

  @override
  State<PeopleManagementScreen> createState() => _PeopleManagementScreenState();
}

/// يُعيَّن في main.dart: يفتح نموذج «تفويض جديد» نفسه الموجود في
/// «المزيد ← التفويضات» والمفوَّض معبّأ باسم الفرد.
Future<void> Function(BuildContext context, String delegateName)?
openDelegationFormForPerson;

/// مفتاح ربط بند في الالتزامات الشخصية بفرد أُضيف البند من تفاصيله.
const String kLinkedPersonKey = 'الفرد المرتبط';

/// حالات منتهية لا تحتاج متابعة.
const Set<String> _closedStatuses = {
  'مكتملة',
  'مكتمل',
  'مؤرشف',
  'محذوف',
  'تمت التسوية',
  'ملغاة',
};

/// أنواع «المتابعة والتخطيط» في الالتزامات الشخصية.
const Set<String> _organizationEntryTypes = {
  'مهمة',
  'موعد',
  'عادة',
  'تذكير',
  'ملاحظات',
  'متابعة',
  'تسجيل / تخطيط',
  'تجديد',
};

/// هل هذا البند من الالتزامات الشخصية يخص هذا الفرد؟
bool _recordLinkedTo(PersonalEntryRecord record, _PersonItem person) {
  if (record.status == 'محذوف') return false;
  final name = person.fullName.trim();
  if ((record.details[kLinkedPersonKey] ?? '').trim() == name) return true;
  // العهدة والدين المرتبطان بالرقم التعريفي: هذا الشخص طرفها الآخر.
  final personId = (person.details['الرقم التعريفي'] ?? '').trim();
  if (personId.isNotEmpty &&
      (record.entryType == 'عهدة مالية' ||
          record.entryType == 'دين / قرض / سلفة')) {
    final holder = (record.details[CustodyAssignment.kHolderId] ?? '').trim();
    final owner = (record.details[CustodyAssignment.kOwnerId] ?? '').trim();
    if (holder == personId || owner == personId) return true;
  }
  if (person.typeKey == 'person_self' &&
      (record.entryType == 'مستند' || record.entryType == 'ضمانات')) {
    return true;
  }
  if (record.entryType == 'أدوية') {
    final who = (record.details['لمن هذا الدواء'] ?? '').trim();
    if (person.typeKey == 'person_self') return who == 'أدوية لي';
    if (who == 'أدوية لشخص آخر') {
      return (record.details['اسم المستفيد'] ?? '').trim() == name;
    }
    return who == name;
  }
  return false;
}

/// كم يومًا بين اليوم وتاريخ بصيغة يوم/شهر/سنة (سالب = فات).
int? _daysFromToday(String raw) {
  final date = AppRemindersStore.parseDisplayDate(raw);
  if (date == null) return null;
  return DateUtils.dateOnly(date)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
}

/// حالة دواء: اليوم (ساري)، قادمة (لم يبدأ)، منتهية.
String _medicineState(PersonalEntryRecord record) {
  final from = _daysFromToday(record.details['من تاريخ'] ?? '');
  final to = _daysFromToday(
    record.details['إلى تاريخ'] ?? record.dueDate,
  );
  if (to != null && to < 0) return 'أدوية منتهية';
  if (from != null && from > 0) return 'أدوية قادمة';
  return 'أدوية اليوم';
}

/// حالة بند متابعة وتخطيط حسب موعده.
String _planState(PersonalEntryRecord record) {
  if (_closedStatuses.contains(record.status)) return 'مكتملة';
  if (entryDerivedStatus(record.status, record.details) == 'منتهية') {
    return 'مكتملة';
  }
  // نفس صفحة الالتزامات الشخصية: الملاحظة بلا موعد، والمتكرر بموعده القادم.
  final follow = entryFollowDate(
    type: record.entryType,
    due: entryParseDay(record.dueDate),
    details: record.details,
  );
  final days = follow == null
      ? null
      : DateUtils.dateOnly(follow)
            .difference(DateUtils.dateOnly(DateTime.now()))
            .inDays;
  if (days == null) return 'نشطة';
  if (days < 0) return 'متأخرة';
  if (days == 0) return 'حان وقتها';
  if (days <= 7) return 'قريبًا';
  return 'نشطة';
}

class _PeopleManagementScreenState extends State<PeopleManagementScreen> {
  static const _peopleStorageKey = 'people_management_records_v1';

  final TextEditingController _searchController = TextEditingController();
  String _selectedScopeKey = 'scope_all';
  String _selectedTypeKey = 'all';
  String _selectedSort = 'الأحدث أولاً';

  // الضيف لا يرى أسماء أمثلة كأنها بيانات أحد — القائمة فارغة حتى يسجّل.
  late final List<_PersonItem> _people =
      FundlyAuth.isGuest ? <_PersonItem>[] : _seedPeople();

  List<_PersonItem> _seedPeople() => [
    _PersonItem(
      fullName: 'أحمد محمد سالم',
      nickName: 'سليم',
      roleTitle: 'سائق خاص',
      badge: 'متابعة',
      badgeColor: const Color(0xFF34A894),
      statusNote: 'مستند ينتهي خلال 10 أيام',
      extraNote: 'مفوّض (بناية سكنية)',
      typeKey: 'person_employee',
      categoryName: 'موظف',
      dueToYou: 0,
      dueOnYou: 120,
      openTasks: 1,
      documentsCount: 4,
      lastUpdate: '2/5/2025',
      createdAt: '8/8/2024',
      sharedCommitments: ['رحلة عائلية', 'اشتراك السكن'],
      documents: ['هوية', 'عقد عمل', 'رخصة قيادة'],
      details: {
        'تاريخ الميلاد': '14/9/1991',
      },
    ),
    _PersonItem(
      fullName: 'راشد خالد',
      nickName: 'يحتاج متابعة',
      roleTitle: 'محاسب',
      badge: 'تنبيه',
      badgeColor: const Color(0xFFF2A93F),
      statusNote: 'مستند قارب على الانتهاء بعد 60 يوم',
      extraNote: 'لديه عهدة نشطة',
      typeKey: 'person_employee',
      categoryName: 'موظف',
      dueToYou: 3200,
      dueOnYou: 0,
      openTasks: 3,
      documentsCount: 8,
      lastUpdate: '1/5/2025',
      createdAt: '11/2/2024',
      sharedCommitments: ['مصاريف المكتب المشتركة'],
      documents: ['هوية', 'عقد توظيف', 'تفويض بنكي'],
      details: {
        'تاريخ الميلاد': '2/3/1988',
      },
    ),
    _PersonItem(
      fullName: 'محمد سالم',
      nickName: 'عاجل',
      roleTitle: 'فني كهرباء',
      badge: 'عاجل',
      badgeColor: const Color(0xFFC4392E),
      statusNote: 'مستند منتهي منذ يومين',
      extraNote: 'لا يوجد عليه مستحقات',
      typeKey: 'person_relative',
      categoryName: 'قريب',
      dueToYou: 500,
      dueOnYou: 0,
      openTasks: 0,
      documentsCount: 2,
      lastUpdate: '28/4/2025',
      createdAt: '9/11/2023',
      sharedCommitments: ['التزام مصروف شهري'],
      documents: ['هوية', 'جواز سفر'],
      details: {
        'تاريخ الميلاد': '20/1/1994',
      },
    ),
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFilter;
    if (initial != null) _applyFilterValues(initial);
    final loaded = _loadSavedPeople();
    // جوال آخر أضاف أو عدّل: تُعاد القراءة حتى لا يُحفظ فوقه ما في الذاكرة.
    FundlyAccount.cloudRevision.addListener(_onCloudChanged);
    _loadDelegations();
    _loadPersonalRecords();
    final openName = widget.openPersonName?.trim() ?? '';
    if (openName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await loaded;
        if (!mounted) return;
        _PersonItem? found;
        for (final person in _people) {
          if (person.fullName.trim() == openName) found = person;
        }
        // غير موجود: تبقى القائمة ظاهرة.
        if (found == null) return;
        await _openPersonDetailsAwait(found);
        if (mounted) Navigator.of(context).pop();
      });
    }
    final typeKey = widget.openAddForType;
    if (typeKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // تُقرأ السجلات المحفوظة أولًا، وإلا كُتب فوقها عند الحفظ.
        await loaded;
        if (!mounted) return;
        _TypeFilterDef? type;
        for (final filter in _allTypeFilters) {
          if (filter.key == typeKey) type = filter;
        }
        await _openContactFormSheet(
          isEntity: typeKey.startsWith('entity_'),
          type: type,
          anyType: typeKey == PeopleManagementScreen.kAddAnyType,
        );
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  /// بنود الالتزامات الشخصية: الطلبات والعهد والأدوية والمتابعات المرتبطة
  /// بكل فرد — لمركز المتابعة الموحّد.
  List<PersonalEntryRecord> _personalRecords = const [];

  Future<void> _loadPersonalRecords() async {
    try {
      final rows = await SupabasePersonalEntriesRepository().fetchAll();
      if (!mounted) return;
      setState(() => _personalRecords = rows);
    } catch (_) {
      // مركز المتابعة يعمل ببيانات الأفراد وحدها إن تعذّر التحميل.
    }
  }

  /// تفويضات كل السجلات — تُقرأ مرة واحدة ليعرف مركز المتابعة ما يقارب
  /// الانتهاء. التفويض محفوظ في جدول «delegations» لا في تفاصيل الشخص.
  List<DelegationRecord> _allDelegations = const [];

  Future<void> _loadDelegations() async {
    try {
      final rows = await SupabaseDelegationsRepository().fetchDelegations();
      if (!mounted) return;
      setState(() => _allDelegations = rows);
    } catch (_) {
      // تعذّر الاتصال: تبقى المجموعة فارغة بلا إسقاط الشاشة.
    }
  }

  /// تفويضات هذا السجل التي تقارب الانتهاء.
  /// تفويضات هذا السجل — يُربط بالمرجع أولًا ثم بالاسم للسجلات القديمة.
  List<DelegationRecord> _delegationsOf(_PersonItem person) {
    final name = person.fullName.trim();
    if (name.isEmpty) return const [];
    return _allDelegations.where((record) {
      final ref = (record.delegateRef ?? '').trim();
      if (ref == 'person:$name') return true;
      if (ref.startsWith('person:')) return false;
      return record.delegateName.trim() == name;
    }).toList(growable: false);
  }

  int _expiringDelegationsFor(_PersonItem person) =>
      _delegationsOf(person).where((record) => record.isExpiringSoon).length;

  /// التفويضات التي انقضى أجلها — كانت غائبة عن مركز المتابعة تمامًا، فلا
  /// ينبّه شيء إلى تفويض ساقط ما زال المستخدم يحسبه ساريًا.
  int _endedDelegationsFor(_PersonItem person) =>
      _delegationsOf(person).where((record) => record.isEnded).length;

  /// تاريخ الاستحقاق المكتوب داخل سطر السجل بصيغة «ينتهي d/m/yyyy».
  /// بنود السجل نصوص مركَّبة، ومن دون قراءة هذا التاريخ تبقى أرقام مركز
  /// المتابعة مبنية على أعلام الواجهة (مثبّت/مجمّد) لا على مواعيد حقيقية.
  static DateTime? _entryDueDate(String line) {
    final match = RegExp(r'ينتهي\s+(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(line);
    if (match == null) return null;
    final d = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    final y = int.tryParse(match.group(3)!);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  /// عدد بنود قسم بعينه الواقعة في نافذة زمنية بالنسبة لليوم:
  /// bucket = 'soon' خلال الأيام القادمة، 'today' اليوم، 'late' فات موعدها.
  int _dueEntryCount(_PersonItem person, String category, String bucket) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var count = 0;
    for (final line in person.activityLog) {
      if (!line.startsWith(category)) continue;
      final due = _entryDueDate(line);
      if (due == null) continue;
      final days = due.difference(today).inDays;
      final matched = switch (bucket) {
        'today' => days == 0,
        'late' => days < 0,
        _ => days > 0 && days <= 7,
      };
      if (matched) count++;
    }
    return count;
  }

  void _openSmartCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(
        builder: (_) => const SmartCalendarScreen(
          modules: SmartCalendarScreen.peopleModules,
          scopeLabel: 'الأفراد والجهات',
        ),
      ));
  }

  /// الأشخاص والجهات المؤرشفة — الأرشفة علامة داخل الملاحظة الإضافية.
  List<_PersonItem> get _archivedPeople => _people
      .where((person) => person.extraNote.contains('[مؤرشف]'))
      .toList(growable: false);

  /// نافذة الأرشيف: إلغاء الأرشفة تنزع العلامة وتُلغي التجميد.
  Future<void> _openArchiveSheet() async {
    final changed = await showArchiveSheet(
      context,
      title: 'الأفراد والجهات',
      entries: [
        for (final person in _archivedPeople)
          ArchiveEntry(
            title: person.fullName,
            subtitle: person.extraNote.replaceAll('[مؤرشف]', '').trim(),
            icon: Icons.person_outline_rounded,
            onUnarchive: () async {
              final index = _people.indexOf(person);
              if (index == -1) return false;
              setState(() {
                _people[index] = person.copyWith(
                  extraNote: person.extraNote
                      .replaceAll('[مؤرشف]', '')
                      .trim(),
                  isFrozen: false,
                );
              });
              await _persistWithFeedback();
              return true;
            },
          ),
      ],
    );
    if (!changed || !mounted) return;
    setState(() {});
  }

  Future<void> _loadSavedPeople() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peopleStorageKey);
    if (raw == null || raw.isEmpty) {
      // لا يوجد مخزون محلي بعد: تُكتب السجلات الأولية الظاهرة في هذه الشاشة
      // إلى نفس المخزن، حتى تقرأها بطاقة "إدارة الأشخاص والجهات" في الصفحة
      // الرئيسية وتعرض العدد الحقيقي بدل صفر لا يطابق ما يراه المستخدم هنا.
      await _persistPeople();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      // شكل غير متوقع = مخزون تالف أيضًا، يُعامَل بنفس المعاملة بدل العودة
      // الصامتة إلى بيانات البذرة.
      if (decoded is! List) throw const FormatException('unexpected shape');
      final restored = decoded
          .whereType<Map>()
          .map((entry) => _PersonItem.fromMap(Map<String, dynamic>.from(entry)))
          .toList(growable: true);
      if (!mounted) return;
      setState(() {
        _people
          ..clear()
          ..addAll(restored);
      });
    } catch (_) {
      // مخزون تالف: تُحفَظ نسخة منه ويُمنع الحفظ فوقه، وإلا كتبت أول عملية
      // تعديل بيانات البذرة الثلاثة فوق جهات المستخدم الحقيقية بلا رجعة.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${_peopleStorageKey}_corrupt_backup', raw);
      } catch (_) {
        // لا شيء إضافي يمكن فعله هنا.
      }
      _storageBlocked = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّرت قراءة السجلات المحفوظة. حُفظت نسخة احتياطية ولن يُكتب فوقها.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// يُرفع عند فشل قراءة المخزون، فيمنع أي كتابة تُتلف بيانات المستخدم.
  bool _storageBlocked = false;

  Future<void> _persistPeople() async {
    if (_storageBlocked) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_people.map((item) => item.toMap()).toList());
    await prefs.setString(_peopleStorageKey, encoded);
  }

  static const List<_TypeFilterDef> _allTypeFilters = [
    _TypeFilterDef('all', 'الكل', Color(0xFF022E2A)),
    _TypeFilterDef('person_relative', 'قريب', Color(0xFF0A5A50)),
    _TypeFilterDef('person_friend', 'صديق', Color(0xFF34A894)),
    _TypeFilterDef('person_employee', 'موظف', Color(0xFFF2A93F)),
    _TypeFilterDef('person_client', 'عميل', Color(0xFF0A5A50)),
    _TypeFilterDef('person_tenant', 'مستأجر', Color(0xFFD95A4E)),
    _TypeFilterDef('person_supplier', 'مورد', Color(0xFFCE8422)),
    _TypeFilterDef('person_contractor', 'مقاول', Color(0xFF0E7161)),
    _TypeFilterDef('person_partner', 'شريك', Color(0xFF34A894)),
    _TypeFilterDef('person_landlord', 'مؤجر', Color(0xFF178F7B)),
    _TypeFilterDef('person_representative', 'مندوب', Color(0xFF0E7161)),
    _TypeFilterDef('person_consultant', 'استشاري', Color(0xFF0A5A50)),
    _TypeFilterDef('person_other', 'أخرى', Color(0xFF5C6B68)),
    _TypeFilterDef('entity_company', 'الشركات', Color(0xFF0A5A50)),
    _TypeFilterDef('entity_government', 'جهات حكومية', Color(0xFF0A5A50)),
    _TypeFilterDef('entity_bank', 'بنك', Color(0xFF34A894)),
    _TypeFilterDef('entity_education', 'مؤسسات تعليمية', Color(0xFFF2A93F)),
    _TypeFilterDef('entity_health', 'مؤسسات صحية', Color(0xFFD95A4E)),
    _TypeFilterDef('entity_organization', 'منظمات', Color(0xFF0E7161)),
    _TypeFilterDef('entity_other', 'جهات أخرى', Color(0xFF5C6B68)),
  ];

  /// تصنيفات لا تُضاف يدويًا من هنا: «مستأجر» و«مؤجر» ينشآن تلقائيًا حين
  /// يُربط الشخص بعقد في العقارات أو الآليات أو الأنشطة التجارية. يبقيان في
  /// قوائم الفلترة ليظهر من أُنشئ منهما.
  static const List<String> _autoOnlyTypeKeys = [
    'person_tenant',
    'person_landlord',
  ];

  List<_TypeFilterDef> _createTypeFilters(bool isEntity) {
    return _allTypeFilters
        .where(
          (filter) =>
              filter.key != 'all' &&
              !_autoOnlyTypeKeys.contains(filter.key) &&
              (isEntity
                  ? filter.key.startsWith('entity_')
                  : filter.key.startsWith('person_')),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    FundlyAccount.cloudRevision.removeListener(_onCloudChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCloudChanged() {
    if (!mounted || _storageBlocked) return;
    _loadSavedPeople();
  }

  // ---------------- تخصيص الصفحة ----------------

  /// «الأفراد» أو «الجهات» — فئة النوع في «تخصيص الصفحات».
  static String _scopeTitleOf(String typeKey) =>
      typeKey.startsWith('entity_') ? 'الجهات' : 'الأفراد';

  /// نوع مخفي (هو أو فئته كلها) من «تخصيص الصفحات».
  static bool _typeKeyHidden(String typeKey) {
    var label = '';
    for (final filter in _allTypeFilters) {
      if (filter.key == typeKey) label = filter.label;
    }
    return PageCustomizationStore.itemHidden(
      PageCustomizationStore.people,
      _scopeTitleOf(typeKey),
      label,
    );
  }

  static bool _scopeHidden(bool isEntity) =>
      PageCustomizationStore.categoryHidden(
        PageCustomizationStore.people,
        isEntity ? 'الجهات' : 'الأفراد',
      );

  /// السجلات الظاهرة — المخفي من «تخصيص الصفحات» لا يُعرض ولا يُعدّ.
  // سجلات صاحب الحساب نفسه (أُضيف كمؤجر أو مستأجر أو موظف...) لا تتكرر
  // في القائمة: تُدمج في بطاقة «أنا» أولها.
  List<_PersonItem> get _visiblePeople => _people
      .where((person) => !_typeKeyHidden(person.typeKey))
      .where((person) => !_isMeRecord(person))
      .toList(growable: false);

  /// سجل يخص صاحب الحساب: برقمه التعريفي، أو باسمه كما في الملف الشخصي.
  static bool _isMeRecord(_PersonItem person) {
    if (person.typeKey == 'person_self') return false;
    final myId = AppIdentity.id.trim().toUpperCase();
    final fnd = (person.details['الرقم التعريفي'] ?? '').trim().toUpperCase();
    if (myId.isNotEmpty && fnd.isNotEmpty) return fnd == myId;
    final settings = AppSettings.instance;
    // نفس رقم هاتفي أو بريدي = أنا، ولو كُتب اسمي بلغة أخرى (مؤجر أُدخل
    // باسمي العربي والملف الشخصي بالإنجليزي مثلًا).
    String lastDigits(String value) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
    }
    final myPhone = lastDigits(settings.phone);
    if (myPhone.length >= 7 &&
        lastDigits(person.details['رقم الهاتف'] ?? '') == myPhone) {
      return true;
    }
    final myEmail = settings.email.trim().toLowerCase();
    if (myEmail.contains('@') &&
        (person.details['البريد الإلكتروني'] ?? '').trim().toLowerCase() ==
            myEmail) {
      return true;
    }
    final name = person.fullName.trim();
    if (name.isEmpty) return false;
    final full = '${settings.givenName} ${settings.familyName}'.trim();
    return settings.isMyName(name) || (full.isNotEmpty && name == full);
  }

  int _countByType(String key) {
    final people = _visiblePeople;
    if (key == 'all') return people.length;
    if (key == 'all_people') {
      return people.where((person) => _isPersonType(person.typeKey)).length;
    }
    if (key == 'all_entities') {
      return people.where((person) => _isEntityType(person.typeKey)).length;
    }
    if (key.startsWith('status_')) {
      return people
          .where((person) => _isPersonType(person.typeKey))
          .where((person) => _matchesPeopleStatusFilter(person, key))
          .length;
    }
    return people.where((person) => person.typeKey == key).length;
  }

  int _countByScope(String scopeKey) {
    final people = _visiblePeople;
    if (scopeKey == 'scope_people') {
      return people.where((person) => _isPersonType(person.typeKey)).length;
    }
    if (scopeKey == 'scope_entities') {
      return people.where((person) => _isEntityType(person.typeKey)).length;
    }
    return people.length;
  }

  bool _isPersonType(String key) => key.startsWith('person_');

  bool _isEntityType(String key) => key.startsWith('entity_');

  bool _matchesPeopleStatusFilter(_PersonItem person, String statusKey) {
    final status = '${person.badge} ${person.nickName} ${person.statusNote}';
    return switch (statusKey) {
      'status_near' =>
        status.contains('قريب') ||
            status.contains('ينتهي خلال') ||
            status.contains('قارب') ||
            _personDocsCount(person, false) > 0,
      'status_urgent' =>
        status.contains('مستعجل') ||
            status.contains('عاجل') ||
            status.contains('تنبيه'),
      'status_late' =>
        status.contains('متأخر') ||
            status.contains('منتهي') ||
            status.contains('متأخرة') ||
            _personDocsCount(person, true) > 0,
      _ => false,
    };
  }

  List<_TypeFilterDef> _visibleTypeFilters() {
    if (_selectedScopeKey == 'scope_people') {
      return _allTypeFilters
          .where((f) => f.key.startsWith('person_'))
          .toList(growable: false);
    }
    if (_selectedScopeKey == 'scope_entities') {
      return [..._allTypeFilters.where((f) => f.key.startsWith('entity_'))];
    }
    return const [];
  }

  /// عناصر القائمة المنسدلة لشريحة "الأفراد" أو "الجهات".
  ///
  /// كانت هذه التصنيفات تُعرض في نافذة تملأ الشاشة بكل عناصرها دفعةً
  /// واحدة؛ صارت قائمة منسدلة أسفل الشريحة نفسها.
  List<AppDropdownItem> _scopeDropdownItems({required bool isEntity}) {
    final scopeKey = isEntity ? 'scope_entities' : 'scope_people';
    final allKey = isEntity ? 'all_entities' : 'all_people';
    final allLabel = isEntity ? 'كل الجهات' : 'كل الأفراد';
    final allIcon = isEntity
        ? Icons.apartment_rounded
        : Icons.people_alt_outlined;

    AppDropdownItem build(String key, String label, IconData icon) {
      return AppDropdownItem(
        label: label,
        icon: icon,
        count: _countByType(key),
        selected: _selectedScopeKey == scopeKey && _selectedTypeKey == key,
        onTap: () => setState(() {
          _selectedScopeKey = scopeKey;
          _selectedTypeKey = key;
          // الفئة الفرعية في الفلتر الكبير تتبع الاختيار هنا، وإلا بقيت
          // قيمة قديمة تُعاد تطبيقها فوق اختيار المستخدم.
          _filter.subCategory = null;
        }),
      );
    }

    return [
      build(allKey, allLabel, allIcon),
      ..._createTypeFilters(isEntity)
          .where((filter) => !_typeKeyHidden(filter.key))
          .map((filter) => build(filter.key, filter.label, _typeIcon(filter.key))),
    ];
  }

  /// قيم الفلتر الرئيسي — نفس البنية في الشاشات الأربع.
  final AppFilterValues _filter = AppFilterValues();

  bool _matchesAdvancedPeopleFilters(_PersonItem person) {
    switch (_filter.status) {
      case 'نشط' || 'نشطة':
        if (person.isFrozen) return false;
      case 'مكتملة':
        if (person.openTasks > 0 ||
            person.dueToYou > 0 ||
            person.dueOnYou > 0) {
          return false;
        }
      case 'المستحق بعد 7 أيام':
        if (person.openTasks <= 0) return false;
      case 'متأخر':
        // وثيقة منتهية فعلًا تُعدّ أيضًا (من تواريخها لا من نص محفوظ).
        if (!person.statusNote.contains('متأخر') &&
            !person.badge.contains('عاجل') &&
            _personDocsCount(person, true) == 0) {
          return false;
        }
      case 'مكتمل':
        if (person.openTasks > 0) return false;
      case 'ملغاة':
        if (!person.badge.contains('ملغا')) return false;
      case 'مؤرشف':
        if (!person.isFrozen) return false;
    }
    // الدين ▼: «لي» مستحقات لك، «عليّ» مستحقات عليك.
    switch (_filter.debtDirection) {
      case 'لي':
        if (person.dueToYou <= 0) return false;
      case 'عليّ':
        if (person.dueOnYou <= 0) return false;
    }
    // المبلغ — الفلتر ▼: قريبة الاستحقاق / مستحقة / متأخرة.
    final dueBucket = switch (_filter.dueState) {
      'قريبة الاستحقاق' => 'soon',
      'مستحقة' => 'today',
      'متأخرة' => 'late',
      _ => null,
    };
    if (dueBucket != null && _dueEntryCount(person, 'مالية', dueBucket) == 0) {
      return false;
    }
    // المستند — الفلتر ▼: قريبة الانتهاء / منتهية.
    if (_filter.documentState != null &&
        !_personDocMatches(person, _filter.documentState!)) {
      return false;
    }
    // اختصارات المبلغ: "لي" مستحقات لك، "عليّ" مستحقات عليك.
    switch (_filter.amountShortcut) {
      case 'لي':
        if (person.dueToYou <= 0) return false;
      case 'عليّ':
        if (person.dueOnYou <= 0) return false;
    }
    final amount = person.dueToYou > 0 ? person.dueToYou : person.dueOnYou;
    if (!_filter.matchesAmount(amount)) return false;
    if (_filter.personName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.personName, [
          person.fullName,
          person.nickName,
          person.roleTitle,
        ])) {
      return false;
    }
    if (_filter.personCategory != null &&
        !person.categoryName.contains(_filter.personCategory!)) {
      return false;
    }
    if (_filter.delegateName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.delegateName, [
          person.fullName,
          person.details['المفوَّض'] ?? '',
        ])) {
      return false;
    }
    if (_filter.documentName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.documentName, person.documents)) {
      return false;
    }
    if (_filter.placeName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.placeName, [
          person.details['العنوان'] ?? '',
          person.details['المكان'] ?? '',
        ])) {
      return false;
    }
    if (!_filter.matchesDate(_parsePeopleDate(person.lastUpdate))) return false;
    return true;
  }

  /// تواريخ انتهاء مستندات الشخص/الجهة (الهوية، الجواز، وثائق الجهة...).
  List<DateTime> _personDocExpiries(_PersonItem person) => [
    for (final entry in person.details.entries)
      if (entry.key.startsWith('انتهاء ') || entry.key == 'تاريخ الانتهاء')
        if (_parsePeopleDate(entry.value.trim()) case final date?) date,
  ];

  /// مستندات قريبة الانتهاء (خلال 30 يومًا) أو منتهية.
  bool _personDocMatches(_PersonItem person, String label) {
    final today = DateUtils.dateOnly(DateTime.now());
    final expiries = _personDocExpiries(person);
    final note = person.statusNote;
    if (label.contains('قريب')) {
      return expiries.any((date) {
            final days = date.difference(today).inDays;
            return days >= 0 && days <= 30;
          }) ||
          (note.contains('مستند') &&
              (note.contains('قريب') || note.contains('ينتهي')));
    }
    if (label.contains('منته')) {
      return expiries.any((date) => date.isBefore(today)) ||
          (note.contains('مستند') && note.contains('منته'));
    }
    return true;
  }

  /// تحويل تاريخ نصّي (d/M/yyyy) إلى DateTime، أو null إن تعذّر.
  DateTime? _parsePeopleDate(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  /// صاحب الحساب نفسه — بطاقة تُبنى من الملف الشخصي في الإعدادات، ولا
  /// تُخزَّن ولا تُعدَّل من هنا. كان على المستخدم أن يُدخل نفسه يدويًا.
  _PersonItem _selfRecord() {
    final settings = AppSettings.instance;
    final owner = settings.name.trim();
    // صفاتي الأخرى (مؤجر، مستأجر، موظف...) من سجلاتي المدموجة تُكتب في
    // سطر التصنيف وفي الملخص، ومستحقاتها ومستنداتها تُجمع هنا.
    final mine = _people.where(_isMeRecord).toList(growable: false);
    final roles = <String>{
      for (final p in mine) ...[
        p.categoryName,
        ...p.additionalCategoryNames,
        p.roleTitle,
      ],
    }.map((e) => e.trim()).where((e) => e.isNotEmpty && e != 'صاحب الحساب');
    final mergedDetails = <String, String>{
      for (final p in mine)
        for (final entry in p.details.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };
    final own = <String, String>{
      'رقم الهاتف': settings.phone,
      'البريد الإلكتروني': settings.email,
      'تاريخ الميلاد': settings.birthday,
      'العنوان': settings.city,
      'معلومات إضافية': settings.social,
    };
    return _PersonItem(
      fullName: 'أنا (${owner.isEmpty ? 'صاحب الحساب' : owner})',
      nickName: 'صاحب الحساب',
      roleTitle: 'صاحب الحساب',
      badge: 'أنا',
      badgeColor: const Color(0xFF0E7161),
      statusNote: 'بياناتك من الملف الشخصي',
      extraNote: '',
      typeKey: 'person_self',
      categoryName: 'صاحب الحساب',
      additionalCategoryNames: roles.toSet().toList(growable: false),
      dueToYou: mine.fold(0, (sum, p) => sum + p.dueToYou),
      dueOnYou: mine.fold(0, (sum, p) => sum + p.dueOnYou),
      openTasks: mine.fold(0, (sum, p) => sum + p.openTasks),
      documentsCount: mine.fold(0, (sum, p) => sum + p.documentsCount),
      lastUpdate: _todayStamp(),
      createdAt: _todayStamp(),
      sharedCommitments: [
        for (final p in mine) ...p.sharedCommitments,
      ].toSet().toList(growable: false),
      documents: [
        for (final p in mine) ...p.documents,
      ].toSet().toList(growable: false),
      activityLog: [for (final p in mine) ...p.activityLog],
      isPinned: true,
      // بيانات الملف الشخصي أولًا، وما ينقصها من سجلاتي المدموجة.
      details: {
        ...mergedDetails,
        for (final entry in own.entries)
          if (entry.value.trim().isNotEmpty ||
              !mergedDetails.containsKey(entry.key))
            entry.key: entry.value,
      },
    );
  }

  List<_PersonItem> _filteredPeople() {
    final query = _searchController.text.trim();

    final filtered = _visiblePeople.where((person) {
      final scopeMatches =
          _selectedScopeKey == 'scope_all' ||
          (_selectedScopeKey == 'scope_people' &&
              _isPersonType(person.typeKey)) ||
          (_selectedScopeKey == 'scope_entities' &&
              _isEntityType(person.typeKey));

      final typeMatches =
          _selectedTypeKey == 'all' ||
          (_selectedTypeKey == 'all_people' && _isPersonType(person.typeKey)) ||
          (_selectedTypeKey == 'all_entities' &&
              _isEntityType(person.typeKey)) ||
          (_selectedTypeKey.startsWith('status_') &&
              _isPersonType(person.typeKey) &&
              _matchesPeopleStatusFilter(person, _selectedTypeKey)) ||
          person.typeKey == _selectedTypeKey;

      final queryMatches = matchesSearchQuery(
        query: query,
        fields: [
          person.fullName,
          person.nickName,
          person.roleTitle,
          person.badge,
          person.statusNote,
          person.categoryName,
          person.extraNote,
          person.typeKey,
          person.lastUpdate,
          person.createdAt,
          '${person.dueToYou}',
          '${person.dueOnYou}',
          '${person.openTasks}',
          ...person.sharedCommitments,
          ...person.documents,
          ...person.details.keys,
          ...person.details.values,
        ],
      );
      return scopeMatches &&
          typeMatches &&
          queryMatches &&
          _matchesAdvancedPeopleFilters(person);
    }).toList();

    // المثبَّت أولًا دائمًا مهما كان الترتيب المختار (نفس سلوك شاشة
    // العقارات)، ثم معيار الترتيب المطلوب. كان الترتيب الافتراضي يقارن
    // التواريخ كنصوص، فيجعل '28/4/2025' أحدث من '2/5/2025'.
    int byPinned(_PersonItem a, _PersonItem b) {
      if (a.isPinned == b.isPinned) return 0;
      return a.isPinned ? -1 : 1;
    }

    // الفلتر الصغير: كل خيار يُظهر ما يطابقه فقط، و«الأحدث أولاً» ترتيب.
    filtered.removeWhere(
      (person) => switch (_selectedSort) {
        'نشط' => person.isFrozen,
        'مستندات قريبة الانتهاء' ||
        'مستندات قريبة الإنتهاء' => !_personDocMatches(person, 'قريبة'),
        'مستندات منتهية' => !_personDocMatches(person, 'منتهية'),
        _ => false,
      },
    );

    filtered.sort((a, b) {
      final pinned = byPinned(a, b);
      if (pinned != 0) return pinned;
      // الدين ▼: «الأعلى/الأقل مطالبة» ترتيب بإجمالي المستحقات.
      if (_filter.amountShortcut == 'أعلى مستحقات' ||
          _filter.debtDirection == 'الأعلى مطالبة') {
        final byDue = (b.dueToYou + b.dueOnYou).compareTo(
          a.dueToYou + a.dueOnYou,
        );
        if (byDue != 0) return byDue;
      } else if (_filter.debtDirection == 'الأقل مطالبة') {
        final byDue = (a.dueToYou + a.dueOnYou).compareTo(
          b.dueToYou + b.dueOnYou,
        );
        if (byDue != 0) return byDue;
      }
      return _parsePersonDate(
        b.lastUpdate,
      ).compareTo(_parsePersonDate(a.lastUpdate));
    });
    return filtered;
  }

  IconData _typeIcon(String key) {
    if (key == 'person_relative') return Icons.family_restroom_rounded;
    if (key == 'person_friend') return Icons.people_outline_rounded;
    if (key == 'person_employee') return Icons.badge_outlined;
    if (key == 'person_client') return Icons.handshake_outlined;
    if (key == 'all_people') return Icons.people_alt_outlined;
    if (key == 'all_entities') return Icons.apartment_rounded;
    if (key == 'status_near') return Icons.schedule_outlined;
    if (key == 'status_urgent') return Icons.priority_high_rounded;
    if (key == 'status_late') return Icons.warning_amber_rounded;
    if (key.startsWith('entity_')) return Icons.apartment_rounded;
    if (key == 'all') return Icons.grid_view_rounded;
    return Icons.person_outline_rounded;
  }

  String _selectedFilterLabel() {
    final visible = _visibleTypeFilters();
    final active = visible.where((item) => item.key == _selectedTypeKey);
    if (active.isNotEmpty) return active.first.label;
    return 'الكل';
  }

  String _activeSearchFilterLabel() {
    if (_selectedScopeKey == 'scope_all' || _selectedTypeKey == 'all') {
      return 'الكل';
    }
    if (_selectedTypeKey == 'all_people') return 'الأفراد';
    if (_selectedTypeKey == 'all_entities') return 'الجهات';

    final all = [
      ..._allTypeFilters,
      const _TypeFilterDef('status_near', 'قريب الانتهاء', Color(0xFF0E7161)),
      const _TypeFilterDef('status_urgent', 'مستعجل', Color(0xFFCE8422)),
      const _TypeFilterDef('status_late', 'متأخر', Color(0xFFC4392E)),
    ];
    for (final item in all) {
      if (item.key == _selectedTypeKey) return item.label;
    }
    return _selectedFilterLabel();
  }

  /// يحفظ ويُخطر المستخدم عند الفشل — كان الحفظ يُنفَّذ دون انتظار أو
  /// معالجة خطأ، فتظهر رسالة نجاح بينما التعديل لم يُكتب فعليًا.
  Future<void> _persistWithFeedback() async {
    try {
      await _persistPeople();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حفظ التعديل. حاول مرة أخرى.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// مركز المتابعة بالقالب الموحَّد نفسه المستعمل في بقية الوحدات.
  ///
  /// كان زر "المزيد" هنا يفتح نافذة **فلترة** لا علاقة لها بالمتابعة، فيرى
  /// المستخدم شيئًا مختلفًا تمامًا عمّا يراه في الالتزامات.
  /// مجموعات مركز المتابعة — مصدر واحد للبطاقة المصغّرة ولنافذة "المزيد"
  /// معًا، فلا تختلف الأرقام بينهما كما كان يحدث حين كانت كل واحدة تُحسب
  /// من استعلام مستقل.
  List<FollowUpGroup> _followUpGroups(List<_PersonItem> people) {
    FollowUpEntry entryFor(_PersonItem person, String trailing) => FollowUpEntry(
      title: person.fullName,
      subtitle: person.categoryName,
      icon: _isEntityKind(person.typeKey)
          ? Icons.apartment_rounded
          : Icons.person_outline_rounded,
      color: person.badgeColor,
      trailingText: trailing,
      onTap: () => _openPersonDetails(person),
    );

    /// مقياس يعدّ لكل فرد عدد بنوده المطابقة ويعرض من له بند واحد فأكثر.
    FollowUpMetric metric(
      String label,
      IconData icon,
      int Function(_PersonItem person) count,
    ) => FollowUpMetric(
      label: label,
      icon: icon,
      entries: [
        for (final person in people)
          if (count(person) > 0) entryFor(person, '${count(person)}'),
      ],
    );

    final myId = AppIdentity.id;
    List<PersonalEntryRecord> linked(_PersonItem person) => [
      for (final record in _personalRecords)
        if (_recordLinkedTo(record, person)) record,
    ];

    int planCount(_PersonItem person, String state) {
      final bucket = switch (state) {
        'متأخرة' => 'late',
        'حان وقتها' => 'today',
        _ => 'soon',
      };
      return _dueEntryCount(person, 'متابعة وتخطيط', bucket) +
          linked(person)
              .where(
                (r) =>
                    _organizationEntryTypes.contains(r.entryType) &&
                    _planState(r) == state,
              )
              .length;
    }

    int docsCount(_PersonItem person, bool expired) =>
        _personDocsCount(person, expired);

    // العهدة: ما سُلِّم لهذا الفرد من «عهدة مالية» في الالتزامات الشخصية.
    List<PersonalEntryRecord> custodyOf(_PersonItem person) => [
      for (final record in _personalRecords)
        if (record.entryType == 'عهدة مالية' &&
            !_closedStatuses.contains(record.status) &&
            (record.details['اسم المستلم'] ?? '').trim() ==
                person.fullName.trim())
          record,
    ];

    // نفس مجموعات مركز المتابعة في الالتزامات الشخصية وبمسمياتها نفسها،
    // ومعها التفويضات الخاصة بالأفراد والجهات.
    return [
      FollowUpGroup(
        title: 'الطلبات',
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFA6691A),
        metrics: [
          metric('بانتظار قبولي', Icons.move_to_inbox_outlined, (person) {
            if (myId.isEmpty) return 0;
            return _personalRecords.where((r) {
              final a = CustodyAssignment.decode(r.details);
              return a.isPending &&
                  a.holderId == myId &&
                  a.ownerName.trim() == person.fullName.trim();
            }).length;
          }),
          metric('أرسلتها بانتظار القبول', Icons.outbox_outlined, (person) {
            if (myId.isEmpty) return 0;
            return _personalRecords.where((r) {
              final a = CustodyAssignment.decode(r.details);
              return a.isPending &&
                  a.ownerId == myId &&
                  a.holderName.trim() == person.fullName.trim();
            }).length;
          }),
        ],
      ),
      FollowUpGroup(
        title: 'المتابعة والتخطيط',
        icon: Icons.checklist_rounded,
        color: const Color(0xFF0E7161),
        metrics: [
          metric(
            'متأخرة',
            Icons.error_outline_rounded,
            (person) => planCount(person, 'متأخرة'),
          ),
          metric(
            'حان وقتها',
            Icons.today_outlined,
            (person) => planCount(person, 'حان وقتها'),
          ),
          metric(
            'قريبة',
            Icons.hourglass_bottom_rounded,
            (person) => planCount(person, 'قريبًا'),
          ),
        ],
      ),
      FollowUpGroup(
        title: 'مالية (عام)',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF34A894),
        metrics: [
          metric(
            'متأخرة',
            Icons.error_outline_rounded,
            (person) => _dueEntryCount(person, 'مالية', 'late'),
          ),
          metric(
            'مستحقة',
            Icons.payments_outlined,
            (person) => _dueEntryCount(person, 'مالية', 'today'),
          ),
          metric(
            'قريبة الاستحقاق',
            Icons.hourglass_bottom_rounded,
            (person) => _dueEntryCount(person, 'مالية', 'soon'),
          ),
          FollowUpMetric(
            label: 'مبالغ لي',
            icon: Icons.south_west_rounded,
            entries: [
              for (final person in people.where((p) => p.dueToYou > 0))
                entryFor(
                  person,
                  '${person.dueToYou} ${AppSettings.currencySuffix}',
                ),
            ],
          ),
          FollowUpMetric(
            label: 'مبالغ عليّ',
            icon: Icons.north_east_rounded,
            entries: [
              for (final person in people.where((p) => p.dueOnYou > 0))
                entryFor(
                  person,
                  '${person.dueOnYou} ${AppSettings.currencySuffix}',
                ),
            ],
          ),
        ],
      ),
      FollowUpGroup(
        title: 'أدوية',
        icon: Icons.medication_outlined,
        color: const Color(0xFFC4392E),
        metrics: [
          metric(
            'منتهية',
            Icons.event_busy_outlined,
            (person) => linked(person)
                .where(
                  (r) =>
                      r.entryType == 'أدوية' &&
                      _medicineState(r) == 'أدوية منتهية',
                )
                .length,
          ),
          metric('قريبة الانتهاء', Icons.hourglass_top_rounded, (person) {
            return linked(person).where((r) {
              if (r.entryType != 'أدوية') return false;
              final days = _daysFromToday(
                r.details['إلى تاريخ'] ?? r.dueDate,
              );
              return days != null && days >= 0 && days <= 7;
            }).length;
          }),
        ],
      ),
      FollowUpGroup(
        title: 'مستندات (عام)',
        icon: Icons.description_outlined,
        color: const Color(0xFFCE8422),
        metrics: [
          metric(
            'منتهية',
            Icons.assignment_late_outlined,
            (person) => docsCount(person, true),
          ),
          metric(
            'قريبة الانتهاء',
            Icons.event_busy_outlined,
            (person) => docsCount(person, false),
          ),
        ],
      ),
      FollowUpGroup(
        title: 'عهدة مالية',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0A5A50),
        metrics: [
          metric('مستنفدة', Icons.money_off_csred_outlined, (person) {
            return custodyOf(person).where((r) {
              return r.amount > 0 && personalCustodySpent(r.details) >= r.amount;
            }).length;
          }),
          metric('قريبة الاستنفاد', Icons.trending_down_rounded, (person) {
            return custodyOf(person).where((r) {
              if (r.amount <= 0) return false;
              final remaining = r.amount - personalCustodySpent(r.details);
              return remaining > 0 && remaining <= r.amount * 0.2;
            }).length;
          }),
        ],
      ),
      FollowUpGroup(
        title: 'تفويضات',
        icon: Icons.assignment_ind_outlined,
        color: const Color(0xFF0A5A50),
        metrics: [
          metric(
            'تقارب الانتهاء',
            Icons.assignment_late_outlined,
            _expiringDelegationsFor,
          ),
          metric(
            'منتهية',
            Icons.assignment_turned_in_outlined,
            _endedDelegationsFor,
          ),
        ],
      ),
    ];
  }

  void _openFollowUpSheet(List<_PersonItem> people) {
    showFollowUpCenterSheet(
      context: context,
      accent: const Color(0xFF0E7161),
      title: 'مركز المتابعة',
      subtitle: 'الأفراد والجهات',
      groups: _followUpGroups(people),
    );
  }

  void _openPersonDetails(_PersonItem person) {
    _openPersonDetailsAwait(person);
  }

  Future<void> _openPersonDetailsAwait(_PersonItem person) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailsScreen(
          person: person,
          onFullEdit: (current) {
            final isEntity = _isEntityKind(current.typeKey);
            _TypeFilterDef? type;
            for (final option in _createTypeFilters(isEntity)) {
              if (option.key == current.typeKey) type = option;
            }
            return _openContactFormSheet(
              isEntity: isEntity,
              type: type,
              editing: current,
            );
          },
          onPersonUpdated: (previous, updated) async {
            final index = _people.indexOf(previous);
            if (index == -1) return;
            setState(() {
              _people[index] = updated;
            });
            await _persistWithFeedback();
          },
          onPersonDeleted: (target) async {
            setState(() {
              _people.remove(target);
            });
            await _persistWithFeedback();
          },
        ),
      ),
    );
  }

  // الفلتر الرئيسي: نفس قالب الشاشات الأربع، والأقسام وترتيبها مطابقة
  // لملف "فلاتر فوندلي" لصفحة الأفراد والجهات.
  void _openTypeFilterSheet() {
    showAppFilterSheet(
      context: context,
      title: 'أفراد وجهات',
      accent: const Color(0xFF0E7161),
      values: _filter
        ..mainCategory = _selectedScopeKey == 'scope_entities'
            ? 'جهات'
            : _selectedScopeKey == 'scope_people'
            ? 'أفراد'
            : 'الكل',
      mainCategories: const ['الكل', 'أفراد', 'جهات'],
      subCategoriesFor: _subCategoriesFor,
      // بلا مدخل "الكل": القالب يضيف رقاقة "الكل" بنفسه، فكانت تظهر مرتين
      // والثانية تُفلتر على تصنيف اسمه "الكل" فلا يطابق أحدًا.
      personCategories: _allTypeFilters
          .where((filter) => filter.key != 'all')
          .map((filter) => filter.label)
          .toList(growable: false),
      // حسب الورقة: الفئات الرئيسية، الفرعية، الحالة ▼، المستند (الاسم +
      // الفلتر ▼)، الدين ▼، التفويض، المواقع والأماكن.
      sections: _peopleFilterSections,
      selectStatuses: _peopleStatuses,
      delegatesLabel: 'التفويض',
      placeLabel: 'المواقع والأماكن',
      placeHint: 'اكتب اسم الموقع أو المكان',
      onApply: (values) => setState(() => _applyFilterValues(values)),
    );
  }

  static const List<AppFilterSection> _peopleFilterSections = [
    AppFilterSection.mainCategory,
    AppFilterSection.subCategory,
    AppFilterSection.statusSelect,
    AppFilterSection.documentSelect,
    // المبلغ في مستطيل + الفلتر ▼ (قريبة الاستحقاق، مستحقة، متأخرة).
    AppFilterSection.dueAmount,
    AppFilterSection.debtSelect,
    AppFilterSection.delegates,
    AppFilterSection.place,
  ];

  /// الحالة ▼ للأفراد والجهات.
  static const List<String> _peopleStatuses = [
    'الأحدث أولاً',
    'نشطة',
    'مكتملة',
  ];

  /// الفئات الفرعية بترتيبها في نموذج الإضافة: فئات الأفراد أو الجهات.
  static List<String> _subCategoriesFor(String main) {
    final prefix = main == 'أفراد'
        ? 'person_'
        : main == 'جهات'
        ? 'entity_'
        : null;
    if (prefix == null) return const <String>[];
    return [
      for (final filter in _allTypeFilters)
        if (filter.key.startsWith(prefix) &&
            !_autoOnlyTypeKeys.contains(filter.key))
          filter.label,
    ];
  }

  /// إعداد الفلتر نفسه لفلتر الصفحة الرئيسية.
  static AppFilterModuleConfig moduleConfig() => AppFilterModuleConfig(
    mainCategories: const ['الكل', 'أفراد', 'جهات'],
    subCategoriesFor: _subCategoriesFor,
    sectionsFor: (_) => _peopleFilterSections,
    selectStatuses: _peopleStatuses,
    delegatesLabel: 'التفويض',
    placeLabel: 'المواقع والأماكن',
    placeHint: 'اكتب اسم الموقع أو المكان',
  );

  void _applyFilterValues(AppFilterValues values) {
    _selectedScopeKey = values.mainCategory == 'أفراد'
        ? 'scope_people'
        : values.mainCategory == 'جهات'
        ? 'scope_entities'
        : 'scope_all';
    final matching = _allTypeFilters
        .where((filter) => filter.label == values.subCategory)
        .toList(growable: false);
    _selectedTypeKey = matching.isNotEmpty
        ? matching.first.key
        : _selectedScopeKey == 'scope_people'
        ? 'all_people'
        : _selectedScopeKey == 'scope_entities'
        ? 'all_entities'
        : 'all';
    _filter.assignFrom(values);
  }

  void _openQuickCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.52,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: AppTr.uiDir,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4EAE8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اختيار نوع الإضافة',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF022E2A),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'اختر النوع لإظهار الإدخالات والفئات المناسبة',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF5C6B68),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                  child: Row(
                    children: [
                      if (!_scopeHidden(false))
                      Expanded(
                        child: _CreateTypeChoiceCard(
                          title: 'إضافة فرد',
                          subtitle: 'أفراد وعائلة وموظفون',
                          icon: Icons.person_add_alt_1_rounded,
                          color: const Color(0xFF0A5A50),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Future<void>.delayed(
                              Duration.zero,
                              () => _openContactFormSheet(isEntity: false),
                            );
                          },
                        ),
                      ),
                      if (!_scopeHidden(false) && !_scopeHidden(true))
                        const SizedBox(width: 10),
                      if (!_scopeHidden(true))
                      Expanded(
                        child: _CreateTypeChoiceCard(
                          title: 'إضافة جهة',
                          subtitle: 'شركات ومؤسسات وجهات',
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF0E7161),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Future<void>.delayed(
                              Duration.zero,
                              () => _openContactFormSheet(isEntity: true),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// تنبيه فوق النموذج المفتوح (رسالة أسفل الشاشة تختفي خلفه).
  Future<void> _formNotice(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          title: const Text(
            'تنبيه',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF022E2A),
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.7,
              fontWeight: FontWeight.w600,
              color: Color(0xFF46534F),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      ),
    );
  }

  /// «موقعك ومكانك»: الموقع الحالي من الجوال، أو فتح الخريطة لاختياره.
  Future<void> _pickPlaceInto(
    BuildContext context,
    TextEditingController controller,
    VoidCallback onChanged,
  ) async {
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'موقعك ومكانك',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF0E7161),
                  ),
                  title: const Text(
                    'استخدام موقعي الحالي',
                    textAlign: TextAlign.right,
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'gps'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.map_outlined,
                    color: Color(0xFF0E7161),
                  ),
                  title: const Text(
                    'اختيار من الخريطة',
                    textAlign: TextAlign.right,
                  ),
                  subtitle: const Text(
                    'تُفتح الخريطة: حدّد المكان ثم انسخ رابطه والصقه في الحقل',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'map'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == 'map') {
      final query = controller.text.trim();
      final uri = Uri.parse(
        query.isEmpty
            ? 'https://www.google.com/maps'
            : 'https://www.google.com/maps/search/?api=1&query='
                  '${Uri.encodeComponent(query)}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (choice != 'gps') return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (context.mounted) {
          await _formNotice(
            context,
            'خدمة الموقع مغلقة على الجهاز — فعّلها ثم أعد المحاولة',
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          await _formNotice(context, 'لم يُسمح بالوصول إلى الموقع');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      controller.text =
          'https://www.google.com/maps/search/?api=1&query='
          '${position.latitude.toStringAsFixed(6)},'
          '${position.longitude.toStringAsFixed(6)}';
      onChanged();
    } catch (_) {
      if (context.mounted) await _formNotice(context, 'تعذر جلب الموقع');
    }
  }

  /// [editing]: نفس نموذج الإضافة لتعديل فرد/جهة موجود — يُملأ ببياناته،
  /// ويعيد السجل المعدَّل بدل إضافة سجل جديد.
  Future<_PersonItem?> _openContactFormSheet({
    required bool isEntity,
    _TypeFilterDef? type,
    bool anyType = false,
    _PersonItem? editing,
  }) {
    // [anyType]: قائمة النوع فيها الأفراد والجهات معًا، ونوع الجهة يحوّل
    // النموذج إلى نموذج الجهة، والباقي نموذج الفرد.
    List<_TypeFilterDef> typeOptions() => anyType
        ? [..._createTypeFilters(false), ..._createTypeFilters(true)]
        : _createTypeFilters(isEntity);
    // النوع أول خانة في النموذج نفسه (بدل صفحة اختيار مستقلة).
    var selectedType = type;
    final controllers = <String, TextEditingController>{
      'name': TextEditingController(),
      'phone': TextEditingController(),
      'email': TextEditingController(),
      'birthday': TextEditingController(),
      'nationality': TextEditingController(),
      'address': TextEditingController(),
      'notes': TextEditingController(),
      'extra': TextEditingController(),
      'location': TextEditingController(),
    };

    // لكل وثيقة رسمية: رقم، تاريخ انتهاء، تذكير، ومرفق.
    final docNumbers = <String, TextEditingController>{
      for (final doc in _IdentityDoc.all) doc.title: TextEditingController(),
    };
    final docExpiries = <String, TextEditingController>{
      for (final doc in _IdentityDoc.all) doc.title: TextEditingController(),
    };
    final docReminders = <String, String>{
      for (final doc in _IdentityDoc.all) doc.title: _kReminderNone,
    };
    final docFiles = <String, String>{
      for (final doc in _IdentityDoc.all) doc.title: '',
    };
    // مرفقات حرّة يضيفها المستخدم قبل الحفظ (أي وثائق أخرى).
    final otherFiles = <String>[];
    // وثائق الجهة: اسم حر وتاريخ انتهاء وتذكير ومرفق، وتُكرَّر بلا حد.
    final entityDocs = <_EntityDoc>[_EntityDoc()];

    // التعديل: الحقول بقيم السجل الحالية.
    final old = editing;
    if (old != null) {
      String v(String key) => (old.details[key] ?? '').trim();
      controllers['name']!.text = old.fullName;
      controllers['phone']!.text = v('رقم الهاتف');
      controllers['email']!.text = v('البريد الإلكتروني');
      controllers['birthday']!.text = v(
        isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد',
      );
      controllers['nationality']!.text = v('الجنسية');
      controllers['address']!.text = v('العنوان');
      controllers['location']!.text = v('الموقع على الخريطة');
      controllers['extra']!.text = v('معلومات إضافية');
      controllers['notes']!.text =
          old.extraNote == 'بانتظار استكمال البيانات' ? '' : old.extraNote;
      if (!isEntity) {
        for (final doc in _IdentityDoc.all) {
          docNumbers[doc.title]!.text = v(doc.numberKey);
          docExpiries[doc.title]!.text = v(doc.expiryKey);
          final reminder = v(doc.reminderKey);
          if (reminder.isNotEmpty) docReminders[doc.title] = reminder;
          docFiles[doc.title] = v(doc.fileKey);
        }
      } else {
        final names = [
          for (final key in old.details.keys)
            if (key.startsWith('انتهاء ')) key.substring('انتهاء '.length),
        ];
        if (names.isNotEmpty) {
          for (final doc in entityDocs) {
            doc.dispose();
          }
          entityDocs.clear();
          for (final name in names) {
            final doc = _EntityDoc();
            doc.name.text = name;
            doc.expiry.text = v('انتهاء $name');
            final reminder = v('تذكير $name');
            if (reminder.isNotEmpty) doc.reminder = reminder;
            doc.file = v('مرفق $name');
            entityDocs.add(doc);
          }
        }
      }
      otherFiles.addAll(
        v('مرفقات أخرى').split('|').where((p) => p.trim().isNotEmpty),
      );
    }

    return showModalBottomSheet<_PersonItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // تصنيفات فرعية إضافية يمكن اختيار أكثر من واحدة منها (بجانب
        // التصنيف الرئيسي "type" الذي تم اختياره في الخطوة السابقة) — لدعم
        // حالة الفرد/الجهة الذي له أكثر من تصنيف في نفس الوقت.
        final selectedAdditional = <String>{
          ...?old?.additionalCategoryNames,
        };
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final additionalOptions = _createTypeFilters(isEntity)
                .where((option) => option.key != selectedType?.key)
                .toList(growable: false);
            return SafeArea(
              top: false,
              child: Container(
                height: MediaQuery.of(sheetContext).size.height * 0.88,
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: Directionality(
                  textDirection: AppTr.uiDir,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4EAE8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // من العقارات والأنشطة والمركبات النوع مخلوط بين فرد
                      // وجهة، فالعنوان «إضافة فرد / جهة».
                      Text(
                        old != null
                            ? (isEntity ? 'تعديل بيانات جهة' : 'تعديل بيانات فرد')
                            : selectedType == null
                            ? (anyType
                                  ? 'إضافة فرد / جهة'
                                  : (isEntity ? 'إضافة جهة' : 'إضافة فرد'))
                            : '${anyType ? 'إضافة فرد / جهة' : (isEntity ? 'إضافة جهة' : 'إضافة فرد')} · '
                                  '${selectedType!.label}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF022E2A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            // أول خانة: النوع (التصنيف)، ثم الاسم.
                            DropdownButtonFormField<String>(
                              initialValue: selectedType?.key,
                              isExpanded: true,
                              decoration: InputDecoration(
                                hintText: AppTr.tr(
                                  isEntity ? 'نوع الجهة *' : 'النوع *',
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              items: [
                                for (final option in typeOptions())
                                  // النوع المخفي من «تخصيص الصفحات» لا يُختار.
                                  if (!_typeKeyHidden(option.key) ||
                                      option.key == selectedType?.key)
                                  DropdownMenuItem(
                                    value: option.key,
                                    child: Text(option.label),
                                  ),
                              ],
                              onChanged: (key) => setSheetState(() {
                                selectedType = typeOptions()
                                    .firstWhere((option) => option.key == key);
                                if (anyType) {
                                  isEntity = selectedType!.key.startsWith(
                                    'entity_',
                                  );
                                  selectedAdditional.clear();
                                }
                                selectedAdditional.remove(
                                  selectedType!.label,
                                );
                              }),
                            ),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['name']!,
                              isEntity ? 'اسم الجهة *' : 'الاسم *',
                            ),
                            const SizedBox(height: 9),
                            _inputField(controllers['phone']!, 'رقم الهاتف *'),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['email']!,
                              'البريد الإلكتروني',
                            ),
                            const SizedBox(height: 9),
                            // الجنسية للأفراد فقط — الجهة لا جنسية لها.
                            if (!isEntity) ...[
                              _inputField(
                                controllers['nationality']!,
                                'الجنسية',
                              ),
                              const SizedBox(height: 9),
                            ],
                            // تقويم لا لوحة مفاتيح: التاريخ يُختار، فلا
                            // تُكتب صيغة مخالفة تكسر الترتيب والتذكير.
                            _dateField(
                              sheetContext,
                              controllers['birthday']!,
                              isEntity ? 'تاريخ التأسيس *' : 'تاريخ الميلاد *',
                              onPicked: () => setSheetState(() {}),
                            ),
                            const SizedBox(height: 9),
                            _inputField(controllers['address']!, 'العنوان'),
                            const SizedBox(height: 9),
                            // موقعك ومكانك: يُكتب، أو يُحدَّد بالزر في آخر
                            // المستطيل نفسه (الموقع الحالي أو الخريطة).
                            TextField(
                              controller: controllers['location'],
                              textDirection: AppTr.uiDir,
                              decoration: InputDecoration(
                                hintText: AppTr.tr('موقعك ومكانك'),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                                suffixIcon: IconButton(
                                  tooltip: AppTr.tr('تحديد من الخريطة'),
                                  icon: const Icon(
                                    Icons.add_location_alt_outlined,
                                    color: Color(0xFF0E7161),
                                  ),
                                  onPressed: () => _pickPlaceInto(
                                    sheetContext,
                                    controllers['location']!,
                                    () => setSheetState(() {}),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            if (additionalOptions.isNotEmpty) ...[
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'تصنيفات إضافية (اختياري)',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF46534F),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                textDirection: AppTr.uiDir,
                                children: additionalOptions.map((option) {
                                  final selected = selectedAdditional
                                      .contains(option.label);
                                  return FilterChip(
                                    label: Text(option.label),
                                    selected: selected,
                                    onSelected: (value) {
                                      setSheetState(() {
                                        if (value) {
                                          selectedAdditional.add(option.label);
                                        } else {
                                          selectedAdditional.remove(
                                            option.label,
                                          );
                                        }
                                      });
                                    },
                                  );
                                }).toList(growable: false),
                              ),
                              const SizedBox(height: 9),
                            ],
                            _inputField(controllers['notes']!, 'ملاحظات'),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['extra']!,
                              'معلومات إضافية',
                            ),
                            const SizedBox(height: 14),
                            // الوثائق الرسمية: رقم وتاريخ انتهاء وتذكير
                            // ومرفق لكل واحدة — فلا يمرّ تاريخ انتهاء بلا
                            // من ينبّه إليه.
                            if (isEntity) ...[
                              _entityDocsBlock(
                                sheetContext,
                                docs: entityDocs,
                                onAdd: () => setSheetState(
                                  () => entityDocs.add(_EntityDoc()),
                                ),
                                onRemove: (doc) => setSheetState(() {
                                  doc.dispose();
                                  entityDocs.remove(doc);
                                }),
                                onRefresh: () => setSheetState(() {}),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (!isEntity)
                            for (final doc in _IdentityDoc.all) ...[
                              _identityDocBlock(
                                sheetContext,
                                doc: doc,
                                numberCtrl: docNumbers[doc.title]!,
                                expiryCtrl: docExpiries[doc.title]!,
                                reminder: docReminders[doc.title]!,
                                onReminder: (value) => setSheetState(
                                  () => docReminders[doc.title] = value,
                                ),
                                attachment: docFiles[doc.title]!,
                                onPick: () async {
                                  final path =
                                      await DocumentStore.pickAndStore(context: context);
                                  if (path == null) return;
                                  setSheetState(
                                    () => docFiles[doc.title] = path,
                                  );
                                },
                                onRemove: () =>
                                    setSheetState(() => docFiles[doc.title] = ''),
                                onRefresh: () => setSheetState(() {}),
                              ),
                              const SizedBox(height: 10),
                            ],
                            // أي وثائق أخرى قبل الحفظ — للأفراد وحدهم.
                            // الجهة لها بالفعل «إضافة وثيقة أخرى» داخل
                            // كتلة وثائقها، فكان الصندوقان يفعلان الشيء
                            // نفسه في الشاشة الواحدة.
                            if (!isEntity)
                              _otherFilesBlock(
                                files: otherFiles,
                                onAdd: () async {
                                  final path =
                                      await DocumentStore.pickAndStore(context: context);
                                  if (path == null) return;
                                  setSheetState(() => otherFiles.add(path));
                                },
                                onRemove: (path) => setSheetState(
                                  () => otherFiles.remove(path),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final name = controllers['name']!.text.trim();
                          // حقول إلزامية: بلا اسم ورقم وتاريخ ميلاد يصير
                          // السجل بلا هوية ولا وسيلة تواصل ولا ترتيب.
                          final missing = <String>[
                            if (selectedType == null)
                              isEntity ? 'نوع الجهة' : 'النوع',
                            if (name.isEmpty)
                              isEntity ? 'اسم الجهة' : 'الاسم',
                            // التعديل لا يُلزم بما لم يكن مسجّلًا أصلًا.
                            if (old == null &&
                                controllers['phone']!.text.trim().isEmpty)
                              'رقم الهاتف',
                            if (old == null &&
                                controllers['birthday']!.text.trim().isEmpty)
                              isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد',
                          ];
                          if (missing.isNotEmpty) {
                            await _formNotice(
                              sheetContext,
                              'أكمل: ${missing.join('، ')}',
                            );
                            return;
                          }
                          if (!sheetContext.mounted) return;
                          final confirmed = await confirmAction(
                            sheetContext,
                            title: 'تأكيد الحفظ',
                            message: old != null
                                ? 'هل تريد حفظ تعديلات «$name»؟'
                                : isEntity
                                ? 'هل تريد حفظ الجهة «$name»؟'
                                : 'هل تريد حفظ الفرد «$name»؟',
                            confirmLabel: 'حفظ',
                          );
                          if (!confirmed) return;
                          final type = selectedType!;
                          // المستندات المرفقة تُسجَّل باسمها في قائمة السجل،
                      // فيطابق العدّاد ما هو موجود فعلًا.
                      final namedEntityDocs = entityDocs
                          .where((doc) => doc.name.text.trim().isNotEmpty)
                          .toList(growable: false);
                      final createdDocuments = <String>[
                        if (!isEntity)
                          for (final doc in _IdentityDoc.all)
                            if (docNumbers[doc.title]!.text.trim().isNotEmpty ||
                                docFiles[doc.title]!.isNotEmpty)
                              doc.title,
                        if (isEntity)
                          for (final doc in namedEntityDocs)
                            doc.expiry.text.trim().isEmpty
                                ? doc.name.text.trim()
                                : '${doc.name.text.trim()} · ينتهي ${doc.expiry.text.trim()}',
                        for (final path in otherFiles)
                          DocumentStore.fileName(path),
                      ];

                      // تذكير لكل وثيقة لها تاريخ انتهاء.
                      for (final doc in _IdentityDoc.all) {
                        if (isEntity) break;
                        // التعديل: تذكير جديد فقط لما تغيّر تاريخه أو تذكيره.
                        if (old != null &&
                            (old.details[doc.expiryKey] ?? '').trim() ==
                                docExpiries[doc.title]!.text.trim() &&
                            (old.details[doc.reminderKey] ?? _kReminderNone) ==
                                docReminders[doc.title]) {
                          continue;
                        }
                        await _registerExpiryReminder(
                          title: '${doc.title} — $name',
                          dateText: docExpiries[doc.title]!.text,
                          reminder: docReminders[doc.title]!,
                        );
                      }
                      for (final doc in namedEntityDocs) {
                        final docName = doc.name.text.trim();
                        if (old != null &&
                            (old.details['انتهاء $docName'] ?? '').trim() ==
                                doc.expiry.text.trim() &&
                            (old.details['تذكير $docName'] ?? _kReminderNone) ==
                                doc.reminder) {
                          continue;
                        }
                        await _registerExpiryReminder(
                          title: '${doc.name.text.trim()} — $name',
                          dateText: doc.expiry.text,
                          reminder: doc.reminder,
                        );
                      }
                      if (!mounted) return;

                      if (old != null) {
                        final notes = controllers['notes']!.text.trim();
                        final base = Map<String, String>.of(old.details);
                        // وثائق الجهة تُكتب من جديد (قد يتغيّر اسم الوثيقة).
                        if (isEntity) {
                          base.removeWhere(
                            (key, _) =>
                                key.startsWith('انتهاء ') ||
                                key.startsWith('تذكير ') ||
                                key.startsWith('مرفق '),
                          );
                        }
                        final documents = <String>[
                          ...old.documents,
                          for (final doc in createdDocuments)
                            if (!old.documents.contains(doc)) doc,
                        ];
                        final updated = old.copyWith(
                          fullName: name,
                          roleTitle: type.label,
                          typeKey: type.key,
                          categoryName: type.label,
                          additionalCategoryNames: selectedAdditional.toList(
                            growable: false,
                          ),
                          // مسح الملاحظة في التعديل يمسحها فعلًا.
                          extraNote: notes,
                          documents: documents,
                          documentsCount: documents.length,
                          lastUpdate: _todayStamp(),
                          details: {
                            ...base,
                            'رقم الهاتف': controllers['phone']!.text.trim(),
                            'البريد الإلكتروني': controllers['email']!.text
                                .trim(),
                            isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد':
                                controllers['birthday']!.text.trim(),
                            'الجنسية': controllers['nationality']!.text.trim(),
                            'العنوان': controllers['address']!.text.trim(),
                            'الموقع على الخريطة': controllers['location']!
                                .text
                                .trim(),
                            'معلومات إضافية': controllers['extra']!.text
                                .trim(),
                            if (!isEntity)
                              for (final doc in _IdentityDoc.all) ...{
                                doc.numberKey: docNumbers[doc.title]!.text
                                    .trim(),
                                doc.expiryKey: docExpiries[doc.title]!.text
                                    .trim(),
                                doc.reminderKey: docReminders[doc.title]!,
                                doc.fileKey: docFiles[doc.title]!,
                              },
                            if (isEntity)
                              for (final doc in namedEntityDocs) ...{
                                'انتهاء ${doc.name.text.trim()}':
                                    doc.expiry.text.trim(),
                                'تذكير ${doc.name.text.trim()}': doc.reminder,
                                'مرفق ${doc.name.text.trim()}': doc.file,
                              },
                            'مرفقات أخرى': otherFiles.join('|'),
                          },
                        );
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, updated);
                        }
                        return;
                      }

                      setState(() {
                            _people.insert(
                              0,
                              _PersonItem(
                                fullName: name,
                                nickName: isEntity ? 'جهة جديدة' : 'جديد',
                                roleTitle: type.label,
                                badge: 'جديد',
                                badgeColor: type.color,
                                statusNote: isEntity
                                    ? 'تم إنشاء ملف الجهة'
                                    : 'تم إنشاء ملف الشخص',
                                extraNote:
                                    controllers['notes']!.text.trim().isEmpty
                                    ? 'بانتظار استكمال البيانات'
                                    : controllers['notes']!.text.trim(),
                                typeKey: type.key,
                                categoryName: type.label,
                                additionalCategoryNames: selectedAdditional
                                    .toList(growable: false),
                                dueToYou: 0,
                            dueOnYou: 0,
                            openTasks: 0,
                            documentsCount: createdDocuments.length,
                            lastUpdate: _todayStamp(),
                            createdAt: _todayStamp(),
                            sharedCommitments: const [],
                            documents: createdDocuments,
                            details: {
                              'رقم الهاتف': controllers['phone']!.text.trim(),
                              'البريد الإلكتروني': controllers['email']!.text
                                  .trim(),
                              isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد':
                                  controllers['birthday']!.text.trim(),
                              'الجنسية': controllers['nationality']!.text
                                  .trim(),
                              'العنوان': controllers['address']!.text.trim(),
                              'الموقع على الخريطة': controllers['location']!
                                  .text
                                  .trim(),
                              ...widget.linkDetails,
                              'معلومات إضافية': controllers['extra']!.text
                                  .trim(),
                              if (!isEntity)
                                for (final doc in _IdentityDoc.all) ...{
                                  doc.numberKey: docNumbers[doc.title]!.text
                                      .trim(),
                                  doc.expiryKey: docExpiries[doc.title]!.text
                                      .trim(),
                                  doc.reminderKey: docReminders[doc.title]!,
                                  doc.fileKey: docFiles[doc.title]!,
                                },
                              if (isEntity)
                                for (final doc in namedEntityDocs) ...{
                                  'انتهاء ${doc.name.text.trim()}':
                                      doc.expiry.text.trim(),
                                  'تذكير ${doc.name.text.trim()}': doc.reminder,
                                  'مرفق ${doc.name.text.trim()}': doc.file,
                                },
                              'مرفقات أخرى': otherFiles.join('|'),
                            },
                          ),
                        );
                        _selectedTypeKey = 'all';
                        // بدون توسيع النطاق أيضًا يُحفَظ السجل الجديد لكنه
                        // لا يظهر في القائمة (مثلاً إضافة شركة والنطاق
                        // الحالي "الأفراد")، فيبدو وكأن الحفظ فشل.
                        _selectedScopeKey = isEntity
                            ? 'scope_entities'
                            : 'scope_people';
                      });
                      // يُبلّغ عند فشل الحفظ بدل إغلاق النافذة بصمت.
                      _persistWithFeedback();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            isEntity
                                ? 'تم حفظ الجهة «$name» بنجاح'
                                : 'تم حفظ الفرد «$name» بنجاح',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      old != null
                          ? 'حفظ التعديلات'
                          : (isEntity ? 'حفظ جهة' : 'حفظ فرد'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF04413B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                    ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _registerExpiryReminder({
    required String title,
    required String dateText,
    required String reminder,
    String customDays = '',
  }) async {
    final expiry = AppRemindersStore.parseDisplayDate(dateText);
    if (expiry == null || reminder == _kReminderNone) return;
    final days = reminder == _kReminderCustom
        ? (int.tryParse(customDays.trim()) ?? 0)
        : AppRemindersStore.reminderDaysFromLabel(reminder);
    if (days <= 0) return;
    await AppRemindersStore.upsert(
      AppReminder(
        id: 'person_doc_${DateTime.now().microsecondsSinceEpoch}_$title',
        title: title,
        module: 'الأفراد والجهات',
        expiryDate: expiry,
        remindBeforeDays: days,
      ),
    );
  }

  /// كتلة وثيقة رسمية: الرقم، تاريخ الانتهاء، التذكير، المرفق.
  Widget _identityDocBlock(
    BuildContext context, {
    required _IdentityDoc doc,
    required TextEditingController numberCtrl,
    required TextEditingController expiryCtrl,
    required String reminder,
    required ValueChanged<String> onReminder,
    required String attachment,
    required Future<void> Function() onPick,
    required VoidCallback onRemove,
    required VoidCallback onRefresh,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(doc.icon, size: 17, color: const Color(0xFF0E7161)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  doc.title,
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F1F1C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _inputField(numberCtrl, 'رقم ${doc.title}'),
          const SizedBox(height: 8),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: _dateField(
                  context,
                  expiryCtrl,
                  'تاريخ الانتهاء',
                  onPicked: onRefresh,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: reminder,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: AppTr.tr('تذكير'),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  items: [
                    for (final option in _kReminderOptions)
                      DropdownMenuItem(
                        value: option,
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(option, maxLines: 1)),
                      ),
                  ],
                  onChanged: (value) => onReminder(value ?? reminder),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (attachment.isEmpty)
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('إضافة مرفق'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0E7161),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          else
            _attachmentRow(
              DocumentStore.shortName(attachment),
              onRemove,
            ),
        ],
      ),
    );
  }

  /// كتلة وثائق الجهة — تتكرّر بلا حد، ولكل وثيقة اسمها وانتهاؤها وتذكيرها.
  Widget _entityDocsBlock(
    BuildContext context, {
    required List<_EntityDoc> docs,
    required VoidCallback onAdd,
    required ValueChanged<_EntityDoc> onRemove,
    required VoidCallback onRefresh,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 17,
                color: Color(0xFF0E7161),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'وثائق',
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F1F1C),
                  ),
                ),
              ),
            ],
          ),
          for (var index = 0; index < docs.length; index++) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(child: _inputField(docs[index].name, 'اسم الوثيقة')),
                      if (docs.length > 1) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => onRemove(docs[index]),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF8C9A97),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: _dateField(
                          context,
                          docs[index].expiry,
                          'تاريخ الانتهاء',
                          onPicked: onRefresh,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: docs[index].reminder,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: AppTr.tr('تذكير'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                          items: [
                            for (final option in _kReminderOptions)
                              DropdownMenuItem(
                                value: option,
                                child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(option, maxLines: 1)),
                              ),
                          ],
                          onChanged: (value) {
                            docs[index].reminder = value ?? docs[index].reminder;
                            onRefresh();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (docs[index].file.isEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final path = await DocumentStore.pickAndStore(context: context);
                        if (path == null) return;
                        docs[index].file = path;
                        onRefresh();
                      },
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: const Text('إضافة مرفق'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0E7161),
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  else
                    _attachmentRow(
                      DocumentStore.shortName(docs[index].file),
                      () {
                        docs[index].file = '';
                        onRefresh();
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('إضافة وثيقة أخرى'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0E7161),
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// أي وثائق أخرى يضيفها المستخدم قبل الحفظ.
  Widget _otherFilesBlock({
    required List<String> files,
    required Future<void> Function() onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 17,
                color: Color(0xFF0E7161),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'وثائق أخرى',
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F1F1C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final path in files) ...[
            _attachmentRow(
              DocumentStore.shortName(path),
              () => onRemove(path),
            ),
            const SizedBox(height: 6),
          ],
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('إضافة مرفق'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0E7161),
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentRow(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 16,
            color: Color(0xFF0E7161),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              textAlign: AppTr.alignEnd,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F1F1C),
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 17,
              color: Color(0xFF8C9A97),
            ),
          ),
        ],
      ),
    );
  }

  /// حقل تاريخ يفتح التقويم عند الضغط — بنفس شكل بقية الحقول.
  Widget _dateField(
    BuildContext context,
    TextEditingController controller,
    String hint, {
    VoidCallback? onPicked,
  }) {
    return TextField(
      controller: controller,
      textDirection: AppTr.uiDir,
      readOnly: true,
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate:
              AppRemindersStore.parseDisplayDate(controller.text) ?? now,
          firstDate: DateTime(now.year - 120),
          lastDate: DateTime(now.year + 20),
          builder: (pickerContext, child) => Directionality(
            textDirection: AppTr.uiDir,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        if (picked == null) return;
        controller.text = '${picked.day}/${picked.month}/${picked.year}';
        onPicked?.call();
      },
      decoration: InputDecoration(
        hintText: hint,
        // بعد الاختيار: × يمسح التاريخ.
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.trim().isEmpty
              ? const Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: Color(0xFF0E7161),
                )
              : clearDateSuffix(controller, onCleared: onPicked),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      textDirection: AppTr.uiDir,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _filteredPeople();

    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        screenId: 'people_management',
        onPressed: _openQuickCreateSheet,
        label: 'إضافة',
        backgroundColor: const Color(0xFF0E7161),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: CustomScrollView(
          slivers: [
            ManagementDashboardHeader(
              title: 'الأفراد والجهات',
              subtitle: 'تسجيل ومتابعة الأفراد والجهات',
              icon: Icons.person_search_rounded,
              colors: const [Color(0xFF0A5A50), Color(0xFF0E7161)],
              // لمسة لون الوحدة.
              tint: const Color(0xFF6B6FC7),
              onSmartCalendarTap: _openSmartCalendar,
              onClose: () => Navigator.of(context).pop(),
            ),
            // مستطيل الوحدة الملوّن: الترويسة والبحث ومركز المتابعة
            // والملخص الشامل بلون الوحدة الخفيف.
            moduleTintedGroup(
              tint: const Color(0xFF6B6FC7),
              slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              sliver: SliverToBoxAdapter(
                child: ManagementSearchBar(
                  controller: _searchController,
                  hint: 'ابحث في الأفراد والجهات',
                  accentColor: const Color(0xFF0E7161),
                  searchId: 'people_management',
                  suggestions: _people
                      .map((person) => person.fullName)
                      .toList(growable: false),
                  onFilterTap: _openTypeFilterSheet,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            // مركز المتابعة يتحرّك مع الصفحة ويختفي عند النزول لأسفل،
            // بدل تثبيت الكتلة كاملة بارتفاع مفترض (278) كان يترك فراغًا
            // ميتًا دائمًا ويمنع مركز المتابعة من الاختفاء.
            SliverToBoxAdapter(
              child: ColoredBox(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    ManagementFollowUpCenter(
                    // ثابت في كل الفئات: يعرض دائمًا كل الأفراد والجهات.
                    subtitle: 'متابعة الأفراد والجهات',
                    accentColor: const Color(0xFF0E7161),
                    onMore: () => _openFollowUpSheet(_people),
                    // البنود الثلاثة نفسها بأيقوناتها في مراكز المتابعة
                    // الأربعة: الطلبات، المتابعة والتخطيط، مستحقات مالية.
                    metrics: () {
                      final groups = _followUpGroups(_people);
                      return [
                        ManagementMetricData(
                          label: 'الطلبات',
                          count: groups[0].total,
                          icon: Icons.hourglass_top_rounded,
                          color: const Color(0xFFA6691A),
                        ),
                        ManagementMetricData(
                          label: 'المتابعة والتخطيط',
                          count: groups[1].total,
                          icon: Icons.fact_check_outlined,
                          color: const Color(0xFF0A5A50),
                        ),
                        ManagementMetricData(
                          label: 'مستحقات مالية',
                          count: groups[2].total,
                          icon: Icons.account_balance_wallet_outlined,
                          color: const Color(0xFF178F7B),
                        ),
                      ];
                    }(),
                  ),
    const SizedBox(height: 8),
    // «الملخص الشامل» لهذا القسم وحده.
    const ModuleSummaryCard(tab: 3, subtitle: 'ملخص الأفراد والجهات'),
  ],
),
                ),
              ),
            ),
            // عنوان "الفئات" يمرّ مع الصفحة، وشريط الشرائح وحده يثبت.
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: const Text(
                  'الفئات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2C3B38),
                  ),
                ),
              ),
            ),
            MeasuredPinnedHeader(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // بلا عنوان "الفئات" — كبقية الشاشات.
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ManagementCategoryTab(
                          label: 'الكل',
                          count: _countByScope('scope_all'),
                          icon: Icons.grid_view_rounded,
                          color: const Color(0xFF022E2A),
                          selected: _selectedScopeKey == 'scope_all',
                          onTap: () => setState(() {
                            _selectedScopeKey = 'scope_all';
                            _selectedTypeKey = 'all';
                            _filter.subCategory = null;
                          }),
                        ),
                        const SizedBox(width: 8),
                        // نفس شريحة "مالية" في الالتزامات الشخصية: شريحة
                        // بسهم يفتح قائمة منسدلة أسفلها بستة عناصر ظاهرة
                        // ومؤشّر تمرير — بدل نافذة تملأ الشاشة بثلاثة عشر
                        // عنصرًا دفعةً واحدة.
                        if (!_scopeHidden(false))
                        AppCategoryDropdownChip(
                          label: 'الأفراد',
                          count: _countByScope('scope_people'),
                          icon: Icons.person_outline_rounded,
                          color: const Color(0xFF0A5A50),
                          selected: _selectedScopeKey == 'scope_people',
                          onTap: () => setState(() {
                            _selectedScopeKey = 'scope_people';
                            _selectedTypeKey = 'all_people';
                            _filter.subCategory = null;
                          }),
                          items: _scopeDropdownItems(isEntity: false),
                        ),
                        const SizedBox(width: 8),
                        if (!_scopeHidden(true))
                        AppCategoryDropdownChip(
                          label: 'الجهات',
                          count: _countByScope('scope_entities'),
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF0E7161),
                          selected: _selectedScopeKey == 'scope_entities',
                          onTap: () => setState(() {
                            _selectedScopeKey = 'scope_entities';
                            _selectedTypeKey = 'all_entities';
                            _filter.subCategory = null;
                          }),
                          items: _scopeDropdownItems(isEntity: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // عنوان القائمة وزر الترتيب مثبَّتان مع الفئات، كبقية
                  // الشاشات: كانا ينزلقان تحت الرأس المثبَّت عند التمرير.
                  ManagementSortHeader(
                    value: _selectedSort,
                    // الفلتر الصغير — كما في ملف "فلاتر فوندلي".
                    options: const [
                      'الأحدث أولاً',
                      'نشط',
                      'مستندات قريبة الانتهاء',
                      'مستندات منتهية',
                    ],
                    onSelected: (value) =>
                        setState(() => _selectedSort = value),
                    title: _selectedTypeKey == 'all'
                        ? 'جميع الأفراد والجهات'
                        : _activeSearchFilterLabel(),
                    count: people.length,
                    accentColor: const Color(0xFF0E7161),
                  ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // بطاقة القائمة هنا مطابقة تماماً لبنية بطاقة الالتزام
                  // الشخصي/المشترك (نفس المقاسات والخطوط والتباعد): أيقونة
                  // 46x46 + اسم مع نقطة حالة وتحته النوع + عمود "له/عليه"
                  // بعرض 108 + سهم تصفّح — بدل مكوّن ManagementCompactCard
                  // العام.
                  // بطاقة «أنا» أول القائمة دائمًا، ولا تخضع للفلترة.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PersonCard(
                      person: _selfRecord(),
                      onTap: () => _openPersonDetails(_selfRecord()),
                    ),
                  ),
                  ...people.map(
                    (person) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PersonCard(
                        person: person,
                        onTap: () => _openPersonDetails(person),
                      ),
                    ),
                  ),
                  if (people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(
                        child: Text(
                          'لا توجد نتائج ضمن هذه التصفية',
                          style: TextStyle(color: Color(0xFF5C6B68)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isMainFilter(String key) {
    return key == 'all' ||
        key == 'family' ||
        key == 'domestic' ||
        key == 'company';
  }
}

class PersonDetailsScreen extends StatefulWidget {
  const PersonDetailsScreen({
    super.key,
    required this.person,
    this.onPersonUpdated,
    this.onPersonDeleted,
    this.onFullEdit,
  });

  /// «تعديل بيانات» بنموذج الإضافة نفسه (كل الحقول)، ويعيد السجل المعدَّل.
  final Future<_PersonItem?> Function(_PersonItem person)? onFullEdit;

  final _PersonItem person;
  final void Function(_PersonItem previous, _PersonItem updated)?
  onPersonUpdated;
  final ValueChanged<_PersonItem>? onPersonDeleted;

  @override
  State<PersonDetailsScreen> createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedMainTab = 0;
  int _selectedSubTab = 0;
  late _PersonItem _person;
  late _PersonItem _sourcePerson;

  // التبويبات: «إضافة إجراء» حُذف، و«السجل» و«التفويضات» صارا تبويبين
  // مستقلين. البيانات الأساسية كلها في الملخص.
  final List<String> _detailTabs = const [
    'الملخص',
    'مالية',
    'متابعة وتخطيط',
    'مستندات',
    'التفويضات',
    'أدوية',
    'مواقع وأماكن',
    'السجل',
  ];

  static const List<DetailSectionTab> _detailSections = [
    DetailSectionTab(label: 'الملخص', icon: Icons.bar_chart_rounded),
    DetailSectionTab(
      label: 'مالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(
      label: 'المتابعة والتخطيط',
      icon: Icons.event_note_outlined,
    ),
    DetailSectionTab(label: 'مستندات', icon: Icons.folder_outlined),
    DetailSectionTab(
      label: 'التفويضات',
      icon: Icons.assignment_ind_outlined,
    ),
    DetailSectionTab(label: 'أدوية', icon: Icons.medication_outlined),
    DetailSectionTab(label: 'مواقع وأماكن', icon: Icons.place_outlined),
    DetailSectionTab(label: 'السجل', icon: Icons.history_rounded),
  ];

  /// فلاتر الأقسام: فئة البند (الشخصية/المشتركة/العقارات…) وحالته.
  static const List<String> _sourceFilters = [
    'الكل',
    'الشخصية',
    'المشتركة',
    'العقارات',
    'الأنشطة التجارية',
    'المركبات ووسائل النقل',
  ];

  /// كلمات يُعرف بها مصدر البند من نصّه.
  static const Map<String, List<String>> _sourceHints = {
    'الشخصية': ['شخصي', 'الشخصية', 'التزام شخصي'],
    'المشتركة': ['مشترك', 'المشتركة', 'رحلة', 'جمعية', 'مشاركة'],
    'العقارات': ['عقار', 'إيجار', 'ايجار', 'وحدة', 'مبنى'],
    'الأنشطة التجارية': ['نشاط', 'تجاري', 'مشروع', 'شركة'],
    'المركبات ووسائل النقل': [
      'آلية',
      'اليات',
      'معدة',
      'معدات',
      'مركبة',
      'سيارة',
      'قارب',
      'طراد',
      'يخت',
    ],
  };

  String _sourceFilter = 'الكل';

  /// «الكل» حُذفت من الحالة: الافتراضي هو النشط، وما انتهى أو أُغلق يُطلب
  /// صراحةً.
  String _statusFilter = 'نشطة';

  /// تبويب المالية الفرعي: له / عليه / عهدة مالية.
  int _financeTab = 0;

  /// سهم الفلتر في المتابعة والتخطيط: الكل / مهمة / موعد / عادة / تذكير /
  /// ملاحظات.
  String _planKind = 'الكل';

  bool _matchesSource(String value) {
    if (_sourceFilter == 'الكل') return true;
    if (_sourceFilter == 'أخرى') {
      for (final hints in _sourceHints.values) {
        for (final hint in hints) {
          if (value.contains(hint)) return false;
        }
      }
      return true;
    }
    for (final hint in _sourceHints[_sourceFilter] ?? const <String>[]) {
      if (value.contains(hint)) return true;
    }
    return false;
  }

  /// كلمات تعني أن البند انتهى أو أُغلق.
  static const List<String> _closedWords = [
    'مكتمل',
    'منتهي',
    'ملغ',
    'مؤرشف',
    'تمت التسوية',
  ];

  bool _matchesStatus(String value, List<String> options) {
    final status = _statusFor(options);
    if (status == 'الأحدث أولاً') return true;
    if (status == 'نشطة') return !_closedWords.any(value.contains);
    if (status == 'مكتملة') {
      return value.contains('مكتمل') || value.contains('تمت التسوية');
    }
    if (status == 'ملغية') return value.contains('ملغ');
    if (value.contains(status)) return true;
    // البنود بلا وسم حالة: يُحكم بآخر تاريخ مكتوب فيها.
    final dates = RegExp(r'(\d{1,2}/\d{1,2}/\d{4})')
        .allMatches(value)
        .toList(growable: false);
    if (dates.isEmpty) return false;
    final days = _daysFromToday(dates.last.group(1)!);
    if (days == null) return false;
    return switch (status) {
      'متأخرة' => days < 0,
      'حان وقتها' || 'مستحقة' || 'أدوية اليوم' => days == 0,
      'قريبًا' || 'قريبة الاستحقاق' => days > 0 && days <= 7,
      'تنتهي قريبًا' => days >= 0 && days <= 30,
      'منتهية' || 'أدوية منتهية' => days < 0,
      'أدوية قادمة' => days > 0,
      _ => false,
    };
  }

  /// بند يحتاج متابعة: مستند انتهى أو ينتهي خلال 30 يومًا، أو متابعة حان
  /// وقتها أو تأخرت. المكتمل والملغي والمؤرشف لا يُحسب.
  bool _rowNeedsAttention(String value, {required bool document}) {
    const done = ['مكتمل', 'ملغ', 'مؤرشف', 'تمت التسوية'];
    if (done.any(value.contains)) return false;
    if (!document && value.contains('منتهي')) return false;
    if (value.contains('يحتاج متابعة') ||
        value.contains('متأخر') ||
        value.contains('حان وقت') ||
        (document &&
            (value.contains('منتهي') || value.contains('تنتهي قريب')))) {
      return true;
    }
    final dates = RegExp(r'(\d{1,2}/\d{1,2}/\d{4})')
        .allMatches(value)
        .toList(growable: false);
    if (dates.isEmpty) return false;
    final days = _daysFromToday(dates.last.group(1)!);
    if (days == null) return false;
    return document ? days <= 30 : days <= 0;
  }

  /// يضمن أن الحالة المختارة موجودة ضمن خيارات هذا القسم بعد تبديل التبويب.
  String _statusFor(List<String> options) =>
      options.contains(_statusFilter) ? _statusFilter : options.first;

  /// رأس القسم: العنوان ومعه الفلتران — المصدر على اليسار والحالة بجانبه.
  Widget _sectionFilters(
    List<String> statusOptions, {
    List<String>? sourceOptions,
  }) {
    final sources = sourceOptions ?? _sourceFilters;
    final sourceValue = sources.contains(_sourceFilter)
        ? _sourceFilter
        : sources.first;
    Widget pill(String value, List<String> options, ValueChanged<String> onPick) {
      // خيار واحد (الفئة في العهدة المالية): نص ثابت بلا قائمة ولا سهم.
      if (options.length == 1) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.field,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Text(
            value,
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F1F1C),
            ),
          ),
        );
      }
      return InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        onTap: () async {
          final picked = await showModalBottomSheet<String>(
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
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  children: [
                    for (final option in options)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          option == value
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: const Color(0xFF0E7161),
                        ),
                        title: Text(
                          option,
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F1F1C),
                          ),
                        ),
                        onTap: () => Navigator.pop(sheetContext, option),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (picked != null) setState(() => onPick(picked));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.field,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Text(
                  value,
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F1F1C),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Color(0xFF0F1F1C),
              ),
            ],
          ),
        ),
      );
    }

    // صندوقان متساويان: «الفئة» على اليمين و«الحالة» على اليسار، كلٌّ
    // بعنوانه فوقه — بدل «الكل الكل» متلاصقتين بلا تسمية.
    Widget box(
      String label,
      IconData icon,
      String value,
      List<String> options,
      ValueChanged<String> onPick,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF5C6B68)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5C6B68),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          pill(value, options, onPick),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: box(
                  'الفئة',
                  Icons.layers_outlined,
                  sourceValue,
                  sources,
                  (v) => _sourceFilter = v,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: box(
                  'الحالة',
                  Icons.schedule_rounded,
                  _statusFor(statusOptions),
                  statusOptions,
                  (v) => _statusFilter = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppTheme.hairline),
        ],
      ),
    );
  }

  Future<void> _openAttachment(String path) async {
    final error = await DocumentStore.open(path);
    if (!mounted || error == null) return;
    _notify(error);
  }

  /// قائمة بنود مرتبطة بعد تطبيق الفلترين.
  Widget _filteredList(
    List<String> items,
    List<String> statusOptions,
    String emptyText,
    IconData icon, {
    bool anySource = false,
  }) {
    final files = _attachments(_person.details);
    final rows = items
        .where(
          (e) =>
              (anySource || _matchesSource(e)) &&
              _matchesStatus(e, statusOptions),
        )
        .toList();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8C9A97),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          InkWell(
            onTap: _salaryRowIds[row] != null
                ? () => _openSalaryReceipt(_salaryRowIds[row]!)
                : _linkedRowIds[row] == null
                ? null
                : () => _openLinkedEntry(_linkedRowIds[row]!),
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Icon(icon, size: 17, color: const Color(0xFF0E7161)),
                const SizedBox(width: 8),
                Expanded(
                  child: () {
                    const style = TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    );
                    // سند القبض: حالته شارة بلون الحالة نفسها في التطبيق.
                    final status = _salaryRowStatus[row];
                    if (status == null ||
                        status.isEmpty ||
                        !row.endsWith(' · $status')) {
                      return Text(
                        row,
                        textAlign: AppTr.alignEnd,
                        maxLines: 3,
                        softWrap: true,
                        style: style,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          row.substring(0, row.length - status.length - 3),
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          softWrap: true,
                          style: style,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _salaryStatusPill(status),
                        ),
                      ],
                    );
                  }(),
                ),
                // المرفق يُفتح من الصف نفسه: صورة المستند أو الفاتورة.
                if ((files[row] ?? '').isNotEmpty) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _openAttachment(files[row]!),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E7161).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: Color(0xFF0E7161),
                      ),
                    ),
                  ),
                ],
                if (_linkedRowIds[row] != null ||
                    _salaryRowIds[row] != null)
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: Color(0xFF8C9A97),
                  ),
              ],
            ),
          ),
          ),
      ],
    );
  }

  String _detailValue(
    _PersonItem person,
    List<String> keys, {
    String fallback = '-',
  }) {
    for (final key in keys) {
      final value = person.details[key]?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// مفتاح خريطة المرفقات داخل تفاصيل السجل: نص البند ← مسار الملف.
  static const String _attachmentsKey = 'مرفقات البنود';

  Map<String, String> _withAttachment(
    Map<String, String> details,
    String label,
    String path,
  ) {
    final map = _attachments(details);
    map[label] = path;
    final next = Map<String, String>.from(details);
    next[_attachmentsKey] = jsonEncode(map);
    return next;
  }

  Map<String, String> _attachments(Map<String, String> details) {
    final raw = (details[_attachmentsKey] ?? '').trim();
    if (raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((key, value) => MapEntry('$key', '${value ?? ''}'));
    } catch (_) {
      return <String, String>{};
    }
  }

  /// بنود «مالية» من السجل الزمني، موزَّعة على له/عليه/عهدة مالية.
  List<String> _moneyEntries(_PersonItem person, int bucket) {
    final lines = person.activityLog
        .where((line) => line.startsWith('مالية'))
        .toList()
        .reversed
        .toList(growable: false);
    if (bucket == 2) {
      return lines.where((line) => line.contains('عهدة')).toList();
    }
    final marker = bucket == 0 ? '· له ·' : '· عليه ·';
    return lines
        .where((line) => line.contains(marker) && !line.contains('عهدة'))
        .toList();
  }

  /// بنود قسم بعينه كما سُجِّلت في السجل الزمني، الأحدث أولًا.
  List<String> _logEntries(_PersonItem person, String category) => person
      .activityLog
      .where((line) => line.startsWith(category))
      .toList()
      .reversed
      .toList(growable: false);

  /// بنود المتابعة والتخطيط المسجَّلة في السجل الزمني.
  List<String> _followUpEntries(_PersonItem person) =>
      _logEntries(person, 'متابعة وتخطيط');

  // =========================================================================
  // التفويض — نفس جدول «delegations» ونفس نموذج DelegationRecord المستعمل
  // في صفحة التفويضات بالإعدادات، فالتفويض الذي يُنشأ من هنا يظهر هناك
  // والعكس. لا نظام تخزين موازٍ.
  // =========================================================================

  final DelegationsRepository _delegationsRepo = SupabaseDelegationsRepository();
  List<DelegationRecord> _delegations = const [];
  bool _delegationsLoading = true;
  String _delegationsError = '';

  /// يربط التفويض بسجل الفرد بدل الاعتماد على تطابق الاسم وحده.
  static const String _delegateRefPrefix = 'person:';

  String get _personRef =>
      '$_delegateRefPrefix${_person.fullName.trim()}';

  bool _isForThisPerson(DelegationRecord record) {
    final ref = (record.delegateRef ?? '').trim();
    if (ref == _personRef) return true;
    if (ref.isNotEmpty && ref.startsWith(_delegateRefPrefix)) return false;
    return record.delegateName.trim() == _person.fullName.trim();
  }

  /// بنود الالتزامات الشخصية المرتبطة بهذا الفرد: أدوية ومتابعات ومواقع
  /// أُضيفت من تفاصيله بنفس نماذج الالتزامات الشخصية.
  List<PersonalEntryRecord> _linked = const [];

  Future<void> _loadLinked() async {
    try {
      final rows = await SupabasePersonalEntriesRepository().fetchAll();
      if (!mounted) return;
      setState(() {
        _linked = [
          for (final record in rows)
            if (_recordLinkedTo(record, _person)) record,
        ];
      });
    } catch (_) {
      // تبقى القوائم ببنود السجل وحدها إن تعذّر التحميل.
    }
  }

  /// يفتح نموذج الالتزامات الشخصية نفسه مربوطًا بهذا الفرد، فيُحفظ البند
  /// هناك ويظهر هنا أيضًا.
  Future<void> _openPersonalForm(
    String formLabel, {
    Map<String, String> prefill = const {},
    Map<String, String> extraLink = const {},
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<PersonalEntryRecord?>(
        builder: (_) => PersonalCommitmentsScreen(
          openFormFor: formLabel,
          prefill: prefill,
          linkDetails: {
            kLinkedPersonKey: _person.fullName.trim(),
            ...extraLink,
          },
        ),
      ),
    );
    await _loadLinked();
  }

  Future<void> _addMedicine() {
    final isSelf = _person.typeKey == 'person_self';
    return _openPersonalForm(
      'أدوية',
      prefill: {'لمن هذا الدواء': isSelf ? 'أدوية لي' : 'أدوية لشخص آخر'},
      extraLink: {if (!isSelf) 'اسم المستفيد': _person.fullName.trim()},
    );
  }

  /// + في المتابعة والتخطيط: اختيار النوع ثم نموذج الالتزامات الشخصية.
  Future<void> _addFollowUp() async {
    const kinds = <(String, IconData)>[
      ('مهمة', Icons.task_alt_outlined),
      ('موعد', Icons.event_outlined),
      ('عادة', Icons.repeat_rounded),
      ('تذكير', Icons.notifications_active_outlined),
      ('ملاحظات', Icons.sticky_note_2_outlined),
    ];
    final picked = await showModalBottomSheet<String>(
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
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              const Text(
                'المتابعة والتخطيط',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 6),
              for (final kind in kinds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kind.$2, color: const Color(0xFF0A5A50)),
                  title: Text(
                    kind.$1,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, kind.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _openPersonalForm(picked);
  }

  /// اتجاه المبلغ مع هذا الفرد لما يُضاف من «+» في «له» أو «عليه».
  static const String _moneyDirectionKey = 'اتجاه المبلغ مع الفرد';

  /// + في «مالية»: «له» = الإيراد بتصنيفاته ودين وقسط وغرامة، «عليه» = دين
  /// وقسط وغرامة، و«عهدة مالية» تُسجَّل من الالتزامات الشخصية.
  Future<void> _addFinance(int tab) async {
    if (tab == 2) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            icon: const Icon(
              Icons.inventory_2_outlined,
              size: 30,
              color: Color(0xFFA6691A),
            ),
            title: const Text('تسجيل عهدة مالية'),
            content: const Text(
              'العهدة المالية تُسجَّل من «الالتزامات الشخصية» ← «عهدة مالية»، '
              'وعند إسنادها لهذا الشخص برقمه التعريفي تظهر هنا تلقائيًا.',
              style: TextStyle(fontSize: 12.5, height: 1.6),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final name = _person.fullName.trim();
    final options = <(String, String, Map<String, String>, IconData)>[
      // الموظف: الراتب بقالب «سند قبض» نفسه الموجود في المستندات.
      if (_isEmployeePerson(_person))
        (
          'سند قبض راتب',
          _salaryOption,
          const <String, String>{},
          Icons.payments_outlined,
        ),
      if (tab == 0)
        for (final category in const [
          'الراتب/معاش',
          'تعويض واسترجاع مصروف',
          'كاش باك',
        ])
          (
            'إيراد — $category',
            'إيراد',
            {'التصنيف الرئيسي': category},
            Icons.trending_up,
          ),
      (
        'دين / قرض / سلفة',
        'دين / قرض / سلفة',
        {
          'نوع الدين': tab == 0 ? 'لي — يدين لي' : 'له — أدين له',
          'اسم الجهة': name,
        },
        Icons.handshake_outlined,
      ),
      ('قسط', 'قسط', const <String, String>{}, Icons.calendar_month_outlined),
      ('غرامة', 'غرامة', const <String, String>{}, Icons.gavel_outlined),
    ];
    final picked = await showModalBottomSheet<int>(
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
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Text(
                tab == 0 ? 'إضافة مبلغ له' : 'إضافة مبلغ عليه',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < options.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(options[i].$4, color: const Color(0xFF0A5A50)),
                  title: Text(
                    options[i].$1,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final option = options[picked];
    if (option.$2 == _salaryOption) {
      await _addSalaryReceipt();
      return;
    }
    await _openPersonalForm(
      option.$2,
      prefill: option.$3,
      extraLink: {_moneyDirectionKey: tab == 0 ? 'له' : 'عليه'},
    );
  }

  // ---------------------------------------------------------------------
  // السجل: كل ما يخص الفرد من مصادره الحقيقية — بنود الالتزامات المرتبطة،
  // وسندات القبض، والتفويضات وأحداثها، وما أُضيف من «+» هنا.
  // ---------------------------------------------------------------------
  final TextEditingController _logQuery = TextEditingController();
  DateTime? _logFrom;
  DateTime? _logTo;
  String _logKind = 'الكل';

  /// تحت «مالية»: الكل / الرواتب / غير الرواتب.
  String _logFinance = 'الكل';

  static const _logFinanceKinds = ['الكل', 'الرواتب', 'غير الرواتب'];

  static const _logKinds = [
    'الكل',
    'مالية',
    'متابعة وتخطيط',
    'مستندات',
    'تفويضات',
    'أخرى',
  ];

  static final RegExp _logDay = RegExp(r'\b\d{1,2}/\d{1,2}/\d{4}\b');

  static String _logDate(DateTime? d) =>
      d == null ? AppTr.tr('بلا تاريخ') : '${d.day}/${d.month}/${d.year}';

  List<_PersonLogEvent> _personLogEvents(_PersonItem person) {
    final out = <_PersonLogEvent>[];
    // بنود الالتزامات الشخصية المرتبطة بالفرد.
    for (final r in _linked) {
      final type = r.entryType;
      final kind = _organizationEntryTypes.contains(type)
          ? 'متابعة وتخطيط'
          : type == 'مستند' || type == 'ضمانات'
          ? 'مستندات'
          : entryFinancialTypes.contains(type) || type == 'عهدة مالية'
          ? 'مالية'
          : 'أخرى';
      final direction = (r.details[_moneyDirectionKey] ?? '').trim();
      final debtType = (r.details['نوع الدين'] ?? '').trim();
      final onMe = direction == 'عليه' ||
          (direction.isEmpty &&
              type == 'دين / قرض / سلفة' &&
              debtType.startsWith('له'));
      final closed = _closedStatuses.contains(r.status) ||
          r.status == 'تمت التسوية';
      out.add(
        _PersonLogEvent(
          kind: kind,
          title: '${AppTr.tr(type)} — ${r.title}',
          detail: [
            if (kind == 'مالية' && direction.isNotEmpty) AppTr.tr(direction),
            AppTr.tr(
              r.status == 'ملغاة'
                  ? 'ملغاة'
                  : closed
                  ? 'مكتملة'
                  : 'نشطة',
            ),
          ].join(' · '),
          date: entryParseDay(r.dueDate) ?? r.createdAt,
          amount: kind == 'مستندات' ? 0 : r.amount.toDouble(),
          currency: AppSettings.currencyOf(r.details['العملة']),
          due: onMe && !closed,
          icon: switch (kind) {
            'مالية' => Icons.payments_outlined,
            'متابعة وتخطيط' => Icons.event_note_outlined,
            'مستندات' => Icons.description_outlined,
            _ => Icons.label_outline_rounded,
          },
          onTap: r.id == null ? null : () => _openLinkedEntry(r.id!),
        ),
      );
    }
    // سندات القبض والرواتب.
    for (final r in _salaryReceipts) {
      out.add(
        _PersonLogEvent(
          kind: 'مالية',
          title:
              '${AppTr.tr(r.isSalary ? 'سند قبض راتب' : 'سند قبض')} — '
              '${AppTr.tr(r.title)}',
          detail: [
            if (_isSelfPerson && r.ownerName.trim().isNotEmpty)
              '${AppTr.tr('من')}: ${r.ownerName.trim()}',
          ].join(' · '),
          salary: r.isSalary,
          status: r.status,
          date: entryParseDay(r.receiptDate) ?? r.createdAt,
          amount: r.paid,
          currency: r.currency.trim().isEmpty
              ? AppSettings.currencySuffix
              : r.currency.trim(),
          icon: Icons.receipt_long_outlined,
          onTap: r.id == null ? null : () => _openSalaryReceipt(r.id!),
        ),
      );
    }
    // التفويضات: منحها، ثم كل حدث في سجلها (قبول، تعديل، إيقاف...).
    for (final record in _delegations) {
      out.add(
        _PersonLogEvent(
          kind: 'تفويضات',
          title: '${AppTr.tr('تفويض')} — ${AppTr.tr(record.scope)}',
          detail: [
            _permissionLevelLabel(record.permissions),
            AppTr.tr(
              record.isActive
                  ? 'سارٍ'
                  : record.isEnded
                  ? 'منتهٍ'
                  : 'موقوف',
            ),
          ].join(' · '),
          date: record.startDate,
          icon: Icons.how_to_reg_outlined,
        ),
      );
      for (final (at, text) in DelegationRecord.logOf(record.permissions)) {
        out.add(
          _PersonLogEvent(
            kind: 'تفويضات',
            title: text,
            detail: AppTr.tr(record.scope),
            date: at,
            icon: Icons.history_rounded,
          ),
        );
      }
    }
    // ما أُضيف من «+» في تفاصيل الفرد (نص مركّب: القسم · النوع · ...).
    const known = {'مالية', 'متابعة وتخطيط', 'مستندات'};
    for (final line in person.activityLog) {
      final parts = [
        for (final p in line.split(' · '))
          if (p.trim().isNotEmpty) p.trim(),
      ];
      if (parts.isEmpty) continue;
      final dayText = _logDay.firstMatch(line)?.group(0);
      final category = known.contains(parts.first) ? parts.first : '';
      final rest = [
        for (final p in category.isEmpty ? parts : parts.skip(1))
          if (p != dayText) p,
      ];
      final title = rest.isEmpty ? (category.isEmpty ? line : category) : rest.first;
      final kind = category.isNotEmpty
          ? category
          : line.contains('تفويض')
          ? 'تفويضات'
          : line.contains('سند') || line.contains('راتب')
          ? 'مالية'
          : 'أخرى';
      out.add(
        _PersonLogEvent(
          kind: kind,
          title: title,
          detail: rest.skip(1).join(' · '),
          date: dayText == null ? null : entryParseDay(dayText),
          due: line.contains('· عليه ·'),
          icon: switch (kind) {
            'مالية' => Icons.payments_outlined,
            'متابعة وتخطيط' => Icons.event_note_outlined,
            'مستندات' => Icons.description_outlined,
            'تفويضات' => Icons.how_to_reg_outlined,
            _ => Icons.history_rounded,
          },
        ),
      );
    }
    out.add(
      _PersonLogEvent(
        kind: 'أخرى',
        title: AppTr.tr('تم إنشاء السجل'),
        date: entryParseDay(person.createdAt),
        icon: Icons.person_add_alt_outlined,
      ),
    );
    // الأحدث أولًا، وما بلا تاريخ في الآخر.
    out.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return out;
  }

  Future<void> _pickLogDate(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _logFrom : _logTo) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() => from ? _logFrom = picked : _logTo = picked);
  }

  Widget _buildPersonLog(_PersonItem person, Color color) {
    final all = _personLogEvents(person);
    final kinds = [
      for (final k in _logKinds)
        if (k == 'الكل' || all.any((e) => e.kind == k)) k,
    ];
    if (!kinds.contains(_logKind)) _logKind = 'الكل';
    final q = _logQuery.text.trim();
    final from = _logFrom == null ? null : DateUtils.dateOnly(_logFrom!);
    final to = _logTo == null ? null : DateUtils.dateOnly(_logTo!);
    final shown = all.where((e) {
      if (_logKind != 'الكل' && e.kind != _logKind) return false;
      if (_logKind == 'مالية' && _logFinance != 'الكل') {
        if ((_logFinance == 'الرواتب') != e.salary) return false;
      }
      if (q.isNotEmpty &&
          !matchesSearchQuery(query: q, fields: [e.title, e.detail])) {
        return false;
      }
      if (from != null || to != null) {
        final day = e.date == null ? null : DateUtils.dateOnly(e.date!);
        if (day == null) return false;
        if (from != null && day.isBefore(from)) return false;
        if (to != null && day.isAfter(to)) return false;
      }
      return true;
    }).toList(growable: false);

    Widget dateButton(bool isFrom) {
      final value = isFrom ? _logFrom : _logTo;
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pickLogDate(isFrom),
          icon: const Icon(Icons.event_rounded, size: 16),
          label: Text(
            value == null
                ? AppTr.tr(isFrom ? 'من تاريخ' : 'إلى تاريخ')
                : _logDate(value),
            style: const TextStyle(fontSize: 11.5),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            backgroundColor: Colors.white,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    Widget row(_PersonLogEvent e) {
      final tint = e.due ? AppTheme.danger : color;
      final body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          textDirection: AppTr.uiDir,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(e.icon, size: 19, color: tint),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    e.title,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  if (e.detail.isNotEmpty)
                    Text(
                      e.detail,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                  if (e.status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _salaryStatusPill(e.status),
                      ),
                    ),
                  Text(
                    _logDate(e.date),
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (e.amount > 0.009) ...[
              const SizedBox(width: 8),
              Text(
                '${_salaryAmount(e.amount)} ${e.currency}'.trim(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: tint,
                ),
              ),
            ],
            if (e.onTap != null)
              const Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: Color(0xFF8C9A97),
              ),
          ],
        ),
      );
      return e.onTap == null
          ? body
          : InkWell(
              onTap: e.onTap,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              child: body,
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _logQuery,
                textAlign: AppTr.alignEnd,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: AppTr.tr('ابحث في السجل'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  dateButton(true),
                  const SizedBox(width: 8),
                  dateButton(false),
                  if (_logFrom != null || _logTo != null)
                    IconButton(
                      tooltip: AppTr.tr('مسح التاريخ'),
                      onPressed: () => setState(() {
                        _logFrom = null;
                        _logTo = null;
                      }),
                      icon: Icon(Icons.close_rounded, color: color),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in kinds)
                    ChoiceChip(
                      label: Text(
                        kind == 'الكل' ? kind : '$kind (${all.where((e) => e.kind == kind).length})',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _logKind == kind,
                      selectedColor: color.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() {
                        _logKind = kind;
                        _logFinance = 'الكل';
                      }),
                    ),
                ],
              ),
              // «مالية»: الرواتب وحدها أو غيرها.
              if (_logKind == 'مالية' &&
                  all.any((e) => e.kind == 'مالية' && e.salary)) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sub in _logFinanceKinds)
                      ChoiceChip(
                        label: Text(
                          sub == 'الكل'
                              ? sub
                              : '$sub (${all.where((e) => e.kind == 'مالية' && e.salary == (sub == 'الرواتب')).length})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        selected: _logFinance == sub,
                        selectedColor: color.withValues(alpha: 0.14),
                        onSelected: (_) => setState(() => _logFinance = sub),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          child: shown.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'لا يوجد ما يطابق — غيّر البحث أو التاريخ أو النوع',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: color.withValues(alpha: 0.12),
                        ),
                      row(shown[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static const String _salaryOption = '__salary_receipt__';

  /// سندات قبض هذا الموظف (برقمه التعريفي، وإلا باسمه) — تظهر في «له».
  List<SalaryReceipt> _salaryReceipts = const [];

  /// نص الصف ← معرّف السند (لفتحه بالضغط).
  final Map<String, String> _salaryRowIds = {};

  /// نص الصف ← حالة السند (تُعرض شارة بلونها بدل كلمة بلا لون).
  final Map<String, String> _salaryRowStatus = {};

  String get _personFnd => (_person.details['الرقم التعريفي'] ?? '').trim();

  bool get _isSelfPerson => _person.typeKey == 'person_self';

  /// «أنا»: الرواتب والسندات التي وصلتني. غيري: ما أصدرته له (موظفًا كان
  /// أو غيره — «المسلّم والمستلم»).
  Future<void> _loadSalaryReceipts() async {
    if (FundlyAuth.isGuest) return;
    try {
      if (_isSelfPerson) {
        final toMe = await SalaryReceiptsRepository().fetchSentToMe(
          AppIdentity.id,
        );
        if (!mounted) return;
        setState(() => _salaryReceipts = toMe);
        return;
      }
      final mine = await SalaryReceiptsRepository().fetchMine();
      if (!mounted) return;
      final fnd = _personFnd;
      final name = _person.fullName.trim();
      setState(() {
        _salaryReceipts = [
          for (final r in mine)
            if (fnd.isNotEmpty
                ? r.employeeFnd == fnd
                : r.employeeName.trim() == name)
              r,
        ];
      });
    } catch (_) {
      // تبقى القائمة بلا سندات إن تعذّر التحميل.
    }
  }

  List<String> _salaryRows() {
    final rows = <String>[];
    for (final r in _salaryReceipts) {
      final row = [
        '${r.isSalary ? 'سند قبض راتب' : 'سند قبض'} — ${r.title}',
        if (_isSelfPerson && r.ownerName.trim().isNotEmpty)
          '${AppTr.tr('من')}: ${r.ownerName.trim()}',
        '${_salaryAmount(r.paid)} '
            '${r.currency.trim().isEmpty ? AppSettings.currencySuffix : r.currency}',
        if (r.receiptDate.trim().isNotEmpty) r.receiptDate.trim(),
        r.status,
      ].join(' · ');
      rows.add(row);
      if (r.id != null) _salaryRowIds[row] = r.id!;
      _salaryRowStatus[row] = r.status;
    }
    return rows;
  }

  static String _salaryAmount(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  /// + ← «سند قبض راتب»: نفس نموذج سند القبض، والموظف هذا الفرد.
  Future<void> _addSalaryReceipt() async {
    var mine = const <SalaryReceipt>[];
    try {
      mine = await SalaryReceiptsRepository().fetchMine();
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SalaryReceiptFormScreen(
          presetFnd: _personFnd,
          presetName: _person.fullName.trim(),
          others: mine,
        ),
      ),
    );
    if (!mounted) return;
    await _loadSalaryReceipts();
    await _loadLinked();
  }

  /// يفتح السند في شاشة «الرواتب وسندات القبض» ثم يعيد التحميل.
  Future<void> _openSalaryReceipt(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // «أنا»: السند في «وصلني» من الشاشة العامة.
        builder: (_) => _isSelfPerson
            ? SalaryReceiptsScreen(openId: id)
            : SalaryReceiptsScreen(
                employeeFnd: _personFnd,
                employeeName: _person.fullName.trim(),
                openId: id,
              ),
      ),
    );
    if (!mounted) return;
    await _loadSalaryReceipts();
    await _loadLinked();
  }

  /// + في التفويضات: نموذج «المزيد ← التفويضات» نفسه.
  Future<void> _addDelegation() async {
    final opener = openDelegationFormForPerson;
    if (opener == null) {
      await _openDelegationSheet();
      return;
    }
    await opener(context, _person.fullName.trim());
    if (mounted) await _loadDelegations();
  }

  /// بنود مرتبطة كسطور للقوائم، بحالتها مكتوبة فيها.
  /// نص الصف ← معرّف البند في الالتزامات الشخصية (لفتحه بالضغط).
  final Map<String, String> _linkedRowIds = {};

  /// يفتح البند في الالتزامات الشخصية (تفاصيله وتعديله وحذفه) ثم يعيد
  /// تحميل ما يخص هذا الفرد.
  Future<void> _openLinkedEntry(String id) async {
    await Navigator.of(context).push(
      directOpenRoute<void>(PersonalCommitmentsScreen(openEntryId: id)),
    );
    await _loadLinked();
  }

  List<String> _linkedRows(String kind) {
    final rows = <String>[];
    for (final r in _linked.reversed) {
      final before = rows.length;
      _addLinkedRow(rows, r, kind);
      if (rows.length > before && r.id != null) {
        _linkedRowIds[rows.last] = r.id!;
      }
    }
    return rows;
  }

  void _addLinkedRow(List<String> rows, PersonalEntryRecord r, String kind) {
    {
      switch (kind) {
        case 'مستندات':
          if (r.entryType != 'مستند' && r.entryType != 'ضمانات') return;
          rows.add(
            [
              r.title,
              if (r.dueDate.trim().isNotEmpty) 'ينتهي ${r.dueDate.trim()}',
              (r.details['التذكير قبل الانتهاء'] ?? '').trim(),
            ].where((part) => part.isNotEmpty).join(' · '),
          );
        case 'أدوية':
          if (r.entryType != 'أدوية') return;
          final from = (r.details['من تاريخ'] ?? '').trim();
          final to = (r.details['إلى تاريخ'] ?? '').trim();
          rows.add(
            [
              r.title,
              if (from.isNotEmpty || to.isNotEmpty)
                'من ${from.isEmpty ? '-' : from} إلى ${to.isEmpty ? '-' : to}',
              _medicineState(r),
            ].join(' · '),
          );
        case 'متابعة وتخطيط':
          if (!_organizationEntryTypes.contains(r.entryType)) return;
          rows.add(
            [
              '${r.entryType} — ${r.title}',
              if (r.dueDate.trim().isNotEmpty) r.dueDate.trim(),
              _planState(r),
            ].join(' · '),
          );
        case 'له':
        case 'عليه':
          // ما أُضيف من «+» هنا يحمل اتجاهه، والإيراد له، والدين حسب نوعه.
          final direction = (r.details[_moneyDirectionKey] ?? '').trim();
          final debtType = (r.details['نوع الدين'] ?? '').trim();
          final forMe = direction == 'له' ||
              (direction.isEmpty &&
                  (r.entryType == 'إيراد' ||
                      (r.entryType == 'دين / قرض / سلفة' &&
                          debtType.startsWith('لي'))));
          final onMe = direction == 'عليه' ||
              (direction.isEmpty &&
                  r.entryType == 'دين / قرض / سلفة' &&
                  debtType.startsWith('له'));
          if (kind == 'له' ? !forMe : !onMe) return;
          rows.add(
            [
              '${r.entryType} — ${r.title}',
              if (r.amount != 0) '${r.amount} ${AppSettings.currencySuffix}',
              if (r.dueDate.trim().isNotEmpty) r.dueDate.trim(),
              _closedStatuses.contains(r.status) ? 'مكتملة' : 'نشطة',
            ].join(' · '),
          );
        case 'عهدة مالية':
          if (r.entryType != 'عهدة مالية') return;
          // قيمة العهدة والمصروف منها والمتبقي، كما في الالتزامات الشخصية.
          final spent = personalCustodySpent(r.details);
          final currency = AppSettings.currencySuffix;
          // ملغاة ← «ملغية»، ومسوّاة أو مؤرشفة بعد تسوية ← «مكتملة».
          final custodyState = (r.details['حالة العهدة'] ?? '').trim();
          final stateLabel = r.status == 'ملغاة' || custodyState == 'ملغاة'
              ? 'ملغية'
              : _closedStatuses.contains(r.status) ||
                    r.status == 'تمت التسوية' ||
                    r.status == 'مؤرشف'
              ? 'مكتملة'
              : 'نشطة';
          rows.add(
            [
              'عهدة مالية — ${r.title}',
              '${AppTr.tr('قيمة العهدة')} ${r.amount} $currency',
              '${AppTr.tr('المصروف')} $spent $currency',
              '${AppTr.tr('المتبقي')} ${r.amount - spent} $currency',
              stateLabel,
            ].join(' · '),
          );
        case 'مواقع وأماكن':
          if (r.entryType != 'مواقع وأماكن') return;
          rows.add(
            [
              r.title,
              (r.details['العنوان'] ?? '').trim(),
              (r.details['التصنيف'] ?? '').trim(),
            ].where((part) => part.isNotEmpty).join(' · '),
          );
      }
    }
  }

  Future<void> _loadDelegations() async {
    if (!mounted) return;
    setState(() {
      _delegationsLoading = _delegations.isEmpty;
      _delegationsError = '';
    });
    try {
      final rows = await _delegationsRepo.fetchDelegations();
      if (!mounted) return;
      setState(() {
        _delegations = rows.where(_isForThisPerson).toList(growable: false);
        _delegationsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _delegationsLoading = false;
        _delegationsError = 'تعذّر تحميل التفويضات — تحقّق من الاتصال';
      });
    }
  }

  /// اسم مستوى الصلاحية من قائمة الصلاحيات المخزَّنة.
  static String _permissionLevelLabel(List<String> permissions) {
    final set = DelegationRecord.plainPermissions(permissions)
        .where((p) => p != DelegationRecord.kNeedsOwnerApproval)
        .toSet();
    if (set.isEmpty) return 'بلا صلاحيات';
    if (!set.containsAll(DelegationRecord.allPermissions)) {
      return DelegationRecord.levelOf(set);
    }
    for (final entry in DelegationRecord.permissionLevels.entries) {
      if (entry.value.toSet().difference(set).isEmpty &&
          set.difference(entry.value.toSet()).isEmpty) {
        return entry.key;
      }
    }
    return '${set.length} صلاحية';
  }

  static String _formatDate(DateTime? value) => value == null
      ? ''
      : '${value.day}/${value.month}/${value.year}';

  /// نموذج التفويض: النطاق والأقسام الفرعية ومستوى الصلاحية والمدة.
  Future<void> _openDelegationSheet({DelegationRecord? existing}) async {
    const accent = Color(0xFF0A5A50);
    var scope = DelegationRecord.mainScopeOf(existing?.scope);
    final subs = <String>{...DelegationRecord.subScopesOf(existing?.scope)};
    var level = existing == null
        ? 'اطّلاع فقط'
        : _permissionLevelLabel(existing.permissions);
    if (!DelegationRecord.permissionLevels.containsKey(level)) {
      level = 'اطّلاع فقط';
    }
    var start = existing?.startDate ?? DateTime.now();
    DateTime? end = existing?.endDate;
    final noteCtrl = TextEditingController(text: existing?.notes ?? '');

    Future<DateTime?> pick(DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 20),
      builder: (pickerContext, child) => Directionality(
        textDirection: AppTr.uiDir,
        child: child ?? const SizedBox.shrink(),
      ),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.rCard),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEDB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      existing == null ? 'تفويض جديد' : 'تعديل التفويض',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'المفوَّض له: ${_person.fullName}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: scope,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('النطاق'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final item in DelegationRecord.scopes)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item, maxLines: 2),
                          ),
                      ],
                      onChanged: (value) => setSheetState(() {
                        scope = value ?? scope;
                        subs.clear();
                      }),
                    ),
                    if ((DelegationRecord.subScopes[scope] ?? const [])
                        .isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'أقسام داخل النطاق (اتركها فارغة ليشمل النطاق كله)',
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5C6B68),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        textDirection: AppTr.uiDir,
                        children: [
                          for (final sub
                              in DelegationRecord.subScopes[scope] ??
                                  const <String>[])
                            InkWell(
                              borderRadius: BorderRadius.circular(
                                AppTheme.rPill,
                              ),
                              onTap: () => setSheetState(() {
                                if (!subs.add(sub)) subs.remove(sub);
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: subs.contains(sub)
                                      ? accent.withValues(alpha: 0.12)
                                      : AppTheme.field,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.rPill,
                                  ),
                                ),
                                child: Text(
                                  sub,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                    color: subs.contains(sub)
                                        ? accent
                                        : AppTheme.body,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'مستوى الصلاحية',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F1F1C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final entry
                        in DelegationRecord.permissionLevels.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                        onTap: () => setSheetState(() => level = entry.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            textDirection: AppTr.uiDir,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                level == entry.key
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      entry.key,
                                      textAlign: AppTr.alignEnd,
                                      maxLines: 2,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F1F1C),
                                      ),
                                    ),
                                    Text(
                                      entry.value.join('، '),
                                      textAlign: AppTr.alignEnd,
                                      maxLines: 3,
                                      softWrap: true,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF8C9A97),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: _DelegationDateField(
                            label: 'من تاريخ',
                            value: _formatDate(start),
                            onTap: () async {
                              final picked = await pick(start);
                              if (picked != null) {
                                setSheetState(() => start = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DelegationDateField(
                            label: 'إلى تاريخ',
                            value: end == null ? 'مفتوح' : _formatDate(end),
                            onTap: () async {
                              final picked = await pick(end);
                              if (picked == null) return;
                              // النهاية لا تسبق البداية.
                              if (DateUtils.dateOnly(picked).isBefore(
                                DateUtils.dateOnly(start),
                              )) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '«إلى تاريخ» لا يسبق «من تاريخ»',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setSheetState(() => end = picked);
                            },
                            onClear: end == null
                                ? null
                                : () => setSheetState(() => end = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('ملاحظات ومستند مرفق'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        existing == null ? 'حفظ التفويض' : 'حفظ التعديل',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rField),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (saved != true || !mounted) return;

    final record = DelegationRecord(
      id: existing?.id,
      delegateName: _person.fullName,
      delegateRef: _personRef,
      scope: DelegationRecord.composeScope(scope, subs),
      permissions: DelegationRecord.withLog(
        [
          ...DelegationRecord.applyHierarchy(
            (DelegationRecord.permissionLevels[level] ?? const <String>[])
                .toSet(),
          ),
          // الموافقة والسقف والعناصر المحددة والسجل لا تضيع هنا.
          ...DelegationRecord.carriedMeta(existing?.permissions, subs),
        ],
        existing == null
            ? 'إنشاء التفويض من صفحة الشخص'
            : 'تعديل التفويض من صفحة الشخص',
      ),
      startDate: start,
      endDate: end,
      isPaused: existing?.isPaused ?? false,
      notes: note.isEmpty ? null : note,
    );
    await _saveDelegation(
      record,
      existing == null
          ? 'تم منح تفويض لـ ${_person.fullName}'
          : 'تم تعديل التفويض',
    );
  }

  Future<void> _saveDelegation(DelegationRecord record, String notice) async {
    try {
      await _delegationsRepo.upsertDelegation(record);
      if (!mounted) return;
      await _loadDelegations();
      if (!mounted) return;
      _applyPersonUpdate(
        _person.copyWith(
          activityLog: [
            ..._person.activityLog,
            'تفويض — ${DelegationRecord.mainScopeOf(record.scope)} · ${_permissionLevelLabel(record.permissions)}',
          ],
          lastUpdate: _todayStamp(),
        ),
        notice: notice,
      );
    } catch (error) {
      if (!mounted) return;
      if (error is PlanLockedException) {
        PlanGate.canEdit(context, PlanModules.delegations);
        return;
      }
      _notify('تعذّر حفظ التفويض — تحقّق من الاتصال');
    }
  }

  /// خيارات التفويض الواحد: تعديل، إيقاف/تشغيل، حذف.
  Future<void> _openDelegationActions(DelegationRecord item) async {
    final action = await showModalBottomSheet<String>(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF0A5A50),
                ),
                title: const Text('تعديل التفويض', textAlign: TextAlign.right),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              ListTile(
                leading: Icon(
                  item.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: const Color(0xFFA6691A),
                ),
                title: Text(
                  item.isPaused ? 'تشغيل التفويض' : 'إيقاف التفويض',
                  textAlign: TextAlign.right,
                ),
                onTap: () => Navigator.pop(sheetContext, 'toggle'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFC4392E),
                ),
                title: const Text('حذف التفويض', textAlign: TextAlign.right),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _openDelegationSheet(existing: item);
      case 'toggle':
        await _saveDelegation(
          item.copyWith(
            isPaused: !item.isPaused,
            permissions: DelegationRecord.withLog(
              item.permissions,
              item.isPaused ? 'إعادة تفعيل التفويض' : 'إيقاف التفويض مؤقتًا',
            ),
          ),
          item.isPaused ? 'تم تشغيل التفويض' : 'تم إيقاف التفويض',
        );
      case 'delete':
        final id = item.id;
        if (id == null) return;
        try {
          await _delegationsRepo.deleteDelegation(id);
          if (!mounted) return;
          await _loadDelegations();
          if (!mounted) return;
          _notify('تم حذف التفويض');
        } catch (_) {
          if (!mounted) return;
          _notify('تعذّر حذف التفويض — تحقّق من الاتصال');
        }
    }
  }

  /// العهد المالية المسندة إلى هذا الشخص (يديرها بتفويض من صاحبها).
  List<PersonalEntryRecord> get _custodiesManagedByPerson {
    final personId = (_person.details['الرقم التعريفي'] ?? '').trim();
    if (personId.isEmpty) return const [];
    return [
      for (final r in _linked)
        if (r.entryType == 'عهدة مالية' &&
            (r.details[CustodyAssignment.kHolderId] ?? '').trim() == personId)
          r,
    ];
  }

  Widget _custodyDelegationRow(PersonalEntryRecord record) {
    final assignment = CustodyAssignment.decode(record.details);
    final closed = _closedStatuses.contains(record.status);
    final state = closed
        ? record.status
        : assignment.isPending
        ? 'بانتظار قبوله'
        : assignment.isRejected
        ? 'رفضها'
        : 'نشطة';
    final color = closed || assignment.isRejected
        ? const Color(0xFF8C9A97)
        : assignment.isPending
        ? const Color(0xFFA6691A)
        : const Color(0xFF0E7161);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      onTap: record.id == null ? null : () => _openLinkedEntry(record.id!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 17,
              color: Color(0xFFA6691A),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${AppTr.tr('مفوَّض بإدارة عهدة مالية')} — ${record.title}',
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (record.amount != 0)
                        '${record.amount} ${AppSettings.currencySuffix}',
                      if ((record.details[CustodyAssignment.kAssignedAt] ?? '')
                          .trim()
                          .isNotEmpty)
                        '${AppTr.tr('منذ')} ${record.details[CustodyAssignment.kAssignedAt]!.trim()}',
                    ].join(' · '),
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                state,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// موظف إن كان نوعه أو تصنيفه الرئيسي أو أحد تصنيفاته الإضافية «موظف».
  bool _isEmployeePerson(_PersonItem person) =>
      person.typeKey == 'person_employee' ||
      person.categoryName == 'موظف' ||
      person.additionalCategoryNames.contains('موظف');

  /// زر «الرواتب وسندات القبض» — يفتح سندات الموظف وبطاقة رواتبه.
  Widget _salaryReceiptsButton(_PersonItem person, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SalaryReceiptsScreen(
                employeeFnd: (person.details['الرقم التعريفي'] ?? '').trim(),
                employeeName: person.fullName,
              ),
            ),
          ),
          icon: const Icon(Icons.payments_outlined, size: 19),
          label: const Text('الرواتب وسندات القبض'),
        ),
      );

  /// قسم التفويضات داخل تبويب المستندات.
  Widget _buildDelegationsSection() {
    final custodies = _custodiesManagedByPerson;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionAddRow(
          title: 'التفويضات الممنوحة له',
          icon: Icons.assignment_ind_outlined,
          accent: const Color(0xFF0A5A50),
          count: _delegations.length + custodies.length,
          onAdd: _person.isFrozen ? null : _addDelegation,
        ),
        if (_delegationsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_delegationsError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _delegationsError,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC4392E),
              ),
            ),
          )
        else if (_delegations.isEmpty && custodies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'لا يوجد تفويض ممنوح لهذا السجل',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8C9A97),
              ),
            ),
          )
        else ...[
          for (final item in _delegations) _delegationRow(item),
          for (final record in custodies) _custodyDelegationRow(record),
        ],
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _delegationRow(DelegationRecord item) {
    final status = item.statusLabel;
    final statusColor = switch (status) {
      'نشط' => const Color(0xFF0E7161),
      'قارب الانتهاء' => const Color(0xFFA6691A),
      'منتهي' => const Color(0xFFC4392E),
      _ => const Color(0xFF8C9A97),
    };
    final period = item.endDate == null
        ? 'من ${_formatDate(item.startDate)} · مفتوح'
        : 'من ${_formatDate(item.startDate)} إلى ${_formatDate(item.endDate)}';
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      onTap: () => _openDelegationActions(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.assignment_ind_outlined,
                  size: 17,
                  color: Color(0xFF0A5A50),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.scope,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    status,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _permissionLevelLabel(item.permissions),
              textAlign: AppTr.alignEnd,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: Color(0xFF46534F),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              (item.notes ?? '').trim().isEmpty
                  ? period
                  : '$period · ${(item.notes ?? '').trim()}',
              textAlign: AppTr.alignEnd,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8C9A97),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// سطر «مفوَّض منك في كذا» داخل الملخص — تذكير سريع بما يملكه هذا السجل.
  Widget _buildDelegationSummaryLines() {
    final active = _delegations.where((e) => e.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const AppSectionAddRow(
          title: 'تفويضات سارية',
          icon: Icons.how_to_reg_outlined,
          accent: Color(0xFF0A5A50),
        ),
        for (final item in active)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.how_to_reg_outlined,
                  size: 17,
                  color: Color(0xFF0A5A50),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'مفوَّض منك في ${item.scope} · ${_permissionLevelLabel(item.permissions)}',
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _applyPersonUpdate(_PersonItem updated, {String? notice}) {
    setState(() {
      _person = updated;
      // مصدر واحد للحقيقة: قائمة المستندات المعروضة تُشتق دائمًا من سجل
      // الشخص المحفوظ حتى لا تنفصل عن العدّاد.
      _personDocuments = List<String>.from(updated.documents);
    });
    widget.onPersonUpdated?.call(_sourcePerson, updated);
    _sourcePerson = updated;
    if (notice != null && notice.isNotEmpty) {
      _notify(notice);
    }
  }

  Future<void> _editPersonData() async {
    final fullEdit = widget.onFullEdit;
    if (fullEdit != null) {
      final updated = await fullEdit(_person);
      if (updated == null || !mounted) return;
      _applyPersonUpdate(updated, notice: 'تم تحديث بيانات الشخص');
      return;
    }
    final nameController = TextEditingController(text: _person.fullName);
    final phoneController = TextEditingController(
      text: _detailValue(_person, const ['رقم الهاتف'], fallback: ''),
    );
    final nationalityController = TextEditingController(
      text: _detailValue(_person, const ['الجنسية'], fallback: ''),
    );
    final birthDateController = TextEditingController(
      text: _detailValue(_person, const ['تاريخ الميلاد'], fallback: ''),
    );
    final noteController = TextEditingController(text: _person.extraNote);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'تعديل بيانات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _editField(nameController, 'الاسم'),
                  _editField(phoneController, 'رقم الهاتف'),
                  _editField(nationalityController, 'الجنسية'),
                  _editField(birthDateController, 'تاريخ الميلاد'),
                  _editField(noteController, 'ملاحظات'),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final nextName = nameController.text.trim().isEmpty
                            ? _person.fullName
                            : nameController.text.trim();
                        final nextDetails =
                            Map<String, String>.from(_person.details)
                              ..['رقم الهاتف'] = phoneController.text.trim()
                              ..['الجنسية'] = nationalityController.text.trim()
                              ..['تاريخ الميلاد'] = birthDateController.text
                                  .trim();

                        _applyPersonUpdate(
                          _person.copyWith(
                            fullName: nextName,
                            extraNote: noteController.text.trim(),
                            details: nextDetails,
                            lastUpdate: _todayStamp(),
                          ),
                          notice: 'تم تحديث بيانات الشخص',
                        );
                        Navigator.of(context).pop();
                      },
                      child: const Text('حفظ التعديلات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      phoneController.dispose();
      nationalityController.dispose();
      birthDateController.dispose();
      noteController.dispose();
    });
  }

  Widget _editField(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        textDirection: AppTr.uiDir,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }

  Future<void> _sharePersonSummary() async {
    final summary = [
      'الاسم: ${_person.fullName}',
      'التصنيف: ${_person.categoryName}',
      'رقم التواصل: ${_detailValue(_person, const ['رقم الهاتف'], fallback: 'غير متوفر')}',
      'الرصيد المستحق له: ${_person.dueToYou}',
      'الرصيد المستحق عليه: ${_person.dueOnYou}',
    ].join('\n');

    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: _person.fullName,
        text: summary,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _deletePerson() async {
    final confirmed = await showDialog<bool>(
      context: context,
      // بدون غلاف اتجاه كان زر "حذف" يقع في الجهة التي يعتاد المستخدم أن
      // يجد فيها "إلغاء" في بقية التطبيق.
      builder: (context) {
        return Directionality(
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            title: const Text('حذف الشخص'),
            content: Text('هل تريد حذف ${_person.fullName}؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC4392E),
                ),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    widget.onPersonDeleted?.call(_sourcePerson);
    Navigator.of(context).pop();
  }

  /// الأرشفة تُنفَّذ كتجميد قابل للتراجع بدل الكتابة فوق التصنيف والحالة.
  /// كانت تستبدل badge/badgeColor/statusNote نهائيًا دون أي وسيلة للتراجع،
  /// فتُفقد بيانات الحالة الأصلية إلى الأبد بينما يبقى السجل في القائمة.
  void _archivePerson() {
    final archived = _person.extraNote.contains('[مؤرشف]');
    final nextNote = archived
        ? _person.extraNote.replaceAll('[مؤرشف]', '').trim()
        : '[مؤرشف] ${_person.extraNote}'.trim();
    _applyPersonUpdate(
      _person.copyWith(
        extraNote: nextNote,
        isFrozen: !archived,
        lastUpdate: _todayStamp(),
      ),
      notice: archived ? 'تم إخراج الشخص من الأرشيف' : 'تمت أرشفة الشخص',
    );
  }

  void _onTopMenuAction(ThreeDotMenuAction action) {
    // التجميد كان يمنع زر الإضافة فقط، بينما يظل التعديل متاحًا — أي أنه
    // تجميد شكلي. الآن يمنع التعديل فعليًا.
    if (action == ThreeDotMenuAction.edit && _person.isFrozen) {
      _notify('لا يمكن التعديل لأن السجل مجمّد. ألغِ التجميد أولاً.');
      return;
    }
    switch (action) {
      case ThreeDotMenuAction.edit:
        _editPersonData();
        break;
      case ThreeDotMenuAction.share:
        _sharePersonSummary();
        break;
      case ThreeDotMenuAction.delete:
        _deletePerson();
        break;
      case ThreeDotMenuAction.archive:
        _archivePerson();
        break;
      // التجميد والتثبيت حُذفا من قائمة الخيارات؛ تبقى الحالتان مقروءتين
      // من السجلات القديمة فقط.
      case ThreeDotMenuAction.freeze:
      case ThreeDotMenuAction.pinHome:
        break;
    }
  }

  late List<String> _personDocuments;
  late List<String> _personSharedCommitments;

  final List<String> _mainTabs = const [
    'الملخص',
    'البيانات الشخصية',
    'إجراءات العلاقات والارتباطات',
    'إجراءات المالية',
    'إجراءات المهام والأعمال',
  ];

  final List<String> _subTabs = const [
    'إجراءات المستندات',
    'إجراءات الالتزامات',
    'إجراءات التفويضات والصلاحيات',
    'إجراءات المواعيد',
  ];

  final List<_ActionGroup> _inputGroups = [
    _ActionGroup('إضافة مالية', const Color(0xFF34A894), const [
      _ActionTemplate('عهدة مالية', [
        _FieldDef('المبلغ', true),
        _FieldDef('الوصف', false),
      ]),
      _ActionTemplate('تحويل مالي', [
        _FieldDef('من', false),
        _FieldDef('إلى', false),
        _FieldDef('المبلغ', true),
      ]),
      _ActionTemplate('قسط', [
        _FieldDef('الجهة', false),
        _FieldDef('المبلغ', true),
        _FieldDef('تاريخ الاستحقاق', false),
      ]),
      _ActionTemplate('اشتراك', [
        _FieldDef('اسم الاشتراك', false),
        _FieldDef('المبلغ', true),
      ]),
      _ActionTemplate('غرامة', [
        _FieldDef('سبب الغرامة', false),
        _FieldDef('المبلغ', true),
      ]),
      _ActionTemplate('دفعة', [
        _FieldDef('الجهة', false),
        _FieldDef('المبلغ', true),
      ]),
      _ActionTemplate('تحصيل', [
        _FieldDef('من', false),
        _FieldDef('المبلغ', true),
      ]),
    ]),
    _ActionGroup('إضافة تنظيمية إدارية', const Color(0xFF0A5A50), const [
      _ActionTemplate('مهمة', [
        _FieldDef('عنوان المهمة', false),
        _FieldDef('المسؤول', false),
        _FieldDef('الموعد', false),
      ]),
      _ActionTemplate('موعد', [
        _FieldDef('العنوان', false),
        _FieldDef('التاريخ', false),
      ]),
      _ActionTemplate('تمديد', [
        _FieldDef('العنصر', false),
        _FieldDef('المدة الجديدة', false),
      ]),
      _ActionTemplate('تذكير', [
        _FieldDef('نص التذكير', false),
        _FieldDef('التوقيت', false),
      ]),
      _ActionTemplate('إعلان', [
        _FieldDef('العنوان', false),
        _FieldDef('التفاصيل', false),
      ]),
      _ActionTemplate('تصويت', [
        _FieldDef('موضوع التصويت', false),
        _FieldDef('الخيارات', false),
      ]),
      _ActionTemplate('قرار', [
        _FieldDef('عنوان القرار', false),
        _FieldDef('الوصف', false),
      ]),
      _ActionTemplate('طلب', [
        _FieldDef('عنوان الطلب', false),
        _FieldDef('التفاصيل', false),
      ]),
      _ActionTemplate('موافقة', [
        _FieldDef('العنصر المطلوب', false),
        _FieldDef('ملاحظة', false),
      ]),
    ]),
    _ActionGroup('إضافة مستند', const Color(0xFF0E7161), const [
      _ActionTemplate('مستند', [
        _FieldDef('اسم المستند', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('عقد', [
        _FieldDef('اسم العقد', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('فاتورة', [
        _FieldDef('المرجع', false),
        _FieldDef('المبلغ', true),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('شهادة', [
        _FieldDef('اسم الشهادة', false),
        _FieldDef('الجهة', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('هوية', [
        _FieldDef('رقم الهوية', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('جواز', [
        _FieldDef('رقم الجواز', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('إيصال', [
        _FieldDef('رقم الإيصال', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('ضمان', [
        _FieldDef('اسم الضمان', false),
        _expiryDateField,
        _expiryReminderField,
      ]),
      _ActionTemplate('اعتماد مستند', [
        _FieldDef('اسم المستند', false),
        _FieldDef('ملاحظة', false),
      ]),
      _ActionTemplate('رفض مستند', [
        _FieldDef('اسم المستند', false),
        _FieldDef('سبب الرفض', false),
      ]),
    ]),
    _ActionGroup('إضافة صلاحية / تفويض', const Color(0xFFC4392E), const [
      _ActionTemplate('تفويض', [
        _FieldDef('نوع التفويض', false),
        _FieldDef('الفترة', false),
      ]),
      _ActionTemplate('صلاحية', [
        _FieldDef('الصلاحية', false),
        _FieldDef('الحدود', false),
      ]),
      _ActionTemplate('تمديد صلاحية', [
        _FieldDef('الصلاحية', false),
        _FieldDef('الفترة الجديدة', false),
      ]),
      _ActionTemplate('إلغاء صلاحية', [
        _FieldDef('الصلاحية', false),
        _FieldDef('السبب', false),
      ]),
      _ActionTemplate('نقل مسؤولية', [
        _FieldDef('من', false),
        _FieldDef('إلى', false),
        _FieldDef('العنصر', false),
      ]),
    ]),
    _ActionGroup('إضافة كلمات سر', const Color(0xFF34A894), const [
      _ActionTemplate('كلمة سر', [
        _FieldDef('اسم التطبيق أو الموقع', false),
        _FieldDef('اسم المستخدم', false),
        _FieldDef('كلمة المرور', false),
      ]),
      _ActionTemplate('حساب دخول', [
        _FieldDef('اسم الحساب', false),
        _FieldDef('نوع الحساب', false),
        _FieldDef('كلمة المرور', false),
      ]),
      _ActionTemplate('تحديث كلمة سر', [
        _FieldDef('اسم الخدمة', false),
        _FieldDef('كلمة المرور الجديدة', false),
        _FieldDef('ملاحظة', false),
      ]),
    ]),
    _ActionGroup('إضافة مواقع وروابط', const Color(0xFF34A894), const [
      _ActionTemplate('موقع', [
        _FieldDef('اسم الموقع', false),
        _FieldDef('العنوان', false),
        _FieldDef('النوع', false),
      ]),
      _ActionTemplate('رابط', [
        _FieldDef('عنوان الرابط', false),
        _FieldDef('الرابط', false),
        _FieldDef('الوصف', false),
      ]),
      _ActionTemplate('دليل اتصال', [
        _FieldDef('الاسم', false),
        _FieldDef('الرابط أو الموقع', false),
        _FieldDef('ملاحظات', false),
      ]),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _loadDelegations();
    _loadLinked();
    _loadSalaryReceipts();
    _sourcePerson = widget.person;
    _personDocuments = List<String>.from(widget.person.documents);
    _personSharedCommitments = List<String>.from(
      widget.person.sharedCommitments,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _logQuery.dispose();
    super.dispose();
  }

  void _openActionForm(_ActionTemplate action, Color color) {
    final controllers = {
      for (final field in action.fields)
        field.label: TextEditingController(text: field.options?.first ?? ''),
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    action.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...action.fields.map((field) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: field.options != null
                          ? DropdownButtonFormField<String>(
                              initialValue: controllers[field.label]!.text,
                              decoration: InputDecoration(
                                labelText: field.label,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                              ),
                              items: field.options!
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) {
                                if (value != null) {
                                  controllers[field.label]!.text = value;
                                }
                              },
                            )
                          : TextField(
                              controller: controllers[field.label],
                              readOnly: field.isDate,
                              textDirection: AppTr.uiDir,
                              keyboardType: field.isNumeric
                                  ? TextInputType.number
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                hintText: field.label,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                isDense: true,
                                suffixIcon: field.isDate
                                    ? const Icon(Icons.event_outlined)
                                    : null,
                              ),
                              onTap: field.isDate
                                  ? () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2045),
                                      );
                                      if (date != null) {
                                        controllers[field.label]!.text =
                                            '${date.day}/${date.month}/${date.year}';
                                      }
                                    }
                                  : null,
                            ),
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final titleValue = action.fields.isEmpty
                            ? action.title
                            : controllers[action.fields.first.label]!.text
                                  .trim();
                        final summary = titleValue.isEmpty
                            ? action.title
                            : titleValue;

                        setState(() {
                          if (_isDocumentAction(action.title)) {
                            _personDocuments.insert(0, summary);
                          }

                          if (_isSharedCommitmentAction(action.title)) {
                            _personSharedCommitments.insert(0, summary);
                          }
                        });

                        final expiry = AppRemindersStore.parseDisplayDate(
                          controllers['تاريخ الانتهاء']?.text ?? '',
                        );
                        if (expiry != null) {
                          await AppRemindersStore.upsert(
                            AppReminder(
                              id: 'person-document-${DateTime.now().microsecondsSinceEpoch}',
                              title: '${action.title}: $summary',
                              module: 'الأفراد والجهات',
                              expiryDate: expiry,
                              remindBeforeDays:
                                  AppRemindersStore.reminderDaysFromLabel(
                                    controllers['التذكير قبل الانتهاء']?.text ??
                                        '',
                                  ),
                            ),
                          );
                        }

                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                      ),
                      child: const Text('حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }

  // نافذة "+ إضافة" الرئيسية لتفاصيل الفرد/الجهة — بنفس الطريقة والترتيب
  // المتّبع تمامًا في تفاصيل الالتزام الشخصي والمشترك (3 مربعات ثم قسم
  // إضافي قابل للطي)، وبنفس ترتيب الأقسام الوارد في ملف المتطلبات:
  // مالية، متابعة وتخطيط، مستندات، إضافة إجراء، مواقع وأماكن، تفويض.
  /// نموذج العهدة المالية — نفس حقول عهدة الالتزامات الشخصية: ما هي،
  /// ومن استلمها، ومتى، وإلى متى. العهدة بلا مستلم ولا أجل ليست عهدة.
  Future<void> _openCustodySheet() async {
    const accent = Color(0xFF34A894);
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final receiverCtrl = TextEditingController();
    final receiverIdCtrl = TextEditingController();
    final receivedCtrl = TextEditingController(text: _todayStamp());
    final dueCtrl = TextEditingController();
    final deliveredCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final referenceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var custodyType = _custodyTypes.first;
    var state = _custodyStates.first;
    var reminder = _kReminderNone;
    var showExtra = false;
    var attachment = '';

    Future<void> pick(TextEditingController controller) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate:
            AppRemindersStore.parseDisplayDate(controller.text) ?? now,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 30),
        builder: (pickerContext, child) => Directionality(
          textDirection: AppTr.uiDir,
          child: child ?? const SizedBox.shrink(),
        ),
      );
      if (picked == null) return;
      controller.text = '${picked.day}/${picked.month}/${picked.year}';
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.92,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.rCard),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEDB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'عهدة مالية',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sheetField(nameCtrl, 'اسم العهدة *', Icons.title_rounded),
                    const SizedBox(height: 9),
                    // قيمة العهدة كانت غائبة هنا بينما هي حقل إلزامي في
                    // عهدة الالتزامات الشخصية — فتُسجَّل عهدة بلا مبلغ.
                    _sheetField(
                      amountCtrl,
                      'قيمة العهدة *',
                      Icons.payments_outlined,
                      numeric: true,
                    ),
                    const SizedBox(height: 9),
                    _sheetField(
                      receiverCtrl,
                      'اسم المستلم *',
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 9),
                    // العهدة لا تُفتح بلا مسؤول: الرقم التعريفي إلزامي كما
                    // في الالتزامات الشخصية.
                    _sheetField(
                      receiverIdCtrl,
                      'الرقم التعريفي للمستلم *',
                      Icons.badge_outlined,
                    ),
                    const FndNameNotice(),
                    const SizedBox(height: 9),
                    _sheetDropdown(
                      'نوع العهدة *',
                      Icons.category_outlined,
                      custodyType,
                      _custodyTypes,
                      (value) => setSheetState(() => custodyType = value),
                    ),
                    const SizedBox(height: 9),
                    _sheetDateField(
                      receivedCtrl,
                      'تاريخ الاستلام *',
                      () async {
                        await pick(receivedCtrl);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 9),
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: _sheetDateField(dueCtrl, 'أجل العهدة *', () async {
                            await pick(dueCtrl);
                            setSheetState(() {});
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _sheetDropdown(
                            'تذكير',
                            Icons.notifications_none_rounded,
                            reminder,
                            _kReminderOptions,
                            (value) => setSheetState(() => reminder = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setSheetState(() => showExtra = !showExtra),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            const Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'الحقول الإضافية',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F1F1C),
                                ),
                              ),
                            ),
                            Icon(
                              showExtra
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showExtra) ...[
                      const SizedBox(height: 6),
                      _sheetDateField(deliveredCtrl, 'تاريخ التسليم', () async {
                        await pick(deliveredCtrl);
                        setSheetState(() {});
                      }),
                      const SizedBox(height: 9),
                      _sheetField(
                        purposeCtrl,
                        'الغرض من العهدة',
                        Icons.flag_outlined,
                      ),
                      const SizedBox(height: 9),
                      _sheetDropdown(
                        'حالة العهدة',
                        Icons.fact_check_outlined,
                        state,
                        _custodyStates,
                        (value) => setSheetState(() => state = value),
                      ),
                      const SizedBox(height: 9),
                      _sheetField(
                        referenceCtrl,
                        'رقم المرجع أو المستند',
                        Icons.tag_rounded,
                      ),
                    ],
                    const SizedBox(height: 9),
                    _sheetField(notesCtrl, 'ملاحظات', Icons.notes_rounded),
                    const SizedBox(height: 12),
                    if (attachment.isEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final path = await DocumentStore.pickAndStore(context: context);
                          if (path == null) return;
                          setSheetState(() => attachment = path);
                        },
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: const Text('إرفاق مستند العهدة'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: AppTheme.field,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            const Icon(
                              Icons.description_outlined,
                              size: 17,
                              color: accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                DocumentStore.shortName(attachment),
                                textAlign: AppTr.alignEnd,
                                maxLines: 3,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F1F1C),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setSheetState(() => attachment = ''),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: Color(0xFF8C9A97),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        final missing = <String>[
                          if (nameCtrl.text.trim().isEmpty) 'اسم العهدة',
                          if (amountCtrl.text.trim().isEmpty) 'قيمة العهدة',
                          if (receiverCtrl.text.trim().isEmpty) 'اسم المستلم',
                          if (receiverIdCtrl.text.trim().isEmpty)
                            'الرقم التعريفي للمستلم',
                          if (receivedCtrl.text.trim().isEmpty) 'تاريخ الاستلام',
                          if (dueCtrl.text.trim().isEmpty) 'أجل العهدة',
                        ];
                        if (missing.isNotEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text('أكمل: ${missing.join('، ')}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rField),
                        ),
                      ),
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final amount = amountCtrl.text.trim();
    final receiver = receiverCtrl.text.trim();
    final receiverId = receiverIdCtrl.text.trim();
    final received = receivedCtrl.text.trim();
    final due = dueCtrl.text.trim();
    final delivered = deliveredCtrl.text.trim();
    final purpose = purposeCtrl.text.trim();
    final reference = referenceCtrl.text.trim();
    final note = notesCtrl.text.trim();
    nameCtrl.dispose();
    amountCtrl.dispose();
    receiverCtrl.dispose();
    receiverIdCtrl.dispose();
    receivedCtrl.dispose();
    dueCtrl.dispose();
    deliveredCtrl.dispose();
    purposeCtrl.dispose();
    referenceCtrl.dispose();
    notesCtrl.dispose();
    if (saved != true || !mounted) return;

    final parts = <String>[
      'مالية — عهدة مالية',
      name,
      if (amount.isNotEmpty) '$amount ${AppSettings.currencySuffix}',
      custodyType,
      'المستلم: $receiver',
      if (receiverId.isNotEmpty) 'تعريف: $receiverId',
      'استُلمت $received',
      'ينتهي $due',
      if (delivered.isNotEmpty) 'سُلّمت $delivered',
      if (purpose.isNotEmpty) purpose,
      state,
      if (reference.isNotEmpty) 'مرجع: $reference',
      if (note.isNotEmpty) note,
    ];
    final logLine = parts.join(' · ');

    var updated = _person.copyWith(
      activityLog: [..._person.activityLog, logLine],
      lastUpdate: _todayStamp(),
    );
    if (attachment.isNotEmpty) {
      updated = updated.copyWith(
        details: _withAttachment(updated.details, logLine, attachment),
      );
    }

    await _registerCustodyReminder(name, due, reminder);
    if (!mounted) return;
    _applyPersonUpdate(updated, notice: 'تمت إضافة عهدة مالية');
  }

  Future<void> _registerCustodyReminder(
    String name,
    String dueText,
    String reminder,
  ) async {
    final expiry = AppRemindersStore.parseDisplayDate(dueText);
    if (expiry == null || reminder == _kReminderNone) return;
    final days = AppRemindersStore.reminderDaysFromLabel(reminder);
    if (days <= 0) return;
    await AppRemindersStore.upsert(
      AppReminder(
        id: 'person_custody_${DateTime.now().microsecondsSinceEpoch}',
        title: 'عهدة: $name — ${_person.fullName}',
        module: 'الأفراد والجهات',
        expiryDate: expiry,
        remindBeforeDays: days,
      ),
    );
  }

  /// خيارات التذكير التي تعمل قبل تاريخ الانتهاء: «قبل أسبوعين» لا معنى
  /// له لمستند ينتهي اليوم.
  List<String> _reminderOptionsUntil(String dateText) {
    final left = _daysFromToday(dateText);
    if (left == null) return _kReminderOptions;
    return [
      for (final option in _kReminderOptions)
        if (option == _kReminderNone ||
            option == _kReminderCustom ||
            AppRemindersStore.reminderDaysFromLabel(option) <= left)
          option,
    ];
  }

  /// حقول نوافذ الإضافة — شكل واحد لكل الحقول بدل ثلاثة أشكال مختلطة.
  Widget _sheetField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      textDirection: AppTr.uiDir,
      keyboardType: numeric ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: AppTr.tr(label),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF8C9A97)),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _sheetDateField(
    TextEditingController controller,
    String label,
    VoidCallback onTap,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: AppTr.tr(label),
        suffixIcon: const Icon(
          Icons.calendar_today_rounded,
          size: 18,
          color: Color(0xFF0E7161),
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _sheetDropdown(
    String label,
    IconData icon,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: AppTr.tr(label),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF8C9A97)),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(option, maxLines: 1))),
      ],
      onChanged: (next) => onChanged(next ?? value),
    );
  }

  /// زر + داخل القسم: يفتح نموذج إضافة هذا القسم مباشرة بلا نافذة اختيار.
  void _addForTab(String category) {
    switch (category) {
      case 'مالية':
        _openPersonKindEntrySheet(
          // الاتجاه من التبويب المختار (له / عليه)، فلا يُسأل مرة ثانية.
          toPerson: _financeTab == 0,
          category: 'مالية',
          color: const Color(0xFF34A894),
          kinds: const [
            'المصروفات الشخصية',
            'إيراد',
            'دين / قرض / سلفة',
            'قسط',
            'غرامة',
          ],
          showAmount: true,
        );
      case 'متابعة وتخطيط':
        // نفس نماذج المتابعة والتخطيط في الالتزامات الشخصية.
        _addFollowUp();
      case 'مستندات':
        _openPersonKindEntrySheet(
          category: 'مستندات',
          color: const Color(0xFF0E7161),
          kinds: const ['مستند عام', 'وثائق شخصية'],
        );
      case 'عهدة مالية':
        // نفس إدخال «عهدة مالية» في الالتزامات الشخصية، والمستلم هذا الفرد.
        _openPersonalForm(
          'عهدة مالية',
          prefill: {'اسم المستلم': _person.fullName.trim()},
        );
      case 'مواقع وأماكن':
        // نفس نموذج المواقع والأماكن في الالتزامات الشخصية.
        _openPersonalForm('مواقع وأماكن');
    }
  }

  Future<void> _openPersonQuickAddSheet() async {
    var orgExpanded = true;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEDB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'إضافة إلى الملف',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F1F1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اختر ما تريد إضافته لهذا الفرد أو الجهة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _PersonQuickAddTile(
                            key: const ValueKey('person-add-finance-option'),
                            label: 'مالية',
                            icon: Icons.payments_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'مالية'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PersonQuickAddTile(
                            key: const ValueKey('person-add-followup-option'),
                            label: 'المتابعة والتخطيط',
                            icon: Icons.event_note_outlined,
                            onTap: () =>
                                Navigator.pop(sheetContext, 'متابعة وتخطيط'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PersonQuickAddTile(
                            key: const ValueKey('person-add-document-option'),
                            label: 'مستندات',
                            icon: Icons.description_outlined,
                            onTap: () =>
                                Navigator.pop(sheetContext, 'مستندات'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // العهدة المالية قسم قائم بذاته لا نوعًا داخل «مالية»:
                    // لها حقولها الخاصة (المستلم، الأجل، الأصناف) تمامًا
                    // كما في الالتزامات الشخصية.
                    Row(
                      children: [
                        Expanded(
                          child: _PersonQuickAddTile(
                            key: const ValueKey('person-add-custody-option'),
                            label: 'عهدة مالية',
                            icon: Icons.inventory_2_outlined,
                            onTap: () =>
                                Navigator.pop(sheetContext, 'عهدة مالية'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: SizedBox()),
                        const SizedBox(width: 8),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () =>
                          setSheetState(() => orgExpanded = !orgExpanded),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: Color(0xFF0E7161),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'إجراءات إضافية',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F1F1C),
                                ),
                              ),
                            ),
                            Icon(
                              orgExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF0E7161),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      // «إضافة إجراء» حُذفت: لا تبويب لها ولا معنى لبند
                      // لا يظهر في أي قسم.
                      Row(
                        children: [
                          Expanded(
                            child: _PersonQuickAddTile(
                              key: const ValueKey('person-add-place-option'),
                              label: 'مواقع وأماكن',
                              icon: Icons.place_outlined,
                              onTap: () =>
                                  Navigator.pop(sheetContext, 'مواقع وأماكن'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // تفويض: بند مستقل هنا حسب ملف المتطلبات، لكن بياناته
                      // تُخزَّن ضمن "متابعة وتخطيط" مباشرة (بقرار المستخدم
                      // السابق)، مع إمكانية إدارة تفصيلية لاحقًا من "المزيد".
                      Row(
                        children: [
                          Expanded(
                            child: _PersonQuickAddTile(
                              key: const ValueKey(
                                'person-add-delegation-option',
                              ),
                              label: 'تفويض',
                              icon: Icons.assignment_ind_outlined,
                              onTap: () =>
                                  Navigator.pop(sheetContext, 'تفويض'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'مالية':
        _openPersonKindEntrySheet(
          category: 'مالية',
          color: const Color(0xFF34A894),
          kinds: const [
            'المصروفات الشخصية',
            'إيراد',
            'دين / قرض / سلفة',
            'قسط',
            'غرامة',
          ],
          showAmount: true,
        );
      case 'متابعة وتخطيط':
        // نفس نماذج المتابعة والتخطيط في الالتزامات الشخصية.
        _addFollowUp();
      case 'مستندات':
        _openPersonKindEntrySheet(
          category: 'مستندات',
          color: const Color(0xFF0E7161),
          kinds: const ['مستند عام', 'وثائق شخصية'],
        );
      case 'عهدة مالية':
        // نفس إدخال «عهدة مالية» في الالتزامات الشخصية، والمستلم هذا الفرد.
        _openPersonalForm(
          'عهدة مالية',
          prefill: {'اسم المستلم': _person.fullName.trim()},
        );
      case 'مواقع وأماكن':
        // نفس نموذج المواقع والأماكن في الالتزامات الشخصية.
        _openPersonalForm('مواقع وأماكن');
      case 'تفويض':
        // نفس نموذج «المزيد ← التفويضات».
        _addDelegation();
    }
  }

  // نافذة الإدخال العامة لكل قسم من أقسام "+ إضافة" — قائمة منسدلة
  // للنوع (مع خيار "+ إضافة أخرى") وحقول تاريخ/ملاحظات (ومبلغ عند
  // الحاجة)، بنفس نمط _openSimpleEntrySheet في الالتزامات المشتركة.
  Future<void> _openPersonKindEntrySheet({
    required String category,
    required Color color,
    required List<String> kinds,
    String? initialKind,
    bool showAmount = false,
    bool? toPerson,
  }) async {
    const customOption = '+ إضافة أخرى';
    var kind = initialKind ?? kinds.first;
    // اتجاه المبلغ يُحدَّده المستخدم صراحةً بنفس ألفاظ الشاشة ("له"/"عليه")
    // بدل استنتاجه من اسم النوع، فلا يُسجَّل مبلغ في الجهة الخاطئة. وإن جاء
    // من تبويب «له» أو «عليه» فهو محدَّد مسبقًا ولا يظهر السؤال.
    var amountToPerson = toPerson ?? false;
    // كل ما له تاريخ انتهاء يحمل تذكيرًا: التاريخ وحده لا ينبّه أحدًا.
    var reminder = _kReminderNone;
    // المرفق: صورة المستند أو الفاتورة. إلزامي في «مستندات».
    var attachment = '';
    final customKindCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final customDaysCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEDB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('النوع'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        ...kinds.map(
                          (k) => DropdownMenuItem(value: k, child: Text(k)),
                        ),
                        const DropdownMenuItem(
                          value: customOption,
                          child: Text(customOption),
                        ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => kind = value ?? kind),
                    ),
                    if (kind == customOption) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customKindCtrl,
                        decoration: InputDecoration(
                          labelText: AppTr.tr('اكتب النوع'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    if (showAmount) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: AppTr.tr('المبلغ'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      // اتجاه المبلغ لا معنى له إلا فيما يُنشئ دَينًا:
                      // الراتب والمصروف لا يُسألان «له أم عليه».
                      if (toPerson == null &&
                          _directionKinds.contains(kind)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              value: true,
                              groupValue: amountToPerson,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'مستحق له',
                                style: TextStyle(fontSize: 12),
                              ),
                              onChanged: (value) => setSheetState(
                                () => amountToPerson = value ?? true,
                              ),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              value: false,
                              groupValue: amountToPerson,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'مستحق عليه',
                                style: TextStyle(fontSize: 12),
                              ),
                              onChanged: (value) => setSheetState(
                                () => amountToPerson = value ?? false,
                              ),
                            ),
                          ),
                        ],
                      ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    // التاريخ والتذكير في سطر واحد، بخط عنوان أصغر ليظهر
                    // كاملًا بلا قصّ.
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dateCtrl,
                            readOnly: true,
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    AppRemindersStore.parseDisplayDate(
                                      dateCtrl.text,
                                    ) ??
                                    now,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 30),
                                builder: (pickerContext, child) =>
                                    Directionality(
                                      textDirection: AppTr.uiDir,
                                      child: child ?? const SizedBox.shrink(),
                                    ),
                              );
                              if (picked == null) return;
                              setSheetState(() {
                                dateCtrl.text =
                                    '${picked.day}/${picked.month}/${picked.year}';
                                // تذكير أبعد من المدة الباقية لا يعمل: يُلغى.
                                if (!_reminderOptionsUntil(dateCtrl.text)
                                    .contains(reminder)) {
                                  reminder = _kReminderNone;
                                }
                              });
                            },
                            decoration: InputDecoration(
                              labelText: AppTr.tr(
                                category == 'مالية'
                                    ? 'تاريخ الاستحقاق'
                                    : 'تاريخ الانتهاء',
                              ),
                              labelStyle: const TextStyle(fontSize: 12),
                              suffixIcon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: Color(0xFF0E7161),
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 34,
                              ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: reminder,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: AppTr.tr('تذكير'),
                              labelStyle: const TextStyle(fontSize: 12),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final option in _reminderOptionsUntil(
                                dateCtrl.text,
                              ))
                                DropdownMenuItem(
                                  value: option,
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(option, maxLines: 1)),
                                ),
                            ],
                            onChanged: (value) => setSheetState(
                              () => reminder = value ?? reminder,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (reminder == _kReminderCustom) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: AppTr.tr('التذكير قبل كم يوم'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('ملاحظات'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // إرفاق المستند: صورة الفاتورة أو الوثيقة نفسها.
                    if (attachment.isEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final path = await DocumentStore.pickAndStore(context: context);
                          if (path == null) return;
                          setSheetState(() => attachment = path);
                        },
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(
                          category == 'مستندات'
                              ? 'إرفاق صورة المستند *'
                              : 'إرفاق مستند أو فاتورة',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: AppTheme.field,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 17,
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                DocumentStore.shortName(attachment),
                                textAlign: AppTr.alignEnd,
                                maxLines: 3,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F1F1C),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  setSheetState(() => attachment = ''),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: Color(0xFF8C9A97),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // المستند بلا مرفق لا قيمة له: الصورة هي المستند.
                        if (category == 'مستندات' && attachment.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('أرفق صورة المستند أولاً'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        Navigator.pop(sheetContext, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                      ),
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) {
      customKindCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      customDaysCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    final resolvedKind = kind == customOption
        ? (customKindCtrl.text.trim().isEmpty
              ? category
              : customKindCtrl.text.trim())
        : kind;
    if (_person.typeKey == 'person_self' && category == 'مستندات') {
      final reminderLabel = reminder == _kReminderCustom
          ? (int.tryParse(customDaysCtrl.text.trim()) ?? 0) > 0
                ? 'قبل ${int.parse(customDaysCtrl.text.trim())} يوم'
                : ''
          : (reminder == _kReminderNone ? '' : reminder);
      try {
        await SupabasePersonalEntriesRepository().create(
          PersonalEntryRecord(
            category: 'document',
            entryType: 'مستند',
            title: resolvedKind,
            amount: 0,
            dueDate: dateCtrl.text.trim(),
            status: 'نشطة',
            details: {
              'نوع المستند': resolvedKind,
              if (dateCtrl.text.trim().isNotEmpty)
                'تاريخ الانتهاء': dateCtrl.text.trim(),
              if (reminderLabel.isNotEmpty)
                'التذكير قبل الانتهاء': reminderLabel,
              if (notesCtrl.text.trim().isNotEmpty)
                'ملاحظات': notesCtrl.text.trim(),
              kLinkedPersonKey: _person.fullName.trim(),
            },
          ),
          attachment: attachment.isEmpty
              ? null
              : XFile(
                  DocumentStore.localPathFor(attachment),
                  name: DocumentStore.fileName(attachment),
                ),
        );
        await _loadLinked();
        _notify('حُفظ المستند في الالتزامات الشخصية ← المستندات');
      } catch (error) {
        _notify('تعذّر حفظ المستند: $error');
      }
      customKindCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      customDaysCtrl.dispose();
      notesCtrl.dispose();
      return;
    }
    final logParts = <String>['$category — $resolvedKind'];
    // اتجاه المبلغ يُكتب صراحةً حتى تُصنَّف البنود تحت «له» و«عليه».
    if (showAmount &&
        _directionKinds.contains(resolvedKind) &&
        amountCtrl.text.trim().isNotEmpty) {
      logParts.add(amountToPerson ? 'له' : 'عليه');
    }
    if (amountCtrl.text.trim().isNotEmpty) {
      logParts.add('${amountCtrl.text.trim()} ${AppSettings.currencySuffix}');
    }
    if (dateCtrl.text.trim().isNotEmpty) {
      logParts.add('ينتهي ${dateCtrl.text.trim()}');
      if (reminder != _kReminderNone) logParts.add(reminder);
    }
    if (notesCtrl.text.trim().isNotEmpty) logParts.add(notesCtrl.text.trim());
    final logLine = logParts.join(' · ');

    var updated = _person.copyWith(
      activityLog: [..._person.activityLog, logLine],
      lastUpdate: _todayStamp(),
    );
    // المبلغ المُدخل يُضاف فعليًا إلى رصيد الشخص. كان يُكتب سابقًا كنص في
    // السجل الزمني فقط، فتبقى بطاقة الشخص تعرض "له : 0 درهم" مهما سُجِّل من
    // مبالغ — وكان ترتيب "الأعلى مستحقات" بلا أي معنى نتيجة ذلك.
    // أرقام عربية وفواصل الآلاف (1,500) تُقرأ — كانت تُحسب صفرًا.
    final amount = entryNumber(amountCtrl.text);
    if (showAmount && _directionKinds.contains(resolvedKind) && amount > 0) {
      updated = amountToPerson
          ? updated.copyWith(
              dueToYou: updated.dueToYou + amount.round(),
            )
          : updated.copyWith(
              dueOnYou: updated.dueOnYou + amount.round(),
            );
    }
    // البند يُحفظ بمعلوماته كاملة (النوع والمبلغ والتاريخ والملاحظة) لا
    // بالنوع وحده، فيظهر في قائمة القسم كما أُدخل.
    final entryLabel = logParts.skip(1).isEmpty
        ? resolvedKind
        : '$resolvedKind · ${logParts.skip(1).join(' · ')}';
    if (attachment.isNotEmpty) {
      // يُفهرس المرفق بنصّ البند وبسطر السجل معًا: قائمة المستندات تعرض
      // الأول وقوائم المالية والمتابعة تعرض الثاني.
      var withFile = _withAttachment(updated.details, entryLabel, attachment);
      withFile = _withAttachment(withFile, logLine, attachment);
      updated = updated.copyWith(details: withFile);
    }
    if (category == 'مستندات') {
      // المستند يُضاف إلى قائمة الشخص نفسها (التي تُحفَظ)، لا إلى قائمة
      // محلية في الشاشة. سابقًا كان العدّاد يزيد بينما اسم المستند يُكتب في
      // متغير مؤقت لا يُحفظ، فيختفي المستند بعد إعادة التشغيل ويبقى العدّاد
      // مرتفعًا — أي رقم لا يطابق محتواه أبدًا.
      updated = updated.copyWith(
        documents: [entryLabel, ...updated.documents],
        documentsCount: updated.documentsCount + 1,
      );
    } else if (category == 'متابعة وتخطيط') {
      updated = updated.copyWith(openTasks: updated.openTasks + 1);
    }

    // التذكير يُسجَّل فعليًا في مخزن التنبيهات، فيظهر في الكلندر ومركز
    // التنبيهات — لا يبقى نصًا في السجل فقط.
    final expiry = AppRemindersStore.parseDisplayDate(dateCtrl.text);
    if (expiry != null && reminder != _kReminderNone) {
      final days = reminder == _kReminderCustom
          ? (int.tryParse(customDaysCtrl.text.trim()) ?? 0)
          : AppRemindersStore.reminderDaysFromLabel(reminder);
      if (days > 0) {
        await AppRemindersStore.upsert(
          AppReminder(
            id: 'person_${_person.fullName}_${DateTime.now().microsecondsSinceEpoch}',
            title: '$resolvedKind — ${_person.fullName}',
            module: 'الأفراد والجهات',
            expiryDate: expiry,
            remindBeforeDays: days,
          ),
        );
      }
    }

    customKindCtrl.dispose();
    amountCtrl.dispose();
    dateCtrl.dispose();
    customDaysCtrl.dispose();
    notesCtrl.dispose();

    _applyPersonUpdate(updated, notice: 'تمت إضافة $resolvedKind');
  }

  void _openMainEntryTypesSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAF9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 26,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DEDB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_box_rounded,
                        color: Color(0xFF04413B),
                        size: 21,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'اختيار نوع الإضافة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF022E2A),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'اختر الإجراء المطلوب للإضافة داخل تفاصيل الأشخاص',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    itemCount: _inputGroups.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.15,
                        ),
                    itemBuilder: (context, index) {
                      final group = _inputGroups[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openMainEntryItemsSheet(group);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rIcon),
          ),
                                child: Icon(
                                  Icons.folder_copy_outlined,
                                  color: group.color,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                group.title,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF022E2A),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${group.actions.length} خيارات',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: group.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openRelationsActionsSheet() {
    const relationsGroup = _ActionGroup(
      'إجراءات العلاقات والارتباطات',
      Color(0xFF34A894),
      [
        _ActionTemplate('ربط شخص بشخص', [
          _FieldDef('الشخص الأول', false),
          _FieldDef('الشخص الثاني', false),
        ]),
        _ActionTemplate('ربط شخص بالتزام', [
          _FieldDef('الشخص', false),
          _FieldDef('الالتزام', false),
        ]),
        _ActionTemplate('ربط شخص بمستند', [
          _FieldDef('الشخص', false),
          _FieldDef('المستند', false),
        ]),
        _ActionTemplate('ربط شخص بأصل', [
          _FieldDef('الشخص', false),
          _FieldDef('الأصل', false),
        ]),
        _ActionTemplate('فك ارتباط', [
          _FieldDef('نوع الارتباط', false),
          _FieldDef('ملاحظة', false),
        ]),
      ],
    );

    _openMainEntryItemsSheet(relationsGroup);
  }

  bool _matchesQuery(String value) {
    final query = _searchController.text.trim();
    return query.isEmpty || value.contains(query);
  }

  List<String> _filterItems(List<String> items) {
    if (_searchController.text.trim().isEmpty) return items;
    return items.where(_matchesQuery).toList(growable: false);
  }

  Widget _buildPersonActionSections() {
    final financialGroup = _inputGroups.firstWhere(
      (g) => g.title == 'إضافة مالية',
    );
    final organizationalGroup = _inputGroups.firstWhere(
      (g) => g.title == 'إضافة تنظيمية إدارية',
    );
    final documentsGroup = _inputGroups.firstWhere(
      (g) => g.title == 'إضافة مستند',
    );
    final permissionsGroup = _inputGroups.firstWhere(
      (g) => g.title == 'إضافة صلاحية / تفويض',
    );

    final showAll = _selectedMainTab <= 1;
    final showRelations = showAll || _selectedMainTab == 2;
    final showFinancial = showAll || _selectedMainTab == 3;
    final showTasks = showAll || _selectedMainTab == 4;
    final showDocsAndPermissions =
        showAll || _selectedSubTab == 0 || _selectedSubTab == 2;

    final cards = <Widget>[];

    if (showTasks) {
      cards.add(
        _ActionShortcutCard(
          title: 'إجراءات المهام والأعمال',
          subtitle: 'إنشاء مهمة، موعد، تذكير، قرار، طلب، موافقة',
          color: organizationalGroup.color,
          icon: Icons.task_alt_rounded,
          onTap: () => _openMainEntryItemsSheet(organizationalGroup),
        ),
      );
    }

    if (showRelations) {
      cards.add(
        _ActionShortcutCard(
          title: 'إجراءات العلاقات والارتباطات',
          subtitle: 'ربط الأشخاص بالالتزامات والمستندات والأصول',
          color: const Color(0xFF34A894),
          icon: Icons.hub_rounded,
          onTap: _openRelationsActionsSheet,
        ),
      );
    }

    if (showFinancial) {
      cards.add(
        _ActionShortcutCard(
          title: 'إجراءات المالية',
          subtitle: 'دفعة، تحصيل، قسط، اشتراك، تحويل مالي، عهدة',
          color: financialGroup.color,
          icon: Icons.payments_rounded,
          onTap: () => _openMainEntryItemsSheet(financialGroup),
        ),
      );
    }

    if (showDocsAndPermissions) {
      cards.add(
        _ActionShortcutCard(
          title: 'إجراءات المستندات والتفويضات',
          subtitle: 'مستند، عقد، هوية، تفويض، صلاحية، تمديد صلاحية',
          color: documentsGroup.color,
          icon: Icons.folder_shared_rounded,
          onTap: () => _openMainEntryItemsSheet(documentsGroup),
          onSecondaryTap: () => _openMainEntryItemsSheet(permissionsGroup),
          secondaryLabel: 'صلاحيات',
        ),
      );
    }

    if (cards.isEmpty) {
      return const _EmptyActionState(
        message: 'لا توجد إجراءات مطابقة لهذا القسم',
      );
    }

    return Column(
      children: cards
          .map(
            (card) =>
                Padding(padding: const EdgeInsets.only(bottom: 8), child: card),
          )
          .toList(growable: false),
    );
  }

  void _openMainEntryItemsSheet(_ActionGroup group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.72,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DEDB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      group.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      textDirection: AppTr.uiDir,
                      children: group.actions
                          .map((action) {
                            return ActionChip(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _openActionForm(action, group.color);
                              },
                              label: Text(action.title),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: group.color.withValues(alpha: 0.35),
                              ),
                              avatar: Icon(
                                Icons.add_circle_outline_rounded,
                                size: 16,
                                color: group.color,
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDocumentAction(String title) {
    return title == 'مستند' ||
        title == 'عقد' ||
        title == 'فاتورة' ||
        title == 'شهادة' ||
        title == 'هوية' ||
        title == 'جواز';
  }

  bool _isSharedCommitmentAction(String title) {
    return title == 'قسط' ||
        title == 'اشتراك' ||
        title == 'دفعة' ||
        title == 'تحصيل';
  }

  void _openDetailSectionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'اختيار القسم',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'الأقسام الرئيسية',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  textDirection: AppTr.uiDir,
                  children: List.generate(_mainTabs.length, (index) {
                    final selected = _selectedMainTab == index;
                    return ChoiceChip(
                      label: Text(_mainTabs[index]),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedMainTab = index);
                        Navigator.of(context).pop();
                      },
                    );
                  }),
                ),
                const SizedBox(height: 10),
                const Text(
                  'الأقسام الفرعية',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  textDirection: AppTr.uiDir,
                  children: List.generate(_subTabs.length, (index) {
                    final selected = _selectedSubTab == index;
                    return ChoiceChip(
                      label: Text(_subTabs[index]),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedSubTab = index);
                        Navigator.of(context).pop();
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    final filteredDocuments = _filterItems([
      ..._linkedRows('مستندات'),
      ..._personDocuments,
    ]);
    final filteredCommitments = _filterItems(_personSharedCommitments);
    final selectedTab = _detailTabs[_selectedMainTab];
    // خيارات «الحالة» لكل تبويب، وأولها «الأحدث أولاً».
    // العهدة: نشطة، مكتملة (تمت تسويتها)، ملغية.
    final financeStatuses = _financeTab == 2
        ? const ['الأحدث أولاً', 'نشطة', 'مكتملة', 'ملغية']
        : const ['الأحدث أولاً', 'نشطة', 'مكتملة'];
    const planStatuses = [
      'الأحدث أولاً',
      'نشطة',
      'قريبًا',
      'حان وقتها',
      'متأخرة',
    ];
    const docStatuses = ['الأحدث أولاً', 'نشطة', 'تنتهي قريبًا', 'منتهية'];
    const placeStatuses = ['الأحدث أولاً', 'نشطة'];
    const medicineStatuses = [
      'الأحدث أولاً',
      'أدوية اليوم',
      'أدوية قادمة',
      'أدوية منتهية',
    ];
    final planRows = [
      ..._linkedRows('متابعة وتخطيط'),
      ..._followUpEntries(person),
    ].where(
      (row) =>
          _planKind == 'الكل' ||
          row.startsWith('$_planKind — ') ||
          row.contains('— $_planKind'),
    ).toList();
    // نقطة حمراء على «المتابعة والتخطيط» و«مستندات» إن كان فيها ما انتهى
    // أو حان وقته أو تأخر أو يحتاج متابعة.
    final tabAlerts = <String>{
      if ([
        ..._linkedRows('متابعة وتخطيط'),
        ..._followUpEntries(person),
      ].any((row) => _rowNeedsAttention(row, document: false)))
        'المتابعة والتخطيط',
      if ([
        ..._linkedRows('مستندات'),
        ..._personDocuments,
      ].any((row) => _rowNeedsAttention(row, document: true)))
        'مستندات',
    };
    final medicineRows = _linkedRows('أدوية');
    final placeRows = [
      ..._linkedRows('مواقع وأماكن'),
      ..._logEntries(person, 'مواقع وأماكن'),
    ];
    const color = Color(0xFF0E7161);

    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // الزر العائم في الملخص وحده: بقية التبويبات فيها زر + داخل سطر
      // القسم، فلا يتكرّر زران لنفس الفعل.
      floatingActionButton: selectedTab != 'الملخص'
          ? null
          : AddFab(
              key: const ValueKey('add-person-detail-entry'),
              screenId: 'person_details_${person.fullName}',
              onPressed: () {
                if (person.isFrozen) {
                  _notify('لا يمكن الإضافة لأن الحساب مجمّد');
                  return;
                }
                _openPersonQuickAddSheet();
              },
              label: 'إضافة',
              icon: Icons.add_rounded,
              backgroundColor: const Color(0xFFF2A93F),
              foregroundColor: const Color(0xFF4A2F09),
              initialOffset: const Offset(0, 0),
            ),
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F1F1C),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text(
          _isEntityKind(person.typeKey) ? 'تفاصيل جهة' : 'تفاصيل فرد',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F1F1C),
          ),
        ),
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        // CustomScrollView ليمكن تثبيت شريط التبويبات: بطاقة بيانات الفرد
        // تختفي عند النزول ويبقى شريط "الملخص / التنظيم / ..." ثابتًا.
        child: CustomScrollView(
          key: const ValueKey('compact-person-details'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            // نفس بنية "مستطيل تفاصيل الالتزام" الموحّد تمامًا: هيدر مدمج
            // + خط رفيع + شريط أبرز البيانات، ثم تبويبات بعرض متساوٍ، ثم
            // محتوى بـ AnimatedSwitcher — بدل مكوّن DetailScaffold العام.
            // ملاحظة: لا يوضع رقم التواصل في مستطيل منفرد لحاله (حسب ملف
            // المتطلبات) — يظهر ضمن "البيانات الأساسية" بتبويب التنظيم.
            Container(
              key: const ValueKey('compact-person-details-header'),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CompactPersonHeader(
                    person: person,
                    color: color,
                    onAction: _onTopMenuAction,
                    // وسم «مفوَّض» يظهر لمن له تفويض ساري، والضغط عليه
                    // ينقل إلى تبويب التفويضات ليرى تفاصيله.
                    delegationCount: _delegations
                        .where((item) => item.isActive)
                        .length,
                    onOpenDelegations: () => setState(
                      () => _selectedMainTab = _detailTabs.indexOf('التفويضات'),
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFF2F6F5)),
                  _PersonHighlightBar(person: person, color: color),
                ],
              ),
            ),
                  ],
                ),
              ),
            ),
            // كانت نسخة محلية مطابقة لـDetailPageTabs إلا أنها تُسقط
            // overflow: ellipsis، فتتجاوز عناوين مثل "متابعة وتخطيط" حدود
            // التبويب الواحد. استُبدلت بالمكوّن المشترك نفسه.
            MeasuredPinnedHeader(
              background: AppTheme.page,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: DetailPageTabs(
                  twoLineLabels: true,
                  alertLabels: tabAlerts,
                  sections: _detailSections,
                  selectedIndex: _selectedMainTab,
                  color: color,
                  onSelected: (index) =>
                      setState(() => _selectedMainTab = index),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 92),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_selectedMainTab),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  if (selectedTab == 'الملخص') ...[
                    // الموظف: سندات القبض وسجل رواتبه سنةً سنة.
                    if (_isEmployeePerson(person))
                      _salaryReceiptsButton(person, color),
                    _SummaryPanel(
                      person: person,
                      textDirection: AppTr.uiDir,
                    ),
                    _buildDelegationSummaryLines(),
                  ],
                  // السجل الزمني صار تبويبًا مستقلًا.
                  // سجل مرتّب كسجل العقارات: بحث، من/إلى تاريخ، وتصفية حسب
                  // النوع، وكل حدث بأيقونته وتاريخه ومبلغه.
                  if (selectedTab == 'السجل') _buildPersonLog(person, color),
                  // مالية: له / عليه / عهدة مالية، ومع كل واحد فلتر المصدر
                  // وفلتر الحالة، وتحتهما البنود المرتبطة.
                  if (selectedTab == 'مالية') ...[
                    _PersonSegments(
                      labels: const ['له', 'عليه', 'عهدة مالية'],
                      selected: _financeTab,
                      color: color,
                      onSelected: (index) =>
                          setState(() => _financeTab = index),
                    ),
                    const SizedBox(height: 10),
                    // للعرض فقط: سطر واحد في المنتصف بلا مستطيل.
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'هذه الصفحة لعرض ما سُجّل سابقًا',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    _sectionFilters(
                      financeStatuses,
                      sourceOptions: _financeTab == 2
                          ? const ['الالتزامات الشخصية']
                          : null,
                    ),
                    AppSectionAddRow(
                      title: _financeTab == 0
                          ? 'له: ${person.dueToYou} ${AppSettings.currencySuffix}'
                          : _financeTab == 1
                          ? 'عليه: ${person.dueOnYou} ${AppSettings.currencySuffix}'
                          : 'عهدة مالية',
                      icon: Icons.account_balance_wallet_outlined,
                      accent: color,
                      onAdd: person.isFrozen
                          ? null
                          : () => _addFinance(_financeTab),
                    ),
                    _filteredList(
                      [
                        if (_financeTab == 0) ..._salaryRows(),
                        if (_financeTab == 0) ..._linkedRows('له'),
                        if (_financeTab == 1) ..._linkedRows('عليه'),
                        if (_financeTab == 2) ..._linkedRows('عهدة مالية'),
                        ..._moneyEntries(person, _financeTab),
                        ...filteredCommitments.where(
                          (e) => _financeTab == 2
                              ? e.contains('عهدة')
                              : e.contains(_financeTab == 0 ? 'له' : 'عليه'),
                        ),
                      ],
                      financeStatuses,
                      _financeTab == 2
                          // عهد موجودة لكن الحالة المختارة تخفيها.
                          ? (_linkedRows('عهدة مالية').isNotEmpty
                                ? 'لا توجد عهدة مالية بهذه الحالة — اختر حالة أخرى أو «الأحدث أولاً» لعرض الكل'
                                : 'لا يوجد عهدة مالية — اذهب إلى الالتزامات الشخصية لتسجيل عهدة مالية')
                          : _financeTab == 0
                          ? 'لا يوجد أموال لك — سجّل في الالتزامات الشخصية أو الالتزامات المشتركة أو العقارات والأنشطة التجارية والمركبات ووسائل النقل لكي تظهر هنا'
                          : 'لا يوجد أموال عليك — سجّل في الالتزامات الشخصية أو الالتزامات المشتركة أو العقارات والأنشطة التجارية والمركبات ووسائل النقل لكي تظهر هنا',
                      Icons.account_balance_wallet_outlined,
                      anySource: _financeTab == 2,
                    ),
                    if (_financeTab == 2)
                      const Padding(
                        padding: EdgeInsets.only(top: 2, bottom: 8),
                        child: Text(
                          'لمزيد من التفاصيل اضغط على العهدة، أو افتح '
                          '«الالتزامات الشخصية» ← «عهدة مالية».',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8C9A97),
                          ),
                        ),
                      ),
                  ],
                  // المتابعة والتخطيط: نفس نماذج وبنود الالتزامات الشخصية
                  // (مهمة، موعد، عادة، تذكير، ملاحظات) مربوطة بهذا الفرد.
                  if (selectedTab == 'متابعة وتخطيط') ...[
                    // العنوان و«+» فقط، وتحته فلترا النوع والحالة.
                    AppSectionAddRow(
                      title: 'المتابعة والتخطيط',
                      icon: Icons.event_note_outlined,
                      accent: color,
                      count: planRows.length,
                      onAdd: person.isFrozen ? null : _addFollowUp,
                    ),
                    FollowFiltersRow(
                      kind: _planKind,
                      status: planStatuses.contains(_statusFilter)
                          ? _statusFilter
                          : planStatuses.first,
                      statusOptions: planStatuses,
                      onKind: (value) => setState(() => _planKind = value),
                      onStatus: (value) =>
                          setState(() => _statusFilter = value),
                    ),
                    _filteredList(
                      planRows,
                      planStatuses,
                      'لا توجد متابعة أو تخطيط مطابق للفلتر',
                      Icons.event_note_outlined,
                      anySource: true,
                    ),
                  ],
                  if (selectedTab == 'التفويضات') _buildDelegationsSection(),
                  if (selectedTab == 'مستندات') ...[
                    // الموظف: سندات القبض والإيصالات وبطاقة الراتب.
                    if (_isEmployeePerson(person))
                      _salaryReceiptsButton(person, color),
                    _sectionFilters(docStatuses),
                    AppSectionAddRow(
                      title: 'المستندات',
                      icon: Icons.folder_outlined,
                      accent: color,
                      // الرقم ملاصق لكلمة «المستندات».
                      count: person.documentsCount +
                          _linkedRows('مستندات').length,
                      onAdd: person.isFrozen
                          ? null
                          : () => _addForTab('مستندات'),
                    ),
                    _filteredList(
                      filteredDocuments,
                      docStatuses,
                      'لا توجد مستندات مطابقة للفلتر',
                      Icons.description_rounded,
                    ),
                  ],
                  // أدوية: نفس نموذج الدواء في الالتزامات الشخصية، ويُحفظ
                  // هناك في قسم الأدوية تلقائيًا.
                  if (selectedTab == 'أدوية') ...[
                    _sectionFilters(medicineStatuses),
                    AppSectionAddRow(
                      title: 'الأدوية',
                      icon: Icons.medication_outlined,
                      accent: color,
                      count: medicineRows.length,
                      onAdd: person.isFrozen ? null : _addMedicine,
                    ),
                    _filteredList(
                      medicineRows,
                      medicineStatuses,
                      'لا توجد أدوية مطابقة للفلتر',
                      Icons.medication_outlined,
                    ),
                  ],
                  if (selectedTab == 'مواقع وأماكن') ...[
                    _sectionFilters(placeStatuses),
                    AppSectionAddRow(
                      title: 'المواقع والأماكن',
                      icon: Icons.place_outlined,
                      accent: color,
                      count: placeRows.length,
                      onAdd: person.isFrozen
                          ? null
                          : () => _openPersonalForm('مواقع وأماكن'),
                    ),
                    _filteredList(
                      placeRows,
                      placeStatuses,
                      'لا توجد مواقع مضافة حتى الآن',
                      Icons.place_outlined,
                    ),
                  ],
                  ],
                ),
              ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// هيدر مدمج لصفحة تفاصيل الفرد/الجهة — مطابق تمامًا لبنية
// _CompactCommitmentHeader في قالب الالتزامات الشخصية: أيقونة 44x44 على
// اليمين، الاسم ثم النوع تحته، شارة الحالة، وقائمة الثلاث نقاط.
/// حقل تاريخ يفتح تقويمًا، ومعه زر مسح يجعل التفويض مفتوح المدة.
class _DelegationDateField extends StatelessWidget {
  const _DelegationDateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppTheme.field,
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              textAlign: AppTr.alignEnd,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 15,
                  color: Color(0xFF0A5A50),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF8C9A97),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// تبويبات فرعية داخل تبويب: مستطيلات متساوية في سطر واحد.
class _PersonSegments extends StatelessWidget {
  const _PersonSegments({
    required this.labels,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: AppTr.uiDir,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rField),
              onTap: () => onSelected(i),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == i
                      ? color.withValues(alpha: 0.12)
                      : AppTheme.field,
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Text(
                  labels[i],
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: selected == i ? color : AppTheme.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactPersonHeader extends StatelessWidget {
  const _CompactPersonHeader({
    required this.person,
    required this.color,
    required this.onAction,
    this.delegationCount = 0,
    this.onOpenDelegations,
  });

  final _PersonItem person;
  final Color color;
  final ValueChanged<ThreeDotMenuAction> onAction;

  /// عدد التفويضات السارية — صفر يعني لا وسم.
  final int delegationCount;
  final VoidCallback? onOpenDelegations;

  @override
  Widget build(BuildContext context) {
    final typeLine = _personTypeLine(person);
    return Container(
      key: const ValueKey('compact-person-header-row'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _personCardTypeIcon(person.typeKey),
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.fullName,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F1F1C),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Flexible(
                      child: Text(
                        typeLine,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5C6B68),
                        ),
                      ),
                    ),
                    if (delegationCount > 0) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onOpenDelegations,
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A5A50).withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(AppTheme.rPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            textDirection: AppTr.uiDir,
                            children: [
                              const Icon(
                                Icons.assignment_ind_outlined,
                                size: 12,
                                color: Color(0xFF0A5A50),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'مفوَّض',
                                maxLines: 3,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0A5A50),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // شارة الحالة حُذفت: الحالة تُقرأ من المتابعة والتخطيط.
          const SizedBox(width: 4),
          ThreeDotMenu(tooltip: AppTr.tr('خيارات'), onAction: onAction),
        ],
      ),
    );
  }
}

// شريط أبرز البيانات (له/عليه/المستندات) — مطابق تمامًا لبنية
// _CategoryHighlightBar (نفس الأيقونة والـ FittedBox والفواصل الرأسية).
class _PersonHighlightBar extends StatelessWidget {
  const _PersonHighlightBar({required this.person, required this.color});

  final _PersonItem person;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // ما يحتاج متابعة فعلًا، بنفس عدّاد بطاقة القائمة.
    final highlights = <(String, String, IconData)>[
      (
        'مستحقات',
        '${_dueFollowUpCount(person)}',
        Icons.account_balance_wallet_outlined,
      ),
      (
        'متابعة وتخطيط',
        '${person.openTasks}',
        Icons.event_note_outlined,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          for (var i = 0; i < highlights.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 34,
                color: color.withValues(alpha: 0.18),
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
            Expanded(child: _buildHighlightTile(highlights[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildHighlightTile((String, String, IconData) highlight) {
    final (label, value, icon) = highlight;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F1F1C),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // الكلمتان جنب بعض في سطر واحد.
        Text(
          label,
          maxLines: 3,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5C6B68),
          ),
        ),
      ],
    );
  }
}

// صف تبويبات بعرض متساوٍ — مطابق تمامًا لبنية _InlineDetailsTabs (أيقونة
// فوق نص فوق خط متحرك)، يقبل List<DetailSectionTab> مباشرة.
class _ActionShortcutCard extends StatelessWidget {
  const _ActionShortcutCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.onSecondaryTap,
    this.secondaryLabel,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Row(
        textDirection: AppTr.uiDir,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF46534F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('تنفيذ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                      ),
                    ),
                    if (onSecondaryTap != null && secondaryLabel != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: onSecondaryTap,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: BorderSide(
                            color: color.withValues(alpha: 0.45),
                          ),
                          foregroundColor: color,
                          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                        ),
                        child: Text(secondaryLabel!),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyActionState extends StatelessWidget {
  const _EmptyActionState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Text(
        message,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF5C6B68),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.hint,
    required this.onFilterTap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onFilterTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: TextField(
        controller: controller,
        textDirection: AppTr.uiDir,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
          // الحاوية أعلاه هي التي ترسم الخلفية المستديرة؛ لولا إطفاء
          // التعبئة هنا لرسمت السِمة تعبئة مربّعة الزوايا فوقها.
          filled: false,
          border: InputBorder.none,
          suffixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF5C6B68),
          ),
          prefixIcon: IconButton(
            onPressed: onFilterTap,
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF46534F)),
            tooltip: AppTr.tr('فلتر'),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _FollowupPeopleCard extends StatelessWidget {
  const _FollowupPeopleCard();

  @override
  Widget build(BuildContext context) {
    return const FollowupCenterCard(
      items: [
        FollowupCenterItem(
          label: 'وثائق منتهية',
          count: '1',
          color: Color(0xFFC4392E),
        ),
        FollowupCenterItem(
          label: 'وثائق تنتهي قريباً',
          count: '2',
          color: Color(0xFFCE8422),
        ),
        FollowupCenterItem(
          label: 'تفويضات منتهية',
          count: '1',
          color: Color(0xFF0E7161),
        ),
        FollowupCenterItem(
          label: 'بيانات ناقصة',
          count: '3',
          color: Color(0xFF0A5A50),
        ),
      ],
    );
  }
}

class _CreateTypeChoiceCard extends StatelessWidget {
  const _CreateTypeChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 142),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                height: 1.25,
                color: Color(0xFF5C6B68),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonQuickAddTile extends StatelessWidget {
  const _PersonQuickAddTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  static const Color _neutral = Color(0xFF2C3B38);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _neutral, size: 22),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center, child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _neutral,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// نسخة top-level من _typeIcon لاستخدامها داخل _PersonCard (ويدجت مستقل عن
// _PeopleManagementScreenState التي تملك الدالة الأصلية).
IconData _personCardTypeIcon(String key) {
  if (key == 'person_relative') return Icons.family_restroom_rounded;
  if (key == 'person_friend') return Icons.people_outline_rounded;
  if (key == 'person_employee') return Icons.badge_outlined;
  if (key == 'person_client') return Icons.handshake_outlined;
  if (key == 'all_people') return Icons.people_alt_outlined;
  if (key == 'all_entities') return Icons.apartment_rounded;
  if (key == 'status_near') return Icons.schedule_outlined;
  if (key == 'status_urgent') return Icons.priority_high_rounded;
  if (key == 'status_late') return Icons.warning_amber_rounded;
  if (key.startsWith('entity_')) return Icons.apartment_rounded;
  if (key == 'all') return Icons.grid_view_rounded;
  return Icons.person_outline_rounded;
}

// بطاقة القائمة — نفس بنية بطاقة الالتزام الشخصي/المشترك تماماً (بنفس
// الارتفاع والخطوط والتباعد والألوان): أيقونة 46x46 + اسم مع نقطة حالة
// صغيرة وتحته النوع + عمود "له/عليه" بعرض 108 + سهم تصفّح عند الحافة
// القائدة. مطابقة لبطاقة _CommitmentCard في قالب الالتزامات الشخصية.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final _PersonItem person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeLine = _personTypeLine(person, withRole: false);

    // البطاقة تعرض دائمًا ما يحتاج متابعة، فلا يبقى الفراغ الذي كان يظهر
    // حين لا توجد مستحقات ولا مستندات.
    final stats = <String>[
      'مستحقات تحتاج متابعة : ${_dueFollowUpCount(person)}',
      'مستندات تحتاج متابعة : ${_docsFollowUpCount(person)}',
    ];

    // بطاقة القائمة الموحَّدة نفسها المستعملة في الالتزامات الشخصية
    // والمشتركة.
    return AppEntityCard(
      icon: _personCardTypeIcon(person.typeKey),
      iconColor: person.badgeColor,
      title: person.fullName,
      // الاسم الكامل (الاسم واسم الأب والقبيلة) على سطرين عند الحاجة بدل
      // قصّه بثلاث نقاط.
      titleMaxLines: 2,
      // «أنا (الاسم)» في سطر واحد.
      titleSingleLine: person.typeKey == 'person_self',
      subtitle: typeLine,
      statusColor: person.badgeColor,
      stats: stats,
      // كل جملة في سطر واحد (يصغر الخط قليلًا إن طالت).
      statsMaxLines: 2,
      statsSingleLine: true,
      leadingBadges: [
        if (person.isPinned)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.push_pin_rounded,
              size: 13,
              color: Color(0xFFF2A93F),
            ),
          ),
        if (person.isFrozen)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.block_rounded, size: 13, color: AppTheme.muted),
          ),
      ],
      onTap: onTap,
    );
  }
}

class _DetailHeaderCard extends StatelessWidget {
  const _DetailHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F4F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9EDE8)),
      ),
      child: const Text(
        'الاسم الكامل، الاسم المختصر، الصورة، الجنس، تاريخ الميلاد، الجنسية، رقم الهوية، جواز السفر، العنوان، أرقام التواصل، البريد الإلكتروني، وسائل التواصل، جهات اتصال بديلة، التصنيف (رئيسي/فرعي)',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF04413B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.person,
    this.textDirection,
  });

  final _PersonItem person;
  /// null = اتجاه الواجهة الحالي (عربي rtl / إنجليزي ltr).
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    // الحقل غير المسجَّل يُعرض بشرطة، لا بكلمة «(اختياري)» التي تبدو قيمة.
    String detailValue(List<String> keys, {String fallback = '-'}) {
      for (final key in keys) {
        final value = person.details[key]?.trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return fallback;
    }

    final isEntity = _isEntityKind(person.typeKey);
    final isSelf = person.typeKey == 'person_self';
    final notes = person.extraNote.trim();
    final nameLabel = isEntity ? 'اسم الجهة' : 'الاسم';
    // نفس حقول نموذج «إضافة فرد/جهة» وبترتيبها، فيظهر هنا ما أُدخل هناك.
    final rows = [
      (isEntity ? 'نوع الجهة' : 'النوع', person.categoryName, Icons.category_outlined),
      (nameLabel, person.fullName, Icons.person_outline_rounded),
      // صاحب الحساب مسجّل أيضًا بصفة أخرى (مؤجر مثلًا): سجلٌّ واحد له،
      // وصفاته الأخرى هنا بدل أن يظهر في الأفراد مرتين.
      if (isSelf && person.additionalCategoryNames.isNotEmpty)
        (
          'صاحب الحساب هو أيضًا',
          person.additionalCategoryNames.map(AppTr.tr).join('، '),
          Icons.how_to_reg_outlined,
        ),
      (
        'رقم الهاتف',
        detailValue(const ['رقم الهاتف'], fallback: 'غير متوفر'),
        Icons.phone_outlined,
      ),
      (
        'البريد الإلكتروني',
        detailValue(const ['البريد الإلكتروني']),
        Icons.alternate_email_rounded,
      ),
      if (!isEntity)
        ('الجنسية', detailValue(const ['الجنسية']), Icons.flag_outlined),
      (
        isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد',
        detailValue([isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد']),
        Icons.cake_outlined,
      ),
      ('العنوان', detailValue(const ['العنوان']), Icons.signpost_outlined),
      (
        'موقعك ومكانك',
        detailValue(const ['الموقع على الخريطة']),
        Icons.place_outlined,
      ),
      if (!isSelf)
        (
          'تصنيفات إضافية',
          person.additionalCategoryNames.isEmpty
              ? '-'
              : person.additionalCategoryNames.join('، '),
          Icons.label_outline_rounded,
        ),
      (
        'ملاحظات',
        notes.isEmpty || notes == 'بانتظار استكمال البيانات' ? '-' : notes,
        Icons.notes_rounded,
      ),
      (
        'معلومات إضافية',
        detailValue(const ['معلومات إضافية']),
        Icons.info_outline_rounded,
      ),
      // الوثائق الرسمية: الرقم وتاريخ الانتهاء في سطر واحد.
      if (!isEntity)
        for (final doc in _IdentityDoc.all)
          (
            doc.title,
            () {
              final number = person.details[doc.numberKey]?.trim() ?? '';
              final expiry = person.details[doc.expiryKey]?.trim() ?? '';
              if (number.isEmpty && expiry.isEmpty) return '-';
              if (expiry.isEmpty) return number;
              if (number.isEmpty) return 'ينتهي $expiry';
              return '$number · ينتهي $expiry';
            }(),
            doc.icon,
          ),
      if (isEntity)
        (
          'وثائق الجهة',
          person.documents.isEmpty ? '-' : person.documents.join('، '),
          Icons.folder_outlined,
        ),
    ];

    // نفس بطاقة تفاصيل الالتزام الشخصي بالضبط: بطاقة رمادية واحدة، وصفوف
    // يفصلها خط أبيض رفيع. كانت هنا بطاقة متدرّجة بحدّ زرقاء وظل، وكل صف
    // فيها صندوق رمادي مستقل — شكل لا يشبه أي صفحة تفاصيل أخرى.
    return AppDetailsCard(
      title: 'بطاقة الملخص',
      icon: Icons.badge_outlined,
      color: const Color(0xFF0E7161),
      children: [
        // شريط الأرقام (المستحق له/عليه، المهام، المستندات) حُذف من ذيل
        // الملخص: نفس الأرقام تظهر في شريط أبرز البيانات وفي تبويب مالية.
        for (final row in rows)
          if (row.$1 == nameLabel)
            // الاسم في سطر واحد، واتجاهه من حروفه: العربي من اليمين،
            // واللاتيني من اليسار.
            AppDetailRow(
              label: row.$1,
              value: row.$2,
              icon: row.$3,
              singleLine: true,
              valueDirection: _nameDirection(row.$2),
            )
          else
            AppDetailRow(label: row.$1, value: row.$2, icon: row.$3),
      ],
    );
  }

  /// اتجاه الاسم من أول حرف فيه (بعد «أنا (…)» في سجل صاحب الحساب).
  static TextDirection _nameDirection(String name) {
    var core = name.trim();
    final self = RegExp(r'^أنا\s*\((.*)\)$').firstMatch(core);
    if (self != null) core = self.group(1)!.trim();
    for (final rune in core.runes) {
      final arabic = (rune >= 0x0600 && rune <= 0x08FF) ||
          (rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF);
      if (arabic) return TextDirection.rtl;
      final latin = (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0xC0 && rune <= 0x24F);
      if (latin) return TextDirection.ltr;
    }
    return AppTr.uiDir;
  }
}

class _SubSectionsPanel extends StatelessWidget {
  const _SubSectionsPanel();

  @override
  Widget build(BuildContext context) {
    final blocks = [
      (
        'المهام والأعمال',
        'المهام الحالية، المهام المنجزة، المهام المتأخرة، طلبات بانتظار التنفيذ، الأعمال المتكررة، سجل الإنجازات',
      ),
      (
        'العلاقات والارتباطات',
        'أفراد الأسرة، الكفيل، المكفولين، الشركات التابعة له، العقارات المرتبط بها، الالتزامات المشتركة، التفويضات، المحافظ',
      ),
      (
        'المالية',
        'مستحقات له، مستحقات عليه، ديون وسلف، عهد، مصروفات وإيرادات، دفعات مستلمة، دفعات مدفوعة، الضمانات المالية',
      ),
      (
        'المستندات والتفويضات والمواعيد',
        'الهوية والجواز، الرخص والعقود، الشهادات والفواتير، الضمانات، مواعيد وتجديدات، مفوض له/منه، سجل التفويضات',
      ),
    ];

    return Column(
      children: blocks
          .map((block) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      block.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      block.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF46534F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _DynamicLinkedDataCard extends StatelessWidget {
  const _DynamicLinkedDataCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.emptyText,
    required this.items,
    this.textDirection,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String emptyText;
  final List<String> items;
  /// null = اتجاه الواجهة الحالي (عربي rtl / إنجليزي ltr).
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final isRtl = (textDirection ?? AppTr.uiDir) == TextDirection.rtl;
    final textAlign = isRtl ? TextAlign.right : TextAlign.left;
    // ملاحظة: CrossAxisAlignment.start يُحلّ أصلًا إلى اليمين داخل اتجاه
    // rtl. الشرط السابق (isRtl ? end : start) كان يعكسه مرتين فيُحاذي كل
    // عناوين البطاقات وقيمها إلى اليسار داخل بطاقة عربية.
    const crossAxis = CrossAxisAlignment.start;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          Row(
            textDirection: textDirection ?? AppTr.uiDir,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  textAlign: textAlign,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF022E2A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              emptyText,
              textAlign: textAlign,
              style: const TextStyle(color: Color(0xFF5C6B68), fontSize: 11),
            )
          else
            ...items
                .take(8)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      textDirection: textDirection ?? AppTr.uiDir,
                      children: [
                        Icon(Icons.circle, size: 6, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            textAlign: textAlign,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2C3B38),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _AlertSectionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'التنبيهات',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF022E2A),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'تنبيهات مالية: دفعة متأخرة، قسط مستحق',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF2C3B38)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات زمنية: مهمة متأخرة، موعد قريب',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF2C3B38)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات مستندات وأشخاص: مستند منتهي، بيانات ناقصة',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF2C3B38)),
          ),
        ],
      ),
    );
  }
}

/// حدث واحد في سجل الفرد.
/// شارة حالة سند القبض بنفس ألوان صفحة سندات القبض: معتمد أخضر، مرفوض
/// أحمر، بانتظار الاعتماد برتقالي.
Widget _salaryStatusPill(String status) {
  final color = switch (status) {
    SalaryReceipt.statusApproved => const Color(0xFF178F7B),
    SalaryReceipt.statusRejected => AppTheme.danger,
    _ => const Color(0xFFA6691A),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppTheme.rPill),
    ),
    child: Text(
      status,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    ),
  );
}

class _PersonLogEvent {
  const _PersonLogEvent({
    required this.kind,
    required this.title,
    this.detail = '',
    this.date,
    this.amount = 0,
    this.currency = '',
    this.due = false,
    this.icon = Icons.history_rounded,
    this.onTap,
    this.salary = false,
    this.status = '',
  });

  /// سند قبض راتب (لفلتر «الرواتب / غير الرواتب» تحت «مالية»).
  final bool salary;

  /// حالة تُعرض شارة ملوّنة بلون الحالة في التطبيق (معتمد أخضر...).
  final String status;

  /// مالية / متابعة وتخطيط / مستندات / تفويضات / أخرى.
  final String kind;
  final String title;
  final String detail;
  final DateTime? date;
  final double amount;
  final String currency;

  /// مبلغ عليه (أحمر).
  final bool due;
  final IconData icon;
  final VoidCallback? onTap;
}

class _HorizontalTabs extends StatelessWidget {
  const _HorizontalTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    this.startFromLeft = false,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool startFromLeft;

  @override
  Widget build(BuildContext context) {
    final textDirection = startFromLeft ? TextDirection.ltr : AppTr.uiDir;

    return Directionality(
      textDirection: textDirection,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFE9F4F1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF0A5A50), width: 1.2),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          reverse: false,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: tabs.length,
          itemBuilder: (context, index) {
            final isSelected = index == selectedIndex;
            return InkWell(
              onTap: () => onTap(index),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsetsDirectional.only(start: 14),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? const Color(0xFF0F1F1C)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: const Color(0xFF0F1F1C),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TypeFilterDef {
  const _TypeFilterDef(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0xFFF7FAF9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : const Color(0xFFE4EAE8)),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF2C3B38),
          ),
        ),
      ),
    );
  }
}

class _ActionGroup {
  const _ActionGroup(this.title, this.color, this.actions);

  final String title;
  final Color color;
  final List<_ActionTemplate> actions;
}

class _ActionTemplate {
  const _ActionTemplate(this.title, this.fields);

  final String title;
  final List<_FieldDef> fields;
}

class _FieldDef {
  const _FieldDef(
    this.label,
    this.isNumeric, {
    this.isDate = false,
    this.options,
  });

  final String label;
  final bool isNumeric;
  final bool isDate;
  final List<String>? options;
}

const _expiryDateField = _FieldDef('تاريخ الانتهاء', false, isDate: true);

const _expiryReminderField = _FieldDef(
  'التذكير قبل الانتهاء',
  false,
  options: ['قبل أسبوع', 'قبل يوم', 'قبل 3 أيام', 'قبل أسبوعين', 'قبل شهر'],
);

class _PersonItem {
  _PersonItem({
    required this.fullName,
    required this.nickName,
    required this.roleTitle,
    required this.badge,
    required this.badgeColor,
    required this.statusNote,
    required this.extraNote,
    required this.typeKey,
    required this.categoryName,
    required this.dueToYou,
    required this.dueOnYou,
    required this.openTasks,
    required this.documentsCount,
    required this.lastUpdate,
    required this.createdAt,
    required this.sharedCommitments,
    required this.documents,
    this.details = const {},
    this.isPinned = false,
    this.isFrozen = false,
    // تصنيفات فرعية إضافية (بجانب التصنيف الرئيسي categoryName) — لدعم حالة
    // "قريب + مستأجر + مورد" التي وردت كسؤال مفتوح في ملف المتطلبات، بقرار
    // المستخدم بالسماح بأكثر من تصنيف لنفس الفرد/الجهة.
    this.additionalCategoryNames = const [],
    // سجل زمني لكل ما أُضيف من نافذة "+ إضافة" (يظهر في تبويب "السجل")،
    // بنفس فكرة "سجّل كل شيء أضيف عند + إضافة" الواردة في ملف المتطلبات.
    this.activityLog = const [],
  });

  final String fullName;
  final String nickName;
  final String roleTitle;
  final String badge;
  final Color badgeColor;
  final String statusNote;
  final String extraNote;
  final String typeKey;
  final String categoryName;
  final List<String> additionalCategoryNames;
  final List<String> activityLog;
  final int dueToYou;
  final int dueOnYou;
  final int openTasks;
  final int documentsCount;
  final String lastUpdate;
  final String createdAt;
  final List<String> sharedCommitments;
  final List<String> documents;
  final Map<String, String> details;
  final bool isPinned;
  final bool isFrozen;

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'nickName': nickName,
      'roleTitle': roleTitle,
      'badge': badge,
      'badgeColor': badgeColor.value,
      'statusNote': statusNote,
      'extraNote': extraNote,
      'typeKey': typeKey,
      'categoryName': categoryName,
      'additionalCategoryNames': additionalCategoryNames,
      'activityLog': activityLog,
      'dueToYou': dueToYou,
      'dueOnYou': dueOnYou,
      'openTasks': openTasks,
      'documentsCount': documentsCount,
      'lastUpdate': lastUpdate,
      'createdAt': createdAt,
      'sharedCommitments': sharedCommitments,
      'documents': documents,
      'details': details,
      'isPinned': isPinned,
      'isFrozen': isFrozen,
    };
  }

  factory _PersonItem.fromMap(Map<String, dynamic> map) {
    final detailsMap = <String, String>{};
    final rawDetails = map['details'];
    if (rawDetails is Map) {
      rawDetails.forEach((key, value) {
        detailsMap['$key'] = '${value ?? ''}';
      });
    }

    final rawShared = map['sharedCommitments'];
    final rawDocuments = map['documents'];
    final rawAdditionalCategories = map['additionalCategoryNames'];
    final rawActivityLog = map['activityLog'];

    return _PersonItem(
      fullName: map['fullName']?.toString() ?? '',
      nickName: map['nickName']?.toString() ?? '',
      roleTitle: map['roleTitle']?.toString() ?? '',
      badge: map['badge']?.toString() ?? '',
      badgeColor: Color((map['badgeColor'] as num?)?.toInt() ?? 0xFF5C6B68),
      statusNote: map['statusNote']?.toString() ?? '',
      extraNote: map['extraNote']?.toString() ?? '',
      typeKey: map['typeKey']?.toString() ?? 'person_other',
      categoryName: map['categoryName']?.toString() ?? 'أخرى',
      additionalCategoryNames: rawAdditionalCategories is List
          ? rawAdditionalCategories.map((e) => '$e').toList(growable: false)
          : const [],
      activityLog: rawActivityLog is List
          ? rawActivityLog.map((e) => '$e').toList(growable: false)
          : const [],
      dueToYou: (map['dueToYou'] as num?)?.toInt() ?? 0,
      dueOnYou: (map['dueOnYou'] as num?)?.toInt() ?? 0,
      openTasks: (map['openTasks'] as num?)?.toInt() ?? 0,
      documentsCount: (map['documentsCount'] as num?)?.toInt() ?? 0,
      lastUpdate: map['lastUpdate']?.toString() ?? '',
      createdAt: map['createdAt']?.toString() ?? '',
      sharedCommitments: rawShared is List
          ? rawShared.map((e) => '$e').toList(growable: false)
          : const [],
      documents: rawDocuments is List
          ? rawDocuments.map((e) => '$e').toList(growable: false)
          : const [],
      details: detailsMap,
      isPinned: map['isPinned'] == true,
      isFrozen: map['isFrozen'] == true,
    );
  }

  _PersonItem copyWith({
    String? fullName,
    String? nickName,
    String? roleTitle,
    String? badge,
    Color? badgeColor,
    String? statusNote,
    String? extraNote,
    String? typeKey,
    String? categoryName,
    List<String>? additionalCategoryNames,
    List<String>? activityLog,
    int? dueToYou,
    int? dueOnYou,
    int? openTasks,
    int? documentsCount,
    String? lastUpdate,
    String? createdAt,
    List<String>? sharedCommitments,
    List<String>? documents,
    Map<String, String>? details,
    bool? isPinned,
    bool? isFrozen,
  }) {
    return _PersonItem(
      fullName: fullName ?? this.fullName,
      nickName: nickName ?? this.nickName,
      roleTitle: roleTitle ?? this.roleTitle,
      badge: badge ?? this.badge,
      badgeColor: badgeColor ?? this.badgeColor,
      statusNote: statusNote ?? this.statusNote,
      extraNote: extraNote ?? this.extraNote,
      typeKey: typeKey ?? this.typeKey,
      categoryName: categoryName ?? this.categoryName,
      additionalCategoryNames:
          additionalCategoryNames ?? this.additionalCategoryNames,
      activityLog: activityLog ?? this.activityLog,
      dueToYou: dueToYou ?? this.dueToYou,
      dueOnYou: dueOnYou ?? this.dueOnYou,
      openTasks: openTasks ?? this.openTasks,
      documentsCount: documentsCount ?? this.documentsCount,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      createdAt: createdAt ?? this.createdAt,
      sharedCommitments: sharedCommitments ?? this.sharedCommitments,
      documents: documents ?? this.documents,
      details: details ?? this.details,
      isPinned: isPinned ?? this.isPinned,
      isFrozen: isFrozen ?? this.isFrozen,
    );
  }

  _PersonItem copyWithDocument(String document) {
    return _PersonItem(
      fullName: fullName,
      nickName: nickName,
      roleTitle: roleTitle,
      badge: badge,
      badgeColor: badgeColor,
      statusNote: statusNote,
      extraNote: extraNote,
      typeKey: typeKey,
      categoryName: categoryName,
      additionalCategoryNames: additionalCategoryNames,
      activityLog: activityLog,
      dueToYou: dueToYou,
      dueOnYou: dueOnYou,
      openTasks: openTasks,
      documentsCount: documentsCount + 1,
      lastUpdate: _todayStamp(),
      createdAt: createdAt,
      sharedCommitments: sharedCommitments,
      documents: [...documents, document],
      details: details,
      isPinned: isPinned,
      isFrozen: isFrozen,
    );
  }
}
