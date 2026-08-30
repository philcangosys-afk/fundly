import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/app_design.dart';
import 'shared/search_matching.dart';

class ManagementPinnedControls extends StatelessWidget {
  const ManagementPinnedControls({
    super.key,
    required this.child,
    this.height = 234,
    this.horizontalPadding = 16,
  });

  final Widget child;
  final double height;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _ManagementPinnedControlsDelegate(
        height: height,
        child: ColoredBox(
          key: const ValueKey('pinned-dashboard-controls'),
          color: AppTheme.page,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              8,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ManagementPinnedControlsDelegate extends SliverPersistentHeaderDelegate {
  const _ManagementPinnedControlsDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.transparent,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: const Color(0x1A0F172A),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_ManagementPinnedControlsDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}

/// ترويسة شاشات الوحدات الأربع.
///
/// كانت الأزرار اختيارية، فاختلفت الترويسات: العقارات فيها زرّا الكلندر
/// والرجوع، والشخصية فيها الكلندر وحده، والأفراد الرجوع وحده،
/// والمشتركة بلا أزرار إطلاقًا. الآن يظهر الزرّان دائمًا، وصار
/// [onSmartCalendarTap] مطلوبًا حتى لا تنسى شاشة جديدة تمريره فتفترق
/// عن أخواتها بصمت.
class ManagementDashboardHeader extends StatelessWidget {
  const ManagementDashboardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onSmartCalendarTap,
    this.onClose,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onSmartCalendarTap;

  /// زر الرجوع في الترويسة. افتراضيًا: الرجوع للخلف.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    // ترويسة بيضاء موحّدة مع بقية التطبيق: أيقونة الوحدة في مربّع بلونها،
    // العنوان بلون النص الأساسي، والأزرار بمقاس وشكل أزرار التطبيق. كانت
    // ترويسة متدرّجة ملوّنة بحدود شبه شفافة تختلف عن كل شاشة أخرى.
    final accent = colors.first;
    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      toolbarHeight: 84,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: AppTheme.page,
      shape: const Border(bottom: BorderSide(color: AppTheme.line)),
      titleSpacing: AppTheme.pageInset,
      title: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            AppIconTile(icon: icon, color: accent),
            const SizedBox(width: AppTheme.sMd),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.cardTitle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowSubtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.sSm),
            AppIconButton(
              tooltip: 'كلندر ذكي',
              icon: Icons.calendar_month_rounded,
              background: AppTheme.field,
              color: accent,
              onTap: onSmartCalendarTap,
            ),
            const SizedBox(width: AppTheme.sSm),
            // سهم رجوع لا علامة إغلاق: الشاشة تُفتح فوق الرئيسية فالخروج
            // منها رجوع للخلف، وهو نفس السهم المستخدم في صفحات التفاصيل.
            // علامة X تعني "إلغاء/إغلاق نافذة" فتوحي بمعنى مختلف.
            // السهم يشير يمينًا لا يسارًا: الواجهة عربية والرجوع في اتجاه
            // القراءة من اليمين إلى اليسار يعني السهم المتّجه يمينًا.
            AppIconButton(
              tooltip: 'رجوع',
              icon: Icons.arrow_forward_ios_rounded,
              background: AppTheme.field,
              color: AppTheme.chevron,
              onTap: onClose ?? () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

class ManagementListHeading extends StatelessWidget {
  const ManagementListHeading({
    super.key,
    required this.title,
    required this.count,
    required this.accentColor,
  });

  final String title;
  final int count;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sMd),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.cardTitle,
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementMetricData {
  const ManagementMetricData({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
}

class ManagementSearchBar extends StatefulWidget {
  const ManagementSearchBar({
    super.key,
    required this.controller,
    this.hint,
    required this.accentColor,
    required this.onChanged,
    required this.onFilterTap,
    this.searchId = 'general',
    this.suggestions = const [],
  });

  final TextEditingController controller;
  final String? hint;
  final Color accentColor;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final String searchId;
  final List<String> suggestions;

  @override
  State<ManagementSearchBar> createState() => _ManagementSearchBarState();
}

class _ManagementSearchBarState extends State<ManagementSearchBar> {
  static const _recentSearchesPrefix = 'recent_searches_';
  List<String> _recentSearches = const [];
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches =
          preferences
              .getStringList('$_recentSearchesPrefix${widget.searchId}')
              ?.take(4)
              .toList(growable: false) ??
          const [];
    });
  }

  Future<void> _saveRecentSearch(String value) async {
    final term = value.trim();
    if (term.isEmpty) return;
    final updated = [
      term,
      ..._recentSearches.where((item) => item != term),
    ].take(4).toList(growable: false);
    setState(() => _recentSearches = updated);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      '$_recentSearchesPrefix${widget.searchId}',
      updated,
    );
  }

  void _selectSearch(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    widget.onChanged(value);
    _saveRecentSearch(value);
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim();
    // مطابقة موحّدة عربيًا: كانت المقارنة سابقًا على النص الخام، فلا تظهر
    // أي نتيجة عند كتابة "اح" لاسم مسجَّل بصيغة "أحمد" — رغم أن الفلترة
    // نفسها كانت تطابقه. الآن يستخدم الاثنان المعيار نفسه.
    final matchingSuggestions = searchSuggestionsFor(
      query: query,
      candidates: widget.suggestions,
    );
    final visibleItems = matchingSuggestions.isNotEmpty
        ? matchingSuggestions
        : query.isEmpty && _hasFocus
        ? _recentSearches
        : const <String>[];
    final showingSuggestions = matchingSuggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Focus(
                onFocusChange: (hasFocus) =>
                    setState(() => _hasFocus = hasFocus),
                child: TextField(
                  controller: widget.controller,
                  textDirection: TextDirection.rtl,
                  onChanged: (value) {
                    widget.onChanged(value);
                    setState(() {});
                  },
                  onSubmitted: _saveRecentSearch,
                  decoration: InputDecoration(
                    // كان النص الإرشادي المُمرَّر من كل شاشة يُتجاهل ويُستبدل
                    // بنص فارغ، فيظهر مربع البحث خاليًا بلا أي دلالة.
                    // حقل ممتلئ بلا حدود بنفس نصف قطر ولون حقول التطبيق.
                    hintText: widget.hint ?? '',
                    hintStyle: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    suffixIcon: const Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: AppTheme.chevron,
                    ),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.sSm),
            Material(
              color: widget.accentColor,
              borderRadius: BorderRadius.circular(AppTheme.rField),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onFilterTap,
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (visibleItems.isNotEmpty) ...[
          const SizedBox(height: AppTheme.sSm),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: visibleItems
                  .map(
                    (item) => ListTile(
                      dense: true,
                      leading: Icon(
                        showingSuggestions
                            ? Icons.search_rounded
                            : Icons.history_rounded,
                        color: widget.accentColor,
                        size: 19,
                      ),
                      title: Text(
                        item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.rowTitle,
                      ),
                      onTap: () => _selectSearch(item),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class ManagementFollowUpCenter extends StatefulWidget {
  const ManagementFollowUpCenter({
    super.key,
    required this.subtitle,
    required this.metrics,
    this.accentColor = const Color(0xFF047857),
    this.onMore,
    this.selectedMetricIndex,
    this.onMetricSelected,
  });

  final String subtitle;
  final List<ManagementMetricData> metrics;
  final Color accentColor;
  final VoidCallback? onMore;
  final int? selectedMetricIndex;
  final ValueChanged<int>? onMetricSelected;

  @override
  State<ManagementFollowUpCenter> createState() =>
      _ManagementFollowUpCenterState();
}

class _ManagementFollowUpCenterState extends State<ManagementFollowUpCenter> {
  int _selectedMetricIndex = 0;

  void _selectMetric(int index) {
    setState(() => _selectedMetricIndex = index);
    widget.onMetricSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final selectedMetricIndex =
        widget.selectedMetricIndex ?? _selectedMetricIndex;
    // مركز المتابعة بنفس لون وحواف البطاقات الموحّدة في التطبيق: رمادي
    // ناعم، نصف قطر كبير، بلا حدود ولا ظل. كان صندوقًا ذهبيًا بحدّ وظل
    // لا يشبه أي عنصر آخر في التطبيق.
    return AppCard(
      key: const ValueKey('management-follow-up-surface'),
      leading: AppIconTile(
        icon: Icons.dashboard_customize_outlined,
        color: widget.accentColor,
      ),
      title: 'مركز المتابعة',
      subtitle: widget.subtitle,
      onTap: widget.onMore,
      trailing: const AppMoreAction(),
      child: SizedBox(
        height: AppMetricChip.stripHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = AppTheme.sSm * (widget.metrics.length - 1);
            final chipWidth =
                ((constraints.maxWidth - spacing) / widget.metrics.length)
                    .clamp(74.0, 132.0);
            // بلا reverse: داخل الاتجاه العربي يبدأ الشريط من اليمين
            // تلقائيًا. كان reverse يقلبه فيبدأ من اليسار، بعكس كل شريط
            // آخر في الصفحة نفسها.
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: widget.metrics.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppTheme.sSm),
              itemBuilder: (context, index) {
                final metric = widget.metrics[index];
                return SizedBox(
                  width: chipWidth,
                  child: AppMetricChip(
                    key: ValueKey('management-flat-metric-$index'),
                    label: metric.label,
                    count: metric.count,
                    icon: metric.icon,
                    color: metric.color,
                    selected: selectedMetricIndex == index,
                    onTap: () => _selectMetric(index),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ManagementCategoryTab extends StatelessWidget {
  const ManagementCategoryTab({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // شريحة الفئة الموحَّدة: بلا حدود، والمحدَّدة ممتلئة بلون الوحدة.
    return AppCategoryChip(
      label: label,
      count: count,
      icon: icon,
      color: color,
      selected: selected,
      onTap: onTap,
    );
  }
}

class ManagementSortHeader extends StatelessWidget {
  const ManagementSortHeader({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.title,
    required this.count,
    required this.accentColor,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final String title;
  final int count;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sMd),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.cardTitle,
            ),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('management-sort-button'),
            tooltip: 'ترتيب النتائج',
            initialValue: value,
            onSelected: onSelected,
            itemBuilder: (context) => options
                .map(
                  (option) => PopupMenuItem(value: option, child: Text(option)),
                )
                .toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementCompactCard extends StatelessWidget {
  const ManagementCompactCard({
    super.key,
    required this.title,
    required this.category,
    required this.date,
    required this.value,
    required this.status,
    required this.icon,
    required this.accentColor,
    required this.statusColor,
    required this.onTap,
  });

  final String title;
  final String category;
  final String date;
  final String value;
  final String status;
  final IconData icon;
  final Color accentColor;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        child: Container(
          height: 94,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
          // بطاقة قائمة رمادية موحّدة بلا حدود ولا ظل، بنفس نصف قطر صفوف
          // القوائم في كل التطبيق.
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              AppIconTile(icon: icon, color: accentColor),
              const SizedBox(width: AppTheme.sMd),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: AppTheme.muted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 86,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
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
    );
  }
}
