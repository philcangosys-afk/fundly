import 'package:flutter/material.dart';

/// نظام التصميم الموحَّد للتطبيق.
///
/// كانت كل شاشة تخترع مقاساتها وألوانها: نصف قطر 10 هنا و14 هناك و18 في
/// ثالثة، وحدود ملوّنة في صندوق وظلال في آخر، وأسهم بأحجام وألوان مختلفة
/// في الصفحة الواحدة. النتيجة تطبيق تبدو صفحاته كأنها من تطبيقات مختلفة.
///
/// كل قيمة هنا مصدرها الوحيد، فالأشياء المتشابهة تظهر متشابهة فعلًا:
/// بطاقة خارجية واحدة، بطاقة داخلية واحدة، سهم واحد، مربع أيقونة واحد.
class AppTheme {
  const AppTheme._();

  // ===== الألوان =====
  /// خلفية الصفحة: بيضاء، فتبرز البطاقات الرمادية فوقها.
  static const page = Color(0xFFFFFFFF);

  /// البطاقة الخارجية — نفس لون ونعومة مربعات الصفحات الاحترافية.
  static const surface = Color(0xFFEDF1F2);

  /// بطاقة داخلية تقع داخل بطاقة خارجية.
  static const surfaceInner = Color(0xFFFFFFFF);

  /// حقول الإدخال والمناطق الخفيفة.
  static const field = Color(0xFFF2F5F6);

  /// خط فاصل رفيع (يُستعمل بشحّ — التصميم يعتمد على الكتل لا الحدود).
  static const line = Color(0xFFE3E9EB);

  static const title = Color(0xFF16232B);
  static const body = Color(0xFF56666E);
  static const muted = Color(0xFF8DA0A8);
  static const chevron = Color(0xFF7C8D95);

  static const accent = Color(0xFF3E8E8B);
  static const accentDark = Color(0xFF2C6B69);
  static const accentSoft = Color(0xFFE4EFEF);

  static const danger = Color(0xFFC7443F);
  static const success = Color(0xFF2E7D62);
  static const warning = Color(0xFFB4741A);

  // ===== أنصاف الأقطار =====
  /// البطاقة الخارجية.
  static const rCard = 24.0;

  /// البطاقة الداخلية.
  static const rInner = 16.0;

  /// مربع الأيقونة والأزرار الصغيرة.
  static const rIcon = 14.0;

  /// حقول الإدخال والأزرار العريضة.
  static const rField = 18.0;

  static const rPill = 999.0;

  // ===== المسافات =====
  static const sXs = 4.0;
  static const sSm = 8.0;
  static const sMd = 12.0;
  static const sLg = 16.0;
  static const sXl = 20.0;
  static const sXxl = 24.0;

  /// الهامش الأفقي الثابت لكل الصفحات.
  static const pageInset = 16.0;

  /// حشوة البطاقة الخارجية.
  static const cardPadding = EdgeInsets.all(sLg);

  /// المسافة الرأسية بين بطاقتين متتاليتين.
  static const cardGap = sMd;

  // ===== المقاسات الموحّدة =====
  /// مربع الأيقونة في صفوف القوائم والبطاقات.
  static const iconTile = 44.0;
  static const iconTileSmall = 36.0;
  static const iconSize = 21.0;
  static const iconSizeSmall = 17.0;
  static const chevronSize = 24.0;

  // ===== النصوص =====
  static const cardTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: title,
    height: 1.25,
  );

  static const sectionTitle = TextStyle(
    fontSize: 18.5,
    fontWeight: FontWeight.w900,
    color: title,
    height: 1.25,
  );

  static const rowTitle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w800,
    color: title,
    height: 1.3,
  );

  static const rowSubtitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: muted,
    height: 1.45,
  );

  static const bodyText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: body,
    height: 1.5,
  );

  static const emptyText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: muted,
    height: 1.5,
  );
}

