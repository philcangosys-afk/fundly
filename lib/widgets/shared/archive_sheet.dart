import 'package:flutter/material.dart' hide Text, Align;

import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';
import 'app_design.dart';

/// عنصر واحد داخل نافذة الأرشيف: ما يُعرض، وكيف تُلغى أرشفته.
class ArchiveEntry {
  const ArchiveEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onUnarchive,
    this.color = AppTheme.brandMid,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// تُعيد true إذا نجحت إزالة الأرشفة فعلًا.
  final Future<bool> Function() onUnarchive;

  /// اختياري: «حذف» من الأرشيف إلى سلة المهملات. تُعيد true إذا نجح.
  final Future<bool> Function()? onDelete;
}

/// زر «الأرشيف» الموحّد: مكتوب داخله الاسم ومعه عدد المؤرشفات.
///
/// المؤرشفات مخفية عن القوائم العادية، فلا بد من باب ظاهر إليها في كل
/// شاشة بدل البحث عنها داخل الفلتر المتقدم.
class AppArchiveButton extends StatelessWidget {
  const AppArchiveButton({
    super.key,
    required this.count,
    required this.onTap,
    this.height = 52,
  });

  final int count;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: count > 0 ? AppTheme.goldSoft : AppTheme.field,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          border: Border.all(
            color: count > 0 ? AppTheme.goldDark : AppTheme.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: AppTr.uiDir,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 19,
              color: count > 0 ? AppTheme.goldDark : AppTheme.title,
            ),
            const SizedBox(width: 7),
            Text(
              'الأرشيف',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: count > 0 ? AppTheme.goldDark : AppTheme.title,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.goldDark,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// نافذة الأرشيف المنبثقة: قائمة المؤرشفات مع «إلغاء الأرشفة» لكل عنصر.
///
/// تُعيد true إذا أُلغيت أرشفة عنصر واحد على الأقل، لتُحدّث الشاشة نفسها.
Future<bool> showArchiveSheet(
  BuildContext context, {
  required String title,
  required List<ArchiveEntry> entries,
}) async {
  var changed = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final rows = entries;
        return Directionality(
          textDirection: AppTr.uiDir,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: rows.isEmpty ? 0.42 : 0.7,
            maxChildSize: 0.92,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.hairline,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: AppTheme.goldDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'أرشيف $title',
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppTheme.hairline),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'لا توجد عناصر مؤرشفة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.muted,
                      ),
                    ),
                  )
                else
                  for (final entry in rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.rInner),
                        border: Border.all(color: AppTheme.hairline),
                      ),
                      child: Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: entry.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppTheme.rIcon,
                              ),
                            ),
                            child: Icon(
                              entry.icon,
                              size: 19,
                              color: entry.color,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  entry.title,
                                  textAlign: AppTr.alignEnd,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.title,
                                  ),
                                ),
                                if (entry.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.subtitle,
                                    textAlign: AppTr.alignEnd,
                                    maxLines: 3,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.brandMid,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(0, 38),
                            ),
                            onPressed: () async {
                              final ok = await confirmAction(
                                sheetContext,
                                title: 'إلغاء الأرشفة',
                                message:
                                    'سيعود «${entry.title}» إلى القائمة '
                                    'النشطة. هل تريد المتابعة؟',
                                confirmLabel: 'إلغاء الأرشفة',
                              );
                              if (!ok) return;
                              final done = await entry.onUnarchive();
                              if (!done) return;
                              changed = true;
                              setSheetState(() => rows.remove(entry));
                            },
                            icon: const Icon(Icons.unarchive_outlined, size: 17),
                            label: const Text(
                              'إلغاء الأرشفة',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (entry.onDelete != null)
                            IconButton(
                              tooltip: AppTr.tr('حذف'),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppTheme.danger,
                              ),
                              onPressed: () async {
                                final ok = await confirmAction(
                                  sheetContext,
                                  title: 'حذف',
                                  message:
                                      'سيُنقل «${entry.title}» إلى سلة '
                                      'المهملات، ومنها يمكن استعادته أو حذفه '
                                      'نهائيًا. هل تريد المتابعة؟',
                                  confirmLabel: 'حذف',
                                  danger: true,
                                );
                                if (!ok) return;
                                final done = await entry.onDelete!();
                                if (!done) return;
                                changed = true;
                                setSheetState(() => rows.remove(entry));
                              },
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return changed;
}
