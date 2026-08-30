import 'package:flutter/material.dart';

import '../data/calendar_items_store.dart';
import '../data/home_dashboard_service.dart';
import '../l10n/home_strings.dart';
import 'people_management_screen.dart';
import 'personal_commitments_screen.dart';
import 'projects_activities_screen.dart';
import 'shared_commitments_screen.dart';
import '../widgets/shared/app_design.dart';

class SmartCalendarScreen extends StatefulWidget {
  const SmartCalendarScreen({super.key, this.metricsLoader});

  final Future<HomeDashboardMetrics> Function()? metricsLoader;

  @override
  State<SmartCalendarScreen> createState() => _SmartCalendarScreenState();
}

class _SmartCalendarScreenState extends State<SmartCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = true;
  bool _showSmartReminders = false;
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
    return _items
        .where((item) => DateUtils.isSameDay(item.date, _selectedDate))
        .toList(growable: false);
  }

  List<HomeCalendarItem> _itemsForDate(DateTime date) {
    return _items
        .where((item) => DateUtils.isSameDay(item.date, date))
        .toList(growable: false);
  }

  Color _colorForDate(DateTime date) {
    final items = _itemsForDate(date);
    if (items.isEmpty) return Colors.transparent;
    final today = DateUtils.dateOnly(DateTime.now());
    if (items.any(
      (item) =>
          item.status != 'مكتملة' && DateUtils.dateOnly(date).isBefore(today),
    )) {
      return const Color(0xFFDC2626);
    }
    if (items.any(
      (item) => item.priority == 'عالية' && item.status != 'مكتملة',
    )) {
      return const Color(0xFFF59E0B);
    }
    if (items.any((item) => item.status != 'مكتملة')) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFF16A34A);
  }

  List<Color> _colorsForDate(DateTime date) {
    final colors = <Color>[];
    for (final item in _itemsForDate(date)) {
      final color = item.status == 'مكتملة'
          ? const Color(0xFF16A34A)
          : DateUtils.dateOnly(
              date,
            ).isBefore(DateUtils.dateOnly(DateTime.now()))
          ? const Color(0xFFDC2626)
          : item.priority == 'عالية'
          ? const Color(0xFFF59E0B)
          : item.type == 'موعد'
          ? const Color(0xFF7C3AED)
          : item.type == 'تذكير'
          ? const Color(0xFF0891B2)
          : const Color(0xFF2563EB);
      if (!colors.contains(color)) colors.add(color);
    }
    return colors;
  }

  List<_SmartReminder> _smartRemindersForSelectedDate() {
    return const [
      _SmartReminder('مستند سينتهي قريبًا', Color(0xFFDC2626)),
      _SmartReminder('ضمان سينتهي قريبًا', Color(0xFFF59E0B)),
      _SmartReminder('مستند جديد', Color(0xFF2563EB)),
      _SmartReminder('مستند محدث', Color(0xFF16A34A)),
      _SmartReminder('مستند مرفوض', Color(0xFF7C3AED)),
      _SmartReminder('توجد مستندات متعارضة أو مكررة', Color(0xFFDC2626)),
      _SmartReminder('ملف مهم سينتهي وقد يؤثر على العمليات', Color(0xFFEA580C)),
      _SmartReminder('مراجعة كل 30 يوم', Color(0xFF0F172A)),
      _SmartReminder('مستند سينتهي خلال 90 يوم', Color(0xFF0891B2)),
      _SmartReminder('اعتماد صرف الموافقات', Color(0xFF0EA5E9)),
      _SmartReminder('احتمال تجاوز الميزانية', Color(0xFFB91C1C)),
      _SmartReminder('زيادة المصروفات بشكل غير طبيعي', Color(0xFFF97316)),
    ];
  }

  Set<String> _dayKeysInVisibleMonth() {
    return _items
        .where(
          (item) =>
              item.date.year == _visibleMonth.year &&
              item.date.month == _visibleMonth.month,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
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
                        color: Color(0xFF0F6AA8),
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
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'مهمة',
                        label: Text('مهمة'),
                        icon: Icon(Icons.task_alt_rounded),
                      ),
                      ButtonSegment(
                        value: 'تذكير',
                        label: Text('تذكير'),
                        icon: Icon(Icons.notifications_active_outlined),
                      ),
                      ButtonSegment(
                        value: 'موعد',
                        label: Text('موعد'),
                        icon: Icon(Icons.schedule_rounded),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (value) =>
                        setSheetState(() => type = value.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('calendar-record-title'),
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'العنوان *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'التفاصيل',
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
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: 'الأولوية',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['منخفضة', 'متوسطة', 'عالية']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => priority = value ?? priority),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: remindBeforeDays,
                    decoration: const InputDecoration(
                      labelText: 'التذكير قبل الموعد',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        const {
                              0: 'في نفس اليوم',
                              1: 'قبل يوم',
                              3: 'قبل 3 أيام',
                              7: 'قبل أسبوع',
                              30: 'قبل شهر',
                            }.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setSheetState(() => remindBeforeDays = value ?? 0),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
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
                      existing == null ? 'حفظ العنصر' : 'حفظ التعديلات',
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
    if (item.module == 'الالتزامات الشخصية') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PersonalCommitmentsScreen()),
      );
      return;
    }
    if (item.module == 'الالتزامات المشتركة') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SharedCommitmentsScreen()),
      );
      return;
    }
    if (item.module == 'الأفراد والجهات') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PeopleManagementScreen()));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProjectsActivitiesScreen()));
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
                        tooltip: 'السنة السابقة',
                        onPressed: () => setDialogState(() => selectedYear--),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                      Expanded(
                        child: Text(
                          'اختر شهر $selectedYear',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'السنة التالية',
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
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(
                          dialogContext,
                          DateTime(selectedYear, monthNumber),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0F6AA8)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF0F6AA8)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            _monthName(monthNumber),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF334155),
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
      final selected = DateUtils.isSameDay(date, _selectedDate);
      final hasItems = dayKeys.contains(key);
      final itemColor = _colorForDate(date);
      final itemColors = _colorsForDate(date);
      cells.add(
        InkWell(
          onTap: () => setState(() {
            _selectedDate = date;
            _showSmartReminders = false;
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: hasItems
                  ? itemColor.withValues(alpha: selected ? 0.22 : 0.10)
                  : selected
                  ? const Color(0xFFEAF2FF)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(
                      color: hasItems ? itemColor : const Color(0xFF0F6AA8),
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
                    color: Color(0xFF0F172A),
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
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
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
          const Row(
            children: [
              Expanded(child: Center(child: Text('أحد'))),
              Expanded(child: Center(child: Text('اثن'))),
              Expanded(child: Center(child: Text('ثلا'))),
              Expanded(child: Center(child: Text('أرب'))),
              Expanded(child: Center(child: Text('خمي'))),
              Expanded(child: Center(child: Text('جمع'))),
              Expanded(child: Center(child: Text('سبت'))),
            ],
          ),
          const SizedBox(height: 6),
          Table(children: rows),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'دليل الألوان',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: const [
                _CalendarLegend(color: Color(0xFFDC2626), label: 'متأخر'),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFF59E0B),
                  label: 'أولوية عالية',
                ),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF2563EB), label: 'مهمة'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF7C3AED), label: 'موعد'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF0891B2), label: 'تذكير'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF16A34A), label: 'مكتمل'),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFDC2626),
                  label: 'مستند سينتهي قريبًا',
                ),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFF59E0B),
                  label: 'ضمان سينتهي قريبًا',
                ),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF2563EB), label: 'مستند جديد'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF16A34A), label: 'مستند محدث'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF7C3AED), label: 'مستند مرفوض'),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFDC2626),
                  label: 'متعارض أو مكرر',
                ),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFFEA580C), label: 'ملف مهم'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF0F172A), label: 'كل 30 يوم'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF0891B2), label: 'خلال 90 يوم'),
                SizedBox(width: 12),
                _CalendarLegend(color: Color(0xFF0EA5E9), label: 'اعتماد صرف'),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFB91C1C),
                  label: 'تجاوز الميزانية',
                ),
                SizedBox(width: 12),
                _CalendarLegend(
                  color: Color(0xFFF97316),
                  label: 'مصروفات غير طبيعية',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaItem(HomeCalendarItem item) {
    final record = _recordFor(item);
    final color = _colorForDate(item.date);
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            item.type == 'مهمة'
                ? Icons.task_alt_rounded
                : item.type == 'موعد'
                ? Icons.schedule_rounded
                : Icons.notifications_active_outlined,
            color: color,
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            decoration: item.status == 'مكتملة'
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              item.type,
              if (item.time.isNotEmpty) item.time,
              item.priority == 'عالية' ? 'أولوية عالية' : null,
              if (item.description.isNotEmpty) item.description,
            ].whereType<String>().join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        trailing: record == null
            ? const Icon(Icons.arrow_back_ios_new_rounded, size: 16)
            : PopupMenuButton<String>(
                tooltip: 'إجراءات العنصر',
                onSelected: (action) {
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
            Icon(Icons.history_rounded, size: 20, color: Color(0xFF475569)),
            SizedBox(width: 7),
            Text(
              'سجل النشاط',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
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
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: completed
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF2563EB),
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
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${eventDate.day}/${eventDate.month}/${eventDate.year}  ${record.type}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
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

  Widget _buildSmartReminders() {
    final reminders = _smartRemindersForSelectedDate();
    final dateLabel =
        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تذكيرات ذكية - $dateLabel',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: reminders
                  .map(
                    (reminder) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Chip(
                        avatar: CircleAvatar(backgroundColor: reminder.color),
                        label: Text(reminder.title),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        side: BorderSide(
                          color: reminder.color.withValues(alpha: 0.3),
                        ),
                        backgroundColor: reminder.color.withValues(alpha: 0.08),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'إغلاق',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('الكلندر الذكي'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: const Color(0xFF0F6AA8),
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
        textDirection: TextDirection.rtl,
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
                      label: Text(
                        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (_showSmartReminders) _buildSmartReminders(),
                  const SizedBox(height: 6),
                  ..._itemsOfSelectedDay().map(_buildAgendaItem),
                  if (_itemsOfSelectedDay().isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        HomeStrings.noData,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
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
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _SmartReminder {
  const _SmartReminder(this.title, this.color);

  final String title;
  final Color color;
}
