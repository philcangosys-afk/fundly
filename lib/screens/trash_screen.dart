import 'dart:convert';

import 'package:flutter/material.dart' hide Text, Align;

import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/app_settings.dart';
import '../data/personal_entries_repository.dart';
import '../data/project_assets_repository.dart';
import '../data/shared_entries_repository.dart';
import '../data/shared_member_state.dart';
import '../data/shared_alerts.dart';
import '../data/shared_expenses.dart';
import '../widgets/shared/app_design.dart';

/// سلة المهملات: ما يُحذف لا يضيع فورًا.
///
/// الحذف في التطبيق لا يمسح السجل من الخادم، بل يضع حالته «محذوف» ويحفظ
/// حالته السابقة وتاريخ الحذف داخل تفاصيله نفسها (بلا أي جدول جديد).
/// من هنا يُستعاد السجل إلى حالته الأصلية أو يُحذف نهائيًا بلا رجعة.
class TrashStore {
  TrashStore._();

  /// الحالة التي تُوضع على أي سجل محذوف.
  static const String status = 'محذوف';

  /// الحالة التي كان عليها السجل قبل الحذف — تُعاد عند الاستعادة.
  static const String previousStatusKey = 'الحالة قبل الحذف';

  /// تاريخ الحذف كما يظهر في السلة.
  static const String deletedAtKey = 'تاريخ الحذف';

  /// من أي قسم جاء السجل، ليُعرف مكانه عند الاستعادة.
  static const String sourceKey = 'مصدر السجل';

  /// كل مفاتيح السلة — تُستثنى من العرض في صفحات التفاصيل.
  static const List<String> keys = [
    previousStatusKey,
    deletedAtKey,
    sourceKey,
  ];

  static String stamp() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  /// تفاصيل السجل بعد نقله إلى السلة.
  static Map<String, String> markDeleted(
    Map<String, String> details,
    String previousStatus,
    String source,
  ) {
    return Map<String, String>.of(details)
      ..[previousStatusKey] = previousStatus
      ..[deletedAtKey] = stamp()
      ..[sourceKey] = source;
  }

  /// تفاصيل السجل بعد استعادته (تُنزع مفاتيح السلة).
  static Map<String, String> clear(Map<String, String> details) {
    final out = Map<String, String>.of(details);
    for (final key in keys) {
      out.remove(key);
    }
    return out;
  }
}

/// صفحة سلة المهملات: كل المحذوفات مع استعادة أو حذف نهائي.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

/// عقار/نشاط/مركبة في السلة: ما يلزم لعرضه واستعادته.
class _TrashedAsset {
  const _TrashedAsset(this.record, this.meta);

  final ProjectAssetRecord record;

  /// البيانات الرسمية المحفوظة في سجل الأصل (منها تاريخ الحذف ومصدره).
  final Map<String, String> meta;

  String get source {
    final saved = (meta[TrashStore.sourceKey] ?? '').trim();
    if (saved.isNotEmpty) return saved;
    return switch (record.category) {
      'real_estate' => 'العقارات',
      'activity' => 'الأنشطة التجارية',
      _ => 'المركبات ووسائل النقل',
    };
  }

  String get deletedAt => (meta[TrashStore.deletedAtKey] ?? '').trim();

