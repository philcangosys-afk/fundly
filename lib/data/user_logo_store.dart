import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// شعار المستخدم (لوجو) — يُحفظ محليًا كالختم، ويظهر في منتصف أعلى
/// الصفحة الأولى من المستندات والتقارير.
class UserLogoStore {
  static const _storageKey = 'user_logo_image_v1';

  static Future<Uint8List?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, base64Encode(bytes));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
