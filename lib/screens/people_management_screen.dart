import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_settings.dart';
import '../data/app_reminders_store.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/followup_center_card.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/app_filter_sheet.dart';
import '../widgets/shared/followup_center_sheet.dart';
import 'smart_calendar_screen.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';

/// تاريخ اليوم بصيغة d/M/yyyy — تُخزَّن التواريخ كنص بهذه الصيغة في سجلات
/// الأشخاص. كانت تُكتب سابقًا بالكلمة الثابتة 'اليوم'، فيظل سجل أُنشئ قبل
/// أشهر يعرض "اليوم"، والأسوأ أن الترتيب كان يقارن هذه النصوص حرفيًا.
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

class PeopleManagementScreen extends StatefulWidget {
  const PeopleManagementScreen({super.key});

  @override
  State<PeopleManagementScreen> createState() => _PeopleManagementScreenState();
}

class _PeopleManagementScreenState extends State<PeopleManagementScreen> {
  static const _peopleStorageKey = 'people_management_records_v1';

  final TextEditingController _searchController = TextEditingController();
  String _selectedScopeKey = 'scope_all';
  String _selectedTypeKey = 'all';
  String _selectedSort = 'الأحدث أولاً';

  late final List<_PersonItem> _people = _seedPeople();

  List<_PersonItem> _seedPeople() => [
    _PersonItem(
      fullName: 'أحمد محمد سالم',
      nickName: 'سليم',
      roleTitle: 'سائق خاص',
      badge: 'متابعة',
      badgeColor: const Color(0xFF0EA5E9),
      statusNote: 'مستند ينتهي خلال 10 أيام',
      extraNote: 'مفوّض (بناية الشامخة)',
      typeKey: 'person_employee',
      categoryName: 'موظف',
      dueToYou: 0,
      dueOnYou: 120,
      openTasks: 1,
      documentsCount: 4,
      lastUpdate: '2/5/2025',
      createdAt: '8/8/2024',
      sharedCommitments: ['رحلة دبي', 'اشتراك السكن'],
      documents: ['إقامة', 'عقد عمل', 'رخصة قيادة'],
      details: {
        'رقم الهاتف': '0501234567',
        'الجنسية': 'سعودي',
        'تاريخ الميلاد': '14/9/1991',
      },
    ),
    _PersonItem(
      fullName: 'راشد خالد',
      nickName: 'يحتاج متابعة',
      roleTitle: 'محاسب',
      badge: 'تنبيه',
      badgeColor: const Color(0xFFF59E0B),
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
        'رقم الهاتف': '0559876543',
        'الجنسية': 'سعودي',
        'تاريخ الميلاد': '2/3/1988',
      },
    ),
    _PersonItem(
      fullName: 'محمد سالم',
      nickName: 'عاجل',
      roleTitle: 'فني كهرباء',
      badge: 'عاجل',
      badgeColor: const Color(0xFFE11D48),
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
        'رقم الهاتف': '0532221144',
        'الجنسية': 'يمني',
        'تاريخ الميلاد': '20/1/1994',
      },
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPeople();
  }

  void _openSmartCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SmartCalendarScreen()));
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

  final List<_TypeFilterDef> _allTypeFilters = const [
    _TypeFilterDef('all', 'الكل', Color(0xFF0B3A78)),
    _TypeFilterDef('person_relative', 'قريب', Color(0xFF0F6AA8)),
    _TypeFilterDef('person_friend', 'صديق', Color(0xFF10B981)),
    _TypeFilterDef('person_employee', 'موظف', Color(0xFFF59E0B)),
    _TypeFilterDef('person_client', 'عميل', Color(0xFF2563EB)),
    _TypeFilterDef('person_tenant', 'مستأجر', Color(0xFFEC4899)),
    _TypeFilterDef('person_supplier', 'مورد', Color(0xFFEA580C)),
    _TypeFilterDef('person_contractor', 'مقاول', Color(0xFF7C3AED)),
    _TypeFilterDef('person_partner', 'شريك', Color(0xFF16A34A)),
    _TypeFilterDef('person_landlord', 'مؤجر', Color(0xFF0891B2)),
    _TypeFilterDef('person_representative', 'مندوب', Color(0xFF0284C7)),
    _TypeFilterDef('person_consultant', 'استشاري', Color(0xFF4F46E5)),
    _TypeFilterDef('person_other', 'أخرى', Color(0xFF64748B)),
    _TypeFilterDef('entity_company', 'الشركات', Color(0xFF0F6AA8)),
    _TypeFilterDef('entity_government', 'جهات حكومية', Color(0xFF2563EB)),
    _TypeFilterDef('entity_bank', 'بنك', Color(0xFF10B981)),
    _TypeFilterDef('entity_education', 'مؤسسات تعليمية', Color(0xFFF59E0B)),
    _TypeFilterDef('entity_health', 'مؤسسات صحية', Color(0xFFEC4899)),
    _TypeFilterDef('entity_organization', 'منظمات', Color(0xFF7C3AED)),
    _TypeFilterDef('entity_other', 'جهات أخرى', Color(0xFF64748B)),
  ];

  List<_TypeFilterDef> _createTypeFilters(bool isEntity) {
    return _allTypeFilters
        .where(
          (filter) =>
              filter.key != 'all' &&
              (isEntity
                  ? filter.key.startsWith('entity_')
                  : filter.key.startsWith('person_')),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _countByType(String key) {
    if (key == 'all') return _people.length;
    if (key == 'all_people') {
      return _people.where((person) => _isPersonType(person.typeKey)).length;
    }
    if (key == 'all_entities') {
      return _people.where((person) => _isEntityType(person.typeKey)).length;
    }
    if (key.startsWith('status_')) {
      return _people
          .where((person) => _isPersonType(person.typeKey))
          .where((person) => _matchesPeopleStatusFilter(person, key))
          .length;
    }
    return _people.where((person) => person.typeKey == key).length;
  }

  int _countByScope(String scopeKey) {
    if (scopeKey == 'scope_people') {
      return _people.where((person) => _isPersonType(person.typeKey)).length;
    }
    if (scopeKey == 'scope_entities') {
      return _people.where((person) => _isEntityType(person.typeKey)).length;
    }
    return _people.length;
  }

  bool _isPersonType(String key) => key.startsWith('person_');

  bool _isEntityType(String key) => key.startsWith('entity_');

  bool _matchesPeopleStatusFilter(_PersonItem person, String statusKey) {
    final status = '${person.badge} ${person.nickName} ${person.statusNote}';
    return switch (statusKey) {
      'status_near' =>
        status.contains('قريب') ||
            status.contains('ينتهي خلال') ||
            status.contains('قارب'),
      'status_urgent' =>
        status.contains('مستعجل') ||
            status.contains('عاجل') ||
            status.contains('تنبيه'),
      'status_late' =>
        status.contains('متأخر') ||
            status.contains('منتهي') ||
            status.contains('متأخرة'),
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
      ..._createTypeFilters(
        isEntity,
      ).map((filter) => build(filter.key, filter.label, _typeIcon(filter.key))),
    ];
  }

  /// قيم الفلتر الرئيسي — نفس البنية في الشاشات الأربع.
  final AppFilterValues _filter = AppFilterValues();

  bool _matchesAdvancedPeopleFilters(_PersonItem person) {
    switch (_filter.status) {
      case 'نشط':
        if (person.isFrozen) return false;
      case 'المستحق بعد 7 أيام':
        if (person.openTasks <= 0) return false;
      case 'متأخر':
        if (!person.statusNote.contains('متأخر') &&
            !person.badge.contains('عاجل')) {
          return false;
        }
      case 'مكتمل':
        if (person.openTasks > 0) return false;
      case 'ملغاة':
        if (!person.badge.contains('ملغا')) return false;
      case 'مؤرشف':
        if (!person.isFrozen) return false;
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

  List<_PersonItem> _filteredPeople() {
    final query = _searchController.text.trim();

    final filtered = _people.where((person) {
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

    // الفلتر الصغير يُقدّم المطابق ولا يُخفي غيره.
    int rank(_PersonItem person) {
      switch (_selectedSort) {
        case 'نشط':
          return person.isFrozen ? 1 : 0;
        case 'مستندات قريبة الإنتهاء':
          return person.statusNote.contains('قريب') &&
                  person.statusNote.contains('مستند')
              ? 0
              : 1;
        case 'مستندات منتهية':
          return person.statusNote.contains('منته') &&
                  person.statusNote.contains('مستند')
              ? 0
              : 1;
        default:
          return 0;
      }
    }

    filtered.sort((a, b) {
      final pinned = byPinned(a, b);
      if (pinned != 0) return pinned;
      // "أعلى مستحقات" من الفلتر الكبير يتقدّم على ترتيب الفلتر الصغير.
      if (_filter.amountShortcut == 'أعلى مستحقات') {
        final byDue = (b.dueToYou + b.dueOnYou).compareTo(
          a.dueToYou + a.dueOnYou,
        );
        if (byDue != 0) return byDue;
      }
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return _parsePersonDate(
        b.lastUpdate,
      ).compareTo(_parsePersonDate(a.lastUpdate));
    });
    return filtered;
  }

  List<_PersonItem> _peopleForSelectedType() {
    if (_selectedScopeKey == 'scope_people') {
      return _people.where((person) => _isPersonType(person.typeKey)).toList();
    }
    if (_selectedScopeKey == 'scope_entities') {
      return _people.where((person) => _isEntityType(person.typeKey)).toList();
    }
    return List.of(_people);
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
      const _TypeFilterDef('status_near', 'قريب الانتهاء', Color(0xFF0284C7)),
      const _TypeFilterDef('status_urgent', 'مستعجل', Color(0xFFD97706)),
      const _TypeFilterDef('status_late', 'متأخر', Color(0xFFDC2626)),
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
  void _openFollowUpSheet(List<_PersonItem> people) {
    FollowUpEntry entryFor(_PersonItem person, String trailing) => FollowUpEntry(
      title: person.fullName,
      subtitle: person.categoryName,
      icon: person.typeKey == 'entity'
          ? Icons.apartment_rounded
          : Icons.person_outline_rounded,
      color: person.badgeColor,
      trailingText: trailing,
      onTap: () => _openPersonDetails(person),
    );

    showFollowUpCenterSheet(
      context: context,
      accent: const Color(0xFF7C3AED),
      groups: [
        FollowUpGroup(
          title: 'المستحقات',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF07835C),
          metrics: [
            FollowUpMetric(
              label: 'مستحقات لك',
              icon: Icons.call_received_rounded,
              entries: [
                for (final person in people.where((p) => p.dueToYou > 0))
                  entryFor(
                    person,
                    '${person.dueToYou} ${AppSettings.currencySuffix}',
                  ),
              ],
            ),
            FollowUpMetric(
              label: 'مستحقات عليك',
              icon: Icons.call_made_rounded,
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
          title: 'المهام',
          icon: Icons.task_alt_rounded,
          color: const Color(0xFFB56A09),
          metrics: [
            FollowUpMetric(
              label: 'مهام مفتوحة',
              icon: Icons.pending_actions_outlined,
              entries: [
                for (final person in people.where((p) => p.openTasks > 0))
                  entryFor(person, '${person.openTasks}'),
              ],
            ),
          ],
        ),
        FollowUpGroup(
          title: 'المستندات',
          icon: Icons.folder_outlined,
          color: const Color(0xFF0F6AA8),
          metrics: [
            FollowUpMetric(
              label: 'وثائق للمتابعة',
              icon: Icons.description_outlined,
              entries: [
                for (final person in people.where(
                  (p) => p.statusNote.contains('مستند'),
                ))
                  entryFor(person, person.statusNote),
              ],
            ),
            FollowUpMetric(
              label: 'بلا مستندات',
              icon: Icons.folder_off_outlined,
              entries: [
                for (final person in people.where((p) => p.documentsCount == 0))
                  entryFor(person, '0'),
              ],
            ),
          ],
        ),
        FollowUpGroup(
          title: 'الحالة',
          icon: Icons.flag_outlined,
          color: const Color(0xFFC73E4D),
          metrics: [
            FollowUpMetric(
              label: 'مجمّدة',
              icon: Icons.ac_unit_rounded,
              entries: [
                for (final person in people.where((p) => p.isFrozen))
                  entryFor(person, 'مجمّد'),
              ],
            ),
            FollowUpMetric(
              label: 'مثبّتة',
              icon: Icons.push_pin_outlined,
              entries: [
                for (final person in people.where((p) => p.isPinned))
                  entryFor(person, 'مثبّت'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _openPersonDetails(_PersonItem person) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailsScreen(
          person: person,
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
      accent: const Color(0xFF7C3AED),
      values: _filter
        ..mainCategory = _selectedScopeKey == 'scope_entities'
            ? 'جهات'
            : _selectedScopeKey == 'scope_people'
            ? 'أفراد'
            : 'الكل',
      mainCategories: const ['الكل', 'أفراد', 'جهات'],
      subCategoriesFor: (main) => main == 'أفراد'
          ? _allTypeFilters
                .where((filter) => filter.key.startsWith('person_'))
                .map((filter) => filter.label)
                .toList(growable: false)
          : main == 'جهات'
          ? _allTypeFilters
                .where((filter) => filter.key.startsWith('entity_'))
                .map((filter) => filter.label)
                .toList(growable: false)
          : const <String>[],
      // بلا مدخل "الكل": القالب يضيف رقاقة "الكل" بنفسه، فكانت تظهر مرتين
      // والثانية تُفلتر على تصنيف اسمه "الكل" فلا يطابق أحدًا.
      personCategories: _allTypeFilters
          .where((filter) => filter.key != 'all')
          .map((filter) => filter.label)
          .toList(growable: false),
      documentStates: const [],
      amountShortcuts: const ['لي', 'عليّ', 'أعلى مستحقات'],
      sections: const [
        AppFilterSection.mainCategory,
        AppFilterSection.subCategory,
        AppFilterSection.people,
        AppFilterSection.delegates,
        AppFilterSection.date,
        AppFilterSection.status,
        AppFilterSection.amount,
        AppFilterSection.document,
        AppFilterSection.place,
      ],
      onApply: (values) => setState(() {
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
        _filter
          ..mainCategory = values.mainCategory
          ..subCategory = values.subCategory
          ..dateFrom = values.dateFrom
          ..dateTo = values.dateTo
          ..status = values.status
          ..amountFrom = values.amountFrom
          ..amountTo = values.amountTo
          ..amountShortcut = values.amountShortcut
          ..documentName = values.documentName
          ..documentState = values.documentState
          ..personName = values.personName
          ..personCategory = values.personCategory
          ..delegateName = values.delegateName
          ..placeName = values.placeName;
      }),
    );
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
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(99),
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
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'اختر النوع لإظهار الإدخالات والفئات المناسبة',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
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
                      Expanded(
                        child: _CreateTypeChoiceCard(
                          title: 'إضافة شخص',
                          subtitle: 'أفراد وعائلة وموظفون',
                          icon: Icons.person_add_alt_1_rounded,
                          color: const Color(0xFF0F6AA8),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Future<void>.delayed(
                              Duration.zero,
                              () => _openCreateActionsSheet(isEntity: false),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CreateTypeChoiceCard(
                          title: 'إضافة جهة',
                          subtitle: 'شركات ومؤسسات وجهات',
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF7C3AED),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Future<void>.delayed(
                              Duration.zero,
                              () => _openCreateActionsSheet(isEntity: true),
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

  void _openCreateActionsSheet({required bool isEntity}) {
    final typeFilters = _createTypeFilters(isEntity);
    final documentTypes = isEntity
        ? const ['عقود', 'رخص تجارية', 'مستندات مالية']
        : const ['الهوية', 'جواز السفر', 'رخصة القيادة', 'صور', 'ملفات أخرى'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEntity ? 'إدخالات الجهات' : 'إدخالات الأشخاص',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'اختر التصنيف أو الإجراء المطلوب',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _CreateActionSection(
                        title: 'إضافة تواصل',
                        icon: Icons.person_add_alt_1_rounded,
                        color: const Color(0xFF0F6AA8),
                        actions: typeFilters
                            .map(
                              (filter) => _CreateActionItem(
                                label: filter.label,
                                icon: isEntity
                                    ? Icons.apartment_rounded
                                    : Icons.person_outline_rounded,
                                color: filter.color,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  Future<void>.delayed(
                                    Duration.zero,
                                    () => _openContactFormSheet(
                                      isEntity: isEntity,
                                      type: filter,
                                    ),
                                  );
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      _CreateActionSection(
                        title: 'إضافة مستند',
                        icon: Icons.description_outlined,
                        color: const Color(0xFF7C3AED),
                        actions: documentTypes
                            .map(
                              (documentType) => _CreateActionItem(
                                label: documentType,
                                icon: Icons.description_outlined,
                                color: const Color(0xFF7C3AED),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  Future<void>.delayed(
                                    Duration.zero,
                                    () => _openDocumentFormSheet(
                                      isEntity: isEntity,
                                      documentType: documentType,
                                    ),
                                  );
                                },
                              ),
                            )
                            .toList(growable: false),
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

  void _openContactFormSheet({
    required bool isEntity,
    required _TypeFilterDef type,
  }) {
    final controllers = <String, TextEditingController>{
      'name': TextEditingController(),
      'phone': TextEditingController(),
      'email': TextEditingController(),
      'birthday': TextEditingController(),
      'address': TextEditingController(),
      'notes': TextEditingController(),
      'extra': TextEditingController(),
      'location': TextEditingController(),
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // تصنيفات فرعية إضافية يمكن اختيار أكثر من واحدة منها (بجانب
        // التصنيف الرئيسي "type" الذي تم اختياره في الخطوة السابقة) — لدعم
        // حالة الفرد/الجهة الذي له أكثر من تصنيف في نفس الوقت.
        final additionalOptions = _createTypeFilters(
          isEntity,
        ).where((option) => option.key != type.key).toList(growable: false);
        final selectedAdditional = <String>{};
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                  textDirection: TextDirection.rtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${isEntity ? 'إضافة جهة' : 'إضافة شخص'} · ${type.label}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            _inputField(
                              controllers['name']!,
                              isEntity ? 'اسم الجهة' : 'الاسم',
                            ),
                            const SizedBox(height: 9),
                            _inputField(controllers['phone']!, 'رقم الهاتف'),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['email']!,
                              'البريد الإلكتروني',
                            ),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['birthday']!,
                              isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد',
                            ),
                            const SizedBox(height: 9),
                            _inputField(controllers['address']!, 'العنوان'),
                            const SizedBox(height: 9),
                            _inputField(
                              controllers['location']!,
                              'الموقع على الخريطة',
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
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                textDirection: TextDirection.rtl,
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          final name = controllers['name']!.text.trim();
                          if (name.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('أدخل الاسم أولاً'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
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
                            documentsCount: 0,
                            lastUpdate: _todayStamp(),
                            createdAt: _todayStamp(),
                            sharedCommitments: const [],
                            documents: const [],
                            details: {
                              'رقم الهاتف': controllers['phone']!.text.trim(),
                              'البريد الإلكتروني': controllers['email']!.text
                                  .trim(),
                              isEntity ? 'تاريخ التأسيس' : 'تاريخ الميلاد':
                                  controllers['birthday']!.text.trim(),
                              'العنوان': controllers['address']!.text.trim(),
                              'الموقع على الخريطة': controllers['location']!
                                  .text
                                  .trim(),
                              'معلومات إضافية': controllers['extra']!.text
                                  .trim(),
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
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isEntity ? 'حفظ الجهة' : 'حفظ الشخص'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4A73),
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

  void _openDocumentFormSheet({
    required bool isEntity,
    required String documentType,
  }) {
    final ownerController = TextEditingController();
    final numberController = TextEditingController();
    final dateController = TextEditingController();
    final notesController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إضافة مستند · $documentType',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _inputField(
                    ownerController,
                    isEntity ? 'اسم الجهة' : 'اسم الشخص',
                  ),
                  const SizedBox(height: 9),
                  _inputField(numberController, 'رقم المستند أو المرجع'),
                  const SizedBox(height: 9),
                  _inputField(dateController, 'تاريخ الانتهاء'),
                  const SizedBox(height: 9),
                  _inputField(notesController, 'ملاحظات'),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      final owner = ownerController.text.trim();
                      if (owner.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('أدخل اسم صاحب المستند أولاً'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      final description = numberController.text.trim().isEmpty
                          ? documentType
                          : '$documentType · ${numberController.text.trim()}';
                      setState(() {
                        final index = _people.indexWhere(
                          (person) => person.fullName == owner,
                        );
                        if (index >= 0) {
                          _people[index] = _people[index].copyWithDocument(
                            description,
                          );
                        } else {
                          _people.insert(
                            0,
                            _PersonItem(
                              fullName: owner,
                              nickName: isEntity ? 'جهة جديدة' : 'جديد',
                              roleTitle: isEntity ? 'جهة' : 'غير محدد',
                              badge: 'جديد',
                              badgeColor: const Color(0xFF7C3AED),
                              statusNote: 'تمت إضافة مستند',
                              extraNote: notesController.text.trim(),
                              typeKey: isEntity
                                  ? 'entity_other'
                                  : 'person_other',
                              categoryName: isEntity ? 'جهات أخرى' : 'أخرى',
                              dueToYou: 0,
                              dueOnYou: 0,
                              openTasks: 0,
                              documentsCount: 1,
                              lastUpdate: _todayStamp(),
                              createdAt: _todayStamp(),
                              sharedCommitments: const [],
                              documents: [description],
                              details: {
                                'تاريخ الانتهاء': dateController.text.trim(),
                              },
                            ),
                          );
                        }
                        _selectedTypeKey = 'all';
                        _selectedScopeKey = 'scope_all';
                      });
                      // يُبلّغ عند فشل الحفظ بدل إغلاق النافذة بصمت.
                      _persistWithFeedback();
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ المستند'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4A73),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _inputField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      textDirection: TextDirection.rtl,
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
    final selectedPeople = _peopleForSelectedType();

    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        screenId: 'people_management',
        onPressed: _openQuickCreateSheet,
        label: 'إضافة',
        backgroundColor: const Color(0xFF7C3AED),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          slivers: [
            ManagementDashboardHeader(
              title: 'إدارة الأفراد والجهات',
              subtitle: 'تنظيم العلاقات والالتزامات وبيانات التواصل',
              icon: Icons.person_search_rounded,
              colors: const [Color(0xFF6D28D9), Color(0xFF7C3AED)],
              onSmartCalendarTap: _openSmartCalendar,
              onClose: () => Navigator.of(context).pop(),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              sliver: SliverToBoxAdapter(
                child: ManagementSearchBar(
                  controller: _searchController,
                  hint: 'ابحث في جميع الأشخاص والجهات...',
                  accentColor: const Color(0xFF7C3AED),
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
                color: AppTheme.page,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ManagementFollowUpCenter(
                    subtitle: _selectedTypeKey == 'all'
                        ? 'الأهم والأقرب من جميع الأشخاص والجهات'
                        // _selectedFilterLabel لا يعرف مفاتيح الحالة
                        // (متأخر/مستعجل/قريب) ولا all_people/all_entities،
                        // فكان الرأس يقول "الكل" بينما القائمة مُصفّاة.
                        : 'متابعة ${_activeSearchFilterLabel()}',
                    accentColor: const Color(0xFF047857),
                    onMore: () => _openFollowUpSheet(selectedPeople),
                    metrics: [
                      ManagementMetricData(
                        label: 'وثائق للمتابعة',
                        count: selectedPeople
                            .where(
                              (person) => person.statusNote.contains('مستند'),
                            )
                            .length,
                        icon: Icons.description_outlined,
                        color: const Color(0xFFC73E4D),
                      ),
                      ManagementMetricData(
                        label: 'مهام مفتوحة',
                        count: selectedPeople.fold<int>(
                          0,
                          (count, person) => count + person.openTasks,
                        ),
                        icon: Icons.task_alt_rounded,
                        color: const Color(0xFFB56A09),
                      ),
                      ManagementMetricData(
                        label: 'مستحقات لك',
                        count: selectedPeople
                            .where((person) => person.dueToYou > 0)
                            .length,
                        icon: Icons.call_received_rounded,
                        color: const Color(0xFF07835C),
                      ),
                      ManagementMetricData(
                        label: 'مستحقات عليك',
                        count: selectedPeople
                            .where((person) => person.dueOnYou > 0)
                            .length,
                        icon: Icons.call_made_rounded,
                        color: const Color(0xFF7956A8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // صف "الفئات" يبقى مثبَّتًا في الأعلى عند التمرير.
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
                          color: const Color(0xFF0B3A78),
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
                        AppCategoryDropdownChip(
                          label: 'الأفراد',
                          count: _countByScope('scope_people'),
                          icon: Icons.person_outline_rounded,
                          color: const Color(0xFF0F6AA8),
                          selected: _selectedScopeKey == 'scope_people',
                          onTap: () => setState(() {
                            _selectedScopeKey = 'scope_people';
                            _selectedTypeKey = 'all_people';
                            _filter.subCategory = null;
                          }),
                          items: _scopeDropdownItems(isEntity: false),
                        ),
                        const SizedBox(width: 8),
                        AppCategoryDropdownChip(
                          label: 'الجهات',
                          count: _countByScope('scope_entities'),
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF7C3AED),
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
                      'مستندات قريبة الإنتهاء',
                      'مستندات منتهية',
                    ],
                    onSelected: (value) =>
                        setState(() => _selectedSort = value),
                    title: _selectedTypeKey == 'all'
                        ? 'جميع الأفراد والجهات'
                        : _activeSearchFilterLabel(),
                    count: people.length,
                    accentColor: const Color(0xFF7C3AED),
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
                          style: TextStyle(color: Color(0xFF64748B)),
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
  });

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

  // تبويبات صفحة التفاصيل الآن مطابقة تماماً لفئات نافذة "+ إضافة" الستة
  // (بالإضافة إلى "الملخص" الأساسي): مالية، متابعة وتخطيط، مستندات،
  // إضافة إجراء، مواقع وأماكن. لا يوجد تبويب "السجل" أو "كلمات سر" أو
  // "تفويض" مستقل — سجل الإضافات ينتقل إلى تبويب الملخص (حسب ملف
  // المتطلبات: "في الملخص اسجل كل شي ضفته عند + إضافة")، وتفويض يدخل ضمن
  // متابعة وتخطيط (بقرار المستخدم).
  final List<String> _detailTabs = const [
    'الملخص',
    'مالية',
    'متابعة وتخطيط',
    'مستندات',
    'إضافة إجراء',
    'مواقع وأماكن',
  ];

  static const List<DetailSectionTab> _detailSections = [
    DetailSectionTab(label: 'الملخص', icon: Icons.bar_chart_rounded),
    DetailSectionTab(
      label: 'مالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(
      label: 'متابعة وتخطيط',
      icon: Icons.event_note_outlined,
    ),
    DetailSectionTab(label: 'مستندات', icon: Icons.folder_outlined),
    DetailSectionTab(label: 'إضافة إجراء', icon: Icons.gavel_outlined),
    DetailSectionTab(label: 'مواقع وأماكن', icon: Icons.place_outlined),
  ];

  String _detailValue(
    _PersonItem person,
    List<String> keys, {
    String fallback = '(اختياري)',
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
                    'تعديل البيانات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
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
        textDirection: TextDirection.rtl,
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
          textDirection: TextDirection.rtl,
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
                  backgroundColor: const Color(0xFFDC2626),
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

  void _toggleFreeze() {
    final nowFrozen = !_person.isFrozen;
    _applyPersonUpdate(
      _person.copyWith(isFrozen: nowFrozen, lastUpdate: _todayStamp()),
      notice: nowFrozen ? 'تم تجميد الشخص' : 'تم إلغاء التجميد',
    );
  }

  void _togglePin() {
    final nowPinned = !_person.isPinned;
    _applyPersonUpdate(
      _person.copyWith(isPinned: nowPinned, lastUpdate: _todayStamp()),
      // الرسالة تصف ما يحدث فعلًا: التثبيت يرفع السجل إلى أعلى القائمة في
      // هذه الشاشة. لا شيء في الصفحة الرئيسية يقرأ isPinned، فكان الوعد
      // السابق بـ"تثبيت في الرئيسية" غير صحيح.
      notice: nowPinned
          ? 'تم تثبيت الشخص في أعلى القائمة'
          : 'تم إلغاء التثبيت',
    );
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
      case ThreeDotMenuAction.freeze:
        _toggleFreeze();
        break;
      case ThreeDotMenuAction.pinHome:
        _togglePin();
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
    _ActionGroup('إضافة مالية', const Color(0xFF0EA5A4), const [
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
    _ActionGroup('إضافة تنظيمية إدارية', const Color(0xFF0F6AA8), const [
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
    _ActionGroup('إضافة مستند', const Color(0xFF7C3AED), const [
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
    _ActionGroup('إضافة صلاحية / تفويض', const Color(0xFFE11D48), const [
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
    _ActionGroup('إضافة كلمات سر', const Color(0xFF10B981), const [
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
    _ActionGroup('إضافة مواقع وروابط', const Color(0xFF0EA5A4), const [
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
    _sourcePerson = widget.person;
    _personDocuments = List<String>.from(widget.person.documents);
    _personSharedCommitments = List<String>.from(
      widget.person.sharedCommitments,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
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
                      color: Color(0xFF0F172A),
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
                              textDirection: TextDirection.rtl,
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
  Future<void> _openPersonQuickAddSheet() async {
    var orgExpanded = true;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
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
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'إضافة إلى الملف',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اختر ما تريد إضافته لهذا الفرد أو الجهة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
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
                            label: 'متابعة وتخطيط',
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
                              color: Color(0xFF0C6A8C),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'إجراءات إضافية',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF172033),
                                ),
                              ),
                            ),
                            Icon(
                              orgExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF0C6A8C),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _PersonQuickAddTile(
                              key: const ValueKey('person-add-action-option'),
                              label: 'إضافة إجراء',
                              icon: Icons.gavel_outlined,
                              onTap: () =>
                                  Navigator.pop(sheetContext, 'إضافة إجراء'),
                            ),
                          ),
                          const SizedBox(width: 8),
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
          color: const Color(0xFF0EA5A4),
          kinds: const ['راتب', 'مكافأة', 'عهدة مالية', 'دفعة / سداد', 'مصروف'],
          showAmount: true,
        );
      case 'متابعة وتخطيط':
        _openPersonKindEntrySheet(
          category: 'متابعة وتخطيط',
          color: const Color(0xFF0F6AA8),
          kinds: const ['مهمة', 'تذكير', 'موعد', 'عادة', 'ملاحظات'],
        );
      case 'مستندات':
        _openPersonKindEntrySheet(
          category: 'مستندات',
          color: const Color(0xFF7C3AED),
          kinds: const ['مستند عام', 'وثائق شخصية'],
        );
      case 'إضافة إجراء':
        _openPersonKindEntrySheet(
          category: 'إضافة إجراء',
          color: const Color(0xFFE11D48),
          kinds: const ['تسوية مالية', 'تصويت', 'اعتراض', 'استبيان'],
        );
      case 'مواقع وأماكن':
        _openPersonKindEntrySheet(
          category: 'مواقع وأماكن',
          color: const Color(0xFF0EA5A4),
          kinds: const ['موقع', 'رابط موقع'],
        );
      case 'تفويض':
        // بيانات التفويض تُخزَّن ضمن "متابعة وتخطيط" مباشرة (وليست قسمًا
        // مستقلاً) بقرار المستخدم السابق، بنفس منطق الالتزامات المشتركة.
        _openPersonKindEntrySheet(
          category: 'متابعة وتخطيط',
          color: const Color(0xFF0F6AA8),
          kinds: const ['مهمة', 'تذكير', 'موعد', 'عادة', 'ملاحظات', 'تفويض'],
          initialKind: 'تفويض',
        );
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
  }) async {
    const customOption = '+ إضافة أخرى';
    var kind = initialKind ?? kinds.first;
    // اتجاه المبلغ يُحدَّده المستخدم صراحةً بنفس ألفاظ الشاشة ("له"/"عليه")
    // بدل استنتاجه من اسم النوع، فلا يُسجَّل مبلغ في الجهة الخاطئة.
    var amountToPerson = false;
    final customKindCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
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
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      category,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(
                        labelText: 'النوع',
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
                        decoration: const InputDecoration(
                          labelText: 'اكتب النوع',
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
                        decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
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
                    const SizedBox(height: 10),
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'التاريخ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('+ إضافة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
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

    if (saved != true || !mounted) {
      customKindCtrl.dispose();
      amountCtrl.dispose();
      dateCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    final resolvedKind = kind == customOption
        ? (customKindCtrl.text.trim().isEmpty
              ? category
              : customKindCtrl.text.trim())
        : kind;
    final logParts = <String>['$category — $resolvedKind'];
    if (amountCtrl.text.trim().isNotEmpty) {
      logParts.add('${amountCtrl.text.trim()} ${AppSettings.currencySuffix}');
    }
    if (dateCtrl.text.trim().isNotEmpty) logParts.add(dateCtrl.text.trim());
    if (notesCtrl.text.trim().isNotEmpty) logParts.add(notesCtrl.text.trim());
    final logLine = logParts.join(' · ');

    var updated = _person.copyWith(
      activityLog: [..._person.activityLog, logLine],
      lastUpdate: _todayStamp(),
    );
    // المبلغ المُدخل يُضاف فعليًا إلى رصيد الشخص. كان يُكتب سابقًا كنص في
    // السجل الزمني فقط، فتبقى بطاقة الشخص تعرض "له : 0 درهم" مهما سُجِّل من
    // مبالغ — وكان ترتيب "الأعلى مستحقات" بلا أي معنى نتيجة ذلك.
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (showAmount && amount > 0) {
      updated = amountToPerson
          ? updated.copyWith(
              dueToYou: updated.dueToYou + amount.round(),
            )
          : updated.copyWith(
              dueOnYou: updated.dueOnYou + amount.round(),
            );
    }
    if (category == 'مستندات') {
      // المستند يُضاف إلى قائمة الشخص نفسها (التي تُحفَظ)، لا إلى قائمة
      // محلية في الشاشة. سابقًا كان العدّاد يزيد بينما اسم المستند يُكتب في
      // متغير مؤقت لا يُحفظ، فيختفي المستند بعد إعادة التشغيل ويبقى العدّاد
      // مرتفعًا — أي رقم لا يطابق محتواه أبدًا.
      updated = updated.copyWith(
        documents: [resolvedKind, ...updated.documents],
        documentsCount: updated.documentsCount + 1,
      );
    } else if (category == 'متابعة وتخطيط' || category == 'إضافة إجراء') {
      updated = updated.copyWith(openTasks: updated.openTasks + 1);
    }

    customKindCtrl.dispose();
    amountCtrl.dispose();
    dateCtrl.dispose();
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
            color: Color(0xFFF8FAFC),
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
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_box_rounded,
                        color: Color(0xFF0B4A73),
                        size: 21,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'اختيار نوع الإضافة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
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
                        color: Color(0xFF64748B),
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
                        borderRadius: BorderRadius.circular(10),
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
                                  color: Color(0xFF0F172A),
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
      Color(0xFF0EA5A4),
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
          color: const Color(0xFF0EA5A4),
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
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      group.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
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
                      textDirection: TextDirection.rtl,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
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
                  textDirection: TextDirection.rtl,
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
                  textDirection: TextDirection.rtl,
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
    final phoneValue = _detailValue(person, const [
      'رقم الهاتف',
    ], fallback: 'غير متوفر');
    final filteredDocuments = _filterItems(_personDocuments);
    final filteredCommitments = _filterItems(_personSharedCommitments);
    final selectedTab = _detailTabs[_selectedMainTab];
    const color = Color(0xFF0C6A8C);

    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AddFab(
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
        backgroundColor: const Color(0xFFE5B22E),
        foregroundColor: const Color(0xFF3D2E08),
        initialOffset: const Offset(0, 0),
      ),
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: const Text(
          'تفاصيل الشخص والجهة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF172033),
          ),
        ),
        leading: IconButton(
          tooltip: 'رجوع',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
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
                  ),
                  Container(height: 1, color: const Color(0xFFEEF2F7)),
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
                    _SummaryPanel(
                      person: person,
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    // سجل كل ما أُضيف من زر "+ إضافة" بالإضافة إلى تاريخ
                    // الإنشاء — هنا داخل الملخص مباشرة، حسب نص ملف
                    // المتطلبات ("في الملخص اسجل كل شي ضفته عند + إضافة").
                    _ActivityLogCard(
                      logs: [
                        ...person.activityLog.reversed,
                        'تم إنشاء السجل بتاريخ ${person.createdAt}',
                        'آخر تحديث: ${person.lastUpdate}',
                      ],
                    ),
                  ],
                  if (selectedTab == 'مالية')
                    _SummaryStatsPanel(
                      title: 'الملخص المالي',
                      textDirection: TextDirection.rtl,
                      blocks: [
                        (
                          'المستحق له',
                          '${person.dueToYou} ${AppSettings.currencySuffix}',
                          const Color(0xFF0F766E),
                        ),
                        (
                          'المستحق عليه',
                          '${person.dueOnYou} ${AppSettings.currencySuffix}',
                          const Color(0xFFB45309),
                        ),
                        (
                          'الالتزامات المشتركة',
                          '${filteredCommitments.length}',
                          const Color(0xFF0F6AA8),
                        ),
                      ],
                    ),
                  if (selectedTab == 'متابعة وتخطيط') ...[
                    _SummaryStatsPanel(
                      title: 'متابعة وتخطيط',
                      textDirection: TextDirection.rtl,
                      blocks: [
                        (
                          'المهام المفتوحة',
                          '${person.openTasks}',
                          const Color(0xFF0369A1),
                        ),
                        (
                          'الحالة الحالية',
                          person.badge,
                          const Color(0xFF7C2D12),
                        ),
                        (
                          'آخر تحديث',
                          person.lastUpdate,
                          const Color(0xFF475569),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _SummaryStatsPanel(
                      title: 'البيانات الأساسية',
                      textDirection: TextDirection.rtl,
                      blocks: [
                        ('رقم الهاتف', phoneValue, const Color(0xFF0F172A)),
                        (
                          'الجنسية',
                          _detailValue(person, const ['الجنسية']),
                          const Color(0xFF0F172A),
                        ),
                        (
                          'تاريخ الميلاد',
                          _detailValue(person, const ['تاريخ الميلاد']),
                          const Color(0xFF0F172A),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // الملاحظات والتفويضات تدخل هنا ضمن متابعة وتخطيط
                    // (وليست تبويباً مستقلاً) بنفس منطق الالتزامات المشتركة.
                    _SummaryStatsPanel(
                      title: 'الملاحظات والتفويضات',
                      textDirection: TextDirection.rtl,
                      blocks: [
                        (
                          'ملاحظة',
                          person.extraNote.isEmpty
                              ? 'لا توجد ملاحظات'
                              : person.extraNote,
                          const Color(0xFF334155),
                        ),
                        (
                          'التفويضات',
                          'تُضاف من زر + إضافة وتظهر هنا',
                          const Color(0xFF334155),
                        ),
                      ],
                    ),
                  ],
                  if (selectedTab == 'مستندات')
                    _DynamicLinkedDataCard(
                      title: 'المستندات المرتبطة بالشخص',
                      icon: Icons.description_rounded,
                      color: const Color(0xFF7C3AED),
                      emptyText: 'لا توجد مستندات مرتبطة حتى الآن',
                      textDirection: TextDirection.rtl,
                      items: filteredDocuments,
                    ),
                  if (selectedTab == 'إضافة إجراء')
                    const _SummaryStatsPanel(
                      title: 'إضافة إجراء',
                      blocks: [
                        (
                          'لا توجد إجراءات مسجلة',
                          'تُضاف من زر + إضافة (تسوية مالية، تصويت، اعتراض، استبيان)',
                          Color(0xFF334155),
                        ),
                      ],
                    ),
                  if (selectedTab == 'مواقع وأماكن')
                    _DynamicLinkedDataCard(
                      title: 'المواقع والأماكن المرتبطة',
                      icon: Icons.place_outlined,
                      color: const Color(0xFF0EA5A4),
                      emptyText: 'لا توجد مواقع مضافة حتى الآن',
                      textDirection: TextDirection.rtl,
                      items: const [],
                    ),
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
class _CompactPersonHeader extends StatelessWidget {
  const _CompactPersonHeader({
    required this.person,
    required this.color,
    required this.onAction,
  });

  final _PersonItem person;
  final Color color;
  final ValueChanged<ThreeDotMenuAction> onAction;

  @override
  Widget build(BuildContext context) {
    final typeLine = person.additionalCategoryNames.isEmpty
        ? '${person.categoryName} · ${person.roleTitle}'
        : '${person.categoryName} + ${person.additionalCategoryNames.join(' + ')} · ${person.roleTitle}';
    final statusLabel = person.isFrozen ? 'مجمّد' : person.badge;
    final statusColor = person.isFrozen
        ? const Color(0xFF64748B)
        : person.badgeColor;
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  typeLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          ThreeDotMenu(tooltip: 'خيارات', onAction: onAction),
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
    final highlights = <(String, String, IconData)>[
      ('له', '${person.dueToYou.toStringAsFixed(0)} ${AppSettings.currencySuffix}', Icons.south_west_rounded),
      ('عليه', '${person.dueOnYou.toStringAsFixed(0)} ${AppSettings.currencySuffix}', Icons.north_east_rounded),
      ('المستندات', '${person.documentsCount}', Icons.folder_outlined),
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
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF172033),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
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
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
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
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  textDirection: TextDirection.rtl,
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
          color: Color(0xFF64748B),
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
        textDirection: TextDirection.rtl,
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
            color: Color(0xFF64748B),
          ),
          prefixIcon: IconButton(
            onPressed: onFilterTap,
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF475569)),
            tooltip: 'فلتر',
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
          color: Color(0xFFDC2626),
        ),
        FollowupCenterItem(
          label: 'وثائق تنتهي قريباً',
          count: '2',
          color: Color(0xFFD97706),
        ),
        FollowupCenterItem(
          label: 'تفويضات منتهية',
          count: '1',
          color: Color(0xFF7C3AED),
        ),
        FollowupCenterItem(
          label: 'بيانات ناقصة',
          count: '3',
          color: Color(0xFF2563EB),
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
      borderRadius: BorderRadius.circular(10),
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
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.25,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateActionItem {
  const _CreateActionItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _CreateActionSection extends StatelessWidget {
  const _CreateActionSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_CreateActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '${actions.length}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final action = actions[index];
              return InkWell(
                onTap: action.onTap,
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: action.color.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(action.icon, color: action.color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const Icon(
                        // يُعكس تلقائيًا مع rtl فيشير لليسار، مطابقًا لسهم
                        // بطاقة الشخص وبقية قوائم التطبيق.
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// مربّع خيار في نافذة "+ إضافة" — نفس شكل _QuickAddTile/_SharedQuickAddTile
// تمامًا (76px، لون محايد واحد بلا تمييز لوني بين الأنواع).
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

  static const Color _neutral = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _neutral,
              ),
            ),
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
    final typeLine = person.additionalCategoryNames.isEmpty
        ? person.categoryName
        : '${person.categoryName} + ${person.additionalCategoryNames.join(' + ')}';
    final currency = AppSettings.currencySuffix;

    // كانت البطاقة تعرض "مستندات : 0" مرتين حين لا توجد مستحقات، لأن
    // السطرين يسقطان على نفس البديل. الآن تُبنى قائمة القيم ذات المعنى
    // فقط، وتعرض البطاقة الموحَّدة أول قيمتين منها.
    final stats = <String>[
      if (person.dueToYou > 0)
        'له : ${person.dueToYou.toStringAsFixed(0)} $currency',
      if (person.dueOnYou > 0)
        'عليه : ${person.dueOnYou.toStringAsFixed(0)} $currency',
      if (person.documentsCount > 0) 'مستندات : ${person.documentsCount}',
    ];

    // بطاقة القائمة الموحَّدة نفسها المستعملة في الالتزامات الشخصية
    // والمشتركة.
    return AppEntityCard(
      icon: _personCardTypeIcon(person.typeKey),
      iconColor: person.badgeColor,
      title: person.fullName,
      subtitle: typeLine,
      statusColor: person.badgeColor,
      stats: stats,
      leadingBadges: [
        if (person.isPinned)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(
              Icons.push_pin_rounded,
              size: 13,
              color: Color(0xFFF59E0B),
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
        color: const Color(0xFFE9F6FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBE6F1)),
      ),
      child: const Text(
        'الاسم الكامل، الاسم المختصر، الصورة، الجنس، تاريخ الميلاد، الجنسية، رقم الهوية، جواز السفر، العنوان، أرقام التواصل، البريد الإلكتروني، وسائل التواصل، جهات اتصال بديلة، التصنيف (رئيسي/فرعي)',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF0F4AA2),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.person,
    this.textDirection = TextDirection.rtl,
  });

  final _PersonItem person;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    String detailValue(List<String> keys, {String fallback = '(اختياري)'}) {
      for (final key in keys) {
        final value = person.details[key]?.trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return fallback;
    }

    final followUpCount = person.openTasks;
    final rows = [
      ('الاسم', person.fullName, Icons.person_outline_rounded),
      (
        'التصنيف',
        person.additionalCategoryNames.isEmpty
            ? person.categoryName
            : '${person.categoryName} + ${person.additionalCategoryNames.join(' + ')}',
        Icons.category_outlined,
      ),
      ('الحالة', person.badge, Icons.verified_user_outlined),
      (
        'رقم الهاتف',
        detailValue(const ['رقم الهاتف'], fallback: 'غير متوفر'),
        Icons.phone_outlined,
      ),
      ('الجنسية', detailValue(const ['الجنسية']), Icons.flag_outlined),
      (
        'تاريخ الميلاد',
        detailValue(const ['تاريخ الميلاد']),
        Icons.cake_outlined,
      ),
      ('تاريخ الإنشاء', person.createdAt, Icons.event_outlined),
      ('آخر تحديث', person.lastUpdate, Icons.edit_note_rounded),
      (
        'ملاحظات',
        person.extraNote.isEmpty ? '-' : person.extraNote,
        Icons.notes_rounded,
      ),
    ];

    // نفس بطاقة تفاصيل الالتزام الشخصي بالضبط: بطاقة رمادية واحدة، وصفوف
    // يفصلها خط أبيض رفيع. كانت هنا بطاقة متدرّجة بحدّ زرقاء وظل، وكل صف
    // فيها صندوق رمادي مستقل — شكل لا يشبه أي صفحة تفاصيل أخرى.
    return AppDetailsCard(
      title: 'بطاقة الملخص',
      icon: Icons.badge_outlined,
      color: const Color(0xFF7C3AED),
      children: [
        for (final row in rows)
          AppDetailRow(label: row.$1, value: row.$2, icon: row.$3),
        const SizedBox(height: AppTheme.sMd),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          textDirection: textDirection,
          children: [
            _metricPill(
              'المستحق له',
              '${person.dueToYou} ${AppSettings.currencySuffix}',
              const Color(0xFFDCFCE7),
              const Color(0xFF166534),
            ),
            _metricPill(
              'المستحق عليه',
              '${person.dueOnYou} ${AppSettings.currencySuffix}',
              const Color(0xFFFFEDD5),
              const Color(0xFF9A3412),
            ),
            _metricPill(
              'المهام المفتوحة',
              '${person.openTasks}',
              const Color(0xFFE0F2FE),
              const Color(0xFF0C4A6E),
            ),
            _metricPill(
              'تحتاج متابعة',
              '$followUpCount',
              const Color(0xFFEDE9FE),
              const Color(0xFF5B21B6),
            ),
            _metricPill(
              'المستندات',
              '${person.documentsCount}',
              const Color(0xFFFCE7F3),
              const Color(0xFF9D174D),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricPill(String label, String value, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _SummaryStatsPanel extends StatelessWidget {
  const _SummaryStatsPanel({
    required this.title,
    required this.blocks,
    this.textDirection = TextDirection.rtl,
  });

  final String title;
  final List<(String, String, Color)> blocks;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final isRtl = textDirection == TextDirection.rtl;
    final textAlign = isRtl ? TextAlign.right : TextAlign.left;
    // ملاحظة: CrossAxisAlignment.start يُحلّ أصلًا إلى اليمين داخل اتجاه
    // rtl. الشرط السابق (isRtl ? end : start) كان يعكسه مرتين فيُحاذي كل
    // عناوين البطاقات وقيمها إلى اليسار داخل بطاقة عربية.
    const crossAxis = CrossAxisAlignment.start;
    return Directionality(
      textDirection: textDirection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
        child: Column(
          crossAxisAlignment: crossAxis,
          children: [
            Text(
              title,
              textAlign: textAlign,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            ...blocks.map((block) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: block.$3.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: block.$3.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: crossAxis,
                  children: [
                    Text(
                      block.$1,
                      textAlign: textAlign,
                      style: TextStyle(
                        fontSize: 11,
                        color: block.$3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      block.$2,
                      textAlign: textAlign,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
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
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      block.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 10.8,
                        color: Color(0xFF475569),
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
    this.textDirection = TextDirection.rtl,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String emptyText;
  final List<String> items;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final isRtl = textDirection == TextDirection.rtl;
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
            textDirection: textDirection,
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
                    color: Color(0xFF0F172A),
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
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            )
          else
            ...items
                .take(8)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      textDirection: textDirection,
                      children: [
                        Icon(Icons.circle, size: 6, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            textAlign: textAlign,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF334155),
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
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'تنبيهات مالية: دفعة متأخرة، قسط مستحق',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات زمنية: مهمة متأخرة، موعد قريب',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات مستندات وأشخاص: مستند منتهي، بيانات ناقصة',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
        ],
      ),
    );
  }
}

class _ActivityLogCard extends StatelessWidget {
  const _ActivityLogCard({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'السجل الزمني',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          ...(logs.isEmpty
              ? [
                  const Text(
                    'لا توجد أحداث بعد',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ]
              : logs
                    .take(8)
                    .map(
                      (log) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 6,
                              color: Color(0xFF0B4A73),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                log,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF334155),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
        ],
      ),
    );
  }
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
    final textDirection = startFromLeft ? TextDirection.ltr : TextDirection.rtl;

    return Directionality(
      textDirection: textDirection,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFFDFEFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E5FA7), width: 1.2),
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
                          ? const Color(0xFF111827)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: const Color(0xFF111827),
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
          color: selected ? color : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : const Color(0xFFDCE5EF)),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF334155),
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
      badgeColor: Color((map['badgeColor'] as num?)?.toInt() ?? 0xFF64748B),
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
