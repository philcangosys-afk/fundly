import 'dart:convert';

import 'package:flutter/material.dart' hide Text, Align;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/app_settings.dart';
import '../data/custody_sharing.dart';
import '../data/delegations_repository.dart';
import '../data/lease_contract_data.dart';
import '../data/personal_entries_repository.dart';
import '../data/project_assets_repository.dart';
import '../data/shared_entries_repository.dart';
import '../data/shared_expenses.dart';
import '../data/shared_alerts.dart';
import '../data/rosca_cycles.dart';
import '../widgets/shared/app_design.dart';
import 'rent_payments_view.dart';

/// صفحة «الملخص» — تُفتح مباشرة من «ملخص شامل» في الصفحة الرئيسية.
///
/// فوقها «فلتر ▼» للفترة، ثم تبويبات: الملخص الشامل، الالتزامات الشخصية،
/// الالتزامات المشتركة، الأفراد/الجهات، العقارات/الأنشطة/الآليات. كل تبويب
/// مستطيلات جنب بعض بترتيب الورقة: 1 يمين، 2 يسار، 3 تحت 1، 4 تحت 2...
class GlobalSummaryScreen extends StatefulWidget {
  /// عند الفتح من قسم بعينه: تبويبه وحده بلا شريط التبويبات (1 الشخصية،
  /// 2 المشتركة، 3 الأفراد/الجهات، 4 العقارات والأنشطة والآليات).
  final int? onlyTab;

  /// يُعرض نافذة منبثقة (كمركز المتابعة) بدل صفحة كاملة.
  final bool asSheet;

  const GlobalSummaryScreen({super.key, this.onlyTab, this.asSheet = false});

  @override
  State<GlobalSummaryScreen> createState() => _GlobalSummaryScreenState();
}

/// مستطيل واحد: عنوان اختياري وسطور (الاسم ← القيمة).
class _SummaryBox {
  const _SummaryBox(this.rows, {this.title = ''});
  final String title;
  final List<(String, String)> rows;
}

class _GlobalSummaryScreenState extends State<GlobalSummaryScreen> {
  static const _accent = Color(0xFF0E7161);

  static const _tabs = [
    'الملخص الشامل',
    'الالتزامات الشخصية',
    'الالتزامات المشتركة',
    'الأفراد/الجهات',
    'العقارات/الأنشطة التجارية/المركبات ووسائل النقل',
  ];

  static const _periods = [
    'جميع الأوقات',
    'اليوم',
    'أمس',
    'آخر 7 أيام',
    'بعد 7 أيام',
    'مخصص',
  ];

  late int _tab = widget.onlyTab ?? 0;
  String _period = 'جميع الأوقات';
  DateTimeRange? _customRange;
  late Future<_SummaryData> _future = _SummaryData.load();

  // ---------------- الفترة ----------------

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  (DateTime, DateTime)? get _range {
    final today = _today;
    return switch (_period) {
      'اليوم' => (today, today),
      'أمس' => (
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      'آخر 7 أيام' => (today.subtract(const Duration(days: 6)), today),
      'بعد 7 أيام' => (today, today.add(const Duration(days: 7))),
      'مخصص' =>
        _customRange == null
            ? null
            : (
                DateUtils.dateOnly(_customRange!.start),
                DateUtils.dateOnly(_customRange!.end),
              ),
      _ => null,
    };
  }

  /// هل يقع التاريخ داخل الفترة؟ «جميع الأوقات» = كل شيء.
  bool _inPeriod(DateTime? date) {
    final range = _range;
    if (range == null) return true;
    if (date == null) return false;
    final day = DateUtils.dateOnly(date);
    return !day.isBefore(range.$1) && !day.isAfter(range.$2);
  }

  String get _periodLabel {
    if (_period != 'مخصص' || _customRange == null) return _period;
    final s = _customRange!.start;
    final e = _customRange!.end;
    return '${s.day}/${s.month} - ${e.day}/${e.month}/${e.year}';
  }

  Future<void> _pickPeriod(String value) async {
    if (value != 'مخصص') {
      setState(() => _period = value);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = 'مخصص';
      _customRange = picked;
    });
  }

  // ---------------- التنسيق ----------------

  String _money(double value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final sign = rounded < 0 ? '-' : '';
    return AppSettings.maskAmount(
      '$sign$buffer ${AppSettings.currencySuffix}',
    );
  }

  String _count(int value) => '$value';

  static String _titleOf(String label) => switch (label) {
    'عدد التفويضات' => 'التفويضات',
    'عدد المواقع والأماكن' => 'المواقع والأماكن',
    'عدد الأفراد' => 'الأفراد',
    'عدد الجهات' => 'الجهات',
    'عدد الصيانات المفتوحة' => 'الصيانة',
    'عدد العهد المالية النشطة' => 'العهد المالية',
    'عدد الأدوية اليوم' => 'الأدوية',
    'عدد الالتزامات المشتركة' => 'الالتزامات المشتركة',
    'عدد المشاركات المشتركة النشطة' => 'المشاركات المشتركة',
    'عدد الرحلة / السفر النشطة' => 'الرحلة / السفر',
    'عدد تحديد الأدوار النشطة' => 'تحديد الأدوار',
    _ => label.startsWith('عدد ') ? label.substring(4) : label,
  };

  // ---------------- حساب المستطيلات ----------------

