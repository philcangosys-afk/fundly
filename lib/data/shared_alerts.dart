import 'dart:convert';

import '../l10n/app_language.dart';
import 'app_settings.dart';
import 'custody_sharing.dart';
import 'home_dashboard_service.dart';
import 'rosca_cycles.dart';
import 'shared_entries_repository.dart';
import 'shared_expenses.dart';

/// تنبيهات الالتزامات المشتركة للكلندر الذكي ومركز التنبيهات — نفس نظام
/// العهدة المالية: بنود «المتابعة والتخطيط»، المستندات قبل انتهائها، موعد
/// دورة الجمعية، المصروفات والميزانيات الإضافية بانتظار اعتماد المسؤول،
/// وبلوغ نسبة الصرف المختارة من الميزانية أو تجاوزها.

/// نسبة تنبيه الصرف من الميزانية — نفس خيار «تنبيه عند صرف نسبة» في العهدة.
const String sharedBudgetAlertKey = 'تنبيه عند صرف نسبة';
const List<String> sharedBudgetAlertOptions = [
  'بلا تنبيه',
  '50%',
  '75%',
  '90%',
  '100%',
];

/// أنواع تنبيهات المصروفات (تُقرأ في الكلندر لتلوينها وتصنيفها).
const String sharedApprovalAlertType = 'اعتماد صرف';
const String sharedBudgetAlertType = 'تنبيه الميزانية';

const String _module = 'الالتزامات المشتركة';
const String _collectKey = 'طريقة تحصيل المبلغ';
const String _lumpSum = 'دفعة مقطوعة';

/// النسبة المختارة (0 = بلا تنبيه).
int sharedBudgetAlertPercent(Map<String, String> details) {
  final match = RegExp(r'\d+').firstMatch(details[sharedBudgetAlertKey] ?? '');
  return match == null ? 0 : int.parse(match.group(0)!);
}

/// هل الالتزام بميزانية مقطوعة؟
bool sharedHasPot(Map<String, String> details) =>
    (details[_collectKey] ?? '').trim() == _lumpSum &&
    SharedLedger.hasBudget(details);

/// نسبة ما صُرف من الميزانية (0 بلا ميزانية).
double sharedSpentPercent(Map<String, String> details) {
  if (!sharedHasPot(details)) return 0;
  final budget = SharedLedger.budget(details);
  return SharedLedger.total(details) * 100 / budget;
}

/// ميزانية مستنفدة: صُرفت كلها أو تجاوزها الصرف.
bool sharedPotDrained(Map<String, String> details) =>
    sharedHasPot(details) && SharedLedger.remaining(details) <= 0.01;

/// قريبة الاستنفاد: بقي منها 20% فأقل — نفس تعريف العهدة.
bool sharedPotNearlyDrained(Map<String, String> details) {
  if (!sharedHasPot(details)) return false;
  final left = SharedLedger.remaining(details);
  return left > 0.01 && left <= SharedLedger.budget(details) * 0.2;
}

/// أسماء الأعضاء كما في الالتزام.
List<String> sharedMemberNames(Map<String, String> details) {
  final names = <String>[];
  for (final member in _members(details)) {
    final name = member.$1;
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names;
}

List<(String, String)> _members(Map<String, String> details) {
  try {
    final decoded = jsonDecode(details['الأعضاء'] ?? '[]');
    if (decoded is! List) return const [];
    return [
      for (final m in decoded.whereType<Map>())
        ('${m['name'] ?? ''}'.trim(), '${m['role'] ?? 'عضو'}'.trim()),
    ];
  } catch (_) {
    return const [];
  }
}

/// هل أنا مسؤول هذا الالتزام؟ (بنفس منطق صفحة التفاصيل.)
bool sharedIAmManager(Map<String, String> details) {
  final myId = AppIdentity.id;
  final creator = (details['معرف المنشئ'] ?? '').trim();
  if (creator.isNotEmpty && creator == myId) return true;
  var manager = '';
  for (final member in _members(details)) {
    if (member.$2 == 'مسؤول') {
      manager = member.$1;
      break;
    }
  }
  if (manager.isEmpty) {
    manager = (details['مدير الرحلة'] ?? details['المسؤول'] ?? '').trim();
  }
  final managerId = RegExp(
    r'FND-[A-Z2-9]{4}-[A-Z2-9]{4}',
  ).firstMatch(manager)?.group(0);
  if (managerId != null) return managerId == myId;
  if (creator.isNotEmpty) return false;
  if (manager.isEmpty) return true;
  return AppSettings.instance.isMyName(manager);
}

/// تاريخ بصيغة يوم/شهر/سنة أو سنة-شهر-يوم (ومعه وقت).
DateTime? _parseDate(String? input) {
  var value = (input ?? '').trim();
  if (value.isEmpty) return null;
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabic[i], '$i');
  }
  final parts = value.split(RegExp(r'[/\-]'));
  if (parts.length < 3) return null;
  final a = int.tryParse(parts[0].trim());
  final b = int.tryParse(parts[1].trim());
  final c = int.tryParse(parts[2].trim().split(RegExp(r'[ T]')).first);
  if (a == null || b == null || c == null) return null;
  final (year, month, day) = parts[0].trim().length == 4 ? (a, b, c) : (c, b, a);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

