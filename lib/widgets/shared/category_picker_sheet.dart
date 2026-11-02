import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';

import 'app_design.dart';

/// منتقي التصنيف: حقل واحد بسهم، ونافذة بحث تعرض كل التصنيفات في قائمة
/// واحدة — الرئيسي مكتوب تحته "تصنيف رئيسي"، والفرعي مكتوب تحته "فرعي من:
/// (اسم الرئيسي)".
///
/// كان الإدخال يطلب قائمتين منفصلتين: تختار الرئيسي ثم تنتظر ظهور الفرعي ثم
/// تفتح قائمة ثانية. والمستخدم في الغالب يعرف الفرعي مباشرة ("تطبيقات
/// توصيل") ولا يريد أن يتذكّر تحت أي رئيسي يقع.

/// نتيجة الاختيار. [main] فارغ = "بدون تصنيف".
class CategoryPickResult {
  const CategoryPickResult({required this.main, this.sub});

  final String main;
  final String? sub;

  bool get isEmpty => main.isEmpty;
}

/// مجموعة تصنيف: رئيسي وما تحته.
class CategoryGroup {
  const CategoryGroup({required this.main, required this.subs});

  final String main;
  final List<String> subs;
}

/// ألوان ثابتة للتصنيفات، تُوزَّع بترتيب المجموعات فيبقى لون كل تصنيف
/// ثابتًا في كل مرة يُفتح فيها المنتقي.
const _kCategoryPalette = <Color>[
  Color(0xFFD95A4E),
  Color(0xFF178F7B),
  Color(0xFF0E7161),
  Color(0xFFA6691A),
  Color(0xFF0E7161),
  Color(0xFF178F7B),
  Color(0xFFC4392E),
  Color(0xFF0A5A50),
  Color(0xFF0A5A50),
  Color(0xFFCE8422),
];

/// أيقونة معبّرة لكل تصنيف معروف، وأيقونة عامة لما عداه.
IconData categoryIconFor(String label) {
  const map = <String, IconData>{
    'طعام ومشروبات': Icons.restaurant_rounded,
    'بقالة وسوبرماركت': Icons.shopping_cart_rounded,
    'مطاعم وكوفيهات': Icons.restaurant_menu_rounded,
    'توصيل وطلبات': Icons.delivery_dining_rounded,
    'لحوم ودواجن': Icons.set_meal_rounded,
    'خضروات وفواكه': Icons.eco_rounded,
    'مخبوزات ومعجنات': Icons.bakery_dining_rounded,
    'مواصلات': Icons.directions_bus_rounded,
    'تطبيقات توصيل': Icons.local_taxi_rounded,
    'نقل عام وتاكسي': Icons.directions_transit_rounded,
    'إيجار': Icons.home_work_outlined,
    'دفع فواتير': Icons.receipt_long_rounded,
    'إنترنت واتصالات': Icons.wifi_rounded,
    'تأمينات': Icons.verified_user_outlined,
    'رسوم دراسية': Icons.school_outlined,
    'صحة': Icons.health_and_safety_outlined,
    'أدوية وصيدلية': Icons.medication_outlined,
    'أطباء وأشعة': Icons.medical_services_outlined,
    'تحاليل وفحوصات': Icons.biotech_outlined,
    'تعليم': Icons.menu_book_rounded,
    'مصروفات مدرسية': Icons.backpack_outlined,
    'دروس خصوصية': Icons.person_search_outlined,
    'دورات تدريبية': Icons.workspace_premium_outlined,
    'كتب ومراجع': Icons.auto_stories_outlined,
    'تسوق': Icons.shopping_bag_outlined,
    'ملابس': Icons.checkroom_rounded,
    'مستلزمات منزلية': Icons.chair_outlined,
    'تسوق إلكتروني': Icons.storefront_outlined,
    'إلكترونيات': Icons.devices_other_rounded,
    'عناية وجمال': Icons.spa_outlined,
    'مغسلة وكوي (مصبغة)': Icons.local_laundry_service_outlined,
    'ترفيه': Icons.celebration_outlined,
    'رياضة وجيم': Icons.fitness_center_rounded,
    'ألعاب': Icons.sports_esports_outlined,
    'سينما': Icons.movie_outlined,
    'سفر': Icons.flight_takeoff_rounded,
    'فنادق وإقامة': Icons.hotel_outlined,
    'تذاكر ورسوم سفر': Icons.airplane_ticket_outlined,
    'سيارة': Icons.directions_car_filled_outlined,
    'وقود': Icons.local_gas_station_outlined,
    'مواقف ورسوم طرق': Icons.local_parking_rounded,
    'صيانة وإصلاح': Icons.build_outlined,
    'قطع غيار': Icons.settings_suggest_outlined,
    'إكسسوارات سيارات': Icons.car_repair_rounded,
    'غسيل وتلميع': Icons.local_car_wash_outlined,
    'مخالفات': Icons.gavel_rounded,
    'غرامات (عام)': Icons.gavel_rounded,
    'رسوم بنكية': Icons.account_balance_outlined,
    'سداد قروض': Icons.credit_score_outlined,
    'سداد أقساط': Icons.calendar_month_outlined,
    'خدمات حكومية': Icons.apartment_rounded,
    'مصروفات أخرى': Icons.more_horiz_rounded,
    // فئات مصروفات الرحلة والالتزامات المشتركة.
    'كوفيهات': Icons.local_cafe_outlined,
    'مطاعم': Icons.restaurant_menu_rounded,
    'مساعدات': Icons.volunteer_activism_outlined,
    'تأجير سيارة': Icons.car_rental_rounded,
    'أنشطة وجولات': Icons.hiking_rounded,
    'دخول أماكن': Icons.confirmation_number_outlined,
    'هدايا': Icons.card_giftcard_rounded,
    'الراتب/معاش': Icons.payments_outlined,
    'الراتب': Icons.account_balance_wallet_outlined,
    'عمولات': Icons.percent_rounded,
    'عمل إضافي': Icons.work_history_outlined,
    'تعويض واسترجاع مصروف': Icons.replay_circle_filled_outlined,
    'كاش باك': Icons.savings_outlined,
    'غرامات': Icons.gavel_rounded,
    'مرور': Icons.traffic_rounded,
    'حكومية': Icons.account_balance_rounded,
    'مالية': Icons.attach_money_rounded,
    'تعاقدية': Icons.description_outlined,
    'خدمات': Icons.miscellaneous_services_outlined,
  };
  return map[label] ?? Icons.label_outline_rounded;
}

