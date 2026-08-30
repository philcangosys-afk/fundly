import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// تفويض ممنوح لشخص أو جهة على نطاق محدَّد من التطبيق.
///
/// كانت التفويضات تُحفظ في قائمة داخل الذاكرة مصحوبة بثلاثة سجلات وهمية:
/// كل إضافة أو تعديل أو حذف يضيع بمجرد الخروج من الصفحة، وتعود البيانات
/// الوهمية في كل مرة. الآن تُحفظ فعليًا مثل بقية بيانات التطبيق.
class DelegationRecord {
  /// نطاقات التفويض — تطابق وحدات التطبيق الفعلية، فلا يُمنح تفويض على
  /// شيء غير موجود.
  static const scopes = [
    'الالتزامات الشخصية',
    'الالتزامات المشتركة',
    'العقارات والأنشطة',
    'الأشخاص والجهات',
    'المحافظ والمدفوعات',
    'المستندات والتقارير',
  ];

  static const allPermissions = [
    'عرض البيانات',
    'إضافة السجلات',
    'تعديل السجلات',
    'حذف السجلات',
    'الموافقة على الطلبات',
  ];

  final String? id;
  final String delegateName;
  final String? delegateRef;
  final String scope;
  final List<String> permissions;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPaused;
  final String? notes;

  const DelegationRecord({
    this.id,
    required this.delegateName,
    this.delegateRef,
    this.scope = 'الالتزامات الشخصية',
    this.permissions = const [],
    this.startDate,
    this.endDate,
    this.isPaused = false,
    this.notes,
  });

  // ===== حالة التفويض — مشتقّة من التواريخ والإيقاف، لا مخزَّنة =====
  // تخزين الحالة كحقل مستقل يجعلها تتقادم: تفويض انتهى أمس يبقى "نشطًا"
  // إلى أن يفتح أحدهم الصفحة ويحدّثه يدويًا.

  bool get isEnded => endDate != null && endDate!.isBefore(DateTime.now());

  bool get isScheduled =>
      !isPaused && startDate != null && startDate!.isAfter(DateTime.now());

  bool get isActive => !isPaused && !isEnded && !isScheduled;

  bool get isExpiringSoon {
    if (!isActive || endDate == null) return false;
    final remaining = endDate!.difference(DateTime.now()).inDays;
    return remaining >= 0 && remaining <= 30;
  }

  /// الأيام المتبقية (سالبة إن انتهى).
  int? get remainingDays =>
      endDate == null ? null : endDate!.difference(DateTime.now()).inDays;

  String get statusLabel {
    if (isEnded) return 'منتهي';
    if (isPaused) return 'موقوف';
    if (isScheduled) return 'مجدول';
    if (isExpiringSoon) return 'قارب الانتهاء';
    return 'نشط';
  }