  /// يقرأ سطر البيانات الرسمية من سجل الأصل (نفس صيغة شاشة العقارات).
  static Map<String, String> metaOf(ProjectAssetRecord record) {
    const prefix = '##meta##';
    final raw = record.logsJson;
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      for (final line in decoded) {
        final text = '$line';
        if (!text.startsWith(prefix)) continue;
        final map = jsonDecode(text.substring(prefix.length));
        if (map is! Map) continue;
        return {
          for (final entry in map.entries) '${entry.key}': '${entry.value ?? ''}',
        };
      }
    } catch (_) {}
    return const {};
  }

  /// نسخة السجل بحالة أخرى (لاستعادته من السلة)، وبوحدات أخرى إن لزم.
  ProjectAssetRecord withStatus(String status, {String? unitsJson}) {
    final r = record;
    return ProjectAssetRecord(
      id: r.id,
      title: r.title,
      subType: r.subType,
      category: r.category,
      status: status,
      locationOrType: r.locationOrType,
      amountLabel: r.amountLabel,
      followupNote: r.followupNote,
      owner: r.owner,
      tenant: r.tenant,
      rentValue: r.rentValue,
      endDate: r.endDate,
      annualYield: r.annualYield,
      occupancyRate: r.occupancyRate,
      contractProgress: r.contractProgress,
      paymentProgress: r.paymentProgress,
      documentsProgress: r.documentsProgress,
      needsAttention: r.needsAttention,
      iconColor: r.iconColor,
      coverUrl: r.coverUrl,
      description: r.description,
      annexes: r.annexes,
      mapLink: r.mapLink,
      quickAddEnabled: r.quickAddEnabled,
      unitsJson: unitsJson ?? r.unitsJson,
      employeesJson: r.employeesJson,
      serialNumber: r.serialNumber,
      isFrozen: r.isFrozen,
      isPinned: r.isPinned,
      isSublease: r.isSublease,
      latitude: r.latitude,
      longitude: r.longitude,
      logsJson: r.logsJson,
    );
  }
}

/// وحدة عقار في السلة: تبقى داخل وحدات عقارها بحالة «محذوفة» حتى
/// تُستعاد إلى أرشيف الوحدات أو تُحذف نهائيًا من العقار.
class _TrashedUnit {
  const _TrashedUnit(this.owner, this.map);

  static const String status = 'محذوفة';

  final _TrashedAsset owner;
  final Map<String, dynamic> map;