/// حقل التصنيف: يعرض الاختيار الحالي ("بدون تصنيف" أو "الرئيسي › الفرعي")
/// ويفتح المنتقي عند الضغط.
class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.groups,
    required this.main,
    required this.sub,
    required this.onChanged,
    this.accent = AppTheme.accent,
    this.required = false,
    this.requireSub = false,
    this.allowCustom = true,
    this.title = 'التصنيف',
  });

  final List<CategoryGroup> groups;
  final String main;
  final String? sub;
  final ValueChanged<CategoryPickResult> onChanged;
  final Color accent;
  final bool required;

  /// هل يلزم اختيار تصنيف فرعي لا الاكتفاء بالرئيسي؟
  final bool requireSub;
  final bool allowCustom;
  final String title;

  String get _label {
    if (main.isEmpty) return 'بدون تصنيف';
    if (sub == null || sub!.isEmpty) return main;
    return '$main › $sub';
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: main,
      validator: trValidator((_) {
        if (required && main.isEmpty) return 'يرجى اختيار التصنيف';
        if (requireSub && (sub == null || sub!.isEmpty)) {
          return 'يرجى اختيار تصنيف فرعي';
        }
        return null;
      }),
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () async {
              final picked = await showCategoryPickerSheet(
                context: context,
                groups: groups,
                selectedMain: main,
                selectedSub: sub,
                accent: accent,
                title: title,
                allowCustom: allowCustom,
              );
              if (picked == null) return;
              state.didChange(picked.main);
              onChanged(picked);
            },
            borderRadius: BorderRadius.circular(AppTheme.rField),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rField),
                border: state.hasError
                    ? Border.all(color: AppTheme.danger, width: 1.2)
                    : null,
              ),
              // النص أولًا ليقع في يمين السطر، والسهم بعده في يساره.
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                      _label,
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: main.isEmpty ? AppTheme.body : AppTheme.title,
                      ),
                    )),
                  ),
                  const SizedBox(width: AppTheme.sSm),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.title,
                  ),
                ],
              ),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(
                state.errorText!,
                style: const TextStyle(fontSize: 11, color: AppTheme.danger),
              ),
            ),
        ],
      ),
    );
  }
}