/// سِمة التطبيق الموحَّدة.
///
/// هذه هي القاعدة التي توحّد النماذج والنوافذ: كانت كل شاشة تكتب شكل
/// حقولها وأزرارها ونوافذها بنفسها — نصف قطر 12 هنا و13 هناك و14 في
/// ثالثة، وحدود رمادية في نموذج وبلا حدود في آخر. الآن يُعرَّف الشكل مرة
/// واحدة هنا فيَرِثه كل حقل وكل زر وكل نافذة في التطبيق تلقائيًا، بما في
/// ذلك ما لم نمرّ عليه يدويًا.
ThemeData buildAppTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTheme.accent,
      primary: AppTheme.accent,
      surface: AppTheme.page,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: AppTheme.page,
  );

  OutlineInputBorder fieldBorder([Color? color, double width = 0]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );

  return base.copyWith(
    // AppBarThemeData / InputDecorationThemeData: أسماء ما بعد توحيد
    // سِمات المكوّنات في Flutter 3.35 — الأصناف القديمة صارت Widgets ولا
    // تُقبل هنا.
    appBarTheme: const AppBarThemeData(
      backgroundColor: AppTheme.page,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppTheme.title,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppTheme.cardTitle,
    ),
    dividerTheme: const DividerThemeData(
      color: AppTheme.line,
      thickness: 1,
      space: 1,
    ),
    // حقول الإدخال: ممتلئة بلا حدود، ونصف قطر واحد في كل التطبيق.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppTheme.field,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.sLg,
        vertical: 14,
      ),
      border: fieldBorder(),
      enabledBorder: fieldBorder(),
      disabledBorder: fieldBorder(),
      focusedBorder: fieldBorder(AppTheme.accent, 1.4),
      errorBorder: fieldBorder(AppTheme.danger, 1.2),
      focusedErrorBorder: fieldBorder(AppTheme.danger, 1.4),
      hintStyle: const TextStyle(
        color: AppTheme.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: const TextStyle(
        color: AppTheme.body,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppTheme.accentDark,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      helperStyle: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
      prefixIconColor: AppTheme.chevron,
      suffixIconColor: AppTheme.chevron,
    ),
    // الأزرار: ارتفاع ونصف قطر موحّدان.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.sXl),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.sXl),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accentDark,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.sXl),
        side: const BorderSide(color: AppTheme.line),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accentDark,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rIcon),
        ),
      ),
    ),
    // النوافذ والشيتات: نفس نصف القطر الكبير في كل مكان.
    dialogTheme: DialogThemeData(
      backgroundColor: AppTheme.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppTheme.cardTitle,
      contentTextStyle: AppTheme.bodyText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppTheme.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppTheme.page,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      textStyle: AppTheme.rowTitle,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.title,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
    ),
    chipTheme: ChipThemeData(
      // فرق واضح بين المحدَّدة وغيرها: accentSoft قريب جدًا من لون
      // الحقول فلا يكاد يُرى الفرق.
      backgroundColor: AppTheme.field,
      selectedColor: AppTheme.accent.withValues(alpha: 0.20),
      checkmarkColor: AppTheme.accentDark,
      side: BorderSide.none,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.body,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
      ),
    ),
    switchTheme: SwitchThemeData(
      // إبهام المفتاح في وضع الإيقاف رمادي لا أبيض: أبيض على مسار فاتح
      // بلا إطار يجعل المفتاح المُطفأ غير مرئي تقريبًا.
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppTheme.chevron,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppTheme.accent
            : AppTheme.field,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(AppTheme.line),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: AppTheme.rowTitle,
      subtitleTextStyle: AppTheme.rowSubtitle,
      iconColor: AppTheme.chevron,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppTheme.accent,
    ),
  );
}

/// السهم الموحَّد في كل التطبيق: رفيع، رمادي، متجه لليسار.
///
/// أيقونات الأسهم في Flutter تنعكس تلقائيًا مع اتجاه النص، فتشير لليمين
/// داخل التغليف العربي. تثبيت الاتجاه هنا مرة واحدة يمنع تكرار الخطأ في
/// كل شاشة.
class AppChevron extends StatelessWidget {
  const AppChevron({super.key, this.color, this.size});

  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Icon(
        Icons.chevron_left_rounded,
        size: size ?? AppTheme.chevronSize,
        color: color ?? AppTheme.chevron,
      ),
    );
  }
}

/// ارتفاع بطاقة المجموعة داخل مركز المتابعة المفصّل.
///
/// كانت البطاقات تأخذ ارتفاع محتواها، فتخرج الشبكة بأطوال مختلفة وفراغات
/// غير منتظمة. الآن تُحسب البطاقة على أكبر عدد بنود في الشاشة فتتساوى كل
/// البطاقات، والحساب يراعي حجم الخط الذي يختاره المستخدم فلا يفيض المحتوى.
double appFollowUpCardExtent(BuildContext context, int maxRows) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  // الترويسة: حشوة علوية 12 + مربع الأيقونة 34 + فاصل 4.
  final headerText = 20 * scale;
  final header = 12 + (headerText > 34 ? headerText : 34.0) + 4;
  // كل بند فرعي: حشوة 7 أعلى و7 أسفل + ارتفاع السطر (أيقونة 18 أو النص).
  final lineText = 17 * scale;
  final rowHeight = 14 + (lineText > 18 ? lineText : 18.0);
  return header + maxRows * rowHeight + 10;
}

