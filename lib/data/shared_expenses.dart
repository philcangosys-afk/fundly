import 'dart:convert';

/// مبلغ أو سعر مكتوب بأي صيغة: أرقام عربية، فاصلة عشرية عربية (٫)، فواصل
/// آلاف (1,500). يعيد null إن لم يكن رقمًا — بدل أن يُحسب صفرًا بصمت.
double? parseMoney(String raw) {
  var text = raw.trim().replaceAll(RegExp(r'\s'), '');
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  text = text.replaceAll('٫', '.').replaceAll('٬', ',').replaceAll('،', ',');
  // «12,5» و«0,075»: فاصلة عشرية. «1,500» و«12,000,000»: فواصل آلاف.
  if (!text.contains('.') &&
      RegExp(r'^-?\d+,\d{1,2}$|^-?0,\d+$').hasMatch(text)) {
    text = text.replaceAll(',', '.');
  }
  return double.tryParse(text.replaceAll(',', ''));
}

/// دفتر مصروفات الالتزام المشترك — على طريقة Splitwise.
///
/// الالتزام المشترك ليس مبلغًا واحدًا يُقسَّم مرة، بل **وعاء** تتراكم فيه
/// مصروفات متعددة: لكل مصروف من دفعه، ومن يشارك فيه، وطريقة تقسيمه.
/// من هذه المصروفات تُحسب أرصدة الأعضاء («لك» و«عليك») تلقائيًا، ثم
/// تُبسَّط إلى أقل عدد من التحويلات عند التصفية.
///
/// كل هذا يُحفظ قائمةَ JSON داخل تفاصيل الالتزام نفسه، بلا أي تعديل على
/// مخطط قاعدة البيانات.
class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.payer,
    required this.date,
    required this.participants,
    required this.method,
    required this.shares,
    this.note = '',
    this.receipt = '',
    this.category = categoryOther,
    this.subcategory = '',
    this.status = statusApproved,
    this.submittedBy = '',
    this.currency = '',
    this.originalAmount = 0,
    this.rate = 1,
    this.decidedAt = '',
  });

  /// تاريخ ووقت موافقة المسؤول أو رفضه («17/10/2026 14:32»).
  final String decidedAt;

  /// عملة المصروف إن صُرف بعملة غير عملة الالتزام (مثلًا جنيه مصري في
  /// رحلة بالدرهم). فارغة = بعملة الالتزام نفسها.
  final String currency;

  /// المبلغ بعملته الأصلية — و[amount] هو ما يعادله بعملة الالتزام، وعليه
  /// تُحسب الأرصدة والتسوية.
  final double originalAmount;

  /// سعر الصرف: 1 من [currency] = [rate] من عملة الالتزام.
  final double rate;

  bool get isForeign => currency.trim().isNotEmpty && originalAmount > 0;

  /// معرّف داخلي للمصروف (وقت الإنشاء بالميلي ثانية).
  final String id;
  final String description;
  final double amount;

  /// من دفع هذا المصروف فعلًا.
  final String payer;
  final String date;

  /// من يشارك في تحمّل هذا المصروف.
  final List<String> participants;

  /// بالتساوي / بالنسبة / بالمبلغ المحدد / بالحصص.
  final String method;

  /// قيمة التقسيم لكل مشارك حسب الطريقة (نسبة أو مبلغ أو عدد حصص).
  final Map<String, double> shares;

  final String note;
  final String receipt;

  /// الفئة الرئيسية — عليها يُبنى فلتر «أين ذهبت الفلوس».
  final String category;

  /// الفئة الفرعية إن وُجدت («مطاعم» تحت «طعام ومشروبات»).
  final String subcategory;

  /// المعتمد وحده يدخل الحساب. ما يرسله عضو غير المسؤول يبقى «بانتظار
  /// الموافقة» حتى يوافق المسؤول أو يرفض.
  final String status;

  /// من أرسل المصروف (الاسم المسجّل على جهازه).
  final String submittedBy;

  static const String statusApproved = 'معتمد';
  static const String statusPending = 'بانتظار الموافقة';
  static const String statusRejected = 'مرفوض';

  bool get isApproved => status == statusApproved;
  bool get isPending => status == statusPending;
  bool get isRejected => status == statusRejected;

  SharedExpense withStatus(String value, {String? by, String? at}) =>
      SharedExpense(
    id: id,
    description: description,
    amount: amount,
    payer: payer,
    date: date,
    participants: participants,
    method: method,
    shares: shares,
    note: note,
    receipt: receipt,
    category: category,
    subcategory: subcategory,
    status: value,
    submittedBy: by ?? submittedBy,
    currency: currency,
    originalAmount: originalAmount,
    rate: rate,
    decidedAt: at ?? decidedAt,
  );

  static const String categoryOther = 'مصروفات أخرى';

  /// الفئات بنفس أسلوب الالتزامات الشخصية: رئيسية وتحت كل منها فرعية.
  /// ويمكن إضافة فئة غير موجودة من المنتقي نفسه.
  static const Map<String, List<String>> categoryGroups = {
    'طعام ومشروبات': ['مطاعم', 'بقالة وسوبرماركت', 'توصيل وطلبات'],
    'كوفيهات': [],
    'مواصلات': ['تطبيقات توصيل', 'نقل عام وتاكسي', 'تأجير سيارة', 'وقود'],
    'فنادق وإقامة': [],
    'تذاكر ورسوم سفر': [],
    'ترفيه': ['أنشطة وجولات', 'دخول أماكن'],
    'تسوق': ['هدايا', 'ملابس'],
    'مساعدات': [],
    categoryOther: [],
  };

  /// أسماء أول نسخة من الفئات، تُقرأ بأسمائها الجديدة.
  static const Map<String, String> _legacyCategories = {
    'غذاء': 'طعام ومشروبات',
    'فنادق': 'فنادق وإقامة',
    'أخرى': categoryOther,
  };

  static const String methodEqual = 'بالتساوي';
  static const String methodPercent = 'بالنسبة';
  static const String methodExact = 'بالمبلغ المحدد';
  static const String methodShares = 'بالحصص';

  static const List<String> methods = [
    methodEqual,
    methodPercent,
    methodExact,
    methodShares,
  ];

  /// نصيب كل مشارك من هذا المصروف بالعملة.
  ///
  /// أي طريقة لا تُنتج مجموعًا صحيحًا (نِسَب ناقصة مثلًا) تعود إلى
  /// التقسيم بالتساوي حتى لا تختلّ الأرصدة بصمت.
  Map<String, double> shareOf() {
    if (participants.isEmpty) return const {};
    switch (method) {
      case methodExact:
        final total = shares.values.fold<double>(0, (sum, v) => sum + v);
        if (total <= 0) return _equal();
        // المبالغ المحددة مكتوبة بعملة المصروف، فتُحوَّل لعملة الالتزام.
        final factor = isForeign ? rate : 1.0;
        return {
          for (final name in participants) name: (shares[name] ?? 0) * factor,
        };
      case methodPercent:
        final total = shares.values.fold<double>(0, (sum, v) => sum + v);
        if (total <= 0) return _equal();
        return {
          for (final name in participants)
            name: amount * ((shares[name] ?? 0) / total),
        };
      case methodShares:
        final total = shares.values.fold<double>(0, (sum, v) => sum + v);
        if (total <= 0) return _equal();
        return {
          for (final name in participants)
            name: amount * ((shares[name] ?? 0) / total),
        };
      default:
        return _equal();
    }
  }

  Map<String, double> _equal() {
    final share = amount / participants.length;
    return {for (final name in participants) name: share};
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
    'payer': payer,
    'date': date,
    'participants': participants,
    'method': method,
    'shares': shares,
    'note': note,
    'receipt': receipt,
    'category': category,
    'subcategory': subcategory,
    'status': status,
    'submittedBy': submittedBy,
    if (decidedAt.isNotEmpty) 'decidedAt': decidedAt,
    if (isForeign) ...{
      'currency': currency,
      'originalAmount': originalAmount,
      'rate': rate,
    },
  };

  static SharedExpense fromJson(Map<dynamic, dynamic> json) {
    final rawShares = json['shares'];
    return SharedExpense(
      id: (json['id'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      amount: double.tryParse('${json['amount']}') ?? 0,
      payer: (json['payer'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      participants: (json['participants'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      method: (json['method'] ?? methodEqual).toString(),
      shares: rawShares is Map
          ? {
              for (final entry in rawShares.entries)
                entry.key.toString():
                    double.tryParse('${entry.value}') ?? 0,
            }
          : const {},
      note: (json['note'] ?? '').toString(),
      receipt: (json['receipt'] ?? '').toString(),
      category: () {
        final value = (json['category'] ?? '').toString().trim();
        if (value.isEmpty) return categoryOther;
        return _legacyCategories[value] ?? value;
      }(),
      subcategory: (json['subcategory'] ?? '').toString().trim(),
      // السجلات القديمة بلا حالة كانت تُحسب دائمًا، فتبقى معتمدة.
      status: () {
        final value = (json['status'] ?? '').toString().trim();
        return value.isEmpty ? statusApproved : value;
      }(),
      submittedBy: (json['submittedBy'] ?? '').toString(),
      currency: (json['currency'] ?? '').toString(),
      originalAmount: double.tryParse('${json['originalAmount']}') ?? 0,
      rate: double.tryParse('${json['rate']}') ?? 1,
      decidedAt: (json['decidedAt'] ?? '').toString(),
    );
  }
}

/// تسوية: دفعة فعلية من عضو إلى آخر تُصفّي جزءًا من الرصيد.
class SharedSettlement {
  const SharedSettlement({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
    this.note = '',
    this.receipt = '',
  });

  final String id;
  final String from;
  final String to;
  final double amount;
  final String date;
  final String note;

  /// مسار صورة الإيصال المرفق مع التسوية.
  final String receipt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'amount': amount,
    'date': date,
    'note': note,
    if (receipt.isNotEmpty) 'receipt': receipt,
  };

  static SharedSettlement fromJson(Map<dynamic, dynamic> json) =>
      SharedSettlement(
        id: (json['id'] ?? '').toString(),
        from: (json['from'] ?? '').toString(),
        to: (json['to'] ?? '').toString(),
        amount: double.tryParse('${json['amount']}') ?? 0,
        date: (json['date'] ?? '').toString(),
        note: (json['note'] ?? '').toString(),
        receipt: (json['receipt'] ?? '').toString(),
      );
}

/// تحويل مقترح عند التصفية: من ← إلى ← المبلغ.
class SharedTransfer {
  const SharedTransfer({
    required this.from,
    required this.to,
    required this.amount,
  });

  final String from;
  final String to;
  final double amount;
}

/// مساهمة عضو في ميزانية الالتزام.
///
/// المساهمة الأساسية تأتي من النموذج نفسه (نصيب كل عضو عند «دفعة مقطوعة»)،
/// وهذه هي **الدفعات الإضافية** التي تُضاف بعد أن يتبيّن أن الميزانية لم
/// تكفِ — فتظهر بجانب العضو بصيغة «+200».
class SharedContribution {
  const SharedContribution({
    required this.id,
    required this.member,
    required this.amount,
    required this.date,
    this.note = '',
    this.status = SharedExpense.statusApproved,
    this.submittedBy = '',
    this.receipt = '',
    this.decidedAt = '',
  });

  /// تاريخ ووقت موافقة المسؤول أو رفضه.
  final String decidedAt;

  final String id;
  final String member;
  final double amount;
  final String date;
  final String note;

  /// مسار صورة الإيصال المرفق مع المساهمة.
  final String receipt;

  /// الميزانية الإضافية تحتاج موافقة المسؤول مثل المصروف.
  final String status;
  final String submittedBy;

  bool get isApproved => status == SharedExpense.statusApproved;
  bool get isPending => status == SharedExpense.statusPending;
  bool get isRejected => status == SharedExpense.statusRejected;

  SharedContribution withStatus(String value, {String? at}) =>
      SharedContribution(
    id: id,
    member: member,
    amount: amount,
    date: date,
    note: note,
    status: value,
    submittedBy: submittedBy,
    receipt: receipt,
    decidedAt: at ?? decidedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'member': member,
    'amount': amount,
    'date': date,
    'note': note,
    'status': status,
    'submittedBy': submittedBy,
    if (receipt.isNotEmpty) 'receipt': receipt,
    if (decidedAt.isNotEmpty) 'decidedAt': decidedAt,
  };

  static SharedContribution fromJson(Map<dynamic, dynamic> json) =>
      SharedContribution(
        id: (json['id'] ?? '').toString(),
        member: (json['member'] ?? '').toString(),
        amount: double.tryParse('${json['amount']}') ?? 0,
        date: (json['date'] ?? '').toString(),
        note: (json['note'] ?? '').toString(),
        status: () {
          final value = (json['status'] ?? '').toString().trim();
          return value.isEmpty ? SharedExpense.statusApproved : value;
        }(),
        submittedBy: (json['submittedBy'] ?? '').toString(),
        receipt: (json['receipt'] ?? '').toString(),
        decidedAt: (json['decidedAt'] ?? '').toString(),
      );
}

/// وقت تسجيل الحركة من معرّفها (وقت الإنشاء بالميلي ثانية): «14:32».
/// المعرّفات التي ليست وقتًا تعيد نصًا فارغًا.
String recordClock(String id) {
  final ms = int.tryParse(id.trim());
  if (ms == null || ms < 1000000000000) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}';
}

/// «17/10/2026 14:32» — الآن.
String recordStampNow() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.day}/${now.month}/${now.year} '
      '${two(now.hour)}:${two(now.minute)}';
}

/// قراءة وكتابة دفتر المصروفات وحساب الأرصدة.
class SharedLedger {
  SharedLedger._();

  static const String expensesKey = 'سجل المصروفات المشتركة';
  static const String settlementsKey = 'سجل التسويات';
  static const String contributionsKey = 'سجل المساهمات';

  /// نصيب كل عضو الأساسي كما أُدخل في النموذج.
  static const String baseSharesKey = 'تقسيم الأعضاء';

  /// دافع بهذا الاسم يعني أن المصروف خرج من الوعاء المشترك لا من جيب أحد،
  /// فلا يُحتسب لأي عضو.
  static const String potPayer = 'الميزانية المشتركة';

  /// تاريخ انضمام كل عضو ومغادرته: {الاسم: {join, leave}}.
  static const String memberDatesKey = 'تواريخ الأعضاء';

  /// مفاتيح الدفتر — تُستثنى من عرض التفاصيل العادي.
  static const List<String> keys = [
    expensesKey,
    settlementsKey,
    contributionsKey,
    baseSharesKey,
    memberDatesKey,
  ];

  /// تاريخ بصيغة يوم/شهر/سنة.
  static DateTime? parseDay(String raw) {
    final parts = raw.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static String formatDay(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  static Map<String, Map<String, String>> memberDates(
    Map<String, String> details,
  ) {
    final raw = details[memberDatesKey];
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            '${entry.key}': {
              for (final e in (entry.value as Map).entries)
                '${e.key}': '${e.value ?? ''}',
            },
      };
    } catch (_) {
      return {};
    }
  }

  static String encodeMemberDates(Map<String, Map<String, String>> dates) =>
      jsonEncode(dates);

  static String joinOf(Map<String, String> details, String member) =>
      memberDates(details)[member]?['join'] ?? '';

  static String leaveOf(Map<String, String> details, String member) =>
      memberDates(details)[member]?['leave'] ?? '';

  /// هل كان العضو ضمن الرحلة في هذا اليوم؟ (يوم المغادرة نفسه محسوب له.)
  static bool activeOn(
    Map<String, String> details,
    String member,
    DateTime day,
  ) {
    final dates = memberDates(details)[member];
    if (dates == null) return true;
    final join = parseDay(dates['join'] ?? '');
    final leave = parseDay(dates['leave'] ?? '');
    final only = DateTime(day.year, day.month, day.day);
    if (join != null && only.isBefore(join)) return false;
    if (leave != null && only.isAfter(leave)) return false;
    return true;
  }

  /// آخر سعر صرف استُعمل لهذه العملة في الالتزام — يُقترح في المصروف التالي.
  static Map<String, double> lastRates(Map<String, String> details) {
    final out = <String, double>{};
    // من المعتمد فقط: سعر خاطئ في مصروف مرفوض لا يُقترح.
    for (final expense in approvedExpenses(details)) {
      if (expense.isForeign && expense.rate > 0) {
        out[expense.currency] = expense.rate;
      }
    }
    return out;
  }

  static List<SharedExpense> expenses(Map<String, String> details) {
    final raw = details[expensesKey];
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(SharedExpense.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String encodeExpenses(List<SharedExpense> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());

  static List<SharedSettlement> settlements(Map<String, String> details) {
    final raw = details[settlementsKey];
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(SharedSettlement.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String encodeSettlements(List<SharedSettlement> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());

  static List<SharedContribution> contributions(Map<String, String> details) {
    final raw = details[contributionsKey];
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(SharedContribution.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String encodeContributions(List<SharedContribution> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());

  /// ما يدخل الحساب فعلًا: المعتمد وحده.
  static List<SharedExpense> approvedExpenses(Map<String, String> details) =>
      expenses(details).where((e) => e.isApproved).toList(growable: false);

  static List<SharedContribution> approvedContributions(
    Map<String, String> details,
  ) => contributions(details)
      .where((c) => c.isApproved)
      .toList(growable: false);

  /// عدد الطلبات التي تنتظر موافقة المسؤول (مصروفات وميزانيات إضافية).
  static int pendingCount(Map<String, String> details) =>
      expenses(details).where((e) => e.isPending).length +
      contributions(details).where((c) => c.isPending).length;

  static const String collectMethodKey = 'طريقة تحصيل المبلغ';
  static const String collectLumpSum = 'دفعة مقطوعة';

  /// المساهمة الأساسية لكل عضو كما أُدخلت في النموذج.
  ///
  /// لا توجد مساهمات أساسية إلا مع «دفعة مقطوعة». النموذج القديم كان يحفظ
  /// في المفتاح نفسه نِسب التقسيم أو مبالغه، فلا تُقرأ تلك مساهماتٍ.
  static Map<String, double> baseShares(Map<String, String> details) {
    if ((details[collectMethodKey] ?? '').trim() != collectLumpSum) {
      return const {};
    }
    final raw = details[baseSharesKey];
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, double>{};
      decoded.forEach((key, value) {
        final amount = parseMoney('$value') ?? 0;
        if (amount != 0) out[key.toString()] = amount;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static double baseOf(Map<String, String> details, String member) =>
      baseShares(details)[member] ?? 0;

  /// مجموع الدفعات الإضافية لهذا العضو.
  static double extraOf(Map<String, String> details, String member) =>
      approvedContributions(details)
          .where((c) => c.member == member)
          .fold<double>(0, (sum, c) => sum + c.amount);

  /// كل ما وضعه العضو فعلًا: مساهمته الأساسية + الإضافية + ما دفعه من
  /// مصروفات من جيبه.
  static double paidInOf(Map<String, String> details, String member) {
    var value = baseOf(details, member) + extraOf(details, member);
    for (final expense in approvedExpenses(details)) {
      if (expense.payer == member) value += expense.amount;
    }
    return value;
  }

  /// نصيب العضو من كل المصروفات المسجّلة.
  static double shareOfMember(Map<String, String> details, String member) {
    var value = 0.0;
    for (final expense in approvedExpenses(details)) {
      value += expense.shareOf()[member] ?? 0;
    }
    return value;
  }

  /// الميزانية المُحصَّلة: المساهمات الأساسية والإضافية مجتمعة.
  ///
  /// صفر يعني أن الالتزام بلا ميزانية مسبقة («دفع فردي»)، فتختفي كل
  /// مفردات الميزانية من الواجهة.
  static double budget(Map<String, String> details) {
    var value = baseShares(details).values.fold<double>(0, (s, v) => s + v);
    for (final contribution in approvedContributions(details)) {
      value += contribution.amount;
    }
    return value;
  }

  static bool hasBudget(Map<String, String> details) =>
      budget(details) > 0.01;

  /// المتبقي في الوعاء بعد المصروفات، وبعد ما رُدّ منه لعضو غادر أو دفعه
  /// عضو إليه (تسويات طرفها «الميزانية المشتركة»).
  static double remaining(Map<String, String> details) =>
      budget(details) - total(details) + potSettlementsNet(details);

  /// صافي التسويات مع الوعاء: ما دُفع إليه ناقص ما خرج منه.
  static double potSettlementsNet(Map<String, String> details) {
    var value = 0.0;
    for (final settlement in settlements(details)) {
      if (settlement.to == potPayer) value += settlement.amount;
      if (settlement.from == potPayer) value -= settlement.amount;
    }
    return value;
  }

  /// كل الأسماء التي لها حركة في الدفتر (بلا الميزانية المشتركة).
  static List<String> _ledgerNames(Map<String, String> details) {
    final names = <String>{
      ...baseShares(details).keys,
      for (final c in approvedContributions(details)) c.member,
      for (final e in approvedExpenses(details)) ...[
        e.payer,
        ...e.shareOf().keys,
      ],
      for (final s in settlements(details)) ...[s.from, s.to],
    }..removeWhere((n) => n.trim().isEmpty || n == potPayer);
    return names.toList();
  }

  /// صافي كل عضو تجاه بقية الأعضاء فقط (مجموعها صفر).
  ///
  /// مع الدفعة المقطوعة: رصيد العضو = ما وضعه ناقص نصيبه من المصروفات،
  /// والمتبقي في الميزانية يُرد لكل عضو من رصيده نفسه. فلا يطالب أحدٌ
  /// أحدًا إلا بما لا تغطيه الميزانية: من استهلك فوق ما وضع عليه الفرق،
  /// ويُوزَّع لمن رصيده موجب بنسبة رصيده.
  static Map<String, double> memberNets(
    Map<String, String> details,
    List<String> members,
  ) {
    final names = {...members, ..._ledgerNames(details)}.toList();
    final raw = balances(details, names);
    if (!hasBudget(details)) return raw;
    var positive = 0.0;
    var negative = 0.0;
    raw.forEach((_, v) {
      if (v > 0) positive += v;
      if (v < 0) negative -= v;
    });
    final matched = positive < negative ? positive : negative;
    return {
      for (final e in raw.entries)
        e.key: e.value > 0
            ? (positive <= 0 ? 0.0 : e.value * matched / positive)
            : (negative <= 0 ? 0.0 : e.value * matched / negative),
    };
  }

  static double memberNet(Map<String, String> details, String member) =>
      memberNets(details, [member])[member] ?? 0;

  /// التسوية المقترحة: ما يُرد من الميزانية المشتركة لكل عضو (أو يدفعه
  /// إليها)، ثم التحويلات بين الأعضاء.
  static List<SharedTransfer> settleTransfers(
    Map<String, String> details,
    List<String> members,
  ) {
    final names = {...members, ..._ledgerNames(details)}.toList();
    final raw = balances(details, names);
    final nets = memberNets(details, names);
    final out = <SharedTransfer>[];
    if (hasBudget(details)) {
      for (final name in names) {
        final pot = (raw[name] ?? 0) - (nets[name] ?? 0);
        final amount = (pot.abs() * 100).round() / 100;
        if (amount < 0.01) continue;
        out.add(
          pot > 0
              ? SharedTransfer(from: potPayer, to: name, amount: amount)
              : SharedTransfer(from: name, to: potPayer, amount: amount),
        );
      }
    }
    return [...out, ...simplify(nets)];
  }

  /// مجموع المصروفات المسجَّلة.
  static double total(Map<String, String> details) =>
      approvedExpenses(details).fold<double>(0, (sum, e) => sum + e.amount);

  /// مجموع كل فئة، مرتّبًا من الأكثر صرفًا إلى الأقل.
  static List<MapEntry<String, double>> totalsByCategory(
    Map<String, String> details,
  ) {
    final sums = <String, double>{};
    for (final expense in approvedExpenses(details)) {
      sums[expense.category] = (sums[expense.category] ?? 0) + expense.amount;
    }
    final rows = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return rows;
  }

  /// صافي رصيد كل عضو: موجب = له، سالب = عليه.
  ///
  /// من دفع يُضاف له المبلغ كاملًا، ويُخصم من كل مشارك نصيبه. ثم تُطرح
  /// التسويات المسجَّلة.
  static Map<String, double> balances(
    Map<String, String> details,
    List<String> members,
  ) {
    final net = <String, double>{for (final name in members) name: 0};
    // الوعاء المشترك ليس عضوًا، وكذلك اسم شخص حُذف من القائمة: لا رصيد له.
    void add(String name, double value) {
      if (!net.containsKey(name)) return;
      net[name] = (net[name] ?? 0) + value;
    }

    // ما وضعه العضو في الوعاء أساسيًا أو إضافيًا يُحسب له.
    baseShares(details).forEach(add);
    for (final contribution in approvedContributions(details)) {
      add(contribution.member, contribution.amount);
    }
    for (final expense in approvedExpenses(details)) {
      add(expense.payer, expense.amount);
      expense.shareOf().forEach((name, share) => add(name, -share));
    }
    for (final settlement in settlements(details)) {
      // من يدفع تسوية يقلّ ما عليه، ومن يستلم يقلّ ما له.
      add(settlement.from, settlement.amount);
      add(settlement.to, -settlement.amount);
    }
    return net;
  }

  /// تبسيط الديون: أقل عدد تحويلات يُصفّي كل الأرصدة.
  ///
  /// خوارزمية جشعة: يُطابَق أكبر دائن بأكبر مدين ويُحوَّل بينهما الأصغر
  /// من الرقمين، ثم يُعاد الحساب حتى تصفر الأرصدة كلها.
  static List<SharedTransfer> simplify(Map<String, double> balances) {
    const epsilon = 0.01;
    final creditors = <MapEntry<String, double>>[];
    final debtors = <MapEntry<String, double>>[];
    balances.forEach((name, value) {
      if (value > epsilon) creditors.add(MapEntry(name, value));
      if (value < -epsilon) debtors.add(MapEntry(name, -value));
    });
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final out = <SharedTransfer>[];
    var i = 0;
    var j = 0;
    var creditLeft = creditors.isEmpty ? 0.0 : creditors.first.value;
    var debtLeft = debtors.isEmpty ? 0.0 : debtors.first.value;
    while (i < creditors.length && j < debtors.length) {
      final amount = creditLeft < debtLeft ? creditLeft : debtLeft;
      if (amount > epsilon) {
        out.add(
          SharedTransfer(
            from: debtors[j].key,
            to: creditors[i].key,
            amount: amount,
          ),
        );
      }
      creditLeft -= amount;
      debtLeft -= amount;
      if (creditLeft <= epsilon) {
        i += 1;
        if (i < creditors.length) creditLeft = creditors[i].value;
      }
      if (debtLeft <= epsilon) {
        j += 1;
        if (j < debtors.length) debtLeft = debtors[j].value;
      }
    }
    return out;
  }
}
