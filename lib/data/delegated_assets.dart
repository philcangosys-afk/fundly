import 'package:flutter/foundation.dart' show ValueNotifier;

/// عقار أو مركبة أو نشاط فوّضني صاحبه بإدارته (تفويض مقبول وساري).
class DelegatedAsset {
  const DelegatedAsset({
    required this.assetId,
    required this.ownerId,
    required this.ownerName,
    required this.ownerFnd,
    required this.permissions,
    required this.wholeAsset,
    required this.unitRefs,
    this.delegationIds = const <String>{},
  });

  /// التفويضات التي أعطتني هذا الأصل — لـ«إلغاء التفويض» من عندي.
  final Set<String> delegationIds;

  final String assetId;
  final String ownerId;
  final String ownerName;
  final String ownerFnd;

  /// كل الصلاحيات من كل التفويضات على هذا الأصل.
  final Set<String> permissions;

  /// مفوَّض بالأصل كاملًا؛ وإلا فبوحدات بعينها [unitRefs].
  final bool wholeAsset;

  /// رقم الوحدة أو اسمها (أو ترتيبها) كما حُفظ في التفويض.
  final Set<String> unitRefs;

  /// اسم المالك كما يظهر: الاسم الظاهر، أو رقمه التعريفي.
  String get owner => ownerName.trim().isNotEmpty ? ownerName.trim() : ownerFnd;

  bool get canAdd => permissions.contains('إضافة السجلات');
  bool get canEdit => permissions.contains('تعديل السجلات');
  bool get canDelete => permissions.contains('حذف السجلات');
  bool get canSubDelegate => permissions.contains('منح تفويض فرعي');

  /// الصلاحيات المختارة بالترتيب (بلا العلامات الداخلية @...).
  List<String> get plainPermissions => [
    for (final p in permissions)
      if (!p.startsWith('@')) p,
  ];

  /// هل هذه الوحدة ضمن التفويض؟
  bool allowsUnit({
    required String number,
    required String name,
    int index = -1,
  }) {
    if (wholeAsset) return true;
    final n = number.trim();
    final m = name.trim();
    return (n.isNotEmpty && unitRefs.contains(n)) ||
        (m.isNotEmpty && unitRefs.contains(m)) ||
        (index >= 0 && unitRefs.contains('$index'));
  }
}

/// سجل ما فُوِّضتُ بإدارته — يُملأ عند تحميل العقارات، ويُقرأ في كل مكان
/// يحتاج أن يميّز العنصر المفوَّض (الوسم، الصلاحيات، إشعار المالك).
class DelegatedAssets {
  DelegatedAssets._();

  static Map<String, DelegatedAsset> _byId = const {};

  /// يزيد بعد كل حفظ ناجح على أصل مفوَّض — تستمع له صفحة العنصر فتقول
  /// للمفوَّض «تم إشعار المالك».
  static final ValueNotifier<int> writes = ValueNotifier<int>(0);

  /// آخر أصل مفوَّض حُفظ فيه شيء.
  static String lastWriteAsset = '';

  static bool get isEmpty => _byId.isEmpty;

  /// يزيد عند إلغاء تفويض من عندي — تعيد القائمة التحميل.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static bool isDelegated(String? assetId) =>
      assetId != null && _byId.containsKey(assetId);

  static DelegatedAsset? of(String? assetId) =>
      assetId == null ? null : _byId[assetId];

  static List<String> get ids => _byId.keys.toList(growable: false);

  /// بعد حفظ ناجح: إن كان الأصل مفوَّضًا يُبلَّغ المفوَّض أن المالك أُشعر.
  static void noteWrite(String? assetId) {
    if (!isDelegated(assetId)) return;
    lastWriteAsset = assetId!;
    writes.value++;
  }

