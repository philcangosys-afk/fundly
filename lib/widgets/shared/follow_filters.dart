import 'package:flutter/material.dart' hide Text, Align;

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// فلترا «المتابعة والتخطيط» الموحّدان في كل الصفحات (الالتزامات الشخصية
/// والمشتركة والأفراد والعقارات والأنشطة والمركبات): تحت العنوان مباشرة،
/// النوع والحالة، وزر «+» وحده في سطر العنوان.
const followKindFilterOptions = [
  'الكل',
  'مهمة',
  'موعد',
  'عادة',
  'تذكير',
  'ملاحظات',
];

const followStatusFilterOptions = [
  'الأحدث أولاً',
  'نشطة',
  'قريبًا',
  'حان وقتها',
  'متأخرة',
];

/// تاريخ البند: «17/10/2026» أو «2026-10-17».
DateTime? parseFollowDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  final parts = text.split(RegExp(r'[/\-.\s]+'));
  if (parts.length < 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

/// هل يطابق البند فلتر الحالة؟ بلا تاريخ = نشط دائمًا.
bool followStatusMatches(String status, String rawDate) {
  if (status == 'الأحدث أولاً' || status == 'الكل') return true;
  final date = parseFollowDate(rawDate);
  if (date == null) return status == 'نشطة';
  final days = DateUtils.dateOnly(date)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
  return switch (status) {
    'نشطة' => days >= 0,
    'قريبًا' => days > 0 && days <= 7,
    'حان وقتها' => days == 0,
    'متأخرة' => days < 0,
    _ => true,
  };
}

/// صندوقا الفلتر: «النوع» و«الحالة»، كلٌّ بعنوانه فوقه ويفتح قائمته.
class FollowFiltersRow extends StatelessWidget {
  const FollowFiltersRow({
    super.key,
    required this.kind,
    required this.status,
    required this.onKind,
    required this.onStatus,
    this.statusOptions = followStatusFilterOptions,
  });

  final String kind;
  final String status;
  final ValueChanged<String> onKind;
  final ValueChanged<String> onStatus;
  final List<String> statusOptions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Row(
        textDirection: AppTr.uiDir,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _FollowFilterBox(
              label: 'النوع',
              icon: Icons.layers_outlined,
              value: kind,
              options: followKindFilterOptions,
              onPick: onKind,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FollowFilterBox(
              label: 'الحالة',
              icon: Icons.schedule_rounded,
              value: status,
              options: statusOptions,
              onPick: onStatus,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowFilterBox extends StatelessWidget {
  const _FollowFilterBox({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onPick,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              for (final option in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    option == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: const Color(0xFF0E7161),
                  ),
                  title: Text(
                    option,
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF5C6B68)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5C6B68),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          onTap: () => _pick(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Expanded(
                  child: Text(
                    value,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Color(0xFF0F1F1C),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
