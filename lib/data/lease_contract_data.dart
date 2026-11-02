import 'dart:convert';

/// نموذج عقد الإيجار الكامل — بكل أقسام العقد الرسمي (توثيق أبوظبي):
/// بيانات العقد، بيانات العقار، المؤجر، المستأجر، ممثل المستأجر، التأمين
/// على العين، وطريقة سداد دفعات الإيجار.
///
/// **لا تعديل على قاعدة البيانات**: كل هذا يُخزَّن نصًا داخل عمود
/// `notes` الموجود أصلًا في جدول عقود الوحدات (`property_unit_contracts`)
/// على شكل JSON بعلامة `__lease__`. أي عقد قديم كانت ملاحظاته نصًا عاديًا
/// يُقرأ كما هو ويوضع في حقل «ملاحظات» بلا فقد.
class LeaseFieldSpec {
  const LeaseFieldSpec(
    this.key,
    this.label, {
    this.numeric = false,
    this.date = false,
    this.multiline = false,
    this.options = const <String>[],
    this.chequeOnly = false,
    this.customReminderOnly = false,
    this.time = false,
    this.hideForCheque = false,
  });

  /// يختفي مع «شيك»: تاريخ الشيك يحلّ محلّه (تاريخ الاستحقاق).
  final bool hideForCheque;

  /// نسخة بعنوان آخر (لإضافة نجمة الحقل الإلزامي مثلًا).
  LeaseFieldSpec withLabel(String newLabel) => LeaseFieldSpec(
    key,
    newLabel,
    numeric: numeric,
    date: date,
    multiline: multiline,
    options: options,
    chequeOnly: chequeOnly,
    customReminderOnly: customReminderOnly,
    time: time,
    hideForCheque: hideForCheque,
  );

  /// حقل ساعة (من الساعة / إلى الساعة).
  final bool time;

  /// لا يظهر إلا إن كانت طريقة التحصيل «شيك».
  final bool chequeOnly;

  /// لا يظهر إلا إن كان التذكير «مخصص».
  final bool customReminderOnly;

  final String key;
  final String label;
  final bool numeric;
  final bool date;
  final bool multiline;

  /// قائمة خيارات ثابتة (تظهر كقائمة منسدلة بدل حقل حر).
  final List<String> options;
}

class LeaseContractData {
  LeaseContractData({
    Map<String, String>? contract,
    Map<String, String>? property,
    Map<String, String>? lessor,
    Map<String, String>? tenant,
    Map<String, String>? representative,
    Map<String, String>? license,
    List<Map<String, String>>? deposits,
    List<Map<String, String>>? payments,
    List<Map<String, String>>? adminFees,
    this.note = '',
  })  : contract = Map<String, String>.from(contract ?? const {}),
        property = Map<String, String>.from(property ?? const {}),
        lessor = Map<String, String>.from(lessor ?? const {}),
        tenant = Map<String, String>.from(tenant ?? const {}),
        representative =
            Map<String, String>.from(representative ?? const {}),
        license = Map<String, String>.from(license ?? const {}),
        deposits = (deposits ?? const <Map<String, String>>[])
            .map((e) => Map<String, String>.from(e))
            .toList(growable: true),
        payments = (payments ?? const <Map<String, String>>[])
            .map((e) => Map<String, String>.from(e))
            .toList(growable: true),
        adminFees = (adminFees ?? const <Map<String, String>>[])
            .map((e) => Map<String, String>.from(e))
            .toList(growable: true);

  final Map<String, String> contract;
  final Map<String, String> property;
  final Map<String, String> lessor;
  final Map<String, String> tenant;
  final Map<String, String> representative;

  /// بيانات الرخصة — في عقد إيجار النشاط التجاري مكان «بيانات العقار».
  final Map<String, String> license;
  final List<Map<String, String>> deposits;
  final List<Map<String, String>> payments;

  /// رسوم إدارية: رسوم تسجيل العقد والتوثيق والخدمات والعمولة. تُسجَّل
  /// مستقلة عن الإيجار لأنها تُدفع مرة واحدة عند التوقيع ولا تتكرر معه،
  /// وقد تدخل في إجمالي العقد أو تبقى خارجه بحسب الاتفاق.
  final List<Map<String, String>> adminFees;
  String note;

  // ===== مفاتيح مستعملة في الكود (بقية المفاتيح نصية كما في الواجهة) =====
  static const kStartDate = 'تاريخ بداية العقد';
  static const kEndDate = 'تاريخ نهاية العقد';
  static const kValue = 'قيمة عقد الإيجار';
  static const kInstallments = 'عدد الدفعات';
  static const kPurpose = 'الغرض من الإيجار';

  /// محل العقد: «مركبة» لعقود تأجير المركبات (بلا ممثل مستأجر ولا «الغرض
  /// من الإيجار»، وبيانات المركبة مكان بيانات العقار).
  static const kSubject = 'محل العقد';
  static const subjectVehicle = 'مركبة';

  bool get isVehicle => (contract[kSubject] ?? '').trim() == subjectVehicle;

  /// حقول عقد تأجير المركبة: حقول العقد نفسها بلا «الغرض من الإيجار».
  /// عقد المركبات: نمط المدة يشمل «بالساعات»، وتحت التاريخين «من الساعة»
  /// و«إلى الساعة».
  static List<LeaseFieldSpec> get vehicleContractFields {
    LeaseFieldSpec of(String key) =>
        contractFields.firstWhere((field) => field.key == key);
    // الرقمان جنب بعض أولًا، ثم نمط المدة سطرًا كاملًا، ثم التاريخان في
    // سطر وتحت كلٍّ ساعته.
    return [
      of(kNewNo),
      of(kOldNo),
      const LeaseFieldSpec(
        kTermMode,
        'نمط مدة الإيجار',
        options: vehicleTermModes,
      ),
      of(kStartDate),
      of(kEndDate),
      const LeaseFieldSpec(kStartTime, 'من الساعة', time: true),
      const LeaseFieldSpec(kEndTime, 'إلى الساعة', time: true),
    ];
  }

  // ===== شروط تأجير المركبة: تُحفظ في بيانات العقد نفسه =====
  static const kTermsLocation = 'موقع التأجير';
  static const kTermsMaintenanceOn = 'الصيانة على';
  static const kTermsFuelOn = 'الوقود على';
  static const kTermsTransportOn = 'نقل المركبة على';
  static const kTermsPhone = 'رقم التواصل';
  static const kTermsNotes = 'شروط التأجير';
  static const termsParties = <String>['على المؤجر', 'على المستأجر'];