  List<_SummaryBox> _boxesFor(_SummaryData data) {
    final p = _PersonalSummary(data.personal, _inPeriod, _today);
    final s = _SharedSummary(data.shared, _inPeriod, _today);
    final r = _PeopleSummary(data.people, _inPeriod, _today);
    final a = _AssetsSummary(data, _inPeriod, _today);
    final delegations = data.delegations
        .where((d) => _inPeriod(d.startDate))
        .toList(growable: false);
    int delegationsOf(String scope) => delegations
        .where((d) => DelegationRecord.mainScopeOf(d.scope) == scope)
        .length;

    _SummaryBox money(
      double received,
      double toReceive,
      double spent,
      double toSpend, {
      int? deposits,
      double? depositsAmount,
      Map<String, int>? cheques,
    }) => _SummaryBox([
      ('المبالغ المستلمة', _money(received)),
      ('المبالغ التي سيتم استلامها', _money(toReceive)),
      ('المبالغ المصروفة', _money(spent)),
      ('المبالغ التي سيتم صرفها', _money(toSpend)),
      if (deposits != null) ('عدد التأمينات', _count(deposits)),
      if (depositsAmount != null) ('مبالغ التأمينات', _money(depositsAmount)),
      // الشيكات بحالاتها.
      if (cheques != null)
        for (final state in _AssetsSummary.chequeStates)
          ('شيكات: $state', _count(cheques[state] ?? 0)),
    ], title: 'المالية');

    _SummaryBox debts(double mine, double onMe) => _SummaryBox([
      ('مبالغ لي', _money(mine)),
      ('مبالغ عليّ', _money(onMe)),
    ], title: 'الديون');

    _SummaryBox docs(int total, int soon, int expired) => _SummaryBox([
      ('عدد المستندات', _count(total)),
      ('عدد المستندات قريبة الانتهاء', _count(soon)),
      ('عدد المستندات المنتهية', _count(expired)),
    ], title: 'المستندات');

    _SummaryBox follow(_FollowCounts f) => _SummaryBox([
      ('عدد المهام', _count(f.tasks)),
      ('عدد المواعيد', _count(f.appointments)),
      ('عدد العادات', _count(f.habits)),
      ('عدد التذكيرات', _count(f.reminders)),
      ('عدد الملاحظات', _count(f.notes)),
    ], title: 'المتابعة والتخطيط');

    // كل مستطيل له عنوان؛ عنوان المستطيل ذي الرقم الواحد من اسمه.
    _SummaryBox one(String label, String value) =>
        _SummaryBox([(label, value)], title: _titleOf(label));

    final peopleCount = r.individuals;
    final entitiesCount = r.entities;

    switch (_tab) {
      case 1: // الالتزامات الشخصية
        return [
          money(p.received, p.toReceive, p.spent, p.toSpend),
          _SummaryBox([
            ('عدد العهد النشطة', _count(p.custodyActive)),
            ('عدد العهد المنتهية', _count(p.custodyEnded)),
            ('إجمالي مبلغ العهد المالية', _money(p.custodyTotal)),
          ], title: 'عهدة مالية'),
          // الديون مكان المستندات، والمستندات مكان الديون.
          debts(p.mine, p.onMe),
          follow(p.follow),
          _SummaryBox([
            ('عدد الأدوية', _count(p.meds)),
            ('عدد الأدوية اليوم', _count(p.medsToday)),
            ('عدد الأدوية القادمة', _count(p.medsUpcoming)),
            ('عدد الأدوية المنتهية', _count(p.medsEnded)),
          ], title: 'أدوية'),
          docs(p.docs, p.docsSoon, p.docsExpired),
          _SummaryBox([
            ('عدد المناسبات النشطة', _count(p.occasions)),
            ('عدد الاشتراكات النشطة', _count(p.subscriptions)),
            ('عدد الهدايا النشطة', _count(p.gifts)),
          ], title: 'نمط الحياة'),
          _SummaryBox([
            ('عدد الأفراد', _count(peopleCount)),
            ('عدد الجهات', _count(entitiesCount)),
          ], title: 'الأفراد والجهات'),
          one(
            'عدد التفويضات',
            _count(p.delegations + delegationsOf('الالتزامات الشخصية')),
          ),
          one('عدد المواقع والأماكن', _count(p.places)),
        ];
      case 2: // الالتزامات المشتركة
        return [
          money(s.received, s.toReceive, s.spent, s.toSpend),
          // نظام المصروفات كالعهدة: ما ينتظر الاعتماد، وحال الميزانيات.
          _SummaryBox([
            ('مصروفات بانتظار الاعتماد', _count(s.pendingCount)),
            ('مبالغ بانتظار الاعتماد', _money(s.pendingAmount)),
            ('ميزانيات مستنفدة', _count(s.drained)),
            ('ميزانيات قريبة الاستنفاد', _count(s.nearlyDrained)),
          ], title: 'الميزانية والمصروفات'),
          debts(s.mine, s.onMe),
          docs(s.docs, s.docsSoon, s.docsExpired),
          follow(s.follow),
          one('عدد المشاركات المشتركة النشطة', _count(s.activeShares)),
          one('عدد الرحلة / السفر النشطة', _count(s.activeTrips)),
          one('عدد تحديد الأدوار النشطة', _count(s.activeRoles)),
          one('عدد المواقع والأماكن', _count(s.places)),
        ];
      case 3: // الأفراد / الجهات
        return [
          money(r.received, r.toReceive, r.spent, r.toSpend),
          debts(r.mine, r.onMe),
          docs(r.docs, r.docsSoon, r.docsExpired),
          follow(r.follow),
          one('عدد الأفراد', _count(peopleCount)),
          one('عدد الجهات', _count(entitiesCount)),
          one('عدد التفويضات', _count(delegations.length)),
          one('عدد المواقع والأماكن', _count(r.places)),
        ];
      case 4: // العقارات / الأنشطة / الآليات
        // ثلاثة مستطيلات فقط، لكل فئة ماليتها وشيكاتها ومستنداتها وعقودها.
        _SummaryBox categoryBox(
          String category,
          String title,
          String activeLabel,
          String cancelledLabel,
        ) {
          final c = _AssetsSummary(
            data.forCategory(category),
            _inPeriod,
            _today,
          );
          return _SummaryBox([
            (activeLabel, _count(c.activeOf(category))),
            (cancelledLabel, _count(c.cancelledOf(category))),
            ('المبالغ المستلمة', _money(c.received)),
            ('المبالغ التي سيتم استلامها', _money(c.toReceive)),
            ('المبالغ المصروفة', _money(c.spent)),
            ('المبالغ التي سيتم صرفها', _money(c.toSpend)),
            ('عدد التأمينات', _count(c.deposits)),
            ('مبالغ التأمينات', _money(c.depositsAmount)),
            ('عدد الشيكات', _count(c.chequesOf(category))),
            ('إجمالي مبلغ الشيكات', _money(c.chequesAmountOf(category))),
            for (final state in _AssetsSummary.chequeStates)
              ('شيكات: $state', _count(c.cheques[state] ?? 0)),
            ('عدد المستندات', _count(c.docs)),
            ('عدد المستندات قريبة الانتهاء', _count(c.docsSoon)),
            ('عدد المستندات المنتهية', _count(c.docsExpired)),
            ('عدد العقود', _count(c.contracts)),
            ('عدد العقود النشطة', _count(c.contractsActive)),
            ('عدد العقود المنتهية', _count(c.contractsEnded)),
          ], title: title);
        }

        return [
          categoryBox(
            'real_estate',
            'العقارات',
            'عدد العقارات النشطة',
            'عدد العقارات الملغاة',
          ),
          categoryBox(
            // القيمة المخزّنة للأنشطة التجارية في قاعدة البيانات.
            'business',
            'الأنشطة التجارية',
            'عدد الأنشطة التجارية النشطة',
            'عدد الأنشطة التجارية الملغاة',
          ),
          categoryBox(
            'equipment',
            'المركبات ووسائل النقل',
            'عدد المركبات ووسائل النقل النشطة',
            'عدد المركبات ووسائل النقل الملغاة',
          ),
        ];
      default: // الملخص الشامل (عام)
        return [
          money(
            p.received + s.received + r.received + a.received,
            p.toReceive + s.toReceive + r.toReceive + a.toReceive,
            p.spent + s.spent + r.spent + a.spent,
            p.toSpend + s.toSpend + r.toSpend + a.toSpend,
            deposits: a.deposits,
            depositsAmount: a.depositsAmount,
          ),
          debts(p.mine + s.mine + r.mine, p.onMe + s.onMe + r.onMe),
          docs(
            p.docs + s.docs + r.docs + a.docs,
            p.docsSoon + s.docsSoon + r.docsSoon + a.docsSoon,
            p.docsExpired + s.docsExpired + r.docsExpired + a.docsExpired,
          ),
          _SummaryBox([
            ('عدد العقود', _count(a.contracts)),
            ('عدد العقود النشطة', _count(a.contractsActive)),
            ('عدد العقود المنتهية', _count(a.contractsEnded)),
          ], title: 'العقود'),
          follow(p.follow + s.follow + r.follow + a.follow),
          one('عدد العهد المالية النشطة', _count(p.custodyActive)),
          one('عدد الأدوية اليوم', _count(p.medsToday)),
          one('عدد الصيانات المفتوحة', _count(a.openMaintenance)),
          one('عدد الالتزامات المشتركة', _count(s.total)),
          one('عدد الأفراد', _count(peopleCount)),
          one('عدد الجهات', _count(entitiesCount)),
          one(
            'عدد التفويضات',
            _count(delegations.length + p.delegations),
          ),
          one(
            'عدد المواقع والأماكن',
            _count(p.places + s.places + r.places + a.places),
          ),
        ];
    }
  }

