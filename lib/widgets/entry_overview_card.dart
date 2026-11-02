import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

class EntryOverviewTile {
  const EntryOverviewTile({
    required this.icon,
    required this.color,
    required this.count,
    this.label,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String? label;
}

class EntryOverviewCard extends StatelessWidget {
  const EntryOverviewCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.tiles,
    required this.onTap,
    this.headerAction,
  });

  final String title;
  final String subtitle;
  final String countLabel;
  final List<EntryOverviewTile> tiles;
  final VoidCallback onTap;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF2F6F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: AppTr.uiDir,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          title,
                          maxLines: 3,
                          style: const TextStyle(
                            color: Color(0xFF0F1F1C),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 3,
                          style: const TextStyle(
                            color: Color(0xFF46534F),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'فتح $title',
                    child: InkResponse(
                      onTap: onTap,
                      radius: 24,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Color(0xFF0F1F1C),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        countLabel,
                        maxLines: 3,
                        style: const TextStyle(
                          color: Color(0xFF46534F),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (headerAction != null) ...[
                    const SizedBox(width: 2),
                    headerAction!,
                  ],
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  reverse: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _EntryTile(tile: tiles[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.tile});

  final EntryOverviewTile tile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 7,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10022E2A),
                    blurRadius: 9,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tile.icon, color: tile.color, size: 34),
                  if (tile.label != null) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        tile.label!,
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2C3B38),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            right: -7,
            top: 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF34A894),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF2F6F5), width: 2),
              ),
              child: Text(
                tile.count > 99 ? '99+' : '${tile.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
