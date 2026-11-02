import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'fundly_notifications.dart';

class AppReminder {
  const AppReminder({
    required this.id,
    required this.title,
    required this.module,
    required this.expiryDate,
    required this.remindBeforeDays,
  });

  final String id;
  final String title;
  final String module;
  final DateTime expiryDate;
  final int remindBeforeDays;

  DateTime get reminderDate =>
      expiryDate.subtract(Duration(days: remindBeforeDays));

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'module': module,
    'expiryDate': expiryDate.toIso8601String(),
    'remindBeforeDays': remindBeforeDays,
  };

  factory AppReminder.fromJson(Map<String, dynamic> json) {
    return AppReminder(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      module: json['module']?.toString() ?? '',
      expiryDate:
          DateTime.tryParse(json['expiryDate']?.toString() ?? '') ??
          DateTime.now(),
      remindBeforeDays: (json['remindBeforeDays'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppRemindersStore {
  static const _storageKey = 'app_expiry_reminders_v1';

  static Future<List<AppReminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    return raw
        .map((item) {
          try {
            return AppReminder.fromJson(
              Map<String, dynamic>.from(jsonDecode(item) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<AppReminder>()
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> upsert(AppReminder reminder) async {
    final reminders = await load();
    final index = reminders.indexWhere((item) => item.id == reminder.id);
    final next = List<AppReminder>.from(reminders);
    if (index == -1) {
      next.add(reminder);
    } else {
      next[index] = reminder;
    }
    await _save(next);
  }

  static Future<void> remove(String id) async {
    final reminders = await load();
    await _save(
      reminders.where((item) => item.id != id).toList(growable: false),
    );
  }

  static Future<void> _save(List<AppReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      reminders
          .map((item) => jsonEncode(item.toJson()))
          .toList(growable: false),
    );

    FundlyNotifications.scheduleSoon();
  }

  static DateTime? parseDisplayDate(String value) {
    final parts = value.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static int reminderDaysFromLabel(String value) {
    if (value == 'قبل يوم') return 1;
    if (value == 'قبل 3 أيام') return 3;
    if (value == 'قبل أسبوع') return 7;
    if (value == 'قبل أسبوعين') return 14;
    if (value == 'قبل شهر') return 30;
    return 0;
  }
}