  void _share(List<_SummaryBox> boxes) {
    final buffer = StringBuffer()
      ..writeln('الملخص — ${_tabs[_tab]}')
      ..writeln('الفترة: $_periodLabel')
      ..writeln('');
    for (final box in boxes) {
      if (box.title.isNotEmpty) buffer.writeln('• ${box.title}');
      for (final row in box.rows) {
        buffer.writeln('${row.$1}: ${row.$2}');
      }
      buffer.writeln('');
    }
    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  // ---------------- الواجهة ----------------

  // كل الصناديق بحجم واحد: عدد «خانات» ثابت لكل صندوق في التبويب (أكبر
  // صندوق فيه)، وكل خانة سطر واحد بارتفاع ثابت — فيتساوى الحجم ولو بقي
  // بعض الصندوق فارغًا.
  static const double _baseLineHeight = 22;

  /// العقارات والأنشطة والمركبات: سطر أعلى ليظهر الاسم بخط واضح قوي كاملًا
  /// (سطرين عند الحاجة) بدل أن يصغر حتى لا يُقرأ.
  bool get _strongLabels => _tab == 4;
  double get _lineHeight => _strongLabels ? 30 : _baseLineHeight;
  static const double _lineGap = 10;
  static const double _boxPadding = 12;

  double _boxHeight(int slots) =>
      _boxPadding * 2 + slots * _lineHeight + (slots - 1) * _lineGap;

  Widget _line(String label, String value) {
    return SizedBox(
      height: _lineHeight,
      child: Row(
        children: [
          Expanded(
            child: _strongLabels
                ? AppFitText(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C2C29),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5C6B68),
                      ),
                    )),
                  ),
          ),
          const SizedBox(width: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _boxTitle(String title) => SizedBox(
    height: _lineHeight,
    child: Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: _accent,
              ),
            )),
          ),
        ),
      ],
    ),
  );

  /// مجموعة السطر داخل الصندوق (المبالغ، التأمينات، الشيكات، المستندات،
  /// العقود) — بين كل مجموعتين فاصل أوضح.
  static String _groupOf(String label) {
    if (label.startsWith('المبالغ')) return 'money';
    if (label.contains('التأمينات')) return 'deposits';
    if (label.contains('الشيكات') || label.startsWith('شيكات:')) {
      return 'cheques';
    }
    if (label.contains('المستندات')) return 'docs';
    if (label.contains('العقود')) return 'contracts';
    return 'main';
  }

  Widget _box(_SummaryBox box, int slots) {
    final single = box.rows.length == 1;
    return Container(
      height: _boxHeight(slots),
      padding: const EdgeInsets.all(_boxPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAE8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A022E2A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: single
          // رقم واحد: الاسم ورقمه كبيرًا في منتصف الصندوق.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (box.title.isNotEmpty) _boxTitle(box.title),
                Expanded(
                  child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppFitText(
                  box.rows.first.$1,
                  textAlign: TextAlign.center,
                  alignment: Alignment.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5C6B68),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                    box.rows.first.$2,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _accent,
                    ),
                  )),
                ),
              ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (box.title.isNotEmpty) _boxTitle(box.title),
                for (var i = 0; i < box.rows.length; i++) ...[
                  if (i > 0 &&
                      _groupOf(box.rows[i].$1) !=
                          _groupOf(box.rows[i - 1].$1))
                    // بداية مجموعة جديدة: فاصل أوضح بنفس الارتفاع.
                    const Divider(
                      height: _lineGap,
                      thickness: 1.6,
                      color: Color(0xFF9FBAB4),
                    )
                  else if (i > 0 || box.title.isNotEmpty)
                    const Divider(
                      height: _lineGap,
                      color: Color(0xFFF0F3F2),
                    ),
                  _line(box.rows[i].$1, box.rows[i].$2),
                ],
              ],
            ),
    );
  }

  /// مستطيلات جنب بعض صفًّا صفًّا: 1 يمين و2 يسار، ثم 3 و4... وكلها بحجم
  /// واحد.
  Widget _grid(List<_SummaryBox> boxes) {
    // ثلاث خانات على الأقل: صندوق الرقم الواحد يحتاج مساحة اسمه ورقمه.
    var slots = 3;
    for (final box in boxes) {
      final count = box.rows.length + (box.title.isEmpty ? 0 : 1);
      if (count > slots) slots = count;
    }
    return Column(
      children: [
        for (var i = 0; i < boxes.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              textDirection: AppTr.uiDir,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _box(boxes[i], slots)),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < boxes.length
                      ? _box(boxes[i + 1], slots)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _periodButton() {
    return PopupMenuButton<String>(
      tooltip: AppTr.tr('الفترة'),
      onSelected: _pickPeriod,
      itemBuilder: (context) => [
        for (final option in _periods)
          PopupMenuItem(
            value: option,
            child: Directionality(
              textDirection: AppTr.uiDir,
              child: Row(
                children: [
                  Icon(
                    option == _period
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 17,
                    color: option == _period
                        ? _accent
                        : const Color(0xFFD5DEDB),
                  ),
                  const SizedBox(width: 8),
                  Text(option),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD5DEDB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 16, color: _accent),
            const SizedBox(width: 6),
            Text(
              _period == 'جميع الأوقات' ? 'فلتر' : _periodLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabsBar() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final selected = index == _tab;
          return Material(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _tab = index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _accent : const Color(0xFFE4EAE8),
                  ),
                ),
                child: Text(
                  _tabs[index],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF2C3B38),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// محتوى الملخص — نفسه في الصفحة الكاملة وفي النافذة المنبثقة.
  Widget _body() {
    return Directionality(
        textDirection: AppTr.uiDir,
        child: FutureBuilder<_SummaryData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data ?? _SummaryData.empty();
            final boxes = _boxesFor(data);
            return RefreshIndicator(
              onRefresh: () async {
                final next = _SummaryData.load();
                setState(() => _future = next);
                await next;
              },
              child: ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tabs[_tab],
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF022E2A),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppTr.tr('مشاركة'),
                          onPressed: () => _share(boxes),
                          icon: const Icon(
                            Icons.ios_share_rounded,
                            size: 20,
                            color: _accent,
                          ),
                        ),
                        _periodButton(),
                      ],
                    ),
                  ),
                  if (widget.onlyTab == null) ...[
                    const SizedBox(height: 10),
                    _tabsBar(),
                  ],
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _grid(boxes),
                  ),
                ],
              ),
            );
          },
        ),
      );
  }

  /// النافذة المنبثقة: مقبض، عنوان وزر إغلاق، ثم المحتوى.
  Widget _sheet(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.page,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.rCard),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD5DEDB),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_chart_outlined_rounded,
                    color: Color(0xFF0E7161),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'الملخص الشامل',
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                  ),
                  AppIconButton(
                    tooltip: AppTr.tr('إغلاق'),
                    icon: Icons.close_rounded,
                    background: AppTheme.field,
                    color: AppTheme.chevron,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asSheet) return _sheet(context);
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F1F1C),
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.onlyTab == null ? 'الملخص' : 'الملخص الشامل',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F1F1C),
          ),
        ),
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: _body(),
    );
  }
}

