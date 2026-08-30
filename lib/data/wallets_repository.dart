import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';
import 'app_settings.dart';

/// محفظة/حساب/بطاقة يملكها المستخدم.
class WalletRecord {
  static const kindCash = 'cash';
  static const kindBank = 'bank';
  static const kindCard = 'card';
  static const kindDigital = 'digital';

  static const kinds = [kindCash, kindBank, kindCard, kindDigital];

  static String kindLabel(String kind) => switch (kind) {
    kindBank => 'حساب بنكي',
    kindCard => 'بطاقة',
    kindDigital => 'محفظة إلكترونية',
    _ => 'نقدية',
  };

  final String? id;
  final String name;
  final String kind;
  final String? issuer;
  final String? last4;
  final double openingBalance;

  /// العملة كما حُفظت مع المحفظة. الفارغة تعني "اتبع عملة الإعدادات"،
  /// فلا تبقى محفظة قديمة تعرض عملة لم يعد المستخدم يستعملها.
  final String currency;
  final int? color;
  final bool isArchived;
  final bool isDefault;
  final String? notes;

  /// العملة المعروضة: المحفوظة إن وُجدت، وإلا عملة الإعدادات.
  String get currencyLabel =>
      currency.trim().isEmpty ? AppSettings.currencySuffix : currency.trim();

  const WalletRecord({
    this.id,
    required this.name,
    this.kind = kindCash,
    this.issuer,
    this.last4,
    this.openingBalance = 0,
    this.currency = '',
    this.color,
    this.isArchived = false,
    this.isDefault = false,
    this.notes,
  });

  factory WalletRecord.fromJson(Map<String, dynamic> json) => WalletRecord(
    id: json['id'] as String?,
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? kindCash,
    issuer: json['issuer'] as String?,
    last4: json['last4'] as String?,
    openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
    // المحافظ القديمة حُفظت جميعها بعملة افتراضية مكتوبة في الشيفرة
    // ('درهم') لا باختيار من المستخدم، فتُعامَل كغير محدَّدة لتتبع عملة
    // الإعدادات مثل المحافظ الجديدة.
    currency: _normalizeCurrency(json['currency'] as String?),
    color: (json['color'] as num?)?.toInt(),
    isArchived: json['is_archived'] as bool? ?? false,
    isDefault: json['is_default'] as bool? ?? false,
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'name': name,
    'kind': kind,
    'issuer': issuer,
    'last4': last4,
    'opening_balance': openingBalance,
    'currency': currency,
    'color': color,
    'is_archived': isArchived,
    'is_default': isDefault,
    'notes': notes,
  };

  WalletRecord copyWith({
    String? id,
    String? name,
    String? kind,
    String? issuer,
    String? last4,
    double? openingBalance,
    String? currency,
    int? color,
    bool? isArchived,
    bool? isDefault,
    String? notes,
  }) => WalletRecord(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    issuer: issuer ?? this.issuer,
    last4: last4 ?? this.last4,
    openingBalance: openingBalance ?? this.openingBalance,
    currency: currency ?? this.currency,
    color: color ?? this.color,
    isArchived: isArchived ?? this.isArchived,
    isDefault: isDefault ?? this.isDefault,
    notes: notes ?? this.notes,
  );
}

/// حركة مالية على محفظة.
///
/// التحويل بين محفظتين يُخزَّن كصفّين (خصم + إيداع) يجمعهما [transferGroup]،
/// فيبقى الطرفان متسقين ويُحذفان معًا — لا يمكن أن يبقى نصف تحويل معلّقًا.
class WalletTransactionRecord {
  static const kindIncome = 'income';
  static const kindExpense = 'expense';
  static const kindTransferIn = 'transfer_in';
  static const kindTransferOut = 'transfer_out';

  final String? id;
  final String walletId;
  final String kind;
  final double amount;
  final DateTime? occurredOn;
  final String? category;
  final String? note;
  final String? transferGroup;
  final String? counterpartyWalletId;

