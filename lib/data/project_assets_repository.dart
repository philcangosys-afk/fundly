import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

/// Repository for the "Projects & Business Activities" screen.
///
/// Persists both the asset itself (a real-estate / project / business item)
/// and its typed sub-entries (contracts, maintenance, rentals, expenses,
/// revenues, documents) into Supabase.
///
/// The wire-up in the UI is intentionally kept optional: [ProjectAssetsRepository]
/// can be injected into the details screen to persist entries as they are
/// created / edited / deleted. When no repository is provided, the UI falls
/// back to purely in-memory state (useful during offline dev).
class ProjectAssetRecord {
  final String? id;
  final String title;
  final String subType;
  final String category;
  final String status;
  final String? locationOrType;
  final String? amountLabel;
  final String? followupNote;
  final String? owner;
  final String? tenant;
  final String? rentValue;
  final String? endDate;
  final String? annualYield;
  final double occupancyRate;
  final double contractProgress;
  final double paymentProgress;
  final double documentsProgress;
  final bool needsAttention;
  final int? iconColor;
  final String? coverUrl;
  final String description;
  final Map<String, int> annexes;
  final String? mapLink;
  final bool quickAddEnabled;
  final String? unitsJson;
  final String? employeesJson;
  final String? serialNumber;
  final bool isFrozen;
  final bool isPinned;
  final bool isSublease;
  final double? latitude;
  final double? longitude;
  final String? logsJson;

  const ProjectAssetRecord({
    this.id,
    required this.title,
    required this.subType,
    required this.category,
    this.status = 'نشط',
    this.locationOrType,
    this.amountLabel,
    this.followupNote,
    this.owner,
    this.tenant,
    this.rentValue,
    this.endDate,
    this.annualYield,
    this.occupancyRate = 0,
    this.contractProgress = 0,
    this.paymentProgress = 0,
    this.documentsProgress = 0,
    this.needsAttention = false,
    this.iconColor,
    this.coverUrl,
    this.description = '',
    this.annexes = const {},
    this.mapLink,
    this.quickAddEnabled = false,
    this.unitsJson,
    this.employeesJson,
    this.serialNumber,
    this.isFrozen = false,
    this.isPinned = false,
    this.isSublease = false,
    this.latitude,
    this.longitude,
    this.logsJson,
  });

