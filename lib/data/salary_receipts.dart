import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// سند قبض: راتب شهر لموظف (برقمه التعريفي)، أو سند قبض عام.
///
/// يوقّعه المستلم على جوال صاحب العمل (معتمد مباشرة)، أو يُرسل إليه
/// للاعتماد والتوقيع (بانتظار الاعتماد ثم معتمد أو مرفوض).
class SalaryReceipt {
  const SalaryReceipt({
    this.id,
    this.ownerId = '',
    this.kind = kindSalary,
    this.employeeFnd = '',
    this.employeeName = '',
    this.ownerName = '',
    this.period = '',
    this.receiptDate = '',
    this.basic = 0,
    this.allowances = 0,
    this.overtime = 0,
    this.loan = 0,
    this.deductions = 0,
    this.total = 0,
    this.paid = 0,
    this.currency = '',
    this.description = '',
    this.notes = '',
    this.signMode = signHere,
    this.status = statusPending,
    this.signature = '',
    this.signedAt,
    this.rejectReason = '',
    this.expenseId = '',
    this.createdAt,
  });

  static const kindSalary = 'راتب';
  static const kindGeneral = 'عام';
  static const signHere = 'here';
  static const signRemote = 'remote';
  static const statusPending = 'بانتظار الاعتماد';
  static const statusApproved = 'معتمد';
  static const statusRejected = 'مرفوض';

  static const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  final String? id;
  final String ownerId;
  final String kind;
  final String employeeFnd;
  final String employeeName;
  final String ownerName;

  /// شهر الراتب: «2026-03».
  final String period;

  /// تاريخ السند: «1/3/2026».
  final String receiptDate;
  final double basic;
  final double allowances;
  final double overtime;
  final double loan;
  final double deductions;
  final double total;
  final double paid;
  final String currency;
  final String description;
  final String notes;
  final String signMode;
  final String status;

  /// التوقيع خطوطًا بنقاط نسبية (0..1) — JSON.
  final String signature;
  final DateTime? signedAt;
  final String rejectReason;

  /// المصروف المسجَّل له في الالتزامات الشخصية.
  final String expenseId;
  final DateTime? createdAt;

  bool get isSalary => kind == kindSalary;
  bool get isPending => status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isRejected => status == statusRejected;

  int? get year => int.tryParse(period.split('-').first);
  int? get month {
    final parts = period.split('-');
    return parts.length > 1 ? int.tryParse(parts[1]) : null;
  }

  /// «مارس 2026».
  String get periodLabel {
    final m = month;
    final y = year;
    if (m == null || y == null || m < 1 || m > 12) return period;
    return '${months[m - 1]} $y';
  }

  /// «راتب مارس 2026» أو بيان السند العام.
  String get title => isSalary
      ? 'راتب $periodLabel'
      : (description.trim().isEmpty ? 'سند قبض' : description.trim());

  List<List<Offset>> get strokes => decodeStrokes(signature);

  static String periodOf(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  static String encodeStrokes(List<List<Offset>> strokes) => jsonEncode([
    for (final stroke in strokes)
      [
        for (final p in stroke)
          [
            double.parse(p.dx.toStringAsFixed(3)),
            double.parse(p.dy.toStringAsFixed(3)),
          ],
      ],
  ]);

  static List<List<Offset>> decodeStrokes(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final stroke in decoded)
          if (stroke is List)
            [
              for (final point in stroke)
                if (point is List && point.length >= 2)
                  Offset(
                    (point[0] as num).toDouble(),
                    (point[1] as num).toDouble(),
                  ),
            ],
      ].where((s) => s.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  factory SalaryReceipt.fromJson(Map<String, dynamic> j) => SalaryReceipt(
    id: '${j['id'] ?? ''}',
    ownerId: '${j['user_id'] ?? ''}',
    kind: '${j['kind'] ?? kindSalary}',
    employeeFnd: '${j['employee_fnd'] ?? ''}',
    employeeName: '${j['employee_name'] ?? ''}',
    ownerName: '${j['owner_name'] ?? ''}',
    period: '${j['period'] ?? ''}',
    receiptDate: '${j['receipt_date'] ?? ''}',
    basic: _num(j['basic']),
    allowances: _num(j['allowances']),
    overtime: _num(j['overtime']),
    loan: _num(j['loan']),
    deductions: _num(j['deductions']),
    total: _num(j['total']),
    paid: _num(j['paid']),
    currency: '${j['currency'] ?? ''}',
    description: '${j['description'] ?? ''}',
    notes: '${j['notes'] ?? ''}',
    signMode: '${j['sign_mode'] ?? signHere}',
    status: '${j['status'] ?? statusPending}',
    signature: '${j['signature'] ?? ''}',
    signedAt: DateTime.tryParse('${j['signed_at'] ?? ''}'),
    rejectReason: '${j['reject_reason'] ?? ''}',
    expenseId: '${j['expense_id'] ?? ''}',
    createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
  );

  Map<String, dynamic> toRow() => {
    'kind': kind,
    'employee_fnd': employeeFnd,
    'employee_name': employeeName,
    'owner_name': ownerName,
    'period': period,
    'receipt_date': receiptDate,
    'basic': basic,
    'allowances': allowances,
    'overtime': overtime,
    'loan': loan,
    'deductions': deductions,
    'total': total,
    'paid': paid,
    'currency': currency,
    'description': description,
    'notes': notes,
    'sign_mode': signMode,
    'status': status,
    'signature': signature,
    'signed_at': signedAt?.toUtc().toIso8601String(),
    'reject_reason': rejectReason,
    'expense_id': expenseId,
  };

  SalaryReceipt copyWith({
    String? id,
    String? status,
    String? signature,
    DateTime? signedAt,
    bool clearSignedAt = false,
    String? rejectReason,
    String? expenseId,
    String? signMode,
  }) => SalaryReceipt(
    id: id ?? this.id,
    ownerId: ownerId,
    kind: kind,
    employeeFnd: employeeFnd,
    employeeName: employeeName,
    ownerName: ownerName,
    period: period,
    receiptDate: receiptDate,
    basic: basic,
    allowances: allowances,
    overtime: overtime,
    loan: loan,
    deductions: deductions,
    total: total,
    paid: paid,
    currency: currency,
    description: description,
    notes: notes,
    signMode: signMode ?? this.signMode,
    status: status ?? this.status,
    signature: signature ?? this.signature,
    signedAt: clearSignedAt ? null : (signedAt ?? this.signedAt),
    rejectReason: rejectReason ?? this.rejectReason,
    expenseId: expenseId ?? this.expenseId,
    createdAt: createdAt,
  );
}

class SalaryReceiptsRepository {
  SalaryReceiptsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _table = 'fundly_salary_receipts';
  static const _timeout = Duration(seconds: 20);

