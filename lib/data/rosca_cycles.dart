import 'dart:convert';

/// دورات الجمعية المالية.
///
/// الجمعية ليست مصروفات متفرقة يدفعها من حضر — هي **مساهمة ثابتة متكررة
/// ودور استلام**. وعدد الدورات وتكرارها وتاريخ بدايتها وترتيب الأعضاء كلها
/// معطيات موجودة أصلًا في بيانات الجمعية، فتُشتق منها جداول الدورات اشتقاقًا
/// بلا إدخال يدوي. ولا يُحفظ إلا ما يقع فعلًا: من دفع في كل دورة وكم ومتى،
/// ومتى سُلِّم المبلغ لصاحب الدور.
///
/// كل هذا يُخزَّن JSON داخل تفاصيل الالتزام نفسه، بلا أي تعديل على مخطط
/// قاعدة البيانات.

/// تحويل «يوم/شهر/سنة» المستعمل في كل حقول التاريخ إلى تاريخ حقيقي.
DateTime? roscaParseDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split(RegExp(r'[/\-\.]'));
  if (parts.length < 3) return null;
  final a = int.tryParse(parts[0].trim());
  final b = int.tryParse(parts[1].trim());
  final c = int.tryParse(parts[2].trim());
  if (a == null || b == null || c == null) return null;
  // التنسيق المعتمد في التطبيق: يوم/شهر/سنة. وإن جاءت السنة أولًا نقبلها.
  if (a > 31) return DateTime(a, b, c);
  return DateTime(c, b, a);
}

String roscaFormatDate(DateTime date) =>
    '${date.day}/${date.month}/${date.year}';

DateTime _addMonths(DateTime start, int steps) {
  final total = start.month - 1 + steps;
  final year = start.year + (total ~/ 12);
  final month = (total % 12) + 1;
  // آخر يوم في الشهر الهدف، حتى لا يتحوّل 31 يناير إلى 3 مارس.
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = start.day > lastDay ? lastDay : start.day;
  return DateTime(year, month, day);
}

/// موعد الدورة رقم (steps + 1) انطلاقًا من تاريخ البداية وتكرار المساهمة.
DateTime roscaCycleDate(DateTime start, String frequency, int steps) {
  switch (frequency.trim()) {
    case 'أسبوعي':
      return start.add(Duration(days: 7 * steps));
    case 'نصف شهري':
      return start.add(Duration(days: 15 * steps));
    case 'سنوي':
      return _addMonths(start, 12 * steps);
    default:
      return _addMonths(start, steps);
  }
}

/// مساهمة عضو واحد في دورة واحدة.
class RoscaPayment {
  const RoscaPayment({
    required this.id,
    required this.member,
    required this.amount,
    required this.date,
    this.note = '',
    this.receipt = '',
  });

  final String id;
  final String member;
  final double amount;
  final String date;
  final String note;

  /// مسار المستند المرفق مع المساهمة (صورة الإيصال).
  final String receipt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'member': member,
    'amount': amount,
    'date': date,
    'note': note,
    if (receipt.isNotEmpty) 'receipt': receipt,
  };

  static RoscaPayment fromJson(Map<dynamic, dynamic> json) => RoscaPayment(
    id: (json['id'] ?? '').toString(),
    member: (json['member'] ?? '').toString(),
    amount: double.tryParse('${json['amount']}') ?? 0,
    date: (json['date'] ?? '').toString(),
    note: (json['note'] ?? '').toString(),
    receipt: (json['receipt'] ?? '').toString(),
  );
}

/// دورة واحدة من دورات الجمعية.
class RoscaCycle {
  const RoscaCycle({
    required this.index,
    required this.dueDate,
    required this.receiver,
    required this.payments,
    required this.share,
    required this.membersCount,
    required this.payoutDate,
    this.note = '',
    this.memberShares = const {},
  });

  /// مساهمة كل عضو إن عُدّلت يدويًا (وإلا فالحصة المتساوية [share]).
  final Map<String, double> memberShares;

  double shareOf(String member) => memberShares[member] ?? share;

