import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'personal_entries_repository.dart';
import 'shared_entries_repository.dart';
import 'shared_member_state.dart';
import 'project_assets_repository.dart';
import '../screens/trash_screen.dart' show TrashStore;

/// عنصر مؤرشف واحد، أيًّا كان القسم الذي جاء منه.
class ArchivedRecord {
  const ArchivedRecord({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.unarchive,
    this.moveToTrash,
  });

  /// اسم القسم: يُستعمل تبويبًا في صفحة الأرشيف.
  final String source;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// تُعيد true إذا نجح إلغاء الأرشفة فعلًا.
  final Future<bool> Function() unarchive;

  /// اختياري: حذف من الأرشيف إلى سلة المهملات (وحدات العقارات).
  final Future<bool> Function()? moveToTrash;
}

/// مركز الأرشيف: يجمع كل ما أُرشف في التطبيق من مصادره الأربعة.
///
/// الأرشفة موزّعة بطبيعتها: الالتزامات تحفظها في حالة السجل، والأفراد في
/// علامة داخل الملاحظة، والعقارات في حالة الأصل. هذا المركز يوحّدها في
/// قائمة واحدة قابلة للبحث والتصفية والاستخراج، ويعرف كيف يُلغي أرشفة كل
/// نوع بطريقته الصحيحة.
class ArchiveCenter {
  ArchiveCenter._();

  static const String personalSource = 'الالتزامات الشخصية';
  static const String sharedSource = 'الالتزامات المشتركة';
  static const String peopleSource = 'الأفراد والجهات';
  static const String assetsSource = 'العقارات والأنشطة';

  static const List<String> sources = [
    personalSource,
    sharedSource,
    peopleSource,
    assetsSource,
  ];

  static const String _peopleStorageKey = 'people_management_records_v1';

  /// الالتزامات المشتركة المكتملة تنتقل إلى الأرشيف تلقائيًا؛ ما أخرجه
  /// المستخدم منها يُحفظ هنا (على جهازه) فيعود إلى قائمته.
  static const String sharedCompletedShownKey = 'shared_completed_shown_v1';
  static const String _archivedMark = '[مؤرشف]';

  /// تحميل كل المؤرشفات. أي مصدر يفشل لا يُسقط البقية.
  static Future<List<ArchivedRecord>> loadAll() async {
    final out = <ArchivedRecord>[];
    out.addAll(await _loadPersonal());
    out.addAll(await _loadShared());
    out.addAll(await _loadPeople());
    out.addAll(await _loadAssets());
    return out;
  }

