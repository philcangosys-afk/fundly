import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';

import 'app_design.dart';

/// قالب "مركز المتابعة" الموحَّد لكل الوحدات.
///
/// كان لكل شاشة مركز متابعة بشكل مختلف: الالتزامات الشخصية تفتح شبكة
/// مجموعات، والمشتركة قائمة عمود واحد، وإدارة الأفراد والعقارات تفتحان
/// نافذة **فلترة** لا علاقة لها بالمتابعة أصلًا. المضمون يختلف بطبيعته من
/// وحدة لأخرى، أما القالب والفائدة فواحدة: مجموعات متابعة، كل مجموعة
/// عناصر فرعية بعدّاد، والضغط على عنصر يعرض ما تحته ثم يفتح تفاصيله.
///
/// هذا الملف هو القالب الوحيد؛ كل شاشة تمرّر بياناتها ومسمياتها فقط.

/// عنصر واحد داخل بند فرعي (التزام، شخص، عقار...).
class FollowUpEntry {
  const FollowUpEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.trailingText,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// نص يسار الصف (مبلغ، تاريخ، عدد...) — يُحذف الصف إن كان فارغًا.
  final String? trailingText;

  /// يُستدعى بعد إغلاق النوافذ، ليفتح تفاصيل العنصر.
  ///
  /// `null` = للاطلاع فقط: يُعرض الصف بلا سهم ولا ضغط، ولا تُغلق النوافذ.
  final VoidCallback? onTap;
}

/// بند فرعي داخل مجموعة (مثال: "متأخرة" داخل "الاستحقاقات").
class FollowUpMetric {
  const FollowUpMetric({
    required this.label,
    required this.icon,
    required this.entries,
    this.isHeading = false,
    this.indented = false,
  });

  /// عنوان رئيسي داخل المجموعة («مالية»): يُكتب بالأسود بلا عدّاد ولا
  /// ضغط، وتحته بنوده الفرعية. كان كل بند يُكتب «مالية · شيكات» فيتكرر
  /// اسم العنوان في كل سطر.
  final bool isHeading;

  /// بند فرعي يتبع عنوانًا: يُزاح قليلًا ليُقرأ كأنه تحته.
  final bool indented;

  final String label;
  final IconData icon;
  final List<FollowUpEntry> entries;

  int get count => entries.length;
}

/// مجموعة كاملة داخل مركز المتابعة.
class FollowUpGroup {
  const FollowUpGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.metrics,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<FollowUpMetric> metrics;

  int get total => metrics.fold(0, (sum, metric) => sum + metric.count);
}

/// يفتح مركز المتابعة الموحَّد.
Future<void> showFollowUpCenterSheet({
  required BuildContext context,
  required Color accent,
  required List<FollowUpGroup> groups,
  String title = 'مركز المتابعة',
  String subtitle = '',
}) {
  final grandTotal = groups.fold<int>(0, (sum, group) => sum + group.total);
  final maxRows = groups.fold<int>(
    0,
    (max, group) => group.metrics.length > max ? group.metrics.length : max,
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAF9),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.rCard),
            ),
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, color: accent),
                    const SizedBox(width: 9),
                    // العنوان ثم العدد بجانبه مباشرة، وتحتهما اسم القسم.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF022E2A),
                                  ),
                                ),
                              ),
                              if (grandTotal > 0) ...[
                                const SizedBox(width: AppTheme.sSm),
                                _CountBadge(count: grandTotal, color: accent),
                              ],
                            ],
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5C6B68),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.sSm),
                    // زر الخروج: كان الإغلاق بالسحب لأسفل فقط.
                    AppIconButton(
                      key: const ValueKey('followup-sheet-close'),
                      tooltip: AppTr.tr('إغلاق'),
                      icon: Icons.close_rounded,
                      background: AppTheme.field,
                      color: AppTheme.chevron,
                      onTap: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: grandTotal == 0
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'لا توجد عناصر تحتاج إلى متابعة حالياً',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5C6B68),
                            ),
                          ),
                        ),
                      )
                    : GridView.builder(
                        key: const ValueKey('followup-center-groups'),
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                        itemCount: groups.length,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              mainAxisExtent: appFollowUpCardExtent(
                                sheetContext,
                                maxRows,
                              ),
                            ),
                        itemBuilder: (context, index) => _FollowUpGroupCard(
                          group: groups[index],
                          rootContext: sheetContext,
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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD5DEDB),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// بطاقة مجموعة واحدة: عنوان وعدّاد، ثم بنودها الفرعية.
class _FollowUpGroupCard extends StatelessWidget {
  const _FollowUpGroupCard({required this.group, required this.rootContext});

