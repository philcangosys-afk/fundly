import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';
import '../../data/fundly_auth.dart';

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
  // مصدرها الوحيد شعار Fundly: الأخضر العميق لجسم الحرف، والبرتقالي
  // للشريط المتموّج داخله. لا هوية لونية ثالثة في التطبيق — فقط رمادي
  // محايد مائل للأخضر للنصوص والخلفيات، وأحمر واحد للخطر. هكذا تبدو كل
  // الشاشات من تطبيق واحد بدل خمسة ألوان متنافرة في الصفحة الواحدة.

  // --- الأخضر: لون الهوية ---
  /// الأساسي: الأزرار الممتلئة، التبويب المحدد، الأرقام المهمة.
  static const brand = Color(0xFF0A5A50);

  /// أغمق درجة للنصوص فوق الخلفيات الفاتحة وللضغط على الأزرار.
  static const brandDark = Color(0xFF04413B);

  /// شبه أسود بمسحة خضراء — لون العناوين الرئيسية.
  static const brandDeep = Color(0xFF022E2A);

  /// درجة وسطى للأيقونات والحالات الإيجابية.
  static const brandMid = Color(0xFF0E7161);

  /// درجة فاتحة للرسوم والتدرجات.
  static const brandLight = Color(0xFF178F7B);

  /// تظليل خفيف: خلفية الشرائح المحددة.
  static const brandTint = Color(0xFFD9EDE8);

  /// أخف تظليل: خلفية البطاقات المميزة.
  static const brandSoft = Color(0xFFE9F4F1);

  // --- البرتقالي: لون التمييز، بشحّ ---
  /// للتنبيه والتمييز فقط (لا يُستعمل كلون أساسي حتى لا يطغى).
  static const gold = Color(0xFFCE8422);
  static const goldDark = Color(0xFFA6691A);
  static const goldLight = Color(0xFFF2A93F);
  static const goldSoft = Color(0xFFFDEFDC);

  // --- الأسطح ---
  /// خلفية الصفحة: بيضاء، فتبرز البطاقات فوقها.
  static const page = Color(0xFFFFFFFF);

  /// البطاقة الخارجية — رمادي بمسحة خضراء خفيفة من الهوية.
  static const surface = Color(0xFFEDF2F0);

  /// بطاقة داخلية تقع داخل بطاقة خارجية.
  static const surfaceInner = Color(0xFFFFFFFF);

  /// حقول الإدخال والمناطق الخفيفة.
  static const field = Color(0xFFF3F7F6);

  /// خط فاصل رفيع (يُستعمل بشحّ — التصميم يعتمد على الكتل لا الحدود).
  static const line = Color(0xFFE1E9E6);

  /// خلفية بطاقات التفاصيل في كل الوحدات (الالتزامات الشخصية والمشتركة
  /// والأفراد والعقارات): رمادي بمسحة خضراء خفيفة من الهوية — لا بيج.
  static const paper = Color(0xFFEDF2F0);

  /// خط فاصل شعري داخل البطاقات.
  static const hairline = Color(0xFFD6E2E0);

  // --- النصوص ---
  static const title = Color(0xFF0F1F1C);
  static const body = Color(0xFF46534F);
  static const muted = Color(0xFF8C9A97);
  static const chevron = Color(0xFF76837F);

  // --- أسماء متوافقة مع الكود القائم (تشير إلى الهوية الجديدة) ---
  static const accent = brand;
  static const accentDark = brandDark;
  static const accentSoft = brandSoft;

  // --- الدلالات ---
  static const danger = Color(0xFFC4392E);
  static const dangerSoft = Color(0xFFFBE7E4);
  static const success = brandMid;
  static const successSoft = brandSoft;
  static const warning = goldDark;
  static const warningSoft = goldSoft;

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

  // ===== سلّم أحجام الخط =====
  // ست درجات فقط لكل التطبيق. أي نص جديد يأخذ إحداها ولا يخترع مقاسًا
  // بينها — هذا ما يجعل الشاشات تبدو من تطبيق واحد.
  static const fsMicro = 10.0; // شارات صغيرة داخل حبّات
  static const fsCaption = 11.0; // تسميات وشروح تحت العناصر
  static const fsSmall = 12.0; // نص ثانوي وأرقام مساعدة
  static const fsBody = 13.0; // النص الأساسي
  static const fsRow = 15.0; // عنوان صف أو بطاقة
  static const fsTitle = 17.0; // عنوان قسم
  static const fsDisplay = 20.0; // عنوان صفحة أو رقم بارز

  // ===== النصوص =====
  static const cardTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: title,
    height: 1.25,
  );

  static const sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w900,
    color: title,
    height: 1.25,
  );

  static const rowTitle = TextStyle(
    fontSize: 15,
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
    // خط واحد لكل التطبيق: يمنع اختلاف شكل الحروف بين الأجهزة.
    fontFamily: 'Cairo',
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
      // الحقل النشط يتوهّج ببرتقالي الشعار: لون الانتباه في التطبيق.
      focusedBorder: fieldBorder(AppTheme.gold, 1.6),
      errorBorder: fieldBorder(AppTheme.danger, 1.2),
      focusedErrorBorder: fieldBorder(AppTheme.danger, 1.4),
      hintStyle: const TextStyle(
        color: AppTheme.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: const TextStyle(
        color: AppTheme.body,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppTheme.goldDark,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      helperStyle: const TextStyle(color: AppTheme.muted, fontSize: 11),
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
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accentDark,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
      selectedColor: AppTheme.brandTint,
      checkmarkColor: AppTheme.gold,
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
      color: AppTheme.gold,
    ),
    // زر الإجراء العائم: برتقالي الشعار في كل الشاشات — فهو "الفعل"
    // الأبرز في الصفحة، والأخضر يبقى للبنية والأزرار داخل النماذج.
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppTheme.gold,
      foregroundColor: Colors.white,
      elevation: 6,
      focusElevation: 6,
      hoverElevation: 6,
      highlightElevation: 6,
      extendedTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
    // التبويبات: النص أخضر والخط تحته برتقالي.
    tabBarTheme: const TabBarThemeData(
      labelColor: AppTheme.brand,
      unselectedLabelColor: AppTheme.muted,
      indicatorColor: AppTheme.gold,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
/// نافذة تأكيد موحّدة لكل إجراءات قائمة النقاط الثلاث في التطبيق:
/// لا يُنفَّذ إجراء (أرشفة، مشاركة، تعديل، حذف…) قبل موافقة صريحة.
/// الاسم المركّب على سطرين: الكلمة الأولى في سطر والباقي تحتها —
/// «الحركة المالية» ← «الحركة» / «المالية». الاسم المفرد يبقى سطرًا واحدًا.
///
/// هذه قاعدة أسماء الفئات والتبويبات: كسر ثابت بين الكلمات بدل أن يقرّر
/// عرض الشاشة أين ينكسر الاسم (أو يقصّه بثلاث نقاط).
String twoLineLabel(String label) {
  final text = AppTr.tr(label).trim();
  if (text.contains(' / ')) return text.replaceFirst(' / ', ' /\n');
  final words = text.split(RegExp(r'\s+'));
  if (words.length < 2) return text;
  if (words.length == 2) return '${words[0]}\n${words[1]}';
  // ثلاث كلمات فأكثر: الكسر عند المسافة الأقرب لمنتصف الطول.
  var best = 1;
  var bestDiff = 1 << 30;
  for (var i = 1; i < words.length; i++) {
    final left = words.sublist(0, i).join(' ').length;
    final right = words.sublist(i).join(' ').length;
    final diff = (left - right).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  return '${words.sublist(0, best).join(' ')}\n'
      '${words.sublist(best).join(' ')}';
}

/// رأس قسم قابل للإضافة: العنوان (ومعه إجماليه) في أوّل السطر، وزر + في
/// آخره، وتحتهما خط رصاصي رفيع.
///
/// هذا هو الشكل الموحّد لكل قسم في التطبيق يمكن أن يُضاف إليه شيء —
/// المصروفات، الدخل الإضافي، المستندات، المتابعات — بدل أن يخترع كل قسم
/// ترتيبه الخاص لزر الإضافة.
/// سهم فلتر صغير في رأس القسم: «الكل» ثم الأنواع (مهمة، موعد...) — نفس
/// الشكل في كل شاشات التطبيق.
class AppKindFilterButton extends StatelessWidget {
  const AppKindFilterButton({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.accent,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.brand;
    return PopupMenuButton<String>(
      tooltip: AppTr.tr('تصفية حسب النوع'),
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in ['الكل', ...options])
          PopupMenuItem<String>(
            value: option,
            child: Directionality(
              textDirection: AppTr.uiDir,
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: option == value
                      ? FontWeight.w900
                      : FontWeight.w600,
                  color: option == value ? color : AppTheme.title,
                ),
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.rIcon),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: AppTr.uiDir,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class AppSectionAddRow extends StatelessWidget {
  const AppSectionAddRow({
    super.key,
    required this.title,
    this.onAdd,
    this.icon,
    this.accent,
    this.trailingText = '',
    this.showDivider = true,
    this.actionIcon = Icons.add_rounded,
    this.count,
    this.filter,
  });

  /// سهم فلتر بجانب زر + (مثل [AppKindFilterButton]).
  final Widget? filter;

  /// عدد يظهر ملاصقًا للعنوان نفسه («المستندات 3») لا في آخر السطر.
  final int? count;

  /// نص العنوان، ويصلح أن يحمل الإجمالي معه: «إجمالي المصروفات: 0.00».
  final String title;

  /// أيقونة الزر — + افتراضًا، و× في نموذج مفتوح يُغلق من رأسه.
  final IconData actionIcon;

  /// اضغط + . تمرير null يخفي الزر.
  final VoidCallback? onAdd;

  final IconData? icon;
  final Color? accent;

  /// نص صغير قبل زر الإضافة (عدد العناصر مثلًا).
  final String trailingText;

  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppTheme.title),
                const SizedBox(width: 8),
              ],
              // سطران عند اللزوم بدل قصّ العنوان بثلاث نقاط.
              if (count == null)
                Expanded(
                  child: Text(
                    title,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                )
              else
                // العنوان وعدده معًا في جهة، و«+» في آخر السطر (يسارًا).
                // كان Flexible + Spacer يقتسمان الفراغ فيقع «+» في الوسط.
                Expanded(
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          textAlign: AppTr.alignEnd,
                          maxLines: 2,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTheme.rPill),
                        ),
                        child: Text(
                          '$count',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (trailingText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  trailingText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
                ),
              ],
              if (filter != null) ...[
                const SizedBox(width: 8),
                filter!,
              ],
              if (onAdd != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                  // الضيف يُطلب منه تسجيل الدخول قبل أي إضافة.
                  onTap: () async {
                    if (await FundlyAuth.requireLogin(context)) onAdd!();
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.rIcon),
                    ),
                    child: Icon(actionIcon, size: 20, color: color),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showDivider) Container(height: 1, color: AppTheme.hairline),
      ],
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
        ),
        title: Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF022E2A),
          ),
        ),
        content: Text(
          message,
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppTheme.danger : AppTheme.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

class AppDetailsCard extends StatelessWidget {
  const AppDetailsCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
    this.onAdd,
    this.addTooltip = 'إضافة',
    this.showHeader = true,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  /// إخفاء ترويسة البطاقة حين يكون عنوان القسم فوقها يحمل الاسم نفسه.
  final bool showHeader;

  /// زر «+» في نهاية ترويسة البطاقة — يظهر فقط عند تمرير إجراء له.
  final VoidCallback? onAdd;
  final String addTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppTheme.sSm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  style: const TextStyle(
                    color: Color(0xFF022E2A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onAdd != null)
                Tooltip(
                  message: AppTr.tr(addTooltip),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                    onTap: onAdd,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(AppTheme.rIcon),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.sSm),
          const Divider(height: 1, thickness: 1, color: AppTheme.hairline),
          const SizedBox(height: AppTheme.sSm),
          ],
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
    this.singleLine = false,
    this.valueDirection,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final bool showDivider;

  /// القيمة في سطر واحد تصغر لتتسع (الاسم مثلًا) بدل أن تنكسر لسطرين.
  final bool singleLine;

  /// اتجاه القيمة نفسها (اسم عربي من اليمين، ولاتيني من اليسار).
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.sMd),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.hairline, width: 0.8),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF8C9A97)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5C6B68),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (singleLine)
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  textDirection: valueDirection,
                  style: TextStyle(
                    color: valueColor ?? const Color(0xFF1C2C29),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                textDirection: valueDirection,
                style: TextStyle(
                  color: valueColor ?? const Color(0xFF1C2C29),
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
          maxLines: 3,
          style: TextStyle(
            fontSize: 12,
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
/// داخل مستطيل الوحدة الملوّن: البطاقات بيضاء بحد واضح حتى لا تذوب في
/// لون الخلفية.
class ModuleTintScope extends InheritedWidget {
  const ModuleTintScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModuleTintScope>() != null;

  @override
  bool updateShouldNotify(ModuleTintScope oldWidget) => false;
}

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
        textDirection: AppTr.uiDir,
        child: Material(
          color:
              background ??
              (ModuleTintScope.of(context) ? Colors.white : AppTheme.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            side: ModuleTintScope.of(context)
                ? const BorderSide(color: AppTheme.hairline)
                : BorderSide.none,
          ),
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
      textDirection: AppTr.uiDir,
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
                        maxLines: 3,
                        style: AppTheme.rowTitle,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 4,
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
      textDirection: AppTr.uiDir,
      child: Row(
        children: [
          // شريط برتقالي رفيع يسبق كل عنوان قسم: توقيع الهوية المتكرر
          // في كل الشاشات، ويفصل العناوين بصريًا عن النص تحتها.
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsetsDirectional.only(end: 8),
            decoration: BoxDecoration(
              color: AppTheme.gold,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
          ),
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
        : Tooltip(message: AppTr.tr(tooltip!), child: button);

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
              maxLines: 3,
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
                  color: selected ? AppTheme.goldLight : color,
                ),
                const SizedBox(width: 6),
                // بلا رقم داخل الشريحة: العدد يظهر في رأس القائمة أسفلها
                // ("١٢ جميع الالتزامات")، فكتابته هنا أيضًا تكرار يزاحم
                // الاسم ويجعل الشرائح بأعرض مختلفة بلا داعٍ.
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.body,
                    fontSize: 11,
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
    this.keepStatSlots = false,
    this.subtitleMaxLines = 1,
    this.titleMaxLines = 1,
    this.statsMaxLines = 1,
    this.footer,
    this.statsHeader,
    this.titleSingleLine = false,
    this.statsSingleLine = false,
  });

  /// كل قيمة في عمود الإحصاءات في سطر واحد (يصغر الخط إن طالت) بدل نزول
  /// آخر كلمة إلى سطر ثانٍ.
  final bool statsSingleLine;

  /// العنوان في سطر واحد دائمًا (يصغر الخط إن طال) بدل نزوله أسطرًا.
  final bool titleSingleLine;

  /// سطر إضافي تحت العنوان الفرعي (مثل الدور في العهدة).
  final Widget? footer;

  /// فوق عمود الأرقام (حالة ملوّنة مثل «نشطة» / «ملغاة» فوق المبلغ).
  final Widget? statsHeader;

  /// أسطر كل قيمة في عمود الإحصاءات: 2 لتظهر الجملة كاملة بلا قصّ.
  final int statsMaxLines;

  /// سطرا العنوان الفرعي عند الحاجة («رحلة سفر» ثم «دفعة مقطوعة»).
  final int subtitleMaxLines;

  /// سطرا العنوان عند الحاجة: الاسم الثلاثي مع القبيلة لا يسع سطرًا واحدًا،
  /// وكان يُقصّ بثلاث نقاط فلا يُعرف صاحب البطاقة من القائمة.
  final int titleMaxLines;

  /// تبقى الخانة الفارغة مكانها بدل أن يصعد ما بعدها إلى السطر الأول —
  /// فالتاريخ يبقى على مستوى السطر الثاني حتى لو لم يكن هناك مبلغ.
  final bool keepStatSlots;

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
    final visibleStats = keepStatSlots
        ? stats.take(2).toList(growable: false)
        : stats
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
            textDirection: AppTr.uiDir,
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
                          child: titleSingleLine
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.title,
                                    ),
                                  ),
                                )
                              : Text(
                                  title,
                                  maxLines: (titleMaxLines) + 2,
                                  style: const TextStyle(
                                    fontSize: 13,
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
                      maxLines: (subtitleMaxLines) + 2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: iconColor,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 5),
                      footer!,
                    ],
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
                      if (statsHeader != null) ...[
                        statsHeader!,
                        const SizedBox(height: 6),
                      ],
                      _statText(
                        visibleStats.first,
                        const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      if (visibleStats.length > 1) ...[
                        const SizedBox(height: 6),
                        _statText(
                          visibleStats[1],
                          const TextStyle(
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

/// قيمة في عمود الإحصاءات: سطر واحد مصغَّر عند [AppEntityCard.statsSingleLine].
extension on AppEntityCard {
  Widget _statText(String value, TextStyle style) => statsSingleLine
      ? FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, maxLines: 1, softWrap: false, style: style),
        )
      : Text(
          value,
          maxLines: (statsMaxLines) + 2,
          softWrap: true,
          style: style,
        );
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
                          color: Color(0x260F1F1C),
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
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 12,
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
                    // اسم من سطرين: يُكتب بفاصل سطر في النص نفسه.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (final line in widget.label.split('\n'))
                          Text(
                            line,
                            style: TextStyle(
                              color: widget.selected
                                  ? Colors.white
                                  : AppTheme.body,
                              fontSize: 11,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
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


/// حوار نصّي صغير يملك متحكّمه ويتخلّص منه بنفسه.
///
/// التخلّص من TextEditingController مباشرة بعد `showDialog` يجعل الحقل
/// يستعمل متحكّمًا محرَّرًا أثناء حركة إغلاق النافذة، فيسقط التطبيق برسالة
/// «A TextEditingController was used after being disposed». هنا المتحكّم
/// مملوك لـ State ويُحرَّر في dispose الخاصة به بعد انتهاء الحركة.
Future<String?> askTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialText = '',
  String confirmLabel = 'إضافة',
  String cancelLabel = 'إلغاء',
}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _AskTextDialog(
      title: title,
      label: label,
      initialText: initialText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog({
    required this.title,
    required this.label,
    required this.initialText,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String label;
  final String initialText;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        backgroundColor: AppTheme.page,
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textDirection: AppTr.uiDir,
          decoration: InputDecoration(labelText: AppTr.tr(widget.label)),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.cancelLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

/// مرفق مختار في نموذج: الزر نفسه، وبجانبه زر «حذف» يزيل الاختيار، فيُرفع
/// غيره بدل الخطأ. قبل الاختيار يظهر الزر وحده كما هو.
class AppRemovableAttachment extends StatelessWidget {
  const AppRemovableAttachment({
    super.key,
    required this.child,
    required this.attached,
    required this.onRemove,
  });

  final Widget child;
  final bool attached;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (!attached) return child;
    return Row(
      textDirection: AppTr.uiDir,
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        Tooltip(
          message: AppTr.tr('حذف المستند'),
          child: Material(
            color: AppTheme.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.rField),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 21,
                  color: AppTheme.danger,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// نص من عدة أسطر داخل مساحة ثابتة (مربع أو صف بارتفاع محدد): يلتفّ
/// على عرض المساحة، وإن لم يتسع ارتفاعها صُغِّر كله حتى يظهر كاملًا —
/// لا كلمة مقصوصة ولا «...».
class AppFitText extends StatelessWidget {
  const AppFitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
          child: Text(text, textAlign: textAlign, softWrap: true, style: style),
        ),
      ),
    );
  }
}
