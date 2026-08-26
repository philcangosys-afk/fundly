import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HomePinnedShortcut {
  final String id;
  final String title;
  final String moduleId;
  final String subtitle;

  const HomePinnedShortcut({
    required this.id,
    required this.title,
    this.moduleId = '',
    this.subtitle = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'moduleId': moduleId,
    'subtitle': subtitle,
  };

  factory HomePinnedShortcut.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    return HomePinnedShortcut(
      id: id,
      title: json['title']?.toString() ?? '',
      moduleId: json['moduleId']?.toString().isNotEmpty == true
          ? json['moduleId'].toString()
          : _legacyModuleId(id),
      subtitle: json['subtitle']?.toString() ?? '',
    );
  }

  static String _legacyModuleId(String id) {
    if (const {'personal', 'shared', 'people', 'assets'}.contains(id)) {
      return id;
    }
    return id.split(':').first;
  }
}

class HomePinnedShortcutsStore {
  static const _key = 'home_pinned_shortcuts_v1';

  static Future<List<HomePinnedShortcut>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((item) => HomePinnedShortcut.fromJson(jsonDecode(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> save(List<HomePinnedShortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      shortcuts
          .map((item) => jsonEncode(item.toJson()))
          .toList(growable: false),
    );
  }
}
