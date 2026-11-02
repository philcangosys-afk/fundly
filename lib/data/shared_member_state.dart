import 'dart:convert';

import 'custody_sharing.dart';
import 'shared_entries_repository.dart';

/// الأرشفة والحذف في الالتزام المشترك لكل عضو وحده.
///
/// السجل واحد في الخادم ويراه كل الأعضاء، فلا تُغيَّر حالته عند أرشفة
/// أحدهم أو حذفه له؛ بل يُضاف رقمه التعريفي إلى «مؤرشف عند» أو
/// «محذوف عند» داخل التفاصيل، فيختفي عنده وحده ويبقى عند الباقين، ويصلهم
/// إشعار (مشغّل fundly_shared_hide_notices) ليقرروا بأنفسهم.
/// يُحذف السجل من الخادم فعلًا حين يحذفه آخر عضو.
class SharedMemberState {
  SharedMemberState._();

  static const archivedKey = 'مؤرشف عند';
  static const removedKey = 'محذوف عند';

  /// «السجل التاريخي»: ما حُذف ولم تتم تسويته لا يُمسح — يختفي من القائمة
  /// ويبقى هنا حفظًا لحقوق الأعضاء ومتابعته لاحقًا.
  static const historyKey = 'سجل تاريخي عند';
  static const _creatorKey = 'معرف المنشئ';
  static const _acceptKey = 'قبول الأعضاء';
  static final _idPattern = RegExp(r'FND-[A-Z2-9]{4}-[A-Z2-9]{4}');

  /// الأرقام المسجّلة في قائمة [key].
  static Set<String> ids(Map<String, String> details, String key) {
    try {
      final decoded = jsonDecode(details[key] ?? '[]');
      if (decoded is List) {
        return {
          for (final value in decoded)
            if ('$value'.trim().isNotEmpty) '$value'.trim(),
        };
      }
    } catch (_) {}
    return <String>{};
  }

  /// هل رقمي في قائمة [key]؟
  static bool hasMine(Map<String, String> details, String key) {
    final me = AppIdentity.id;
    return me.isNotEmpty && ids(details, key).contains(me);
  }

  static Map<String, String> withMine(
    Map<String, String> details,
    String key, {
    required bool add,
  }) {
    final me = AppIdentity.id;
    final set = ids(details, key);
    if (add) {
      set.add(me);
    } else {
      set.remove(me);
    }
    return Map<String, String>.of(details)
      ..[key] = jsonEncode(set.toList()..sort());
  }

  /// أصحاب الأرقام في الالتزام (المنشئ والأعضاء)، بلا من رفض الدعوة.
  static Set<String> participants(Map<String, String> details) {
    final rejected = <String>{};
    try {
      final decoded = jsonDecode(details[_acceptKey] ?? '{}');
      if (decoded is Map) {
        decoded.forEach((key, value) {
          // رفض الدعوة، أو ألغاها المنشئ: ليس مشاركًا.
          if (value is Map &&
              ('${value['state']}' == 'rejected' ||
                  '${value['state']}' == 'cancelled')) {
            rejected.add('$key');
          }
        });
      }
    } catch (_) {}
    final out = <String>{};
    for (final value in details.values) {
      for (final match in _idPattern.allMatches(value)) {
        out.add(match.group(0)!);
      }
    }
    return out..removeAll(rejected);
  }

  // ---------------- دعوات الأعضاء: حالة كل مدعو ----------------

  /// متى أُرسلت دعوة كل رقم: {FND-...: ISO}.
  static const inviteAtKey = 'وقت دعوة الأعضاء';

  /// صلاحية الدعوة: بعدها «تأخر بالرد» ولا تُقبل، ويبقى اسمه.
  static const inviteValidity = Duration(hours: 24);

  static final _idInName = RegExp(r'\((FND-[A-Z2-9]{4}-[A-Z2-9]{4})\)');