/// مستطيل «الملخص الشامل» تحت مركز المتابعة في كل قسم — بشكله وعرضه
/// وأنحف منه، ويفتح ملخص القسم وحده.
class ModuleSummaryCard extends StatelessWidget {
  const ModuleSummaryCard({super.key, required this.tab, this.subtitle});

  /// تبويب القسم في صفحة الملخص.
  final int tab;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Material(
        // داخل مستطيل الوحدة الملوّن: أبيض بحد واضح.
        color: ModuleTintScope.of(context) ? Colors.white : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          side: ModuleTintScope.of(context)
              ? const BorderSide(color: AppTheme.hairline)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // نافذة منبثقة بنفس طريقة مركز المتابعة، لا صفحة كاملة.
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.9,
              child: GlobalSummaryScreen(onlyTab: tab, asSheet: true),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const AppIconTile(
                  icon: Icons.insert_chart_outlined_rounded,
                  color: Color(0xFF0E7161),
                  size: 34,
                  iconSize: 18,
                ),
                const SizedBox(width: AppTheme.sMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الملخص الشامل', style: AppTheme.cardTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 3,
                          style: AppTheme.rowSubtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                const AppChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// تحميل البيانات
// ======================================================================

class _SummaryData {
  _SummaryData({
    required this.personal,
    required this.shared,
    required this.people,
    required this.assets,
    required this.contracts,
    required this.payments,
    required this.entries,
    required this.delegations,
  });

  factory _SummaryData.empty() => _SummaryData(
    personal: const [],
    shared: const [],
    people: const [],
    assets: const [],
    contracts: const [],
    payments: const [],
    entries: const [],
    delegations: const [],
  );

  /// نفس البيانات مقصورة على فئة أصول واحدة (عقارات / أنشطة / مركبات):
  /// أصولها، وعقودها، ودفعات تلك العقود، وبنودها.
  _SummaryData forCategory(String category) {
    final ids = {
      for (final asset in assets)
        if (asset.category == category && asset.id != null) asset.id!,
    };
    final contractsOf = [
      for (final c in contracts)
        if (ids.contains(c.assetId)) c,
    ];
    final contractIds = {
      for (final c in contractsOf)
        if (c.id != null) c.id!,
    };
    return _SummaryData(
      personal: const [],
      shared: const [],
      people: const [],
      assets: [
        for (final asset in assets)
          if (asset.category == category) asset,
      ],
      contracts: contractsOf,
      payments: [
        for (final p in payments)
          if (contractIds.contains(p.contractId)) p,
      ],
      entries: [
        for (final e in entries)
          if (ids.contains(e.assetId)) e,
      ],
      delegations: const [],
    );
  }

  final List<PersonalEntryRecord> personal;
  final List<SharedEntryRecord> shared;
  final List<Map<String, dynamic>> people;
  final List<ProjectAssetRecord> assets;
  final List<PropertyUnitContractRecord> contracts;
  final List<PropertyUnitPaymentRecord> payments;
  final List<ProjectAssetEntryRecord> entries;
  final List<DelegationRecord> delegations;

  /// كل مصدر في محاولة مستقلة: فشل أحدها لا يُفرغ الملخص كله.
  static Future<_SummaryData> load() async {
    Future<List<T>> safe<T>(Future<List<T>> Function() read) async {
      try {
        return await read();
      } catch (error) {
        debugPrint('GlobalSummary load failed: $error');
        return <T>[];
      }
    }

    final assetsRepo = SupabaseProjectAssetsRepository();
    final results = await Future.wait<Object>([
      safe(() => SupabasePersonalEntriesRepository().fetchAll()),
      safe(() => SupabaseSharedEntriesRepository().fetchAll()),
      safe(_loadPeople),
      safe(assetsRepo.fetchAssets),
      safe(assetsRepo.fetchAllUnitContracts),
      safe(assetsRepo.fetchAllUnitPayments),
      safe(assetsRepo.fetchAllEntries),
      safe(() => SupabaseDelegationsRepository().fetchDelegations()),
    ]);
    return _SummaryData(
      personal: results[0] as List<PersonalEntryRecord>,
      shared: results[1] as List<SharedEntryRecord>,
      people: results[2] as List<Map<String, dynamic>>,
      assets: results[3] as List<ProjectAssetRecord>,
      contracts: results[4] as List<PropertyUnitContractRecord>,
      payments: results[5] as List<PropertyUnitPaymentRecord>,
      entries: results[6] as List<ProjectAssetEntryRecord>,
      delegations: results[7] as List<DelegationRecord>,
    );
  }

  static Future<List<Map<String, dynamic>>> _loadPeople() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('people_management_records_v1');
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }
}

// ======================================================================
// أدوات مشتركة
// ======================================================================

typedef _InPeriod = bool Function(DateTime? date);

/// d/m/yyyy أو yyyy-m-d.
DateTime? _parseDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final parts = text.split(RegExp(r'[/\-]'));
  if (parts.length < 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2].split(' ').first.split('T').first);
  if (a == null || b == null || c == null) return null;
  return a > 31 ? DateTime(a, b, c) : DateTime(c, b, a);
}

