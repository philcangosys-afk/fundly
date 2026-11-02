import 'dart:convert';

import 'package:flutter/material.dart' hide Text, Align;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/app_settings.dart';
import '../data/document_store.dart';
import '../data/lease_contract_data.dart';
import '../data/project_assets_repository.dart';
import '../widgets/shared/app_design.dart';
import '../data/template_print.dart' show PrintSection, buildRecordPdf;
import 'template_print_screen.dart';

/// دفعة إيجارية مربوطة بعقدها ووحدتها.
///
/// تُستعمل في مكانين بنفس الشكل: «الحركات المالية» في صفحة العقار (كل
/// دفعات وحداته)، وداخل تفاصيل الوحدة (دفعات هذه الوحدة فقط).
class RentPaymentEntry {
  const RentPaymentEntry({
    required this.contract,
    required this.payment,
    required this.unitName,
    required this.order,
    required this.totalInContract,
  });

  final PropertyUnitContractRecord contract;
  final PropertyUnitPaymentRecord payment;
  final String unitName;

  /// ترتيب الدفعة داخل عقدها: «الدفعة 1 من 4».
  final int order;
  final int totalInContract;

  /// الاسم كما كُتب في العقد («دفعة مارس»، «رسوم التسجيل»، «تأمين»)،
  /// وإلا ترقيمها. كان العنوان ترقيمًا دائمًا، فتظهر «رسوم التسجيل»
  /// باسم «الدفعة 5 من 7» ولا يُعرف أنها رسم لا إيجار.
  String get title {
    final extra = decodePayExtra(payment.notes);
    final name = (extra[kPayName] ?? '').trim();
    if (name.isEmpty) return 'الدفعة $order من $totalInContract';
    // اسم هو رقم فقط («1»، «2») لا يُفهم وحده: «الدفعة 1»، «الرسم 1».
    if (RegExp(r'^[0-9٠-٩]+$').hasMatch(name)) {
      return switch (extra[kPayKind] ?? '') {
        kPayKindFee => 'الرسم $name',
        kPayKindDeposit => 'التأمين $name',
        _ => 'الدفعة $name',
      };
    }
    return name;
  }

  /// نوع البند للعرض: «دفعة إيجارية» / «رسوم إدارية» / «تأمين».
  String get kindLabel => (decodePayExtra(payment.notes)[kPayKind] ?? '').trim();
}

// ===== بيانات الدفعة الإضافية داخل عمود الملاحظات (بلا تعديل قاعدة بيانات) =====
const String kPayBeneficiary = 'المستفيد';
const String kPayMethod = 'طريقة الدفع';
const String kPayCheque = 'رقم الشيك';

/// سجل الدفعة: سطر لكل عملية سداد «يوم/شهر/سنة — ما حدث».
const String kPayLog = 'سجل الدفعة';

String _payDmy(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// سطر العقد الذي وُلدت منه الدفعة (دفعة / رسم / تأمين)، مع موضعه.
({Map<String, String> row, int kind, int index})? payLeaseRow(
  RentPaymentEntry entry, [
  LeaseContractData? lease,
]) {
  final rid = (decodePayExtra(entry.payment.notes)[kPayRowId] ?? '').trim();
  if (rid.isEmpty) return null;
  final data = lease ?? LeaseContractData.decode(entry.contract.notes);
  final lists = [data.payments, data.adminFees, data.deposits];
  for (var k = 0; k < lists.length; k++) {
    for (var i = 0; i < lists[k].length; i++) {
      if ((lists[k][i][LeaseContractData.kRowId] ?? '') == rid) {
        return (row: lists[k][i], kind: k, index: i);
      }
    }
  }
  return null;
}

/// ترتيب الدفعات كما في العقد: كل وحدة معًا، وفيها الدفعات الإيجارية ثم
/// الرسوم الإدارية ثم التأمين، وكلٌّ بترتيب سطره ثم بتاريخه.
List<RentPaymentEntry> sortPaymentEntries(List<RentPaymentEntry> entries) {
  final list = List<RentPaymentEntry>.of(entries);
  final index = <RentPaymentEntry, int>{};
  final contractRank = <String, int>{};
  final leases = <String, LeaseContractData>{};
  final rowIndex = <RentPaymentEntry, int>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    index[entry] = i;
    final key = entry.contract.id ?? entry.unitName;
    contractRank.putIfAbsent(key, () => contractRank.length);
    final lease = leases.putIfAbsent(
      key,
      () => LeaseContractData.decode(entry.contract.notes),
    );
    rowIndex[entry] = payLeaseRow(entry, lease)?.index ?? 1 << 20;
  }
  int rankOf(RentPaymentEntry e) =>
      contractRank[e.contract.id ?? e.unitName] ?? 0;
  list.sort((a, b) {
    final byUnit = rankOf(a).compareTo(rankOf(b));
    if (byUnit != 0) return byUnit;
    final byKind = payKindRank(a.payment).compareTo(payKindRank(b.payment));
    if (byKind != 0) return byKind;
    final byRow = rowIndex[a]!.compareTo(rowIndex[b]!);
    if (byRow != 0) return byRow;
    final da = a.payment.dueDate;
    final db = b.payment.dueDate;
    if (da != null && db != null) {
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
    } else if (da != null || db != null) {
      return da == null ? 1 : -1;
    }
    return index[a]!.compareTo(index[b]!);
  });
  return list;
}

