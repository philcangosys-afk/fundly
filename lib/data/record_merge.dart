import 'dart:convert';

/// دمج التعديلات قبل الحفظ في سجل يعدّله أكثر من شخص (العهدة بين المالك
/// والمسند إليه، والرحلة بين أعضائها).
///
/// كل شاشة تحفظ السجل كاملًا من نسختها التي حمّلتها. لو حفظ طرف بعد أن عدّل
/// الطرف الآخر، لمُحي تعديل الآخر. هنا دمج ثلاثي: «الأصل» الذي حمّله هذا
/// الجهاز، و«نسختي» بعد التعديل، و«الأحدث» في الخادم الآن — فيُطبَّق ما غيّرتُه
/// أنا فقط فوق الأحدث، ويبقى ما غيّره غيري.
class RecordMerge {
  RecordMerge._();

  /// قيمة عمود واحد: إن لم أغيّره تبقى قيمة الخادم.
  static T pick<T>(T base, T mine, T theirs) => mine == base ? theirs : mine;

  /// تفاصيل السجل (نصوص، وبعضها قوائم أو خرائط JSON).
  static Map<String, String> details(
    Map<String, String> base,
    Map<String, String> mine,
    Map<String, String> theirs,
  ) {
    final out = Map<String, String>.of(theirs);
    for (final key in {...base.keys, ...mine.keys}) {
      final b = base[key];
      final m = mine[key];
      final t = theirs[key];
      if (m == b) continue; // لم أغيّره: تبقى قيمة الخادم.
      if (t == b) {
        _put(out, key, m); // لم يغيّره غيري.
        continue;
      }
      // كلانا غيّره: إن كان قائمة أو خريطة JSON يُدمج عنصرًا عنصرًا.
      _put(out, key, _mergeJson(b, m, t) ?? m);
    }
    return out;
  }

  static void _put(Map<String, String> out, String key, String? value) {
    if (value == null) {
      out.remove(key);
    } else {
      out[key] = value;
    }
  }

  static Object? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final text = raw.trim();
    if (!text.startsWith('[') && !text.startsWith('{')) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String? _mergeJson(String? b, String? m, String? t) {
    final mine = _decode(m);
    final theirs = _decode(t);
    if (mine == null || theirs == null) return null;
    final base = _decode(b);
    if (mine is List && theirs is List) {
      return jsonEncode(_mergeLists(base is List ? base : const [], mine, theirs));
    }
    if (mine is Map && theirs is Map) {
      return jsonEncode(_mergeMaps(base is Map ? base : const {}, mine, theirs));
    }
    return null;
  }

  /// هوية العنصر: معرّفه إن وُجد، وإلا محتواه كاملًا.
  static String _idOf(Object? element) {
    if (element is Map) {
      final id = element['id'];
      if (id != null && '$id'.isNotEmpty) return 'id:$id';
    }
    return jsonEncode(element);
  }

  static List<Object?> _mergeLists(
    List<Object?> base,
    List<Object?> mine,
    List<Object?> theirs,
  ) {
    final baseById = {for (final e in base) _idOf(e): jsonEncode(e)};
    final mineById = {for (final e in mine) _idOf(e): e};
    final result = <Object?>[];
    final seen = <String>{};
    for (final element in theirs) {
      final id = _idOf(element);
      seen.add(id);
      if (baseById.containsKey(id) && !mineById.containsKey(id)) {
        continue; // حذفتُه أنا.
      }
      final mineVersion = mineById[id];
      if (mineVersion != null &&
          baseById.containsKey(id) &&
          jsonEncode(mineVersion) != baseById[id]) {
        result.add(mineVersion); // عدّلتُه أنا.
      } else {
        result.add(element);
      }
    }
    for (final element in mine) {
      final id = _idOf(element);
      if (!baseById.containsKey(id) && !seen.contains(id)) {
        result.add(element); // أضفتُه أنا.
      }
    }
    return result;
  }

  static Map<String, Object?> _mergeMaps(
    Map<Object?, Object?> base,
    Map<Object?, Object?> mine,
    Map<Object?, Object?> theirs,
  ) {
    final out = <String, Object?>{
      for (final e in theirs.entries) '${e.key}': e.value,
    };
    final keys = {...base.keys.map((k) => '$k'), ...mine.keys.map((k) => '$k')};
    for (final key in keys) {
      final b = jsonEncode(base[key]);
      final m = jsonEncode(mine[key]);
      if (m == b) continue;
      if (!mine.containsKey(key)) {
        out.remove(key);
      } else {
        out[key] = mine[key];
      }
    }
    return out;
  }
}
