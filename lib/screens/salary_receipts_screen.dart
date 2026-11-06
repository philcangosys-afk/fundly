import 'dart:async';

import 'package:flutter/material.dart' hide Text, Align;

import '../data/app_settings.dart';
import '../data/custody_sharing.dart';
import '../data/fundly_account.dart';
import '../data/fundly_auth.dart';
import '../data/people_directory_store.dart';
import '../data/personal_entries_repository.dart';
import '../data/salary_income_sync.dart';
import '../data/salary_receipt_pdf.dart';
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
    // استُلم الراتب ووُقّع: المصروف «مكتملة» لا «نشطة».
    status: r.isApproved ? 'مكتملة' : 'نشطة',
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

/// السند الذي رفضه المستلم («لم أستلم»): مصروفه المرتبط عند صاحب العمل
/// يصبح «ملغاة» فلا يُحسب في مصروفاته. والمعتمد (استلمه ووقّع) يصبح
/// مصروفه «مكتملة».
Future<void> _cancelRejectedExpenses(List<SalaryReceipt> mine) async {
  final rejected = {
    for (final r in mine)
      if (r.isRejected && r.expenseId.isNotEmpty) r.expenseId,
  };
  final approved = {
    for (final r in mine)
      if (r.isApproved && r.expenseId.isNotEmpty) r.expenseId,
  };
  if (rejected.isEmpty && approved.isEmpty) return;
  try {
    final repo = SupabasePersonalEntriesRepository();
    for (final record in await repo.fetchAll()) {
      if (rejected.contains(record.id)) {
        if (record.status == 'ملغاة' || record.status == 'محذوف') continue;
        await repo.update(record.copyWith(status: 'ملغاة'));
      } else if (approved.contains(record.id) && record.status == 'نشطة') {
        await repo.update(record.copyWith(status: 'مكتملة'));
      }
    }
  } catch (_) {
    // يُعاد في التحميل التالي.
  }
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
      unawaited(_cancelRejectedExpenses(mine));
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

  /// مشاركة سند أو أكثر كملف PDF (صفحة لكل سند).
  Future<void> _sharePdf(List<SalaryReceipt> list) async {
    if (list.isEmpty) return;
    _notify('جارٍ تجهيز ملف PDF...');
    try {
      await shareSalaryReceiptsPdf(list);
    } catch (error) {
      debugPrint('Salary PDF failed: $error');
      _notify('تعذّر تجهيز ملف PDF. حاول مرة أخرى.');
    }
  }

  // ---------------- التحديد للمشاركة ----------------

  bool _selecting = false;
  final Set<String> _selected = {};

  void _toggleSelecting() => setState(() {
    _selecting = !_selecting;
    _selected.clear();
  });

  void _toggleOne(SalaryReceipt r) {
    final id = r.id;
    if (id == null) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// المحدَّد بترتيب السجل (الأحدث أولًا).
  List<SalaryReceipt> get _selectedReceipts => [
    for (final r in _source)
      if (r.id != null && _selected.contains(r.id)) r,
  ];

  /// رد الموظف من داخل السند: موافقة وتوقيع، أو رفض.
  Future<void> _answer(SalaryReceipt r, bool accept) async {
    var signature = '';
    var reason = '';
    if (accept) {
      final strokes = await showSignaturePad(
        context,
        title: 'التوقيع للموافقة',
        subtitle:
            '${AppTr.tr('توقيعك يعني أنك استلمت')} '
            '${_moneyOf(r.paid, r.currency)} — ${AppTr.tr(r.title)}',
      );
      if (strokes == null || strokes.isEmpty || !mounted) return;
      // الاسم كتبه المرسل ويبقى كما هو — لا يُطلب من الموظف.
      signature = SalaryReceipt.encodeStrokes(strokes);
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
      );
      // المعتمد يظهر عندي في «مالية» كإيراد.
      if (error == null && accept) await SalaryIncomeSync.syncReceived();
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

    String money(double v) => _moneyOf(v, r.currency);
    final breakdown = <(String, String, bool)>[
      if (r.isSalary) ...[
        ('الراتب الأساسي', money(r.basic), false),
        if (r.allowances > 0) ('العلاوات', money(r.allowances), false),
        if (r.overtime > 0) ('العمل الإضافي', money(r.overtime), false),
        if (r.loan > 0) ('السلفة', '− ${money(r.loan)}', false),
        if (r.deductions > 0) ('الخصومات', '− ${money(r.deductions)}', false),
        ('المجموع', money(r.total), true),
      ] else
        ('البيان', r.description.isEmpty ? '—' : r.description, false),
    ];
    final info = <(String, String)>[
      ('رقم السند', salaryReceiptNo(r)),
      ('التاريخ', r.receiptDate),
      (
        'طريقة التوقيع',
        AppTr.tr(
          r.signMode == SalaryReceipt.signHere
              ? r.signHereLabel
              : 'أُرسل للاعتماد والتوقيع',
        ),
      ),
      if (r.signedAt != null)
        (r.isRejected ? 'وقت الرفض' : 'وقت التوقيع', stamp(r.signedAt!)),
      if (r.notes.isNotEmpty) ('ملاحظات', r.notes),
      if (r.isRejected && r.rejectReason.isNotEmpty)
        ('سبب الرفض', r.rejectReason),
    ];
    const deep = Color(0xFF0A5A50);

    Widget card({required Widget child, EdgeInsets? padding}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: child,
    );

    Widget party(String label, String name, String fnd) => Expanded(
      child: card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name.isEmpty ? '—' : name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
            if (fnd.isNotEmpty)
              Text(
                fnd,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
          ],
        ),
      ),
    );

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // لا يصعد تحت النتوء وشريط الحالة، وفيه زر إغلاق ظاهر.
      useSafeArea: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.hairline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // الرأس: نوع السند وشهره وحالته، والمبلغ المدفوع بارزًا.
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.rCard),
                    gradient: const LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [deep, Color(0xFF0E7161)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            r.isSalary
                                ? Icons.payments_outlined
                                : Icons.receipt_long_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.isSalary ? 'سند قبض راتب' : 'سند قبض',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(
                                AppTheme.rPill,
                              ),
                            ),
                            child: Text(
                              r.status,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: _statusColor(r.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppTr.tr(r.title),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'المبلغ المدفوع',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      Text(
                        money(r.paid),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // الطرفان: الاسم كما كتبه المرسل (لا يُعدَّل عند الموظف).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    party(r.payerLabel, r.ownerName, ''),
                    const SizedBox(width: 8),
                    party(
                      r.payeeLabel,
                      r.employeeName,
                      r.employeeFnd,
                    ),
                  ],
                ),
                // تفاصيل الراتب.
                card(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        r.isSalary ? 'تفاصيل الراتب' : 'تفاصيل السند',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: deep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (var i = 0; i < breakdown.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppTheme.hairline),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  breakdown[i].$1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: breakdown[i].$3
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    color: breakdown[i].$3
                                        ? AppTheme.title
                                        : AppTheme.muted,
                                  ),
                                ),
                              ),
                              Text(
                                breakdown[i].$2,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.title,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // بيانات السند.
                card(
                  child: Column(
                    children: [
                      for (final (label, value) in info)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 104,
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.title,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // التوقيع.
                if (r.signature.isNotEmpty)
                  card(
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.field,
                            borderRadius: BorderRadius.circular(
                              AppTheme.rInner,
                            ),
                          ),
                          child: SignatureView(strokes: r.strokes, size: 96),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'توقيع المستلم',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.muted,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                r.employeeName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.title,
                                ),
                              ),
                              if (r.signedAt != null)
                                Text(
                                  stamp(r.signedAt!),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                // الموظف: يوافق ويوقّع أو يرفض ما ينتظر اعتماده.
                if (!asOwner && r.isPending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.brand,
                              minimumSize: const Size.fromHeight(46),
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
                              minimumSize: const Size.fromHeight(46),
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
                  ),
                // مشاركة PDF: للمرسل والمستلم.
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: deep,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _sharePdf([r]);
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                  label: const Text('مشاركة PDF'),
                ),
                if (asOwner) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // غير المعتمد يُعدَّل ويُعاد إرساله أو توقيعه.
                      if (!r.isApproved) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openForm(existing: r);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(
                              r.isRejected ? 'تعديل وإعادة الإرسال' : 'تعديل',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
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
                      ),
                    ],
                  ),
                ],
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
        onTap: () {
          if (r == null) {
            if (!_selecting) _openForm(month: m);
          } else if (_selecting) {
            _toggleOne(r);
          } else {
            _openDetails(r, asOwner: true);
          }
        },
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
              if (r != null && _selecting)
                Icon(
                  _selected.contains(r.id)
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: AppTheme.brand,
                )
              else if (r != null)
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
    final picked = r.id != null && _selected.contains(r.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // وضع التحديد: الضغط يحدد السند، والضغط المطوّل يبدأ التحديد.
          onTap: () {
            if (_selecting) {
              _toggleOne(r);
            } else {
              _openDetails(r, asOwner: asOwner);
            }
          },
          onLongPress: _selecting
              ? null
              : () {
                  setState(() => _selecting = true);
                  _toggleOne(r);
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                if (_selecting)
                  Checkbox(
                    value: picked,
                    activeColor: AppTheme.brand,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => _toggleOne(r),
                  ),
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
        leading: _selecting
            ? IconButton(
                tooltip: AppTr.tr('إلغاء التحديد'),
                icon: const Icon(Icons.close_rounded),
                onPressed: _toggleSelecting,
              )
            : null,
        title: Text(
          _selecting
              ? '${AppTr.tr('تم تحديد')} ${_selected.length}'
              : _forEmployee
              ? '${AppTr.tr('رواتب')} ${widget.employeeName}'
              : 'سندات القبض والرواتب',
        ),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: () => setState(() {
                final all = {
                  for (final r in _source)
                    if (r.id != null) r.id!,
                };
                if (_selected.length == all.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(all);
                }
              }),
              child: const Text('تحديد الكل'),
            )
          else if (_source.isNotEmpty)
            IconButton(
              tooltip: AppTr.tr('تحديد سندات للمشاركة'),
              icon: const Icon(Icons.checklist_rounded),
              onPressed: _toggleSelecting,
            ),
        ],
      ),
      // وضع التحديد: مشاركة المحدَّد كملف PDF واحد.
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A5A50),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _sharePdf(_selectedReceipts),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    '${AppTr.tr('مشاركة PDF')} (${_selected.length})',
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: _tab == 0 && !_selecting
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
                        onSelectionChanged: (s) => setState(() {
                          _tab = s.first;
                          _selected.clear();
                        }),
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

  /// صفة الطرفين، وعملة السند (لكل سند وحده).
  late String _parties;
  late String _currency;
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
    _parties = e?.parties ?? SalaryReceipt.partiesEmployer;
    _currency = (e?.currency ?? '').trim().isNotEmpty
        ? e!.currency.trim()
        : AppSettings.currencySuffix;
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

  /// كلمات «الموظف» في الراتب بصفة «صاحب العمل والموظف» فقط.
  bool get _employeeWords =>
      _isSalary && _parties != SalaryReceipt.partiesHandover;

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
      // السند العام: اسم صاحب الرقم مقترح. الراتب: يكتب المرسل اسم الموظف.
      if (name != null && !_isSalary && _name.text.trim().isEmpty) {
        _name.text = name;
      }
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
    // الراتب: الاسم كما كتبه المرسل (اسمين أو أكثر) في الحالتين.
    final name = _isSalary
        ? _name.text.trim().replaceAll(RegExp(r'\s+'), ' ')
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
      error = _employeeWords ? 'اكتب اسم الموظف الحقيقي' : 'اكتب اسم المستلم';
    } else if (_isSalary && nameParts < 2) {
      error = _employeeWords
          ? 'اكتب اسم الموظف الحقيقي من اسمين على الأقل'
          : 'اكتب اسم المستلم من اسمين على الأقل';
    } else if (!_isSalary && _description.text.trim().isEmpty) {
      error = 'اكتب بيان السند';
    } else if (paid <= 0) {
      error = 'أدخل المبلغ المدفوع';
    }
    if (error != null) {
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
            '${_moneyOf(paid, _currency)}',
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
        currency: _currency,
        description: _isSalary ? '' : _description.text.trim(),
        notes: _notes.text.trim(),
        signMode: _signMode,
        status: status,
        signature: signature,
        signedAt: signedAt,
        expenseId: widget.existing?.expenseId ?? '',
        parties: _parties,
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
          typeKey: _employeeWords ? 'person_employee' : 'person_other',
          categoryName: _employeeWords ? 'موظف' : 'أخرى',
          roleTitle: _employeeWords ? 'موظف' : '',
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
    // العملة ظاهرة دائمًا داخل الخانة (suffixText كان لا يظهر إلا بعد
    // الكتابة فيها).
    decoration: _decor(label).copyWith(
      suffixIcon: _currency.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Text(
                _currency,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.muted,
                ),
              ),
            ),
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    ),
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
            const SizedBox(height: 10),
            // صفة الطرفين في السند ونسخته PDF.
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: SalaryReceipt.partiesEmployer,
                  icon: Icon(Icons.business_center_outlined, size: 18),
                  label: Text('صاحب العمل والموظف'),
                ),
                ButtonSegment(
                  value: SalaryReceipt.partiesHandover,
                  icon: Icon(Icons.handshake_outlined, size: 18),
                  label: Text('المسلّم والمستلم'),
                ),
              ],
              selected: {_parties},
              onSelectionChanged: (s) => setState(() => _parties = s.first),
            ),
            const SizedBox(height: 10),
            // عملة السند: الافتراضية من الإعدادات، وتُغيَّر لهذا السند وحده.
            DropdownButtonFormField<String>(
              initialValue: _currency.isEmpty ? null : _currency,
              isExpanded: true,
              decoration: _decor('العملة', icon: Icons.payments_outlined),
              hint: const Text('اختر العملة'),
              items: [
                for (final c in {
                  ...AppSettings.currencySuffixes,
                  if (_currency.isNotEmpty) _currency,
                })
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
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
                      _employeeWords ? '2. الموظف' : '2. المستلم',
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
            // اسم الموظف: يكتبه المرسل في الحالتين (اسمين أو ثلاثة)، ويظهر
            // للموظف كما هو بلا تعديل.
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('salary-employee-name'),
              controller: _name,
              textDirection: AppTr.uiDir,
              onChanged: (_) => setState(() {}),
              decoration: _decor(
                _employeeWords ? 'اكتب اسم الموظف *' : 'اسم المستلم *',
                icon: Icons.person_outline_rounded,
                hint: _isSalary ? AppTr.tr('اسمين أو ثلاثة') : null,
              ),
            ),
            if (_isSalary)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  _employeeWords
                      ? 'إلزامي — اسمين على الأقل، ويظهر للموظف كما كتبته.'
                      : 'إلزامي — اسمين على الأقل، ويظهر للمستلم كما كتبته.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ),
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
                      _moneyOf(_total, _currency),
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