/// بطاقة تفاصيل موحَّدة لكل صفحات التفاصيل الداخلية.
///
/// كانت كل شاشة تفاصيل ترسم بطاقتها بنفسها: الالتزام الشخصي ببطاقة رمادية
/// وصفوف يفصلها خط أبيض رفيع، والشخص/الجهة ببطاقة متدرّجة بحدّ زرقاء وظل
/// وصفوف كل واحد منها صندوق مستقل، والعقار بشكل ثالث. الشكل الواحد هنا
/// مصدره الوحيد، فتتطابق الصفحات فعلًا.
class AppDetailsCard extends StatelessWidget {
  const AppDetailsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: AppTheme.sSm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.sMd),
          ...children,
        ],
      ),
    );
  }
}

/// صف معلومة داخل [AppDetailsCard]: أيقونة، اسم الحقل، قيمته، ويفصله عمّا
/// تحته خط أبيض رفيع لا صندوق مستقل.
class AppDetailRow extends StatelessWidget {
  const AppDetailRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.sMd),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? const Color(0xFF1E293B),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// إجراء "المزيد" الموحَّد: كلمة + سهم.
///
/// السهم وحده لا يقول للمستخدم ماذا يفتح، فأُضيفت الكلمة بجانبه بلا تغيير
/// اتجاه السهم.
class AppMoreAction extends StatelessWidget {
  const AppMoreAction({super.key, this.label = 'المزيد', this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color ?? AppTheme.muted,
          ),
        ),
        const SizedBox(width: AppTheme.sXs),
        AppChevron(color: color),
      ],
    );
  }
}

/// مربع أيقونة موحَّد: خلفية بلون الأيقونة الباهت ونصف قطر ثابت.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size,
    this.iconSize,
    this.background,
  });

  final IconData icon;
  final Color color;
  final double? size;
  final double? iconSize;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final box = size ?? AppTheme.iconTile;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
      ),
      child: Icon(
        icon,
        color: color,
        size: iconSize ?? (box >= AppTheme.iconTile ? AppTheme.iconSize : AppTheme.iconSizeSmall),
      ),
    );
  }
}

/// البطاقة الخارجية الموحَّدة: مستطيل رمادي ناعم بلا حدود ولا ظل،
/// عنوانه أقصى اليمين وسهمه أقصى اليسار.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.trailing,
    this.showChevron = true,
    this.padding,
    this.background,
    this.margin,
    required this.child,
  });

  final String? title;
  final String? subtitle;

  /// أيقونة أو عنصر يسبق العنوان (أقصى اليمين).
  final Widget? leading;
  final VoidCallback? onTap;

  /// عنصر يحل محل السهم أقصى اليسار (زر مثلًا).
  final Widget? trailing;
  final bool showChevron;
  final EdgeInsetsGeometry? padding;
  final Color? background;
  final EdgeInsetsGeometry? margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final header = title == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppTheme.sMd),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title!, style: AppTheme.cardTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: AppTheme.rowSubtitle),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.sSm),
              if (trailing != null)
                trailing!
              else if (showChevron && onTap != null)
                const AppChevron(),
            ],
          );

    final content = Padding(
      padding: padding ?? AppTheme.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[header, const SizedBox(height: AppTheme.sMd)],
          child,
        ],
      ),
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: background ?? AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          clipBehavior: Clip.antiAlias,
          child: onTap == null
              ? content
              : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// بطاقة داخلية بيضاء تقع داخل [AppCard].