String _htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// «كشف الدفعات» بوضعها الحالي: لكل دفعة مبلغها وما استُلم منها وما بقي
/// وحالتها، ثم المجاميع، وتاريخ الطباعة. يُفتح ورقةً للطباعة أو يُشارَك.
Future<void> printPaymentsStatement({
  required BuildContext context,
  required String title,
  required List<RentPaymentEntry> entries,
  bool showUnitName = false,
}) async {
  if (entries.isEmpty) return;
  final rows = sortPaymentEntries(entries);
  final now = DateTime.now();
  final printedAt =
      '${_payDmy(now)} ${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
  final tenants = {
    for (final e in rows)
      if ((e.contract.tenantName ?? '').trim().isNotEmpty)
        e.contract.tenantName!.trim(),
  };
  final due = rows.fold<double>(0, (s, e) => s + e.payment.amountDue);
  final paid = rows.fold<double>(0, (s, e) => s + e.payment.amountPaid);
  final remaining = rows.fold<double>(0, (s, e) => s + payRemaining(e.payment));
  final paidCount = rows.where((e) => payRemaining(e.payment) <= 0).length;

  String statusOf(RentPaymentEntry e) {
    final cheque = payChequeLabel(e);
    return [
      rentPaymentStatusLabel(e.payment),
      if (cheque.isNotEmpty) cheque,
    ].join(' · ');
  }

  // ===== الورقة (HTML) =====
  final html = StringBuffer()
    ..writeln('<!doctype html><html lang="ar" dir="rtl"><head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>كشف الدفعات</title><style>')
    ..writeln('body{font-family:Tahoma,Arial,sans-serif;margin:24px;color:#022E2A}')
    ..writeln('h1{font-size:20px;margin:0 0 4px}')
    ..writeln('.meta{font-size:12px;color:#46534F;margin:2px 0}')
    ..writeln('table{width:100%;border-collapse:collapse;margin-top:14px;font-size:12px}')
    ..writeln('th,td{border:1px solid #CFDAD7;padding:6px;text-align:right}')
    ..writeln('th{background:#E8F1EF}')
    ..writeln('.ok{color:#0E7161;font-weight:bold}.late{color:#B42318;font-weight:bold}')
    ..writeln('.sum td{font-weight:bold;background:#F4F8F7}')
    ..writeln('@media print{body{margin:10mm}}')
    ..writeln('</style></head><body>')
    ..writeln('<h1>كشف الدفعات — ${_htmlEscape(title)}</h1>');
  if (tenants.isNotEmpty) {
    html.writeln(
      '<p class="meta">المستأجر: ${_htmlEscape(tenants.join('، '))}</p>',
    );
  }
  html
    ..writeln('<p class="meta">تاريخ الطباعة: $printedAt</p>')
    ..writeln('<table><thead><tr>')
    ..writeln('<th>#</th>${showUnitName ? '<th>الوحدة</th>' : ''}'
        '<th>البند</th><th>النوع</th><th>الاستحقاق</th><th>المبلغ</th>'
        '<th>المستلم</th><th>المتبقي</th><th>الحالة</th>'
        '<th>تاريخ التحصيل</th><th>طريقة التحصيل</th>')
    ..writeln('</tr></thead><tbody>');
  for (var i = 0; i < rows.length; i++) {
    final e = rows[i];
    final p = e.payment;
    final extra = decodePayExtra(p.notes);
    final label = rentPaymentStatusLabel(p);
    final cls = payRemaining(p) <= 0
        ? 'ok'
        : (label == 'متأخرة' ? 'late' : '');
    html.writeln(
      '<tr><td>${i + 1}</td>'
      '${showUnitName ? '<td>${_htmlEscape(e.unitName)}</td>' : ''}'
      '<td>${_htmlEscape(e.title)}</td>'
      '<td>${_htmlEscape(e.kindLabel)}</td>'
      '<td>${fmtPayDate(p.dueDate)}</td>'
      '<td>${p.amountDue.toStringAsFixed(2)}</td>'
      '<td>${p.amountPaid.toStringAsFixed(2)}</td>'
      '<td>${payRemaining(p).toStringAsFixed(2)}</td>'
      '<td class="$cls">${_htmlEscape(statusOf(e))}</td>'
      '<td>${p.amountPaid > 0.009 ? fmtPayDate(p.paidAt) : '—'}</td>'
      '<td>${_htmlEscape(extra[kPayMethod] ?? '—')}</td></tr>',
    );
  }
  final span = showUnitName ? 5 : 4;
  html
    ..writeln('<tr class="sum"><td colspan="$span">الإجمالي '
        '(${rows.length} بند — المستلم كاملًا $paidCount)</td>'
        '<td>${due.toStringAsFixed(2)}</td>'
        '<td>${paid.toStringAsFixed(2)}</td>'
        '<td>${remaining.toStringAsFixed(2)}</td><td colspan="3"></td></tr>')
    ..writeln('</tbody></table>')
    ..writeln('<p class="meta">المبالغ بـ ${AppSettings.currencySuffix}.</p>')
    ..writeln('</body></html>');

  // ===== النص (للمشاركة) =====
  final text = StringBuffer()
    ..writeln('كشف الدفعات — $title')
    ..writeln('تاريخ الطباعة: $printedAt');
  if (tenants.isNotEmpty) text.writeln('المستأجر: ${tenants.join('، ')}');
  text.writeln();
  for (var i = 0; i < rows.length; i++) {
    final e = rows[i];
    final p = e.payment;
    text.writeln(
      '${i + 1}. ${showUnitName ? '${e.unitName} · ' : ''}${e.title}: '
      '${payMoney(p.amountDue)} · المستلم ${payMoney(p.amountPaid)} · '
      'المتبقي ${payMoney(payRemaining(p))} · ${statusOf(e)} · '
      'استحقاق ${fmtPayDate(p.dueDate)}',
    );
  }
  text
    ..writeln()
    ..writeln('الإجمالي: ${payMoney(due)}')
    ..writeln('المستلم: ${payMoney(paid)}')
    ..writeln('غير المستلم: ${payMoney(remaining)}');

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'كشف الدفعات',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${rows.length} بند · المستلم ${payMoney(paid)} · '
                'غير المستلم ${payMoney(remaining)}\n'
                'تاريخ الطباعة: $printedAt',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final path = await DocumentStore.saveText(
                    'كشف-الدفعات-${now.millisecondsSinceEpoch}.html',
                    html.toString(),
                  );
                  if (!sheetContext.mounted) return;
                  final error = path == null
                      ? 'تعذر حفظ الكشف'
                      : await DocumentStore.open(path);
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.print_outlined, size: 19),
                label: const Text('فتح الكشف للطباعة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await SharePlus.instance.share(
                    ShareParams(text: text.toString()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('مشاركة الكشف'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// ترتيب نوع البند: الدفعات الإيجارية أولًا، ثم الرسوم الإدارية، ثم التأمين.
int payKindRank(PropertyUnitPaymentRecord payment) =>
    switch (decodePayExtra(payment.notes)[kPayKind] ?? '') {
      kPayKindRent => 0,
      kPayKindFee => 1,
      kPayKindDeposit => 2,
      _ => 3,
    };

/// يُعيَّن من شاشة العقارات: يفتح «إدارة الشيكات» لشيك الدفعة (حالته
/// وإجراءاته وسجله). يعيد true إن تغيّر شيء.
Future<bool> Function(
  BuildContext context,
  ProjectAssetsRepository repository,
  RentPaymentEntry entry,
)?
openPaymentChequeManager;

/// طريقة تحصيل البند: من سطره في العقد، وإلا المسجّلة عند سداده.
String payMethodOf(RentPaymentEntry entry, [LeaseContractData? lease]) {
  final fromLease =
      (payLeaseRow(entry, lease)?.row[LeaseContractData.kCollectMethod] ?? '')
          .trim();
  if (fromLease.isNotEmpty) return fromLease;
  return (decodePayExtra(entry.payment.notes)[kPayMethod] ?? '').trim();
}

/// حالة الشيك بجانب الدفعة: «استُلم الشيك»، «الشيك في البنك»،
/// «حُصِّل المبلغ»… — فارغة إن لم تكن الدفعة بشيك.
String payChequeLabel(RentPaymentEntry entry, [LeaseContractData? lease]) {
  final found = payLeaseRow(entry, lease);
  if (found == null) return '';
  final row = found.row;
  final number = (row[LeaseContractData.kPaymentCheque] ?? '').trim();
  final method = (row[LeaseContractData.kCollectMethod] ?? '').trim();
  if (number.isEmpty && method != 'شيك') return '';
  var state = (row[LeaseContractData.kChequeState] ?? '').trim();
  if (state.isEmpty) {
    final payment = entry.payment;
    state = payment.amountPaid > 0.009 && payRemaining(payment) <= 0
        ? LeaseContractData.chequeCleared
        : LeaseContractData.chequeReceived;
  }
  return switch (state) {
    LeaseContractData.chequeReceived => 'استُلم الشيك (لم يُصرف)',
    LeaseContractData.chequeAtBank => 'الشيك في البنك',
    LeaseContractData.chequeCleared => 'حُصِّل المبلغ',
    LeaseContractData.chequeRejected => 'الشيك مرفوض',
    LeaseContractData.chequeReturned => 'الشيك مرتجع',
    LeaseContractData.chequeCancelled => 'الشيك ملغى',
    LeaseContractData.chequeReplaced => 'استُبدل الشيك',
    _ => state,
  };
}

/// أسطر سجل الدفعة. الدفعة المسددة قبل وجود السجل تُعطى سطرًا من تاريخ
/// سدادها.
List<String> payLogLines(PropertyUnitPaymentRecord payment) {
  final extra = decodePayExtra(payment.notes);
  final log = (extra[kPayLog] ?? '').trim();
  if (log.isNotEmpty) {
    return log
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
  if (payment.amountPaid <= 0.009) return const <String>[];
  final paidAt = payment.paidAt;
  final method = (extra[kPayMethod] ?? '').trim();
  final kind = payRemaining(payment) > 0 ? 'سداد جزئي' : 'سداد كلي';
  return [
    '${paidAt == null ? '' : '${_payDmy(paidAt)} — '}'
        '$kind ${payMoney(payment.amountPaid)}'
        '${method.isEmpty ? '' : ' · $method'}',
  ];
}

/// نوع البند واسمه ومعرّف سطره في العقد — تُكتب عند ربط العقد بالجدول.
const String kPayKind = 'نوع البند';
const String kPayName = 'اسم البند';
const String kPayRowId = 'معرّف البند';

const String kPayKindRent = 'دفعة إيجارية';
const String kPayKindFee = 'رسوم إدارية';
const String kPayKindDeposit = 'تأمين';

/// المتبقي على البند — لا يقلّ عن صفر.
/// دفعة متبقية لعقد مُغلق لا تُتابَع: سُوّيت مبالغه عند الإلغاء
/// ([LeaseContractData.isSettled])، أو استحقاقها بعد تاريخ إغلاقه.
/// ما استُحق قبل الإغلاق ولم يُسوَّ يبقى مستحقًا يُتابَع في الحركات المالية.
bool paymentWaivedByClosure(
  PropertyUnitContractRecord contract,
  PropertyUnitPaymentRecord payment,
) {
  final closed =
      contract.status == PropertyUnitContractRecord.statusExpired ||
      contract.status == 'ended' ||
      contract.status == 'cancelled';
  if (!closed) return false;
  if (payRemaining(payment) <= 0.009) return false;
  if (LeaseContractData.isSettled(contract.notes)) return true;
  final closedOn =
      DateTime.tryParse(
        (LeaseContractData.decode(contract.notes).contract['تاريخ إلغاء العقد'] ??
                '')
            .trim(),
      ) ??
      contract.endDate;
  final due = payment.dueDate;
  if (due == null || closedOn == null) return false;
  return DateUtils.dateOnly(due).isAfter(DateUtils.dateOnly(closedOn));
}

double payRemaining(PropertyUnitPaymentRecord payment) {
  final remaining = payment.amountDue - payment.amountPaid;
  return remaining > 0.009 ? remaining : 0;
}

/// الحالة المشتقّة من المبلغين: مسددة، جزئية، أو قائمة.
String payStatusFor(double due, double paid) {
  if (due > 0 && paid + 0.009 >= due) return PropertyUnitPaymentRecord.statusPaid;
  if (paid > 0.009) return PropertyUnitPaymentRecord.statusPartial;
  return PropertyUnitPaymentRecord.statusPending;
}

/// بند مطلوب من العقد قبل تحويله إلى سجل.
class _LeaseDue {
  _LeaseDue({
    required this.rowId,
    required this.kind,
    required this.name,
    required this.amount,
    required this.dueDate,
    required this.method,
    required this.cheque,
    required this.initialPaid,
  });

  final String rowId;
  final String kind;
  final String name;
  final double amount;
  final DateTime? dueDate;
  final String method;
  final String cheque;
  final double initialPaid;
}

double _leaseNum(String? raw) {
  if (raw == null) return 0;
  return double.tryParse(
        raw.replaceAll(',', '').replaceAll('٬', '').trim(),
      ) ??
      0;
}

DateTime? _leaseDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

bool _sameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// سطر تأمين من العقد.
///
/// التأمين لا ضريبة عليه. و«تاريخ تحصيل التأمين» في الماضي أو اليوم يعني
/// أنه حُصِّل عند التوقيع، فيُسجَّل مسددًا؛ وفي المستقبل يبقى مستحقًا.
_LeaseDue _depositDue(
  Map<String, String> row,
  DateTime? start,
  DateTime today,
) {
  final amount = _leaseNum(row[LeaseContractData.kDepositAmount]);
  final method = (row[LeaseContractData.kCollectMethod] ?? '').trim();
  if (method == 'شيك') {
    return _LeaseDue(
      rowId: row[LeaseContractData.kRowId] ?? '',
      kind: kPayKindDeposit,
      name: 'تأمين العقد',
      amount: amount,
      dueDate: _leaseDate(row[LeaseContractData.kPaymentChequeDate]),
      method: method,
      cheque: (row[LeaseContractData.kPaymentCheque] ?? '').trim(),
      // التأمين يبقى «مستحقًا» حتى يُحصَّل، وبلا تاريخ إن لم يُكتب تاريخ.
      initialPaid: 0,
    );
  }
  final date = _leaseDate(row['تاريخ تحصيل التأمين']);
  return _LeaseDue(
    rowId: row[LeaseContractData.kRowId] ?? '',
    kind: kPayKindDeposit,
    name: 'تأمين العقد',
    amount: amount,
    // التأمين بلا تاريخ تحصيل يبقى بلا تاريخ — لا يُعطى تاريخ بداية العقد.
    dueDate: date,
    method: (row[LeaseContractData.kCollectMethod] ?? '').trim(),
    cheque: (row[LeaseContractData.kPaymentCheque] ?? '').trim(),
    initialPaid: date != null && !date.isAfter(today) ? amount : 0,
  );
}

/// يربط دفعات العقد المكتوبة في نموذجه بجدول الدفعات.
///
/// هذه هي الحلقة التي كانت مقطوعة: نموذج العقد يحفظ الدفعات والرسوم
/// والتأمين داخل نصّ العقد وحده، بينما «الدفعات» و«التحصيل» ومركز
/// المتابعة وبطاقة الوحدة كلها تقرأ من جدول property_unit_payments. فتُكتب
/// اثنتا عشرة دفعة في العقد، ثم تظهر الوحدة «بلا دفعات» وأصفار في كل
/// إجمالي، ولا يوجد ما يُحصَّل.
///
/// القواعد:
/// - لكل سطر في العقد سجلٌّ واحد، يُعرف بمعرّف السطر لا بترتيبه.
/// - ما سُدِّد لا يُمسّ: تعديل المبلغ في العقد يحدّث المستحق ويُبقي
///   المسدد، والحالة تُعاد حسابها من المبلغين.
/// - سطر حُذف من العقد يُحذف سجلّه **فقط إن لم يُحصَّل منه شيء**؛ وإلا
///   يبقى، لأن المال المستلم واقعة لا يمحوها تعديل عقد.
/// - السجلات المضافة يدويًا (بلا معرّف سطر) لا تُلمس.
///
/// يعيد `true` إن كُتب أي شيء، فيعيد المستدعي التحميل.
Future<bool> syncLeasePaymentRecords({
  required ProjectAssetsRepository repository,
  required PropertyUnitContractRecord contract,
  List<PropertyUnitPaymentRecord>? existing,
}) async {
  final contractId = contract.id;
  if (contractId == null || contractId.isEmpty) return false;
  final lease = LeaseContractData.decode(contract.notes);
  var wrote = false;

  // عقود حُفظت قبل المعرّفات: تُمنح معرّفاتها وتُحفظ مرة واحدة.
  if (lease.ensureRowIds()) {
    await repository.upsertUnitContract(
      contract.copyWith(notes: lease.encode()),
    );
    wrote = true;
  }

  final start = contract.startDate;
  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  final wanted = <_LeaseDue>[
    for (final row in lease.payments)
      if (_leaseNum(row[LeaseContractData.kPaymentAmount]) > 0)
        _LeaseDue(
          rowId: row[LeaseContractData.kRowId] ?? '',
          kind: kPayKindRent,
          name: (row[LeaseContractData.kPaymentFee] ?? '').trim().isEmpty
              ? 'دفعة إيجارية'
              : row[LeaseContractData.kPaymentFee]!.trim(),
          // المستحق يشمل الضريبة: هذا ما سيُدفع فعلًا.
          amount: _leaseNum(row[LeaseContractData.kPaymentAmount]) +
              lease.paymentTaxOf(row),
          dueDate: _leaseDate(row[LeaseContractData.kPaymentDue]) ?? start,
          method: (row[LeaseContractData.kCollectMethod] ?? '').trim(),
          cheque: (row[LeaseContractData.kPaymentCheque] ?? '').trim(),
          initialPaid:
              (row[LeaseContractData.kPaymentStatus] ?? '') == 'مسددة'
              ? _leaseNum(row[LeaseContractData.kPaymentAmount]) +
                    lease.paymentTaxOf(row)
              : 0,
        ),
    for (final row in lease.adminFees)
      if (_leaseNum(row[LeaseContractData.kAdminFeeAmount]) > 0)
        _LeaseDue(
          rowId: row[LeaseContractData.kRowId] ?? '',
          kind: kPayKindFee,
          name: (row[LeaseContractData.kAdminFeeType] ?? '').trim().isEmpty
              ? 'رسوم إدارية'
              : row[LeaseContractData.kAdminFeeType]!.trim(),
          amount: _leaseNum(row[LeaseContractData.kAdminFeeAmount]) +
              lease.adminFeeTaxOf(row),
          dueDate: _leaseDate(row[LeaseContractData.kAdminFeeDue]) ?? start,
          method: (row[LeaseContractData.kCollectMethod] ?? '').trim(),
          cheque: '',
          initialPaid: 0,
        ),
    for (final row in lease.deposits)
      if (_leaseNum(row[LeaseContractData.kDepositAmount]) > 0)
        _depositDue(row, start, today),
  ];

  final current =
      existing ?? await repository.fetchUnitPayments(contractId);
  final byRow = <String, PropertyUnitPaymentRecord>{};
  for (final record in current) {
    final rid = (decodePayExtra(record.notes)[kPayRowId] ?? '').trim();
    if (rid.isNotEmpty) byRow[rid] = record;
  }

  final seen = <String>{};
  for (final due in wanted) {
    if (due.rowId.isEmpty) continue;
    seen.add(due.rowId);
    final old = byRow[due.rowId];
    final extra = <String, String>{
      ...decodePayExtra(old?.notes),
      kPayKind: due.kind,
      kPayName: due.name,
      kPayRowId: due.rowId,
      if (due.method.isNotEmpty) kPayMethod: due.method,
      if (due.cheque.isNotEmpty) kPayCheque: due.cheque,
    };
    final paid = old == null ? due.initialPaid : old.amountPaid;
    final next = PropertyUnitPaymentRecord(
      id: old?.id,
      contractId: contractId,
      // التأمين: تاريخه كما في العقد (وبلا تاريخ إن لم يُكتب)، فلا يبقى
      // تاريخ قديم أُعطي له سابقًا.
      dueDate: due.kind == kPayKindDeposit
          ? due.dueDate
          : (due.dueDate ?? old?.dueDate),
      amountDue: due.amount,
      amountPaid: paid,
      paidAt: old?.paidAt ?? (paid > 0 ? DateTime.now() : null),
      status: payStatusFor(due.amount, paid),
      referenceNo: due.cheque.isEmpty ? old?.referenceNo : due.cheque,
      notes: encodePayExtra(extra),
    );
    if (old != null &&
        (old.amountDue - next.amountDue).abs() < 0.009 &&
        (old.amountPaid - next.amountPaid).abs() < 0.009 &&
        _sameDay(old.dueDate, next.dueDate) &&
        old.status == next.status &&
        (old.referenceNo ?? '') == (next.referenceNo ?? '') &&
        (old.notes ?? '') == (next.notes ?? '')) {
      continue;
    }
    await repository.upsertUnitPayment(next);
    wrote = true;
  }

  for (final entry in byRow.entries) {
    if (seen.contains(entry.key)) continue;
    final record = entry.value;
    if (record.id == null || record.amountPaid > 0.009) continue;
    await repository.deleteUnitPayment(record.id!);
    wrote = true;
  }
  return wrote;
}

Map<String, String> decodePayExtra(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return <String, String>{};
  if (!text.startsWith('{')) return <String, String>{'ملاحظة': text};
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return <String, String>{'ملاحظة': text};
    final out = <String, String>{};
    decoded.forEach((key, value) {
      if (key == '__pay__') return;
      final v = '${value ?? ''}'.trim();
      if (v.isNotEmpty) out['$key'] = v;
    });
    return out;
  } catch (_) {
    return <String, String>{'ملاحظة': text};
  }
}

String encodePayExtra(Map<String, String> data) {
  final clean = <String, dynamic>{'__pay__': 1};
  data.forEach((key, value) {
    if (value.trim().isNotEmpty) clean[key] = value.trim();
  });
  return jsonEncode(clean);
}

/// حالة الدفعة كما تظهر للمستخدم: مدفوعة / متأخرة / مجدولة / مستحقة.
String rentPaymentStatusLabel(PropertyUnitPaymentRecord payment) {
  if (payment.status == PropertyUnitPaymentRecord.statusPaid) return 'مدفوعة';
  if (payment.status == PropertyUnitPaymentRecord.statusPartial) {
    return 'مدفوعة جزئيًا';
  }
  if (payment.status == PropertyUnitPaymentRecord.statusLate) return 'متأخرة';
  final due = payment.dueDate;
  if (due != null) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (due.isBefore(today)) return 'متأخرة';
    if (due.isAfter(today.add(const Duration(days: 7)))) return 'قادمة';
  }
  return 'مستحقة';
}

Color rentPaymentStatusColor(String label) => switch (label) {
  'مدفوعة' => const Color(0xFF0E7161),
  'مدفوعة جزئيًا' => const Color(0xFF178F7B),
  'متأخرة' => const Color(0xFFC4392E),
  'قادمة' => const Color(0xFF5C6B68),
  _ => const Color(0xFFA6691A),
};

String fmtPayDate(DateTime? date) {
  if (date == null) return 'غير محدد';
  return '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

String payMoney(double value) =>
    '${value.toStringAsFixed(2)} ${AppSettings.currencySuffix}';

/// صفحة سداد الدفعة — الشكل الواحد لكل مكان تُفتح منه دفعة.
///
/// لكل دفعة: بياناتها، وتحتها «نوع السداد» (كلي/جزئي) و«طريقة التحصيل»،
/// ومع الجزئي مبلغه، ومع الشيك رقمه. ثم تاريخ التحصيل، و«سداد» ← مراجعة
/// وتأكيد ← رسالة بما سُجِّل. سند القبض والمطالبة المالية في الثلاث نقاط.
///
/// تعيد `true` إن سُجِّل سداد.
Future<bool> openPaymentSettlePage({
  required BuildContext context,
  required ProjectAssetsRepository repository,
  required List<RentPaymentEntry> entries,
  bool showUnitName = false,
  Future<void> Function(RentPaymentEntry entry, String action)? onMenu,
}) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => _PaymentSettlePage(
        repository: repository,
        entries: entries,
        showUnitName: showUnitName,
        onMenu: onMenu,
      ),
    ),
  );
  return changed == true;
}

