import 'package:supabase_flutter/supabase_flutter.dart';

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

abstract class ProjectAssetsRepository {
  Future<List<ProjectAssetRecord>> fetchAssets();
  Future<ProjectAssetRecord> createAsset(ProjectAssetRecord asset);
  Future<ProjectAssetRecord> updateAsset(ProjectAssetRecord asset);
  Future<void> deleteAsset(String assetId);

  Future<List<ProjectAssetEntryRecord>> fetchEntries(String assetId);
  Future<ProjectAssetEntryRecord> upsertEntry(ProjectAssetEntryRecord entry);
  Future<void> deleteEntry(String entryId);
}

class SupabaseProjectAssetsRepository implements ProjectAssetsRepository {
  static const _assetsTable = 'project_assets';
  static const _entriesTable = 'project_asset_entries';
  static const _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _client;

  SupabaseProjectAssetsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<User> _authenticatedUser() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser != null) return currentUser;

    final response = await _client.auth.signInAnonymously().timeout(
      _requestTimeout,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('تعذر إنشاء جلسة لحفظ بيانات النشاط');
    }
    return user;
  }

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
}