double _num(String? raw) =>
    double.tryParse(
      (raw ?? '').replaceAll(RegExp(r'[^0-9.\-]'), ''),
    ) ??
    0;

const _closedStatuses = {
  'مكتملة',
  'مكتمل',
  'مسددة',
  'مؤرشف',
  'منتهية',
  'تمت التسوية',
};

class _FollowCounts {
  _FollowCounts([
    this.tasks = 0,
    this.appointments = 0,
    this.habits = 0,
    this.reminders = 0,
    this.notes = 0,
  ]);

  int tasks;
  int appointments;
  int habits;
  int reminders;
  int notes;

  void add(String kind) {
    final k = kind.trim();
    if (k.contains('مهمة') || k.contains('مهام')) {
      tasks++;
    } else if (k.contains('موعد') || k.contains('مواعيد')) {
      appointments++;
    } else if (k.contains('عادة') || k.contains('عادات')) {
      habits++;
    } else if (k.contains('تذكير')) {
      reminders++;
    } else if (k.contains('ملاحظ')) {
      notes++;
    }
  }

  _FollowCounts operator +(_FollowCounts other) => _FollowCounts(
    tasks + other.tasks,
    appointments + other.appointments,
    habits + other.habits,
    reminders + other.reminders,
    notes + other.notes,
  );
}

// ======================================================================
// الالتزامات الشخصية
// ======================================================================

