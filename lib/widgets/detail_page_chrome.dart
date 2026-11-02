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
                        maxLines: 3,
                        textAlign: TextAlign.right,
                        style: AppTheme.cardTitle,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 3,
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
    this.twoLineLabels = false,
    this.alertLabels = const <String>{},
  });

  /// الاسم المركّب على سطرين ثابتين («الحركة» / «المالية»).
  final bool twoLineLabels;

  /// تبويبات فيها ما يحتاج متابعة (انتهى، حان وقته، متأخر): نقطة حمراء
  /// صغيرة تحتها.
  final Set<String> alertLabels;

  /// الارتفاع الموحَّد لشريط تبويبات صفحات التفاصيل.
  ///
  /// يتّسع لسطرين من النص: عناوين مثل "متابعة وتنظيم" و"مواقع وأماكن"
  /// كانت تُقصّ بثلاث نقاط في تبويب عرضه سُدس الشاشة، فيقرأ المستخدم
  /// "متابعة وت…". الآن تنزل الكلمة الثانية سطرًا كاملًا تحت الأولى.
  static const stripHeight = 74.0;

  /// فوق هذا العدد لا تتّسع التبويبات في عرض الشاشة دون أن تنكسر كلماتها
  /// («مستندا» في سطر و«ت» في سطر)، فيصير الشريط قابلًا للتمرير وتأخذ كل
  /// تبويبة عرض عنوانها كاملًا.
  static const scrollThreshold = 5;

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
      child: sections.length > scrollThreshold
          ? _ScrollingTabs(count: sections.length, builder: _tab)
          : Row(
              children: List.generate(
                sections.length,
                (index) => Expanded(child: _tab(index)),
              ),
            ),
    );
  }

  Widget _tab(int index) {
    final section = sections[index];
    final selected = index == selectedIndex;
    final alert = alertLabels.contains(section.label);
    return InkWell(
              key: ValueKey('shared-detail-page-tab-$index'),
              onTap: () => onSelected(index),
              child: Stack(
              // يملأ التبويب كاملًا فيبقى المحتوى في الوسط كما كان.
              fit: StackFit.expand,
              children: [
              Padding(
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
                  // كل سطر بكلماته كاملة («إدارة العهدة» / «والمصروفات»)،
                  // ويُصغَّر الخط إن ضاق التبويب بدل كسر الكلمة حرفًا حرفًا.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        twoLineLabels
                            ? twoLineLabel(section.label)
                            : section.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                          color: selected ? color : AppTheme.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: selected ? 26 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      // الخط تحت التبويب المحدَّد برتقالي في كل الصفحات.
                      color: selected ? AppTheme.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                  ),
                  ],
                ),
              ),
              if (alert)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 1,
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
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
          maxLines: 3,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          metric.value,
          maxLines: 3,
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
            maxLines: 3,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.chevron,
            ),
          ),
        ],
      ],
    );
  }
}

/// شريط تبويبات يتمرّر: أربعة تبويبات ونصف في العرض، فيظهر نصف التالي،
/// وسهم خفيف عند الحافة يختفي حين يصل المستخدم إلى آخر تبويب — فيُعرف من
/// النظرة الأولى أن هناك تبويبات أخرى.
class _ScrollingTabs extends StatefulWidget {
  const _ScrollingTabs({required this.count, required this.builder});

  final int count;
  final Widget Function(int index) builder;

  @override
  State<_ScrollingTabs> createState() => _ScrollingTabsState();
}

class _ScrollingTabsState extends State<_ScrollingTabs> {
  final _controller = ScrollController();
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final atEnd = position.pixels >= position.maxScrollExtent - 4;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth / 4.5).clamp(70.0, 112.0).toDouble();
        // ما يظهر من التبويب الأخير جزئيًا يُغطّى كاملًا: لا كلمة مقطوعة
        // في الطرف («السجـ»)، ويبقى السهم دليلًا على المزيد.
        final visible = constraints.maxWidth / width;
        final partial = visible - visible.floorToDouble();
        final cover = (partial * width + 6).clamp(30.0, width + 6).toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: ListView.builder(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.count,
                itemBuilder: (context, index) =>
                    SizedBox(width: width, child: widget.builder(index)),
              ),
            ),
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _atEnd ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: cover,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          AppTheme.surface.withValues(alpha: 0),
                          AppTheme.surface,
                          AppTheme.surface,
                        ],
                        stops: [0, (10 / cover).clamp(0.0, 1.0).toDouble(), 1],
                      ),
                    ),
                    child: Icon(
                      rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      size: 22,
                      color: AppTheme.title,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