class AppInnerCard extends StatelessWidget {
  const AppInnerCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.background,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppTheme.sMd),
      child: child,
    );
    return Material(
      color: background ?? AppTheme.surfaceInner,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// صف قائمة موحَّد: أيقونة يمينًا، عنوان ووصف، سهم يسارًا.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.background,
    this.compact = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? background;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: background ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.sLg,
              vertical: compact ? AppTheme.sMd : AppTheme.sLg,
            ),
            child: Row(
              children: [
                AppIconTile(
                  icon: icon,
                  color: iconColor,
                  size: compact ? AppTheme.iconTileSmall : AppTheme.iconTile,
                ),
                const SizedBox(width: AppTheme.sMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.rowTitle,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.rowSubtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.sSm),
                trailing ?? (onTap == null ? const SizedBox.shrink() : const AppChevron()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// عنوان قسم داخل الصفحة (خارج البطاقات).
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppTheme.sectionTitle)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// زر أيقونة مربّع موحَّد (زر إجراء داخل ترويسة أو بطاقة).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double? size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final box = size ?? AppTheme.iconTile;
    final button = Material(
      color: background ?? AppTheme.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.rIcon),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: box,
          height: box,
          child: Icon(
            icon,
            size: AppTheme.iconSize,
            color: color ?? AppTheme.accentDark,
          ),
        ),
      ),
    );

    final wrapped = tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);

    if (!badge) return wrapped;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        wrapped,
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.danger,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// مؤشر داخل مركز المتابعة: بطاقة داخلية صغيرة، المحدَّد منها يتلوّن.
///
/// كان لكل شاشة نسختها الخاصة من هذا المؤشر بألوان ومقاسات مختلفة، وكان
/// الفرق بين المحدَّد وغيره سماكة خط لا تكاد تُرى.
class AppMetricChip extends StatelessWidget {
  const AppMetricChip({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// الارتفاع الموحَّد لشريط المؤشرات.
  static const stripHeight = 58.0;

  /// العرض الموحَّد لكل مؤشر.
  static const chipWidth = 106.0;

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // بلا صندوق ولا لون تحديد ولا وميض لمس: الأيقونة والرقم والنص فقط،
    // بالشكل نفسه قبل الضغط وبعده. الضغط يصفّي القائمة أسفل مركز المتابعة
    // وهذا هو أثره المرئي، أما تلوين المؤشر نفسه فكان يجعل الشريط يتراقص
    // بالألوان مع كل ضغطة. لذلك GestureDetector لا InkWell (لا موجة لمس).
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: AppTheme.sXs),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: AppTheme.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريحة فئة موحَّدة (تبويبات الفئات فوق القوائم).
class AppCategoryChip extends StatelessWidget {
  const AppCategoryChip({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? color : AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : color,
                ),
                const SizedBox(width: 6),
                // بلا رقم داخل الشريحة: العدد يظهر في رأس القائمة أسفلها
                // ("١٢ جميع الالتزامات")، فكتابته هنا أيضًا تكرار يزاحم
                // الاسم ويجعل الشرائح بأعرض مختلفة بلا داعٍ.
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.body,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة عنصر القائمة الموحَّدة (التزام شخصي، التزام مشترك، شخص/جهة...).
///
/// كانت كل شاشة تكتب بطاقتها بنفسها، فاختلفت الارتفاعات (94 هنا وارتفاع
/// تلقائي هناك) والحشوات وأنصاف الأقطار وأحجام الخط رغم أن الشكل واحد.
/// الآن بطاقة واحدة تستعملها الشاشات الثلاث، فيستحيل أن تفترق.
///
/// عمود الإحصاءات يعرض أول قيمتين غير فارغتين فقط: فبند بلا مبلغ لا
/// يعرض "المبلغ : 0.00"، وشخص بلا مستحقات لا يكرّر السطر نفسه مرتين.
class AppEntityCard extends StatelessWidget {
  const AppEntityCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconBackground,
    this.statusColor,
    this.stats = const [],
    this.leadingBadges = const [],
    this.trailing,
  });

  /// عرض عمود الإحصاءات الموحَّد.
  static const statsWidth = 108.0;

  /// مقاس مربّع الأيقونة في بطاقات القوائم.
  static const iconBox = 46.0;

  final IconData icon;
  final Color iconColor;
  final Color? iconBackground;
  final String title;
  final String subtitle;
  final Color? statusColor;

  /// حتى قيمتين تظهران يسار البطاقة؛ الفارغة منها تُحذف تمامًا.
  final List<String> stats;

  /// أيقونات صغيرة قبل العنوان (تثبيت، تجميد...).
  final List<Widget> leadingBadges;

  /// إجراء إضافي بعد السهم (قائمة الخيارات مثلًا).
  final Widget? trailing;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visibleStats = stats
        .where((value) => value.trim().isNotEmpty)
        .take(2)
        .toList(growable: false);

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            14,
            12,
            trailing == null ? 12 : 4,
            12,
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: iconBackground ?? iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(icon, color: iconColor, size: 23),
              ),
              const SizedBox(width: AppTheme.sMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        ...leadingBadges,
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        if (statusColor != null)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsetsDirectional.only(
                              start: 6,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (visibleStats.isNotEmpty) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: statsWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        visibleStats.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      if (visibleStats.length > 1) ...[
                        const SizedBox(height: 6),
                        Text(
                          visibleStats[1],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(width: AppTheme.sXs),
              const AppChevron(size: 22),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// عنصر داخل قائمة شريحة الفئة المنسدلة.
class AppDropdownItem {
  const AppDropdownItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
}

/// شريحة فئة بسهم يفتح قائمة منسدلة أسفلها مباشرةً.
///
/// القائمة تعرض ستة عناصر فقط ثم تُمرَّر، ويظهر سهم صغير أسفلها يدل على
/// وجود عناصر أخرى — بدل نافذة تملأ الشاشة بثلاثة عشر عنصرًا دفعةً واحدة.
class AppCategoryDropdownChip extends StatefulWidget {
  const AppCategoryDropdownChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.count,
    this.items = const [],
  });

  /// ارتفاع الصف الواحد داخل القائمة.
  static const rowHeight = 44.0;

  /// أقصى عدد عناصر ظاهرة قبل التمرير.
  static const visibleRows = 6;

  static const menuWidth = 214.0;

  final String label;
  final IconData icon;
  final Color color;
  final int? count;
  final bool selected;

  /// الضغط على جسم الشريحة (لا على السهم).
  final VoidCallback onTap;

  /// عناصر القائمة؛ الفارغة تعني شريحة بلا سهم.
  final List<AppDropdownItem> items;

  @override
  State<AppCategoryDropdownChip> createState() =>
      _AppCategoryDropdownChipState();
}

class _AppCategoryDropdownChipState extends State<AppCategoryDropdownChip> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _canScrollMore = ValueNotifier(false);
  OverlayEntry? _entry;
  bool _open = false;
  Rect _anchorRect = Rect.zero;

  /// الشريط الذي تعيش فيه الشريحة — يُراقَب لإغلاق القائمة عند تمريره.
  ScrollPosition? _hostScrollPosition;

  @override
  void dispose() {
    _removeEntry();
    _scrollController.dispose();
    _canScrollMore.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppCategoryDropdownChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // بدون هذا تبقى القائمة المفتوحة معروضة بأعداد وحالات قديمة بعد أي
    // تحديث للشاشة خلفها. ويُؤجَّل إلى ما بعد الإطار لأن didUpdateWidget
    // يعمل أثناء البناء، وطبقة القائمة شقيقة لا تابعة — فيقع خطأ
    // "markNeedsBuild أثناء البناء".
    final entry = _entry;
    if (entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry != entry) return;
      // يُعاد حساب موضع الإرساء أيضًا، فقد يكون الشريط قد تحرّك.
      final anchor = _resolveAnchor();
      if (anchor != null) _anchorRect = anchor;
      entry.markNeedsBuild();
    });
  }

  void _detachHostScroll() {
    _hostScrollPosition?.removeListener(_closeOnHostScroll);
    _hostScrollPosition = null;
  }

  void _closeOnHostScroll() {
    // موضع الإرساء يُلتقط مرة واحدة عند الفتح؛ فلو تحرّك الشريط بقيت
    // القائمة معلّقة في مكان قديم. تُغلق بدل أن تطفو في غير موضعها.
    if (mounted && _open) setState(_removeEntry);
  }

  void _removeEntry() {
    _detachHostScroll();
    _entry?.remove();
    // OverlayEntry صار ChangeNotifier ويجب التخلص منه، وإلا رُصد كتسريب.
    _entry?.dispose();
    _entry = null;
    _open = false;
  }

  double get _menuHeight {
    final count = widget.items.length;
    final rows = count > AppCategoryDropdownChip.visibleRows
        ? AppCategoryDropdownChip.visibleRows
        : (count < 1 ? 1 : count);
    final overflow = count > AppCategoryDropdownChip.visibleRows;
    return AppCategoryDropdownChip.rowHeight * rows + (overflow ? 24 : 0);
  }

  /// موضع القائمة محسوبًا داخل حدود الشاشة.
  ///
  /// الإرساء المركزي وحده كان يُخرج قائمة بعرض 214 خارج الشاشة حين تكون
  /// الشريحة قرب إحدى الحافتين، ولا يقلبها للأعلى قرب الأسفل.
  Rect? _resolveAnchor() {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlayBox == null) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & box.size;
  }