  /// رقم الدورة، يبدأ من 1.
  final int index;

  /// موعد استحقاق المساهمة في هذه الدورة (مشتق، غير محفوظ).
  final DateTime? dueDate;

  /// صاحب الدور: من يستلم مجموع الدورة.
  final String receiver;

  final List<RoscaPayment> payments;

  /// المساهمة المستحقة على الفرد الواحد.
  final double share;

  final int membersCount;

  /// تاريخ تسليم المبلغ لصاحب الدور — فارغ يعني لم يُسلَّم بعد.
  final String payoutDate;

  final String note;

  static const String statusDone = 'مكتملة';
  static const String statusLate = 'متأخرة';
  static const String statusOpen = 'جارية';
  static const String statusNext = 'قادمة';

  /// المستهدف تحصيله في هذه الدورة.
  double get target {
    if (memberShares.isEmpty) return share * membersCount;
    final custom = memberShares.values.fold<double>(0, (s, v) => s + v);
    final rest = membersCount - memberShares.length;
    return custom + (rest > 0 ? share * rest : 0);
  }

  double get collected =>
      payments.fold<double>(0, (sum, p) => sum + p.amount);

  double get remaining {
    final value = target - collected;
    return value <= 0 ? 0 : value;
  }

  double get progress {
    if (target <= 0) return payments.isEmpty ? 0 : 1;
    final value = collected / target;
    return value > 1 ? 1 : value;
  }

  double paidBy(String member) => payments
      .where((p) => p.member == member)
      .fold<double>(0, (sum, p) => sum + p.amount);

  /// يُعتبر العضو دافعًا إذا بلغ ما سدّده حصته المقرّرة.
  bool memberPaid(String member) {
    final paid = paidBy(member);
    final due = shareOf(member);
    if (due <= 0) return paid > 0;
    return paid + 0.01 >= due;
  }

  List<String> paidOf(List<String> members) =>
      members.where(memberPaid).toList(growable: false);

  List<String> unpaidOf(List<String> members) =>
      members.where((m) => !memberPaid(m)).toList(growable: false);

  bool get isComplete =>
      target > 0 ? remaining <= 0.01 : payments.isNotEmpty;

  bool get isPaidOut => payoutDate.trim().isNotEmpty;

  String get dueText => dueDate == null ? '—' : roscaFormatDate(dueDate!);
}

/// خطة الجمعية كاملة: الدورات المشتقّة + ما سُجّل عليها.
class RoscaPlan {
  const RoscaPlan({
    required this.cycles,
    required this.members,
    required this.share,
    required this.frequency,
    this.memberShares = const {},
  });

  final List<RoscaCycle> cycles;
  final List<String> members;
  final double share;
  final String frequency;

  /// مساهمة كل عضو إن عُدّلت يدويًا عند الإضافة.
  final Map<String, double> memberShares;

  double shareOf(String member) => memberShares[member] ?? share;

  /// ما يُجمع في الدورة الواحدة (ويستلمه صاحب الدور).
  double get cycleTotal =>
      members.fold<double>(0, (sum, m) => sum + shareOf(m));

  bool get isEmpty => cycles.isEmpty;

  /// أول دورة لم تكتمل — هي الدورة الجارية.
  RoscaCycle? get current {
    for (final cycle in cycles) {
      if (!cycle.isComplete) return cycle;
    }
    return null;
  }

  int get completedCount => cycles.where((c) => c.isComplete).length;

  double get collectedTotal =>
      cycles.fold<double>(0, (sum, c) => sum + c.collected);

  double get targetTotal => cycles.fold<double>(0, (sum, c) => sum + c.target);

  double get remainingTotal {
    final value = targetTotal - collectedTotal;
    return value <= 0 ? 0 : value;
  }

