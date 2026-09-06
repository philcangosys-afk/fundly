import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';

import '../../data/app_settings.dart';
import '../../data/home_summary_service.dart';
import '../../data/scope_catalog.dart';
import 'app_design.dart';

/// اختيار موحّد لصفحات الملخص الشامل والتقارير والأرشيف، بالتسلسل نفسه:
/// بحث ← القسم ← الأقسام المطلوب إظهارها ← الأنواع ← التصفية ← التاريخ ←
/// العنوان ← (مسح الكل / تطبيق).
class ScopeSelection {
  ScopeSelection({
    this.query = '',
    this.scope = ScopeCatalog.general,
    Set<String>? sections,
    Set<String>? types,
    this.status = ScopeCatalog.all,
    this.person = ScopeCatalog.all,
    this.amountRange = ScopeCatalog.all,
    this.payment = ScopeCatalog.all,
    this.from,
    this.to,
    this.dateShortcut,
    this.title = '',
  }) : sections = sections ?? <String>{},
       types = types ?? <String>{};

  String query;
  String scope;
  final Set<String> sections;
  final Set<String> types;
  String status;
  String person;
  String amountRange;
  String payment;
  DateTime? from;
  DateTime? to;
  String? dateShortcut;
  String title;

  ScopeSelection copy() => ScopeSelection(
    query: query,
    scope: scope,
    sections: {...sections},
    types: {...types},
    status: status,
    person: person,
    amountRange: amountRange,
    payment: payment,
    from: from,
    to: to,
    dateShortcut: dateShortcut,
    title: title,
  );

  void clear() {
    query = '';
    scope = ScopeCatalog.general;
    sections.clear();
    types.clear();
    status = ScopeCatalog.all;
    person = ScopeCatalog.all;
    amountRange = ScopeCatalog.all;
    payment = ScopeCatalog.all;
    from = null;
    to = null;
    dateShortcut = null;
    title = '';
  }

  /// هل يطابق هذا العنصر كل ما اختاره المستخدم؟
  bool matches(SummaryItem item) {
    if (scope != ScopeCatalog.general && item.scope != scope) return false;
    if (sections.isNotEmpty && !sections.contains(item.section)) return false;
    if (types.isNotEmpty && !types.contains(item.type)) return false;

    if (status != ScopeCatalog.all) {
      switch (status) {
        case 'متأخرة':
          if (!item.isOverdue) return false;
        case 'قريبة الاستحقاق':
          if (!item.isDueSoon) return false;
        default:
          if (item.status != status) return false;
      }
    }

    if (person != ScopeCatalog.all && item.person != person) return false;
    if (payment != ScopeCatalog.all && item.payment != payment) return false;

    if (amountRange != ScopeCatalog.all) {
      final amount = item.amount;
      switch (amountRange) {
        case 'بلا مبلغ':
          if (amount != 0) return false;
        case 'أقل من ١٠٠٠':
          if (amount <= 0 || amount >= 1000) return false;
        case '١٠٠٠ - ٥٠٠٠':
          if (amount < 1000 || amount > 5000) return false;
        case 'أكثر من ٥٠٠٠':
          if (amount <= 5000) return false;
      }
    }

    if (from != null || to != null) {
      final date = item.date ?? item.createdAt;
      if (date == null) return false;
      if (from != null && date.isBefore(from!)) return false;
      if (to != null && date.isAfter(to!)) return false;
    }

    if (query.trim().isNotEmpty) {
      final q = query.trim();
      final haystack = [
        item.title,
        item.type,
        item.section,
        item.scope,
        item.person,
        item.status,
      ].join(' ');
      if (!haystack.contains(q)) return false;
    }
    return true;
  }

