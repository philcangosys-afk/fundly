import 'package:flutter/material.dart';

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
}

/// حالات العنصر الموحَّدة في كل الشاشات.
const kAppFilterStatuses = <String>[
  'كل الحالات',
  'المستحق بعد 7 أيام',
  'نشط',
  'مكتمل',
  'متأخر',
  'ملغاة',
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
  });

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
      placeName.trim().isNotEmpty;

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
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF334155),
        ),
      ),
    );
  }
}

/// تنسيق حقول الإدخال داخل نافذة الفلتر.
InputDecoration appFilterFieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.4),
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
        color: selected ? color : const Color(0xFF475569),
      ),
      side: BorderSide(color: selected ? color : const Color(0xFFE2E8F0)),
      showCheckmark: false,
    );
  }
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
  List<String> personCategories = const [],
  List<String> documentStates = kAppFilterDocumentStates,
  String defaultMainCategory = 'الكل',
  IconData icon = Icons.tune_rounded,
}) {
  final draft = values.copy();
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
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
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

          Widget dateButton({required bool isFrom}) {
            final value = isFrom ? draft.dateFrom : draft.dateTo;
            return Expanded(
              child: InkWell(
                onTap: () => pickDate(isFrom: isFrom),
                borderRadius: BorderRadius.circular(AppTheme.rField),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.field,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 18,
                        color: value == null ? AppTheme.muted : accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          value == null
                              ? (isFrom ? 'من' : 'إلى')
                              : '${value.day}/${value.month}/${value.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: value == null
                                ? AppTheme.muted
                                : AppTheme.title,
                          ),
                        ),
                      ),
                      if (value != null)
                        InkWell(
                          onTap: () => setSheetState(() {
                            if (isFrom) {
                              draft.dateFrom = null;
                            } else {
                              draft.dateTo = null;
                            }
                          }),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppTheme.muted,
                          ),
                        ),
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
                  if (amountShortcuts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    chipsRow(
                      [null, ...amountShortcuts],
                      draft.amountShortcut,
                      (value) => draft.amountShortcut = value,
                      nullLabel: 'بدون',
                    ),
                  ],
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
                  const AppFilterSectionLabel('المفوّضون'),
                  TextField(
                    controller: delegateCtrl,
                    decoration: appFilterFieldDecoration('اكتب اسم المفوَّض'),
                  ),
                ];
              case AppFilterSection.place:
                return [
                  const AppFilterSectionLabel('المكان'),
                  TextField(
                    controller: placeCtrl,
                    decoration: appFilterFieldDecoration('اكتب اسم المكان'),
                  ),
                ];
            }
          }

          return FractionallySizedBox(
            heightFactor: 0.92,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
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
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('app-filter-clear-all'),
                          onPressed: () => setSheetState(() {
                            activeDateShortcut = null;
                            clearEpoch++;
                            draft.clear(
                              defaultMainCategory: defaultMainCategory,
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
                        for (final section in sections) ...[
                          ...buildSection(section),
                          const SizedBox(height: 16),
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
                          onApply(draft.copy());
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text(
                          'تطبيق الفلتر',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
