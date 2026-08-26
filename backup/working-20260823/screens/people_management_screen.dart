import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_reminders_store.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/followup_center_card.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/module_shared_widgets.dart';

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

  Future<void> _loadSavedPeople() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peopleStorageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
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
      // Ignore malformed local cache and continue with seeded data.
    }
  }

  Future<void> _persistPeople() async {
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

  Future<void> _openScopeFiltersPopup({required bool isEntity}) async {
    final scopeKey = isEntity ? 'scope_entities' : 'scope_people';
    final allKey = isEntity ? 'all_entities' : 'all_people';
    final allLabel = isEntity ? 'كل الجهات' : 'كل الأفراد';
    final allColor = isEntity
        ? const Color(0xFF7C3AED)
        : const Color(0xFF0F6AA8);
    final allIcon = isEntity
        ? Icons.apartment_rounded
        : Icons.people_alt_outlined;

    final filters = _createTypeFilters(isEntity);
    final options = <({String key, String label, Color color, IconData icon})>[
      (key: allKey, label: allLabel, color: allColor, icon: allIcon),
      ...filters.map(
        (filter) => (
          key: filter.key,
          label: filter.label,
          color: filter.color,
          icon: _typeIcon(filter.key),
        ),
      ),
    ];

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'scope_filter_popup',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 80,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x30000000),
                        blurRadius: 26,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isEntity
                                      ? 'تصنيفات الجهات'
                                      : 'تصنيفات الأفراد',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'إغلاق',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: SingleChildScrollView(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 420
                                      ? 3
                                      : 2;
                                  const spacing = 8.0;
                                  final itemWidth =
                                      (constraints.maxWidth -
                                          spacing * (columns - 1)) /
                                      columns;

                                  return Wrap(
                                    spacing: spacing,
                                    runSpacing: spacing,
                                    children: options
                                        .map(
                                          (option) => SizedBox(
                                            width: itemWidth,
                                            child: _ScopeFilterRect(
                                              label: option.label,
                                              count: _countByType(option.key),
                                              icon: option.icon,
                                              color: option.color,
                                              selected:
                                                  _selectedScopeKey ==
                                                      scopeKey &&
                                                  _selectedTypeKey ==
                                                      option.key,
                                              onTap: () {
                                                setState(() {
                                                  _selectedScopeKey = scopeKey;
                                                  _selectedTypeKey = option.key;
                                                });
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              },
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  );
                                },
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
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  List<(String label, String key, Color color)> _topTypeFilters() {
    final relativeCount = _countByType('person_relative');
    final employeeCount = _countByType('person_employee');
    final clientCount = _countByType('person_client');

    return [
      ('الكل', 'all', const Color(0xFF0B3A78)),
      ('قريب ($relativeCount)', 'person_relative', const Color(0xFF0F6AA8)),
      ('موظف ($employeeCount)', 'person_employee', const Color(0xFFF59E0B)),
      ('عميل ($clientCount)', 'person_client', const Color(0xFF2563EB)),
      ('المزيد', 'more', const Color(0xFF7C3AED)),
    ];
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
      return scopeMatches && typeMatches && queryMatches;
    }).toList();

    if (_selectedSort == 'الأعلى مستحقات') {
      filtered.sort(
        (a, b) => (b.dueToYou + b.dueOnYou).compareTo(a.dueToYou + a.dueOnYou),
      );
    } else if (_selectedSort == 'الأكثر مهاماً') {
      filtered.sort((a, b) => b.openTasks.compareTo(a.openTasks));
    } else {
      filtered.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    }
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

  void _openPersonDetails(_PersonItem person) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailsScreen(
          person: person,
          onPersonUpdated: (previous, updated) {
            final index = _people.indexOf(previous);
            if (index == -1) return;
            setState(() {
              _people[index] = updated;
            });
            _persistPeople();
          },
          onPersonDeleted: (target) {
            setState(() {
              _people.remove(target);
            });
            _persistPeople();
          },
        ),
      ),
    );
  }

  void _openTypeFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final scopeOptions = [
          ('scope_all', 'الكل'),
          ('scope_people', 'الأفراد'),
          ('scope_entities', 'الجهات'),
        ];

        final typeOptions = _selectedScopeKey == 'scope_all'
            ? _allTypeFilters
            : _selectedScopeKey == 'scope_people'
            ? [
                const _TypeFilterDef(
                  'all_people',
                  'كل الأفراد',
                  Color(0xFF0F6AA8),
                ),
                ..._allTypeFilters.where((f) => f.key.startsWith('person_')),
                const _TypeFilterDef(
                  'status_near',
                  'قريب الانتهاء',
                  Color(0xFF0284C7),
                ),
                const _TypeFilterDef(
                  'status_urgent',
                  'مستعجل',
                  Color(0xFFD97706),
                ),
                const _TypeFilterDef('status_late', 'متأخر', Color(0xFFDC2626)),
              ]
            : [
                const _TypeFilterDef(
                  'all_entities',
                  'كل الجهات',
                  Color(0xFF7C3AED),
                ),
                ..._allTypeFilters.where((f) => f.key.startsWith('entity_')),
              ];

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'تصفية الأشخاص',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'النطاق',
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
                  children: scopeOptions
                      .map((scope) {
                        final selected = _selectedScopeKey == scope.$1;
                        return ChoiceChip(
                          label: Text(scope.$2),
                          selected: selected,
                          selectedColor: const Color(
                            0xFF7C3AED,
                          ).withValues(alpha: 0.2),
                          onSelected: (_) {
                            setState(() {
                              _selectedScopeKey = scope.$1;
                              if (scope.$1 == 'scope_all') {
                                _selectedTypeKey = 'all';
                              } else if (scope.$1 == 'scope_people') {
                                _selectedTypeKey = 'all_people';
                              } else {
                                _selectedTypeKey = 'all_entities';
                              }
                            });
                          },
                        );
                      })
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                const Text(
                  'الفئة',
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
                  children: typeOptions
                      .map((filter) {
                        final isSelected = _selectedTypeKey == filter.key;
                        return ChoiceChip(
                          label: Text(
                            '${filter.label} (${_countByType(filter.key)})',
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              if (_selectedScopeKey == 'scope_all') {
                                if (filter.key.startsWith('person_') ||
                                    filter.key == 'all_people' ||
                                    filter.key.startsWith('status_')) {
                                  _selectedScopeKey = 'scope_people';
                                } else if (filter.key.startsWith('entity_') ||
                                    filter.key == 'all_entities') {
                                  _selectedScopeKey = 'scope_entities';
                                }
                              }
                              _selectedTypeKey = filter.key;
                            });
                            Navigator.of(context).pop();
                          },
                          selectedColor: filter.color,
                          backgroundColor: const Color(0xFFF8FAFC),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF334155),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isSelected
                                  ? filter.color
                                  : const Color(0xFFDCE5EF),
                            ),
                          ),
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E6EA)),
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                        _inputField(controllers['email']!, 'البريد الإلكتروني'),
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
                        _inputField(controllers['notes']!, 'ملاحظات'),
                        const SizedBox(height: 9),
                        _inputField(controllers['extra']!, 'معلومات إضافية'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final name = controllers['name']!.text.trim();
                      if (name.isEmpty) return;
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
                            extraNote: controllers['notes']!.text.trim().isEmpty
                                ? 'بانتظار استكمال البيانات'
                                : controllers['notes']!.text.trim(),
                            typeKey: type.key,
                            categoryName: type.label,
                            dueToYou: 0,
                            dueOnYou: 0,
                            openTasks: 0,
                            documentsCount: 0,
                            lastUpdate: 'اليوم',
                            createdAt: 'اليوم',
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
                      });
                      _persistPeople();
                      Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isEntity ? 'حفظ الجهة' : 'حفظ الشخص'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4A73),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      if (owner.isEmpty) return;
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
                              lastUpdate: 'اليوم',
                              createdAt: 'اليوم',
                              sharedCommitments: const [],
                              documents: [description],
                              details: {
                                'تاريخ الانتهاء': dateController.text.trim(),
                              },
                            ),
                          );
                        }
                        _selectedTypeKey = 'all';
                      });
                      _persistPeople();
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
      backgroundColor: const Color(0xFFF5F8FC),
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
              title: 'إدارة الأشخاص',
              subtitle: 'تنظيم العلاقات والالتزامات وبيانات التواصل',
              icon: Icons.person_search_rounded,
              colors: const [Color(0xFF6D28D9), Color(0xFF7C3AED)],
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
            ManagementPinnedControls(
              height: 278,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ManagementFollowUpCenter(
                    subtitle: _selectedTypeKey == 'all'
                        ? 'الأهم والأقرب من جميع الأشخاص والجهات'
                        : 'متابعة ${_selectedFilterLabel()}',
                    accentColor: const Color(0xFF047857),
                    onMore: _openTypeFilterSheet,
                    metrics: [
                      ManagementMetricData(
                        label: 'وثائق تحتاج متابعة',
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
                  const SizedBox(height: 8),
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
                          }),
                        ),
                        const SizedBox(width: 8),
                        _SplitScopeCategoryTab(
                          label: 'الأفراد',
                          count: _countByScope('scope_people'),
                          icon: Icons.person_outline_rounded,
                          color: const Color(0xFF0F6AA8),
                          selected: _selectedScopeKey == 'scope_people',
                          onLabelTap: () => setState(() {
                            _selectedScopeKey = 'scope_people';
                            _selectedTypeKey = 'all_people';
                          }),
                          onArrowTap: () =>
                              _openScopeFiltersPopup(isEntity: false),
                        ),
                        const SizedBox(width: 8),
                        _SplitScopeCategoryTab(
                          label: 'الجهات',
                          count: _countByScope('scope_entities'),
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF7C3AED),
                          selected: _selectedScopeKey == 'scope_entities',
                          onLabelTap: () => setState(() {
                            _selectedScopeKey = 'scope_entities';
                            _selectedTypeKey = 'all_entities';
                          }),
                          onArrowTap: () =>
                              _openScopeFiltersPopup(isEntity: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ManagementSortHeader(
                    value: _selectedSort,
                    options: const [
                      'الأحدث أولاً',
                      'الأعلى مستحقات',
                      'الأكثر مهاماً',
                    ],
                    onSelected: (value) =>
                        setState(() => _selectedSort = value),
                    title: _selectedTypeKey == 'all'
                        ? 'جميع الأشخاص والجهات'
                        : _selectedFilterLabel(),
                    count: people.length,
                    accentColor: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(height: 10),
                  ...people.map(
                    (person) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ManagementCompactCard(
                        title: person.fullName,
                        category:
                            '${person.categoryName} · ${person.roleTitle}',
                        date: person.lastUpdate,
                        value: person.dueToYou > 0
                            ? 'لك ${person.dueToYou.toStringAsFixed(0)}'
                            : 'عليك ${person.dueOnYou.toStringAsFixed(0)}',
                        status: person.badge,
                        icon: _typeIcon(person.typeKey),
                        accentColor: const Color(0xFF7C3AED),
                        statusColor: person.badgeColor,
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

  final List<String> _detailTabs = const [
    'الملخص',
    'المالية',
    'المستندات',
    'التنظيم والمتابعة والبيانات',
    'كلمات السر',
    'الملاحظات',
  ];

  static const List<DetailSectionTab> _detailSections = [
    DetailSectionTab(label: 'الملخص', icon: Icons.bar_chart_rounded),
    DetailSectionTab(
      label: 'المالية',
      icon: Icons.account_balance_wallet_outlined,
    ),
    DetailSectionTab(label: 'المستندات', icon: Icons.folder_outlined),
    DetailSectionTab(label: 'التنظيم', icon: Icons.rule_folder_outlined),
    DetailSectionTab(label: 'كلمات السر', icon: Icons.password_rounded),
    DetailSectionTab(label: 'الملاحظات', icon: Icons.sticky_note_2_outlined),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                            lastUpdate: 'اليوم',
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
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الشخص'),
          content: Text('هل تريد حذف ${_person.fullName}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('حذف'),
            ),
          ],
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
      _person.copyWith(isFrozen: nowFrozen, lastUpdate: 'اليوم'),
      notice: nowFrozen ? 'تم تجميد الشخص' : 'تم إلغاء التجميد',
    );
  }

  void _togglePin() {
    final nowPinned = !_person.isPinned;
    _applyPersonUpdate(
      _person.copyWith(isPinned: nowPinned, lastUpdate: 'اليوم'),
      notice: nowPinned ? 'تم تثبيت الصفحة في الرئيسية' : 'تم إلغاء التثبيت',
    );
  }

  void _archivePerson() {
    _applyPersonUpdate(
      _person.copyWith(
        badge: 'مؤرشف',
        badgeColor: const Color(0xFF64748B),
        statusNote: 'مؤرشف',
        lastUpdate: 'اليوم',
      ),
      notice: 'تمت أرشفة الشخص',
    );
  }

  void _onTopMenuAction(ThreeDotMenuAction action) {
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                          borderRadius: BorderRadius.circular(12),
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
                            color: const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFDDE2E7)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: const Color(0xFFDDE2E7),
                                  ),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    final followUpCount = person.openTasks;
    final filteredDocuments = _filterItems(_personDocuments);
    final filteredCommitments = _filterItems(_personSharedCommitments);
    final selectedTab = _detailTabs[_selectedMainTab];
    const color = Color(0xFF0C6A8C);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AddFab(
        key: const ValueKey('add-person-detail-entry'),
        screenId: 'person_details_${person.fullName}',
        onPressed: () {
          if (person.isFrozen) {
            _notify('لا يمكن الإضافة لأن الحساب مجمّد');
            return;
          }
          _openMainEntryTypesSheet();
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
        child: ListView(
          key: const ValueKey('compact-person-details'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          children: [
            DetailScaffold(
              header: DetailPageHeader(
                title: person.fullName,
                subtitle:
                    '${person.categoryName} · ${person.roleTitle}${person.isFrozen ? ' · مجمّد' : ''}${person.isPinned ? ' · مثبّت' : ''}',
                icon: Icons.person_outline_rounded,
                color: color,
                status: person.isFrozen ? 'مجمّد' : person.badge,
                statusColor: person.isFrozen
                    ? const Color(0xFF64748B)
                    : person.badgeColor,
                metrics: [
                  DetailHeaderMetric(
                    label: 'لك',
                    value: '${person.dueToYou}',
                    caption: 'درهم',
                    icon: Icons.south_west_rounded,
                  ),
                  DetailHeaderMetric(
                    label: 'عليك',
                    value: '${person.dueOnYou}',
                    caption: 'درهم',
                    icon: Icons.north_east_rounded,
                  ),
                  DetailHeaderMetric(
                    label: 'المستندات',
                    value: '${person.documentsCount}',
                    caption: person.lastUpdate,
                    icon: Icons.folder_outlined,
                  ),
                ],
                trailing: ThreeDotMenu(
                  tooltip: 'خيارات',
                  onAction: _onTopMenuAction,
                ),
              ),
              tabs: _detailSections,
              selectedTabIndex: _selectedMainTab,
              onTabSelected: (index) =>
                  setState(() => _selectedMainTab = index),
              accentColor: color,
              actions: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDCE5EF)),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(
                        'رقم التواصل: $phoneValue',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'تحتاج متابعة (عام): $followUpCount',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selectedTab == 'الملخص')
                    _SummaryPanel(
                      person: person,
                      textDirection: TextDirection.rtl,
                    ),
                  if (selectedTab == 'المالية')
                    _SummaryStatsPanel(
                      title: 'الملخص المالي',
                      textDirection: TextDirection.rtl,
                      blocks: [
                        (
                          'المستحق له',
                          '${person.dueToYou} درهم',
                          const Color(0xFF0F766E),
                        ),
                        (
                          'المستحق عليه',
                          '${person.dueOnYou} درهم',
                          const Color(0xFFB45309),
                        ),
                        (
                          'الالتزامات المشتركة',
                          '${filteredCommitments.length}',
                          const Color(0xFF0F6AA8),
                        ),
                      ],
                    ),
                  if (selectedTab == 'المستندات')
                    _DynamicLinkedDataCard(
                      title: 'المستندات المرتبطة بالشخص',
                      icon: Icons.description_rounded,
                      color: const Color(0xFF7C3AED),
                      emptyText: 'لا توجد مستندات مرتبطة حتى الآن',
                      textDirection: TextDirection.rtl,
                      items: filteredDocuments,
                    ),
                  if (selectedTab == 'التنظيم والمتابعة والبيانات') ...[
                    _SummaryStatsPanel(
                      title: 'التنظيم والمتابعة',
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
                  ],
                  if (selectedTab == 'كلمات السر')
                    const _SummaryStatsPanel(
                      title: 'كلمات السر',
                      blocks: [
                        (
                          'لا توجد كلمات سر محفوظة',
                          'يمكن إضافتها من زر + إضافة',
                          Color(0xFF334155),
                        ),
                      ],
                    ),
                  if (selectedTab == 'الملاحظات')
                    _SummaryStatsPanel(
                      title: 'الملاحظات',
                      blocks: [
                        (
                          'ملاحظة',
                          person.extraNote.isEmpty
                              ? 'لا توجد ملاحظات'
                              : person.extraNote,
                          const Color(0xFF334155),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
                          borderRadius: BorderRadius.circular(10),
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
                            borderRadius: BorderRadius.circular(10),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE2E7)),
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
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EA)),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFDDE2E7)),
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
                        Icons.chevron_left_rounded,
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final _PersonItem person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: person.badgeColor.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.person_rounded,
                    color: person.badgeColor,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        person.fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${person.roleTitle} · ${person.categoryName}',
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: person.badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        person.badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: person.badgeColor,
                        ),
                      ),
                    ),
                    if (person.isPinned || person.isFrozen) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.rtl,
                        children: [
                          if (person.isPinned)
                            const Icon(
                              Icons.push_pin_rounded,
                              size: 15,
                              color: Color(0xFFF59E0B),
                            ),
                          if (person.isPinned && person.isFrozen)
                            const SizedBox(width: 4),
                          if (person.isFrozen)
                            const Icon(
                              Icons.block_rounded,
                              size: 15,
                              color: Color(0xFF64748B),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                _PeopleCardStat(
                  icon: Icons.description_rounded,
                  value: person.documentsCount,
                  label: 'الوثائق',
                ),
                _PeopleCardStat(
                  icon: Icons.task_alt_rounded,
                  value: person.openTasks,
                  label: 'المهام',
                ),
                _PeopleCardStat(
                  icon: Icons.groups_rounded,
                  value: person.sharedCommitments.length,
                  label: 'المشتركة',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleCardStat extends StatelessWidget {
  const _PeopleCardStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
    final isRtl = textDirection == TextDirection.rtl;
    final crossAxis = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = isRtl ? TextAlign.right : TextAlign.left;
    final rows = [
      ('تاريخ الإنشاء', person.createdAt),
      ('الاسم', person.fullName),
      ('الجنسية', detailValue(const ['الجنسية'])),
      ('تاريخ الميلاد', detailValue(const ['تاريخ الميلاد'])),
      ('التصنيف', person.categoryName),
      ('رقم الهاتف', detailValue(const ['رقم الهاتف'], fallback: 'غير متوفر')),
      ('الحالة', person.badge),
      ('آخر تحديث', person.lastUpdate),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF8FBFF), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1E1F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: crossAxis,
        children: [
          Text(
            'بطاقة الملخص',
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0B4A73),
            ),
          ),
          const SizedBox(height: 10),
          ...rows.map((item) => _line(item.$1, item.$2, textDirection)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            textDirection: textDirection,
            children: [
              _metricPill(
                'المستحق له',
                '${person.dueToYou} درهم',
                const Color(0xFFDCFCE7),
                const Color(0xFF166534),
              ),
              _metricPill(
                'المستحق عليه',
                '${person.dueOnYou} درهم',
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
          const SizedBox(height: 10),
          _line(
            'ملاحظات',
            person.extraNote.isEmpty ? '-' : person.extraNote,
            textDirection,
          ),
        ],
      ),
    );
  }

  Widget _line(String title, String value, TextDirection textDirection) {
    final isRtl = textDirection == TextDirection.rtl;
    final textAlign = isRtl ? TextAlign.right : TextAlign.left;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: textAlign,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
    final crossAxis = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Directionality(
      textDirection: textDirection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE5EF)),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDCE5EF)),
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
    final crossAxis = isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
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

class _ScopeFilterRect extends StatelessWidget {
  const _ScopeFilterRect({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : const Color(0xFFDCE5EF),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitScopeCategoryTab extends StatelessWidget {
  const _SplitScopeCategoryTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onLabelTap,
    required this.onArrowTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onLabelTap;
  final VoidCallback onArrowTap;

  @override
  Widget build(BuildContext context) {
    final baseBorder = selected
        ? const Color(0xFFBFD2E6)
        : const Color(0xFFDCE5EF);
    final textColor = const Color(0xFF334155);
    final badgeBackground = const Color(0xFFF1F5F9);

    return Container(
      width: 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: baseBorder, width: selected ? 1.4 : 1),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.white,
                child: InkWell(
                  onTap: onLabelTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBackground,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count',
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
                ),
              ),
            ),
            Container(
              width: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(
                  right: BorderSide(color: const Color(0xFFDCE5EF)),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onArrowTap,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: const Color(0xFF0F172A),
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
      dueToYou: dueToYou,
      dueOnYou: dueOnYou,
      openTasks: openTasks,
      documentsCount: documentsCount + 1,
      lastUpdate: 'اليوم',
      createdAt: createdAt,
      sharedCommitments: sharedCommitments,
      documents: [...documents, document],
      details: details,
      isPinned: isPinned,
      isFrozen: isFrozen,
    );
  }
}
