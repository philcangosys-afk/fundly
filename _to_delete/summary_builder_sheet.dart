import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/home_summary_service.dart';
import 'app_design.dart';

/// خطوات بناء الملخص الشامل بالتسلسل نفسه المستخدم في فلتر الالتزامات:
/// ١ القسم ← ٢ النوع ← ٣ الفترة ← ٤ الحالة، ثم النتيجة التفصيلية.
///
/// كل خطوة تُبنى من البيانات الحقيقية المتبقية بعد الخطوة التي قبلها، فلا
/// يظهر نوع أو حالة لا وجود لها في سجلات القسم المختار.
Future<void> showSummaryBuilderSheet({
  required BuildContext context,
  required Future<List<SummaryItem>> Function() loadItems,
  required void Function(String title, List<String> lines, bool asPdf) onShare,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.page,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: FractionallySizedBox(
        heightFactor: 1,
        child: _SummaryBuilder(loadItems: loadItems, onShare: onShare),
      ),
    ),
  );
}

const _modules = [
  (key: 'personal', label: 'الالتزامات الشخصية', icon: Icons.person_outline_rounded, color: Color(0xFF2563EB)),
  (key: 'shared', label: 'الالتزامات المشتركة', icon: Icons.groups_2_outlined, color: Color(0xFF10B981)),
  (key: 'people', label: 'إدارة الأشخاص والجهات', icon: Icons.badge_outlined, color: Color(0xFF7C3AED)),
  (key: 'assets', label: 'العقارات/الأنشطة التجارية/المعدات وأخرى', icon: Icons.apartment_rounded, color: Color(0xFFEA580C)),
];

class _SummaryBuilder extends StatefulWidget {
  const _SummaryBuilder({required this.loadItems, required this.onShare});

  final Future<List<SummaryItem>> Function() loadItems;
  final void Function(String title, List<String> lines, bool asPdf) onShare;

  @override
  State<_SummaryBuilder> createState() => _SummaryBuilderState();
}

class _SummaryBuilderState extends State<_SummaryBuilder> {
  List<SummaryItem> _all = const [];
  bool _loading = true;
  String? _error;