  /// حالة الدورة: مكتملة / متأخرة / جارية / قادمة.
  String statusOf(RoscaCycle cycle, [DateTime? now]) {
    if (cycle.isComplete) return RoscaCycle.statusDone;
    // أي دورة فات موعدها ولم تكتمل «متأخرة» — لا الجارية وحدها.
    final due = cycle.dueDate;
    if (due != null) {
      final today = now ?? DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(day)) return RoscaCycle.statusLate;
    }
    final currentIndex = current?.index;
    if (currentIndex == null || cycle.index != currentIndex) {
      return RoscaCycle.statusNext;
    }
    return RoscaCycle.statusOpen;
  }

  /// عدد الدورات المستحقة (حلّ موعدها) ولم يدفعها هذا العضو.
  int overdueOf(String member, [DateTime? now]) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    var count = 0;
    for (final cycle in cycles) {
      final due = cycle.dueDate;
      if (due == null) continue;
      // يوم الاستحقاق نفسه ليس تأخرًا: المتأخر ما فات موعده.
      if (!DateTime(due.year, due.month, due.day).isBefore(day)) continue;
      if (!cycle.memberPaid(member)) count += 1;
    }
    return count;
  }

  /// عدد الدورات التي سدّدها العضو.
  int paidCountOf(String member) =>
      cycles.where((c) => c.memberPaid(member)).length;

  double paidTotalOf(String member) =>
      cycles.fold<double>(0, (sum, c) => sum + c.paidBy(member));

  /// رقم دورة استلام هذا العضو، أو null إن لم يكن له دور.
  int? turnOf(String member) {
    for (final cycle in cycles) {
      if (cycle.receiver == member) return cycle.index;
    }
    return null;
  }

  /// هل استلم العضو دوره فعلًا (سُلِّم له المبلغ)؟
  bool receivedBy(String member) {
    for (final cycle in cycles) {
      if (cycle.receiver == member && cycle.isPaidOut) return true;
    }
    return false;
  }
}

/// قراءة وكتابة سجل الدورات داخل تفاصيل الالتزام.
class RoscaLedger {
  RoscaLedger._();

  /// المفتاح الوحيد المحفوظ: خريطة رقم الدورة ← {المدفوعات، المستلم، التسليم}.
  static const String cyclesKey = 'سجل دورات الجمعية';

  // مفاتيح موجودة أصلًا في نموذج الجمعية — تُقرأ ولا تُكتب هنا.
  static const String countKey = 'عدد الدورات';
  static const String shareKey = 'المساهمة على الشخص';
  static const String totalKey = 'إجمالي المساهمة';
  static const String frequencyKey = 'تكرار المساهمة';
  static const String startKey = 'تاريخ البداية';
  static const String memberSharesKey = 'تقسيم الأعضاء';

