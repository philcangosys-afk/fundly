import 'package:flutter/material.dart' hide Text, Align;

import '../data/app_settings.dart';
import '../data/lease_contract_data.dart';
import '../data/people_directory_store.dart';
import '../data/project_assets_repository.dart';
import '../data/template_print.dart' show PrintSection, buildRecordPdf;
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import 'rent_payments_view.dart';
import 'template_print_screen.dart';

/// حدث واحد في «السجل» أو «السجل التاريخي» للعقار أو النشاط أو المركبة.
class AssetRecordEvent {
  const AssetRecordEvent({
    required this.title,
    this.date,
    this.detail = '',
    this.unit = '',
    this.icon = Icons.history_rounded,
    this.kind = kindLog,
    this.amount = 0,
    this.fields = const <String, String>{},
  });

  /// كل ما سُجّل في البند (صيانة، مستند، متابعة...) — يظهر مفصّلًا في
  /// صفحة عنصر السجل التاريخي وفي طباعتها.
  final Map<String, String> fields;

  static const kindLog = 'log';
  static const kindContract = 'contract';
  static const kindPayment = 'payment';
  static const kindDeposit = 'deposit';
  static const kindDue = 'due';
  static const kindMaintenance = 'maintenance';
  static const kindDocument = 'document';
  static const kindFollow = 'follow';
  static const kindMoney = 'money';

  final DateTime? date;
  final String title;
  final String detail;
  final String unit;
  final IconData icon;
  final String kind;
  final double amount;
}

/// عنصر في «السجل التاريخي» للعقار: العقار نفسه، أو وحدة أُلغي عقدها أو
/// أُرشفت. يُعرض مستطيلًا صغيرًا (النوع / الاسم وتاريخ الإلغاء أو الأرشفة)،
/// والضغط عليه يفتح صفحته كاملة.
class AssetArchiveItem {
  const AssetArchiveItem({
    required this.name,
    required this.type,
    required this.cancelled,
    this.date,
    this.unitName = '',
    this.contractId,
    this.isAsset = false,
  });

  /// اسم الوحدة (أو العقار).
  final String name;

  /// نوع الوحدة (أو نوع العقار).
  final String type;

  /// true: ملغي. false: مؤرشف.
  final bool cancelled;

  /// تاريخ الإلغاء أو الأرشفة.
  final DateTime? date;

  /// اسم الوحدة في العقود والحركات ('' للعقار كله).
  final String unitName;

  /// العقد الملغى بعينه (للإلغاء)؛ null: كل عقود الوحدة.
  final String? contractId;

  /// العقار كله (أُلغي أو أُرشف).
  final bool isAsset;

  String get label =>
      type.trim().isEmpty ? name : '${type.trim()} / $name';
}

/// عقود العنصر: العقد الملغى وحده، أو كل عقود الوحدة، أو كل عقود العقار.
List<PropertyUnitContractRecord> archiveContractsOf(
  AssetArchiveItem item,
  List<PropertyUnitContractRecord> all,
) {
  if (item.isAsset) return List.of(all);
  final id = item.contractId;
  if (id != null) return all.where((c) => c.id == id).toList();
  return all
      .where((c) => (c.unitName ?? '').trim() == item.unitName.trim())
      .toList();
}

/// دفعات العنصر بنفس منطق عقوده.
List<RentPaymentEntry> archivePaymentsOf(
  AssetArchiveItem item,
  List<RentPaymentEntry> all,
) {
  if (item.isAsset) return List.of(all);
  final id = item.contractId;
  if (id != null) return all.where((p) => p.contract.id == id).toList();
  final unit = item.unitName.trim();
  return all
      .where(
        (p) =>
            p.unitName.trim() == unit ||
            (p.contract.unitName ?? '').trim() == unit,
      )
      .toList();
}

/// المتبقي الذي يحتاج تسوية: غير مسدد، ولم تُسوَّ مبالغ عقده، ولم يسقط
/// بإغلاق العقد (استحقاقه بعد تاريخ الإلغاء).
double archiveUnsettledOf(List<RentPaymentEntry> payments) {
  var left = 0.0;
  for (final p in payments) {
    final rest = payRemaining(p.payment);
    if (rest <= 0) continue;
    if (LeaseContractData.isSettled(p.contract.notes)) continue;
    if (paymentWaivedByClosure(p.contract, p.payment)) continue;
    left += rest;
  }
  return left;
}

/// فئة العنصر: «ملغي (يحتاج تسوية)»، «مؤرشف (مسوّى)»...
String archiveCategoryOf(AssetArchiveItem item, bool needsSettlement) =>
    '${item.cancelled ? 'ملغي' : 'مؤرشف'} '
    '(${needsSettlement ? 'يحتاج تسوية' : 'مسوّى'})';

/// «السجل»: كل حركة بتاريخها. «السجل التاريخي»: صفحة أرشيف بنية غير
/// نشطة — لكل وحدة من أول تسجيل إلى اليوم: العقود (ومنها الملغاة)،
/// التأمينات السابقة والجديدة ومجموعها، المحصّل والمتبقي، مع تسجيل دفعة
/// ولو بعد إلغاء العقد. لا حذف ولا أرشفة من هنا.
class AssetRecordsScreen extends StatefulWidget {
  const AssetRecordsScreen({
    super.key,
    required this.assetTitle,
    required this.history,
    required this.events,
    required this.payments,
    required this.contracts,
    required this.units,
    this.repository,
    this.reload,
    this.accent = const Color(0xFF0A5A50),
    this.unitLabel = 'الوحدة',
    this.currentStatus,
    this.archiveItems,
    this.assetType = '',
    this.unitDetails,
  });