  /// شرائح توضّح الاختيار الحالي (تُعرض فوق النتيجة وفي بطاقة التقرير).
  List<String> chips() => [
    scope,
    if (sections.isNotEmpty) sections.join('، '),
    if (types.isNotEmpty) types.join('، '),
    if (status != ScopeCatalog.all) 'الحالة: $status',
    if (person != ScopeCatalog.all) 'الأفراد والجهات: $person',
    if (amountRange != ScopeCatalog.all) 'المبلغ: $amountRange',
    if (payment != ScopeCatalog.all) 'طريقة الدفع: $payment',
    if (dateShortcut != null) dateShortcut!,
    if (dateShortcut == null && from != null) 'من ${_fmt(from!)}',
    if (dateShortcut == null && to != null) 'إلى ${_fmt(to!)}',
    if (query.trim().isNotEmpty) 'بحث: ${query.trim()}',
  ];

  Map<String, dynamic> toMap() => {
    'query': query,
    'scope': scope,
    'sections': sections.toList(),
    'types': types.toList(),
    'status': status,
    'person': person,
    'amountRange': amountRange,
    'payment': payment,
    'from': from?.toIso8601String(),
    'to': to?.toIso8601String(),
    'dateShortcut': dateShortcut,
    'title': title,
  };

  factory ScopeSelection.fromMap(Map<String, dynamic> map) => ScopeSelection(
    query: (map['query'] ?? '').toString(),
    scope: (map['scope'] ?? ScopeCatalog.general).toString(),
    sections: (map['sections'] as List? ?? const [])
        .map((e) => e.toString())
        .toSet(),
    types: (map['types'] as List? ?? const [])
        .map((e) => e.toString())
        .toSet(),
    status: (map['status'] ?? ScopeCatalog.all).toString(),
    person: (map['person'] ?? ScopeCatalog.all).toString(),
    amountRange: (map['amountRange'] ?? ScopeCatalog.all).toString(),
    payment: (map['payment'] ?? ScopeCatalog.all).toString(),
    from: map['from'] == null ? null : DateTime.tryParse('${map['from']}'),
    to: map['to'] == null ? null : DateTime.tryParse('${map['to']}'),
    dateShortcut: map['dateShortcut']?.toString(),
    title: (map['title'] ?? '').toString(),
  );

  static String _fmt(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';
}

/// يفتح نافذة الاختيار ويعيد النتيجة عند الضغط على "تطبيق" (أو null عند
/// الإلغاء). [kind] يظهر في العناوين: تقرير / أرشيف / ملخص.
Future<ScopeSelection?> showScopeBuilderSheet({
  required BuildContext context,
  required String kind,
  required Color accent,
  required List<SummaryItem> items,
  ScopeSelection? initial,
}) {
  return showModalBottomSheet<ScopeSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: _ScopeBuilder(
        kind: kind,
        accent: accent,
        items: items,
        initial: initial?.copy() ?? ScopeSelection(),
      ),
    ),
  );
}

class _ScopeBuilder extends StatefulWidget {
  const _ScopeBuilder({
    required this.kind,
    required this.accent,
    required this.items,
    required this.initial,
  });

  final String kind;
  final Color accent;
  final List<SummaryItem> items;
  final ScopeSelection initial;

  @override
  State<_ScopeBuilder> createState() => _ScopeBuilderState();
}

class _ScopeBuilderState extends State<_ScopeBuilder> {
  late ScopeSelection _draft = widget.initial;
  late final TextEditingController _queryCtrl = TextEditingController(
    text: _draft.query,
  );
  late final TextEditingController _titleCtrl = TextEditingController(
    text: _draft.title,
  );
  var _resetEpoch = 0;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  List<SummaryItem> get _scopeItems => _draft.scope == ScopeCatalog.general
      ? widget.items
      : widget.items
            .where((item) => item.scope == _draft.scope)
            .toList(growable: false);

  /// السجلات بعد تطبيق القسم + الأقسام + التصنيف المختار — منها تُشتق
  /// بقية القوائم (الحالة، الأفراد، طريقة الدفع) فتعرض فقط ما له علاقة
  /// فعلية بما اختير في الأعلى.
  List<SummaryItem> get _narrowedItems => _scopeItems
      .where(
        (item) =>
            (_draft.sections.isEmpty ||
                _draft.sections.contains(item.section)) &&
            (_draft.types.isEmpty || _draft.types.contains(item.type)),
      )
      .toList(growable: false);