  static Map<String, dynamic> store(Map<String, String> details) {
    final raw = details[cyclesKey];
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      return {
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String encode(Map<String, dynamic> data) => jsonEncode(data);

  static Map<String, dynamic> _cycleAt(Map<String, dynamic> data, int index) {
    final entry = data['$index'];
    if (entry is! Map) return <String, dynamic>{};
    return {for (final e in entry.entries) e.key.toString(): e.value};
  }

  /// بناء خطة الجمعية: الدورات مشتقّة من الإعدادات، والمدفوعات من المحفوظ.
  ///
  /// تغيير عدد الدورات أو تاريخ البداية لاحقًا يعيد بناء الجدول بلا فقدان
  /// أي دفعة، لأن المدفوعات مربوطة برقم الدورة لا بموعدها.
  static RoscaPlan plan(Map<String, String> details, List<String> members) {
    final data = store(details);
    final frequency = (details[frequencyKey] ?? 'شهري').trim();
    final start = roscaParseDate(details[startKey] ?? '');

    // التقسيم بالتساوي دائمًا: الإجمالي ÷ عدد الأعضاء، فلا يُقبل رقم
    // يخالف الإجمالي. القيمة المحفوظة احتياط للسجلات بلا إجمالي فقط.
    final total = double.tryParse((details[totalKey] ?? '').trim()) ?? 0;
    var share = total > 0 && members.isNotEmpty
        ? total / members.length
        : double.tryParse((details[shareKey] ?? '').trim()) ?? 0;

    // مساهمة كل عضو كما وُزّعت أو عُدّلت عند الإضافة («تقسيم الأعضاء»).
    final memberShares = <String, double>{};
    try {
      final raw = details[memberSharesKey];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final amount = double.tryParse('$value');
            if (amount != null && amount > 0 && members.contains('$key')) {
              memberShares['$key'] = amount;
            }
          });
        }
      }
    } catch (_) {}
    // عضو أُضيف بعد التوزيع: التوزيع القديم لا يطابق العدد الجديد، فيُقسَّم
    // الإجمالي بالتساوي حتى لا يدفع أحد أكثر مما يستلم.
    if (memberShares.isNotEmpty && memberShares.length != members.length) {
      memberShares.clear();
    }

    // عدد الدورات تلقائي: دورة لكل عضو يستلم فيها.
    var count = members.length;
    if (count <= 0) count = int.tryParse((details[countKey] ?? '').trim()) ?? 0;
    if (count <= 0) count = data.length;

    final cycles = <RoscaCycle>[];
    for (var i = 1; i <= count; i++) {
      final saved = _cycleAt(data, i);
      final payments = (saved['payments'] as List? ?? const [])
          .whereType<Map>()
          .map(RoscaPayment.fromJson)
          .toList(growable: false);
      final savedReceiver = (saved['receiver'] ?? '').toString().trim();
      // الافتراضي: ترتيب الأعضاء في النموذج هو ترتيب الاستلام.
      final receiver = savedReceiver.isNotEmpty
          ? savedReceiver
          : (members.length >= i ? members[i - 1] : '');
      cycles.add(
        RoscaCycle(
          index: i,
          dueDate: start == null
              ? null
              : roscaCycleDate(start, frequency, i - 1),
          receiver: receiver,
          payments: payments,
          share: share,
          membersCount: members.length,
          payoutDate: (saved['payout'] ?? '').toString(),
          note: (saved['note'] ?? '').toString(),
          memberShares: memberShares,
        ),
      );
    }
    return RoscaPlan(
      cycles: cycles,
      members: members,
      share: share,
      frequency: frequency,
      memberShares: memberShares,
    );
  }

  static String withPayment(
    Map<String, String> details,
    int index,
    RoscaPayment payment,
  ) {
    final data = store(details);
    final cycle = _cycleAt(data, index);
    final rows = [
      ...(cycle['payments'] as List? ?? const []),
      payment.toJson(),
    ];
    cycle['payments'] = rows;
    data['$index'] = cycle;
    return encode(data);
  }

  static String withPayments(
    Map<String, String> details,
    int index,
    List<RoscaPayment> payments,
  ) {
    final data = store(details);
    final cycle = _cycleAt(data, index);
    cycle['payments'] = [
      ...(cycle['payments'] as List? ?? const []),
      ...payments.map((p) => p.toJson()),
    ];
    data['$index'] = cycle;
    return encode(data);
  }

  static String withoutPayment(
    Map<String, String> details,
    int index,
    String paymentId,
  ) {
    final data = store(details);
    final cycle = _cycleAt(data, index);
    final rows = (cycle['payments'] as List? ?? const [])
        .whereType<Map>()
        .where((row) => (row['id'] ?? '').toString() != paymentId)
        .toList();
    cycle['payments'] = rows;
    data['$index'] = cycle;
    return encode(data);
  }

  static String withReceiver(
    Map<String, String> details,
    int index,
    String receiver,
  ) {
    final data = store(details);
    final cycle = _cycleAt(data, index);
    cycle['receiver'] = receiver;
    data['$index'] = cycle;
    return encode(data);
  }

  /// تسجيل تسليم مبلغ الدورة لصاحب الدور — تمريرُ نصٍّ فارغ يلغي التسليم.
  static String withPayout(
    Map<String, String> details,
    int index,
    String date,
  ) {
    final data = store(details);
    final cycle = _cycleAt(data, index);
    cycle['payout'] = date;
    data['$index'] = cycle;
    return encode(data);
  }
}