  String? _module;
  final Set<String> _types = {};
  DateTime? _from;
  DateTime? _to;
  String _status = 'الكل';
  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.loadItems();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل البيانات. تحقّق من الاتصال وحاول مرة أخرى.';
        _loading = false;
      });
    }
  }

  // ===== مصادر الخيارات: كل خطوة تُشتق مما تبقّى بعد سابقتها =====

  List<SummaryItem> get _moduleItems => _module == null
      ? const []
      : _all.where((item) => item.module == _module).toList(growable: false);

  List<String> get _typeOptions {
    final types = _moduleItems.map((item) => item.type).toSet().toList();
    types.sort();
    return types;
  }

  List<SummaryItem> get _typeItems => _types.isEmpty
      ? _moduleItems
      : _moduleItems
            .where((item) => _types.contains(item.type))
            .toList(growable: false);

  List<SummaryItem> get _dateItems => _typeItems.where((item) {
    if (_from == null && _to == null) return true;
    final date = item.date;
    if (date == null) return false;
    if (_from != null && date.isBefore(_from!)) return false;
    if (_to != null && date.isAfter(_to!)) return false;
    return true;
  }).toList(growable: false);

  List<String> get _statusOptions {
    final statuses = _dateItems
        .map((item) => item.status)
        .where((status) => status.trim().isNotEmpty)
        .toSet()
        .toList();
    statuses.sort();
    return [
      'الكل',
      ...statuses,
      if (_dateItems.any((item) => item.isOverdue)) kSummaryStatusOverdue,
      if (_dateItems.any((item) => item.isDueSoon)) kSummaryStatusDueSoon,
    ];
  }

  List<SummaryItem> get _result => _dateItems.where((item) {
    if (_status == 'الكل') return true;
    if (_status == kSummaryStatusOverdue) return item.isOverdue;
    if (_status == kSummaryStatusDueSoon) return item.isDueSoon;
    return item.status == _status;
  }).toList(growable: false);

  String get _moduleLabel => _modules
      .firstWhere(
        (module) => module.key == _module,
        orElse: () => _modules.first,
      )
      .label;

  Color get _accent => _module == null
      ? AppTheme.accent
      : _modules
            .firstWhere(
              (module) => module.key == _module,
              orElse: () => _modules.first,
            )
            .color;

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
      _status = 'الكل';
    });
  }

  List<String> _resultLines() {
    final items = _result;
    final total = items.fold<int>(0, (sum, item) => sum + item.amount);
    final byType = <String, int>{};
    for (final item in items) {
      byType[item.type] = (byType[item.type] ?? 0) + 1;
    }
    return [
      'القسم: $_moduleLabel',
      if (_types.isNotEmpty) 'الأنواع: ${_types.join('، ')}',
      if (_from != null) 'من: ${_formatDate(_from!)}',
      if (_to != null) 'إلى: ${_formatDate(_to!)}',
      'الحالة: $_status',
      'عدد العناصر: ${items.length}',
      if (total > 0) 'الإجمالي: $total ${AppSettings.currencySuffix}',
      '',
      for (final entry in byType.entries) '${entry.key}: ${entry.value}',
      '',
      for (final item in items)
        '${item.title}${item.date == null ? '' : ' — ${_formatDate(item.date!)}'}'
            '${item.amount == 0 ? '' : ' — ${item.amount} ${AppSettings.currencySuffix}'}'
            '${item.status.isEmpty ? '' : ' (${item.status})'}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _errorView()
              : _showResult
              ? _resultView()
              : _stepsView(),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE1E8F0))),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('close-global-summary'),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              _showResult ? 'نتيجة الملخص' : 'الملخص الشامل',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: _showResult
                ? IconButton(
                    key: const ValueKey('global-summary-back'),
                    tooltip: 'تعديل الاختيار',
                    onPressed: () => setState(() => _showResult = false),
                    icon: const Icon(Icons.tune_rounded),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 34, color: AppTheme.muted),
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: AppTheme.emptyText),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _stepsView() {
    final typeOptions = _typeOptions;
    final statusOptions = _statusOptions;
    return ListView(
      key: const ValueKey('global-summary-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _stepTitle(1, 'القسم', enabled: true),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final module in _modules)
              _choice(
                label: module.label,
                icon: module.icon,
                color: module.color,
                selected: _module == module.key,
                onTap: () => setState(() {
                  _module = module.key;
                  _types.clear();
                  _from = null;
                  _to = null;
                  _status = 'الكل';
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _stepTitle(2, 'النوع داخل القسم', enabled: _module != null),
        const SizedBox(height: 8),
        if (_module == null)
          const _StepHint('اختر القسم أولًا.')
        else if (typeOptions.isEmpty)
          const _StepHint('لا توجد سجلات في هذا القسم بعد.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in typeOptions)
                _choice(
                  label:
                      '$type (${_moduleItems.where((item) => item.type == type).length})',
                  color: _accent,
                  selected: _types.contains(type),
                  onTap: () => setState(() {
                    if (_types.contains(type)) {
                      _types.remove(type);
                    } else {
                      _types.add(type);
                    }
                    _status = 'الكل';
                  }),
                ),
            ],
          ),
        if (_module != null && typeOptions.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _StepHint('بلا اختيار = كل الأنواع.'),
        ],
        const SizedBox(height: 18),
        _stepTitle(3, 'الفترة', enabled: _module != null),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _module == null ? null : () => _pickDate(isFrom: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  _from == null ? 'من تاريخ' : 'من: ${_formatDate(_from!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _module == null
                    ? null
                    : () => _pickDate(isFrom: false),
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(
                  _to == null ? 'إلى تاريخ' : 'إلى: ${_formatDate(_to!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (_from != null || _to != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _from = null;
                _to = null;
                _status = 'الكل';
              }),
              icon: const Icon(Icons.event_busy_outlined, size: 16),
              label: const Text('مسح الفترة'),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _stepTitle(4, 'الحالة', enabled: _module != null),
        const SizedBox(height: 8),
        if (_module == null)
          const _StepHint('اختر القسم أولًا.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in statusOptions)
                _choice(
                  label: status,
                  color: _accent,
                  selected: _status == status,
                  onTap: () => setState(() => _status = status),
                ),
            ],
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const ValueKey('global-summary-show'),
          onPressed: _module == null
              ? null
              : () => setState(() => _showResult = true),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(
            _module == null
                ? 'اختر القسم أولًا'
                : 'عرض الملخص (${_result.length})',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final items = _result;
    final total = items.fold<int>(0, (sum, item) => sum + item.amount);
    final byType = <String, int>{};
    for (final item in items) {
      byType[item.type] = (byType[item.type] ?? 0) + 1;
    }
    final overdue = items.where((item) => item.isOverdue).length;
    final dueSoon = items.where((item) => item.isDueSoon).length;

    return ListView(
      key: const ValueKey('global-summary-result'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in [
              _moduleLabel,
              if (_types.isNotEmpty) _types.join('، '),
              if (_from != null) 'من ${_formatDate(_from!)}',
              if (_to != null) 'إلى ${_formatDate(_to!)}',
              if (_status != 'الكل') _status,
            ])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _resultCard(
          title: 'إجمالي النتيجة',
          rows: [
            ('عدد العناصر', '${items.length}'),
            if (total > 0)
              ('الإجمالي المالي', '$total ${AppSettings.currencySuffix}'),
            if (overdue > 0) ('متأخرة', '$overdue'),
            if (dueSoon > 0) ('قريبة الاستحقاق', '$dueSoon'),
          ],
        ),
        if (byType.length > 1) ...[
          const SizedBox(height: 10),
          _resultCard(
            title: 'التوزيع حسب النوع',
            rows: [
              for (final entry in byType.entries) (entry.key, '${entry.value}'),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            child: Text(
              'لا توجد عناصر مطابقة لهذا الاختيار.',
              style: AppTheme.emptyText,
            ),
          )
        else
          _resultCard(
            title: 'العناصر (${items.length})',
            rows: [
              for (final item in items.take(60))
                (
                  item.title.isEmpty ? 'بلا عنوان' : item.title,
                  [
                    if (item.date != null) _formatDate(item.date!),
                    if (item.amount != 0)
                      '${item.amount} ${AppSettings.currencySuffix}',
                    if (item.status.isNotEmpty) item.status,
                  ].join(' · '),
                ),
            ],
          ),
        if (items.length > 60) ...[
          const SizedBox(height: 6),
          Text(
            'عُرضت أول ٦٠ عنصرًا، والإرسال يشمل الجميع.',
            style: AppTheme.emptyText,
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('send-selected-summary'),
          onPressed: () =>
              widget.onShare('ملخص: $_moduleLabel', _resultLines(), false),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('إرسال كنص'),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('send-selected-summary-pdf'),
          onPressed: () =>
              widget.onShare('ملخص: $_moduleLabel', _resultLines(), true),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('إرسال PDF'),
        ),
      ],
    );
  }

  Widget _resultCard({
    required String title,
    required List<(String, String)> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.body,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.$2,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepTitle(int index, String text, {required bool enabled}) {
    final color = enabled ? AppTheme.title : AppTheme.muted;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? _accent : AppTheme.line,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: enabled ? Colors.white : AppTheme.muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _choice({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? color : AppTheme.title,
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

class _StepHint extends StatelessWidget {
  const _StepHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: AppTheme.emptyText),
    );
  }
}
