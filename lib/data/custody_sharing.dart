import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هوية المستخدم داخل التطبيق: رقم تعريفي ثابت يُولَّد مرة واحدة على
/// الجهاز ويُستعمل لربط المعاملات المشتركة بين شخصين (إسناد عهدة مثلًا).
///
/// التطبيق يعمل على حساب واحد مشترك في الخادم، فكل النسخ ترى نفس السجلات؛
/// الرقم التعريفي هو ما يميّز «من صاحب العهدة» و«من المسند إليه» داخل
/// السجل نفسه، بلا أي تعديل على مخطط قاعدة البيانات.
class AppIdentity {
  AppIdentity._();

  static const _kUserId = 'settings_user_id';

  static String _id = '';

  /// يزيد كلما تغيّر الرقم (يصل من الخادم بعد فتح الشاشات): الشاشات التي
  /// تعرض طلبات العهدة تعيد البناء فلا يفوتها طلب وصل.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// الرقم التعريفي الحالي — فارغ قبل استدعاء [load].
  static String get id => _id;

  /// تحميل الرقم التعريفي المحفوظ على الجهاز. الرقم نفسه يولّده الخادم
  /// لكل حساب ويُقرأ بعد الدخول ([setFromServer])، فلا يتغيّر بحذف
  /// التطبيق أو تبديل الجوال.
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    _id = (prefs.getString(_kUserId) ?? '').trim();
    return _id;
  }

  /// الرقم كما في الخادم لحساب المستخدم الحالي.
  static Future<void> setFromServer(String value) async {
    final normalized = normalize(value);
    if (!isValid(normalized)) return;
    final changed = normalized != _id;
    _id = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, normalized);
    if (changed) revision.value++;
  }

  /// عند الخروج: لا رقم حتى يدخل الحساب التالي.
  static Future<void> clear() async {
    _id = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserId);
  }

  /// رقم بصيغة FND-XXXX-XXXX سهل القراءة والنسخ والإملاء.
  static String _generate() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String block() => List.generate(
      4,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return 'FND-${block()}-${block()}';
  }

  /// تعيين رقم تعريفي يكتبه المستخدم بنفسه — يُستعمل في التجربة لتمييز
  /// جهازين، أو لاستعادة رقم قديم بعد إعادة التثبيت. يُرفض ما لا يوافق
  /// الصيغة المعتمدة.
  static Future<bool> setId(String value) async {
    final normalized = normalize(value);
    if (!isValid(normalized)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, normalized);
    _id = normalized;
    return true;
  }

  /// توليد رقم جديد يستبدل الحالي على هذا الجهاز.
  static Future<String> regenerate() async {
    final prefs = await SharedPreferences.getInstance();
    _id = _generate();
    await prefs.setString(_kUserId, _id);
    return _id;
  }

  /// التحقق من صيغة رقم تعريفي أدخله المستخدم.
  static bool isValid(String value) =>
      RegExp(r'^FND-[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(value.trim());

  /// تنظيف ما يكتبه المستخدم (مسافات وحروف صغيرة).
  static String normalize(String value) =>
      value.trim().toUpperCase().replaceAll(' ', '');
}

/// حالة إسناد العهدة المالية لشخص آخر.
enum CustodyAssignmentState { none, pending, accepted, rejected }

/// دور المستخدم الحالي تجاه عهدة مالية بعينها.
enum CustodyRole {
  /// عهدة خاصة به ولم تُسند لأحد — يتصرّف فيها كاملًا.
  soleOwner,

  /// هو مالك العهدة وقد أسندها لغيره — قراءة فقط للصرفيات، ويملك زيادة المبلغ.
  owner,

  /// هو المسند إليه — يصرف من العهدة ويرفع فواتيرها.
  holder,

  /// لا علاقة له بها (عهدة بين شخصين آخرين على الحساب المشترك).
  observer,
}

/// قراءة وكتابة بيانات إسناد العهدة داخل خريطة `details` نفسها.
class CustodyAssignment {
  const CustodyAssignment({
    required this.ownerId,
    required this.ownerName,
    required this.holderId,
    required this.holderName,
    required this.state,
    required this.assignedAt,
    required this.note,
  });

  static const kOwnerId = 'عهدة_مالك_المعرّف';
  static const kOwnerName = 'عهدة_مالك_الاسم';
  static const kHolderId = 'عهدة_مسندة_إلى';
  static const kHolderName = 'عهدة_المسند_إليه_الاسم';
  static const kState = 'عهدة_حالة_الإسناد';
  static const kAssignedAt = 'عهدة_تاريخ_الإسناد';
  static const kNote = 'عهدة_ملاحظة_الإسناد';

  /// تاريخ ووقت رد المسند إليه (القبول أو الرفض).
  static const kRespondedAt = 'عهدة_تاريخ_الرد';

  /// كل مفاتيح الإسناد — تُستثنى من حقول التحرير اليدوي.
  static const keys = <String>[
    kOwnerId,
    kOwnerName,
    kHolderId,
    kHolderName,
    kState,
    kAssignedAt,
    kNote,
    kRespondedAt,
  ];

  static const _statePending = 'بانتظار القبول';
  static const _stateAccepted = 'مقبولة';
  static const _stateRejected = 'مرفوضة';

