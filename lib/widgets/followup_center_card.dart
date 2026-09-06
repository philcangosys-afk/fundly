import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

class FollowupCenterItem {
  final String label;
  final String count;
  final Color color;

  const FollowupCenterItem({
    required this.label,
    required this.count,
    required this.color,
  });
}

class FollowupCenterCard extends StatefulWidget {
  final List<FollowupCenterItem> items;
  final VoidCallback? onMoreTap;
  final String subtitle;

  const FollowupCenterCard({
    super.key,
    required this.items,
    this.onMoreTap,
    this.subtitle = 'يوجد أمور تحتاج متابعة',
  });

  @override
  State<FollowupCenterCard> createState() => _FollowupCenterCardState();
}

class _FollowupCenterCardState extends State<FollowupCenterCard> {
  int _selectedIndex = 0;

  static const _followUpColor = Color(0xFF8A6D1F);
  static const _followUpBackground = Color(0xFFFAF7EC);
  static const _followUpBorder = Color(0xFFE8DCB5);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('follow-up-center-surface'),
      width: double.infinity,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                child: const Icon(
                  Icons.dashboard_customize_outlined,
                  size: 20,
                  color: _followUpColor,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مركز المتابعة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: _followUpColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: _followUpColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('follow-up-more'),
                onPressed: widget.onMoreTap ?? () {},
                tooltip: AppTr.tr('عرض المتابعة كاملة'),
                visualDensity: VisualDensity.compact,
                color: _followUpColor,
                icon: Icon(
                  AppTr.isEnglish
                      ? Icons.arrow_back_ios_new_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                for (var index = 0; index < widget.items.length; index++) ...[
                  _FollowupItemText(
                    item: widget.items[index],
                    isSelected: _selectedIndex == index,
                    onTap: () => setState(() => _selectedIndex = index),
                  ),
                  if (index < widget.items.length - 1) const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowupItemText extends StatelessWidget {
  final FollowupCenterItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _FollowupItemText({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const followUpColor = Color(0xFF8A6D1F);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 112,
        padding: const EdgeInsets.fromLTRB(7, 3, 7, 0),
        decoration: const BoxDecoration(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.count,
              style: const TextStyle(
                fontSize: 16,
                color: followUpColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: followUpColor,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