  static Future<List<ArchivedRecord>> _loadPersonal() async {
    try {
      final repository = SupabasePersonalEntriesRepository();
      final rows = await repository.fetchAll();
      return [
        for (final row in rows)
          if (row.status == 'مؤرشف')
            ArchivedRecord(
              source: personalSource,
              title: row.title,
              subtitle: [
                if (row.entryType.isNotEmpty) row.entryType,
                if (row.amount > 0) '${row.amount}',
                if (row.dueDate.isNotEmpty) row.dueDate,
              ].join(' · '),
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF34A894),
              unarchive: () async {
                try {
                  await repository.update(
                    PersonalEntryRecord(
                      id: row.id,
                      category: row.category,
                      entryType: row.entryType,
                      title: row.title,
                      amount: row.amount,
                      dueDate: row.dueDate,
                      status: 'نشطة',
                      details: row.details,
                      attachmentUrl: row.attachmentUrl,
                    ),
                  );
                  return true;
                } catch (_) {
                  return false;
                }
              },
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ArchivedRecord>> _loadShared() async {
    try {
      final repository = SupabaseSharedEntriesRepository();
      final rows = await repository.fetchAll();
      final prefs = await SharedPreferences.getInstance();
      final shown =
          (prefs.getStringList(sharedCompletedShownKey) ?? const <String>[])
              .toSet();
      return [
        for (final row in rows)
          // المؤرشف للجميع (الحالة)، أو المؤرشف عندي وحدي، أو المكتمل.
          if (row.status.contains('مؤرشف') ||
              SharedMemberState.hasMine(
                row.details,
                SharedMemberState.archivedKey,
              ) ||
              (row.status == 'مكتملة' && !shown.contains(row.id)))
            ArchivedRecord(
              source: sharedSource,
              title: row.title,
              subtitle: [
                if (row.entryType.isNotEmpty) row.entryType,
                if (row.amount > 0) '${row.amount}',
                if (row.dueDate.isNotEmpty) row.dueDate,
              ].join(' · '),
              icon: Icons.groups_2_outlined,
              color: const Color(0xFF0E7161),
              unarchive: () async {
                try {
                  // المكتمل: يعود إلى قائمتي فقط (الحالة تبقى «مكتملة»).
                  if (row.status == 'مكتملة' &&
                      !SharedMemberState.hasMine(
                        row.details,
                        SharedMemberState.archivedKey,
                      )) {
                    final store = await SharedPreferences.getInstance();
                    final list = (store.getStringList(
                              sharedCompletedShownKey,
                            ) ??
                            const <String>[])
                        .toList();
                    if (row.id != null && !list.contains(row.id)) {
                      list.add(row.id!);
                    }
                    await store.setStringList(sharedCompletedShownKey, list);
                    return true;
                  }
                  if (SharedMemberState.hasMine(
                    row.details,
                    SharedMemberState.archivedKey,
                  )) {
                    await SharedMemberState.markMine(
                      repository,
                      row,
                      SharedMemberState.archivedKey,
                      add: false,
                    );
                    return true;
                  }
                  await repository.update(
                    SharedEntryRecord(
                      id: row.id,
                      entryType: row.entryType,
                      title: row.title,
                      amount: row.amount,
                      dueDate: row.dueDate,
                      status: 'نشطة',
                      details: row.details,
                    ),
                  );
                  return true;
                } catch (_) {
                  return false;
                }
              },
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ArchivedRecord>> _loadPeople() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_peopleStorageKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final rows = decoded.whereType<Map>().toList();
      final out = <ArchivedRecord>[];
      for (var i = 0; i < rows.length; i++) {
        final row = Map<String, dynamic>.from(rows[i]);
        final note = (row['extraNote'] ?? '').toString();
        if (!note.contains(_archivedMark)) continue;
        final index = i;
        out.add(
          ArchivedRecord(
            source: peopleSource,
            title: (row['fullName'] ?? '').toString(),
            subtitle: [
              (row['roleTitle'] ?? '').toString(),
              (row['categoryName'] ?? '').toString(),
            ].where((value) => value.trim().isNotEmpty).join(' · '),
            icon: Icons.person_outline_rounded,
            color: const Color(0xFF178F7B),
            unarchive: () async {
              try {
                final store = await SharedPreferences.getInstance();
                final current = jsonDecode(
                  store.getString(_peopleStorageKey) ?? '[]',
                );
                if (current is! List || index >= current.length) return false;
                final person = Map<String, dynamic>.from(
                  current[index] as Map,
                );
                person['extraNote'] = (person['extraNote'] ?? '')
                    .toString()
                    .replaceAll(_archivedMark, '')
                    .trim();
                person['isFrozen'] = false;
                current[index] = person;
                await store.setString(
                  _peopleStorageKey,
                  jsonEncode(current),
                );
                return true;
              } catch (_) {
                return false;
              }
            },
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ArchivedRecord>> _loadAssets() async {
    try {
      final repository = SupabaseProjectAssetsRepository();
      final rows = await repository.fetchAssets();
      return [
        // وحدات العقارات المؤرشفة: تبقى داخل وحدات عقارها بحالة «مؤرشفة».
        for (final row in rows)
          if (row.status != TrashStore.status)
            for (final unit in _decodeUnits(row.unitsJson))
              if (unit['status'] == _unitArchived)
                ArchivedRecord(
                  source: assetsSource,
                  title: '${unit['name'] ?? 'وحدة'}',
                  subtitle: 'وحدة في «${row.title}»',
                  icon: Icons.meeting_room_outlined,
                  color: const Color(0xFFCE8422),
                  unarchive: () => _rewriteUnit(
                    repository,
                    row,
                    unit,
                    (u) => {...u, 'status': 'شاغرة'},
                  ),
                  moveToTrash: () => _rewriteUnit(
                    repository,
                    row,
                    unit,
                    (u) => {
                      ...u,
                      'status': _unitTrashed,
                      'extras': TrashStore.markDeleted(
                        _extrasOf(u),
                        _unitArchived,
                        'العقارات — ${row.title}',
                      ),
                    },
                  ),
                ),
        for (final row in rows)
          if (row.status == 'مؤرشف')
            ArchivedRecord(
              source: assetsSource,
              title: row.title,
              subtitle: [
                if (row.subType.isNotEmpty) row.subType,
                if ((row.locationOrType ?? '').isNotEmpty) row.locationOrType!,
              ].join(' · '),
              icon: Icons.business_center_outlined,
              color: const Color(0xFFCE8422),
              unarchive: () async {
                try {
                  await repository.updateAsset(
                    ProjectAssetRecord(
                      id: row.id,
                      title: row.title,
                      subType: row.subType,
                      category: row.category,
                      status: 'نشط',
                      locationOrType: row.locationOrType,
                      amountLabel: row.amountLabel,
                      followupNote: row.followupNote,
                      owner: row.owner,
                      tenant: row.tenant,
                      rentValue: row.rentValue,
                      endDate: row.endDate,
                      annualYield: row.annualYield,
                      occupancyRate: row.occupancyRate,
                      contractProgress: row.contractProgress,
                      paymentProgress: row.paymentProgress,
                      documentsProgress: row.documentsProgress,
                      needsAttention: row.needsAttention,
                      iconColor: row.iconColor,
                      coverUrl: row.coverUrl,
                      description: row.description,
                      annexes: row.annexes,
                      mapLink: row.mapLink,
                      quickAddEnabled: row.quickAddEnabled,
                      unitsJson: row.unitsJson,
                      employeesJson: row.employeesJson,
                      serialNumber: row.serialNumber,
                      isFrozen: false,
                      isPinned: row.isPinned,
                      isSublease: row.isSublease,
                      latitude: row.latitude,
                      longitude: row.longitude,
                      logsJson: row.logsJson,
                    ),
                  );
                  return true;
                } catch (_) {
                  return false;
                }
              },
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static const String _unitArchived = 'مؤرشفة';
  static const String _unitTrashed = 'محذوفة';

  static List<Map<String, dynamic>> _decodeUnits(String? json) {
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

  static Map<String, String> _extrasOf(Map<String, dynamic> unit) =>
      unit['extras'] is Map
      ? (unit['extras'] as Map).map((k, v) => MapEntry('$k', '${v ?? ''}'))
      : <String, String>{};

  static String _unitKeyOf(Map<String, dynamic> unit) {
    final pinned = (_extrasOf(unit)['__key'] ?? '').trim();
    if (pinned.isNotEmpty) return pinned;
    return '${unit['type'] ?? ''}|${unit['name'] ?? ''}|${unit['unitNumber'] ?? ''}';
  }

  /// يعيد كتابة وحدة واحدة داخل وحدات عقارها (من أحدث نسخة على الخادم).
  static Future<bool> _rewriteUnit(
    ProjectAssetsRepository repository,
    ProjectAssetRecord row,
    Map<String, dynamic> unit,
    Map<String, dynamic> Function(Map<String, dynamic> unit) change,
  ) async {
    try {
      var current = row;
      for (final fresh in await repository.fetchAssets()) {
        if (fresh.id == row.id) current = fresh;
      }
      final key = _unitKeyOf(unit);
      var found = false;
      final units = <Map<String, dynamic>>[];
      for (final u in _decodeUnits(current.unitsJson)) {
        if (!found && u['status'] == _unitArchived && _unitKeyOf(u) == key) {
          found = true;
          units.add(change(u));
        } else {
          units.add(u);
        }
      }
      if (!found) return false;
      final r = current;
      await repository.updateAsset(
        ProjectAssetRecord(
          id: r.id,
          title: r.title,
          subType: r.subType,
          category: r.category,
          status: r.status,
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
          unitsJson: jsonEncode(units),
          employeesJson: r.employeesJson,
          serialNumber: r.serialNumber,
          isFrozen: r.isFrozen,
          isPinned: r.isPinned,
          isSublease: r.isSublease,
          latitude: r.latitude,
          longitude: r.longitude,
          logsJson: r.logsJson,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
