import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// تخزين صورة الختم الرسمي محليًا على الجهاز (base64 داخل التفضيلات)،
/// بنفس أسلوب تخزين التوقيع المرسوم — فيبقى الختم محفوظًا بعد إغلاق
/// التطبيق ويُستخدم في معاينة المستندات مع التوقيع.
class UserStampStore {
  static const _storageKey = 'user_stamp_image_v1';

  static Future<Uint8List?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      // بيانات تالفة: تُعامَل كأنه لا يوجد ختم بدل إسقاط الشاشة.
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