  factory ProjectAssetRecord.fromJson(Map<String, dynamic> json) {
    double asRatio(dynamic v) {
      final n = (v as num?)?.toDouble() ?? 0;
      if (n.isNaN) return 0;
      return n.clamp(0, 1);
    }

    return ProjectAssetRecord(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      subType: json['sub_type'] as String? ?? '',
      category: json['category'] as String? ?? 'real_estate',
      status: json['status'] as String? ?? 'نشط',
      locationOrType: json['location_or_type'] as String?,
      amountLabel: json['amount_label'] as String?,
      followupNote: json['followup_note'] as String?,
      owner: json['owner'] as String?,
      tenant: json['tenant'] as String?,
      rentValue: json['rent_value'] as String?,
      endDate: json['end_date'] as String?,
      annualYield: json['annual_yield'] as String?,
      occupancyRate: asRatio(json['occupancy_rate']),
      contractProgress: asRatio(json['contract_progress']),
      paymentProgress: asRatio(json['payment_progress']),
      documentsProgress: asRatio(json['documents_progress']),
      needsAttention: json['needs_attention'] as bool? ?? false,
      iconColor: (json['icon_color'] as num?)?.toInt(),
      coverUrl: json['cover_url'] as String?,
      description: json['description'] as String? ?? '',
      annexes: (json['annexes'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
      ),
      mapLink: json['map_link'] as String?,
      quickAddEnabled: json['quick_add_enabled'] as bool? ?? false,
      unitsJson: json['units_json'] as String?,
      employeesJson: json['employees_json'] as String?,
      serialNumber: json['serial_number'] as String?,
      isFrozen: json['is_frozen'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      isSublease: json['is_sublease'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      logsJson: json['logs_json'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'title': title,
    'sub_type': subType,
    'category': category,
    'status': status,
    'location_or_type': locationOrType,
    'amount_label': amountLabel,
    'followup_note': followupNote,
    'owner': owner,
    'tenant': tenant,
    'rent_value': rentValue,
    'end_date': endDate,
    'annual_yield': annualYield,
    'occupancy_rate': occupancyRate,
    'contract_progress': contractProgress,
    'payment_progress': paymentProgress,
    'documents_progress': documentsProgress,
    'needs_attention': needsAttention,
    'icon_color': iconColor,
    'cover_url': coverUrl,
    'description': description,
    'annexes': annexes,
    'map_link': mapLink,
    'quick_add_enabled': quickAddEnabled,
    'units_json': unitsJson,
    'employees_json': employeesJson,
    'serial_number': serialNumber,
    'is_frozen': isFrozen,
    'is_pinned': isPinned,
    'is_sublease': isSublease,
    'latitude': latitude,
    'longitude': longitude,
    'logs_json': logsJson,
  };
}

class ProjectAssetEntryRecord {
  static const kindContract = 'contract';
  static const kindMaintenance = 'maintenance';
  static const kindRental = 'rental';
  static const kindExpense = 'expense';
  static const kindRevenue = 'revenue';
  static const kindDocument = 'document';

  static const allKinds = [
    kindContract,
    kindMaintenance,
    kindRental,
    kindExpense,
    kindRevenue,
    kindDocument,
  ];

  final String? id;
  final String assetId;
  final String kind;
  final Map<String, String> data;
  final String? attachmentUrl;

  const ProjectAssetEntryRecord({
    this.id,
    required this.assetId,
    required this.kind,
    required this.data,
    this.attachmentUrl,
  });

  factory ProjectAssetEntryRecord.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'] as Map<String, dynamic>? ?? const {};
    return ProjectAssetEntryRecord(
      id: json['id'] as String?,
      assetId: json['asset_id'] as String? ?? '',
      kind: json['kind'] as String? ?? kindContract,
      data: rawData.map((key, value) => MapEntry(key, value?.toString() ?? '')),
      attachmentUrl: json['attachment_url'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'asset_id': assetId,
    'kind': kind,
    'data': data,
    'attachment_url': attachmentUrl,
  };
}

/// A rental/lease contract for one (or more, in the multi-unit case) unit
/// inside a real-estate asset (building/property).
class PropertyUnitContractRecord {
  static const leaseTypeStandard = 'standard';
  static const leaseTypeMultiUnit = 'multi_unit';
  static const leaseTypeSublease = 'sublease';

  static const statusActive = 'active';
  static const statusExpired = 'expired';
  static const statusPending = 'pending';
  static const statusLate = 'late';

  final String? id;
  final String assetId;
  final String unitKey;
  final String? unitName;
  final String? tenantName;
  final String? tenantPhone;
  final String leaseType;
  final double annualRent;
  final String paymentCycle;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final String? notes;
  final String? groupKey;

  const PropertyUnitContractRecord({
    this.id,
    required this.assetId,
    required this.unitKey,
    this.unitName,
    this.tenantName,
    this.tenantPhone,
    this.leaseType = leaseTypeStandard,
    this.annualRent = 0,
    this.paymentCycle = 'شهري',
    this.startDate,
    this.endDate,
    this.status = statusActive,
    this.notes,
    this.groupKey,
  });

  factory PropertyUnitContractRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v as String);
    }

    return PropertyUnitContractRecord(
      id: json['id'] as String?,
      assetId: json['asset_id'] as String? ?? '',
      unitKey: json['unit_key'] as String? ?? '',
      unitName: json['unit_name'] as String?,
      tenantName: json['tenant_name'] as String?,
      tenantPhone: json['tenant_phone'] as String?,
      leaseType: json['lease_type'] as String? ?? leaseTypeStandard,
      annualRent: (json['annual_rent'] as num?)?.toDouble() ?? 0,
      paymentCycle: json['payment_cycle'] as String? ?? 'شهري',
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
      status: json['status'] as String? ?? statusActive,
      notes: json['notes'] as String?,
      groupKey: json['group_key'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'asset_id': assetId,
    'unit_key': unitKey,
    'unit_name': unitName,
    'tenant_name': tenantName,
    'tenant_phone': tenantPhone,
    'lease_type': leaseType,
    'annual_rent': annualRent,
    'payment_cycle': paymentCycle,
    'start_date': startDate?.toIso8601String().split('T').first,
    'end_date': endDate?.toIso8601String().split('T').first,
    'status': status,
    'notes': notes,
    'group_key': groupKey,
  };

  PropertyUnitContractRecord copyWith({
    String? id,
    String? assetId,
    String? unitKey,
    String? unitName,
    String? tenantName,
    String? tenantPhone,
    String? leaseType,
    double? annualRent,
    String? paymentCycle,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? notes,
    String? groupKey,
  }) {
    return PropertyUnitContractRecord(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      unitKey: unitKey ?? this.unitKey,
      unitName: unitName ?? this.unitName,
      tenantName: tenantName ?? this.tenantName,
      tenantPhone: tenantPhone ?? this.tenantPhone,
      leaseType: leaseType ?? this.leaseType,
      annualRent: annualRent ?? this.annualRent,
      paymentCycle: paymentCycle ?? this.paymentCycle,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      groupKey: groupKey ?? this.groupKey,
    );
  }
}

/// A single due/paid rent installment tied to a [PropertyUnitContractRecord].
class PropertyUnitPaymentRecord {
  static const statusPending = 'pending';
  static const statusPaid = 'paid';
  static const statusLate = 'late';
  static const statusPartial = 'partial';

  final String? id;
  final String contractId;
  final DateTime? dueDate;
  final double amountDue;
  final double amountPaid;
  final DateTime? paidAt;
  final String status;
  final String? referenceNo;
  final String? notes;

  const PropertyUnitPaymentRecord({
    this.id,
    required this.contractId,
    this.dueDate,
    this.amountDue = 0,
    this.amountPaid = 0,
    this.paidAt,
    this.status = statusPending,
    this.referenceNo,
    this.notes,
  });

  factory PropertyUnitPaymentRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v as String);
    }

    return PropertyUnitPaymentRecord(
      id: json['id'] as String?,
      contractId: json['contract_id'] as String? ?? '',
      dueDate: parseDate(json['due_date']),
      amountDue: (json['amount_due'] as num?)?.toDouble() ?? 0,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      paidAt: parseDate(json['paid_at']),
      status: json['status'] as String? ?? statusPending,
      referenceNo: json['reference_no'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'contract_id': contractId,
    'due_date': dueDate?.toIso8601String().split('T').first,
    'amount_due': amountDue,
    'amount_paid': amountPaid,
    'paid_at': paidAt?.toIso8601String(),
    'status': status,
    'reference_no': referenceNo,
    'notes': notes,
  };

  PropertyUnitPaymentRecord copyWith({
    String? id,
    String? contractId,
    DateTime? dueDate,
    double? amountDue,
    double? amountPaid,
    DateTime? paidAt,
    String? status,
    String? referenceNo,
    String? notes,
  }) {
    return PropertyUnitPaymentRecord(
      id: id ?? this.id,
      contractId: contractId ?? this.contractId,
      dueDate: dueDate ?? this.dueDate,
      amountDue: amountDue ?? this.amountDue,
      amountPaid: amountPaid ?? this.amountPaid,
      paidAt: paidAt ?? this.paidAt,
      status: status ?? this.status,
      referenceNo: referenceNo ?? this.referenceNo,
      notes: notes ?? this.notes,
    );
  }
}

/// حركة مالية حقيقية (إيراد أو مصروف) على عقار أو على وحدة بعينه.
///
/// [unitKey] فارغ/null يعني أن الحركة تخصّ العقار ككل، وغير ذلك تخصّ الوحدة
/// صاحبة هذا المفتاح — بحيث تخدم نفس الجدول شاشة العقار وشاشة الوحدة معًا.
class PropertyUnitTransactionRecord {
  static const kindIncome = 'income';
  static const kindExpense = 'expense';

  final String? id;
  final String assetId;
  final String? unitKey;
  final String kind;
  final double amount;
  final DateTime? occurredOn;
  final String? category;
  final String? note;

  const PropertyUnitTransactionRecord({
    this.id,
    required this.assetId,
    this.unitKey,
    required this.kind,
    this.amount = 0,
    this.occurredOn,
    this.category,
    this.note,
  });

  bool get isIncome => kind == kindIncome;

  factory PropertyUnitTransactionRecord.fromJson(Map<String, dynamic> json) {
    final rawDate = json['occurred_on'];
    return PropertyUnitTransactionRecord(
      id: json['id'] as String?,
      assetId: json['asset_id'] as String? ?? '',
      unitKey: json['unit_key'] as String?,
      kind: json['kind'] as String? ?? kindExpense,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      occurredOn: rawDate == null ? null : DateTime.tryParse(rawDate as String),
      category: json['category'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'asset_id': assetId,
    'unit_key': unitKey,
    'kind': kind,
    'amount': amount,
    'occurred_on': occurredOn?.toIso8601String().split('T').first,
    'category': category,
    'note': note,
  };

  PropertyUnitTransactionRecord copyWith({
    String? id,
    String? assetId,
    String? unitKey,
    String? kind,
    double? amount,
    DateTime? occurredOn,
    String? category,
    String? note,
  }) => PropertyUnitTransactionRecord(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    unitKey: unitKey ?? this.unitKey,
    kind: kind ?? this.kind,
    amount: amount ?? this.amount,
    occurredOn: occurredOn ?? this.occurredOn,
    category: category ?? this.category,
    note: note ?? this.note,
  );
}

abstract class ProjectAssetsRepository {
  Future<List<ProjectAssetRecord>> fetchAssets();
  Future<ProjectAssetRecord> createAsset(ProjectAssetRecord asset);
  Future<ProjectAssetRecord> updateAsset(ProjectAssetRecord asset);
  Future<void> deleteAsset(String assetId);

  Future<List<ProjectAssetEntryRecord>> fetchEntries(String assetId);
  Future<ProjectAssetEntryRecord> upsertEntry(ProjectAssetEntryRecord entry);
  Future<void> deleteEntry(String entryId);

  Future<List<PropertyUnitContractRecord>> fetchUnitContracts(String assetId);
  Future<PropertyUnitContractRecord> upsertUnitContract(
    PropertyUnitContractRecord contract,
  );
  Future<void> deleteUnitContract(String contractId);

  Future<List<PropertyUnitPaymentRecord>> fetchUnitPayments(String contractId);
  Future<PropertyUnitPaymentRecord> upsertUnitPayment(
    PropertyUnitPaymentRecord payment,
  );
  Future<void> deleteUnitPayment(String paymentId);

  /// يجلب كل حركات العقار المالية. مرّر [unitKey] لقصر النتيجة على وحدة
  /// بعينها، أو اتركه فارغًا لجلب حركات العقار كاملة (بما فيها الوحدات).
  Future<List<PropertyUnitTransactionRecord>> fetchUnitTransactions(
    String assetId, {
    String? unitKey,
  });
  Future<PropertyUnitTransactionRecord> upsertUnitTransaction(
    PropertyUnitTransactionRecord transaction,
  );
  Future<void> deleteUnitTransaction(String transactionId);
}

class SupabaseProjectAssetsRepository implements ProjectAssetsRepository {
  static const _assetsTable = 'project_assets';
  static const _entriesTable = 'project_asset_entries';
  static const _unitContractsTable = 'property_unit_contracts';
  static const _unitPaymentsTable = 'property_unit_payments';
  static const _unitTransactionsTable = 'property_unit_transactions';
  static const _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _client;

  SupabaseProjectAssetsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// يدخل بحساب التطبيق الثابت عبر [AppSession]. كان يستدعي
  /// signInAnonymously() فيُنشئ مستخدمًا جديدًا عند كل إعادة تثبيت،
  /// فتصبح كل البيانات السابقة غير مرئية.
  Future<User> _authenticatedUser() => AppSession.ensureSignedIn();

  @override
  Future<List<ProjectAssetRecord>> fetchAssets() async {
    await _authenticatedUser();
    final rows = await _client
        .from(_assetsTable)
        .select()
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows.map(ProjectAssetRecord.fromJson).toList(growable: false);
  }

  @override
  Future<ProjectAssetRecord> createAsset(ProjectAssetRecord asset) async {
    final user = await _authenticatedUser();
    final row = await _client
        .from(_assetsTable)
        .insert(asset.toJson(user.id))
        .select()
        .single()
        .timeout(_requestTimeout);
    return ProjectAssetRecord.fromJson(row);
  }

  @override
  Future<ProjectAssetRecord> updateAsset(ProjectAssetRecord asset) async {
    final user = await _authenticatedUser();
    if (asset.id == null) {
      throw const PostgrestException(message: 'Missing project asset id');
    }
    final row = await _client
        .from(_assetsTable)
        .update(asset.toJson(user.id))
        .eq('id', asset.id!)
        .select()
        .single()
        .timeout(_requestTimeout);
    return ProjectAssetRecord.fromJson(row);
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    await _authenticatedUser();
    await _client
        .from(_assetsTable)
        .delete()
        .eq('id', assetId)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<ProjectAssetEntryRecord>> fetchEntries(String assetId) async {
    await _authenticatedUser();
    final rows = await _client
        .from(_entriesTable)
        .select()
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows.map(ProjectAssetEntryRecord.fromJson).toList(growable: false);
  }

  @override
  Future<ProjectAssetEntryRecord> upsertEntry(
    ProjectAssetEntryRecord entry,
  ) async {
    final user = await _authenticatedUser();
    Map<String, dynamic> row;
    if (entry.id == null) {
      row = await _client
          .from(_entriesTable)
          .insert(entry.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_entriesTable)
          .update(entry.toJson(user.id))
          .eq('id', entry.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return ProjectAssetEntryRecord.fromJson(row);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _authenticatedUser();
    await _client
        .from(_entriesTable)
        .delete()
        .eq('id', entryId)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<PropertyUnitContractRecord>> fetchUnitContracts(
    String assetId,
  ) async {
    await _authenticatedUser();
    final rows = await _client
        .from(_unitContractsTable)
        .select()
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows
        .map(PropertyUnitContractRecord.fromJson)
        .toList(growable: false);
  }

  @override
  Future<PropertyUnitContractRecord> upsertUnitContract(
    PropertyUnitContractRecord contract,
  ) async {
    final user = await _authenticatedUser();
    Map<String, dynamic> row;
    if (contract.id == null) {
      row = await _client
          .from(_unitContractsTable)
          .insert(contract.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_unitContractsTable)
          .update(contract.toJson(user.id))
          .eq('id', contract.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return PropertyUnitContractRecord.fromJson(row);
  }

  @override
  Future<void> deleteUnitContract(String contractId) async {
    await _authenticatedUser();
    await _client
        .from(_unitContractsTable)
        .delete()
        .eq('id', contractId)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<PropertyUnitPaymentRecord>> fetchUnitPayments(
    String contractId,
  ) async {
    await _authenticatedUser();
    final rows = await _client
        .from(_unitPaymentsTable)
        .select()
        .eq('contract_id', contractId)
        .order('due_date', ascending: true)
        .timeout(_requestTimeout);
    return rows.map(PropertyUnitPaymentRecord.fromJson).toList(growable: false);
  }

  @override
  Future<PropertyUnitPaymentRecord> upsertUnitPayment(
    PropertyUnitPaymentRecord payment,
  ) async {
    final user = await _authenticatedUser();
    Map<String, dynamic> row;
    if (payment.id == null) {
      row = await _client
          .from(_unitPaymentsTable)
          .insert(payment.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_unitPaymentsTable)
          .update(payment.toJson(user.id))
          .eq('id', payment.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return PropertyUnitPaymentRecord.fromJson(row);
  }

  @override
  Future<void> deleteUnitPayment(String paymentId) async {
    await _authenticatedUser();
    await _client
        .from(_unitPaymentsTable)
        .delete()
        .eq('id', paymentId)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<PropertyUnitTransactionRecord>> fetchUnitTransactions(
    String assetId, {
    String? unitKey,
  }) async {
    await _authenticatedUser();
    final query = _client
        .from(_unitTransactionsTable)
        .select()
        .eq('asset_id', assetId);
    final rows = await (unitKey == null ? query : query.eq('unit_key', unitKey))
        .order('occurred_on', ascending: false)
        .timeout(_requestTimeout);
    return rows
        .map(PropertyUnitTransactionRecord.fromJson)
        .toList(growable: false);
  }

  @override
  Future<PropertyUnitTransactionRecord> upsertUnitTransaction(
    PropertyUnitTransactionRecord transaction,
  ) async {
    final user = await _authenticatedUser();
    Map<String, dynamic> row;
    if (transaction.id == null) {
      row = await _client
          .from(_unitTransactionsTable)
          .insert(transaction.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_unitTransactionsTable)
          .update(transaction.toJson(user.id))
          .eq('id', transaction.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return PropertyUnitTransactionRecord.fromJson(row);
  }

  @override
  Future<void> deleteUnitTransaction(String transactionId) async {
    await _authenticatedUser();
    await _client
        .from(_unitTransactionsTable)
        .delete()
        .eq('id', transactionId)
        .timeout(_requestTimeout);
  }
}
