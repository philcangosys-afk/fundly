import 'user_logo_store.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../l10n/app_language.dart';
import '../widgets/shared/app_filter_sheet.dart';
import '../widgets/shared/search_matching.dart';
import 'app_settings.dart';
import 'home_summary_service.dart';
import 'scope_catalog.dart';

// =============================================================================
// التقارير والأرشيف: المعايير (فلتر الصفحة الرئيسية + البحث)، تطبيقها على
// السجلات، وبناء المستند الاحترافي (HTML ← PDF) للمعاينة والطباعة والمشاركة.
// =============================================================================

/// أقسام فلتر التقرير — نفس أقسام فلتر الصفحة الرئيسية وبترتيبها.
const kReportModules = <String>[
  'الكل',
  'الالتزامات الشخصية',
  'الالتزامات المشتركة',
  'الأفراد والجهات',
  'العقارات',
  'الأنشطة التجارية',
  'المركبات ووسائل النقل',
];

/// أقسام الفلتر التي يطبّقها التقرير فعلًا على السجلات. ما سواها (المستندات،
/// الأدوية، الدين، الصيانة، العملة، التفويض) لا يظهر في فلتر التقرير حتى لا
/// يُختار شيء لا أثر له في النتيجة.
const kReportFilterSections = <AppFilterSection>{
  AppFilterSection.mainCategory,
  AppFilterSection.subCategory,
  AppFilterSection.period,
  AppFilterSection.date,
  AppFilterSection.statusSelect,
  AppFilterSection.status,
  AppFilterSection.amountSelect,
  AppFilterSection.amount,
  AppFilterSection.paymentMethod,
  AppFilterSection.people,
  AppFilterSection.place,
};

/// القسم الرئيسي في [ScopeCatalog] لكل قسم من أقسام الفلتر.
String? reportScopeOfModule(String module) => switch (module) {
  'الالتزامات الشخصية' => ScopeCatalog.personal,
  'الالتزامات المشتركة' => ScopeCatalog.shared,
  'الأفراد والجهات' => ScopeCatalog.people,
  'العقارات' => ScopeCatalog.realEstate,
  'الأنشطة التجارية' => ScopeCatalog.activities,
  'المركبات ووسائل النقل' => ScopeCatalog.equipment,
  _ => null,
};

/// اسم القسم كما يظهر في التقرير (المركبات بدل الاسم القديم المخزّن).
String reportScopeLabel(String scope) =>
    scope == ScopeCatalog.equipment ? 'المركبات ووسائل النقل' : scope;

/// معايير تقرير/أرشيف: القسم وقيم فلتره وكلمة البحث.
class ReportFilter {
  ReportFilter({required this.module, required this.values, this.query = ''});

  final String module;
  final AppFilterValues values;
  final String query;

  Map<String, dynamic> toMap() => {
    'module': module,
    'values': values.toMap(),
    'query': query,
  };

  factory ReportFilter.fromMap(Map<String, dynamic> map) => ReportFilter(
    module: (map['module'] ?? 'الكل').toString(),
    values: map['values'] is Map
        ? AppFilterValues.fromMap(
            Map<String, dynamic>.from(map['values'] as Map),
          )
        : AppFilterValues(),
    query: (map['query'] ?? '').toString(),
  );

  /// المعايير المختارة كأزواج (العنوان، القيمة) — تظهر في رأس التقرير.
  List<(String, String)> describe() {
    final v = values;
    final out = <(String, String)>[('القسم', module)];
    if (v.mainCategory != 'الكل' && v.mainCategory != module) {
      out.add(('الفئة', v.mainCategory));
    }
    if (v.subCategory != null) out.add(('التصنيف', v.subCategory!));
    if (v.dateFrom != null || v.dateTo != null) {
      final range =
          '${v.dateFrom == null ? '—' : reportDate(v.dateFrom!)}'
          ' ← ${v.dateTo == null ? '—' : reportDate(v.dateTo!)}';
      out.add((
        'الفترة',
        v.datePeriod == null ? range : '${v.datePeriod} ($range)',
      ));
    }
    if (v.status != 'كل الحالات') out.add(('الحالة', v.status));
    if (v.amountShortcut != null) out.add(('المبلغ', v.amountShortcut!));
    if (v.amountFrom != null || v.amountTo != null) {
      out.add((
        'نطاق المبلغ',
        '${v.amountFrom?.toStringAsFixed(0) ?? '—'} ← '
            '${v.amountTo?.toStringAsFixed(0) ?? '—'}',
      ));
    }
    if (v.paymentMethod != null) out.add(('طريقة الدفع', v.paymentMethod!));
    if (v.personName.trim().isNotEmpty) {
      out.add(('الشخص / الجهة', v.personName.trim()));
    }
    if (v.placeName.trim().isNotEmpty) out.add(('المكان', v.placeName.trim()));
    if (query.trim().isNotEmpty) out.add(('كلمة البحث', query.trim()));
    return out;
  }
}