  /// هل لهذا القسم مستوى "أقسام" أصلًا؟ العقارات والأنشطة والمعدات لا —
  /// تصنيفها يعرض أنواع الأصل مباشرة.
  bool get _scopeHasSections =>
      (ScopeCatalog.sections[_draft.scope] ?? const []).isNotEmpty;

  /// الأقسام المعرَّفة للقسم المختار كاملة كما في المتطلبات.
  List<String> get _sectionOptions =>
      [...?ScopeCatalog.sections[_draft.scope]];

  /// خيارات "التصنيف": أنواع القسم الفرعي المختار (المالية → المصروفات
  /// الشخصية، إيراد...) — وللأقسام بلا مستوى أقسام (العقارات...) الأنواع
  /// الحقيقية من السجلات مباشرة (عمارة، فيلا، شقة...).
  List<String> get _typeOptions {
    if (_draft.scope == ScopeCatalog.general) {
      final defined = <String>[
        for (final table in ScopeCatalog.typesByScope.values)
          for (final list in table.values) ...list,
      ];
      final present = widget.items
          .map((item) => item.type)
          .where((value) => value.trim().isNotEmpty)
          .toSet();
      return [
        ScopeCatalog.all,
        ...defined,
        ...present.where((value) => !defined.contains(value)),
      ];
    }
    final sections = _draft.sections.isEmpty
        ? _sectionOptions
        : _draft.sections.toList(growable: false);
    final defined = <String>[
      for (final section in sections)
        ...ScopeCatalog.typesFor(_draft.scope, section),
    ];
    final present = _scopeItems
        .where(
          (item) =>
              _draft.sections.isEmpty || _draft.sections.contains(item.section),
        )
        .map((item) => item.type)
        .where((value) => value.trim().isNotEmpty)
        .toSet();
    return [
      ScopeCatalog.all,
      ...defined,
      ...present.where((value) => !defined.contains(value)),
    ];
  }

  /// الحالات: قائمة القسم المعرَّفة كاملة (أكثر من مجرد ما صادف وجوده)
  /// مدموجة مع الموجود فعلًا في السجلات المطابقة للاختيار الأعلى.
  List<String> get _statusOptions {
    final defined = _draft.scope == ScopeCatalog.general
        ? <String>[
            for (final list in ScopeCatalog.statusesByScope.values) ...list,
          ]
        : ScopeCatalog.statusesFor(_draft.scope);
    final present = _narrowedItems
        .map((item) => item.status)
        .where((value) => value.trim().isNotEmpty)
        .toSet();
    return [
      ScopeCatalog.all,
      ...defined,
      ...present.where((value) => !defined.contains(value)),
    ];
  }

  /// الأفراد والجهات المرتبطون فعلًا بالسجلات المطابقة لما اختير أعلاه —
  /// اختيار "المالية" يعرض أصحاب العلاقة بالمالية وحدهم.
  List<String> get _personOptions {
    final present = _narrowedItems
        .map((item) => item.person)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return [ScopeCatalog.all, ...present];
  }

  /// طرق الدفع المعروفة (كاش، تحويل، إيداع...) + الموجود في السجلات.
  List<String> get _paymentOptions {
    final present = _narrowedItems
        .map((item) => item.payment)
        .where((value) => value.trim().isNotEmpty)
        .toSet();
    return [
      ScopeCatalog.all,
      ...ScopeCatalog.paymentMethods,
      ...present.where(
        (value) => !ScopeCatalog.paymentMethods.contains(value),
      ),
    ];
  }

