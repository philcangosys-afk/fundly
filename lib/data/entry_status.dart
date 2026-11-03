import 'dart:convert';

import 'package:flutter/material.dart' show DateUtils;

/// حالة البند كما تظهر للمستخدم، محسوبة من تواريخه عند العرض (لا تُخزَّن).

/// الحالات النهائية التي لا تتغيّر بالتاريخ.
const Set<String> entryFinalStatuses = {
  'مكتملة',
  'مؤرشف',
  'ملغاة',
  'تمت التسوية',
  'محذوف',
  'مجمّدة',
};

/// المصروفات والإيرادات عمليات تمّت: لا تُعدّ «متأخرة» بمرور تاريخها،
/// والمتكرر منها يُحسب بموعده القادم.
const Set<String> entryTransactionTypes = {
  'المصروفات الشخصية',
  'مصروف',
  'إيراد',
  'تحويل مالي',
};

/// «يوم/شهر/سنة» (صيغة التطبيق) أو «سنة-شهر-يوم» (صيغة الخادم).
DateTime? entryParseDay(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parts = value.split(RegExp(r'[/\-]'));
  if (parts.length < 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2].split(' ').first);
  if (a == null || b == null || c == null) return null;
  if (parts[0].length == 4) return DateTime(a, b, c);
  return DateTime(c, b, a);
}

/// ما له تاريخ نهاية («إلى تاريخ» أو «تاريخ الانتهاء») ومرّ هذا التاريخ =
/// «منتهية»، لا «نشطة». الحالات النهائية تبقى كما هي.
String entryDerivedStatus(
  String stored,
  Map<String, String> details, {
  DateTime? now,
}) {
  if (entryFinalStatuses.contains(stored)) return stored;
  final end =
      entryParseDay(details['إلى تاريخ'] ?? '') ??
      entryParseDay(details['تاريخ الانتهاء'] ?? '');
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  if (end != null && end.isBefore(today)) return 'منتهية';
  // مُدِّد تاريخه بعد انتهائه: يعود نشطًا.
  if (stored == 'منتهية') return 'نشطة';
  return stored;
}

/// دورات التكرار المعروفة في نماذج التطبيق.
const Map<String, int> _repeatMonths = {
  'شهري': 1,
  'شهريًا': 1,
  'ربع سنوي': 3,
  'كل 3 شهور': 3,
  'نصف سنوي': 6,
  'كل 6 شهور': 6,
  'سنوي': 12,
  'سنويًا': 12,
  'شهر أختاره': 12,
};
const Map<String, int> _repeatDays = {
  'يومي': 1,
  'يوميًا': 1,
  'أسبوعي': 7,
  'أسبوعيًا': 7,
};

/// نفس اليوم بعد [months] شهرًا (أو آخر يوم في الشهر إن كان أقصر).
DateTime _addMonths(DateTime from, int months) {
  final target = DateTime(from.year, from.month + months);
  final last = DateUtils.getDaysInMonth(target.year, target.month);
  return DateTime(
    target.year,
    target.month,
    from.day > last ? last : from.day,
  );
}

/// هل للبند دورة تكرار فعلية؟ («بدون تكرار» و«لا يتكرر» ليست تكرارًا، ومفتاح
/// التفعيل إن وُجد هو الحكم.)
bool entryIsRepeating(Map<String, String> details) {
  final toggle = details['تفعيل عملية متكررة'];
  if (toggle != null && toggle.trim() != 'نعم') return false;
  final cycle = (details['التكرار'] ?? '').trim();
  return _repeatMonths.containsKey(cycle) || _repeatDays.containsKey(cycle);
}

/// بند متكرر (راتب شهري، اشتراك ربع سنوي...): موعده القادم (اليوم أو بعده)
/// من تاريخه الأول ودورته، أو null إن لم يكن متكررًا.
DateTime? entryNextRepeatDate(
  DateTime? first,
  Map<String, String> details, {
  DateTime? now,
}) {
  if (first == null || !entryIsRepeating(details)) return null;
  final cycle = (details['التكرار'] ?? '').trim();
  final months = _repeatMonths[cycle] ?? 0;
  final days = _repeatDays[cycle] ?? 0;
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final anchor = DateUtils.dateOnly(first);
  var next = anchor;
  for (var i = 1; i < 5000 && next.isBefore(today); i++) {
    next = months > 0
        ? _addMonths(anchor, months * i)
        : DateTime(anchor.year, anchor.month, anchor.day + days * i);
  }
  return next;
}

// ======================= المتابعة: موعد البند ونتيجته =======================

