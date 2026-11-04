import 'package:flutter/material.dart' hide Text, Align;
import '../../l10n/tr_widgets.dart';
import '../../l10n/app_language.dart';

import 'app_design.dart';

/// قالب "الفلتر الرئيسي" (الذي بجانب مربع البحث) — واحد للشاشات الأربع.
///
/// كانت كل شاشة تكتب نافذة فلتر خاصة بها: الشخصية والمشتركة بصفحة كاملة،
/// والأفراد والعقارات بلوح رقائق يُطبَّق فور اللمس. الآن القالب هنا،
/// والشاشة لا تمرّر إلا **الأقسام التي تعنيها وقوائم خياراتها**.

/// أقسام الفلتر. ترتيبها في القائمة التي تمرّرها الشاشة هو ترتيب ظهورها.
enum AppFilterSection {
  mainCategory,
  subCategory,
  date,
  status,
  amount,
  document,
  people,
  delegates,
  place,

  // ===== أقسام فلتر «الالتزامات الشخصية» (حسب الورقة المعتمدة) =====
  /// التاريخ: من، إلى، والفترة ▼ في سطر واحد.
  period,

  /// الحالة ▼ (كل الحالات، الأحدث أولاً، نشط...).
  statusSelect,

  /// المبلغ ▼ (أعلى مبلغًا، أقل مبلغًا، مخصص ← من/إلى).
  amountSelect,

  /// العملة ▼.
  currency,

  /// طريقة الدفع ▼.
  paymentMethod,

  /// المستند: اسم المستند + الفلتر ▼ (قريبة الانتهاء، منتهية).
  documentSelect,

  /// الأدوية ▼ (أدوية اليوم، قادمة، منتهية).
  medicine,

  /// الدين: لي / عليّ.
  debt,

  /// الدين ▼ (بدون، لي، عليّ، الأعلى مطالبة، الأقل مطالبة) — الأفراد والجهات.
  debtSelect,

  /// الصيانة ▼ (على المستأجر، على المؤجر، مناصفة) — العقارات والأنشطة.
  maintenance,

  /// المبلغ: مستطيل لكتابة المبلغ + الفلتر ▼ (قريبة الاستحقاق، مستحقة،
  /// متأخرة) في سطر واحد — الأفراد والجهات.
  dueAmount,

  /// الشيكات ▼ (قريبة الاستحقاق، مستحقة، متأخرة) — العقارات والأنشطة
  /// والمركبات.
  cheques,
}

/// فلتر الشيكات في الفلتر الكبير: استحقاقها.
const kAppFilterChequeStates = <String>[
  'قريبة الاستحقاق',
  'مستحقة',
  'متأخرة',
];

/// فلتر الاستحقاق بجانب المبلغ.
const kAppFilterDueStates = <String>[
  'قريبة الاستحقاق',
  'مستحقة',
  'متأخرة',
];

/// الفترة ▼ في قسم التاريخ.
const kAppFilterPeriods = <String>[
  'اليوم',
  'أمس',
  'غدًا',
  'آخر 7 أيام',
  'بعد أسبوع',
  'آخر 30 يوم',
  'آخر شهرين',
  'آخر 3 أشهر',
  'آخر 6 أشهر',
  'آخر سنة',
  // مخصص: يفتح اختيار من/إلى.
  'مخصص',
];

/// الحالة ▼ — «الأحدث أولاً» ترتيب لا تصفية.
const kAppFilterSelectStatuses = <String>[
  'الأحدث أولاً',
  'نشط',
  'قريبة الاستحقاق',
  'مستحقة',
  'متأخرة',
  'مكتملة',
];

/// المبلغ ▼.
const kAppFilterAmountOrders = <String>['أعلى مبلغًا', 'أقل مبلغًا', 'مخصص'];

/// العملات المعروفة (تُدمج معها عملات السجلات).
const kAppFilterCurrencies = <String>[
  'جنيه سوداني',
  'جنيه مصري',
  'درهم',
  'دولار',
  'دينار بحريني',
  'دينار',
  'ريال',
  'ريال عماني',
  'ريال قطري',
  'روبية باكستانية',
  'روبية هندية',
  'يوان صيني',
  'يورو',
];

/// طريقة الدفع ▼.
const kAppFilterPaymentMethods = <String>[
  'نقدًا',
  'تحويل بنكي',
  'بطاقة بنكية',
  'محفظة إلكترونية',
  'أخرى',
];

/// المستند — الفلتر ▼.
const kAppFilterDocumentFilters = <String>[
  'مستندات قريبة الانتهاء',
  'مستندات منتهية',
];

/// الدين ▼ (للأفراد والجهات).
const kAppFilterDebtOptions = <String>[
  'لي',
  'عليّ',
  'الأعلى مطالبة',
  'الأقل مطالبة',
];

/// الصيانة ▼.
const kAppFilterMaintenanceOptions = <String>[
  'على المستأجر',
  'على المؤجر',
  'مناصفة',
];

/// الأدوية ▼.
const kAppFilterMedicineStates = <String>[
  'أدوية اليوم',
  'أدوية قادمة',
  'أدوية منتهية',
];