  /// بيانات الوحدة نفسها (النوع، الرقم، المساحة، العدادات...) وقوائمها
  /// المسجّلة فيها (الصيانة، المرافق، الملاحظات...) — لصفحة عنصر السجل.
  final ({
    List<(String, String)> info,
    List<(String, List<Map<String, String>>)> lists,
  })
  Function(String unitName)?
  unitDetails;

  /// العقار: «السجل التاريخي» يعرض ما أُلغي أو أُرشف فقط (العقار والوحدات)
  /// مستطيلات صغيرة، بفلتري الوحدة والفئة. null: الشكل السابق.
  final List<AssetArchiveItem> Function()? archiveItems;

  /// نوع العقار — أعلى الصفحة «نوع العقار / اسم العقار».
  final String assetType;

  /// الحالة الآن لكل وحدة/مركبة («مؤجرة — فلان»، «شاغرة»، «صيانة»).
  final String Function(String unit)? currentStatus;

  final String assetTitle;

  /// true: «السجل التاريخي» (صفحة بنية). false: «السجل».
  final bool history;

  /// تُقرأ من جديد بعد كل تسجيل دفعة.
  final List<AssetRecordEvent> Function() events;
  final List<RentPaymentEntry> Function() payments;
  final List<PropertyUnitContractRecord> Function() contracts;
  final List<String> units;

  final ProjectAssetsRepository? repository;

  /// يعيد تحميل الدفعات في الشاشة الأم بعد السداد.
  final Future<void> Function()? reload;

  final Color accent;

  /// «الوحدة» للعقار، «المركبة» أو «النشاط» لغيرهما.
  final String unitLabel;

  @override
  State<AssetRecordsScreen> createState() => _AssetRecordsScreenState();
}

class _AssetRecordsScreenState extends State<AssetRecordsScreen> {
  static const _brown = Color(0xFF4E342E);
  static const _brownDark = Color(0xFF3E2723);
  static const _brownCard = Color(0xFFF6EFEA);
  static const _brownAccent = Color(0xFF8D6E63);

  static const _kindAll = 'الكل';
  static const _kindDues = 'مستحقات';
  static const _kindFollow = 'متابعة وتخطيط';

  final _query = TextEditingController();
  String _unit = '';

  /// فلتر الفئة في السجل التاريخي للعقار ('' = الكل).
  String _category = '';

  static const _archiveCategories = <String>[
    'مؤرشف (يحتاج تسوية)',
    'مؤرشف (مسوّى)',
    'ملغي (يحتاج تسوية)',
    'ملغي (مسوّى)',
  ];

  bool get _archiveMode => _history && widget.archiveItems != null;

  String get _assetHeading => [
    if (widget.assetType.trim().isNotEmpty) widget.assetType.trim(),
    widget.assetTitle,
  ].join(' / ');
  DateTime? _from;
  DateTime? _to;
  String _kind = _kindAll;

  bool get _history => widget.history;
  Color get _accent => _history ? _brownAccent : widget.accent;
  Color get _cardColor => _history ? _brownCard : AppTheme.surface;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _date(DateTime? d) => d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  String _money(double value) {
    final fixed = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final text = parts.length > 1 ? '$digits.${parts[1]}' : digits;
    return '$text ${AppSettings.currencySuffix}';
  }

  bool _textHas(String text, String query) =>
      text.toLowerCase().contains(query.toLowerCase());

  bool _inRange(DateTime? date) {
    if (_from == null && _to == null) return true;
    if (date == null) return false;
    final day = DateUtils.dateOnly(date);
    if (_from != null && day.isBefore(DateUtils.dateOnly(_from!))) return false;
    if (_to != null && day.isAfter(DateUtils.dateOnly(_to!))) return false;
    return true;
  }

  bool _unitMatches(String unit) {
    if (_unit.isNotEmpty && unit.trim() != _unit) return false;
    final q = _query.text.trim();
    if (q.isEmpty || !_history) return true;
    return _textHas(unit, q);
  }