// ============================ تطبيق المعايير ============================

const _closedWords = [
  'مكتمل',
  'منته',
  'مغلق',
  'مسدد',
  'منجز',
  'مؤرشف',
  'تسوية',
  'مجمّد',
  'محذوف',
];

bool _isClosed(String status) =>
    _closedWords.any((word) => status.contains(word));

bool _isCancelled(String status) => status.contains('ملغ');

/// عدد الأيام من اليوم حتى تاريخ السجل (سالب = فات).
int? _daysUntil(SummaryItem item) {
  // يوم المتابعة نفسه المستعمل في الملخص (المصروف المتكرر بموعده القادم،
  // وتاريخ إضافة الشخص لا يُحسب).
  final date = item.followDay;
  if (date == null) return null;
  final today = DateUtils.dateOnly(DateTime.now());
  return DateUtils.dateOnly(date).difference(today).inDays;
}

/// حالة العرض الموحّدة لسجل: مكتمل، ملغى، متأخر، مستحق، قريب، نشط.
ReportItemState reportStateOf(SummaryItem item) {
  final status = item.status.trim();
  if (status.contains('مؤرشف')) return ReportItemState.archived;
  if (_isCancelled(status)) return ReportItemState.cancelled;
  if (_isClosed(status)) return ReportItemState.done;
  final days = _daysUntil(item);
  if (days != null && item.scope != ScopeCatalog.people) {
    if (days < 0) {
      return item.canBeOverdue
          ? ReportItemState.overdue
          : ReportItemState.active;
    }
    if (days == 0) return ReportItemState.dueToday;
    if (days <= 7) return ReportItemState.dueSoon;
  }
  return ReportItemState.active;
}

enum ReportItemState {
  active,
  dueSoon,
  dueToday,
  overdue,
  done,
  cancelled,
  archived,
}

bool _matchesCategory(SummaryItem item, String category) {
  final wanted = switch (category) {
    'أفراد' => 'الأفراد',
    'جهات' => 'الجهات والشركات',
    _ => category,
  };
  if (item.section == wanted || item.type == wanted) return true;
  if (item.subtitle == wanted) return true;
  // «اللقاءات» نوع قديم دُمج في «مشاركات مشتركة».
  return wanted == 'مشاركات مشتركة' && item.type == 'اللقاءات';
}

bool _matchesStatus(SummaryItem item, String option) {
  final status = item.status.trim();
  final days = _daysUntil(item);
  final closed = _isClosed(status) || _isCancelled(status);
  switch (option) {
    case '':
    case 'كل الحالات':
    case 'الأحدث أولاً':
      return true;
    case 'نشط':
      return !closed;
    case 'قريبة الاستحقاق':
    case 'المستحق بعد 7 أيام':
      return !closed && days != null && days >= 0 && days <= 7;
    case 'تنتهي قريبًا':
      return !closed && days != null && days >= 0 && days <= 30;
    case 'مستحقة':
      return !closed && days == 0;
    case 'متأخرة':
    case 'متأخر':
      return !closed && item.canBeOverdue && days != null && days < 0;
    case 'مكتملة':
    case 'مكتمل':
      return _isClosed(status);
    case 'منتهية':
      return status.contains('منته') || (days != null && days < 0);
    case 'ملغاة':
      return _isCancelled(status);
    case 'مؤرشف':
      return status.contains('مؤرشف');
  }
  return status == option || status.contains(option);
}

