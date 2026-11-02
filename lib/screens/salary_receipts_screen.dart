import 'package:flutter/material.dart' hide Text, Align;
import 'package:share_plus/share_plus.dart';

import '../data/app_settings.dart';
import '../data/custody_sharing.dart';
import '../data/fundly_account.dart';
import '../data/fundly_auth.dart';
import '../data/people_directory_store.dart';
import '../data/personal_entries_repository.dart';
import '../data/salary_receipts.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/signature_pad.dart';

String _plainNum(double v) => v.toStringAsFixed(v.abs() % 1 == 0 ? 0 : 2);

String _moneyOf(double v, [String currency = '']) =>
    '${_plainNum(v)} ${currency.isEmpty ? AppSettings.currencySuffix : currency}';

String _dayOf(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// لون الحالة: معتمد أخضر، بانتظار الاعتماد برتقالي، مرفوض أحمر.
Color _statusColor(String status) => switch (status) {
  SalaryReceipt.statusApproved => const Color(0xFF178F7B),
  SalaryReceipt.statusRejected => AppTheme.danger,
  _ => const Color(0xFFA6691A),
};

Widget _statusPill(String status) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: _statusColor(status).withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(AppTheme.rPill),
  ),
  child: Text(
    status,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w900,
      color: _statusColor(status),
    ),
  ),
);

/// المصروف المرتبط بالسند في الالتزامات الشخصية (الراتب من مصروفاتي).
Future<String> _syncExpense(SalaryReceipt r) async {
  final repo = SupabasePersonalEntriesRepository();
  final title = '${r.title} — ${r.employeeName}';
  final details = <String, String>{
    'المبلغ': _plainNum(r.paid),
    'التصنيف الرئيسي': r.isSalary ? 'رواتب' : 'مصروفات أخرى',
    'التاريخ': r.receiptDate,
    'العنوان': title,
    if (r.notes.trim().isNotEmpty) 'الملاحظات': r.notes.trim(),
    'جهة الصرف': r.employeeName,
    'الفرد المرتبط': r.employeeName,
    'سند القبض': r.id ?? '',
  };
  PersonalEntryRecord record({String? id}) => PersonalEntryRecord(
    id: id,
    category: 'financial',
    entryType: 'المصروفات الشخصية',
    title: title,
    amount: r.paid.round(),
    dueDate: r.receiptDate,
    status: 'نشطة',
    details: details,
  );
  if (r.expenseId.isNotEmpty) {
    try {
      final saved = await repo.update(record(id: r.expenseId));
      return saved.id ?? r.expenseId;
    } catch (_) {
      // حُذف المصروف من هناك: يُسجَّل من جديد.
    }
  }
  final saved = await repo.create(record());
  return saved.id ?? '';
}

/// سندات القبض والرواتب: ما أصدرته، وما وصلني للاعتماد والتوقيع.
/// مع [employeeFnd]: سجل رواتب موظف واحد وبطاقة سنته شهرًا شهرًا.
class SalaryReceiptsScreen extends StatefulWidget {
  const SalaryReceiptsScreen({
    super.key,
    this.employeeFnd = '',
    this.employeeName = '',
    this.openId,
  });

  final String employeeFnd;
  final String employeeName;

  /// يُفتح هذا السند بعد التحميل (من إشعار أو طلب).
  final String? openId;

  @override
  State<SalaryReceiptsScreen> createState() => _SalaryReceiptsScreenState();
}

class _SalaryReceiptsScreenState extends State<SalaryReceiptsScreen> {
  final _repo = SalaryReceiptsRepository();
  List<SalaryReceipt> _mine = const [];
  List<SalaryReceipt> _toMe = const [];
  bool _loading = true;
  String _error = '';
  int _tab = 0;
  int _year = DateTime.now().year;
  bool _openedOnce = false;

  bool get _forEmployee =>
      widget.employeeFnd.trim().isNotEmpty ||
      widget.employeeName.trim().isNotEmpty;