  /// صفوف fundly_my_delegated_assets — صف لكل تفويض/وحدة، تُجمع بالأصل.
  static void replaceFromRows(List<dynamic> rows) {
    final perms = <String, Set<String>>{};
    final units = <String, Set<String>>{};
    final whole = <String, bool>{};
    final owners = <String, (String, String, String)>{};
    final delegations = <String, Set<String>>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final id = '${raw['asset_id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      owners[id] = (
        '${raw['owner_id'] ?? ''}',
        '${raw['owner_name'] ?? ''}',
        '${raw['owner_fnd'] ?? ''}',
      );
      final delegationId = '${raw['delegation_id'] ?? ''}'.trim();
      if (delegationId.isNotEmpty) {
        delegations.putIfAbsent(id, () => <String>{}).add(delegationId);
      }
      final list = raw['permissions'];
      if (list is List) {
        perms.putIfAbsent(id, () => <String>{}).addAll(list.map((p) => '$p'));
      }
      final ref = '${raw['unit_ref'] ?? ''}'.trim();
      if (ref.isEmpty || raw['unit_ref'] == null) {
        whole[id] = true;
      } else {
        units.putIfAbsent(id, () => <String>{}).add(ref);
      }
    }
    _byId = {
      for (final entry in owners.entries)
        entry.key: DelegatedAsset(
          assetId: entry.key,
          ownerId: entry.value.$1,
          ownerName: entry.value.$2,
          ownerFnd: entry.value.$3,
          permissions: perms[entry.key] ?? const <String>{},
          wholeAsset: whole[entry.key] ?? false,
          unitRefs: units[entry.key] ?? const <String>{},
          delegationIds: delegations[entry.key] ?? const <String>{},
        ),
    };
  }

  static void clear() => _byId = const {};
}

/// ما فوّضتُه أنا لغيري (تفويض مقبول وساري) على عقار/مركبة/نشاط أو وحدة.
class OutgoingDelegation {
  const OutgoingDelegation({
    required this.delegateName,
    required this.wholeAsset,
    required this.unitRefs,
    this.permissions = const <String>[],
  });

  /// الصلاحيات التي أعطيتها (بلا العلامات الداخلية).
  final List<String> permissions;

  final String delegateName;

  /// العنصر كاملًا؛ وإلا وحدات بعينها [unitRefs].
  final bool wholeAsset;
  final Set<String> unitRefs;

  bool allowsUnit({
    required String number,
    required String name,
    int index = -1,
  }) {
    if (wholeAsset) return true;
    final n = number.trim();
    final m = name.trim();
    if (n.isNotEmpty) return unitRefs.contains(n);
    if (m.isNotEmpty) return unitRefs.contains(m);
    return index >= 0 && unitRefs.contains('$index');
  }
}

/// سجل ما فوّضتُه لغيري — يُملأ مع قائمة العقارات ويُقرأ في البطاقات.
class OutgoingDelegations {
  OutgoingDelegations._();

  static Map<String, List<OutgoingDelegation>> _byAsset = const {};

  static List<OutgoingDelegation> of(String? assetId) =>
      assetId == null ? const [] : (_byAsset[assetId] ?? const []);

  static void replace(Map<String, List<OutgoingDelegation>> map) =>
      _byAsset = map;

  /// «فوّضته إلى: زين» أو «فوّضت وحدات منه إلى: زين» — فارغ إن لا شيء.
  static String noteOf(String? assetId) {
    final list = of(assetId);
    if (list.isEmpty) return '';
    final whole = <String>{
      for (final d in list)
        if (d.wholeAsset) d.delegateName,
    };
    final units = <String>{
      for (final d in list)
        if (!d.wholeAsset) d.delegateName,
    };
    return [
      if (whole.isNotEmpty) 'فوّضت غيري بإدارته — ${whole.join('، ')}',
      if (units.isNotEmpty) 'فوّضت غيري بإدارة وحدات منه — ${units.join('، ')}',
    ].join(' · ');
  }

  /// من فُوِّض بهذه الوحدة بعينها (تفويض الوحدة لا العقار كاملًا).
  static String unitNoteOf(
    String? assetId, {
    required String number,
    required String name,
    int index = -1,
  }) {
    final names = <String>{
      for (final d in of(assetId))
        if (!d.wholeAsset &&
            d.allowsUnit(number: number, name: name, index: index))
          d.delegateName,
    };
    return names.isEmpty ? '' : 'فوّضت غيري بإدارته — ${names.join('، ')}';
  }
}
