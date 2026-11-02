import 'subscription_plans.dart';
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
  /// النطاقات الرئيسية — بأسمائها الحقيقية كما تظهر في التطبيق نفسه،
  /// فلا يُمنح تفويض على قسم باسم مختصر لا وجود له في الواجهة.
  static const scopes = [
    'كل الأقسام',
    'الالتزامات الشخصية',
    'الالتزامات المشتركة',
    'الأفراد والجهات',
    'العقارات والأنشطة والمركبات',
    'المستندات',
    'التقارير والأرشيف',
    'التنبيهات والكلندر ومراكز المتابعة',
    'الإعدادات والتفويضات',
  ];

  /// الأقسام الفرعية لكل نطاق رئيسي — تتيح تفويضًا أدقّ من "قسم كامل":
  /// مثلاً تفويض على "المعدات" وحدها داخل العقارات والأنشطة.
  static const subScopes = <String, List<String>>{
    // نفس فئات كل شاشة كما تظهر فيها.
    'الالتزامات الشخصية': [
      'مالية',
      'مستند',
      'المتابعة والتخطيط',
      'أدوية وبيانات وكلمات سر',
      'نمط الحياة',
      'مواقع وأماكن',
      'عهدة مالية',
    ],
    'الالتزامات المشتركة': [
      'مشاركات مشتركة',
      'الرحلة / السفر',
      'جمعية مالية',
    ],
    'الأفراد والجهات': [
      'الأفراد',
      'الجهات والشركات',
      'المستحقات والمدفوعات',
      'مستندات الأفراد والجهات',
    ],
    'العقارات والأنشطة والمركبات': [
      'العقارات',
      'الأنشطة التجارية',
      'المركبات ووسائل النقل',
      'العقود والإيجارات',
    ],
    'المستندات': [
      'مستندات الالتزامات الشخصية',
      'مستندات الالتزامات المشتركة',
      'مستندات الأفراد والجهات',
      'مستندات العقارات والأنشطة والمركبات',
    ],
    'التقارير والأرشيف': [
      'التقارير',
      'الأرشيف',
      'قوالب المستندات والإيصالات',
    ],
    'التنبيهات والكلندر ومراكز المتابعة': [
      'مركز التنبيهات',
      'الكلندر الذكي',
      'مراكز المتابعة',
    ],
    'الإعدادات والتفويضات': [
      'الإعدادات العامة',
      'التوقيع الإلكتروني والختم',
      'منح تفويضات فرعية',
    ],
  };

  /// الصلاحيات الأساسية بترتيب تصاعدي: اختيار صلاحية يعني ضمنًا كل ما
  /// دونها (لا يُعقل "حذف" بلا "عرض")، وهذا هو تسلسل الصلاحيات.
  static const orderedPermissions = [
    'عرض البيانات',
    'إضافة السجلات',
    'تعديل السجلات',
    'حذف السجلات',
  ];

  /// صلاحيات إضافية مستقلة عن التسلسل، لكنها تتطلب "عرض البيانات".
  static const extraPermissions = [
    'الموافقة على الطلبات',
    'تنفيذ المدفوعات والتحويلات',
    'تصدير ومشاركة التقارير',
    'إدارة المستندات والمرفقات',
    'إدارة التنبيهات والمتابعة',
    'منح تفويض فرعي',
  ];

  static const allPermissions = [
    ...orderedPermissions,
    ...extraPermissions,
  ];

  /// مستويات جاهزة تختصر الاختيار.
  static const permissionLevels = <String, List<String>>{
    'اطّلاع فقط': ['عرض البيانات'],
    'إدخال فقط': ['عرض البيانات', 'إضافة السجلات'],
    'تعديل فقط': ['عرض البيانات', 'تعديل السجلات'],
    'تعديل ومسح فقط': ['عرض البيانات', 'تعديل السجلات', 'حذف السجلات'],
    'إدخال وتعديل ومسح فقط': [
      'عرض البيانات',
      'إضافة السجلات',
      'تعديل السجلات',
      'حذف السجلات',
    ],
    'إدارة كاملة': allPermissions,
  };

  /// الإجراءات الإضافية المسموح اختيارها مع كل مستوى — فـ«اطّلاع فقط» لا
  /// يسمح بإضافة سجلات ولا بتنفيذ مدفوعات.
  static const levelExtras = <String, List<String>>{
    'اطّلاع فقط': ['تصدير ومشاركة التقارير'],
    'إدخال فقط': [
      'تصدير ومشاركة التقارير',
      'إدارة المستندات والمرفقات',
      'إدارة التنبيهات والمتابعة',
    ],
    'تعديل فقط': [
      'تصدير ومشاركة التقارير',
      'إدارة المستندات والمرفقات',
      'إدارة التنبيهات والمتابعة',
    ],
    'تعديل ومسح فقط': [
      'تصدير ومشاركة التقارير',
      'إدارة المستندات والمرفقات',
      'إدارة التنبيهات والمتابعة',
    ],
    'إدخال وتعديل ومسح فقط': [
      'تصدير ومشاركة التقارير',
      'إدارة المستندات والمرفقات',
      'إدارة التنبيهات والمتابعة',
      'الموافقة على الطلبات',
      'تنفيذ المدفوعات والتحويلات',
    ],
    'إدارة كاملة': extraPermissions,
  };

  static const fullLevel = 'إدارة كاملة';

  /// إجراءات المستوى الأساسية (عرض/إضافة/تعديل/حذف).
  static List<String> coreOf(String level) => [
    for (final p in permissionLevels[level] ?? const <String>[])
      if (orderedPermissions.contains(p)) p,
  ];

  /// المستوى الذي تطابقه صلاحيات محفوظة.
  static String levelOf(Iterable<String> permissions) {
    final set = permissions.toSet();
    if (set.containsAll(allPermissions)) return fullLevel;
    final core = set.where(orderedPermissions.contains).toSet();
    for (final entry in permissionLevels.entries) {
      if (entry.key == fullLevel) continue;
      final levelCore = coreOf(entry.key).toSet();
      if (levelCore.length == core.length && levelCore.containsAll(core)) {
        return entry.key;
      }
    }
    return permissionLevels.keys.first;
  }

  /// هل يحتاج ما يُدخله المفوَّض موافقة المالك قبل اعتماده؟ يُحفظ ضمن قائمة
  /// الصلاحيات نفسها (بلا عمود جديد في قاعدة البيانات).
  static const kNeedsOwnerApproval = 'يتطلب موافقة المالك';

  /// بيانات إضافية تُحفظ داخل قائمة الصلاحيات (بلا أعمدة جديدة) وتبدأ بـ @:
  /// عنصر محدد يُفوَّض عليه (@target:) وسقف مبلغ العملية (@limit:).
  static const targetPrefix = '@target:';
  static const limitPrefix = '@limit:';

  /// سجل التفويض: حدث بتاريخه (إنشاء، تعديل، إيقاف، تمديد، إلغاء فوري).
  static const logPrefix = '@log:';
  static const _maxLog = 30;

  static String logEntry(String event, [DateTime? at]) =>
      '$logPrefix${(at ?? DateTime.now()).toIso8601String()}|'
      '${event.replaceAll('|', '/')}';

  /// يضيف حدثًا للسجل ويُبقي آخر [_maxLog] حدثًا فقط.
  static List<String> withLog(Iterable<String> permissions, String event) {
    final list = [...permissions, logEntry(event)];
    final logs = list.where((p) => p.startsWith(logPrefix)).toList();
    if (logs.length <= _maxLog) return list;
    final drop = logs.take(logs.length - _maxLog).toSet();
    return [for (final p in list) if (!drop.contains(p)) p];
  }

  /// أحداث السجل — الأحدث أولًا.
  static List<(DateTime, String)> logOf(Iterable<String> permissions) {
    final result = <(DateTime, String)>[];
    for (final p in permissions) {
      if (!p.startsWith(logPrefix)) continue;
      final body = p.substring(logPrefix.length);
      final cut = body.indexOf('|');
      if (cut <= 0) continue;
      final at = DateTime.tryParse(body.substring(0, cut));
      if (at == null) continue;
      result.add((at, body.substring(cut + 1)));
    }
    result.sort((a, b) => b.$1.compareTo(a.$1));
    return result;
  }

  static bool isMeta(String permission) => permission.startsWith('@');

  // ===== التفويض بالرقم التعريفي (بيانات داخل قائمة الصلاحيات) =====
  /// رقم المفوَّض التعريفي: به يصله التفويض في تطبيقه.
  static const fndPrefix = '@fnd:';

  /// رد المفوَّض: pending / accepted / rejected.
  static const acceptPrefix = '@accept:';

  /// اسم المالك كما يظهر للمفوَّض.
  static const ownerNamePrefix = '@ownername:';

  static String _meta(Iterable<String> permissions, String prefix) {
    for (final p in permissions) {
      if (p.startsWith(prefix)) return p.substring(prefix.length).trim();
    }
    return '';
  }

  static String delegateFndOf(Iterable<String> permissions) =>
      _meta(permissions, fndPrefix);

  static String acceptOf(Iterable<String> permissions) =>
      _meta(permissions, acceptPrefix);

  static String ownerNameOf(Iterable<String> permissions) =>
      _meta(permissions, ownerNamePrefix);

  /// تفويض وصلني من حساب آخر (لا أملكه).
  bool get isIncoming {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return ownerId != null && me != null && ownerId != me;
  }

  /// الصلاحيات كما تُعرض للمستخدم — بلا البيانات الإضافية.
  static List<String> plainPermissions(Iterable<String> permissions) => [
    for (final p in permissions)
      if (!isMeta(p)) p,
  ];

  static int? limitOf(Iterable<String> permissions) {
    for (final p in permissions) {
      if (p.startsWith(limitPrefix)) {
        return int.tryParse(p.substring(limitPrefix.length));
      }
    }
    return null;
  }

  static int targetCountOf(Iterable<String> permissions) =>
      permissions.where((p) => p.startsWith(targetPrefix)).length;

  /// عند تعديل التفويض من شاشة لا تعرض هذه الإضافات: تُبقى الموافقة
  /// والسقف والعناصر المحددة لأقسام فرعية ما زالت مختارة.
  static List<String> carriedMeta(
    Iterable<String>? old,
    Iterable<String> subs,
  ) {
    final keep = subs.toSet();
    return [
      for (final p in old ?? const <String>[])
        if (p == kNeedsOwnerApproval ||
            p.startsWith(limitPrefix) ||
            p.startsWith(logPrefix) ||
            (p.startsWith(targetPrefix) &&
                keep.contains(p.substring(targetPrefix.length).split('|').first)))
          p,
    ];
  }

  /// الصلاحيات مستقلة (إدخال فقط، تعديل فقط...)، والشرط الوحيد أن أي
  /// صلاحية تتضمن «عرض البيانات».
  static Set<String> applyHierarchy(Set<String> selected) {
    final result = <String>{...selected};
    if (result.any((p) => p != kNeedsOwnerApproval)) {
      result.add('عرض البيانات');
    }
    return result;
  }

  /// النطاق يُخزَّن نصًا واحدًا: "الرئيسي" أو "الرئيسي — فرع، فرع".
  static const scopeSeparator = ' — ';

  static String composeScope(String main, Iterable<String> subs) {
    final list = subs.where((s) => s.trim().isNotEmpty).toList(growable: false);
    if (list.isEmpty) return main;
    return '$main$scopeSeparator${list.join('، ')}';
  }

  static String mainScopeOf(String? scope) {
    if (scope == null || scope.trim().isEmpty) return scopes.first;
    final main = scope.split(scopeSeparator).first.trim();
    // أسماء قديمة محفوظة قبل توحيد المسميات الحقيقية.
    const legacy = {
      'العقارات والأنشطة': 'العقارات والأنشطة والمركبات',
      'العقارات/الأنشطة التجارية/المعدات وأخرى': 'العقارات والأنشطة والمركبات',
      'الأشخاص والجهات': 'الأفراد والجهات',
      'إدارة الأشخاص والجهات': 'الأفراد والجهات',
      'المستندات والتقارير': 'التقارير والأرشيف',
      'قوالب المستندات والتقارير والأرشيف': 'التقارير والأرشيف',
    };
    final mapped = legacy[main] ?? main;
    return scopes.contains(mapped) ? mapped : scopes.first;
  }

  static List<String> subScopesOf(String? scope) {
    if (scope == null || !scope.contains(scopeSeparator)) return const [];
    final main = mainScopeOf(scope);
    final available = subScopes[main] ?? const <String>[];
    return scope
        .split(scopeSeparator)
        .last
        .split('،')
        .map((part) => part.trim())
        // اسم قديم محفوظ في التفويضات السابقة.
        .map(
          (part) => switch (part) {
            'التنظيم والمتابعة' => 'المتابعة والتخطيط',
            'آليات ومعدات' => 'المركبات ووسائل النقل',
            'مستندات الأشخاص والجهات' => 'مستندات الأفراد والجهات',
            _ => part,
          },
        )
        .where((part) => available.contains(part))
        .toList(growable: false);
  }

  final String? id;
  final String delegateName;
  final String? delegateRef;
  final String scope;
  final List<String> permissions;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPaused;
  final String? notes;

  /// صاحب التفويض (حساب المالك). يختلف عن حسابي في التفويض الذي وصلني من
  /// حساب آخر بالرقم التعريفي.
  final String? ownerId;

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
    this.ownerId,
  });

  // ===== حالة التفويض — مشتقّة من التواريخ والإيقاف، لا مخزَّنة =====
  // تخزين الحالة كحقل مستقل يجعلها تتقادم: تفويض انتهى أمس يبقى "نشطًا"
  // إلى أن يفتح أحدهم الصفحة ويحدّثه يدويًا.

  bool get isEnded =>
      endDate != null && endDate!.isBefore(DateTime.now());

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
      ownerId: json['user_id'] as String?,
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
    ownerId: ownerId,
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
  /// [includeIncoming]: ومعها التفويضات التي وصلتني من حسابات أخرى.
  Future<List<DelegationRecord>> fetchDelegations({
    bool includeIncoming = false,
  });
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
  Future<List<DelegationRecord>> fetchDelegations({
    bool includeIncoming = false,
  }) async {
    final user = await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_delegationsTable)
        .select()
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows
        .map(DelegationRecord.fromJson)
        // ما وصلني من غيري لا يُحسب ضمن تفويضاتي في الأعداد والملخصات.
        .where((d) => includeIncoming || d.ownerId == null || d.ownerId == user.id)
        .toList(growable: false);
  }

  /// المفوَّض يعدّل سجلًا شخصيًا أو مشتركًا في نطاق التفويض (الخادم يتحقق
  /// من النطاق والصلاحية ويُشعر المالك). null = بلا تغيير.
  Future<void> editDelegatedEntry({
    required String delegationId,
    required String source,
    required String entryId,
    String? title,
    num? amount,
    String? dueDate,
    String? status,
    String note = '',
  }) async {
    await AppSession.ensureSignedIn();
    await _client
        .rpc(
          'fundly_delegate_edit_entry',
          params: {
            'p_delegation': delegationId,
            'p_source': source,
            'p_id': entryId,
            'p_title': title,
            'p_amount': amount,
            'p_due': dueDate,
            'p_status': status,
            'p_note': note,
          },
        )
        .timeout(_requestTimeout);
  }

  /// المفوَّض ينقل السجل إلى سلة المالك (بصلاحية «حذف السجلات»).
  Future<void> trashDelegatedEntry({
    required String delegationId,
    required String source,
    required String entryId,
  }) async {
    await AppSession.ensureSignedIn();
    await _client
        .rpc(
          'fundly_delegate_trash_entry',
          params: {
            'p_delegation': delegationId,
            'p_source': source,
            'p_id': entryId,
          },
        )
        .timeout(_requestTimeout);
  }

  /// المفوَّض يغيّر رده على تفويض بمعرّفه: withdrawn (إلغاء التفويض من
  /// عنده) أو accepted (العودة إليه). الخادم لا يقبل منه غير ذلك.
  Future<void> setIncomingAnswer(String id, String answer) async {
    await AppSession.ensureSignedIn();
    final row = await _client
        .from(_delegationsTable)
        .select('permissions')
        .eq('id', id)
        .single()
        .timeout(_requestTimeout);
    final current = [
      for (final p in (row['permissions'] as List? ?? const [])) '$p',
    ];
    final permissions = [
      for (final p in current)
        if (!p.startsWith(DelegationRecord.acceptPrefix)) p,
      '${DelegationRecord.acceptPrefix}$answer',
    ];
    await _client
        .from(_delegationsTable)
        .update({'permissions': permissions})
        .eq('id', id)
        .timeout(_requestTimeout);
  }

  /// رد المفوَّض على تفويض وصله: قبول أو رفض (الخادم لا يقبل غير ذلك).
  Future<void> respondIncoming(DelegationRecord d, bool accept) async {
    await AppSession.ensureSignedIn();
    final id = d.id;
    if (id == null) return;
    final permissions = [
      for (final p in d.permissions)
        if (!p.startsWith(DelegationRecord.acceptPrefix)) p,
      '${DelegationRecord.acceptPrefix}${accept ? 'accepted' : 'rejected'}',
    ];
    await _client
        .from(_delegationsTable)
        .update({'permissions': permissions})
        .eq('id', id)
        .timeout(_requestTimeout);
  }

  /// سجلات المالك في نطاق تفويض مقبول وساري (للعرض فقط).
  Future<List<Map<String, dynamic>>> delegatedRecords(String id) async {
    await AppSession.ensureSignedIn();
    final rows = await _client
        .rpc('fundly_delegated_records', params: {'p_delegation': id})
        .timeout(_requestTimeout);
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<DelegationRecord> upsertDelegation(DelegationRecord d) async {
    PlanAccess.ensureEdit(PlanModules.delegations);
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
    PlanAccess.ensureEdit(PlanModules.delegations);
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
