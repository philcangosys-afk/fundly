import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../widgets/shared/module_shared_widgets.dart' show directOpenRoute;
import '../l10n/app_language.dart';

import '../data/calendar_items_store.dart';
import '../data/entry_status.dart';
import '../data/home_dashboard_service.dart';
import '../data/shared_alerts.dart';
import '../l10n/home_strings.dart';
import 'people_management_screen.dart';
import 'personal_commitments_screen.dart';
import 'projects_activities_screen.dart';
import 'shared_commitments_screen.dart';
import '../widgets/shared/app_design.dart';

class SmartCalendarScreen extends StatefulWidget {
  const SmartCalendarScreen({
    super.key,
    this.metricsLoader,
    this.modules,
    this.scopeLabel = '',
  });

  final Future<HomeDashboardMetrics> Function()? metricsLoader;

  /// كلندر داخلي لقسم: بنود هذه الأقسام وحدها (أسماء [HomeCalendarItem.module]).
  /// بدونه: كل الأقسام (كلندر الرئيسية).
  final Set<String>? modules;

  /// اسم القسم تحت العنوان في الكلندر الداخلي.
  final String scopeLabel;

  /// كلندر الالتزامات الشخصية — ونظائره للأقسام الأخرى.
  static const personalModules = {'الالتزامات الشخصية'};
  static const sharedModules = {'الالتزامات المشتركة'};
  static const peopleModules = {'الأفراد والجهات'};
  static const assetModules = {
    'العقارات والأنشطة التجارية',
    'الأنشطة التجارية',
    'العقارات',
    'المركبات ووسائل النقل',
  };

  @override
  State<SmartCalendarScreen> createState() => _SmartCalendarScreenState();
}