  static List<Map<String, dynamic>> decode(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      return [
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> extrasOf(Map<String, dynamic> m) =>
      m['extras'] is Map
      ? (m['extras'] as Map).map((k, v) => MapEntry('$k', '${v ?? ''}'))
      : <String, String>{};

  /// نفس مفتاح الوحدة في شاشة العقارات: المثبَّت أو «النوع|الاسم|الرقم».
  static String keyOf(Map<String, dynamic> m) {
    final pinned = (extrasOf(m)['__key'] ?? '').trim();
    if (pinned.isNotEmpty) return pinned;
    return '${m['type'] ?? ''}|${m['name'] ?? ''}|${m['unitNumber'] ?? ''}';
  }

  String get key => keyOf(map);

  String get name {
    final value = '${map['name'] ?? ''}'.trim();
    return value.isEmpty ? 'وحدة' : value;
  }

  String get deletedAt =>
      (extrasOf(map)[TrashStore.deletedAtKey] ?? '').trim();
}

class _TrashScreenState extends State<TrashScreen> {
  final PersonalEntriesRepository _repository = SupabasePersonalEntriesRepository();
  final ProjectAssetsRepository _assetsRepository =
      SupabaseProjectAssetsRepository();
  List<PersonalEntryRecord> _items = const [];

  /// العقارات والأنشطة والمركبات المحذوفة (بعد إلغائها).
  List<_TrashedAsset> _assets = const [];

  /// وحدات العقارات المحذوفة من أرشيف الوحدات.
  List<_TrashedUnit> _units = const [];

  /// الالتزامات المشتركة المحذوفة من عندي (المشاركات والرحلات وتحديد
  /// الأدوار).
  final SupabaseSharedEntriesRepository _sharedRepository =
      SupabaseSharedEntriesRepository();
  List<SharedEntryRecord> _shared = const [];

  int get _count =>
      _items.length + _assets.length + _units.length + _shared.length;

  String _sharedKeyOf(SharedEntryRecord record) => 's:${record.id}';

  /// حذف نهائي من الخادم: وحدي، أو بعد أن حذفه كل الأعضاء.
  bool _canPurgeShared(SharedEntryRecord record) =>
      !SharedMemberState.sharedWithOthers(record.details) ||
      SharedMemberState.removedByAll(record.details);

  Future<bool> _restoreShared(SharedEntryRecord record) async {
    try {
      await SharedMemberState.markMine(
        _sharedRepository,
        record,
        SharedMemberState.removedKey,
        add: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _purgeShared(SharedEntryRecord record) async {
    final id = record.id;
    if (id == null || !_canPurgeShared(record)) return false;
    try {
      await _sharedRepository.delete(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// العناصر المحددة: «p:معرّف» للالتزامات و«a:معرّف» للأصول.
  final Set<String> _selected = {};

  String _keyOf(PersonalEntryRecord record) => 'p:${record.id}';
  String _assetKeyOf(_TrashedAsset asset) => 'a:${asset.record.id}';
  String _unitKeyOf(_TrashedUnit unit) =>
      'u:${unit.owner.record.id}:${unit.key}';

  List<String> get _allKeys => [
    for (final record in _items) _keyOf(record),
    for (final asset in _assets) _assetKeyOf(asset),
    for (final unit in _units) _unitKeyOf(unit),
    for (final record in _shared) _sharedKeyOf(record),
  ];

  bool get _allSelected =>
      _count > 0 && _allKeys.every((key) => _selected.contains(key));

  void _toggle(String key) => setState(() {
    if (!_selected.remove(key)) _selected.add(key);
  });

  Widget _selectBox(String key) => Checkbox(
    value: _selected.contains(key),
    activeColor: AppTheme.brandMid,
    visualDensity: VisualDensity.compact,
    onChanged: (_) => _toggle(key),
  );

  /// شريط التحديد: «تحديد الكل»، ثم استعادة أو حذف المحدد نهائيًا.
  Widget _buildSelectionBar() {
    final count = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Checkbox(
            value: _allSelected,
            activeColor: AppTheme.brandMid,
            onChanged: (_) => setState(() {
              if (_allSelected) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(_allKeys);
              }
            }),
          ),
          Expanded(
            child: Text(
              count == 0 ? 'تحديد الكل' : 'المحدد: $count',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
          ),
          if (count > 0) ...[
            TextButton.icon(
              onPressed: _restoreSelected,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('استعادة'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.brandMid,
                visualDensity: VisualDensity.compact,
              ),
            ),
            TextButton.icon(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text('حذف نهائي'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.danger,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _restoreSelected() async {
    final ok = await confirmAction(
      context,
      title: 'استعادة المحدد',
      message: 'سيعود ${_selected.length} عنصرًا إلى أماكنها. هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
    );
    if (!ok) return;
    var failed = 0;
    for (final record in _items) {
      if (!_selected.contains(_keyOf(record))) continue;
      final previous =
          (record.details[TrashStore.previousStatusKey] ?? '').trim();
      try {
        await _repository.update(
          PersonalEntryRecord(
            id: record.id,
            category: record.category,
            entryType: record.entryType,
            title: record.title,
            amount: record.amount,
            dueDate: record.dueDate,
            status: previous.isEmpty ? 'نشطة' : previous,
            details: TrashStore.clear(record.details),
            attachmentUrl: record.attachmentUrl,
          ),
        );
      } catch (_) {
        failed++;
      }
    }
    for (final asset in _assets) {
      if (!_selected.contains(_assetKeyOf(asset))) continue;
      final previous = (asset.meta[TrashStore.previousStatusKey] ?? '').trim();
      try {
        await _assetsRepository.updateAsset(
          asset.withStatus(previous.isEmpty ? 'ملغي' : previous),
        );
      } catch (_) {
        failed++;
      }
    }
    try {
      await _applyUnits(
        [for (final u in _units) if (_selected.contains(_unitKeyOf(u))) u],
        restore: true,
      );
    } catch (_) {
      failed++;
    }
    for (final record in _shared) {
      if (!_selected.contains(_sharedKeyOf(record))) continue;
      if (!await _restoreShared(record)) failed++;
    }
    if (!mounted) return;
    _selected.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0 ? 'تمت الاستعادة' : 'تمت الاستعادة، وتعذّر $failed عنصر',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _load();
  }

  Future<void> _deleteSelected() async {
    final ok = await confirmAction(
      context,
      title: 'حذف نهائي',
      message: 'سيُحذف ${_selected.length} عنصرًا نهائيًا ولا يمكن '
          'استرجاعها. هل تريد المتابعة؟',
      confirmLabel: 'حذف نهائي',
      danger: true,
    );
    if (!ok) return;
    for (final record in _items) {
      final id = record.id;
      if (id == null || !_selected.contains(_keyOf(record))) continue;
      try {
        await _repository.delete(id);
      } catch (_) {}
    }
    for (final asset in _assets) {
      final id = asset.record.id;
      if (id == null || !_selected.contains(_assetKeyOf(asset))) continue;
      try {
        await _assetsRepository.deleteAsset(id);
      } catch (_) {}
    }
    try {
      await _applyUnits(
        [for (final u in _units) if (_selected.contains(_unitKeyOf(u))) u],
        restore: false,
      );
    } catch (_) {}
    for (final record in _shared) {
      if (_selected.contains(_sharedKeyOf(record))) await _purgeShared(record);
    }
    if (!mounted) return;
    _selected.clear();
    await _load();
  }
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repository.fetchAll();
      var assets = const <_TrashedAsset>[];
      var units = const <_TrashedUnit>[];
      try {
        final records = await _assetsRepository.fetchAssets();
        assets = [
          for (final record in records)
            if (record.status == TrashStore.status)
              _TrashedAsset(record, _TrashedAsset.metaOf(record)),
        ];
        // وحدات محذوفة داخل عقارات قائمة (العقار المحذوف يأخذ وحداته معه).
        units = [
          for (final record in records)
            if (record.status != TrashStore.status)
              for (final row in _TrashedUnit.decode(record.unitsJson))
                if (row['status'] == _TrashedUnit.status)
                  _TrashedUnit(
                    _TrashedAsset(record, _TrashedAsset.metaOf(record)),
                    row,
                  ),
        ];
      } catch (_) {
        // تعذّر تحميل الأصول لا يُخفي محذوفات الالتزامات.
      }
      var shared = const <SharedEntryRecord>[];
      try {
        shared = await _sharedRepository.fetchRemovedByMe();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _shared = shared;
        _items = rows
            .where((row) => row.status == TrashStore.status)
            .toList(growable: false);
        _assets = assets;
        _units = units;
        _loading = false;
        _selected.removeWhere((key) => !_allKeys.contains(key));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _restore(PersonalEntryRecord record) async {
    final ok = await confirmAction(
      context,
      title: 'استعادة',
      // القسم والفئة والنوع الذي يعود إليه.
      message: '${AppTr.tr('سيعود')} «${record.title}» '
          '${AppTr.tr('إلى')} ${AppTr.tr('الالتزامات الشخصية')} - '
          '${_categoryName(record.category)}'
          '${record.entryType.isEmpty ? '' : ' - ${AppTr.tr(record.entryType)}'}. '
          '${AppTr.tr('هل تريد المتابعة؟')}',
      confirmLabel: 'استعادة',
    );
    if (!ok) return;
    final previous =
        (record.details[TrashStore.previousStatusKey] ?? '').trim();
    try {
      await _repository.update(
        PersonalEntryRecord(
          id: record.id,
          category: record.category,
          entryType: record.entryType,
          title: record.title,
          amount: record.amount,
          dueDate: record.dueDate,
          status: previous.isEmpty ? 'نشطة' : previous,
          details: TrashStore.clear(record.details),
          attachmentUrl: record.attachmentUrl,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('استُعيد «${record.title}» إلى مكانه'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّرت الاستعادة: $error')));
    }
  }

  Future<void> _deleteForever(PersonalEntryRecord record) async {
    final ok = await confirmAction(
      context,
      title: 'حذف نهائي',
      message: 'سيُحذف «${record.title}» نهائيًا ولا يمكن استرجاعه بعدها. '
          'هل تريد الحذف؟',
      confirmLabel: 'حذف نهائي',
      danger: true,
    );
    if (!ok) return;
    final id = record.id;
    if (id == null) return;
    try {
      await _repository.delete(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حُذف «${record.title}» نهائيًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر الحذف: $error')));
    }
  }

  Future<void> _restoreAsset(_TrashedAsset asset) async {
    final ok = await confirmAction(
      context,
      title: 'استعادة',
      message: 'سيعود «${asset.record.title}» إلى ${asset.source} بحالة '
          '«ملغي». هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
    );
    if (!ok) return;
    final previous = (asset.meta[TrashStore.previousStatusKey] ?? '').trim();
    try {
      await _assetsRepository.updateAsset(
        asset.withStatus(previous.isEmpty ? 'ملغي' : previous),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('استُعيد «${asset.record.title}» إلى مكانه'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّرت الاستعادة: $error')));
    }
  }

  Future<void> _deleteAssetForever(_TrashedAsset asset) async {
    final ok = await confirmAction(
      context,
      title: 'حذف نهائي',
      message: 'سيُحذف «${asset.record.title}» نهائيًا مع بياناته ولا يمكن '
          'استرجاعه بعدها. هل تريد الحذف؟',
      confirmLabel: 'حذف نهائي',
      danger: true,
    );
    if (!ok) return;
    final id = asset.record.id;
    if (id == null) return;
    try {
      await _assetsRepository.deleteAsset(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حُذف «${asset.record.title}» نهائيًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر الحذف: $error')));
    }
  }

  Future<void> _emptyTrash() async {
    final ok = await confirmAction(
      context,
      title: 'إفراغ السلة',
      message: 'سيُحذف $_count عنصرًا نهائيًا ولا يمكن استرجاعها. '
          'هل تريد المتابعة؟',
      confirmLabel: 'إفراغ',
      danger: true,
    );
    if (!ok) return;
    for (final record in _items) {
      final id = record.id;
      if (id == null) continue;
      try {
        await _repository.delete(id);
      } catch (_) {
        // عنصر تعذّر حذفه لا يوقف بقية العناصر.
      }
    }
    for (final asset in _assets) {
      final id = asset.record.id;
      if (id == null) continue;
      try {
        await _assetsRepository.deleteAsset(id);
      } catch (_) {}
    }
    try {
      await _applyUnits(_units, restore: false);
    } catch (_) {}
    for (final record in _shared) {
      await _purgeShared(record);
    }
    if (!mounted) return;
    await _load();
  }

  /// يكتب تغيير وحدات السلة في عقاراتها: استعادة إلى أرشيف الوحدات، أو
  /// حذف نهائي من وحدات العقار. وحدات العقار الواحد تُكتب معًا.
  Future<void> _applyUnits(
    List<_TrashedUnit> units, {
    required bool restore,
  }) async {
    final byAsset = <String, List<_TrashedUnit>>{};
    for (final unit in units) {
      final id = unit.owner.record.id;
      if (id == null) continue;
      byAsset.putIfAbsent(id, () => []).add(unit);
    }
    for (final group in byAsset.values) {
      final owner = group.first.owner;
      final keys = {for (final unit in group) unit.key};
      final out = <Map<String, dynamic>>[];
      for (final row in _TrashedUnit.decode(owner.record.unitsJson)) {
        final inTrash = row['status'] == _TrashedUnit.status &&
            keys.contains(_TrashedUnit.keyOf(row));
        if (!inTrash) {
          out.add(row);
          continue;
        }
        if (!restore) continue;
        final extras = _TrashedUnit.extrasOf(row);
        final previous = (extras[TrashStore.previousStatusKey] ?? '').trim();
        out.add({
          ...row,
          'status': previous.isEmpty ? 'مؤرشفة' : previous,
          'extras': TrashStore.clear(extras),
        });
      }
      await _assetsRepository.updateAsset(
        owner.withStatus(owner.record.status, unitsJson: jsonEncode(out)),
      );
    }
  }

  Future<void> _restoreUnit(_TrashedUnit unit) async {
    final ok = await confirmAction(
      context,
      title: 'استعادة',
      message: 'ستعود «${unit.name}» إلى أرشيف وحدات '
          '«${unit.owner.record.title}». هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
    );
    if (!ok) return;
    try {
      await _applyUnits([unit], restore: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('استُعيدت «${unit.name}» إلى أرشيف الوحدات'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّرت الاستعادة: $error')));
    }
  }

  Future<void> _deleteUnitForever(_TrashedUnit unit) async {
    final ok = await confirmAction(
      context,
      title: 'حذف نهائي',
      message: 'ستُحذف «${unit.name}» نهائيًا من «${unit.owner.record.title}» '
          'ولا يمكن استرجاعها بعدها. هل تريد الحذف؟',
      confirmLabel: 'حذف نهائي',
      danger: true,
    );
    if (!ok) return;
    try {
      await _applyUnits([unit], restore: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حُذفت «${unit.name}» نهائيًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر الحذف: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text('سلة المهملات', style: AppTheme.cardTitle),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (_count > 0)
              IconButton(
                tooltip: AppTr.tr('إفراغ السلة'),
                onPressed: _emptyTrash,
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppTheme.danger,
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError()
            : _count == 0
            ? _buildEmpty()
            : RefreshIndicator(
                onRefresh: _load,
                color: AppTheme.brandMid,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _count + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        children: [
                          _buildHint(),
                          const SizedBox(height: 10),
                          _buildSelectionBar(),
                        ],
                      );
                    }
                    final i = index - 1;
                    if (i < _items.length) return _buildRow(_items[i]);
                    if (i < _items.length + _assets.length) {
                      return _buildAssetRow(_assets[i - _items.length]);
                    }
                    final u = i - _items.length - _assets.length;
                    if (u < _units.length) return _buildUnitRow(_units[u]);
                    return _buildSharedRow(_shared[u - _units.length]);
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.goldSoft,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: AppTheme.goldDark,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'كل ما تحذفه يصل إلى هنا، ويمكنك استعادته إلى مكانه أو حذفه '
              'نهائيًا.',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: AppTheme.goldDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              size: 52,
              color: AppTheme.muted,
            ),
            const SizedBox(height: 12),
            const Text(
              'السلة فارغة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ما تحذفه من الالتزامات الشخصية والعقارات والأنشطة والمركبات '
              'يظهر هنا قبل حذفه نهائيًا.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 46,
              color: AppTheme.danger,
            ),
            const SizedBox(height: 12),
            const Text(
              'تعذّر تحميل السلة',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brand,
                foregroundColor: Colors.white,
              ),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  /// وحدة عقار في السلة — نفس بطاقة العقارات، والاستعادة إلى أرشيف
  /// وحدات العقار.
  Widget _buildUnitRow(_TrashedUnit unit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _selectBox(_unitKeyOf(unit)),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: const Icon(
                  Icons.meeting_room_outlined,
                  size: 20,
                  color: AppTheme.goldDark,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      unit.name,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // سطر واحد كامل: يصغر الخط بدل القص.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                      [
                        'وحدة في «${unit.owner.record.title}»',
                        if (unit.deletedAt.isNotEmpty)
                          'حُذفت في ${unit.deletedAt}',
                      ].join(' · '),
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _restoreUnit(unit),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text(
                    'استعادة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _deleteUnitForever(unit),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text(
                    'حذف نهائي',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssetRow(_TrashedAsset asset) {
    final icon = switch (asset.record.category) {
      'real_estate' => Icons.apartment_rounded,
      'activity' => Icons.storefront_rounded,
      _ => Icons.directions_car_rounded,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _selectBox(_assetKeyOf(asset)),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(icon, size: 20, color: AppTheme.goldDark),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      asset.record.title,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // سطر واحد كامل: يصغر الخط بدل القص.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                      [
                        asset.source,
                        if (asset.record.subType.isNotEmpty)
                          asset.record.subType,
                        if (asset.deletedAt.isNotEmpty)
                          'حُذف في ${asset.deletedAt}',
                      ].join(' · '),
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _restoreAsset(asset),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text(
                    'استعادة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _deleteAssetForever(asset),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text(
                    'حذف نهائي',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// التزام مشترك حذفته من عندي: استعادة، أو حذف نهائي (وحدي أو بعد
  /// حذف كل الأعضاء له).
  Widget _buildSharedRow(SharedEntryRecord record) {
    final type = record.entryType == 'جمعية مالية'
        ? 'تحديد أدوار'
        : record.entryType;
    final cancelled = record.status == 'ملغاة';
    final canPurge = _canPurgeShared(record);
    // حالته: مكتمل، ملغى، أو هل بقي فيه حساب لم يُسوَّ.
    final state = record.status == 'مكتملة'
        ? 'مكتملة'
        : cancelled
        ? 'ملغاة'
        : type == 'تحديد أدوار'
        ? (record.status.isEmpty ? 'نشطة' : record.status)
        : SharedLedger.settleTransfers(
                record.details,
                sharedMemberNames(record.details),
              ).isEmpty
        ? 'تمت التسوية'
        : 'لم تتم التسوية';
    final stateColor = switch (state) {
      'مكتملة' => const Color(0xFF1E2725),
      'تمت التسوية' => AppTheme.brandMid,
      'ملغاة' || 'لم تتم التسوية' => AppTheme.danger,
      _ => AppTheme.muted,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _selectBox(_sharedKeyOf(record)),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: const Icon(
                  Icons.groups_2_outlined,
                  size: 20,
                  color: AppTheme.brandMid,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      record.title.isEmpty ? type : record.title,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        AppTr.tr('الالتزامات المشتركة'),
                        AppTr.tr(type),
                      ].join(' · '),
                      textAlign: AppTr.alignEnd,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stateColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTheme.rPill),
                        ),
                        child: Text(
                          '${AppTr.tr('الحالة')}: ${AppTr.tr(state)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: stateColor,
                          ),
                        ),
                      ),
                    ),
                    if (!canPurge)
                      const Text(
                        'يُحذف نهائيًا بعد أن يحذفه كل الأعضاء',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.goldDark,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final ok = await confirmAction(
                      context,
                      title: 'استعادة',
                      message: '${AppTr.tr('سيعود')} «${record.title}» '
                          '${AppTr.tr('إلى')} ${AppTr.tr('الالتزامات المشتركة')} - '
                          '${AppTr.tr(type == 'مشاركات مشتركة' ? 'المشاركات المشتركة' : type)}. '
                          '${AppTr.tr('هل تريد المتابعة؟')}',
                      confirmLabel: 'استعادة',
                    );
                    if (!ok) return;
                    await _restoreShared(record);
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text(
                    'استعادة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              if (canPurge) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      minimumSize: const Size.fromHeight(34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: 'حذف نهائي',
                        message: 'سيُحذف «${record.title}» نهائيًا ولا يمكن '
                            'استرجاعه. هل تريد المتابعة؟',
                        confirmLabel: 'حذف نهائي',
                        danger: true,
                      );
                      if (!ok) return;
                      await _purgeShared(record);
                      if (mounted) await _load();
                    },
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text(
                      'حذف نهائي',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// اسم فئة الالتزام الشخصي (المخزّن رمزها).
  static String _categoryName(String slug) => AppTr.tr(switch (slug) {
    'financial' => 'مالية',
    'document' => 'مستندات',
    'organization' => 'المتابعة والتخطيط',
    'medical_accounts' => 'أدوية وبيانات وكلمات سر',
    'lifestyle' => 'نمط الحياة',
    'location' => 'مواقع وأماكن',
    'custody' => 'عهدة مالية',
    _ => slug.isEmpty ? 'أخرى' : slug,
  });

  Widget _buildRow(PersonalEntryRecord record) {
    final deletedAt = (record.details[TrashStore.deletedAtKey] ?? '').trim();
    // حالته قبل الحذف: المتأخر أحمر والمكتمل أسود.
    final previous =
        (record.details[TrashStore.previousStatusKey] ?? '').trim();
    final state = previous.isEmpty ? 'نشطة' : previous;
    final stateColor = state.contains('متأخر')
        ? AppTheme.danger
        : state.contains('مكتمل')
        ? const Color(0xFF1E2725)
        : state.contains('ملغا')
        ? AppTheme.muted
        : AppTheme.brandMid;
    final source = (record.details[TrashStore.sourceKey] ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _selectBox(_keyOf(record)),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppTheme.brandMid,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      record.title,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // سطر واحد كامل: يصغر الخط بدل القص.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                      [
                        if (source.isNotEmpty)
                          source
                        else if (record.entryType.isNotEmpty)
                          record.entryType,
                        if (record.amount > 0)
                          '${record.amount} ${AppSettings.currencySuffix}',
                        if (deletedAt.isNotEmpty) 'حُذف في $deletedAt',
                      ].join(' · '),
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stateColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTheme.rPill),
                        ),
                        child: Text(
                          '${AppTr.tr('الحالة')}: ${AppTr.tr(state)} · '
                          '${_categoryName(record.category)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: stateColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _restore(record),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text(
                    'استعادة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size.fromHeight(34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _deleteForever(record),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text(
                    'حذف نهائي',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
