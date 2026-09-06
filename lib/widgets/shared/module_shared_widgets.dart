import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../detail_page_chrome.dart';
import '../management_dashboard_chrome.dart';
import 'app_design.dart';

// أدوات مطابقة البحث نُقلت إلى ملف مستقل لتجنّب الاستيراد الدائري مع
// management_dashboard_chrome.dart، ويُعاد تصديرها هنا حتى تبقى كل
// مواضع الاستدعاء القائمة تعمل دون تغيير.
export 'search_matching.dart';

enum ThreeDotMenuAction { edit, share, delete, archive, freeze, pinHome }

class SearchAndFilterBar extends StatelessWidget {
  const SearchAndFilterBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.accentColor,
    required this.onSearch,
    required this.onFilter,
  });

  final TextEditingController controller;
  final String hintText;
  final Color accentColor;
  final ValueChanged<String> onSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return ManagementSearchBar(
      controller: controller,
      hint: hintText,
      accentColor: accentColor,
      onChanged: onSearch,
      onFilterTap: onFilter,
    );
  }
}

class UnifiedSearchFilterBar extends StatelessWidget {
  const UnifiedSearchFilterBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.accentColor,
    required this.activeFilterLabel,
    required this.onChanged,
    required this.onFilterTap,
    this.onClear,
    this.resultText,
  });

  final TextEditingController controller;
  final String hintText;
  final Color accentColor;
  final String activeFilterLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final VoidCallback? onClear;
  final String? resultText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textDirection: AppTr.uiDir,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    suffixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF475569),
                    ),
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
                    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onFilterTap,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'الفلتر: $activeFilterLabel',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (resultText != null)
                Text(
                  resultText!,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (controller.text.trim().isNotEmpty && onClear != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('مسح'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}


class FollowUpCenter extends StatelessWidget {
  const FollowUpCenter({
    super.key,
    required this.subtitle,
    required this.metrics,
    this.onMore,
    this.selectedMetricIndex,
    this.onMetricSelected,
  });

  final String subtitle;
  final List<ManagementMetricData> metrics;
  final VoidCallback? onMore;
  final int? selectedMetricIndex;
  final ValueChanged<int>? onMetricSelected;

  @override
  Widget build(BuildContext context) {
    final slots = metrics.length >= 3 ? metrics.take(3).toList() : metrics;
    return ManagementFollowUpCenter(
      subtitle: subtitle,
      metrics: slots,
      onMore: onMore,
      selectedMetricIndex: selectedMetricIndex,
      onMetricSelected: onMetricSelected,
    );
  }
}

class CategoryChipItem {
  const CategoryChipItem({
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
}

class CategoryChipsRow extends StatelessWidget {
  const CategoryChipsRow({super.key, required this.items});

  final List<CategoryChipItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 39,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final item = items[index];
          return ManagementCategoryTab(
            label: item.label,
            count: item.count,
            icon: item.icon,
            color: item.color,
            selected: item.selected,
            onTap: item.onTap,
          );
        },
      ),
    );
  }
}

class ListHeaderRow extends StatelessWidget {
  const ListHeaderRow({
    super.key,
    required this.count,
    required this.title,
    required this.sortValue,
    required this.sortOptions,
    required this.accentColor,
    required this.onSortChanged,
  });

  final int count;
  final String title;
  final String sortValue;
  final List<String> sortOptions;
  final Color accentColor;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return ManagementSortHeader(
      value: sortValue,
      options: sortOptions,
      onSelected: onSortChanged,
      title: title,
      count: count,
      accentColor: accentColor,
    );
  }
}

class EntityCard extends StatelessWidget {
  const EntityCard({
    super.key,
    required this.leadingIcon,
    required this.title,
    required this.category,
    required this.subtitleDate,
    required this.trailingValue,
    required this.status,
    required this.accentColor,
    required this.statusColor,
    required this.onTap,
  });

  final IconData leadingIcon;
  final String title;
  final String category;
  final String subtitleDate;
  final String trailingValue;
  final String status;
  final Color accentColor;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ManagementCompactCard(
      title: title,
      category: category,
      date: subtitleDate,
      value: trailingValue,
      status: status,
      icon: leadingIcon,
      accentColor: accentColor,
      statusColor: statusColor,
      onTap: onTap,
    );
  }
}

class AddFab extends StatefulWidget {
  const AddFab({
    super.key,
    required this.screenId,
    required this.onPressed,
    this.label = '+ إضافة',
    this.icon = Icons.add,
    this.backgroundColor = const Color(0xFF0F6AA8),
    this.foregroundColor = Colors.white,
    this.initialOffset = const Offset(0, 0),
  });

  final String screenId;
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Offset initialOffset;

  @override
  State<AddFab> createState() => _AddFabState();
}

class _AddFabState extends State<AddFab> {
  Offset? _offset;
  static const double _fabWidth = 170;
  static const double _fabHeight = 56;