  /// ردود الأعضاء: {FND-...: {name, state, at}}.
  static Map<String, Map<String, String>> acceptances(
    Map<String, String> details,
  ) {
    try {
      final decoded = jsonDecode(details[_acceptKey] ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            '${entry.key}': (entry.value as Map).map(
              (k, v) => MapEntry('$k', '$v'),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  /// أوقات الدعوات المسجّلة.
  static Map<String, String> inviteTimes(Map<String, String> details) {
    try {
      final decoded = jsonDecode(details[inviteAtKey] ?? '{}');
      if (decoded is! Map) return {};
      return {for (final e in decoded.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  /// متى أُرسلت دعوة [id] — ولدعوات ما قبل التسجيل تاريخ إنشاء السجل.
  static DateTime? inviteSentAt(
    Map<String, String> details,
    String id, {
    DateTime? fallback,
  }) {
    final raw = inviteTimes(details)[id];
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return (parsed ?? fallback)?.toLocal();
  }

  /// حالة دعوة [id]: accepted / rejected / cancelled / expired / pending.
  static String inviteState(
    Map<String, String> details,
    String id, {
    DateTime? createdAt,
  }) {
    final answer = acceptances(details)[id];
    final state = answer?['state'] ?? '';
    if (state == 'accepted' || state == 'rejected' || state == 'cancelled') {
      return state;
    }
    final sent = inviteSentAt(details, id, fallback: createdAt);
    if (sent != null && DateTime.now().difference(sent) >= inviteValidity) {
      return 'expired';
    }
    return 'pending';
  }

  /// الوقت الباقي لدعوة لم يُرد عليها (null إن لا وقت مسجّل).
  static Duration? inviteRemaining(
    Map<String, String> details,
    String id, {
    DateTime? createdAt,
  }) {
    final sent = inviteSentAt(details, id, fallback: createdAt);
    if (sent == null) return null;
    final left = inviteValidity - DateTime.now().difference(sent);
    return left.isNegative ? Duration.zero : left;
  }

  /// كل رقم جديد في «الأعضاء» (غير المنشئ) يُسجَّل وقت دعوته الآن.
  static Map<String, String> stampInvites(Map<String, String> details) {
    final raw = details['الأعضاء'] ?? '';
    if (raw.isEmpty) return details;
    final creator = (details[_creatorKey] ?? '').trim();
    final ids = {
      for (final m in _idInName.allMatches(raw))
        if (m.group(1) != creator) m.group(1)!,
    };
    if (ids.isEmpty) return details;
    final times = inviteTimes(details);
    final now = DateTime.now().toUtc().toIso8601String();
    var changed = false;
    for (final id in ids) {
      if (!times.containsKey(id)) {
        times[id] = now;
        changed = true;
      }
    }
    if (!changed) return details;
    return Map<String, String>.of(details)..[inviteAtKey] = jsonEncode(times);
  }

  /// فيه أعضاء آخرون بأرقامهم؟ إن لم يكن، فالحذف والأرشفة كما كانا.
  static bool sharedWithOthers(Map<String, String> details) {
    final me = AppIdentity.id;
    if (me.isEmpty) return false;
    return participants(details).any((id) => id != me);
  }

  /// حذفه كل الأعضاء والمنشئ؟ حينها يُحذف من الخادم نهائيًا.
  static bool removedByAll(Map<String, String> details) {
    final creator = (details[_creatorKey] ?? '').trim();
    if (creator.isEmpty) return false;
    // بلا أعضاء آخرين: لا يُحذف تلقائيًا — يبقى في سلة المهملات حتى
    // يُستعاد أو يُحذف نهائيًا منها.
    if (participants(details).every((id) => id == creator)) return false;
    final removed = ids(details, removedKey);
    final all = participants(details)..add(creator);
    return all.every(removed.contains);
  }

  /// يضيف رقمي إلى [key] (أو يزيله) على أحدث نسخة في الخادم. يعيد null
  /// إن لم يعد السجل موجودًا.
  static Future<SharedEntryRecord?> markMine(
    SharedEntriesRepository repository,
    SharedEntryRecord current,
    String key, {
    required bool add,
  }) async {
    var base = current;
    if (repository is SupabaseSharedEntriesRepository && current.id != null) {
      final latest = await repository.fetchOne(current.id!);
      if (latest == null) return null;
      base = latest;
    }
    final saved = await repository.update(
      base.copyWith(details: withMine(base.details, key, add: add)),
      planExempt: true,
    );
    if (add && key == removedKey) await purgeIfRemovedByAll(repository, saved);
    return saved;
  }

  /// آخر عضو حذفه: يُحذف من الخادم (ينجح للمالك فقط حسب الصلاحيات، وإلا
  /// يحذفه المالك عند فتحه القائمة).
  static Future<void> purgeIfRemovedByAll(
    SharedEntriesRepository repository,
    SharedEntryRecord record,
  ) async {
    final id = record.id;
    if (id == null || !removedByAll(record.details)) return;
    try {
      await repository.delete(id);
    } catch (_) {}
  }
}
