import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import 'shared/app_design.dart';

class DetailHeaderMetric {
  const DetailHeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.caption = '',
  });

  final String label;
  final String value;
  final IconData icon;
  final String caption;
}

class DetailSectionTab {
  const DetailSectionTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class DetailPageHeader extends StatelessWidget {
  const DetailPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.status,
    required this.statusColor,
    required this.metrics,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String status;
  final Color statusColor;
  final List<DetailHeaderMetric> metrics;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // الترتيب معكوس دائمًا لأن الشجرة أدناه تفرض rtl صراحةً مهما كان
    // الاتجاه المحيط؛ ربط العكس بالاتجاه المحيط كان يقلب المؤشرات في أي
    // سياق ليس rtl أصلًا.
    final visualMetrics = List<DetailHeaderMetric>.from(metrics.reversed);

    return Directionality(
      textDirection: AppTr.uiDir,
      child: Container(
        key: const ValueKey('shared-detail-page-header'),
        padding: const EdgeInsets.all(AppTheme.sLg),
        // بطاقة الملخص العلوية بنفس لون وحواف البطاقات الموحّدة: رمادية
        // ناعمة بلا حدود ولا ظل، والمؤشرات داخلها في بطاقة بيضاء.
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        child: Column(
          children: [
            Row(
              textDirection: AppTr.uiDir,
              children: [
                AppIconTile(icon: icon, color: color),
                const SizedBox(width: AppTheme.sMd),
                Expanded(
                  child: Column(
                    // داخل غلاف rtl المفروض أعلاه تعني start "اليمين".
                    // كانت end تعني اليسار، فيبتعد العنوان القصير عن
                    // أيقونته إلى الطرف المقابل.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTheme.cardTitle,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTheme.rowSubtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.sSm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppTheme.sXs),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: AppTheme.sMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.sMd,
                vertical: AppTheme.sMd,
              ),
              decoration: BoxDecoration(
                color: AppTheme.surfaceInner,
                borderRadius: BorderRadius.circular(AppTheme.rInner),
              ),
              child: Row(
                textDirection: TextDirection.ltr,
                children: List.generate(visualMetrics.length, (index) {
                  return Expanded(
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Expanded(
                          child: _DetailMetric(metric: visualMetrics[index]),
                        ),
                        if (index < visualMetrics.length - 1)
                          const SizedBox(
                            height: 54,
                            child: VerticalDivider(
                              width: 14,
                              color: AppTheme.line,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailPageTabs extends StatelessWidget {
  const DetailPageTabs({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.color,
    required this.onSelected,
  });

  /// الارتفاع الموحَّد لشريط تبويبات صفحات التفاصيل.
  ///
  /// يتّسع لسطرين من النص: عناوين مثل "متابعة وتنظيم" و"مواقع وأماكن"
  /// كانت تُقصّ بثلاث نقاط في تبويب عرضه سُدس الشاشة، فيقرأ المستخدم
  /// "متابعة وت…". الآن تنزل الكلمة الثانية سطرًا كاملًا تحت الأولى.
  static const stripHeight = 68.0;

  final List<DetailSectionTab> sections;
  final int selectedIndex;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // شريط تبويبات موحَّد: حاوية رمادية ناعمة بلا حدود، والتبويب المحدَّد
    // يتميّز بلونه وبخط سفلي رفيع بمقاس ولون ثابتين في كل صفحات التفاصيل.
    return Container(
      key: const ValueKey('shared-detail-page-tabs'),
      height: stripHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.sXs),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: List.generate(sections.length, (index) {
          final section = sections[index];
          final selected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              key: ValueKey('shared-detail-page-tab-$index'),
              onTap: () => onSelected(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    section.icon,
                    size: 19,
                    color: selected ? color : AppTheme.muted,
                  ),
                  const SizedBox(height: 4),
                  // سطران بمحاذاة وسط، وكسر الأسطر عند المسافة بين
                  // الكلمتين لا داخل الكلمة الواحدة.
                  Text(
                    section.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: selected ? color : AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: selected ? 26 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selected ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.metric});

  final DetailHeaderMetric metric;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(metric.icon, size: 17, color: AppTheme.chevron),
        const SizedBox(height: 5),
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppTheme.title,
          ),
        ),
        if (metric.caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            metric.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.chevron,
            ),
          ),
        ],
      ],
    );
  }
}
