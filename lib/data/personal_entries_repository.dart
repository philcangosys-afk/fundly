import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';

class PersonalEntryRecord {
  final String? id;
  final String category;
  final String entryType;
  final String title;
  final int amount;
  final String dueDate;
  final String status;
  final Map<String, String> details;
  final String? attachmentUrl;
  final DateTime? createdAt;

  const PersonalEntryRecord({
    this.id,
    required this.category,
    required this.entryType,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.details,
    this.attachmentUrl,
    this.createdAt,
  });

  factory PersonalEntryRecord.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'] as Map<String, dynamic>? ?? const {};
    return PersonalEntryRecord(
      id: json['id'] as String?,
      category: json['category'] as String? ?? '',
      entryType: json['entry_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.round() ?? 0,
      dueDate: _displayDate(json['due_date'] as String?),
      status: json['status'] as String? ?? 'نشطة',
      details: rawDetails.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
      attachmentUrl: json['attachment_url'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'category': category,
    'entry_type': entryType,
    'title': title,
    'amount': amount,
    'due_date': _databaseDate(dueDate),
    'status': status,
    'details': details,
    'attachment_url': attachmentUrl,
  };

  PersonalEntryRecord copyWith({
    String? title,
    int? amount,
    String? dueDate,
    String? status,
    Map<String, String>? details,
    String? attachmentUrl,
  }) {
    return PersonalEntryRecord(
      id: id,
      category: category,
      entryType: entryType,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      details: details ?? this.details,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      createdAt: createdAt,
    );
  }

  static String? _databaseDate(String value) {
    if (value.trim().isEmpty) return null;
    final parts = value.split('/');
    if (parts.length != 3) return value;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return value;
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  static String _displayDate(String? value) {
    if (value == null || value.isEmpty) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day}/${date.month}/${date.year}';
  }
}

abstract class PersonalEntriesRepository {
  Future<List<PersonalEntryRecord>> fetchAll();

  Future<PersonalEntryRecord> create(
    PersonalEntryRecord entry, {
    XFile? attachment,
  });

  Future<PersonalEntryRecord> update(
    PersonalEntryRecord entry, {
    XFile? attachment,
  });

  Future<void> delete(String entryId);
}

class SupabasePersonalEntriesRepository implements PersonalEntriesRepository {
  static const _table = 'personal_entries';
  static const _bucket = 'personal-entry-attachments';
  static const _requestTimeout = Duration(seconds: 15);

  final SupabaseClient _client;

  SupabasePersonalEntriesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// يدخل بحساب التطبيق الثابت عبر [AppSession]. كان يستدعي
  /// signInAnonymously() فيُنشئ مستخدمًا جديدًا عند كل إعادة تثبيت،
  /// فتصبح كل البيانات السابقة غير مرئية.
  Future<User> _authenticatedUser() => AppSession.ensureSignedIn();

  @override
  Future<List<PersonalEntryRecord>> fetchAll() async {
    await _authenticatedUser();
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .timeout(_requestTimeout);
    return rows.map(PersonalEntryRecord.fromJson).toList(growable: false);
  }

  @override
  Future<PersonalEntryRecord> create(
    PersonalEntryRecord entry, {
    XFile? attachment,
  }) async {
    final user = await _authenticatedUser();
    var record = entry;

    if (attachment != null) {
      final bytes = await attachment.readAsBytes();
      final extension = _fileExtension(attachment.name);
      final path =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}$extension';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: false),
          )
          .timeout(_requestTimeout);
      record = record.copyWith(attachmentUrl: path);
    }

    final row = await _client
        .from(_table)
        .insert(record.toJson(user.id))
        .select()
        .single()
        .timeout(_requestTimeout);
    return PersonalEntryRecord.fromJson(row);
  }

  @override
  Future<PersonalEntryRecord> update(
    PersonalEntryRecord entry, {
    XFile? attachment,
  }) async {
    final user = await _authenticatedUser();
    if (entry.id == null) {
      throw const PostgrestException(message: 'Missing personal entry id');
    }
    var record = entry;
    if (attachment != null) {
      final bytes = await attachment.readAsBytes();
      final extension = _fileExtension(attachment.name);
      final path =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}$extension';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: false),
          )
          .timeout(_requestTimeout);
      record = record.copyWith(attachmentUrl: path);
    }
    final row = await _client
        .from(_table)
        .update(record.toJson(user.id))
        .eq('id', record.id!)
        .select()
        .single()
        .timeout(_requestTimeout);
    return PersonalEntryRecord.fromJson(row);
  }

  @override
  Future<void> delete(String entryId) async {
    await _authenticatedUser();
    await _client
        .from(_table)
        .delete()
        .eq('id', entryId)
        .timeout(_requestTimeout);
  }

  String _fileExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
  }
}