  const WalletTransactionRecord({
    this.id,
    required this.walletId,
    required this.kind,
    this.amount = 0,
    this.occurredOn,
    this.category,
    this.note,
    this.transferGroup,
    this.counterpartyWalletId,
  });

  /// هل تزيد هذه الحركة رصيد المحفظة؟
  bool get isCredit => kind == kindIncome || kind == kindTransferIn;

  /// أثرها الموقَّع على الرصيد.
  double get signedAmount => isCredit ? amount : -amount;

  bool get isTransfer => kind == kindTransferIn || kind == kindTransferOut;

  factory WalletTransactionRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['occurred_on'];
    return WalletTransactionRecord(
      id: json['id'] as String?,
      walletId: json['wallet_id'] as String? ?? '',
      kind: json['kind'] as String? ?? kindExpense,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      occurredOn: raw == null ? null : DateTime.tryParse(raw as String),
      category: json['category'] as String?,
      note: json['note'] as String?,
      transferGroup: json['transfer_group'] as String?,
      counterpartyWalletId: json['counterparty_wallet_id'] as String?,
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'wallet_id': walletId,
    'kind': kind,
    'amount': amount,
    'occurred_on': occurredOn?.toIso8601String().split('T').first,
    'category': category,
    'note': note,
    'transfer_group': transferGroup,
    'counterparty_wallet_id': counterpartyWalletId,
  };
}

String _normalizeCurrency(String? stored) {
  final value = (stored ?? '').trim();
  return value == 'درهم' ? '' : value;
}

abstract class WalletsRepository {
  Future<List<WalletRecord>> fetchWallets();
  Future<WalletRecord> upsertWallet(WalletRecord wallet);
  Future<void> deleteWallet(String walletId);

  /// كل الحركات. مرّر [walletId] لقصر النتيجة على محفظة واحدة.
  Future<List<WalletTransactionRecord>> fetchTransactions({String? walletId});
  Future<WalletTransactionRecord> upsertTransaction(
    WalletTransactionRecord transaction,
  );
  Future<void> deleteTransaction(WalletTransactionRecord transaction);

  /// تحويل بين محفظتين: يُنشئ طرفَي الحركة معًا بمجموعة واحدة.
  Future<void> transfer({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    DateTime? occurredOn,
    String? note,
  });
}

class SupabaseWalletsRepository implements WalletsRepository {
  static const _walletsTable = 'wallets';
  static const _transactionsTable = 'wallet_transactions';
  static const _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _client;

  SupabaseWalletsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<List<WalletRecord>> fetchWallets() async {
    await AppSession.ensureSignedIn();
    final rows = await _client
        .from(_walletsTable)
        .select()
        .order('created_at', ascending: true)
        .timeout(_requestTimeout);
    return rows.map(WalletRecord.fromJson).toList(growable: false);
  }