/// مدى الفترة المختارة (من، إلى).
(DateTime, DateTime) appFilterPeriodRange(String period) {
  final now = DateUtils.dateOnly(DateTime.now());
  return switch (period) {
    'أمس' => (
      now.subtract(const Duration(days: 1)),
      now.subtract(const Duration(days: 1)),
    ),
    // القادم: غدًا وحده، و«بعد أسبوع» = من اليوم حتى أسبوع قادم.
    'غدًا' => (
      now.add(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    ),
    'بعد أسبوع' => (now, now.add(const Duration(days: 7))),
    'آخر 7 أيام' => (now.subtract(const Duration(days: 6)), now),
    'آخر 30 يوم' => (now.subtract(const Duration(days: 29)), now),
    'آخر شهرين' => (DateTime(now.year, now.month - 2, now.day), now),
    'آخر 3 أشهر' => (DateTime(now.year, now.month - 3, now.day), now),
    'آخر 6 أشهر' => (DateTime(now.year, now.month - 6, now.day), now),
    'آخر سنة' => (DateTime(now.year - 1, now.month, now.day), now),
    _ => (now, now),
  };
}

/// حالات العنصر الموحَّدة في كل الشاشات.
const kAppFilterStatuses = <String>[
  'كل الحالات',
  'المستحق بعد 7 أيام',
  'نشط',
  'مكتمل',
  'متأخر',
  'مؤرشف',
];

/// اختصارات التاريخ السريعة.
const kAppFilterDateShortcuts = <String>[
  'اليوم',
  'هذا الأسبوع',
  'قبل شهر',
  'قبل شهرين',
  'قبل 3 شهور',
  'قبل 6 شهور',
];

/// اختصارات المبلغ السريعة.
const kAppFilterAmountShortcuts = <String>[
  'لي',
  'عليّ',
  'أعلى مبلغ',
  'أقل مبلغ',
];

/// حالات المستند السريعة.
const kAppFilterDocumentStates = <String>['قريب الانتهاء', 'منتهي', 'مسودة'];

/// قيم الفلتر الكبير كاملة.
class AppFilterValues {
  AppFilterValues({
    this.mainCategory = 'الكل',
    this.subCategory,
    this.dateFrom,
    this.dateTo,
    this.status = 'كل الحالات',
    this.amountFrom,
    this.amountTo,
    this.amountShortcut,
    this.documentName = '',
    this.documentState,
    this.personName = '',
    this.personCategory,
    this.delegateName = '',
    this.placeName = '',
    this.datePeriod,
    this.currency,
    this.paymentMethod,
    this.medicineState,
    this.debtDirection,
    this.maintenanceBy,
    this.dueState,
    this.chequeState,
  });

  /// حالة الشيك المختارة في قسم «الشيكات».
  String? chequeState;

  /// الاستحقاق بجانب المبلغ: قريبة الاستحقاق / مستحقة / متأخرة.
  String? dueState;

  String mainCategory;
  String? subCategory;
  DateTime? dateFrom;
  DateTime? dateTo;
  String status;
  num? amountFrom;
  num? amountTo;
  String? amountShortcut;
  String documentName;
  String? documentState;
  String personName;
  String? personCategory;
  String delegateName;
  String placeName;

  /// الفترة ▼ المختارة (للعرض؛ المدى نفسه في [dateFrom]/[dateTo]).
  String? datePeriod;
  String? currency;
  String? paymentMethod;
  String? medicineState;

  /// الدين: «لي» أو «عليّ».
  String? debtDirection;

  /// الصيانة: على المستأجر / على المؤجر / مناصفة.
  String? maintenanceBy;

  /// نسخ كل القيم من [other] إلى هذه.
  void assignFrom(AppFilterValues other) {
    mainCategory = other.mainCategory;
    subCategory = other.subCategory;
    dateFrom = other.dateFrom;
    dateTo = other.dateTo;
    status = other.status;
    amountFrom = other.amountFrom;
    amountTo = other.amountTo;
    amountShortcut = other.amountShortcut;
    documentName = other.documentName;
    documentState = other.documentState;
    personName = other.personName;
    personCategory = other.personCategory;
    delegateName = other.delegateName;
    placeName = other.placeName;
    datePeriod = other.datePeriod;
    currency = other.currency;
    paymentMethod = other.paymentMethod;
    medicineState = other.medicineState;
    debtDirection = other.debtDirection;
    maintenanceBy = other.maintenanceBy;
    dueState = other.dueState;
    chequeState = other.chequeState;
  }

  /// حفظ القيم (للتقارير والأرشيف المحفوظة).
  Map<String, dynamic> toMap() => {
    'mainCategory': mainCategory,
    'subCategory': subCategory,
    'dateFrom': dateFrom?.toIso8601String(),
    'dateTo': dateTo?.toIso8601String(),
    'status': status,
    'amountFrom': amountFrom,
    'amountTo': amountTo,
    'amountShortcut': amountShortcut,
    'documentName': documentName,
    'documentState': documentState,
    'personName': personName,
    'personCategory': personCategory,
    'delegateName': delegateName,
    'placeName': placeName,
    'datePeriod': datePeriod,
    'currency': currency,
    'paymentMethod': paymentMethod,
    'medicineState': medicineState,
    'debtDirection': debtDirection,
    'maintenanceBy': maintenanceBy,
    'dueState': dueState,
    'chequeState': chequeState,
  };

  factory AppFilterValues.fromMap(Map<String, dynamic> map) {
    String? text(String key) {
      final value = map[key];
      if (value == null) return null;
      final out = value.toString();
      return out.isEmpty ? null : out;
    }

    DateTime? date(String key) {
      final value = text(key);
      return value == null ? null : DateTime.tryParse(value);
    }

    num? number(String key) {
      final value = map[key];
      if (value is num) return value;
      return value == null ? null : num.tryParse(value.toString());
    }

    return AppFilterValues(
      mainCategory: text('mainCategory') ?? 'الكل',
      subCategory: text('subCategory'),
      dateFrom: date('dateFrom'),
      dateTo: date('dateTo'),
      status: text('status') ?? 'كل الحالات',
      amountFrom: number('amountFrom'),
      amountTo: number('amountTo'),
      amountShortcut: text('amountShortcut'),
      documentName: text('documentName') ?? '',
      documentState: text('documentState'),
      personName: text('personName') ?? '',
      personCategory: text('personCategory'),
      delegateName: text('delegateName') ?? '',
      placeName: text('placeName') ?? '',
      datePeriod: text('datePeriod'),
      currency: text('currency'),
      paymentMethod: text('paymentMethod'),
      medicineState: text('medicineState'),
      debtDirection: text('debtDirection'),
      maintenanceBy: text('maintenanceBy'),
      dueState: text('dueState'),
      chequeState: text('chequeState'),
    );
  }

  AppFilterValues copy() => AppFilterValues(
    mainCategory: mainCategory,
    subCategory: subCategory,
    dateFrom: dateFrom,
    dateTo: dateTo,
    status: status,
    amountFrom: amountFrom,
    amountTo: amountTo,
    amountShortcut: amountShortcut,
    documentName: documentName,
    documentState: documentState,
    personName: personName,
    personCategory: personCategory,
    delegateName: delegateName,
    placeName: placeName,
    datePeriod: datePeriod,
    currency: currency,
    paymentMethod: paymentMethod,
    medicineState: medicineState,
    debtDirection: debtDirection,
    maintenanceBy: maintenanceBy,
    dueState: dueState,
    chequeState: chequeState,
  );

  /// هل من فلتر **إضافي** مطبَّق؟ (يُستعمل لإظهار مؤشّر على زر الفلتر)
  ///
  /// الفئة الرئيسية مستثناة عمدًا: هي مرئية أصلًا في شريط الفئات، وعدّها
  /// فلترًا كان يُضيء المؤشّر لمجرد اختيار فئة أو حتى فتح النافذة.
  bool get isActive =>
      subCategory != null ||
      dateFrom != null ||
      dateTo != null ||
      status != 'كل الحالات' ||
      amountFrom != null ||
      amountTo != null ||
      amountShortcut != null ||
      documentName.trim().isNotEmpty ||
      documentState != null ||
      personName.trim().isNotEmpty ||
      personCategory != null ||
      delegateName.trim().isNotEmpty ||
      placeName.trim().isNotEmpty ||
      currency != null ||
      paymentMethod != null ||
      medicineState != null ||
      debtDirection != null ||
      maintenanceBy != null ||
      dueState != null ||
      chequeState != null;

  void clear({String defaultMainCategory = 'الكل'}) {
    mainCategory = defaultMainCategory;
    subCategory = null;
    dateFrom = null;
    dateTo = null;
    status = 'كل الحالات';
    amountFrom = null;
    amountTo = null;
    amountShortcut = null;
    documentName = '';
    documentState = null;
    personName = '';
    personCategory = null;
    delegateName = '';
    placeName = '';
    datePeriod = null;
    currency = null;
    paymentMethod = null;
    medicineState = null;
    debtDirection = null;
    maintenanceBy = null;
    dueState = null;
    chequeState = null;
  }

  /// هل يقع هذا التاريخ داخل المدى المختار؟ (فارغ = لا تقييد)
  bool matchesDate(DateTime? date) {
    if (dateFrom == null && dateTo == null) return true;
    if (date == null) return false;
    final day = DateUtils.dateOnly(date);
    if (dateFrom != null && day.isBefore(DateUtils.dateOnly(dateFrom!))) {
      return false;
    }
    if (dateTo != null && day.isAfter(DateUtils.dateOnly(dateTo!))) {
      return false;
    }
    return true;
  }

  /// هل يقع هذا المبلغ داخل المدى المختار؟
  bool matchesAmount(num amount) {
    if (amountFrom != null && amount < amountFrom!) return false;
    if (amountTo != null && amount > amountTo!) return false;
    return true;
  }

  /// مطابقة نصية متسامحة (تتجاهل الفراغات والحالة).
  static bool textMatches(String filter, Iterable<String> fields) {
    final needle = filter.trim();
    if (needle.isEmpty) return true;
    return fields.any((field) => field.trim().contains(needle));
  }
}

/// عنوان قسم داخل نافذة الفلتر.
class AppFilterSectionLabel extends StatelessWidget {
  const AppFilterSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Color(0xFF2C3B38),
        ),
      ),
    );
  }
}

