import 'package:flutter/material.dart';

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
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final visualMetrics = isRtl
        ? List<DetailHeaderMetric>.from(metrics.reversed)
        : List<DetailHeaderMetric>.from(metrics);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const ValueKey('shared-detail-page-header'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE1E7EF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 4), trailing!],
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                textDirection: TextDirection.ltr,
                children: List.generate(visualMetrics.length, (index) {
                  return Expanded(
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Expanded(child: _DetailMetric(metric: visualMetrics[index])),
                        if (index < visualMetrics.length - 1)
                          const SizedBox(
                            height: 54,
                            child: VerticalDivider(
                              width: 14,
                              color: Color(0xFFE2E8F0),
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

  final List<DetailSectionTab> sections;
  final int selectedIndex;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('shared-detail-page-tabs'),
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Row(
        children: List.generate(sections.length, (index) {
          final section = sections[index];
          final selected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              key: ValueKey('shared-detail-page-tab-$index'),
              onTap: () => onSelected(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    section.icon,
                    size: 18,
                    color: selected ? color : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: selected ? color : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: selected ? 28 : 0,
                    height: 2,
                    color: selected ? color : Colors.transparent,
                  ),
                ],
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
        Icon(metric.icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(height: 5),
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
        ),
        if (metric.caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            metric.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }
}