/// يفتح نافذة اختيار التصنيف. يُعيد null إن أُغلقت بلا اختيار.
Future<CategoryPickResult?> showCategoryPickerSheet({
  required BuildContext context,
  required List<CategoryGroup> groups,
  String selectedMain = '',
  String? selectedSub,
  Color accent = AppTheme.accent,
  String title = 'التصنيف',
  bool allowCustom = true,
}) {
  final searchController = TextEditingController();

  return showModalBottomSheet<CategoryPickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchController.text.trim();

          // القائمة مسطّحة: رئيسي ثم فروعه، وكل صف يقول ما هو.
          final rows = <({String label, String? parent, Color color})>[];
          for (var index = 0; index < groups.length; index++) {
            final group = groups[index];
            final color = _kCategoryPalette[index % _kCategoryPalette.length];
            rows.add((label: group.main, parent: null, color: color));
            for (final sub in group.subs) {
              rows.add((label: sub, parent: group.main, color: color));
            }
          }
          final visible = query.isEmpty
              ? rows
              : rows
                    .where(
                      (row) =>
                          row.label.contains(query) ||
                          (row.parent?.contains(query) ?? false),
                    )
                    .toList(growable: false);

          return FractionallySizedBox(
            heightFactor: 0.9,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7FAF9),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.rCard),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DEDB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF022E2A),
                            ),
                          ),
                        ),
                        AppIconButton(
                          tooltip: AppTr.tr('إغلاق'),
                          icon: Icons.close_rounded,
                          background: AppTheme.field,
                          color: AppTheme.chevron,
                          onTap: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        hintText: AppTr.tr('ابحث باسم التصنيف'),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rField),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rField),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      children: [
                        if (query.isEmpty)
                          _CategoryRow(
                            label: 'بدون تصنيف',
                            subtitle: null,
                            icon: Icons.block_rounded,
                            color: AppTheme.muted,
                            selected: selectedMain.isEmpty,
                            isSub: false,
                            onTap: () => Navigator.of(sheetContext).pop(
                              const CategoryPickResult(main: ''),
                            ),
                          ),
                        for (final row in visible)
                          _CategoryRow(
                            label: row.label,
                            subtitle: row.parent == null
                                ? 'تصنيف رئيسي'
                                : 'فرعي من: ${row.parent}',
                            icon: categoryIconFor(row.label),
                            color: row.color,
                            isSub: row.parent != null,
                            selected: row.parent == null
                                ? selectedMain == row.label &&
                                      (selectedSub == null ||
                                          selectedSub.isEmpty)
                                : selectedMain == row.parent &&
                                      selectedSub == row.label,
                            onTap: () => Navigator.of(sheetContext).pop(
                              CategoryPickResult(
                                main: row.parent ?? row.label,
                                sub: row.parent == null ? null : row.label,
                              ),
                            ),
                          ),
                        // إضافة تصنيف جديد بالاسم: الملف المعتمد ينص على
                        // "+ إضافة أخرى" في قوائم التصنيف.
                        if (allowCustom)
                          _CategoryRow(
                            label: '+ إضافة أخرى',
                            subtitle: 'يُحفظ مع هذا الإدخال',
                            icon: Icons.add_rounded,
                            color: accent,
                            selected: false,
                            isSub: false,
                            onTap: () async {
                              final name = await _askCustomCategory(
                                sheetContext,
                                query,
                              );
                              if (name == null || !sheetContext.mounted) return;
                              // إن كان هناك تصنيف رئيسي مختار، فالاسم
                              // الجديد فرعٌ منه؛ وإلا فهو تصنيف رئيسي جديد.
                              Navigator.of(sheetContext).pop(
                                selectedMain.isEmpty
                                    ? CategoryPickResult(main: name)
                                    : CategoryPickResult(
                                        main: selectedMain,
                                        sub: name,
                                      ),
                              );
                            },
                          ),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text(
                              'لا يوجد تصنيف بهذا الاسم',
                              textAlign: TextAlign.center,
                              style: AppTheme.emptyText,
                            ),
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
    ),
  ).whenComplete(searchController.dispose);
}

/// حوار صغير لاسم الإضافة الجديدة — يستعمل الحوار الموحّد الآمن.
Future<String?> _askCustomCategory(
  BuildContext context,
  String initialText,
) => askTextDialog(
  context,
  title: 'إضافة أخرى',
  label: 'الاسم',
  initialText: initialText,
);

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.isSub,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool isSub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // التصنيف الفرعي يبدأ مُزاحًا عن الرئيسي بمقدار كلمة تقريبًا،
      // فيظهر بوضوح أنه فرع مما فوقه لا بندًا مستقلًا.
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: isSub ? 44 : 0),
        child: Material(
        color: selected ? AppTheme.accentSoft : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (selected)
                  Icon(Icons.check_circle_rounded, color: AppTheme.success)
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 3,
                        style: AppTheme.rowTitle,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 3,
                          style: AppTheme.rowSubtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                // سهم صغير يشير إلى أن هذا الصف فرع من التصنيف الذي فوقه.
                if (isSub) ...[
                  const Icon(
                    Icons.subdirectory_arrow_left_rounded,
                    size: 16,
                    color: AppTheme.muted,
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