List<Map<String, dynamic>> _simple(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final m in decoded.whereType<Map>())
        m.map((k, v) => MapEntry('$k', v)),
    ];
  } catch (_) {
    return const [];
  }
}

String _plain(double value) {
  final v = (value.abs() * 100).round() / 100;
  return v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
}

/// معرّف الالتزام من معرّف التنبيه («id#f0» ← «id»).
String sharedAlertEntryId(String sourceId) => sourceId.split('#').first;

/// كل تنبيهات الالتزام المشترك المفتوح.
List<HomeCalendarItem> sharedAlertItems(SharedEntryRecord entry) {
  final id = entry.id ?? '';
  final details = entry.details;
  final name = entry.title.trim().isEmpty
      ? entry.entryType
      : entry.title.trim();
  final currency = (details['العملة'] ?? '').trim().isEmpty
      ? AppSettings.currencySuffix
      : details['العملة']!.trim();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final out = <HomeCalendarItem>[];

  // معرّف كل تنبيه: معرّف الالتزام ثم «#» ولاحقة تميّزه — فلا تتداخل
  // إشعارات الهاتف المجدولة، ويُفتح الالتزام نفسه بما قبل «#».
  // ---- المتابعة والتخطيط: مهمة، موعد، عادة، تذكير، ملاحظات.
  final follows = _simple(details['متابعة وتخطيط']);
  for (var i = 0; i < follows.length; i++) {
    final m = follows[i];
    final date = _parseDate('${m['date'] ?? ''}');
    if (date == null) continue;
    final kind = '${m['kind'] ?? ''}'.trim().isEmpty
        ? 'مهمة'
        : '${m['kind']}'.trim();
    final title = '${m['title'] ?? ''}'.trim();
    final extra = m['extra'] is Map
        ? (m['extra'] as Map).map((k, v) => MapEntry('$k', '$v'))
        : const <String, String>{};
    // المكتمل لا يُنبَّه.
    if ((extra['الحالة'] ?? '') == 'مكتملة') continue;
    final repeat = (extra['التكرار'] ?? '').trim();
    final recurring = repeat.isNotEmpty &&
        !repeat.contains('بدون') &&
        !repeat.contains('لا يتكرر');
    out.add(
      HomeCalendarItem(
        title: '${title.isEmpty ? AppTr.tr(kind) : title} — $name',
        module: _module,
        date: recurring
            ? HomeDashboardService.nextOccurrence(date, repeat, today)
            : date,
        sourceId: '$id#f$i',
        type: kind,
        entryType: kind,
        time: (extra['الوقت'] ?? '').trim(),
        repeat: recurring ? repeat : '',
        description: kind,
      ),
    );
  }

  // ---- المستندات: تنبيه قبل تاريخ الانتهاء.
  final docs = _simple(details['مستندات']);
  for (var i = 0; i < docs.length; i++) {
    final m = docs[i];
    final date = _parseDate('${m['date'] ?? ''}');
    if (date == null) continue;
    final title = '${m['title'] ?? ''}'.trim();
    out.add(
      HomeCalendarItem(
        title: '${AppTr.tr('انتهاء')} '
            '${title.isEmpty ? AppTr.tr('مستند') : title} — $name',
        module: _module,
        date: date,
        sourceId: '$id#d$i',
        type: 'مستند',
        entryType: 'مستند',
        isExpiry: true,
      ),
    );
  }

  // ---- الجمعية: موعد الدورة الجارية.
  final type = entry.entryType.trim();
  if (type == 'جمعية مالية' || type == 'جمعية') {
    final plan = RoscaLedger.plan(details, sharedMemberNames(details));
    final current = plan.current;
    final due = current?.dueDate;
    if (current != null && due != null) {
      out.add(
        HomeCalendarItem(
          title: '${AppTr.tr('الدورة رقم')}: ${current.index} — $name',
          module: _module,
          date: DateTime(due.year, due.month, due.day),
          sourceId: '$id#r${current.index}',
          type: 'استحقاق',
          entryType: 'جمعية مالية',
          description: current.receiver,
        ),
      );
    }

    // ---- التأخر في الدفع: مساهمة حلّ موعدها ولم تُدفع — لي، وللمسؤول
    // عن كل عضو.
    final names = sharedMemberNames(details);
    final manager = sharedIAmManager(details);
    final myId = AppIdentity.id;
    for (final cycle in plan.cycles) {
      final due = cycle.dueDate;
      if (due == null) continue;
      final dueDay = DateTime(due.year, due.month, due.day);
      if (!dueDay.isBefore(today)) continue;
      for (final member in names) {
        if (cycle.memberPaid(member)) continue;
        final mine = (myId.isNotEmpty && member.contains('($myId)')) ||
            AppSettings.instance.isMyName(member);
        if (!mine && !manager) continue;
        final shown = member
            .replaceAll(RegExp(r'\s*\(FND-[A-Z2-9]{4}-[A-Z2-9]{4}\)'), '')
            .trim();
        out.add(
          HomeCalendarItem(
            title: mine
                ? '${AppTr.tr('متأخرة')}: ${AppTr.tr('مساهمتك في الدورة')} '
                      '${cycle.index} — $name'
                : '${AppTr.tr('متأخرة')}: $shown — '
                      '${AppTr.tr('الدورة رقم')} ${cycle.index} — $name',
            module: _module,
            date: dueDay,
            sourceId: '$id#r${cycle.index}-${names.indexOf(member)}',
            type: 'استحقاق',
            entryType: 'جمعية مالية',
          ),
        );
      }
    }
  }

  // ---- بانتظار اعتمادي (المسؤول وحده يعتمد).
  if (sharedIAmManager(details)) {
    for (final e in SharedLedger.expenses(details).where((e) => e.isPending)) {
      final label = e.description.trim().isEmpty
          ? AppTr.tr('مصروف')
          : e.description;
      out.add(
        HomeCalendarItem(
          title: '${AppTr.tr('مصروف بانتظار اعتمادك')}: $label '
              '${_plain(e.amount)} $currency — $name',
          module: _module,
          date: _parseDate(e.date) ?? today,
          sourceId: '$id#a${e.id}',
          type: sharedApprovalAlertType,
          entryType: sharedApprovalAlertType,
          remindBeforeDays: 0,
        ),
      );
    }
    for (final c
        in SharedLedger.contributions(details).where((c) => c.isPending)) {
      out.add(
        HomeCalendarItem(
          title: '${AppTr.tr('ميزانية إضافية بانتظار اعتمادك')}: '
              '${_plain(c.amount)} $currency — $name',
          module: _module,
          date: _parseDate(c.date) ?? today,
          sourceId: '$id#c${c.id}',
          type: sharedApprovalAlertType,
          entryType: sharedApprovalAlertType,
          remindBeforeDays: 0,
        ),
      );
    }
  }

  // ---- الميزانية: بلوغ النسبة المختارة، أو تجاوز الميزانية دائمًا.
  if (sharedHasPot(details)) {
    final budget = SharedLedger.budget(details);
    final left = SharedLedger.remaining(details);
    final percent = sharedBudgetAlertPercent(details);
    final spentPct = sharedSpentPercent(details);
    final exceeded = left < -0.01;
    if (exceeded || (percent > 0 && spentPct + 0.001 >= percent)) {
      // يوم بلوغ الحد: أول مصروف معتمد جعل المجموع يصل إليه.
      final limit = exceeded ? budget : budget * percent / 100;
      final rows = [
        for (final e in SharedLedger.approvedExpenses(details))
          (_parseDate(e.date) ?? today, e.amount),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var sum = 0.0;
      var reached = today;
      for (final row in rows) {
        sum += row.$2;
        if (exceeded ? sum > limit + 0.01 : sum + 0.01 >= limit) {
          reached = row.$1;
          break;
        }
      }
      out.add(
        HomeCalendarItem(
          title: exceeded
              ? '${AppTr.tr('تجاوز الميزانية')} «$name»: '
                    '${AppTr.tr('العجز')} ${_plain(-left)} $currency'
              : '${AppTr.tr('الميزانية')} «$name»: ${AppTr.tr('صُرف')} '
                    '${spentPct.round()}% ${AppTr.tr('من قيمتها')}',
          module: _module,
          date: reached,
          sourceId: '$id#b',
          type: sharedBudgetAlertType,
          entryType: sharedBudgetAlertType,
          remindBeforeDays: 0,
        ),
      );
    }
  }
  return out;
}