class _PersonalSummary {
  _PersonalSummary(
    List<PersonalEntryRecord> entries,
    _InPeriod inPeriod,
    DateTime today,
  ) {
    const income = {'إيراد', 'دخل'};
    const expense = {
      'المصروفات الشخصية',
      'مصروف',
      'قسط',
      'غرامة',
      'تحويل مالي',
    };
    final myId = AppIdentity.id;
    for (final e in entries) {
      // المحذوف (في السلة) لا يدخل أي رقم.
      if (e.status.trim() == 'محذوف') continue;
      final due = _parseDate(e.dueDate);
      final date = due ?? e.createdAt;
      if (!inPeriod(date)) continue;
      final type = e.entryType.trim();
      final closed = _closedStatuses.contains(e.status.trim());
      final cancelled = e.status.trim() == 'ملغاة' || e.status.trim() == 'ملغى';
      final open = !closed && !cancelled;
      // عهدة أو دين مع حساب آخر: يُقرأ من جهتي، وما لم أقبله لا يُحسب.
      var flipDebt = false;
      if (type == 'عهدة مالية' || type == 'دين / قرض / سلفة') {
        final assignment = CustodyAssignment.decode(e.details);
        final role = assignment.roleFor(myId);
        if (role == CustodyRole.observer ||
            (role == CustodyRole.holder && !assignment.isAccepted)) {
          continue;
        }
        flipDebt = role == CustodyRole.holder;
      }
      if (cancelled && (income.contains(type) || expense.contains(type))) {
        continue;
      }
      // تمّ: مكتمل، أو بلا تاريخ، أو حلّ تاريخه.
      final done = closed || due == null || !due.isAfter(today);
      final amount = e.amount.toDouble();

      if (income.contains(type)) {
        if (done) {
          received += amount;
        } else {
          toReceive += amount;
        }
      } else if (expense.contains(type)) {
        if (done) {
          spent += amount;
        } else {
          toSpend += amount;
        }
      } else if (type == 'دين / قرض / سلفة' || type == 'ديون') {
        if (open) {
          final dir = (e.details['نوع الدين'] ?? e.details['الاتجاه'] ?? '')
              .trim();
          final forOwner = dir.startsWith('لي') || dir.contains('يدين لي');
          if (forOwner != flipDebt) {
            mine += amount;
          } else {
            onMe += amount;
          }
        }
      } else if (type == 'عهدة مالية') {
        custodyTotal += cancelled ? 0 : amount;
        if (closed || cancelled) {
          custodyEnded++;
        } else {
          custodyActive++;
        }
      } else if (type == 'مستند') {
        docs++;
        // المؤرشف / الملغى ليس «منتهيًا» يحتاج متابعة.
        if (due != null && open) {
          final days = due.difference(today).inDays;
          if (days < 0) {
            docsExpired++;
          } else if (days <= 30) {
            docsSoon++;
          }
        }
      } else if (type == 'أدوية') {
        meds++;
        if (!open) continue;
        final from = _parseDate(e.details['من تاريخ']);
        final to = _parseDate(e.details['إلى تاريخ']);
        if (to != null && to.isBefore(today)) {
          medsEnded++;
        } else if (from != null && from.isAfter(today)) {
          medsUpcoming++;
        } else {
          medsToday++;
        }
      } else if (type == 'مناسبة') {
        if (open) occasions++;
      } else if (type == 'اشتراك' || type == 'اشتراكات') {
        if (open) subscriptions++;
      } else if (type == 'هدية') {
        if (open) gifts++;
      } else if (type == 'مواقع وأماكن') {
        places++;
      } else if (type == 'تفويض') {
        delegations++;
      } else {
        follow.add(type);
      }
    }
  }

  double received = 0;
  double toReceive = 0;
  double spent = 0;
  double toSpend = 0;
  double mine = 0;
  double onMe = 0;
  int custodyActive = 0;
  double custodyTotal = 0;
  int custodyEnded = 0;
  int docs = 0;
  int docsSoon = 0;
  int docsExpired = 0;
  int meds = 0;
  int medsToday = 0;
  int medsUpcoming = 0;
  int medsEnded = 0;
  int occasions = 0;
  int subscriptions = 0;
  int gifts = 0;
  int places = 0;
  int delegations = 0;
  final _FollowCounts follow = _FollowCounts();
}

// ======================================================================
// الالتزامات المشتركة
// ======================================================================

/// بنود بسيطة داخل التفاصيل (مستندات، متابعة، أماكن) بصيغة JSON.
List<Map<String, String>> _simpleEntries(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded.whereType<Map>())
        item.map((key, value) => MapEntry('$key', '${value ?? ''}')),
    ];
  } catch (_) {
    return const [];
  }
}

/// اسمي كما هو في قائمة أعضاء الالتزام: بالرقم التعريفي أولًا ثم بالاسم.
String _memberNameOf(Map<String, String> details, String myName) {
  final id = AppIdentity.id;
  try {
    final decoded = jsonDecode(details['الأعضاء'] ?? '[]');
    if (decoded is List) {
      for (final member in decoded.whereType<Map>()) {
        final name = '${member['name'] ?? ''}'.trim();
        if (id.isNotEmpty && name.contains('($id)')) return name;
      }
      for (final member in decoded.whereType<Map>()) {
        final name = '${member['name'] ?? ''}'.trim();
        if (name == myName || name == AppSettings.instance.publicName) {
          return name;
        }
      }
    }
  } catch (_) {}
  return myName;
}

class _SharedSummary {
  _SharedSummary(
    List<SharedEntryRecord> entries,
    _InPeriod inPeriod,
    DateTime today,
  ) {
    final me = AppSettings.instance.name.trim();
    for (final e in entries) {
      final date = _parseDate(e.dueDate) ?? e.createdAt;
      if (!inPeriod(date)) continue;
      total++;
      final details = e.details;
      final status = e.status.trim();
      final open =
          !_closedStatuses.contains(status) && !status.contains('ملغا');

      // الوعاء: ما جُمع وما صُرف.
      final budget = SharedLedger.budget(details);
      final spentNow = SharedLedger.total(details);
      received += budget;
      final planned = e.amount.toDouble();
      final isRosca = e.entryType.trim() == 'جمعية مالية' ||
          e.entryType.trim() == 'جمعية';
      // الجمعية تُحسب من دوراتها تحت.
      if (!isRosca && planned > budget) toReceive += planned - budget;
      spent += spentNow;
      final left = SharedLedger.remaining(details);
      if (left > 0) toSpend += left;

      // الجمعية: ما جُمع من الأعضاء وما بقي، وما سُلِّم لأصحاب الأدوار.
      if (isRosca) {
        final plan = RoscaLedger.plan(details, sharedMemberNames(details));
        received += plan.collectedTotal;
        toReceive += plan.remainingTotal;
        for (final cycle in plan.cycles) {
          if (cycle.isPaidOut) {
            spent += cycle.collected;
          } else {
            toSpend += cycle.collected;
          }
        }
      }

      // بانتظار الاعتماد، وحال الميزانية (كالعهدة).
      for (final x in SharedLedger.expenses(details).where((x) => x.isPending)) {
        pendingCount++;
        pendingAmount += x.amount;
      }
      for (final c
          in SharedLedger.contributions(details).where((c) => c.isPending)) {
        pendingCount++;
        pendingAmount += c.amount;
      }
      if (open && sharedPotDrained(details)) drained++;
      if (open && sharedPotNearlyDrained(details)) nearlyDrained++;

      // رصيدك أنت: موجب لك، سالب عليك.
      // اسمي في الأعضاء قد يكون مع رقمي: «سارة (FND-...)».
      final who = _memberNameOf(details, me);
      if (who.isNotEmpty) {
        // المتبقي في الوعاء ليس دينًا بين الأعضاء قبل التسوية.
        final net = SharedLedger.memberNet(details, who);
        if (net > 0) mine += net;
        if (net < 0) onMe += -net;
      }

      for (final doc in _simpleEntries(details['مستندات'])) {
        docs++;
        final due = _parseDate(doc['date']);
        if (due == null) continue;
        final days = due.difference(today).inDays;
        if (days < 0) {
          docsExpired++;
        } else if (days <= 30) {
          docsSoon++;
        }
      }
      for (final item in _simpleEntries(details['متابعة وتخطيط'])) {
        follow.add(item['kind'] ?? '');
      }
      places += _simpleEntries(details['مواقع وأماكن']).length;

      if (open) {
        final type = e.entryType.trim();
        if (type == 'الرحلة / السفر' || type == 'رحلة') {
          activeTrips++;
        } else if (type == 'جمعية مالية' || type == 'جمعية') {
          activeRoles++;
        } else {
          activeShares++;
        }
      }
    }
  }

