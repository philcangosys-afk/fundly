import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../detail_page_chrome.dart';
import '../management_dashboard_chrome.dart';
import 'app_design.dart';
import '../../data/fundly_auth.dart';

// أدوات مطابقة البحث نُقلت إلى ملف مستقل لتجنّب الاستيراد الدائري مع
// management_dashboard_chrome.dart، ويُعاد تصديرها هنا حتى تبقى كل
// مواضع الاستدعاء القائمة تعمل دون تغيير.
export 'search_matching.dart';

enum ThreeDotMenuAction { edit, share, delete, archive, freeze, pinHome }

/// أمر إضافي يُعرض أعلى قائمة الثلاث نقاط.
///
/// للأوامر غير المُتلِفة — «إضافة وحدة»، «بيانات العقار الرسمية» — فتُنفَّذ
/// بلا نافذة تأكيد، ويختفي معها زر «+» المكرَّر من رأس كل قسم.
class ThreeDotExtraAction {
  const ThreeDotExtraAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

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
          colors: [Color(0xFFFFFFFF), Color(0xFFE9F4F1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12022E2A),
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
                      color: Color(0xFF8C9A97),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    suffixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF46534F),
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
                    color: Color(0xFF5C6B68),
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
                    foregroundColor: const Color(0xFF46534F),
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
    this.label = 'إضافة',
    this.icon = Icons.add,
    this.backgroundColor = const Color(0xFF0A5A50),
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
    // اتجاه الواجهة داخل الزر نفسه: «+» قبل الكلمة (يمينها بالعربية) في
    // كل الشاشات، مهما كان اتجاه الصفحة التي وُضع فيها الزر.
    return Opacity(
      opacity: opacity,
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: FloatingActionButton.extended(
        // الضيف يُطلب منه تسجيل الدخول قبل أي إضافة.
        onPressed: () async {
          if (await FundlyAuth.requireLogin(context)) widget.onPressed();
        },
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
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
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
    this.extraActions = const [],
    this.deleteLabel = 'حذف',
    this.deleteIcon = Icons.delete_outline_rounded,
    this.deleteMessage =
        'سيُحذف العنصر نهائيًا ولا يمكن التراجع. هل تريد الحذف؟',
    this.deleteConfirmLabel = 'حذف',
    this.showEdit = true,
    this.showDelete = true,
    this.trailingActions = const [],
    this.showArchive = true,
    this.deleteBlockedMessage,
  });

  /// سبب يمنع الحذف/الإلغاء الآن (عقد إيجار ساري مثلًا): يظهر بدل نافذة
  /// التأكيد ولا يُنفَّذ شيء.
  final String? deleteBlockedMessage;

  /// false: بلا «أرشيف» (العنصر المفوَّض: الأرشفة لصاحبه وحده).
  final bool showArchive;

  /// أوامر تحت «أرشيف» في آخر القائمة («تفويض آخرين» مثلًا) — بلا تأكيد.
  final List<ThreeDotExtraAction> trailingActions;

  /// false: بلا أمر الحذف/الإلغاء (العقار أو النشاط أو المركبة الملغى لا
  /// يُحذف — يبقى في «السجل التاريخي»).
  final bool showDelete;

  /// false: بلا «تعديل بيانات» (حين يوجد أمر تعديل خاص في [extraActions]).
  final bool showEdit;

  /// أمر «الحذف» قابل للتسمية: في العقارات والأنشطة والمركبات يظهر
  /// «إلغاء» أولًا، و«حذف» (إلى سلة المهملات) للعنصر الملغى فقط.
  final String deleteLabel;
  final IconData deleteIcon;
  final String deleteMessage;
  final String deleteConfirmLabel;

  final ValueChanged<ThreeDotMenuAction> onAction;
  final String tooltip;
  final String freezeLabel;
  final String pinLabel;