  String get _xKey => 'add_fab_${widget.screenId}_x';
  String get _yKey => 'add_fab_${widget.screenId}_y';

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_xKey);
    final y = prefs.getDouble(_yKey);
    if (!mounted) return;
    setState(() {
      _offset = (x == null || y == null) ? widget.initialOffset : Offset(x, y);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offset == null) return;
    final viewport = MediaQuery.of(context).size;
    final normalized = _clampOffset(_offset!, viewport);
    if (normalized != _offset) {
      _offset = normalized;
      _savePosition(normalized);
    }
  }

  Offset _clampOffset(Offset offset, Size viewport) {
    final minDx = -(viewport.width - _fabWidth - 24);
    const maxDx = 0.0;
    final minDy = -(viewport.height - _fabHeight - 96);
    const maxDy = 0.0;
    return Offset(
      offset.dx.clamp(minDx, maxDx).toDouble(),
      offset.dy.clamp(minDy, maxDy).toDouble(),
    );
  }

  Future<void> _savePosition(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_xKey, offset.dx);
    await prefs.setDouble(_yKey, offset.dy);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    final currentOffset = _offset ?? widget.initialOffset;
    final visibleOffset = _clampOffset(currentOffset, viewport);

    return SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Transform.translate(
          offset: visibleOffset,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) {
              final current = _offset ?? visibleOffset;
              setState(() {
                _offset = _clampOffset(current + details.delta, viewport);
              });
            },
            onPanEnd: (_) {
              _savePosition(_offset ?? visibleOffset);
            },
            onPanCancel: () {
              _savePosition(_offset ?? visibleOffset);
            },
            child: _buildFab(),
          ),
        ),
      ),
    );
  }

  Widget _buildFab({double opacity = 1}) {
    return Opacity(
      opacity: opacity,
      child: FloatingActionButton.extended(
        onPressed: widget.onPressed,
        backgroundColor: widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        elevation: 7,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        icon: Icon(widget.icon, color: widget.foregroundColor),
        label: Text(
          widget.label,
          style: TextStyle(
            color: widget.foregroundColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class AddTypeSheet extends StatelessWidget {
  const AddTypeSheet({super.key, required this.groups});

  final Map<String, List<String>> groups;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: groups.entries
              .map(
                (entry) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value
                          .map(
                            (item) => ActionChip(
                              label: Text(item),
                              onPressed: () => Navigator.of(context).pop(item),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.header,
    required this.tabs,
    required this.selectedTabIndex,
    required this.onTabSelected,
    required this.accentColor,
    required this.body,
    this.actions,
  });

  final DetailPageHeader header;
  final List<DetailSectionTab> tabs;
  final int selectedTabIndex;
  final ValueChanged<int> onTabSelected;
  final Color accentColor;
  final Widget body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 10),
        if (actions != null) ...[actions!, const SizedBox(height: 10)],
        DetailPageTabs(
          sections: tabs,
          selectedIndex: selectedTabIndex,
          color: accentColor,
          onSelected: onTabSelected,
        ),
        const SizedBox(height: 10),
        body,
      ],
    );
  }
}

class ThreeDotMenu extends StatelessWidget {
  const ThreeDotMenu({
    super.key,
    required this.onAction,
    this.tooltip = 'خيارات',
    this.freezeLabel = 'تجميد / إلغاء التجميد',
    this.pinLabel = 'تثبيت في الرئيسية',
  });

  final ValueChanged<ThreeDotMenuAction> onAction;
  final String tooltip;
  final String freezeLabel;
  final String pinLabel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThreeDotMenuAction>(
      tooltip: tooltip,
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 23,
        color: Color(0xFF475569),
      ),
      onSelected: onAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: ThreeDotMenuAction.edit,
          child: _ThreeDotMenuItemRow(
            label: 'تعديل البيانات',
            icon: Icons.edit_outlined,
          ),
        ),
        const PopupMenuItem(
          value: ThreeDotMenuAction.share,
          child: _ThreeDotMenuItemRow(
            label: 'مشاركة',
            icon: Icons.share_outlined,
          ),
        ),
        const PopupMenuItem(
          value: ThreeDotMenuAction.delete,
          child: _ThreeDotMenuItemRow(
            label: 'حذف',
            icon: Icons.delete_outline_rounded,
            color: Color(0xFFB42318),
          ),
        ),
        const PopupMenuItem(
          value: ThreeDotMenuAction.archive,
          child: _ThreeDotMenuItemRow(
            label: 'أرشيف',
            icon: Icons.archive_outlined,
          ),
        ),
        PopupMenuItem(
          value: ThreeDotMenuAction.freeze,
          child: _ThreeDotMenuItemRow(
            label: freezeLabel,
            icon: Icons.block_rounded,
          ),
        ),
        PopupMenuItem(
          value: ThreeDotMenuAction.pinHome,
          child: _ThreeDotMenuItemRow(
            label: pinLabel,
            icon: Icons.push_pin_outlined,
          ),
        ),
      ],
    );
  }
}

class _ThreeDotMenuItemRow extends StatelessWidget {
  const _ThreeDotMenuItemRow({
    required this.label,
    required this.icon,
    this.color = const Color(0xFF334155),
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