class _SmartCalendarScreenState extends State<SmartCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = true;
  bool _showSmartReminders = true;

  /// النوع المختار من أزرار اليوم (مهمة، موعد...) — يصفّي قائمة اليوم.
  String? _subFilter;

  /// «الكل»: كل البنود بكل الأيام، الأحدث أولًا — حتى يُضغط يوم.
  bool _allDays = true;
  List<HomeCalendarItem> _items = const [];
  List<CalendarRecord> _records = const [];

  String _monthName(int month) {
    const names = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return names[month - 1];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final metricsLoader = widget.metricsLoader;
    final results = await Future.wait([
      metricsLoader != null
          ? metricsLoader()
          : HomeDashboardService().loadMetrics(),
      CalendarItemsStore.load(),
    ]);
    if (!mounted) return;
    final metrics = results[0] as HomeDashboardMetrics;
    final records = results[1] as List<CalendarRecord>;
    final scope = widget.modules;
    // الكلندر الداخلي: بنود القسم وحدها — بلا ما أُضيف في الكلندر العام.
    if (scope != null) {
      setState(() {
        _items = [
          for (final item in metrics.calendarItems)
            if (scope.contains(item.module)) item,
        ];
        _records = const [];
        _isLoading = false;
      });
      return;
    }
    final items = List<HomeCalendarItem>.from(metrics.calendarItems);
    for (final record in records) {
      if (items.any((item) => item.sourceId == record.id)) continue;
      items.add(
        HomeCalendarItem(
          title: record.title,
          module: 'التقويم الذكي',
          date: record.date,
          sourceId: record.id,
          remindBeforeDays: record.remindBeforeDays,
          type: record.type,
          status: record.status,
          priority: record.priority,
          time: record.time,
          description: record.description,
          notes: record.notes,
          isUserCreated: true,
        ),
      );
    }
    setState(() {
      _items = items;
      _records = records;
      _isLoading = false;
    });
  }

  List<HomeCalendarItem> _itemsOfSelectedDay() {
    if (_allDays) return _items;
    return _items
        .where((item) => DateUtils.isSameDay(item.date, _selectedDate))
        .toList(growable: false);
  }

  // ---- التصنيف: الكلندر يعرض التنبيهات فقط بمجموعاتها.
  static const _cOverdue = Color(0xFFC4392E);
  static const _cHigh = Color(0xFFF2A93F);
  static const _cFollow = Color(0xFF0E7161);
  static const _cExpiry = Color(0xFFCE8422);
  static const _cDue = Color(0xFF0A5A50);
  static const _cApproval = Color(0xFF34A894);
  static const _cBudget = Color(0xFFA82F26);

  static const _gFollow = 'متابعة وتخطيط';
  static const _gExpiry = 'سينتهي قريبًا';
  static const _gDue = 'استحقاقات';
  static const _gApproval = 'اعتماد صرف';
  static const _gBudget = 'تنبيه الميزانية';

  static const _followKinds = ['مهمة', 'موعد', 'عادة', 'تذكير', 'ملاحظات'];
  static const _docsSoon = 'مستندات ستنتهي قريبًا';
  // الضمانات ضمن المستندات.
  static const _docsExpired = 'مستندات منتهية';

  /// دليل الألوان بترتيب الأهمية.
  static const _legend = [
    ('متأخر', _cOverdue),
    (_gBudget, _cBudget),
    (_gApproval, _cApproval),
    ('أولوية عالية', _cHigh),
    (_gExpiry, _cExpiry),
    (_gFollow, _cFollow),
    (_gDue, _cDue),
  ];

  bool _isDone(HomeCalendarItem item) =>
      HomeDashboardService.closedStatuses.contains(item.status.trim());

  String _kindOf(HomeCalendarItem item) => item.entryType.trim().isNotEmpty
      ? item.entryType.trim()
      : item.type.trim();

  /// المجموعة: متابعة وتخطيط / سينتهي قريبًا / استحقاقات / اعتماد صرف /
  /// تنبيه الميزانية.
  String _groupOf(HomeCalendarItem item) {
    final kind = _kindOf(item);
    if (kind == sharedApprovalAlertType) return _gApproval;
    if (kind == sharedBudgetAlertType) return _gBudget;
    if (item.isExpiry ||
        kind == 'مستند' ||
        kind == 'ضمانات' ||
        kind == 'انتهاء') {
      return _gExpiry;
    }
    if (item.isUserCreated || _followKinds.contains(kind)) return _gFollow;
    return _gDue;
  }

  /// النوع داخل المجموعة: أزرار اليوم (مهمة، موعد... مستندات ستنتهي...).
  String _subOf(HomeCalendarItem item) {
    final group = _groupOf(item);
    if (group == _gFollow) {
      final kind = _kindOf(item);
      return _followKinds.contains(kind) ? kind : 'مهمة';
    }
    if (group == _gExpiry) {
      return DateUtils.dateOnly(item.date)
              .isBefore(DateUtils.dateOnly(DateTime.now()))
          ? _docsExpired
          : _docsSoon;
    }
    return group;
  }

  /// متأخر: فات موعده ولم يُغلق — إلا الملاحظات والعادة وما يتكرر.
  bool _isOverdue(HomeCalendarItem item) {
    if (_isDone(item)) return false;
    final kind = _kindOf(item);
    if (kind == 'ملاحظات' || kind == 'عادة' || item.repeat.isNotEmpty) {
      return false;
    }
    // المصروف / الإيراد عملية تمّت: لا تُعدّ «متأخرة» بمرور تاريخها (كما في
    // صفحة الالتزامات الشخصية).
    if (entryTransactionTypes.contains(kind)) return false;
    // العهدة والدواء والمناسبة والهدية: يومها بداية أو حدث لا موعد سداد.
    if (const {'عهدة مالية', 'أدوية', 'مناسبة', 'هدية'}.contains(kind)) {
      return false;
    }
    final group = _groupOf(item);
    if (group == _gApproval || group == _gBudget) return false;
    return DateUtils.dateOnly(
      item.date,
    ).isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  Color _dotColor(HomeCalendarItem item) {
    final group = _groupOf(item);
    if (group == _gApproval) return _cApproval;
    if (group == _gBudget) return _cBudget;
    if (_isOverdue(item)) return _cOverdue;
    if (item.priority == 'عالية') return _cHigh;
    return switch (group) {
      _gFollow => _cFollow,
      _gExpiry => _cExpiry,
      _ => _cDue,
    };
  }

  List<HomeCalendarItem> _itemsForDate(DateTime date) {
    return _items
        .where((item) => DateUtils.isSameDay(item.date, date))
        .toList(growable: false);
  }

  /// لون اليوم: أهم تنبيه فيه.
  Color _colorForDate(DateTime date) {
    final colors = _colorsForDate(date);
    for (final entry in _legend) {
      if (colors.contains(entry.$2)) return entry.$2;
    }
    return Colors.transparent;
  }

  /// نقاط اليوم: لون كل تنبيه مفتوح فيه (المكتمل بلا نقطة).
  List<Color> _colorsForDate(DateTime date) {
    final colors = <Color>[];
    for (final item in _itemsForDate(date)) {
      if (_isDone(item)) continue;
      final color = _dotColor(item);
      if (!colors.contains(color)) colors.add(color);
    }
    // الأهم أولًا (تظهر ثلاث نقاط فقط).
    colors.sort(
      (a, b) => _legend
          .indexWhere((e) => e.$2 == a)
          .compareTo(_legend.indexWhere((e) => e.$2 == b)),
    );
    return colors;
  }

  /// ألوان الشهر الظاهر — دليل الألوان يعرض ما فيه تنبيهات فقط.
  Set<Color> _colorsInVisibleMonth() {
    final colors = <Color>{};
    for (final item in _items) {
      if (item.date.year != _visibleMonth.year ||
          item.date.month != _visibleMonth.month ||
          _isDone(item)) {
        continue;
      }
      colors.add(_dotColor(item));
    }
    return colors;
  }

  Set<String> _dayKeysInVisibleMonth() {
    return _items
        .where(
          (item) =>
              item.date.year == _visibleMonth.year &&
              item.date.month == _visibleMonth.month &&
              !_isDone(item),
        )
        .map((item) => '${item.date.year}-${item.date.month}-${item.date.day}')
        .toSet();
  }

  CalendarRecord? _recordFor(HomeCalendarItem item) {
    for (final record in _records) {
      if (record.id == item.sourceId) return record;
    }
    return null;
  }

  Future<void> _openRecordForm([CalendarRecord? existing]) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var type = existing?.type ?? 'مهمة';
    var priority = existing?.priority ?? 'متوسطة';
    var remindBeforeDays = existing?.remindBeforeDays ?? 0;
    var date = existing?.date ?? _selectedDate;
    var time = existing?.time ?? '';

    final record = await showModalBottomSheet<CalendarRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.event_note_rounded,
                        color: Color(0xFF0A5A50),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          existing == null ? 'إضافة عنصر جديد' : 'تعديل العنصر',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // مهمة، موعد، عادة، تذكير، ملاحظات — الخمسة في سطر واحد
                  // وبمقاس واحد: الأيقونة فوق الاسم.
                  Row(
                    children: [
                      for (final option in const [
                        ('مهمة', Icons.task_alt_rounded),
                        ('موعد', Icons.schedule_rounded),
                        ('عادة', Icons.repeat_rounded),
                        ('تذكير', Icons.notifications_active_outlined),
                        ('ملاحظات', Icons.sticky_note_2_outlined),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppTheme.rPill,
                              ),
                              onTap: () =>
                                  setSheetState(() => type = option.$1),
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: type == option.$1
                                      ? const Color(0xFF0A5A50)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: type == option.$1
                                        ? const Color(0xFF0A5A50)
                                        : const Color(0xFFD5DEDB),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      option.$2,
                                      size: 16,
                                      color: type == option.$1
                                          ? Colors.white
                                          : const Color(0xFF0A5A50),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      option.$1,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: type == option.$1
                                            ? Colors.white
                                            : const Color(0xFF2C3B38),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('calendar-record-title'),
                    controller: titleController,
                    decoration: InputDecoration(
                      label: const Text('الموضوع *'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('التفاصيل'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setSheetState(() => date = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text('${date.day}/${date.month}/${date.year}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null) {
                              setSheetState(
                                () => time = picked.format(context),
                              );
                            }
                          },
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(time.isEmpty ? 'اختيار الوقت' : time),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // «مخصص» (-1): يكتب عدد الأيام بنفسه.
                  DropdownButtonFormField<int>(
                    key: ValueKey('calendar-remind-$remindBeforeDays'),
                    initialValue: remindBeforeDays,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('التذكير قبل الموعد'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in {
                        0: 'في نفس اليوم',
                        1: 'قبل يوم',
                        3: 'قبل 3 أيام',
                        7: 'قبل أسبوع',
                        30: 'قبل شهر',
                        if (!const {0, 1, 3, 7, 30}.contains(remindBeforeDays))
                          remindBeforeDays:
                              '${AppTr.tr('قبل')} $remindBeforeDays ${AppTr.tr('يوم')}',
                        -1: 'مخصص',
                      }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) async {
                      if (value != -1) {
                        setSheetState(() => remindBeforeDays = value ?? 0);
                        return;
                      }
                      final days = await _askCustomRemindDays(
                        context,
                        remindBeforeDays,
                      );
                      // يُعاد بناء الحقل بالقيمة الجديدة (أو القديمة إن أُلغي).
                      setSheetState(
                        () => remindBeforeDays = days ?? remindBeforeDays,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('ملاحظات'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('save-calendar-record'),
                    onPressed: () {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;
                      Navigator.pop(
                        sheetContext,
                        CalendarRecord(
                          id:
                              existing?.id ??
                              'calendar-${DateTime.now().microsecondsSinceEpoch}',
                          title: title,
                          type: type,
                          date: date,
                          time: time,
                          priority: priority,
                          status: existing?.status ?? 'قادمة',
                          description: descriptionController.text.trim(),
                          notes: notesController.text.trim(),
                          remindBeforeDays: remindBeforeDays,
                          createdAt: existing?.createdAt ?? DateTime.now(),
                          completedAt: existing?.completedAt,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      'حفظ',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    notesController.dispose();
    if (record == null) return;
    await CalendarItemsStore.upsert(record);
    _selectedDate = record.date;
    _visibleMonth = DateTime(record.date.year, record.date.month);
    await _load();
  }

  /// «مخصص»: عدد الأيام قبل الموعد يكتبه المستخدم.
  Future<int?> _askCustomRemindDays(BuildContext context, int current) async {
    final controller = TextEditingController(
      text: current > 0 ? '$current' : '',
    );
    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('تذكير مخصص'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppTr.tr('عدد الأيام قبل الموعد'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(
                  controller.text.trim().replaceAllMapped(
                    RegExp('[٠-٩]'),
                    (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}',
                  ),
                );
                if (n == null || n < 0 || n > 365) return;
                Navigator.pop(dialogContext, n);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    return days;
  }

  Future<void> _toggleCompleted(CalendarRecord record) async {
    final completed = record.status == 'مكتملة';
    await CalendarItemsStore.upsert(
      record.copyWith(
        status: completed ? 'قادمة' : 'مكتملة',
        completedAt: completed ? null : DateTime.now(),
        clearCompletedAt: completed,
      ),
    );
    await _load();
  }

  Future<void> _deleteRecord(CalendarRecord record) async {
    await CalendarItemsStore.remove(record.id);
    await _load();
  }

  void _openItem(HomeCalendarItem item) {
    // يُفتح البند نفسه (وفي المشتركة على تبويبه) بدل القائمة فقط.
    var id = item.sourceId.trim();
    // تنبيه نسبة صرف العهدة: معرّفه «custody_percent_» ثم معرّف العهدة.
    const custodyPrefix = 'custody_percent_';
    if (id.startsWith(custodyPrefix)) id = id.substring(custodyPrefix.length);
    // بمعرّف: التفاصيل مباشرة (صفحة واحدة)، وبدونه القائمة.
    Route<void> route(Widget page, bool direct) => direct
        ? directOpenRoute<void>(page)
        : MaterialPageRoute<void>(builder: (_) => page);
    if (item.module == 'الالتزامات الشخصية') {
      Navigator.of(context).push(
        route(
          PersonalCommitmentsScreen(openEntryId: id.isEmpty ? null : id),
          id.isNotEmpty,
        ),
      );
      return;
    }
    if (item.module == 'الالتزامات المشتركة') {
      Navigator.of(context).push(
        route(
          SharedCommitmentsScreen(openEntryId: id.isEmpty ? null : id),
          id.isNotEmpty,
        ),
      );
      return;
    }
    if (item.module == 'الأفراد والجهات') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PeopleManagementScreen()));
      return;
    }
    final assetDirect =
        item.module == 'العقارات والأنشطة التجارية' && id.isNotEmpty;
    Navigator.of(context).push(
      route(
        ProjectsActivitiesScreen(openAssetId: assetDirect ? id : null),
        assetDirect,
      ),
    );
  }

  Future<void> _showMonthPickerDialog() async {
    final selectedDate = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        var selectedYear = _visibleMonth.year;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: AppTr.tr('السنة السابقة'),
                        onPressed: () => setDialogState(() => selectedYear--),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                      Expanded(
                        child: Text(
                          'اختر شهر $selectedYear',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppTr.tr('السنة التالية'),
                        onPressed: () => setDialogState(() => selectedYear++),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 12,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.8,
                        ),
                    itemBuilder: (_, index) {
                      final monthNumber = index + 1;
                      final isSelected =
                          _visibleMonth.year == selectedYear &&
                          _visibleMonth.month == monthNumber;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(
                          dialogContext,
                          DateTime(selectedYear, monthNumber),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0A5A50)
                                : const Color(0xFFF7FAF9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF0A5A50)
                                  : const Color(0xFFE4EAE8),
                            ),
                          ),
                          child: Text(
                            _monthName(monthNumber),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF2C3B38),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedDate == null) return;
    setState(() {
      _visibleMonth = selectedDate;
      _selectedDate = DateTime(selectedDate.year, selectedDate.month, 1);
    });
  }

  Widget _buildMonthCalendar() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final startWeekday = firstDay.weekday % 7;
    final dayKeys = _dayKeysInVisibleMonth();
    final cells = <Widget>[];

    for (var i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
      final key = '${date.year}-${date.month}-${date.day}';
      final selected = !_allDays && DateUtils.isSameDay(date, _selectedDate);
      final hasItems = dayKeys.contains(key);
      final itemColor = _colorForDate(date);
      final itemColors = _colorsForDate(date);
      cells.add(
        InkWell(
          // الضغط على اليوم يعرض أنواع ما فيه (مهمة، موعد، عادة...).
          onTap: () => setState(() {
            _selectedDate = date;
            _allDays = false;
            _showSmartReminders = true;
            _subFilter = null;
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: hasItems
                  ? itemColor.withValues(alpha: selected ? 0.22 : 0.10)
                  : selected
                  ? const Color(0xFFD9EDE8)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(
                      color: hasItems ? itemColor : const Color(0xFF0A5A50),
                      width: 1.5,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 2),
                if (hasItems)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: itemColors
                        .take(3)
                        .map(
                          (color) => Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  )
                else
                  const SizedBox(height: 5),
              ],
            ),
          ),
        ),
      );
    }

    final rows = <TableRow>[];
    for (var i = 0; i < cells.length; i += 7) {
      final rowCells = cells.skip(i).take(7).toList(growable: true);
      while (rowCells.length < 7) {
        rowCells.add(const SizedBox.shrink());
      }
      rows.add(TableRow(children: rowCells));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month - 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: InkWell(
                  onTap: _showMonthPickerDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          // أسماء الأيام كاملة؛ تصغر تلقائيًا لتتسع في عمودها بلا قطع.
          Row(
            children: [
              for (final day in const [
                'الأحد',
                'الاثنين',
                'الثلاثاء',
                'الأربعاء',
                'الخميس',
                'الجمعة',
                'السبت',
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        day,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Table(children: rows),
          // دليل الألوان: ما في الشهر من تنبيهات فقط.
          if (_colorsInVisibleMonth().isNotEmpty) ...[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'دليل الألوان',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF022E2A),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final entry in _legend)
                    if (_colorsInVisibleMonth().contains(entry.$2))
                      _CalendarLegend(color: entry.$2, label: entry.$1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgendaItem(HomeCalendarItem item) {
    final record = _recordFor(item);
    final color = _isDone(item) ? const Color(0xFF8C9A97) : _dotColor(item);
    final group = _groupOf(item);
    final kind = _kindOf(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: ListTile(
        onTap: record == null ? () => _openItem(item) : null,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            switch (group) {
              _gApproval => Icons.verified_outlined,
              _gBudget => Icons.account_balance_wallet_outlined,
              _gExpiry => Icons.event_busy_outlined,
              _gDue => Icons.payments_outlined,
              _ => switch (kind) {
                'مهمة' => Icons.task_alt_rounded,
                'موعد' => Icons.schedule_rounded,
                'عادة' => Icons.repeat_rounded,
                'ملاحظات' => Icons.sticky_note_2_outlined,
                _ => Icons.notifications_active_outlined,
              },
            },
            color: color,
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF022E2A),
            decoration: item.status == 'مكتملة'
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              '${AppTr.tr(_subOf(item))} · ${AppTr.tr(item.module)}',
              if (item.time.isNotEmpty) item.time,
              item.priority == 'عالية' ? 'أولوية عالية' : null,
              if (item.description.isNotEmpty) item.description,
            ].whereType<String>().join(' • '),
            maxLines: 4,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5C6B68),
            ),
          ),
        ),
        trailing: record == null
            ? const Icon(Icons.arrow_back_ios_new_rounded, size: 16)
            : PopupMenuButton<String>(
                tooltip: AppTr.tr('إجراءات العنصر'),
                onSelected: (action) async {
                  final danger = action == 'delete';
                  final ok = await confirmAction(
                    context,
                    title: switch (action) {
                      'toggle' => record.status == 'مكتملة'
                          ? 'إعادة فتح العنصر'
                          : 'تحديد العنصر كمكتمل',
                      'edit' => 'تعديل العنصر',
                      _ => 'حذف العنصر',
                    },
                    message: danger
                        ? 'سيُحذف العنصر نهائيًا ولا يمكن التراجع. '
                              'هل تريد الحذف؟'
                        : 'هل تريد تنفيذ هذا الإجراء على العنصر؟',
                    confirmLabel: danger ? 'حذف' : 'تأكيد',
                    danger: danger,
                  );
                  if (!ok || !context.mounted) return;
                  if (action == 'toggle') _toggleCompleted(record);
                  if (action == 'edit') _openRecordForm(record);
                  if (action == 'delete') _deleteRecord(record);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      record.status == 'مكتملة' ? 'إعادة فتح' : 'تحديد كمكتمل',
                    ),
                  ),
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
      ),
    );
  }

  Widget _buildActivityLog() {
    final records = [..._records]
      ..sort((a, b) {
        final aDate = a.completedAt ?? a.createdAt;
        final bDate = b.completedAt ?? b.createdAt;
        return bDate.compareTo(aDate);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: Color(0xFF46534F)),
            SizedBox(width: 7),
            Text(
              'سجل النشاط',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE4EAE8)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'سيظهر هنا سجل العناصر التي تضيفها وتنجزها.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ...records.take(20).map((record) {
            final eventDate = record.completedAt ?? record.createdAt;
            final completed = record.status == 'مكتملة';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE4EAE8))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: completed
                          ? const Color(0xFF34A894)
                          : const Color(0xFF0A5A50),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          completed
                              ? 'تم إنجاز: ${record.title}'
                              : 'تمت إضافة: ${record.title}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${eventDate.day}/${eventDate.month}/${eventDate.year}  ${record.type}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5C6B68),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// أنواع ما في اليوم المختار: المتابعة والتخطيط (مهمة، موعد، عادة، تذكير،
  /// ملاحظات)، وما سينتهي قريبًا (مستندات، ضمانات)، ثم المالية. الضغط على
  /// نوع يعرض بنوده وحدها تحت.
  /// مربعات اليوم المختار: «متابعة وتخطيط» خمسة مربعات (مهمة، موعد، عادة،
  /// تذكير، ملاحظات)، و«مستندات» (منتهية، ستنتهي قريبًا — والضمانات
  /// منها)، ثم المالية إن وُجدت. في كل مربع اسمه وتحته عدد ما يُتابَع،
  /// والضغط عليه يعرض بنوده تحت.
  Widget _buildSmartReminders() {
    final day = _itemsOfSelectedDay();
    int count(String sub) =>
        day.where((i) => !_isDone(i) && _subOf(i) == sub).length;
    /// [stacked]: الرقم تحت الاسم (مربعات «متابعة وتخطيط» الخمسة)، وإلا
    /// بجانبه.
    Widget tile(String sub, Color color, {bool stacked = false}) {
      final n = count(sub);
      final selected = _subFilter == sub;
      final label = Text(
        sub,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: n == 0 ? const Color(0xFF8C9A97) : color,
        ),
      );
      final number = Text(
        '$n',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: n == 0 ? const Color(0xFF8C9A97) : color,
        ),
      );
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          onTap: () => setState(() => _subFilter = selected ? null : sub),
          // الرقم بجانب الاسم في سطر واحد — المربعات أصغر.
          child: SizedBox(
            height: stacked ? 58 : 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.18)
                    : n == 0
                    ? const Color(0xFFF2F6F5)
                    : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.rInner),
                border: Border.all(
                  color: selected
                      ? color
                      : color.withValues(alpha: n == 0 ? 0.1 : 0.3),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: stacked
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [label, const SizedBox(height: 2), number],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: label),
                        const SizedBox(width: 4),
                        number,
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    Widget section(String title, Color color, List<Widget> tiles) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                tiles[i],
              ],
            ],
          ),
        ],
      ),
    );

    final allCount = day.where((i) => !_isDone(i)).length;
    final allSelected = _subFilter == null;
    final allTile = Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        onTap: () => setState(() {
          _subFilter = null;
          _allDays = true;
        }),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: allSelected
                ? AppTheme.brand.withValues(alpha: 0.14)
                : const Color(0xFFF2F6F5),
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(
              color: allSelected
                  ? AppTheme.brand
                  : AppTheme.brand.withValues(alpha: 0.2),
              width: allSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            '${AppTr.tr('الكل')} ($allCount)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.brand,
            ),
          ),
        ),
      ),
    );
    final money = [
      for (final entry in const [
        (_gDue, _cDue),
        (_gApproval, _cApproval),
        (_gBudget, _cBudget),
      ])
        if (count(entry.$1) > 0) tile(entry.$1, entry.$2),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(_gFollow, _cFollow, [
            for (final kind in _followKinds)
              tile(kind, _cFollow, stacked: true),
          ]),
          section('مستندات', _cExpiry, [
            tile(_docsExpired, _cOverdue),
            tile(_docsSoon, _cExpiry),
          ]),
          if (money.isNotEmpty) section('مالية', _cDue, money),
          // «الكل»: كل البنود (كل الأيام إن لم يُختر يوم) الأحدث أولًا.
          section('الكل', AppTheme.brand, [allTile]),
        ],
      ),
    );
  }

  /// بنود اليوم بعد تصفية النوع المختار.
  List<HomeCalendarItem> _visibleDayItems() {
    final day = _itemsOfSelectedDay();
    final filter = _subFilter;
    final list = filter == null
        ? [...day]
        : day.where((i) => _subOf(i) == filter).toList();
    // الأحدث أولًا: بالتاريخ ثم الوقت.
    list.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.time.compareTo(a.time);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        // سهم الرجوع نفسه في الكلندر والقرعة والتنبيهات.
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: widget.scopeLabel.isEmpty
            ? const Text('الكلندر الذكي')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('الكلندر الذكي'),
                  Text(
                    widget.scopeLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: const Color(0xFF0A5A50),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openRecordForm(),
                child: const SizedBox(
                  width: 44,
                  height: 40,
                  child: Icon(Icons.add_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildMonthCalendar(),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _showSmartReminders = !_showSmartReminders,
                      ),
                      icon: const Icon(Icons.notifications_active_outlined),
                      // «الكل»: إرشاد بدل التاريخ؛ ومع يوم مختار تاريخه.
                      label: Text(
                        _allDays
                            ? 'اضغط على اليوم أو على الفئات التي في الأسفل'
                            : '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (_showSmartReminders) _buildSmartReminders(),
                  const SizedBox(height: 6),
                  ..._visibleDayItems().map(_buildAgendaItem),
                  if (_visibleDayItems().isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        HomeStrings.noData,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5C6B68),
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  _buildActivityLog(),
                ],
              ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF5C6B68)),
        ),
      ],
    );
  }
}