/// أنواع «مالية» في مراكز المتابعة والرئيسية.
const Set<String> entryFinancialTypes = {
  'المصروفات الشخصية',
  'مصروف',
  'إيراد',
  'تحويل مالي',
  'دين / قرض / سلفة',
  'قسط',
  'غرامة',
  'جمعية',
};

/// يُسدَّد مبلغها: سداد كامله يجعلها «مكتملة».
const Set<String> entryPayableTypes = {'دين / قرض / سلفة', 'قسط'};

/// تاريخها يوم حدث لا موعد سداد: بعد مروره (بلا تكرار) «منتهية» لا «متأخرة».
const Set<String> entryEventTypes = {'مناسبة', 'هدية'};

/// مفتاح سجل دفعات البند في تفاصيله.
const String entryPaymentsKey = 'سجل دفعات الالتزام';

/// رقم من نص بأي صيغة (أرقام عربية، فواصل، «500 درهم»).
double entryNumber(String raw) {
  var text = raw.replaceAll(RegExp(r'[,،٬\s]'), '').replaceAll('٫', '.');
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  final match = RegExp(r'\d+(\.\d+)?').firstMatch(text);
  return match == null ? 0 : (double.tryParse(match.group(0)!) ?? 0);
}

/// مجموع ما سُجِّل من دفعات على البند.
int entryPaidTotal(Map<String, String> details) {
  final raw = details[entryPaymentsKey];
  if (raw == null || raw.trim().isEmpty) return 0;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return 0;
    var sum = 0.0;
    for (final row in decoded) {
      if (row is Map) sum += entryNumber('${row['المبلغ'] ?? ''}');
    }
    return sum.round();
  } catch (_) {
    return 0;
  }
}

/// القسط: تاريخ أول قسط لم يغطّه المدفوع (الأقساط بالترتيب، والمدفوع يُوزَّع
/// عليها من الأول). null: لا جدول أقساط أو سُدِّدت كلها.
DateTime? entryNextUnpaidInstallment(Map<String, String> details, int paid) {
  final rows = <(DateTime, double)>[];
  for (var i = 1; i <= 600; i++) {
    final raw = details['القسط $i'];
    if (raw == null) break;
    final parts = raw.split('—');
    final date = entryParseDay(parts.first.trim());
    if (date == null) continue;
    rows.add((date, parts.length > 1 ? entryNumber(parts[1]) : 0));
  }
  if (rows.isEmpty) return null;
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  var covered = 0.0;
  for (final row in rows) {
    covered += row.$2;
    if (covered > paid + 0.5) return row.$1;
  }
  return null;
}

/// اليوم الذي يُتابَع عليه البند («متأخرة» / «مستحقة» / «قريبة»)، أو null إن
/// لم يكن له موعد يُتأخَّر عنه:
/// - الملاحظات، والعادة غير المتكررة، والعهدة (حالتها من رصيدها)، والدواء
///   (يُتابَع بتاريخ انتهائه) — لا موعد.
/// - المصروف / الإيراد: المتكرر بموعده القادم، وغير المتكرر عملية تمّت.
/// - القسط: أول قسط لم يُسدَّد.
/// - المتكرر (اشتراك شهري، تذكير أسبوعي...): موعده القادم.
DateTime? entryFollowDate({
  required String type,
  required DateTime? due,
  required Map<String, String> details,
  DateTime? now,
}) {
  if (due == null) return null;
  if (type == 'ملاحظات' || type == 'ملاحظة') return null;
  if (type == 'عهدة مالية' || type == 'أدوية') return null;
  if (entryTransactionTypes.contains(type)) {
    return entryNextRepeatDate(due, details, now: now);
  }
  if (type == 'عادة' && !entryIsRepeating(details)) return null;
  if (type == 'قسط') {
    final next = entryNextUnpaidInstallment(details, entryPaidTotal(details));
    if (next != null) return next;
  }
  return entryNextRepeatDate(due, details, now: now) ?? due;
}

/// نتيجة البند من بياناته: «مكتملة» لما سُدِّد كامل مبلغه، و«منتهية»
/// للمناسبة / الهدية التي مرّ يومها بلا تكرار. null: لا نتيجة بعد.
String? entryOutcomeStatus({
  required String type,
  required DateTime? due,
  required Map<String, String> details,
  required int total,
  DateTime? now,
}) {
  if (entryPayableTypes.contains(type) &&
      total > 0 &&
      entryPaidTotal(details) >= total) {
    return 'مكتملة';
  }
  if (entryEventTypes.contains(type) &&
      due != null &&
      !entryIsRepeating(details) &&
      DateUtils.dateOnly(due).isBefore(
        DateUtils.dateOnly(now ?? DateTime.now()),
      )) {
    return 'منتهية';
  }
  return null;
}