  int total = 0;
  double received = 0;
  double toReceive = 0;
  double spent = 0;
  double toSpend = 0;
  double mine = 0;
  double onMe = 0;
  int docs = 0;
  int docsSoon = 0;
  int docsExpired = 0;
  int places = 0;
  int activeShares = 0;
  int activeTrips = 0;
  int activeRoles = 0;
  int pendingCount = 0;
  double pendingAmount = 0;
  int drained = 0;
  int nearlyDrained = 0;
  final _FollowCounts follow = _FollowCounts();
}

// ======================================================================
// الأفراد والجهات
// ======================================================================

class _PeopleSummary {
  _PeopleSummary(
    List<Map<String, dynamic>> people,
    _InPeriod inPeriod,
    DateTime today,
  ) {
    for (final person in people) {
      if ('${person['extraNote'] ?? ''}'.contains('[مؤرشف]')) continue;
      final created = _parseDate('${person['createdAt'] ?? ''}');
      final details = <String, String>{
        if (person['details'] is Map)
          for (final entry in (person['details'] as Map).entries)
            '${entry.key}': '${entry.value ?? ''}',
      };

      if (inPeriod(created)) {
        final isEntity = '${person['typeKey'] ?? ''}'.startsWith('entity_');
        if (isEntity) {
          entities++;
        } else {
          individuals++;
        }
        mine += ((person['dueToYou'] as num?) ?? 0).toDouble();
        onMe += ((person['dueOnYou'] as num?) ?? 0).toDouble();
        if ((details['العنوان'] ?? details['المكان'] ?? '').trim().isNotEmpty) {
          places++;
        }
        // المستندات: الوثائق المسجّلة + كل تاريخ انتهاء.
        final docsList = person['documents'];
        docs += docsList is List ? docsList.length : 0;
        for (final entry in details.entries) {
          if (!entry.key.startsWith('انتهاء ')) continue;
          final due = _parseDate(entry.value);
          if (due == null) continue;
          if (docsList is! List || docsList.isEmpty) docs++;
          final days = due.difference(today).inDays;
          if (days < 0) {
            docsExpired++;
          } else if (days <= 30) {
            docsSoon++;
          }
        }
      }

      // بنود السجل: «مالية — نوع · له/عليه · مبلغ · ينتهي d/m/yyyy».
      final log = person['activityLog'];
      if (log is! List) continue;
      for (final raw in log) {
        final line = '$raw';
        final dueMatch = RegExp(
          r'ينتهي\s+(\d{1,2}/\d{1,2}/\d{4})',
        ).firstMatch(line);
        final due = dueMatch == null ? null : _parseDate(dueMatch.group(1));
        if (!inPeriod(due ?? created)) continue;
        if (line.startsWith('مالية')) {
          final parts = line.split(' · ');
          final amountPart = parts.firstWhere(
            (part) => part.contains(AppSettings.currencySuffix),
            orElse: () => '',
          );
          final amount = _num(amountPart.replaceAll(
            AppSettings.currencySuffix,
            '',
          ));
          if (amount <= 0) continue;
          final done = due == null || !due.isAfter(today);
          // «عليه» = على الشخص لك (تستلمه)، «له» = له عليك (تصرفه).
          final toMe = parts.contains('عليه');
          if (toMe && done) {
            received += amount;
          } else if (toMe) {
            toReceive += amount;
          } else if (done) {
            spent += amount;
          } else {
            toSpend += amount;
          }
        } else if (line.startsWith('متابعة وتخطيط') ||
            line.startsWith('المتابعة والتخطيط')) {
          final head = line.split(' · ').first;
          final kind = head.contains('—') ? head.split('—').last : head;
          follow.add(kind);
        }
      }
    }
  }

  int individuals = 0;
  int entities = 0;
  double received = 0;
  double toReceive = 0;
  double spent = 0;
  double toSpend = 0;
  double mine = 0;
  double onMe = 0;
  int docs = 0;
  int docsSoon = 0;
  int docsExpired = 0;
  int places = 0;
  final _FollowCounts follow = _FollowCounts();
}

// ======================================================================
// العقارات / الأنشطة التجارية / المركبات ووسائل النقل
// ======================================================================