/// يطبّق معايير [filter] على السجلات ويرتّبها كما طلب الفلتر.
List<SummaryItem> applyReportFilter(
  List<SummaryItem> items,
  ReportFilter filter,
) {
  final v = filter.values;
  final scope = reportScopeOfModule(filter.module);
  final category = v.mainCategory;
  final out = items.where((item) {
    if (scope == null) {
      // «الكل»: أقسام الفلتر نفسها (التفويضات ليست منها).
      if (item.scope == ScopeCatalog.delegations) return false;
    } else if (item.scope != scope) {
      return false;
    }
    if (category != 'الكل' &&
        category != filter.module &&
        !_matchesCategory(item, category)) {
      return false;
    }
    final sub = v.subCategory;
    if (sub != null && !_matchesCategory(item, sub)) return false;
    if (!v.matchesDate(item.date ?? item.createdAt)) return false;
    if (!_matchesStatus(item, v.status)) return false;
    if (v.amountFrom != null && item.amount < v.amountFrom!) return false;
    if (v.amountTo != null && item.amount > v.amountTo!) return false;
    final payment = v.paymentMethod;
    if (payment != null) {
      if (payment == 'أخرى') {
        if (item.payment.trim().isEmpty ||
            kAppFilterPaymentMethods.any(
              (known) => known != 'أخرى' && item.payment.contains(known),
            )) {
          return false;
        }
      } else if (!item.payment.contains(payment)) {
        return false;
      }
    }
    if (v.personName.trim().isNotEmpty &&
        !matchesSearchQuery(
          query: v.personName,
          fields: [item.person, item.title, item.searchText],
        )) {
      return false;
    }
    if (v.placeName.trim().isNotEmpty &&
        !matchesSearchQuery(
          query: v.placeName,
          fields: [item.subtitle, item.searchText],
        )) {
      return false;
    }
    if (filter.query.trim().isNotEmpty &&
        !matchesSearchQuery(
          query: filter.query,
          fields: [
            item.title,
            item.subtitle,
            item.person,
            item.type,
            item.section,
            item.status,
            item.payment,
            item.searchText,
          ],
        )) {
      return false;
    }
    return true;
  }).toList();

  int byDate(SummaryItem a, SummaryItem b) {
    final da = a.date ?? a.createdAt;
    final db = b.date ?? b.createdAt;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  if (v.amountShortcut == 'أعلى مبلغًا') {
    out.sort((a, b) => b.amount.compareTo(a.amount));
  } else if (v.amountShortcut == 'أقل مبلغًا') {
    out.sort((a, b) => a.amount.compareTo(b.amount));
  } else if (v.status == 'الأحدث أولاً') {
    out.sort((a, b) => byDate(b, a));
  } else {
    out.sort(byDate);
  }
  return out;
}

// ============================ مستند التقرير ============================

String reportDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String reportAmount(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return AppSettings.maskAmount('${negative ? '-' : ''}$buffer');
}

/// كل ما يلزم لبناء مستند تقرير أو أرشيف.
class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.archive,
    required this.reference,
    required this.createdAt,
    required this.createdBy,
    required this.criteria,
    required this.items,
    this.archivedAt,
    this.archiveReason = '',
  });

  final String title;
  final bool archive;

  /// رقم مرجعي قصير يظهر في الرأس (يُشتق من معرّف التقرير).
  final String reference;
  final DateTime createdAt;
  final String createdBy;
  final List<(String, String)> criteria;
  final List<SummaryItem> items;
  final DateTime? archivedAt;
  final String archiveReason;

  String get kind => archive ? 'أرشيف' : 'تقرير';

  /// اسم ملف صالح لكل الأنظمة.
  String get fileName {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), '-')
        .trim();
    return '${clean.isEmpty ? kind : clean}.pdf';
  }
}

// الخطوط والشعار تُضمَّن في الصفحة نفسها (base64) فيُبنى الملف بلا إنترنت
// وبخط التطبيق نفسه على كل جهاز.
String? _fontRegular;
String? _fontSemiBold;
String? _fontBold;
String? _fontBlack;
String? _logo;