  /// السندات التي أصدرتها.
  Future<List<SalaryReceipt>> fetchMine() async {
    final user = await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_table)
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return _sorted(rows.map(SalaryReceipt.fromJson));
  }

  /// السندات التي أُرسلت إلى رقمي التعريفي.
  Future<List<SalaryReceipt>> fetchSentToMe(String myFnd) async {
    if (myFnd.trim().isEmpty) return const [];
    await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_table)
        .select()
        .eq('employee_fnd', myFnd.trim())
        .order('created_at', ascending: false)
        .timeout(_timeout);
    return _sorted(rows.map(SalaryReceipt.fromJson));
  }

  /// الأحدث شهرًا أولًا، ثم الأحدث تسجيلًا.
  static List<SalaryReceipt> _sorted(Iterable<SalaryReceipt> items) =>
      items.toList()..sort((a, b) {
        final byPeriod = b.period.compareTo(a.period);
        if (byPeriod != 0) return byPeriod;
        return (b.createdAt ?? DateTime(1970)).compareTo(
          a.createdAt ?? DateTime(1970),
        );
      });

  Future<SalaryReceipt?> fetchOne(String id) async {
    await AppSession.ensureSignedIn();
    final row = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle()
        .timeout(_timeout);
    return row == null ? null : SalaryReceipt.fromJson(row);
  }

  Future<SalaryReceipt> create(SalaryReceipt receipt) async {
    await AppSession.ensureSignedIn();
    final row = await _client
        .from(_table)
        .insert(receipt.toRow())
        .select()
        .single()
        .timeout(_timeout);
    return SalaryReceipt.fromJson(row);
  }

  Future<SalaryReceipt> update(SalaryReceipt receipt) async {
    await AppSession.ensureSignedIn();
    final row = await _client
        .from(_table)
        .update(receipt.toRow())
        .eq('id', receipt.id!)
        .select()
        .single()
        .timeout(_timeout);
    return SalaryReceipt.fromJson(row);
  }

  Future<void> delete(String id) async {
    await AppSession.ensureSignedIn();
    await _client.from(_table).delete().eq('id', id).timeout(_timeout);
  }

  /// رد الموظف. يعيد null عند النجاح، أو رسالة توضح السبب.
  Future<String?> respond(
    String id,
    bool accept, {
    String signature = '',
    String reason = '',
    String name = '',
  }) async {
    await AppSession.ensureSignedIn();
    final result = await _client
        .rpc(
          'fundly_salary_respond',
          params: {
            'p_id': id,
            'p_accept': accept,
            'p_signature': signature,
            'p_reason': reason,
            'p_name': name,
          },
        )
        .timeout(_timeout);
    return switch ('${result ?? ''}') {
      'ok' => null,
      'answered' => 'سبق الرد على هذا السند',
      'no_signature' => 'التوقيع مطلوب للموافقة',
      'no_name' => 'اكتب اسمك الثلاثي لإكمال الاعتماد',
      'not_yours' || 'not_found' => 'لم يعد هذا السند قائمًا',
      _ => 'تعذّر الحفظ. حاول مرة أخرى.',
    };
  }
}
