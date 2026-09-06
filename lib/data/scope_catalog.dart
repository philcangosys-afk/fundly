/// فهرس الأقسام الموحّد لصفحات: الملخص الشامل، التقارير، الأرشيف.
///
/// الثلاثة تستخدم التسلسل نفسه (القسم ← الأقسام المطلوب إظهارها ←
/// التصفية ← التاريخ ← العنوان)، فتُعرَّف قوائمها هنا مرة واحدة بدل
/// ثلاث قوائم متباينة في ثلاث صفحات.
class ScopeCatalog {
  static const general = 'عام';
  static const personal = 'الالتزامات الشخصية';
  static const shared = 'الالتزامات المشتركة';
  static const people = 'الأفراد والجهات';
  static const delegations = 'التفويضات';
  static const realEstate = 'العقارات';
  static const activities = 'الأنشطة التجارية';
  static const equipment = 'آليات ومعدات';

  /// "عام" أولًا لأنه يشمل الجميع (يُعرض كمستطيل طويل في الأعلى).
  static const scopes = [
    general,
    personal,
    shared,
    people,
    delegations,
    realEstate,
    activities,
    equipment,
  ];

  /// الأقسام المطلوب إظهارها داخل كل قسم رئيسي.
  static const sections = <String, List<String>>{
    personal: [
      'مالية',
      'مستند',
      'التنظيم والمتابعة',
      'أدوية وبيانات وكلمات سر',
      'نمط الحياة',
      'مواقع وأماكن',
      'عهدة مالية',
    ],
    // الالتزامات المشتركة تحتوي فعليًا: جمعية مالية (مالية)،
    // الرحلة/السفر واللقاءات (نمط الحياة)، مشاركات مشتركة (تنظيم
    // ومتابعة) — لا أدوية ولا كلمات سر هنا.
    shared: [
      'مالية',
      'نمط الحياة',
      'التنظيم والمتابعة',
    ],
    people: [
      'الأفراد',
      'الجهات والشركات',
    ],
    delegations: [
      'الالتزامات الشخصية',
      'الالتزامات المشتركة',
      'إدارة الأشخاص والجهات',
      'العقارات/الأنشطة التجارية/المعدات وأخرى',
      'المحافظ والمدفوعات',
      'قوالب المستندات والتقارير والأرشيف',
      'التنبيهات والكلندر ومراكز المتابعة',
      'الإعدادات والتفويضات',
      'كل الأقسام',
    ],
    // العقارات/الأنشطة/المعدات بلا مستوى "أقسام": التصنيف يعرض أنواع
    // الأصل مباشرة (عمارة، فيلا، شقة...) من البيانات نفسها.
  };

  /// الأنواع داخل كل قسم فرعي — **لكل قسم رئيسي جدوله الخاص**، فالتزام
  /// شخصي واشتراك مشترك لا يعرضان القائمة نفسها. المفتاح الخارجي هو
  /// القسم الرئيسي والداخلي هو القسم الفرعي.
  static const typesByScope = <String, Map<String, List<String>>>{
    personal: {
      'مالية': [
        'المصروفات الشخصية',
        'إيراد',
        'تحويل مالي',
        'دين / قرض / سلفة',
        'قسط',
        'غرامة',
      ],
      'مستند': ['مستند'],
      'التنظيم والمتابعة': ['مهمة', 'موعد', 'تفويض'],
      'أدوية وبيانات وكلمات سر': ['أدوية', 'كلمات سر'],
      'نمط الحياة': ['اشتراك', 'مناسبة'],
      'مواقع وأماكن': ['مكان'],
      'عهدة مالية': ['عهدة مالية'],
    },
    // أنواع الالتزامات المشتركة الحقيقية في التطبيق.
    shared: {
      'مالية': ['جمعية مالية'],
      'نمط الحياة': ['الرحلة / السفر', 'اللقاءات'],
      'التنظيم والمتابعة': ['مشاركات مشتركة'],
    },
    people: {
      'الأفراد': ['فرد'],
      'الجهات والشركات': ['جهة'],
    },
  };