  /// أوامر تُعرض أعلى القائمة وتُنفَّذ بلا تأكيد — انظر
  /// [ThreeDotExtraAction].
  final List<ThreeDotExtraAction> extraActions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: tooltip,
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 23,
        color: Color(0xFF46534F),
      ),
      // لا يُنفَّذ أي إجراء مُتلِف من هذه القائمة قبل نافذة تأكيد صريحة.
      // والأوامر الإضافية تُستثنى: الإضافة لا تُتلف شيئًا ليُؤكَّد.
      onSelected: (value) async {
        if (value is int) {
          if (value >= 0 && value < extraActions.length) {
            extraActions[value].onSelected();
          } else if (value >= 1000 &&
              value - 1000 < trailingActions.length) {
            trailingActions[value - 1000].onSelected();
          }
          return;
        }
        final action = value as ThreeDotMenuAction;
        final blocked = deleteBlockedMessage?.trim() ?? '';
        if (action == ThreeDotMenuAction.delete && blocked.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => Directionality(
              textDirection: AppTr.uiDir,
              child: AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                ),
                title: Text(
                  deleteLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
                content: Text(
                  blocked,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF46534F),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('حسنًا'),
                  ),
                ],
              ),
            ),
          );
          return;
        }
        final (label, message, danger) = switch (action) {
          ThreeDotMenuAction.edit => (
            'تعديل بيانات',
            'سيُفتح نموذج التعديل. هل تريد المتابعة؟',
            false,
          ),
          ThreeDotMenuAction.share => (
            'مشاركة',
            'ستُشارك البيانات عبر تطبيق تختاره. هل تريد المتابعة؟',
            false,
          ),
          ThreeDotMenuAction.delete => (deleteLabel, deleteMessage, true),
          ThreeDotMenuAction.archive => (
            'أرشفة',
            'سيُنقل العنصر إلى الأرشيف ويمكن إخراجه لاحقًا. هل تريد الأرشفة؟',
            false,
          ),
          ThreeDotMenuAction.freeze => (
            freezeLabel,
            'سيتغيّر وضع التجميد لهذا العنصر. هل تريد المتابعة؟',
            false,
          ),
          ThreeDotMenuAction.pinHome => (
            pinLabel,
            'سيتغيّر تثبيت العنصر في الصفحة الرئيسية. هل تريد المتابعة؟',
            false,
          ),
        };
        final ok = await confirmAction(
          context,
          title: label,
          message: message,
          confirmLabel: danger ? deleteConfirmLabel : 'تأكيد',
          danger: danger,
        );
        if (!ok || !context.mounted) return;
        onAction(action);
      },
      itemBuilder: (context) => [
        for (var i = 0; i < extraActions.length; i++)
          PopupMenuItem<Object>(
            value: i,
            child: _ThreeDotMenuItemRow(
              label: extraActions[i].label,
              icon: extraActions[i].icon,
              color: const Color(0xFF0E7161),
            ),
          ),
        if (extraActions.isNotEmpty) const PopupMenuDivider(),
        if (showEdit)
          const PopupMenuItem<Object>(
            value: ThreeDotMenuAction.edit,
            child: _ThreeDotMenuItemRow(
              label: 'تعديل بيانات',
              icon: Icons.edit_outlined,
            ),
          ),
        const PopupMenuItem<Object>(
          value: ThreeDotMenuAction.share,
          child: _ThreeDotMenuItemRow(
            label: 'مشاركة',
            icon: Icons.share_outlined,
          ),
        ),
        if (showDelete)
          PopupMenuItem<Object>(
            value: ThreeDotMenuAction.delete,
            child: _ThreeDotMenuItemRow(
              label: deleteLabel,
              icon: deleteIcon,
              color: const Color(0xFFA82F26),
            ),
          ),
        if (showArchive)
        const PopupMenuItem<Object>(
          value: ThreeDotMenuAction.archive,
          child: _ThreeDotMenuItemRow(
            label: 'أرشيف',
            icon: Icons.archive_outlined,
          ),
        ),
        for (var i = 0; i < trailingActions.length; i++)
          PopupMenuItem<Object>(
            value: 1000 + i,
            child: _ThreeDotMenuItemRow(
              label: trailingActions[i].label,
              icon: trailingActions[i].icon,
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
    this.color = const Color(0xFF2C3B38),
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