/// تنسيق حقول الإدخال داخل نافذة الفلتر.
InputDecoration appFilterFieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF8C9A97)),
    filled: true,
    fillColor: AppTheme.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      borderSide: const BorderSide(color: Color(0xFF0E7161), width: 1.4),
    ),
  );
}

/// رقاقة اختيار موحَّدة داخل نافذة الفلتر.
class AppFilterChoiceChip extends StatelessWidget {
  const AppFilterChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: color.withValues(alpha: 0.16),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: selected ? color : const Color(0xFF46534F),
      ),
      side: BorderSide(color: selected ? color : const Color(0xFFE4EAE8)),
      showCheckmark: false,
    );
  }
}

/// إعداد فلتر قسم كامل (الشخصية، المشتركة، الأفراد، العقارات...) — يستعمله
/// فلتر الصفحة الرئيسية ليعرض تحت القسم المختار فلترَه نفسه.
class AppFilterModuleConfig {
  const AppFilterModuleConfig({
    required this.sectionsFor,
    this.mainCategories = const [],
    this.subCategoriesFor,
    this.fixedMainCategory,
    this.statuses = kAppFilterStatuses,
    this.selectStatuses = kAppFilterSelectStatuses,
    this.selectStatusesFor,
    this.currencies = kAppFilterCurrencies,
    this.amountShortcuts = kAppFilterAmountShortcuts,
    this.amountShortcutsFor,
    this.personCategories = const [],
    this.documentStates = kAppFilterDocumentStates,
    this.delegatesLabel = 'المفوّضون',
    this.placeLabel = 'المكان',
    this.placeHint = 'اكتب اسم المكان',
  });

  final List<AppFilterSection> Function(String mainCategory) sectionsFor;
  final List<String> mainCategories;
  final List<String> Function(String mainCategory)? subCategoriesFor;