  /// أنواع قسم فرعي داخل قسم رئيسي بعينه.
  static List<String> typesFor(String scope, String section) =>
      typesByScope[scope]?[section] ?? const <String>[];

  /// القسم الفرعي الذي ينتمي إليه نوع الإدخال داخل قسمه الرئيسي — عكس
  /// [typesByScope].
  static String sectionForType(
    String scope,
    String entryType, {
    String fallback = '',
  }) {
    final table = typesByScope[scope];
    if (table != null) {
      for (final entry in table.entries) {
        if (entry.value.contains(entryType)) return entry.key;
      }
    }
    // أسماء قديمة قبل توحيد المسميات.
    const legacy = {
      'مصروف': 'مالية',
      'دخل': 'مالية',
      'ديون': 'مالية',
      'اشتراكات': 'نمط الحياة',
      'رحلة': 'نمط الحياة',
      'جمعية': 'مالية',
    };
    final mapped = legacy[entryType];
    if (mapped != null) return mapped;
    final sectionList = sections[scope] ?? const <String>[];
    if (sectionList.contains(fallback)) return fallback;
    return fallback.isEmpty ? 'أخرى' : fallback;
  }

  // ===== قوائم التصفية المشتركة =====
  static const all = 'الكل';

  /// الحالات المعروفة لكل قسم — تُدمج مع الحالات الموجودة فعلًا في
  /// السجلات، فلا تنحصر القائمة في ثلاث حالات مصادفةً.
  static const statusesByScope = <String, List<String>>{
    personal: [
      'نشطة',
      'قيد التنفيذ',
      'مكتملة',
      'مسددة',
      'متأخرة',
      'قريبة الاستحقاق',
      'منتهية',
      'ملغاة',
    ],
    shared: [
      'نشطة',
      'قيد التنفيذ',
      'مكتملة',
      'متأخرة',
      'قريبة الاستحقاق',
      'منتهية',
      'ملغاة',
    ],
    people: ['فرد', 'جهة'],
    delegations: ['نشط', 'مجدول', 'قارب الانتهاء', 'موقوف', 'منتهي'],
    realEstate: ['نشط', 'مؤجر', 'شاغر', 'قيد الصيانة', 'متوقف'],
    activities: ['نشط', 'قيد التأسيس', 'متوقف'],
    equipment: ['نشط', 'قيد الصيانة', 'متوقف'],
  };

  static List<String> statusesFor(String scope) =>
      statusesByScope[scope] ?? const <String>[];

  /// طرق الدفع المعروفة — تُدمج مع الموجود فعلًا في السجلات.
  static const paymentMethods = [
    'كاش',
    'تحويل بنكي',
    'إيداع',
    'بطاقة',
    'شيك',
    'محفظة إلكترونية',
  ];


  static const amountRanges = [
    all,
    'بلا مبلغ',
    'أقل من ١٠٠٠',
    '١٠٠٠ - ٥٠٠٠',
    'أكثر من ٥٠٠٠',
  ];


  static const dateShortcuts = [
    'اليوم',
    'هذا الأسبوع',
    'قبل شهر',
    'قبل شهرين',
    'قبل 3 أشهر',
    'قبل 6 أشهر',
  ];

  /// يحوّل الاختصار إلى مدى تاريخي حقيقي (من، إلى).
  static (DateTime, DateTime) rangeForShortcut(String shortcut) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (shortcut) {
      'اليوم' => (today, today),
      'هذا الأسبوع' => (today.subtract(Duration(days: today.weekday % 7)), today),
      'قبل شهر' => (DateTime(now.year, now.month - 1, now.day), today),
      'قبل شهرين' => (DateTime(now.year, now.month - 2, now.day), today),
      'قبل 3 أشهر' => (DateTime(now.year, now.month - 3, now.day), today),
      'قبل 6 أشهر' => (DateTime(now.year, now.month - 6, now.day), today),
      _ => (today, today),
    };
  }
}