  static const vehicleTermsFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kTermsLocation, 'موقع التأجير / المشروع'),
    LeaseFieldSpec(kTermsPhone, 'رقم التواصل', numeric: true),
    LeaseFieldSpec(kTermsMaintenanceOn, 'الصيانة على', options: termsParties),
    LeaseFieldSpec(kTermsFuelOn, 'الوقود على', options: termsParties),
    LeaseFieldSpec(
      kTermsTransportOn,
      'نقل المركبة على',
      options: termsParties,
    ),
    LeaseFieldSpec(kTermsNotes, 'شروط التأجير', multiline: true),
  ];

  /// حقول عقد المركبة الإلزامية (نجمة حمراء): نمط المدة، وبيانات المركبة.
  static const vehicleRequired = <String, Set<String>>{
    'contract': {kTermMode},
    'property': {
      'تصنيف المركبة',
      'نوع المركبة',
      'اسم المركبة',
      'تاريخ انتهاء الملكية',
    },
  };

  /// عقد المركبة: بسائق أو بدون سائق.
  static const kDriver = 'السائق';
  static const driverOptions = <String>['بسائق', 'بدون سائق'];

  static const kStartTime = 'ساعة بداية العقد';
  static const kEndTime = 'ساعة نهاية العقد';
  static const vehicleTermModes = <String>[
    'بالساعات',
    'يومي',
    'شهري',
    'سنوي',
    'مخصص',
  ];
  /// مدة العقد المحفوظة في عقود قديمة — لم يعد لها حقل في النموذج، وتبقى
  /// للقراءة فقط حتى لا تضيع من سجل كُتب قبل الحذف.
  static const kDuration = 'مدة عقد الإيجار';
  static const kNewNo = 'رقم العقد الجديد';

  /// نمط المدة: يومي للشقق المفروشة، شهري، سنوي، أو مخصص.
  static const kTermMode = 'نمط مدة الإيجار';
  static const termModes = <String>['يومي', 'شهري', 'سنوي', 'مخصص'];

  /// تصنيف المستأجر — في عقد النشاط التجاري.
  static const kTenantClass = 'تصنيف المستأجر';
  static const tenantClasses = <String>[
    'فرد',
    'مؤسسة فردية',
    'شركة',
    'جهة حكومية',
    'أخرى',
  ];

  static const purposes = <String>[
    'تجاري',
    'سكني',
    'صناعي',
    'مستودع',
    'زراعي',
    'أخرى',
  ];
  static const kOldNo = 'رقم العقد المنتهي';

  /// صفة المؤجر في العقد: مالك أو مستثمر (المستثمر: «عقد مستثمر»).
  static const kLessorCapacity = 'صفة المؤجر';

  /// أسماء مستندات العقار المرفقة بالعقد (سطر لكل مستند).
  static const kAttachedDocs = 'المستندات المرفقة';

  /// على من فاتورة الكهرباء والمياه.
  static const kElectricityOn = 'الكهرباء على';
  static const kWaterOn = 'المياه على';
  static const utilityPayers = <String>['المستأجر', 'المؤجر'];

  /// عدد العدادات وأرقامها (سطر لكل عداد) وعلى من كلٌّ منها (سطر لكل
  /// عداد) — نفس مفاتيح عدادات العقار والوحدة فتُملأ منها تلقائيًا.
  static const kElectricCount = 'عدد عدادات الكهرباء';
  static const kElectricMeters = 'عدادات الكهرباء';
  static const kWaterCount = 'عدد عدادات المياه';
  static const kWaterMeters = 'عدادات المياه';

  /// مفتاح العدد ← (مفتاح الأرقام، مفتاح «على من»، عنوان رقم العداد،
  /// المفتاح القديم لرقم عداد واحد).
  static const meterGroups = <String, (String, String, String, String)>{
    kElectricCount: (
      kElectricMeters,
      kElectricityOn,
      'رقم عداد الكهرباء',
      'رقم تسجيل الوحدة',
    ),
    kWaterCount: (kWaterMeters, kWaterOn, 'رقم عداد المياه', 'معرف العقار'),
  };

  /// عدد العدادات المكتوب (0 إن لم يُكتب)، بحدّ أعلى 20.
  static int meterCountOf(Map<String, String> store, String countKey) {
    final n = int.tryParse((store[countKey] ?? '').trim()) ?? 0;
    return n < 0 ? 0 : (n > 20 ? 20 : n);
  }

  /// أسطر [raw] بطول [count] بالضبط (تُكمَّل بفراغ أو تُقصّ).
  static List<String> meterLines(String? raw, int count) {
    final lines = (raw ?? '').split('\n').map((s) => s.trim()).toList();
    if ((raw ?? '').trim().isEmpty) lines.clear();
    while (lines.length < count) {
      lines.add('');
    }
    return lines.sublist(0, count);
  }

  /// عقود قديمة فيها رقم عداد واحد بلا عدد: يصير العدد 1 ورقمه كما هو،
  /// ويُحذف المفتاح القديم متى وُجد العدد (فلا يُطبع الرقم مرتين).
  static void migrateMeters(Map<String, String> store) {
    meterGroups.forEach((countKey, group) {
      final legacy = (store[group.$4] ?? '').trim();
      if ((store[countKey] ?? '').trim().isEmpty && legacy.isNotEmpty) {
        store[countKey] = '1';
        if ((store[group.$1] ?? '').trim().isEmpty) store[group.$1] = legacy;
      }
      if ((store[countKey] ?? '').trim().isNotEmpty) store.remove(group.$4);
    });
  }

  /// العنوان الظاهر لمفتاح من بيانات العقار المحفوظة.
  static String metaLabel(String key) => switch (key) {
    'رقم تسجيل الوحدة' => 'رقم عداد الكهرباء',
    'معرف العقار' => 'رقم عداد المياه',
    'تصنيف العقار' => 'النوع',
    'عدادات الكهرباء' => 'أرقام عدادات الكهرباء',
    'عدادات المياه' => 'أرقام عدادات المياه',
    _ => key,
  };
  static const capacityOwner = 'مالك';
  static const capacityInvestor = 'مستثمر';
  static const lessorCapacities = <String>[capacityOwner, capacityInvestor];

  /// عقد مستثمر؟
  bool get isInvestor =>
      (contract[kLessorCapacity] ?? '').trim() == capacityInvestor;

  // ===== عقد إيجار النشاط التجاري: بيانات الرخصة والتذكيران =====
  // (نفس مفاتيح بيانات النشاط في شاشة الأنشطة.)
  static const kTradeName = 'الاسم التجاري';
  static const kActivityClass = 'تصنيف النشاط';
  static const kLegalForm = 'الشكل القانوني';
  static const kLicenseNo = 'رقم الرخصة التجارية';
  static const kLicenseIssue = 'تاريخ إصدار الرخصة';
  static const kLicenseEnd = 'تاريخ انتهاء الرخصة';
  static const kLicenseReminder = 'تذكير انتهاء الرخصة';
  static const kLicenseReminderDays = 'أيام تذكير الرخصة';
  static const kLicenseClass = 'فئة الرخصة';
  static const kChamber = 'عضوية الغرفة';
  static const kActivities = 'الأنشطة التجارية';
  static const kCapital = 'رأس المال';
  static const kLeaseReminder = 'تذكير نهاية العقد';
  static const kLeaseReminderDays = 'أيام تذكير نهاية العقد';

  /// التذكيران لا يظهران في العقد المطبوع ولا في المشاركة.
  static const activityReminderKeys = <String>{
    kLicenseReminder,
    kLicenseReminderDays,
    kLeaseReminder,
    kLeaseReminderDays,
  };

  static const activityReminders = <String>[
    'بلا تذكير',
    'قبل أسبوعين',
    'قبل شهر',
    'قبل شهرين',
    'مخصص',
  ];

  static const legalForms = <String>[
    'مؤسسة فردية',
    'شركة ذات مسؤولية محدودة',
    'شركة مساهمة',
    'شركة تضامن',
    'فرع شركة',
    'أخرى',
  ];

  static const licenseClasses = <String>['تاجر', 'وطني'];

  static const kName = 'الإسم';
  static const kRepName = 'اسم ممثل المستأجر';
  static const kMobile = 'رقم الجوال';
  static const kPhone = 'رقم الهاتف';

  /// ملاحظات أسفل «مبالغ الدفعات».
  static const kPaymentsNote = 'ملاحظات الدفعات';

  /// موقع النشاط التجاري (بيانات الرخصة).
  static const kActivityLocation = 'موقع النشاط';

  /// الحقول الإلزامية في عقد النشاط التجاري، لكل قسم.
  static const activityRequired = <String, Set<String>>{
    'contract': {kTermMode, kStartDate, kEndDate},
    'license': {kTradeName, kLicenseIssue, kLicenseEnd},
    'lessor': {kName, 'رقم الهوية', 'تاريخ انتهاء الهوية', 'صادرة من', kPhone},
    'tenant': {kName, 'رقم الهوية', 'تاريخ انتهاء الهوية', 'صادرة من', kPhone},
  };

  /// رقم الجوال القديم يُنقل إلى «رقم الهاتف» — حقل واحد للهاتف.
  static void mergeMobileIntoPhone(Map<String, String> store) {
    final mobile = (store[kMobile] ?? '').trim();
    if (mobile.isEmpty) {
      store.remove(kMobile);
      return;
    }
    final phone = (store[kPhone] ?? '').trim();
    if (phone.isEmpty || phone == mobile) {
      store[kPhone] = mobile;
      store.remove(kMobile);
    }
  }

  static const kDepositAmount = 'مبلغ التأمين';
  static const kAdminFeeType = 'نوع الرسم';
  static const kAdminFeeAmount = 'قيمة الرسم';
  static const kAdminFeeDue = 'تاريخ الاستحقاق';
  static const kPaymentAmount = 'قيمة الدفعة';
  static const kPaymentFee = 'نوع الرسوم';
  static const kPaymentDue = 'تاريخ الاستحقاق';

  /// تذكير الدفعة قبل استحقاقها: قبل شهر، قبل شهرين، أو عدد أيام مخصص.
  static const kPaymentReminder = 'التذكير';
  static const kPaymentReminderDays = 'أيام التذكير المخصص';
  static const reminderNone = 'بلا تذكير';
  static const reminderCustom = 'مخصص';
  static const paymentReminders = <String>[
    reminderNone,
    'قبل شهر',
    'قبل شهرين',
    reminderCustom,
  ];

  /// أيام التذكير قبل الاستحقاق لسطر دفعة، أو 0 بلا تذكير.
  static int reminderDaysOf(Map<String, String> row) {
    return switch (row[kPaymentReminder] ?? '') {
      'قبل شهر' => 30,
      'قبل شهرين' => 60,
      reminderCustom =>
        int.tryParse((row[kPaymentReminderDays] ?? '').trim()) ?? 0,
      _ => 0,
    };
  }
  static const kPaymentCheque = 'رقم الشيك';
  static const kPaymentChequeDate = 'تاريخ الشيك';
  static const kPaymentBank = 'اسم البنك';

  /// ملاحظات دفعة واحدة.
  static const kPaymentNote = 'ملاحظات الدفعة';

  /// حالة الشيك نفسه — مستقلة عن حالة الدفعة: الشيك قد يُستلم ويُرسل إلى
  /// البنك قبل أن يُحصَّل مبلغه، وقد يُلغى أو يُستبدل.
  static const kChequeState = 'حالة الشيك';

  /// سجل ما جرى على الشيك سطرًا سطرًا: «التاريخ — الإجراء».
  static const kChequeLog = 'سجل الشيك';

  static const chequeReceived = 'مستلم';
  static const chequeAtBank = 'مرسل إلى البنك';
  static const chequeCleared = 'تم استلام المبلغ';
  static const chequeCancelled = 'ملغى';

  /// أعاده البنك بلا صرف (مرتجع) — تبقى دفعته مستحقة.
  static const chequeRejected = 'مرفوض';
  static const chequeReplaced = 'مستبدل';

  /// أُرجع الشيك (مرتجع) — حالة مستقلة عن الرفض، وتبقى دفعته مستحقة.
  static const chequeReturned = 'مرتجع';

  /// طريقة التحصيل — مسمّى واحد في التأمين والدفعات والرسوم الإدارية.
  /// كانت تُسمّى «طريقة تحصيل التأمين» هنا و«طريقة السداد» هناك.
  static const kCollectMethod = 'طريقة التحصيل';
  static const collectMethods = <String>[
    'كاش',
    'شيك',
    'تحويل بنكي',
    'أخرى',
  ];

  /// بيانات البنك — تُطلب عند اختيار «شيك» فقط.
  static const kBankAccount = 'رقم الحساب';
  static const kBankBranch = 'اسم الفرع';
  static const kBankIban = 'الآيبان';
  static const kPaymentStatus = 'حالة الدفعة';

  // ===== وصف الحقول: منه تُبنى الواجهة كاملة =====
  // الرقمان (الجديد والمنتهي) جنب بعض في السطر الأول، ثم نمط المدة والغرض،
  // ثم التاريخان.
  static const contractFields = <LeaseFieldSpec>[
    // سطر كامل أعلى بيانات العقد: مالك أو مستثمر.
    LeaseFieldSpec(
      kLessorCapacity,
      'مالك أو مستثمر',
      options: lessorCapacities,
    ),
    LeaseFieldSpec(kNewNo, 'رقم العقد الجديد'),
    LeaseFieldSpec(kOldNo, 'رقم العقد المنتهي'),
    LeaseFieldSpec(kTermMode, 'نمط مدة الإيجار', options: termModes),
    // حُذف «الغرض من الإيجار»: «نوع الاستخدام» في بيانات العقار يغني عنه.
    // حُذف «سنة العقد»: تُقرأ من التاريخين أسفله.
    // وحُذفت «مدة عقد الإيجار»: تكرّر [kTermMode] أعلى النموذج، والتاريخان
    // يحدّدان المدة بدقة اليوم لا بخيار من قائمة.
    LeaseFieldSpec(kStartDate, 'تاريخ بداية عقد الإيجار', date: true),
    LeaseFieldSpec(kEndDate, 'تاريخ نهاية عقد الإيجار', date: true),
  ];

  /// بيانات عقد إيجار النشاط التجاري: نمط المدة، رقم العقد، التاريخان،
  /// الغرض، وتصنيف المستأجر.
  static const activityContractFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kTermMode, 'نمط مدة الإيجار', options: termModes),
    LeaseFieldSpec(kNewNo, 'رقم عقد الإيجار'),
    LeaseFieldSpec(kStartDate, 'تاريخ بداية العقد', date: true),
    LeaseFieldSpec(kEndDate, 'تاريخ نهاية العقد', date: true),
    LeaseFieldSpec(kPurpose, 'الغرض من الإيجار', options: purposes),
    LeaseFieldSpec(kTenantClass, 'تصنيف المستأجر', options: tenantClasses),
  ];

  static const propertyFields = <LeaseFieldSpec>[
    LeaseFieldSpec('بيانات العين المؤجرة', 'بيانات العين المؤجرة'),
    LeaseFieldSpec('المدينة', 'المدينة'),
    LeaseFieldSpec('المنطقة', 'المنطقة'),
    LeaseFieldSpec('حوض رقم', 'حوض رقم'),
    LeaseFieldSpec('قطعة رقم', 'قطعة رقم'),
    LeaseFieldSpec('رقم العين', 'رقم العين'),
    // نوع العين اختيار لا كتابة حرّة: كانت تُكتب بصيغ مختلفة لكل عقار
    // فلا تصلح للفرز ولا تُطبع موحّدة في العقود.
    LeaseFieldSpec(
      'نوع العين',
      'نوع العين',
      options: <String>['سكني', 'تجاري', 'استثماري', 'صناعي', 'زراعي', 'أخرى'],
    ),
    LeaseFieldSpec('مساحة العين', 'مساحة العين (م٢)', numeric: true),
    LeaseFieldSpec('نوع الاستخدام', 'نوع الاستخدام'),
    LeaseFieldSpec('الغرض من استخدام العين', 'الغرض من استخدام العين'),
    LeaseFieldSpec('رقم العقار', 'رقم العقار'),
    // المفتاحان كما هما (بيانات قديمة محفوظة بهما)، والعنوان الظاهر:
    // رقم عداد الكهرباء ورقم عداد المياه، ومعهما على من تُدفع.
    LeaseFieldSpec('رقم تسجيل الوحدة', 'رقم عداد الكهرباء'),
    LeaseFieldSpec(
      kElectricityOn,
      'الكهرباء على',
      options: utilityPayers,
    ),
    LeaseFieldSpec('معرف العقار', 'رقم عداد المياه'),
    LeaseFieldSpec(kWaterOn, 'المياه على', options: utilityPayers),
    LeaseFieldSpec('مكونات العين', 'مكونات العين', multiline: true),
  ];

  /// خيارات «نوع الاستخدام» و«الغرض من استخدام العين» في عقد الإيجار.
  static const usageTypes = <String>[
    'تجاري',
    'سكني',
    'صناعي',
    'مستودع',
    'زراعي',
    'أخرى',
  ];
  static const usagePurposes = <String>[
    'سكن عائلة',
    'محل ملابس',
    'مكتب تخزين',
    'تخزين بضائع',
    'أخرى',
  ];

  /// «بيانات العقار» في نموذج عقد الإيجار: بلا «نوع العين»، ونوع الاستخدام
  /// والغرض منه اختياران، وعدد عدادات الكهرباء والمياه (وتحت كلٍّ رقم كل
  /// عداد وعلى من). [propertyFields] تبقى لنماذج العقار نفسه.
  static const leasePropertyFields = <LeaseFieldSpec>[
    LeaseFieldSpec('بيانات العين المؤجرة', 'بيانات العين المؤجرة'),
    LeaseFieldSpec('المدينة', 'المدينة'),
    LeaseFieldSpec('المنطقة', 'المنطقة'),
    LeaseFieldSpec('حوض رقم', 'حوض رقم'),
    LeaseFieldSpec('قطعة رقم', 'قطعة رقم'),
    LeaseFieldSpec('رقم العين', 'رقم العين'),
    LeaseFieldSpec('مساحة العين', 'مساحة العين (م٢)', numeric: true),
    LeaseFieldSpec('نوع الاستخدام', 'نوع الاستخدام', options: usageTypes),
    LeaseFieldSpec(
      'الغرض من استخدام العين',
      'الغرض من استخدام العين',
      options: usagePurposes,
    ),
    LeaseFieldSpec('رقم العقار', 'رقم العقار'),
    LeaseFieldSpec(kElectricCount, 'عدد عدادات الكهرباء', numeric: true),
    LeaseFieldSpec(kWaterCount, 'عدد عدادات المياه', numeric: true),
    LeaseFieldSpec('مكونات العين', 'مكونات العين', multiline: true),
  ];

  static const lessorFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kName, 'الإسم'),
    LeaseFieldSpec('رقم الهوية', 'رقم الهوية'),
    LeaseFieldSpec('الجنسية', 'الجنسية'),
    LeaseFieldSpec('تاريخ انتهاء الهوية', 'تاريخ انتهاء الهوية', date: true),
    LeaseFieldSpec('صادرة من', 'صادرة من'),
    LeaseFieldSpec(kPhone, 'رقم الهاتف'),
    LeaseFieldSpec('صندوق البريد', 'صندوق البريد'),
    LeaseFieldSpec('البريد الإلكتروني', 'البريد الإلكتروني'),
    LeaseFieldSpec('رقم الجواز', 'رقم الجواز'),
    LeaseFieldSpec('تاريخ انتهاء الجواز', 'تاريخ انتهاء الجواز', date: true),
  ];

  static const tenantFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kName, 'الإسم'),
    LeaseFieldSpec('رقم الهوية', 'رقم الهوية'),
    LeaseFieldSpec('الجنسية', 'الجنسية'),
    LeaseFieldSpec('تاريخ انتهاء الهوية', 'تاريخ انتهاء الهوية', date: true),
    LeaseFieldSpec('صادرة من', 'صادرة من'),
    LeaseFieldSpec(kPhone, 'رقم الهاتف'),
    LeaseFieldSpec('صندوق البريد', 'صندوق البريد'),
    LeaseFieldSpec('رخصة رقم', 'رخصة رقم'),
    LeaseFieldSpec('الاسم التجاري', 'الاسم التجاري'),
    LeaseFieldSpec('تاريخ انتهاء الرخصة', 'تاريخ انتهاء الرخصة', date: true),
    LeaseFieldSpec('مصدر الرخصة', 'مصدر الرخصة'),
    LeaseFieldSpec('البريد الإلكتروني', 'البريد الإلكتروني'),
  ];

  static const representativeFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kRepName, 'اسم ممثل المستأجر'),
    LeaseFieldSpec('اللقب', 'اللقب'),
    LeaseFieldSpec('رقم الهوية', 'رقم الهوية'),
    LeaseFieldSpec('الجنسية', 'الجنسية'),
    LeaseFieldSpec('تاريخ انتهاء الهوية', 'تاريخ انتهاء الهوية', date: true),
    LeaseFieldSpec('صادرة من', 'صادرة من'),
    LeaseFieldSpec('رقم الجواز', 'رقم الجواز'),
    LeaseFieldSpec('تاريخ انتهاء الجواز', 'تاريخ انتهاء الجواز', date: true),
    LeaseFieldSpec('وكالة رقم', 'وكالة رقم'),
    LeaseFieldSpec('مصدر الوكالة', 'الوكالة صادرة من'),
    LeaseFieldSpec('تاريخ إصدار الوكالة', 'تاريخ إصدار الوكالة', date: true),
    LeaseFieldSpec('تاريخ انتهاء الوكالة', 'تاريخ انتهاء الوكالة', date: true),
    LeaseFieldSpec(kMobile, 'رقم الهاتف'),
    LeaseFieldSpec('البريد الإلكتروني', 'البريد الإلكتروني'),
  ];

  /// تاريخ شيك التأمين اختياري (بلا نجمة) — عنوانه غير «تاريخ الشيك».
  static const depositChequeDateLabel = 'تاريخ الشيك (إن وُجد)';

  static const depositFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kDepositAmount, 'مبلغ التأمين', numeric: true),
    LeaseFieldSpec(kCollectMethod, 'طريقة التحصيل',
        options: collectMethods),
    // مع «شيك» وحده: رقم الشيك وتاريخه (إن وُجد) وبنكه — والتأمين بشيك
    // مجرد ضمان، فلا «تاريخ تحصيل» له.
    LeaseFieldSpec(kPaymentCheque, 'رقم الشيك', chequeOnly: true),
    LeaseFieldSpec(kPaymentChequeDate, depositChequeDateLabel,
        date: true, chequeOnly: true),
    LeaseFieldSpec(kPaymentBank, 'اسم البنك', chequeOnly: true),
    LeaseFieldSpec('تاريخ تحصيل التأمين', 'تاريخ تحصيل التأمين',
        date: true, hideForCheque: true),
    LeaseFieldSpec('رقم الإيصال', 'رقم الإيصال'),
    LeaseFieldSpec('ملاحظات', 'ملاحظات', multiline: true),
  ];

  static const adminFeeFields = <LeaseFieldSpec>[
    LeaseFieldSpec(kAdminFeeType, 'نوع الرسم', options: adminFeeTypes),
    LeaseFieldSpec(kAdminFeeAmount, 'قيمة الرسم', numeric: true),
    LeaseFieldSpec(kAdminFeeDue, 'تاريخ الاستحقاق', date: true),
    LeaseFieldSpec(kCollectMethod, 'طريقة التحصيل',
        options: collectMethods),
    LeaseFieldSpec('رقم الإيصال', 'رقم الإيصال'),
    LeaseFieldSpec('على من', 'يتحمّلها',
        options: <String>['المستأجر', 'المؤجر', 'مناصفة']),
    LeaseFieldSpec('ملاحظات', 'ملاحظات', multiline: true),
  ];

  static const adminFeeTypes = <String>[
    'رسوم تسجيل العقد',
    'رسوم إدارية',
    'رسوم خدمات',
    'رسوم توثيق',
    'عمولة',
    'رسوم أخرى',
  ];

  /// ترتيب حقول الدفعة: رقمها، ثم مبلغها، ثم موعدها، ثم كيف تُحصَّل —
  /// وبيانات البنك لا تظهر إلا إن كان التحصيل بشيك.
  static const paymentFields = <LeaseFieldSpec>[
    // اسم حرّ: «دفعة مارس»، «دفعة التوقيع»، «الدفعة الأولى» — يكتبه
    // المستخدم كما يسمّيه في عقده، لا كما رتّبته قائمة جاهزة.
    LeaseFieldSpec(kPaymentFee, 'اسم الدفعة'),
    LeaseFieldSpec(kPaymentAmount, 'قيمة الدفعة', numeric: true),
    // طريقة التحصيل، وتحتها تاريخ الاستحقاق، ثم التذكير. مع «شيك» يختفي
    // تاريخ الاستحقاق: تاريخ الشيك هو الاستحقاق.
    LeaseFieldSpec(kCollectMethod, 'طريقة التحصيل',
        options: collectMethods),
    LeaseFieldSpec(kPaymentDue, 'تاريخ الاستحقاق',
        date: true, hideForCheque: true),
    LeaseFieldSpec(kPaymentCheque, 'رقم الشيك', chequeOnly: true),
    LeaseFieldSpec(kPaymentChequeDate, 'تاريخ الشيك',
        date: true, chequeOnly: true),
    // التذكير تحت تاريخ الاستحقاق (أو تاريخ الشيك) مباشرة، ثم بيانات البنك.
    LeaseFieldSpec(kPaymentReminder, 'التذكير', options: paymentReminders),
    LeaseFieldSpec(kPaymentReminderDays, 'التذكير قبل الاستحقاق بكم يوم',
        numeric: true, customReminderOnly: true),
    LeaseFieldSpec(kPaymentBank, 'اسم البنك', chequeOnly: true),
    LeaseFieldSpec(kBankAccount, 'رقم الحساب', chequeOnly: true),
    LeaseFieldSpec(kBankBranch, 'اسم الفرع', chequeOnly: true),
    LeaseFieldSpec(kBankIban, 'الآيبان', chequeOnly: true),
    LeaseFieldSpec(kPaymentNote, 'ملاحظات', multiline: true),
    // بلا «حالة الدفعة»: كل دفعة تُسجَّل مستحقة، وحالتها تتغيّر عند
    // السداد من شاشة الدفعات لا عند كتابة العقد.
  ];

  // ===== الضريبة =====
  /// المبالغ المكتوبة في العقد **صافية قبل الضريبة**، والضريبة تُضاف
  /// فوقها وتُعرض لكل دفعة ولكل رسم على حدة. هكذا يقرأ الطرفان
  /// «الإجمالي بدون ضريبة» و«الإجمالي بضريبة» صريحين، بدل رقم واحد
  /// ملتبس لا يُعرف أشامل هو أم لا.
  static const kTaxRate = 'نسبة الضريبة %';
  static const kRentTaxable = 'الإيجار خاضع للضريبة';

  /// الرسوم الإدارية: قرار ونسبة لمستطيلها كله، لا لكل سطر — تفعيل
  /// الضريبة يخصّ باب الرسوم لا رسمًا بعينه.
  static const kAdminFeesTaxable = 'الرسوم الإدارية خاضعة للضريبة';
  static const kAdminFeesTaxRate = 'نسبة ضريبة الرسوم %';

  /// توقيع صاحب العقد وختمه من داخل التطبيق.
  static const kSignedAt = 'تاريخ التوقيع والختم';
  static const kSignedBy = 'وقّع وختم';

  bool get isSigned => (contract[kSignedAt] ?? '').trim().isNotEmpty;

  /// الحقول التي لا يكون العقد عقدًا بدونها. نقصها لا يمنع الحفظ —
  /// يُحفظ كمسودة، فلا يضيع ما أُدخل — لكنه يمنع اعتباره عقدًا ساريًا.
  ///
  /// بيانات المستأجر وممثله كلها اختيارية: قد لا يكون للمستأجر ممثل، وقد
  /// تُستكمل بياناته لاحقًا.
  List<String> get missingRequired => <String>[
    if ((contract[kStartDate] ?? '').trim().isEmpty) 'تاريخ بداية العقد',
    if ((contract[kEndDate] ?? '').trim().isEmpty) 'تاريخ نهاية العقد',
    // الوحدات الأخرى في عقد متعدد الوحدات: دفعاته على وحدته الرئيسية.
    if (payments.isEmpty && (contract[kMultiPrimary] ?? '').trim().isEmpty)
      'دفعات الإيجار',
    // «محتوى العقد» اختيار إلزامي في العقارات والأنشطة (لا في المركبات).
    // «الملخص المالي للعقد» (محتوى العقد) إلزامي في كل العقود.
    if ((contract[kContractScope] ?? '').trim().isEmpty)
      'الملخص المالي للعقد',
    // المركبة: بسائق أو بدون، ونمط المدة، وبيانات المركبة الأساسية.
    if (isVehicle) ...[
      if ((contract[kDriver] ?? '').trim().isEmpty) 'بسائق أو بدون سائق',
      if ((contract[kTermMode] ?? '').trim().isEmpty) 'نمط مدة الإيجار',
      for (final key in vehicleRequired['property']!)
        if ((property[key] ?? '').trim().isEmpty) key,
    ],
    if ((tenant['تاريخ انتهاء الهوية'] ?? '').trim().isEmpty)
      'تاريخ انتهاء هوية المستأجر',
    // عقد العقار: بيانات العين الأساسية (لا في المركبات ولا في النشاط).
    if (!isVehicle && license.isEmpty)
      for (final key in requiredProperty)
        if ((property[key] ?? '').trim().isEmpty) key,
    // المؤجر: الاسم والهوية وتاريخ انتهائها. المستأجر: الاسم والهوية.
    if ((lessor[kName] ?? '').trim().isEmpty) 'اسم المؤجر',
    if ((lessor['رقم الهوية'] ?? '').trim().isEmpty) 'رقم هوية المؤجر',
    if ((lessor['تاريخ انتهاء الهوية'] ?? '').trim().isEmpty)
      'تاريخ انتهاء هوية المؤجر',
    if ((tenant[kName] ?? '').trim().isEmpty) 'اسم المستأجر',
    if ((tenant['رقم الهوية'] ?? '').trim().isEmpty) 'رقم هوية المستأجر',
    if ((lessor[kPhone] ?? '').trim().isEmpty &&
        (lessor[kMobile] ?? '').trim().isEmpty)
      'رقم هاتف المؤجر',
    if ((tenant[kPhone] ?? '').trim().isEmpty &&
        (tenant[kMobile] ?? '').trim().isEmpty)
      'رقم هاتف المستأجر',
  ];

  /// عقد متعدد الوحدات: كل الوحدات المشمولة (بالأسماء)، وفي سجلات الوحدات
  /// غير الرئيسية اسم الوحدة الرئيسية التي تحمل الدفعات.
  static const kMultiUnits = 'الوحدات المشمولة';
  static const kMultiPrimary = 'الوحدة الرئيسية للعقد';

  /// حقول العين الإلزامية في عقد العقار.
  static const requiredProperty = <String>[
    'بيانات العين المؤجرة',
    'المدينة',
    'المنطقة',
  ];

  /// الحقول الإلزامية لكل قسم في عقد العقار والمركبة (نجمة حمراء).
  static const contractRequired = <String, Set<String>>{
    'property': {
      'بيانات العين المؤجرة',
      'المدينة',
      'المنطقة',
    },
    'lessor': {kName, 'رقم الهوية', 'تاريخ انتهاء الهوية', kPhone},
    'tenant': {kName, 'رقم الهوية', 'تاريخ انتهاء الهوية', kPhone},
  };

  bool get isDraft => missingRequired.isNotEmpty;

  /// علامة «سُوّيت مبالغ العقد» عند إلغائه/إنهائه: ما بقي منه لا يُتابَع.
  static const kSettled = 'تمت تسوية المبالغ';

  static bool isSettled(String? notes) =>
      (notes ?? '').contains('"$kSettled":"نعم"');

  /// ما يذكره العقد المطبوع: الدفعات وحدها، أم الدفعات والرسوم معًا.
  static const kContractScope = 'محتوى العقد';
  static const scopePaymentsOnly = 'الدفعات الإيجارية فقط';
  static const scopeWithAdminFees = 'الدفعات الإيجارية + الرسوم الإدارية';

  double get taxRate => _num(contract[kTaxRate]);

  bool get rentTaxable => (contract[kRentTaxable] ?? '').trim() == 'نعم';

  String get contractScope =>
      (contract[kContractScope] ?? '').trim() == scopePaymentsOnly
      ? scopePaymentsOnly
      : scopeWithAdminFees;

  bool get contractIncludesAdminFees => contractScope == scopeWithAdminFees;

  static double _taxOf(double amount, double rate) =>
      rate <= 0 ? 0 : amount * rate / 100;

  /// ضريبة دفعة إيجار واحدة — بنسبة العقد.
  double paymentTaxOf(Map<String, String> row) =>
      rentTaxable ? _taxOf(_num(row[kPaymentAmount]), taxRate) : 0;

  /// مبلغ الدفعة شاملًا ضريبتها — هو مبلغ الشيك الفعلي.
  double paymentTotalOf(Map<String, String> row) =>
      _num(row[kPaymentAmount]) + paymentTaxOf(row);

  bool get adminFeesTaxable =>
      (contract[kAdminFeesTaxable] ?? '').trim() == 'نعم';

  double get adminFeesTaxRate {
    final own = _num(contract[kAdminFeesTaxRate]);
    return own > 0 ? own : taxRate;
  }

  /// ضريبة رسم إداري واحد — بنسبة مستطيل الرسوم.
  double adminFeeTaxOf(Map<String, String> row) => adminFeesTaxable
      ? _taxOf(_num(row[kAdminFeeAmount]), adminFeesTaxRate)
      : 0;

  // ===== حسابات =====
  static double _num(String? raw) {
    if (raw == null) return 0;
    final cleaned = raw.replaceAll(',', '').replaceAll('٬', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  double get paymentsTotal =>
      payments.fold(0.0, (sum, row) => sum + _num(row[kPaymentAmount]));

  double get depositsTotal =>
      deposits.fold(0.0, (sum, row) => sum + _num(row[kDepositAmount]));

  double get adminFeesTotal =>
      adminFees.fold(0.0, (sum, row) => sum + _num(row[kAdminFeeAmount]));

  // ===== إجماليات =====
  double get paymentsTax =>
      payments.fold(0.0, (sum, row) => sum + paymentTaxOf(row));

  double get paymentsGross => paymentsTotal + paymentsTax;

  double get adminFeesTax =>
      adminFees.fold(0.0, (sum, row) => sum + adminFeeTaxOf(row));

  double get adminFeesGross => adminFeesTotal + adminFeesTax;

  /// إجماليات العقد بحسب ما اختير أن يتضمّنه.
  double get contractNetTotal =>
      paymentsTotal + (contractIncludesAdminFees ? adminFeesTotal : 0);

  double get contractTaxTotal =>
      paymentsTax + (contractIncludesAdminFees ? adminFeesTax : 0);

  double get contractGrossTotal => contractNetTotal + contractTaxTotal;

  double get paidTotal => payments
      .where((row) => (row[kPaymentStatus] ?? '') == 'مسددة')
      .fold(0.0, (sum, row) => sum + _num(row[kPaymentAmount]));

  double get remainingTotal => paymentsTotal - paidTotal;

  /// قيمة العقد = مجموع دفعاته. لا تُكتب يدويًا.
  double get contractValue => paymentsTotal;

  /// عدد الدفعات = عدد ما سُجِّل منها.
  int get installmentsCount => payments.length;

  /// تُكتب القيمتان في خريطة العقد قبل الحفظ حتى تظهرا في العقد المطبوع
  /// وفي سجلّ الوحدة.
  void syncDerivedContractValues() {
    contract[kValue] = paymentsTotal.toStringAsFixed(2);
    contract[kInstallments] = '$installmentsCount';
  }

  bool get isEmpty =>
      contract.isEmpty &&
      property.isEmpty &&
      lessor.isEmpty &&
      tenant.isEmpty &&
      representative.isEmpty &&
      deposits.isEmpty &&
      payments.isEmpty &&
      adminFees.isEmpty;

  /// أقرب دفعة قادمة غير مسددة (لمركز المتابعة وإدارة الشيكات).
  Map<String, String>? get nextDuePayment {
    DateTime? bestDate;
    Map<String, String>? best;
    for (final row in payments) {
      if ((row[kPaymentStatus] ?? '') == 'مسددة') continue;
      final date = DateTime.tryParse(row[kPaymentDue] ?? '');
      if (date == null) continue;
      if (bestDate == null || date.isBefore(bestDate)) {
        bestDate = date;
        best = row;
      }
    }
    return best;
  }

  /// كل الشيكات المسجّلة داخل العقد (تُستعمل في قسم «إدارة الشيكات»).
  List<Map<String, String>> get cheques => payments
      .where((row) => (row[kPaymentCheque] ?? '').trim().isNotEmpty)
      .toList(growable: false);

  // ===== التخزين =====
  Map<String, dynamic> toJson() => <String, dynamic>{
        '__lease__': 1,
        'contract': contract,
        'property': property,
        'lessor': lessor,
        'tenant': tenant,
        'representative': representative,
        if (license.isNotEmpty) 'license': license,
        'deposits': deposits,
        'payments': payments,
        'adminFees': adminFees,
        'note': note,
      };

  String encode() => jsonEncode(toJson());

  /// معرّف ثابت لكل سطر دفعة ورسم وتأمين.
  ///
  /// يربط السطر المكتوب في العقد بسجلّه في جدول الدفعات: إعادة حفظ العقد
  /// تحدّث السجل نفسه بدل أن تُنشئ نسخة ثانية، وما سُدِّد منه لا يضيع.
  /// يبدأ بشرطتين سفليتين فلا يُطبع في العقد ولا في المشاركة.
  static const kRowId = '__rid';

  /// يمنح كل سطر بلا معرّف معرّفًا. يعيد `true` إن أُضيف معرّف واحد على
  /// الأقل — أي أن العقد تغيّر ويجب حفظه.
  bool ensureRowIds() {
    var changed = false;
    var seq = 0;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    for (final list in [payments, adminFees, deposits]) {
      for (final row in list) {
        if ((row[kRowId] ?? '').trim().isNotEmpty) continue;
        row[kRowId] = '$stamp-${seq++}';
        changed = true;
      }
    }
    return changed;
  }

  static Map<String, String> _mapOf(dynamic raw) {
    final out = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        out['$key'] = '${value ?? ''}';
      });
    }
    return out;
  }

  static List<Map<String, String>> _listOf(dynamic raw) {
    if (raw is! List) return <Map<String, String>>[];
    return raw.whereType<Map>().map(_mapOf).toList(growable: true);
  }

  /// يقرأ العقد من عمود الملاحظات. النص العادي القديم يُحفظ في `note`.
  factory LeaseContractData.decode(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return LeaseContractData();
    if (!text.startsWith('{')) return LeaseContractData(note: text);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map || decoded['__lease__'] == null) {
        return LeaseContractData(note: text);
      }
      final lessor = _mapOf(decoded['lessor']);
      final tenant = _mapOf(decoded['tenant']);
      mergeMobileIntoPhone(lessor);
      mergeMobileIntoPhone(tenant);
      return LeaseContractData(
        contract: _mapOf(decoded['contract']),
        property: _mapOf(decoded['property']),
        lessor: lessor,
        tenant: tenant,
        representative: _mapOf(decoded['representative']),
        license: _mapOf(decoded['license']),
        deposits: _listOf(decoded['deposits']),
        payments: _listOf(decoded['payments']),
        adminFees: _listOf(decoded['adminFees']),
        note: decoded['note']?.toString() ?? '',
      );
    } catch (_) {
      return LeaseContractData(note: text);
    }
  }

  LeaseContractData copy() => LeaseContractData(
        contract: contract,
        property: property,
        lessor: lessor,
        tenant: tenant,
        representative: representative,
        license: license,
        deposits: deposits,
        payments: payments,
        adminFees: adminFees,
        note: note,
      );

  /// يملأ قسم «بيانات العقار» من بيانات العقار المسجّلة في التطبيق،
  /// دون مسح ما أدخله المستخدم يدويًا.
  void fillPropertyFrom(Map<String, String> meta) {
    meta.forEach((key, value) {
      if (value.trim().isEmpty) return;
      final current = property[key];
      if (current == null || current.trim().isEmpty) {
        property[key] = value.trim();
      }
    });
  }

  /// ملخص نصي للعقد — يُستعمل في المشاركة والطباعة.
  String toShareText() {
    final buffer = StringBuffer();
    void section(String title, Map<String, String> values) {
      final filled = values.entries
          .where((e) => e.value.trim().isNotEmpty)
          .toList(growable: false);
      if (filled.isEmpty) return;
      buffer.writeln('— $title —');
      for (final entry in filled) {
        buffer.writeln(
          '${entry.key == kMobile ? kPhone : entry.key}: ${entry.value}',
        );
      }
      buffer.writeln();
    }

    buffer.writeln(isVehicle ? 'عقد تأجير مركبة' : 'عقد إيجار');
    buffer.writeln();
    section(
      'بيانات عقد الإيجار',
      Map<String, String>.of(contract)
        ..remove(kSubject)
        ..remove(kPaymentsNote),
    );
    // بيانات الرخصة (عقد النشاط التجاري) — بلا التذكيرين.
    section(
      'بيانات الرخصة',
      Map<String, String>.of(license)
        ..removeWhere((key, _) => activityReminderKeys.contains(key)),
    );
    section(isVehicle ? 'بيانات المركبة' : 'بيانات العقار', property);
    section('بيانات المؤجر', lessor);
    section('بيانات المستأجر', tenant);
    if (!isVehicle) section('بيانات ممثل المستأجر', representative);
    if (deposits.isNotEmpty) {
      buffer.writeln('— قيمة التأمين على العين —');
      for (final row in deposits) {
        buffer.writeln(
          '${row[kDepositAmount] ?? ''} · ${row[kCollectMethod] ?? ''} · '
          '${row['تاريخ تحصيل التأمين'] ?? ''} · إيصال ${row['رقم الإيصال'] ?? ''}',
        );
      }
      buffer.writeln();
    }
    if (payments.isNotEmpty) {
      buffer.writeln('— طريقة سداد دفعات الإيجار —');
      for (final row in payments) {
        final tax = paymentTaxOf(row);
        buffer.writeln(
          '${row[kPaymentFee] ?? ''}: ${row[kPaymentAmount] ?? ''}'
          '${tax > 0 ? ' + ضريبة ${tax.toStringAsFixed(2)}' : ''} · '
          'استحقاق ${row[kPaymentDue] ?? ''} · شيك ${row[kPaymentCheque] ?? ''} '
          '(${row[kPaymentBank] ?? ''})',
        );
      }
      buffer.writeln(
        'الإجمالي بدون ضريبة: ${paymentsTotal.toStringAsFixed(2)}',
      );
      if (paymentsTax > 0) {
        buffer.writeln(
          'الإجمالي بضريبة: ${paymentsGross.toStringAsFixed(2)}',
        );
      }
      final paymentsNote = (contract[kPaymentsNote] ?? '').trim();
      if (paymentsNote.isNotEmpty) buffer.writeln('ملاحظات: $paymentsNote');
      buffer.writeln();
    }
    if (adminFees.isNotEmpty && contractIncludesAdminFees) {
      buffer.writeln('— مبالغ رسوم إدارية —');
      for (final row in adminFees) {
        final tax = adminFeeTaxOf(row);
        buffer.writeln(
          '${row[kAdminFeeType] ?? ''}: ${row[kAdminFeeAmount] ?? ''}'
          '${tax > 0 ? ' + ضريبة ${tax.toStringAsFixed(2)}' : ''} · '
          'استحقاق ${row[kAdminFeeDue] ?? ''} · '
          'يتحمّلها ${row['على من'] ?? ''}',
        );
      }
      buffer.writeln(
        'الإجمالي بدون ضريبة: ${adminFeesTotal.toStringAsFixed(2)}',
      );
      if (adminFeesTax > 0) {
        buffer.writeln(
          'الإجمالي بضريبة: ${adminFeesGross.toStringAsFixed(2)}',
        );
      }
      buffer.writeln();
    }
    buffer.writeln('— الملخص المالي —');
    buffer.writeln('محتوى العقد: $contractScope');
    buffer.writeln(
      'الإجمالي بدون ضريبة: ${contractNetTotal.toStringAsFixed(2)}',
    );
    if (contractTaxTotal > 0) {
      buffer.writeln('الضريبة: ${contractTaxTotal.toStringAsFixed(2)}');
      buffer.writeln(
        'الإجمالي بضريبة: ${contractGrossTotal.toStringAsFixed(2)}',
      );
    }
    if (depositsTotal > 0) {
      buffer.writeln(
        'التأمين (مسترد، خارج الإجمالي): '
        '${depositsTotal.toStringAsFixed(2)}',
      );
    }
    if (isSigned) {
      buffer.writeln();
      buffer.writeln(
        'وُقِّع وخُتم إلكترونيًا في ${contract[kSignedAt]}'
        '${(contract[kSignedBy] ?? '').trim().isEmpty ? '' : ' — ${contract[kSignedBy]}'}',
      );
    }
    buffer.writeln();
    if (note.trim().isNotEmpty) {
      buffer.writeln('ملاحظات: $note');
    }
    return buffer.toString();
  }
}