  void _toggle() {
    if (_open) {
      setState(_removeEntry);
      return;
    }
    final anchor = _resolveAnchor();
    if (anchor == null) return;
    _anchorRect = anchor;
    _canScrollMore.value =
        widget.items.length > AppCategoryDropdownChip.visibleRows;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => _buildMenu());
    overlay.insert(_entry!);
    final hostPosition = Scrollable.maybeOf(context)?.position;
    hostPosition?.addListener(_closeOnHostScroll);
    _hostScrollPosition = hostPosition;
    setState(() => _open = true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _canScrollMore.value = position.pixels < position.maxScrollExtent - 2;
  }

  Widget _buildMenu() {
    final items = widget.items;
    final hasOverflow = items.length > AppCategoryDropdownChip.visibleRows;
    final rows = hasOverflow
        ? AppCategoryDropdownChip.visibleRows
        : (items.isEmpty ? 1 : items.length);
    final listHeight = AppCategoryDropdownChip.rowHeight * rows;
    final menuHeight = _menuHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 8.0;
        const gap = 6.0;
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        var maxLeft =
            screenWidth - AppCategoryDropdownChip.menuWidth - edge;
        if (maxLeft < edge) maxLeft = edge;
        var left =
            _anchorRect.center.dx - AppCategoryDropdownChip.menuWidth / 2;
        if (left < edge) left = edge;
        if (left > maxLeft) left = maxLeft;

        var top = _anchorRect.bottom + gap;
        if (top + menuHeight > screenHeight - edge) {
          final above = _anchorRect.top - gap - menuHeight;
          if (above >= edge) {
            top = above;
          } else {
            top = screenHeight - menuHeight - edge;
            if (top < edge) top = edge;
          }
        }

        return Stack(
          children: [
            // طبقة شفافة تغلق القائمة عند اللمس خارجها.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (mounted) setState(_removeEntry);
                },
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: AppCategoryDropdownChip.menuWidth,
              child: Directionality(
                textDirection: Directionality.of(this.context),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.page,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2616232B),
                          blurRadius: 22,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: listHeight,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              _onScroll();
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.zero,
                              itemExtent: AppCategoryDropdownChip.rowHeight,
                              itemCount: items.length,
                              itemBuilder: (_, index) => _menuRow(items[index]),
                            ),
                          ),
                        ),
                        if (hasOverflow)
                          // مؤشّر "يوجد المزيد أسفل" — يختفي عند الوصول
                          // إلى نهاية القائمة.
                          ValueListenableBuilder<bool>(
                            valueListenable: _canScrollMore,
                            builder: (_, more, _) => AnimatedOpacity(
                              duration: const Duration(milliseconds: 160),
                              opacity: more ? 1 : 0,
                              child: Container(
                                height: 24,
                                width: double.infinity,
                                color: AppTheme.field,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: AppTheme.chevron,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menuRow(AppDropdownItem item) {
    return Material(
      color: item.selected
          ? widget.color.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          item.onTap();
          if (mounted) setState(_removeEntry);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.sMd),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 17,
                color: item.selected ? widget.color : AppTheme.chevron,
              ),
              const SizedBox(width: AppTheme.sSm),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: item.selected
                        ? FontWeight.w900
                        : FontWeight.w600,
                    color: item.selected ? widget.color : AppTheme.body,
                  ),
                ),
              ),
              if (item.count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${item.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: item.selected ? widget.color : AppTheme.muted,
                  ),
                ),
              ],
              if (item.selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 16, color: widget.color),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMenu = widget.items.isNotEmpty;
    final foreground = widget.selected ? Colors.white : widget.color;

    // نفس شكل شريحة الفئة الموحَّدة (بنفس زمن تلوّن التحديد)، مع قسم سهم
    // اختياري.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: widget.selected ? widget.color : AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  12,
                  0,
                  hasMenu ? 4 : 12,
                  0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 16, color: foreground),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.selected ? Colors.white : AppTheme.body,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    // بلا رقم داخل الشريحة — كبقية شرائح الفئات.
                  ],
                ),
              ),
            ),
            if (hasMenu)
              InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(2, 0, 8, 0),
                  child: Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: foreground,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