  final String ownerId;
  final String ownerName;
  final String holderId;
  final String holderName;
  final CustodyAssignmentState state;
  final String assignedAt;
  final String note;

  bool get isAssigned => state != CustodyAssignmentState.none;
  bool get isPending => state == CustodyAssignmentState.pending;
  bool get isAccepted => state == CustodyAssignmentState.accepted;
  bool get isRejected => state == CustodyAssignmentState.rejected;

  String get stateLabel => switch (state) {
    CustodyAssignmentState.pending => _statePending,
    CustodyAssignmentState.accepted => _stateAccepted,
    CustodyAssignmentState.rejected => _stateRejected,
    CustodyAssignmentState.none => 'غير مسندة',
  };

  static CustodyAssignment decode(Map<String, String> details) {
    final rawState = (details[kState] ?? '').trim();
    final state = switch (rawState) {
      _statePending => CustodyAssignmentState.pending,
      _stateAccepted => CustodyAssignmentState.accepted,
      _stateRejected => CustodyAssignmentState.rejected,
      _ => CustodyAssignmentState.none,
    };
    return CustodyAssignment(
      ownerId: (details[kOwnerId] ?? '').trim(),
      ownerName: (details[kOwnerName] ?? '').trim(),
      holderId: (details[kHolderId] ?? '').trim(),
      holderName: (details[kHolderName] ?? '').trim(),
      state: state,
      assignedAt: (details[kAssignedAt] ?? '').trim(),
      note: (details[kNote] ?? '').trim(),
    );
  }

  /// دمج حالة الإسناد في خريطة التفاصيل (تُعاد خريطة جديدة).
  Map<String, String> applyTo(Map<String, String> details) {
    final out = Map<String, String>.of(details);
    void put(String key, String value) {
      if (value.trim().isEmpty) {
        out.remove(key);
      } else {
        out[key] = value.trim();
      }
    }

    put(kOwnerId, ownerId);
    put(kOwnerName, ownerName);
    put(kHolderId, holderId);
    put(kHolderName, holderName);
    put(kState, state == CustodyAssignmentState.none ? '' : stateLabel);
    put(kAssignedAt, assignedAt);
    put(kNote, note);
    return out;
  }

  CustodyAssignment copyWith({
    String? ownerId,
    String? ownerName,
    String? holderId,
    String? holderName,
    CustodyAssignmentState? state,
    String? assignedAt,
    String? note,
  }) => CustodyAssignment(
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    holderId: holderId ?? this.holderId,
    holderName: holderName ?? this.holderName,
    state: state ?? this.state,
    assignedAt: assignedAt ?? this.assignedAt,
    note: note ?? this.note,
  );

  /// عهدة بلا إسناد.
  static const empty = CustodyAssignment(
    ownerId: '',
    ownerName: '',
    holderId: '',
    holderName: '',
    state: CustodyAssignmentState.none,
    assignedAt: '',
    note: '',
  );

  /// دور المستخدم صاحب [myId] تجاه هذه العهدة.
  CustodyRole roleFor(String myId) {
    if (!isAssigned) {
      // بلا إسناد قائم (أو أُلغي): صاحبها المعروف وحده يتصرف فيها، ومن
      // كان مسندًا إليه سابقًا يطّلع فقط.
      if (ownerId.isNotEmpty && ownerId != myId) return CustodyRole.observer;
      return CustodyRole.soleOwner;
    }
    if (ownerId.isNotEmpty && ownerId == myId) return CustodyRole.owner;
    if (holderId.isNotEmpty && holderId == myId) return CustodyRole.holder;
    // عهدة قديمة أُنشئت قبل وجود الأرقام التعريفية: صاحبها هو من يراها.
    if (ownerId.isEmpty && holderId != myId) return CustodyRole.soleOwner;
    return CustodyRole.observer;
  }

  /// من يملك زيادة المبلغ أو تعديل بيانات العهدة.
  bool canManageAmount(String myId) {
    final role = roleFor(myId);
    return role == CustodyRole.soleOwner || role == CustodyRole.owner;
  }

  /// من يملك الصرف من العهدة ورفع فواتيرها.
  bool canSpend(String myId) {
    final role = roleFor(myId);
    if (role == CustodyRole.soleOwner) return true;
    return role == CustodyRole.holder && isAccepted;
  }
}

/// سجل زيادات المبلغ على العهدة — يُحفظ داخل `details` بلا جدول جديد.
class CustodyTopUps {
  CustodyTopUps._();

  static const key = 'سجل زيادات العهدة';

  static List<Map<String, String>> parse(Map<String, String> details) {
    final raw = details[key];
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) => entry.map(
              (k, value) => MapEntry(k.toString(), value?.toString() ?? ''),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<Map<String, String>> rows) => jsonEncode(rows);

  static int total(Map<String, String> details) => parse(details).fold<int>(
    0,
    (sum, row) => sum + parseAmountInt(row['المبلغ'] ?? ''),
  );
}

/// مبلغ مكتوب بأي صيغة: أرقام عربية، كسور (50.5)، فواصل آلاف (1,500) —
/// يُقرَّب لأقرب عدد صحيح بدل أن يُحسب صفرًا.
int parseAmountInt(String raw) {
  var text = raw.trim().replaceAll(RegExp(r'[,،٬\s]'), '').replaceAll('٫', '.');
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return (double.tryParse(text) ?? 0).round();
}
