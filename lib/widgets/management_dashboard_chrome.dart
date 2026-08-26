import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          color: const Color(0xFFF5F8FC),
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

class ManagementDashboardHeader extends StatelessWidget {
  const ManagementDashboardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.onSmartCalendarTap,
    this.onClose,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onSmartCalendarTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      toolbarHeight: 88,
      elevation: 0,
      scrolledUnderElevation: 5,
      shadowColor: colors.first.withValues(alpha: 0.28),
      backgroundColor: colors.first,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
      ),
      titleSpacing: 14,
      title: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 23),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (onSmartCalendarTap != null) ...[
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'كلندر ذكي',
                onPressed: onSmartCalendarTap,
                icon: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ],
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
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
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
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
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
                    hintText: widget.hint ?? '',
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    suffixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: widget.accentColor,
                        width: 1.4,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            InkWell(
              onTap: widget.onFilterTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
        if (visibleItems.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
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

  static const _followUpColor = Color(0xFF8A6D1F);
  static const _followUpBackground = Color(0xFFFAF7EC);
  static const _followUpBorder = Color(0xFFE8DCB5);

  void _selectMetric(int index) {
    setState(() => _selectedMetricIndex = index);
    widget.onMetricSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final selectedMetricIndex =
        widget.selectedMetricIndex ?? _selectedMetricIndex;
    return Container(
      key: const ValueKey('management-follow-up-surface'),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: _followUpBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _followUpBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x128A6D1F),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _followUpBorder,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.dashboard_customize_outlined,
                  color: _followUpColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مركز المتابعة',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: _followUpColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _followUpColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onMore != null)
                IconButton(
                  onPressed: widget.onMore,
                  tooltip: 'عرض المتابعة كاملة',
                  visualDensity: VisualDensity.compact,
                  color: _followUpColor,
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 19),
                ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 7.0 * (widget.metrics.length - 1);
              final cardWidth =
                  ((constraints.maxWidth - spacing) / widget.metrics.length)
                      .clamp(72.0, 112.0);

              return SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: widget.metrics.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final metric = widget.metrics[index];
                    final selected = selectedMetricIndex == index;
                    return SizedBox(
                      width: cardWidth,
                      child: InkWell(
                        key: ValueKey('management-flat-metric-$index'),
                        onTap: () => _selectMetric(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.fromLTRB(7, 3, 7, 0),
                          decoration: const BoxDecoration(),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    metric.icon,
                                    color: _followUpColor,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${metric.count}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: _followUpColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                metric.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: _followUpColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : const Color(0xFFDCE5EF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF334155),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
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
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
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
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 94,
          padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFE6ECF3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
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
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
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
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
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