  @override
  Future<WalletRecord> upsertWallet(WalletRecord wallet) async {
    final user = await AppSession.ensureSignedIn();
    Map<String, dynamic> row;
    if (wallet.id == null) {
      row = await _client
          .from(_walletsTable)
          .insert(wallet.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_walletsTable)
          .update(wallet.toJson(user.id))
          .eq('id', wallet.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return WalletRecord.fromJson(row);
  }

  @override
  Future<void> deleteWallet(String walletId) async {
    await AppSession.ensureSignedIn();
    // حركات المحفظة نفسها تُحذف تلقائيًا عبر on delete cascade، لكن الطرف
    // المقابل لأي تحويل يقع في محفظة أخرى ولا يشمله الحذف المتتالي
    // (counterparty_wallet_id معرّف بـ set null)، فيبقى خصمٌ بلا إيداع
    // مقابل ويختل رصيد المحفظة الأخرى. لذا تُحذف مجموعات التحويل كاملة
    // أولًا. كل تحويل يخصّ هذه المحفظة له طرف عليها، فجلب أطرافها يكفي
    // للوصول إلى كل المجموعات المعنية.
    final legs = await _client
        .from(_transactionsTable)
        .select('transfer_group')
        .eq('wallet_id', walletId)
        .not('transfer_group', 'is', null)
        .timeout(_requestTimeout);
    final groups = legs
        .map((row) => row['transfer_group'] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (groups.isNotEmpty) {
      await _client
          .from(_transactionsTable)
          .delete()
          .inFilter('transfer_group', groups)
          .timeout(_requestTimeout);
    }
    await _client
        .from(_walletsTable)
        .delete()
        .eq('id', walletId)
        .timeout(_requestTimeout);
  }

  @override
  Future<List<WalletTransactionRecord>> fetchTransactions({
    String? walletId,
  }) async {
    await AppSession.ensureSignedIn();
    final query = _client.from(_transactionsTable).select();
    final rows =
        await (walletId == null ? query : query.eq('wallet_id', walletId))
            // nullsFirst: false حتى لا تتصدّر الحركات بلا تاريخ القائمة
            // (Postgres يضع NULL أولًا افتراضيًا في الترتيب التنازلي).
            .order('occurred_on', ascending: false, nullsFirst: false)
            .timeout(_requestTimeout);
    return rows.map(WalletTransactionRecord.fromJson).toList(growable: false);
  }

  @override
  Future<WalletTransactionRecord> upsertTransaction(
    WalletTransactionRecord transaction,
  ) async {
    final user = await AppSession.ensureSignedIn();
    Map<String, dynamic> row;
    if (transaction.id == null) {
      row = await _client
          .from(_transactionsTable)
          .insert(transaction.toJson(user.id))
          .select()
          .single()
          .timeout(_requestTimeout);
    } else {
      row = await _client
          .from(_transactionsTable)
          .update(transaction.toJson(user.id))
          .eq('id', transaction.id!)
          .select()
          .single()
          .timeout(_requestTimeout);
    }
    return WalletTransactionRecord.fromJson(row);
  }

  @override
  Future<void> deleteTransaction(WalletTransactionRecord transaction) async {
    await AppSession.ensureSignedIn();
    final group = transaction.transferGroup;
    // حذف طرف واحد من تحويل يترك الطرف الآخر معلّقًا فيختل رصيد المحفظتين،
    // لذا يُحذف الطرفان معًا دائمًا.
    if (group != null && group.isNotEmpty) {
      await _client
          .from(_transactionsTable)
          .delete()
          .eq('transfer_group', group)
          .timeout(_requestTimeout);
      return;
    }
    if (transaction.id == null) return;
    await _client
        .from(_transactionsTable)
        .delete()
        .eq('id', transaction.id!)
        .timeout(_requestTimeout);
  }

  @override
  Future<void> transfer({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    DateTime? occurredOn,
    String? note,
  }) async {
    final user = await AppSession.ensureSignedIn();
    final group = 'trf_${DateTime.now().microsecondsSinceEpoch}';
    final date = occurredOn ?? DateTime.now();
    // يُدرَج الطرفان في نداء واحد: إمّا أن يُكتبا معًا أو لا يُكتب أيّهما،
    // فلا ينشأ تحويل ناقص يُظهر خصمًا بلا إيداع مقابل.
    await _client
        .from(_transactionsTable)
        .insert([
          WalletTransactionRecord(
            walletId: fromWalletId,
            kind: WalletTransactionRecord.kindTransferOut,
            amount: amount,
            occurredOn: date,
            category: 'تحويل',
            note: note,
            transferGroup: group,
            counterpartyWalletId: toWalletId,
          ).toJson(user.id),
          WalletTransactionRecord(
            walletId: toWalletId,
            kind: WalletTransactionRecord.kindTransferIn,
            amount: amount,
            occurredOn: date,
            category: 'تحويل',
            note: note,
            transferGroup: group,
            counterpartyWalletId: fromWalletId,
          ).toJson(user.id),
        ])
        .timeout(_requestTimeout);
  }
}