  List<AssetRecordEvent> get _shownEvents {
    final q = _query.text.trim();
    final list = widget.events().where((e) {
      if (_unit.isNotEmpty && e.unit.trim() != _unit) return false;
      if (!_inRange(e.date)) return false;
      if (_kind == _kindDues && e.kind != AssetRecordEvent.kindDue) {
        return false;
      }
      if (_kind == _kindFollow && e.kind != AssetRecordEvent.kindFollow) {
        return false;
      }
      if (q.isEmpty) return true;
      if (_history) return _textHas(e.unit, q);
      return _textHas(e.title, q) ||
          _textHas(e.detail, q) ||
          _textHas(e.unit, q);
    }).toList();
    list.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  /// الوحدات الظاهرة في السجل التاريخي حسب البحث والاختيار.
  List<String> get _shownUnits {
    final names = <String>[
      for (final u in widget.units)
        if (u.trim().isNotEmpty) u.trim(),
      for (final c in widget.contracts())
        if ((c.unitName ?? '').trim().isNotEmpty) c.unitName!.trim(),
    ];
    final unique = <String>[];
    for (final n in names) {
      if (!unique.contains(n)) unique.add(n);
    }
    return unique.where(_unitMatches).toList();
  }

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2070),
    );
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
  }

  Future<void> _payUnit(List<RentPaymentEntry> outstanding) async {
    final repo = widget.repository;
    if (repo == null || outstanding.isEmpty) return;
    final changed = await openPaymentSettlePage(
      context: context,
      repository: repo,
      entries: outstanding,
      showUnitName: true,
    );
    if (!changed) return;
    await widget.reload?.call();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسجيل الدفعة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _history ? 'السجل التاريخي' : 'السجل';
    final events = _shownEvents;
    final units = _history ? _shownUnits : const <String>[];
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: _history ? _brown : AppTheme.page,
        appBar: AppBar(
          backgroundColor: _history ? _brownDark : Colors.white,
          foregroundColor: _history ? Colors.white : AppTheme.title,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: _history ? 18 : 16,
                  fontWeight: FontWeight.w900,
                  color: _history ? Colors.white : AppTheme.title,
                ),
              ),
              Text(
                _assetHeading,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _history ? Colors.white70 : AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
        body: _archiveMode
            ? ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                children: [
                  _archiveBanner(),
                  _archiveFilters(),
                  const SizedBox(height: 12),
                  ..._archiveList(),
                ],
              )
            : ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            if (_history) _archiveBanner(),
            _filters(),
            const SizedBox(height: 12),
            if (_history) ...[
              if (units.isEmpty)
                _emptyCard('لا توجد نتائج مطابقة')
              else
                for (final unit in units) _unitCard(unit),
              const SizedBox(height: 6),
              _sectionTitle('كل الحركات'),
            ],
            if (events.isEmpty)
              _emptyCard('لا توجد حركات مطابقة')
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < events.length; i++) ...[
                      _eventRow(events[i]),
                      if (i < events.length - 1)
                        const Divider(height: 1, color: AppTheme.hairline),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _archiveBanner() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _brownDark,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      border: Border.all(color: _brownAccent),
    ),
    child: Row(
      children: [
        const Icon(Icons.inventory_2_outlined, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _archiveMode
                ? switch (widget.unitLabel) {
                    'المركبة' =>
                      'السجل التاريخي للمركبة: تُحفظ فيه جميع السجلات '
                          'السابقة، وتستمر متابعة المستحقات المالية وغيرها حتى '
                          'تسويتها.',
                    'الوحدة' =>
                      'السجل التاريخي للوحدة: تُحفظ فيه جميع السجلات السابقة، '
                          'وتستمر متابعة المستحقات المالية وغيرها حتى تسويتها.',
                    _ =>
                      'السجل التاريخي للنشاط: تُحفظ فيه جميع السجلات '
                          'السابقة، وتستمر متابعة المستحقات المالية وغيرها حتى '
                          'تسويتها.',
                  }
                : 'صفحة أرشيف غير نشطة: كل ما سُجّل منذ البداية، ولا يُحذف '
                      'منها شيء. المستحقات تُتابَع وتُسدَّد من هنا.',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );

  // ================= السجل التاريخي للعقار =================

  /// العناصر بعد البحث والوحدة والفئة والتاريخ، الأحدث أولًا.
  List<(AssetArchiveItem, double)> get _shownArchive {
    final payments = widget.payments();
    final q = _query.text.trim();
    final out = <(AssetArchiveItem, double)>[];
    for (final item in widget.archiveItems!()) {
      if (_unit.isNotEmpty && _archiveUnitName(item) != _unit) continue;
      if (q.isNotEmpty && !_textHas(item.label, q)) continue;
      if (!_inRange(item.date)) continue;
      final left = archiveUnsettledOf(archivePaymentsOf(item, payments));
      if (_category.isNotEmpty &&
          archiveCategoryOf(item, left > 0) != _category) {
        continue;
      }
      out.add((item, left));
    }
    out.sort((a, b) {
      final da = a.$1.date;
      final db = b.$1.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return out;
  }

  String _archiveUnitName(AssetArchiveItem item) =>
      (item.isAsset ? item.name : item.unitName).trim();

  List<Widget> _archiveList() {
    final items = _shownArchive;
    if (items.isEmpty) {
      return [
        _emptyCard(
          widget.archiveItems!().isEmpty
              ? 'لا يوجد ما أُلغي أو أُرشف بعد'
              : 'لا توجد نتائج مطابقة',
        ),
      ];
    }
    return [for (final (item, left) in items) _archiveRow(item, left)];
  }

  InputDecoration _filterDecoration(String label) => InputDecoration(
    labelText: AppTr.tr(label),
    labelStyle: const TextStyle(fontSize: 11),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  /// صندوق فلاتر صغير: البحث، ثم الوحدة والفئة في سطر، ثم التاريخان.
  Widget _archiveFilters() {
    final names = <String>[];
    for (final item in widget.archiveItems!()) {
      final name = _archiveUnitName(item);
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    if (_unit.isNotEmpty && !names.contains(_unit)) _unit = '';
    Widget dateButton(bool from) {
      final value = from ? _from : _to;
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pickDate(from),
          onLongPress: () => setState(() => from ? _from = null : _to = null),
          icon: const Icon(Icons.event_rounded, size: 14),
          label: Text(
            value == null
                ? AppTr.tr(from ? 'من تاريخ' : 'إلى تاريخ')
                : _date(value),
            style: const TextStyle(fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            backgroundColor: Colors.white,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: _accent.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    DropdownMenuItem<String> item(String value, String label) =>
        DropdownMenuItem(
          value: value,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 11.5),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: TextField(
              controller: _query,
              textAlign: AppTr.alignEnd,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: AppTr.tr('ابحث عن ${widget.unitLabel}'),
                hintStyle: const TextStyle(fontSize: 11.5),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('archive-unit-$_unit'),
                  initialValue: _unit,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 18,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.title,
                  ),
                  decoration: _filterDecoration(widget.unitLabel),
                  items: [
                    item('', 'الكل'),
                    for (final name in names) item(name, name),
                  ],
                  onChanged: (value) => setState(() => _unit = value ?? ''),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('archive-category-$_category'),
                  initialValue: _category,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 18,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.title,
                  ),
                  decoration: _filterDecoration('الفئة'),
                  items: [
                    item('', 'الكل'),
                    for (final category in _archiveCategories)
                      item(category, category),
                  ],
                  onChanged: (value) =>
                      setState(() => _category = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              dateButton(true),
              const SizedBox(width: 6),
              dateButton(false),
              if (_from != null || _to != null)
                IconButton(
                  tooltip: AppTr.tr('مسح التاريخ'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  icon: Icon(Icons.close_rounded, size: 18, color: _accent),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// مستطيل صغير: النوع / الاسم، وتاريخ الإلغاء أو الأرشفة، وفئته.
  Widget _archiveRow(AssetArchiveItem item, double left) {
    final needs = left > 0;
    final category = archiveCategoryOf(item, needs);
    final color = needs ? AppTheme.danger : const Color(0xFF34A894);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _cardColor,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          onTap: () => _openArchiveItem(item),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(
                color: needs ? AppTheme.danger.withValues(alpha: 0.5) : _accent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.isAsset
                      ? Icons.apartment_rounded
                      : Icons.home_work_outlined,
                  size: 20,
                  color: _accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${AppTr.tr(item.cancelled ? 'تاريخ الإلغاء' : 'تاريخ الأرشفة')}: '
                        '${_date(item.date)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left_rounded, color: _accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openArchiveItem(AssetArchiveItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArchiveItemPage(item: item, screen: widget),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w900,
        color: _history ? Colors.white : AppTheme.title,
      ),
    ),
  );

  Widget _emptyCard(String text) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppTheme.muted,
      ),
    ),
  );

  Widget _filters() {
    final allUnits = <String>[];
    for (final u in [
      ...widget.units,
      for (final c in widget.contracts()) c.unitName ?? '',
    ]) {
      final name = u.trim();
      if (name.isNotEmpty && !allUnits.contains(name)) allUnits.add(name);
    }
    Widget dateButton(bool from) {
      final value = from ? _from : _to;
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pickDate(from),
          onLongPress: () => setState(() => from ? _from = null : _to = null),
          icon: const Icon(Icons.event_rounded, size: 16),
          label: Text(
            value == null
                ? AppTr.tr(from ? 'من تاريخ' : 'إلى تاريخ')
                : _date(value),
            style: const TextStyle(fontSize: 11.5),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            backgroundColor: Colors.white,
            side: BorderSide(color: _accent.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _query,
            textAlign: AppTr.alignEnd,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: AppTr.tr(
                _history ? 'ابحث عن ${widget.unitLabel}' : 'ابحث في السجل',
              ),
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
          if (allUnits.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _unit,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: AppTr.tr(widget.unitLabel),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('الكل')),
                for (final name in allUnits)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) => setState(() => _unit = value ?? ''),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              dateButton(true),
              const SizedBox(width: 8),
              dateButton(false),
              if (_from != null || _to != null)
                IconButton(
                  tooltip: AppTr.tr('مسح التاريخ'),
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                  icon: Icon(Icons.close_rounded, color: _accent),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in const [_kindAll, _kindDues, _kindFollow])
                ChoiceChip(
                  label: Text(kind, style: const TextStyle(fontSize: 11.5)),
                  selected: _kind == kind,
                  selectedColor: _accent.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eventRow(AssetRecordEvent e) {
    final due = e.kind == AssetRecordEvent.kindDue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e.icon, size: 19, color: due ? AppTheme.danger : _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title,
                  ),
                ),
                if (e.detail.isNotEmpty)
                  Text(
                    e.detail,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                Text(
                  [
                    if (e.unit.isNotEmpty) e.unit,
                    e.date == null ? AppTr.tr('بلا تاريخ') : _date(e.date),
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (e.amount > 0.009)
            Text(
              _money(e.amount),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: due ? AppTheme.danger : _accent,
              ),
            ),
        ],
      ),
    );
  }

  /// بطاقة وحدة في السجل التاريخي: عقودها، تأميناتها ومجموعها، المحصّل
  /// والمتبقي، وزر تسجيل دفعة ولو بعد الإلغاء.
  Widget _unitCard(String unit) {
    final contracts = widget.contracts()
        .where((c) => (c.unitName ?? '').trim() == unit)
        .toList()
      ..sort(
        (a, b) => (a.startDate ?? DateTime(1900)).compareTo(
          b.startDate ?? DateTime(1900),
        ),
      );
    final payments = widget.payments()
        .where(
          (p) =>
              p.unitName.trim() == unit ||
              (p.contract.unitName ?? '').trim() == unit,
        )
        .toList();
    final deposits = payments
        .where((p) => p.kindLabel == kPayKindDeposit)
        .toList();
    var depositsTotal = 0.0;
    var paidTotal = 0.0;
    var left = 0.0;
    final outstanding = <RentPaymentEntry>[];
    for (final p in payments) {
      paidTotal += p.payment.amountPaid;
      final rest = payRemaining(p.payment);
      if (rest > 0) {
        left += rest;
        outstanding.add(p);
      }
    }
    for (final d in deposits) {
      depositsTotal += d.payment.amountPaid;
    }
    if (_kind == _kindDues && left <= 0) return const SizedBox.shrink();
    final dates = <DateTime>[
      for (final c in contracts)
        if (c.startDate != null) c.startDate!,
      for (final e in widget.events())
        if (e.unit.trim() == unit && e.date != null) e.date!,
    ]..sort();

    // العقود حسب سنة بدايتها، الأحدث أولًا.
    final byYear = <int, List<PropertyUnitContractRecord>>{};
    for (final c in contracts) {
      byYear.putIfAbsent(c.startDate?.year ?? 0, () => []).add(c);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final list in byYear.values) {
      list.sort(
        (a, b) => (b.startDate ?? DateTime(1900)).compareTo(
          a.startDate ?? DateTime(1900),
        ),
      );
    }

    String statusOf(PropertyUnitContractRecord c) {
      if (c.status == 'cancelled') return 'ملغي';
      final end = c.endDate;
      if (end != null &&
          DateUtils.dateOnly(end).isBefore(DateUtils.dateOnly(DateTime.now()))) {
        return 'منتهي';
      }
      return 'نشط';
    }

    Widget line(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.title,
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(
          color: left > 0 ? AppTheme.danger.withValues(alpha: 0.5) : _accent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.home_work_outlined, size: 19, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              // علامة حمراء: مبالغ متبقية تحتاج تسوية.
              if (left > 0)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: const Text(
                    'تحتاج تسوية',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              Text(
                dates.isEmpty
                    ? ''
                    : '${AppTr.tr('منذ')} ${_date(dates.first)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // الحالة الآن، ثم العقود سنةً سنة (الأحدث أولًا): من استأجر وبكم.
          if ((widget.currentStatus?.call(unit) ?? '').isNotEmpty)
            line(
              'الحالة الآن',
              widget.currentStatus!(unit),
              color: widget.currentStatus!(unit).startsWith('مؤجر')
                  ? const Color(0xFF34A894)
                  : (widget.currentStatus!(unit) == 'صيانة'
                        ? AppTheme.danger
                        : AppTheme.goldDark),
            ),
          if (contracts.isEmpty)
            const Text(
              'لا توجد عقود',
              style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
            )
          else
            for (final year in years) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  year == 0 ? AppTr.tr('بلا تاريخ') : '${AppTr.tr('سنة')} $year',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _accent,
                  ),
                ),
              ),
              for (final c in byYear[year]!)
                line(
                [
                  (c.tenantName ?? '').trim().isEmpty
                      ? AppTr.tr('مستأجر')
                      : c.tenantName!.trim(),
                  '${_date(c.startDate)} - ${_date(c.endDate)}',
                  if (c.status == 'cancelled' &&
                      LeaseContractData.isSettled(c.notes))
                    AppTr.tr('تمت التسوية'),
                  if ((c.notes ?? '').contains('أُلغي بدون تسوية'))
                    AppTr.tr('أُلغي بدون تسوية'),
                ].join(' · '),
                [
                  if (c.annualRent > 0) _money(c.annualRent),
                  statusOf(c),
                ].join(' · '),
                color: statusOf(c) == 'ملغي'
                    ? AppTheme.danger
                    : (statusOf(c) == 'نشط' ? const Color(0xFF34A894) : null),
              ),
            ],
          if (deposits.isNotEmpty) ...[
            const Divider(height: 16, color: AppTheme.hairline),
            Text(
              AppTr.tr('التأمينات'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
            for (final d in deposits)
              line(
                '${d.title} · ${_date(d.payment.paidAt ?? d.payment.dueDate)}',
                _money(
                  d.payment.amountPaid > 0
                      ? d.payment.amountPaid
                      : d.payment.amountDue,
                ),
              ),
            line('مجموع التأمينات المدفوعة', _money(depositsTotal), color: _accent),
          ],
          const Divider(height: 16, color: AppTheme.hairline),
          line('إجمالي المحصّل', _money(paidTotal), color: const Color(0xFF34A894)),
          line(
            'المتبقي للمتابعة',
            _money(left),
            color: left > 0 ? AppTheme.danger : null,
          ),
          if (left > 0 && widget.repository != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _payUnit(outstanding),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('تسجيل دفعة'),
              style: FilledButton.styleFrom(
                backgroundColor: _history ? _brownDark : widget.accent,
                minimumSize: const Size.fromHeight(42),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صفحة عنصر من «السجل التاريخي» كاملة في صفحة واحدة: المستحقات أولًا،
/// ثم كل ما سُجّل عنه مفصّلًا — بيانات الوحدة، العقود بكل أقسامها (العقد،
/// العقار، المؤجر، المستأجر، الممثل، التأمينات، الدفعات، الرسوم)، الأفراد
/// والجهات، الحركة المالية، قوائم الوحدة، وكل فئة فيها حركات (الصيانة،
/// المستندات، المتابعة...). وزر طباعة يطبع الصفحة كما هي.
class _ArchiveItemPage extends StatefulWidget {
  const _ArchiveItemPage({required this.item, required this.screen});

  final AssetArchiveItem item;
  final AssetRecordsScreen screen;

  @override
  State<_ArchiveItemPage> createState() => _ArchiveItemPageState();
}

class _ArchiveItemPageState extends State<_ArchiveItemPage> {
  static const _brown = Color(0xFF4E342E);
  static const _brownDark = Color(0xFF3E2723);
  static const _card = Color(0xFFF6EFEA);
  static const _accent = Color(0xFF8D6E63);

  static const _dueTitle = 'المستحقات';

  /// أسماء الفئات بترتيب ظهورها.
  static const _kindLabels = <String, String>{
    AssetRecordEvent.kindMaintenance: 'الصيانة',
    AssetRecordEvent.kindDocument: 'المستندات',
    AssetRecordEvent.kindFollow: 'المتابعة والتخطيط',
    AssetRecordEvent.kindMoney: 'الدخل والمصروفات',
    AssetRecordEvent.kindContract: 'أحداث العقود',
    AssetRecordEvent.kindPayment: 'الدفعات المحصّلة',
    AssetRecordEvent.kindDeposit: 'التأمينات المحصّلة',
    AssetRecordEvent.kindLog: 'سجل النشاط',
  };

  /// «الأفراد والجهات» المربوطون بهذا العقار/الوحدة.
  List<PeopleDirectoryEntry> _people = const [];

  AssetArchiveItem get _item => widget.item;
  AssetRecordsScreen get _s => widget.screen;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    try {
      final all = await PeopleDirectoryStore.load();
      if (!mounted) return;
      final asset = _s.assetTitle.trim();
      final unit = _item.unitName.trim();
      setState(() {
        _people = [
          for (final p in all)
            if ((p.details['الأصل المرتبط'] ?? '').trim() == asset &&
                (_item.isAsset ||
                    (p.details['الوحدة المرتبطة'] ?? '').trim() == unit))
              p,
        ];
      });
    } catch (_) {
      // بلا دليل الأفراد: يبقى من في العقود.
    }
  }

  List<PropertyUnitContractRecord> get _contracts =>
      archiveContractsOf(_item, _s.contracts())..sort(
        (a, b) => (b.startDate ?? DateTime(1900)).compareTo(
          a.startDate ?? DateTime(1900),
        ),
      );

  List<RentPaymentEntry> get _payments =>
      sortPaymentEntries(archivePaymentsOf(_item, _s.payments()));

  List<AssetRecordEvent> get _events {
    final unit = _item.unitName.trim();
    final list = _s.events().where((e) {
      if (_item.isAsset) return true;
      return e.unit.trim() == unit;
    }).toList();
    list.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  /// ما يحتاج تسوية: غير مسدد، ولم تُسوَّ مبالغ عقده، ولم يسقط بالإلغاء.
  List<RentPaymentEntry> get _outstanding => [
    for (final p in _payments)
      if (payRemaining(p.payment) > 0 &&
          !LeaseContractData.isSettled(p.contract.notes) &&
          !paymentWaivedByClosure(p.contract, p.payment))
        p,
  ];

  String _date(DateTime? d) =>
      d == null ? '—' : '${d.day}/${d.month}/${d.year}';

  String _money(double value) {
    final fixed = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final text = parts.length > 1 ? '$digits.${parts[1]}' : digits;
    return '$text ${AppSettings.currencySuffix}';
  }

  /// تاريخ مخزَّن (2026-10-22) بالشكل المقروء، وغيره كما هو.
  String _show(String value) {
    final text = value.trim();
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)
        ? DateTime.tryParse(text)
        : null;
    return date == null ? text : _date(date);
  }

  String _contractStatus(PropertyUnitContractRecord c) {
    if (c.status == 'cancelled') return 'ملغي';
    if (c.status == PropertyUnitContractRecord.statusPending) return 'مسودة';
    final end = c.endDate;
    if (end != null &&
        DateUtils.dateOnly(end).isBefore(DateUtils.dateOnly(DateTime.now()))) {
      return 'منتهي';
    }
    return 'نشط';
  }

  /// أزواج من بيانات محفوظة: بلا الفارغ ولا المفاتيح الداخلية.
  List<(String, String)> _pairs(Map<String, String> map) => [
    for (final e in map.entries)
      if (!e.key.startsWith('__') && e.value.trim().isNotEmpty)
        (LeaseContractData.metaLabel(e.key), _show(e.value)),
  ];

  /// بيانات العقار: كل عداد بسطره ومن يدفعه.
  Map<String, String> _propertyForShow(Map<String, String> property) {
    final out = Map<String, String>.of(property);
    LeaseContractData.migrateMeters(out);
    LeaseContractData.meterGroups.forEach((countKey, group) {
      final n = LeaseContractData.meterCountOf(out, countKey);
      final numbers = LeaseContractData.meterLines(out[group.$1], n);
      final payers = LeaseContractData.meterLines(out[group.$2], n);
      out.remove(group.$1);
      out.remove(group.$2);
      for (var i = 0; i < n; i++) {
        final value = [
          if (numbers[i].isNotEmpty) numbers[i],
          if (payers[i].isNotEmpty) 'على ${payers[i]}',
        ].join(' — ');
        if (value.isNotEmpty) out['${group.$3} ${i + 1}'] = value;
      }
    });
    return out;
  }

  /// صفوف قائمة (تأمينات، دفعات، صيانة...) بأعمدة كل مفاتيحها.
  (List<String>, List<List<String>>) _table(List<Map<String, String>> rows) {
    final heads = <String>[];
    for (final row in rows) {
      for (final e in row.entries) {
        if (e.key.startsWith('__') || e.value.trim().isEmpty) continue;
        if (!heads.contains(e.key)) heads.add(e.key);
      }
    }
    return (
      heads,
      [
        for (final row in rows)
          [for (final h in heads) _show(row[h] ?? '')],
      ],
    );
  }

  PrintSection _listSection(String title, List<Map<String, String>> rows) {
    final (heads, cells) = _table(rows);
    return PrintSection(title, heads: heads, rows: cells);
  }

  /// كل أقسام الصفحة — نفسها تُعرض وتُطبع.
  List<PrintSection> _sections() {
    final out = <PrintSection>[];
    final payments = _payments;
    final contracts = _contracts;
    final events = _events;

    // ١. المستحقات أولًا.
    final due = _outstanding;
    final dueTotal = due.fold<double>(
      0,
      (sum, p) => sum + payRemaining(p.payment),
    );
    out.add(
      PrintSection(
        _dueTitle,
        pairs: [
          ('إجمالي المستحقات', _money(dueTotal)),
          ('الفئة', archiveCategoryOf(_item, dueTotal > 0)),
        ],
        heads: const ['البند', 'المتبقي', 'تاريخ الاستحقاق', 'الحالة'],
        rows: [
          for (final p in due)
            [
              _item.isAsset ? '${p.unitName} · ${p.title}' : p.title,
              _money(payRemaining(p.payment)),
              p.payment.dueDate == null ? 'لا يوجد' : _date(p.payment.dueDate),
              [
                rentPaymentStatusLabel(p.payment),
                if (payMethodOf(p).isNotEmpty) payMethodOf(p),
              ].join('/'),
            ],
        ],
      ),
    );

    // ٢. «المتابعة والتخطيط» تحت المستحقات في مربع مستقل — إن وُجدت.
    final follow = [
      for (final e in events)
        if (e.kind == AssetRecordEvent.kindFollow) e,
    ];
    if (follow.isNotEmpty) {
      out.add(_kindSection(AssetRecordEvent.kindFollow, follow));
    }

    // ٣. «بيانات العقد» كاملة كما في إدارة التأجير: العقد، بيانات المركبة
    // أو العقار، المؤجر، المستأجر، التأمين، الدفعات، الرسوم، الملاحظات.
    for (var i = 0; i < contracts.length; i++) {
      final c = contracts[i];
      final lease = LeaseContractData.decode(c.notes);
      final name = contracts.length > 1
          ? 'بيانات العقد ${i + 1}'
          : 'بيانات العقد';
      out.add(
        PrintSection(
          name,
          pairs: [
            if (_item.isAsset && (c.unitName ?? '').trim().isNotEmpty)
              ('الوحدة', c.unitName!.trim()),
            ('المستأجر', (c.tenantName ?? '').trim()),
            ('هاتف المستأجر', (c.tenantPhone ?? '').trim()),
            ('بداية العقد', _date(c.startDate)),
            ('نهاية العقد', _date(c.endDate)),
            ('حالة العقد', _contractStatus(c)),
            if (c.annualRent > 0) ('قيمة العقد', _money(c.annualRent)),
            ('دورية السداد', c.paymentCycle),
            ..._pairs(lease.contract),
          ],
        ),
      );
      final property = _pairs(_propertyForShow(lease.property));
      if (property.isNotEmpty) {
        out.add(PrintSection('$name — $_subjectTitle', pairs: property));
      }
      for (final (title, map) in [
        ('بيانات المؤجر', lease.lessor),
        ('بيانات المستأجر', lease.tenant),
        ('بيانات ممثل المستأجر', lease.representative),
        ('بيانات الرخصة', lease.license),
      ]) {
        final pairs = _pairs(map);
        if (pairs.isNotEmpty) {
          out.add(PrintSection('$name — $title', pairs: pairs));
        }
      }
      if (lease.deposits.isNotEmpty) {
        final (heads, cells) = _table(lease.deposits);
        out.add(
          PrintSection(
            '$name — قيمة التأمين',
            pairs: [('مجموع التأمين', _money(lease.depositsTotal))],
            heads: heads,
            rows: cells,
          ),
        );
      }
      for (final (title, rows) in [
        ('دفعات العقد', lease.payments),
        ('الرسوم الإدارية', lease.adminFees),
      ]) {
        if (rows.isNotEmpty) out.add(_listSection('$name — $title', rows));
      }
      if (lease.note.trim().isNotEmpty) {
        out.add(
          PrintSection(
            '$name — ملاحظات',
            pairs: [('ملاحظات على العقد', lease.note.trim())],
          ),
        );
      }
    }

    // ٤. بيانات الوحدة (أو المركبة أو النشاط أو العقار) كما سُجّلت.
    final details = _s.unitDetails?.call(_item.unitName);
    final status = _item.isAsset
        ? ''
        : (_s.currentStatus?.call(_item.unitName) ?? '');
    out.add(
      PrintSection(
        _dataTitle,
        pairs: [
          ('النوع', _item.type),
          ('الاسم', _item.name),
          (
            _item.cancelled ? 'تاريخ الإلغاء' : 'تاريخ الأرشفة',
            _date(_item.date),
          ),
          if (status.isNotEmpty) ('الحالة الآن', status),
          ...?details?.info,
        ],
      ),
    );

    // ٥. الحركة المالية: كل البنود بحالتها ومبالغها.
    if (payments.isNotEmpty) {
      var paid = 0.0;
      var left = 0.0;
      for (final p in payments) {
        paid += p.payment.amountPaid;
        left += payRemaining(p.payment);
      }
      out.add(
        PrintSection(
          'الحركة المالية',
          pairs: [
            ('إجمالي المحصّل', _money(paid)),
            ('إجمالي المتبقي', _money(left)),
          ],
          heads: const [
            'البند',
            'المبلغ',
            'المسدد',
            'المتبقي',
            'الاستحقاق',
            'الحالة',
          ],
          rows: [
            for (final p in payments)
              [
                _item.isAsset ? '${p.unitName} · ${p.title}' : p.title,
                _money(p.payment.amountDue),
                _money(p.payment.amountPaid),
                _money(payRemaining(p.payment)),
                p.payment.dueDate == null
                    ? 'لا يوجد'
                    : _date(p.payment.dueDate),
                [
                  rentPaymentStatusLabel(p.payment),
                  if (payMethodOf(p).isNotEmpty) payMethodOf(p),
                ].join('/'),
              ],
          ],
        ),
      );
    }

    // ٦. قوائم الوحدة المسجّلة فيها (الصيانة، المرافق، الملاحظات...).
    for (final (title, rows)
        in details?.lists ??
            const <(String, List<Map<String, String>>)>[]) {
      if (rows.isNotEmpty) out.add(_listSection(title, rows));
    }

    // ٧. كل فئة تابعة له فيها حركات (الصيانة، المستندات...) — وما لا حركة
    // فيه لا يظهر.
    for (final kind in _kindLabels.keys) {
      if (kind == AssetRecordEvent.kindFollow) continue;
      final list = [
        for (final e in events)
          if (e.kind == kind) e,
      ];
      if (list.isEmpty) continue;
      out.add(_kindSection(kind, list));
    }

    // ٨. الأفراد والجهات.
    final people = <List<String>>[];
    for (final c in contracts) {
      final lease = LeaseContractData.decode(c.notes);
      String phone(Map<String, String> m) =>
          (m[LeaseContractData.kPhone] ?? m[LeaseContractData.kMobile] ?? '')
              .trim();
      void add(String role, String name, String number) {
        if (name.trim().isEmpty) return;
        final exists = people.any((r) => r[0] == role && r[1] == name.trim());
        if (!exists) people.add([role, name.trim(), number]);
      }

      add('المؤجر', lease.lessor[LeaseContractData.kName] ?? '',
          phone(lease.lessor));
      add(
        'المستأجر',
        (lease.tenant[LeaseContractData.kName] ?? c.tenantName ?? ''),
        phone(lease.tenant).isEmpty
            ? (c.tenantPhone ?? '')
            : phone(lease.tenant),
      );
      add('ممثل المستأجر',
          lease.representative[LeaseContractData.kRepName] ?? '',
          phone(lease.representative));
    }
    for (final p in _people) {
      people.add([
        p.categoryName,
        p.fullName,
        p.firstOf(const ['رقم الهاتف', 'رقم الجوال']),
      ]);
    }
    if (people.isNotEmpty) {
      out.add(
        PrintSection(
          'الأفراد والجهات',
          heads: const ['الصفة', 'الاسم', 'الهاتف'],
          rows: people,
        ),
      );
    }
    return out;
  }

  /// عنوان بيانات العين في العقد: المركبة أو العقار.
  String get _subjectTitle =>
      _s.unitLabel == 'المركبة' ? 'بيانات المركبة' : 'بيانات العقار';

  /// عنوان بيانات العنصر نفسه كما سُجّل.
  String get _dataTitle => _s.unitLabel == 'المركبة'
      ? 'بيانات المركبة'
      : _s.unitLabel == 'العقد'
      ? 'بيانات النشاط'
      : (_item.isAsset ? 'بيانات العقار' : 'بيانات الوحدة');

  /// فئة واحدة بكل ما سُجّل في بنودها.
  PrintSection _kindSection(String kind, List<AssetRecordEvent> list) {
    final extra = <String>[];
    for (final e in list) {
      for (final f in e.fields.entries) {
        if (f.key.startsWith('__') || f.value.trim().isEmpty) continue;
        if (!extra.contains(f.key)) extra.add(f.key);
      }
    }
    final hasAmount = list.any((e) => e.amount > 0.009);
    final hasDetail = list.any((e) => e.detail.isNotEmpty);
    return PrintSection(
      _kindLabels[kind] ?? kind,
      heads: [
        'البيان',
        'التاريخ',
        if (hasAmount) 'المبلغ',
        if (_item.isAsset) 'الوحدة',
        if (hasDetail) 'تفاصيل',
        ...extra,
      ],
      rows: [
        for (final e in list)
          [
            e.title,
            e.date == null ? 'بلا تاريخ' : _date(e.date),
            if (hasAmount) e.amount > 0.009 ? _money(e.amount) : '',
            if (_item.isAsset) e.unit,
            if (hasDetail) e.detail,
            for (final key in extra) _show(e.fields[key] ?? ''),
          ],
      ],
    );
  }

  Future<void> _pay(List<RentPaymentEntry> outstanding) async {
    final repo = _s.repository;
    if (repo == null || outstanding.isEmpty) return;
    final changed = await openPaymentSettlePage(
      context: context,
      repository: repo,
      entries: outstanding,
      showUnitName: _item.isAsset,
    );
    if (!changed) return;
    await _s.reload?.call();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسجيل الدفعة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _heading => [
    if (_s.assetType.trim().isNotEmpty) _s.assetType.trim(),
    _s.assetTitle,
  ].join(' / ');

  void _print() {
    final sections = _sections();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatePrintScreen(
          title: 'طباعة السجل التاريخي',
          fileName: 'السجل التاريخي - ${_item.label}',
          buildPdf: (format) => buildRecordPdf(
            title: 'السجل التاريخي — ${_item.label}',
            subtitle: 'ARCHIVE RECORD',
            sections: sections,
            format: format,
            meta: [if (!_item.isAsset) ('العقار', _heading)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    final outstanding = _outstanding;
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: _brown,
        appBar: AppBar(
          backgroundColor: _brownDark,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _item.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Text(
                _item.isAsset ? 'السجل التاريخي' : _heading,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: AppTr.tr('طباعة'),
              onPressed: _print,
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            for (final section in sections)
              _sectionBox(
                section,
                footer: section.title == _dueTitle &&
                        outstanding.isNotEmpty &&
                        _s.repository != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          onPressed: () => _pay(outstanding),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('تسجيل دفعة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _brownDark,
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5C6B68),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
        ),
      ],
    ),
  );

  /// قسم في صندوق: أزواجه، ثم كل صف في بطاقة صغيرة بكل حقوله.
  Widget _sectionBox(PrintSection section, {Widget? footer}) {
    final due = section.title == _dueTitle;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: due && section.rows.isNotEmpty
            ? Border.all(color: AppTheme.danger.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: due && section.rows.isNotEmpty
                  ? AppTheme.danger
                  : _accent,
            ),
          ),
          for (final (label, value) in section.pairs)
            if (value.trim().isNotEmpty) _line(label, value),
          if (due && section.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'لا مستحقات متبقية',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF34A894),
                ),
              ),
            ),
          for (final row in section.rows)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < section.heads.length && i < row.length; i++)
                    if (row[i].trim().isNotEmpty) _line(section.heads[i], row[i]),
                ],
              ),
            ),
          if (footer != null) footer,
        ],
      ),
    );
  }
}