  factory DelegationRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return DelegationRecord(
      id: json['id'] as String?,
      delegateName: json['delegate_name'] as String? ?? '',
      delegateRef: json['delegate_ref'] as String?,
      scope: json['scope'] as String? ?? scopes.first,
      permissions: (json['permissions'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      startDate: parse(json['start_date']),
      endDate: parse(json['end_date']),
      isPaused: json['is_paused'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'delegate_name': delegateName,
    'delegate_ref': delegateRef,
    'scope': scope,
    'permissions': permissions,
    'start_date': startDate?.toIso8601String().split('T').first,
    'end_date': endDate?.toIso8601String().split('T').first,
    'is_paused': isPaused,
    'notes': notes,
  };

  DelegationRecord copyWith({
    String? id,
    String? delegateName,
    String? delegateRef,
    String? scope,
    List<String>? permissions,
    DateTime? startDate,
    DateTime? endDate,
    bool? isPaused,
    String? notes,
  }) => DelegationRecord(
    id: id ?? this.id,
    delegateName: delegateName ?? this.delegateName,
    delegateRef: delegateRef ?? this.delegateRef,
    scope: scope ?? this.scope,
    permissions: permissions ?? this.permissions,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isPaused: isPaused ?? this.isPaused,
    notes: notes ?? this.notes,
  );
}

/// مستند/إيصال أنشأه المستخدم من أحد القوالب.
class DocumentRecordEntry {
  final String? id;
  final String docType;
  final Map<String, String> fields;

  /// الربط بكيان حقيقي داخل التطبيق (شخص، عقار/نشاط، محفظة، تفويض).
  final String? linkedKind;
  final String? linkedLabel;
  final String? linkedId;

  final String? docNumber;
  final DateTime? issuedOn;
  final String? notes;

  const DocumentRecordEntry({
    this.id,
    required this.docType,
    this.fields = const {},
    this.linkedKind,
    this.linkedLabel,
    this.linkedId,
    this.docNumber,
    this.issuedOn,
    this.notes,
  });

  factory DocumentRecordEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['fields'] as Map<String, dynamic>? ?? const {};
    return DocumentRecordEntry(
      id: json['id'] as String?,
      docType: json['doc_type'] as String? ?? '',
      fields: raw.map((k, v) => MapEntry(k, v?.toString() ?? '')),
      linkedKind: json['linked_kind'] as String?,
      linkedLabel: json['linked_label'] as String?,
      linkedId: json['linked_id'] as String?,
      docNumber: json['doc_number'] as String?,
      issuedOn: json['issued_on'] == null
          ? null
          : DateTime.tryParse(json['issued_on'].toString()),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'doc_type': docType,
    'fields': fields,
    'linked_kind': linkedKind,
    'linked_label': linkedLabel,
    'linked_id': linkedId,
    'doc_number': docNumber,
    'issued_on': issuedOn?.toIso8601String().split('T').first,
    'notes': notes,
  };
}

abstract class DelegationsRepository {
  Future<List<DelegationRecord>> fetchDelegations();
  Future<DelegationRecord> upsertDelegation(DelegationRecord delegation);
  Future<void> deleteDelegation(String id);

  Future<List<DocumentRecordEntry>> fetchDocuments();
  Future<DocumentRecordEntry> upsertDocument(DocumentRecordEntry document);
  Future<void> deleteDocument(String id);
}

class SupabaseDelegationsRepository implements DelegationsRepository {
  static const _delegationsTable = 'delegations';
  static const _documentsTable = 'document_records';
  static const _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _client;

  SupabaseDelegationsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<DelegationRecord>> fetchDelegations() async {
    await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_delegationsTable)
        .select()
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows.map(DelegationRecord.fromJson).toList(growable: false);
  }

  @override
  Future<DelegationRecord> upsertDelegation(DelegationRecord d) async {
    final user = await AppSession.ensureSignedIn();
    Map<String, dynamic> row;
    if (d.id == null) {
      row = await _client
          .from(_delegationsTable)
          .insert(d.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_delegationsTable)
          .update(d.toJson(user.id))
          .eq('id', d.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return DelegationRecord.fromJson(row);
  }

  @override
  Future<void> deleteDelegation(String id) async {
    await AppSession.ensureSignedIn();
    await _client
        .from(_delegationsTable)
        .delete()
        .eq('id', id)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<DocumentRecordEntry>> fetchDocuments() async {
    await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_documentsTable)
        .select()
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows.map(DocumentRecordEntry.fromJson).toList(growable: false);
  }

  @override
  Future<DocumentRecordEntry> upsertDocument(DocumentRecordEntry doc) async {
    final user = await AppSession.ensureSignedIn();
    Map<String, dynamic> row;
    if (doc.id == null) {
      row = await _client
          .from(_documentsTable)
          .insert(doc.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_documentsTable)
          .update(doc.toJson(user.id))
          .eq('id', doc.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return DocumentRecordEntry.fromJson(row);
  }

  @override
  Future<void> deleteDocument(String id) async {
    await AppSession.ensureSignedIn();
    await _client
        .from(_documentsTable)
        .delete()
        .eq('id', id)
        .timeout(_requestTimeout);
  }
}