  /// سند هذا الموظف: برقمه التعريفي، وإلا باسمه.
  bool _isEmployee(SalaryReceipt r) => widget.employeeFnd.trim().isNotEmpty
      ? r.employeeFnd == widget.employeeFnd.trim()
      : r.employeeName.trim() == widget.employeeName.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final mine = await _repo.fetchMine();
      final toMe = _forEmployee
          ? const <SalaryReceipt>[]
          : await _repo.fetchSentToMe(AppIdentity.id);
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _toMe = toMe;
        _loading = false;
      });
      final openId = widget.openId;
      if (!_openedOnce && openId != null) {
        _openedOnce = true;
        for (final r in [...mine, ...toMe]) {
          if (r.id != openId) continue;
          final incoming = toMe.contains(r);
          setState(() {
            _tab = incoming ? 1 : 0;
            _year = r.year ?? _year;
          });
          await _openDetails(r, asOwner: !incoming);
          break;
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل السندات. تحقّق من الاتصال وحاول مرة أخرى.';
      });
    }
  }

  List<SalaryReceipt> get _source {
    final list = _tab == 0 ? _mine : _toMe;
    if (!_forEmployee) return list;
    return list.where(_isEmployee).toList(growable: false);
  }

  List<int> get _years {
    final years = <int>{
      DateTime.now().year,
      for (final r in _source)
        if (r.year != null) r.year!,
    }.toList()..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<SalaryReceipt> get _shown =>
      _source.where((r) => r.year == _year).toList(growable: false);

  Future<void> _openForm({SalaryReceipt? existing, int? month}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SalaryReceiptFormScreen(
          existing: existing,
          presetFnd: widget.employeeFnd,
          presetName: widget.employeeName,
          presetPeriod: month == null
              ? null
              : SalaryReceipt.periodOf(_year, month),
          others: _mine,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppTr.tr(message)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _delete(SalaryReceipt r) async {
    final ok = await confirmAction(
      context,
      title: 'حذف السند',
      message:
          'سيُحذف «${r.title}» ومصروفه من الالتزامات الشخصية. هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || r.id == null) return;
    try {
      if (r.expenseId.isNotEmpty) {
        try {
          await SupabasePersonalEntriesRepository().delete(r.expenseId);
        } catch (_) {}
      }
      await _repo.delete(r.id!);
      _notify('تم حذف السند');
      await _load();
    } catch (_) {
      _notify('تعذّر الحذف. حاول مرة أخرى.');
    }
  }

  Future<void> _share(SalaryReceipt r) async {
    final lines = [
      AppTr.tr(r.isSalary ? 'سند قبض راتب' : 'سند قبض'),
      AppTr.tr(r.title),
      '${AppTr.tr('المستلم')}: ${r.employeeName}'
          '${r.employeeFnd.isEmpty ? '' : ' (${r.employeeFnd})'}',
      '${AppTr.tr('صاحب العمل')}: ${r.ownerName}',
      if (r.isSalary) ...[
        '${AppTr.tr('الراتب الأساسي')}: ${_moneyOf(r.basic, r.currency)}',
        if (r.allowances > 0)
          '${AppTr.tr('العلاوات')}: ${_moneyOf(r.allowances, r.currency)}',
        if (r.overtime > 0)
          '${AppTr.tr('العمل الإضافي')}: ${_moneyOf(r.overtime, r.currency)}',
        if (r.loan > 0)
          '${AppTr.tr('السلفة')}: ${_moneyOf(r.loan, r.currency)}',
        if (r.deductions > 0)
          '${AppTr.tr('الخصومات')}: ${_moneyOf(r.deductions, r.currency)}',
        '${AppTr.tr('المجموع')}: ${_moneyOf(r.total, r.currency)}',
      ],
      '${AppTr.tr('المبلغ المدفوع')}: ${_moneyOf(r.paid, r.currency)}',
      '${AppTr.tr('التاريخ')}: ${r.receiptDate}',
      '${AppTr.tr('الحالة')}: ${AppTr.tr(r.status)}',
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  /// رد الموظف من داخل السند: موافقة وتوقيع، أو رفض.
  Future<void> _answer(SalaryReceipt r, bool accept) async {
    var signature = '';
    var reason = '';
    var fullName = '';
    if (accept) {
      final strokes = await showSignaturePad(
        context,
        title: 'التوقيع للموافقة',
        subtitle:
            '${AppTr.tr('توقيعك يعني أنك استلمت')} '
            '${_moneyOf(r.paid, r.currency)} — ${AppTr.tr(r.title)}',
      );
      if (strokes == null || strokes.isEmpty || !mounted) return;
      signature = SalaryReceipt.encodeStrokes(strokes);
      // الراتب: الاسم الثلاثي قبل إكمال الاعتماد.
      if (r.isSalary) {
        final typed = await askFullName(context);
        if (typed == null) return;
        fullName = typed;
      }
    } else {
      final value = await _askReason();
      if (value == null) return;
      reason = value;
    }
    try {
      final error = await _repo.respond(
        r.id!,
        accept,
        signature: signature,
        reason: reason,
        name: fullName,
      );
      if (!mounted) return;
      _notify(error ?? (accept ? 'تمت الموافقة والتوقيع' : 'تم رفض السند'));
      await _load();
    } catch (_) {
      _notify('تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.');
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('رفض السند'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textDirection: AppTr.uiDir,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: AppTr.tr('سبب الرفض (اختياري)'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('رفض'),
            ),
          ],
        ),
      ),
    );
    final text = ctrl.text.trim();
    Future.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    return ok == true ? text : null;
  }

  Future<void> _openDetails(SalaryReceipt r, {required bool asOwner}) {
    String stamp(DateTime d) {
      final l = d.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${l.day}/${l.month}/${l.year} ${two(l.hour)}:${two(l.minute)}';
    }

    final rows = <(String, String)>[
      ('النوع', AppTr.tr(r.isSalary ? 'سند قبض راتب' : 'سند قبض')),
      (
        asOwner ? 'المستلم' : 'صاحب العمل',
        asOwner
            ? '${r.employeeName}${r.employeeFnd.isEmpty ? '' : ' (${r.employeeFnd})'}'
            : r.ownerName,
      ),
      if (r.isSalary) ('الشهر', AppTr.tr(r.periodLabel)),
      if (!r.isSalary && r.description.isNotEmpty) ('البيان', r.description),
      ('التاريخ', r.receiptDate),
      if (r.isSalary) ...[
        ('الراتب الأساسي', _moneyOf(r.basic, r.currency)),
        if (r.allowances > 0) ('العلاوات', _moneyOf(r.allowances, r.currency)),
        if (r.overtime > 0) ('العمل الإضافي', _moneyOf(r.overtime, r.currency)),
        if (r.loan > 0) ('السلفة', '− ${_moneyOf(r.loan, r.currency)}'),
        if (r.deductions > 0)
          ('الخصومات', '− ${_moneyOf(r.deductions, r.currency)}'),
        ('المجموع', _moneyOf(r.total, r.currency)),
      ],
      ('المبلغ المدفوع', _moneyOf(r.paid, r.currency)),
      if (r.notes.isNotEmpty) ('ملاحظات', r.notes),
      (
        'طريقة التوقيع',
        AppTr.tr(
          r.signMode == SalaryReceipt.signHere
              ? 'وقّع على جوال صاحب العمل'
              : 'أُرسل للاعتماد والتوقيع',
        ),
      ),
      if (r.signedAt != null)
        (r.isRejected ? 'وقت الرفض' : 'وقت التوقيع', stamp(r.signedAt!)),
      if (r.isRejected && r.rejectReason.isNotEmpty)
        ('سبب الرفض', r.rejectReason),
    ];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppTr.tr(r.title),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    _statusPill(r.status),
                  ],
                ),
                const SizedBox(height: 10),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 118,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (r.signature.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${AppTr.tr('توقيع المستلم')}: ${r.employeeName}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SignatureView(strokes: r.strokes, size: 150),
                  ),
                ],
                const SizedBox(height: 14),
                // الموظف: يوافق ويوقّع أو يرفض ما ينتظر اعتماده.
                if (!asOwner && r.isPending)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brand,
                          ),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _answer(r, true);
                          },
                          icon: const Icon(Icons.draw_outlined, size: 18),
                          label: const Text('موافقة وتوقيع'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.danger),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _answer(r, false);
                          },
                          child: const Text('رفض'),
                        ),
                      ),
                    ],
                  ),
                if (asOwner)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _share(r);
                        },
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('مشاركة'),
                      ),
                      // غير المعتمد يُعدَّل ويُعاد إرساله أو توقيعه.
                      if (!r.isApproved)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openForm(existing: r);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(
                            r.isRejected ? 'تعديل وإعادة الإرسال' : 'تعديل',
                          ),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _delete(r);
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('حذف'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة رواتب السنة: لكل شهر حالته ومبلغه — للموظف الواحد.
  Widget _yearCard() {
    SalaryReceipt? of(int month) {
      for (final r in _shown) {
        if (r.isSalary && r.month == month) return r;
      }
      return null;
    }

    Widget row(int m) {
      final r = of(m);
      return InkWell(
        onTap: () => r == null
            ? _openForm(month: m)
            : _openDetails(r, asOwner: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  SalaryReceipt.months[m - 1],
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r == null ? '—' : _moneyOf(r.paid, r.currency),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.body,
                  ),
                ),
              ),
              if (r != null)
                _statusPill(r.status)
              else
                const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${AppTr.tr('بطاقة رواتب')} $_year',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 6),
          for (var m = 1; m <= 12; m++) row(m),
        ],
      ),
    );
  }

  Widget _receiptCard(SalaryReceipt r) {
    final asOwner = _tab == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDetails(r, asOwner: asOwner),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                AppIconTile(
                  icon: r.isSalary
                      ? Icons.payments_outlined
                      : Icons.receipt_long_outlined,
                  color: AppTheme.brand,
                  size: 36,
                  iconSize: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTr.tr(r.title),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${asOwner ? r.employeeName : r.ownerName} · '
                        '${r.receiptDate}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _moneyOf(r.paid, r.currency),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _statusPill(r.status),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          _forEmployee
              ? '${AppTr.tr('رواتب')} ${widget.employeeName}'
              : 'سندات القبض والرواتب',
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.gold,
              foregroundColor: const Color(0xFF4A2F09),
              onPressed: () async {
                if (!await FundlyAuth.requireLogin(context)) return;
                _openForm();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('سند قبض'),
            )
          : null,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error,
                          style: const TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    if (!_forEmployee)
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(
                              '${AppTr.tr('أصدرتها')} (${_mine.length})',
                            ),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(
                              '${AppTr.tr('وصلتني')} (${_toMe.length})',
                            ),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    const SizedBox(height: 10),
                    // السنة: سجل الرواتب محفوظ لكل سنة.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final y in _years)
                          ChoiceChip(
                            label: Text('$y'),
                            selected: _year == y,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _year = y),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_forEmployee) ...[
                      _yearCard(),
                      const SizedBox(height: 12),
                    ],
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text(
                          'لا توجد سندات في هذه السنة',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted,
                          ),
                        ),
                      )
                    else
                      for (final r in shown) _receiptCard(r),
                  ],
                ),
              ),
      ),
    );
  }
}

