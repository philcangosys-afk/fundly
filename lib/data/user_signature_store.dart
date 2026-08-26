import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

class UserSignatureStore {
  static const _storageKey = 'user_signature_strokes_v1';

  static Future<List<List<Offset>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (stroke) => (stroke as List<dynamic>)
                .map((point) {
                  final values = point as List<dynamic>;
                  return Offset(
                    (values[0] as num).toDouble(),
                    (values[1] as num).toDouble(),
                  );
                })
                .toList(growable: false),
          )
          .where((stroke) => stroke.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<List<Offset>> strokes) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = strokes
        .map(
          (stroke) => stroke
              .map((point) => [point.dx, point.dy])
              .toList(growable: false),
        )
        .toList(growable: false);
    await prefs.setString(_storageKey, jsonEncode(encoded));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