  int get _matchCount => widget.items.where(_draft.matches).length;

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _draft.from : _draft.to) ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _draft.from = picked;
      } else {
        _draft.to = picked;
      }
      _draft.dateShortcut = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 6),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 19, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.kind,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppTr.tr('إغلاق'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                TextField(
                  key: ValueKey('scope-query-$_resetEpoch'),
                  controller: _queryCtrl,
                  onChanged: (value) => setState(() => _draft.query = value),
                  decoration: InputDecoration(
                    hintText: AppTr.tr('البحث بالاسم أو النوع أو التاريخ...'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                _label('اختر:'),
                const SizedBox(height: 8),
                // "عام" مستطيل طويل بعرض الصفحة، ثم بقية الأقسام شبكة.
                _wideChoice(
                  label: ScopeCatalog.general,
                  icon: Icons.public_rounded,
                  selected: _draft.scope == ScopeCatalog.general,
                  onTap: () => _selectScope(ScopeCatalog.general),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scope in ScopeCatalog.scopes.skip(1))
                      _chip(
                        label: scope,
                        selected: _draft.scope == scope,
                        onTap: () => _selectScope(scope),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                // "عام" يعني كل شيء، فلا يُعرض قسم فرعي أصلًا؛ ومع قسم
                // محدد تظهر أقسامه هو، والاختيار واحد في كل مرة: الضغط
                // على "التنظيم والمتابعة" يستبدل "المالية" لا يجتمع معها.
                if (_draft.scope != ScopeCatalog.general &&
                    _scopeHasSections) ...[
                  _label('الأقسام:'),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final section in _sectionOptions)
                          _chip(
                            label:
                                '$section (${_scopeItems.where((i) => i.section == section).length})',
                            selected: _draft.sections.contains(section),
                            onTap: () => setState(() {
                              final wasSelected = _draft.sections.contains(
                                section,
                              );
                              _draft.sections.clear();
                              if (!wasSelected) {
                                _draft.sections.add(section);
                              }
                              _draft.types.clear();
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                ],
                _label('تصفية ${widget.kind}: حدد عناصرك'),
                const SizedBox(height: 8),
                // أزرار بأسهم: كل زر يفتح قائمته المبنية على ما اختير في
                // الأعلى (التصنيف يعرض أنواع الأقسام المختارة، وهكذا).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _filterButton(
                        label: 'التصنيف',
                        value: _draft.types.isEmpty
                            ? ScopeCatalog.all
                            : _draft.types.first,
                        options: _typeOptions,
                        onSelected: (value) => setState(() {
                          _draft.types.clear();
                          if (value != ScopeCatalog.all) {
                            _draft.types.add(value);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _filterButton(
                        label: 'الحالة',
                        value: _statusOptions.contains(_draft.status)
                            ? _draft.status
                            : ScopeCatalog.all,
                        options: _statusOptions,
                        onSelected: (value) =>
                            setState(() => _draft.status = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _filterButton(
                        label: 'الأفراد والجهات',
                        value: _personOptions.contains(_draft.person)
                            ? _draft.person
                            : ScopeCatalog.all,
                        options: _personOptions,
                        onSelected: (value) =>
                            setState(() => _draft.person = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _filterButton(
                        label: 'المبلغ',
                        value: _draft.amountRange,
                        options: ScopeCatalog.amountRanges,
                        onSelected: (value) =>
                            setState(() => _draft.amountRange = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _filterButton(
                        label: 'طريقة الدفع',
                        value: _paymentOptions.contains(_draft.payment)
                            ? _draft.payment
                            : ScopeCatalog.all,
                        options: _paymentOptions,
                        onSelected: (value) =>
                            setState(() => _draft.payment = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
                const SizedBox(height: 18),
                _label('التاريخ:'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: true),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _draft.from == null
                              ? 'من'
                              : 'من: ${ScopeSelection._fmt(_draft.from!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: false),
                        icon: const Icon(Icons.event_outlined, size: 16),
                        label: Text(
                          _draft.to == null
                              ? 'إلى'
                              : 'إلى: ${ScopeSelection._fmt(_draft.to!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // "الفترة" بجانبهما بسهم: يعرض الاختصارات (اليوم،
                    // هذا الأسبوع، قبل شهر...).
                    Expanded(child: _buildPeriodButton()),
                  ],
                ),
                // عند تحديد "من" و"إلى" يظهر طول المدة بالأيام.
                if (_draft.from != null && _draft.to != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'المدة: ${_draft.to!.difference(_draft.from!).inDays + 1} يومًا'
                    ' (${ScopeSelection._fmt(_draft.from!)} ← ${ScopeSelection._fmt(_draft.to!)})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF047857),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _label('عنوان ${widget.kind}:'),
                const SizedBox(height: 8),
                TextField(
                  key: ValueKey('scope-title-$_resetEpoch'),
                  controller: _titleCtrl,
                  onChanged: (value) => _draft.title = value,
                  decoration: InputDecoration(
                    hintText: AppTr.tr('مثال: ${widget.kind} خاص'),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('scope-clear-all'),
                    onPressed: () => setState(() {
                      _draft.clear();
                      _queryCtrl.clear();
                      _titleCtrl.clear();
                      _resetEpoch++;
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                    label: const Text('مسح الكل'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('scope-apply'),
                    onPressed: () {
                      _draft.title = _titleCtrl.text.trim();
                      _draft.query = _queryCtrl.text.trim();
                      Navigator.pop(context, _draft);
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('تطبيق ($_matchCount)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectScope(String scope) => setState(() {
    _draft.scope = scope;
    _draft.sections.clear();
    _draft.types.clear();
    _draft.status = ScopeCatalog.all;
    _draft.person = ScopeCatalog.all;
    _draft.payment = ScopeCatalog.all;
  });

  Widget _label(String text) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w900,
        color: Color(0xFF24332F),
      ),
    ),
  );


  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = widget.accent;
    return Material(
      color: selected ? accent.withValues(alpha: 0.10) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: selected ? accent : AppTheme.title,
              ),
            ),
          ),
        ),
      ),
    );
  }


  /// زر "الفترة" — اختصارات التاريخ في قائمة منسدلة.
  Widget _buildPeriodButton() {
    return _filterButton(
                  label: 'الفترة',
                  value: _draft.dateShortcut ?? 'بلا فترة محددة',
                  allLabel: 'بلا فترة محددة',
                  options: const ['بلا فترة محددة', ...ScopeCatalog.dateShortcuts],
                  onSelected: (value) => setState(() {
                    if (value == 'بلا فترة محددة') {
                      _draft.dateShortcut = null;
                      _draft.from = null;
                      _draft.to = null;
                      return;
                    }
                    final range = ScopeCatalog.rangeForShortcut(value);
                    _draft.dateShortcut = value;
                    _draft.from = range.$1;
                    _draft.to = range.$2;
                  }),
                );
  }

  /// زر تصفية بسهم: يعرض العنوان والقيمة الحالية، وعند الضغط تفتح قائمته
  /// المبنية على ما اختير في الأعلى.
  Widget _filterButton({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelected,
    String allLabel = ScopeCatalog.all,
  }) {
    final accent = widget.accent;
    final active = value != allLabel;
    final unique = <String>[];
    for (final option in options) {
      if (option.trim().isEmpty) continue;
      if (!unique.contains(option)) unique.add(option);
    }
    if (!unique.contains(allLabel)) {
      unique.insert(0, allLabel);
    }
    return PopupMenuButton<String>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in unique)
          PopupMenuItem<String>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == value
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: option == value ? accent : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.08) : AppTheme.field,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          border: Border.all(
            color: active ? accent : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: active ? accent : AppTheme.title,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 19,
              color: active ? accent : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideChoice({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = widget.accent;
    return Material(
      color: selected ? accent : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rField),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : accent,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : AppTheme.title,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// عرض نتيجة الاختيار بأسلوب تقرير احترافي: ترويسة، بطاقات مؤشرات،
/// توزيع حسب النوع، ثم قائمة عناصر منسّقة بحالة ملوّنة ومبلغ بارز.
class ScopeResultView extends StatelessWidget {
  const ScopeResultView({
    super.key,
    required this.selection,
    required this.items,
    required this.accent,
  });

  final ScopeSelection selection;
  final List<SummaryItem> items;
  final Color accent;

  Color _statusColor(SummaryItem item) {
    if (item.isOverdue) return const Color(0xFFDC2626);
    if (item.isDueSoon) return const Color(0xFFD97706);
    if (const {'منتهية', 'منتهي', 'ملغاة', 'متوقف'}.contains(item.status)) {
      return const Color(0xFF64748B);
    }
    return const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, item) => sum + item.amount);
    final byType = <String, int>{};
    for (final item in items) {
      byType[item.type] = (byType[item.type] ?? 0) + 1;
    }
    final overdue = items.where((item) => item.isOverdue).length;
    final dueSoon = items.where((item) => item.isDueSoon).length;
    final maxTypeCount = byType.values.fold<int>(1, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ترويسة النطاق والمعايير المختارة.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
            ),
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.insights_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selection.title.trim().isEmpty
                          ? selection.scope
                          : selection.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in selection.chips())
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // مؤشرات سريعة: عناصر / إجمالي / متأخرة / قريبة.
        Row(
          children: [
            _stat('العناصر', '${items.length}', accent),
            const SizedBox(width: 8),
            _stat(
              'الإجمالي',
              total == 0 ? '—' : '$total ${AppSettings.currencySuffix}',
              const Color(0xFF0F6AA8),
            ),
            const SizedBox(width: 8),
            _stat('متأخرة', '$overdue', const Color(0xFFDC2626)),
            const SizedBox(width: 8),
            _stat('قريبة', '$dueSoon', const Color(0xFFD97706)),
          ],
        ),
        if (byType.length > 1) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'التوزيع حسب النوع',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in byType.entries) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.body,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // شريط نسبة بسيط يوضح ثقل كل نوع.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value / maxTypeCount,
                      minHeight: 5,
                      backgroundColor: Colors.white,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        accent.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  size: 30,
                  color: AppTheme.muted,
                ),
                const SizedBox(height: 8),
                Text(
                  'لا توجد عناصر مطابقة لهذا الاختيار.',
                  textAlign: TextAlign.center,
                  style: AppTheme.emptyText,
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, bottom: 8),
            child: Text(
              'العناصر (${items.length})',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
          ),
          for (final item in items.take(80)) ...[
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rInner),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? 'بلا عنوان' : item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            item.type,
                            if (item.date != null)
                              ScopeSelection._fmt(item.date!),
                            if (item.person.isNotEmpty) item.person,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (item.amount != 0)
                        Text(
                          '${item.amount} ${AppSettings.currencySuffix}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                      if (item.status.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(item).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.status,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: _statusColor(item),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (items.length > 80)
            Text(
              'عُرضت أول ٨٠ عنصرًا، والإرسال يشمل الجميع.',
              style: AppTheme.emptyText,
            ),
        ],
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// أسطر نصية للمشاركة (نص أو PDF) من نتيجة الاختيار.
List<String> scopeResultLines(
  ScopeSelection selection,
  List<SummaryItem> items,
) {
  final total = items.fold<int>(0, (sum, item) => sum + item.amount);
  return [
    ...selection.chips(),
    'عدد العناصر: ${items.length}',
    if (total > 0) 'الإجمالي: $total ${AppSettings.currencySuffix}',
    '',
    for (final item in items)
      '${item.title}'
          '${item.date == null ? '' : ' — ${ScopeSelection._fmt(item.date!)}'}'
          '${item.amount == 0 ? '' : ' — ${item.amount} ${AppSettings.currencySuffix}'}'
          '${item.status.isEmpty ? '' : ' (${item.status})'}',
  ];
}