/// نموذج سند القبض: راتب (بالرقم التعريفي إلزاميًا) أو سند عام، ثم التوقيع
/// على هذا الجوال أو الإرسال للاعتماد والتوقيع.
class SalaryReceiptFormScreen extends StatefulWidget {
  const SalaryReceiptFormScreen({
    super.key,
    this.existing,
    this.presetFnd = '',
    this.presetName = '',
    this.presetPeriod,
    this.others = const [],
  });

  final SalaryReceipt? existing;
  final String presetFnd;
  final String presetName;
  final String? presetPeriod;

  /// السندات الحالية — لتنبيه تكرار راتب الشهر نفسه.
  final List<SalaryReceipt> others;

  @override
  State<SalaryReceiptFormScreen> createState() =>
      _SalaryReceiptFormScreenState();
}

class _SalaryReceiptFormScreenState extends State<SalaryReceiptFormScreen> {
  final _repo = SalaryReceiptsRepository();
  late String _kind;
  late final TextEditingController _fnd;
  late final TextEditingController _name;
  late final TextEditingController _basic;
  late final TextEditingController _allowances;
  late final TextEditingController _overtime;
  late final TextEditingController _loan;
  late final TextEditingController _deductions;
  late final TextEditingController _paid;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late int _year;
  late int _month;
  late DateTime _date;
  late String _signMode;
  bool _paidTouched = false;
  bool _saving = false;
  String _error = '';

