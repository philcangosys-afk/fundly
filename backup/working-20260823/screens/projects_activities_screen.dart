import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_reminders_store.dart';
import '../data/project_assets_repository.dart';
import 'document_templates_screen.dart';
import 'smart_calendar_screen.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/module_shared_widgets.dart';

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
  const ProjectsActivitiesScreen({super.key});

  @override
  State<ProjectsActivitiesScreen> createState() =>
      _ProjectsActivitiesScreenState();
}

class _ProjectsActivitiesScreenState extends State<ProjectsActivitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ProjectAssetsRepository _repository = SupabaseProjectAssetsRepository();
  String _selectedFilter = 'all';
  String _selectedSort = 'الأحدث أولاً';
  bool _isLoadingRemote = true;

  final List<_TopFilter> _filters = const [
    _TopFilter('all', 'الكل', Color(0xFF0B3A78)),
    _TopFilter('real_estate', 'العقارات', Color(0xFF0F6AA8)),
    _TopFilter('activity', 'الأنشطة التجارية', Color(0xFF10B981)),
    _TopFilter('equipment', 'المعدات', Color(0xFFF59E0B)),
    _TopFilter('maintenance', 'صيانة', Color(0xFFEA580C)),
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
      amountLabel: record.amountLabel ?? '0 درهم',
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
      logs: const [],
      createdAt: DateTime.now(),
      description: record.description,
      annexes: record.annexes,
      iconColor: record.iconColor == null ? null : Color(record.iconColor!),
    );
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
    );
  }

  String _toDatabaseCategory(String uiCategory) {
    if (uiCategory == 'activity' || uiCategory == 'equipment') {
      return 'business';
    }
    if (uiCategory == 'other') return 'project';
    return 'real_estate';
  }

  String _fromDatabaseCategory(String dbCategory) {
    if (dbCategory == 'business') return 'activity';
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

  bool _matchesFilter(_AssetItem item, String filter) {
    if (filter == 'all') return true;
    if (filter == 'maintenance') {
      return item.tasks.isNotEmpty ||
          item.needsAttention ||
          item.status.contains('صيانة');
    }
    return item.category == filter;
  }

  List<(String, String, Color)> _filterLabels() {
    return _filters
        .map((filter) {
          final count = _countByCategory(filter.key);
          final label = filter.key == 'all'
              ? 'الكل'
              : '${filter.label} ($count)';
          return (label, filter.key, filter.color);
        })
        .toList(growable: false);
  }

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
      return typeMatches && queryMatches;
    }).toList();

    if (_selectedSort == 'تحتاج متابعة') {
      filtered.sort(
        (a, b) =>
            (b.needsAttention ? 1 : 0).compareTo(a.needsAttention ? 1 : 0),
      );
    } else if (_selectedSort == 'حسب الاسم') {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    } else {
      filtered.sort((a, b) => b.endDate.compareTo(a.endDate));
    }
    return filtered;
  }

  IconData _filterIcon(String key) {
    if (key == 'real_estate') return Icons.apartment_rounded;
    if (key == 'activity') return Icons.storefront_rounded;
    if (key == 'equipment') return Icons.precision_manufacturing_outlined;
    if (key == 'maintenance') return Icons.build_circle_outlined;
    return Icons.grid_view_rounded;
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

  void _openFilterSheet() {
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'تصفية',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCE5EF)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    textDirection: TextDirection.rtl,
                    children: _filters
                        .map((filter) {
                          final selected = _selectedFilter == filter.key;
                          return _ProjectsFilterChip(
                            title: filter.label,
                            count: _countByCategory(filter.key),
                            selected: selected,
                            onTap: () {
                              setState(() => _selectedFilter = filter.key);
                              Navigator.of(context).pop();
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'الترتيب',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  textDirection: TextDirection.rtl,
                  children: ['الأحدث أولاً', 'تحتاج متابعة', 'حسب الاسم']
                      .map((sort) {
                        final selected = _selectedSort == sort;
                        return ChoiceChip(
                          label: Text(sort),
                          selected: selected,
                          selectedColor: const Color(
                            0xFF047857,
                          ).withOpacity(0.2),
                          onSelected: (_) {
                            setState(() => _selectedSort = sort);
                            Navigator.of(context).pop();
                          },
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
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
                                  ? '0 درهم'
                                  : '${annualRentController.text.trim()} درهم',
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
      backgroundColor: const Color(0xFFF5F8FC),
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
            ManagementPinnedControls(
              height: 242,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ManagementFollowUpCenter(
                    subtitle: _selectedFilter == 'all'
                        ? 'الأهم والأقرب من جميع الأصول والأنشطة'
                        : 'متابعة ${_filters.firstWhere((item) => item.key == _selectedFilter).label}',
                    accentColor: const Color(0xFF047857),
                    onMore: _openFilterSheet,
                    metrics: [
                      ManagementMetricData(
                        label: 'دفعات تحتاج متابعة',
                        count: selectedAssets
                            .where((item) => item.paymentProgress < 0.7)
                            .length,
                        icon: Icons.payments_outlined,
                        color: const Color(0xFFB56A09),
                      ),
                      ManagementMetricData(
                        label: 'وثائق شخصية تحتاج متابعة',
                        count: selectedAssets
                            .where((item) => item.documentsProgress < 0.8)
                            .length,
                        icon: Icons.badge_outlined,
                        color: const Color(0xFF0F6AA8),
                      ),
                      ManagementMetricData(
                        label: 'عقود تحتاج متابعة',
                        count: selectedAssets
                            .where(
                              (item) =>
                                  item.contracts.isNotEmpty &&
                                  item.needsAttention,
                            )
                            .length,
                        icon: Icons.description_outlined,
                        color: const Color(0xFFC73E4D),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'الفئات',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                          onTap: () =>
                              setState(() => _selectedFilter = filter.key),
                        );
                      },
                    ),
                  ),
                ],
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
                  ManagementSortHeader(
                    value: _selectedSort,
                    options: const [
                      'الأحدث أولاً',
                      'تحتاج متابعة',
                      'حسب الاسم',
                    ],
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
                  const SizedBox(height: 10),
                  ...filtered.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ManagementCompactCard(
                        title: item.title,
                        category: item.subType,
                        date: item.endDate,
                        value: item.amountLabel,
                        status: item.isFrozen
                            ? 'مجمّد'
                            : (item.needsAttention ? 'متابعة' : item.status),
                        icon: _filterIcon(item.category),
                        accentColor: const Color(0xFF047857),
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
  }

  void _updateItem(_AssetItem updated) {
    setState(() => _item = updated);
    widget.onItemChanged?.call(updated);
  }

  void _onTopMenuAction(ThreeDotMenuAction action) {
    if (action == ThreeDotMenuAction.share) {
      Share.share(
        'تفاصيل العقار\n'
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
          title: const Text('حذف العقار'),
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
                      decoration: const InputDecoration(
                        labelText: 'اسم المشروع',
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
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
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
      await repository.upsertEntry(
        ProjectAssetEntryRecord(assetId: assetId, kind: group.kind, data: data),
      );
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
    final quickAddOptions = [
      (
        title: 'إضافة مالية',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0EA5E9),
        group: _groups.firstWhere((g) => g.kind == _entryKindExpense),
      ),
      (
        title: 'إضافة ادارية',
        icon: Icons.manage_accounts_outlined,
        color: const Color(0xFF7C3AED),
        group: _groups.firstWhere((g) => g.kind == _entryKindContract),
      ),
      (
        title: 'إضافة مستند',
        icon: Icons.description_outlined,
        color: const Color(0xFF0F766E),
        group: _groups.firstWhere((g) => g.kind == _entryKindDocument),
      ),
      (
        title: 'إضافة شخص/جهة',
        icon: Icons.person_add_alt_1_rounded,
        color: const Color(0xFF0D9488),
        group: _groups.firstWhere((g) => g.kind == _entryKindContract),
      ),
      (
        title: 'إضافة وحدة',
        icon: Icons.home_work_outlined,
        color: const Color(0xFF10B981),
        group: _groups.firstWhere((g) => g.kind == _entryKindRental),
      ),
      (
        title: 'إضافة أصل ومحتويات',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFFF59E0B),
        group: _groups.firstWhere((g) => g.kind == _entryKindMaintenance),
      ),
      (
        title: 'إضافة رابط',
        icon: Icons.link_outlined,
        color: const Color(0xFF2563EB),
        group: _groups.firstWhere((g) => g.kind == _entryKindDocument),
      ),
      (
        title: 'أخرى',
        icon: Icons.more_horiz_rounded,
        color: const Color(0xFF64748B),
        group: _groups.firstWhere((g) => g.kind == _entryKindExpense),
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
                          _openActionForm(option.group);
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

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: const Color(0xFFF5F7FA),
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
        title: const Text(
          'تفاصيل العقار',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: Color(0xFFD22E2E),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
    final statusColor = item.status == 'نشط'
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F0F172A),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
  }) : annexes = annexes ?? <String, int>{},
       maintenance = maintenance ?? <Map<String, String>>[],
       rentals = rentals ?? <Map<String, String>>[],
       expenses = expenses ?? <Map<String, String>>[],
       revenues = revenues ?? <Map<String, String>>[];

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
    );
  }
}
