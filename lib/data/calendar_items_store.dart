import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'fundly_notifications.dart';

class CalendarRecord {
  const CalendarRecord({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    required this.time,
    required this.priority,
    required this.status,
    required this.description,
    required this.notes,
    required this.remindBeforeDays,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final String title;
  final String type;
  final DateTime date;
  final String time;
  final String priority;
  final String status;
  final String description;
  final String notes;
  final int remindBeforeDays;
  final DateTime createdAt;
  final DateTime? completedAt;

  CalendarRecord copyWith({
    String? title,
    String? type,
    DateTime? date,
    String? time,
    String? priority,
    String? status,
    String? description,
    String? notes,
    int? remindBeforeDays,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return CalendarRecord(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      date: date ?? this.date,
      time: time ?? this.time,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      remindBeforeDays: remindBeforeDays ?? this.remindBeforeDays,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'date': date.toIso8601String(),
    'time': time,
    'priority': priority,
    'status': status,
    'description': description,
    'notes': notes,
    'remindBeforeDays': remindBeforeDays,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory CalendarRecord.fromJson(Map<String, dynamic> json) {
    return CalendarRecord(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? 'مهمة',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      time: json['time']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'متوسطة',
      status: json['status']?.toString() ?? 'قادمة',
      description: json['description']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      remindBeforeDays: (json['remindBeforeDays'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
    );
  }
}

class CalendarItemsStore {
  static const _storageKey = 'smart_calendar_records_v1';

  static Future<List<CalendarRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    final records = raw
        .map((item) {
          try {
            return CalendarRecord.fromJson(
              Map<String, dynamic>.from(jsonDecode(item) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<CalendarRecord>()
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList(growable: false);
    records.sort((a, b) => a.date.compareTo(b.date));
    return records;
  }

  static Future<void> upsert(CalendarRecord record) async {
    final records = await load();
    final next = List<CalendarRecord>.from(records);
    final index = next.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      next.add(record);
    } else {
      next[index] = record;
    }
    await _save(next);
  }

  static Future<void> remove(String id) async {
    final records = await load();
    await _save(records.where((item) => item.id != id).toList(growable: false));
  }

  static Future<void> _save(List<CalendarRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      records.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );

    FundlyNotifications.scheduleSoon();
  }
}