  final FollowUpGroup group;

  /// سياق النافذة الأم، ليُغلق مركز المتابعة كله قبل فتح التفاصيل.
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    // بنود كل مجموعة تظهر دائمًا ولو كانت أصفارًا: غيابها يجعل المستخدم
    // يظنّ أن المجموعة بلا بنود أصلًا.
    final hasItems = group.metrics.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(13, 12, 13, hasItems ? 4 : 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(group.icon, color: group.color, size: 18),
                ),
                const SizedBox(width: 9),
                // الاسم المركّب على سطرين بدل قصّه («مالية (عا…»).
                Expanded(
                  child: Text(
                    twoLineLabel(group.title),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${group.total}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: group.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasItems)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
              child: Column(
                children: [
                  for (final metric in group.metrics)
                    _MetricRow(
                      metric: metric,
                      group: group,
                      rootContext: rootContext,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.metric,
    required this.group,
    required this.rootContext,
  });

  final FollowUpMetric metric;
  final FollowUpGroup group;
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    if (metric.isHeading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Row(
          children: [
            Icon(metric.icon, size: 16, color: const Color(0xFF022E2A)),
            const SizedBox(width: 8),
            Expanded(
              // العنوان كاملًا («المتابعة والتخطيط») بلا قصّ.
              child: Text(
                metric.label,
                maxLines: 2,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final enabled = metric.count > 0;
    return InkWell(
      onTap: enabled
          ? () => _openMetricSheet(context, metric, group, rootContext)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: 5,
          bottom: 5,
          start: metric.indented ? 14 : 0,
        ),
        child: Row(
          children: [
            Icon(
              metric.icon,
              size: 16,
              color: enabled
                  ? const Color(0xFF46534F)
                  : const Color(0xFFD5DEDB),
            ),
            const SizedBox(width: 8),
            // البند كاملًا: يصغُر قليلًا ليدخل بدل «بانتظار الموا…».
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                metric.label,
                maxLines: 3,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? const Color(0xFF2C3B38)
                      : const Color(0xFF8C9A97),
                ),
              ),
              ),
            ),
            Text(
              '${metric.count}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: enabled
                    ? const Color(0xFF022E2A)
                    : const Color(0xFFD5DEDB),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 4),
              const AppChevron(size: 18, color: Color(0xFF8C9A97)),
            ],
          ],
        ),
      ),
    );
  }
}

/// نافذة البند الفرعي: قائمة عناصره، والضغط على عنصر يفتح تفاصيله.
void _openMetricSheet(
  BuildContext context,
  FollowUpMetric metric,
  FollowUpGroup group,
  BuildContext rootContext,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.62,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAF9),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.rCard),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(metric.icon, size: 18, color: group.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        metric.label,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF022E2A),
                        ),
                      ),
                    ),
                    _CountBadge(count: metric.count, color: group.color),
                    const SizedBox(width: AppTheme.sSm),
                    AppIconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      icon: Icons.close_rounded,
                      background: AppTheme.field,
                      color: AppTheme.chevron,
                      onTap: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  shrinkWrap: true,
                  itemCount: metric.entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = metric.entries[index];
                    final open = entry.onTap;
                    return _EntryTile(
                      entry: entry,
                      onTap: open == null
                          ? null
                          : () {
                              // يُغلق البند ثم مركز المتابعة، فتظهر
                              // التفاصيل فوق الشاشة الأصلية لا فوق نافذتين
                              // مكدّستين.
                              Navigator.of(sheetContext).pop();
                              Navigator.of(rootContext).pop();
                              open();
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final FollowUpEntry entry;

  /// `null` = صف للاطلاع فقط.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(entry.icon, color: entry.color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 3,
                      style: AppTheme.rowTitle,
                    ),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // سطران لا سطر مقصوص: التاريخ والحالة في آخره.
                      Text(
                        entry.subtitle,
                        maxLines: 4,
                        style: AppTheme.rowSubtitle,
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.trailingText != null &&
                  entry.trailingText!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  entry.trailingText!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
              ],
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const AppChevron(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
