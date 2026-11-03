import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/app_design.dart';
import 'shared/search_matching.dart';

/// خلفية الوحدة الخفيفة: لونها بنسبة قليلة فوق الأبيض.
Color moduleTintFill(Color tint) =>
    Color.alphaBlend(tint.withValues(alpha: 0.07), Colors.white);

/// مستطيل الوحدة الملوّن من الترويسة حتى «الملخص الشامل»: يلوّن خلفية
/// [slivers] كلها بلون الوحدة الخفيف بحواف سفلية دائرية.
Widget moduleTintedGroup({required Color tint, required List<Widget> slivers}) {
  return DecoratedSliver(
    decoration: BoxDecoration(
      color: moduleTintFill(tint),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
    ),
    sliver: ModuleTintScope(
      child: SliverMainAxisGroup(
        slivers: [
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
        ],
      ),
    ),
  );
}

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
      shadowColor: const Color(0x1A022E2A),
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
    this.titleMaxLines = 2,
    this.toolbarHeight = 84,
    this.subtitleMaxLines = 2,
    this.titleFontSize,
    this.tint,
  });

  /// لون الوحدة: لمسة خفيفة في خلفية الترويسة وخط سفلي، تميّز الشخصية
  /// عن المشتركة والأفراد والعقارات.
  final Color? tint;

  /// أسطر الجملة تحت العنوان: 1 يصغّر الخط قليلًا لتظهر كاملة في سطر.
  final int subtitleMaxLines;

  /// حجم خط العنوان إن احتاج عنوان طويل أن يظهر كاملًا في سطرين.
  final double? titleFontSize;

  /// أسطر العنوان: 3 لعنوان طويل يظهر كاملًا بلا قصّ.
  final int titleMaxLines;

  /// ارتفاع الترويسة، يزيد مع عنوان من ثلاثة أسطر.
  final double toolbarHeight;

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
    final accent = tint ?? colors.first;
    final tinted = tint == null ? AppTheme.page : moduleTintFill(tint!);
    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: tinted,
      // مع لون الوحدة: بلا خط فاصل، فالترويسة وما تحتها مستطيل واحد.
      shape: tint == null
          ? const Border(bottom: BorderSide(color: AppTheme.line))
          : null,
      titleSpacing: AppTheme.pageInset,
      title: Directionality(
        textDirection: AppTr.uiDir,
        child: Row(
          children: [
            AppIconTile(icon: icon, color: accent),
            const SizedBox(width: AppTheme.sMd),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // العنوان كاملًا أيضًا: اسم الوحدة الطويل كان يُقصّ فلا
                  // يُعرف ما الذي تغطّيه الصفحة.
                  Text(
                    title,
                    maxLines: (titleMaxLines) + 2,
                    softWrap: true,
                    style: titleFontSize == null
                        ? AppTheme.cardTitle
                        : AppTheme.cardTitle.copyWith(fontSize: titleFontSize),
                  ),
                  const SizedBox(height: 3),
                  // الجملة كاملة: كانت تُقصّ بثلاث نقاط فلا تُقرأ. وفي سطر
                  // واحد يصغُر خطها بقدر ما يلزم لتظهر كلها.
                  if (subtitleMaxLines == 1)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        subtitle,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.muted,
                        ),
                      ),
                    )
                  else
                    Text(
                      subtitle,
                      maxLines: subtitleMaxLines,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.sSm),
            AppIconButton(
              tooltip: AppTr.tr('كلندر ذكي'),
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
              tooltip: AppTr.tr('رجوع'),
              icon: AppTr.isEnglish
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.arrow_forward_ios_rounded,
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
      textDirection: AppTr.uiDir,
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
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sMd),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.25,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
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
                  textDirection: AppTr.uiDir,
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
                    // علامة البحث في بداية المستطيل.
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: widget.accentColor,
                    ),
                    filled: true,
                    // داخل مستطيل الوحدة الملوّن: أبيض بحد واضح.
                    fillColor: ModuleTintScope.of(context)
                        ? Colors.white
                        : AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: ModuleTintScope.of(context)
                          ? const BorderSide(color: AppTheme.hairline)
                          : BorderSide.none,
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
                        maxLines: 3,
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
    this.accentColor = const Color(0xFF0E7161),
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
      textDirection: AppTr.uiDir,
      child: Row(
        children: [
          // العنوان ثم العدد ملاصقًا له من اليسار، وزر الترتيب في أقصى
          // الطرف دائمًا.
          Expanded(
            child: Row(
              children: [
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              softWrap: true,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.25,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sSm),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
          ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            key: const ValueKey('management-sort-button'),
            tooltip: AppTr.tr('ترتيب النتائج'),
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
                    fontSize: 10,
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
    this.categoryTitle,
    this.titleNote,
    this.trailingNote,
    this.showChevron = false,
    this.stacked = false,
    this.categoryStatus,
    this.badge,
    this.badgeColor = const Color(0xFF6A4C93),
    this.draftTag,
  });

  /// وسم «مسودة» بجانب الحالة (شاغر / مؤجر) — ما حُفظ مسودة ولم يُعتمد.
  final String? draftTag;

  static const _draftColor = Color(0xFFA6691A);

  Widget _draftPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _draftColor.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(AppTheme.rPill),
    ),
    child: Text(
      draftTag!,
      maxLines: 1,
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: _draftColor,
      ),
    ),
  );

  bool get _hasDraft => draftTag != null && draftTag!.trim().isNotEmpty;

  /// «مسودة» بجانب الحالة أينما كُتبت: في سطر النوع إن كانت الحالة فيه
  /// (العقار)، وإلا تحت وسم الحالة في الطرف (المركبة والنشاط).
  bool get _draftInCategoryRow =>
      _hasDraft &&
      ((categoryStatus?.trim().isNotEmpty ?? false) || status.trim().isEmpty);

  /// وسم صغير بجانب الاسم («مفوَّض أنا بإدارته» مثلًا).
  final String? badge;
  final Color badgeColor;

  // بلا خلفية: الكلمة وحدها بلونها، كما في صفحة العنصر من الداخل.
  Widget _badgePill() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      badge!,
      maxLines: 1,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        color: badgeColor,
      ),
    ),
  );

  /// حالة تُكتب في آخر سطر [categoryTitle] (يسارًا) بلون [statusColor] —
  /// العقار: شاغر / مؤجر.
  final String? categoryStatus;

  /// تخطيط مرتّب: الاسم وحده سطرًا، ثم الموقع بأيقونته، ثم النوع والحالة،
  /// ثم العقد وتاريخه. كان الاسم والموقع يُحشران في سطر واحد فيلتصق
  /// «فيلا زين» بـ«مدينة الرياض ـ حوض…» ولا يُقرأ أيهما.
  final bool stacked;

  /// نص خافت يلي العنوان في السطر نفسه — موقع العقار مثلًا. كان الموقع
  /// يُدفع إلى عمود اليسار فيُقرأ بعيدًا عن الاسم الذي يخصّه.
  final String? titleNote;

  /// سهم صغير في نهاية البطاقة (يسارًا في RTL) يوضح إمكانية الدخول.
  final bool showChevron;

  /// سطر صغير في نهاية البطاقة (الاتجاه المعاكس) — مكان العنصر مثلًا.
  final String? trailingNote;

  final String title;
  final String category;

  /// الفئة الرئيسية (العقارات / نشاط تجاري / آليات ومعدات...). حين تُمرَّر
  /// تُعرض سطرًا بارزًا فوق سطر النوع، فيقرأ المستخدم الفئة ثم النوع
  /// تحتها (مثال: نشاط تجاري ← متجر إلكتروني).
  final String? categoryTitle;
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
          height: 104,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
          // بطاقة قائمة رمادية موحّدة بلا حدود ولا ظل، بنفس نصف قطر صفوف
          // القوائم في كل التطبيق.
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              AppIconTile(icon: icon, color: accentColor),
              const SizedBox(width: AppTheme.sMd),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stacked)
                      // الاسم وحده في سطره: هو ما تبحث عنه العين أولًا،
                      // وازدحامه بالموقع كان يُفقده وضوحه.
                      Row(
                        children: [
                          Flexible(
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              title,
                              maxLines: 1,
                              style: AppTheme.rowTitle,
                            )),
                          ),
                          if (badge != null && badge!.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _badgePill(),
                          ],
                        ],
                      )
                    else
                      Row(
                        children: [
                          Flexible(
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              title,
                              maxLines: 1,
                              style: AppTheme.rowTitle,
                            )),
                          ),
                          if (titleNote != null &&
                              titleNote!.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                titleNote!,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.muted,
                                ),
                              )),
                            ),
                          ],
                          if (badge != null && badge!.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _badgePill(),
                          ],
                        ],
                      ),
                    if (categoryTitle != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              categoryTitle!,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: accentColor,
                              ),
                            )),
                          ),
                          if (_draftInCategoryRow) ...[
                            const SizedBox(width: 6),
                            _draftPill(),
                          ],
                          if (categoryStatus != null &&
                              categoryStatus!.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              categoryStatus!,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                    ] else
                      const SizedBox(height: 7),
                    if (category.trim().isNotEmpty || date.trim().isNotEmpty)
                    Row(
                      children: [
                        if (stacked && category.trim().isNotEmpty) ...[
                          const Icon(
                            Icons.description_outlined,
                            size: 11,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                            category,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: categoryTitle != null
                                  ? AppTheme.muted
                                  : accentColor,
                            ),
                          )),
                        ),
                        // بلا تاريخ لا تظهر الأيقونة ولا نصّها: أيقونة
                        // تقويم بجانب «غير محدد» تشغل مكان معلومة ولا
                        // تحمل واحدة.
                        if (date.trim().isNotEmpty) ...[
                          const SizedBox(width: 7),
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              date,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.muted,
                              ),
                            )),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (value.trim().isNotEmpty ||
                  status.trim().isNotEmpty ||
                  (trailingNote?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 86,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (value.trim().isNotEmpty) ...[
                      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                        value,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      )),
                      const SizedBox(height: 7),
                    ],
                    if (status.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                        status,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      )),
                    ),
                    // «مسودة» تحت وسم الحالة (شاغر / مؤجر).
                    if (_hasDraft && !_draftInCategoryRow) ...[
                      const SizedBox(height: 4),
                      _draftPill(),
                    ],
                    if (trailingNote != null &&
                        trailingNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                        trailingNote!,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      )),
                    ],
                  ],
                ),
              ),
              ],
              // نفس سهم بطاقات الالتزامات والأفراد: متجه للخارج (يسارًا)
              // ثابتًا مهما كان اتجاه الواجهة.
              if (showChevron) const AppChevron(size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