class _AssetsSummary {
  _AssetsSummary(_SummaryData data, _InPeriod inPeriod, DateTime today) {
    // ما بقي من عقد أُغلق وسُوّيت مبالغه (أو استحقاقه بعد إغلاقه) لا يُحسب
    // مستحقًا؛ وما لم يُسوَّ يبقى مستحقًا يُتابَع.
    // أصول في سلة المهملات: لا عقودها ولا دفعاتها.
    final trashed = {
      for (final asset in data.assets)
        if (asset.status.trim() == 'محذوف' && asset.id != null) asset.id!,
    };
    // المسودة لم تُعتمد: لا تُعدّ عقدًا ولا تُستحق دفعاتها.
    final contractById = {
      for (final c in data.contracts)
        if (c.id != null &&
            !trashed.contains(c.assetId) &&
            c.status != PropertyUnitContractRecord.statusPending)
          c.id!: c,
    };
    for (final payment in data.payments) {
      if (!contractById.containsKey(payment.contractId)) continue;
      if (!inPeriod(payment.dueDate)) continue;
      received += payment.amountPaid;
      final left = payment.amountDue - payment.amountPaid;
      final owner = contractById[payment.contractId];
      if (left > 0.009 &&
          (owner == null || !paymentWaivedByClosure(owner, payment))) {
        toReceive += left;
      }
      if (decodePayExtra(payment.notes)[kPayKind] == kPayKindDeposit) {
        deposits++;
        depositsAmount += payment.amountDue;
      }
    }

    // فئة كل أصل: لشيكات كل فئة ولعدد النشط والملغى منها.
    final categoryOf = <String, String>{
      for (final asset in data.assets)
        if (asset.id != null) asset.id!: asset.category,
    };
    for (final asset in data.assets) {
      final status = asset.status.trim();
      if (status == 'محذوف' || status == 'مؤرشف') continue;
      final map = status.contains('ملغ') ? _cancelled : _active;
      map[asset.category] = (map[asset.category] ?? 0) + 1;
    }
    for (final contract in contractById.values) {
      if (!inPeriod(contract.startDate ?? contract.endDate)) continue;
      final category = categoryOf[contract.assetId] ?? 'real_estate';
      // الشيكات المكتوبة في العقد بحالة كل منها.
      for (final row in LeaseContractData.decode(contract.notes).payments) {
        if ((row[LeaseContractData.kPaymentCheque] ?? '').trim().isEmpty) {
          continue;
        }
        _chequeCount[category] = (_chequeCount[category] ?? 0) + 1;
        _chequeAmount[category] =
            (_chequeAmount[category] ?? 0) +
            _num(row[LeaseContractData.kPaymentAmount]);
        var state = (row[LeaseContractData.kChequeState] ?? '').trim();
        if (state.isEmpty) {
          state = (row[LeaseContractData.kPaymentStatus] ?? '') == 'مسددة'
              ? LeaseContractData.chequeCleared
              : LeaseContractData.chequeReceived;
        }
        cheques[state] = (cheques[state] ?? 0) + 1;
      }
      contracts++;
      final end = contract.endDate;
      final ended =
          contract.status == PropertyUnitContractRecord.statusExpired ||
          contract.status == 'ended' ||
          contract.status == 'cancelled' ||
          (end != null && DateUtils.dateOnly(end).isBefore(today));
      if (ended) {
        contractsEnded++;
      } else {
        contractsActive++;
      }
    }

    for (final entry in data.entries) {
      final d = entry.data;
      switch (entry.kind) {
        case ProjectAssetEntryRecord.kindExpense:
          {
            final date = _parseDate(d['تاريخ المصروف']);
            if (!inPeriod(date)) break;
            final amount = _num(d['المبلغ']);
            if (date == null || !date.isAfter(today)) {
              spent += amount;
            } else {
              toSpend += amount;
            }
          }
        case ProjectAssetEntryRecord.kindMaintenance:
          {
            final requested = _parseDate(d['تاريخ الطلب']);
            // صيانة البناية بنموذج الوحدة: «التاريخ» و«المبلغ».
            final executed = _parseDate(d['تاريخ التنفيذ'] ?? d['التاريخ']);
            if (!inPeriod(executed ?? requested)) break;
            final cost = _num(d['التكلفة'] ?? d['المبلغ']);
            if (executed != null && !executed.isAfter(today)) {
              spent += cost;
            } else {
              toSpend += cost;
              openMaintenance++;
            }
          }
        case ProjectAssetEntryRecord.kindDocument:
          {
            final due = _parseDate(d['تاريخ الانتهاء']);
            if (!inPeriod(due ?? _parseDate(d['تاريخ الإصدار']))) break;
            docs++;
            if (due == null) break;
            final days = due.difference(today).inDays;
            if (days < 0) {
              docsExpired++;
            } else if (days <= 30) {
              docsSoon++;
            }
          }
        case ProjectAssetEntryRecord.kindRental:
          {
            final kind = d['نوع المتابعة'] ?? '';
            if (kind.isEmpty) break;
            if (!inPeriod(_parseDate(d['التاريخ']))) break;
            follow.add(kind);
          }
      }
    }

    for (final asset in data.assets) {
      final location = (asset.locationOrType ?? '').trim();
      if ((location.isNotEmpty && location != 'غير محدد') ||
          (asset.mapLink ?? '').trim().isNotEmpty) {
        // الأماكن بلا تاريخ: تُحسب مع «جميع الأوقات» فقط.
        if (inPeriod(null)) places++;
      }
    }
  }

  double received = 0;
  double toReceive = 0;
  double spent = 0;
  double toSpend = 0;
  int deposits = 0;
  double depositsAmount = 0;

  /// عدد الشيكات بكل حالة.
  final Map<String, int> cheques = {};

  // حسب الفئة (real_estate / activity / equipment).
  final Map<String, int> _active = {};
  final Map<String, int> _cancelled = {};
  final Map<String, int> _chequeCount = {};
  final Map<String, double> _chequeAmount = {};

  int activeOf(String category) => _active[category] ?? 0;
  int cancelledOf(String category) => _cancelled[category] ?? 0;
  int chequesOf(String category) => _chequeCount[category] ?? 0;
  double chequesAmountOf(String category) => _chequeAmount[category] ?? 0;

  static const chequeStates = <String>[
    LeaseContractData.chequeReceived,
    LeaseContractData.chequeAtBank,
    LeaseContractData.chequeCleared,
    LeaseContractData.chequeRejected,
    LeaseContractData.chequeCancelled,
    LeaseContractData.chequeReplaced,
    LeaseContractData.chequeReturned,
  ];
  int docs = 0;
  int docsSoon = 0;
  int docsExpired = 0;
  int contracts = 0;
  int contractsActive = 0;
  int contractsEnded = 0;
  int openMaintenance = 0;
  int places = 0;
  final _FollowCounts follow = _FollowCounts();
}