  /// فئة رئيسية ثابتة للقسم (العقارات مثلًا) بلا رقائق فئات.
  final String? fixedMainCategory;
  final List<String> statuses;
  final List<String> selectStatuses;

  /// خيارات «الحالة ▼» حسب الفئة المختارة (تحلّ محلّ [selectStatuses]).
  final List<String> Function(String mainCategory)? selectStatusesFor;
  final List<String> currencies;
  final List<String> amountShortcuts;
  final List<String> Function(String mainCategory, String? subCategory)?
  amountShortcutsFor;
  final List<String> personCategories;
  final List<String> documentStates;
  final String delegatesLabel;
  final String placeLabel;
  final String placeHint;
}

/// يفتح الفلتر الرئيسي الموحَّد.
Future<void> showAppFilterSheet({
  required BuildContext context,
  required String title,
  required Color accent,
  required AppFilterValues values,
  required List<AppFilterSection> sections,
  required ValueChanged<AppFilterValues> onApply,
  List<String> mainCategories = const [],
  List<String> Function(String mainCategory)? subCategoriesFor,
  List<String> statuses = kAppFilterStatuses,
  List<String> amountShortcuts = kAppFilterAmountShortcuts,
  /// خيارات «المبلغ ▼» (أعلى مبلغًا، أقل مبلغًا، مخصص... وما تضيفه الوحدة).
  List<String> amountOrders = kAppFilterAmountOrders,
  /// اختصارات المبلغ المحسوبة من الفئة المختارة داخل الورقة نفسها —
  /// «لي/عليّ» مثلًا تخصّ الديون فقط، فتختفي بمجرد تغيير الفئة هنا.
  List<String> Function(String mainCategory, String? subCategory)?
  amountShortcutsFor,
  List<String> personCategories = const [],
  List<String> documentStates = kAppFilterDocumentStates,
  String defaultMainCategory = 'الكل',
  IconData icon = Icons.tune_rounded,
  /// أقسام تتبع الفئة المختارة **داخل الورقة** (تحلّ محلّ [sections]).
  List<AppFilterSection> Function(String mainCategory)? sectionsFor,
  List<String> selectStatuses = kAppFilterSelectStatuses,
  List<String> Function(String mainCategory)? selectStatusesFor,
  List<String> currencies = kAppFilterCurrencies,
  String delegatesLabel = 'المفوّضون',
  String placeLabel = 'المكان',
  String placeHint = 'اكتب اسم المكان',
  /// فلتر الصفحة الرئيسية: الأقسام أولًا، واختيار قسم يُظهر تحته فلترَه.
  List<String> modules = const [],
  String? initialModule,
  String modulesLabel = 'الأقسام',
  AppFilterModuleConfig? Function(String module)? moduleConfigFor,
  void Function(String module, AppFilterValues values)? onApplyModule,
  /// نص زر التنفيذ في الأسفل («إنشاء تقرير» مثلًا بدل «تطبيق الفلتر»).
  String applyLabel = 'تطبيق الفلتر',
  IconData? applyIcon,
  /// حقول إضافية تظهر في آخر الورقة قبل زر التنفيذ (عنوان التقرير...).
  List<Widget> extraFields = const [],
  String? extraFieldsLabel,
}) {
  final draft = values.copy();
  // القيم الأصلية — تُستبدل داخل الورقة بإعداد القسم المختار إن وُجد.
  final baseMainCategories = mainCategories;
  final baseSubCategoriesFor = subCategoriesFor;
  final baseStatuses = statuses;
  final baseSelectStatuses = selectStatuses;
  final baseSelectStatusesFor = selectStatusesFor;
  final baseCurrencies = currencies;
  final baseAmountShortcuts = amountShortcuts;
  final baseAmountShortcutsFor = amountShortcutsFor;
  final basePersonCategories = personCategories;
  final baseDocumentStates = documentStates;
  final baseDelegatesLabel = delegatesLabel;
  final basePlaceLabel = placeLabel;
  final basePlaceHint = placeHint;
  final baseSections = sections;
  final baseSectionsFor = sectionsFor;
  var activeModule = initialModule ?? (modules.isEmpty ? '' : modules.first);
  final amountFromCtrl = TextEditingController(
    text: draft.amountFrom?.toStringAsFixed(0) ?? '',
  );
  final amountToCtrl = TextEditingController(
    text: draft.amountTo?.toStringAsFixed(0) ?? '',
  );
  final documentCtrl = TextEditingController(text: draft.documentName);
  final personCtrl = TextEditingController(text: draft.personName);
  final delegateCtrl = TextEditingController(text: draft.delegateName);
  final placeCtrl = TextEditingController(text: draft.placeName);
  String? activeDateShortcut;
  // يتغيّر مع كل "مسح الكل" ليُجبر حقل الفئة الفرعية على إعادة البناء،
  // وإلا بقي الاختيار القديم معروضًا بعد المسح.
  var clearEpoch = 0;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          // إعداد القسم المختار (فلتر الصفحة الرئيسية) أو القيم الأصلية.
          final useModules = modules.isNotEmpty;
          final cfg = useModules ? moduleConfigFor?.call(activeModule) : null;
          final mainCategories = useModules
              ? (cfg?.mainCategories ?? const <String>[])
              : baseMainCategories;
          final subCategoriesFor = useModules
              ? cfg?.subCategoriesFor
              : baseSubCategoriesFor;
          final statuses = cfg?.statuses ?? baseStatuses;
          final selectStatuses = cfg?.selectStatuses ?? baseSelectStatuses;
          final selectStatusesFor = useModules
              ? cfg?.selectStatusesFor
              : baseSelectStatusesFor;
          final currencies = cfg?.currencies ?? baseCurrencies;
          final amountShortcuts = cfg?.amountShortcuts ?? baseAmountShortcuts;
          final amountShortcutsFor = useModules
              ? cfg?.amountShortcutsFor
              : baseAmountShortcutsFor;
          final personCategories =
              cfg?.personCategories ?? basePersonCategories;
          final documentStates = cfg?.documentStates ?? baseDocumentStates;
          final delegatesLabel = cfg?.delegatesLabel ?? baseDelegatesLabel;
          final placeLabel = cfg?.placeLabel ?? basePlaceLabel;
          final placeHint = cfg?.placeHint ?? basePlaceHint;
          final List<AppFilterSection> sections = useModules
              ? const <AppFilterSection>[]
              : baseSections;
          final List<AppFilterSection> Function(String)? sectionsFor =
              useModules
              ? (cfg == null
                    ? (String _) => const <AppFilterSection>[]
                    : cfg.sectionsFor)
              : baseSectionsFor;

          // الاختصار المختار يظهر محدَّدًا بدل أن يبدو كأن الضغطة لم تفعل
          // شيئًا؛ ويُلغى تحديده متى غيّر المستخدم التاريخ يدويًا.
          Future<void> pickDate({required bool isFrom}) async {
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate:
                  (isFrom ? draft.dateFrom : draft.dateTo) ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            setSheetState(() {
              activeDateShortcut = null;
              draft.datePeriod = null;
              if (isFrom) {
                draft.dateFrom = picked;
              } else {
                draft.dateTo = picked;
              }
            });
          }

          void applyDateShortcut(String label) {
            final now = DateUtils.dateOnly(DateTime.now());
            final from = switch (label) {
              'اليوم' => now,
              'هذا الأسبوع' => now.subtract(Duration(days: now.weekday % 7)),
              'قبل شهر' => DateTime(now.year, now.month - 1, now.day),
              'قبل شهرين' => DateTime(now.year, now.month - 2, now.day),
              'قبل 3 شهور' => DateTime(now.year, now.month - 3, now.day),
              'قبل 6 شهور' => DateTime(now.year, now.month - 6, now.day),
              _ => now,
            };
            setSheetState(() {
              activeDateShortcut = label;
              draft.dateFrom = from;
              draft.dateTo = now;
            });
          }

          // [compact]: ثلاثة حقول في سطر (من، إلى، الفترة) — بلا أيقونة،
          // والتاريخ يصغر ليظهر كاملًا بدل أن يُقصّ.
          Widget dateButton({required bool isFrom, bool compact = false}) {
            final value = isFrom ? draft.dateFrom : draft.dateTo;
            return Expanded(
              child: InkWell(
                onTap: () => pickDate(isFrom: isFrom),
                borderRadius: BorderRadius.circular(AppTheme.rField),
                child: Container(
                  height: 46,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  decoration: BoxDecoration(
                    color: AppTheme.field,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    children: [
                      if (!compact) ...[
                        Icon(
                          Icons.event_outlined,
                          size: 18,
                          color: value == null ? AppTheme.muted : accent,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                          value == null
                              ? (isFrom ? 'من' : 'إلى')
                              : '${value.day}/${value.month}/${value.year}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: value == null
                                ? AppTheme.muted
                                : AppTheme.title,
                          ),
                        )),
                        ),
                      ),
                      if (value != null) ...[
                        SizedBox(width: compact ? 2 : 4),
                        InkWell(
                          onTap: () => setSheetState(() {
                            draft.datePeriod = null;
                            if (isFrom) {
                              draft.dateFrom = null;
                            } else {
                              draft.dateTo = null;
                            }
                          }),
                          child: Icon(
                            Icons.close_rounded,
                            size: compact ? 14 : 16,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          Widget chipsRow(
            List<String?> options,
            String? current,
            ValueChanged<String?> onPick, {
            String nullLabel = 'الكل',
          }) {
            return Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final option in options)
                  AppFilterChoiceChip(
                    label: option ?? nullLabel,
                    color: accent,
                    selected: current == option,
                    onSelected: () => setSheetState(() => onPick(option)),
                  ),
              ],
            );
          }

          /// سطر «العنوان: [القائمة ▼]» كما في الورقة.
          Widget labeledDropdown({
            required String label,
            required String? value,
            required List<String> options,
            required ValueChanged<String?> onChanged,
            String hint = '—',
          }) {
            final current = options.contains(value) ? value : null;
            return Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2C3B38),
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('dd-$label-$clearEpoch-$current'),
                    initialValue: current,
                    isExpanded: true,
                    decoration: appFilterFieldDecoration(''),
                    hint: Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8C9A97),
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          hint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8C9A97),
                          ),
                        ),
                      ),
                      for (final option in options)
                        DropdownMenuItem<String?>(
                          value: option,
                          child: Text(
                            option,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                    ],
                    onChanged: (value) => setSheetState(() => onChanged(value)),
                  ),
                ),
              ],
            );
          }

          List<Widget> buildSection(AppFilterSection section) {
            switch (section) {
              case AppFilterSection.mainCategory:
                if (mainCategories.isEmpty) return const [];
                return [
                  const AppFilterSectionLabel('الفئات الرئيسية'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final category in mainCategories)
                        AppFilterChoiceChip(
                          label: category,
                          color: accent,
                          selected: draft.mainCategory == category,
                          onSelected: () => setSheetState(() {
                            draft.mainCategory = category;
                            draft.subCategory = null;
                          }),
                        ),
                    ],
                  ),
                ];
              case AppFilterSection.subCategory:
                final options =
                    subCategoriesFor?.call(draft.mainCategory) ??
                    const <String>[];
                if (draft.subCategory != null &&
                    !options.contains(draft.subCategory)) {
                  draft.subCategory = null;
                }
                return [
                  const AppFilterSectionLabel('الفئات الفرعية'),
                  DropdownButtonFormField<String>(
                    // مفتاح مرتبط بالفئة الرئيسية: تغييرها يُعيد بناء الحقل
                    // فيُمحى الاختيار القديم بدل بقائه معروضًا وهو خارج
                    // القائمة الجديدة.
                    key: ValueKey('sub-$clearEpoch-${draft.mainCategory}'),
                    initialValue: draft.subCategory,
                    isExpanded: true,
                    decoration: appFilterFieldDecoration(
                      options.isEmpty
                          ? 'اختر الفئة الرئيسية أولاً'
                          : 'كل الأنواع ضمن الفئة',
                    ),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: options.isEmpty
                        ? null
                        : (value) =>
                              setSheetState(() => draft.subCategory = value),
                  ),
                ];
              case AppFilterSection.date:
                return [
                  const AppFilterSectionLabel('التاريخ'),
                  Row(
                    children: [
                      dateButton(isFrom: true),
                      const SizedBox(width: 8),
                      dateButton(isFrom: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final shortcut in kAppFilterDateShortcuts)
                        AppFilterChoiceChip(
                          label: shortcut,
                          color: accent,
                          selected: activeDateShortcut == shortcut,
                          onSelected: () => applyDateShortcut(shortcut),
                        ),
                    ],
                  ),
                ];
              case AppFilterSection.status:
                return [
                  const AppFilterSectionLabel('الحالة'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final status in statuses)
                        AppFilterChoiceChip(
                          label: status,
                          color: accent,
                          selected: draft.status == status,
                          onSelected: () =>
                              setSheetState(() => draft.status = status),
                        ),
                    ],
                  ),
                ];
              case AppFilterSection.amount:
                return [
                  const AppFilterSectionLabel('المبلغ'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountFromCtrl,
                          keyboardType: TextInputType.number,
                          decoration: appFilterFieldDecoration('من'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: amountToCtrl,
                          keyboardType: TextInputType.number,
                          decoration: appFilterFieldDecoration('إلى'),
                        ),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final shortcuts =
                          amountShortcutsFor?.call(
                            draft.mainCategory,
                            draft.subCategory,
                          ) ??
                          amountShortcuts;
                      // اختصار مختار لم يعد معروضًا يُلغى حتى لا يبقى
                      // فلترًا خفيًا يعمل بلا أن يراه المستخدم.
                      if (draft.amountShortcut != null &&
                          !shortcuts.contains(draft.amountShortcut)) {
                        draft.amountShortcut = null;
                      }
                      if (shortcuts.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: chipsRow(
                          [null, ...shortcuts],
                          draft.amountShortcut,
                          (value) => draft.amountShortcut = value,
                          nullLabel: 'بدون',
                        ),
                      );
                    },
                  ),
                ];
              case AppFilterSection.document:
                return [
                  const AppFilterSectionLabel('المستند'),
                  TextField(
                    controller: documentCtrl,
                    decoration: appFilterFieldDecoration('اكتب اسم المستند'),
                  ),
                  if (documentStates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    chipsRow(
                      [null, ...documentStates],
                      draft.documentState,
                      (value) => draft.documentState = value,
                    ),
                  ],
                ];
              case AppFilterSection.people:
                return [
                  const AppFilterSectionLabel('أفراد وجهات'),
                  TextField(
                    controller: personCtrl,
                    decoration: appFilterFieldDecoration(
                      'اكتب اسم الفرد أو الجهة',
                    ),
                  ),
                  if (personCategories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    chipsRow(
                      [null, ...personCategories],
                      draft.personCategory,
                      (value) => draft.personCategory = value,
                    ),
                  ],
                ];
              case AppFilterSection.delegates:
                return [
                  AppFilterSectionLabel(delegatesLabel),
                  TextField(
                    controller: delegateCtrl,
                    decoration: appFilterFieldDecoration('اكتب اسم المفوَّض'),
                  ),
                ];
              case AppFilterSection.place:
                return [
                  AppFilterSectionLabel(placeLabel),
                  TextField(
                    controller: placeCtrl,
                    decoration: appFilterFieldDecoration(placeHint),
                  ),
                ];
              case AppFilterSection.period:
                return [
                  const AppFilterSectionLabel('التاريخ'),
                  // الفترة أولًا (في جهة اليمين) فتُفتح قائمتها يمينًا.
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey(
                            'period-$clearEpoch-${draft.datePeriod}',
                          ),
                          initialValue:
                              kAppFilterPeriods.contains(draft.datePeriod)
                              ? draft.datePeriod
                              : null,
                          isExpanded: true,
                          decoration: appFilterFieldDecoration(''),
                          hint: const Text(
                            'الفترة',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8C9A97),
                            ),
                          ),
                          items: [
                            for (final period in kAppFilterPeriods)
                              DropdownMenuItem<String?>(
                                value: period,
                                // الكلمات في جهة اليمين داخل القائمة.
                                alignment: AppTr.isEnglish
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: Text(
                                  period,
                                  maxLines: 3,
                                  textAlign: AppTr.isEnglish
                                      ? TextAlign.left
                                      : TextAlign.right,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                          onChanged: (value) async {
                            if (value == 'مخصص') {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(now.year - 20),
                                lastDate: DateTime(now.year + 20),
                                initialDateRange:
                                    draft.dateFrom != null &&
                                        draft.dateTo != null
                                    ? DateTimeRange(
                                        start: draft.dateFrom!,
                                        end: draft.dateTo!,
                                      )
                                    : null,
                              );
                              setSheetState(() {
                                if (picked == null) return;
                                draft.datePeriod = 'مخصص';
                                draft.dateFrom = picked.start;
                                draft.dateTo = picked.end;
                              });
                              return;
                            }
                            setSheetState(() {
                              draft.datePeriod = value;
                              if (value == null) return;
                              final range = appFilterPeriodRange(value);
                              draft.dateFrom = range.$1;
                              draft.dateTo = range.$2;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      dateButton(isFrom: true, compact: true),
                      const SizedBox(width: 6),
                      dateButton(isFrom: false, compact: true),
                    ],
                  ),
                ];
              case AppFilterSection.statusSelect:
                return [
                  labeledDropdown(
                    label: 'الحالة',
                    value: draft.status,
                    options:
                        selectStatusesFor?.call(draft.mainCategory) ??
                        selectStatuses,
                    hint: 'كل الحالات',
                    onChanged: (value) =>
                        draft.status = value ?? 'كل الحالات',
                  ),
                ];
              case AppFilterSection.amountSelect:
                return [
                  labeledDropdown(
                    label: 'المبلغ',
                    value: draft.amountShortcut,
                    options: amountOrders,
                    onChanged: (value) => draft.amountShortcut = value,
                  ),
                  if (draft.amountShortcut == 'مخصص') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 96),
                        Expanded(
                          child: TextField(
                            controller: amountFromCtrl,
                            keyboardType: TextInputType.number,
                            decoration: appFilterFieldDecoration('من'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: amountToCtrl,
                            keyboardType: TextInputType.number,
                            decoration: appFilterFieldDecoration('إلى'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ];
              case AppFilterSection.currency:
                return [
                  labeledDropdown(
                    label: 'العملة',
                    value: draft.currency,
                    options: currencies,
                    onChanged: (value) => draft.currency = value,
                  ),
                ];
              case AppFilterSection.paymentMethod:
                return [
                  labeledDropdown(
                    label: 'طريقة الدفع',
                    value: draft.paymentMethod,
                    options: kAppFilterPaymentMethods,
                    onChanged: (value) => draft.paymentMethod = value,
                  ),
                ];
              case AppFilterSection.documentSelect:
                return [
                  const AppFilterSectionLabel('المستند'),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: documentCtrl,
                          decoration: appFilterFieldDecoration(
                            'اكتب اسم المستند',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey(
                            'docf-$clearEpoch-${draft.documentState}',
                          ),
                          initialValue: kAppFilterDocumentFilters.contains(
                                draft.documentState,
                              )
                              ? draft.documentState
                              : null,
                          isExpanded: true,
                          decoration: appFilterFieldDecoration(''),
                          hint: const Text(
                            'الفلتر',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8C9A97),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'الكل',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            for (final option in kAppFilterDocumentFilters)
                              DropdownMenuItem<String?>(
                                value: option,
                                child: Text(
                                  option,
                                  maxLines: 3,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                          onChanged: (value) => setSheetState(
                            () => draft.documentState = value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ];
              case AppFilterSection.medicine:
                return [
                  labeledDropdown(
                    label: 'الأدوية',
                    value: draft.medicineState,
                    options: kAppFilterMedicineStates,
                    onChanged: (value) => draft.medicineState = value,
                  ),
                ];
              case AppFilterSection.debtSelect:
                return [
                  labeledDropdown(
                    label: 'الدين',
                    value: draft.debtDirection,
                    options: kAppFilterDebtOptions,
                    hint: 'بدون',
                    onChanged: (value) => draft.debtDirection = value,
                  ),
                ];
              case AppFilterSection.maintenance:
                return [
                  labeledDropdown(
                    label: 'الصيانة',
                    value: draft.maintenanceBy,
                    options: kAppFilterMaintenanceOptions,
                    onChanged: (value) => draft.maintenanceBy = value,
                  ),
                ];
              case AppFilterSection.cheques:
                return [
                  labeledDropdown(
                    label: 'الشيكات',
                    value: draft.chequeState,
                    options: kAppFilterChequeStates,
                    onChanged: (value) => draft.chequeState = value,
                  ),
                ];
              case AppFilterSection.dueAmount:
                return [
                  const AppFilterSectionLabel('المبلغ'),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: amountFromCtrl,
                          keyboardType: TextInputType.number,
                          decoration: appFilterFieldDecoration('اكتب المبلغ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey('due-$clearEpoch-${draft.dueState}'),
                          initialValue:
                              kAppFilterDueStates.contains(draft.dueState)
                              ? draft.dueState
                              : null,
                          isExpanded: true,
                          decoration: appFilterFieldDecoration(''),
                          hint: const Text(
                            'الفلتر',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8C9A97),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'الكل',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            for (final option in kAppFilterDueStates)
                              DropdownMenuItem<String?>(
                                value: option,
                                child: Text(
                                  option,
                                  maxLines: 3,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                          onChanged: (value) => setSheetState(
                            () => draft.dueState = value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ];
              case AppFilterSection.debt:
                return [
                  Row(
                    children: [
                      const SizedBox(
                        width: 96,
                        child: Text(
                          'الدين',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2C3B38),
                          ),
                        ),
                      ),
                      for (final direction in const ['لي', 'عليّ']) ...[
                        AppFilterChoiceChip(
                          label: direction,
                          color: accent,
                          selected: draft.debtDirection == direction,
                          onSelected: () => setSheetState(
                            () => draft.debtDirection =
                                draft.debtDirection == direction
                                ? null
                                : direction,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ];
            }
          }

          // الورقة ترتفع فوق لوحة المفاتيح فتبقى حقول الكتابة (الاسم، المكان،
          // عنوان التقرير) ظاهرة أثناء الكتابة.
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: FractionallySizedBox(
            heightFactor: 0.92,
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
                        Icon(icon, color: accent),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF022E2A),
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('app-filter-clear-all'),
                          onPressed: () => setSheetState(() {
                            activeDateShortcut = null;
                            clearEpoch++;
                            draft.clear(
                              defaultMainCategory:
                                  cfg?.fixedMainCategory ??
                                  defaultMainCategory,
                            );
                            amountFromCtrl.clear();
                            amountToCtrl.clear();
                            documentCtrl.clear();
                            personCtrl.clear();
                            delegateCtrl.clear();
                            placeCtrl.clear();
                          }),
                          child: const Text('مسح الكل'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      children: [
                        // فلتر الصفحة الرئيسية: الأقسام بترتيبها، واختيار
                        // قسم يُظهر تحته فلترَه كما في شاشته.
                        if (useModules) ...[
                          AppFilterSectionLabel(modulesLabel),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final module in modules)
                                AppFilterChoiceChip(
                                  label: module,
                                  color: accent,
                                  selected: activeModule == module,
                                  onSelected: () => setSheetState(() {
                                    activeModule = module;
                                    activeDateShortcut = null;
                                    clearEpoch++;
                                    draft.clear(
                                      defaultMainCategory:
                                          moduleConfigFor
                                              ?.call(module)
                                              ?.fixedMainCategory ??
                                          defaultMainCategory,
                                    );
                                    amountFromCtrl.clear();
                                    amountToCtrl.clear();
                                    documentCtrl.clear();
                                    personCtrl.clear();
                                    delegateCtrl.clear();
                                    placeCtrl.clear();
                                  }),
                                ),
                            ],
                          ),
                          if (cfg != null) ...[
                            const SizedBox(height: 14),
                            const Divider(height: 1),
                          ] else ...[
                            // «الكل» بلا فلتر خاص: إرشاد بدل مساحة فارغة.
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'اختر قسمًا لتظهر فلاترُه تحته. «الكل» يعرض كل الأقسام في الصفحة الرئيسية.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                        for (final section
                            in sectionsFor?.call(draft.mainCategory) ??
                                sections) ...[
                          ...buildSection(section),
                          const SizedBox(height: 16),
                        ],
                        if (extraFields.isNotEmpty) ...[
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          if (extraFieldsLabel != null)
                            AppFilterSectionLabel(extraFieldsLabel),
                          for (final field in extraFields) ...[
                            field,
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 6),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        key: const ValueKey('app-filter-apply'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.rField,
                            ),
                          ),
                        ),
                        onPressed: () {
                          draft.amountFrom = num.tryParse(
                            amountFromCtrl.text.trim(),
                          );
                          draft.amountTo = num.tryParse(
                            amountToCtrl.text.trim(),
                          );
                          draft.documentName = documentCtrl.text.trim();
                          draft.personName = personCtrl.text.trim();
                          draft.delegateName = delegateCtrl.text.trim();
                          draft.placeName = placeCtrl.text.trim();
                          if (sectionsFor != null) {
                            final shown = sectionsFor(draft.mainCategory);
                            if (!shown.contains(AppFilterSection.subCategory)) {
                              draft.subCategory = null;
                            }
                            if (!shown.contains(AppFilterSection.statusSelect) &&
                                !shown.contains(AppFilterSection.status)) {
                              draft.status = 'كل الحالات';
                            }
                            if (!shown.contains(AppFilterSection.amountSelect) &&
                                !shown.contains(AppFilterSection.amount)) {
                              draft.amountShortcut = null;
                            }
                            if (!shown.contains(AppFilterSection.currency)) {
                              draft.currency = null;
                            }
                            if (!shown.contains(
                              AppFilterSection.paymentMethod,
                            )) {
                              draft.paymentMethod = null;
                            }
                            if (!shown.contains(
                                  AppFilterSection.documentSelect,
                                ) &&
                                !shown.contains(AppFilterSection.document)) {
                              draft.documentName = '';
                              draft.documentState = null;
                            }
                            if (!shown.contains(AppFilterSection.medicine)) {
                              draft.medicineState = null;
                            }
                            if (!shown.contains(AppFilterSection.debt) &&
                                !shown.contains(AppFilterSection.debtSelect)) {
                              draft.debtDirection = null;
                            }
                            if (!shown.contains(
                              AppFilterSection.maintenance,
                            )) {
                              draft.maintenanceBy = null;
                            }
                            if (!shown.contains(AppFilterSection.dueAmount)) {
                              draft.dueState = null;
                            }
                            if (!shown.contains(AppFilterSection.cheques)) {
                              draft.chequeState = null;
                            }
                            if (!shown.contains(AppFilterSection.people)) {
                              draft.personName = '';
                            }
                            if (!shown.contains(AppFilterSection.delegates)) {
                              draft.delegateName = '';
                            }
                            if (!shown.contains(AppFilterSection.place)) {
                              draft.placeName = '';
                            }
                          }
                          // «من/إلى» للمبلغ لا تعمل إلا مع «مخصص».
                          if ((sectionsFor?.call(draft.mainCategory) ??
                                      sections)
                                  .contains(AppFilterSection.amountSelect) &&
                              draft.amountShortcut != 'مخصص') {
                            draft.amountFrom = null;
                            draft.amountTo = null;
                          }
                          // «اكتب المبلغ»: مطابقة المبلغ نفسه.
                          if ((sectionsFor?.call(draft.mainCategory) ??
                                  sections)
                              .contains(AppFilterSection.dueAmount)) {
                            draft.amountTo = draft.amountFrom;
                          }
                          if (useModules && onApplyModule != null) {
                            onApplyModule(activeModule, draft.copy());
                          } else {
                            onApply(draft.copy());
                          }
                          Navigator.of(sheetContext).pop();
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (applyIcon != null) ...[
                              Icon(applyIcon, color: Colors.white, size: 19),
                              const SizedBox(width: 7),
                            ],
                            Text(
                              applyLabel,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
    ),
  ).whenComplete(() {
    amountFromCtrl.dispose();
    amountToCtrl.dispose();
    documentCtrl.dispose();
    personCtrl.dispose();
    delegateCtrl.dispose();
    placeCtrl.dispose();
  });
}
