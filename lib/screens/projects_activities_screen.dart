import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/app_settings.dart';
import '../data/app_reminders_store.dart';
import '../data/project_assets_repository.dart';
import 'document_templates_screen.dart';
import 'smart_calendar_screen.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/app_filter_sheet.dart';
import '../widgets/shared/followup_center_sheet.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';

const _propertyAnnexLabels = [
  'ممرات',
  'درج',
  'سطح',
  'بلكونات',
  'غرفة الاتصالات',
  'غرفة الكهرباء',
  'غرفة الدفاع المدني',
];

class ProjectsActivitiesScreen extends StatefulWidget {
  /// الفئة المفتوحة عند الدخول: تسمح لاختصارات الصفحة الرئيسية بفتح
  /// العقارات أو الأنشطة مباشرةً بدل فتح "الكل" ثم البحث يدويًا.
  final String initialFilter;

  const ProjectsActivitiesScreen({super.key, this.initialFilter = 'all'});

  @override
  State<ProjectsActivitiesScreen> createState() =>
      _ProjectsActivitiesScreenState();
}

class _ProjectsActivitiesScreenState extends State<ProjectsActivitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ProjectAssetsRepository _repository = SupabaseProjectAssetsRepository();
  late String _selectedFilter = widget.initialFilter;
  String _selectedSort = 'الأحدث أولاً';
  bool _isLoadingRemote = true;

  final List<_TopFilter> _filters = const [
    _TopFilter('all', 'الكل', Color(0xFF0B3A78)),
    _TopFilter('real_estate', 'العقارات', Color(0xFF0F6AA8)),
    _TopFilter('activity', 'الأنشطة التجارية', Color(0xFF10B981)),
    _TopFilter('equipment', 'المعدات', Color(0xFFF59E0B)),
  ];

  late final List<_AssetItem> _items = [
    _AssetItem(
      title: 'فيلا الياسمينة',
      subType: 'فيلا',
      category: 'real_estate',
      locationOrType: 'الرياض / عقار',
      status: 'نشط',
      amountLabel: '1850 درهم',
      followupNote: 'عقد ينتهي بعد 30 يوم',
      owner: 'عبدالله السالم',
      tenant: 'شركة الواحة',
      rentValue: '1850 درهم شهري',
      endDate: '2026/08/15',
      annualYield: '22,200 درهم',
      occupancyRate: 0.9,
      contractProgress: 0.72,
      paymentProgress: 0.66,
      documentsProgress: 0.83,
      needsAttention: true,
      documents: ['سند ملكية', 'عقد الإيجار', 'فاتورة كهرباء'],
      contracts: ['عقد إيجار رئيسي', 'عقد صيانة سنوي'],
      tasks: ['متابعة المستأجر', 'زيارة ميدانية'],
      alerts: ['عقد سينتهي قريبًا', 'دفعة متأخرة'],
      logs: ['تجديد عقد الصيانة', 'رفع فاتورة جديدة'],
      createdAt: DateTime.now(),
    ),
    _AssetItem(
      title: 'مشروع الصفا',
      subType: 'مشروع سكني',
      category: 'real_estate',
      locationOrType: 'الرياض / مشروع',
      status: 'نشط',
      amountLabel: '420,000 درهم',
      followupNote: 'الصيانة مطلوبة في مرحلتين',
      owner: 'شركة Fundly',
      tenant: 'غير مطبق',
      rentValue: 'غير مطبق',
      endDate: '2027/02/01',
      annualYield: '12%',
      occupancyRate: 0.55,
      contractProgress: 0.48,
      paymentProgress: 0.52,
      documentsProgress: 0.61,
      needsAttention: true,
      documents: ['عقد مقاول', 'شهادة إشغال'],
      contracts: ['عقد إدارة المشروع'],
      tasks: ['اعتماد مرحلة', 'متابعة أعمال'],
      alerts: ['مشروع تجاوز الجدول الزمني'],
      logs: ['تعديل خطة الدفعات'],
      createdAt: DateTime.now(),
    ),
    _AssetItem(
      title: 'مطعم روز بيلا',
      subType: 'مطعم ونشاط تجاري',
      category: 'activity',
      locationOrType: 'الرياض / نشاط تجاري',
      status: 'نشط',
      amountLabel: 'إيراد 18,400 درهم',
      followupNote: 'رخصة ستنتهي بعد 45 يوم',
      owner: 'راشد خالد',
      tenant: 'غير مطبق',
      rentValue: 'غير مطبق',
      endDate: '2026/09/25',
      annualYield: 'ربحية 22%',
      occupancyRate: 0.97,
      contractProgress: 0.78,
      paymentProgress: 0.81,
      documentsProgress: 0.74,
      needsAttention: false,
      documents: ['رخصة نشاط', 'شهادة ضريبية', 'عقد مورد'],
      contracts: ['عقد مورد أغذية', 'عقد خدمات توصيل'],
      tasks: ['تجديد الرخصة', 'متابعة عميل'],
      alerts: ['فاتورة مستحقة', 'ضمان سينتهي'],
      logs: ['إضافة فاتورة مورد', 'تحصيل دفعة عميل'],
      createdAt: DateTime.now(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadAssetsFromRemote();
  }

  Future<void> _loadAssetsFromRemote() async {
    setState(() => _isLoadingRemote = true);
    try {
      final records = await _repository.fetchAssets();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(records.map(_assetFromRecord));
        _isLoadingRemote = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingRemote = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر جلب بيانات العقارات والأنشطة: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createAssetRemote(_AssetItem item) async {
    try {
      final created = await _repository.createAsset(_assetToRecord(item));
      if (!mounted) return;
      setState(() {
        _items.insert(0, _assetFromRecord(created));
        _selectedFilter = 'all';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حفظ الأصل في قاعدة البيانات: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _updateAssetRemote(_AssetItem item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      final updated = await _repository.updateAsset(
        _assetToRecord(item, id: item.id),
      );
      if (!mounted) return;
      final index = _items.indexWhere((e) => e.id == updated.id);
      if (index == -1) return;
      setState(() => _items[index] = _assetFromRecord(updated));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث الأصل في قاعدة البيانات: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteAssetRemote(_AssetItem item) async {
    if (item.id == null || item.id!.isEmpty) return;
    try {
      await _repository.deleteAsset(item.id!);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف الأصل من قاعدة البيانات: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  _AssetItem _assetFromRecord(ProjectAssetRecord record) {
    final displayDate = record.endDate?.replaceAll('-', '/') ?? 'غير محدد';
    final mappedCategory = _fromDatabaseCategory(record.category);
    final status = record.status.isEmpty ? 'نشط' : record.status;
    return _AssetItem(
      id: record.id,
      title: record.title,
      subType: record.subType,
      category: mappedCategory,
      locationOrType: record.locationOrType ?? 'غير محدد',
      status: status,
      amountLabel: record.amountLabel ?? '0 ${AppSettings.currencySuffix}',
      followupNote: record.followupNote ?? 'لا توجد ملاحظات متابعة',
      owner: record.owner ?? 'غير محدد',
      tenant: record.tenant ?? 'غير محدد',
      rentValue: record.rentValue ?? 'غير محدد',
      endDate: displayDate,
      annualYield: record.annualYield ?? 'غير محدد',
      occupancyRate: record.occupancyRate,
      contractProgress: record.contractProgress,
      paymentProgress: record.paymentProgress,
      documentsProgress: record.documentsProgress,
      needsAttention: record.needsAttention,
      documents: const [],
      contracts: const [],
      tasks: const [],
      alerts: const [],
      logs: _decodeStringList(record.logsJson),
      createdAt: DateTime.now(),
      description: record.description,
      annexes: record.annexes,
      iconColor: record.iconColor == null ? null : Color(record.iconColor!),
      mapLink: record.mapLink ?? '',
      quickAddEnabled: record.quickAddEnabled,
      units: _decodeUnits(record.unitsJson),
      employees: _decodeStringMaps(record.employeesJson),
      serialNumber: record.serialNumber ?? '',
      isFrozen: record.isFrozen,
      isPinned: record.isPinned,
      isSublease: record.isSublease,
      latitude: record.latitude,
      longitude: record.longitude,
    );
  }

  List<_PropertyUnit> _decodeUnits(String? unitsJson) {
    if (unitsJson == null || unitsJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(unitsJson);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => _PropertyUnit.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<String> _decodeStringList(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, String>> _decodeStringMaps(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (m) => m.map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  ProjectAssetRecord _assetToRecord(_AssetItem item, {String? id}) {
    return ProjectAssetRecord(
      id: id,
      title: item.title,
      subType: item.subType,
      category: _toDatabaseCategory(item.category),
      status: item.status,
      locationOrType: item.locationOrType,
      amountLabel: item.amountLabel,
      followupNote: item.followupNote,
      owner: item.owner,
      tenant: item.tenant,
      rentValue: item.rentValue,
      endDate: item.endDate == 'غير محدد'
          ? null
          : item.endDate.replaceAll('/', '-'),
      annualYield: item.annualYield,
      occupancyRate: item.occupancyRate,
      contractProgress: item.contractProgress,
      paymentProgress: item.paymentProgress,
      documentsProgress: item.documentsProgress,
      needsAttention: item.needsAttention,
      iconColor: item.iconColor?.toARGB32(),
      description: item.description,
      annexes: item.annexes,
      mapLink: item.mapLink,
      quickAddEnabled: item.quickAddEnabled,
      unitsJson: jsonEncode(item.units.map((u) => u.toMap()).toList()),
      employeesJson: jsonEncode(item.employees),
      serialNumber: item.serialNumber,
      isFrozen: item.isFrozen,
      isPinned: item.isPinned,
      isSublease: item.isSublease,
      latitude: item.latitude,
      longitude: item.longitude,
      logsJson: jsonEncode(item.logs),
    );
  }

  String _toDatabaseCategory(String uiCategory) {
    if (uiCategory == 'activity') return 'business';
    // للمعدات فئة قاعدة بيانات مستقلة عن "الأنشطة التجارية"؛ كانت سابقًا
    // تُخزَّن بنفس قيمة النشاط التجاري ('business') فتتحول كل معدة إلى نشاط
    // تجاري بشكل دائم بمجرد إعادة تحميل البيانات من الخادم (خطأ تصنيف غير
    // قابل للتراجع كان يفقد نوع الأصل الحقيقي).
    if (uiCategory == 'equipment') return 'equipment';
    if (uiCategory == 'other') return 'project';
    return 'real_estate';
  }

  String _fromDatabaseCategory(String dbCategory) {
    if (dbCategory == 'business') return 'activity';
    if (dbCategory == 'equipment') return 'equipment';
    if (dbCategory == 'project') return 'other';
    return 'real_estate';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _countByCategory(String key) {
    if (key == 'all') return _items.length;
    return _items.where((item) => _matchesFilter(item, key)).length;
  }

  /// السطر الثاني في بطاقة القائمة: نوع الأصل، ويُضاف للعقار عدد وحداته
  /// وموقعه — فلا تضيع بيانات العقار حين توحّدت البطاقة مع بقية الفئات.
  String _assetSubtitle(_AssetItem item) {
    final parts = <String>[
      if (item.subType.trim().isNotEmpty) item.subType.trim(),
      if (item.category == 'real_estate' && item.units.isNotEmpty)
        item.units.length == 1
            ? 'وحدة واحدة'
            : item.units.length == 2
            ? 'وحدتان'
            : '${item.units.length} وحدات',
      if (item.locationOrType.trim().isNotEmpty) item.locationOrType.trim(),
    ];
    return parts.join(' · ');
  }

  bool _matchesFilter(_AssetItem item, String filter) {
    if (filter == 'all') return true;
    return item.category == filter;
  }

  /// قيم الفلتر الرئيسي — نفس البنية في الشاشات الأربع.
  final AppFilterValues _filter = AppFilterValues();

  bool _matchesAdvancedAssetFilters(_AssetItem item) {
    // مقارنة بعد trim: قائمة الأنواع تُبنى من قيم منظّفة، فأي فراغ زائد
    // في البيانات كان يمنع العنصر من مطابقة نوعه نفسه.
    if (_filter.subCategory != null &&
        item.subType.trim() != _filter.subCategory) {
      return false;
    }
    switch (_filter.status) {
      case 'نشط':
        if (item.isFrozen || item.needsAttention) return false;
      case 'المستحق بعد 7 أيام':
        final due = _parseAssetDate(item.endDate);
        if (due == null) return false;
        final days = due.difference(DateUtils.dateOnly(DateTime.now())).inDays;
        if (days < 0 || days > 7) return false;
      case 'متأخر':
        if (!item.needsAttention) return false;
      case 'مكتمل':
        if (item.needsAttention || item.isFrozen) return false;
      case 'ملغاة':
        if (!item.status.contains('ملغا')) return false;
      case 'مؤرشف':
        if (!item.isFrozen) return false;
    }
    if (!_filter.matchesDate(_parseAssetDate(item.endDate))) return false;
    final amount = num.tryParse(
      item.rentValue.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    if ((_filter.amountFrom != null || _filter.amountTo != null) &&
        (amount == null || !_filter.matchesAmount(amount))) {
      return false;
    }
    if (_filter.documentName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.documentName, [
          ...item.documents,
          ...item.contracts,
        ])) {
      return false;
    }
    if (_filter.personName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.personName, [
          item.owner,
          item.tenant,
        ])) {
      return false;
    }
    if (_filter.delegateName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.delegateName, [
          item.owner,
          for (final employee in item.employees) employee['الاسم'] ?? '',
        ])) {
      return false;
    }
    if (_filter.placeName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.placeName, [
          item.locationOrType,
          item.mapLink,
        ])) {
      return false;
    }
    return true;
  }

  /// تحويل تاريخ نصّي (d/M/yyyy أو yyyy/M/d) إلى DateTime، أو null.
  DateTime? _parseAssetDate(String raw) {
    final parts = raw.split(RegExp(r'[/-]'));
    if (parts.length != 3) return null;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) return null;
    return first > 31
        ? DateTime(first, second, third)
        : DateTime(third, second, first);
  }

  /// الأنواع الفرعية الموجودة فعلًا ضمن الفئة المختارة.
  List<String> _subTypesFor(String category) {
    final values = <String>{
      for (final item in _items)
        if (category == 'all' || item.category == category)
          if (item.subType.trim().isNotEmpty) item.subType.trim(),
    }.toList()..sort();
    return values;
  }

  /// خيارات الفلتر الصغير حسب الفئة المختارة.
  List<String> _quickSortOptions() => [
    'الأحدث أولاً',
    'نشط',
    if (_selectedFilter != 'activity') 'شاغر',
    'مستندات قريبة الإنتهاء',
    'مستندات منتهية',
  ];

  List<_AssetItem> _filteredItems() {
    final query = _searchController.text.trim();

    final filtered = _items.where((item) {
      final typeMatches = _matchesFilter(item, _selectedFilter);
      final queryMatches = matchesSearchQuery(
        query: query,
        fields: [
          item.title,
          item.subType,
          item.category,
          item.followupNote,
          item.locationOrType,
          item.status,
          item.owner,
          item.tenant,
          item.rentValue,
          item.amountLabel,
          item.endDate,
          item.annualYield,
          item.description,
          ...item.documents,
          ...item.contracts,
          ...item.tasks,
          ...item.alerts,
          ...item.logs,
        ],
      );
      return typeMatches &&
          queryMatches &&
          _matchesAdvancedAssetFilters(item);
    }).toList();

    // الفلتر الصغير يُقدّم المطابق ولا يُخفي غيره.
    final today = DateUtils.dateOnly(DateTime.now());
    int rank(_AssetItem item) {
      switch (_selectedSort) {
        case 'نشط':
          return item.isFrozen || item.needsAttention ? 1 : 0;
        case 'شاغر':
          return item.vacantUnitsCount > 0 ? 0 : 1;
        case 'مستندات قريبة الإنتهاء':
          {
            final due = _parseAssetDate(item.endDate);
            if (due == null) return 1;
            final days = due.difference(today).inDays;
            return days >= 0 && days <= 30 ? 0 : 1;
          }
        case 'مستندات منتهية':
          {
            final due = _parseAssetDate(item.endDate);
            return due != null && due.isBefore(today) ? 0 : 1;
          }
        default:
          return 0;
      }
    }

    num assetAmount(_AssetItem item) =>
        num.tryParse(item.rentValue.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

    filtered.sort((a, b) {
      // "أعلى/أقل مبلغ" من الفلتر الكبير يتقدّم على ترتيب الفلتر الصغير.
      if (_filter.amountShortcut == 'أعلى مبلغ') {
        final byAmount = assetAmount(b).compareTo(assetAmount(a));
        if (byAmount != 0) return byAmount;
      } else if (_filter.amountShortcut == 'أقل مبلغ') {
        final byAmount = assetAmount(a).compareTo(assetAmount(b));
        if (byAmount != 0) return byAmount;
      }
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (_parseAssetDate(b.endDate) ?? DateTime(2000)).compareTo(
        _parseAssetDate(a.endDate) ?? DateTime(2000),
      );
    });
    return filtered;
  }

  IconData _filterIcon(String key) {
    if (key == 'real_estate') return Icons.apartment_rounded;
    if (key == 'activity') return Icons.storefront_rounded;
    if (key == 'equipment') return Icons.precision_manufacturing_outlined;
    return Icons.grid_view_rounded;
  }

  /// مركز المتابعة بالقالب الموحَّد نفسه المستعمل في بقية الوحدات.
  ///
  /// كان زر "المزيد" هنا يفتح نافذة **فلترة** لا علاقة لها بالمتابعة.
  /// مجموعات مركز المتابعة — مصدر واحد للبطاقة المصغّرة ولنافذة "المزيد".
  List<FollowUpGroup> _followUpGroups(List<_AssetItem> assets) {
    FollowUpEntry entryFor(_AssetItem item, String trailing) => FollowUpEntry(
      title: item.title,
      subtitle: item.subType.isEmpty ? item.status : item.subType,
      icon: _filterIcon(item.category),
      color: item.iconColor ?? const Color(0xFF0F6AA8),
      trailingText: trailing,
      onTap: () => _openDetails(item),
    );

    String percent(double value) => '${(value * 100).round()}%';

    return [
        FollowUpGroup(
          title: 'الدفعات',
          icon: Icons.payments_outlined,
          color: const Color(0xFFB56A09),
          metrics: [
            FollowUpMetric(
              label: 'دفعات للمتابعة',
              icon: Icons.pending_actions_outlined,
              entries: [
                for (final item in assets.where((a) => a.paymentProgress < 0.7))
                  entryFor(item, percent(item.paymentProgress)),
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
              label: 'مستندات ناقصة',
              icon: Icons.badge_outlined,
              entries: [
                for (final item in assets.where(
                  (a) => a.documentsProgress < 0.8,
                ))
                  entryFor(item, percent(item.documentsProgress)),
              ],
            ),
            FollowUpMetric(
              label: 'بلا مستندات',
              icon: Icons.folder_off_outlined,
              entries: [
                for (final item in assets.where((a) => a.documents.isEmpty))
                  entryFor(item, '0'),
              ],
            ),
          ],
        ),
        FollowUpGroup(
          title: 'العقود',
          icon: Icons.description_outlined,
          color: const Color(0xFFC73E4D),
          metrics: [
            FollowUpMetric(
              label: 'عقود للمتابعة',
              icon: Icons.assignment_late_outlined,
              entries: [
                for (final item in assets.where(
                  (a) => a.contracts.isNotEmpty && a.needsAttention,
                ))
                  entryFor(item, percent(item.contractProgress)),
              ],
            ),
            FollowUpMetric(
              label: 'بلا عقد',
              icon: Icons.assignment_outlined,
              entries: [
                for (final item in assets.where((a) => a.contracts.isEmpty))
                  entryFor(item, 'لا يوجد'),
              ],
            ),
          ],
        ),
        FollowUpGroup(
          title: 'الحالة',
          icon: Icons.flag_outlined,
          color: const Color(0xFF7956A8),
          metrics: [
            FollowUpMetric(
              label: 'تحتاج متابعة',
              icon: Icons.warning_amber_rounded,
              entries: [
                for (final item in assets.where((a) => a.needsAttention))
                  entryFor(item, item.status),
              ],
            ),
            FollowUpMetric(
              label: 'وحدات شاغرة',
              icon: Icons.meeting_room_outlined,
              entries: [
                for (final item in assets.where((a) => a.vacantUnitsCount > 0))
                  entryFor(item, '${item.vacantUnitsCount}'),
              ],
            ),
            FollowUpMetric(
              label: 'مجمّدة',
              icon: Icons.ac_unit_rounded,
              entries: [
                for (final item in assets.where((a) => a.isFrozen))
                  entryFor(item, 'مجمّد'),
              ],
            ),
          ],
        ),
      ];
  }

  void _openFollowUpSheet(List<_AssetItem> assets) {
    showFollowUpCenterSheet(
      context: context,
      accent: const Color(0xFF047857),
      title: _selectedFilter == 'all'
          ? 'مركز المتابعة'
          : 'متابعة ${_filters.firstWhere((item) => item.key == _selectedFilter).label}',
      groups: _followUpGroups(assets),
    );
  }

  void _openDetails(_AssetItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectAssetDetailsScreen(
          item: item,
          repository: _repository,
          onItemChanged: (updated) {
            final index = _items.indexWhere((e) => _sameAsset(e, updated));
            if (index == -1) return;
            setState(() {
              _items[index] = updated;
              _items.sort(
                (a, b) => (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0),
              );
            });
            _updateAssetRemote(updated);
          },
          onItemDeleted: (deleted) {
            setState(() {
              _items.removeWhere((e) => _sameAsset(e, deleted));
            });
            _deleteAssetRemote(deleted);
          },
        ),
      ),
    );
  }

  bool _sameAsset(_AssetItem a, _AssetItem b) {
    if (a.id != null && b.id != null) return a.id == b.id;
    return a.title == b.title &&
        a.category == b.category &&
        a.locationOrType == b.locationOrType &&
        a.createdAt == b.createdAt;
  }

  // الفلتر الرئيسي: نفس قالب الشاشات الأربع، والأقسام وترتيبها مطابقة
  // لملف "فلاتر فوندلي" لصفحة العقارات والأنشطة والمعدات.
  void _openFilterSheet() {
    const labels = {
      'all': 'الكل',
      'real_estate': 'العقارات',
      'activity': 'الأنشطة التجارية',
      'equipment': 'المعدات',
    };
    showAppFilterSheet(
      context: context,
      title: 'العقارات والأنشطة والمعدات',
      accent: const Color(0xFF047857),
      values: _filter..mainCategory = labels[_selectedFilter] ?? 'الكل',
      mainCategories: labels.values.toList(growable: false),
      subCategoriesFor: (main) => _subTypesFor(
        labels.entries
            .firstWhere(
              (entry) => entry.value == main,
              orElse: () => const MapEntry('all', 'الكل'),
            )
            .key,
      ),
      amountShortcuts: const ['أعلى مبلغ', 'أقل مبلغ'],
      documentStates: const [],
      sections: const [
        AppFilterSection.mainCategory,
        AppFilterSection.subCategory,
        AppFilterSection.status,
        AppFilterSection.amount,
        AppFilterSection.document,
        AppFilterSection.date,
        AppFilterSection.people,
        AppFilterSection.delegates,
        AppFilterSection.place,
      ],
      onApply: (values) => setState(() {
        _selectedFilter = labels.entries
            .firstWhere(
              (entry) => entry.value == values.mainCategory,
              orElse: () => const MapEntry('all', 'الكل'),
            )
            .key;
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

  void _openAddAssetSheet({
    String initialType = 'عقار',
    bool lockType = false,
  }) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final locationController = TextEditingController();
    final unitsController = TextEditingController();
    final apartmentsController = TextEditingController();
    final shopsController = TextEditingController();
    final ownerController = TextEditingController();
    final annualRentController = TextEditingController();
    final startDateController = TextEditingController();
    final periodController = TextEditingController();
    final otherAnnexController = TextEditingController();
    final annexCounts = <String, int>{
      for (final label in _propertyAnnexLabels) label: 0,
    };
    String selectedType = initialType;
    bool quickAddEnabled = false;
    bool subleaseEnabled = false;
    String paymentCycle = 'شهري';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isBuilding =
                selectedType == 'عقار' ||
                selectedType == 'فيلا' ||
                selectedType == 'مزرعة';
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'إضافة أصل / نشاط',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (lockType)
                        InputDecorator(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                            labelText: 'نوع النشاط المختار',
                          ),
                          child: Text(
                            selectedType,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: selectedType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                            labelText: 'نوع النشاط',
                          ),
                          items:
                              const [
                                    'عقار',
                                    'مشروع',
                                    'نشاط تجاري',
                                    'معدات',
                                    'أرض',
                                    'متجر',
                                    'مكتب',
                                    'مستودع',
                                    'فيلا',
                                    'مزرعة',
                                    'مطعم',
                                  ]
                                  .map(
                                    (t) => DropdownMenuItem<String>(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => selectedType = v);
                          },
                        ),
                      const SizedBox(height: 8),
                      _field(titleController, 'الاسم'),
                      const SizedBox(height: 8),
                      _field(descController, 'الوصف'),
                      if (isBuilding) ...[
                        const SizedBox(height: 8),
                        _PropertyAnnexesEditor(
                          counts: annexCounts,
                          otherController: otherAnnexController,
                          onCountChanged: (label, count) =>
                              setModalState(() => annexCounts[label] = count),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _field(locationController, 'الموقع (يدعم تحديد الخريطة)'),
                      if (isBuilding) ...[
                        const SizedBox(height: 8),
                        _field(unitsController, 'عدد الوحدات', numeric: true),
                        const SizedBox(height: 8),
                        _field(
                          apartmentsController,
                          'عدد الشقق',
                          numeric: true,
                        ),
                        const SizedBox(height: 8),
                        _field(shopsController, 'عدد المحلات', numeric: true),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'تفعيل الإضافة السريعة للوحدات',
                            textAlign: TextAlign.right,
                          ),
                          value: quickAddEnabled,
                          onChanged: (v) =>
                              setModalState(() => quickAddEnabled = v),
                        ),
                      ],
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'تفعيل الإيجار من الباطن',
                          textAlign: TextAlign.right,
                        ),
                        value: subleaseEnabled,
                        onChanged: (v) =>
                            setModalState(() => subleaseEnabled = v),
                      ),
                      if (subleaseEnabled) ...[
                        const SizedBox(height: 8),
                        _field(ownerController, 'اسم المالك الخارجي'),
                        const SizedBox(height: 8),
                        _field(
                          annualRentController,
                          'الإيجار السنوي',
                          numeric: true,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: paymentCycle,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                            labelText: 'دورة الدفع',
                          ),
                          items:
                              const [
                                    'شهري',
                                    'كل 3 شهور',
                                    'كل 4 شهور',
                                    'كل 6 شهور',
                                    'سنوي',
                                  ]
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() => paymentCycle = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        _field(startDateController, 'تاريخ البداية'),
                        const SizedBox(height: 8),
                        _field(periodController, 'مدة الاتفاق'),
                      ],
                      const SizedBox(height: 10),
                      const _HintBlock(
                        title: 'يحتوي كل عنصر على',
                        content:
                            'العقود، الصيانة، الإيجارات، المصروفات، الإيرادات، المستندات',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (titleController.text.trim().isEmpty) return;
                            final category = _resolveCategory(selectedType);
                            final item = _AssetItem(
                              title: titleController.text.trim(),
                              subType: selectedType,
                              category: category,
                              locationOrType:
                                  locationController.text.trim().isEmpty
                                  ? 'غير محدد'
                                  : locationController.text.trim(),
                              status: 'نشط',
                              amountLabel:
                                  annualRentController.text.trim().isEmpty
                                  ? '0 ${AppSettings.currencySuffix}'
                                  : '${annualRentController.text.trim()} ${AppSettings.currencySuffix}',
                              followupNote:
                                  'تم الإنشاء وبانتظار استكمال البيانات',
                              description: descController.text.trim(),
                              annexes: {
                                for (final entry in annexCounts.entries)
                                  if (entry.value > 0) entry.key: entry.value,
                                if (otherAnnexController.text.trim().isNotEmpty)
                                  'أخرى: ${otherAnnexController.text.trim()}':
                                      1,
                              },
                              owner: ownerController.text.trim().isEmpty
                                  ? 'غير محدد'
                                  : ownerController.text.trim(),
                              tenant: 'غير محدد',
                              rentValue:
                                  annualRentController.text.trim().isEmpty
                                  ? 'غير محدد'
                                  : '${annualRentController.text.trim()} سنويًا',
                              endDate: 'غير محدد',
                              annualYield: 'غير محدد',
                              occupancyRate: 0.0,
                              contractProgress: 0.0,
                              paymentProgress: 0.0,
                              documentsProgress: 0.0,
                              needsAttention: false,
                              documents: const [],
                              contracts: const [],
                              tasks: const [],
                              alerts: const [],
                              logs: [
                                'تم إنشاء الأصل: ${titleController.text.trim()}',
                                if (quickAddEnabled)
                                  'تم تفعيل الإضافة السريعة للوحدات',
                                if (subleaseEnabled)
                                  'إيجار من الباطن ($paymentCycle) ${startDateController.text.trim()}',
                              ],
                              createdAt: DateTime.now(),
                            );
                            Navigator.of(context).pop();
                            await _createAssetRemote(item);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0B4A73),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('إنشاء'),
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

  void _openAddEntrySheet() {
    final typeOptions = <_AssetEntryTypeOption>[
      const _AssetEntryTypeOption(
        title: 'إضافة عقار',
        subtitle: 'عقار سكني أو استثماري',
        icon: Icons.apartment_rounded,
        color: Color(0xFF0EA5A6),
      ),
      const _AssetEntryTypeOption(
        title: 'إضافة نشاط تجاري',
        subtitle: 'نشاط بيع أو خدمة',
        icon: Icons.storefront_rounded,
        color: Color(0xFFF97316),
      ),
      const _AssetEntryTypeOption(
        title: 'إضافة معدة',
        subtitle: 'معدات وأدوات تشغيل',
        icon: Icons.precision_manufacturing_rounded,
        color: Color(0xFF7C3AED),
      ),
      const _AssetEntryTypeOption(
        title: 'أخرى',
        subtitle: 'نوع إضافي آخر',
        icon: Icons.more_horiz_rounded,
        color: Color(0xFF64748B),
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxSheetHeight = MediaQuery.of(context).size.height * 0.82;
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'اختيار نوع الإضافة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'اختر نوع النشاط الذي تريد إضافته',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(typeOptions.length, (index) {
                            final option = typeOptions[index];
                            return SizedBox(
                              width: cardWidth,
                              child: _AssetEntryActionCard(
                                key: ValueKey('projects-entry-type-$index'),
                                title: option.title,
                                subtitle: option.subtitle,
                                icon: option.icon,
                                color: option.color,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  if (option.title == 'إضافة عقار') {
                                    _openAddPropertyWizard();
                                    return;
                                  }
                                  if (option.title == 'إضافة نشاط تجاري') {
                                    _openAddBusinessActivity();
                                    return;
                                  }
                                  if (option.title == 'إضافة معدة') {
                                    _openAddEquipment();
                                    return;
                                  }
                                  _openAddAssetSheet(
                                    initialType: option.title,
                                    lockType: true,
                                  );
                                },
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _resolveCategory(String type) {
    if (type == 'نشاط تجاري' ||
        type == 'متجر' ||
        type == 'مطعم' ||
        type == 'مكتب') {
      return 'activity';
    }
    if (type == 'معدات') return 'equipment';
    if (type == 'مشروع') return 'other';
    return 'real_estate';
  }

  // مسار "إضافة عقار" الجديد: مستخرج من الفيديو المرجعي (وصف + عنوان
  // + عدد وحدات → تفاصيل كل وحدة → مراجعة البيانات) — يحل محل النموذج
  // القديم (الشيت العام) خصيصاً لفئة العقارات، بنفس الشكل البصري المعتمد
  // في قوالب الالتزامات الشخصية والمشتركة وإدارة الأفراد والجهات.
  Future<void> _openAddPropertyWizard() async {
    final isSublease = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _PropertyOwnershipStepScreen()),
    );
    if (isSublease == null || !mounted) return;

    final propertyType = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _PropertyTypeGridScreen()),
    );
    if (propertyType == null || !mounted) return;

    final result = await Navigator.of(context).push<_PropertyDraft>(
      MaterialPageRoute(
        builder: (_) => _AddPropertyStep1Screen(propertyType: propertyType),
      ),
    );
    if (result == null || !mounted) return;
    final unitsLabel = result.units.isEmpty
        ? 'بدون وحدات'
        : '${result.units.length} وحدة';
    final coords = _parseLatLngFromMapLink(result.mapLink);
    final item = _AssetItem(
      title: result.description.isEmpty ? 'عقار جديد' : result.description,
      subType: result.units.length > 1
          ? 'عمارة'
          : (result.units.isNotEmpty ? result.units.first.type : propertyType),
      category: 'real_estate',
      isSublease: isSublease,
      locationOrType: result.address.isEmpty ? 'غير محدد' : result.address,
      status: 'نشط',
      amountLabel: '0 ${AppSettings.currencySuffix}',
      followupNote: 'تم الإنشاء وبانتظار استكمال البيانات',
      description: result.description,
      owner: 'غير محدد',
      tenant: 'غير محدد',
      rentValue: 'غير محدد',
      endDate: 'غير محدد',
      annualYield: 'غير محدد',
      occupancyRate: 0.0,
      contractProgress: 0.0,
      paymentProgress: 0.0,
      documentsProgress: 0.0,
      needsAttention: false,
      documents: const [],
      contracts: const [],
      tasks: const [],
      alerts: const [],
      // المرافق المختارة تُحفظ في ملحقات العقار وتظهر في تفاصيله.
      annexes: {for (final facility in result.facilities) facility: 1},
      logs: [
        'تمت إضافة العقار بـ $unitsLabel'
            '${result.facilities.isEmpty ? '' : ' ومرافق: ${result.facilities.join('، ')}'}',
      ],
      createdAt: DateTime.now(),
      units: result.units,
      mapLink: result.mapLink,
      quickAddEnabled: result.quickAddEnabled,
      latitude: coords?.$1,
      longitude: coords?.$2,
    );
    await _createAssetRemote(item);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تمت إضافة العقار')));
  }

  // "إضافة نشاط تجاري" الجديدة — بنفس الشكل البصري المعتمد لصفحة إضافة
  // العقار (هيدر أبيض 60 + عنوان w900 + سهم رجوع)، مع حقول مبنية على
  // المتطلبات المنطقية لأي نشاط تجاري: الترخيص، نوع النشاط، الموقع،
  // المسؤول، وفريق الموظفين (قائمة قابلة للتكرار مثل وحدات العقار).
  Future<void> _openAddBusinessActivity() async {
    final result = await Navigator.of(context).push<_ActivityDraft>(
      MaterialPageRoute(builder: (_) => const _AddBusinessActivityScreen()),
    );
    if (result == null || !mounted) return;
    // رقم الرخصة كان يُحفظ فقط داخل قائمة "contracts" المحلية التي لا يوجد
    // لها عمود مقابل في ProjectAssetRecord (تُصفَّر دائمًا عند القراءة من
    // الخادم)، فيختفي رقم الرخصة نهائيًا بعد أول تحديث. يُدمَج هنا مع
    // ملاحظة المتابعة الفعلية (followupNote) التي تُحفظ فعليًا.
    final activityFollowupParts = [
      if (result.licenseNumber.isNotEmpty)
        'رخصة تجارية رقم ${result.licenseNumber}',
      if (result.licenseExpiry.isNotEmpty)
        'الرخصة تنتهي بتاريخ ${result.licenseExpiry}',
    ];
    final item = _AssetItem(
      title: result.name.isEmpty ? 'نشاط تجاري جديد' : result.name,
      subType: result.activityType,
      category: 'activity',
      locationOrType: result.address.isEmpty ? 'غير محدد' : result.address,
      status: 'نشط',
      amountLabel: result.capital.isEmpty ? '0 ${AppSettings.currencySuffix}' : '${result.capital} ${AppSettings.currencySuffix}',
      followupNote: activityFollowupParts.isEmpty
          ? 'تم الإنشاء وبانتظار استكمال البيانات'
          : activityFollowupParts.join(' • '),
      description: result.notes,
      owner: result.manager.isEmpty ? 'غير محدد' : result.manager,
      tenant: 'غير محدد',
      rentValue: 'غير محدد',
      endDate: result.licenseExpiry.isEmpty ? 'غير محدد' : result.licenseExpiry,
      annualYield: 'غير محدد',
      occupancyRate: 0.0,
      contractProgress: 0.0,
      paymentProgress: 0.0,
      documentsProgress: 0.0,
      needsAttention: false,
      documents: const [],
      contracts: const [],
      tasks: const [],
      alerts: const [],
      logs: [
        'تم إنشاء النشاط التجاري: ${result.name}',
        if (result.employees.isNotEmpty)
          'تمت إضافة ${result.employees.length} موظف',
      ],
      createdAt: DateTime.now(),
      employees: result.employees,
    );
    await _createAssetRemote(item);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تمت إضافة النشاط التجاري')));
  }

  // "إضافة معدة" الجديدة — بنفس القالب البصري، بحقول تقنية مبنية على
  // المتطلبات المنطقية لتتبع أي معدة: الرقم التسلسلي، الشراء والضمان،
  // المورد، الموقع المخصصة له، وحالتها التشغيلية.
  Future<void> _openAddEquipment() async {
    final result = await Navigator.of(context).push<_EquipmentDraft>(
      MaterialPageRoute(builder: (_) => const _AddEquipmentScreen()),
    );
    if (result == null || !mounted) return;
    // "تاريخ الشراء" لا يقابله عمود مستقل في ProjectAssetRecord؛ كان يُلتقط
    // في النموذج ثم يُهمَل تمامًا عند الحفظ. يُدمَج هنا مع ملاحظة المتابعة
    // الفعلية بدل أن يبقى إدخالًا شكليًا بلا أثر.
    final equipmentFollowupParts = [
      if (result.purchaseDate.isNotEmpty)
        'تاريخ الشراء ${result.purchaseDate}',
      if (result.warrantyExpiry.isNotEmpty)
        'الضمان ينتهي بتاريخ ${result.warrantyExpiry}',
    ];
    final item = _AssetItem(
      title: result.name.isEmpty ? 'معدة جديدة' : result.name,
      subType: result.equipmentType.isEmpty ? 'معدة' : result.equipmentType,
      category: 'equipment',
      locationOrType: result.assignedLocation.isEmpty
          ? 'غير محدد'
          : result.assignedLocation,
      status: result.condition.isEmpty ? 'تعمل' : result.condition,
      amountLabel: result.value.isEmpty ? '0 ${AppSettings.currencySuffix}' : '${result.value} ${AppSettings.currencySuffix}',
      followupNote: equipmentFollowupParts.isEmpty
          ? 'تم الإنشاء وبانتظار استكمال البيانات'
          : equipmentFollowupParts.join(' • '),
      description: result.notes,
      owner: result.supplier.isEmpty ? 'غير محدد' : result.supplier,
      tenant: 'غير محدد',
      rentValue: 'غير محدد',
      endDate: result.warrantyExpiry.isEmpty
          ? 'غير محدد'
          : result.warrantyExpiry,
      annualYield: 'غير محدد',
      occupancyRate: 0.0,
      contractProgress: 0.0,
      paymentProgress: 0.0,
      documentsProgress: 0.0,
      needsAttention: result.condition == 'تحت الصيانة',
      documents: const [],
      contracts: const [],
      tasks: const [],
      alerts: const [],
      logs: ['تم إنشاء المعدة: ${result.name}'],
      createdAt: DateTime.now(),
      serialNumber: result.serialNumber,
    );
    await _createAssetRemote(item);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تمت إضافة المعدة')));
  }

  Widget _field(TextEditingController c, String hint, {bool numeric = false}) {
    return TextField(
      controller: c,
      textDirection: TextDirection.rtl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems();
    final selectedAssets = _items
        .where((item) => _matchesFilter(item, _selectedFilter))
        .toList();
    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        screenId: 'projects_activities',
        onPressed: _openAddEntrySheet,
        label: 'إضافة',
        backgroundColor: const Color(0xFF047857),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          slivers: [
            ManagementDashboardHeader(
              title: 'العقارات / الأنشطة التجارية / المعدات وأخرى',
              subtitle: 'متابعة الأصول والتجارة والمهام والأداء',
              icon: Icons.business_center_rounded,
              colors: const [Color(0xFF065F46), Color(0xFF0F766E)],
              onSmartCalendarTap: _openSmartCalendar,
              onClose: () => Navigator.of(context).pop(),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              sliver: SliverToBoxAdapter(
                child: ManagementSearchBar(
                  controller: _searchController,
                  hint: 'ابحث في جميع المشاريع والأنشطة...',
                  accentColor: const Color(0xFF047857),
                  searchId: 'projects_activities',
                  suggestions: _items
                      .map((asset) => asset.title)
                      .toList(growable: false),
                  onFilterTap: _openFilterSheet,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            // مركز المتابعة يتحرّك مع الصفحة ويختفي عند النزول لأسفل،
            // بدل تثبيت الكتلة كاملة بارتفاع مفترض (242).
            SliverToBoxAdapter(
              child: ColoredBox(
                color: AppTheme.page,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ManagementFollowUpCenter(
                    subtitle: _selectedFilter == 'all'
                        ? 'الأهم والأقرب من جميع الأصول والأنشطة'
                        : 'متابعة ${_filters.firstWhere((item) => item.key == _selectedFilter).label}',
                    accentColor: const Color(0xFF047857),
                    onMore: () => _openFollowUpSheet(selectedAssets),
                    // المؤشرات الثلاثة مبنية من مجموعات مركز المتابعة
                    // نفسها — كالالتزامات الشخصية، فتتطابق الأرقام بين
                    // البطاقة المصغّرة ونافذة "المزيد".
                    metrics: [
                      for (final group in _followUpGroups(
                        selectedAssets,
                      ).take(3))
                        ManagementMetricData(
                          label: group.title,
                          count: group.total,
                          icon: group.icon,
                          color: group.color,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // عنوان "الفئات" يمرّ مع الصفحة، وشريط الشرائح وحده يثبت.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: const Text(
                  'الفئات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ),
            MeasuredPinnedHeader(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // بلا عنوان "الفئات" — كبقية الشاشات.
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      key: const ValueKey('projects-category-list'),
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final selected = _selectedFilter == filter.key;
                        final count = _countByCategory(filter.key);
                        return ManagementCategoryTab(
                          label: filter.label,
                          count: count,
                          icon: _filterIcon(filter.key),
                          color: filter.color,
                          selected: selected,
                          // تغيير الفئة يمسح النوع الفرعي: نوع فرعي من
                          // فئة أخرى يُفرغ القائمة بلا تفسير.
                          onTap: () => setState(() {
                            _selectedFilter = filter.key;
                            _filter.subCategory = null;
                            // "شاغر" غير متاح للأنشطة التجارية، فلا يبقى
                            // مختارًا وهو خارج القائمة.
                            if (!_quickSortOptions().contains(_selectedSort)) {
                              _selectedSort = 'الأحدث أولاً';
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  // عنوان القائمة وزر الترتيب مثبَّتان مع الفئات، كبقية
                  // الشاشات: كانا ينزلقان تحت الرأس المثبَّت عند التمرير.
                  ManagementSortHeader(
                    value: _selectedSort,
                    // الفلتر الصغير — كما في ملف "فلاتر فوندلي": "شاغر"
                    // للعقارات والمعدات فقط، لأن الأنشطة التجارية بلا وحدات.
                    options: _quickSortOptions(),
                    onSelected: (value) =>
                        setState(() => _selectedSort = value),
                    title: _selectedFilter == 'all'
                        ? 'جميع الأصول والأنشطة'
                        : _filters
                              .firstWhere((item) => item.key == _selectedFilter)
                              .label,
                    count: filtered.length,
                    accentColor: const Color(0xFF047857),
                  ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoadingRemote)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  ...filtered.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      // بطاقة واحدة لكل الفئات: كان العقار ببطاقة خاصة
                      // أطول وأغزر بيانات، فيبدو صف القائمة متفاوت
                      // الارتفاع بين عقار ومعدة ونشاط تجاري.
                      child: ManagementCompactCard(
                              title: item.title,
                              category: _assetSubtitle(item),
                              date: item.endDate,
                              value: item.amountLabel,
                              status: item.isFrozen
                                  ? 'مجمّد'
                                  : (item.needsAttention
                                        ? 'متابعة'
                                        : item.status),
                              icon: _filterIcon(item.category),
                              accentColor:
                                  item.iconColor ?? const Color(0xFF047857),
                              statusColor: item.isFrozen
                                  ? const Color(0xFF64748B)
                                  : (item.needsAttention
                                        ? const Color(0xFFE11D48)
                                        : const Color(0xFF10B981)),
                              onTap: () => _openDetails(item),
                            ),
                    ),
                  ),
                  if (filtered.isEmpty)
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

  void _openSmartCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SmartCalendarScreen()));
  }
}

class ProjectAssetDetailsScreen extends StatefulWidget {
  const ProjectAssetDetailsScreen({
    super.key,
    required this.item,
    this.repository,
    this.onItemChanged,
    this.onItemDeleted,
  });

  final _AssetItem item;
  final ProjectAssetsRepository? repository;
  final ValueChanged<_AssetItem>? onItemChanged;
  final ValueChanged<_AssetItem>? onItemDeleted;

  @override
  State<ProjectAssetDetailsScreen> createState() =>
      _ProjectAssetDetailsScreenState();
}

class _ProjectAssetDetailsScreenState extends State<ProjectAssetDetailsScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// نوع الوحدة المفتوح من بطاقة "الوحدات" (null = عرض كل الوحدات،
  /// و[_kVacantUnitsKey] = الشاغرة فقط).
  String? _openUnitType;
  int _selectedTab = 0;
  int _selectedSecondaryTab = 0;
  late _AssetItem _item;

  late List<String> _documents;
  late List<String> _contracts;
  late List<String> _tasks;

  static const _entryKindContract = 'contract';
  static const _entryKindMaintenance = 'maintenance';
  static const _entryKindRental = 'rental';
  static const _entryKindExpense = 'expense';
  static const _entryKindRevenue = 'revenue';
  static const _entryKindDocument = 'document';
  static const _peopleStorageKey = 'people_management_records_v1';

  final List<_ActionGroup> _groups = const [
    _ActionGroup(
      title: 'العقود',
      kind: _entryKindContract,
      color: Color(0xFF0F6AA8),
      icon: Icons.description_rounded,
      fields: [
        _FieldDef('اسم العقد', false),
        _FieldDef('الطرف الآخر', false),
        _FieldDef('تاريخ البداية', false, isDate: true),
        _FieldDef('تاريخ الانتهاء', false, isDate: true),
        _FieldDef(
          'التذكير قبل الانتهاء',
          false,
          options: [
            'قبل أسبوع',
            'قبل يوم',
            'قبل 3 أيام',
            'قبل أسبوعين',
            'قبل شهر',
          ],
        ),
        _FieldDef('قيمة العقد', true),
        _FieldDef('ملاحظات', false, multiline: true),
      ],
    ),
    _ActionGroup(
      title: 'الصيانة',
      kind: _entryKindMaintenance,
      color: Color(0xFFF97316),
      icon: Icons.build_rounded,
      fields: [
        _FieldDef('وصف العطل', false),
        _FieldDef('الأولوية', false),
        _FieldDef('تاريخ الطلب', false, isDate: true),
        _FieldDef('تاريخ التنفيذ', false, isDate: true),
        _FieldDef('التكلفة', true),
        _FieldDef('الفني / المقاول', false),
      ],
    ),
    _ActionGroup(
      title: 'الإيجارات',
      kind: _entryKindRental,
      color: Color(0xFF10B981),
      icon: Icons.home_work_rounded,
      fields: [
        _FieldDef('اسم المستأجر', false),
        _FieldDef('الوحدة / الرقم', false),
        _FieldDef('قيمة الإيجار', true),
        _FieldDef('تاريخ البداية', false, isDate: true),
        _FieldDef('تاريخ الانتهاء', false, isDate: true),
        _FieldDef('دورة الدفع', false),
      ],
    ),
    _ActionGroup(
      title: 'المصروفات',
      kind: _entryKindExpense,
      color: Color(0xFFE11D48),
      icon: Icons.trending_down_rounded,
      fields: [
        _FieldDef('البند', false),
        _FieldDef('المبلغ', true),
        _FieldDef('تاريخ المصروف', false, isDate: true),
        _FieldDef('الفئة', false),
        _FieldDef('ملاحظات', false, multiline: true),
      ],
    ),
    _ActionGroup(
      title: 'الإيرادات',
      kind: _entryKindRevenue,
      color: Color(0xFF16A34A),
      icon: Icons.trending_up_rounded,
      fields: [
        _FieldDef('المصدر', false),
        _FieldDef('المبلغ', true),
        _FieldDef('تاريخ الإيراد', false, isDate: true),
        _FieldDef('الفئة', false),
        _FieldDef('ملاحظات', false, multiline: true),
      ],
    ),
    _ActionGroup(
      title: 'المستندات',
      kind: _entryKindDocument,
      color: Color(0xFF7C3AED),
      icon: Icons.folder_copy_rounded,
      fields: [
        _FieldDef('اسم المستند', false),
        _FieldDef(
          'نوع المستند',
          false,
          options: ['مستند', 'إيصال', 'ضمان', 'فاتورة', 'تقرير ضريبي', 'إنذار'],
        ),
        _FieldDef('تاريخ الانتهاء', false, isDate: true),
        _FieldDef(
          'التذكير قبل الانتهاء',
          false,
          options: [
            'قبل أسبوع',
            'قبل يوم',
            'قبل 3 أيام',
            'قبل أسبوعين',
            'قبل شهر',
          ],
        ),
        _FieldDef('ملاحظات', false, multiline: true),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _documents = List<String>.from(widget.item.documents);
    _contracts = List<String>.from(widget.item.contracts);
    _tasks = List<String>.from(widget.item.tasks);
    _entriesByKind = {
      _entryKindContract: _cloneEntries(
        widget.item.contracts.map(
          (name) => <String, String>{'اسم العقد': name},
        ),
      ),
      _entryKindMaintenance: _cloneEntries(widget.item.maintenance),
      _entryKindRental: _cloneEntries(widget.item.rentals),
      _entryKindExpense: _cloneEntries(widget.item.expenses),
      _entryKindRevenue: _cloneEntries(widget.item.revenues),
      _entryKindDocument: _cloneEntries(
        widget.item.documents.map(
          (name) => <String, String>{'اسم المستند': name},
        ),
      ),
    };
    // تحميل العقود/الصيانة/الإيجارات/المصروفات/الإيرادات/المستندات الفعلية
    // من جدول project_asset_entries: كانت هذه القائمة تُبنى محليًا فقط من
    // قوائم قديمة فارغة دائمًا (widget.item.contracts وغيرها تُصفَّر عند كل
    // تحميل من الخادم)، فتختفي كل البيانات المُدخلة سابقًا فور إعادة فتح
    // شاشة التفاصيل.
    _loadEntriesFromRemote();
    _loadUnitContractsFromRemote();
  }

  List<PropertyUnitContractRecord> _unitContracts = const [];

  Future<void> _loadUnitContractsFromRemote() async {
    final repository = widget.repository;
    final assetId = widget.item.id;
    if (repository == null || assetId == null || assetId.isEmpty) return;
    try {
      final contracts = await repository.fetchUnitContracts(assetId);
      if (!mounted) return;
      setState(() => _unitContracts = contracts);
    } catch (_) {
      // تُترك القائمة فارغة عند الفشل بدل عرض خطأ يعطّل تبويب الوحدات كاملاً.
    }
  }

  /// أحدث عقد نشط (غير منتهٍ) لوحدة معيّنة، إن وُجد.
  PropertyUnitContractRecord? _activeContractForUnit(String unitKey) {
    for (final c in _unitContracts) {
      if (c.unitKey == unitKey && c.status != PropertyUnitContractRecord.statusExpired) {
        return c;
      }
    }
    return null;
  }

  /// عقد نشط "تمثيلي" يُعرض على خريطة رأس العقار — يُستخدم فقط عندما يكون
  /// العقار نفسه إيجارًا من الباطن (isSublease)، لعرض لمحة سريعة عن أحد
  /// عقود الوحدات النشطة فيه (بيانات حقيقية من قاعدة البيانات، وليست بيانات
  /// وهمية).
  PropertyUnitContractRecord? get _representativeContract {
    if (!_item.isSublease) return null;
    for (final c in _unitContracts) {
      if (c.status != PropertyUnitContractRecord.statusExpired) return c;
    }
    return null;
  }

  /// يجمع الوحدات المشتركة في نفس عقد "متعدد الوحدات" (group_key واحد)
  /// لعرضها كبطاقة واحدة موحّدة بدل بطاقة منفصلة لكل وحدة.
  Map<String, List<_PropertyUnit>> _multiUnitGroups() {
    final groups = <String, List<_PropertyUnit>>{};
    for (final unit in _item.units) {
      final contract = _activeContractForUnit(unit.unitKey);
      if (contract?.groupKey == null) continue;
      groups.putIfAbsent(contract!.groupKey!, () => []).add(unit);
    }
    return groups;
  }

  Future<void> _openMultiUnitContractForm() async {
    final assetId = _item.id;
    final repository = widget.repository;
    if (assetId == null || repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب حفظ العقار أولاً قبل إنشاء عقد متعدد الوحدات')),
      );
      return;
    }
    final vacantUnits = _item.units
        .where((u) => _activeContractForUnit(u.unitKey) == null)
        .toList();
    if (vacantUnits.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يلزم وجود وحدتين شاغرتين على الأقل لإنشاء عقد متعدد الوحدات'),
        ),
      );
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MultiUnitContractFormScreen(
          assetId: assetId,
          vacantUnits: vacantUnits,
          repository: repository,
        ),
      ),
    );
    if (created == true) {
      await _loadUnitContractsFromRemote();
      // تحديث حالة الوحدات المشمولة إلى "مؤجرة" محليًا وبالخادم.
      final units = List<_PropertyUnit>.from(_item.units);
      for (var i = 0; i < units.length; i++) {
        if (_activeContractForUnit(units[i].unitKey) != null ||
            vacantUnits.any((v) => v.unitKey == units[i].unitKey)) {
          units[i] = units[i].copyWith(status: 'مؤجرة');
        }
      }
      _updateItem(_item.copyWith(units: units));
    }
  }

  Future<void> _loadEntriesFromRemote() async {
    final repository = widget.repository;
    final assetId = widget.item.id;
    if (repository == null || assetId == null || assetId.isEmpty) return;
    try {
      final entries = await repository.fetchEntries(assetId);
      if (!mounted) return;
      final grouped = <String, List<Map<String, String>>>{
        for (final group in _groups) group.kind: [],
      };
      for (final entry in entries) {
        final data = Map<String, String>.from(entry.data);
        if (entry.id != null) data['_id'] = entry.id!;
        grouped[entry.kind]?.add(data);
      }
      setState(() {
        for (final group in _groups) {
          _entriesByKind[group.kind] = grouped[group.kind] ?? [];
        }
        _contracts
          ..clear()
          ..addAll(
            _entriesByKind[_entryKindContract]!.map(
              (e) => e['اسم العقد'] ?? '',
            ),
          );
        _documents
          ..clear()
          ..addAll(
            _entriesByKind[_entryKindDocument]!.map(
              (e) => e['اسم المستند'] ?? '',
            ),
          );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل سجلات الأصل: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _updateItem(_AssetItem updated) {
    setState(() => _item = updated);
    widget.onItemChanged?.call(updated);
  }

  void _onTopMenuAction(ThreeDotMenuAction action) {
    if (action == ThreeDotMenuAction.share) {
      Share.share(
        'تفاصيل ${_singularCategoryLabel(_item.category)}\n'
        'الاسم: ${_item.title}\n'
        'النوع: ${_item.subType}\n'
        'الحالة: ${_item.isFrozen ? 'مجمّد' : _item.status}\n'
        'الموقع: ${_item.locationOrType}\n'
        'القيمة: ${_item.amountLabel}',
      );
      return;
    }

    if (action == ThreeDotMenuAction.freeze) {
      _updateItem(_item.copyWith(isFrozen: !_item.isFrozen));
      return;
    }

    if (action == ThreeDotMenuAction.pinHome) {
      _updateItem(_item.copyWith(isPinned: !_item.isPinned));
      return;
    }

    if (action == ThreeDotMenuAction.archive) {
      _updateItem(
        _item.copyWith(status: 'مؤرشف', needsAttention: false, isFrozen: true),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت أرشفة الأصل')));
      return;
    }

    if (action == ThreeDotMenuAction.delete) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('حذف ${_singularCategoryLabel(_item.category)}'),
          content: Text('هل تريد حذف ${_item.title}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                widget.onItemDeleted?.call(_item);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      return;
    }

    if (action == ThreeDotMenuAction.edit) {
      final titleController = TextEditingController(text: _item.title);
      final locationController = TextEditingController(
        text: _item.locationOrType,
      );
      final ownerController = TextEditingController(text: _item.owner);
      final descriptionController = TextEditingController(
        text: _item.description,
      );
      final annexCounts = <String, int>{
        for (final label in _propertyAnnexLabels)
          label: _item.annexes[label] ?? 0,
      };
      final otherAnnex = _item.annexes.entries
          .where((entry) => entry.key.startsWith('أخرى: '))
          .map((entry) => entry.key.substring('أخرى: '.length))
          .join('، ');
      final otherAnnexController = TextEditingController(text: otherAnnex);
      final mapLinkController = TextEditingController(text: _item.mapLink);
      final latController = TextEditingController(
        text: _item.latitude?.toString() ?? '',
      );
      final lngController = TextEditingController(
        text: _item.longitude?.toString() ?? '',
      );
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تعديل البيانات',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'اسم ${_singularCategoryLabel(_item.category)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'الموقع/النوع',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ownerController,
                      decoration: const InputDecoration(labelText: 'المالك'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'الوصف العام',
                      ),
                    ),
                    if (_item.category == 'real_estate') ...[
                      const SizedBox(height: 8),
                      _PropertyAnnexesEditor(
                        counts: annexCounts,
                        otherController: otherAnnexController,
                        onCountChanged: (label, count) =>
                            setModalState(() => annexCounts[label] = count),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mapLinkController,
                        decoration: const InputDecoration(
                          labelText: 'رابط الموقع على خرائط جوجل',
                          hintText: 'الصق رابط Google Maps هنا',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'تُستخرج الإحداثيات تلقائيًا من الرابط لعرض خريطة العقار — أو أدخلها يدويًا أدناه.',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latController,
                              keyboardType: const TextInputType.numberWithOptions(
                                signed: true,
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'خط العرض (اختياري)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: lngController,
                              keyboardType: const TextInputType.numberWithOptions(
                                signed: true,
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'خط الطول (اختياري)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final manualLat = double.tryParse(
                          latController.text.trim(),
                        );
                        final manualLng = double.tryParse(
                          lngController.text.trim(),
                        );
                        final parsedFromLink = _parseLatLngFromMapLink(
                          mapLinkController.text,
                        );
                        _updateItem(
                          _item.copyWith(
                            title: titleController.text.trim().isEmpty
                                ? _item.title
                                : titleController.text.trim(),
                            locationOrType:
                                locationController.text.trim().isEmpty
                                ? _item.locationOrType
                                : locationController.text.trim(),
                            owner: ownerController.text.trim().isEmpty
                                ? _item.owner
                                : ownerController.text.trim(),
                            description: descriptionController.text.trim(),
                            annexes: {
                              for (final entry in annexCounts.entries)
                                if (entry.value > 0) entry.key: entry.value,
                              if (otherAnnexController.text.trim().isNotEmpty)
                                'أخرى: ${otherAnnexController.text.trim()}': 1,
                            },
                            mapLink: mapLinkController.text.trim(),
                            latitude:
                                manualLat ?? parsedFromLink?.$1 ?? _item.latitude,
                            longitude:
                                manualLng ?? parsedFromLink?.$2 ?? _item.longitude,
                          ),
                        );
                        Navigator.pop(context);
                      },
                      child: const Text('حفظ التعديل'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  late Map<String, List<Map<String, String>>> _entriesByKind;

  List<Map<String, String>> _cloneEntries(Iterable<Map<String, String>> src) =>
      src.map((e) => Map<String, String>.from(e)).toList();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _mainTabsFor(_AssetItem item) {
    if (item.category == 'activity') {
      return const ['الملخص', 'المالية', 'العملاء', 'الموردون', 'الأشخاص'];
    }
    return const ['الملخص', 'العقود', 'الأشخاص', 'المالية', 'الصيانة'];
  }

  List<String> _secondaryTabsFor(_AssetItem item) {
    if (item.category == 'activity') {
      return const ['الأصول والمعدات', 'المستندات', 'المهام'];
    }
    return const ['المستندات', 'المهام'];
  }

  void _openActionForm(
    _ActionGroup group, {
    Map<String, String>? existing,
    int? editIndex,
  }) {
    final controllers = {
      for (final field in group.fields)
        field.label: TextEditingController(
          text: existing?[field.label] ?? field.options?.first ?? '',
        ),
    };
    final isEditing = existing != null && editIndex != null;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: SingleChildScrollView(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: group.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(group.icon, color: group.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEditing
                                        ? 'تعديل ${group.title}'
                                        : 'إضافة إلى ${group.title}',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Text(
                                    'أدخل البيانات المطلوبة',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...group.fields.map((field) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: field.options != null
                                ? DropdownButtonFormField<String>(
                                    initialValue:
                                        controllers[field.label]!.text,
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
                                    maxLines: field.multiline ? 3 : 1,
                                    textDirection: TextDirection.rtl,
                                    keyboardType: field.isNumeric
                                        ? const TextInputType.numberWithOptions(
                                            decimal: true,
                                          )
                                        : (field.multiline
                                              ? TextInputType.multiline
                                              : TextInputType.text),
                                    decoration: InputDecoration(
                                      labelText: field.label,
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      isDense: true,
                                      suffixIcon: field.isDate
                                          ? Icon(
                                              Icons.event_rounded,
                                              color: group.color,
                                            )
                                          : null,
                                    ),
                                    onTap: field.isDate
                                        ? () async {
                                            final date = await showDatePicker(
                                              context: context,
                                              initialDate: DateTime.now(),
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2035),
                                            );
                                            if (date != null) {
                                              setModalState(() {
                                                controllers[field.label]!.text =
                                                    '${date.day}/${date.month}/${date.year}';
                                              });
                                            }
                                          }
                                        : null,
                                  ),
                          );
                        }),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final data = <String, String>{
                                for (final field in group.fields)
                                  field.label: controllers[field.label]!.text
                                      .trim(),
                              };
                              data['_reminder_id'] =
                                  existing?['_reminder_id'] ??
                                  'asset-entry-${DateTime.now().microsecondsSinceEpoch}';
                              final primaryLabel = group.fields.first.label;
                              if ((data[primaryLabel] ?? '').isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('أدخل $primaryLabel')),
                                );
                                return;
                              }
                              _persistEntry(group, data, editIndex: editIndex);
                              Navigator.of(context).pop();
                            },
                            icon: Icon(
                              isEditing
                                  ? Icons.save_rounded
                                  : Icons.check_rounded,
                            ),
                            label: Text(isEditing ? 'حفظ التعديل' : 'حفظ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: group.color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      for (final c in controllers.values) {
        c.dispose();
      }
    });
  }

  void _persistEntry(
    _ActionGroup group,
    Map<String, String> data, {
    int? editIndex,
  }) {
    final list = _entriesByKind[group.kind]!;
    setState(() {
      if (editIndex != null && editIndex >= 0 && editIndex < list.length) {
        list[editIndex] = data;
      } else {
        list.insert(0, data);
      }

      // Keep legacy string lists in sync for the summary chips.
      if (group.kind == _entryKindContract) {
        _contracts
          ..clear()
          ..addAll(list.map((e) => e['اسم العقد'] ?? ''));
      } else if (group.kind == _entryKindDocument) {
        _documents
          ..clear()
          ..addAll(list.map((e) => e['اسم المستند'] ?? ''));
      }
    });
    _syncEntryToRemote(group, data);
    _syncEntryReminder(group, data);
  }

  void _deleteEntry(_ActionGroup group, int index) {
    final list = _entriesByKind[group.kind]!;
    if (index < 0 || index >= list.length) return;
    final reminderId = list[index]['_reminder_id'];
    final entryId = list[index]['_id'];
    setState(() {
      list.removeAt(index);
      if (group.kind == _entryKindContract) {
        _contracts
          ..clear()
          ..addAll(list.map((e) => e['اسم العقد'] ?? ''));
      } else if (group.kind == _entryKindDocument) {
        _documents
          ..clear()
          ..addAll(list.map((e) => e['اسم المستند'] ?? ''));
      }
    });
    if (reminderId != null && reminderId.isNotEmpty) {
      AppRemindersStore.remove(reminderId);
    }
    // بدون هذا الاستدعاء يبقى السجل المحذوف محفوظًا في قاعدة البيانات إلى
    // الأبد رغم اختفائه من الشاشة، ويعود للظهور فور إعادة تحميل البيانات.
    if (entryId != null && entryId.isNotEmpty) {
      widget.repository?.deleteEntry(entryId).catchError((error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف السجل من قاعدة البيانات: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  Future<void> _syncEntryReminder(
    _ActionGroup group,
    Map<String, String> data,
  ) async {
    if (group.kind != _entryKindContract && group.kind != _entryKindDocument) {
      return;
    }
    final reminderId = data['_reminder_id'] ?? '';
    final expiry = AppRemindersStore.parseDisplayDate(
      data['تاريخ الانتهاء'] ?? '',
    );
    if (reminderId.isEmpty) return;
    if (expiry == null) {
      await AppRemindersStore.remove(reminderId);
      return;
    }
    await AppRemindersStore.upsert(
      AppReminder(
        id: reminderId,
        title: data[group.fields.first.label] ?? group.title,
        module: 'العقارات والأنشطة التجارية',
        expiryDate: expiry,
        remindBeforeDays: AppRemindersStore.reminderDaysFromLabel(
          data['التذكير قبل الانتهاء'] ?? '',
        ),
      ),
    );
  }

  Future<void> _syncEntryToRemote(
    _ActionGroup group,
    Map<String, String> data,
  ) async {
    final repository = widget.repository;
    final assetId = widget.item.id;
    if (repository == null || assetId == null || assetId.isEmpty) return;
    try {
      // تمرير المعرّف الحالي (إن وُجد) يجعل الاستدعاء تحديثًا لنفس السجل
      // بدل إنشاء سجل جديد مكرر في كل مرة يُعدَّل فيها هذا العنصر — بدون
      // هذا كانت كل عملية تعديل تُضاعف السجل على الخادم دون حذف القديم.
      final existingId = data['_id'];
      final saved = await repository.upsertEntry(
        ProjectAssetEntryRecord(
          id: (existingId != null && existingId.isNotEmpty)
              ? existingId
              : null,
          assetId: assetId,
          kind: group.kind,
          data: Map<String, String>.of(data)..remove('_id'),
        ),
      );
      if (!mounted || saved.id == null) return;
      final list = _entriesByKind[group.kind];
      if (list == null) return;
      final index = list.indexWhere(
        (entry) =>
            identical(entry, data) || (existingId != null && entry['_id'] == existingId),
      );
      if (index != -1) {
        setState(() => list[index]['_id'] = saved.id!);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر مزامنة بيانات ${group.title}: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openMainEntryTypesSheet() {
    // كانت هذه القائمة سابقًا تضم 8 مربعات، لكن أكثر من نصفها يفتح نموذجًا
    // لا علاقة له باسمه فعليًا (مثل "إضافة وحدة" التي كانت تفتح نموذج
    // الإيجارات بدل إنشاء وحدة عقارية حقيقية، و"إضافة رابط" التي كانت تفتح
    // نموذج المستندات رغم عدم وجود حقل رابط فيه). استُبدلت بمربع واحد فقط
    // لكل نوع سجلّ حقيقي موجود فعلًا في _groups، بالإضافة لمربع "وحدة" الذي
    // يستدعي _addUnit() الحقيقية (كانت غير قابلة للوصول من أي زر إطلاقًا).
    final quickAddOptions = [
      for (final group in _groups)
        (
          title: 'إضافة ${group.title}',
          icon: group.icon,
          color: group.color,
          onTap: () => _openActionForm(group),
        ),
      if (_item.category == 'real_estate')
        (
          title: 'إضافة وحدة',
          icon: Icons.home_work_outlined,
          color: const Color(0xFF10B981),
          onTap: _addUnit,
        ),
    ];

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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      'اختر نوع الإضافة المطلوب داخل تفاصيل العقار أو النشاط',
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
                    itemCount: quickAddOptions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.95,
                        ),
                    itemBuilder: (context, index) {
                      final option = quickAddOptions[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(context).pop();
                          option.onTap();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: option.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: option.color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: option.color,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  option.icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                option.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
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

  void _openDetailSectionsSheet() {
    final mainTabs = _mainTabsFor(widget.item);
    final secondaryTabs = _secondaryTabsFor(widget.item);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  children: List.generate(mainTabs.length, (index) {
                    final selected = _selectedTab == index;
                    return ChoiceChip(
                      label: Text(mainTabs[index]),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedTab = index);
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
                  children: List.generate(secondaryTabs.length, (index) {
                    final selected = _selectedSecondaryTab == index;
                    return ChoiceChip(
                      label: Text(secondaryTabs[index]),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _selectedSecondaryTab = index);
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

  Widget _buildFollowupLine(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0B4A73),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesQuery(String value) {
    final query = _searchController.text.trim();
    return query.isEmpty || value.contains(query);
  }

  List<String> _filterItems(List<String> items) {
    if (_searchController.text.trim().isEmpty) return items;
    return items.where(_matchesQuery).toList(growable: false);
  }

  Color _categoryColor(String key) {
    switch (key) {
      case 'real_estate':
        return const Color(0xFF0F6AA8);
      case 'activity':
        return const Color(0xFF10B981);
      case 'equipment':
        return const Color(0xFFF59E0B);
      case 'other':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF0B4A73);
    }
  }

  Color get _pageColor => Color.lerp(
    _item.iconColor ?? _categoryColor(_item.category),
    const Color(0xFF073B67),
    0.35,
  )!;

  static const List<DetailSectionTab> _realEstateTabs = [
    DetailSectionTab(label: 'الوحدات', icon: Icons.home_work_outlined),
    DetailSectionTab(
      label: 'الحركة المالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(label: 'المتابعات', icon: Icons.event_note_outlined),
    DetailSectionTab(label: 'الصيانة', icon: Icons.build_outlined),
    DetailSectionTab(label: 'الملاحظات', icon: Icons.sticky_note_2_outlined),
  ];

  void _addUnit() {
    // شاشة "إضافة الوحدات والمرافق العامة" الكاملة بدل نافذة النوع
    // والرقم القديمة: قائمة ثابتة يمينًا ونموذج يسارًا وحفظ لكل نوع
    // ومسودة تلقائية كل دقيقتين.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UnitsEntryScreen(
          assetKey: _item.id ?? _item.title,
          existingUnits: _item.units,
          existingAnnexes: _item.annexes,
          onCommit: (newUnits, annexes, logLine) {
            final mergedAnnexes = {..._item.annexes};
            annexes.forEach(
              (key, value) =>
                  mergedAnnexes[key] = (mergedAnnexes[key] ?? 0) + value,
            );
            _updateItem(
              _item.copyWith(
                units: [..._item.units, ...newUnits],
                annexes: mergedAnnexes,
                logs: [logLine, ..._item.logs],
              ),
            );
          },
        ),
      ),
    );
  }

  void _toggleUnitStatus(int index) {
    final units = List<_PropertyUnit>.from(_item.units);
    final unit = units[index];
    units[index] = unit.copyWith(
      status: unit.status == 'شاغرة' ? 'مؤجرة' : 'شاغرة',
    );
    _updateItem(_item.copyWith(units: units));
  }

  void _setUnitStatus(int index, String status) {
    final units = List<_PropertyUnit>.from(_item.units);
    if (units[index].status == status) return;
    units[index] = units[index].copyWith(status: status);
    _updateItem(_item.copyWith(units: units));
  }

  void _openUnitDetails(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UnitDetailsScreen(
          assetId: _item.id,
          assetTitle: _item.title,
          unit: _item.units[index],
          repository: widget.repository,
          onUnitStatusChanged: (status) => _setUnitStatus(index, status),
          assetLocation: _item.locationOrType,
          assetLatitude: _item.latitude,
          assetLongitude: _item.longitude,
        ),
      ),
    );
  }

  void _openUnitDetailsFor(_PropertyUnit unit) {
    final index = _item.units.indexWhere((u) => u.unitKey == unit.unitKey);
    if (index == -1) return;
    _openUnitDetails(index);
  }

  void _openMultiUnitContractSummary(List<_PropertyUnit> units) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'عقد متعدد الوحدات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _activeContractForUnit(units.first.unitKey)?.tenantName ??
                      '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                for (final unit in units)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      unit.name,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'الإيجار السنوي لهذه الوحدة: ${_activeContractForUnit(unit.unitKey)?.annualRent.toStringAsFixed(0) ?? '0'}',
                      textAlign: TextAlign.right,
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openUnitDetailsFor(unit);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRealEstateDetails(BuildContext context) {
    final item = _item;
    if (_selectedTab >= _realEstateTabs.length) _selectedTab = 0;
    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        key: const ValueKey('add-property-detail-entry'),
        screenId: 'asset_details_real_estate',
        onPressed: _selectedTab == 0
            ? _addUnit
            : _selectedTab == 1
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRental),
              )
            : _selectedTab == 2
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
              )
            : _selectedTab == 3
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
              )
            : _openMainEntryTypesSheet,
        label: '+ إضافة',
        icon: Icons.add_rounded,
        backgroundColor: _kPropertyColor,
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
          'تفاصيل العقار',
          style: TextStyle(
            fontSize: 19,
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
        // تحوّلت من ListView إلى CustomScrollView ليمكن تثبيت شريط
        // التبويبات: البطاقة العلوية تتحرّك وتختفي عند النزول، ويبقى
        // شريط التبويبات (الوحدات/العقود/...) ثابتًا في الأعلى.
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Container(
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                children: [
                  _AssetDetailHeaderCard(
                    item: item,
                    onAction: _onTopMenuAction,
                    icon: Icons.apartment_rounded,
                    accentColor: _kPropertyColor,
                  ),
                  if (item.latitude != null && item.longitude != null)
                    _LeaseMapHeader(
                      latitude: item.latitude!,
                      longitude: item.longitude!,
                      contract: _representativeContract,
                      isSublease: item.isSublease,
                      onManage: _representativeContract == null
                          ? null
                          : () {
                              final unit = item.units
                                  .where(
                                    (u) =>
                                        u.unitKey ==
                                        _representativeContract!.unitKey,
                                  )
                                  .toList();
                              if (unit.isNotEmpty) {
                                _openUnitDetailsFor(unit.first);
                              }
                            },
                    ),
                  if (item.units.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: OutlinedButton.icon(
                        onPressed: _openMultiUnitContractForm,
                        icon: const Icon(Icons.layers_rounded, size: 18),
                        label: const Text('أنشئ عقدًا متعدد الوحدات'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPropertyColor,
                          side: const BorderSide(color: _kPropertyColor),
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
              ),
            ),
            MeasuredPinnedHeader(
              background: AppTheme.page,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: DetailPageTabs(
                  sections: _realEstateTabs,
                  selectedIndex: _selectedTab,
                  color: _kPropertyColor,
                  onSelected: (i) => setState(() => _selectedTab = i),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 92),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('real-estate-tab-$_selectedTab'),
                    child: _buildRealEstateTabContent(item),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// هل تنتمي الوحدة إلى النوع (أو الحالة) المفتوح من بطاقة الوحدات؟
  bool _unitMatchesOpenType(_PropertyUnit unit) {
    final open = _openUnitType;
    if (open == null) return true;
    if (open == _kVacantUnitsKey) return unit.status == 'شاغرة';
    return unit.type == open;
  }

  Widget _buildRealEstateTabContent(_AssetItem item) {
    switch (_selectedTab) {
      case 0: // الوحدات
        if (item.units.isEmpty) {
          return const _DetailHintCard(
            message: 'لا توجد وحدات بعد — استخدم زر + إضافة لإضافة شقة أو محل جديد لهذا العقار.',
          );
        }
        final groups = _multiUnitGroups();
        final groupedUnitKeys = groups.values
            .expand((units) => units.map((u) => u.unitKey))
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // تركيبة العقار: عدد كل نوع وحدة + الشاغر، مبنية من الوحدات
            // نفسها فتشمل أي نوع يُضاف لاحقًا. كانت أعلى الصفحة بعيدة عن
            // الوحدات التي تصفها.
            _UnitsCompositionCard(
              units: item.units,
              selectedType: _openUnitType,
              // الضغط على نوع يفتح وحداته أسفل البطاقة، والضغط عليه ثانية
              // يعيد عرض كل الوحدات.
              onSelectType: (type) => setState(
                () => _openUnitType = _openUnitType == type ? null : type,
              ),
            ),
            const SizedBox(height: 10),
            // عند فتح نوع معيّن تُعرض وحداته وحدها (بما فيها المشمولة بعقد
            // متعدد الوحدات)، وإلا فالعرض الكامل كما هو.
            if (_openUnitType != null) ...[
              for (var i = 0; i < item.units.length; i++) ...[
                if (_unitMatchesOpenType(item.units[i])) ...[
                  _UnitCard(
                    unit: item.units[i],
                    onToggleStatus: () => _toggleUnitStatus(i),
                    onTap: () => _openUnitDetails(i),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (!item.units.any(_unitMatchesOpenType))
                const _DetailHintCard(
                  message: 'لا توجد وحدات من هذا النوع حاليًا.',
                ),
            ] else ...[
              for (final entry in groups.entries) ...[
                _MultiUnitContractCard(
                  units: entry.value,
                  contract: _activeContractForUnit(entry.value.first.unitKey)!,
                  onTap: () => _openMultiUnitContractSummary(entry.value),
                ),
                const SizedBox(height: 8),
              ],
              for (var i = 0; i < item.units.length; i++) ...[
                if (!groupedUnitKeys.contains(item.units[i].unitKey)) ...[
                  _UnitCard(
                    unit: item.units[i],
                    onToggleStatus: () => _toggleUnitStatus(i),
                    onTap: () => _openUnitDetails(i),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ],
        );
      case 1: // الحركة المالية
        return Column(
          children: [
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindRental),
              entries: _filterEntries(_entriesByKind[_entryKindRental]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRental),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRental),
                existing: _entriesByKind[_entryKindRental]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindRental),
                index,
              ),
            ),
            const SizedBox(height: 10),
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindExpense),
              entries: _filterEntries(_entriesByKind[_entryKindExpense]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
                existing: _entriesByKind[_entryKindExpense]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
                index,
              ),
            ),
            const SizedBox(height: 10),
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindRevenue),
              entries: _filterEntries(_entriesByKind[_entryKindRevenue]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
                existing: _entriesByKind[_entryKindRevenue]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
                index,
              ),
            ),
          ],
        );
      case 2: // المتابعات
        return Column(
          children: [
            _PropertyFollowupDetailsCard(item: item, color: _kPropertyColor),
            const SizedBox(height: 10),
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindContract),
              entries: _filterEntries(_entriesByKind[_entryKindContract]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
                existing: _entriesByKind[_entryKindContract]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
                index,
              ),
            ),
          ],
        );
      case 3: // الصيانة
        return _EntryGroupCard(
          group: _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
          entries: _filterEntries(_entriesByKind[_entryKindMaintenance]!),
          onAdd: () => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
          ),
          onEdit: (index) => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
            existing: _entriesByKind[_entryKindMaintenance]![index],
            editIndex: index,
          ),
          onDelete: (index) => _deleteEntry(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
            index,
          ),
        );
      default: // الملاحظات
        return _AssetUnifiedCard(
          title: 'الملاحظات',
          icon: Icons.sticky_note_2_outlined,
          color: _kPropertyColor,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                item.description.isEmpty
                    ? 'لا توجد ملاحظات مسجّلة بعد.'
                    : item.description,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF334155),
                  height: 1.6,
                ),
              ),
            ),
          ],
        );
    }
  }

  // ============================================================
  // فئة "الأنشطة التجارية" — نفس نمط شاشة تفاصيل العقار (هيدر + شريط
  // أبرز البيانات + تبويبات)، مع تبويب "الموظفون" الذي يقابل تبويب
  // "الوحدات" في العقارات (قائمة قابلة للتكرار).
  // ============================================================

  static const List<DetailSectionTab> _activityTabs = [
    DetailSectionTab(label: 'الموظفون', icon: Icons.groups_2_outlined),
    DetailSectionTab(
      label: 'الحركة المالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(label: 'المتابعات', icon: Icons.event_note_outlined),
    DetailSectionTab(label: 'المستندات', icon: Icons.folder_outlined),
    DetailSectionTab(label: 'الملاحظات', icon: Icons.sticky_note_2_outlined),
  ];

  void _addEmployee() {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
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
              top: 14,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة موظف',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textAlign: TextAlign.right,
                    decoration: _propertyInputDecoration('اسم الموظف'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: roleCtrl,
                    textAlign: TextAlign.right,
                    decoration: _propertyInputDecoration('الوظيفة'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty) return;
                      _updateItem(
                        _item.copyWith(
                          employees: [
                            ..._item.employees,
                            {
                              'الاسم': nameCtrl.text.trim(),
                              'الوظيفة': roleCtrl.text.trim(),
                            },
                          ],
                          logs: [
                            'تمت إضافة موظف: ${nameCtrl.text.trim()}',
                            ..._item.logs,
                          ],
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kActivityColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '+ إضافة',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  void _removeEmployee(int index) {
    final employees = List<Map<String, String>>.from(_item.employees);
    if (index < 0 || index >= employees.length) return;
    employees.removeAt(index);
    _updateItem(_item.copyWith(employees: employees));
  }

  Widget _buildActivityDetails(BuildContext context) {
    final item = _item;
    if (_selectedTab >= _activityTabs.length) _selectedTab = 0;
    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        key: const ValueKey('add-activity-detail-entry'),
        screenId: 'asset_details_activity',
        onPressed: _selectedTab == 0
            ? _addEmployee
            : _selectedTab == 1
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
              )
            : _selectedTab == 2
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
              )
            : _selectedTab == 3
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindDocument),
              )
            : _openMainEntryTypesSheet,
        label: '+ إضافة',
        icon: Icons.add_rounded,
        backgroundColor: _kActivityColor,
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
          'تفاصيل النشاط التجاري',
          style: TextStyle(
            fontSize: 19,
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
        // CustomScrollView ليمكن تثبيت شريط التبويبات أعلى الشاشة.
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Container(
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                children: [
                  _AssetDetailHeaderCard(
                    item: item,
                    onAction: _onTopMenuAction,
                    icon: Icons.storefront_rounded,
                    accentColor: _kActivityColor,
                  ),
                  const Divider(height: 1, color: Color(0xFFEEF2F7)),
                  _AssetHighlightBarRow(
                    accentColor: _kActivityColor,
                    tiles: [
                      _AssetHighlightTile(
                        Icons.groups_2_outlined,
                        '${item.employees.length}',
                        'موظفين',
                      ),
                      _AssetHighlightTile(
                        Icons.badge_outlined,
                        item.subType.isEmpty ? '—' : item.subType,
                        'نوع النشاط',
                      ),
                      _AssetHighlightTile(
                        Icons.event_busy_outlined,
                        item.endDate,
                        'انتهاء الرخصة',
                      ),
                    ],
                  ),
                ],
              ),
            ),
              ),
            ),
            MeasuredPinnedHeader(
              background: AppTheme.page,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: DetailPageTabs(
                  sections: _activityTabs,
                  selectedIndex: _selectedTab,
                  color: _kActivityColor,
                  onSelected: (i) => setState(() => _selectedTab = i),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 92),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('activity-tab-$_selectedTab'),
                    child: _buildActivityTabContent(item),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTabContent(_AssetItem item) {
    switch (_selectedTab) {
      case 0: // الموظفون
        if (item.employees.isEmpty) {
          return const _DetailHintCard(
            message: 'لا يوجد موظفون بعد — استخدم زر + إضافة لإضافة موظف جديد.',
          );
        }
        return Column(
          children: [
            for (var i = 0; i < item.employees.length; i++) ...[
              _EmployeeCard(
                name: item.employees[i]['الاسم'] ?? '',
                role: item.employees[i]['الوظيفة'] ?? '',
                onDelete: () => _removeEmployee(i),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      case 1: // الحركة المالية
        return Column(
          children: [
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindExpense),
              entries: _filterEntries(_entriesByKind[_entryKindExpense]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
                existing: _entriesByKind[_entryKindExpense]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
                index,
              ),
            ),
            const SizedBox(height: 10),
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindRevenue),
              entries: _filterEntries(_entriesByKind[_entryKindRevenue]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
                existing: _entriesByKind[_entryKindRevenue]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindRevenue),
                index,
              ),
            ),
          ],
        );
      case 2: // المتابعات (الرخصة والمتابعة الإدارية)
        return Column(
          children: [
            _PropertyFollowupDetailsCard(item: item, color: _kActivityColor),
            const SizedBox(height: 10),
            _EntryGroupCard(
              group: _groups.firstWhere((g) => g.kind == _entryKindContract),
              entries: _filterEntries(_entriesByKind[_entryKindContract]!),
              onAdd: () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
              ),
              onEdit: (index) => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
                existing: _entriesByKind[_entryKindContract]![index],
                editIndex: index,
              ),
              onDelete: (index) => _deleteEntry(
                _groups.firstWhere((g) => g.kind == _entryKindContract),
                index,
              ),
            ),
          ],
        );
      case 3: // المستندات
        return _EntryGroupCard(
          group: _groups.firstWhere((g) => g.kind == _entryKindDocument),
          entries: _filterEntries(_entriesByKind[_entryKindDocument]!),
          onAdd: () => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
          ),
          onEdit: (index) => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
            existing: _entriesByKind[_entryKindDocument]![index],
            editIndex: index,
          ),
          onDelete: (index) => _deleteEntry(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
            index,
          ),
        );
      default: // الملاحظات
        return _AssetUnifiedCard(
          title: 'الملاحظات',
          icon: Icons.sticky_note_2_outlined,
          color: _kActivityColor,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                item.description.isEmpty
                    ? 'لا توجد ملاحظات مسجّلة بعد.'
                    : item.description,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF334155),
                  height: 1.6,
                ),
              ),
            ),
          ],
        );
    }
  }

  // ============================================================
  // فئة "المعدات" — نفس النمط، بتبويبات مبنية على المتطلبات المنطقية
  // لتتبع أي معدة: بياناتها الفنية، صيانتها، حركتها المالية، مستنداتها.
  // ============================================================

  static const List<DetailSectionTab> _equipmentTabs = [
    DetailSectionTab(
      label: 'البيانات الفنية',
      icon: Icons.precision_manufacturing_outlined,
    ),
    DetailSectionTab(label: 'الصيانة', icon: Icons.build_outlined),
    DetailSectionTab(
      label: 'الحركة المالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(label: 'المستندات', icon: Icons.folder_outlined),
    DetailSectionTab(label: 'الملاحظات', icon: Icons.sticky_note_2_outlined),
  ];

  void _cycleEquipmentCondition() {
    const order = ['تعمل', 'تحت الصيانة', 'متوقفة'];
    final currentIndex = order.indexOf(_item.status);
    final next = order[(currentIndex + 1) % order.length];
    _updateItem(
      _item.copyWith(status: next, needsAttention: next == 'تحت الصيانة'),
    );
  }

  Widget _buildEquipmentDetails(BuildContext context) {
    final item = _item;
    if (_selectedTab >= _equipmentTabs.length) _selectedTab = 0;
    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        key: const ValueKey('add-equipment-detail-entry'),
        screenId: 'asset_details_equipment',
        onPressed: _selectedTab == 1
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
              )
            : _selectedTab == 2
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindExpense),
              )
            : _selectedTab == 3
            ? () => _openActionForm(
                _groups.firstWhere((g) => g.kind == _entryKindDocument),
              )
            : _openMainEntryTypesSheet,
        label: '+ إضافة',
        icon: Icons.add_rounded,
        backgroundColor: _kEquipmentColor,
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
          'تفاصيل المعدة',
          style: TextStyle(
            fontSize: 19,
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
        // CustomScrollView ليمكن تثبيت شريط التبويبات أعلى الشاشة.
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Container(
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                children: [
                  _AssetDetailHeaderCard(
                    item: item,
                    onAction: _onTopMenuAction,
                    icon: Icons.precision_manufacturing_rounded,
                    accentColor: _kEquipmentColor,
                  ),
                  const Divider(height: 1, color: Color(0xFFEEF2F7)),
                  _AssetHighlightBarRow(
                    accentColor: _kEquipmentColor,
                    tiles: [
                      _AssetHighlightTile(
                        Icons.flash_on_outlined,
                        item.status,
                        'الحالة',
                      ),
                      _AssetHighlightTile(
                        Icons.qr_code_2_outlined,
                        item.serialNumber.isEmpty ? '—' : item.serialNumber,
                        'الرقم التسلسلي',
                      ),
                      _AssetHighlightTile(
                        Icons.event_busy_outlined,
                        item.endDate,
                        'انتهاء الضمان',
                      ),
                    ],
                  ),
                ],
              ),
            ),
              ),
            ),
            MeasuredPinnedHeader(
              background: AppTheme.page,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: DetailPageTabs(
                  sections: _equipmentTabs,
                  selectedIndex: _selectedTab,
                  color: _kEquipmentColor,
                  onSelected: (i) => setState(() => _selectedTab = i),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 92),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('equipment-tab-$_selectedTab'),
                    child: _buildEquipmentTabContent(item),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipmentTabContent(_AssetItem item) {
    switch (_selectedTab) {
      case 0: // البيانات الفنية
        return _AssetUnifiedCard(
          title: 'البيانات الفنية',
          icon: Icons.precision_manufacturing_outlined,
          color: _kEquipmentColor,
          children: [
            _AssetInfoRow(
              label: 'الرقم التسلسلي',
              value: item.serialNumber.isEmpty ? 'غير محدد' : item.serialNumber,
              icon: Icons.qr_code_2_outlined,
              color: _kEquipmentColor,
            ),
            _AssetInfoRow(
              label: 'المورد',
              value: item.owner,
              icon: Icons.local_shipping_outlined,
              color: _kEquipmentColor,
            ),
            _AssetInfoRow(
              label: 'الموقع المخصصة له',
              value: item.locationOrType,
              icon: Icons.place_outlined,
              color: _kEquipmentColor,
            ),
            _AssetInfoRow(
              label: 'القيمة الشرائية',
              value: item.amountLabel,
              icon: Icons.payments_outlined,
              color: _kEquipmentColor,
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _cycleEquipmentCondition,
              icon: const Icon(Icons.sync_alt_rounded),
              label: Text('تغيير الحالة (${item.status})'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kEquipmentColor,
                side: const BorderSide(color: _kEquipmentColor),
              ),
            ),
          ],
        );
      case 1: // الصيانة
        return _EntryGroupCard(
          group: _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
          entries: _filterEntries(_entriesByKind[_entryKindMaintenance]!),
          onAdd: () => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
          ),
          onEdit: (index) => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
            existing: _entriesByKind[_entryKindMaintenance]![index],
            editIndex: index,
          ),
          onDelete: (index) => _deleteEntry(
            _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
            index,
          ),
        );
      case 2: // الحركة المالية
        return _EntryGroupCard(
          group: _groups.firstWhere((g) => g.kind == _entryKindExpense),
          entries: _filterEntries(_entriesByKind[_entryKindExpense]!),
          onAdd: () => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindExpense),
          ),
          onEdit: (index) => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindExpense),
            existing: _entriesByKind[_entryKindExpense]![index],
            editIndex: index,
          ),
          onDelete: (index) => _deleteEntry(
            _groups.firstWhere((g) => g.kind == _entryKindExpense),
            index,
          ),
        );
      case 3: // المستندات
        return _EntryGroupCard(
          group: _groups.firstWhere((g) => g.kind == _entryKindDocument),
          entries: _filterEntries(_entriesByKind[_entryKindDocument]!),
          onAdd: () => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
          ),
          onEdit: (index) => _openActionForm(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
            existing: _entriesByKind[_entryKindDocument]![index],
            editIndex: index,
          ),
          onDelete: (index) => _deleteEntry(
            _groups.firstWhere((g) => g.kind == _entryKindDocument),
            index,
          ),
        );
      default: // الملاحظات
        return _AssetUnifiedCard(
          title: 'الملاحظات',
          icon: Icons.sticky_note_2_outlined,
          color: _kEquipmentColor,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                item.description.isEmpty
                    ? 'لا توجد ملاحظات مسجّلة بعد.'
                    : item.description,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF334155),
                  height: 1.6,
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // فئات "العقارات" و"الأنشطة التجارية" و"المعدات" لها الآن شاشات
    // تفاصيل مخصّصة (هيدر + شريط أبرز البيانات + تبويبات) بنفس القالب
    // البصري المعتمد في كل شاشات التطبيق. فئة "أخرى" فقط تستمر بالشكل
    // القديم العام إلى أن يُعاد بناؤها لاحقاً.
    if (_item.category == 'real_estate') {
      return _buildRealEstateDetails(context);
    }
    if (_item.category == 'activity') {
      return _buildActivityDetails(context);
    }
    if (_item.category == 'equipment') {
      return _buildEquipmentDetails(context);
    }
    final item = _item;
    final baseColor = _pageColor;
    const propertySections = [
      DetailSectionTab(label: 'الملخص', icon: Icons.bar_chart_rounded),
      DetailSectionTab(
        label: 'المالية',
        icon: Icons.account_balance_wallet_outlined,
      ),
      DetailSectionTab(label: 'الوحدات', icon: Icons.home_work_outlined),
      DetailSectionTab(
        label: 'التنظيم/المتابعة',
        icon: Icons.notifications_none_rounded,
      ),
      DetailSectionTab(label: 'المستأجرين', icon: Icons.people_alt_outlined),
      DetailSectionTab(label: 'الصيانة', icon: Icons.build_rounded),
      DetailSectionTab(label: 'المستندات', icon: Icons.folder_outlined),
      DetailSectionTab(label: 'أخرى', icon: Icons.more_horiz_rounded),
    ];
    if (_selectedTab >= propertySections.length) {
      _selectedTab = 0;
    }

    return Scaffold(
      backgroundColor: AppTheme.page,
      floatingActionButton: AddFab(
        key: const ValueKey('add-asset-detail-entry'),
        screenId: 'asset_details',
        onPressed: _openMainEntryTypesSheet,
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
        title: Text(
          'تفاصيل ${_singularCategoryLabel(_item.category)}',
          style: const TextStyle(
            fontSize: 19,
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
        child: ListView(
          key: const ValueKey('compact-asset-details'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          children: [
            DetailScaffold(
              header: DetailPageHeader(
                title: item.title,
                subtitle:
                    '${item.subType} · ${item.locationOrType}${item.isFrozen ? ' · مجمّد' : ''}${item.isPinned ? ' · مثبّت' : ''}',
                icon: item.category == 'activity'
                    ? Icons.storefront_rounded
                    : Icons.apartment_rounded,
                color: baseColor,
                status: item.isFrozen ? 'مجمّد' : item.status,
                statusColor: item.isFrozen
                    ? const Color(0xFF64748B)
                    : item.needsAttention
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
                metrics: [
                  DetailHeaderMetric(
                    label: 'القيمة',
                    value: item.amountLabel,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  DetailHeaderMetric(
                    label: 'تاريخ الانتهاء',
                    value: item.endDate,
                    icon: Icons.calendar_month_outlined,
                  ),
                  DetailHeaderMetric(
                    label: 'التنبيهات',
                    value: '${item.alerts.length}',
                    icon: Icons.notifications_none_rounded,
                  ),
                ],
                trailing: ThreeDotMenu(
                  tooltip: 'المزيد',
                  onAction: _onTopMenuAction,
                ),
              ),
              tabs: propertySections,
              selectedTabIndex: _selectedTab,
              onTabSelected: (index) => setState(() => _selectedTab = index),
              accentColor: baseColor,
              actions: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openMainEntryTypesSheet,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFE2C7),
                        foregroundColor: const Color(0xFF2D2217),
                        side: BorderSide(color: baseColor, width: 1.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size.fromHeight(38),
                      ),
                      child: const Text(
                        'إضافة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openDelegationPicker,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFE2C7),
                        foregroundColor: const Color(0xFF2D2217),
                        side: BorderSide(color: baseColor, width: 1.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size.fromHeight(38),
                      ),
                      child: const Text(
                        'طلب تفويض',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedTab == 0)
                    _PropertySummaryDetails(item: item)
                  else if (_selectedTab == 1)
                    _PropertyFinanceDetails(item: item, color: baseColor)
                  else if (_selectedTab == 2)
                    _EntryGroupCard(
                      group: _groups.firstWhere(
                        (g) => g.kind == _entryKindRental,
                      ),
                      entries: _filterEntries(
                        _entriesByKind[_entryKindRental]!,
                      ),
                      onAdd: () => _openActionForm(
                        _groups.firstWhere((g) => g.kind == _entryKindRental),
                      ),
                      onEdit: (index) => _openActionForm(
                        _groups.firstWhere((g) => g.kind == _entryKindRental),
                        existing: _entriesByKind[_entryKindRental]![index],
                        editIndex: index,
                      ),
                      onDelete: (index) => _deleteEntry(
                        _groups.firstWhere((g) => g.kind == _entryKindRental),
                        index,
                      ),
                    )
                  else if (_selectedTab == 3)
                    _PropertyFollowupDetailsCard(item: item, color: baseColor)
                  else if (_selectedTab == 4)
                    _AssetTenantDetailsCard(item: item, color: baseColor)
                  else if (_selectedTab == 5)
                    _EntryGroupCard(
                      group: _groups.firstWhere(
                        (g) => g.kind == _entryKindMaintenance,
                      ),
                      entries: _filterEntries(
                        _entriesByKind[_entryKindMaintenance]!,
                      ),
                      onAdd: () => _openActionForm(
                        _groups.firstWhere(
                          (g) => g.kind == _entryKindMaintenance,
                        ),
                      ),
                      onEdit: (index) => _openActionForm(
                        _groups.firstWhere(
                          (g) => g.kind == _entryKindMaintenance,
                        ),
                        existing: _entriesByKind[_entryKindMaintenance]![index],
                        editIndex: index,
                      ),
                      onDelete: (index) => _deleteEntry(
                        _groups.firstWhere(
                          (g) => g.kind == _entryKindMaintenance,
                        ),
                        index,
                      ),
                    )
                  else if (_selectedTab == 6) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DocumentTemplatesScreen(
                            linkedProperty: item.title,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('فتح النماذج الجاهزة لهذا العقار'),
                    ),
                    const SizedBox(height: 10),
                    _EntryGroupCard(
                      group: _groups.firstWhere(
                        (g) => g.kind == _entryKindDocument,
                      ),
                      entries: _filterEntries(
                        _entriesByKind[_entryKindDocument]!,
                      ),
                      onAdd: () => _openActionForm(
                        _groups.firstWhere((g) => g.kind == _entryKindDocument),
                      ),
                      onEdit: (index) => _openActionForm(
                        _groups.firstWhere((g) => g.kind == _entryKindDocument),
                        existing: _entriesByKind[_entryKindDocument]![index],
                        editIndex: index,
                      ),
                      onDelete: (index) => _deleteEntry(
                        _groups.firstWhere((g) => g.kind == _entryKindDocument),
                        index,
                      ),
                    ),
                  ] else ...[
                    _SearchInput(
                      controller: _searchController,
                      hint: 'ابحث داخل الإدخالات',
                      onFilterTap: _openDetailSectionsSheet,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    for (final group in _groups) ...[
                      if (group.kind == _entryKindExpense ||
                          group.kind == _entryKindRevenue ||
                          group.kind == _entryKindContract) ...[
                        _EntryGroupCard(
                          group: group,
                          entries: _filterEntries(_entriesByKind[group.kind]!),
                          onAdd: () => _openActionForm(group),
                          onEdit: (index) => _openActionForm(
                            group,
                            existing: _entriesByKind[group.kind]![index],
                            editIndex: index,
                          ),
                          onDelete: (index) => _deleteEntry(group, index),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _filterEntries(List<Map<String, String>> entries) {
    final query = _searchController.text.trim();
    if (query.isEmpty) return entries;
    return entries
        .where((e) => e.values.any((v) => v.contains(query)))
        .toList(growable: false);
  }

  String _categoryLabel(String key) {
    if (key == 'real_estate') return 'العقارات';
    if (key == 'activity') return 'الأنشطة';
    if (key == 'equipment') return 'المعدات';
    return 'أخرى';
  }

  // نسخة مفردة من اسم الفئة تُستخدم في العناوين ("تفاصيل العقار"، "حذف
  // العقار"...)؛ كانت هذه النصوص ثابتة على كلمة "العقار" حتى للأنشطة
  // التجارية والمعدات، رغم وجود _categoryLabel أصلًا لهذا الغرض.
  String _singularCategoryLabel(String key) {
    if (key == 'activity') return 'النشاط التجاري';
    if (key == 'equipment') return 'المعدة';
    if (key == 'real_estate') return 'العقار';
    return 'الأصل';
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  Future<void> _openDelegationPicker() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peopleStorageKey);
    final registeredPeople = <String>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map<String, dynamic>) {
              final name = (entry['fullName'] ?? '').toString().trim();
              if (name.isNotEmpty) {
                registeredPeople.add(name);
              }
            } else if (entry is Map) {
              final name = (entry['fullName'] ?? '').toString().trim();
              if (name.isNotEmpty) {
                registeredPeople.add(name);
              }
            }
          }
        }
      } catch (_) {
        // Ignore malformed cache and use fallback list.
      }
    }
    if (registeredPeople.isEmpty) {
      registeredPeople.addAll(const ['أحمد محمد سالم', 'نورة عبدالله']);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'إضافة شخص لتفويض عقار',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              ...registeredPeople.map(
                (person) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(
                    person,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // لا يوجد جدول تفويضات فعلي بعد؛ الحد الأدنى الصادق هو
                    // تسجيل العملية ضمن سجل الأصل نفسه (يظهر في "آخر
                    // مراجعة") بدل الاكتفاء برسالة نجاح لا تُحدث أي أثر.
                    _updateItem(
                      _item.copyWith(
                        logs: [
                          'تم إرسال طلب تفويض عقار إلى: $person',
                          ..._item.logs,
                        ],
                      ),
                    );
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('تم إرسال طلب تفويض إلى: $person'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyFollowupDetailsCard extends StatelessWidget {
  const _PropertyFollowupDetailsCard({required this.item, required this.color});

  final _AssetItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final notes =
        (item.followupNote.isEmpty
                ? const <String>[]
                : item.followupNote
                      .split(RegExp(r'\n+'))
                      .where((value) => value.trim().isNotEmpty)
                      .toList())
            .where((value) => value.trim().isNotEmpty)
            .toList();

    final lastReview = item.logs.isNotEmpty ? item.logs.first : 'غير محدد';
    final nextDate = item.endDate.isEmpty ? 'غير محدد' : item.endDate;

    return _AssetUnifiedCard(
      title: 'التنظيم/المتابعة',
      icon: Icons.notifications_none_rounded,
      color: color,
      children: [
        _AssetInfoRow(
          label: 'حالة المتابعة',
          value: item.needsAttention ? 'يحتاج متابعة' : 'مستقر',
          icon: Icons.flag_outlined,
          color: color,
        ),
        _AssetInfoRow(
          label: 'الموعد القادم',
          value: nextDate,
          icon: Icons.event_available_outlined,
          color: color,
        ),
        _AssetInfoRow(
          label: 'آخر مراجعة',
          value: lastReview,
          icon: Icons.fact_check_outlined,
          color: color,
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerRight,
          child: Text(
            'الملاحظات',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (notes.isEmpty)
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'لا توجد ملاحظات',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          )
        else ...[
          ...notes.map(
            (note) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                note.trim(),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF334155),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ],
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
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.item, required this.onTap});

  final _AssetItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const healthyStatuses = {'نشط', 'تعمل'};
    final statusColor = healthyStatuses.contains(item.status)
        ? const Color(0xFF10B981)
        : const Color(0xFFE11D48);
    final progress =
        ((item.contractProgress +
                    item.paymentProgress +
                    item.documentsProgress) /
                3)
            .clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
        child: Column(
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_assetIcon(item.category), color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.subType} · ${item.locationOrType}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.amountLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F4AA2),
                      ),
                    ),
                    Text(
                      item.status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _assetIcon(String category) {
    if (category == 'real_estate') return Icons.apartment_rounded;
    if (category == 'project') return Icons.account_tree_rounded;
    return Icons.storefront_rounded;
  }
}

class _ProgressOverviewCard extends StatelessWidget {
  const _ProgressOverviewCard({required this.item});

  final _AssetItem item;

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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'شريط التقدم (سريان العقد / الدفعات / اكتمال المستندات)',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF334155),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _progress(
            'سريان العقد',
            item.contractProgress,
            const Color(0xFF0F6AA8),
          ),
          const SizedBox(height: 8),
          _progress('الدفعات', item.paymentProgress, const Color(0xFF0EA5A4)),
          const SizedBox(height: 8),
          _progress(
            'اكتمال المستندات',
            item.documentsProgress,
            const Color(0xFF7C3AED),
          ),
        ],
      ),
    );
  }

  Widget _progress(String title, double value, Color color) {
    final percent = (value * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$title: $percent%',
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 10.5,
            color: Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.16),
          ),
        ),
      ],
    );
  }
}

class _TabsRow extends StatelessWidget {
  const _TabsRow({
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: false,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    decoration: selected
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.item});

  final _AssetItem item;

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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _line('اسم العنصر', item.title),
          _line('النوع', item.subType),
          _line('الحالة', item.status),
          _line('المالك', item.owner),
          _line('المستأجر / العميل', item.tenant),
          _line('قيمة الإيجار / الدخل', item.rentValue),
          _line('تاريخ الانتهاء', item.endDate),
          _line('العائد السنوي', item.annualYield),
          _line(
            'نسبة الإشغال',
            '${(item.occupancyRate * 100).toStringAsFixed(0)}%',
          ),
          _line('ملاحظات مهمة', item.followupNote),
        ],
      ),
    );
  }

  Widget _line(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$title: $value',
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF334155),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PropertySummaryDetails extends StatelessWidget {
  const _PropertySummaryDetails({required this.item});

  final _AssetItem item;

  @override
  Widget build(BuildContext context) {
    return _AssetUnifiedCard(
      title: 'ملخص العقار',
      icon: Icons.bar_chart_rounded,
      color: item.iconColor ?? const Color(0xFF0F6AA8),
      children: [
        _AssetInfoRow(
          label: 'اسم المشروع',
          value: item.title,
          icon: Icons.home_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'النوع',
          value: item.subType,
          icon: Icons.category_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'الحالة',
          value: item.isFrozen ? 'مجمّد' : item.status,
          icon: Icons.flag_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'المالك',
          value: item.owner,
          icon: Icons.person_outline_rounded,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'المستأجر/العميل',
          value: item.tenant,
          icon: Icons.groups_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'تاريخ نهاية العقد',
          value: item.endDate,
          icon: Icons.event_available_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'الوصف العام',
          value: item.description.isEmpty ? 'غير محدد' : item.description,
          icon: Icons.subject_rounded,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'ملحقات العقار',
          value: item.annexes.isEmpty
              ? 'لم تُحدد'
              : item.annexes.entries
                    .map((entry) => '${entry.key} (${entry.value})')
                    .join('، '),
          icon: Icons.domain_add_outlined,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
        _AssetInfoRow(
          label: 'ملاحظات',
          value: item.followupNote,
          icon: Icons.notes_rounded,
          color: item.iconColor ?? const Color(0xFF0F6AA8),
        ),
      ],
    );
  }
}

class _PropertyFinanceDetails extends StatelessWidget {
  const _PropertyFinanceDetails({required this.item, required this.color});

  final _AssetItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AssetUnifiedCard(
      title: 'المالية',
      icon: Icons.account_balance_wallet_rounded,
      color: color,
      children: [
        _AssetInfoRow(
          label: 'قيمة العقد',
          value: item.amountLabel,
          icon: Icons.savings_outlined,
          color: color,
        ),
        _AssetInfoRow(
          label: 'العائد السنوي',
          value: item.annualYield,
          icon: Icons.trending_up_rounded,
          color: color,
        ),
        _AssetInfoRow(
          label: 'قيمة الإيجار / الدخل',
          value: item.rentValue,
          icon: Icons.payments_outlined,
          color: color,
        ),
        _AssetInfoRow(
          label: 'نسبة الاشغال',
          value: '${(item.occupancyRate * 100).toStringAsFixed(0)}%',
          icon: Icons.pie_chart_outline_rounded,
          color: color,
        ),
      ],
    );
  }
}

class _AssetTenantDetailsCard extends StatelessWidget {
  const _AssetTenantDetailsCard({required this.item, required this.color});

  final _AssetItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tenants = <String>[
      if (item.tenant.trim().isNotEmpty) item.tenant,
      ...item.tasks.where((task) => task.trim().isNotEmpty),
    ].where((value) => value.trim().isNotEmpty).toList();

    return _AssetUnifiedCard(
      title: 'المستأجرين',
      icon: Icons.people_alt_outlined,
      color: color,
      children: [
        _AssetInfoRow(
          label: 'اسم المستأجر / العميل',
          value: item.tenant.isEmpty ? 'غير محدد' : item.tenant,
          icon: Icons.person_outline_rounded,
          color: color,
        ),
        _AssetInfoRow(
          label: 'تاريخ نهاية العقد',
          value: item.endDate.isEmpty ? 'غير محدد' : item.endDate,
          icon: Icons.event_available_outlined,
          color: color,
        ),
        _AssetInfoRow(
          label: 'حالة المتابعة',
          value: item.needsAttention ? 'يحتاج متابعة' : 'مستقر',
          icon: Icons.notifications_none_rounded,
          color: color,
        ),
        const SizedBox(height: 6),
        if (tenants.isEmpty)
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'لا توجد بيانات مستأجرين حاليًا',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'قائمة المتابعة',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...tenants.map(
            (value) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// غلافان رفيعان فوق مكوّني نظام التصميم، فتطابق صفحة تفاصيل العقار/النشاط
// صفحة تفاصيل الالتزام الشخصي حرفًا بحرف: بطاقة رمادية واحدة، وصفوف يفصل
// بينها خط أبيض رفيع. كانت الترويسة هنا بمربع أيقونة ملوّن والصفوف بلا أي
// فاصل، فيبدو الجدول كتلة واحدة ملتصقة.
class _AssetUnifiedCard extends StatelessWidget {
  const _AssetUnifiedCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppDetailsCard(
    title: title,
    icon: icon,
    color: color,
    children: children,
  );
}

class _AssetInfoRow extends StatelessWidget {
  const _AssetInfoRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      AppDetailRow(label: label, value: value, icon: icon);
}

class _DynamicListCard extends StatelessWidget {
  const _DynamicListCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.emptyText,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String emptyText;
  final List<String> items;

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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
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
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            )
          else
            ...items
                .take(10)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Icon(Icons.circle, size: 6, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
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
                ),
        ],
      ),
    );
  }
}

class _DetailHintCard extends StatelessWidget {
  const _DetailHintCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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

class _AlertsKnowledgeCard extends StatelessWidget {
  const _AlertsKnowledgeCard();

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
            'تنبيهات مالية: دفعة متأخرة، قسط مستحق، إيجار مستحق',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات زمنية: مهمة متأخرة، صيانة مستحقة',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
          ),
          SizedBox(height: 4),
          Text(
            'تنبيهات مستندات وذكية: مستند منتهي، تجديد مطلوب',
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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'السجل',
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
                    .take(10)
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

class _HintBlock extends StatelessWidget {
  const _HintBlock({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetEntryActionCard extends StatelessWidget {
  const _AssetEntryActionCard({
    super.key,
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
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
          ],
        ),
      ),
    );
  }
}

class _AssetEntryTypeOption {
  const _AssetEntryTypeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _TopFilter {
  const _TopFilter(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;
}

class _ProjectsFilterChip extends StatelessWidget {
  const _ProjectsFilterChip({
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7EEF8) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF1E4F95) : const Color(0xFF2E5FA7),
            width: selected ? 1.4 : 1.1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected
                    ? const Color(0xFF0B3A78)
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF0B3A78)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetHero extends StatelessWidget {
  const _AssetHero({
    required this.item,
    required this.baseColor,
    required this.gradientEnd,
    required this.categoryLabel,
  });

  final _AssetItem item;
  final Color baseColor;
  final Color gradientEnd;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final progress =
        ((item.contractProgress +
                    item.paymentProgress +
                    item.documentsProgress) /
                3)
            .clamp(0.0, 1.0);
    final progressText = '${(progress * 100).toStringAsFixed(0)}%';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [baseColor, gradientEnd],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 74, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  _assetIcon(item.category),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$categoryLabel • ${item.subType}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  item.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'التقدم $progressText',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${item.locationOrType}  •  ${item.amountLabel}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _assetIcon(String category) {
    if (category == 'real_estate') return Icons.apartment_rounded;
    if (category == 'project') return Icons.account_tree_rounded;
    return Icons.storefront_rounded;
  }
}

class _EntryGroupCard extends StatelessWidget {
  const _EntryGroupCard({
    required this.group,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final _ActionGroup group;
  final List<Map<String, String>> entries;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(group.icon, color: group.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${entries.length}',
                  style: TextStyle(
                    color: group.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: group.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (entries.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'لا توجد ${group.title} بعد — اضغط + للإضافة',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i++) ...[
              _EntryTile(
                entry: entries[i],
                color: group.color,
                primaryLabel: group.fields.first.label,
                secondaryLabels: group.fields
                    .skip(1)
                    .map((f) => f.label)
                    .toList(growable: false),
                onEdit: () => onEdit(i),
                onDelete: () => onDelete(i),
              ),
              if (i < entries.length - 1)
                Divider(
                  height: 14,
                  thickness: 0.6,
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.color,
    required this.primaryLabel,
    required this.secondaryLabels,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, String> entry;
  final Color color;
  final String primaryLabel;
  final List<String> secondaryLabels;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = (entry[primaryLabel] ?? '').isNotEmpty
        ? entry[primaryLabel]!
        : 'بدون عنوان';
    final subtitle = secondaryLabels
        .map((label) => entry[label] ?? '')
        .where((v) => v.trim().isNotEmpty)
        .take(3)
        .join(' • ');

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, size: 18, color: color),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'تعديل',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFDC2626),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGroup {
  const _ActionGroup({
    required this.title,
    required this.kind,
    required this.color,
    required this.icon,
    required this.fields,
  });

  final String title;
  final String kind;
  final Color color;
  final IconData icon;
  final List<_FieldDef> fields;
}

class _FieldDef {
  const _FieldDef(
    this.label,
    this.isNumeric, {
    this.isDate = false,
    this.multiline = false,
    this.options,
  });

  final String label;
  final bool isNumeric;
  final bool isDate;
  final bool multiline;
  final List<String>? options;
}

class _PropertyAnnexesEditor extends StatelessWidget {
  const _PropertyAnnexesEditor({
    required this.counts,
    required this.otherController,
    required this.onCountChanged,
  });

  final Map<String, int> counts;
  final TextEditingController otherController;
  final void Function(String label, int count) onCountChanged;

  @override
  Widget build(BuildContext context) {
    final selectedCount = counts.values.where((count) => count > 0).length;
    return Container(
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        title: const Text(
          'ملحقات العقار',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          selectedCount == 0
              ? 'حدد الممرات والغرف والمرافق التابعة للعقار'
              : 'تم تحديد $selectedCount من الملحقات',
        ),
        children: [
          for (final label in _propertyAnnexLabels)
            Row(
              children: [
                Checkbox(
                  value: (counts[label] ?? 0) > 0,
                  onChanged: (selected) =>
                      onCountChanged(label, selected == true ? 1 : 0),
                ),
                Expanded(child: Text(label)),
                if ((counts[label] ?? 0) > 0) ...[
                  IconButton(
                    onPressed: () => onCountChanged(
                      label,
                      ((counts[label] ?? 1) - 1).clamp(0, 99),
                    ),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${counts[label]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onCountChanged(
                      label,
                      ((counts[label] ?? 0) + 1).clamp(0, 99),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 6),
          TextField(
            controller: otherController,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'إضافة ملحق آخر',
              hintText: 'مثال: غرفة حارس، مستودع خارجي',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// أنواع الوحدات داخل العقار ومنطق كل نوع، معرّفة في مكان واحد حتى تبقى
// كل الشاشات متسقة:
//   • شقة    : سكنية بعدد غرف ودورات مياه وموقف ومساحة.
//   • استديو : سكنية مفتوحة — لها دورات مياه وموقف ومساحة، لكن بلا عدد
//              غرف مستقل لأن الغرفة واحدة بطبيعتها (تُحفظ rooms = 1).
//   • محل    : تجاري — مساحة فقط (بلا غرف/دورات مياه/موقف).
// ============================================================
const String _kUnitApartment = 'شقة';
const String _kUnitStudio = 'استديو';
const String _kUnitShop = 'محل';
const String _kUnitOffice = 'مكتب';
const String _kUnitWarehouse = 'مستودع';
const String _kUnitRoom = 'غرفة';
const String _kUnitParking = 'موقف';
const String _kUnitFullFloor = 'دور كامل';
const String _kUnitShowroom = 'معرض';
const String _kUnitMezzanine = 'ميزانين';
const List<String> _kUnitTypes = [
  _kUnitApartment,
  _kUnitStudio,
  _kUnitFullFloor,
  _kUnitRoom,
  _kUnitShop,
  _kUnitOffice,
  _kUnitShowroom,
  _kUnitMezzanine,
  _kUnitWarehouse,
  _kUnitParking,
];

/// هل يملك هذا النوع عدد غرف قابلًا للإدخال؟ (الشقة والمكتب فقط).
bool _unitTypeHasRooms(String type) =>
    type == _kUnitApartment || type == _kUnitOffice || type == _kUnitFullFloor;

/// هل لهذا النوع دورات مياه وموقف؟ السكني والمكتب نعم، أما المحل
/// والمستودع والموقف فلا.
bool _unitTypeIsResidential(String type) =>
    type == _kUnitApartment ||
    type == _kUnitStudio ||
    type == _kUnitRoom ||
    type == _kUnitOffice ||
    type == _kUnitFullFloor;

/// عدد الغرف المنطقي المخزَّن لكل نوع: الاستديو والغرفة غرفة واحدة دائمًا.
int _unitTypeRoomsFor(String type, int enteredRooms) {
  if (type == _kUnitStudio || type == _kUnitRoom) return 1;
  if (type == _kUnitApartment ||
      type == _kUnitOffice ||
      type == _kUnitFullFloor) {
    return enteredRooms;
  }
  return 0;
}

IconData _unitTypeIcon(String type) {
  switch (type) {
    case _kUnitShop:
      return Icons.storefront_rounded;
    case _kUnitStudio:
      return Icons.single_bed_rounded;
    case _kUnitOffice:
      return Icons.business_center_rounded;
    case _kUnitWarehouse:
      return Icons.warehouse_rounded;
    case _kUnitRoom:
      return Icons.meeting_room_rounded;
    case _kUnitParking:
      return Icons.local_parking_rounded;
    case _kUnitFullFloor:
      return Icons.layers_rounded;
    case _kUnitMezzanine:
      return Icons.unfold_less_double_rounded;
    case _kUnitShowroom:
      return Icons.store_mall_directory_rounded;
    default:
      return Icons.apartment_rounded;
  }
}

class _PropertyUnit {
  const _PropertyUnit({
    required this.type,
    required this.name,
    this.unitNumber = '',
    this.area = '',
    this.rooms = 0,
    this.halls = 0,
    this.balconies = 0,
    this.bathrooms = 0,
    this.parkingCount = 0,
    this.hasParking = false,
    this.notes = '',
    this.status = 'شاغرة',
  });

  final String type;
  final String name;
  final String unitNumber;
  final String area;
  final int rooms;

  /// عدد الصالات والبلكونات وموقف السيارات الخاصة والملاحظات — من نموذج
  /// "إضافة الوحدات والمرافق العامة".
  final int halls;
  final int balconies;
  final int bathrooms;
  final int parkingCount;
  final bool hasParking;
  final String notes;
  final String status;

  /// معرّف مستقر لهذه الوحدة داخل العقار، يُستخدم للربط مع عقود/دفعات
  /// الإيجار في property_unit_contracts (عمود unit_key). لا يُخزَّن بشكل
  /// منفصل؛ يُشتق من الحقول الحالية حتى لا يتغير عند إعادة القراءة من
  /// الخادم.
  String get unitKey => '$type|$name|$unitNumber';

  _PropertyUnit copyWith({
    String? type,
    String? name,
    String? unitNumber,
    String? area,
    int? rooms,
    int? halls,
    int? balconies,
    int? bathrooms,
    int? parkingCount,
    bool? hasParking,
    String? notes,
    String? status,
  }) => _PropertyUnit(
    type: type ?? this.type,
    name: name ?? this.name,
    unitNumber: unitNumber ?? this.unitNumber,
    area: area ?? this.area,
    rooms: rooms ?? this.rooms,
    halls: halls ?? this.halls,
    balconies: balconies ?? this.balconies,
    bathrooms: bathrooms ?? this.bathrooms,
    parkingCount: parkingCount ?? this.parkingCount,
    hasParking: hasParking ?? this.hasParking,
    notes: notes ?? this.notes,
    status: status ?? this.status,
  );

  Map<String, dynamic> toMap() => {
    'type': type,
    'name': name,
    'unitNumber': unitNumber,
    'area': area,
    'rooms': rooms,
    'halls': halls,
    'balconies': balconies,
    'bathrooms': bathrooms,
    'parkingCount': parkingCount,
    'hasParking': hasParking,
    'notes': notes,
    'status': status,
  };

  factory _PropertyUnit.fromMap(Map<String, dynamic> map) => _PropertyUnit(
    type: (map['type'] ?? _kUnitApartment).toString(),
    name: (map['name'] ?? '').toString(),
    unitNumber: (map['unitNumber'] ?? '').toString(),
    area: (map['area'] ?? '').toString(),
    rooms: (map['rooms'] as num?)?.toInt() ?? 0,
    halls: (map['halls'] as num?)?.toInt() ?? 0,
    balconies: (map['balconies'] as num?)?.toInt() ?? 0,
    bathrooms: (map['bathrooms'] as num?)?.toInt() ?? 0,
    parkingCount: (map['parkingCount'] as num?)?.toInt() ?? 0,
    hasParking: map['hasParking'] == true,
    notes: (map['notes'] ?? '').toString(),
    status: (map['status'] ?? 'شاغرة').toString(),
  );
}

class _AssetItem {
  _AssetItem({
    required this.title,
    required this.subType,
    required this.category,
    required this.locationOrType,
    required this.status,
    required this.amountLabel,
    required this.followupNote,
    required this.owner,
    required this.tenant,
    required this.rentValue,
    required this.endDate,
    required this.annualYield,
    required this.occupancyRate,
    required this.contractProgress,
    required this.paymentProgress,
    required this.documentsProgress,
    required this.needsAttention,
    required this.documents,
    required this.contracts,
    required this.tasks,
    required this.alerts,
    required this.logs,
    required this.createdAt,
    this.isFrozen = false,
    this.isPinned = false,
    this.description = '',
    Map<String, int>? annexes,
    this.id,
    this.iconColor,
    List<Map<String, String>>? maintenance,
    List<Map<String, String>>? rentals,
    List<Map<String, String>>? expenses,
    List<Map<String, String>>? revenues,
    List<_PropertyUnit>? units,
    this.mapLink = '',
    this.quickAddEnabled = false,
    List<Map<String, String>>? employees,
    this.serialNumber = '',
    this.isSublease = false,
    this.latitude,
    this.longitude,
  }) : annexes = annexes ?? <String, int>{},
       maintenance = maintenance ?? <Map<String, String>>[],
       rentals = rentals ?? <Map<String, String>>[],
       expenses = expenses ?? <Map<String, String>>[],
       revenues = revenues ?? <Map<String, String>>[],
       units = units ?? <_PropertyUnit>[],
       employees = employees ?? <Map<String, String>>[];

  final String? id;
  final String title;
  final String subType;
  final String category;
  final String locationOrType;
  final String status;
  final String amountLabel;
  final String followupNote;
  final String owner;
  final String tenant;
  final String rentValue;
  final String endDate;
  final String annualYield;
  final double occupancyRate;
  final double contractProgress;
  final double paymentProgress;
  final double documentsProgress;
  final bool needsAttention;
  final List<String> documents;
  final List<String> contracts;
  final List<String> tasks;
  final List<String> alerts;
  final List<String> logs;
  final DateTime createdAt;
  final bool isFrozen;
  final bool isPinned;
  final String description;
  final Map<String, int> annexes;
  final Color? iconColor;
  final List<Map<String, String>> maintenance;
  final List<Map<String, String>> rentals;
  final List<Map<String, String>> expenses;
  final List<Map<String, String>> revenues;
  final List<_PropertyUnit> units;
  final String mapLink;
  final bool quickAddEnabled;
  final List<Map<String, String>> employees;
  final String serialNumber;
  final bool isSublease;
  final double? latitude;
  final double? longitude;

  int get apartmentsCount =>
      units.where((u) => u.type == _kUnitApartment).length;
  int get studiosCount =>
      units.where((u) => u.type == _kUnitStudio).length;
  int get shopsCount => units.where((u) => u.type == _kUnitShop).length;
  int get vacantUnitsCount =>
      units.where((u) => u.status == 'شاغرة').length;

  _AssetItem copyWith({
    String? title,
    String? subType,
    String? category,
    String? locationOrType,
    String? status,
    String? amountLabel,
    String? followupNote,
    String? owner,
    String? tenant,
    String? rentValue,
    String? endDate,
    String? annualYield,
    double? occupancyRate,
    double? contractProgress,
    double? paymentProgress,
    double? documentsProgress,
    bool? needsAttention,
    List<String>? documents,
    List<String>? contracts,
    List<String>? tasks,
    List<String>? alerts,
    List<String>? logs,
    DateTime? createdAt,
    bool? isFrozen,
    bool? isPinned,
    String? description,
    Map<String, int>? annexes,
    String? id,
    Color? iconColor,
    List<Map<String, String>>? maintenance,
    List<Map<String, String>>? rentals,
    List<Map<String, String>>? expenses,
    List<Map<String, String>>? revenues,
    List<_PropertyUnit>? units,
    String? mapLink,
    bool? quickAddEnabled,
    List<Map<String, String>>? employees,
    String? serialNumber,
    bool? isSublease,
    double? latitude,
    double? longitude,
  }) {
    return _AssetItem(
      title: title ?? this.title,
      subType: subType ?? this.subType,
      category: category ?? this.category,
      locationOrType: locationOrType ?? this.locationOrType,
      status: status ?? this.status,
      amountLabel: amountLabel ?? this.amountLabel,
      followupNote: followupNote ?? this.followupNote,
      owner: owner ?? this.owner,
      tenant: tenant ?? this.tenant,
      rentValue: rentValue ?? this.rentValue,
      endDate: endDate ?? this.endDate,
      annualYield: annualYield ?? this.annualYield,
      occupancyRate: occupancyRate ?? this.occupancyRate,
      contractProgress: contractProgress ?? this.contractProgress,
      paymentProgress: paymentProgress ?? this.paymentProgress,
      documentsProgress: documentsProgress ?? this.documentsProgress,
      needsAttention: needsAttention ?? this.needsAttention,
      documents: documents ?? this.documents,
      contracts: contracts ?? this.contracts,
      tasks: tasks ?? this.tasks,
      alerts: alerts ?? this.alerts,
      logs: logs ?? this.logs,
      createdAt: createdAt ?? this.createdAt,
      isFrozen: isFrozen ?? this.isFrozen,
      isPinned: isPinned ?? this.isPinned,
      description: description ?? this.description,
      annexes: annexes ?? this.annexes,
      id: id ?? this.id,
      iconColor: iconColor ?? this.iconColor,
      maintenance: maintenance ?? this.maintenance,
      rentals: rentals ?? this.rentals,
      expenses: expenses ?? this.expenses,
      revenues: revenues ?? this.revenues,
      units: units ?? this.units,
      mapLink: mapLink ?? this.mapLink,
      quickAddEnabled: quickAddEnabled ?? this.quickAddEnabled,
      employees: employees ?? this.employees,
      serialNumber: serialNumber ?? this.serialNumber,
      isSublease: isSublease ?? this.isSublease,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

// ============================================================
// معالج "إضافة عقار" الجديد — مستخرج من الفيديو المرجعي، بنفس الشكل
// البصري المعتمد (هيدر أبيض بارتفاع 60 + عنوان بخط w900 + سهم رجوع).
// خطوة 1: وصف + عنوان + عدد وحدات ← خطوة 2: تفاصيل كل وحدة (أو تخطيها
// عبر الإضافة السريعة) ← خطوة 3: مراجعة البيانات ثم الإنشاء الفعلي عبر
// _openAddPropertyWizard في الشاشة الرئيسية.
// ============================================================

const Color _kPropertyColor = Color(0xFF0B6E4F);

// نتيجة المعالج التي تُبنى منها _AssetItem الفعلية.
class _PropertyDraft {
  const _PropertyDraft({
    required this.description,
    required this.address,
    required this.mapLink,
    required this.quickAddEnabled,
    required this.units,
    this.facilities = const [],
  });

  final String description;
  final String address;
  final String mapLink;
  final bool quickAddEnabled;
  final List<_PropertyUnit> units;

  /// المرافق العامة المختارة في خطوة البيانات — تُحفظ في ملحقات العقار.
  final List<String> facilities;
}

// ============================================================
// خطوة 0-أ: نوع الملكية (عقار مملوك / إيجار من الباطن) — تحدد isSublease
// على الأصل النهائي (شارة "باطن" في القائمة).
// ============================================================
class _PropertyOwnershipStepScreen extends StatefulWidget {
  const _PropertyOwnershipStepScreen();

  @override
  State<_PropertyOwnershipStepScreen> createState() =>
      _PropertyOwnershipStepScreenState();
}

class _PropertyOwnershipStepScreenState
    extends State<_PropertyOwnershipStepScreen> {
  bool? _isSublease;

  @override
  Widget build(BuildContext context) {
    Widget option({
      required String title,
      required String subtitle,
      required IconData icon,
      required bool value,
    }) {
      final selected = _isSublease == value;
      return InkWell(
        onTap: () => setState(() => _isSublease = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? _kPropertyColor.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kPropertyColor : const Color(0xFFE1E7EF),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, color: _kPropertyColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _kPropertyColor : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'إضافة عقار',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _propertyFieldLabel('نوع الملكية'),
            const SizedBox(height: 10),
            option(
              title: 'عقار مملوك',
              subtitle: 'العقار مسجَّل باسمك وتديره مباشرةً',
              icon: Icons.home_work_rounded,
              value: false,
            ),
            const SizedBox(height: 10),
            option(
              title: 'إيجار من الباطن',
              subtitle: 'تستأجر العقار وتقوم بتأجيره لطرف آخر',
              icon: Icons.compare_arrows_rounded,
              value: true,
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _isSublease == null
                  ? null
                  : () => Navigator.of(context).pop(_isSublease),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPropertyColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'التالي',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// خطوة 0-ب: نوع العقار — شبكة الأنواع كما في الفيديو المرجعي.
// ============================================================
const List<Map<String, dynamic>> _propertyTypeOptions = [
  {'label': 'شقة', 'icon': Icons.apartment_rounded},
  {'label': 'استديو', 'icon': Icons.single_bed_rounded},
  {'label': 'فيلا', 'icon': Icons.villa_rounded},
  {'label': 'عمارة', 'icon': Icons.location_city_rounded},
  {'label': 'محل', 'icon': Icons.storefront_rounded},
  {'label': 'دور', 'icon': Icons.layers_rounded},
  {'label': 'غرفة', 'icon': Icons.meeting_room_rounded},
  {'label': 'شاليهات', 'icon': Icons.holiday_village_rounded},
  {'label': 'محطة', 'icon': Icons.local_gas_station_rounded},
  {'label': 'مجمع تجاري', 'icon': Icons.store_mall_directory_rounded},
  {'label': 'أرض', 'icon': Icons.terrain_rounded},
  {'label': 'شاليه', 'icon': Icons.cottage_rounded},
];

class _PropertyTypeGridScreen extends StatefulWidget {
  const _PropertyTypeGridScreen();

  @override
  State<_PropertyTypeGridScreen> createState() =>
      _PropertyTypeGridScreenState();
}

class _PropertyTypeGridScreenState extends State<_PropertyTypeGridScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'نوع العقار',
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
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: _propertyTypeOptions.length,
                itemBuilder: (context, index) {
                  final option = _propertyTypeOptions[index];
                  final label = option['label'] as String;
                  final icon = option['icon'] as IconData;
                  final selected = _selected == label;
                  return InkWell(
                    onTap: () => setState(() => _selected = label),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? _kPropertyColor.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? _kPropertyColor
                              : const Color(0xFFE1E7EF),
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 30,
                            color: selected
                                ? _kPropertyColor
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? _kPropertyColor
                                    : const Color(0xFF172033),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: ElevatedButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.of(context).pop(_selected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPropertyColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'التالي',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// المرافق العامة المنطقية لكل نوع عقار — لا يُعرض مسبح مع "محل" ولا
/// نادٍ رياضي مع "مستودع"؛ كل نوع يقترح مرافقه المعقولة فقط.
List<String> _facilitiesForPropertyType(String type) {
  switch (type) {
    case 'عمارة':
    case 'مجمع تجاري':
      return const [
        'مواقف سيارات عامة',
        'المصعد',
        'الدرج',
        'المداخل / اللوبي',
        'الممرات',
        'السطح',
        'غرفة الحارس',
        'غرفة الكهرباء',
        'غرفة الاتصالات',
        'غرفة المياه والمضخات',
        'خزانات المياه',
        'غرفة النفايات',
        'النادي الرياضي',
        'المسبح',
        'غرفة الخدمات',
        'ميزانين',
        'أخرى',
      ];
    case 'شقة':
    case 'استديو':
    case 'دور':
    case 'غرفة':
      return const [
        'مواقف سيارات عامة',
        'المصعد',
        'الدرج',
        'المداخل / اللوبي',
        'الممرات',
        'السطح',
        'خزانات المياه',
        'النادي الرياضي',
        'المسبح',
        'غرفة الخدمات',
        'أخرى',
      ];
    case 'فيلا':
    case 'شاليه':
    case 'شاليهات':
      return const [
        'مواقف سيارات عامة',
        'الحوش / الساحة',
        'السطح',
        'الدرج',
        'غرفة الحارس',
        'غرفة الكهرباء',
        'خزانات المياه',
        'المسبح',
        'غرفة الخدمات',
        'أخرى',
      ];
    case 'محل':
    case 'معرض':
      return const [
        'مواقف سيارات عامة',
        'المداخل / اللوبي',
        'الممرات',
        'غرفة الكهرباء',
        'ميزانين',
        'مستودع تخزين',
        'غرفة الخدمات',
        'أخرى',
      ];
    case 'مستودع':
      return const [
        'مواقف سيارات عامة',
        'مكتب إداري',
        'ميزانين',
        'غرفة الكهرباء',
        'غرفة الخدمات',
        'غرفة الحارس',
        'أخرى',
      ];
    case 'محطة':
      return const [
        'مواقف سيارات عامة',
        'مكتب إداري',
        'غرفة الكهرباء',
        'خزانات المياه',
        'مستودع تخزين',
        'غرفة الخدمات',
        'غرفة الحارس',
        'أخرى',
      ];
    case 'أرض':
      return const [
        'الحوش / الساحة',
        'غرفة الحارس',
        'خزانات المياه',
        'أخرى',
      ];
    default:
      return const [
        'مواقف سيارات عامة',
        'غرفة الكهرباء',
        'غرفة الخدمات',
        'أخرى',
      ];
  }
}

class _AddPropertyStep1Screen extends StatefulWidget {
  const _AddPropertyStep1Screen({required this.propertyType});

  /// نوع العقار المختار في الخطوة السابقة — يظهر أعلى الشاشة وتُبنى عليه
  /// قائمة المرافق العامة المنطقية.
  final String propertyType;

  @override
  State<_AddPropertyStep1Screen> createState() =>
      _AddPropertyStep1ScreenState();
}

class _AddPropertyStep1ScreenState extends State<_AddPropertyStep1Screen> {
  /// المرافق العامة المختارة لهذا العقار.
  final Set<String> _facilities = {};
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _mapLinkCtrl = TextEditingController();
  int _apartmentsCount = 0;
  int _studiosCount = 0;
  int _shopsCount = 0;
  bool _quickAddEnabled = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _mapLinkCtrl.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_apartmentsCount + _studiosCount + _shopsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدد عدد الوحدات (شقة أو استديو أو محل) أولاً'),
        ),
      );
      return;
    }

    if (_quickAddEnabled) {
      // الإضافة السريعة: توليد الوحدات تلقائياً بأرقام افتراضية بدل تعبئة
      // نموذج تفصيلي لكل وحدة على حدة.
      final units = <_PropertyUnit>[
        for (var i = 0; i < _apartmentsCount; i++)
          _PropertyUnit(
            type: _kUnitApartment,
            name: 'شقة ${i + 1}',
            unitNumber: '${i + 1}',
          ),
        for (var i = 0; i < _studiosCount; i++)
          _PropertyUnit(
            type: _kUnitStudio,
            name: 'استديو ${i + 1}',
            unitNumber: '${i + 1}',
            rooms: 1,
          ),
        for (var i = 0; i < _shopsCount; i++)
          _PropertyUnit(
            type: _kUnitShop,
            name: 'محل ${i + 1}',
            unitNumber: '${i + 1}',
          ),
      ];
      final result = await Navigator.of(context).push<_PropertyDraft>(
        MaterialPageRoute(
          builder: (_) => _PropertyReviewScreen(
            description: _descriptionCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            mapLink: _mapLinkCtrl.text.trim(),
            quickAddEnabled: true,
            units: units,
          ),
        ),
      );
      if (result != null && mounted) {
        Navigator.of(context).pop(_withFacilities(result));
      }
      return;
    }

    final result = await Navigator.of(context).push<_PropertyDraft>(
      MaterialPageRoute(
        builder: (_) => _PropertyUnitsDetailsScreen(
          description: _descriptionCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          mapLink: _mapLinkCtrl.text.trim(),
          apartmentsCount: _apartmentsCount,
          studiosCount: _studiosCount,
          shopsCount: _shopsCount,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(_withFacilities(result));
    }
  }

  /// يضمّ المرافق المختارة إلى المسودة العائدة من شاشات المراجعة.
  _PropertyDraft _withFacilities(_PropertyDraft draft) => _PropertyDraft(
    description: draft.description,
    address: draft.address,
    mapLink: draft.mapLink,
    quickAddEnabled: draft.quickAddEnabled,
    units: draft.units,
    facilities: _facilities.toList(growable: false),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'إضافة عقار',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // نوع العقار المختار — في الأعلى على اليمين وبخط واضح.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _kPropertyColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kPropertyColor, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.home_work_rounded,
                      size: 20,
                      color: _kPropertyColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'نوع العقار: ${widget.propertyType}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: _kPropertyColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // المرافق العامة المنطقية لهذا النوع فقط: محل بلا مسبح،
            // ومستودع بمكتب إداري وميزانين... حسب علاقات كل نوع.
            _propertyFieldLabel('المرافق العامة (اختياري)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final facility in _facilitiesForPropertyType(
                  widget.propertyType,
                ))
                  Builder(
                    builder: (context) {
                      final selected = _facilities.contains(facility);
                      return InkWell(
                        key: ValueKey('property-facility-$facility'),
                        onTap: () => setState(() {
                          if (!_facilities.remove(facility)) {
                            _facilities.add(facility);
                          }
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? _kPropertyColor.withValues(alpha: 0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? _kPropertyColor
                                  : const Color(0xFFE1E7EF),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 16,
                                color: selected
                                    ? _kPropertyColor
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                facility,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? _kPropertyColor
                                      : const Color(0xFF172033),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _propertyFieldLabel('الوصف'),
            const SizedBox(height: 6),
            TextField(
              controller: _descriptionCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCFE7DB)),
              ),
              child: const Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: Color(0xFF0B6E4F),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حدد موقع العقار من البحث أو العنوان حتى تظهر بياناته بشكل أوضح لاحقاً',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B6E4F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _propertyFieldLabel('العنوان / ابحث عن موقع'),
            const SizedBox(height: 6),
            TextField(
              controller: _addressCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(
                'مثال: مدينة الرياض 31 - أبو ظبي - الإمارات',
              ).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 12),
            _propertyFieldLabel('رابط الموقع على الخريطة (اختياري)'),
            const SizedBox(height: 6),
            TextField(
              controller: _mapLinkCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('رابط Google Maps مثلاً'),
            ),
            const SizedBox(height: 20),
            _propertyFieldLabel('عدد الوحدات'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CounterField(
                    label: 'عدد المحلات',
                    value: _shopsCount,
                    onChanged: (v) => setState(() => _shopsCount = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CounterField(
                    label: 'عدد الشقق',
                    value: _apartmentsCount,
                    onChanged: (v) => setState(() => _apartmentsCount = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CounterField(
                    label: 'عدد الاستديوهات',
                    value: _studiosCount,
                    onChanged: (v) => setState(() => _studiosCount = v),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Switch(
                  value: _quickAddEnabled,
                  activeTrackColor: _kPropertyColor,
                  onChanged: (v) => setState(() => _quickAddEnabled = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'تفعيل الإضافة السريعة',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'حدد عدد الوحدات أولاً، ثم فعّل الإضافة السريعة لتوليدها تلقائياً بدل تعبئة كل وحدة يدوياً',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _goNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPropertyColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'التالي',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _propertyFieldLabel(String text) => Align(
  alignment: Alignment.centerRight,
  child: Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: Color(0xFF334155),
      ),
    ),
  ),
);

/// حقول شاشات "إضافة عقار / نشاط تجاري / معدة".
///
/// كانت تُملأ بالأبيض فوق صفحة بيضاء، وتعرّف `border` وحده — بينما Flutter
/// يستعمل `enabledBorder` في الحالة العادية، وسِمة التطبيق تجعله بلا حدّ.
/// النتيجة: حقول لا يُرى لها أثر إطلاقًا، فلا يعرف المستخدم أين يكتب.
/// الآن هي بنفس شكل حقول التطبيق كلها: ممتلئة برمادي فاتح، نصف قطر موحّد،
/// وحدّ يظهر بلون التمييز عند التركيز.
InputDecoration _propertyInputDecoration(String hint) {
  OutlineInputBorder border([Color? color]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.rField),
    borderSide: color == null
        ? BorderSide.none
        : BorderSide(color: color, width: 1.4),
  );

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
    filled: true,
    fillColor: AppTheme.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(),
    enabledBorder: border(),
    disabledBorder: border(),
    focusedBorder: border(const Color(0xFF047857)),
    errorBorder: border(AppTheme.danger),
    focusedErrorBorder: border(AppTheme.danger),
  );
}

/// يحاول استخراج الإحداثيات (خط العرض، خط الطول) من رابط خرائط جوجل الذي
/// يلصقه المستخدم — يدعم صيغ "@lat,lng"، "q=lat,lng"، "ll=lat,lng"،
/// وكذلك إدخال الإحداثيات مباشرة "lat,lng". لا يحتاج أي مفتاح Google Maps
/// API؛ يعمل على نص الرابط نفسه فقط.
(double, double)? _parseLatLngFromMapLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final patterns = [
    RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|ll|query)=(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)'),
    RegExp(r'^\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*$'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null) return (lat, lng);
    }
  }
  return null;
}

class _CounterField extends StatelessWidget {
  const _CounterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => onChanged(value + 1),
              borderRadius: BorderRadius.circular(20),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFEFF6F2),
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: Color(0xFF0B6E4F),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF172033),
                ),
              ),
            ),
            InkWell(
              onTap: value > 0 ? () => onChanged(value - 1) : null,
              borderRadius: BorderRadius.circular(20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Icon(
                  Icons.remove_rounded,
                  size: 18,
                  color: value > 0
                      ? const Color(0xFF64748B)
                      : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// خطوة 2: تفاصيل الوحدات — نموذج متكرر لكل شقة ولكل محل
// ============================================================
class _PropertyUnitsDetailsScreen extends StatefulWidget {
  const _PropertyUnitsDetailsScreen({
    required this.description,
    required this.address,
    required this.mapLink,
    required this.apartmentsCount,
    required this.studiosCount,
    required this.shopsCount,
  });

  final String description;
  final String address;
  final String mapLink;
  final int apartmentsCount;
  final int studiosCount;
  final int shopsCount;

  @override
  State<_PropertyUnitsDetailsScreen> createState() =>
      _PropertyUnitsDetailsScreenState();
}

class _PropertyUnitsDetailsScreenState
    extends State<_PropertyUnitsDetailsScreen> {
  late List<_UnitFormData> _apartments = List.generate(
    widget.apartmentsCount,
    (_) => _UnitFormData(type: _kUnitApartment),
  );
  late List<_UnitFormData> _studios = List.generate(
    widget.studiosCount,
    (_) => _UnitFormData(type: _kUnitStudio),
  );
  late List<_UnitFormData> _shops = List.generate(
    widget.shopsCount,
    (_) => _UnitFormData(type: _kUnitShop),
  );

  @override
  void dispose() {
    for (final u in _apartments) {
      u.dispose();
    }
    for (final u in _studios) {
      u.dispose();
    }
    for (final u in _shops) {
      u.dispose();
    }
    super.dispose();
  }

  void _addApartment({bool copyLast = false}) {
    setState(() {
      final unit = _UnitFormData(type: _kUnitApartment);
      if (copyLast && _apartments.isNotEmpty) {
        unit.copyFrom(_apartments.last);
      }
      _apartments.add(unit);
    });
  }

  void _addStudio({bool copyLast = false}) {
    setState(() {
      final unit = _UnitFormData(type: _kUnitStudio);
      if (copyLast && _studios.isNotEmpty) {
        unit.copyFrom(_studios.last);
      }
      _studios.add(unit);
    });
  }

  void _addShop({bool copyLast = false}) {
    setState(() {
      final unit = _UnitFormData(type: _kUnitShop);
      if (copyLast && _shops.isNotEmpty) {
        unit.copyFrom(_shops.last);
      }
      _shops.add(unit);
    });
  }

  Future<void> _goReview() async {
    final units = [
      ..._apartments.map((u) => u.toUnit()),
      ..._studios.map((u) => u.toUnit()),
      ..._shops.map((u) => u.toUnit()),
    ];
    if (units.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أضف وحدة واحدة على الأقل')));
      return;
    }
    final result = await Navigator.of(context).push<_PropertyDraft>(
      MaterialPageRoute(
        builder: (_) => _PropertyReviewScreen(
          description: widget.description,
          address: widget.address,
          mapLink: widget.mapLink,
          quickAddEnabled: false,
          units: units,
        ),
      ),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'تفاصيل الوحدات',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (_apartments.isNotEmpty) ...[
              for (var i = 0; i < _apartments.length; i++) ...[
                _UnitFormCard(
                  data: _apartments[i],
                  onDelete: () => setState(() => _apartments.removeAt(i)),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _addApartment(copyLast: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPropertyColor,
                        side: const BorderSide(color: _kPropertyColor),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('نسخ آخر شقة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _addApartment(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPropertyColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('إضافة شقة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            if (_studios.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الاستديوهات',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _studios.length; i++) ...[
                _UnitFormCard(
                  data: _studios[i],
                  onDelete: () => setState(() => _studios.removeAt(i)),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _addStudio(copyLast: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPropertyColor,
                        side: const BorderSide(color: _kPropertyColor),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('نسخ آخر استديو'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _addStudio(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPropertyColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('إضافة استديو'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            if (_shops.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'المحلات',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _shops.length; i++) ...[
                _UnitFormCard(
                  data: _shops[i],
                  onDelete: () => setState(() => _shops.removeAt(i)),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _addShop(copyLast: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPropertyColor,
                        side: const BorderSide(color: _kPropertyColor),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('نسخ آخر محل'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _addShop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPropertyColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('إضافة محل'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            ElevatedButton(
              onPressed: _goReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF172033),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'مراجعة البيانات',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// حالة نموذج وحدة واحدة أثناء التعبئة (شقة أو محل) — تُحوَّل إلى
// _PropertyUnit عند الحفظ.
class _UnitFormData {
  _UnitFormData({required this.type});

  final String type; // 'شقة' أو 'استديو' أو 'محل'
  final nameCtrl = TextEditingController();
  final numberCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  int rooms = 2;
  int bathrooms = 2;
  bool hasParking = false;

  void copyFrom(_UnitFormData other) {
    nameCtrl.text = other.nameCtrl.text;
    numberCtrl.text = other.numberCtrl.text;
    areaCtrl.text = other.areaCtrl.text;
    rooms = other.rooms;
    bathrooms = other.bathrooms;
    hasParking = other.hasParking;
  }

  void dispose() {
    nameCtrl.dispose();
    numberCtrl.dispose();
    areaCtrl.dispose();
  }

  _PropertyUnit toUnit() => _PropertyUnit(
    type: type,
    name: nameCtrl.text.trim().isEmpty ? type : nameCtrl.text.trim(),
    unitNumber: numberCtrl.text.trim(),
    area: areaCtrl.text.trim(),
    rooms: _unitTypeRoomsFor(type, rooms),
    bathrooms: _unitTypeIsResidential(type) ? bathrooms : 0,
    hasParking: _unitTypeIsResidential(type) ? hasParking : false,
  );
}

class _UnitFormCard extends StatefulWidget {
  const _UnitFormCard({required this.data, required this.onDelete});

  final _UnitFormData data;
  final VoidCallback onDelete;

  @override
  State<_UnitFormCard> createState() => _UnitFormCardState();
}

class _UnitFormCardState extends State<_UnitFormCard> {
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    // الشقة والاستديو كلاهما سكني (مساحة/حمامات/موقف)، والفارق أن الاستديو
    // بلا عدد غرف مستقل. المحل تجاري: اسم ورقم ومساحة فقط.
    final isResidential = _unitTypeIsResidential(data.type);
    final hasRooms = _unitTypeHasRooms(data.type);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isResidential) ...[
            TextField(
              controller: data.nameCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('اسم الوحدة'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.areaCtrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: _propertyInputDecoration('المساحة'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.numberCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('رقم الوحدة'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (hasRooms) ...[
                  Expanded(
                    child: _StepperMini(
                      label: 'عدد الغرف',
                      value: data.rooms,
                      onChanged: (v) => setState(() => data.rooms = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _StepperMini(
                    label: 'عدد الحمامات',
                    value: data.bathrooms,
                    onChanged: (v) => setState(() => data.bathrooms = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                const Text(
                  'موقف سيارة',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                _YesNoToggle(
                  value: data.hasParking,
                  onChanged: (v) => setState(() => data.hasParking = v),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFB42318),
                  ),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: data.nameCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('اسم المحل'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.numberCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('رقم المحل'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: data.areaCtrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: _propertyInputDecoration('مساحة المحل'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFB42318),
                  ),
                ),
                // (أُزيل زر "نسخ" الذي كان ينسخ بيانات البطاقة إلى نفسها،
                // أي بلا أي أثر فعلي. النسخ الحقيقي متاح عبر زر
                // "نسخ آخر محل" أسفل القائمة.)
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperMini extends StatelessWidget {
  const _StepperMini({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => onChanged(value + 1),
              child: const Icon(
                Icons.add_circle_outline_rounded,
                size: 20,
                color: Color(0xFF0B6E4F),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            InkWell(
              onTap: value > 0 ? () => onChanged(value - 1) : null,
              child: Icon(
                Icons.remove_circle_outline_rounded,
                size: 20,
                color: value > 0
                    ? const Color(0xFF64748B)
                    : const Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _YesNoToggle extends StatelessWidget {
  const _YesNoToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _kPropertyColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _kPropertyColor : const Color(0xFFCBD5E1),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option('نعم', value, () => onChanged(true)),
        const SizedBox(width: 6),
        option('لا', !value, () => onChanged(false)),
      ],
    );
  }
}

// ============================================================
// خطوة 3: مراجعة البيانات قبل الإرسال
// ============================================================
class _PropertyReviewScreen extends StatelessWidget {
  const _PropertyReviewScreen({
    required this.description,
    required this.address,
    required this.mapLink,
    required this.quickAddEnabled,
    required this.units,
  });

  final String description;
  final String address;
  final String mapLink;
  final bool quickAddEnabled;
  final List<_PropertyUnit> units;

  String get _propertyType {
    if (units.length > 1) return 'عمارة';
    if (units.length == 1) return units.first.type;
    return _kUnitApartment;
  }

  void _confirm(BuildContext context) {
    final draft = _PropertyDraft(
      description: description,
      address: address,
      mapLink: mapLink,
      quickAddEnabled: quickAddEnabled,
      units: units,
    );
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final apartments = units.where((u) => u.type == _kUnitApartment).length;
    final studios = units.where((u) => u.type == _kUnitStudio).length;
    final shops = units.where((u) => u.type == _kUnitShop).length;
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'مراجعة البيانات',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              'مراجعة تفاصيل العقار قبل الإرسال',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kPropertyColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.apartment_rounded,
                          color: _kPropertyColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          description.isEmpty ? 'بدون اسم' : description,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _propertyReviewRow('نوع العقار', _propertyType),
                  _propertyReviewRow(
                    'الموقع',
                    address.isEmpty ? 'غير محدد' : address,
                  ),
                  if (mapLink.isNotEmpty)
                    _propertyReviewRow('رابط الخريطة', mapLink),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFEEF2F7)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _propertyReviewCount(
                          _kUnitApartment,
                          apartments,
                          Icons.home_work_outlined,
                        ),
                      ),
                      Expanded(
                        child: _propertyReviewCount(
                          _kUnitStudio,
                          studios,
                          Icons.single_bed_rounded,
                        ),
                      ),
                      Expanded(
                        child: _propertyReviewCount(
                          _kUnitShop,
                          shops,
                          Icons.storefront_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCE3C0)),
              ),
              child: const Text(
                'تأكد من جميع البيانات قبل الإرسال، يمكنك العودة للتعديل إذا لزم الأمر',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9A5B13),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _confirm(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPropertyColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'تأكيد وإضافة العقار',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _propertyReviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF334155),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _propertyReviewCount(String label, int count, IconData icon) =>
      Column(
        children: [
          Icon(icon, color: _kPropertyColor, size: 20),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      );
}

// ============================================================
// عناصر شاشة "تفاصيل العقار" المخصّصة — نفس نمط الهيدر المدمج وشريط
// أبرز البيانات وبطاقة القائمة المعتمد في قوالب الالتزامات الشخصية
// والمشتركة وإدارة الأفراد والجهات.
// ============================================================

class _AssetDetailHeaderCard extends StatelessWidget {
  const _AssetDetailHeaderCard({
    required this.item,
    required this.onAction,
    required this.icon,
    required this.accentColor,
  });

  final _AssetItem item;
  final ValueChanged<ThreeDotMenuAction> onAction;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final statusLabel = item.isFrozen ? 'مجمّد' : item.status;
    final statusColor = item.isFrozen
        ? const Color(0xFF64748B)
        : item.needsAttention
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.subType} · ${item.locationOrType}',
                  textAlign: TextAlign.right,
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
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
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

class _AssetHighlightTile {
  const _AssetHighlightTile(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;
}

/// مفتاح "الشاغرة" داخل بطاقة الوحدات — حالة لا نوع.
const String _kVacantUnitsKey = '__vacant';

/// بطاقة "الوحدات" أعلى تبويب الوحدات: عدد كل نوع موجود فعلًا + الشاغر،
/// محسوبة من الوحدات نفسها فتشمل أي نوع جديد (مستودع، مكتب، غرفة...).
/// والضغط على أي نوع يفتح وحداته أسفل البطاقة.
class _UnitsCompositionCard extends StatelessWidget {
  const _UnitsCompositionCard({
    required this.units,
    required this.selectedType,
    required this.onSelectType,
  });

  final List<_PropertyUnit> units;
  final String? selectedType;
  final ValueChanged<String> onSelectType;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final unit in units) {
      counts[unit.type] = (counts[unit.type] ?? 0) + 1;
    }
    final vacant = units.where((u) => u.status == 'شاغرة').length;
    final entries =
        <({IconData icon, String value, String label, Color color, String key})>[
          for (final type in _kUnitTypes)
            if ((counts[type] ?? 0) > 0)
              (
                icon: _unitTypeIcon(type),
                value: '${counts[type]}',
                label: type,
                color: _kPropertyColor,
                key: type,
              ),
          // أي نوع قديم محفوظ خارج القائمة الحالية لا يختفي من العدّ.
          for (final entry in counts.entries)
            if (!_kUnitTypes.contains(entry.key))
              (
                icon: Icons.dashboard_customize_rounded,
                value: '${entry.value}',
                label: entry.key,
                color: _kPropertyColor,
                key: entry.key,
              ),
          (
            icon: Icons.meeting_room_outlined,
            value: '$vacant',
            label: 'شاغرة',
            color: const Color(0xFFD97706),
            key: _kVacantUnitsKey,
          ),
        ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: _kPropertyColor,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'الوحدات',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                selectedType == null
                    ? '${units.length} وحدة'
                    : 'اضغط مرة أخرى لعرض الكل',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                Material(
                  color: selectedType == entry.key
                      ? entry.color.withValues(alpha: 0.12)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelectType(entry.key),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedType == entry.key
                              ? entry.color
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.icon, size: 15, color: entry.color),
                          const SizedBox(width: 6),
                          Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: entry.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entry.label,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            selectedType == entry.key
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 15,
                            color: const Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssetHighlightBarRow extends StatelessWidget {
  const _AssetHighlightBarRow({
    required this.tiles,
    required this.accentColor,
  });

  final List<_AssetHighlightTile> tiles;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    Widget tile(_AssetHighlightTile t) => Expanded(
      child: Column(
        children: [
          Icon(t.icon, size: 16, color: accentColor),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              t.value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            t.label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );

    Widget divider() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: accentColor.withValues(alpha: 0.18),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) divider(),
            tile(tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.name,
    required this.role,
    required this.onDelete,
  });

  final String name;
  final String role;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kActivityColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: _kActivityColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  name.isEmpty ? 'بدون اسم' : name,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role.isEmpty ? 'غير محدد' : role,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFB42318),
            ),
          ),
        ],
      ),
    );
  }
}

/// خريطة ثابتة (صورة بدون مفتاح Google Maps API) + زر "فتح في الخرائط"
/// يفتح الموقع الحقيقي في تطبيق الخرائط الخارجي عبر url_launcher — البديل
/// المعتمد من المستخدم بدل الخريطة التفاعلية (تجنّبًا لإعداد مفتاح API).
/// بطاقة عرض العقار في قائمة "العقارات" — بشارات حقيقية مبنية على بيانات
/// العقار نفسه (عدد الوحدات، نوع العقار، إيجار من الباطن، شاغرة)، بدل
/// البطاقة العامة المستخدمة لبقية الفئات.
class _LeaseMapHeader extends StatelessWidget {
  const _LeaseMapHeader({
    required this.latitude,
    required this.longitude,
    this.contract,
    this.isSublease = false,
    this.onManage,
  });

  final double latitude;
  final double longitude;
  final PropertyUnitContractRecord? contract;
  final bool isSublease;

  /// عند تمريره تظهر أيقونتا "تعديل" (أعلى الخريطة) و"..." (على البطاقة)،
  /// وكلتاهما تنفّذان نفس إجراء إدارة عقد الإيجار الحالي. تُخفى الأيقونتان
  /// تمامًا إن لم يمرَّر أي إجراء بدل عرض أزرار بلا وظيفة.
  final VoidCallback? onManage;

  Future<void> _openExternally(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الخرائط')));
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final staticMapUrl =
        'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$latitude,$longitude&zoom=15&size=640x320'
        '&markers=$latitude,$longitude,red-pushpin';
    final c = contract;
    final showSubleaseTag =
        isSublease || c?.leaseType == PropertyUnitContractRecord.leaseTypeSublease;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: c != null ? 300 : 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFFF1F5F9),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: () => _openExternally(context),
                child: Image.network(
                  staticMapUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.map_outlined,
                      size: 34,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ),
            if (c == null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 13,
                        color: _kPropertyColor,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'فتح في الخرائط',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _kPropertyColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (c != null) ...[
              if (onManage != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _circleIconButton(
                    icon: Icons.edit_rounded,
                    onTap: onManage,
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                top: 56,
                bottom: 40,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 34, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              const Icon(
                                Icons.home_work_rounded,
                                color: Colors.white70,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  showSubleaseTag
                                      ? 'ملف الإيجار من الباطن'
                                      : 'ملف الإيجار',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.tenantName ?? '—',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 6,
                            textDirection: TextDirection.rtl,
                            children: [
                              _pill(Icons.sync_alt_rounded, c.paymentCycle),
                              _pill(
                                Icons.payments_outlined,
                                'الإيجار السنوي ${c.annualRent.toStringAsFixed(0)} ريال',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                color: Colors.white70,
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_fmtDate(c.startDate)} - ${_fmtDate(c.endDate)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (showSubleaseTag)
                        Positioned(
                          top: -22,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'من الباطن',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      if (onManage != null)
                        Positioned(
                          bottom: -2,
                          left: 0,
                          child: _circleIconButton(
                            icon: Icons.more_horiz_rounded,
                            onTap: onManage,
                            size: 26,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    double size = 32,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.5, color: Colors.white),
      ),
    );
  }

  Widget _pill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// بطاقة موحّدة لعقد "متعدد الوحدات" — تجمع كل الوحدات المشمولة بنفس العقد
/// (نفس group_key) بدل عرض بطاقة منفصلة لكل واحدة منها.
class _MultiUnitContractCard extends StatelessWidget {
  const _MultiUnitContractCard({
    required this.units,
    required this.contract,
    required this.onTap,
  });

  final List<_PropertyUnit> units;
  final PropertyUnitContractRecord contract;
  final VoidCallback onTap;

  bool get _isOverdue =>
      contract.status == PropertyUnitContractRecord.statusLate ||
      (contract.endDate != null && contract.endDate!.isBefore(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final unitNumbers = units
        .map((u) => u.unitNumber.isEmpty ? u.name : u.unitNumber)
        .join('، ');
    final statusColor = _isOverdue
        ? const Color(0xFFEF4444)
        : const Color(0xFF10B981);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _isOverdue ? 'متأخرة' : 'نشطة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    contract.tenantName ?? '—',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${units.length} وحدات مشمولة',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الوحدات المشمولة: $unitNumbers',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'توزيع متساوٍ: ${contract.annualRent.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'عقد متعدد الوحدات',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B82F6),
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

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.onToggleStatus,
    this.onTap,
  });

  final _PropertyUnit unit;
  final VoidCallback onToggleStatus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vacant = unit.status == 'شاغرة';
    final statusColor = vacant
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);
    final residential = _unitTypeIsResidential(unit.type);
    final details = <String>[
      unit.type,
      if (unit.area.trim().isNotEmpty) '${unit.area} م²',
      if (_unitTypeHasRooms(unit.type)) '${unit.rooms} غرف',
      if (residential) '${unit.bathrooms} حمامات',
      if (residential) (unit.hasParking ? 'موقف سيارة' : 'بدون موقف'),
    ];
    // اتجاه صريح للبطاقة بالكامل حتى لا تتأثر بمحاذاة الشاشة المحيطة:
    // مع rtl يصبح CrossAxisAlignment.start = محاذاة لليمين، وأول عنصر في
    // الصف هو الأيمن. هذا يضمن ثبات الترتيب أينما استُخدمت البطاقة.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // اسم الوحدة وتحته رقمها — في أقصى اليمين.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unit.name,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'رقم الوحدة: ${unit.unitNumber.isEmpty ? '—' : unit.unitNumber}',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // حالة الوحدة ثم السهم — في أقصى اليسار.
                  InkWell(
                    onTap: onToggleStatus,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unit.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 2),
                    // اتجاه ثابت ltr للأيقونة فقط: بعض أيقونات الأسهم في
                    // فلاتر تنعكس تلقائيًا مع rtl، وهذا يثبّتها متجهة لليسار.
                    const Directionality(
                      textDirection: TextDirection.ltr,
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),
                // بقية بيانات الوحدة في منتصف السطر السفلي.
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    for (int i = 0; i < details.length; i++) ...[
                      if (i != 0)
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        details[i],
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// تبويب "الحركة المالية" لوحدة (شقة/محل/استديو): زرّا تسجيل إيراد ومصروف،
/// ملخّص حقيقي للإجماليات والصافي، وقائمة الحركات المسجّلة مع تعديل وحذف.
/// كل رقم هنا محسوب من سجلات property_unit_transactions الفعلية.
class _UnitFinancialsTab extends StatelessWidget {
  const _UnitFinancialsTab({
    required this.transactions,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PropertyUnitTransactionRecord> transactions;
  final ValueChanged<String> onAdd;
  final ValueChanged<PropertyUnitTransactionRecord> onEdit;
  final ValueChanged<PropertyUnitTransactionRecord> onDelete;

  static const _incomeColor = Color(0xFF10B981);
  static const _expenseColor = Color(0xFFEF4444);

  String _money(double v) => v.toStringAsFixed(2);

  String _fmtDate(DateTime? d) {
    if (d == null) return 'بدون تاريخ';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final income = transactions
        .where((t) => t.isIncome)
        .fold<double>(0, (s, t) => s + t.amount);
    final expense = transactions
        .where((t) => !t.isIncome)
        .fold<double>(0, (s, t) => s + t.amount);
    final net = income - expense;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: 'الدخل / الإيراد',
                  icon: Icons.trending_up_rounded,
                  color: _incomeColor,
                  onTap: () =>
                      onAdd(PropertyUnitTransactionRecord.kindIncome),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  label: 'المصروف',
                  icon: Icons.trending_down_rounded,
                  color: _expenseColor,
                  onTap: () =>
                      onAdd(PropertyUnitTransactionRecord.kindExpense),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
            child: Row(
              children: [
                Expanded(
                  child: _summaryCell(
                    'إجمالي الإيرادات',
                    _money(income),
                    _incomeColor,
                  ),
                ),
                Container(width: 1, height: 34, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _summaryCell(
                    'إجمالي المصروفات',
                    _money(expense),
                    _expenseColor,
                  ),
                ),
                Container(width: 1, height: 34, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _summaryCell(
                    'الصافي',
                    _money(net),
                    net < 0 ? _expenseColor : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (transactions.isEmpty)
            const _DetailHintCard(
              message:
                  'لا توجد حركة مالية مسجّلة لهذه الوحدة بعد. استخدم زر "الدخل / الإيراد" لتسجيل دخل، أو زر "المصروف" لتسجيل مصروف عليها.',
            )
          else ...[
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'سجل الحركات',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final t in transactions)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onEdit(t),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: (t.isIncome ? _incomeColor : _expenseColor)
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            t.isIncome
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 18,
                            color: t.isIncome ? _incomeColor : _expenseColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (t.category ?? '').trim().isEmpty
                                    ? (t.isIncome ? 'إيراد' : 'مصروف')
                                    : t.category!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (t.note ?? '').trim().isEmpty
                                    ? _fmtDate(t.occurredOn)
                                    : '${_fmtDate(t.occurredOn)} · ${t.note!.trim()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${t.isIncome ? '+' : '-'}${_money(t.amount)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: t.isIncome ? _incomeColor : _expenseColor,
                          ),
                        ),
                        IconButton(
                          onPressed: () => onDelete(t),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _summaryCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// شاشة تفاصيل الوحدة — حالتان: شاغرة (أزرار طلب عقد/إعلان + إضافة مستأجر)
// أو مؤجرة (بيانات المستأجر + متابعة الدفعات)، مبنية بالكامل على
// property_unit_contracts / property_unit_payments الحقيقية (بدون أي
// بيانات وهمية أو أزرار بلا وظيفة).
// ============================================================

class _UnitDetailsScreen extends StatefulWidget {
  const _UnitDetailsScreen({
    required this.assetId,
    required this.assetTitle,
    required this.unit,
    required this.repository,
    required this.onUnitStatusChanged,
    this.assetLocation,
    this.assetLatitude,
    this.assetLongitude,
  });

  final String? assetId;
  final String assetTitle;
  final _PropertyUnit unit;
  final ProjectAssetsRepository? repository;
  final ValueChanged<String> onUnitStatusChanged;
  final String? assetLocation;
  final double? assetLatitude;
  final double? assetLongitude;

  @override
  State<_UnitDetailsScreen> createState() => _UnitDetailsScreenState();
}

class _UnitDetailsScreenState extends State<_UnitDetailsScreen> {
  bool _loading = true;
  String? _error;
  PropertyUnitContractRecord? _contract;
  List<PropertyUnitPaymentRecord> _payments = const [];
  List<PropertyUnitTransactionRecord> _transactions = const [];
  int _selectedTab = 0;

  static const List<DetailSectionTab> _unitTabs = [
    DetailSectionTab(label: 'الإيجار', icon: Icons.assignment_outlined),
    DetailSectionTab(
      label: 'الحركة المالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(label: 'الصيانة', icon: Icons.build_outlined),
    DetailSectionTab(label: 'المتابعات', icon: Icons.event_note_outlined),
    DetailSectionTab(label: 'الملاحظات', icon: Icons.sticky_note_2_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    final assetId = widget.assetId;
    if (repo == null || assetId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contracts = await repo.fetchUnitContracts(assetId);
      final mine = contracts
          .where((c) => c.unitKey == widget.unit.unitKey)
          .toList();
      final active = mine.isNotEmpty ? mine.first : null;
      List<PropertyUnitPaymentRecord> payments = const [];
      if (active?.id != null) {
        payments = await repo.fetchUnitPayments(active!.id!);
      }
      // تُجلب الحركات المالية في محاولة مستقلة: فشلها (مثلاً لأن جدول
      // property_unit_transactions لم يُنشأ بعد على الخادم) يجب ألا يُسقط
      // شاشة الوحدة كلها ويُخفي بيانات العقد والدفعات السليمة.
      List<PropertyUnitTransactionRecord> transactions = const [];
      try {
        transactions = await repo.fetchUnitTransactions(
          assetId,
          unitKey: widget.unit.unitKey,
        );
      } catch (_) {
        transactions = const [];
      }
      if (!mounted) return;
      setState(() {
        _contract = active;
        _payments = payments;
        _transactions = transactions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل بيانات الوحدة';
      });
    }
  }

  double get _totalDue =>
      _payments.fold<double>(0, (sum, p) => sum + p.amountDue);
  double get _totalPaid =>
      _payments.fold<double>(0, (sum, p) => sum + p.amountPaid);
  double get _totalRemaining => (_totalDue - _totalPaid).clamp(
    0,
    double.infinity,
  );

  bool get _hasOverdue => _payments.any(
    (p) =>
        p.status != PropertyUnitPaymentRecord.statusPaid &&
        p.dueDate != null &&
        p.dueDate!.isBefore(DateTime.now()),
  );

  /// نموذج إضافة/تعديل حركة مالية (إيراد أو مصروف) على هذه الوحدة.
  /// يُحفظ فعليًا في property_unit_transactions مرتبطًا بمفتاح الوحدة.
  Future<void> _openTransactionForm({
    required String kind,
    PropertyUnitTransactionRecord? existing,
  }) async {
    final repo = widget.repository;
    final assetId = widget.assetId;
    if (repo == null || assetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب حفظ العقار أولاً قبل تسجيل حركة مالية'),
        ),
      );
      return;
    }
    final income = kind == PropertyUnitTransactionRecord.kindIncome;
    final amountCtrl = TextEditingController(
      text: existing == null || existing.amount == 0
          ? ''
          : existing.amount.toStringAsFixed(2),
    );
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    DateTime? occurredOn = existing?.occurredOn ?? DateTime.now();
    final accent = income ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final suggestions = income
        ? const ['إيجار', 'تأمين مسترد', 'رسوم خدمات', 'دخل آخر']
        : const ['صيانة', 'كهرباء وماء', 'رسوم حكومية', 'تنظيف', 'مصروف آخر'];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            income
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            color: accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            existing == null
                                ? (income ? 'إضافة إيراد' : 'إضافة مصروف')
                                : (income ? 'تعديل إيراد' : 'تعديل مصروف'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountCtrl,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _propertyInputDecoration('المبلغ'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: sheetContext,
                            initialDate: occurredOn ?? DateTime.now(),
                            firstDate: DateTime(2015),
                            lastDate: DateTime(2060),
                          );
                          if (picked != null) {
                            setSheetState(() => occurredOn = picked);
                          }
                        },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(
                          occurredOn == null
                              ? 'تاريخ الحركة'
                              : '${occurredOn!.year}/${occurredOn!.month}/${occurredOn!.day}',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: categoryCtrl,
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration('التصنيف'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in suggestions)
                            ActionChip(
                              label: Text(
                                s,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () =>
                                  setSheetState(() => categoryCtrl.text = s),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteCtrl,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        decoration: _propertyInputDecoration('ملاحظات'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final amount =
                              double.tryParse(amountCtrl.text.trim()) ?? 0;
                          if (amount <= 0) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text('أدخل مبلغًا صحيحًا أكبر من صفر'),
                              ),
                            );
                            return;
                          }
                          final record = PropertyUnitTransactionRecord(
                            id: existing?.id,
                            assetId: assetId,
                            unitKey: widget.unit.unitKey,
                            kind: kind,
                            amount: amount,
                            occurredOn: occurredOn,
                            category: categoryCtrl.text.trim().isEmpty
                                ? null
                                : categoryCtrl.text.trim(),
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                          try {
                            await repo.upsertUnitTransaction(record);
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop(true);
                          } catch (e) {
                            if (!sheetContext.mounted) return;
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر حفظ الحركة المالية'),
                              ),
                            );
                          }
                        },
                        child: Text(
                          existing == null ? 'حفظ' : 'حفظ التعديل',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _deleteTransaction(PropertyUnitTransactionRecord t) async {
    final repo = widget.repository;
    if (repo == null || t.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الحركة المالية'),
          content: const Text('سيتم حذف هذه الحركة نهائيًا. هل تريد المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'حذف',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deleteUnitTransaction(t.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حذف الحركة المالية')));
    }
  }

  Future<void> _openTenantForm() async {
    final repo = widget.repository;
    final assetId = widget.assetId;
    if (repo == null || assetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب حفظ العقار أولاً قبل إضافة مستأجر')),
      );
      return;
    }
    final tenantCtrl = TextEditingController(text: _contract?.tenantName);
    final phoneCtrl = TextEditingController(text: _contract?.tenantPhone);
    final rentCtrl = TextEditingController(
      text: _contract?.annualRent == null || _contract!.annualRent == 0
          ? ''
          : _contract!.annualRent.toString(),
    );
    final notesCtrl = TextEditingController(text: _contract?.notes ?? '');
    String cycle = _contract?.paymentCycle ?? 'شهري';
    DateTime? start = _contract?.startDate;
    DateTime? end = _contract?.endDate;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'إضافة / تعديل مستأجر',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tenantCtrl,
                      textAlign: TextAlign.right,
                      decoration: _propertyInputDecoration('اسم المستأجر'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.phone,
                      decoration: _propertyInputDecoration(
                        'رقم جوال المستأجر (اختياري)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rentCtrl,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      decoration: _propertyInputDecoration(
                        'قيمة الإيجار السنوي',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: cycle,
                      decoration: _propertyInputDecoration('دورية السداد'),
                      items: const [
                        'شهري',
                        'ربع سنوي',
                        'نصف سنوي',
                        'سنوي',
                      ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setSheetState(() => cycle = v ?? cycle),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: sheetContext,
                                initialDate: start ?? DateTime.now(),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2060),
                              );
                              if (picked != null) {
                                setSheetState(() => start = picked);
                              }
                            },
                            child: Text(
                              start == null
                                  ? 'تاريخ البداية'
                                  : '${start!.year}/${start!.month}/${start!.day}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: sheetContext,
                                initialDate:
                                    end ?? start ?? DateTime.now(),
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2060),
                              );
                              if (picked != null) {
                                setSheetState(() => end = picked);
                              }
                            },
                            child: Text(
                              end == null
                                  ? 'تاريخ الانتهاء'
                                  : '${end!.year}/${end!.month}/${end!.day}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      textAlign: TextAlign.right,
                      maxLines: 3,
                      decoration: _propertyInputDecoration('ملاحظات'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPropertyColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (tenantCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('أدخل اسم المستأجر')),
                          );
                          return;
                        }
                        final record = PropertyUnitContractRecord(
                          id: _contract?.id,
                          assetId: assetId,
                          unitKey: widget.unit.unitKey,
                          unitName: widget.unit.name,
                          tenantName: tenantCtrl.text.trim(),
                          tenantPhone: phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                          leaseType:
                              _contract?.leaseType ??
                              PropertyUnitContractRecord.leaseTypeStandard,
                          groupKey: _contract?.groupKey,
                          annualRent:
                              double.tryParse(rentCtrl.text.trim()) ?? 0,
                          paymentCycle: cycle,
                          startDate: start,
                          endDate: end,
                          status: PropertyUnitContractRecord.statusActive,
                          notes: notesCtrl.text.trim(),
                        );
                        try {
                          final saved = await repo.upsertUnitContract(record);
                          if (!sheetContext.mounted) return;
                          setState(() => _contract = saved);
                          widget.onUnitStatusChanged('مؤجرة');
                          Navigator.of(sheetContext).pop(true);
                        } catch (e) {
                          if (!sheetContext.mounted) return;
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('تعذر حفظ بيانات المستأجر')),
                          );
                        }
                      },
                      child: const Text('حفظ'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _openPaymentForm({PropertyUnitPaymentRecord? existing}) async {
    final repo = widget.repository;
    final contract = _contract;
    if (repo == null || contract?.id == null) return;
    final dueCtrl = TextEditingController(
      text: existing == null || existing.amountDue == 0
          ? ''
          : existing.amountDue.toStringAsFixed(2),
    );
    final paidCtrl = TextEditingController(
      text: existing == null || existing.amountPaid == 0
          ? ''
          : existing.amountPaid.toStringAsFixed(2),
    );
    final refCtrl = TextEditingController(text: existing?.referenceNo ?? '');
    DateTime? dueDate = existing?.dueDate ?? DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'تسجيل سداد' : 'تعديل الدفعة',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2060),
                        );
                        if (picked != null) {
                          setSheetState(() => dueDate = picked);
                        }
                      },
                      child: Text(
                        dueDate == null
                            ? 'تاريخ الاستحقاق'
                            : '${dueDate!.year}/${dueDate!.month}/${dueDate!.day}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dueCtrl,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      decoration: _propertyInputDecoration('المبلغ المستحق'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: paidCtrl,
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      decoration: _propertyInputDecoration('المبلغ المسدد'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: refCtrl,
                      textAlign: TextAlign.right,
                      decoration: _propertyInputDecoration('رقم المرجع / السند'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPropertyColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final due = double.tryParse(dueCtrl.text.trim()) ?? 0;
                        final paid =
                            double.tryParse(paidCtrl.text.trim()) ?? 0;
                        if (due <= 0 && paid <= 0) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('أدخل مبلغًا صحيحًا')),
                          );
                          return;
                        }
                        String status = PropertyUnitPaymentRecord.statusPending;
                        if (paid >= due && due > 0) {
                          status = PropertyUnitPaymentRecord.statusPaid;
                        } else if (paid > 0) {
                          status = PropertyUnitPaymentRecord.statusPartial;
                        }
                        final record = PropertyUnitPaymentRecord(
                          id: existing?.id,
                          contractId: contract!.id!,
                          dueDate: dueDate,
                          amountDue: due,
                          amountPaid: paid,
                          paidAt: paid > 0
                              ? (existing?.paidAt ?? DateTime.now())
                              : null,
                          status: status,
                          referenceNo: refCtrl.text.trim().isEmpty
                              ? null
                              : refCtrl.text.trim(),
                          notes: existing?.notes,
                        );
                        try {
                          await repo.upsertUnitPayment(record);
                          if (!sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop(true);
                        } catch (e) {
                          if (!sheetContext.mounted) return;
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('تعذر حفظ الدفعة')),
                          );
                        }
                      },
                      child: Text(
                        existing == null ? 'حفظ الدفعة' : 'حفظ التعديل',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (saved == true) {
      await _load();
    }
  }

  void _shareFinancialClaim() {
    final contract = _contract;
    if (contract == null) return;
    Share.share(
      'مطالبة مالية\n'
      'العقار: ${widget.assetTitle}\n'
      'الوحدة: ${widget.unit.name}\n'
      'المستأجر: ${contract.tenantName ?? '—'}\n'
      'الإيجار السنوي: ${contract.annualRent.toStringAsFixed(0)}\n'
      'إجمالي المستحق: ${_totalDue.toStringAsFixed(0)}\n'
      'إجمالي المسدد: ${_totalPaid.toStringAsFixed(0)}\n'
      'المتبقي: ${_totalRemaining.toStringAsFixed(0)}',
    );
  }

  void _shareReceiptVoucher() {
    final contract = _contract;
    if (contract == null || _payments.isEmpty) return;
    final lastPaid = _payments.lastWhere(
      (p) => p.amountPaid > 0,
      orElse: () => _payments.first,
    );
    Share.share(
      'سند قبض\n'
      'العقار: ${widget.assetTitle}\n'
      'الوحدة: ${widget.unit.name}\n'
      'المستأجر: ${contract.tenantName ?? '—'}\n'
      'المبلغ المسدد: ${lastPaid.amountPaid.toStringAsFixed(0)}\n'
      'المرجع: ${lastPaid.referenceNo ?? '—'}\n'
      'التاريخ: ${lastPaid.paidAt != null ? '${lastPaid.paidAt!.year}/${lastPaid.paidAt!.month}/${lastPaid.paidAt!.day}' : '—'}',
    );
  }

  void _shareAdRequest() {
    Share.share(
      'طلب إعلان عقاري\n'
      'العقار: ${widget.assetTitle}\n'
      'الوحدة: ${widget.unit.name} (${widget.unit.type})\n'
      'المساحة: ${widget.unit.area.isEmpty ? '—' : widget.unit.area} م²\n'
      'الحالة: شاغرة ومتاحة للإيجار',
    );
  }

  /// أقدم دفعة غير مسددة بالكامل وتجاوز تاريخ استحقاقها اليوم — تُعرض في
  /// بطاقة تنبيه أعلى تبويب "الإيجار" (نفس فكرة "الدفعة متأخرة منذ..." في
  /// الشاشات المرجعية).
  PropertyUnitPaymentRecord? get _mostOverduePayment {
    final overdue =
        _payments
            .where(
              (p) =>
                  p.status != PropertyUnitPaymentRecord.statusPaid &&
                  p.dueDate != null &&
                  p.dueDate!.isBefore(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return overdue.isEmpty ? null : overdue.first;
  }

  /// رقم عقد مختصر ومستقر مُشتق من معرّف العقد الفعلي في قاعدة البيانات
  /// (وليس رقمًا وهميًا) — لعرضه بنفس شكل "رقم العقد" في الشاشات المرجعية.
  String _contractNumber(PropertyUnitContractRecord contract) {
    final id = contract.id;
    if (id == null) return '—';
    final digitsOnly = id.replaceAll(RegExp('[^0-9]'), '');
    final source = digitsOnly.isEmpty ? id.replaceAll('-', '') : digitsOnly;
    return source.length <= 11 ? source : source.substring(0, 11);
  }

  String _cycleDetailLabel(PropertyUnitContractRecord contract) {
    final count = _payments.length;
    final cyclePart = switch (contract.paymentCycle) {
      'شهري' => 'كل شهر',
      'ربع سنوي' => 'كل 3 أشهر',
      'نصف سنوي' => 'كل 6 أشهر',
      'سنوي' => 'سنويًا',
      _ => contract.paymentCycle,
    };
    return count == 0 ? cyclePart : '$cyclePart ($count دفعات)';
  }

  Future<void> _launchPhone(String phone, {required bool whatsapp}) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    final uri = whatsapp
        ? Uri.parse('https://wa.me/${digits.replaceAll('+', '')}')
        : Uri.parse('tel:$digits');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(whatsapp ? 'تعذر فتح واتساب' : 'تعذر إجراء الاتصال')),
      );
    }
  }

  Future<void> _addPastPaymentsAndExpenses() async {
    if (_contract == null) {
      await _openTenantForm();
      if (_contract == null || !mounted) return;
    }
    await _openPaymentForm();
  }

  Future<void> _editOrDeleteOverduePayment(
    PropertyUnitPaymentRecord payment,
  ) async {
    final repo = widget.repository;
    if (repo == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل الدفعة'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
              title: const Text('حذف الدفعة', style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'delete') {
      if (payment.id != null) {
        await repo.deleteUnitPayment(payment.id!);
        await _load();
      }
    } else if (action == 'edit') {
      await _openPaymentForm(existing: payment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leased = _contract != null;
    final hasMap = widget.assetLatitude != null && widget.assetLongitude != null;
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: Text(
          widget.unit.name,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              // CustomScrollView ليمكن تثبيت شريط التبويبات: البطاقة
              // العلوية (الخريطة والحالة والإحصاءات) تختفي عند النزول
              // ويبقى شريط "الإيجار / الحركة المالية / ..." ثابتًا.
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                    decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                    child: Column(
                      children: [
                        if (hasMap)
                          _LeaseMapHeader(
                            latitude: widget.assetLatitude!,
                            longitude: widget.assetLongitude!,
                            contract: _contract,
                            onManage: _contract == null ? null : _openTenantForm,
                          ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            14,
                            hasMap ? 0 : 14,
                            14,
                            10,
                          ),
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: (leased
                                          ? (_hasOverdue
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFF10B981))
                                          : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  leased
                                      ? (_hasOverdue ? 'متأخرة' : 'مؤجرة')
                                      : 'شاغرة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: leased
                                        ? (_hasOverdue
                                              ? const Color(0xFFEF4444)
                                              : const Color(0xFF10B981))
                                        : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.unit.name,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      (widget.assetLocation ?? '').isNotEmpty
                                          ? widget.assetLocation!
                                          : '${widget.unit.type} · رقم ${widget.unit.unitNumber.isEmpty ? '—' : widget.unit.unitNumber}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: _AssetHighlightBarRow(
                            accentColor: _kPropertyColor,
                            tiles: [
                              if (_unitTypeIsResidential(widget.unit.type))
                                _AssetHighlightTile(
                                  Icons.bathtub_outlined,
                                  '${widget.unit.bathrooms}',
                                  'حمامات',
                                ),
                              if (_unitTypeHasRooms(widget.unit.type))
                                _AssetHighlightTile(
                                  Icons.bed_outlined,
                                  '${widget.unit.rooms}',
                                  'غرف',
                                ),
                              _AssetHighlightTile(
                                Icons.straighten_rounded,
                                widget.unit.area.isEmpty ? '—' : widget.unit.area,
                                'م²',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                    ),
                  ),
                  // شريط التبويبات يرث اتجاهه من الشاشة، وهذه الشاشة بلا
                  // غلاف rtl، فكانت التبويبات تُرتَّب من اليسار: "الإيجار"
                  // أولًا على اليسار و"الملاحظات" على اليمين. تثبيت rtl هنا
                  // يجعلها تبدأ بـ"الإيجار" من اليمين كبقية شاشات التفاصيل.
                  MeasuredPinnedHeader(
                    background: AppTheme.page,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: DetailPageTabs(
                          sections: _unitTabs,
                          selectedIndex: _selectedTab,
                          color: _kPropertyColor,
                          onSelected: (i) => setState(() => _selectedTab = i),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey('unit-tab-$_selectedTab'),
                          child: _buildTabContent(leased),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTabContent(bool leased) {
    if (_selectedTab == 1) {
      return _UnitFinancialsTab(
        transactions: _transactions,
        onAdd: (kind) => _openTransactionForm(kind: kind),
        onEdit: (t) => _openTransactionForm(kind: t.kind, existing: t),
        onDelete: _deleteTransaction,
      );
    }
    if (_selectedTab != 0) {
      const messages = {
        2: 'لا توجد طلبات صيانة مسجّلة لهذه الوحدة بعد.',
        3: 'لا توجد متابعات مسجّلة لهذه الوحدة بعد.',
        4: 'لا توجد ملاحظات مسجّلة لهذه الوحدة بعد.',
      };
      return _DetailHintCard(message: messages[_selectedTab] ?? '');
    }

    if (!leased) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _openTenantForm,
            icon: const Icon(Icons.assignment_add),
            label: const Text('طلب عقد إيجار'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _shareAdRequest,
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('اطلب إعلانًا عقاريًا'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: const [
                          Text(
                            'لا يوجد مستأجر بعد',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'أضف مستأجرًا لتظهر بيانات العقد والدفعات هنا.',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _placeholderRow(Icons.tag_rounded, 'غير محددة بعد'),
                const SizedBox(height: 8),
                _placeholderRow(
                  Icons.calendar_today_rounded,
                  'من غير محدد إلى غير محدد',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _totalsColumn('الإجمالي', 0)),
                    Expanded(child: _totalsColumn('إجمالي المسدد', 0)),
                    Expanded(child: _totalsColumn('المتبقي', 0)),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPropertyColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _openTenantForm,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('إضافة مستأجر'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _addPastPaymentsAndExpenses,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('أضف دفعات ومصاريف سابقة'),
          ),
        ],
      );
    }

    final contract = _contract!;
    final overdue = _mostOverduePayment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overdue != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'الدفعة متأخرة منذ ${DateTime.now().difference(overdue.dueDate!).inDays} يوم',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(overdue.amountDue - overdue.amountPaid).toStringAsFixed(2)} ريال',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
                IconButton(
                  onPressed: () => _editOrDeleteOverduePayment(overdue),
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF991B1B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    color: _kPropertyColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      contract.tenantName ?? '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openTenantForm,
                    child: const Text('تعديل'),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFF1F5F9)),
              _kvRow('رقم العقد', _contractNumber(contract)),
              _kvRow('دورية السداد', _cycleDetailLabel(contract)),
              _kvRow(
                'الإيجار السنوي',
                '${contract.annualRent.toStringAsFixed(2)} ريال',
              ),
              _kvRow(
                'الفترة',
                '${_fmtShortDate(contract.startDate)} - ${_fmtShortDate(contract.endDate)}',
              ),
              if ((contract.tenantPhone ?? '').isNotEmpty) ...[
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(
                        'اسم المستأجر: ${contract.tenantName ?? '—'}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          _launchPhone(contract.tenantPhone!, whatsapp: false),
                      icon: const Icon(Icons.call_outlined, color: _kPropertyColor),
                    ),
                    IconButton(
                      onPressed: () =>
                          _launchPhone(contract.tenantPhone!, whatsapp: true),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kvRow('إجمالي المستحق', _totalDue.toStringAsFixed(2)),
              _kvRow('إجمالي المسدد', _totalPaid.toStringAsFixed(2)),
              _kvRow('المتبقي', _totalRemaining.toStringAsFixed(2)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPropertyColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _openPaymentForm,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تسجيل سداد'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareFinancialClaim,
                      icon: const Icon(Icons.request_page_outlined),
                      label: const Text('مطالبة مالية'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _payments.isEmpty ? null : _shareReceiptVoucher,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('سند قبض'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'سجل الدفعات',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final p in _payments) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: InkWell(
                onTap: () => _editOrDeleteOverduePayment(p),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p.dueDate == null
                                ? 'بدون تاريخ استحقاق'
                                : 'استحقاق ${_fmtShortDate(p.dueDate)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'مستحق ${p.amountDue.toStringAsFixed(2)} — مسدد ${p.amountPaid.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _paymentStatusChip(p.status),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  String _fmtShortDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _placeholderRow(IconData icon, String label) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Text(
          label,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _totalsColumn(String label, double value) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _paymentStatusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case PropertyUnitPaymentRecord.statusPaid:
        color = const Color(0xFF10B981);
        label = 'مسدد';
        break;
      case PropertyUnitPaymentRecord.statusPartial:
        color = const Color(0xFFF59E0B);
        label = 'جزئي';
        break;
      case PropertyUnitPaymentRecord.statusLate:
        color = const Color(0xFFEF4444);
        label = 'متأخر';
        break;
      default:
        color = const Color(0xFF64748B);
        label = 'قيد الانتظار';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

// ============================================================
// شاشة إنشاء "عقد متعدد الوحدات" — تختار عدة وحدات شاغرة وتُنشئ عقدًا
// مستقلاً لكل وحدة (لتبقى الدفعات منفصلة لكل وحدة) بنفس المستأجر ونفس
// group_key، مع توزيع الإيجار السنوي بالتساوي على الوحدات المختارة.
// ============================================================
class _MultiUnitContractFormScreen extends StatefulWidget {
  const _MultiUnitContractFormScreen({
    required this.assetId,
    required this.vacantUnits,
    required this.repository,
  });

  final String assetId;
  final List<_PropertyUnit> vacantUnits;
  final ProjectAssetsRepository repository;

  @override
  State<_MultiUnitContractFormScreen> createState() =>
      _MultiUnitContractFormScreenState();
}

class _MultiUnitContractFormScreenState
    extends State<_MultiUnitContractFormScreen> {
  final _tenantCtrl = TextEditingController();
  final _rentCtrl = TextEditingController();
  final Set<String> _selectedUnitKeys = {};
  String _cycle = 'شهري';
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void dispose() {
    _tenantCtrl.dispose();
    _rentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_tenantCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل اسم المستأجر')));
      return;
    }
    if (_selectedUnitKeys.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر وحدتين على الأقل')),
      );
      return;
    }
    final totalRent = double.tryParse(_rentCtrl.text.trim()) ?? 0;
    final perUnitRent = totalRent / _selectedUnitKeys.length;
    final groupKey = 'grp_${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _saving = true);
    try {
      for (final unit in widget.vacantUnits) {
        if (!_selectedUnitKeys.contains(unit.unitKey)) continue;
        await widget.repository.upsertUnitContract(
          PropertyUnitContractRecord(
            assetId: widget.assetId,
            unitKey: unit.unitKey,
            unitName: unit.name,
            tenantName: _tenantCtrl.text.trim(),
            leaseType: PropertyUnitContractRecord.leaseTypeMultiUnit,
            annualRent: perUnitRent,
            paymentCycle: _cycle,
            startDate: _start,
            endDate: _end,
            status: PropertyUnitContractRecord.statusActive,
            groupKey: groupKey,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء العقد المتعدد')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'عقد متعدد الوحدات',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _propertyFieldLabel('اختر الوحدات المشمولة بالعقد'),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: widget.vacantUnits.map((unit) {
                final selected = _selectedUnitKeys.contains(unit.unitKey);
                return FilterChip(
                  label: Text(unit.name),
                  selected: selected,
                  selectedColor: _kPropertyColor.withValues(alpha: 0.16),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedUnitKeys.add(unit.unitKey);
                    } else {
                      _selectedUnitKeys.remove(unit.unitKey);
                    }
                  }),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),
            _propertyFieldLabel('اسم المستأجر'),
            const SizedBox(height: 6),
            TextField(
              controller: _tenantCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('اسم المستأجر'),
            ),
            const SizedBox(height: 12),
            _propertyFieldLabel('إجمالي الإيجار السنوي (يُوزَّع بالتساوي)'),
            const SizedBox(height: 6),
            TextField(
              controller: _rentCtrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: _propertyInputDecoration('المبلغ الإجمالي'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cycle,
              decoration: _propertyInputDecoration('دورية السداد'),
              items: const ['شهري', 'ربع سنوي', 'نصف سنوي', 'سنوي']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _cycle = v ?? _cycle),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _start ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2060),
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
                    child: Text(
                      _start == null
                          ? 'تاريخ البداية'
                          : '${_start!.year}/${_start!.month}/${_start!.day}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _end ?? _start ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2060),
                      );
                      if (picked != null) setState(() => _end = picked);
                    },
                    child: Text(
                      _end == null
                          ? 'تاريخ الانتهاء'
                          : '${_end!.year}/${_end!.month}/${_end!.day}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPropertyColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'إنشاء العقد',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// "إضافة نشاط تجاري" الجديدة — نفس القالب البصري، بحقول مبنية على
// المتطلبات المنطقية لأي نشاط تجاري (رخصة، نوع نشاط، فريق عمل).
// ============================================================

const Color _kActivityColor = Color(0xFFF97316);
const Color _kEquipmentColor = Color(0xFF7C3AED);

const List<String> _activityTypeOptions = [
  'متجر',
  'مطعم / مقهى',
  'خدمات',
  'مكتب',
  'نشاط إلكتروني',
  'أخرى',
];

class _ActivityDraft {
  const _ActivityDraft({
    required this.name,
    required this.activityType,
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.address,
    required this.manager,
    required this.capital,
    required this.notes,
    required this.employees,
  });

  final String name;
  final String activityType;
  final String licenseNumber;
  final String licenseExpiry;
  final String address;
  final String manager;
  final String capital;
  final String notes;
  final List<Map<String, String>> employees;
}

class _AddBusinessActivityScreen extends StatefulWidget {
  const _AddBusinessActivityScreen();

  @override
  State<_AddBusinessActivityScreen> createState() =>
      _AddBusinessActivityScreenState();
}

class _AddBusinessActivityScreenState
    extends State<_AddBusinessActivityScreen> {
  final _nameCtrl = TextEditingController();
  final _licenseNumberCtrl = TextEditingController();
  final _licenseExpiryCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();
  final _capitalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _activityType = _activityTypeOptions.first;
  final List<_EmployeeFormData> _employees = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _licenseNumberCtrl.dispose();
    _licenseExpiryCtrl.dispose();
    _addressCtrl.dispose();
    _managerCtrl.dispose();
    _capitalCtrl.dispose();
    _notesCtrl.dispose();
    for (final e in _employees) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLicenseExpiry() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2060),
    );
    if (date != null) {
      setState(
        () => _licenseExpiryCtrl.text = '${date.day}/${date.month}/${date.year}',
      );
    }
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل الاسم التجاري')));
      return;
    }
    final draft = _ActivityDraft(
      name: _nameCtrl.text.trim(),
      activityType: _activityType,
      licenseNumber: _licenseNumberCtrl.text.trim(),
      licenseExpiry: _licenseExpiryCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      manager: _managerCtrl.text.trim(),
      capital: _capitalCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      employees: _employees
          .where((e) => e.nameCtrl.text.trim().isNotEmpty)
          .map(
            (e) => {
              'الاسم': e.nameCtrl.text.trim(),
              'الوظيفة': e.roleCtrl.text.trim(),
            },
          )
          .toList(),
    );
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'إضافة نشاط تجاري',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _propertyFieldLabel('الاسم التجاري'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('نوع النشاط'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _activityType,
              decoration: _propertyInputDecoration(''),
              items: _activityTypeOptions
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(growable: false),
              onChanged: (v) {
                if (v != null) setState(() => _activityType = v);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('رقم الرخصة التجارية'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _licenseNumberCtrl,
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration(''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('تاريخ انتهاء الرخصة'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _licenseExpiryCtrl,
                        readOnly: true,
                        onTap: _pickLicenseExpiry,
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration(
                          'اختر التاريخ',
                        ).copyWith(suffixIcon: const Icon(Icons.event_rounded)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('الموقع / العنوان'),
            const SizedBox(height: 6),
            TextField(
              controller: _addressCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(
                '',
              ).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('المدير المسؤول'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _managerCtrl,
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration(''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('رأس المال / الإيراد المتوقع'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _capitalCtrl,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        decoration: _propertyInputDecoration(''),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                const Text(
                  'فريق العمل',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _employees.add(_EmployeeFormData())),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('إضافة موظف'),
                  style: TextButton.styleFrom(foregroundColor: _kActivityColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _employees.length; i++) ...[
              _EmployeeFormRow(
                data: _employees[i],
                accentColor: _kActivityColor,
                onDelete: () => setState(() => _employees.removeAt(i)),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            _propertyFieldLabel('ملاحظات'),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              textAlign: TextAlign.right,
              maxLines: 3,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kActivityColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'إضافة النشاط',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeFormData {
  final nameCtrl = TextEditingController();
  final roleCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    roleCtrl.dispose();
  }
}

class _EmployeeFormRow extends StatelessWidget {
  const _EmployeeFormRow({
    required this.data,
    required this.accentColor,
    required this.onDelete,
  });

  final _EmployeeFormData data;
  final Color accentColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFB42318),
            ),
          ),
          Expanded(
            child: TextField(
              controller: data.roleCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('الوظيفة'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: data.nameCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration('اسم الموظف'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// "إضافة معدة" الجديدة — نفس القالب البصري، بحقول تقنية مبنية على
// المتطلبات المنطقية لتتبع أي معدة (رقم تسلسلي، ضمان، مورد، حالة).
// ============================================================

const List<String> _equipmentConditionOptions = ['تعمل', 'تحت الصيانة', 'متوقفة'];

class _EquipmentDraft {
  const _EquipmentDraft({
    required this.name,
    required this.equipmentType,
    required this.serialNumber,
    required this.purchaseDate,
    required this.warrantyExpiry,
    required this.supplier,
    required this.assignedLocation,
    required this.condition,
    required this.value,
    required this.notes,
  });

  final String name;
  final String equipmentType;
  final String serialNumber;
  final String purchaseDate;
  final String warrantyExpiry;
  final String supplier;
  final String assignedLocation;
  final String condition;
  final String value;
  final String notes;
}

class _AddEquipmentScreen extends StatefulWidget {
  const _AddEquipmentScreen();

  @override
  State<_AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<_AddEquipmentScreen> {
  final _nameCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _purchaseDateCtrl = TextEditingController();
  final _warrantyExpiryCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _condition = _equipmentConditionOptions.first;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _typeCtrl.dispose();
    _serialCtrl.dispose();
    _purchaseDateCtrl.dispose();
    _warrantyExpiryCtrl.dispose();
    _supplierCtrl.dispose();
    _locationCtrl.dispose();
    _valueCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2060),
    );
    if (date != null) {
      setState(() => controller.text = '${date.day}/${date.month}/${date.year}');
    }
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل اسم المعدة')));
      return;
    }
    final draft = _EquipmentDraft(
      name: _nameCtrl.text.trim(),
      equipmentType: _typeCtrl.text.trim(),
      serialNumber: _serialCtrl.text.trim(),
      purchaseDate: _purchaseDateCtrl.text.trim(),
      warrantyExpiry: _warrantyExpiryCtrl.text.trim(),
      supplier: _supplierCtrl.text.trim(),
      assignedLocation: _locationCtrl.text.trim(),
      condition: _condition,
      value: _valueCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'إضافة معدة',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _propertyFieldLabel('اسم المعدة'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('نوع المعدة'),
            const SizedBox(height: 6),
            TextField(
              controller: _typeCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(
                'مثال: مولد كهرباء، مكيف، جهاز طباعة',
              ),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('الرقم التسلسلي'),
            const SizedBox(height: 6),
            TextField(
              controller: _serialCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('تاريخ الشراء'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _purchaseDateCtrl,
                        readOnly: true,
                        onTap: () => _pickDate(_purchaseDateCtrl),
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration(
                          'اختر التاريخ',
                        ).copyWith(suffixIcon: const Icon(Icons.event_rounded)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _propertyFieldLabel('تاريخ انتهاء الضمان'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _warrantyExpiryCtrl,
                        readOnly: true,
                        onTap: () => _pickDate(_warrantyExpiryCtrl),
                        textAlign: TextAlign.right,
                        decoration: _propertyInputDecoration(
                          'اختر التاريخ',
                        ).copyWith(suffixIcon: const Icon(Icons.event_rounded)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('المورد / الجهة الموردة'),
            const SizedBox(height: 6),
            TextField(
              controller: _supplierCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('الموقع / الجهة المخصصة لها'),
            const SizedBox(height: 6),
            TextField(
              controller: _locationCtrl,
              textAlign: TextAlign.right,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('الحالة'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              decoration: _propertyInputDecoration(''),
              items: _equipmentConditionOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(growable: false),
              onChanged: (v) {
                if (v != null) setState(() => _condition = v);
              },
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('القيمة الشرائية'),
            const SizedBox(height: 6),
            TextField(
              controller: _valueCtrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 14),
            _propertyFieldLabel('ملاحظات'),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              textAlign: TextAlign.right,
              maxLines: 3,
              decoration: _propertyInputDecoration(''),
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kEquipmentColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                )              ),
              child: const Text(
                'إضافة المعدة',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// شاشة "إضافة الوحدات والمرافق العامة" — حسب ملف "ادخال الوحدات":
// القائمة على اليمين ثابتة (أنواع الوحدات ثم المرافق العامة)، والضغط على
// أي بند يفتح نموذجه في اللوحة على اليسار. لكل نوع زر حفظ خاص به، ومسودة
// تُحفظ تلقائيًا كل دقيقتين حتى لا تضيع الإدخالات الكثيرة.
// ============================================================

const List<String> _kFacilityLabels = [
  'مواقف سيارات عامة',
  'المصعد',
  'الدرج',
  'المداخل / اللوبي',
  'الممرات',
  'السطح',
  'الحوش / الساحة',
  'غرفة الحارس',
  'غرفة الكهرباء',
  'غرفة الاتصالات',
  'غرفة المياه والمضخات',
  'خزانات المياه',
  'غرفة النفايات',
  'النادي الرياضي',
  'المسبح',
  'غرفة الخدمات',
  'أخرى',
];

/// حقول نموذج نوع واحد (وحدة أو مرفق) — تبقى حيّة عند التنقل بين الأنواع.
class _UnitEntryForm {
  final count = TextEditingController();
  final name = TextEditingController();
  final firstNumber = TextEditingController(text: '1');
  final area = TextEditingController();
  final rooms = TextEditingController();
  final halls = TextEditingController();
  final balconies = TextEditingController();
  final bathrooms = TextEditingController();
  final parking = TextEditingController();
  final notes = TextEditingController();
  bool quickAdd = true;

  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  List<TextEditingController> get controllers => [
    count,
    name,
    firstNumber,
    area,
    rooms,
    halls,
    balconies,
    bathrooms,
    parking,
    notes,
  ];

  Map<String, dynamic> toDraft() => {
    'count': count.text,
    'name': name.text,
    'firstNumber': firstNumber.text,
    'area': area.text,
    'rooms': rooms.text,
    'halls': halls.text,
    'balconies': balconies.text,
    'bathrooms': bathrooms.text,
    'parking': parking.text,
    'notes': notes.text,
    'quickAdd': quickAdd,
  };

  void restore(Map<String, dynamic> draft) {
    count.text = (draft['count'] ?? '').toString();
    name.text = (draft['name'] ?? '').toString();
    firstNumber.text = (draft['firstNumber'] ?? '1').toString();
    area.text = (draft['area'] ?? '').toString();
    rooms.text = (draft['rooms'] ?? '').toString();
    halls.text = (draft['halls'] ?? '').toString();
    balconies.text = (draft['balconies'] ?? '').toString();
    bathrooms.text = (draft['bathrooms'] ?? '').toString();
    parking.text = (draft['parking'] ?? '').toString();
    notes.text = (draft['notes'] ?? '').toString();
    quickAdd = draft['quickAdd'] != false;
  }
}

class _UnitsEntryScreen extends StatefulWidget {
  const _UnitsEntryScreen({
    required this.assetKey,
    required this.existingUnits,
    required this.existingAnnexes,
    required this.onCommit,
  });

  /// معرّف ثابت للعقار تُخزَّن به المسودة محليًا.
  final String assetKey;
  final List<_PropertyUnit> existingUnits;
  final Map<String, int> existingAnnexes;

  /// يُستدعى عند كل حفظ نوع: وحدات جديدة تُضاف، ومرافق تُحدَّث أعدادها،
  /// وسطر سجل يوثّق ما حدث (يشمل ملاحظات المرافق).
  final void Function(
    List<_PropertyUnit> newUnits,
    Map<String, int> annexes,
    String logLine,
  )
  onCommit;

  @override
  State<_UnitsEntryScreen> createState() => _UnitsEntryScreenState();
}

class _UnitsEntryScreenState extends State<_UnitsEntryScreen> {
  final Map<String, _UnitEntryForm> _forms = {};
  String _selected = _kUnitApartment;
  Timer? _autoSaveTimer;
  DateTime? _lastAutoSave;
  final Set<String> _savedTypes = {};

  static const _draftPrefix = 'units_entry_draft_v1_';

  bool get _isFacility => _kFacilityLabels.contains(_selected);

  _UnitEntryForm get _form => _forms.putIfAbsent(_selected, _UnitEntryForm.new);

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    // حفظ تلقائي كل دقيقتين — مع عدد كبير من الوحدات لا يضيع المدخل
    // شيئًا لو خرج أو انقطع التطبيق.
    _autoSaveTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _saveDraft(),
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // حفظ أخير عند الخروج بدل انتظار الدورة القادمة.
    _saveDraft();
    for (final form in _forms.values) {
      form.dispose();
    }
    super.dispose();
  }

  Future<void> _saveDraft() async {
    try {
      // تُلتقط القيم قبل أي await: عند الاستدعاء من dispose تكون الحقول
      // على وشك التخلص منها، فلا يصح قراءتها بعد الانتظار.
      final data = {
        for (final entry in _forms.entries) entry.key: entry.value.toDraft(),
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_draftPrefix${widget.assetKey}',
        jsonEncode(data),
      );
      if (!mounted) return;
      setState(() => _lastAutoSave = DateTime.now());
    } catch (_) {
      // فشل الحفظ المحلي لا يوقف الإدخال.
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_draftPrefix${widget.assetKey}');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          _forms
              .putIfAbsent(entry.key.toString(), _UnitEntryForm.new)
              .restore(Map<String, dynamic>.from(entry.value as Map));
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // مسودة تالفة تُتجاهل.
    }
  }

  Future<void> _clearDraftFor(String type) async {
    // بعد حفظ النوع في العقار تُصفَّر خاناته حتى لا يُضاف مرتين بالخطأ.
    _forms[type]?.dispose();
    _forms.remove(type);
    await _saveDraft();
  }

  int _intOf(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  /// حفظ النوع المفتوح: وحدات تُولَّد وتُضاف للعقار، ومرفق يُحدَّث عدده.
  void _commitSelected() {
    final form = _form;
    final type = _selected;
    final count = _intOf(form.count);
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل العدد أولًا')),
      );
      return;
    }

    if (_isFacility) {
      final note = form.notes.text.trim();
      widget.onCommit(
        const [],
        {type: count},
        'تمت إضافة مرفق: $type (العدد $count)'
        '${note.isEmpty ? '' : ' — $note'}',
      );
    } else {
      final first = int.tryParse(form.firstNumber.text.trim()) ?? 1;
      final baseName = form.name.text.trim().isEmpty
          ? type
          : form.name.text.trim();
      final showFull = type == _kUnitApartment || type == _kUnitFullFloor;
      final units = <_PropertyUnit>[
        for (var i = 0; i < count; i++)
          _PropertyUnit(
            type: type,
            name: count == 1 ? baseName : '$baseName ${first + i}',
            unitNumber: '${first + i}',
            area: form.area.text.trim(),
            rooms: _unitTypeRoomsFor(type, _intOf(form.rooms)),
            halls: showFull ? _intOf(form.halls) : 0,
            balconies: showFull ? _intOf(form.balconies) : 0,
            bathrooms: _unitTypeIsResidential(type)
                ? _intOf(form.bathrooms)
                : 0,
            parkingCount: _unitTypeIsResidential(type)
                ? _intOf(form.parking)
                : 0,
            hasParking:
                _unitTypeIsResidential(type) && _intOf(form.parking) > 0,
            notes: form.notes.text.trim(),
          ),
      ];
      widget.onCommit(
        units,
        const {},
        'تمت إضافة $count × $type من نموذج إدخال الوحدات',
      );
    }
    setState(() {
      _savedTypes.add(type);
    });
    _clearDraftFor(type);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ $type في العقار')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text(
            'إضافة الوحدات والمرافق العامة',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
          ),
          actions: [
            // زر حفظ المسودة يدويًا — نفس ما يفعله المؤقّت كل دقيقتين.
            IconButton(
              key: const ValueKey('units-entry-save-draft'),
              tooltip: 'حفظ المسودة الآن',
              onPressed: _saveDraft,
              icon: const Icon(Icons.save_outlined, size: 20),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_lastAutoSave != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFE7F3F0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                child: Text(
                  'آخر حفظ تلقائي للمسودة: '
                  '${_lastAutoSave!.hour.toString().padLeft(2, '0')}:${_lastAutoSave!.minute.toString().padLeft(2, '0')}'
                  ' — يتكرر كل دقيقتين',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF087F6A),
                  ),
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // القائمة الثابتة على اليمين: الوحدات ثم المرافق.
                  SizedBox(width: 128, child: _buildTypesList()),
                  const VerticalDivider(width: 1, color: Color(0xFFE3E9EB)),
                  // اللوحة على اليسار: نموذج النوع المفتوح.
                  Expanded(child: _buildFormPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypesList() {
    Widget entry(String label, {required bool facility}) {
      final selected = _selected == label;
      final existingCount = facility
          ? (widget.existingAnnexes[label] ?? 0)
          : widget.existingUnits.where((u) => u.type == label).length;
      return InkWell(
        key: ValueKey('units-entry-type-$label'),
        onTap: () => setState(() => _selected = label),
        child: Container(
          color: selected
              ? const Color(0xFF047857).withValues(alpha: 0.08)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              Icon(
                facility
                    ? Icons.apartment_outlined
                    : _unitTypeIcon(label),
                size: 15,
                color: selected
                    ? const Color(0xFF047857)
                    : AppTheme.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected
                        ? const Color(0xFF047857)
                        : AppTheme.title,
                  ),
                ),
              ),
              if (existingCount > 0 || _savedTypes.contains(label))
                Text(
                  '$existingCount',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF087F6A),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: AppTheme.muted,
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        header('الوحدات'),
        for (final type in const [
          _kUnitApartment,
          _kUnitStudio,
          _kUnitFullFloor,
          _kUnitOffice,
          _kUnitShop,
          _kUnitShowroom,
          _kUnitMezzanine,
          _kUnitWarehouse,
          _kUnitParking,
        ])
          entry(type, facility: false),
        const Divider(height: 16),
        header('المرافق العامة'),
        for (final facility in _kFacilityLabels)
          entry(facility, facility: true),
      ],
    );
  }

  Widget _buildFormPanel() {
    final form = _form;
    final type = _selected;
    final facility = _isFacility;
    // موقف السيارات (كوحدة) والمرافق: العدد والملاحظات فقط.
    final countOnly = facility || type == _kUnitParking;
    final hasRooms = _unitTypeHasRooms(type);
    final residential = _unitTypeIsResidential(type);
    final showFull = type == _kUnitApartment || type == _kUnitFullFloor;

    Widget field(
      String label,
      TextEditingController controller, {
      bool number = true,
      int maxLines = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          textAlign: TextAlign.right,
          decoration: _propertyInputDecorationShared(label),
        ),
      );
    }

    final first = int.tryParse(form.firstNumber.text.trim()) ?? 1;
    final count = _intOf(form.count);

    return ListView(
      key: ValueKey('units-entry-form-$type'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        Row(
          children: [
            Icon(
              facility ? Icons.apartment_outlined : _unitTypeIcon(type),
              size: 18,
              color: const Color(0xFF047857),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                facility ? 'مرفق: $type' : 'إعدادات $type',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        field(facility ? 'العدد' : 'عدد ($type)', form.count),
        if (!countOnly) ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'تفعيل الإضافة السريعة',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'سنعبّئ الوحدات تلقائيًا حسب الإعدادات التالية، والتفاصيل تُطبَّق على كل الوحدات. بلا تفعيل يكون الإدخال يدويًا وحدة وحدة.',
              style: TextStyle(fontSize: 10.5, height: 1.4),
            ),
            value: form.quickAdd,
            onChanged: (value) => setState(() => form.quickAdd = value),
          ),
          const SizedBox(height: 6),
          field('اسم $type', form.name, number: false),
          field('رقم أول $type', form.firstNumber),
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'الترقيم من $first إلى ${first + count - 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          field('مساحة كل وحدة', form.area),
          if (hasRooms) field('عدد الغرف', form.rooms),
          if (showFull) field('عدد الصالات', form.halls),
          if (showFull) field('عدد البلكونات', form.balconies),
          if (residential) field('عدد الحمامات', form.bathrooms),
          if (residential)
            field('عدد مواقف السيارات الخاصة', form.parking),
        ],
        field('الملاحظات', form.notes, number: false, maxLines: 3),
        const SizedBox(height: 6),
        FilledButton.icon(
          key: ValueKey('units-entry-commit-$type'),
          onPressed: _commitSelected,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(facility ? 'إضافة المرفق' : 'إضافة $type'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF047857),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
          ),
        ),
      ],
    );
  }
}

/// زخرفة حقول شاشة إدخال الوحدات — حدود ظاهرة على نمط حقول العقارات.
InputDecoration _propertyInputDecorationShared(String label) {
  OutlineInputBorder border([Color? color]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.rField),
    borderSide: color == null
        ? BorderSide.none
        : BorderSide(color: color, width: 1.4),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppTheme.field,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(const Color(0xFF047857)),
  );
}