  String _checked = '';
  String? _owner;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    String n(double v) => v == 0 ? '' : _plainNum(v);
    _kind = e?.kind ?? SalaryReceipt.kindSalary;
    _fnd = TextEditingController(text: e?.employeeFnd ?? widget.presetFnd);
    _name = TextEditingController(text: e?.employeeName ?? widget.presetName);
    _basic = TextEditingController(text: n(e?.basic ?? 0));
    _allowances = TextEditingController(text: n(e?.allowances ?? 0));
    _overtime = TextEditingController(text: n(e?.overtime ?? 0));
    _loan = TextEditingController(text: n(e?.loan ?? 0));
    _deductions = TextEditingController(text: n(e?.deductions ?? 0));
    _paid = TextEditingController(text: n(e?.paid ?? 0));
    _description = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _paidTouched = e != null;
    final now = DateTime.now();
    final period = e?.period ?? widget.presetPeriod ?? '';
    final parts = period.split('-');
    _year = parts.length == 2 ? int.tryParse(parts[0]) ?? now.year : now.year;
    _month = parts.length == 2
        ? int.tryParse(parts[1]) ?? now.month
        : now.month;
    _date = _parseDay(e?.receiptDate ?? '') ?? now;
    _signMode = e?.signMode ?? SalaryReceipt.signHere;
    // راتب الموظف السابق يُقترح للسند الجديد.
    if (e == null && widget.presetFnd.isNotEmpty) {
      for (final r in widget.others) {
        if (r.isSalary && r.employeeFnd == widget.presetFnd) {
          _basic.text = n(r.basic);
          _allowances.text = n(r.allowances);
          break;
        }
      }
      if (_paid.text.isEmpty && _total > 0) _paid.text = _plainNum(_total);
    }
    if (_fnd.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fnd,
      _name,
      _basic,
      _allowances,
      _overtime,
      _loan,
      _deductions,
      _paid,
      _description,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static DateTime? _parseDay(String raw) {
    final p = raw.split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final y = int.tryParse(p[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  static double _v(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  bool get _isSalary => _kind == SalaryReceipt.kindSalary;

  double get _total {
    final t =
        _v(_basic) + _v(_allowances) + _v(_overtime) - _v(_loan) -
        _v(_deductions);
    return t < 0 ? 0 : t;
  }

  Future<void> _lookup() async {
    final id = AppIdentity.normalize(_fnd.text);
    if (!AppIdentity.isValid(id)) {
      setState(() {
        _checked = '';
        _owner = null;
        _looking = false;
      });
      return;
    }
    if (id == _checked) return;
    setState(() => _looking = true);
    final name = await FundlyAccount.nameForFnd(id);
    if (!mounted || AppIdentity.normalize(_fnd.text) != id) return;
    setState(() {
      _checked = id;
      _owner = name;
      _looking = false;
      if (name != null && _name.text.trim().isEmpty) _name.text = name;
    });
  }

  /// «جلب من الأفراد»: الاسم ورقمه التعريفي المسجَّل إن وُجد.
  Future<void> _pickFromPeople() async {
    final entries = await PeopleDirectoryStore.load();
    if (!mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppTr.tr('لا يوجد أفراد بعد في «الأفراد والجهات»')),
        ),
      );
      return;
    }
    // الموظفون أولًا.
    final sorted = [
      ...entries.where((e) => e.typeKey == 'person_employee'),
      ...entries.where((e) => e.typeKey != 'person_employee'),
    ];
    var query = '';
    final picked = await showModalBottomSheet<PeopleDirectoryEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final q = query.trim();
          final shown = sorted
              .where(
                (e) =>
                    q.isEmpty ||
                    e.fullName.contains(q) ||
                    e.categoryName.contains(q),
              )
              .toList(growable: false);
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختر من الأفراد والجهات',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    textDirection: AppTr.uiDir,
                    onChanged: (v) => setSheet(() => query = v),
                    decoration: _decor(
                      'ابحث بالاسم أو التصنيف',
                      icon: Icons.search_rounded,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppTheme.hairline),
                      itemBuilder: (_, i) {
                        final e = shown[i];
                        final id = e.detail('الرقم التعريفي').trim();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.isEntity
                                ? Icons.business_rounded
                                : Icons.person_rounded,
                            color: AppTheme.brand,
                          ),
                          title: Text(
                            e.fullName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            id.isEmpty
                                ? e.categoryName
                                : '${e.categoryName} · $id',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(sheetContext, e),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    final id = picked.detail('الرقم التعريفي').trim();
    setState(() {
      _name.text = picked.fullName.trim();
      _fnd.text = id;
      if (id.isEmpty) {
        _checked = '';
        _owner = null;
      }
    });
    if (id.isNotEmpty) await _lookup();
  }

  void _recalc() {
    if (!_paidTouched) _paid.text = _total == 0 ? '' : _plainNum(_total);
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final fnd = AppIdentity.normalize(_fnd.text);
    final hasFnd = fnd.isNotEmpty;
    final remote = _signMode == SalaryReceipt.signRemote;
    // الراتب المُرسل للاعتماد: الاسم المرتبط برقمه التعريفي، ويكتب الموظف
    // اسمه الثلاثي بنفسه عند الموافقة.
    final name = remote && _isSalary
        ? (_owner ?? '').trim()
        : _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : (_owner ?? '').trim();
    final paid = _v(_paid);
    String? error;
    final nameParts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .length;
    if (remote && !hasFnd) {
      error = 'الإرسال للاعتماد والتوقيع يحتاج الرقم التعريفي للمستلم';
    } else if (hasFnd && !AppIdentity.isValid(fnd)) {
      error = 'الرقم التعريفي بصيغة FND-XXXX-XXXX';
    } else if (hasFnd && fnd == AppIdentity.id) {
      error = 'لا يمكن إصدار سند لنفسك';
    } else if (remote && (_checked != fnd || _owner == null)) {
      error = _looking
          ? 'انتظر حتى يظهر صاحب الرقم التعريفي'
          : 'لم يُعثر على صاحب هذا الرقم — تأكد منه';
    } else if (name.isEmpty) {
      error = _isSalary ? 'اكتب اسم الموظف الحقيقي' : 'اكتب اسم المستلم';
    } else if (_isSalary && !remote && nameParts < 2) {
      error = 'اكتب اسم الموظف الحقيقي من اسمين على الأقل';
    } else if (!_isSalary && _description.text.trim().isEmpty) {
      error = 'اكتب بيان السند';
    } else if (paid <= 0) {
      error = 'أدخل المبلغ المدفوع';
    }
    if (error != null) {
      setState(() => _error = error!);
      return;
    }    if (error != null) {
      setState(() => _error = error!);
      return;
    }
    final period = _isSalary
        ? SalaryReceipt.periodOf(_year, _month)
        : SalaryReceipt.periodOf(_date.year, _date.month);
    // راتب الشهر نفسه مسجَّل من قبل؟
    if (_isSalary) {
      final dup = widget.others.any(
        (r) =>
            r.isSalary &&
            r.id != widget.existing?.id &&
            (hasFnd ? r.employeeFnd == fnd : r.employeeName == name) &&
            r.period == period &&
            !r.isRejected,
      );
      if (dup) {
        final go = await confirmAction(
          context,
          title: 'راتب مسجَّل',
          message:
              '${AppTr.tr('يوجد سند راتب لـ')} $name ${AppTr.tr('عن')} '
              '${AppTr.tr(SalaryReceipt.months[_month - 1])} $_year. '
              '${AppTr.tr('هل تريد إضافة سند آخر للشهر نفسه؟')}',
          confirmLabel: 'متابعة',
        );
        if (!go || !mounted) return;
      }
    }
    var signature = '';
    DateTime? signedAt;
    var status = SalaryReceipt.statusPending;
    if (_signMode == SalaryReceipt.signHere) {
      final strokes = await showSignaturePad(
        context,
        title: '${AppTr.tr('توقيع')} $name',
        subtitle:
            '${AppTr.tr('يوقّع المستلم بإصبعه على هذا الجوال تأكيدًا لاستلام')} '
            '${_moneyOf(paid)}',
      );
      if (strokes == null || strokes.isEmpty || !mounted) return;
      signature = SalaryReceipt.encodeStrokes(strokes);
      signedAt = DateTime.now();
      status = SalaryReceipt.statusApproved;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final draft = SalaryReceipt(
        id: widget.existing?.id,
        kind: _kind,
        employeeFnd: fnd,
        employeeName: name,
        ownerName: AppSettings.instance.publicName,
        period: period,
        receiptDate: _dayOf(_date),
        basic: _isSalary ? _v(_basic) : 0,
        allowances: _isSalary ? _v(_allowances) : 0,
        overtime: _isSalary ? _v(_overtime) : 0,
        loan: _isSalary ? _v(_loan) : 0,
        deductions: _isSalary ? _v(_deductions) : 0,
        total: _isSalary ? _total : paid,
        paid: paid,
        currency: AppSettings.currencySuffix,
        description: _isSalary ? '' : _description.text.trim(),
        notes: _notes.text.trim(),
        signMode: _signMode,
        status: status,
        signature: signature,
        signedAt: signedAt,
        expenseId: widget.existing?.expenseId ?? '',
      );
      var saved = widget.existing == null
          ? await _repo.create(draft)
          : await _repo.update(draft);
      // الراتب من مصروفاتي: مصروف مرتبط بالسند.
      try {
        final expenseId = await _syncExpense(saved);
        if (expenseId.isNotEmpty && expenseId != saved.expenseId) {
          saved = await _repo.update(saved.copyWith(expenseId: expenseId));
        }
      } catch (_) {}
      // يُضاف في «الأفراد والجهات» برقمه التعريفي.
      if (hasFnd) {
        await PeopleDirectoryStore.upsert(
          fullName: name,
          typeKey: _isSalary ? 'person_employee' : 'person_other',
          categoryName: _isSalary ? 'موظف' : 'أخرى',
          roleTitle: _isSalary ? 'موظف' : '',
          details: {'الرقم التعريفي': fnd},
          sourceNote: 'سند قبض',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _signMode == SalaryReceipt.signRemote
                ? '${AppTr.tr('أُرسل السند إلى')} $name '
                      '${AppTr.tr('للاعتماد والتوقيع')}'
                : AppTr.tr('تم حفظ السند الموقّع'),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.';
      });
    }
  }

  InputDecoration _decor(String label, {IconData? icon, String? hint}) =>
      InputDecoration(
        labelText: AppTr.tr(label),
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppTheme.field,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          borderSide: BorderSide.none,
        ),
      );

  Widget _amount(
    TextEditingController c,
    String label, {
    VoidCallback? onChanged,
  }) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => (onChanged ?? _recalc)(),
    decoration: _decor(label).copyWith(suffixText: AppSettings.currencySuffix),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: AppTheme.title,
      ),
    ),
  );

  Widget _signOption(String value, String title, String subtitle) =>
      RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        value: value,
        groupValue: _signMode,
        onChanged: (v) => setState(() => _signMode = v ?? _signMode),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      );

  @override
  Widget build(BuildContext context) {
    final fnd = AppIdentity.normalize(_fnd.text);
    final checkedNow = _checked.isNotEmpty && _checked == fnd;
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.existing == null ? 'سند قبض' : 'تعديل السند'),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // نوع السند: راتب شهر أو سند عام.
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: SalaryReceipt.kindSalary,
                  icon: Icon(Icons.payments_outlined, size: 18),
                  label: Text('راتب'),
                ),
                ButtonSegment(
                  value: SalaryReceipt.kindGeneral,
                  icon: Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('سند قبض عام'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: widget.existing == null
                  ? (s) => setState(() => _kind = s.first)
                  : null,
            ),
            // التوقيع أولًا: يحدد إن كان الرقم التعريفي إلزاميًا.
            _section('1. التوقيع'),
            _signOption(
              SalaryReceipt.signHere,
              'يوقّع المستلم على جوالي الآن',
              'تفتح شاشة مربعة للتوقيع باللمس، ويُحفظ السند معتمدًا — '
                  'الرقم التعريفي اختياري',
            ),
            _signOption(
              SalaryReceipt.signRemote,
              'إرسال للاعتماد والتوقيع',
              'يصله على رقمه التعريفي فيوافق ويوقّع أو يرفض — وحالته '
                  '«بانتظار الاعتماد» حتى يرد',
            ),
            // عنوان القسم وعلى يساره «جلب من الأفراد».
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isSalary ? '2. الموظف' : '2. المستلم',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.brand,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _pickFromPeople,
                    icon: const Icon(Icons.person_search_rounded, size: 18),
                    label: const Text(
                      'جلب من الأفراد',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _fnd,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _lookup(),
              decoration: _decor(
                _signMode == SalaryReceipt.signRemote
                    ? 'الرقم التعريفي (إلزامي للإرسال)'
                    : 'الرقم التعريفي (غير إلزامي)',
                icon: Icons.badge_outlined,
                hint: 'FND-XXXX-XXXX',
              ),
            ),
            if (_looking)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'جارٍ التحقق من صاحب الرقم...',
                  style: TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
              )
            else if (checkedNow)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _owner != null
                      ? AppTheme.brandSoft
                      : const Color(0xFFFFF6E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      _owner != null
                          ? Icons.verified_user_outlined
                          : Icons.help_outline_rounded,
                      size: 18,
                      color: _owner != null
                          ? AppTheme.brand
                          : const Color(0xFFA6691A),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _owner != null
                            ? '${AppTr.tr('الرقم التعريفي يخص')}: $_owner'
                            : AppTr.tr(
                                'لم يُعثر على صاحب هذا الرقم — تأكد منه',
                              ),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _owner != null
                              ? AppTheme.brand
                              : const Color(0xFF6B4A12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // الراتب المُرسل للاعتماد: يظهر باسمه المرتبط برقمه التعريفي،
            // ويكتب اسمه الثلاثي بنفسه عند الموافقة.
            if (_isSalary && _signMode == SalaryReceipt.signRemote)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'يظهر الموظف باسمه المرتبط برقمه التعريفي، ويكتب اسمه '
                  'الثلاثي بنفسه عند الموافقة والتوقيع.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                textDirection: AppTr.uiDir,
                onChanged: (_) => setState(() {}),
                decoration: _decor(
                  _isSalary
                      ? 'اسم الموظف الحقيقي (اسمين على الأقل)'
                      : 'اسم المستلم',
                  icon: Icons.person_outline_rounded,
                ),
              ),
            ],
            if (_isSalary) ...[
              _section('3. الشهر'),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _month,
                      decoration: _decor('الشهر'),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(SalaryReceipt.months[m - 1]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _month = v ?? _month),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      decoration: _decor('السنة'),
                      items: [
                        for (
                          var y = DateTime.now().year + 1;
                          y >= DateTime.now().year - 6;
                          y--
                        )
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (v) => setState(() => _year = v ?? _year),
                    ),
                  ),
                ],
              ),
              _section('4. الراتب'),
              _amount(_basic, 'الراتب الأساسي'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _amount(_allowances, 'العلاوات')),
                  const SizedBox(width: 8),
                  Expanded(child: _amount(_overtime, 'العمل الإضافي')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _amount(_loan, 'السلفة (تُخصم)')),
                  const SizedBox(width: 8),
                  Expanded(child: _amount(_deductions, 'الخصومات')),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'المجموع',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                    Text(
                      _moneyOf(_total),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.brand,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _amount(
                _paid,
                'المبلغ المدفوع',
                onChanged: () => setState(() => _paidTouched = true),
              ),
            ] else ...[
              _section('3. السند'),
              TextField(
                controller: _description,
                textDirection: AppTr.uiDir,
                decoration: _decor('البيان', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 8),
              _amount(
                _paid,
                'المبلغ',
                onChanged: () => setState(() => _paidTouched = true),
              ),
            ],
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: _decor('تاريخ السند', icon: Icons.event_outlined),
                child: Text(_dayOf(_date)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              textDirection: AppTr.uiDir,
              maxLines: 2,
              decoration: _decor('ملاحظات (اختياري)'),
            ),
            if (_error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF4F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFA82F26),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _saving ? null : _save,
              icon: Icon(
                _signMode == SalaryReceipt.signHere
                    ? Icons.draw_outlined
                    : Icons.send_rounded,
                size: 19,
              ),
              label: Text(
                _signMode == SalaryReceipt.signHere
                    ? 'التوقيع والحفظ'
                    : 'إرسال للاعتماد والتوقيع',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