Future<String?> _assetBase64(String path) async {
  try {
    final data = await rootBundle.load(path);
    return base64Encode(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

Future<void> _loadReportAssets() async {
  _fontRegular ??= await _assetBase64('assets/fonts/CairoRegular.ttf');
  _fontSemiBold ??= await _assetBase64('assets/fonts/CairoSemiBold.ttf');
  _fontBold ??= await _assetBase64('assets/fonts/CairoBold.ttf');
  _fontBlack ??= await _assetBase64('assets/fonts/CairoExtraBold.ttf');
  _logo ??= await _assetBase64('assets/images/logo_mark.png');
}

String _esc(String input) => const HtmlEscape(HtmlEscapeMode.element)
    .convert(input)
    .replaceAll('"', '&quot;');

String _t(String text) => _esc(AppTr.tr(text));

String _fontFace(String? data, int weight) => data == null
    ? ''
    : "@font-face{font-family:'ReportCairo';font-weight:$weight;"
          "src:url(data:font/ttf;base64,$data) format('truetype');}";

(String, String) _stateBadge(ReportItemState state) => switch (state) {
  ReportItemState.done => ('done', 'مكتمل'),
  ReportItemState.cancelled => ('cancel', 'ملغى'),
  ReportItemState.overdue => ('late', 'متأخر'),
  ReportItemState.dueToday => ('today', 'مستحق اليوم'),
  ReportItemState.dueSoon => ('soon', 'قريب الاستحقاق'),
  ReportItemState.active => ('active', 'نشط'),
  ReportItemState.archived => ('archived', 'مؤرشف'),
};

/// صفحة HTML كاملة للتقرير — تصميم A4 جاهز للطباعة وللتحويل إلى PDF.
Future<String> buildReportHtml(ReportDocument doc) async {
  await _loadReportAssets();
  final items = doc.items;
  final currency = AppTr.tr(AppSettings.currencySuffix);
  final total = items.fold<int>(0, (sum, item) => sum + item.amount);
  final states = items.map(reportStateOf).toList(growable: false);
  final overdue = states.where((s) => s == ReportItemState.overdue).length;
  final soon = states
      .where(
        (s) => s == ReportItemState.dueSoon || s == ReportItemState.dueToday,
      )
      .length;
  final done = states.where((s) => s == ReportItemState.done).length;
  final showScope = items.map((item) => item.scope).toSet().length > 1;

  // التوزيع حسب التصنيف (أو حسب القسم في «الكل»).
  final groups = <String, (int, int)>{};
  for (final item in items) {
    final key = showScope
        ? reportScopeLabel(item.scope)
        : (item.type.trim().isEmpty ? 'غير مصنّف' : item.type.trim());
    final current = groups[key] ?? (0, 0);
    groups[key] = (current.$1 + 1, current.$2 + item.amount);
  }
  // الترتيب نفسه الذي في شاشات الأقسام (المصروفات الشخصية أولًا...)،
  // وما لا ترتيب معروفًا له يأتي بعدها حسب العدد.
  final scopeOfItems = items.isEmpty ? '' : items.first.scope;
  int rankOf(String key) => showScope
      ? _rankIn(kReportModules, key)
      : _typeRank(scopeOfItems, key);
  final groupRows = groups.entries.toList()
    ..sort((a, b) {
      final byRank = rankOf(a.key).compareTo(rankOf(b.key));
      return byRank != 0 ? byRank : b.value.$1.compareTo(a.value.$1);
    });
  // النسبة = حصة الصف من إجمالي المبالغ؛ وإن لم تكن مبالغ فمن عدد العناصر.
  final shareByAmount = total > 0;

  final dir = AppTr.isEnglish ? 'ltr' : 'rtl';
  final html = StringBuffer()
    ..write('<!DOCTYPE html><html lang="${AppTr.code}" ')
    ..write('dir="$dir"><head><meta charset="utf-8">')
    ..write('<title>${_esc(doc.title)}</title><style>')
    ..write(_fontFace(_fontRegular, 400))
    ..write(_fontFace(_fontSemiBold, 600))
    ..write(_fontFace(_fontBold, 700))
    ..write(_fontFace(_fontBlack, 800))
    ..write(kReportCss)
    ..write('</style></head><body>');

  if (doc.archive) {
    html.write('<div class="watermark">${_t('أرشيف')}</div>');
  }

  // شعار المستخدم في منتصف أعلى الصفحة الأولى.
  final userLogo = await UserLogoStore.load();
  if (userLogo != null && userLogo.isNotEmpty) {
    final mime = userLogo.length > 2 &&
            userLogo[0] == 0xFF &&
            userLogo[1] == 0xD8
        ? 'image/jpeg'
        : 'image/png';
    html.write(
      '<div style="text-align:center;margin:0 0 10px;">'
      '<img src="data:$mime;base64,${base64Encode(userLogo)}" '
      'style="max-height:70px;max-width:200px;object-fit:contain;"></div>',
    );
  }

  // ---------- الرأس ----------
  html
    ..write('<header class="head"><div class="brand">')
    ..write(
      _logo == null
          ? ''
          : '<img class="logo" src="data:image/png;base64,$_logo" alt="">',
    )
    ..write('<div class="brand-text"><div class="app">Fundly</div>')
    ..write('<div class="app-sub">${_t('إدارة الالتزامات والأصول')}</div>')
    ..write('</div></div><div class="doc-id">')
    ..write(
      '<span class="kind ${doc.archive ? 'kind-archive' : ''}">'
      '${_t(doc.kind)}</span>',
    )
    ..write('<div class="ref">${_t('رقم المرجع')}: ')
    ..write('<b>${_esc(doc.reference)}</b></div>')
    ..write(
      '<div class="ref">${_t('تاريخ الإصدار')}: '
      '<b>${reportDate(doc.createdAt)}</b></div>',
    )
    ..write('</div></header>')
    ..write('<div class="title-block"><h1>${_esc(doc.title)}</h1>')
    ..write(
      '<div class="by">${_t('أُعدّ بواسطة')}: '
      '<b>${_esc(doc.createdBy)}</b></div></div>',
    );

  // ---------- المعايير ----------
  html.write('<section class="criteria"><div class="sec-title">');
  html.write(_t(doc.archive ? 'معايير الأرشيف' : 'معايير التقرير'));
  html.write('</div><div class="chips">');
  for (final (label, value) in doc.criteria) {
    html.write(
      '<span class="chip"><i>${_t(label)}</i>${_t(value)}</span>',
    );
  }
  html.write('</div></section>');

  if (doc.archive &&
      (doc.archivedAt != null || doc.archiveReason.trim().isNotEmpty)) {
    html
      ..write('<section class="archive-box"><div class="ab-row">')
      ..write('<span>${_t('تاريخ الأرشفة')}</span><b>')
      ..write(doc.archivedAt == null ? '—' : reportDate(doc.archivedAt!))
      ..write('</b></div><div class="ab-row"><span>${_t('سبب الأرشفة')}')
      ..write('</span><b>')
      ..write(
        doc.archiveReason.trim().isEmpty
            ? _t('غير محدد')
            : _esc(doc.archiveReason),
      )
      ..write('</b></div></section>');
  }

  // ---------- المؤشرات ----------
  html
    ..write('<section class="kpis">')
    ..write(_kpi('عدد العناصر', '${items.length}', 'teal'))
    ..write(
      _kpi(
        'إجمالي المبالغ',
        '${reportAmount(total)} <small>$currency</small>',
        'gold',
      ),
    )
    ..write(_kpi('متأخرة', '$overdue', 'red'))
    ..write(_kpi('قريبة / مستحقة', '$soon', 'amber'))
    ..write(_kpi('مكتملة', '$done', 'green'))
    ..write('</section>');

  if (items.isEmpty) {
    html.write(
      '<div class="empty">${_t('لا توجد عناصر تطابق المعايير المختارة.')}'
      '</div>',
    );
  } else {
    // ---------- التوزيع ----------
    html
      ..write('<section class="block"><div class="sec-title">')
      ..write(_t(showScope ? 'التوزيع حسب القسم' : 'التوزيع حسب التصنيف'))
      ..write('</div><div class="hint">')
      ..write(
        shareByAmount
            ? '${_t('النسبة = حصة كل صف من إجمالي المبالغ')} '
                  '(${reportAmount(total)} $currency)'
            : '${_t('النسبة = حصة كل صف من عدد العناصر')} (${items.length})',
      )
      ..write('</div><table class="dist"><thead><tr>')
      ..write('<th>${_t(showScope ? 'القسم' : 'التصنيف')}</th>')
      ..write('<th class="n">${_t('العدد')}</th>')
      ..write('<th class="n">${_t('الإجمالي')}</th>')
      ..write(
        '<th class="bar-col">${_t(shareByAmount ? 'النسبة من إجمالي المبالغ' : 'النسبة من عدد العناصر')}'
        '</th></tr></thead><tbody>',
      );
    for (final row in groupRows) {
      final part = shareByAmount ? row.value.$2 : row.value.$1;
      final whole = shareByAmount ? total : items.length;
      final percent = whole == 0 ? 0 : (part * 100 / whole).round();
      html
        ..write('<tr><td>${_t(row.key)}</td>')
        ..write('<td class="n">${row.value.$1}</td>')
        ..write('<td class="n">${reportAmount(row.value.$2)}</td>')
        ..write('<td class="bar-col"><div class="bar"><span ')
        ..write('style="width:$percent%"></span></div><em>$percent%</em>')
        ..write('</td></tr>');
    }
    html.write('</tbody></table></section>');

    // ---------- التفاصيل ----------
    html
      ..write('<section class="block"><div class="sec-title">')
      ..write('${_t('التفاصيل')} <small>(${items.length})</small></div>')
      ..write('<table class="details"><thead><tr><th class="idx">#</th>')
      ..write('<th>${_t('العنوان')}</th>')
      ..write('<th>${_t(showScope ? 'القسم / التصنيف' : 'التصنيف')}</th>')
      ..write('<th>${_t('الشخص / الجهة')}</th>')
      ..write('<th class="d">${_t('التاريخ')}</th>')
      ..write('<th class="s">${_t('الحالة')}</th>')
      ..write('<th class="n">${_t('المبلغ')}</th></tr></thead><tbody>');
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final (badgeClass, badgeLabel) = _stateBadge(states[i]);
      final rawStatus = item.status.trim();
      final category = [
        if (showScope) reportScopeLabel(item.scope),
        if (item.type.trim().isNotEmpty && item.type.trim() != item.scope)
          item.type.trim(),
      ].map(AppTr.tr).map(_esc).join(' › ');
      final date = item.date ?? item.createdAt;
      html
        ..write('<tr><td class="idx">${i + 1}</td>')
        ..write('<td><b>${_esc(item.title.isEmpty ? '—' : item.title)}</b>')
        ..write(
          item.subtitle.trim().isEmpty || item.subtitle == item.type
              ? ''
              : '<div class="sub">${_esc(AppTr.tr(item.subtitle))}</div>',
        )
        ..write('</td><td>${category.isEmpty ? '—' : category}</td>')
        ..write(
          '<td>${item.person.trim().isEmpty ? '—' : _esc(item.person)}</td>',
        )
        ..write('<td class="d">${date == null ? '—' : reportDate(date)}</td>')
        ..write('<td class="s"><span class="badge $badgeClass">')
        ..write(_t(badgeLabel))
        ..write('</span>')
        ..write(
          rawStatus.isEmpty || rawStatus == badgeLabel
              ? ''
              : '<div class="sub">${_t(rawStatus)}</div>',
        )
        ..write('</td><td class="n">')
        ..write(item.amount == 0 ? '—' : reportAmount(item.amount))
        ..write('</td></tr>');
    }
    html
      ..write('</tbody><tfoot><tr><td colspan="6">${_t('الإجمالي')}</td>')
      ..write('<td class="n">${reportAmount(total)} $currency</td></tr>')
      ..write('</tfoot></table></section>');
  }

  // ---------- التوقيعات والتذييل ----------
  html
    ..write('<section class="signs"><div class="sign"><span>')
    ..write(_t('توقيع المُعِدّ'))
    ..write('</span><i></i><b>${_esc(doc.createdBy)}</b></div>')
    ..write('<div class="sign"><span>${_t('الاعتماد')}</span><i></i>')
    ..write('<b>&nbsp;</b></div></section>')
    ..write('<footer class="foot"><span>${_t('صدر من تطبيق')} Fundly</span>')
    ..write('<span>${reportDate(DateTime.now())} · ')
    ..write('${_esc(doc.reference)}</span></footer>')
    ..write('</body></html>');
  return html.toString();
}

int _rankIn(List<String> order, String key) {
  final index = order.indexOf(key);
  return index < 0 ? 1000 : index;
}

/// ترتيب النوع كما في شاشة قسمه ([ScopeCatalog.typesByScope]).
int _typeRank(String scope, String type) {
  final table = ScopeCatalog.typesByScope[scope];
  if (table == null) return 1000;
  var index = 0;
  for (final types in table.values) {
    for (final candidate in types) {
      if (candidate == type) return index;
      index++;
    }
  }
  return 1000;
}

String _kpi(String label, String value, String tone) =>
    '<div class="kpi $tone"><span>${_t(label)}</span><b>$value</b></div>';

/// هوامش الصفحة: تُطبَّق من إعداد الطباعة نفسه لأن متصفّح الجوال لا يلتزم
/// دائمًا بهوامش CSS.
PdfPageFormat get kReportPageFormat => PdfPageFormat.a4.copyWith(
  marginTop: 12 * PdfPageFormat.mm,
  marginBottom: 12 * PdfPageFormat.mm,
  marginLeft: 11 * PdfPageFormat.mm,
  marginRight: 11 * PdfPageFormat.mm,
);

/// ملف PDF للتقرير (للمعاينة والمشاركة والطباعة).
Future<Uint8List> buildReportPdf(
  ReportDocument doc, [
  PdfPageFormat? format,
]) async {
  final html = await buildReportHtml(doc);
  final base = format ?? kReportPageFormat;
  return Printing.convertHtml(
    format: base.copyWith(
      marginTop: 12 * PdfPageFormat.mm,
      marginBottom: 12 * PdfPageFormat.mm,
      marginLeft: 11 * PdfPageFormat.mm,
      marginRight: 11 * PdfPageFormat.mm,
    ),
    html: html,
  );
}

/// نافذة الطباعة في النظام (طابعة، أو حفظ PDF).
Future<void> printReportDocument(ReportDocument doc) => Printing.layoutPdf(
  name: doc.fileName,
  format: kReportPageFormat,
  onLayout: (format) => buildReportPdf(doc, format),
);

/// مشاركة ملف PDF (واتساب، بريد، حفظ في الملفات...).
Future<void> shareReportDocument(ReportDocument doc) async {
  final bytes = await buildReportPdf(doc);
  await Printing.sharePdf(bytes: bytes, filename: doc.fileName);
}

/// تنسيق المستند — A4، خط التطبيق، ألوان الهوية.
const String kReportCss = r'''
@page{size:A4;}
*{box-sizing:border-box;margin:0;padding:0;}
html,body{background:#fff;}
body{font-family:'ReportCairo','Cairo',sans-serif;color:#1d2b29;font-size:11px;
line-height:1.55;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
b{font-weight:700;}
.watermark{position:fixed;top:42%;left:0;right:0;text-align:center;
font-size:120px;font-weight:800;color:rgba(166,105,26,.07);
transform:rotate(-24deg);z-index:0;pointer-events:none;}
.head{display:flex;justify-content:space-between;align-items:center;
padding:14px 18px;border-radius:14px;
background:linear-gradient(120deg,#022E2A 0%,#0A5A50 55%,#0E7161 100%);color:#fff;}
.brand{display:flex;align-items:center;gap:10px;}
.logo{width:34px;height:46px;object-fit:contain;background:#fff;border-radius:9px;
padding:5px 6px;}
.app{font-size:19px;font-weight:800;letter-spacing:.5px;line-height:1.1;}
.app-sub{font-size:10px;opacity:.8;font-weight:600;}
.doc-id{text-align:end;}
.kind{display:inline-block;background:#F2A93F;color:#3b2606;font-weight:800;
font-size:11px;padding:2px 14px;border-radius:999px;margin-bottom:4px;}
.kind-archive{background:#fff;color:#A6691A;}
.ref{font-size:10px;opacity:.92;}
.ref b{font-weight:700;}
.title-block{padding:14px 4px 6px;border-bottom:2px solid #E9F4F1;margin-bottom:12px;
display:flex;justify-content:space-between;align-items:flex-end;gap:12px;}
h1{font-size:21px;font-weight:800;color:#022E2A;line-height:1.3;}
.by{font-size:10.5px;color:#5C6B68;white-space:nowrap;}
.by b{color:#0A5A50;}
.sec-title{font-size:12.5px;font-weight:800;color:#022E2A;margin:0 0 7px;
padding-inline-start:9px;border-inline-start:4px solid #0E7161;line-height:1.3;}
.sec-title small{color:#8C9A97;font-weight:600;font-size:10.5px;}
.criteria{margin-bottom:12px;}
.chips{display:flex;flex-wrap:wrap;gap:6px;}
.chip{background:#F4F8F7;border:1px solid #E1EBE8;border-radius:999px;
padding:3px 11px;font-weight:700;color:#0A5A50;font-size:10.5px;}
.chip i{font-style:normal;color:#8C9A97;font-weight:600;margin-inline-end:5px;}
.chip i:after{content:':';}
.archive-box{display:flex;gap:10px;margin-bottom:12px;background:#FDEFDC;
border:1px solid #F5D9AE;border-radius:12px;padding:9px 14px;}
.ab-row{flex:1;}
.ab-row span{display:block;font-size:9.5px;color:#A6691A;font-weight:700;}
.ab-row b{font-size:11.5px;color:#3b2606;}
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-bottom:14px;}
.kpi{border-radius:12px;padding:9px 11px;border:1px solid #E6EEEC;background:#FAFCFB;
position:relative;overflow:hidden;}
.kpi:before{content:'';position:absolute;inset-inline-start:0;top:0;bottom:0;width:4px;}
.kpi span{display:block;font-size:9.5px;color:#5C6B68;font-weight:700;}
.kpi b{display:block;font-size:17px;font-weight:800;color:#022E2A;line-height:1.35;}
.kpi b small{font-size:9.5px;color:#8C9A97;font-weight:600;}
.kpi.teal:before{background:#0E7161;}.kpi.gold:before{background:#CE8422;}
.kpi.red:before{background:#C4392E;}.kpi.amber:before{background:#F2A93F;}
.kpi.green:before{background:#34A894;}
.kpi.red b{color:#C4392E;}
.block{margin-bottom:14px;}
table{width:100%;border-collapse:separate;border-spacing:0;}
thead{display:table-header-group;}
tfoot{display:table-row-group;}
tr{page-break-inside:avoid;break-inside:avoid;}
th{background:#0A5A50;color:#fff;font-weight:700;font-size:10px;text-align:start;
padding:7px 8px;}
th:first-child{border-start-start-radius:9px;}
th:last-child{border-start-end-radius:9px;}
td{padding:6px 8px;border-bottom:1px solid #EEF3F2;vertical-align:top;font-size:10.5px;}
tbody tr:nth-child(even) td{background:#F7FAF9;}
td .sub{font-size:9px;color:#8C9A97;font-weight:600;margin-top:1px;}
.n{text-align:end;white-space:nowrap;font-variant-numeric:tabular-nums;}
.d{white-space:nowrap;text-align:center;}
.s{text-align:center;}
.idx{width:26px;text-align:center;color:#8C9A97;font-weight:700;}
.dist td{font-weight:600;}
.hint{font-size:9.5px;color:#8C9A97;font-weight:600;margin:-3px 0 6px;}
.dist th.bar-col{white-space:nowrap;}
.bar-col{width:38%;}
.bar{display:inline-block;width:calc(100% - 38px);height:8px;background:#EAF1EF;
border-radius:99px;overflow:hidden;vertical-align:middle;}
.bar span{display:block;height:100%;background:linear-gradient(90deg,#178F7B,#0A5A50);
border-radius:99px;}
.bar-col em{font-style:normal;font-size:9.5px;color:#5C6B68;font-weight:700;
display:inline-block;width:34px;text-align:end;}
tfoot td{background:#E9F4F1;font-weight:800;color:#022E2A;font-size:11px;
border-bottom:none;}
tfoot td:first-child{border-end-start-radius:9px;}
tfoot td:last-child{border-end-end-radius:9px;}
.badge{display:inline-block;padding:1px 9px;border-radius:999px;font-size:9.5px;
font-weight:700;white-space:nowrap;}
.badge.active{background:#E3F3EF;color:#0E7161;}
.badge.soon{background:#FFF3DF;color:#A6691A;}
.badge.today{background:#FDE9D2;color:#A6691A;}
.badge.late{background:#FBE5E2;color:#C4392E;}
.badge.done{background:#E2F5EC;color:#1C7A55;}
.badge.cancel{background:#EEF1F0;color:#5C6B68;}
.badge.archived{background:#FDEFDC;color:#A6691A;}
.empty{text-align:center;padding:30px;border:1px dashed #D5DEDB;border-radius:12px;
color:#8C9A97;font-weight:700;margin-bottom:14px;}
.signs{display:flex;gap:40px;margin-top:26px;page-break-inside:avoid;}
.sign{flex:1;}
.sign span{font-size:10px;color:#5C6B68;font-weight:700;}
.sign i{display:block;border-bottom:1.5px dashed #B9C7C4;height:34px;margin:2px 0 4px;}
.sign b{font-size:10.5px;color:#022E2A;}
.foot{display:flex;justify-content:space-between;margin-top:16px;padding-top:8px;
border-top:1px solid #E6EEEC;font-size:9px;color:#8C9A97;font-weight:600;}
''';