class _PaymentSettlePage extends StatefulWidget {
  const _PaymentSettlePage({
    required this.repository,
    required this.entries,
    required this.showUnitName,
    required this.onMenu,
  });

  final ProjectAssetsRepository repository;
  final List<RentPaymentEntry> entries;
  final bool showUnitName;

  /// الثلاث نقاط: «share» / «receipt» / «demand» / «edit».
  final Future<void> Function(RentPaymentEntry entry, String action)? onMenu;

  @override
  State<_PaymentSettlePage> createState() => _PaymentSettlePageState();
}

class _PaymentSettlePageState extends State<_PaymentSettlePage> {
  static const _full = 'كلي';
  static const _partial = 'جزئي';

  final Map<String, String> _modes = {};
  final Map<String, String> _methods = {};
  final Map<String, TextEditingController> _amounts = {};
  final Map<String, TextEditingController> _cheques = {};
  late DateTime _date;
  String _error = '';
  bool _saving = false;

  /// «ملاحظات» تحت تاريخ التحصيل — تُحفظ مع الدفعة وفي سجلها.
  final TextEditingController _noteCtrl = TextEditingController();

  List<RentPaymentEntry> get _payable => widget.entries
      .where((e) => e.payment.id != null && payRemaining(e.payment) > 0)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    for (final entry in widget.entries) {
      final id = entry.payment.id;
      if (id == null) continue;
      final extra = decodePayExtra(entry.payment.notes);
      final stored = (extra[kPayMethod] ?? '').trim();
      _modes[id] = _full;
      _methods[id] = LeaseContractData.collectMethods.contains(stored)
          ? stored
          : 'كاش';
      _amounts[id] = TextEditingController(
        text: payRemaining(entry.payment).toStringAsFixed(2),
      );
      _cheques[id] = TextEditingController(
        text: extra[kPayCheque] ?? entry.payment.referenceNo ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [..._amounts.values, ..._cheques.values]) {
      controller.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  double _amountOf(RentPaymentEntry entry) {
    final id = entry.payment.id!;
    if (_modes[id] == _full) return payRemaining(entry.payment);
    return double.tryParse(
          _amounts[id]!.text.replaceAll(',', '').trim(),
        ) ??
        0;
  }

  Future<void> _submit() async {
    final payable = _payable;
    for (final entry in payable) {
      final amount = _amountOf(entry);
      final remaining = payRemaining(entry.payment);
      if (amount <= 0 || amount > remaining + 0.009) {
        setState(
          () => _error =
              'مبلغ «${entry.title}» يجب أن يكون أكبر من صفر ولا يتجاوز '
              'المتبقي ${payMoney(remaining)}.',
        );
        return;
      }
      final id = entry.payment.id!;
      if (_methods[id] == 'شيك' && _cheques[id]!.text.trim().isEmpty) {
        setState(() => _error = 'اكتب رقم الشيك لـ«${entry.title}».');
        return;
      }
    }
    setState(() => _error = '');

    // مراجعة قبل الحفظ: ما سيُسجَّل بندًا بندًا.
    final total = payable.fold<double>(0, (sum, e) => sum + _amountOf(e));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('تأكيد السداد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // كل بند باسمه ونوعه في سطر، وتفاصيل سداده تحته — فيُعرف
                // أي دفعة هي وأي رسم.
                for (final entry in payable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                            if (widget.showUnitName) entry.unitName,
                            entry.title,
                          ].join(' · ') +
                              (entry.kindLabel.isEmpty
                                  ? ''
                                  : ' (${entry.kindLabel})'),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                        Text(
                          'سداد ${_modes[entry.payment.id!]} · '
                          '${_methods[entry.payment.id!]} · '
                          '${payMoney(_amountOf(entry))}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF46534F),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                Text(
                  'المجموع: ${payMoney(total)}\n'
                  'تاريخ التحصيل: ${fmtPayDate(_date)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأكيد السداد'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    var done = 0;
    final failures = <String>[];
    for (final entry in payable) {
      final payment = entry.payment;
      final id = payment.id!;
      final amount = _amountOf(entry);
      final paid = payment.amountPaid + amount;
      final method = _methods[id]!;
      final cheque = _cheques[id]!.text.trim();
      final oldExtra = decodePayExtra(payment.notes);
      final previousLog = (oldExtra[kPayLog] ?? '').trim();
      final note = _noteCtrl.text.trim().replaceAll('\n', ' ');
      final logLine =
          '${_payDmy(_date)} — '
          '${_modes[id] == _full ? 'سداد كلي' : 'سداد جزئي'} '
          '${payMoney(amount)} · $method'
          '${method == 'شيك' && cheque.isNotEmpty ? ' رقم $cheque' : ''}'
          '${note.isEmpty ? '' : ' — $note'}';
      try {
        await widget.repository.upsertUnitPayment(
          payment.copyWith(
            amountPaid: paid,
            paidAt: _date,
            status: payStatusFor(payment.amountDue, paid),
            referenceNo: method == 'شيك' && cheque.isNotEmpty
                ? cheque
                : payment.referenceNo,
            notes: encodePayExtra(<String, String>{
              ...oldExtra,
              kPayMethod: method,
              if (method == 'شيك' && cheque.isNotEmpty) kPayCheque: cheque,
              if (note.isNotEmpty) 'ملاحظة': note,
              kPayLog: [
                if (previousLog.isNotEmpty) previousLog,
                logLine,
              ].join('\n'),
            }),
          ),
        );
        done++;
      } catch (error) {
        failures.add('${entry.title}: $error');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (failures.isNotEmpty) {
      setState(
        () => _error =
            'سُجِّل $done، وتعذّر ${failures.length}: ${failures.first}',
      );
      return;
    }
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          done == 1
              ? 'تم تسجيل سداد «${payable.first.title}» بمبلغ ${payMoney(total)}'
              : 'تم تسجيل سداد $done دفعات بمجموع ${payMoney(total)}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: AppTr.tr(label),
    filled: true,
    fillColor: AppTheme.field,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rIcon),
      borderSide: BorderSide.none,
    ),
  );

  Widget _dataRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        textDirection: AppTr.uiDir,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color ?? const Color(0xFF022E2A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(RentPaymentEntry entry) {
    final onMenu = widget.onMenu;
    if (onMenu == null) return const SizedBox.shrink();
    final payment = entry.payment;
    return PopupMenuButton<String>(
      tooltip: AppTr.tr('خيارات الدفعة'),
      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF46534F)),
      onSelected: (value) async {
        Navigator.of(context).pop(false);
        await onMenu(entry, value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('تعديل بيانات الدفعة')),
        const PopupMenuItem(value: 'share', child: Text('مشاركة')),
        // سند القبض بما استُلم، والمطالبة بما بقي — لكلٍّ وقته.
        PopupMenuItem(
          value: 'receipt',
          enabled: payment.amountPaid > 0,
          child: const Text('سند قبض'),
        ),
        PopupMenuItem(
          value: 'demand',
          enabled: payRemaining(payment) > 0,
          child: const Text('مطالبة مالية'),
        ),
      ],
    );
  }

  /// دفعة إيجارية بشيك (لها سطر في العقد يُدار شيكه).
  bool _isChequeEntry(RentPaymentEntry entry) {
    final found = payLeaseRow(entry);
    if (found == null || found.kind != 0) return false;
    return (found.row[LeaseContractData.kPaymentCheque] ?? '')
        .trim()
        .isNotEmpty;
  }

  Future<void> _openChequeManager(RentPaymentEntry entry) async {
    final open = openPaymentChequeManager;
    if (open == null) return;
    final changed = await open(context, widget.repository, entry);
    // تغيّرت حالة الشيك (قد يكون حُصِّل فسُدِّدت الدفعة): تُغلق الصفحة
    // ويُعاد تحميل الدفعات بحالتها الجديدة.
    if (changed && mounted) Navigator.of(context).pop(true);
  }

  Widget _card(RentPaymentEntry entry) {
    final payment = entry.payment;
    final id = payment.id;
    final label = rentPaymentStatusLabel(payment);
    final extra = decodePayExtra(payment.notes);
    final remaining = payRemaining(payment);
    final payable = id != null && remaining > 0;
    final cheque = (extra[kPayCheque] ?? payment.referenceNo ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // دفعة بشيك: حركة الشيك (إرسال للبنك، تحصيل، رفض...) تُسجَّل
          // وتُتابَع من «إدارة الشيكات».
          if (_isChequeEntry(entry) && openPaymentChequeManager != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _openChequeManager(entry),
                borderRadius: BorderRadius.circular(AppTheme.rIcon),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.goldDark.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                    border: Border.all(
                      color: AppTheme.goldDark.withValues(alpha: 0.3),
                    ),
                  ),
                  // الجملة بعرض المستطيل كله، والرابط تحتها في طرفه.
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.request_quote_outlined,
                            size: 18,
                            color: AppTheme.goldDark,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'لتسجيل ومتابعة حركة الشيك اضغط على «إدارة الشيكات»',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF46534F),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'إدارة الشيكات',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.goldDark,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 18,
                            color: AppTheme.goldDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Text(
                  widget.showUnitName
                      ? '${entry.unitName} · ${entry.title}'
                      : entry.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: rentPaymentStatusColor(label).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: rentPaymentStatusColor(label),
                  ),
                ),
              ),
              if (widget.entries.length > 1) _menu(entry),
            ],
          ),
          const SizedBox(height: 8),
          _dataRow('المبلغ المستحق', payMoney(payment.amountDue)),
          if (payment.amountPaid > 0)
            _dataRow(
              'المسدد',
              payMoney(payment.amountPaid),
              color: const Color(0xFF0E7161),
            ),
          if (payment.amountPaid > 0)
            _dataRow('المتبقي', payMoney(remaining), color: AppTheme.goldDark),
          _dataRow('تاريخ الاستحقاق', fmtPayDate(payment.dueDate)),
          _dataRow('المستأجر', entry.contract.tenantName ?? 'غير محدد'),
          if ((extra[kPayBeneficiary] ?? '').isNotEmpty)
            _dataRow('المستفيد', extra[kPayBeneficiary]!),
          if ((extra[kPayMethod] ?? '').isNotEmpty && !payable)
            _dataRow('طريقة التحصيل', extra[kPayMethod]!),
          if (cheque.isNotEmpty) _dataRow('رقم الشيك', cheque),
          if (payChequeLabel(entry).isNotEmpty)
            _dataRow('حالة الشيك', payChequeLabel(entry)),
          if (payment.amountPaid > 0.009)
            _dataRow('تاريخ التحصيل', fmtPayDate(payment.paidAt)),
          if ((extra['ملاحظة'] ?? '').trim().isNotEmpty)
            _dataRow('ملاحظات', extra['ملاحظة']!.trim()),
          if (payable) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppTheme.hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _modes[id],
                    isExpanded: true,
                    decoration: _decoration('نوع السداد'),
                    items: const [
                      DropdownMenuItem(value: _full, child: Text('كلي')),
                      DropdownMenuItem(value: _partial, child: Text('جزئي')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _modes[id] = value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _methods[id],
                    isExpanded: true,
                    decoration: _decoration('طريقة التحصيل'),
                    items: [
                      for (final option in LeaseContractData.collectMethods)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _methods[id] = value);
                    },
                  ),
                ),
              ],
            ),
            if (_modes[id] == _partial) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _amounts[id],
                textAlign: AppTr.alignEnd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: _decoration(
                  'المبلغ المستلم الآن (المتبقي ${payMoney(remaining)})',
                ),
              ),
            ],
            if (_methods[id] == 'شيك') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _cheques[id],
                textAlign: AppTr.alignEnd,
                decoration: _decoration('رقم الشيك'),
              ),
            ],
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'سُدِّدت هذه الدفعة بالكامل.',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0E7161),
              ),
            ),
          ],
          // سجل الدفعة: كل سداد وكل تعديل بتاريخه.
          if (payLogLines(payment).isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.hairline),
            const SizedBox(height: 10),
            const Text(
              'سجل الدفعة',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              payLogLines(payment).join('\n'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.8,
                fontWeight: FontWeight.w600,
                color: Color(0xFF46534F),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payable = _payable;
    final single = widget.entries.length == 1;
    final total = payable.fold<double>(0, (sum, e) => sum + _amountOf(e));
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: Text(
            single
                ? widget.entries.first.title
                : 'سداد ${widget.entries.length} دفعات',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          actions: [if (single) _menu(widget.entries.first)],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            for (final entry in widget.entries) _card(entry),
            if (payable.isNotEmpty) ...[
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rIcon),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2070),
                    helpText: AppTr.tr('تاريخ التحصيل'),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: _decoration('تاريخ التحصيل'),
                  child: Text(
                    fmtPayDate(_date),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                textAlign: AppTr.alignEnd,
                minLines: 1,
                maxLines: 3,
                decoration: _decoration('ملاحظات'),
              ),
              const SizedBox(height: 12),
              if (_error.isNotEmpty) ...[
                Text(
                  _error,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.task_alt_rounded, size: 19),
                label: Text(
                  _saving
                      ? 'جارٍ التسجيل...'
                      : 'سداد · ${payMoney(total)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// عرض «الدفعات الإيجارية» الكامل: فلتر الحالات، سجل الدفعات، صفوف
/// الدفعات بمربعات اختيار، وتفاصيل الدفعة بأزرار السداد وسند القبض
/// والمطالبة المالية.
class RentPaymentsView extends StatefulWidget {
  const RentPaymentsView({
    super.key,
    required this.repository,
    required this.assetTitle,
    required this.entries,
    required this.onChanged,
    this.showUnitName = true,
    this.showHeaderRow = true,
    this.filter,
    this.onFilterChanged,
    this.onNext,
    this.emptyMessage =
        'لا توجد دفعات بعد — تُولَّد الدفعات من عقد الإيجار الكامل للوحدة.',
    this.accent = const Color(0xFF0A5A50),
    this.unitTypeOf,
  });

  /// نوع الوحدة من اسمها (شقة، محل...) — لسطر «نوع الوحدة / اسم الوحدة».
  final String Function(String unitName)? unitTypeOf;

  final ProjectAssetsRepository repository;
  final String assetTitle;
  final List<RentPaymentEntry> entries;

  /// يُستدعى بعد أي تعديل ليعيد الشاشة الأم تحميل البيانات.
  final Future<void> Function() onChanged;

  final bool showUnitName;

  /// سطر «العناصر: N + الفلتر» داخل القسم — يُطفأ عندما يكون الفلتر
  /// مرفوعًا إلى شريط الرأس أعلى الصفحة.
  final bool showHeaderRow;

  /// الفلتر المُدار من الشاشة الأم (مع [onFilterChanged]).
  final String? filter;
  final ValueChanged<String>? onFilterChanged;

  /// زر «التالي»: يأخذ الدفعات المؤشَّرة إلى خطوة السداد.
  final VoidCallback? onNext;

  final String emptyMessage;
  final Color accent;

  @override
  State<RentPaymentsView> createState() => _RentPaymentsViewState();
}

class _RentPaymentsViewState extends State<RentPaymentsView> {
  static const List<String> _filterOptions = [
    'الكل',
    'مستحقة',
    'متأخرة',
    'قادمة',
    'مدفوعة',
  ];

  String _internalFilter = 'الكل';
  final Set<String> _selected = <String>{};

  String get _filter => widget.filter ?? _internalFilter;

  void _setFilter(String value) {
    if (widget.onFilterChanged != null) {
      widget.onFilterChanged!(value);
    } else {
      setState(() => _internalFilter = value);
    }
  }

  List<RentPaymentEntry> get _visible {
    final list = _filter == 'الكل'
        ? List<RentPaymentEntry>.of(widget.entries)
        : widget.entries.where((entry) {
            final label = rentPaymentStatusLabel(entry.payment);
            if (_filter == 'مدفوعة') {
              return label == 'مدفوعة' || label == 'مدفوعة جزئيًا';
            }
            return label == _filter;
          }).toList();
    return sortPaymentEntries(list);
  }

  /// «سجل الدفعات» أسفل القائمة: كل عملية سداد بتاريخها. الدفعات المسددة
  /// قبل وجود السجل تظهر بسطر من تاريخ سدادها.
  Widget _paymentsLog() {
    final lines = <({DateTime? date, int seq, String text})>[];
    var seq = 0;
    for (final entry in widget.entries) {
      final payment = entry.payment;
      final extra = decodePayExtra(payment.notes);
      final name = widget.showUnitName
          ? '${entry.unitName} · ${entry.title}'
          : entry.title;
      final log = (extra[kPayLog] ?? '').trim();
      if (log.isNotEmpty) {
        for (final raw in log.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final cut = line.indexOf(' — ');
          final day = cut > 0 ? line.substring(0, cut) : '';
          final rest = cut > 0 ? line.substring(cut + 3) : line;
          final parts = day.split('/');
          DateTime? date;
          if (parts.length == 3) {
            final d = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            final y = int.tryParse(parts[2]);
            if (d != null && m != null && y != null) date = DateTime(y, m, d);
          }
          lines.add((
            date: date,
            seq: seq++,
            text: '${day.isEmpty ? '' : '$day — '}«$name»: $rest',
          ));
        }
      } else if (payment.amountPaid > 0.009) {
        final paidAt = payment.paidAt;
        final method = (extra[kPayMethod] ?? '').trim();
        final kind = payRemaining(payment) > 0 ? 'سداد جزئي' : 'سداد كلي';
        lines.add((
          date: paidAt,
          seq: seq++,
          text: '${paidAt == null ? '' : '${_payDmy(paidAt)} — '}'
              '«$name»: $kind ${payMoney(payment.amountPaid)}'
              '${method.isEmpty ? '' : ' · $method'}',
        ));
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    lines.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da != null && db != null && da != db) return da.compareTo(db);
      if ((da == null) != (db == null)) return da == null ? 1 : -1;
      return a.seq.compareTo(b.seq);
    });
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سجل الدفعات',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF022E2A),
            ),
          ),
          const SizedBox(height: 6),
          // كل سطر يبدأ بخط قصير فيُرى أنه سطر مستقل.
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                textDirection: AppTr.uiDir,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E7161),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      line.text,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF46534F),
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

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeaderRow)
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Text(
              'العناصر: ${visible.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: AppTr.tr('تصفية الدفعات'),
              position: PopupMenuPosition.under,
              onSelected: _setFilter,
              itemBuilder: (context) => [
                for (final option in _filterOptions)
                  PopupMenuItem<String>(
                    value: option,
                    child: Text(
                      option,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: option == _filter
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: option == _filter
                            ? widget.accent
                            : const Color(0xFF022E2A),
                      ),
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _filter,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: Color(0xFF0E7161),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.showHeaderRow) const SizedBox(height: 10),
        // صفحة العقار: إجمالي الدفعات والمسدد والمتبقي في ثلاثة مربعات،
        // وتحتها «التفاصيل المالية للوحدات» و«طباعة».
        if (widget.showUnitName)
          _propertyTotals()
        else
        // إجمالي الدفعات بعددها — معلومة للقراءة، لا زر.
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 15,
                  color: widget.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'إجمالي الدفعات '
                        '${payMoney(widget.entries.fold<double>(0, (sum, e) => sum + e.payment.amountDue))}'
                        ' (${widget.entries.length})',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // ما دُفع وما بقي في الصفحة نفسها.
                      Wrap(
                        textDirection: AppTr.uiDir,
                        spacing: 14,
                        children: [
                          Text(
                            'المسدد ${payMoney(widget.entries.fold<double>(0, (sum, e) => sum + e.payment.amountPaid))}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0E7161),
                            ),
                          ),
                          Text(
                            'المتبقي ${payMoney(widget.entries.fold<double>(0, (sum, e) => sum + payRemaining(e.payment)))}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.goldDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // صفحة العقار: جدول الدفعات لكل وحدة (الإيجارية والإدارية
                // والتأمين منفصلًا).
                if (widget.showUnitName && widget.entries.isNotEmpty)
                  TextButton.icon(
                    onPressed: _openBreakdown,
                    style: TextButton.styleFrom(
                      foregroundColor: widget.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 34),
                    ),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text(
                      'تفصيل الوحدات',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                // كشف الدفعات بوضعها الحالي مع تاريخ الطباعة.
                if (widget.entries.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => printPaymentsStatement(
                      context: context,
                      title: widget.assetTitle,
                      entries: widget.entries,
                      showUnitName: widget.showUnitName,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 34),
                    ),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text(
                      'طباعة',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
        ),
        const SizedBox(height: 12),
        if (visible.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const Expanded(
                  child: Text(
                    'الدفعات',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                ),
                const Text(
                  'اختر الدفعة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8C9A97),
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        if (visible.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Text(
              widget.entries.isEmpty
                  ? widget.emptyMessage
                  : 'لا توجد دفعات ضمن هذه التصفية.',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5C6B68),
              ),
            ),
          )
        else if (widget.showUnitName)
          ..._unitGroups(visible)
        else
          for (var i = 0; i < visible.length; i++)
            _row(visible[i], seq: i + 1),
        // «التالي» لا يظهر إلا عند وجود دفعات فعلية (وحدة مؤجرة لها دفعات).
        if (visible.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(
          textDirection: AppTr.uiDir,
          children: [
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _selected.isEmpty
                    ? AppTheme.muted
                    : widget.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
              ),
              onPressed: _goNext,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                _selected.isEmpty
                    ? 'التالي'
                    : 'التالي (${_selected.length})',
              ),
            ),
          ],
        ),
        ],
        _paymentsLog(),
      ],
    );
  }

  /// «التالي»: يمضي بالدفعات المؤشَّرة إلى السداد — دفعة واحدة تفتح
  /// خيار الكامل/الجزئي، وعدة دفعات تُسدَّد بتأكيد واحد.
  Future<void> _goNext() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الدفعة التي ستدفعها أولًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (widget.onNext != null) {
      widget.onNext!();
      return;
    }
    final targets = widget.entries
        .where((e) => e.payment.id != null && _selected.contains(e.payment.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    // الشكل نفسه الذي يفتحه الضغط على دفعة: بياناتها ثم نوع السداد وطريقة
    // التحصيل — لكل دفعة محدَّدة.
    final changed = await openPaymentSettlePage(
      context: context,
      repository: widget.repository,
      entries: targets,
      showUnitName: widget.showUnitName,
      onMenu: _runMenu,
    );
    if (!mounted) return;
    setState(_selected.clear);
    if (changed) await widget.onChanged();
  }

  /// خيارات الدفعة بعد «التالي»: سداد دفعة / سند قبض / مطالبة مالية.
  Future<void> _openActionsSheet(List<RentPaymentEntry> targets) async {
    final many = targets.length > 1;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                many
                    ? 'إجراءات ${targets.length} دفعات محددة'
                    : 'إجراءات الدفعة',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
              const SizedBox(height: 6),
              ListTile(
                leading: Icon(Icons.payments_rounded, color: widget.accent),
                title: const Text('سداد دفعة'),
                subtitle: const Text(
                  'يخيّرك بين سداد جزئي أو كامل',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(sheetContext).pop('pay'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.receipt_rounded,
                  color: AppTheme.brandMid,
                ),
                title: const Text('سند قبض'),
                subtitle: const Text(
                  'سند بالمبلغ المستلم جاهز للإرسال',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(sheetContext).pop('receipt'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppTheme.goldDark,
                ),
                title: const Text('مطالبة مالية'),
                subtitle: const Text(
                  'عند الاستحقاق ترسل للمستأجر مطالبة بالمبلغ',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(sheetContext).pop('demand'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'pay') {
      if (targets.length == 1) {
        await _settle(targets.first);
      } else {
        await _paySelected();
      }
      return;
    }
    if (targets.length == 1) {
      if (choice == 'receipt') {
        await _openReceiptForm(targets.first);
      } else {
        await _openDemandForm(targets.first);
      }
      return;
    }
    // عدة دفعات: سند/مطالبة مجمّعة بنص واحد.
    final buffer = StringBuffer();
    for (final entry in targets) {
      buffer.writeln(
        choice == 'receipt' ? _receiptText(entry) : _demandText(entry),
      );
      buffer.writeln();
    }
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  /// «نوع الوحدة / اسم الوحدة».
  String _unitLine(RentPaymentEntry entry) {
    final type = (widget.unitTypeOf?.call(entry.unitName) ?? '').trim();
    return type.isEmpty ? entry.unitName : '$type / ${entry.unitName}';
  }

  /// تاريخ الاستحقاق — والتأمين بلا تاريخ «لا يوجد».
  String _dueText(RentPaymentEntry entry) =>
      entry.payment.dueDate == null && entry.kindLabel == kPayKindDeposit
      ? 'لا يوجد'
      : fmtPayDate(entry.payment.dueDate);

  // ---------------- تفصيل الدفعات حسب الوحدة ----------------

  /// لكل وحدة: الإيجارية والرسوم الإدارية والتأمين — الإجمالي والمسدد
  /// والمتبقي.
  Map<String, Map<String, (double, double, double)>> _byUnit() {
    final out = <String, Map<String, (double, double, double)>>{};
    for (final entry in widget.entries) {
      final p = entry.payment;
      final kind = switch (entry.kindLabel) {
        kPayKindFee => kPayKindFee,
        kPayKindDeposit => kPayKindDeposit,
        _ => kPayKindRent,
      };
      final unit = out.putIfAbsent(_unitLine(entry), () => {});
      final old = unit[kind] ?? (0.0, 0.0, 0.0);
      unit[kind] = (
        old.$1 + p.amountDue,
        old.$2 + p.amountPaid,
        old.$3 + payRemaining(p),
      );
    }
    return out;
  }

  /// قسما الجدول: الإيجارية والإدارية لكل وحدة بمجموعها، والتأمين منفصلًا.
  List<PrintSection> _breakdownSections() {
    final units = _byUnit();
    final rows = <List<String>>[];
    var due = 0.0, paid = 0.0, left = 0.0;
    units.forEach((unit, kinds) {
      var uDue = 0.0, uPaid = 0.0, uLeft = 0.0;
      for (final (kind, label) in const [
        (kPayKindRent, 'الدفعات الإيجارية'),
        (kPayKindFee, 'الرسوم الإدارية'),
      ]) {
        final v = kinds[kind];
        if (v == null) continue;
        rows.add([unit, label, payMoney(v.$1), payMoney(v.$2), payMoney(v.$3)]);
        uDue += v.$1;
        uPaid += v.$2;
        uLeft += v.$3;
      }
      if (uDue > 0 || uPaid > 0) {
        rows.add([
          unit,
          'إجمالي الوحدة',
          payMoney(uDue),
          payMoney(uPaid),
          payMoney(uLeft),
        ]);
      }
      due += uDue;
      paid += uPaid;
      left += uLeft;
    });
    rows.add(['الكل', 'الإجمالي', payMoney(due), payMoney(paid), payMoney(left)]);

    final deposits = <List<String>>[];
    var dDue = 0.0, dPaid = 0.0, dLeft = 0.0;
    units.forEach((unit, kinds) {
      final v = kinds[kPayKindDeposit];
      if (v == null) return;
      deposits.add([unit, payMoney(v.$1), payMoney(v.$2), payMoney(v.$3)]);
      dDue += v.$1;
      dPaid += v.$2;
      dLeft += v.$3;
    });
    if (deposits.isNotEmpty) {
      deposits.add(['الإجمالي', payMoney(dDue), payMoney(dPaid), payMoney(dLeft)]);
    }
    return [
      PrintSection(
        'الدفعات الإيجارية والرسوم الإدارية',
        heads: const ['الوحدة', 'البند', 'الإجمالي', 'المسدد', 'المتبقي'],
        rows: rows,
      ),
      if (deposits.isNotEmpty)
        PrintSection(
          'التأمين',
          heads: const ['الوحدة', 'التأمين', 'المسدد', 'المتبقي'],
          rows: deposits,
        ),
    ];
  }

  /// جدول بسيط: رأس ملوّن، وسطر الإجمالي بخط عريض وخلفية.
  Widget _grid(PrintSection section) {
    bool bold(List<String> row) =>
        row.contains('إجمالي الوحدة') || row.first == 'الكل' ||
        row.first == 'الإجمالي';
    TableRow line(List<String> cells, {bool head = false, bool strong = false}) =>
        TableRow(
          decoration: BoxDecoration(
            color: head
                ? widget.accent
                : (strong ? widget.accent.withValues(alpha: 0.1) : Colors.white),
          ),
          children: [
            for (final cell in cells)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  cell,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: head || strong ? FontWeight.w900 : FontWeight.w600,
                    color: head ? Colors.white : const Color(0xFF022E2A),
                  ),
                ),
              ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: widget.accent,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: AppTheme.hairline),
            children: [
              line(section.heads, head: true),
              for (final row in section.rows) line(row, strong: bold(row)),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Future<void> _openBreakdown() async {
    final sections = _breakdownSections();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Icon(Icons.table_chart_outlined, color: widget.accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'التفاصيل المالية للوحدات',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppTr.tr('طباعة'),
                    onPressed: () => Navigator.of(sheetContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TemplatePrintScreen(
                          title: 'التفاصيل المالية للوحدات',
                          fileName: 'تفصيل الدفعات - ${widget.assetTitle}',
                          buildPdf: (format) => buildRecordPdf(
                            title: 'التفاصيل المالية للوحدات',
                            subtitle: 'PAYMENTS BY UNIT',
                            sections: sections,
                            format: format,
                            meta: [('العقار', widget.assetTitle)],
                          ),
                        ),
                      ),
                    ),
                    icon: Icon(Icons.print_outlined, color: widget.accent),
                  ),
                  IconButton(
                    tooltip: AppTr.tr('إغلاق'),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final section in sections) _grid(section),
            ],
          ),
        ),
      ),
    );
  }

  /// الوحدات المفتوحة في صفحة العقار (الباقي مطويّ).
  final Set<String> _openUnits = <String>{};

  /// دفعات كل وحدة تحت اسمها، وسهم يطويها ويُظهرها.
  List<Widget> _unitGroups(List<RentPaymentEntry> visible) {
    final groups = <String, List<RentPaymentEntry>>{};
    for (final entry in visible) {
      groups.putIfAbsent(_unitLine(entry), () => []).add(entry);
    }
    return [
      for (final group in groups.entries) ...[
        _unitHeader(group.key, group.value),
        if (_openUnits.contains(group.key))
          for (var i = 0; i < group.value.length; i++)
            _row(group.value[i], seq: i + 1, grouped: true),
      ],
    ];
  }

  Widget _unitHeader(String unit, List<RentPaymentEntry> entries) {
    final open = _openUnits.contains(unit);
    final left = entries.fold<double>(
      0,
      (sum, e) => sum + payRemaining(e.payment),
    );
    final lateCount = entries
        .where((e) => rentPaymentStatusLabel(e.payment) == 'متأخرة')
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => setState(() {
          if (open) {
            _openUnits.remove(unit);
          } else {
            _openUnits.add(unit);
          }
        }),
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: open ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(AppTheme.rIcon),
            border: Border.all(color: widget.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(Icons.home_work_outlined, size: 19, color: widget.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${entries.length} ${AppTr.tr('دفعة')}',
                        '${AppTr.tr('المتبقي')} ${payMoney(left)}',
                        if (lateCount > 0) '${AppTr.tr('متأخرة')}: $lateCount',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: lateCount > 0
                            ? const Color(0xFFC4392E)
                            : const Color(0xFF5C6B68),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: widget.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// صندوق إجمالي صفحة العقار: ثلاثة مربعات بمقاس واحد، ثم الزران.
  Widget _propertyTotals() {
    final entries = widget.entries;
    final due = entries.fold<double>(0, (sum, e) => sum + e.payment.amountDue);
    final paid = entries.fold<double>(0, (sum, e) => sum + e.payment.amountPaid);
    final left = entries.fold<double>(
      0,
      (sum, e) => sum + payRemaining(e.payment),
    );
    Widget cell(String label, double value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5C6B68),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                payMoney(value),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              cell(
                '${AppTr.tr('إجمالي الدفعات')} (${entries.length})',
                due,
                AppTheme.title,
              ),
              const SizedBox(width: 6),
              cell(AppTr.tr('المسدد'), paid, const Color(0xFF0E7161)),
              const SizedBox(width: 6),
              cell(AppTr.tr('المتبقي'), left, AppTheme.goldDark),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              textDirection: AppTr.uiDir,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openBreakdown,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.accent,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'التفاصيل المالية للوحدات',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => printPaymentsStatement(
                    context: context,
                    title: widget.assetTitle,
                    entries: widget.entries,
                    showUnitName: widget.showUnitName,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accent,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text(
                    'طباعة',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(RentPaymentEntry entry, {int? seq, bool grouped = false}) {
    final payment = entry.payment;
    final label = rentPaymentStatusLabel(payment);
    final color = rentPaymentStatusColor(label);
    final id = payment.id ?? '${entry.contract.id}-${entry.order}';
    final checked = _selected.contains(id);
    final settled = label == 'مدفوعة';
    return InkWell(
      onTap: () => _openDetails(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.hairline, width: 0.8),
          ),
        ),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            // رقم تسلسل الدفعة في القائمة.
            if (seq != null)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsetsDirectional.only(end: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$seq',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: widget.accent,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صفحة العقار: «نوع الوحدة / اسم الوحدة» في سطر، واسم
                  // الدفعة في سطر، والمبلغ وتاريخ الاستحقاق في سطر، والحالة
                  // في سطر.
                  if (widget.showUnitName && !grouped) ...[
                    Text(
                      _unitLine(entry),
                      textAlign: AppTr.alignEnd,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: widget.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    entry.title,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  if (widget.showUnitName) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${payMoney(payment.amountDue)} · ${_dueText(entry)}',
                      textAlign: AppTr.alignEnd,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF46534F),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      payMethodOf(entry).isEmpty
                          ? label
                          : '$label/${payMethodOf(entry)}',
                      if (payment.amountPaid > 0.009 &&
                          payRemaining(payment) > 0)
                        'المتبقي ${payMoney(payRemaining(payment))}',
                      if (payChequeLabel(entry).isNotEmpty)
                        payChequeLabel(entry),
                    ].join(' · '),
                    textAlign: AppTr.alignEnd,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.showUnitName)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  payMoney(payment.amountDue),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dueText(entry),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5C6B68),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            if (!settled)
              Checkbox(
                value: checked,
                activeColor: widget.accent,
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              ),
            // سند القبض والمطالبة المالية هنا وحدهما — لكل دفعة، ويُتاح كلٌّ
            // حين يكون له معنى.
            PopupMenuButton<String>(
              tooltip: AppTr.tr('خيارات الدفعة'),
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 22,
                color: Color(0xFF46534F),
              ),
              onSelected: (value) => _runMenu(entry, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'share', child: Text('مشاركة')),
                PopupMenuItem(
                  value: 'receipt',
                  enabled: payment.amountPaid > 0,
                  child: const Text('سند قبض'),
                ),
                PopupMenuItem(
                  value: 'demand',
                  enabled: payRemaining(payment) > 0,
                  child: const Text('مطالبة مالية'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- سجل الدفعات ----------------

  String _ledgerText() {
    final buffer = StringBuffer();
    buffer.writeln('سجل الدفعات — ${widget.assetTitle}');
    buffer.writeln();
    for (final entry in widget.entries) {
      buffer.writeln(
        '${entry.unitName} · ${entry.title}: '
        '${payMoney(entry.payment.amountDue)} · '
        '${rentPaymentStatusLabel(entry.payment)} · '
        'استحقاق ${fmtPayDate(entry.payment.dueDate)}'
        '${entry.payment.amountPaid > 0 ? ' · المسدد ${payMoney(entry.payment.amountPaid)}' : ''}',
      );
    }
    final due = widget.entries.fold<double>(
      0,
      (sum, e) => sum + e.payment.amountDue,
    );
    final paid = widget.entries.fold<double>(
      0,
      (sum, e) => sum + e.payment.amountPaid,
    );
    buffer.writeln();
    buffer.writeln('الإجمالي: ${payMoney(due)}');
    buffer.writeln('المسدد: ${payMoney(paid)}');
    buffer.writeln('المتبقي: ${payMoney(due - paid)}');
    return buffer.toString();
  }

  Future<void> _openLedger() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => Directionality(
          textDirection: AppTr.uiDir,
          child: Scaffold(
            backgroundColor: AppTheme.page,
            appBar: AppBar(
              title: const Text('سجل الدفعات'),
              actions: [
                IconButton(
                  tooltip: AppTr.tr('مشاركة السجل'),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  onPressed: () async {
                    await SharePlus.instance.share(
                      ShareParams(text: _ledgerText()),
                    );
                  },
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: Text(
                    widget.assetTitle,
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in widget.entries)
                  InkWell(
                    // الضغط على أي دفعة في السجل يفتح تفاصيلها للتعديل.
                    onTap: () {
                      Navigator.of(pageContext).pop();
                      _openDetails(entry);
                    },
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                    child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry.unitName} · ${entry.title} · '
                                '${payMoney(entry.payment.amountDue)}',
                                textAlign: AppTr.alignEnd,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF022E2A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${rentPaymentStatusLabel(entry.payment)} · '
                                'استحقاق ${fmtPayDate(entry.payment.dueDate)}'
                                '${(entry.contract.tenantName ?? '').isEmpty ? '' : ' · ${entry.contract.tenantName}'}',
                                textAlign: AppTr.alignEnd,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: rentPaymentStatusColor(
                                    rentPaymentStatusLabel(entry.payment),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- تفاصيل الدفعة ----------------

  /// الضغط على دفعة في أي مكان يفتح الصفحة الموحّدة.
  Future<void> _openDetails(RentPaymentEntry entry) async {
    final changed = await openPaymentSettlePage(
      context: context,
      repository: widget.repository,
      entries: [entry],
      showUnitName: widget.showUnitName,
      onMenu: _runMenu,
    );
    if (changed) await widget.onChanged();
  }

  /// أوامر الثلاث نقاط: تعديل، مشاركة، سند قبض، مطالبة مالية.
  Future<void> _runMenu(RentPaymentEntry entry, String action) async {
    switch (action) {
      case 'edit':
        await _openExtraSheet(entry);
      case 'share':
        await SharePlus.instance.share(
          ShareParams(
            text: entry.payment.amountPaid > 0
                ? _receiptText(entry)
                : _demandText(entry),
          ),
        );
      case 'receipt':
        await _openReceiptForm(entry);
      case 'demand':
        await _openDemandForm(entry);
    }
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.hairline, width: 0.8),
        ),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color ?? const Color(0xFF022E2A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _receiptText(RentPaymentEntry entry) {
    final payment = entry.payment;
    final extra = decodePayExtra(payment.notes);
    final cheque = extra[kPayCheque] ?? payment.referenceNo ?? '';
    return 'سند قبض\n'
        'العقار: ${widget.assetTitle}\n'
        'الوحدة: ${entry.unitName}\n'
        'المستأجر: ${entry.contract.tenantName ?? 'غير محدد'}\n'
        'الدفعة: ${entry.title}\n'
        'المبلغ المستلم: ${payMoney(payment.amountPaid > 0 ? payment.amountPaid : payment.amountDue)}\n'
        'تاريخ الاستحقاق: ${fmtPayDate(payment.dueDate)}\n'
        'تاريخ السداد: ${fmtPayDate(payment.paidAt)}\n'
        'طريقة التحصيل: ${extra[kPayMethod] ?? 'غير محددة'}'
        '${cheque.isEmpty ? '' : ' — شيك رقم $cheque'}\n'
        'المستفيد: ${extra[kPayBeneficiary] ?? 'غير محدد'}';
  }

  String _demandText(RentPaymentEntry entry) {
    return 'مطالبة مالية\n'
        'إلى: ${entry.contract.tenantName ?? 'المستأجر'}\n'
        'بخصوص: ${entry.unitName} — ${widget.assetTitle}\n'
        '${entry.title} بمبلغ '
        '${payMoney(entry.payment.amountDue)}\n'
        'تاريخ الاستحقاق: ${fmtPayDate(entry.payment.dueDate)}\n'
        'الحالة: ${rentPaymentStatusLabel(entry.payment)}\n'
        'نأمل السداد في موعده، وشكرًا لتعاونكم.';
  }

  // ---------------- سند القبض والمطالبة المالية ----------------

  InputDecoration _formDecoration(String label) => InputDecoration(
    labelText: AppTr.tr(label),
    isDense: true,
    filled: true,
    fillColor: AppTheme.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rIcon),
      borderSide: BorderSide.none,
    ),
    labelStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.body,
    ),
  );

  Widget _formDateField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onPick,
    BuildContext pageContext,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: pageContext,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2070),
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(AppTheme.rIcon),
      child: InputDecorator(
        decoration: _formDecoration(label),
        child: Text(
          fmtPayDate(value),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF022E2A),
          ),
        ),
      ),
    );
  }

  /// فورم «سند قبض»: يحمل بيانات السند جاهزة للتعديل ثم المعاينة والإرسال.
  Future<void> _openReceiptForm(RentPaymentEntry entry) async {
    final payment = entry.payment;
    final extra = decodePayExtra(payment.notes);
    final received = payment.amountPaid > 0
        ? payment.amountPaid
        : payment.amountDue;
    final noCtrl = TextEditingController(
      text: payment.referenceNo ?? '',
    );
    final amountCtrl = TextEditingController(
      text: received.toStringAsFixed(2),
    );
    final fromCtrl = TextEditingController(
      text: entry.contract.tenantName ?? '',
    );
    final aboutCtrl = TextEditingController(
      text: '${entry.title} — ${entry.unitName}',
    );
    final beneficiaryCtrl = TextEditingController(
      text: extra[kPayBeneficiary] ?? '',
    );
    final chequeCtrl = TextEditingController(
      text: extra[kPayCheque] ?? payment.referenceNo ?? '',
    );
    final noteCtrl = TextEditingController();
    var method = extra[kPayMethod] ?? 'كاش';
    var date = payment.paidAt ?? DateTime.now();
    const methods = ['كاش', 'شيك', 'تحويل بنكي', 'بطاقة'];

    String buildText() {
      final cheque = chequeCtrl.text.trim();
      return 'سند قبض\n'
          '${noCtrl.text.trim().isEmpty ? '' : 'رقم السند: ${noCtrl.text.trim()}\n'}'
          'التاريخ: ${fmtPayDate(date)}\n'
          'استلمنا من: ${fromCtrl.text.trim()}\n'
          'مبلغًا وقدره: ${amountCtrl.text.trim()} ${AppSettings.currencySuffix}\n'
          'وذلك عن: ${aboutCtrl.text.trim()}\n'
          'العقار: ${widget.assetTitle}\n'
          'طريقة التحصيل: $method'
          '${cheque.isEmpty ? '' : ' — شيك رقم $cheque'}\n'
          '${beneficiaryCtrl.text.trim().isEmpty ? '' : 'المستفيد: ${beneficiaryCtrl.text.trim()}\n'}'
          '${noteCtrl.text.trim().isEmpty ? '' : 'ملاحظات: ${noteCtrl.text.trim()}\n'}'
          '\nتوقيع المستلم: ..............................';
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) => Directionality(
            textDirection: AppTr.uiDir,
            child: Scaffold(
              backgroundColor: AppTheme.page,
              appBar: AppBar(title: const Text('سند قبض')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                children: [
                  TextField(
                    controller: noCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _formDecoration('رقم السند'),
                  ),
                  const SizedBox(height: 10),
                  _formDateField(
                    'تاريخ السند',
                    date,
                    (picked) => setPageState(() => date = picked),
                    pageContext,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fromCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _formDecoration('استلمنا من (المستأجر)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _formDecoration('المبلغ المستلم'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aboutCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    decoration: _formDecoration('وذلك عن'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: methods.contains(method) ? method : null,
                    isExpanded: true,
                    decoration: _formDecoration('طريقة التحصيل'),
                    items: methods
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setPageState(() => method = value ?? method),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: chequeCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _formDecoration('رقم الشيك (إن وُجد)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: beneficiaryCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _formDecoration('المستفيد'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    decoration: _formDecoration('ملاحظات'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'معاينة السند',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          buildText(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF46534F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await SharePlus.instance.share(
                              ShareParams(text: buildText()),
                            );
                          },
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('إرسال / مشاركة'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setPageState(() {}),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('تحديث المعاينة'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    noCtrl.dispose();
    amountCtrl.dispose();
    fromCtrl.dispose();
    aboutCtrl.dispose();
    beneficiaryCtrl.dispose();
    chequeCtrl.dispose();
    noteCtrl.dispose();
  }

  /// فورم «مطالبة مالية»: نص جاهز قابل للتعديل مع إرسال عبر واتساب أو مشاركة.
  Future<void> _openDemandForm(RentPaymentEntry entry) async {
    final payment = entry.payment;
    final remaining = payment.amountDue - payment.amountPaid;
    final toCtrl = TextEditingController(
      text: entry.contract.tenantName ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: entry.contract.tenantPhone ?? '',
    );
    final amountCtrl = TextEditingController(
      text: (remaining > 0 ? remaining : payment.amountDue).toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController(
      text: 'نأمل السداد في موعده، وشكرًا لتعاونكم.',
    );
    var deadline = DateTime.now().add(const Duration(days: 7));

    String buildText() {
      return 'مطالبة مالية\n'
          'إلى: ${toCtrl.text.trim()}\n'
          'بخصوص: ${entry.unitName} — ${widget.assetTitle}\n'
          '${entry.title}\n'
          'المبلغ المطالب به: ${amountCtrl.text.trim()} '
          '${AppSettings.currencySuffix}\n'
          'تاريخ الاستحقاق: ${fmtPayDate(payment.dueDate)}\n'
          'الحالة: ${rentPaymentStatusLabel(payment)}\n'
          'آخر موعد للسداد: ${fmtPayDate(deadline)}\n'
          '${noteCtrl.text.trim()}';
    }

    Future<void> sendWhatsapp() async {
      final digits = phoneCtrl.text.replaceAll(RegExp('[^0-9]'), '');
      if (digits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أدخل رقم هاتف المستأجر أولًا'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final uri = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(buildText())}',
      );
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب')),
        );
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) => Directionality(
            textDirection: AppTr.uiDir,
            child: Scaffold(
              backgroundColor: AppTheme.page,
              appBar: AppBar(title: const Text('مطالبة مالية')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                children: [
                  TextField(
                    controller: toCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _formDecoration('إلى (المستأجر)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: TextInputType.phone,
                    decoration: _formDecoration('رقم الهاتف (للإرسال)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _formDecoration('المبلغ المطالب به'),
                  ),
                  const SizedBox(height: 10),
                  _formDateField(
                    'آخر موعد للسداد',
                    deadline,
                    (picked) => setPageState(() => deadline = picked),
                    pageContext,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    decoration: _formDecoration('نص المطالبة'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'معاينة المطالبة',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          buildText(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF46534F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.goldDark,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: sendWhatsapp,
                          icon: const Icon(Icons.chat_rounded, size: 18),
                          label: const Text('إرسال واتساب'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await SharePlus.instance.share(
                              ShareParams(text: buildText()),
                            );
                          },
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('مشاركة'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setPageState(() {}),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('تحديث المعاينة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    toCtrl.dispose();
    phoneCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  // ---------------- السداد ----------------

  Future<void> _settle(RentPaymentEntry entry) async {
    final payment = entry.payment;
    if (payment.id == null) return;
    final remaining = payment.amountDue - payment.amountPaid;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text(
                'نوع السداد',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
              ListTile(
                leading: Icon(Icons.done_all_rounded, color: widget.accent),
                title: const Text('سداد كامل'),
                subtitle: Text(
                  'المتبقي: ${payMoney(remaining)}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(sheetContext).pop('full'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.percent_rounded,
                  color: AppTheme.goldDark,
                ),
                title: const Text('سداد جزئي'),
                subtitle: const Text(
                  'تُدخل المبلغ المستلم وتبقى الدفعة مفتوحة بالباقي',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(sheetContext).pop('partial'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    var paidNow = remaining;
    if (choice == 'partial') {
      final controller = TextEditingController();
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.page,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.rCard),
          ),
        ),
        builder: (sheetContext) => Directionality(
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
                  'المبلغ المستلم',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  textAlign: AppTr.alignEnd,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: AppTr.tr('المبلغ'),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rIcon),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('تسجيل السداد'),
                ),
              ],
            ),
          ),
        ),
      );
      final typed = double.tryParse(controller.text.trim()) ?? 0;
      controller.dispose();
      if (confirmed != true || typed <= 0) return;
      paidNow = typed;
    }

    final newPaid = payment.amountPaid + paidNow;
    final settled = newPaid + 0.001 >= payment.amountDue;
    try {
      await widget.repository.upsertUnitPayment(
        payment.copyWith(
          amountPaid: newPaid,
          paidAt: DateTime.now(),
          status: settled
              ? PropertyUnitPaymentRecord.statusPaid
              : PropertyUnitPaymentRecord.statusPartial,
        ),
      );
      _selected.remove(payment.id);
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settled ? 'تم تسجيل السداد الكامل' : 'تم تسجيل سداد جزئي',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل السداد')),
      );
    }
  }

  Future<void> _paySelected() async {
    final targets = widget.entries
        .where((e) => e.payment.id != null && _selected.contains(e.payment.id))
        .toList(growable: false);
    if (targets.isEmpty) return;
    final total = targets.fold<double>(
      0,
      (sum, e) => sum + (e.payment.amountDue - e.payment.amountPaid),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('تأكيد السداد'),
          content: Text(
            'سيتم تسجيل سداد ${targets.length} دفعة بإجمالي ${payMoney(total)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      for (final entry in targets) {
        await widget.repository.upsertUnitPayment(
          entry.payment.copyWith(
            amountPaid: entry.payment.amountDue,
            paidAt: DateTime.now(),
            status: PropertyUnitPaymentRecord.statusPaid,
          ),
        );
      }
      _selected.clear();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل سداد الدفعات المحددة')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل السداد')),
      );
    }
  }

  /// بيانات الدفعة الإضافية: المستفيد وطريقة الدفع ورقم الشيك.
  Future<void> _openExtraSheet(RentPaymentEntry entry) async {
    final payment = entry.payment;
    if (payment.id == null) return;
    final extra = decodePayExtra(payment.notes);
    final beneficiaryCtrl = TextEditingController(
      text: extra[kPayBeneficiary] ?? '',
    );
    final chequeCtrl = TextEditingController(
      text: extra[kPayCheque] ?? payment.referenceNo ?? '',
    );
    final noteCtrl = TextEditingController(text: extra['ملاحظة'] ?? '');
    var method = extra[kPayMethod] ?? 'شيك';
    const methods = ['شيك', 'كاش', 'تحويل بنكي', 'بطاقة'];
    // تاريخ التحصيل يُعدَّل هنا للدفعة التي استُلم منها شيء.
    final hasPaid = payment.amountPaid > 0.009;
    var paidAt = payment.paidAt;

    InputDecoration decoration(String label) => InputDecoration(
      labelText: AppTr.tr(label),
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        borderSide: BorderSide.none,
      ),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'بيانات الدفعة',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: beneficiaryCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: decoration('المستفيد'),
                  ),
                  const SizedBox(height: 9),
                  DropdownButtonFormField<String>(
                    initialValue: methods.contains(method) ? method : null,
                    isExpanded: true,
                    decoration: decoration('طريقة التحصيل'),
                    items: methods
                        .map(
                          (option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(
                              option,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => method = value ?? method),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: chequeCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: decoration('رقم الشيك'),
                  ),
                  if (hasPaid) ...[
                    const SizedBox(height: 9),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rIcon),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: paidAt ?? DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2070),
                          helpText: AppTr.tr('تاريخ التحصيل'),
                        );
                        if (picked != null) {
                          setSheetState(() => paidAt = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: decoration('تاريخ التحصيل'),
                        child: Text(
                          fmtPayDate(paidAt),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  TextField(
                    controller: noteCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    decoration: decoration('ملاحظة'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final beneficiary = beneficiaryCtrl.text.trim();
    final cheque = chequeCtrl.text.trim();
    final note = noteCtrl.text.trim();
    beneficiaryCtrl.dispose();
    chequeCtrl.dispose();
    noteCtrl.dispose();
    if (saved != true) return;
    // سجل التعديل: ما تغيّر فقط، من القيمة القديمة إلى الجديدة.
    final changes = <String>[];
    String old(String key) => (extra[key] ?? '').trim();
    final oldPaidAt = payment.paidAt;
    if (hasPaid &&
        paidAt != null &&
        (oldPaidAt == null ||
            _payDmy(oldPaidAt) != _payDmy(paidAt!))) {
      changes.add(
        'تاريخ التحصيل ${oldPaidAt == null ? '' : 'من ${_payDmy(oldPaidAt)} '}'
        'إلى ${_payDmy(paidAt!)}',
      );
    }
    if (old(kPayMethod) != method) {
      changes.add(
        'طريقة التحصيل ${old(kPayMethod).isEmpty ? '' : 'من ${old(kPayMethod)} '}'
        'إلى $method',
      );
    }
    final oldCheque = old(kPayCheque).isEmpty
        ? (payment.referenceNo ?? '').trim()
        : old(kPayCheque);
    if (oldCheque != cheque && cheque.isNotEmpty) {
      changes.add('رقم الشيك إلى $cheque');
    }
    if (old(kPayBeneficiary) != beneficiary) {
      changes.add('المستفيد إلى ${beneficiary.isEmpty ? '—' : beneficiary}');
    }
    if (old('ملاحظة') != note) changes.add('الملاحظة');
    final previousLog = old(kPayLog);
    final logLine = changes.isEmpty
        ? ''
        : '${_payDmy(DateTime.now())} — تعديل: ${changes.join('، ')}';
    try {
      await widget.repository.upsertUnitPayment(
        payment.copyWith(
          referenceNo: cheque.isEmpty ? payment.referenceNo : cheque,
          paidAt: hasPaid ? paidAt : payment.paidAt,
          // دمج لا استبدال: نوع البند واسمه ومعرّف سطره في العقد تبقى،
          // وإلا عدّ الربط التالي السجل يتيمًا وأنشأ نسخة ثانية منه.
          notes: encodePayExtra(<String, String>{
            ...decodePayExtra(payment.notes),
            kPayBeneficiary: beneficiary,
            kPayMethod: method,
            kPayCheque: cheque,
            'ملاحظة': note,
            if (logLine.isNotEmpty)
              kPayLog: [
                // الدفعة المسددة قبل السجل: سطر سدادها أولًا ثم التعديل.
                if (previousLog.isNotEmpty)
                  previousLog
                else
                  ...payLogLines(payment),
                logLine,
              ].join('\n'),
          }),
        ),
      );
      await widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ بيانات الدفعة')),
      );
    }
  }
}
