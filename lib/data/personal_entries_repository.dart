import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';
import 'record_merge.dart';
import 'fundly_notifications.dart';

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
      createdAt: DateTime.tryParse(
        json['created_at'] as String? ?? '',
      )?.toLocal(),
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
  /// آخر نسخة استلمها هذا الجهاز لكل سجل — «الأصل» في دمج التعديلات قبل
  /// الحفظ ([RecordMerge])، حتى لا يمحو حفظٌ تعديلَ طرف آخر على السجل نفسه.
  static final Map<String, PersonalEntryRecord> _seen = {};

  static void _remember(PersonalEntryRecord record) {
    final id = record.id;
    if (id != null) _seen[id] = record;
  }

  /// رفع ملف وحده (فاتورة صرف مثلًا) وإعادة مساره — دون أن يصير مرفق
  /// السجل نفسه.
  Future<String> uploadAttachment(XFile file) async {
    final user = await _authenticatedUser();
    final bytes = await file.readAsBytes();
    final path =
        '${user.id}/${DateTime.now().microsecondsSinceEpoch}'
        '${_fileExtension(file.name)}';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: false),
        )
        .timeout(_requestTimeout);
    return path;
  }

  /// أحدث نسخة من سجل واحد في الخادم.
  Future<PersonalEntryRecord?> fetchOne(String id) async {
    await _authenticatedUser();
    final row = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle()
        .timeout(_requestTimeout);
    if (row == null) return null;
    final record = PersonalEntryRecord.fromJson(row);
    _remember(record);
    return record;
  }

  /// ما غيّرتُه عن آخر نسخة استلمتها، مطبَّقًا على أحدث نسخة في الخادم.
  Future<PersonalEntryRecord> _mergeWithLatest(PersonalEntryRecord entry) async {
    final id = entry.id;
    final base = id == null ? null : _seen[id];
    if (id == null || base == null) return entry;
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle()
          .timeout(_requestTimeout);
      if (row == null) return entry;
      final latest = PersonalEntryRecord.fromJson(row);
      return PersonalEntryRecord(
        id: id,
        category: RecordMerge.pick(base.category, entry.category, latest.category),
        entryType: RecordMerge.pick(
          base.entryType,
          entry.entryType,
          latest.entryType,
        ),
        title: RecordMerge.pick(base.title, entry.title, latest.title),
        amount: RecordMerge.pick(base.amount, entry.amount, latest.amount),
        dueDate: RecordMerge.pick(base.dueDate, entry.dueDate, latest.dueDate),
        status: RecordMerge.pick(base.status, entry.status, latest.status),
        details: RecordMerge.details(base.details, entry.details, latest.details),
        attachmentUrl: RecordMerge.pick(
          base.attachmentUrl,
          entry.attachmentUrl,
          latest.attachmentUrl,
        ),
        createdAt: latest.createdAt,
      );
    } catch (_) {
      // بلا اتصال بالقراءة: يُحفظ كما هو.
      return entry;
    }
  }

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
    final records = rows.map(PersonalEntryRecord.fromJson).toList(growable: false);
    records.forEach(_remember);
    return records;
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
    final saved = PersonalEntryRecord.fromJson(row);
    _remember(saved);
    FundlyNotifications.scheduleSoon();
    return saved;
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
    // ما غيّرتُه فقط فوق أحدث نسخة في الخادم.
    var record = await _mergeWithLatest(entry);
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
    final saved = PersonalEntryRecord.fromJson(row);
    _remember(saved);
    FundlyNotifications.scheduleSoon();
    return saved;
  }

  @override
  Future<void> delete(String entryId) async {
    await _authenticatedUser();
    await _client
        .from(_table)
        .delete()
        .eq('id', entryId)
        .timeout(_requestTimeout);

    FundlyNotifications.scheduleSoon();
  }

  String _fileExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
  }
}
