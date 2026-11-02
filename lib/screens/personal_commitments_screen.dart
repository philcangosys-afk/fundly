import 'dart:convert';

import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_settings.dart';
import '../widgets/shared/fnd_lookup.dart';
import '../widgets/shared/follow_filters.dart';
import '../data/app_reminders_store.dart';
import '../data/personal_entries_repository.dart';
import '../data/document_store.dart';
import '../data/reminder_lead.dart';
import '../data/custody_sharing.dart';
import '../data/people_directory_store.dart';
import 'smart_calendar_screen.dart';
import 'trash_screen.dart';
import 'global_summary_screen.dart';
import '../widgets/shared/archive_sheet.dart';
import '../data/page_customization_store.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/maps_link_paste.dart';
import '../widgets/shared/app_filter_sheet.dart';
import '../widgets/shared/category_picker_sheet.dart';
import '../widgets/shared/followup_center_sheet.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';

const _addedAttachmentTypeKey = 'نوع المرفق الإضافي';
const _addedAttachmentNameKey = 'اسم المرفق الإضافي';
const _addedAttachmentExpiryKey = 'تاريخ انتهاء المرفق';

/// مستندات إضافية بجانب المرفق الأول: [{id, path, name, type, expiry}] —
/// كانت إضافة مستند ثانٍ تستبدل الأول.
const _extraAttachmentsKey = 'مرفقات إضافية';

/// أدوية الوصفة الواحدة (زيارة طبيب واحدة): معرّف الدواء الأول فيها.
const _prescriptionGroupKey = 'مجموعة الوصفة';

/// حقل نهاية ← حقل بدايته: لا تُختار نهاية قبل البداية.
const Map<String, String> _dateRangeStart = {
  'إلى تاريخ': 'من تاريخ',
  'تاريخ نهاية التفويض': 'تاريخ بداية التفويض',
};

/// وقتان لا يكونان متساويين (وقت الدواء الإضافي غير وقت الجرعة).
const Map<String, String> _distinctTimes = {'وقت إضافي': 'وقت الجرعة'};

/// ما يتغيّر بين أدوية الوصفة الواحدة: الاسم والجرعة وكل ما يخص القياس؛
/// والباقي (لمن، الفترة، الأوقات، التذكير، الطبيب...) يُنسخ كما هو.
const _perMedicineFields = {
  'اسم الدواء',
  'الاسم العلمي',
  'الجرعة',
  'وحدة الجرعة',
  'التركيز',
  'شكل الدواء',
};

List<Map<String, String>> _parseExtraAttachments(Map<String, String> details) {
  final raw = details[_extraAttachmentsKey];
  if (raw == null || raw.trim().isEmpty) return <Map<String, String>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, String>>[];
    return [
      for (final row in decoded.whereType<Map>())
        row.map((k, v) => MapEntry('$k', '${v ?? ''}')),
    ];
  } catch (_) {
    return <Map<String, String>>[];
  }
}

// قائمة أسماء الأشخاص المحفوظة مسبقًا، مشتركة بين أكثر من مكان في هذه
// الشاشة (اسم المفوَّض عند إضافة تفويض، واسم المستلم عند إضافة عهدة مالية)
// حتى لا يُضطر المستخدم لكتابة نفس الاسم يدويًا في كل مرة. دوال على مستوى
// الملف (لا داخل صنف State) لأنها تُستخدم من أكثر من صنف State في هذا الملف.
const String _savedPeopleNamesPrefKey = 'personal_saved_people_names';

Future<List<String>> _loadSavedPeopleNames() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_savedPeopleNamesPrefKey) ?? const [];
}

Future<void> _savePersonName(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getStringList(_savedPeopleNamesPrefKey) ?? const [];
  if (existing.contains(trimmed)) return;
  final next = [trimmed, ...existing].take(30).toList(growable: false);
  await prefs.setStringList(_savedPeopleNamesPrefKey, next);
}

// ربط شخص بالعهدة المالية: كل عملية صرف من العهدة تُحفظ كعنصر ضمن قائمة
// مُرمَّزة بصيغة JSON داخل details['سجل صرفيات العهدة']، بدل إضافة جدول أو
// نوع سجلّات جديد في قاعدة البيانات — أبسط ويعمل مع البنية الحالية القائمة
// على Map<String, String> للتفاصيل.
const String _custodyTransactionsDetailKey = 'سجل صرفيات العهدة';

List<Map<String, String>> _parseCustodyTransactions(
  Map<String, String> details,
) {
  final raw = details[_custodyTransactionsDetailKey];
  if (raw == null || raw.trim().isEmpty) return <Map<String, String>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, String>>[];
    return decoded
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        )
        .toList();
  } catch (_) {
    return <Map<String, String>>[];
  }
}

String _encodeCustodyTransactions(List<Map<String, String>> transactions) =>
    jsonEncode(transactions);

/// ما صُرف من عهدة مالية — لمركز متابعة الأفراد والجهات.
int personalCustodySpent(Map<String, String> details) =>
    _custodyTotalSpent(details);

int _custodyTotalSpent(Map<String, String> details) {
  // ما ينتظر اعتماد صاحب العهدة أو رُفض لا يُخصم منها.
  final transactions = _parseCustodyTransactions(
    details,
  ).where(_custodySpendCounts);
  final custodySpent = transactions.fold<int>(
    0,
    (sum, transaction) => sum + parseAmountInt(transaction['المبلغ'] ?? ''),
  );
  // تعويض احتياطي: زر "دفعة" العام (المخصص للاشتراكات) كان يظهر سابقًا لكل
  // أنواع الالتزامات بما فيها "عهدة مالية"، فتُسجَّل بعض عمليات الصرف من
  // العهدة بالخطأ داخل مفتاح دفعات الاشتراك بدل مفتاح صرفيات العهدة. تُضاف
  // هذه القيم هنا حتى يظهر المصروف الصحيح دون فقدان بيانات مُسجَّلة مسبقًا.
  final misroutedPayments = _subscriptionTotalPaid(details);
  return custodySpent + misroutedPayments;
}

// نفس فكرة سجل صرفيات العهدة أعلاه: كل دفعة تُسجَّل على التزام (اشتراك أو
// غيره) تُحفظ كعنصر ضمن قائمة مُرمَّزة بصيغة JSON داخل
// details['سجل دفعات الالتزام'] بدل الاكتفاء بتعديل الحالة محليًا فقط —
// حتى لا تختفي الدفعات المسجَّلة عند إعادة تحميل البيانات من الخادم.
const String _subscriptionPaymentsDetailKey = 'سجل دفعات الالتزام';
// مفتاح مسار صورة الفاتورة داخل عنصر الدفعة نفسه (وليس فقط في المرفق العام
// الوحيد للقيد)، حتى تبقى كل فاتورة مرتبطة بدفعتها وتُسترجع بعد إعادة
// تحميل البيانات من الخادم بدل الاختفاء لأنها لم تكن تُشفَّر أصلاً.
const String _paymentInvoiceKey = 'مرفق الفاتورة';

/// وقت تسجيل الحركة (ساعة:دقيقة) — يظهر بجانب تاريخها في السجلات.
const String _recordTimeKey = 'وقت التسجيل';
const String _approvedAtKey = 'تاريخ ووقت الاعتماد';
const String _rejectedAtKey = 'تاريخ ووقت الرفض';

String _pad2(int v) => v.toString().padLeft(2, '0');

String _clockNow() {
  final now = DateTime.now();
  return '${_pad2(now.hour)}:${_pad2(now.minute)}';
}

String _stampNow() {
  final now = DateTime.now();
  return '${now.day}/${now.month}/${now.year} '
      '${_pad2(now.hour)}:${_pad2(now.minute)}';
}

/// «17/10/2026 14:32» — والسجلات القديمة بلا وقت تبقى بالتاريخ وحده.
String _withTime(String date, String? time) {
  final clock = (time ?? '').trim();
  return clock.isEmpty ? date : '$date $clock';
}

/// السطر الثاني لمصروف العهدة: التاريخ والوقت ومن صرف، ووقت الاعتماد/الرفض.
String _custodySpendLine2(Map<String, String> row) {
  final date = (row['التاريخ'] ?? '').trim();
  final by = (row['بواسطة'] ?? '').trim();
  final approvedAt = (row[_approvedAtKey] ?? '').trim();
  final rejectedAt = (row[_rejectedAtKey] ?? '').trim();
  return [
    if (date.isNotEmpty) _withTime(date, row[_recordTimeKey]),
    if (by.isNotEmpty) 'بواسطة $by',
    if (approvedAt.isNotEmpty) '${AppTr.tr('اعتُمد في')} $approvedAt',
    if (rejectedAt.isNotEmpty) '${AppTr.tr('رُفض في')} $rejectedAt',
  ].join(' · ');
}

/// سجل المتابعة والتنظيم: ملاحظات وتذكيرات وغيرها تُحفظ داخل تفاصيل
/// الالتزام نفسه (بلا جدول جديد) وتُعرض مجمَّعة في قسم «المتابعة/التخطيط».
const String _followupLogKey = 'سجل المتابعة';

/// فلاتر زمنية صغيرة تُضاف إلى شريحة «أدوية وبيانات وكلمات سر».
const List<String> _medicineTimeFilters = [
  'اليوم',
  'القادم',
  'المكتمل',
  'منتهي',
];

DateTime? _parseDayValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parts = value.split(RegExp(r'[/\-]'));
  if (parts.length < 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2]);
  if (a == null || b == null || c == null) return null;
  // صيغة التطبيق: يوم/شهر/سنة، وصيغة الخادم: سنة-شهر-يوم.
  if (parts[0].length == 4) return DateTime(a, b, c);
  return DateTime(c, b, a);
}

/// أنواع الإضافات التي تُسجَّل في سجل المتابعة بدل إنشاء التزام مستقل.
const Set<String> _followupTypes = {
  'ملاحظات',
  'ملاحظة',
  'تذكير',
  'مهمة',
  'موعد',
  'عادة',
  'متابعة',
  'تسجيل / تخطيط',
  'تجديد',
};

List<Map<String, String>> _parseFollowupRows(Map<String, String> details) {
  final raw = details[_followupLogKey];
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}

/// تصنيف صف السجل إلى مجموعته المعروضة: ملاحظات، تذكير، أخرى.
String _followupGroupOf(Map<String, String> row) {
  final type = (row['النوع'] ?? '').trim();
  if (type == 'ملاحظات' || type == 'ملاحظة') return 'ملاحظات';
  if (const {'تذكير', 'مهمة', 'موعد', 'عادة'}.contains(type)) return type;
  return 'أخرى';
}

List<Map<String, String>> _parseSubscriptionPayments(
  Map<String, String> details,
) {
  final raw = details[_subscriptionPaymentsDetailKey];
  if (raw == null || raw.trim().isEmpty) return <Map<String, String>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, String>>[];
    return decoded
        .whereType<Map>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        )
        .toList();
  } catch (_) {
    return <Map<String, String>>[];
  }
}

String _encodeSubscriptionPayments(List<Map<String, String>> payments) =>
    jsonEncode(payments);

int _subscriptionTotalPaid(Map<String, String> details) {
  final payments = _parseSubscriptionPayments(details);
  return payments.fold<int>(
    0,
    (sum, payment) => sum + parseAmountInt(payment['المبلغ'] ?? ''),
  );
}

// يفتح صورة فاتورة الدفعة المحفوظة في مخزن Supabase (نفس bucket المرفقات
// العام) عبر رابط موقَّع مؤقت، بدل الاكتفاء بحفظ المسار دون أي وسيلة لعرضه.
Future<void> _openInvoiceImage(BuildContext context, String storagePath) async {
  try {
    final url = await Supabase.instance.client.storage
        .from('personal-entry-attachments')
        .createSignedUrl(storagePath, 3600);
    if (!context.mounted) return;
    final lower = storagePath.toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.bmp'];
    if (!imageExts.any(lower.endsWith)) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(24),
                    child: const Text('تعذر تحميل صورة الفاتورة'),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF5C6B68),
              ),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تعذر فتح صورة الفاتورة')));
  }
}

/// عنوان حقل الرقم التعريفي للشخص المسند إليه في نموذج العهدة المالية.
const String _custodyHolderIdLabel = 'الرقم التعريفي للمستلم';

/// تنبيه العهدة: حين يبلغ ما صُرف هذه النسبة من قيمتها يصل تذكير.
const String _custodyAlertLabel = 'تنبيه عند صرف نسبة';
const List<String> _custodyAlertOptions = [
  'بلا تنبيه',
  '50%',
  '75%',
  '90%',
  '100%',
];

/// اعتماد صرفيات العهدة: هل يحتاج كل مصروف يرسله المستلم موافقة صاحب
/// العهدة قبل خصمه منها. يُحفظ في التفاصيل، وحالة كل مصروف داخل سجله.
const String _custodyApprovalLabel = 'اعتماد المصروفات';
const String _custodyApprovalRequired = 'بموافقة صاحب العهدة';
const String _custodyApprovalNone = 'بدون موافقة';
const String _custodySpendStateKey = 'حالة الاعتماد';
const String _custodySpendPending = 'بانتظار الاعتماد';
const String _custodySpendApproved = 'معتمد';
const String _custodySpendRejected = 'مرفوض';

/// المستلم (المسند إليه) لا يرى إضافة المبلغ ولا الإسناد ولا الإلغاء ولا
/// التسوية — هذه لصاحب العهدة الذي أرسلها فقط.
bool _isCustodyRecipient(Map<String, String> details) {
  final myId = AppIdentity.id;
  if (myId.isEmpty) return false;
  final assignment = CustodyAssignment.decode(details);
  if (assignment.holderId.isNotEmpty && assignment.holderId == myId) {
    return true;
  }
  return AppIdentity.normalize(details[_custodyHolderIdLabel] ?? '') == myId;
}

/// صاحب العهدة (من أرسلها): إضافة مبلغ، تسوية، إلغاء، إسناد.
bool _isCustodyOwnerView(Map<String, String> details) =>
    CustodyAssignment.decode(details).canManageAmount(AppIdentity.id) &&
    !_isCustodyRecipient(details);

/// الدين لي (موجب) من جهتي: يُقرأ اتجاهه كما سجّله صاحبه، ويُقلب إن كنت أنا
/// الطرف الآخر المرتبط به.
bool _debtIsForMe(_CommitmentItem item) {
  final ownerSide = (item.details['نوع الدين'] ?? '').trim().startsWith('لي');
  final role = CustodyAssignment.decode(item.details).roleFor(AppIdentity.id);
  return role == CustodyRole.holder ? !ownerSide : ownerSide;
}

/// إضافة أشهر مع البقاء في آخر الشهر إن كان أقصر (31 ← 28/30).
DateTime _addMonthsClamped(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > last ? last : date.day);
}

/// الطرف الآخر في عهدة أو دين (مسند إليه أو مطّلع): لا يحذف سجل غيره ولا
/// يؤرشفه.
/// حالة العهدة بكلمة ولون ثابتين: الأخضر نشطة، الأزرق مكتملة (سُوّيت)،
/// الأحمر ملغاة، الرمادي مؤرشفة.
(String, Color) _custodyStateLook(String status) => switch (status) {
  'تمت التسوية' => ('مكتملة', const Color(0xFF2F6FB0)),
  'ملغاة' => ('ملغاة', const Color(0xFFC4392E)),
  'مؤرشف' => ('مؤرشفة', const Color(0xFF8C9A97)),
  // «مجمّد» للعهدة المالية وحدها: يتوقف الصرف حتى يُلغى التجميد.
  'مجمّدة' => ('مجمّدة', const Color(0xFF5B7A99)),
  _ => ('نشطة', const Color(0xFF178F7B)),
};

/// «مفوَّض بها أنا» (أنا المستلم) أو «فوّضت بها غيري» (أنا صاحبها).
String? _custodyRoleLabel(Map<String, String> details) {
  final assignment = CustodyAssignment.decode(details);
  if (!assignment.isAssigned || assignment.isRejected) return null;
  final me = AppIdentity.id;
  if (me.isEmpty) return null;
  if (assignment.holderId == me) return 'مفوَّض بها أنا';
  if (assignment.ownerId == me) return 'فوّضت بها غيري';
  return null;
}

/// حالة العهدة الملوّنة (فوق المبلغ في البطاقة).
Widget _custodyStatePill(_CommitmentItem item) {
  final (label, color) = _custodyStateLook(item.status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
    ),
  );
}

/// دوري في العهدة (تحت «عهدة مالية» مقابل التاريخ)، أو لا شيء.
Widget? _custodyRoleText(_CommitmentItem item) {
  final role = _custodyRoleLabel(item.details);
  if (role == null) return null;
  return Text(
    role,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: Color(0xFFA6691A),
    ),
  );
}

bool _isSharedGuest(_CommitmentItem item) {
  if (!_sharedEntryTypes.contains(item.entryType)) return false;
  final role = CustodyAssignment.decode(item.details).roleFor(AppIdentity.id);
  return role == CustodyRole.holder || role == CustodyRole.observer;
}

/// قبل الرد على إسناد: أحدث نسخة من الخادم، والطلب ما زال بانتظار القبول
/// وموجّهًا لي. يعيد التفاصيل الأحدث، أو null إن لم يعد قائمًا.
Future<Map<String, String>?> _stillPendingForMe(
  PersonalEntriesRepository repository,
  String? id,
  Map<String, String> fallback,
) async {
  var details = fallback;
  if (id != null && repository is SupabasePersonalEntriesRepository) {
    try {
      final fresh = await repository.fetchOne(id);
      if (fresh == null) return null;
      details = fresh.details;
    } catch (_) {
      // بلا اتصال: يُعتمد على النسخة المعروضة.
    }
  }
  final assignment = CustodyAssignment.decode(details);
  if (!assignment.isPending || assignment.holderId != AppIdentity.id) {
    return null;
  }
  return details;
}

bool _custodyNeedsApproval(Map<String, String> details) =>
    (details[_custodyApprovalLabel] ?? '').trim() == _custodyApprovalRequired;

/// المصروف المحسوب على العهدة: المعتمد أو الذي لا يحتاج اعتمادًا.
bool _custodySpendCounts(Map<String, String> transaction) {
  final state = transaction[_custodySpendStateKey] ?? '';
  return state != _custodySpendPending && state != _custodySpendRejected;
}

int _custodyAlertPercent(Map<String, String> details) {
  final match = RegExp(r'\d+').firstMatch(details[_custodyAlertLabel] ?? '');
  return match == null ? 0 : int.parse(match.group(0)!);
}

/// يتحقق من بلوغ نسبة الصرف المختارة مرة واحدة لكل عهدة ونسبة: يضيف
/// تذكيرًا في التنبيهات ويعيد نص الرسالة، أو `null` إن لم يُبلغ بعد.
Future<String?> _checkCustodyAlert({
  required String? id,
  required String title,
  required int total,
  required Map<String, String> details,
}) async {
  final percent = _custodyAlertPercent(details);
  if (id == null || id.isEmpty || percent <= 0 || total <= 0) return null;
  final spent = _custodyTotalSpent(details);
  if (spent * 100 < total * percent) return null;
  const key = 'custody_percent_alerts_v1';
  try {
    final prefs = await SharedPreferences.getInstance();
    final sent = (prefs.getStringList(key) ?? const <String>[]).toSet();
    final stamp = '$id|$percent';
    if (sent.contains(stamp)) return null;
    sent.add(stamp);
    await prefs.setStringList(key, sent.toList());
    final actual = (spent * 100 / total).round();
    final message =
        '${AppTr.tr('العهدة')} «$title»: ${AppTr.tr('صُرف')} $actual% '
        '${AppTr.tr('من قيمتها')}';
    final today = DateTime.now();
    await AppRemindersStore.upsert(
      AppReminder(
        id: 'custody_percent_$id',
        title: message,
        module: 'الالتزامات الشخصية',
        expiryDate: DateTime(today.year, today.month, today.day),
        remindBeforeDays: 0,
      ),
    );
    return message;
  } catch (_) {
    return null;
  }
}

/// الرقم التعريفي للطرف الثاني في الدين — اختياري؛ إن كُتب دخل الطرف
/// الآخر على الدين نفسه وسجّل سداده فيظهر عند صاحب الدين مباشرة.
const String _debtHolderIdLabel = 'الرقم التعريفي للطرف الثاني';

/// أنواع الالتزامات التي تُشارَك مع طرف ثانٍ بالرقم التعريفي.
const Set<String> _sharedEntryTypes = {'عهدة مالية', 'دين / قرض / سلفة'};

/// عنوان فوق الحقل — يُستعمل في النموذج المبسّط للحقول ذات الأسماء
/// الطويلة حتى تظهر كاملة على سطرين بدل قصّها داخل الحقل.
Widget _outerLabelWrap(_FinancialField field, Widget child) {
  if (!field.half) return child;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 6, end: 6, bottom: 5),
        child: Text(
          field.required ? '${field.label} *' : field.label,
          textAlign: AppTr.alignEnd,
          maxLines: 2,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: AppTheme.muted,
          ),
        ),
      ),
      child,
    ],
  );
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

/// العهدة المالية تُسند إلزاميًا إلى شخص بالرقم التعريفي: تُدمج حالة
/// الإسناد «بانتظار القبول» في تفاصيل السجل لحظة الإنشاء، فيصل الطلب إلى
/// الطرف الآخر فور فتح تطبيقه ولا تبقى عهدة بلا مسؤول.
Map<String, String> _withCustodyAssignment(
  String entryType,
  Map<String, String> details,
  String holderName,
) {
  if (!_sharedEntryTypes.contains(entryType)) return details;
  final idLabel = entryType == 'عهدة مالية'
      ? _custodyHolderIdLabel
      : _debtHolderIdLabel;
  final holderId = AppIdentity.normalize(details[idLabel] ?? '');
  if (!AppIdentity.isValid(holderId) || holderId == AppIdentity.id) {
    return details;
  }
  final now = DateTime.now();
  final stamp =
      '${now.day}/${now.month}/${now.year} '
      '${_pad2(now.hour)}:${_pad2(now.minute)}';
  final out = Map<String, String>.of(details);
  out[idLabel] = holderId;
  return CustodyAssignment(
    ownerId: AppIdentity.id,
    ownerName: AppSettings.instance.publicName,
    holderId: holderId,
    holderName: holderName,
    state: CustodyAssignmentState.pending,
    assignedAt: stamp,
    note: '',
  ).applyTo(out);
}

enum _CommitmentMenuAction {
  edit,
  newCourse,
  samePrescription,
  newCustody,
  share,
  delete,
  cancel,
  cancelAssignment,
  reopenCustody,
  freezeCustody,
  archive,
}

/// اسم النوع في رسالة «تم حفظ ...»: «تم حفظ الإيراد»، «تم حفظ المصروفات
/// الشخصية»...
String _savedLabel(String type) {
  const names = {
    'المصروفات الشخصية': 'المصروفات الشخصية',
    'إيراد': 'الإيراد',
    'دين / قرض / سلفة': 'الدين / القرض / السلفة',
    'قسط': 'القسط',
    'غرامة': 'الغرامة',
    'مستند': 'المستند',
    'مهمة': 'المهمة',
    'موعد': 'الموعد',
    'عادة': 'العادة',
    'تذكير': 'التذكير',
    'ملاحظات': 'الملاحظات',
    'ملاحظة': 'الملاحظة',
    'أدوية': 'الدواء',
    'كلمات سر': 'كلمة السر',
    'مناسبة': 'المناسبة',
    'هدية': 'الهدية',
    'اشتراك': 'الاشتراك',
    'مواقع وأماكن': 'الموقع',
    'عهدة مالية': 'العهدة المالية',
    'جمعية': 'الجمعية',
    'تجديد': 'التجديد',
    'متابعة': 'المتابعة',
    'صورة': 'الصورة',
    'فاتورة': 'الفاتورة',
  };
  return names[type] ?? type;
}

/// سجل كورسات الدواء: كل كورس سابق ببياناته («كورس 1»، «كورس 2»...).
const String _courseLogKey = 'سجل الكورسات';

/// المستفيد من الدواء: «أدوية لي» = اسم المستخدم، وغيرها كما كُتب.
String _medicineBeneficiary(_CommitmentItem item) {
  final who = (item.details['لمن هذا الدواء'] ?? '').trim();
  if (who.isEmpty) return 'غير محدد';
  if (who == 'أدوية لي') {
    final name = AppSettings.instance.name.trim();
    return name.isEmpty ? 'أنا' : name;
  }
  if (who == 'أدوية لشخص آخر') {
    final other = _firstNonEmpty([
      item.details['اسم المستفيد'] ?? '',
      item.details['اسم الشخص'] ?? '',
    ]);
    return other.isEmpty ? 'شخص آخر' : other;
  }
  return who;
}

/// سجل العهد السابقة: «بدء عهدة جديدة» ينقل العهدة الحالية إليه
/// (عهدة رقم 1، 2…) بكل معلوماتها وصرفياتها.
const String _custodyLogKey = 'سجل العهد السابقة';

List<Map<String, String>> _parseCustodyLog(Map<String, String> details) {
  try {
    final decoded = jsonDecode(details[_custodyLogKey] ?? '[]');
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded.whereType<Map>())
        entry.map((k, v) => MapEntry('$k', '$v')),
    ];
  } catch (_) {
    return const [];
  }
}

/// تفاصيل عهدة سابقة من السجل: كل معلوماتها وصرفياتها.
Future<void> _showCustodySnapshot(
  BuildContext context,
  Map<String, String> snapshot,
  String currency,
) {
  final spends = _parseCustodyTransactions(snapshot);
  final rows = [
    for (final entry in snapshot.entries)
      if (entry.key != 'العهدة' &&
          entry.key != _custodyTransactionsDetailKey &&
          entry.key != CustodyTopUps.key &&
          !CustodyAssignment.keys.contains(entry.key) &&
          entry.value.trim().isNotEmpty)
        entry,
  ];
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        title: Text(snapshot['العهدة'] ?? 'عهدة'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (spends.isNotEmpty) ...[
                const Divider(),
                Text(
                  '${AppTr.tr('مصروفات العهدة')} (${spends.length})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                for (final spend in spends)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '-${spend['المبلغ'] ?? '0'} $currency'
                      '${(spend['الغرض'] ?? '').isEmpty ? '' : ' · ${spend['الغرض']}'}'
                      '${(spend['التاريخ'] ?? '').isEmpty ? '' : ' · ${spend['التاريخ']}'}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ),
  );
}

List<Map<String, String>> _parseCourseLog(Map<String, String> details) {
  try {
    final decoded = jsonDecode(details[_courseLogKey] ?? '[]');
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded.whereType<Map>())
        entry.map((k, v) => MapEntry('$k', '$v')),
    ];
  } catch (_) {
    return const [];
  }
}

/// فلتر الالتزامات الشخصية — لفلتر الصفحة الرئيسية.
AppFilterModuleConfig personalFilterModuleConfig() =>
    _PersonalCommitmentsScreenState.moduleConfig();

class PersonalCommitmentsScreen extends StatefulWidget {
  final PersonalEntriesRepository? repository;

  /// فلتر يُطبَّق عند الفتح (من فلتر الصفحة الرئيسية).
  final AppFilterValues? initialFilter;

  /// فتح نموذج إضافة نوع بعينه مباشرة ثم الرجوع بعد إغلاقه — يُستعمل من
  /// تفاصيل فرد لإضافة دواء أو متابعة أو موقع بنفس نموذج الالتزامات
  /// الشخصية، فيُحفظ هنا ويظهر عند الفرد أيضًا.
  final String? openFormFor;

  /// قيم تُعبّأ في النموذج عند الفتح المباشر (مثل «لمن هذا الدواء»).
  final Map<String, String> prefill;

  /// تفاصيل تُحفظ مع البند الجديد (ربطه بالفرد).
  final Map<String, String> linkDetails;

  /// فتح تفاصيل بند بعينه مباشرة (للتعديل أو الحذف) ثم الرجوع.
  final String? openEntryId;

  const PersonalCommitmentsScreen({
    super.key,
    this.repository,
    this.initialFilter,
    this.openFormFor,
    this.prefill = const {},
    this.linkDetails = const {},
    this.openEntryId,
  });

  @override
  State<PersonalCommitmentsScreen> createState() =>
      _PersonalCommitmentsScreenState();
}

class _PersonalCommitmentsScreenState extends State<PersonalCommitmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final PersonalEntriesRepository _repository;
  String _selectedEntryType = 'الكل';

  /// شريط الفئات: يُمرَّر حتى تظهر الفئة المختارة عند الفتح بفلتر (مثل
  /// «عهدة مالية» من المثبّت في الرئيسية، وهي آخر الشرائح).
  final ScrollController _chipsScroll = ScrollController();

  void _revealSelectedChip([int attempt = 0]) {
    if (!mounted || _selectedEntryType == 'الكل') return;
    if (!_chipsScroll.hasClients) {
      if (attempt < 10) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _revealSelectedChip(attempt + 1),
        );
      }
      return;
    }
    final shown = [
      for (final filter in _personalDashboardFilters)
        if (filter.$1 == 'الكل' ||
            !PageCustomizationStore.categoryHidden(_pc, filter.$1))
          filter.$1,
    ];
    final index = shown.indexOf(_selectedEntryType);
    if (index <= 0 || shown.length < 2) return;
    final max = _chipsScroll.position.maxScrollExtent;
    _chipsScroll.animateTo(
      max * index / (shown.length - 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// الأفراد والجهات المسجّلون — لاختيار الطرف في الدين والقسط وملء بياناته.
  Map<String, PeopleDirectoryEntry> _partyDirectory = const {};

  /// أرقام تعريفية معروفة ← أسماء أصحابها (من العهد والديون السابقة ومن
  /// «الأفراد والجهات») — الاسم وحده، بلا هاتف ولا عنوان.
  Map<String, String> _knownIdentities = const {};
  static const _knownIdentitiesKey = 'known_identities_v1';

  Future<Map<String, String>> _loadKnownIdentities() async {
    final out = <String, String>{};
    void put(String id, String name) {
      final key = AppIdentity.normalize(id);
      if (!AppIdentity.isValid(key) || key == AppIdentity.id) return;
      if (name.trim().isEmpty) return;
      out[key] = name.trim();
    }

    for (final item in _items) {
      final assignment = CustodyAssignment.decode(item.details);
      put(assignment.ownerId, assignment.ownerName);
      put(assignment.holderId, assignment.holderName);
    }
    try {
      for (final entry in await PeopleDirectoryStore.load()) {
        put(entry.firstOf(['الرقم التعريفي', 'رقم التعريف']), entry.fullName);
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownIdentitiesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) => put('$key', '$value'));
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _rememberIdentity(String id, String name) async {
    final key = AppIdentity.normalize(id);
    if (!AppIdentity.isValid(key) || name.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownIdentitiesKey);
      final map = <String, String>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) => map['$k'] = '$v');
        }
      }
      map[key] = name.trim();
      await prefs.setString(_knownIdentitiesKey, jsonEncode(map));
    } catch (_) {}
  }

  /// بعد حفظ دواء جديد: «إضافة دواء آخر من نفس الوصفة؟» — يفتح النموذج
  /// بالبيانات نفسها، ويُكتب اسم الدواء والجرعة فقط. ويتكرّر بعد كل دواء.
  Future<void> _offerSamePrescription(
    _FinancialEntryForm form,
    PersonalEntryRecord saved,
    void Function(PersonalEntryRecord record)? onSaved,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    // اختار «إضافة دواء»: تنبيه بما سيحدث ثم النموذج.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: Text('تم حفظ «${saved.title}»'),
          content: const Text(
            'الدواء الآخر سيتم بنفس المعلومات السابقة للدواء، فأرجو التعديل.',
            textAlign: TextAlign.right,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    await _openFinancialEntryForm(
      form,
      copyFrom: _itemFromRecord(saved),
      sameVisit: true,
      onSaved: onSaved,
    );
  }

  /// تأكيد حفظ دواء جديد: «إضافة دواء» يمين «إلغاء»، ثم «تأكيد».
  /// يُعيد 'save' أو 'add'، أو null عند الإلغاء.
  Future<String?> _askMedicineSave(
    BuildContext context,
    _FinancialEntryForm form,
  ) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        // «إضافة دواء آخر» و«إلغاء» أقصى اليمين تحت السؤال، و«تأكيد» يسارًا.
        child: AlertDialog(
          title: const Text('تأكيد الحفظ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'هل تريد حفظ ${_savedLabel(form.label)}؟',
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              Row(
                textDirection: AppTr.uiDir,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('add'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('إضافة دواء آخر'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop('save'),
                    child: const Text('تأكيد'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// نموذج إضافة جديد مملوء ببيانات [item] (بتاريخ اليوم) — يُحفظ كسجل جديد.
  /// [sameVisit]: دواء آخر من نفس الوصفة (التواريخ كما هي، والاسم والجرعة
  /// فارغان).
  Future<PersonalEntryRecord?> _openCopyFormFor(
    _CommitmentItem item, {
    bool sameVisit = false,
  }) async {
    final form = _financialEntryForms[item.entryType];
    if (form == null) return null;
    PersonalEntryRecord? result;
    await _openFinancialEntryForm(
      form,
      copyFrom: item,
      sameVisit: sameVisit,
      onSaved: (record) => result = record,
    );
    if (result != null && mounted) await _loadEntries();
    return result;
  }

  /// فتح نموذج الإضافة نفسه لتعديل البيانات (أو لبدء كورس دواء جديد).
  Future<PersonalEntryRecord?> _openFullEditFor(
    _CommitmentItem item,
    bool newCourse,
  ) async {
    final form = _financialEntryForms[item.entryType];
    if (form == null) return null;
    PersonalEntryRecord? result;
    await _openFinancialEntryForm(
      form,
      editing: item,
      newCourse: newCourse,
      onSaved: (record) => result = record,
    );
    return result;
  }
  String _selectedSort = 'الأحدث أولاً';
  int _selectedFollowUpMetric = 0;
  List<String> _recentSearches = const [];
  // إخفاء تنبيه "طلب بانتظار إجراء" بزر (✕) — يبقى مخفيًا لهذه الجلسة فقط،
  // ويظهر من جديد تلقائيًا عند وجود طلب جديد مختلف عن آخر عدد تم إخفاؤه.
  bool _requestBannerDismissed = false;
  int _requestBannerDismissedAtCount = -1;

  // حالة شاشة الفلتر المتقدم (زر "تصفية" بجانب البحث). "الفئة الرئيسية"
  // تُدار عبر _selectedEntryType نفسه (نفس فلتر الفئات في الأعلى)؛ بقية
  // الحقول فلاتر إضافية تُطبَّق فوقه وفوق شريط البحث في _filteredItems().
  /// قيم الفلتر الرئيسي — نفس البنية في الشاشات الأربع.
  final AppFilterValues _filter = AppFilterValues();

  // اسم مختصر للفئة الفرعية، تستعمله رقائق الفئات وعنوان القائمة.
  String? get _advFilterSubType => _filter.subCategory;
  set _advFilterSubType(String? value) => _filter.subCategory = value;

  bool get _hasActiveAdvancedFilters => _filter.isActive;

  static const String _statusOverdue = 'متأخرة';
  static const String _statusDueSoon = 'قريبة الاستحقاق';
  static const String _statusActive = 'نشطة';
  static const String _statusCompleted = 'مكتملة';

  static const Map<String, int> _statusPriority = {
    _statusOverdue: 0,
    _statusDueSoon: 1,
    _statusActive: 2,
    _statusCompleted: 3,
  };

  final List<_CommitmentItem> _items = [];

  static const List<_EntryCategory> _entryCategories = [
    _EntryCategory(
      title: 'مالية',
      subtitle: 'مصروفات وإيرادات وديون',
      color: Color(0xFF34A894),
      icon: Icons.account_balance_wallet,
      types: [
        _EntryType('المصروفات الشخصية', Icons.trending_down),
        _EntryType('إيراد', Icons.trending_up),
        _EntryType('دين / قرض / سلفة', Icons.handshake),
        _EntryType('قسط', Icons.calendar_month),
        _EntryType('غرامة', Icons.gavel),
      ],
    ),
    _EntryCategory(
      title: 'مستند',
      subtitle: 'وثائق وملفات مهمة',
      color: Color(0xFFCE8422),
      icon: Icons.description_outlined,
      types: [_EntryType('مستند', Icons.description_outlined)],
    ),
    _EntryCategory(
      title: 'المتابعة والتخطيط',
      subtitle: 'مهام ومواعيد وعادات',
      color: Color(0xFF0E7161),
      icon: Icons.event_note_outlined,
      // الأنواع الخمسة المعتمدة في ملف الإدخالات: مهمة، موعد، عادة،
      // تذكير، ملاحظات. حُذف "تجديد" و"متابعة" و"تسجيل / تخطيط" لأنها
      // ليست في الملف. أُبقي "تفويض" لأنه نظام قائم بذاته في التطبيق
      // (طلبات وتفويضات) لا مجرد نوع إدخال.
      types: [
        _EntryType('مهمة', Icons.task_alt_outlined),
        _EntryType('موعد', Icons.event_outlined),
        _EntryType('عادة', Icons.repeat_rounded),
        _EntryType('تذكير', Icons.notifications_active_outlined),
        _EntryType('ملاحظات', Icons.sticky_note_2_outlined),
      ],
    ),
    _EntryCategory(
      title: 'أدوية وبيانات وكلمات سر',
      subtitle: 'الأدوية والحسابات وكلمات المرور',
      color: Color(0xFFC4392E),
      icon: Icons.medical_information_outlined,
      types: [
        _EntryType('أدوية', Icons.medication_outlined),
        _EntryType('كلمات سر', Icons.password_rounded),
      ],
    ),
    _EntryCategory(
      title: 'نمط الحياة',
      subtitle: 'مناسبات واشتراكات وهدايا',
      color: Color(0xFFC4392E),
      icon: Icons.celebration_outlined,
      // "جمعية" ليست ضمن نمط الحياة في الملف المعتمد (وهي أصلًا التزام
      // مشترك لا شخصي)، فحُذفت من القائمة وبقي نموذجها لعرض ما سُجّل سابقًا.
      types: [
        _EntryType('مناسبة', Icons.celebration_outlined),
        _EntryType('اشتراك', Icons.autorenew),
        _EntryType('هدية', Icons.volunteer_activism_outlined),
      ],
    ),
    _EntryCategory(
      title: 'مواقع وأماكن',
      subtitle: 'أماكن ومواقع مهمة',
      color: Color(0xFF0E7161),
      icon: Icons.location_on_outlined,
      types: [_EntryType('مواقع وأماكن', Icons.location_on_outlined)],
    ),
    _EntryCategory(
      title: 'عهدة مالية',
      subtitle: 'مبالغ تحت مسؤولية شخص',
      color: Color(0xFFA6691A),
      icon: Icons.inventory_2_outlined,
      types: [_EntryType('عهدة مالية', Icons.inventory_2_outlined)],
    ),
  ];

  // تصنيف فرعي (للفلترة فقط) لفئة "مستند": بما أن كل المستندات لها نفس
  // نوع الإدخال ('مستند') وتُميَّز فيما بينها عبر حقل "نوع المستند" داخل
  // النموذج، لا تصلح آلية الفئة الفرعية العادية (المبنية على أنواع إدخال
  // منفصلة). بدلها: مجموعات عرض فقط تُطابق قيم "نوع المستند" الفعلية.
  static const Map<String, List<String>> _documentSubtypeGroups = {
    'وثائق شخصية': [
      'هوية',
      'جواز سفر',
      'اقامة وتأشيرة',
      'رخصة قيادة',
      'ملكية سيارة',
      'تأمين سيارة',
      'تأمين صحي',
    ],
    'ضمانات': ['ضمانات'],
    'مستندات عامة': [
      'مستند دراسي',
      'مستند سفر',
      'مستند بنكي',
      'تقرير طبي',
      'تصاريح',
      'فواتير',
      'ايصالات',
    ],
  };

  static const Map<String, IconData> _documentSubtypeGroupIcons = {
    'وثائق شخصية': Icons.badge_outlined,
    'ضمانات': Icons.verified_user_outlined,
    'مستندات عامة': Icons.folder_open_outlined,
  };

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabasePersonalEntriesRepository();
    final initial = widget.initialFilter;
    if (initial != null) {
      _selectedEntryType = initial.mainCategory;
      _filter.assignFrom(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedChip());
    }
    _loadEntries();
    _loadRecentSearches();
    // الرقم التعريفي قد يصل من الخادم بعد فتح الشاشة: طلبات العهدة تُحسب
    // به، فتُعاد قراءتها حين يصل.
    AppIdentity.revision.addListener(_onIdentityChanged);
    final entryId = widget.openEntryId;
    if (entryId != null && entryId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final records = await _repository.fetchAll();
          PersonalEntryRecord? found;
          for (final record in records) {
            if (record.id == entryId) found = record;
          }
          if (found != null && mounted) {
            await _openDetails(_itemFromRecord(found));
          }
        } catch (_) {}
        if (mounted) Navigator.of(context).pop();
      });
    }
    final directForm = _financialEntryForms[widget.openFormFor ?? ''];
    if (directForm != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        PersonalEntryRecord? saved;
        await _openFinancialEntryForm(
          directForm,
          onSaved: (record) => saved = record,
        );
        if (mounted) Navigator.of(context).pop(saved);
      });
    }
    // قائمة عمليات البحث السابقة (والاقتراحات) تظهر وتختفي فقط حسب تركيز
    // خانة البحث (تم الضغط بداخلها أم لا)، وليس دائمًا.
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadEntries() async {
    try {
      final records = await _repository.fetchAll();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(records.map(_itemFromRecord));
      });
      await _notifySenderResponses();
      await _notifyCustodyAlerts();
    } catch (error) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
      });
    }
  }

  /// نسبة صرف العهدة: تنبيه مرة واحدة حين يبلغ الصرف النسبة المختارة.
  Future<void> _notifyCustodyAlerts() async {
    final messages = <String>[];
    for (final item in List.of(_items)) {
      if (item.entryType != 'عهدة مالية') continue;
      final message = await _checkCustodyAlert(
        id: item.id,
        title: item.title,
        total: item.totalAmount,
        details: item.details,
      );
      if (message != null) messages.add(message);
    }
    if (messages.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(messages.join('\n')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// اختيار المستلم من «الأفراد والجهات» (ومن سبق التعامل معهم بالرقم
  /// التعريفي): يُرجع الاسم والرقم التعريفي إن وُجد.
  Future<({String name, String id})?> _pickCustodyPerson(
    Map<String, String> known,
  ) async {
    final people = <({String name, String id, String category})>[];
    final seen = <String>{};
    try {
      for (final entry in await PeopleDirectoryStore.load()) {
        final name = entry.fullName.trim();
        if (name.isEmpty) continue;
        final id = AppIdentity.normalize(
          entry.firstOf(const ['الرقم التعريفي', 'رقم التعريف']),
        );
        people.add((name: name, id: id, category: entry.categoryName));
        seen.add(name);
        if (id.isNotEmpty) seen.add(id);
      }
    } catch (_) {}
    known.forEach((id, name) {
      if (seen.contains(id) || seen.contains(name)) return;
      people.add((name: name, id: id, category: ''));
    });
    if (!mounted) return null;
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد أفراد محفوظون بعد — أضفهم من «الأفراد والجهات»'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    var query = '';
    return showModalBottomSheet<({String name, String id})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final visible = people
              .where(
                (p) =>
                    query.trim().isEmpty ||
                    p.name.contains(query.trim()) ||
                    p.id.contains(query.trim().toUpperCase()),
              )
              .toList(growable: false);
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختر المستلم',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    textDirection: AppTr.uiDir,
                    onChanged: (value) => setSheet(() => query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppTr.tr('ابحث بالاسم أو الرقم التعريفي'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppTheme.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 340,
                    child: ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.line),
                      itemBuilder: (context, index) {
                        final person = visible[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.person_outline_rounded,
                            color: Color(0xFF0E7161),
                          ),
                          title: Text(
                            person.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (person.category.isNotEmpty) person.category,
                              person.id.isEmpty
                                  ? AppTr.tr('بلا رقم تعريفي')
                                  : person.id,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(
                            sheetContext,
                            (name: person.name, id: person.id),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// المرسل: إشعار عند قبول/رفض ما أرسله بالرقم التعريفي (عهدة أو دين)،
  /// ومع القبول يُضاف الطرف الآخر إلى «الأفراد والجهات» باسمه ورقمه فقط —
  /// وبقية بياناته يضيفها المستخدم بنفسه من صفحة الشخص.
  Future<void> _notifySenderResponses() async {
    final myId = AppIdentity.id;
    if (myId.isEmpty) return;
    const key = 'notified_assignment_responses_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(key) ?? const <String>[]).toSet();
      final messages = <String>[];
      for (final item in List.of(_items)) {
        if (!_sharedEntryTypes.contains(item.entryType)) continue;
        final assignment = CustodyAssignment.decode(item.details);
        if (assignment.ownerId != myId || assignment.holderId.isEmpty) continue;
        if (!assignment.isAccepted && !assignment.isRejected) continue;
        final stamp = '${item.id}|${assignment.holderId}|${assignment.stateLabel}';
        if (notified.contains(stamp)) continue;
        notified.add(stamp);
        final who = assignment.holderName.isEmpty
            ? assignment.holderId
            : assignment.holderName;
        final what = item.entryType == 'عهدة مالية' ? 'العهدة' : 'الدين';
        if (assignment.isAccepted) {
          messages.add('قبل $who $what «${item.title}» — أُضيف إلى الأفراد والجهات، ويمكنك من هناك إضافة أي بيانات أخرى عنه');
          if (assignment.holderName.isNotEmpty) {
            await PeopleDirectoryStore.upsert(
              fullName: assignment.holderName,
              typeKey: 'person_other',
              categoryName: 'أخرى',
              details: {'الرقم التعريفي': assignment.holderId},
              sourceNote: 'قبل $what «${item.title}»',
            );
          }
        } else {
          messages.add('رفض $who $what «${item.title}»');
        }
      }
      await prefs.setStringList(key, notified.toList());
      if (messages.isEmpty || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages.join('\n')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (_) {}
  }

  _CommitmentItem _itemFromRecord(PersonalEntryRecord record) {
    final form = _financialEntryForms[record.entryType];
    final color = form?.color ?? const Color(0xFF46534F);
    final createdAt = record.createdAt?.toLocal() ?? DateTime.now();
    final payments = _parseSubscriptionPayments(record.details)
        .map(
          (payment) => _SubscriptionPayment(
            payerName: payment['الدافع'] ?? '',
            amount: parseAmountInt(payment['المبلغ'] ?? ''),
            date: payment['التاريخ'] ?? '',
            invoiceImagePath: (payment[_paymentInvoiceKey]?.isNotEmpty ?? false)
                ? payment[_paymentInvoiceKey]
                : null,
          ),
        )
        .toList();
    final paidAmount = _subscriptionTotalPaid(record.details);
    return _CommitmentItem(
      id: record.id,
      category: record.category,
      title: record.title,
      status: record.status,
      statusColor: _personalStatusColor(record.status),
      amount: record.amount,
      dueDate: record.dueDate,
      progress: record.amount > 0
          ? (paidAmount / record.amount).clamp(0.0, 1.0)
          : 0.0,
      remainingInstallments: record.entryType == 'قسط' ? 1 : 0,
      lastUpdate:
          '${createdAt.day}/${createdAt.month}/${createdAt.year} '
          '${_pad2(createdAt.hour)}:${_pad2(createdAt.minute)}',
      icon: form?.icon ?? Icons.description_outlined,
      iconColor: color,
      iconBackground: color.withValues(alpha: 0.12),
      subscriptionMembers:
          record.entryType == 'اشتراك' ||
              record.entryType == 'اشتراكات'
          ? int.tryParse(record.details['عدد الأفراد'] ?? '') ?? 1
          : null,
      entryType: record.entryType,
      details: record.details,
      attachmentPath: record.attachmentUrl,
      paidAmount: paidAmount,
      payments: payments,
    );
  }

  @override
  void dispose() {
    AppIdentity.revision.removeListener(_onIdentityChanged);
    _chipsScroll.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onIdentityChanged() {
    if (mounted) setState(() {});
  }

  /// العهدة المالية القائمة (ومنها المرسلة بانتظار الموافقة) تُعدّ نشطة.
  bool _isActiveCustody(_CommitmentItem item) =>
      item.entryType == 'عهدة مالية' &&
      _isOpenItem(item) &&
      item.status != 'ملغاة' &&
      item.status != 'تمت التسوية' &&
      item.status != 'مؤرشف' &&
      item.status != 'مجمّدة';

  List<_CommitmentItem> _filteredItems() {
    final q = _searchController.text.trim();
    var filtered = _items.where((item) {
      // المحذوف لا يظهر مهما كانت الفلاتر — مكانه سلة المهملات.
      if (item.status == TrashStore.status) return false;
      // المخفي من «تخصيص الصفحات» لا يظهر.
      if (_itemHidden(item)) return false;
      final typeMatches =
          _selectedEntryType == 'الكل' ||
          _entryTypeMatches(item.entryType, _selectedEntryType);
      final queryMatches =
          q.isEmpty ||
          item.title.contains(q) ||
          item.status.contains(q) ||
          (item.entryType?.contains(q) ?? false);
      return typeMatches && queryMatches;
    }).toList();

    filtered = _applyAdvancedFilters(filtered);

    // الفلتر الصغير بجانب العنوان: كل خيار يُظهر ما يطابقه فقط، و«الأحدث
    // أولاً» و«أعلى/أقل مبلغًا» ترتيب لا تصفية.
    filtered = filtered
        .where((item) => _matchesQuickFilter(item, _selectedSort))
        .toList();

    final amountOrder = _filter.amountShortcut;
    final highFirst =
        amountOrder == 'أعلى مبلغ' ||
        amountOrder == 'أعلى مبلغًا' ||
        _selectedSort == 'أعلى مبلغًا';
    final lowFirst =
        amountOrder == 'أقل مبلغ' ||
        amountOrder == 'أقل مبلغًا' ||
        _selectedSort == 'أقل مبلغًا';
    if (highFirst) {
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (lowFirst) {
      filtered.sort((a, b) => a.amount.compareTo(b.amount));
    } else {
      // الأحدث أولاً، ومع التساوي الأهم حالةً.
      filtered.sort((a, b) {
        final byDate = _itemDate(b).compareTo(_itemDate(a));
        if (byDate != 0) return byDate;
        final pa = _statusPriority[a.status] ?? 99;
        final pb = _statusPriority[b.status] ?? 99;
        return pa.compareTo(pb);
      });
    }

    return filtered;
  }

  /// تاريخ الالتزام للفلاتر الزمنية (اليوم، غدًا، بعد أسبوع): تاريخ
  /// الاستحقاق، أو «التاريخ» في المهام والمواعيد.
  DateTime? _quickDateOf(_CommitmentItem item) =>
      _parseDueDate(item.dueDate) ??
      _parseDayValue(item.details['التاريخ'] ?? '');

  /// هل يطابق الالتزام خيار الفلتر الصغير؟
  bool _matchesQuickFilter(_CommitmentItem item, String label) {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (label) {
      case 'الأحدث أولاً':
      case 'أعلى مبلغًا':
      case 'أقل مبلغًا':
        return true;
      case 'نشط':
        return _effectiveStatus(item) == _statusActive ||
            _isActiveCustody(item);
      case 'قريبة الاستحقاق':
      case 'قريب الإستحقاق':
        return _effectiveStatus(item) == _statusDueSoon;
      case 'مستحقة':
        return _isOpenItem(item) &&
            item.status != 'ملغاة' &&
            _isDueToday(item);
      case 'متأخرة':
        return item.status != 'ملغاة' &&
            _effectiveStatus(item) == _statusOverdue;
      case 'مكتمل':
        // العهدة المسوّاة مكتملة أيضًا.
        return item.status == _statusCompleted ||
            item.status == 'تمت التسوية';
      case 'ملغاة':
        return item.status == 'ملغاة';
      case 'مجمّدة':
        return item.status == 'مجمّدة';
      case 'اليوم':
      case 'غدًا':
      case 'بعد أسبوع':
        {
          final date = _quickDateOf(item);
          if (date == null) return false;
          final day = DateUtils.dateOnly(date);
          final days = day.difference(today).inDays;
          return switch (label) {
            'اليوم' => days == 0,
            'غدًا' => days == 1,
            _ => days >= 0 && days <= 7,
          };
        }
      default:
        // المستندات والأدوية.
        return _quickSortRank(item, label) == 0;
    }
  }

  // يطبّق فلاتر شاشة "الفلتر المتقدم" (الفئة الفرعية، التاريخ، الحالة،
  // المبلغ، المستند، المكان) فوق فلتر الفئة الرئيسية وشريط البحث.
  List<_CommitmentItem> _applyAdvancedFilters(List<_CommitmentItem> items) {
    if (!_filter.isActive) return items;
    return items.where((item) {
      if (_filter.subCategory != null) {
        // فئة "مستند" الفرعية مجموعات عرض (وثائق شخصية/ضمانات/مستندات
        // عامة) وليست أنواع إدخال منفصلة، فتُطابَق عبر حقل "نوع المستند"
        // داخل التفاصيل بدل مطابقة نوع الإدخال نفسه.
        final documentGroup = _documentSubtypeGroups[_filter.subCategory];
        if (documentGroup != null) {
          if (item.entryType != 'مستند' ||
              !documentGroup.contains(item.details['نوع المستند'] ?? '')) {
            return false;
          }
        } else if (_medicineTimeFilters.contains(_filter.subCategory)) {
          // فلاتر الوقت للأدوية: اليوم، القادم، المكتمل، منتهي.
          final today = DateTime.now();
          final day = DateTime(today.year, today.month, today.day);
          final from = _parseDayValue(item.details['من تاريخ'] ?? '');
          final to = _parseDayValue(item.details['إلى تاريخ'] ?? '');
          switch (_filter.subCategory) {
            case 'اليوم':
              final started = from == null || !from.isAfter(day);
              final notEnded = to == null || !to.isBefore(day);
              if (!started || !notEnded) return false;
            case 'القادم':
              if (from == null || !from.isAfter(day)) return false;
            case 'المكتمل':
              if (item.status != _statusCompleted &&
                  item.status != 'مؤرشف') {
                return false;
              }
            case 'منتهي':
              if (to == null || !to.isBefore(day)) return false;
          }
        } else if (item.entryType != _filter.subCategory) {
          return false;
        }
      }
      if (!_filter.matchesDate(_parseDueDate(item.dueDate) ?? _itemDate(item))) {
        return false;
      }
      // المحذوف مكانه سلة المهملات، فلا يظهر في أي قائمة هنا.
      if (item.status == TrashStore.status) return false;
      // المؤرشف يختفي من العرض الافتراضي ولا يظهر إلا بفلتر «مؤرشف».
      if (item.status == 'مؤرشف' && _filter.status != 'مؤرشف') return false;
      switch (_filter.status) {
        // قائمة «الحالة ▼» الجديدة.
        case 'قريبة الاستحقاق':
          if (_effectiveStatus(item) != _statusDueSoon) return false;
        case 'مستحقة':
          if (!_isOpenItem(item) || !_isDueToday(item)) return false;
        case 'متأخرة':
          if (_effectiveStatus(item) != _statusOverdue) return false;
        case 'مكتملة':
          if (item.status != _statusCompleted) return false;
        case 'المستحق بعد 7 أيام':
          if (_effectiveStatus(item) != _statusDueSoon) return false;
        case 'نشط':
          if (_effectiveStatus(item) != _statusActive &&
              !_isActiveCustody(item)) {
            return false;
          }
        case 'مكتمل':
          if (item.status != _statusCompleted) return false;
        case 'متأخر':
          if (_effectiveStatus(item) != _statusOverdue) return false;
        case 'ملغاة':
          if (item.status != 'ملغاة') return false;
        case 'مؤرشف':
          if (item.status != 'مؤرشف') return false;
      }
      if (!_filter.matchesAmount(item.amount)) return false;
      // اختصارات المبلغ: "لي" و"عليّ" تعتمدان على اتجاه الدين المسجَّل.
      switch (_filter.amountShortcut) {
        case 'لي':
          if (!_debtIsForMe(item)) return false;
        case 'عليّ':
          if (!(item.details['نوع الدين'] ?? '').startsWith('ل') ||
              _debtIsForMe(item)) {
            return false;
          }
      }
      if (_filter.documentName.isNotEmpty) {
        final matchesDoc = AppFilterValues.textMatches(_filter.documentName, [
          item.title,
          item.details['اسم المستند'] ?? '',
          item.details['نوع المستند'] ?? '',
        ]);
        if (!matchesDoc) return false;
      }
      if (_filter.documentState != null) {
        if (item.entryType != 'مستند') return false;
        final expiry = _parseDueDate(item.dueDate);
        final today = DateUtils.dateOnly(DateTime.now());
        switch (_filter.documentState) {
          case 'قريب الانتهاء':
          case 'مستندات قريبة الانتهاء':
            if (expiry == null ||
                expiry.isBefore(today) ||
                expiry.difference(today).inDays > 30) {
              return false;
            }
          case 'منتهي':
          case 'مستندات منتهية':
            if (expiry == null || !expiry.isBefore(today)) return false;
          case 'مسودة':
            if (expiry != null) return false;
        }
      }
      if (_filter.personName.isNotEmpty) {
        final matchesPerson = AppFilterValues.textMatches(_filter.personName, [
          item.title,
          item.details['اسم الجهة'] ?? '',
          item.details['اسم المستلم'] ?? '',
          item.details['الجهة'] ?? '',
          item.details['اسم المفوَّض'] ?? '',
        ]);
        if (!matchesPerson) return false;
      }
      if (_filter.delegateName.isNotEmpty) {
        final matchesDelegate = AppFilterValues.textMatches(
          _filter.delegateName,
          [item.details['اسم المفوَّض'] ?? '', item.title],
        );
        if (item.entryType != 'تفويض' || !matchesDelegate) return false;
      }
      // العملة: عملة السجل، وبلا عملة = عملة التطبيق.
      if (_filter.currency != null) {
        if (item.currency != _filter.currency) return false;
      }
      // طريقة الدفع.
      if (_filter.paymentMethod != null) {
        final method = (item.details['طريقة الدفع'] ?? '').trim();
        final kind = method.contains('نقد') || method.contains('كاش')
            ? 'نقدًا'
            : method.contains('تحويل')
            ? 'تحويل بنكي'
            : method.contains('بطاقة')
            ? 'بطاقة بنكية'
            : method.contains('محفظة')
            ? 'محفظة إلكترونية'
            : method.isEmpty
            ? ''
            : 'أخرى';
        if (kind != _filter.paymentMethod) return false;
      }
      // الأدوية: اليوم، القادمة، المنتهية — من «من/إلى تاريخ» في الدواء.
      if (_filter.medicineState != null) {
        if (item.entryType != 'أدوية') return false;
        final today = DateUtils.dateOnly(DateTime.now());
        final from = _parseDayValue(item.details['من تاريخ'] ?? '');
        final to = _parseDayValue(item.details['إلى تاريخ'] ?? '');
        switch (_filter.medicineState) {
          case 'أدوية اليوم':
            final started = from == null || !from.isAfter(today);
            final notEnded = to == null || !to.isBefore(today);
            if (!started || !notEnded) return false;
          case 'أدوية قادمة':
            if (from == null || !from.isAfter(today)) return false;
          case 'أدوية منتهية':
            if (to == null || !to.isBefore(today)) return false;
        }
      }
      // الدين: «لي» أو «عليّ» حسب اتجاه الدين المسجَّل.
      switch (_filter.debtDirection) {
        case 'لي':
          if (!_debtIsForMe(item)) return false;
        case 'عليّ':
          if (!(item.details['نوع الدين'] ?? '').startsWith('ل') ||
              _debtIsForMe(item)) {
            return false;
          }
      }
      if (_filter.placeName.isNotEmpty) {
        // مقصور على إدخالات المواقع: حقل "العنوان" مستعمل أيضًا في المصروف
        // والإيراد والدين، فبحث اسم المكان كان يسحب معه إدخالات مالية.
        final matchesPlace =
            item.entryType == 'مواقع وأماكن' &&
            AppFilterValues.textMatches(_filter.placeName, [
              item.title,
              item.details['اسم الموقع'] ?? '',
              item.details['العنوان'] ?? '',
            ]);
        if (!matchesPlace) return false;
      }
      return true;
    }).toList();
  }

  // مصدر الحقيقة الوحيد لتصنيف كل نوع إدخال ضمن إحدى الفئات السبع.
  // يُستخدم في: عرض/فلترة القائمة، عدّاد الفئات، وتحديد category عند الحفظ.
  static const Map<String, String> _entryTypeCategorySlug = {
    // مالية
    'المصروفات الشخصية': 'financial',
    'مصروف': 'financial', // اسم قديم — لبيانات سُجّلت قبل توحيد المسميات
    'إيراد': 'financial',
    'تحويل مالي': 'financial',
    'دين / قرض / سلفة': 'financial',
    'قسط': 'financial',
    'غرامة': 'financial',
    // مستند
    'مستند': 'document',
    // تنظيم ومتابعة
    'مهمة': 'organization',
    'موعد': 'organization',
    'عادة': 'organization',
    'ملاحظات': 'organization',
    'متابعة': 'organization',
    'تسجيل / تخطيط': 'organization',
    'تجديد': 'organization',
    'تفويض': 'organization',
    'تذكير': 'organization',
    // أدوية وبيانات وكلمات سر
    'أدوية': 'medical_accounts',
    'كلمات سر': 'medical_accounts',
    'أدوية وبياناتها': 'medical_accounts', // أسماء قديمة
    'حسابات': 'medical_accounts',
    'الحسابات والبيانات': 'medical_accounts',
    'كلمات السر': 'medical_accounts',
    'الإيميلات': 'medical_accounts',
    'الحسابات البنكية': 'medical_accounts',
    // نمط حياة
    'مناسبة': 'lifestyle',
    'اشتراك': 'lifestyle',
    'اشتراكات': 'lifestyle',
    'هدية': 'lifestyle',
    'عطاء': 'lifestyle', // اسم قديم لنفس النوع (هدية)، للتوافق مع بيانات سابقة
    'جمعية': 'lifestyle',
    // مواقع وأماكن
    'مواقع وأماكن': 'location',
    // عهدة مالية
    'عهدة مالية': 'custody',
  };

  static const Map<String, String> _categorySlugFilterLabel = {
    'financial': 'مالية',
    'document': 'مستند',
    'organization': 'المتابعة والتخطيط',
    'medical_accounts': 'أدوية وبيانات وكلمات سر',
    'lifestyle': 'نمط الحياة',
    'location': 'مواقع وأماكن',
    'custody': 'عهدة مالية',
  };

  // ---------------- تخصيص الصفحة ----------------

  static const String _pc = PageCustomizationStore.personal;

  /// فئة الالتزام كما تظهر في شريط الفئات، من نوع إدخاله.
  static String? _categoryOfType(String? entryType) =>
      _categorySlugFilterLabel[_entryTypeCategorySlug[entryType]];

  /// نوع مخفي داخل فئته من «تخصيص الصفحات».
  static bool _typeHidden(String category, String type) =>
      PageCustomizationStore.itemHidden(_pc, category, type);

  /// الالتزام مخفي إن أُخفيت فئته أو نوعه (والمستند بمجموعة نوعه).
  static bool _hiddenByCustomization(String? entryType, String docType) {
    final category = _categoryOfType(entryType);
    if (category == null) return false;
    if (PageCustomizationStore.categoryHidden(_pc, category)) return true;
    if (category == 'مستند') {
      for (final group in _documentSubtypeGroups.entries) {
        if (group.value.contains(docType)) {
          return _typeHidden(category, group.key);
        }
      }
      return false;
    }
    return _typeHidden(category, entryType ?? '');
  }

  bool _itemHidden(_CommitmentItem item) => _hiddenByCustomization(
    item.entryType,
    item.details['نوع المستند'] ?? '',
  );

  bool _entryTypeMatches(String? entryType, String filter) {
    final slug = _entryTypeCategorySlug[entryType];
    return slug != null && _categorySlugFilterLabel[slug] == filter;
  }

  // عنوان القائمة: اسم الفئة المختارة، أو الفئة الفرعية إن وُجدت. كان
  // يظهر مكرَّرًا في سطر ملخّص فوق القائمة وفي رأسها معًا؛ بقي في الرأس
  // وحده لأنه المثبَّت عند التمرير ومعه العدد وزر الترتيب.
  String _categorySummaryLabel() {
    if (_advFilterSubType != null) return _advFilterSubType!;
    return _selectedEntryType == 'الكل'
        ? 'جميع الالتزامات'
        : _selectedEntryType;
  }

  List<_CommitmentItem> _itemsForSelectedEntryType() {
    final visible = _items.where((item) => !_itemHidden(item));
    if (_selectedEntryType == 'الكل') return List.of(visible);
    return visible
        .where((item) => _entryTypeMatches(item.entryType, _selectedEntryType))
        .toList();
  }

  DateTime _itemDate(_CommitmentItem item) {
    if (item.lastUpdate.trim() == 'الآن') return DateTime.now();
    // «17/10/2026 14:32»: التاريخ ثم الساعة — بالساعة يكون الأحدث في
    // اليوم نفسه أعلى (عهدتان في يوم واحد مثلًا).
    final raw = (item.lastUpdate.isEmpty ? item.dueDate : item.lastUpdate)
        .trim();
    final pieces = raw.split(' ');
    final parts = pieces.first.split('/');
    if (parts.length != 3) return DateTime(1970);
    final first = int.tryParse(parts[0]) ?? 1;
    final second = int.tryParse(parts[1]) ?? 1;
    final third = int.tryParse(parts[2]) ?? 1970;
    var hour = 0;
    var minute = 0;
    if (pieces.length > 1) {
      final clock = pieces[1].split(':');
      hour = int.tryParse(clock.first) ?? 0;
      minute = clock.length > 1 ? (int.tryParse(clock[1]) ?? 0) : 0;
    }
    return first > 31
        ? DateTime(first, second, third, hour, minute)
        : DateTime(third, second, first, hour, minute);
  }

  DateTime? _parseDueDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  // الحالة الفعلية للالتزام لأغراض مركز المتابعة، محسوبة من تاريخ الاستحقاق
  // (لا تُخزَّن في قاعدة البيانات، تُحسب فقط عند العرض). الحالات النهائية
  // (مكتملة/مؤرشف) تبقى كما هي. عتبة "قريبة الاستحقاق" = 7 أيام، حسب تعريف
  // ملف المتطلبات ("المستحق بعد 7 أيام").
  /// حالات منتهية: لا تُعدّ متأخرة ولا قريبة ولا مفتوحة.
  static const Set<String> _closedStatuses = {
    _statusCompleted,
    'مؤرشف',
    'ملغاة',
    'تمت التسوية',
    'محذوف',
  };

  String _effectiveStatus(_CommitmentItem item) {
    if (_closedStatuses.contains(item.status)) {
      return item.status;
    }
    final due = _parseDueDate(item.dueDate);
    if (due == null) return item.status;
    final days = due
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    if (days < 0) return _statusOverdue;
    // يوم الاستحقاق نفسه «مستحقة» فقط، لا «قريبة الاستحقاق» أيضًا.
    if (days == 0) return 'مستحقة';
    if (days <= 7) return _statusDueSoon;
    return _statusActive;
  }

  bool _isDueToday(_CommitmentItem item) {
    final due = _parseDueDate(item.dueDate);
    if (due == null) return false;
    final today = DateUtils.dateOnly(DateTime.now());
    return due.year == today.year &&
        due.month == today.month &&
        due.day == today.day;
  }

  bool _isOpenItem(_CommitmentItem item) =>
      !_closedStatuses.contains(item.status);

  // عدد الطلبات (تفويض وغيره) بانتظار إجراء، من كل الالتزامات بغض النظر عن
  // الفئة المختارة حاليًا — يُستخدم في تنبيه الشاشة الرئيسية وفي بند
  // "طلباتي" داخل مركز المتابعة.
  int _pendingRequestsCount() => _items
      .where((i) => _isOpenItem(i) && _requestEntryTypes.contains(i.entryType))
      .length;

  // يبني بيانات مركز المتابعة الكاملة مقسّمة إلى 6 مجموعات تطابق ملف
  // المتطلبات: الاستحقاقات، العمليات المالية، التجديدات والانتهاءات،
  // المهام والإجراءات، المواعيد، والمتابعة الخاصة.
  List<_FollowUpGroupData> _buildFollowUpGroups() {
    // ثابت في كل الفئات: يعرض دائمًا كل الالتزامات، أيًّا كانت الفئة
    // المختارة في الأعلى.
    // المحذوف (في السلة) لا يظهر في مركز المتابعة.
    final items = _items.where((i) => i.status != 'محذوف').toList();
    final today = DateUtils.dateOnly(DateTime.now());

    // أنواع كل مجموعة كما في الملف المعتمد لمركز المتابعة.
    const organizationTypes = {
      'مهمة',
      'موعد',
      'عادة',
      'تذكير',
      'ملاحظات',
      'متابعة',
      'تسجيل / تخطيط',
      'تجديد',
      'تفويض',
    };
    const financialTypes = {
      'المصروفات الشخصية',
      'مصروف',
      'إيراد',
      'تحويل مالي',
      'دين / قرض / سلفة',
      'قسط',
      'غرامة',
      'جمعية',
    };
    const lifestyleTypes = {
      'مناسبة',
      'هدية',
      'اشتراك',
      'اشتراكات',
    };

    /// تاريخ انتهاء العنصر: حقل الانتهاء إن وُجد، وإلا تاريخ الاستحقاق.
    DateTime? endDateOf(_CommitmentItem item) =>
        _parseDayValue(item.details['إلى تاريخ'] ?? '') ??
        _parseDayValue(item.details['تاريخ الانتهاء'] ?? '') ??
        _parseDueDate(item.dueDate);

    List<_CommitmentItem> byType(Set<String> types) => items
        .where((i) => _isOpenItem(i) && types.contains(i.entryType))
        .toList(growable: false);

    // الملاحظات بلا موعد، والعادة وما يتكرر يتجدد موعده: لا يُعدّان
    // «متأخرة» في المتابعة والتخطيط.
    bool noDeadline(_CommitmentItem i) {
      final repeat = (i.details['التكرار'] ?? '').trim();
      final repeating = repeat.isNotEmpty &&
          !repeat.contains('بدون') &&
          !repeat.contains('لا يتكرر') &&
          repeat != 'لا';
      return i.entryType == 'ملاحظات' || i.entryType == 'عادة' || repeating;
    }

    List<_CommitmentItem> overdueOf(Set<String> types) => byType(types)
        .where(
          (i) =>
              !(identical(types, organizationTypes) && noDeadline(i)) &&
              _effectiveStatus(i) == _statusOverdue,
        )
        .toList(growable: false);

    List<_CommitmentItem> todayOf(Set<String> types) =>
        byType(types).where(_isDueToday).toList(growable: false);

    List<_CommitmentItem> soonOf(Set<String> types) => byType(types)
        .where((i) => _effectiveStatus(i) == _statusDueSoon)
        .toList(growable: false);

    /// المنتهي: تجاوز تاريخ انتهائه اليوم.
    List<_CommitmentItem> expiredOf(String type) => items
        .where((i) {
          if (!_isOpenItem(i) || i.entryType != type) return false;
          final end = endDateOf(i);
          return end != null && end.isBefore(today);
        })
        .toList(growable: false);

    /// قريب الانتهاء: يبقى له [days] يومًا أو أقل.
    List<_CommitmentItem> expiringOf(String type, int days) => items
        .where((i) {
          if (!_isOpenItem(i) || i.entryType != type) return false;
          final end = endDateOf(i);
          if (end == null || end.isBefore(today)) return false;
          return end.difference(today).inDays <= days;
        })
        .toList(growable: false);

    // العهدة: المستنفدة ما صُرف كامل مبلغها، والقريبة ما بقي منها 20% فأقل.
    final custodyItems = items
        .where((i) => i.entryType == 'عهدة مالية')
        .toList(growable: false);
    final custodyDrained = custodyItems.where((i) {
      final spent = _custodyTotalSpent(i.details);
      return i.totalAmount > 0 && spent >= i.totalAmount;
    }).toList(growable: false);
    final custodyNearlyDrained = custodyItems.where((i) {
      if (i.totalAmount <= 0) return false;
      final spent = _custodyTotalSpent(i.details);
      final remaining = i.totalAmount - spent;
      if (remaining <= 0) return false;
      return remaining <= (i.totalAmount * 0.2);
    }).toList(growable: false);

    // الطلبات: ما وصلني بالرقم التعريفي بانتظار قبولي، وما أرسلته أنا
    // وينتظر قبول الطرف الآخر.
    final myId = AppIdentity.id;
    final incoming = _pendingCustodyInvites
        .where(items.contains)
        .toList(growable: false);
    final outgoing = items.where((i) {
      if (myId.isEmpty || !_sharedEntryTypes.contains(i.entryType)) {
        return false;
      }
      final assignment = CustodyAssignment.decode(i.details);
      return assignment.isPending && assignment.ownerId == myId;
    }).toList(growable: false);

    return [
      _FollowUpGroupData(
        title: 'الطلبات',
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFA6691A),
        metrics: [
          _FollowUpSubMetric(
            label: 'بانتظار قبولي',
            icon: Icons.move_to_inbox_outlined,
            items: incoming,
          ),
          _FollowUpSubMetric(
            label: 'أرسلتها بانتظار القبول',
            icon: Icons.outbox_outlined,
            items: outgoing,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'المتابعة والتخطيط',
        icon: Icons.checklist_rounded,
        color: const Color(0xFF0E7161),
        metrics: [
          _FollowUpSubMetric(
            label: 'متأخرة',
            icon: Icons.error_outline_rounded,
            items: overdueOf(organizationTypes),
          ),
          _FollowUpSubMetric(
            label: 'حان وقتها',
            icon: Icons.today_outlined,
            items: todayOf(organizationTypes),
          ),
          _FollowUpSubMetric(
            label: 'قريبة',
            icon: Icons.hourglass_bottom_rounded,
            items: soonOf(organizationTypes),
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'مالية (عام)',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF34A894),
        metrics: [
          _FollowUpSubMetric(
            label: 'متأخرة',
            icon: Icons.error_outline_rounded,
            items: overdueOf(financialTypes),
          ),
          _FollowUpSubMetric(
            label: 'مستحقة',
            icon: Icons.payments_outlined,
            items: todayOf(financialTypes),
          ),
          _FollowUpSubMetric(
            label: 'قريبة الاستحقاق',
            icon: Icons.hourglass_bottom_rounded,
            items: soonOf(financialTypes),
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'أدوية',
        icon: Icons.medication_outlined,
        color: const Color(0xFFC4392E),
        metrics: [
          _FollowUpSubMetric(
            label: 'منتهية',
            icon: Icons.event_busy_outlined,
            items: expiredOf('أدوية'),
          ),
          _FollowUpSubMetric(
            label: 'قريبة الانتهاء',
            icon: Icons.hourglass_top_rounded,
            items: expiringOf('أدوية', 7),
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'مستندات (عام)',
        icon: Icons.description_outlined,
        color: const Color(0xFFCE8422),
        metrics: [
          _FollowUpSubMetric(
            label: 'منتهية',
            icon: Icons.assignment_late_outlined,
            items: expiredOf('مستند'),
          ),
          _FollowUpSubMetric(
            label: 'قريبة الانتهاء',
            icon: Icons.event_busy_outlined,
            items: expiringOf('مستند', 30),
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'نمط الحياة',
        icon: Icons.celebration_outlined,
        color: const Color(0xFFA6691A),
        metrics: [
          _FollowUpSubMetric(
            label: 'متأخرة',
            icon: Icons.error_outline_rounded,
            items: overdueOf(lifestyleTypes),
          ),
          _FollowUpSubMetric(
            label: 'حان وقتها',
            icon: Icons.today_outlined,
            items: todayOf(lifestyleTypes),
          ),
          _FollowUpSubMetric(
            label: 'قريبة',
            icon: Icons.hourglass_bottom_rounded,
            items: soonOf(lifestyleTypes),
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'عهدة مالية',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0A5A50),
        metrics: [
          _FollowUpSubMetric(
            label: 'مستنفدة',
            icon: Icons.money_off_csred_outlined,
            items: custodyDrained,
          ),
          _FollowUpSubMetric(
            label: 'قريبة الاستنفاد',
            icon: Icons.trending_down_rounded,
            items: custodyNearlyDrained,
          ),
        ],
      ),
    ];
  }

  // أنواع الإدخال التي تمثّل "طلبًا" ينتظر إجراء (وليس مجرد التزام عادي) —
  // التفويض حاليًا هو المثال الوحيد، وأي نوع طلب جديد يُضاف مستقبلًا يكفي
  // إدراجه هنا ليظهر تلقائيًا ضمن بند "طلباتي" في مركز المتابعة.
  static const Set<String> _requestEntryTypes = {'تفويض'};

  /// رتبة العنصر ضمن الفلتر الصغير: 0 مطابق فيتقدّم، 1 غير مطابق.
  ///
  /// الفلتر الصغير لا يُخفي شيئًا بل يُقدّم المطابق — فيبقى المستخدم يرى
  /// قائمته كاملة ولا يظنّ أن بياناته اختفت.
  int _quickSortRank(_CommitmentItem item, String label) {
    final today = DateUtils.dateOnly(DateTime.now());
    final due = _parseDueDate(item.dueDate);
    switch (label) {
      case 'نشط':
        return _effectiveStatus(item) == _statusActive ||
                _isActiveCustody(item)
            ? 0
            : 1;
      case 'قريب الإستحقاق':
        return _effectiveStatus(item) == _statusDueSoon ? 0 : 1;
      case 'مكتمل':
        return item.status == _statusCompleted ? 0 : 1;
      case 'ملغاة':
        return item.status == 'ملغاة' ? 0 : 1;
      case 'مستندات قريبة الانتهاء':
      case 'مستندات قريبة الإنتهاء':
        if (item.entryType != 'مستند' || due == null) return 1;
        final days = due.difference(today).inDays;
        return days >= 0 && days <= 30 ? 0 : 1;
      case 'مستندات منتهية':
        if (item.entryType != 'مستند' || due == null) return 1;
        return due.isBefore(today) ? 0 : 1;
      // الأدوية: يُقدَّم ما يُؤخذ اليوم، أو ما لم يبدأ بعد، أو ما انتهى.
      // كل حالة داخل كتلة مستقلة: حالات switch تتشارك النطاق في دارت.
      case 'أدوية اليوم':
        {
          if (item.entryType != 'أدوية') return 1;
          final start = _parseDayValue(item.details['من تاريخ'] ?? '');
          final end = _parseDayValue(item.details['إلى تاريخ'] ?? '');
          final started = start == null || !start.isAfter(today);
          final notEnded = end == null || !end.isBefore(today);
          return started && notEnded ? 0 : 1;
        }
      case 'أدوية قادمة':
        {
          if (item.entryType != 'أدوية') return 1;
          final start = _parseDayValue(item.details['من تاريخ'] ?? '');
          return start != null && start.isAfter(today) ? 0 : 1;
        }
      case 'أدوية منتهية':
        {
          if (item.entryType != 'أدوية') return 1;
          final end = _parseDayValue(item.details['إلى تاريخ'] ?? '');
          return end != null && end.isBefore(today) ? 0 : 1;
        }
      default:
        return 1;
    }
  }

  void _openNewEntrySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4EAE8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: AppTr.uiDir,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'اختيار نوع الإضافة',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'اختر الفئة ثم نوع الإضافة المناسب',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5C6B68),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2F6F5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Color(0xFF46534F),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.62,
                        // المخفي من «تخصيص الصفحات» لا يُضاف.
                        children: _entryCategories
                            .where(
                              (category) =>
                                  !PageCustomizationStore.categoryHidden(
                                    _pc,
                                    category.title,
                                  ) &&
                                  category.types.any(
                                    (type) => !_typeHidden(
                                      category.title,
                                      type.label,
                                    ),
                                  ),
                            )
                            .map(
                              (category) => _EntryCategoryCard(
                                category: category,
                                onTap: () => _openEntryTypesSheet(category),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openEntryTypesSheet(_EntryCategory category) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4EAE8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: AppTr.uiDir,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: category.color,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: category.color.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          category.icon,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              category.title,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${category.types.length} نوع إدخال',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5C6B68),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2F6F5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Color(0xFF46534F),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.82,
                        children: category.types
                            .where(
                              (type) => !_typeHidden(category.title, type.label),
                            )
                            .map(
                              (type) => _EntryTypeCard(
                                type: type,
                                color: category.color,
                                onTap: () {
                                  Navigator.pop(context);
                                  final form = _financialEntryForms[type.label];
                                  if (form == null) {
                                    // لا يُغلق الاختيار بصمت: نوع بلا نموذج
                                    // يجب أن يُبلَّغ عنه لا أن يبدو معطّلًا.
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'نموذج «${type.label}» غير متوفر بعد',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  Future<void>.delayed(
                                    Duration.zero,
                                    () => _openFinancialEntryForm(form),
                                  );
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// هل يُعرض هذا الحقل الآن؟
  static bool _isFieldVisible(
    _FinancialField field,
    Map<String, TextEditingController> controllers,
  ) {
    // التصنيف الفرعي لم يعد حقلًا مستقلًا: صار جزءًا من منتقي التصنيف
    // الواحد، فإظهاره هنا يعني سؤال المستخدم مرتين عن الشيء نفسه.
    if (field.label == 'التصنيف الفرعي') return false;
    if (field.hidden) return false;
    // «التكرار» يتبع مفتاح «تفعيل عملية متكررة» في النماذج التي فيها
    // المفتاح فقط؛ أما النماذج التي تستعمل التكرار وحده (اشتراك، مهمة،
    // موعد، عادة، تذكير، تجديد) فيظهر فيها دائمًا.
    // بلا تفعيل العملية المتكررة لا يظهر التكرار ولا يوم التنفيذ.
    // نماذج التنظيم والمتابعة: التكرار وساعة التذكير يتبعان مفتاح التذكير.
    // الأدوية: كل نمط جرعات يكشف حقله الخاص فقط، والتذكير المسبق يتبع
    // مفتاح التذكيرات.
    if (controllers.containsKey('نمط الجرعات')) {
      final pattern = controllers['نمط الجرعات']!.text.trim();
      if (field.label == 'كل كم ساعة') {
        return pattern == 'كل عدد من الساعات';
      }
      if (field.label == 'أيام الأسبوع') {
        return pattern == 'أيام أسبوع محددة';
      }
      if (field.label == 'كل كم يوم') {
        return pattern == 'كل عدد من الأيام';
      }
      if (field.label == 'تواريخ مخصصة') {
        return pattern == 'تواريخ مخصصة';
      }
    }
    if (field.label == 'التذكير قبل الموعد' &&
        controllers.containsKey('تفعيل التذكيرات')) {
      return controllers['تفعيل التذكيرات']!.text == 'نعم';
    }
    if ((field.label == 'التكرار' || field.label == 'وقت التذكير') &&
        controllers.containsKey('تفعيل تذكير')) {
      return controllers['تفعيل تذكير']!.text == 'نعم';
    }
    if ((field.label == 'التكرار' || field.label == 'اليوم') &&
        controllers.containsKey('تفعيل عملية متكررة')) {
      return controllers['تفعيل عملية متكررة']!.text == 'نعم';
    }
    return true;
  }

  Future<void> _openFinancialEntryForm(
    _FinancialEntryForm form, {
    _CommitmentItem? editing,
    bool newCourse = false,
    _CommitmentItem? copyFrom,
    bool sameVisit = false,
    void Function(PersonalEntryRecord record)? onSaved,
  }) async {
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in form.fields) field.label: TextEditingController(),
      // حقل نصّي مرافق لكل قائمة اختيار، يظهر عند اختيار "+ إضافة أخرى".
      // بدونه كان الخيار يُحفظ حرفيًا كنص "+ إضافة أخرى" في طريقة الدفع
      // والتكرار بلا أي وسيلة لكتابة القيمة الحقيقية.
      for (final field in form.fields)
        if (field.kind == _FinancialFieldKind.select)
          '${field.label} (مخصص)': TextEditingController(),
    };
    // تعديل البيانات: نفس نموذج الإضافة مملوءًا بالبيانات الحالية (ومثله
    // «بدء عهدة جديدة» من بيانات عهدة سابقة).
    final source = editing ?? copyFrom;
    if (source != null) {
      for (final field in form.fields) {
        final target = controllers[field.label];
        if (target == null) continue;
        var value = source.details[field.label] ?? '';
        if (value.isEmpty && field.isTitle) value = source.title;
        // تعديل عهدة أو دين: المبلغ الحالي (بعد الزيادات)، لا قيمته الأولى —
        // وإلا أعاد الحفظ المبلغ القديم وأسقط الزيادات.
        if (editing != null &&
            field.isAmount &&
            _sharedEntryTypes.contains(form.label) &&
            source.totalAmount != 0) {
          value = '${source.totalAmount}';
        } else if (value.isEmpty &&
            field.isAmount &&
            source.totalAmount != 0) {
          value = '${source.totalAmount}';
        }
        // وقت التذكير المحفوظ («قبل 3 ساعة») ← الخيار المخصص وعدده؛ وقيمة
        // قديمة على شكل ساعة تُترك فارغة.
        if (field.label == 'وقت التذكير' &&
            field.kind == _FinancialFieldKind.select) {
          final (option, number) = reminderLeadSplit(value);
          controllers['${field.label} (مخصص)']?.text = number;
          value = option;
        }
        if (field.kind == _FinancialFieldKind.select &&
            value.isNotEmpty &&
            field.label != 'التصنيف الرئيسي' &&
            !field.options.contains(value)) {
          final companion = controllers['${field.label} (مخصص)'];
          if (companion != null && field.options.contains('مخصص')) {
            companion.text = _kReminderLabels.contains(field.label)
                ? RegExp(r'\d+').firstMatch(value)?.group(0) ?? value
                : value;
            value = 'مخصص';
          } else if (companion != null && field.allowCustom) {
            companion.text = value;
            value = '+ إضافة أخرى';
          }
        }
        target.text = value;
      }
    }
    // دواء آخر من نفس الوصفة: كل البيانات كما هي (الطبيب، الفترة،
    // الجرعات، التذكير)، ويُكتب اسم الدواء وجرعته فقط.
    if (sameVisit && copyFrom != null) {
      for (final label in _perMedicineFields) {
        controllers[label]?.text = '';
      }
    }
    // العهدة الجديدة: نفس البيانات، والتاريخ اليوم وحالتها من جديد.
    if ((copyFrom != null && !sameVisit) ||
        (newCourse && form.label == 'عهدة مالية')) {
      final today = DateTime.now();
      for (final field in form.fields) {
        if (field.kind == _FinancialFieldKind.date) {
          controllers[field.label]?.text =
              '${today.day}/${today.month}/${today.year}';
        }
      }
      controllers['حالة العهدة']?.text = '';
    }
    // العملة: تبدأ بالعملة الافتراضية للتطبيق، ويغيّرها المستخدم لهذا
    // السجل وحده إن شاء.
    final currencyController = controllers['العملة'];
    if (currencyController != null && currencyController.text.trim().isEmpty) {
      currencyController.text = AppSettings.currencySuffix;
    }
    XFile? attachment;
    var isSaving = false;
    var showAdditionalFields = false;
    // وضع إدخال الموقع لنوع "مواقع وأماكن" فقط: استخدام الموقع الحالي
    // (مؤقتًا يملأ الحقل بنص ثابت لحين إضافة صلاحيات GPS لاحقًا) | إضافة
    // من رابط | إدخال يدوي. لا يغيّر منطق الحفظ، فقط يوجّه المستخدم.
    var locationMode = 'manual';
    // عند إضافة "عهدة مالية": نجلب أسماء الأشخاص المحفوظين مسبقًا (نفس
    // قائمة "المفوَّضين") لعرضها كاختيار سريع في حقل "اسم المستلم" بدل
    // الكتابة اليدوية في كل مرة.
    final isCustodyForm = form.label == 'عهدة مالية';
    if (isCustodyForm) _knownIdentities = await _loadKnownIdentities();
    // الدين والقسط: اختيار الطرف من «الأفراد والجهات» مع بياناته.
    final isPartyForm =
        form.label == 'دين / قرض / سلفة' || form.label == 'قسط';
    var savedPeopleNames = const <String>[];
    if (isCustodyForm) {
      savedPeopleNames = await _loadSavedPeopleNames();
    } else if (isPartyForm) {
      final entries = await PeopleDirectoryStore.load();
      _partyDirectory = {
        for (final entry in entries)
          if (entry.fullName.trim().isNotEmpty) entry.fullName.trim(): entry,
      };
      final saved = await _loadSavedPeopleNames();
      savedPeopleNames = [
        ..._partyDirectory.keys,
        ...saved.where((name) => !_partyDirectory.containsKey(name)),
      ];
    }
    // الحقول الإضافية تبقى للأدوية وكلمات السر فقط.
    // الفتح المباشر من تفاصيل فرد: قيم معبّأة مسبقًا.
    if (editing == null) {
      widget.prefill.forEach((label, value) {
        controllers[label]?.text = value;
      });
    }
    final keepAdditional = form.label == 'أدوية' || form.label == 'كلمات سر';
    // القسط: خانة لكل قسط بتاريخه، ومبلغه إن لم تكن الأقساط متساوية.
    final instDates = <TextEditingController>[];
    final instAmounts = <TextEditingController>[];
    final instRemoved = <TextEditingController>[];
    var equalSplit = editing?.details['تقسيم القسط بالتساوي'] != 'لا';
    void syncInstallments() {
      final count =
          (int.tryParse(controllers['عدد الأقساط']?.text.trim() ?? '') ?? 0)
              .clamp(0, 120);
      while (instDates.length < count) {
        // عند التعديل: «القسط N» محفوظ بصيغة «التاريخ — المبلغ العملة».
        final saved = editing?.details['القسط ${instDates.length + 1}'] ?? '';
        final parts = saved.split(' — ');
        instDates.add(TextEditingController(text: parts.first.trim()));
        instAmounts.add(
          TextEditingController(
            text: parts.length > 1
                ? (RegExp(r'[\d.]+').firstMatch(parts[1])?.group(0) ?? '')
                : '',
          ),
        );
      }
      while (instDates.length > count) {
        instRemoved
          ..add(instDates.removeLast())
          ..add(instAmounts.removeLast());
      }
    }

    // بالتساوي: الإجمالي ÷ عدد الأقساط، والفرق (إن وُجد) على آخر قسط.
    String fmtAmount(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    void autoSplit() {
      if (!equalSplit || instAmounts.isEmpty) return;
      final total =
          double.tryParse(controllers['المبلغ الإجمالي']?.text.trim() ?? '') ??
          0;
      if (total <= 0) return;
      final count = instAmounts.length;
      final each = (total / count * 100).floorToDouble() / 100;
      for (var i = 0; i < count; i++) {
        final value = i == count - 1 ? total - each * (count - 1) : each;
        instAmounts[i].text = fmtAmount(value);
      }
    }

    String dmy(DateTime d) => '${d.day}/${d.month}/${d.year}';
    DateTime? parseDmy(String value) {
      final parts = value.trim().split('/');
      if (parts.length != 3) return null;
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day == null || month == null || year == null) return null;
      return DateTime(year, month, day);
    }
    if (!mounted) return;
    PersonalEntryRecord? savedRecord;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.92,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: Directionality(
                  textDirection: AppTr.uiDir,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EAE8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: form.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(form.icon, color: form.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      editing == null
                                          ? 'إضافة ${form.label}'
                                          : newCourse
                                          ? (form.label == 'عهدة مالية'
                                                ? 'بدء عهدة جديدة — ${editing.title}'
                                                : 'بدء كورس جديد — ${editing.title}')
                                          : 'تعديل بيانات ${form.label}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF022E2A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 14,
                                      ),
                                      child: Text(
                                        form.subtitle,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5C6B68),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: AppTr.tr('إغلاق'),
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _buildFormSectionTitle(
                            'الحقول الأساسية',
                            Icons.edit_note_rounded,
                          ),
                          const SizedBox(height: 12),
                          if (form.label == 'مواقع وأماكن') ...[
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children:
                                  const [
                                        (
                                          'current',
                                          'أنا في المكان الآن',
                                          Icons.my_location_rounded,
                                        ),
                                        (
                                          'link',
                                          'لصق رابط خرائط جوجل',
                                          Icons.link_rounded,
                                        ),
                                        (
                                          'manual',
                                          'كتابة العنوان بنفسي',
                                          Icons.edit_location_alt_outlined,
                                        ),
                                      ]
                                      .map(
                                        (mode) => ChoiceChip(
                                          label: Text(mode.$2),
                                          avatar: Icon(mode.$3, size: 16),
                                          selected: locationMode == mode.$1,
                                          // «أنا في المكان الآن» يجلب الموقع
                                          // فورًا بلا ضغطة ثانية.
                                          onSelected: (_) async {
                                            setModalState(
                                              () => locationMode = mode.$1,
                                            );
                                            // «لصق رابط خرائط جوجل» يلصق
                                            // الرابط المنسوخ فعلًا.
                                            if (mode.$1 == 'link') {
                                              final link =
                                                  await pasteMapsLink(context);
                                              if (link == null) return;
                                              setModalState(
                                                () =>
                                                    controllers['الموقع أو الرابط']!
                                                            .text =
                                                        link,
                                              );
                                              return;
                                            }
                                            if (mode.$1 != 'current') return;
                                            final value =
                                                await _fetchCurrentLocation(
                                                  context,
                                                );
                                            if (value == null) return;
                                            setModalState(
                                              () =>
                                                  controllers['الموقع أو الرابط']!
                                                          .text =
                                                      value,
                                            );
                                          },
                                        ),
                                      )
                                      .toList(),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              switch (locationMode) {
                                'current' =>
                                  'وأنت داخل المكان: يُحفظ موقعك الحالي من GPS الجوال في «الموقع أو الرابط».',
                                'link' =>
                                  'افتح المكان في خرائط جوجل ← مشاركة ← نسخ الرابط، ثم الصقه في «الموقع أو الرابط».',
                                _ => 'اكتب العنوان أو وصف الطريق بنفسك في الحقول.',
                              },
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.6,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5C6B68),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (locationMode == 'link')
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final link = await pasteMapsLink(context);
                                  if (link == null) return;
                                  setModalState(
                                    () =>
                                        controllers['الموقع أو الرابط']!.text =
                                            link,
                                  );
                                },
                                icon: const Icon(Icons.content_paste_rounded),
                                label: const Text('لصق الرابط المنسوخ'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: form.color,
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            if (locationMode == 'current')
                              InkWell(
                                onTap: () async {
                                  final value = await _fetchCurrentLocation(
                                    context,
                                  );
                                  if (value == null) return;
                                  setModalState(() {
                                    controllers['الموقع أو الرابط']!.text =
                                        value;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: form.color.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: form.color),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.my_location_rounded,
                                        color: form.color,
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'جلب موقعي الآن مرة أخرى',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1C2C29),
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_left_rounded,
                                        color: Color(0xFF8C9A97),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          if (form.label == 'مناسبة' ||
                              form.label == 'مواقع وأماكن') ...[
                            AppRemovableAttachment(
                              attached: attachment != null,
                              onRemove: () => setModalState(() => attachment = null),
                              child: InkWell(
                              onTap: () async {
                                try {
                                  final image = await DocumentStore.pickXFile(context, imageQuality: 82, allowFiles: false);
                                  if (image == null || !context.mounted) return;
                                  setModalState(() => attachment = image);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تعذر فتح المعرض — تحقق من إذن الوصول '
                                        'إلى الصور',
                                      ),
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: form.color.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: attachment == null
                                        ? const Color(0xFFE4EAE8)
                                        : form.color,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      attachment == null
                                          ? Icons.add_a_photo_outlined
                                          : Icons.check_circle_rounded,
                                      color: form.color,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        attachment == null
                                            ? (form.label == 'مواقع وأماكن'
                                                  ? 'اختيار صورة للمكان'
                                                  : 'اختيار صورة للمناسبة')
                                            : (form.label == 'مواقع وأماكن'
                                                  ? 'تم اختيار صورة المكان'
                                                  : 'تم اختيار صورة المناسبة'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1C2C29),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_left_rounded,
                                      color: Color(0xFF8C9A97),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          ..._buildFieldRows(
                            form.fields
                                .where(
                                  (field) =>
                                      field.isPrimary &&
                                      _isFieldVisible(field, controllers),
                                )
                                .toList(growable: false),
                            entryLabel: form.label,
                            controllers: controllers,
                            setModalState: setModalState,
                            savedPeopleNames: savedPeopleNames,
                          ),
                          // جدول الأقساط: خيار التقسيم بالتساوي ثم خانة لكل قسط.
                          if (form.label == 'قسط') ...[
                            // يُزامَن عدد الخانات قبل بنائها في القائمة نفسها.
                            ...(() {
                              syncInstallments();
                              autoSplit();
                              return const <Widget>[];
                            })(),
                            if ((int.tryParse(
                                      controllers['عدد الأقساط']?.text.trim() ??
                                          '',
                                    ) ??
                                    0) >
                                0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.field,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.rField,
                                  ),
                                ),
                                child: Row(
                                  textDirection: AppTr.uiDir,
                                  children: [
                                    const Icon(
                                      Icons.call_split_rounded,
                                      size: 20,
                                      color: Color(0xFF34A894),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'تقسيم القسط بالتساوي',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1C2C29),
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: equalSplit,
                                      activeThumbColor: const Color(0xFF0E7161),
                                      onChanged: (value) => setModalState(
                                        () => equalSplit = value,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (
                                var i = 0;
                                i < instDates.length &&
                                    i <
                                        (int.tryParse(
                                              controllers['عدد الأقساط']!.text
                                                  .trim(),
                                            ) ??
                                            0);
                                i++
                              ) ...[
                                Row(
                                  textDirection: AppTr.uiDir,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 62,
                                      height: 46,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: form.color.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${AppTr.tr('القسط')} ${i + 1}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w900,
                                          color: form.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: instDates[i],
                                        readOnly: true,
                                        style: _kFieldTextStyle,
                                        decoration: _expenseInputDecoration(
                                          'تاريخ القسط',
                                          Icons.event_outlined,
                                          half: true,
                                          hint: 'تاريخ القسط ${i + 1}',
                                        ),
                                        onTap: () async {
                                          final previous = i > 0
                                              ? parseDmy(instDates[i - 1].text)
                                              : null;
                                          final now = DateTime.now();
                                          final initial =
                                              parseDmy(instDates[i].text) ??
                                              (previous == null
                                                  ? now
                                                  : _addMonthsClamped(
                                                      previous,
                                                      1,
                                                    ));
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: initial,
                                            firstDate: DateTime(now.year - 20),
                                            lastDate: DateTime(now.year + 30),
                                          );
                                          if (picked == null) return;
                                          setModalState(() {
                                            instDates[i].text = dmy(picked);
                                            // الخانات الفارغة بعده تُملأ شهريًا
                                            // ويمكن تغيير أي منها.
                                            for (
                                              var j = i + 1;
                                              j < instDates.length;
                                              j++
                                            ) {
                                              if (instDates[j].text
                                                  .trim()
                                                  .isNotEmpty) {
                                                continue;
                                              }
                                              // 31 يناير ← 28 فبراير، لا 3 مارس.
                                              instDates[j].text = dmy(
                                                _addMonthsClamped(
                                                  picked,
                                                  j - i,
                                                ),
                                              );
                                            }
                                          });
                                        },
                                        validator: trValidator((value) =>
                                            value == null || value.trim().isEmpty
                                            ? 'اختر تاريخ القسط'
                                            : null),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // مبلغ كل قسط: يُملأ بالتساوي ويمكن تعديله
                                    // (التعديل يوقف التقسيم التلقائي).
                                    Expanded(
                                      child: TextFormField(
                                              controller: instAmounts[i],
                                              onChanged: (_) => setModalState(
                                                () => equalSplit = false,
                                              ),
                                              style: _kFieldTextStyle,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration:
                                                  _expenseInputDecoration(
                                                    'المبلغ',
                                                    Icons.payments_outlined,
                                                    half: true,
                                                    suffixText: AppSettings
                                                        .currencySuffix,
                                                  ),
                                              validator: trValidator((value) =>
                                                  double.tryParse(
                                                        (value ?? '').trim(),
                                                      ) ==
                                                      null
                                                  ? 'أدخل المبلغ'
                                                  : null),
                                            ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
                              Builder(
                                builder: (_) {
                                  final total =
                                      double.tryParse(
                                        controllers['المبلغ الإجمالي']!.text
                                            .trim(),
                                      ) ??
                                      0;
                                  var sum = 0.0;
                                  for (final c in instAmounts) {
                                    sum += double.tryParse(c.text.trim()) ?? 0;
                                  }
                                  final matches = (sum - total).abs() < 0.01;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      '${AppTr.tr('مجموع الأقساط')}: '
                                      '${fmtAmount(sum)} ${AppTr.tr('من')} '
                                      '${fmtAmount(total)} '
                                      '${AppSettings.currencyOf(controllers['العملة']?.text)}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: matches
                                            ? const Color(0xFF0E7161)
                                            : const Color(0xFFC4392E),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                          // «الحقول الإضافية» بلا عنوانها: محتوياتها ظاهرة
                          // مباشرة تحت الأساسية (عدا الأدوية وكلمات السر).
                          if (!keepAdditional)
                            ..._buildFieldRows(
                              form.fields
                                  .where(
                                    (field) =>
                                        !field.isPrimary &&
                                        _isFieldVisible(field, controllers),
                                  )
                                  .toList(growable: false),
                              entryLabel: form.label,
                              controllers: controllers,
                              setModalState: setModalState,
                              savedPeopleNames: savedPeopleNames,
                            ),
                          if (keepAdditional)
                          InkWell(
                            onTap: () => setModalState(
                              () =>
                                  showAdditionalFields = !showAdditionalFields,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
                              child: Row(
                                children: [
                                  // العنوان الوحيد بالأسود في النموذج،
                                  // والسهم أسود مثله.
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                    color: AppTheme.title,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'الحقول الإضافية',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.title,
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: showAdditionalFields ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: AppTheme.title,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (keepAdditional && showAdditionalFields)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ..._buildFieldRows(
                                    form.fields
                                        .where(
                                          (field) =>
                                              !field.isPrimary &&
                                              _isFieldVisible(
                                                field,
                                                controllers,
                                              ),
                                        )
                                        .toList(growable: false),
                                    entryLabel: form.label,
                                    controllers: controllers,
                                    setModalState: setModalState,
                                    savedPeopleNames: savedPeopleNames,
                                  ),
                                  AppRemovableAttachment(
                                    attached: attachment != null,
                                    onRemove: () => setModalState(() => attachment = null),
                                    child: OutlinedButton.icon(
                                    onPressed: () async {
                                      try {
                                        final image = await DocumentStore.pickXFile(context, imageQuality: 82);
                                        if (image == null ||
                                            !context.mounted) {
                                          return;
                                        }
                                        setModalState(
                                          () => attachment = image,
                                        );
                                      } catch (_) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'تعذر فتح المعرض — تحقق من إذن '
                                              'الوصول إلى الصور',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: Icon(
                                      attachment == null
                                          ? Icons.attach_file_rounded
                                          : Icons.check_circle_rounded,
                                    ),
                                    label: Text(
                                      attachment == null
                                          ? 'إرفاق مستند'
                                          : 'تم إرفاق المستند',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: form.color,
                                      side: BorderSide(color: form.color),
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                                    ),
                                  ),
                                  ),
                                ],
                              ),
                            ),
                          // بلا «الحقول الإضافية»: إرفاق المستند ظاهر مباشرة.
                          if (!keepAdditional) ...[
                            AppRemovableAttachment(
                              attached: attachment != null,
                              onRemove: () => setModalState(() => attachment = null),
                              child: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  final image = await DocumentStore.pickXFile(context, imageQuality: 82);
                                  if (image == null || !context.mounted) {
                                    return;
                                  }
                                  setModalState(() => attachment = image);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تعذر فتح المعرض — تحقق من إذن '
                                        'الوصول إلى الصور',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: Icon(
                                attachment == null
                                    ? Icons.attach_file_rounded
                                    : Icons.check_circle_rounded,
                              ),
                              label: Text(
                                attachment == null
                                    ? 'إرفاق مستند'
                                    : 'تم إرفاق المستند',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: form.color,
                                side: BorderSide(color: form.color),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.rField,
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!(formKey.currentState?.validate() ??
                                        false)) {
                                      return;
                                    }
                                    // تأكيد أولًا، وبعد الحفظ رسالة «بنجاح».
                                    // دواء جديد: ثلاثة أزرار — «إضافة دواء»
                                    // يحفظ ثم يفتح دواءً آخر بنفس المعلومات.
                                    var addAnother = false;
                                    final medicineNew = editing == null &&
                                        form.label == 'أدوية';
                                    final bool confirmed;
                                    if (medicineNew) {
                                      final choice = await _askMedicineSave(
                                        context,
                                        form,
                                      );
                                      addAnother = choice == 'add';
                                      confirmed = choice != null;
                                    } else {
                                      confirmed = await confirmAction(
                                      context,
                                      title: editing == null
                                          ? 'تأكيد الحفظ'
                                          : newCourse
                                          ? (form.label == 'عهدة مالية'
                                                ? 'بدء عهدة جديدة'
                                                : 'بدء كورس جديد')
                                          : 'تأكيد التعديل',
                                      message: editing == null
                                          ? 'هل تريد حفظ ${_savedLabel(form.label)}؟'
                                          : newCourse
                                          ? (form.label == 'عهدة مالية'
                                                ? 'ستبدأ عهدة جديدة، وتُحفظ الحالية بكل معلوماتها في السجل. هل تريد المتابعة؟'
                                                : 'سيبدأ كورس جديد ويُنقل الحالي إلى السجل. هل تريد المتابعة؟')
                                          : 'هل تريد حفظ تعديل ${_savedLabel(form.label)}؟',
                                      confirmLabel: 'تأكيد',
                                    );
                                    }
                                    if (!confirmed || !context.mounted) {
                                      return;
                                    }
                                    setModalState(() => isSaving = true);
                                    // جدول الأقساط يُحفظ في التفاصيل، والاستحقاق
                                    // = أقرب قسط قادم.
                                    final extra = <String, String>{};
                                    // أدوية الوصفة الواحدة تُجمع بمعرّف أولها.
                                    if (sameVisit && copyFrom != null) {
                                      final group =
                                          (copyFrom.details[_prescriptionGroupKey] ??
                                                  '')
                                              .trim();
                                      extra[_prescriptionGroupKey] =
                                          group.isNotEmpty
                                          ? group
                                          : (copyFrom.id ?? '');
                                    }
                                    String? dueOverride;
                                    if (form.label == 'قسط' &&
                                        instDates.isNotEmpty) {
                                      final dates = <DateTime>[];
                                      final unit = AppSettings.currencyOf(controllers['العملة']?.text);
                                      for (var i = 0; i < instDates.length; i++) {
                                        final date = instDates[i].text.trim();
                                        final amount = instAmounts[i].text.trim();
                                        extra['القسط ${i + 1}'] =
                                            '$date — $amount $unit';
                                        final parsed = parseDmy(date);
                                        if (parsed != null) dates.add(parsed);
                                      }
                                      extra['تقسيم القسط بالتساوي'] =
                                          equalSplit ? 'نعم' : 'لا';
                                      if (dates.isNotEmpty) {
                                        dates.sort();
                                        extra['تاريخ القسط الأول'] =
                                            dmy(dates.first);
                                        extra['تاريخ آخر قسط'] = dmy(dates.last);
                                        final today = DateUtils.dateOnly(
                                          DateTime.now(),
                                        );
                                        dueOverride = dmy(
                                          dates.firstWhere(
                                            (d) => !d.isBefore(today),
                                            orElse: () => dates.last,
                                          ),
                                        );
                                      }
                                    }
                                    try {
                                      await _saveFinancialEntry(
                                        form,
                                        controllers,
                                        attachment,
                                        extraDetails: extra,
                                        dueDateOverride: dueOverride,
                                        editing: editing,
                                        newCourse: newCourse,
                                        onSaved: (record) {
                                          savedRecord = record;
                                          onSaved?.call(record);
                                        },
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                      // دواء جديد: عرض إضافة دواء آخر من نفس
                                      // الوصفة بنفس البيانات.
                                      final created = savedRecord;
                                      if (editing == null &&
                                          form.label == 'أدوية' &&
                                          created != null &&
                                          addAnother) {
                                        _offerSamePrescription(
                                          form,
                                          created,
                                          onSaved,
                                        );
                                      }
                                      // رسالة الحفظ بعد إغلاق النموذج حتى تُرى.
                                      if (mounted) {
                                        ScaffoldMessenger.of(this.context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                editing == null
                                                    ? 'تم حفظ ${_savedLabel(form.label)} بنجاح'
                                                    : newCourse
                                                    ? (form.label ==
                                                              'عهدة مالية'
                                                          ? 'بدأت عهدة جديدة، والسابقة في السجل'
                                                          : 'بدأ كورس جديد، والسابق في السجل')
                                                    : 'تم حفظ التعديل بنجاح',
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                      }
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _saveErrorMessage(error),
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (context.mounted) {
                                        setModalState(() => isSaving = false);
                                      }
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              isSaving
                                  ? 'جارٍ الحفظ...'
                                  : editing == null
                                  ? 'حفظ ${form.label}'
                                  : 'حفظ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: form.color,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      for (final controller in [
        ...controllers.values,
        ...instDates,
        ...instAmounts,
        ...instRemoved,
      ]) {
        controller.dispose();
      }
    });
  }

  Widget _buildFormSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF0A5A50)),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C2C29),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFFE4EAE8))),
      ],
    );
  }

  /// يبني الحقول صفًّا صفًّا، ويجمع كل حقلين بنصف عرض في سطر واحد.
  /// الحقول النصفية ضيّقة، فالعنوان يُكتب فوق الحقل — على سطرين إن لزم —
  /// بدل قصّه داخله («وحدة الجرعة» لا «وحدة الج..»).
  Widget _withOuterLabel(_FinancialField field, Widget child) {
    if (!field.half) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, end: 6, bottom: 5),
          child: Text(
            field.required ? '${field.shown} *' : field.shown,
            textAlign: AppTr.alignEnd,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: AppTheme.muted,
            ),
          ),
        ),
        child,
      ],
    );
  }

  List<Widget> _buildFieldRows(
    List<_FinancialField> fields, {
    required String entryLabel,
    required Map<String, TextEditingController> controllers,
    required StateSetter setModalState,
    List<String> savedPeopleNames = const [],
  }) {
    final rows = <Widget>[];
    var i = 0;
    while (i < fields.length) {
      final field = fields[i];
      final next = i + 1 < fields.length ? fields[i + 1] : null;
      if (field.half && next != null && next.half) {
        rows.add(
          Row(
            textDirection: AppTr.uiDir,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _withOuterLabel(
                  field,
                  _buildDynamicField(
                    field,
                    controllers[field.label]!,
                    entryLabel: entryLabel,
                    controllers: controllers,
                    setModalState: setModalState,
                    savedPeopleNames: savedPeopleNames,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _withOuterLabel(
                  next,
                  _buildDynamicField(
                    next,
                    controllers[next.label]!,
                    entryLabel: entryLabel,
                    controllers: controllers,
                    setModalState: setModalState,
                    savedPeopleNames: savedPeopleNames,
                  ),
                ),
              ),
            ],
          ),
        );
        i += 2;
      } else {
        rows.add(
          _buildDynamicField(
            field,
            controllers[field.label]!,
            entryLabel: entryLabel,
            controllers: controllers,
            setModalState: setModalState,
            savedPeopleNames: savedPeopleNames,
          ),
        );
        i += 1;
      }
      rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  /// مستطيل «اعتماد المصروفات» في نموذج العهدة المالية.
  Widget _custodyApprovalBox(
    TextEditingController approval,
    StateSetter setModalState,
  ) {
    const green = Color(0xFF0E7161);
    final on = approval.text.trim() == _custodyApprovalRequired;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: on ? const Color(0x120E7161) : AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(
          color: on ? green : AppTheme.hairline,
          width: on ? 1.3 : 1,
        ),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Icon(
            on ? Icons.verified_rounded : Icons.verified_outlined,
            size: 21,
            color: on ? green : AppTheme.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يحتاج المصروف موافقة صاحب العهدة لاعتماده',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  on
                      ? 'كل مصروف يرسله المستلم يصلك لتعتمده أو ترفضه، ولا يُخصم من العهدة قبل اعتماده.'
                      : 'مصروفات المستلم تُخصم من العهدة مباشرة بلا موافقة.',
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: green,
            onChanged: (value) => setModalState(
              () => approval.text = value
                  ? _custodyApprovalRequired
                  : _custodyApprovalNone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicField(
    _FinancialField field,
    TextEditingController controller, {
    required String entryLabel,
    required Map<String, TextEditingController> controllers,
    required StateSetter setModalState,
    List<String> savedPeopleNames = const [],
  }) {
    // ربط العهدة المالية بشخص: بدل كتابة "اسم المستلم" يدويًا، يمكن
    // الاختيار من قائمة الأشخاص المحفوظين مسبقًا (نفس قائمة "المفوَّضين")
    // أو كتابة اسم جديد وسيُحفظ تلقائيًا بعد الحفظ الناجح.
    // العهدة: خانة واحدة للمستلم — يُختار من السهم إن كان معروفًا، أو يُكتب
    // رقمه التعريفي فيظهر اسمه تلقائيًا. الاسم وحده، بلا هاتف ولا عنوان.
    if (entryLabel == 'عهدة مالية' && field.label == 'اسم المستلم') {
      final idController = controllers[_custodyHolderIdLabel]!;
      final known = _knownIdentities;
      final typedId = AppIdentity.normalize(idController.text);
      final resolved = known[typedId];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: idController,
            style: _kFieldTextStyle,
            textCapitalization: TextCapitalization.characters,
            decoration:
                _expenseInputDecoration(
                  'المستلم (الرقم التعريفي)',
                  Icons.badge_outlined,
                  required: true,
                  hint: 'FND-XXXX-XXXX',
                ).copyWith(
                  helperText: fndNameHint(),
                  helperMaxLines: 3,
                  // اختيار المستلم من «الأفراد والجهات» (ومن سبق التعامل
                  // معهم بالرقم التعريفي).
                  suffixIcon: IconButton(
                    tooltip: AppTr.tr('اختر من الأفراد والجهات'),
                    icon: const Icon(
                      Icons.person_search_outlined,
                      color: Color(0xFF0E7161),
                    ),
                    onPressed: () async {
                      final picked = await _pickCustodyPerson(known);
                      if (picked == null || !mounted) return;
                      setModalState(() {
                        controller.text = picked.name;
                        idController.text = picked.id;
                        if (picked.id.isNotEmpty) {
                          _knownIdentities = {
                            ..._knownIdentities,
                            picked.id: picked.name,
                          };
                        }
                      });
                      if (picked.id.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${AppTr.tr('اكتب الرقم التعريفي لـ')} ${picked.name}',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),
            onChanged: (value) => setModalState(() {
              final name = known[AppIdentity.normalize(value)];
              if (name != null) controller.text = name;
            }),
            validator: trValidator((value) {
              final id = AppIdentity.normalize(value ?? '');
              if (id.isEmpty) return 'يرجى إدخال الرقم التعريفي للمستلم';
              if (!AppIdentity.isValid(id)) return 'الصيغة الصحيحة FND-XXXX-XXXX';
              if (id == AppIdentity.id) return 'لا يمكن إسناد العهدة إلى نفسك';
              return null;
            }),
          ),
          const SizedBox(height: 6),
          if (resolved != null)
            Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: Color(0xFF0E7161),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${AppTr.tr('المستلم')}: $resolved',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                ),
              ],
            )
          else if (AppIdentity.isValid(typedId)) ...[
            const SizedBox(height: 4),
            TextFormField(
              controller: controller,
              style: _kFieldTextStyle,
              decoration: _expenseInputDecoration(
                'اسم المستلم',
                Icons.person_outline_rounded,
                required: true,
                hint: 'رقم جديد — اكتب اسمه مرة واحدة',
              ),
              validator: trValidator((value) => value == null || value.trim().isEmpty
                  ? 'يرجى إدخال اسم المستلم'
                  : null),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'يُربط المستلم بالعهدة المالية برقمه التعريفي ويصله طلب قبول. '
            'يظهر اسمه فقط — لا يُشارك رقم هاتفه ولا عنوانه إلا بموافقته.',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.muted,
            ),
          ),
          // هل يحتاج المصروف الذي يرسله المستلم موافقة صاحب العهدة؟
          if (controllers[_custodyApprovalLabel] != null) ...[
            const SizedBox(height: 10),
            _custodyApprovalBox(
              controllers[_custodyApprovalLabel]!,
              setModalState,
            ),
          ],
        ],
      );
    }
    if ((entryLabel == 'دين / قرض / سلفة' && field.label == 'اسم الجهة') ||
        (entryLabel == 'قسط' && field.label == 'الجهة')) {
      return TextFormField(
        controller: controller,
        decoration:
            _expenseInputDecoration(
              field.shown,
              field.icon,
              required: field.required,
              hint: field.hint,
              half: field.half,
            ).copyWith(
          suffixIcon: savedPeopleNames.isEmpty
              ? null
              : Directionality(
                  textDirection: AppTr.uiDir,
                  child: PopupMenuButton<String>(
                    tooltip: AppTr.tr('اختر من الأسماء المحفوظة'),
                    icon: const Icon(
                      Icons.arrow_drop_down_circle_outlined,
                      color: Color(0xFF0E7161),
                    ),
                    position: PopupMenuPosition.under,
                    color: Colors.white,
                    surfaceTintColor: Colors.white,
                    shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                    onSelected: (value) => setModalState(() {
                      controller.text = value;
                      // شخص مسجّل في الأفراد والجهات: تُملأ بياناته المحفوظة.
                      final person = _partyDirectory[value];
                      if (person == null) return;
                      void fill(String key, List<String> from) {
                        final target = controllers[key];
                        final saved = person.firstOf(from);
                        if (target != null &&
                            target.text.trim().isEmpty &&
                            saved.isNotEmpty) {
                          target.text = saved;
                        }
                      }

                      fill('رقم الهاتف', [
                        'رقم الهاتف',
                        'رقم الجوال',
                        'الجوال',
                        'الهاتف',
                      ]);
                      fill('البريد الإلكتروني', [
                        'البريد الإلكتروني',
                        'الإيميل',
                        'البريد',
                      ]);
                    }),
                    itemBuilder: (context) => [
                      for (final name in savedPeopleNames)
                        PopupMenuItem<String>(
                          value: name,
                          child: Directionality(
                            textDirection: AppTr.uiDir,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline_rounded,
                                  size: 18,
                                  color: Color(0xFF0E7161),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2C3B38),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        validator: trValidator((value) {
          if (field.required && (value == null || value.trim().isEmpty)) {
            return 'يرجى إدخال ${field.label}';
          }
          return null;
        }),
      );
    }
    // حقل التصنيف الواحد: يحلّ محلّ قائمتَي "التصنيف الرئيسي" و"الفرعي".
    // المستخدم في الغالب يعرف الفرعي مباشرة ("تطبيقات توصيل") ولا يريد أن
    // يتذكّر تحت أي رئيسي يقع، فصارت قائمة واحدة قابلة للبحث تُبيّن لكل
    // بند: أهو رئيسي أم فرعي وممّن.
    // عنوان قسم داخل النموذج: نص أسود عريض يفصل مجموعة حقول عمّا قبلها.
    if (field.kind == _FinancialFieldKind.header) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(field.icon, size: 18, color: AppTheme.title),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                field.label,
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
          ],
        ),
      );
    }
    // مفتاح تشغيل/إطفاء بدل قائمة «نعم/لا».
    if (field.kind == _FinancialFieldKind.toggle) {
      final on = controller.text == 'نعم';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.field,
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(field.icon, size: 20, color: const Color(0xFF34A894)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                field.label,
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C2C29),
                ),
              ),
            ),
            Switch.adaptive(
              value: on,
              activeThumbColor: const Color(0xFF0E7161),
              onChanged: (value) => setModalState(() {
                controller.text = value ? 'نعم' : '';
                if (!value) controllers['التكرار']?.text = '';
              }),
            ),
          ],
        ),
      );
    }

    // حقل العنوان: أيقونة موقع في طرف السطر تجلب الإحداثيات من الجوال.
    if ((field.isTitle && field.label == 'العنوان') ||
        field.label == 'الموقع أو الرابط') {
      final geo = controllers['الموقع الجغرافي'];
      return TextFormField(
        controller: controller,
        decoration:
            _expenseInputDecoration(
              field.shown,
              field.icon,
              required: field.required,
              hint: field.hint,
              half: field.half,
            ).copyWith(
          suffixIcon: geo == null
              ? null
              : IconButton(
                  tooltip: AppTr.tr('جلب الموقع الحالي'),
                  icon: Icon(
                    geo.text.trim().isEmpty
                        ? Icons.my_location_rounded
                        : Icons.location_on_rounded,
                    color: geo.text.trim().isEmpty
                        ? const Color(0xFF8C9A97)
                        : const Color(0xFF0E7161),
                  ),
                  onPressed: () async {
                    final value = await _fetchCurrentLocation(context);
                    if (value == null) return;
                    setModalState(() => geo.text = value);
                  },
                ),
        ),
        validator: trValidator((value) {
          if (field.required && (value == null || value.trim().isEmpty)) {
            return 'يرجى إدخال ${field.label}';
          }
          return null;
        }),
      );
    }

    if (field.label == 'التصنيف الرئيسي') {
      final mainController = controllers['التصنيف الرئيسي']!;
      final subController = controllers['التصنيف الفرعي'];
      return CategoryPickerField(
        title: 'التصنيف',
        required: field.required,
        // الغرامة تصنيفها الرئيسي واحد ("غرامات")، فالمعنى كله في الفرعي
        // (مرور/حكومية/مالية...) ولذلك يبقى إلزاميًا كما كان قبل التوحيد.
        requireSub: entryLabel == 'غرامة',
        allowCustom: field.allowCustom,
        accent: const Color(0xFF0E7161),
        main: mainController.text,
        sub: subController?.text,
        groups: [
          for (final main in field.options)
            CategoryGroup(
              main: main,
              subs: _subcategoriesForEntry(entryLabel, main)
                  .where((sub) => sub != '+ إضافة أخرى')
                  .toList(growable: false),
            ),
        ],
        onChanged: (picked) => setModalState(() {
          mainController.text = picked.main;
          subController?.text = picked.sub ?? '';
        }),
      );
    }
    if (field.kind == _FinancialFieldKind.select) {
      // التصنيفان (الرئيسي والفرعي) لهما منتقيهما الخاص أعلاه، فما يصل
      // إلى هنا هو بقية القوائم فقط.
      final options = [
        ...field.options,
        if (field.allowCustom && !field.options.contains('+ إضافة أخرى'))
          '+ إضافة أخرى',
      ];
      final value = options.contains(controller.text) ? controller.text : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            alignment: AlignmentDirectional.centerEnd,
            // نفس خط حقول الكتابة بالضبط: القائمة كانت ترث خط الثيم
            // الأكبر فتبدو «وحدة الجرعة» أكبر من «وقت الجرعة».
            style: _kFieldTextStyle,
            iconEnabledColor: AppTheme.title,
            iconDisabledColor: AppTheme.title,
            decoration: _expenseInputDecoration(
              field.shown,
              field.icon,
              required: field.required,
              hint: field.hint,
              half: field.half,
            ),
            items: options
                .map(
                  (option) => DropdownMenuItem(
                    value: option,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      option,
                      textAlign: TextAlign.right,
                      style: _kFieldTextStyle,
                    ),
                  ),
                )
                .toList(),
            onChanged: (selected) =>
                setModalState(() => controller.text = selected ?? ''),
            validator: trValidator((selected) {
              if (field.required &&
                  (selected == null || selected.trim().isEmpty)) {
                return 'يرجى اختيار ${field.label}';
              }
              return null;
            }),
          ),
          // القوائم (طريقة الدفع، التكرار، ...) تحصل على حقل نصّي عند
          // اختيار "+ إضافة أخرى".
          if ((controller.text == '+ إضافة أخرى' ||
                  controller.text == 'مخصص' ||
                  controller.text == kLeadCustomHours ||
                  controller.text == kLeadCustomDays) &&
              controllers['${field.label} (مخصص)'] != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: controllers['${field.label} (مخصص)'],
              keyboardType: _kReminderLabels.contains(field.label) ||
                      field.label == 'وقت التذكير'
                  ? TextInputType.number
                  : null,
              decoration: _expenseInputDecoration(
                controller.text == kLeadCustomHours
                    ? 'كم ساعة قبل الموعد؟'
                    : (_kReminderLabels.contains(field.label) ||
                          controller.text == kLeadCustomDays)
                    ? 'كم يومًا قبل الموعد؟'
                    : '${field.shown} — القيمة الجديدة',
                Icons.add_rounded,
              ),
              validator: trValidator((text) => text == null || text.trim().isEmpty
                  ? 'يرجى إدخال ${field.label}'
                  : null),
            ),
          ],
        ],
      );
    }
    return TextFormField(
      controller: controller,
      style: _kFieldTextStyle,
      // القسط: العدد والقيمة يحدّثان جدول الأقساط فورًا.
      onChanged:
          entryLabel == 'قسط' &&
              (field.label == 'عدد الأقساط' ||
                  field.label == 'المبلغ الإجمالي')
          ? (_) => setModalState(() {})
          : null,
      readOnly:
          field.kind == _FinancialFieldKind.date ||
          field.kind == _FinancialFieldKind.time,
      obscureText: field.kind == _FinancialFieldKind.secret,
      keyboardType: field.kind == _FinancialFieldKind.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      minLines: field.kind == _FinancialFieldKind.multiline ? 3 : 1,
      maxLines: field.kind == _FinancialFieldKind.multiline ? 4 : 1,
      textInputAction: field.kind == _FinancialFieldKind.multiline
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: _expenseInputDecoration(
        field.shown,
        field.icon,
        required: field.required,
        half: field.half,
        hint: field.label == _custodyHolderIdLabel
            ? 'FND-XXXX-XXXX'
            : field.hint == '#auto'
            ? 'أوصف $entryLabel'
            : field.hint,
        // عملة النموذج نفسه (الافتراضية ما لم تُغيَّر لهذا السجل).
        suffixText: field.kind == _FinancialFieldKind.number && field.isAmount
            ? AppSettings.currencyOf(controllers['العملة']?.text)
            : null,
      ).copyWith(
        // خانة الرقم التعريفي: كيف سيظهر اسمي للطرف الآخر.
        helperText:
            field.label == _custodyHolderIdLabel ||
                field.label == _debtHolderIdLabel
            ? fndNameHint()
            : null,
        helperMaxLines: 3,
      ),
      onTap: field.kind == _FinancialFieldKind.time
          ? () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (picked != null) {
                final hour = picked.hour.toString().padLeft(2, '0');
                final minute = picked.minute.toString().padLeft(2, '0');
                controller.text = '$hour:$minute';
              }
            }
          : field.kind == _FinancialFieldKind.date
          ? () async {
              final now = DateTime.now();
              // «إلى تاريخ» يبدأ من «من تاريخ»: لا يُختار ما قبله.
              final startLabel = _dateRangeStart[field.label];
              final start = startLabel == null
                  ? null
                  : _parseDayValue(controllers[startLabel]?.text ?? '');
              final date = await showDatePicker(
                context: context,
                initialDate: start != null && now.isBefore(start) ? start : now,
                firstDate: start ?? DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (date != null) {
                controller.text = '${date.day}/${date.month}/${date.year}';
              }
            }
          : null,
      validator: trValidator((value) {
        if (field.required && (value == null || value.trim().isEmpty)) {
          return 'يرجى إدخال ${field.label}';
        }
        final startLabel = _dateRangeStart[field.label];
        if (startLabel != null && value != null && value.trim().isNotEmpty) {
          final start = _parseDayValue(controllers[startLabel]?.text ?? '');
          final end = _parseDayValue(value);
          if (start != null && end != null && end.isBefore(start)) {
            return '«${field.label}» لا يسبق «$startLabel»';
          }
        }
        final otherTime = _distinctTimes[field.label];
        if (otherTime != null &&
            value != null &&
            value.trim().isNotEmpty &&
            value.trim() == (controllers[otherTime]?.text.trim() ?? '')) {
          return 'يجب أن يختلف عن «$otherTime»';
        }
        // الرقم التعريفي يُقبل بصيغته فقط، ولا يجوز إسناد العهدة للنفس.
        if ((field.label == _custodyHolderIdLabel ||
                field.label == _debtHolderIdLabel) &&
            value != null &&
            value.trim().isNotEmpty) {
          final normalized = AppIdentity.normalize(value);
          if (!AppIdentity.isValid(normalized)) {
            return 'الصيغة الصحيحة FND-XXXX-XXXX';
          }
          if (normalized == AppIdentity.id) {
            return 'لا يمكن إسناد العهدة إلى نفسك';
          }
        }
        if (field.kind == _FinancialFieldKind.number &&
            value != null &&
            value.trim().isNotEmpty) {
          final number = double.tryParse(value.trim());
          if (number == null || number < 0) return 'أدخل رقماً صحيحاً';
        }
        return null;
      }),
    );
  }

  Future<void> _saveFinancialEntry(
    _FinancialEntryForm form,
    Map<String, TextEditingController> controllers,
    XFile? attachment, {
    Map<String, String> extraDetails = const {},
    String? dueDateOverride,
    _CommitmentItem? editing,
    bool newCourse = false,
    void Function(PersonalEntryRecord record)? onSaved,
  }) async {
    String valueFor(bool Function(_FinancialField field) predicate) {
      for (final field in form.fields) {
        if (predicate(field)) return controllers[field.label]!.text.trim();
      }
      return '';
    }

    String labelFor(bool Function(_FinancialField field) predicate) {
      for (final field in form.fields) {
        if (predicate(field)) return field.label;
      }
      return '';
    }

    final amountValue = valueFor((field) => field.isAmount);
    final details = <String, String>{
      for (final field in form.fields)
        if (controllers[field.label]!.text.trim().isNotEmpty)
          field.label: controllers[field.label]!.text.trim(),
      ...extraDetails,
      // ربط البند بفرد عند الإضافة من تفاصيله.
      if (editing == null) ...widget.linkDetails,
    };

    // بقية القوائم: تُستبدل "+ إضافة أخرى" و«مخصص» بالقيمة التي كتبها
    // المستخدم (التذكير المخصص يُحفظ «قبل N يوم»).
    for (final field in form.fields) {
      if (field.kind != _FinancialFieldKind.select) continue;
      final picked = details[field.label];
      // وقت التذكير المخصص: «قبل N ساعة» أو «قبل N يوم».
      if (picked == kLeadCustomHours || picked == kLeadCustomDays) {
        final value = reminderLeadValue(
          picked ?? '',
          controllers['${field.label} (مخصص)']?.text ?? '',
        );
        if (value.isEmpty) {
          details.remove(field.label);
        } else {
          details[field.label] = value;
        }
        continue;
      }
      if (picked != '+ إضافة أخرى' && picked != 'مخصص') continue;
      final custom = controllers['${field.label} (مخصص)']?.text.trim() ?? '';
      if (custom.isEmpty) continue;
      final days = int.tryParse(custom);
      details[field.label] =
          _kReminderLabels.contains(field.label) && days != null && days > 0
          ? _reminderLabelForDays(days)
          : custom;
    }

    if (details.containsKey('العملة')) {
      final stored = AppSettings.currencyToStore(details['العملة']);
      if (stored.isEmpty) {
        details.remove('العملة');
      } else {
        details['العملة'] = stored;
      }
    }

    // العنوان يُقرأ بعد الاستبدال لا قبله: نماذج مثل "غرامة" عنوانها هو
    // التصنيف الفرعي، فكان يُحفظ حرفيًا "+ إضافة أخرى" بدل ما كتبه المستخدم.
    final titleValue = (details[labelFor((field) => field.isTitle)] ?? '')
        .trim();
    // تاريخ الاستحقاق هو ما تُبنى عليه حالة التأخّر والتنبيهات؛ وبدون هذا
    // التفضيل كان الدين يُقيَّم على "تاريخ الدين" لأنه أول حقل تاريخ.
    // العهدة: الاستحقاق تاريخ التسليم إن وُجد (وعليه التذكير).
    // المستند والضمان: تاريخ الانتهاء هو ما يُنبَّه عليه (لا تاريخ الإصدار).
    final dueDateLabel = details.containsKey('تاريخ الاستحقاق')
        ? 'تاريخ الاستحقاق'
        : (details['تاريخ الانتهاء'] ?? '').trim().isNotEmpty
        ? 'تاريخ الانتهاء'
        : (details['تاريخ نهاية التفويض'] ?? '').trim().isNotEmpty
        ? 'تاريخ نهاية التفويض'
        : form.label == 'عهدة مالية' && details.containsKey('تاريخ التسليم')
        ? 'تاريخ التسليم'
        : labelFor((field) => field.kind == _FinancialFieldKind.date);
    final dateValue = (dueDateOverride ?? details[dueDateLabel] ?? '').trim();

    final fallbackTitle = details['التصنيف الفرعي']?.trim().isNotEmpty == true
        ? details['التصنيف الفرعي']!.trim()
        : details['التصنيف الرئيسي']?.trim().isNotEmpty == true
        ? details['التصنيف الرئيسي']!.trim()
        : form.label;

    if (editing != null) {
      // تعديل: تبقى البيانات غير الظاهرة في النموذج (السجلات والإسناد...)،
      // وتُستبدل حقول النموذج بما في النموذج الآن.
      final labels = {for (final field in form.fields) field.label};
      final merged = Map<String, String>.of(editing.details)
        ..removeWhere(
          (key, _) => labels.contains(key) || key.startsWith('القسط '),
        )
        ..addAll(details);
      if (newCourse && form.label == 'عهدة مالية') {
        // العهدة الحالية تنتقل إلى السجل «عهدة رقم N» بكل معلوماتها
        // وصرفياتها، والجديدة تبدأ بلا صرفيات ولا زيادات.
        final log = [..._parseCustodyLog(editing.details)];
        final number =
            int.tryParse(editing.details['رقم العهدة'] ?? '') ??
            log.length + 1;
        final spent = _custodyTotalSpent(editing.details);
        log.add({
          'العهدة': 'عهدة رقم $number',
          for (final field in form.fields)
            if (!field.hidden &&
                (editing.details[field.label] ?? '').trim().isNotEmpty)
              field.label: editing.details[field.label]!.trim(),
          'قيمة العهدة': '${editing.totalAmount}',
          'المصروف': '$spent',
          'المتبقي': '${editing.totalAmount - spent}',
          'الحالة': editing.status,
          if ((editing.details[_custodyTransactionsDetailKey] ?? '').isNotEmpty)
            _custodyTransactionsDetailKey:
                editing.details[_custodyTransactionsDetailKey]!,
          if ((editing.details[CustodyTopUps.key] ?? '').isNotEmpty)
            CustodyTopUps.key: editing.details[CustodyTopUps.key]!,
        });
        merged[_custodyLogKey] = jsonEncode(log);
        merged['رقم العهدة'] = '${number + 1}';
        for (final key in [
          _custodyTransactionsDetailKey,
          _subscriptionPaymentsDetailKey,
          CustodyTopUps.key,
          'تاريخ التسوية',
          'المبلغ المعاد عند التسوية',
          'تاريخ الإلغاء',
        ]) {
          merged.remove(key);
        }
      } else if (newCourse) {
        // الكورس الحالي ينتقل إلى السجل باسم «كورس N»، والجديد = N+1.
        final courses = <Map<String, String>>[];
        try {
          final decoded = jsonDecode(editing.details[_courseLogKey] ?? '[]');
          if (decoded is List) {
            for (final entry in decoded.whereType<Map>()) {
              courses.add(entry.map((k, v) => MapEntry('$k', '$v')));
            }
          }
        } catch (_) {}
        final number =
            int.tryParse(editing.details['رقم الكورس'] ?? '') ??
            courses.length + 1;
        courses.add({
          'الكورس': 'كورس $number',
          for (final field in form.fields)
            if ((editing.details[field.label] ?? '').trim().isNotEmpty)
              field.label: editing.details[field.label]!.trim(),
        });
        merged[_courseLogKey] = jsonEncode(courses);
        merged['رقم الكورس'] = '${number + 1}';
      }
      // تغيّر رقم المستلم في التعديل: إسناد جديد بانتظار قبول الشخص الجديد.
      if (_sharedEntryTypes.contains(form.label)) {
        final idLabel = form.label == 'عهدة مالية'
            ? _custodyHolderIdLabel
            : _debtHolderIdLabel;
        final oldId = AppIdentity.normalize(editing.details[idLabel] ?? '');
        final newId = AppIdentity.normalize(merged[idLabel] ?? '');
        if (newId != oldId) {
          for (final key in CustodyAssignment.keys) {
            merged.remove(key);
          }
          // نسخة مستقلة: الدالة تعيد الخريطة نفسها إن كان الرقم فارغًا أو
          // غير صالح، فيمحوها clear() قبل إعادة إضافتها.
          final reassigned = Map<String, String>.of(
            _withCustodyAssignment(
              form.label,
              merged,
              merged['اسم المستلم'] ?? merged['اسم الجهة'] ?? '',
            ),
          );
          merged
            ..clear()
            ..addAll(reassigned);
        }
      }
      final updated = await _repository.update(
        PersonalEntryRecord(
          id: editing.id,
          category: editing.category,
          entryType: editing.entryType ?? form.label,
          title: titleValue.isEmpty ? fallbackTitle : titleValue,
          amount: amountValue.trim().isEmpty
              ? editing.totalAmount
              : parseAmountInt(amountValue),
          dueDate: dateValue,
          status: newCourse ? _statusActive : editing.status,
          details: merged,
          attachmentUrl: editing.attachmentPath,
        ),
        attachment: attachment,
      );
      if (form.label == 'عهدة مالية') {
        await _rememberIdentity(
          details[_custodyHolderIdLabel] ?? '',
          details['اسم المستلم'] ?? '',
        );
      }
      onSaved?.call(updated);
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _items[index] = _itemFromRecord(updated);
      });
      return;
    }

    final saved = await _repository.create(
      PersonalEntryRecord(
        category: _categoryFor(form.label),
        entryType: form.label,
        title: titleValue.isEmpty ? fallbackTitle : titleValue,
        amount: parseAmountInt(amountValue),
        dueDate: dateValue,
        status: _statusActive,
        details: _withCustodyAssignment(
          form.label,
          details,
          _firstNonEmpty([
            valueFor((field) => field.label == 'اسم المستلم'),
            valueFor((field) => field.label == 'اسم الجهة'),
          ]),
        ),
      ),
      attachment: attachment,
    );
    onSaved?.call(saved);
    if (form.label == 'عهدة مالية') {
      await _rememberIdentity(
        details[_custodyHolderIdLabel] ?? '',
        details['اسم المستلم'] ?? '',
      );
    }
    if (form.label == 'عهدة مالية') {
      final recipientName = valueFor((field) => field.label == 'اسم المستلم');
      if (recipientName.isNotEmpty) {
        await _savePersonName(recipientName);
      }
    }
    if (!mounted) return;
    setState(() {
      _items.insert(0, _itemFromRecord(saved));
      // تصفير الفلاتر كلها، وإلا حُفظ العنصر ولم يظهر في القائمة.
      _selectedEntryType = 'الكل';
      _advFilterSubType = null;
      _filter.clear();
    });
  }

  /// مسح البحث وكل الفلاتر معًا — يستعملها زر القائمة الفارغة وشريحة «الكل».
  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
      _selectedEntryType = 'الكل';
      _advFilterSubType = null;
      _filter.clear();
    });
  }

  String _categoryFor(String entryType) {
    return _entryTypeCategorySlug[entryType] ?? 'organization';
  }


  InputDecoration _expenseInputDecoration(
    String label,
    IconData icon, {
    String? suffixText,
    bool required = false,
    String hint = '',
    bool half = false,
  }) {
    return InputDecoration(
      // الحقل النصفي عنوانه مكتوب فوقه كاملًا، فلا يتكرر داخله ولا يُقصّ.
      // نجمة صغيرة على كل حقل إلزامي ليعرف المستخدم ما لا يصح تركه فارغًا.
      labelText: half || required ? null : label,
      label: !half && required
          ? Text(
              '$label *',
              maxLines: 3,
            )
          : null,
      hintText: half
          ? (hint.isEmpty ? label : hint)
          : (hint.isEmpty ? null : hint),
      // الحقول النصفية ضيّقة: أيقونة أصغر بحيّز أضيق تترك مساحة للعنوان
      // كاملًا بدل قصّه («طري..» بدل «طريقة الدفع»).
      prefixIconConstraints: BoxConstraints(
        minWidth: half ? 32 : 44,
        minHeight: half ? 32 : 44,
      ),
      // خط أصغر وأفتح للعناوين والتلميحات حتى تظهر كاملة في الحقول
      // النصفية بدل أن تُقصّ («طري..» بدل «طريقة الدفع»).
      isDense: true,
      labelStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.brandMid,
      ),
      hintStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppTheme.muted,
      ),
      // لون واحد لكل عناوين الحقول وأيقوناتها؛ الأسود للأسهم وعنوان
      // «الحقول الإضافية» فقط.
      prefixIcon: Icon(icon, size: half ? 17 : 20, color: AppTheme.muted),
      suffixText: suffixText,
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF34A894), width: 1.5),
      ),
    );
  }

  Future<void> _openDetails(
    _CommitmentItem item, {
    bool openEdit = false,
  }) async {
    final wasDeleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PersonalCommitmentDetailsScreen(
          item: item,
          repository: _repository,
          openEditOnStart: openEdit,
          onFullEdit: _openFullEditFor,
          onStartCopy: _openCopyFormFor,
          onSamePrescription: (item) =>
              _openCopyFormFor(item, sameVisit: true),
        ),
      ),
    );
    if (!mounted) return;
    // إعادة تحميل القائمة من قاعدة البيانات دائمًا عند العودة من شاشة
    // التفاصيل: المستخدم قد يكون أضاف عنصرًا جديدًا من زر "+ إضافة" هناك
    // (دفعة/مستند/صورة/مهمة/موعد/عادة/ملاحظات/تجديد/تفويض) أو عدّل الالتزام،
    // وبدون إعادة التحميل هذه لا يظهر أي شيء من ذلك في هذه القائمة إلا بعد
    // إغلاق التطبيق وإعادة فتحه.
    await _loadEntries();
    if (!mounted) return;
    if (wasDeleted == true) {
      _items.removeWhere((existing) => existing.id == item.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم نقل الالتزام إلى سلة المهملات بنجاح'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: AppTr.tr('فتح السلة'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            ),
          ),
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _buildScreenBody(),
      ),
      floatingActionButton: AddFab(
        screenId: 'personal_commitments',
        onPressed: _openNewEntrySheet,
        label: 'إضافة',
        backgroundColor: const Color(0xFF0E7161),
      ),
    );
  }

  // حماية دفاعية: أي خطأ غير متوقّع أثناء بناء محتوى الشاشة كان سابقًا
  // يجعلها تظهر بيضاء فارغة تمامًا (فقط زر الإضافة يبقى ظاهرًا) بدون أي
  // رسالة، ولا يُصلَح إلا بلمس أي عنصر يستدعي إعادة البناء (setState) بشكل
  // عشوائي. الآن أي خطأ من هذا النوع يظهر برسالة واضحة وزر "إعادة المحاولة"
  // بدل الفراغ الصامت، ويُسجَّل في السجل (debugPrint) لتشخيصه لاحقًا.
  Widget _buildScreenBody() {
    try {
      final filtered = _filteredItems();
      // السحب للأسفل يعيد القراءة من الخادم: ما يصرفه الطرف الآخر من عهدة
      // مسندة إليه يصل هنا بلا إعادة فتح الشاشة.
      return RefreshIndicator(
        onRefresh: _loadEntries,
        color: AppTheme.brandMid,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ManagementDashboardHeader(
            title: 'الالتزامات الشخصية',
            subtitle: 'إدارة التزاماتك في مكان واحد',
            icon: Icons.account_balance_wallet_rounded,
            colors: const [Color(0xFF0A5A50), Color(0xFF0A5A50)],
            // لمسة لون الوحدة.
            tint: const Color(0xFF0E7161),
            onSmartCalendarTap: _openSmartCalendar,
            onClose: () => Navigator.of(context).pop(),
          ),
            // مستطيل الوحدة الملوّن: الترويسة والبحث ومركز المتابعة
            // والملخص الشامل بلون الوحدة الخفيف.
            moduleTintedGroup(
              tint: const Color(0xFF0E7161),
              slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
              child: _buildSearchControl(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildRequestsBanner(),
            ),
          ),
          // طلبات العهدة المُسندة إليّ: تظهر أعلى الصفحة حتى أقبل أو أرفض.
          if (_pendingCustodyInvites.isNotEmpty)
            SliverToBoxAdapter(
              child: ColoredBox(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _buildCustodyInvitesBanner(),
                ),
              ),
            ),
          // مركز المتابعة يتحرّك مع الصفحة ويختفي عند النزول لأسفل.
          SliverToBoxAdapter(
            child: ColoredBox(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _buildFollowUpCenter(),
    const SizedBox(height: 8),
    // «الملخص الشامل» لهذا القسم وحده.
    const ModuleSummaryCard(tab: 1, subtitle: 'ملخص الالتزامات الشخصية'),
  ],
),
              ),
            ),
          ),
          // عنوان "الفئات" يمرّ مع الصفحة، وشريط الشرائح وحده هو الذي
          // يثبت في الأعلى.
              ],
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: const Text(
                'الفئات',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2C3B38),
                ),
              ),
            ),
          ),
          MeasuredPinnedHeader(
            background: AppTheme.page,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCategoriesBlock(),
                  const SizedBox(height: 10),
                  // سطر "جميع الالتزامات" مثبَّت مع الفئات: كان ينزلق تحت
                  // الرأس المثبَّت فيبقى المستخدم يرى الفئات بلا عنوان
                  // القائمة ولا زر الترتيب.
                  _buildListHeader(filtered.length),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (filtered.isEmpty)
                  _buildEmptyState()
                else
                  ...filtered.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CommitmentCard(
                        item: item,
                        onTap: () => _openDetails(item),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('personal_commitments_screen build error: $error\n$stackTrace');
      return _buildScreenBodyError();
    }
  }

  Widget _buildScreenBodyError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Color(0xFFA82F26),
            ),
            const SizedBox(height: 12),
            const Text(
              'حدث خطأ غير متوقع أثناء عرض الشاشة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2C3B38),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const ValueKey('personal-commitments-retry'),
              onPressed: _loadEntries,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSmartCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartCalendarScreen()),
    );
  }

  // يحتفظ بآخر 3 عمليات بحث سابقة فقط، حسب طلب المستخدم.
  static const int _maxRecentSearches = 3;

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = prefs.getStringList('personal_recent_searches') ?? const [];
    setState(() {
      _recentSearches = stored.take(_maxRecentSearches).toList(growable: false);
    });
  }

  Future<void> _saveRecentSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    final next = <String>[query, ..._recentSearches.where((item) => item != query)];
    final limited = next.take(_maxRecentSearches).toList(growable: false);
    setState(() => _recentSearches = limited);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('personal_recent_searches', limited);
  }

  Future<void> _removeRecentSearch(String value) async {
    final next = _recentSearches
        .where((item) => item != value)
        .toList(growable: false);
    setState(() => _recentSearches = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('personal_recent_searches', next);
  }

  List<String> _searchSuggestions() {
    // مطابقة موحّدة عربيًا (تتجاهل فروق الهمزة والتاء المربوطة والتشكيل)
    // وترتّب ما يبدأ بالمكتوب أولًا، بدل مطابقة نصية خام كانت تُفشل
    // اقتراح "أحمد" عند كتابة "اح".
    return searchSuggestionsFor(
      query: _searchController.text,
      candidates: _items.map((item) => item.title),
    );
  }

  // قائمة عمليات البحث السابقة/الاقتراحات: تظهر كقائمة رأسية (وليست
  // رقائق متفرّقة) تحت خانة البحث مباشرة، ولا تظهر إلا عندما تكون خانة
  // البحث نفسها مركّزًا عليها (تم الضغط بداخلها)، وتختفي بمجرد فقدان
  // التركيز. عمليات البحث السابقة فقط (وليست نتائج الاقتراح الحيّة) لها
  // زر حذف صغير لإزالتها فردًا فردًا.
  Widget _buildSearchSuggestions() {
    if (!_searchFocusNode.hasFocus) return const SizedBox.shrink();
    final query = _searchController.text.trim();
    final isRecentList = query.length < kSearchSuggestionMinChars;
    final values = isRecentList ? _recentSearches : _searchSuggestions();
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        // قائمة الاقتراحات تطفو فوق القائمة خلفها، فتحتفظ بظل خفيف يفصلها
        // عمّا تحتها — وحده الاستثناء عن قاعدة "بلا ظلال".
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F1F1C),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFF2F6F5)),
              _buildSearchSuggestionRow(values[i], isRecent: isRecentList),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSuggestionRow(String value, {required bool isRecent}) {
    return InkWell(
      key: ValueKey('personal-search-suggestion-$value'),
      onTap: () {
        _searchController.text = value;
        _searchController.selection = TextSelection.collapsed(
          offset: value.length,
        );
        _saveRecentSearch(value);
        _searchFocusNode.unfocus();
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(
              isRecent ? Icons.history_rounded : Icons.search_rounded,
              size: 16,
              color: const Color(0xFF8C9A97),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 3,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3B38),
                ),
              ),
            ),
            if (isRecent)
              InkWell(
                key: ValueKey('personal-search-suggestion-remove-$value'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => _removeRecentSearch(value),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Color(0xFF8C9A97),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// الالتزامات المؤرشفة — مصدر زر «الأرشيف» ونافذته.
  List<_CommitmentItem> get _archivedItems => _items
      .where((item) => item.status == 'مؤرشف')
      .toList(growable: false);

  /// نافذة الأرشيف: إلغاء الأرشفة يعيد الالتزام نشطًا فورًا في القائمة.
  Future<void> _openArchiveSheet() async {
    final changed = await showArchiveSheet(
      context,
      title: 'الالتزامات الشخصية',
      entries: [
        for (final item in _archivedItems)
          ArchiveEntry(
            title: item.title,
            subtitle: item.entryType ?? '',
            icon: item.icon,
            color: item.iconColor,
            onUnarchive: () async {
              final id = item.id;
              if (id == null) return false;
              try {
                await _repository.update(
                  PersonalEntryRecord(
                    id: id,
                    category: item.category,
                    entryType: item.entryType ?? '',
                    title: item.title,
                    amount: item.totalAmount,
                    dueDate: item.dueDate,
                    status: _statusActive,
                    details: item.details,
                    attachmentUrl: item.attachmentPath,
                  ),
                );
                return true;
              } catch (_) {
                return false;
              }
            },
          ),
      ],
    );
    if (!changed || !mounted) return;
    await _loadEntries();
  }

  Widget _buildSearchControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('personal-search-field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                textDirection: AppTr.uiDir,
                onChanged: (_) => setState(() {}),
                onSubmitted: _saveRecentSearch,
                decoration: InputDecoration(
                  // أيقونة العدسة ثابتة على يمين الحقل (بداية القراءة بالعربية)،
                  // وزر المسح (X) يظهر في الطرف الآخر فقط عند وجود نص بحث،
                  // حتى لا يبقى نص بحث قديم منسيًا يُخفي التزامات موجودة فعلًا
                  // دون أن يلاحظ المستخدم السبب.
                  // حقل ممتلئ بلا حدود بنفس نصف قطر ولون حقول التطبيق.
                  hintText: AppTr.tr('بحث'),
                  hintStyle: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 21,
                    color: AppTheme.chevron,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('personal-search-clear'),
                          tooltip: AppTr.tr('مسح البحث'),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.muted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  // البحث داخل مستطيل الوحدة الملوّن: أبيض بحد واضح.
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                    borderSide: const BorderSide(color: AppTheme.hairline),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.sSm),
            InkWell(
              key: const ValueKey('personal-filter-button'),
              onTap: _openAdvancedFilterSheet,
              borderRadius: BorderRadius.circular(AppTheme.rField),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E7161),
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Center(
                      child: Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                    ),
                    if (_hasActiveAdvancedFilters)
                      Positioned(
                        top: -2,
                        left: -2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2A93F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        _buildSearchSuggestions(),
      ],
    );
  }

  // يفتح شاشة "الفلتر المتقدم" الكاملة: الفئة الرئيسية/الفرعية، التاريخ
  // (مع اختصارات سريعة)، الحالة، نطاق المبلغ (مع فرز أعلى/أقل)، والبحث
  // باسم المستند أو المكان — حسب ملف المتطلبات.
  /// الأسماء الطويلة تُعرض على سطرين داخل شريحة الفئة.
  static String _chipLabel(String title) => switch (title) {
    'المتابعة والتخطيط' => 'المتابعة\nوالتخطيط',
    'أدوية وبيانات وكلمات سر' => 'أدوية وبيانات\nكلمات سر',
    _ => title,
  };

  /// أقسام الفلتر حسب الورقة المعتمدة، بترتيبها: الفئات الرئيسية،
  /// الفرعية، التاريخ (من، إلى، الفترة)، الحالة، المبلغ، العملة، طريقة
  /// الدفع، المستند، الأدوية، الدين، أفراد وجهات، التفويض، مواقع وأماكن.
  /// «الكل» يُظهرها كلها، وكل فئة تُظهر ما يخصّها فقط.
  static List<AppFilterSection> _filterSectionsFor(String category) {
    const base = [
      AppFilterSection.mainCategory,
      AppFilterSection.subCategory,
      AppFilterSection.period,
    ];
    return switch (category) {
      'مالية' => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.amountSelect,
        AppFilterSection.currency,
        AppFilterSection.paymentMethod,
        AppFilterSection.debt,
        AppFilterSection.people,
      ],
      'مستند' => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.documentSelect,
        AppFilterSection.people,
      ],
      'المتابعة والتخطيط' => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.people,
        AppFilterSection.delegates,
      ],
      'أدوية وبيانات وكلمات سر' => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.medicine,
      ],
      'نمط الحياة' => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.amountSelect,
        AppFilterSection.currency,
        AppFilterSection.paymentMethod,
        AppFilterSection.people,
      ],
      'مواقع وأماكن' => const [...base, AppFilterSection.place],
      'عهدة مالية' => const [
        AppFilterSection.mainCategory,
        AppFilterSection.period,
        AppFilterSection.statusSelect,
        AppFilterSection.amountSelect,
        AppFilterSection.currency,
        AppFilterSection.paymentMethod,
        AppFilterSection.people,
      ],
      _ => const [
        ...base,
        AppFilterSection.statusSelect,
        AppFilterSection.amountSelect,
        AppFilterSection.currency,
        AppFilterSection.paymentMethod,
        AppFilterSection.documentSelect,
        AppFilterSection.medicine,
        AppFilterSection.debt,
        AppFilterSection.people,
        AppFilterSection.delegates,
        AppFilterSection.place,
      ],
    };
  }

  /// عملات القائمة: المعروفة + عملة التطبيق + ما في السجلات.
  List<String> get _filterCurrencies {
    final out = <String>[...kAppFilterCurrencies];
    void add(String value) {
      final v = value.trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }

    add(AppSettings.currencySuffix);
    for (final item in _items) {
      add(item.details['العملة'] ?? '');
    }
    return out;
  }

  void _openAdvancedFilterSheet() {
    // الفلتر الرئيسي: القالب مشترك مع الشاشات الثلاث الأخرى، والأقسام
    // وترتيبها هنا مطابقة لملف "فلاتر فوندلي" لصفحة الالتزامات الشخصية.
    showAppFilterSheet(
      context: context,
      title: 'الالتزامات الشخصية',
      accent: const Color(0xFF0E7161),
      // نسخة: إغلاق الورقة بلا «تطبيق» يجب ألا يغيّر شيئًا.
      values: _filter.copy()..mainCategory = _selectedEntryType,
      mainCategories: _personalDashboardFilters
          .map((filter) => filter.$1)
          .toList(growable: false),
      // الفئات الفرعية كما هي، إلا: «أدوية وبيانات وكلمات سر» = أدوية،
      // كلمات سر فقط (حالات الأدوية في «الأدوية ▼»)، و«تفويض» منفصل في
      // قسم «التفويض» تحت أفراد وجهات بدل أن يكون نوعًا في المتابعة.
      subCategoriesFor: _subCategoriesFor,
      // الأقسام تتبع الفئة المختارة داخل الورقة نفسها.
      sections: _filterSectionsFor(_selectedEntryType),
      sectionsFor: _filterSectionsFor,
      currencies: _filterCurrencies,
      delegatesLabel: 'التفويض',
      placeLabel: 'مواقع وأماكن',
      placeHint: 'اكتب اسم الموقع أو المكان',
      onApply: (values) => setState(() {
        _selectedEntryType = values.mainCategory;
        _filter.assignFrom(values);
      }),
    );
  }

  static List<String> _subCategoriesFor(String main) => main == 'الكل'
      ? const <String>[]
      : main == 'مستند'
      ? _documentSubtypeGroups.keys.toList(growable: false)
      : [
          ..._entryCategories
              .where((category) => category.title == main)
              .expand((category) => category.types.map((type) => type.label))
              .where((label) => label != 'تفويض'),
        ];

  /// إعداد الفلتر نفسه لفلتر الصفحة الرئيسية.
  static AppFilterModuleConfig moduleConfig() => AppFilterModuleConfig(
    mainCategories: [for (final filter in _personalDashboardFilters) filter.$1],
    subCategoriesFor: _subCategoriesFor,
    sectionsFor: _filterSectionsFor,
    currencies: [
      ...kAppFilterCurrencies,
      if (!kAppFilterCurrencies.contains(AppSettings.currencySuffix))
        AppSettings.currencySuffix,
    ],
    delegatesLabel: 'التفويض',
    placeLabel: 'مواقع وأماكن',
    placeHint: 'اكتب اسم الموقع أو المكان',
  );

  static const _personalDashboardFilters = [
    ('الكل', Icons.grid_view_rounded, Color(0xFF0E7161)),
    ('مالية', Icons.account_balance_wallet_rounded, Color(0xFF34A894)),
    ('مستند', Icons.description_outlined, Color(0xFFCE8422)),
    ('المتابعة والتخطيط', Icons.checklist_rounded, Color(0xFF0E7161)),
    (
      'أدوية وبيانات وكلمات سر',
      Icons.medical_information_outlined,
      Color(0xFFC4392E),
    ),
    ('نمط الحياة', Icons.celebration_outlined, Color(0xFFC4392E)),
    ('مواقع وأماكن', Icons.location_on_outlined, Color(0xFF0E7161)),
    ('عهدة مالية', Icons.inventory_2_outlined, Color(0xFFA6691A)),
  ];

  Widget _buildCategoriesBlock() {
    // الفئات المخفية من «تخصيص الصفحات» لا تظهر.
    final dashboardFilters = [
      for (final filter in _personalDashboardFilters)
        if (filter.$1 == 'الكل' ||
            !PageCustomizationStore.categoryHidden(_pc, filter.$1))
          filter,
    ];
    final selectedFilter = _personalDashboardFilters.firstWhere(
      (filter) => filter.$1 == _selectedEntryType,
      orElse: () => _personalDashboardFilters.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // بلا عنوان "الفئات": الشرائح نفسها تقول ما هي، والعنوان يشغل
        // سطرًا كاملًا في رأس مثبَّت مساحته ضيقة أصلًا.
        // صف الرقائق الأفقي كما كان بالتصميم السابق. أي فئة فيها أكثر من
        // نوع فرعي واحد (مثل "مالية") تحمل سهمًا صغيرًا (▾) يفتح قائمة
        // منسدلة بنمط "Posts ▾" (قائمة رأسية بعلامة ✓ أمام النوع المختار)
        // بدل توسيع صف رقائق أسفل الفئات بالكامل.
        SizedBox(
          // نفس ارتفاع شريط الفئات في بقية الشاشات.
          height: 46,
          child: ListView.separated(
            key: const ValueKey('personal-category-tabs'),
            controller: _chipsScroll,
            scrollDirection: Axis.horizontal,
            reverse: false,
            itemCount: dashboardFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = dashboardFilters[index];
              final selected = _selectedEntryType == filter.$1;
              final categorySubtypes = filter.$1 == 'الكل'
                  ? const <_EntryType>[]
                  : filter.$1 == 'مستند'
                  ? [
                      for (final label in _documentSubtypeGroups.keys)
                        if (!_typeHidden('مستند', label))
                          _EntryType(
                            label,
                            _documentSubtypeGroupIcons[label] ??
                                Icons.description_outlined,
                          ),
                    ]
                  : [
                      for (final type in _entryCategories
                          .firstWhere(
                            (c) => c.title == filter.$1,
                            orElse: () => _entryCategories.first,
                          )
                          .types)
                        if (!_typeHidden(filter.$1, type.label)) type,
                    ];
              // الشريحة المنسدلة الموحَّدة نفسها المستعملة في شريحتَي
              // "الأفراد" و"الجهات": ستة عناصر ظاهرة ثم تمرير مع مؤشّر.
              void selectSubtype(String? value) {
                setState(() {
                  _selectedEntryType = filter.$1;
                  _advFilterSubType = value;
                  if (!_sortOptions.any((o) => o.$1 == _selectedSort)) {
                    _selectedSort = 'الأحدث أولاً';
                  }
                });
              }

              return AppCategoryDropdownChip(
                key: ValueKey('personal-category-tab-${filter.$1}'),
                label: _chipLabel(filter.$1),
                icon: filter.$2,
                color: filter.$3,
                selected: selected,
                onTap: () => setState(() {
                  _selectedEntryType = filter.$1;
                  _advFilterSubType = null;
                  // خيار ترتيب لا يخصّ الفئة الجديدة يعود إلى الافتراضي.
                  if (!_sortOptions.any((o) => o.$1 == _selectedSort)) {
                    _selectedSort = 'الأحدث أولاً';
                  }
                }),
                items: categorySubtypes.length > 1
                    ? [
                        AppDropdownItem(
                          label: 'الكل',
                          icon: Icons.apps_rounded,
                          selected: selected && _advFilterSubType == null,
                          onTap: () => selectSubtype(null),
                        ),
                        ...categorySubtypes.map(
                          (type) => AppDropdownItem(
                            label: type.label,
                            icon: type.icon,
                            selected:
                                selected && _advFilterSubType == type.label,
                            onTap: () => selectSubtype(type.label),
                          ),
                        ),
                      ]
                    : const [],
              );
            },
          ),
        ),
      ],
    );
  }

  // تنبيه علوي قابل للإخفاء (✕) يظهر عند وجود طلب واحد أو أكثر بانتظار
  // إجراء (تفويض مثلًا)، بدل تخصيص مكان دائم له في الصفحة الرئيسية — يضغط
  // المستخدم عليه فينتقل إلى بند "طلباتي" داخل مركز المتابعة الشامل.
  Widget _buildRequestsBanner() {
    final count = _pendingRequestsCount();
    if (count == 0) return const SizedBox.shrink();
    if (_requestBannerDismissed && _requestBannerDismissedAtCount == count) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openFollowUpSheet,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFD9EDE8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7FC7B9)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.forward_to_inbox_outlined,
                color: Color(0xFF0E7161),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? 'لديك طلب واحد بانتظار الإجراء'
                      : 'لديك $count طلبات بانتظار الإجراء',
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0A5A50),
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _requestBannerDismissed = true;
                  _requestBannerDismissedAtCount = count;
                }),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF0E7161),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// العهد المُسندة إليّ وتنتظر قبولي — تُقرأ من نفس السجلات المشتركة.
  List<_CommitmentItem> get _pendingCustodyInvites {
    final myId = AppIdentity.id;
    if (myId.isEmpty) return const [];
    return _items.where((item) {
      if (!_sharedEntryTypes.contains(item.entryType)) return false;
      final assignment = CustodyAssignment.decode(item.details);
      return assignment.isPending && assignment.holderId == myId;
    }).toList(growable: false);
  }

  /// قبول أو رفض عهدة مُسندة إليّ من قائمة الطلبات مباشرة.
  Future<void> _respondToInvite(_CommitmentItem item, bool accept) async {
    final confirmed = await confirmAction(
      context,
      title: accept ? 'قبول الطلب' : 'رفض الطلب',
      message: accept
          ? 'هل تريد قبول «${item.title}»؟ سيظهر اسمك ورقمك التعريفي لصاحب الطلب.'
          : 'هل تريد رفض «${item.title}»؟',
      confirmLabel: accept ? 'قبول' : 'رفض',
      danger: !accept,
    );
    if (!confirmed || !mounted) return;
    final fresh = await _stillPendingForMe(_repository, item.id, item.details);
    if (!mounted) return;
    if (fresh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يعد هذا الطلب قائمًا — حدّث الصفحة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadEntries();
      return;
    }
    final assignment = CustodyAssignment.decode(fresh);
    final updated = assignment.copyWith(
      state: accept
          ? CustodyAssignmentState.accepted
          : CustodyAssignmentState.rejected,
      holderName: accept
          ? AppSettings.instance.publicName
          : assignment.holderName,
    );
    try {
      final saved = await _repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: item.status,
          details: updated.applyTo(fresh),
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      setState(() {
        item.details = saved.details;
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'تم قبول «${item.title}» بنجاح'
                : 'تم رفض «${item.title}»',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
    }
  }

  Widget _buildCustodyInvitesBanner() {
    final invites = _pendingCustodyInvites;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEFDC),
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: const Color(0xFFE8CFA6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 19,
                color: Color(0xFFA6691A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'طلبات عهدة بانتظارك (${invites.length})',
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF7A4E12),
                  ),
                ),
              ),
            ],
          ),
          for (final item in invites) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.rIcon),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.title,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Builder(
                    builder: (context) {
                      final assignment = CustodyAssignment.decode(
                        item.details,
                      );
                      return Text(
                        [
                          '${item.totalAmount} ${item.currency}',
                          if (assignment.ownerName.isNotEmpty)
                            'من ${assignment.ownerName}',
                          if (assignment.note.isNotEmpty) assignment.note,
                        ].join(' · '),
                        textAlign: AppTr.alignEnd,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5C6B68),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0E7161),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 42),
                          ),
                          onPressed: () => _respondToInvite(item, true),
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text(
                            'قبول',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            minimumSize: const Size(0, 42),
                          ),
                          onPressed: () => _respondToInvite(item, false),
                          icon: const Icon(Icons.close_rounded, size: 17),
                          label: const Text(
                            'رفض',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowUpCenter() {
    // البطاقة المصغّرة تعرض 3 مؤشرات سريعة مبنية من نفس بيانات مركز
    // المتابعة الكامل (6 مجموعات)، حتى تبقى الأرقام متطابقة بين البطاقة
    // المصغّرة والشاشة الكاملة التي يفتحها السهم.
    // البطاقة المصغّرة تعرض مجموعتين من مركز المتابعة نفسه، فتبقى الأرقام
    // متطابقة بين البطاقة والشاشة الكاملة.
    final groups = _buildFollowUpGroups();
    // [0] الطلبات، [1] المتابعة والتخطيط، [2] المالية.
    final organizationTotal = groups[1].total;
    final financialTotal = groups[2].total;
    const accent = Color(0xFF0A5A50);
    // شريحتان فقط في البطاقة الخارجية، والاسم كاملًا بلا اختصار.
    final metrics = [
      (
        'المتابعة والتخطيط',
        organizationTotal,
        Icons.checklist_rounded,
        const Color(0xFF0E7161),
      ),
      (
        'مستحقات',
        financialTotal,
        Icons.payments_outlined,
        const Color(0xFF34A894),
      ),
    ];

    // مركز المتابعة بنفس لون وحواف البطاقات الموحّدة في التطبيق. وحُذف
    // عنوان "اختر ما تريد متابعته بسرعة" الذي كان يشغل سطرًا كاملًا
    // ويكرّر ما تقوله المؤشرات نفسها.
    return AppCard(
      key: const ValueKey('personal-follow-up-center'),
      leading: const AppIconTile(
        icon: Icons.dashboard_customize_outlined,
        color: accent,
      ),
      title: 'مركز المتابعة',
      subtitle: 'الأهم والأقرب من جميع الالتزامات',
      onTap: _openFollowUpSheet,
      trailing: const AppMoreAction(key: ValueKey('personal-follow-up-more')),
      child: SizedBox(
        height: AppMetricChip.stripHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = AppTheme.sSm * (metrics.length - 1);
            // شريحتان تتقاسمان العرض كاملًا ليظهر الاسم الطويل كاملًا.
            final chipWidth =
                ((constraints.maxWidth - spacing) / metrics.length)
                    .clamp(74.0, 260.0);
            // بلا reverse: يبدأ الشريط من اليمين تلقائيًا في الاتجاه
            // العربي، كبقية الأشرطة في الصفحة.
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: metrics.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppTheme.sSm),
              itemBuilder: (context, index) {
                final metric = metrics[index];
                return SizedBox(
                  width: chipWidth,
                  child: AppMetricChip(
                    label: metric.$1,
                    count: metric.$2,
                    icon: metric.$3,
                    color: metric.$4,
                    selected: _selectedFollowUpMetric == index,
                    // المؤشر لم يعد مجرد تلوين: يفتح مركز المتابعة الكامل
                    // على المجموعة التي يمثّلها.
                    onTap: () {
                      setState(() => _selectedFollowUpMetric = index);
                      _openFollowUpSheet();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // يفتح مركز المتابعة المفصّل: 6 مجموعات قابلة للطي مطابقة لملف
  // المتطلبات، كل مجموعة تعرض عناصرها الفرعية مع عدّاد، ويمكن فتح أي
  // عنصر فرعي لعرض الالتزامات المطابقة له والانتقال إلى تفاصيلها.
  void _openFollowUpSheet() {
    // القالب مشترك مع بقية الوحدات؛ هذه الشاشة تمرّر بياناتها فقط.
    showFollowUpCenterSheet(
      context: context,
      accent: const Color(0xFF0A5A50),
      title: 'مركز المتابعة',
      subtitle: 'الالتزامات الشخصية',
      groups: [
        for (final group in _buildFollowUpGroups())
          FollowUpGroup(
            title: group.title,
            icon: group.icon,
            color: group.color,
            metrics: [
              for (final metric in group.metrics)
                FollowUpMetric(
                  label: metric.label,
                  icon: metric.icon,
                  entries: [
                    for (final item in metric.items)
                      FollowUpEntry(
                        title: item.title,
                        subtitle: item.dueDate.isEmpty
                            ? (item.entryType ?? '')
                            : '${item.entryType ?? ''} · ${item.dueDate}',
                        icon: item.icon,
                        color: item.iconColor,
                        trailingText: item.totalAmount > 0
                            ? '${item.totalAmount} ${item.currency}'
                            : null,
                        onTap: () => _openDetails(item),
                      ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  // الفلتر الصغير (بجانب عنوان القائمة) — القائمة كما في ملف "فلاتر فوندلي".
  /// خيارات الفلتر الصغير — تتبع الفئة المختارة، فلا تظهر خيارات الأدوية
  /// داخل «مالية» ولا خيارات المستندات داخل «أدوية».
  List<(String, IconData)> get _sortOptions {
    const newest = ('الأحدث أولاً', Icons.schedule_rounded);
    const active = ('نشط', Icons.play_circle_outline_rounded);
    const dueSoon = ('قريبة الاستحقاق', Icons.hourglass_bottom_rounded);
    const due = ('مستحقة', Icons.payments_outlined);
    const overdue = ('متأخرة', Icons.error_outline_rounded);
    const done = ('مكتمل', Icons.check_circle_outline_rounded);
    const docsSoon = ('مستندات قريبة الانتهاء', Icons.event_busy_outlined);
    const docsExpired = ('مستندات منتهية', Icons.assignment_late_outlined);
    const medsToday = ('أدوية اليوم', Icons.today_outlined);
    const medsNext = ('أدوية قادمة', Icons.upcoming_outlined);
    const medsEnded = ('أدوية منتهية', Icons.event_busy_outlined);
    const highest = ('أعلى مبلغًا', Icons.arrow_upward_rounded);
    const lowest = ('أقل مبلغًا', Icons.arrow_downward_rounded);
    const today = ('اليوم', Icons.today_outlined);
    const tomorrow = ('غدًا', Icons.event_outlined);
    const week = ('بعد أسبوع', Icons.date_range_outlined);
    return switch (_selectedEntryType) {
      'مالية' => const [
        newest,
        active,
        dueSoon,
        due,
        overdue,
        done,
        highest,
        lowest,
      ],
      'مستند' => const [newest, docsSoon, docsExpired],
      'المتابعة والتخطيط' => const [
        newest,
        active,
        overdue,
        done,
        today,
        tomorrow,
        week,
      ],
      'أدوية وبيانات وكلمات سر' => const [
        newest,
        medsToday,
        medsNext,
        medsEnded,
      ],
      'نمط الحياة' => const [
        newest,
        active,
        overdue,
        done,
        today,
        tomorrow,
        week,
      ],
      'مواقع وأماكن' => const [newest],
      'عهدة مالية' => const [
        newest,
        active,
        done,
        ('ملغاة', Icons.cancel_outlined),
        ('مجمّدة', Icons.ac_unit_rounded),
      ],
      _ => const [
        newest,
        active,
        dueSoon,
        due,
        overdue,
        done,
        docsSoon,
        docsExpired,
        medsToday,
        medsNext,
        medsEnded,
      ],
    };
  }

  // زر ترتيب القائمة، بنفس شكل زر قائمة الفئات المنسدلة (حدود واضحة +
  // أيقونة + سهم)، وقائمته مُغلَّفة صراحةً باتجاه RTL حتى لا تظهر عناصرها
  // بترتيب واتجاه معكوس (كانت تعتمد على الاتجاه الافتراضي للقائمة المنبثقة
  // وهو LTR بشكل مستقل عن اتجاه الشاشة، فيظهر شكلها غير احترافي).
  Widget _buildSortDropdownButton() {
    return PopupMenuButton<String>(
      key: const ValueKey('personal-sort-button'),
      tooltip: AppTr.tr('ترتيب الالتزامات'),
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      onSelected: (value) => setState(() => _selectedSort = value),
      itemBuilder: (context) => _sortOptions.map((option) {
        final selected = _selectedSort == option.$1;
        return PopupMenuItem<String>(
          value: option.$1,
          child: Directionality(
            textDirection: AppTr.uiDir,
            child: Row(
              children: [
                Icon(
                  option.$2,
                  size: 17,
                  color: selected
                      ? const Color(0xFF0A5A50)
                      : const Color(0xFF5C6B68),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.$1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: selected
                          ? const Color(0xFF0A5A50)
                          : const Color(0xFF2C3B38),
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: Color(0xFF0A5A50),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
      // بلا مستطيل حول الكلمة: بقية الشاشات تعرض الكلمة والسهم فقط، وكان
      // هذا الزر وحده داخل صندوق أزرق فيبدو مختلفًا عن أخواته.
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedSort,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0A5A50),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Color(0xFF0A5A50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListHeader(int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            // الجملة أولًا ثم العدد بعدها (يسارها)، وزر الترتيب في أقصى
            // الطرف دائمًا.
            Expanded(
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
            Flexible(
              child: Text(
                _categorySummaryLabel(),
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              constraints: const BoxConstraints(minWidth: 36),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFD9EDE8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0E7161),
                ),
              ),
            ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildSortDropdownButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E7161).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 32,
              color: Color(0xFF0E7161),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'لا توجد التزامات مطابقة',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF022E2A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'جرّب تغيير الفلتر أو مسح البحث',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF5C6B68),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('مسح الفلتر والبحث'),
          ),
        ],
      ),
    );
  }
}

class _PersonalCommitmentDetailsScreen extends StatefulWidget {
  final _CommitmentItem item;
  final PersonalEntriesRepository repository;
  final bool openEditOnStart;

  /// يفتح نموذج الإضافة نفسه للتعديل (أو لكورس دواء جديد).
  final Future<PersonalEntryRecord?> Function(
    _CommitmentItem item,
    bool newCourse,
  )?
  onFullEdit;

  /// «بدء عهدة مالية جديدة»: نموذج الإضافة مملوءًا ببيانات هذه العهدة.
  final Future<PersonalEntryRecord?> Function(_CommitmentItem item)?
  onStartCopy;

  /// «دواء آخر من نفس الوصفة»: سجل جديد بنفس البيانات، والاسم والجرعة فارغان.
  final Future<PersonalEntryRecord?> Function(_CommitmentItem item)?
  onSamePrescription;

  const _PersonalCommitmentDetailsScreen({
    required this.item,
    required this.repository,
    this.openEditOnStart = false,
    this.onFullEdit,
    this.onStartCopy,
    this.onSamePrescription,
  });

  @override
  State<_PersonalCommitmentDetailsScreen> createState() =>
      _PersonalCommitmentDetailsScreenState();
}

class _PersonalCommitmentDetailsScreenState
    extends State<_PersonalCommitmentDetailsScreen> {
  int _detailSectionIndex = 0;
  bool _showAllDetails = false;

  static const _custodySectionLabel = 'إدارة\nالعهدة و\nالمصروفات';

  /// عند التمرير لأعلى يثبت شريط مختصر: الاسم ونوع الالتزام وحالته.
  final ScrollController _detailsScroll = ScrollController();
  final ValueNotifier<bool> _compactHeader = ValueNotifier(false);

  void _onDetailsScroll() {
    final compact =
        _detailsScroll.hasClients && _detailsScroll.offset > 150;
    if (_compactHeader.value != compact) _compactHeader.value = compact;
  }

  @override
  void dispose() {
    _detailsScroll.removeListener(_onDetailsScroll);
    _detailsScroll.dispose();
    _compactHeader.dispose();
    super.dispose();
  }

  // الترتيب: الملخص، ثم «المتابعة» وتحتها «التخطيط» في قسم واحد،
  // ثم المستندات، والسجل آخرًا.
  static const _detailSections = [
    (label: 'الملخص', icon: Icons.bar_chart_rounded),
    (label: 'المتابعة\nالتخطيط', icon: Icons.notifications_none_rounded),
    (label: 'المستندات', icon: Icons.folder_outlined),
    (label: 'السجل', icon: Icons.schedule_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _detailsScroll.addListener(_onDetailsScroll);
    if (widget.openEditOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFullEdit();
      });
    }
  }

  Color get _pageColor =>
      Color.lerp(widget.item.iconColor, const Color(0xFF022E2A), 0.38)!;

  String _detailValue(List<String> labels, {String fallback = 'غير محدد'}) {
    for (final label in labels) {
      final value = widget.item.details[label]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  // زر "+ إضافة" في شاشة التفاصيل، حسب ملف الإدخالات المعتمد: مستطيلات
  // خاصة بنوع الالتزام (سداد وزيادة للدين والقسط، صرف وعهدة جديدة للعهدة،
  // جرعات للأدوية) ثم "مستند"، وتحتها قسم "تنظيم ومتابعة" وفيه ملاحظات
  // وتذكير و"+ إضافة أخرى" فقط.
  Future<void> _openAddAttachmentMenu() async {
    var orgExpanded = true;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEDB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'إضافة إلى الالتزام',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F1F1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اختر ما تريد إضافته لهذا الالتزام',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // القائمة مختصرة على ما نصّ عليه ملف الإدخالات: مستند
                    // وتنظيم ومتابعة فقط، وتُضاف إليها إجراءات نوع الالتزام
                    // نفسه (سداد وزيادة للدين والقسط، صرف وعهدة جديدة
                    // للعهدة، جرعات للأدوية). حُذفت "صورة" و"دفعة" العامة.
                    for (final (index, row)
                        in _quickAddRows(widget.item.entryType).indexed) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _buildOrgRow(sheetContext, row),
                    ],
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => setSheetState(
                        () => orgExpanded = !orgExpanded,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_note_outlined,
                              size: 18,
                              color: Color(0xFF0E7161),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'المتابعة والتخطيط',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F1F1C),
                                ),
                              ),
                            ),
                            Icon(
                              orgExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF0E7161),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      _buildOrgRow(sheetContext, const [
                        ('مهمة', Icons.task_alt_outlined),
                        ('موعد', Icons.event_outlined),
                        ('عادة', Icons.repeat_rounded),
                        ('تذكير', Icons.notifications_active_outlined),
                        ('ملاحظات', Icons.sticky_note_2_outlined),
                        ('+ إضافة أخرى', Icons.add_rounded),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'تسجيل سداد / سداد جزئي') {
      _openSubscriptionPaymentForm();
      return;
    }
    if (action == 'إدارة العهدة') {
      await _openCustodyManagementSheet();
      return;
    }
    if (action == 'إدارة الديون') {
      setState(() => _detailSectionIndex = 1);
      return;
    }
    if (action == 'إضافة مبلغ للعهدة') {
      await _openCustodyTopUpForm();
      return;
    }
    if (action == 'إسناد العهدة لشخص') {
      await _openCustodyAssignForm();
      return;
    }
    if (action == 'صرف من العهدة') {
      _openCustodySpendForm();
      return;
    }
    if (action == 'زيادة على الدين السابق') {
      await _openDebtIncreaseForm();
      return;
    }
    if (action == 'بدء عهدة مالية جديدة') {
      await _startNewCustody();
      return;
    }
    if (action == 'بدء كورس جديد') {
      _openQuickOrganizationForm('أدوية');
      return;
    }
    if (_medicationLogActions.contains(action)) {
      await _logMedicationAction(action);
      return;
    }
    if (action == '+ إضافة أخرى') {
      final name = await _askAdditionName();
      if (name == null || !mounted) return;
      // أي إضافة يكتبها المستخدم تُسجَّل في متابعة هذا الالتزام تحت «أخرى».
      await _addFollowupRow(name);
      return;
    }
    // ما يُضاف من التنظيم والمتابعة يُسجَّل داخل هذا الالتزام نفسه ويظهر
    // مجمَّعًا في قسم «المتابعة/التخطيط»، لا كالتزام مستقل في القائمة.
    if (_followupTypes.contains(action)) {
      await _addFollowupRow(action);
      return;
    }
    if (action != 'مستند') {
      _openQuickOrganizationForm(action);
      return;
    }

    final attachmentType = action;
    final attachment = await DocumentStore.pickXFile(context, imageQuality: 88);
    if (attachment == null || !mounted) return;
    await _saveAddedAttachment(attachmentType, attachment);
  }

  /// إجراءات الأدوية التي تُسجَّل في سجل الجرعات بلا نموذج.
  static const _medicationLogActions = {
    'تسجيل التناول',
    'تأجيل',
    'تخطي',
  };

  /// مفتاح سجل الجرعات داخل تفاصيل الالتزام.
  static const _medicationLogKey = 'سجل الجرعات';

  /// مستطيلات "+ إضافة" الخاصة بنوع الالتزام، ثلاثة في كل صف.
  List<List<(String, IconData)>> _quickAddRows(String? entryType) {
    final tiles = <(String, IconData)>[];
    switch (entryType) {
      case 'قسط':
        tiles.addAll(const [
          ('تسجيل سداد / سداد جزئي', Icons.payments_outlined),
          ('زيادة على الدين السابق', Icons.add_card_outlined),
        ]);
      case 'دين / قرض / سلفة':
        // «إدارة الديون» تبويب مستقل، فلا تتكرر هنا كإضافة.
        if (_isDebtCreditor(widget.item)) {
          tiles.add(('زيادة على الدين السابق', Icons.add_card_outlined));
        }
        if (_canRepayDebt(widget.item)) {
          tiles.add(('تسجيل سداد / سداد جزئي', Icons.payments_outlined));
        }
      case 'عهدة مالية':
        // توزيع الأدوار: «صرف من العهدة» للمسند إليه وحده بعد قبوله،
        // و«إضافة مبلغ» لصاحب العهدة الذي أسندها. وما دامت العهدة مسندة
        // فلا يُعاد عرض «إسناد العهدة لشخص» ولا «بدء عهدة جديدة».
        // «إدارة العهدة» تبويب مستقل في الصفحة، فلا تتكرر كإضافة هنا:
        // ورقة الإضافة لما يُضاف فعلًا (صرف، مبلغ، مستند...).
        // «إضافة مبلغ» و«تسوية العهدة» صارتا في بطاقة «إدارة العهدة»،
        // و«إسناد العهدة لشخص» داخل لوحة «إدارة العهدة» لصاحبها.
        final assignment = CustodyAssignment.decode(widget.item.details);
        final myId = AppIdentity.id;
        // المغلقة (ملغاة أو تمت تسويتها) لا يُصرف منها.
        final cancelled = widget.item.status == 'ملغاة' ||
            widget.item.status == 'تمت التسوية' ||
            widget.item.status == 'مجمّدة';
        // الصرف للطرف الآخر (المستلم) فقط، لا لصاحب العهدة.
        if (!cancelled &&
            assignment.canSpend(myId) &&
            _isCustodyRecipient(widget.item.details)) {
          tiles.add(
            ('صرف من العهدة', Icons.remove_circle_outline_rounded),
          );
        }
        // «بدء عهدة جديدة» صار في قائمة النقاط الثلاث (⋮).
      case 'أدوية':
      case 'أدوية وبياناتها':
        tiles.addAll(const [
          ('تسجيل التناول', Icons.check_circle_outline_rounded),
          ('تأجيل', Icons.snooze_rounded),
          ('تخطي', Icons.skip_next_rounded),
          ('بدء كورس جديد', Icons.restart_alt_rounded),
        ]);
      case 'اشتراك':
      case 'اشتراكات':
        tiles.add(('تسجيل سداد / سداد جزئي', Icons.payments_outlined));
    }
    tiles.add(('مستند', Icons.description_outlined));
    return [
      for (var i = 0; i < tiles.length; i += 3)
        tiles.sublist(i, i + 3 > tiles.length ? tiles.length : i + 3),
    ];
  }

  /// اسم الإضافة المخصّصة عند اختيار "+ إضافة أخرى" — حوار موحّد آمن.
  Future<String?> _askAdditionName() =>
      askTextDialog(context, title: 'إضافة أخرى', label: 'اسم الإضافة');

  /// تسجيل تناول/تأجيل/تخطي جرعة في سجل الدواء نفسه.
  Future<void> _logMedicationAction(String action) async {
    final item = widget.item;
    final now = DateTime.now();
    final stamp =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    final previous = item.details[_medicationLogKey] ?? '';
    final line = '$action — $stamp';
    final details = Map<String, String>.of(item.details)
      ..[_medicationLogKey] = previous.isEmpty ? line : '$previous\n$line';
    try {
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: item.status,
          details: details,
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      setState(() {
        item.details = updated.details;
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم الحفظ: $action')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ. حاول مرة أخرى.')),
      );
    }
  }

  /// زيادة على الدين السابق: تُضاف إلى المبلغ الإجمالي وتُسجَّل في سجل
  /// الزيادات، فيبقى أصل الدين وتاريخ كل زيادة ظاهرين لا مجرد رقم جديد.
  Future<void> _openDebtIncreaseForm() async {
    final item = widget.item;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('زيادة على الدين السابق'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: AppTr.tr('مبلغ الزيادة'),
                  suffixText: widget.item.currency,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: InputDecoration(labelText: AppTr.tr('سبب الزيادة')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final amount = double.tryParse(amountController.text.trim());
    final note = noteController.text.trim();
    amountController.dispose();
    noteController.dispose();
    if (added != true || !mounted) return;
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغ زيادة صحيحًا')),
      );
      return;
    }
    final now = DateTime.now();
    final stamp = '${now.year}/${now.month}/${now.day}';
    final previous = item.details['سجل الزيادات'] ?? '';
    final line =
        '${amount.round()} ${widget.item.currency} — $stamp'
        '${note.isEmpty ? '' : ' — $note'}';
    final details = Map<String, String>.of(item.details)
      ..['سجل الزيادات'] = previous.isEmpty ? line : '$previous\n$line';
    final newTotal = item.totalAmount + amount.round();
    try {
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: newTotal,
          dueDate: item.dueDate,
          status: item.status,
          details: details,
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      setState(() {
        item.details = updated.details;
        item.totalAmount = newTotal;
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ الزيادة — الإجمالي الآن '
            '$newTotal ${widget.item.currency}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ. حاول مرة أخرى.')),
      );
    }
  }

  Widget _buildOrgRow(
    BuildContext sheetContext,
    List<(String, IconData)> items,
  ) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _QuickAddTile(
              key: ValueKey('add-org-${items[i].$1}'),
              label: items[i].$1,
              icon: items[i].$2,
              onTap: () => Navigator.pop(sheetContext, items[i].$1),
            ),
          ),
        ],
      ],
    );
  }

  /// «تعديل بيانات»: نفس صفحة الإضافة مملوءة بالبيانات الحالية.
  Future<void> _openFullEdit({bool newCourse = false}) async {
    final full = widget.onFullEdit;
    if (full == null || _financialEntryForms[widget.item.entryType] == null) {
      if (!newCourse) await _openEditForm();
      return;
    }
    final updated = await full(widget.item, newCourse);
    if (updated == null || !mounted) return;
    setState(() {
      final item = widget.item;
      item.title = updated.title;
      item.totalAmount = updated.amount;
      item.dueDate = updated.dueDate;
      item.status = updated.status;
      item.statusColor = _personalStatusColor(updated.status);
      item.details = updated.details;
      item.attachmentPath = updated.attachmentUrl ?? item.attachmentPath;
      item.lastUpdate = 'الآن';
    });
  }

  /// كل إجراءات قائمة النقاط الثلاث تمرّ بنافذة تأكيد قبل التنفيذ.
  Future<void> _handleMenuAction(_CommitmentMenuAction action) async {
    // إلغاء العهدة يمر بنافذة التسوية نفسها، فلا تأكيد عام قبلها.
    if (action == _CommitmentMenuAction.cancel) {
      await _cancelCustody();
      return;
    }
    // «إلغاء الإسناد» صار في القائمة ⋮ فقط، وله تأكيده الخاص.
    // المستلم لا يعدّل بيانات العهدة أو الدين (حتى لو وصل الأمر بطريق آخر).
    if (action == _CommitmentMenuAction.edit && _isSharedGuest(widget.item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التعديل لصاحب العهدة فقط'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // إعادة فتح عهدة سُوّيت: لها تأكيدها الخاص.
    if (action == _CommitmentMenuAction.reopenCustody) {
      await _reopenCustody();
      return;
    }
    if (action == _CommitmentMenuAction.cancelAssignment) {
      await _cancelCustodyAssignment();
      return;
    }
    // التجميد له تأكيده الخاص.
    if (action == _CommitmentMenuAction.freezeCustody) {
      await _toggleCustodyFreeze();
      return;
    }
    final title = widget.item.title;
    final (label, message, danger) = switch (action) {
      _CommitmentMenuAction.edit => (
        'تعديل بيانات',
        'ستُفتح بيانات «$title» في نموذج الإضافة نفسه لتعديلها. هل تريد '
            'المتابعة؟',
        false,
      ),
      _CommitmentMenuAction.newCourse => (
        'بدء كورس جديد',
        'ستُفتح بيانات «$title» كما هي لتعدّل التاريخ؛ الكورس الحالي يُحفظ '
            'في السجل. هل تريد المتابعة؟',
        false,
      ),
      _CommitmentMenuAction.samePrescription => (
        'دواء آخر من نفس الوصفة',
        'هل ترغب بإضافة دواء آخر بنفس معلومات «$title»؟ تكتب اسم الدواء '
            'والجرعة والقياسات فقط، و«$title» يبقى كما هو.',
        false,
      ),
      _CommitmentMenuAction.newCustody => (
        'بدء عهدة جديدة',
        'ستُفتح بيانات «$title» كما هي بتاريخ اليوم — غيّر ما تراه ثم احفظ. '
            'العهدة الحالية تُحفظ في السجل كعهدة رقم '
            '${int.tryParse(widget.item.details['رقم العهدة'] ?? '') ?? _parseCustodyLog(widget.item.details).length + 1} '
            'بكل معلوماتها ومصروفاتها.',
        false,
      ),
      _CommitmentMenuAction.share => (
        'مشاركة الالتزام',
        'ستُشارك بيانات «$title» عبر تطبيق تختاره. هل تريد المتابعة؟',
        false,
      ),
      _CommitmentMenuAction.delete => (
        'حذف الالتزام',
        'سيُنقل «$title» إلى سلة المهملات، ويمكنك استعادته منها أو حذفه '
            'نهائيًا. هل تريد المتابعة؟',
        true,
      ),
      _CommitmentMenuAction.cancel => (
        'إلغاء العهدة',
        'ستُلغى «$title»: يتوقف الصرف منها والإضافة عليها، وتبقى بياناتها '
            'وسجلها للاطلاع. بعد الإلغاء يمكنك حذفها. هل تريد المتابعة؟',
        true,
      ),
      _CommitmentMenuAction.reopenCustody => (
        'إعادة فتح العهدة',
        '',
        false,
      ),
      _CommitmentMenuAction.cancelAssignment => (
        'إلغاء الإسناد',
        '',
        true,
      ),
      _CommitmentMenuAction.freezeCustody => ('تجميد العهدة', '', false),
      _CommitmentMenuAction.archive => widget.item.status == 'مؤرشف'
          ? (
              'إخراج من الأرشيف',
              'سيعود «$title» إلى الالتزامات النشطة. هل تريد المتابعة؟',
              false,
            )
          : (
              'أرشفة الالتزام',
              'سيُنقل «$title» إلى الأرشيف ويمكنك إخراجه لاحقًا. '
                  'هل تريد الأرشفة؟',
              false,
            ),
    };
    final ok = await confirmAction(
      context,
      title: label,
      message: message,
      confirmLabel: action == _CommitmentMenuAction.cancel
          ? 'إلغاء العهدة'
          : danger
          ? 'حذف'
          : 'تأكيد',
      cancelLabel: action == _CommitmentMenuAction.cancel ? 'رجوع' : 'إلغاء',
      danger: danger,
    );
    if (!ok || !mounted) return;
    switch (action) {
      case _CommitmentMenuAction.edit:
        await _openFullEdit();
      case _CommitmentMenuAction.newCourse:
        await _openFullEdit(newCourse: true);
      case _CommitmentMenuAction.samePrescription:
        {
          final add = widget.onSamePrescription;
          if (add == null) return;
          final saved = await add(widget.item);
          if (saved == null || !mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppTr.tr('أُضيف')} «${saved.title}» '
                '${AppTr.tr('من نفس الوصفة')}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case _CommitmentMenuAction.newCustody:
        // مثل «بدء كورس جديد»: نفس السجل، والسابقة تُحفظ في السجل.
        await _openFullEdit(newCourse: true);
      case _CommitmentMenuAction.share:
        await _shareCommitment();
      case _CommitmentMenuAction.delete:
        await _deleteCommitment();
      case _CommitmentMenuAction.cancel:
        await _cancelCustody();
      case _CommitmentMenuAction.reopenCustody:
        await _reopenCustody();
      case _CommitmentMenuAction.cancelAssignment:
        await _cancelCustodyAssignment();
      case _CommitmentMenuAction.freezeCustody:
        await _toggleCustodyFreeze();
      case _CommitmentMenuAction.archive:
        if (widget.item.status == 'مؤرشف') {
          await _unarchiveCommitment();
        } else {
          await _archiveCommitment();
        }
    }
  }

  Future<void> _shareCommitment() async {
    final item = widget.item;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: item.title,
        text: [
          item.title,
          'النوع: ${item.entryType ?? 'التزام شخصي'}',
          'المبلغ: ${item.totalAmount} ${widget.item.currency}',
          'الاستحقاق: ${item.dueDate.isEmpty ? 'غير محدد' : item.dueDate}',
          'الحالة: ${item.status}',
        ].join('\n'),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _archiveCommitment() async {
    final item = widget.item;
    if (_isSharedGuest(item)) return;
    try {
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: 'مؤرشف',
          details: item.details,
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      setState(() {
        item.status = updated.status;
        item.statusColor = const Color(0xFF5C6B68);
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت أرشفة الالتزام بنجاح')));
      // الرجوع بنتيجة ليُعاد تحميل القائمة فيختفي المؤرشف من العرض.
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
    }
  }

  /// إخراج الالتزام من الأرشيف وإعادته نشطًا.
  Future<void> _unarchiveCommitment() async {
    final item = widget.item;
    try {
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: item.entryType == 'عهدة مالية' &&
                  item.details['حالة العهدة'] == 'تمت التسوية'
              ? 'تمت التسوية'
              : 'نشطة',
          details: item.details,
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      setState(() {
        item.status = updated.status;
        item.statusColor = _personalStatusColor(updated.status);
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إخراج الالتزام من الأرشيف بنجاح')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
    }
  }

  Future<void> _deleteCommitment() async {
    // التأكيد يتم في قائمة النقاط الثلاث، فلا تُعرض نافذتان متتاليتان.
    if (_isSharedGuest(widget.item)) return;
    final id = widget.item.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الالتزام غير المحفوظ.')),
      );
      return;
    }
    try {
      // الحذف نقل إلى سلة المهملات لا محو نهائي: الحالة تصير «محذوف»
      // وتُحفظ الحالة السابقة وتاريخ الحذف لاستعادته كما كان.
      final item = widget.item;
      await widget.repository.update(
        PersonalEntryRecord(
          id: id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: TrashStore.status,
          details: TrashStore.markDeleted(
            item.details,
            item.status,
            'الالتزامات الشخصية',
          ),
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
    }
  }

  /// يعيد معرّف المستند الإضافي إن أُضيف بجانب مرفق موجود، و'' إن صار هو
  /// المرفق الأول، وnull إن تعذّر الحفظ.
  Future<String?> _saveAddedAttachment(String type, XFile attachment) async {
    final item = widget.item;
    final repository = widget.repository;
    final hasMain = (item.attachmentPath ?? '').trim().isNotEmpty;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      // يوجد مستند: الجديد يُضاف بجانبه ولا يستبدله.
      if (hasMain && repository is SupabasePersonalEntriesRepository) {
        final path = await repository.uploadAttachment(attachment);
        final id = '${DateTime.now().millisecondsSinceEpoch}';
        final rows = [
          ..._parseExtraAttachments(item.details),
          {'id': id, 'path': path, 'name': attachment.name, 'type': type},
        ];
        final updated = await repository.update(
          PersonalEntryRecord(
            id: item.id,
            category: item.category,
            entryType: item.entryType ?? '',
            title: item.title,
            amount: item.totalAmount,
            dueDate: item.dueDate,
            status: item.status,
            details: Map<String, String>.of(item.details)
              ..[_extraAttachmentsKey] = jsonEncode(rows),
            attachmentUrl: item.attachmentPath,
          ),
        );
        if (!mounted) return null;
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          item.details = updated.details;
          item.lastUpdate = 'الآن';
          _detailSectionIndex = 2;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ ${_savedLabel(type)} بنجاح')),
        );
        return id;
      }
      final details = Map<String, String>.of(item.details)
        ..[_addedAttachmentTypeKey] = type
        ..[_addedAttachmentNameKey] = attachment.name;
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: item.totalAmount,
          dueDate: item.dueDate,
          status: item.status,
          details: details,
          attachmentUrl: item.attachmentPath,
        ),
        attachment: attachment,
      );
      if (!mounted) return null;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        item.details = updated.details;
        item.attachmentPath = updated.attachmentUrl;
        item.lastUpdate = 'الآن';
        // المستند المُضاف يُعرض في قسم «المستندات».
        _detailSectionIndex = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ ${_savedLabel(type)} بنجاح')),
      );
      return '';
    } catch (_) {
      if (!mounted) return null;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع المرفق. حاول مرة أخرى.')),
      );
      return null;
    }
  }

  InputDecoration _custodyFieldDecoration(
    String label,
    IconData icon,
    Color color,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: color, size: 20),
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1.4),
      ),
    );
  }

  // تسجيل عملية صرف من عهدة مالية: يُضاف كعنصر جديد إلى سجل الصرفيات
  // المخزّن داخل تفاصيل الالتزام، ثم يُعاد حساب الرصيد المتبقي (قيمة
  // العهدة − مجموع الصرفيات)، وإن وصل الرصيد إلى صفر أو أقل تُحدَّث حالة
  // العهدة تلقائيًا إلى "تمت التسوية".
  /// حفظ تفاصيل العهدة بعد تعديلها (إسناد أو زيادة مبلغ) في المستودع.
  Widget _custodyStatRow(String label, int value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Text(
            '$value ${widget.item.currency}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color ?? const Color(0xFF022E2A),
            ),
          ),
        ],
      ),
    );
  }

  /// «إدارة العهدة»: كل ما جرى على العهدة — الإسناد، الزيادات، الصرفيات
  /// وفواتيرها — بصلاحيات مختلفة للمالك وللمسند إليه.
  Future<void> _openCustodyManagementSheet() async {
    // أحدث حالة (قبول/رفض/مصروفات الطرف الآخر) قبل فتح الإدارة.
    await _refreshItemFromServer(quiet: true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final item = widget.item;
          final myId = AppIdentity.id;
          final assignment = CustodyAssignment.decode(item.details);
          final role = assignment.roleFor(myId);
          final spends = _parseCustodyTransactions(item.details);
          final topUps = CustodyTopUps.parse(item.details);
          final spent = _custodyTotalSpent(item.details);
          final remaining = item.totalAmount - spent;
          final cancelled = item.status == 'ملغاة' ||
              item.status == 'تمت التسوية' ||
              item.status == 'مجمّدة';
          final canManage = _isCustodyOwnerView(item.details) && !cancelled;
          final canSpend =
              assignment.canSpend(myId) &&
              !cancelled &&
              _isCustodyRecipient(item.details);

          Future<void> refresh(Future<void> Function() action) async {
            await action();
            if (sheetContext.mounted) setSheetState(() {});
          }

          return Directionality(
            textDirection: AppTr.uiDir,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              builder: (context, controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      const Icon(
                        Icons.manage_accounts_outlined,
                        size: 20,
                        color: Color(0xFF0E7161),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        // المفوَّض بها يراها «معلومات العهدة المالية».
                        child: Text(
                          _isCustodyOwnerView(item.details)
                              ? 'إدارة العهدة'
                              : 'معلومات العهدة المالية',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppTr.tr('إغلاق'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const Divider(height: 14, thickness: 1, color: AppTheme.line),

                  // ===== حالة الإسناد =====
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            const Expanded(
                              child: Text(
                                'حالة الإسناد',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF022E2A),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: assignment.isAccepted
                                    ? const Color(0x1A0E7161)
                                    : assignment.isPending
                                    ? const Color(0x1ACE8422)
                                    : const Color(0x14000000),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                assignment.stateLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: assignment.isAccepted
                                      ? const Color(0xFF0E7161)
                                      : assignment.isPending
                                      ? const Color(0xFFA6691A)
                                      : const Color(0xFF5C6B68),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (assignment.isAssigned) ...[
                          const SizedBox(height: 8),
                          _leaseLikeRow(
                            'المالك',
                            assignment.ownerName.isEmpty
                                ? assignment.ownerId
                                : '${assignment.ownerName} · '
                                      '${assignment.ownerId}',
                          ),
                          _leaseLikeRow(
                            'المسند إليه',
                            assignment.holderName.isEmpty
                                ? assignment.holderId
                                : '${assignment.holderName} · '
                                      '${assignment.holderId}',
                          ),
                          if (assignment.assignedAt.isNotEmpty)
                            _leaseLikeRow(
                              'تاريخ الإسناد',
                              assignment.assignedAt,
                            ),
                          if ((item.details[CustodyAssignment.kRespondedAt] ??
                                      '')
                                  .isNotEmpty &&
                              (assignment.isAccepted || assignment.isRejected))
                            _leaseLikeRow(
                              assignment.isAccepted
                                  ? 'تاريخ ووقت القبول'
                                  : 'تاريخ ووقت الرفض',
                              item.details[CustodyAssignment.kRespondedAt]!,
                            ),
                          if (assignment.note.isNotEmpty)
                            _leaseLikeRow('ملاحظة', assignment.note),
                        ] else ...[
                          const SizedBox(height: 6),
                          const Text(
                            'العهدة غير مسندة لأحد — يمكنك إسنادها بالرقم '
                            'التعريفي للشخص فيصرف منها وترى أنت كل حركة.',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.6,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5C6B68),
                            ),
                          ),
                        ],
                        // قبول/رفض للمسند إليه وهو بانتظار القبول.
                        if (role == CustodyRole.holder &&
                            assignment.isPending) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0E7161),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: () => refresh(
                                    () => _respondToCustodyAssignment(
                                      accept: true,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('قبول العهدة'),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.danger,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: () => refresh(
                                    () => _respondToCustodyAssignment(
                                      accept: false,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('رفض'),
                                ),
                              ),
                            ],
                          ),
                        ],
                        // الإسناد لشخص: لصاحب العهدة وهي غير مسندة.
                        if (canManage &&
                            (!assignment.isAssigned ||
                                assignment.isRejected)) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();
                              await _openCustodyAssignForm();
                            },
                            icon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 18,
                            ),
                            label: const Text('إسناد العهدة لشخص'),
                          ),
                        ],
                        // «إلغاء الإسناد» صار في قائمة النقاط الثلاث فقط.
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ===== الأرقام =====
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      border: Border.all(color: AppTheme.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _custodyStatRow('إجمالي العهدة', item.totalAmount),
                        _custodyStatRow(
                          'المصروف',
                          spent,
                          color: const Color(0xFFC4392E),
                        ),
                        _custodyStatRow(
                          'المتبقي',
                          remaining,
                          color: remaining < 0
                              ? const Color(0xFFC4392E)
                              : const Color(0xFF0E7161),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (canManage)
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0E7161),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(sheetContext).pop();
                                    await _openCustodyTopUpForm();
                                  },
                                  icon: const Icon(
                                    Icons.add_card_outlined,
                                    size: 17,
                                  ),
                                  label: const Text(
                                    'إضافة مبلغ',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            if (canManage && canSpend)
                              const SizedBox(width: 9),
                            if (canSpend)
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(sheetContext).pop();
                                    await _openCustodySpendForm();
                                  },
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 17,
                                  ),
                                  label: const Text(
                                    'صرف من العهدة',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (spends.any(
                          (row) =>
                              row[_custodySpendStateKey] == _custodySpendPending,
                        ))
                          _custodyStatRow(
                            'بانتظار الاعتماد',
                            spends
                                .where(
                                  (row) =>
                                      row[_custodySpendStateKey] ==
                                      _custodySpendPending,
                                )
                                .fold<int>(
                                  0,
                                  (sum, row) =>
                                      sum +
                                      parseAmountInt(row['المبلغ'] ?? ''),
                                ),
                            color: const Color(0xFFA6691A),
                          ),
                        if (role == CustodyRole.owner)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _custodyNeedsApproval(item.details)
                                  ? 'العهدة مسندة — الصرف عند الطرف الآخر، وكل '
                                        'مصروف يرسله يصلك هنا لتعتمده أو ترفضه.'
                                  : 'العهدة مسندة — الصرف عند الطرف الآخر، وأنت '
                                        'ترى حركاتها وفواتيرها للقراءة فقط.',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.6,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFA6691A),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ===== السجل: قبول العهدة أو رفضها بتاريخه ووقته =====
                  if (assignment.isAccepted || assignment.isRejected)
                    _custodyLogRow(
                      icon: assignment.isAccepted
                          ? Icons.verified_outlined
                          : Icons.cancel_outlined,
                      color: assignment.isAccepted
                          ? const Color(0xFF0E7161)
                          : AppTheme.danger,
                      line1:
                          '${assignment.isAccepted ? AppTr.tr('مقبولة') : AppTr.tr('مرفوضة')}'
                          ' — ${assignment.holderName.isEmpty ? assignment.holderId : assignment.holderName}',
                      line2:
                          item.details[CustodyAssignment.kRespondedAt] ?? '',
                    ),
                  // ===== سجل الزيادات =====
                  if (topUps.isNotEmpty) ...[
                    const Text(
                      'الزيادات على العهدة',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final row in topUps)
                      _custodyLogRow(
                        icon: Icons.add_card_outlined,
                        color: const Color(0xFF0E7161),
                        line1:
                            '+${row['المبلغ'] ?? '0'} '
                            '${widget.item.currency}',
                        line2: [
                          if ((row['التاريخ'] ?? '').isNotEmpty)
                            _withTime(row['التاريخ']!, row[_recordTimeKey]),
                          if ((row['بواسطة'] ?? '').isNotEmpty)
                            'بواسطة ${row['بواسطة']}',
                          if ((row['السبب'] ?? '').isNotEmpty) row['السبب']!,
                        ].join(' · '),
                      ),
                    const SizedBox(height: 14),
                  ],

                  // ===== سجل الصرفيات =====
                  Text(
                    'مصروفات العهدة (${spends.length})',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (spends.isEmpty)
                    const Text(
                      'لا توجد مصروفات مسجّلة بعد.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C9A97),
                      ),
                    )
                  else
                    for (var i = 0; i < spends.length; i++)
                      _custodyLogRow(
                        icon: Icons.receipt_long_outlined,
                        color: _custodySpendCounts(spends[i])
                            ? const Color(0xFFC4392E)
                            : const Color(0xFF8C9A97),
                        line1:
                            '-${spends[i]['المبلغ'] ?? '0'} '
                            '${widget.item.currency}'
                            '${(spends[i]['الغرض'] ?? '').isEmpty ? '' : ' · ${spends[i]['الغرض']}'}',
                        line2: _custodySpendLine2(spends[i]),
                        invoicePath: spends[i][_paymentInvoiceKey],
                        state: spends[i][_custodySpendStateKey] ?? '',
                        details: spends[i],
                        // صاحب العهدة يعتمد المصروف أو يرفضه.
                        onApprove:
                            canManage &&
                                spends[i][_custodySpendStateKey] ==
                                    _custodySpendPending
                            ? () => refresh(
                                () => _setCustodySpendState(i, approve: true),
                              )
                            : null,
                        onReject:
                            canManage &&
                                spends[i][_custodySpendStateKey] ==
                                    _custodySpendPending
                            ? () => refresh(
                                () => _setCustodySpendState(i, approve: false),
                              )
                            : null,
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _leaseLikeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value.isEmpty ? 'غير محدد' : value,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _custodyLogRow({
    required IconData icon,
    required Color color,
    required String line1,
    required String line2,
    String? invoicePath,
    String state = '',
    VoidCallback? onApprove,
    VoidCallback? onReject,
    Map<String, String>? details,
  }) {
    final hasInvoice = invoicePath != null && invoicePath.trim().isNotEmpty;
    final stateColor = state == _custodySpendRejected
        ? const Color(0xFFC4392E)
        : state == _custodySpendPending
        ? const Color(0xFFA6691A)
        : const Color(0xFF0E7161);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(
          color: state == _custodySpendPending
              ? const Color(0x80CE8422)
              : AppTheme.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      Row(
        textDirection: AppTr.uiDir,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  line1,
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF022E2A),
                  ),
                ),
                if (line2.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    line2,
                    textAlign: AppTr.alignEnd,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // «مرفق» بنص وأيقونة: يُفهم أن الضغط يفتح المرفق.
          if (hasInvoice)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0E7161),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: () =>
                  _openInvoiceImage(context, (invoicePath ?? '').trim()),
              icon: const Icon(Icons.attach_file_rounded, size: 17),
              label: const Text(
                'مرفق',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ),
          // حالة اعتماد المصروف (إن كانت العهدة تشترط الموافقة).
          if (state.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                state,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: stateColor,
                ),
              ),
            ),
        ],
      ),
          // «عرض التفاصيل»: كل بيانات المصروف قبل اعتماده.
          if (details != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _showSpendDetails(
                  details,
                  onApprove: onApprove,
                  onReject: onReject,
                ),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: const Text(
                  'عرض التفاصيل',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (onApprove != null)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0E7161),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: const Text(
                        'اعتماد',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                if (onApprove != null && onReject != null)
                  const SizedBox(width: 8),
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text(
                        'رفض',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// صاحب العهدة يعتمد مصروف المستلم (فيُخصم منها) أو يرفضه.
  Future<void> _setCustodySpendState(int index, {required bool approve}) async {
    final item = widget.item;
    final rows = _parseCustodyTransactions(item.details);
    if (index < 0 || index >= rows.length) return;
    rows[index][_custodySpendStateKey] = approve
        ? _custodySpendApproved
        : _custodySpendRejected;
    rows[index][approve ? _approvedAtKey : _rejectedAtKey] = _stampNow();
    final encoded = _encodeCustodyTransactions(rows);
    final details = Map<String, String>.of(item.details)
      ..[_custodyTransactionsDetailKey] = encoded;
    final remaining = item.totalAmount - _custodyTotalSpent(details);
    if (approve && remaining <= 0) details['حالة العهدة'] = 'تمت التسوية';
    final ok = await _persistCustody(
      details,
      newStatus: approve && remaining <= 0 ? 'تمت التسوية' : null,
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approve
              ? 'اعتُمد المصروف وخُصم من العهدة'
              : 'رُفض المصروف ولم يُخصم من العهدة',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (approve) {
      // بلغ الصرف نسبة التنبيه المختارة: تذكير ورسالة.
      final alert = await _checkCustodyAlert(
        id: item.id,
        title: item.title,
        total: item.totalAmount,
        details: item.details,
      );
      if (alert != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(alert), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  /// «بدء عهدة جديدة»: نفس بيانات هذه العهدة بتاريخ اليوم، تراجعها ثم
  /// تحفظ عهدة جديدة (الحالية تبقى كما هي).
  Future<void> _startNewCustody() async {
    final copy = widget.onStartCopy;
    if (copy == null) {
      _openQuickOrganizationForm('عهدة مالية');
      return;
    }
    final saved = await copy(widget.item);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ عهدة مالية جديدة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// نافذة التسوية الموحّدة: الأرقام، وحقل إلزامي يكتب فيه صاحب العهدة ما
  /// حدث، ثم يختار أحد [options] (القيمة، النص، زر رئيسي؟، أحمر؟).
  /// تعيد (الاختيار، الملاحظة) أو null عند الرجوع.
  Future<(String, String)?> _askCustodySettlement({
    required String title,
    required String intro,
    required String noteLabel,
    required List<(String, String, bool, bool)> options,
  }) async {
    final item = widget.item;
    final spent = _custodyTotalSpent(item.details);
    final remaining = item.totalAmount - spent;
    final noteController = TextEditingController();
    Widget summaryRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C6B68),
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F1F1C),
            ),
          ),
        ],
      ),
    );
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var showError = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void pick(String value) {
              if (noteController.text.trim().isEmpty) {
                setDialogState(() => showError = true);
                return;
              }
              Navigator.pop(dialogContext, value);
            }

            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intro,
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    summaryRow(
                      AppTr.tr('مبلغ العهدة'),
                      '${item.totalAmount} ${item.currency}',
                    ),
                    summaryRow(
                      AppTr.tr('المصروف'),
                      '$spent ${item.currency}',
                    ),
                    summaryRow(
                      AppTr.tr('المتبقي (يُسجَّل مُعادًا)'),
                      '${remaining > 0 ? remaining : 0} ${item.currency}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) {
                        if (showError) setDialogState(() => showError = false);
                      },
                      decoration: InputDecoration(
                        labelText: noteLabel,
                        errorText: showError
                            ? AppTr.tr('اكتب ما تم قبل التسوية')
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('رجوع'),
                ),
                for (final option in options)
                  if (option.$3)
                    FilledButton(
                      onPressed: () => pick(option.$1),
                      child: Text(option.$2),
                    )
                  else
                    TextButton(
                      style: option.$4
                          ? TextButton.styleFrom(
                              foregroundColor: const Color(0xFFA82F26),
                            )
                          : null,
                      onPressed: () => pick(option.$1),
                      child: Text(option.$2),
                    ),
              ],
            );
          },
        );
      },
    );
    final note = noteController.text.trim();
    // بعد انتهاء حركة إغلاق النافذة.
    Future<void>.delayed(
      const Duration(milliseconds: 500),
      noteController.dispose,
    );
    if (choice == null) return null;
    return (choice, note);
  }

  /// إعادة فتح عهدة سُوّيت: تعود نشطة ويُصرف من المتبقي حتى صفر، وتبقى
  /// التسوية السابقة مذكورة في السجل.
  Future<void> _reopenCustody() async {
    final item = widget.item;
    if (!_isCustodyOwnerView(item.details) || item.status != 'تمت التسوية') {
      return;
    }
    final remaining = item.totalAmount - _custodyTotalSpent(item.details);
    final ok = await confirmAction(
      context,
      title: 'إعادة فتح العهدة',
      message:
          '${AppTr.tr('ستعود العهدة نشطة، ويُصرف منها من جديد من المتبقي')}: '
          '$remaining ${item.currency}. ${AppTr.tr('هل تريد المتابعة؟')}',
      confirmLabel: 'إعادة الفتح',
      cancelLabel: 'رجوع',
    );
    if (!ok || !mounted) return;
    final details = Map<String, String>.of(item.details);
    final previous = [
      (details['تاريخ التسوية'] ?? '').trim(),
      (details['ملاحظة التسوية'] ?? details['سبب التسوية'] ?? '').trim(),
    ].where((part) => part.isNotEmpty).join(' — ');
    for (final key in const [
      'تاريخ التسوية',
      'ملاحظة التسوية',
      'سبب التسوية',
      'المبلغ المعاد عند التسوية',
    ]) {
      details.remove(key);
    }
    details['حالة العهدة'] = 'قيد الاستخدام';
    details['أُعيد فتحها في'] = _stampNow();
    if (previous.isNotEmpty) details['تسوية سابقة'] = previous;
    final saved = await _persistCustody(details, newStatus: 'نشطة');
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('أُعيد فتح العهدة — يمكن الصرف من المتبقي'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// مصروفات بانتظار الاعتماد تمنع التسوية (وإلا صار «المعاد» خاطئًا).
  bool _blockSettlementIfPending() {
    final pending = _parseCustodyTransactions(
      widget.item.details,
    ).where((row) => row[_custodySpendStateKey] == _custodySpendPending).length;
    if (pending == 0) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppTr.tr('مصروفات بانتظار الاعتماد')}: $pending — '
          '${AppTr.tr('اعتمدها أو ارفضها قبل التسوية.')}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  /// حفظ نتيجة التسوية: [status] الحالة الجديدة، و[noteKey] مكان الملاحظة.
  /// المؤرشفة تختفي من القائمة، فنرجع بنتيجة لتُعاد قراءتها.
  Future<void> _applyCustodySettlement({
    required String note,
    required String noteKey,
    required String custodyState,
    required String status,
    required String doneMessage,
    bool cancelled = false,
  }) async {
    final item = widget.item;
    final remaining = item.totalAmount - _custodyTotalSpent(item.details);
    final stamp = _stampNow();
    final details = Map<String, String>.of(item.details)
      ..[noteKey] = note
      ..['تاريخ التسوية'] = stamp
      ..['حالة العهدة'] = custodyState;
    if (cancelled) details['تاريخ الإلغاء'] = stamp;
    if (remaining > 0) details['المبلغ المعاد عند التسوية'] = '$remaining';
    final ok = await _persistCustody(details, newStatus: status);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppTr.tr(doneMessage)),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (status == 'مؤرشف') Navigator.pop(context, true);
  }

  /// إلغاء العهدة (لصاحبها) — مثل عقد الإيجار: لا إلغاء بلا تسوية.
  /// يكتب سبب التسوية ثم يختار: «إلغاء العهدة» فتصبح ملغاة (تبقى للاطلاع
  /// ويتاح حذفها)، أو «تسوية وأرشفة» فتُغلق وتنتقل للأرشيف.
  Future<void> _cancelCustody() async {
    if (!_isCustodyOwnerView(widget.item.details)) return;
    if (_blockSettlementIfPending()) return;
    final result = await _askCustodySettlement(
      title: AppTr.tr('تسوية العهدة قبل الإلغاء'),
      intro: AppTr.tr(
        'لا تُلغى العهدة بدون تسوية. اكتب سبب التسوية ثم اختر '
        'إلغاء العهدة أو تسويتها وأرشفتها.',
      ),
      noteLabel: AppTr.tr('سبب التسوية *'),
      options: const [
        ('cancel', 'إلغاء العهدة', false, true),
        ('archive', 'تسوية وأرشفة', true, false),
      ],
    );
    if (result == null || !mounted) return;
    final archive = result.$1 == 'archive';
    await _applyCustodySettlement(
      note: result.$2,
      noteKey: 'سبب التسوية',
      custodyState: archive ? 'تمت التسوية' : 'ملغاة',
      status: archive ? 'مؤرشف' : 'ملغاة',
      cancelled: !archive,
      doneMessage: archive
          ? 'تمت تسوية العهدة ونُقلت إلى الأرشيف'
          : 'أُلغيت العهدة بعد التسوية — يمكنك حذفها من القائمة ⋮',
    );
  }

  /// تسوية العهدة (لصاحبها): يكتب ما تم، ثم يختار إبقاءها ظاهرة بحالة
  /// «تمت التسوية» أو نقلها إلى الأرشيف. المتبقي يُسجَّل مُعادًا.
  Future<void> _settleCustody() async {
    if (!_isCustodyOwnerView(widget.item.details)) return;
    if (_blockSettlementIfPending()) return;
    final result = await _askCustodySettlement(
      title: AppTr.tr('تسوية العهدة'),
      intro: AppTr.tr(
        'ستُغلق العهدة ولا يُصرف منها بعد ذلك. اكتب ما تم في التسوية '
        '(مثل: استلمت المتبقي نقدًا)، ثم اختر إبقاءها أو أرشفتها.',
      ),
      noteLabel: AppTr.tr('ملاحظة التسوية — ماذا تم؟ *'),
      options: const [
        ('keep', 'تسوية وإبقاؤها', false, false),
        ('archive', 'تسوية وأرشفة', true, false),
      ],
    );
    if (result == null || !mounted) return;
    final archive = result.$1 == 'archive';
    await _applyCustodySettlement(
      note: result.$2,
      noteKey: 'ملاحظة التسوية',
      custodyState: 'تمت التسوية',
      status: archive ? 'مؤرشف' : 'تمت التسوية',
      doneMessage: archive
          ? 'تمت تسوية العهدة ونُقلت إلى الأرشيف'
          : 'تمت تسوية العهدة — تبقى ظاهرة بحالة «تمت التسوية»',
    );
  }

  Future<bool> _persistCustody(
    Map<String, String> details, {
    int? newAmount,
    String? newStatus,
  }) async {
    final item = widget.item;
    try {
      final updated = await widget.repository.update(
        PersonalEntryRecord(
          id: item.id,
          category: item.category,
          entryType: item.entryType ?? '',
          title: item.title,
          amount: newAmount ?? item.totalAmount,
          dueDate: item.dueDate,
          status: newStatus ?? item.status,
          details: details,
          attachmentUrl: item.attachmentPath,
        ),
      );
      if (!mounted) return false;
      setState(() {
        item.details = updated.details;
        item.totalAmount = updated.amount;
        item.status = updated.status;
        item.statusColor = _personalStatusColor(updated.status);
        item.lastUpdate = 'الآن';
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
      return false;
    }
  }

  /// إسناد العهدة إلى شخص آخر برقمه التعريفي — تنتقل إلى «بانتظار القبول»
  /// فيظهر له طلب قبول في تطبيقه.
  Future<void> _openCustodyAssignForm() async {
    final idController = TextEditingController();
    final noteController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إسناد العهدة لشخص',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'أدخل الرقم التعريفي للشخص (يجده في إعداداته). سيصله طلب '
                'قبول العهدة، وبعد قبوله يصرف منها وترى أنت كل حركة وفاتورة '
                'للقراءة فقط.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.7,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5C6B68),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: idController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                decoration: _editInputDecoration(
                  'الرقم التعريفي (FND-XXXX-XXXX)',
                  Icons.qr_code_2_rounded,
                ).copyWith(helperText: fndNameHint(), helperMaxLines: 3),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                decoration: _editInputDecoration(
                  'ملاحظة للمستلم (اختياري)',
                  Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E7161),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('إرسال طلب الإسناد'),
              ),
            ],
          ),
        ),
      ),
    );
    final targetId = AppIdentity.normalize(idController.text);
    final note = noteController.text.trim();
    idController.dispose();
    noteController.dispose();
    if (saved != true || !mounted) return;
    if (!AppIdentity.isValid(targetId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرقم التعريفي غير صحيح — الصيغة FND-XXXX-XXXX'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (targetId == AppIdentity.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إسناد العهدة إلى نفسك'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final now = DateTime.now();
    final assignment = CustodyAssignment(
      ownerId: AppIdentity.id,
      ownerName: AppSettings.instance.publicName,
      holderId: targetId,
      holderName: '',
      state: CustodyAssignmentState.pending,
      assignedAt: _stampNow(),
      note: note,
    );
    // رقم المستلم في البيانات يتبع الإسناد الجديد، فلا يبقى السابق مرتبطًا.
    final base = Map<String, String>.of(widget.item.details)
      ..[_custodyHolderIdLabel] = targetId;
    final ok = await _persistCustody(assignment.applyTo(base));
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('أُرسل طلب إسناد العهدة إلى $targetId\n${fndSentNote()}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// قبول أو رفض عهدة مُسندة إليّ.
  Future<void> _respondToCustodyAssignment({required bool accept}) async {
    // الطلب ما زال قائمًا وموجّهًا لي؟ (قد يكون المالك ألغاه أو أسنده لغيري.)
    final fresh = await _stillPendingForMe(
      widget.repository,
      widget.item.id,
      widget.item.details,
    );
    if (!mounted) return;
    if (fresh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يعد هذا الطلب قائمًا — حدّث الصفحة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final assignment = CustodyAssignment.decode(fresh);
    final updated = assignment.copyWith(
      state: accept
          ? CustodyAssignmentState.accepted
          : CustodyAssignmentState.rejected,
      holderName: accept
          ? AppSettings.instance.publicName
          : assignment.holderName,
    );
    // تاريخ ووقت الرد يظهران في سجل العهدة عند الطرفين.
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.day}/${now.month}/${now.year} ${two(now.hour)}:${two(now.minute)}';
    final ok = await _persistCustody(
      updated.applyTo(fresh)..[CustodyAssignment.kRespondedAt] = stamp,
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.item.entryType == 'عهدة مالية'
              ? (accept ? 'قبلت العهدة المالية' : 'رفضت العهدة المالية')
              : (accept ? 'قبلت مشاركة الدين' : 'رفضت مشاركة الدين'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// إلغاء الإسناد وإرجاع العهدة إلى صاحبها.
  Future<void> _cancelCustodyAssignment() async {
    final ok = await confirmAction(
      context,
      title: 'إلغاء الإسناد',
      message: 'ستعود العهدة إليك وتتوقف صلاحية الصرف عند الطرف الآخر. '
          'تبقى كل المصروفات المسجّلة كما هي. هل تريد المتابعة؟',
      danger: true,
      confirmLabel: 'إلغاء الإسناد',
    );
    if (!ok || !mounted) return;
    final cleared = Map<String, String>.of(widget.item.details);
    for (final key in CustodyAssignment.keys) {
      // يبقى صاحب العهدة معروفًا، فلا يتصرف فيها من كان مسندًا إليه.
      if (key == CustodyAssignment.kOwnerId ||
          key == CustodyAssignment.kOwnerName) {
        continue;
      }
      cleared.remove(key);
    }
    final done = await _persistCustody(cleared);
    if (!done || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('أُلغي الإسناد وعادت العهدة إليك'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// إضافة مبلغ إضافي على العهدة — للمالك وحده.
  Future<void> _openCustodyTopUpForm() async {
    if (_blockIfCustodyFrozen()) return;
    // زيادة مبلغ العهدة حقّ صاحبها الذي أسندها، لا المسند إليه.
    if (widget.item.status == 'تمت التسوية') {
      // سُوّيت وأُعيد متبقيها: الزيادة عليها تُفسد الحساب — عهدة جديدة.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('العهدة سُوّيت — ابدأ عهدة جديدة من القائمة ⋮'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_isCustodyOwnerView(widget.item.details) ||
        widget.item.status == 'ملغاة') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('زيادة مبلغ العهدة حقّ صاحبها وحده'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إضافة مبلغ للعهدة',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                textAlign: AppTr.alignEnd,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _editInputDecoration(
                  'المبلغ المضاف',
                  Icons.payments_outlined,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                textAlign: AppTr.alignEnd,
                decoration: _editInputDecoration(
                  'سبب الإضافة (اختياري)',
                  Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E7161),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('إضافة المبلغ'),
              ),
            ],
          ),
        ),
      ),
    );
    final amount = parseAmountInt(amountController.text);
    final note = noteController.text.trim();
    amountController.dispose();
    noteController.dispose();
    if (saved != true || !mounted) return;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل مبلغًا صحيحًا أكبر من صفر'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final now = DateTime.now();
    final rows = [
      ...CustodyTopUps.parse(widget.item.details),
      <String, String>{
        'المبلغ': '$amount',
        'السبب': note,
        'التاريخ': '${now.day}/${now.month}/${now.year}',
        _recordTimeKey: _clockNow(),
        'بواسطة': AppSettings.instance.publicName,
      },
    ];
    final details = Map<String, String>.of(widget.item.details)
      ..[CustodyTopUps.key] = CustodyTopUps.encode(rows);
    final ok = await _persistCustody(
      details,
      newAmount: widget.item.totalAmount + amount,
      newStatus: widget.item.status == 'تمت التسوية'
          ? 'نشطة'
          : widget.item.status,
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم الحفظ — أُضيف $amount ${widget.item.currency} إلى العهدة',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// العهدة المجمّدة: لا صرف ولا إضافة حتى يُلغي صاحبها التجميد.
  bool _blockIfCustodyFrozen() {
    if (widget.item.status != 'مجمّدة') return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('العهدة مجمّدة — لا صرف ولا إضافة حتى يُلغى التجميد'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  /// تجميد العهدة أو إلغاء تجميدها — لصاحبها من القائمة ⋮.
  Future<void> _toggleCustodyFreeze() async {
    final item = widget.item;
    if (!_isCustodyOwnerView(item.details)) return;
    final frozen = item.status == 'مجمّدة';
    final ok = await confirmAction(
      context,
      title: frozen ? 'إلغاء التجميد' : 'تجميد العهدة',
      message: frozen
          ? 'ستعود العهدة نشطة ويُصرف منها من جديد. هل تريد المتابعة؟'
          : 'سيتوقف الصرف من العهدة والإضافة عليها حتى تُلغي التجميد، '
                'وتبقى بياناتها وسجلها كما هي. هل تريد المتابعة؟',
      confirmLabel: frozen ? 'إلغاء التجميد' : 'تجميد',
      cancelLabel: 'رجوع',
    );
    if (!ok || !mounted) return;
    final saved = await _persistCustody(
      Map<String, String>.of(item.details),
      newStatus: frozen ? 'نشطة' : 'مجمّدة',
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          frozen ? 'أُلغي التجميد — العهدة نشطة' : 'جُمّدت العهدة',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openCustodySpendForm() async {
    if (_blockIfCustodyFrozen()) return;
    final item = widget.item;
    // الصرف حكر على المسند إليه بعد قبوله العهدة: صاحب العهدة يقرأ ويزيد
    // المبلغ فقط، ولا يُفتح له هذا النموذج حتى لو وصل إليه بأي طريق.
    if (!CustodyAssignment.decode(item.details).canSpend(AppIdentity.id) ||
        item.status == 'ملغاة' ||
        item.status == 'تمت التسوية') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الصرف من العهدة حقّ المسند إليه بعد قبولها'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final purposeController = TextEditingController();
    final now = DateTime.now();
    final dateController = TextEditingController(
      text: '${now.day}/${now.month}/${now.year}',
    );
    // ساعة الصرف: الآن افتراضيًا، وتُعدَّل إن صُرف في وقت سابق.
    final timeController = TextEditingController(
      text: '${_pad2(now.hour)}:${_pad2(now.minute)}',
    );
    var isSaving = false;
    // فاتورة الصرف: يرفعها المسند إليه، ويفتحها المالك للقراءة فقط.
    XFile? invoiceImage;
    const color = Color(0xFF0E7161);
    final currentRemaining = item.totalAmount - _custodyTotalSpent(item.details);
    // المستلم يرسل المصروف لاعتماد صاحب العهدة إن اشترط ذلك.
    final needsApproval =
        _custodyNeedsApproval(item.details) &&
        CustodyAssignment.decode(item.details).roleFor(AppIdentity.id) ==
            CustodyRole.holder;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setModalState(() => isSaving = true);
              // فاتورة الصرف تُرفع وحدها وتُربط ببند الصرف، فلا تستبدل مرفق
              // العهدة الأصلي.
              String? invoicePath;
              final repository = widget.repository;
              final invoice = invoiceImage;
              if (invoice != null &&
                  repository is SupabasePersonalEntriesRepository) {
                try {
                  invoicePath = await repository.uploadAttachment(invoice);
                } catch (_) {
                  invoicePath = null;
                }
              }
              final transactions = _parseCustodyTransactions(item.details)
                ..add({
                  if (invoicePath != null) _paymentInvoiceKey: invoicePath,
                  'المبلغ': '${parseAmountInt(amountController.text)}',
                  'الغرض': purposeController.text.trim(),
                  'التاريخ': dateController.text.trim(),
                  _recordTimeKey: timeController.text.trim().isEmpty
                      ? _clockNow()
                      : timeController.text.trim(),
                  // من صرف: يظهر للمالك في «إدارة العهدة».
                  'بواسطة': AppSettings.instance.publicName,
                  'معرّف المنفّذ': AppIdentity.id,
                  // يحتاج موافقة صاحب العهدة: لا يُخصم قبل اعتماده.
                  if (needsApproval)
                    _custodySpendStateKey: _custodySpendPending,
                });
              final encodedTransactions = _encodeCustodyTransactions(
                transactions,
              );
              final newRemaining =
                  item.totalAmount -
                  _custodyTotalSpent({
                    _custodyTransactionsDetailKey: encodedTransactions,
                  });
              final details = Map<String, String>.of(item.details)
                ..[_custodyTransactionsDetailKey] = encodedTransactions;
              final newStatus = newRemaining <= 0 ? 'تمت التسوية' : item.status;
              if (newRemaining <= 0) {
                details['حالة العهدة'] = 'تمت التسوية';
              }
              try {
                final updated = await widget.repository.update(
                  PersonalEntryRecord(
                    id: item.id,
                    category: item.category,
                    entryType: item.entryType ?? '',
                    title: item.title,
                    amount: item.totalAmount,
                    dueDate: item.dueDate,
                    status: newStatus,
                    details: details,
                    attachmentUrl: item.attachmentPath,
                  ),
                  // بلا مستودع Supabase (الاختبارات): الطريقة القديمة.
                  attachment: invoicePath == null &&
                          repository is! SupabasePersonalEntriesRepository
                      ? invoice
                      : null,
                );
                if (!mounted) return;
                Navigator.pop(sheetContext);
                setState(() {
                  item.details = updated.details;
                  item.attachmentPath =
                      updated.attachmentUrl ?? item.attachmentPath;
                  item.status = newStatus;
                  item.statusColor = _personalStatusColor(newStatus);
                  item.lastUpdate = 'الآن';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      needsApproval
                          ? 'أُرسل المصروف لاعتماد صاحب العهدة'
                          : newRemaining <= 0
                          ? 'تم حفظ الصرف — تمت تسوية العهدة بالكامل'
                          : 'تم حفظ الصرف، الرصيد المتبقي: $newRemaining ${widget.item.currency}',
                    ),
                  ),
                );
                // بلغ الصرف نسبة التنبيه المختارة: تذكير ورسالة.
                final alert = await _checkCustodyAlert(
                  id: item.id,
                  title: item.title,
                  total: item.totalAmount,
                  details: updated.details,
                );
                if (alert != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(alert),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
              } catch (error) {
                setModalState(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
              }
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: Directionality(
                  textDirection: AppTr.uiDir,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EAE8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'تسجيل صرف من العهدة',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF022E2A),
                                      ),
                                    ),
                                    Text(
                                      'الرصيد المتبقي حاليًا: $currentRemaining ${widget.item.currency} من أصل ${item.totalAmount} ${widget.item.currency}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5C6B68),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _custodyFieldDecoration(
                              'مبلغ الصرف',
                              Icons.payments_outlined,
                              color,
                            ),
                            validator: trValidator((value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'أدخل مبلغ الصرف';
                              }
                              if (parseAmountInt(value) <= 0) {
                                return 'أدخل رقمًا صحيحًا أكبر من صفر';
                              }
                              return null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: purposeController,
                            decoration: _custodyFieldDecoration(
                              'الغرض من الصرف',
                              Icons.flag_outlined,
                              color,
                            ),
                            validator: trValidator((value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'أدخل الغرض من الصرف'
                                : null),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: dateController,
                            readOnly: true,
                            decoration: _custodyFieldDecoration(
                              'تاريخ الصرف',
                              Icons.event_outlined,
                              color,
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: now,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 5),
                              );
                              if (picked != null) {
                                setModalState(
                                  () => dateController.text =
                                      '${picked.day}/${picked.month}/${picked.year}',
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: timeController,
                            readOnly: true,
                            decoration: _custodyFieldDecoration(
                              'ساعة الصرف',
                              Icons.schedule_rounded,
                              color,
                            ),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked != null) {
                                setModalState(
                                  () => timeController.text =
                                      '${_pad2(picked.hour)}:${_pad2(picked.minute)}',
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          // فاتورة الصرف: ترتبط بهذا البند تحديدًا ويفتحها
                          // مالك العهدة من «إدارة العهدة».
                          AppRemovableAttachment(
                            attached: invoiceImage != null,
                            onRemove: () => setModalState(() => invoiceImage = null),
                            child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final image = await DocumentStore.pickXFile(context, imageQuality: 85);
                                if (image == null) return;
                                setModalState(() => invoiceImage = image);
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'تعذر فتح المعرض — تحقق من إذن الوصول '
                                      'إلى الصور',
                                    ),
                                  ),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                            icon: Icon(
                              invoiceImage == null
                                  ? Icons.add_a_photo_outlined
                                  : Icons.check_circle_rounded,
                              size: 18,
                            ),
                            label: Text(
                              invoiceImage == null
                                  ? 'إرفاق فاتورة الصرف (اختياري)'
                                  : 'تم اختيار الفاتورة',
                            ),
                          ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isSaving ? null : save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'حفظ عملية الصرف',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // إنشاء سريع لأحد أنواع "تنظيم ومتابعة" (ملاحظات، تذكير، أو اسم يكتبه
  // المستخدم) من داخل شاشة تفاصيل الالتزام، مبني على نفس تعريف الحقول في
  // _financialEntryForms لكن بنموذج مبسّط بدون الحقول الإضافية القابلة للطي.
  Future<void> _openQuickOrganizationForm(String entryType) async {
    // إضافة باسم كتبه المستخدم ("+ إضافة أخرى"): تأخذ جدول التنظيم
    // والمتابعة نفسه بدل أن تُغلق الشاشة بلا شيء.
    final form =
        _financialEntryForms[entryType] ??
        _FinancialEntryForm(
          label: entryType,
          subtitle: 'إضافة إلى الالتزام',
          icon: Icons.add_task_rounded,
          color: const Color(0xFF0E7161),
          fields: _organizationFields,
        );
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in form.fields) field.label: TextEditingController(),
      // حقل نصّي مرافق لكل قائمة اختيار، يظهر عند اختيار "+ إضافة أخرى".
      // بدونه كان الخيار يُحفظ حرفيًا كنص "+ إضافة أخرى" في طريقة الدفع
      // والتكرار بلا أي وسيلة لكتابة القيمة الحقيقية.
      for (final field in form.fields)
        if (field.kind == _FinancialFieldKind.select)
          '${field.label} (مخصص)': TextEditingController(),
    };
    var isSaving = false;
    final isDelegateForm = entryType == 'تفويض';
    final delegateNames = isDelegateForm
        ? await _loadSavedPeopleNames()
        : const <String>[];
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final confirmed = await confirmAction(
                context,
                title: 'تأكيد الحفظ',
                message: 'هل تريد حفظ ${_savedLabel(entryType)}؟',
                confirmLabel: 'تأكيد',
              );
              if (!confirmed || !context.mounted) return;
              setModalState(() => isSaving = true);
              String valueFor(bool Function(_FinancialField) predicate) {
                for (final field in form.fields) {
                  if (predicate(field)) {
                    return controllers[field.label]!.text.trim();
                  }
                }
                return '';
              }

              final titleValue = valueFor((f) => f.isTitle);
              final dateValue = valueFor(
                (f) => f.kind == _FinancialFieldKind.date,
              );
              final details = <String, String>{
                for (final field in form.fields)
                  if (controllers[field.label]!.text.trim().isNotEmpty)
                    field.label: controllers[field.label]!.text.trim(),
              };
              // «مخصص»: القيمة المكتوبة بدل كلمة «مخصص».
              for (final field in form.fields) {
                final picked = details[field.label];
                final typed =
                    controllers['${field.label} (مخصص)']?.text.trim() ?? '';
                if (picked == kLeadCustomHours || picked == kLeadCustomDays) {
                  final value = reminderLeadValue(picked ?? '', typed);
                  if (value.isEmpty) {
                    details.remove(field.label);
                  } else {
                    details[field.label] = value;
                  }
                } else if ((picked == 'مخصص' || picked == '+ إضافة أخرى') &&
                    typed.isNotEmpty) {
                  details[field.label] = typed;
                }
              }
              try {
                await widget.repository.create(
                  PersonalEntryRecord(
                    category:
                        _PersonalCommitmentsScreenState
                            ._entryTypeCategorySlug[entryType] ??
                        'organization',
                    entryType: entryType,
                    title: titleValue.isEmpty ? entryType : titleValue,
                    // المبلغ يُقرأ من حقل المبلغ الفعلي (قيمة العهدة مثلًا)
                    // بدل تثبيته صفرًا فيفسد الرصيد المتبقي.
                    amount:
                        double.tryParse(
                          valueFor((f) => f.isAmount).replaceAll(',', ''),
                        )?.round() ??
                        0,
                    dueDate: dateValue,
                    status: 'نشطة',
                    details: _withCustodyAssignment(
                      entryType,
                      details,
                      _firstNonEmpty([
                        valueFor((f) => f.label == 'اسم المستلم'),
                        valueFor((f) => f.label == 'اسم الجهة'),
                      ]),
                    ),
                  ),
                );
                if (isDelegateForm && titleValue.isNotEmpty) {
                  await _savePersonName(titleValue);
                }
                if (!mounted) return;
                Navigator.pop(sheetContext);
                // ما يُضاف من المتابعة والتنظيم يُعرض في قسم «المتابعة».
                setState(() => _detailSectionIndex = 1);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حفظ ${_savedLabel(entryType)} بنجاح')),
                );
              } catch (error) {
                setModalState(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
              }
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: Directionality(
                  textDirection: AppTr.uiDir,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EAE8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: form.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(form.icon, color: form.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'إضافة ${form.label}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF022E2A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        start: 14,
                                      ),
                                      child: Text(
                                        form.subtitle,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5C6B68),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          for (final field in form.fields.where(
                            (field) =>
                                _PersonalCommitmentsScreenState
                                    ._isFieldVisible(field, controllers),
                          )) ...[
                            if (isDelegateForm && field.label == 'اسم المفوَّض')
                              _buildDelegateNameField(
                                field,
                                controllers[field.label]!,
                                color: form.color,
                                delegateNames: delegateNames,
                                setModalState: setModalState,
                              )
                            else
                              _outerLabelWrap(
                                field,
                                _buildQuickAddField(
                                  field,
                                  controllers[field.label]!,
                                  color: form.color,
                                  setModalState: setModalState,
                                  companion:
                                      controllers['${field.label} (مخصص)'],
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isSaving ? null : save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: form.color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'حفظ ${form.label}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // عرض عام مبسّط لأي حقل _FinancialField (بدون منطق الفئات الرئيسية/
  // الفرعية الخاص بنموذج الإضافة الكبير) — يكفي لأنواع تنظيم ومتابعة.
  Widget _buildQuickAddField(
    _FinancialField field,
    TextEditingController controller, {
    required Color color,
    required void Function(void Function()) setModalState,
    TextEditingController? companion,
  }) {
    final decoration = InputDecoration(
      labelText: field.half || field.required ? null : field.label,
      label: !field.half && field.required
          ? Text(
              '${field.label} *',
              maxLines: 3,
            )
          : null,
      hintText: field.hint == '#auto' || field.hint.isEmpty
          ? (field.half ? field.label : null)
          : field.hint,
      // خط أصغر وحيّز أيقونة أضيق ليظهر العنوان كاملًا في الحقول النصفية.
      isDense: true,
      labelStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      hintStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppTheme.muted,
      ),
      prefixIcon: Icon(
        field.icon,
        color: AppTheme.muted,
        size: field.half ? 17 : 20,
      ),
      prefixIconConstraints: BoxConstraints(
        minWidth: field.half ? 32 : 44,
        minHeight: field.half ? 32 : 44,
      ),
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1.4),
      ),
    );
    String? validator(String? value) {
      if (!field.required) return null;
      if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
      return null;
    }

    switch (field.kind) {
      case _FinancialFieldKind.select:
        {
        final dropdown = DropdownButtonFormField<String>(
          value: controller.text.isEmpty ? null : controller.text,
          isExpanded: true,
          decoration: decoration,
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setModalState(() => controller.text = v ?? ''),
          validator: validator,
        );
        // «مخصص» (والتذكير بالساعات أو الأيام): خانة لكتابة القيمة.
        final custom = controller.text == 'مخصص' ||
            controller.text == '+ إضافة أخرى' ||
            controller.text == kLeadCustomHours ||
            controller.text == kLeadCustomDays;
        if (companion == null || !custom) return dropdown;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dropdown,
            const SizedBox(height: 8),
            TextFormField(
              controller: companion,
              keyboardType: controller.text == kLeadCustomHours ||
                      controller.text == kLeadCustomDays
                  ? TextInputType.number
                  : null,
              decoration: InputDecoration(
                isDense: true,
                hintText: AppTr.tr(
                  controller.text == kLeadCustomHours
                      ? 'كم ساعة قبل الموعد؟'
                      : controller.text == kLeadCustomDays
                      ? 'كم يومًا قبل الموعد؟'
                      : 'اكتب القيمة',
                ),
              ),
            ),
          ],
        );
        }
      case _FinancialFieldKind.date:
        return TextFormField(
          controller: controller,
          readOnly: true,
          decoration: decoration,
          validator: validator,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setModalState(
                () => controller.text =
                    '${picked.day}/${picked.month}/${picked.year}',
              );
            }
          },
        );
      case _FinancialFieldKind.time:
        return TextFormField(
          controller: controller,
          readOnly: true,
          decoration: decoration,
          validator: validator,
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              setModalState(
                () => controller.text =
                    '${picked.hour.toString().padLeft(2, '0')}:'
                    '${picked.minute.toString().padLeft(2, '0')}',
              );
            }
          },
        );
      case _FinancialFieldKind.multiline:
        return TextFormField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: decoration,
          validator: validator,
        );
      case _FinancialFieldKind.secret:
        return TextFormField(
          controller: controller,
          obscureText: true,
          decoration: decoration,
          validator: validator,
        );
      case _FinancialFieldKind.number:
        return TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: decoration,
          validator: validator,
        );
      case _FinancialFieldKind.header:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            field.label,
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
        );
      case _FinancialFieldKind.toggle:
        final on = controller.text == 'نعم';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.field,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(field.icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  field.label,
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C2C29),
                  ),
                ),
              ),
              Switch.adaptive(
                value: on,
                activeThumbColor: color,
                onChanged: (value) =>
                    setModalState(() => controller.text = value ? 'نعم' : ''),
              ),
            ],
          ),
        );
      case _FinancialFieldKind.text:
        return TextFormField(
          controller: controller,
          decoration: decoration,
          validator: validator,
        );
    }
  }

  // حقل "اسم المفوَّض": نفس شكل الحقل النصي العادي، لكن مع زر بجانبه لاختيار
  // اسم من قائمة المفوَّضين المحفوظين مسبقًا بدل كتابة الاسم يدويًا في كل مرة.
  Widget _buildDelegateNameField(
    _FinancialField field,
    TextEditingController controller, {
    required Color color,
    required List<String> delegateNames,
    required void Function(void Function()) setModalState,
  }) {
    final decoration = InputDecoration(
      labelText: field.required ? null : field.label,
      label: field.required
          ? Text(
              '${field.label} *',
              maxLines: 3,
            )
          : null,
      hintText: AppTr.tr('اكتب اسمًا جديدًا أو اختر من القائمة المحفوظة'),
      prefixIcon: Icon(field.icon, color: color, size: 20),
      suffixIcon: delegateNames.isEmpty
          ? null
          : Directionality(
              textDirection: AppTr.uiDir,
              child: PopupMenuButton<String>(
                tooltip: AppTr.tr('اختر من الأسماء المحفوظة'),
                icon: Icon(Icons.arrow_drop_down_circle_outlined, color: color),
                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                onSelected: (value) =>
                    setModalState(() => controller.text = value),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Directionality(
                      textDirection: AppTr.uiDir,
                      child: Text(
                        'أسماء محفوظة مسبقًا',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8C9A97),
                        ),
                      ),
                    ),
                  ),
                  for (final name in delegateNames)
                    PopupMenuItem<String>(
                      value: name,
                      child: Directionality(
                        textDirection: AppTr.uiDir,
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 18,
                              color: color,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2C3B38),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1.4),
      ),
    );
    return TextFormField(
      controller: controller,
      decoration: decoration,
      validator: trValidator((value) {
        if (!field.required) return null;
        if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
        return null;
      }),
    );
  }

  void _openSubscriptionPaymentForm() {
    // الدائن لا يسدّد دينه بنفسه: السداد وإرفاق فاتورته حقّ المدين.
    if (widget.item.entryType == 'دين / قرض / سلفة' &&
        !_canRepayDebt(widget.item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السداد يسجّله المدين — لك الزيادة والمطالبة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final payerController = TextEditingController();
    final amountController = TextEditingController();
    final dateController = TextEditingController();
    XFile? invoiceImage;
    var isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: Directionality(
                  textDirection: AppTr.uiDir,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4EAE8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF34A894,
                                  ).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.add_card_rounded,
                                  color: Color(0xFF34A894),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'إضافة دفعة',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF022E2A),
                                      ),
                                    ),
                                    Text(
                                      'المتبقي ${widget.item.amount} ${widget.item.currency}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5C6B68),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: payerController,
                            textInputAction: TextInputAction.next,
                            decoration: _paymentInputDecoration(
                              'اسم الشخص الذي دفع',
                              Icons.person_outline_rounded,
                            ),
                            validator: trValidator((value) =>
                                value == null || value.trim().isEmpty
                                ? 'أدخل اسم الشخص الذي دفع'
                                : null),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: _paymentInputDecoration(
                              'مبلغ الدفعة',
                              Icons.payments_outlined,
                              suffixText: widget.item.currency,
                            ),
                            validator: trValidator((value) {
                              final amount = double.tryParse(
                                value?.trim() ?? '',
                              );
                              if (amount == null || amount <= 0) {
                                return 'أدخل مبلغ دفعة صحيحاً';
                              }
                              if (amount > widget.item.amount) {
                                return 'المبلغ أكبر من المتبقي';
                              }
                              return null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: dateController,
                            readOnly: true,
                            decoration: _paymentInputDecoration(
                              'تاريخ الدفع',
                              Icons.event_outlined,
                            ),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                dateController.text =
                                    '${date.day}/${date.month}/${date.year}';
                              }
                            },
                            validator: trValidator((value) => value == null || value.isEmpty
                                ? 'حدد تاريخ الدفع'
                                : null),
                          ),
                          const SizedBox(height: 12),
                          AppRemovableAttachment(
                            attached: invoiceImage != null,
                            onRemove: () => setModalState(() => invoiceImage = null),
                            child: InkWell(
                            onTap: () async {
                              final image = await DocumentStore.pickXFile(context, imageQuality: 82);
                              if (image != null) {
                                setModalState(() => invoiceImage = image);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7FAF9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: invoiceImage == null
                                      ? const Color(0xFFE4EAE8)
                                      : const Color(0xFF34A894),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    invoiceImage == null
                                        ? Icons.add_photo_alternate_outlined
                                        : Icons.check_circle_rounded,
                                    color: const Color(0xFF34A894),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      invoiceImage?.name ??
                                          'إضافة صورة من الفاتورة',
                                      maxLines: 3,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF2C3B38),
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_left_rounded,
                                    color: Color(0xFF8C9A97),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!(formKey.currentState?.validate() ??
                                          false)) {
                                        return;
                                      }
                                      if (invoiceImage == null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'يرجى إضافة صورة من الفاتورة',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      setModalState(() => isSaving = true);
                                      final paymentAmount = double.parse(
                                        amountController.text.trim(),
                                      ).round();
                                      final item = widget.item;
                                      // نفس أسلوب حفظ صرفيات العهدة: تُضاف
                                      // الدفعة الجديدة إلى السجل المُرمَّز
                                      // بصيغة JSON داخل details، ثم يُحفظ
                                      // القيد كاملاً عبر المستودع حتى لا
                                      // تختفي الدفعة عند إعادة التحميل من
                                      // الخادم (كانت سابقًا تُحفظ محليًا
                                      // فقط عبر setState دون أي اتصال
                                      // بقاعدة البيانات).
                                      // هوية من سجّل السداد تُحفظ مع الدفعة
                                      // ليعرف الطرف الآخر من دفع فعلًا.
                                      final newPayment = {
                                        'الدافع': payerController.text.trim(),
                                        'المبلغ': '$paymentAmount',
                                        'التاريخ': dateController.text.trim(),
                                        _recordTimeKey: _clockNow(),
                                        'سجّلها': AppSettings.instance.publicName,
                                        'معرّف المسجِّل': AppIdentity.id,
                                      };
                                      try {
                                        // الخطوة 1: رفع صورة الفاتورة (إن
                                        // وُجدت) وحفظ الدفعة الجديدة ضمن
                                        // السجل مباشرة. رفع الملف هنا يحدّث
                                        // أيضًا المرفق العام الوحيد للقيد،
                                        // لأن جدول personal_entries يحتفظ
                                        // بمسار مرفق واحد فقط لكل قيد.
                                        final firstPass =
                                            _parseSubscriptionPayments(
                                              item.details,
                                            )..insert(0, newPayment);
                                        var updated = await widget.repository
                                            .update(
                                              PersonalEntryRecord(
                                                id: item.id,
                                                category: item.category,
                                                entryType: item.entryType ?? '',
                                                title: item.title,
                                                amount: item.totalAmount,
                                                dueDate: item.dueDate,
                                                status: item.status,
                                                details:
                                                    Map<String, String>.of(
                                                        item.details,
                                                      )
                                                      ..[_subscriptionPaymentsDetailKey] =
                                                          _encodeSubscriptionPayments(
                                                            firstPass,
                                                          ),
                                                attachmentUrl:
                                                    item.attachmentPath,
                                              ),
                                              attachment: invoiceImage,
                                            );
                                        // الخطوة 2: بعد معرفة مسار الفاتورة
                                        // المرفوعة فعليًا على الخادم، تُدمَج
                                        // داخل عنصر هذه الدفعة تحديدًا (لا
                                        // تكتفي بالمرفق العام) حتى تبقى
                                        // مرتبطة بها وتظهر عند إعادة التحميل.
                                        if (invoiceImage != null &&
                                            updated.attachmentUrl != null) {
                                          newPayment[_paymentInvoiceKey] =
                                              updated.attachmentUrl!;
                                          final finalPayments =
                                              _parseSubscriptionPayments(
                                                updated.details,
                                              );
                                          if (finalPayments.isNotEmpty) {
                                            finalPayments[0] = newPayment;
                                          }
                                          updated = await widget.repository
                                              .update(
                                                PersonalEntryRecord(
                                                  id: item.id,
                                                  category: item.category,
                                                  entryType:
                                                      item.entryType ?? '',
                                                  title: item.title,
                                                  amount: item.totalAmount,
                                                  dueDate: item.dueDate,
                                                  status: item.status,
                                                  details:
                                                      Map<String, String>.of(
                                                          updated.details,
                                                        )
                                                        ..[_subscriptionPaymentsDetailKey] =
                                                            _encodeSubscriptionPayments(
                                                              finalPayments,
                                                            ),
                                                  attachmentUrl:
                                                      updated.attachmentUrl,
                                                ),
                                              );
                                        }
                                        final newPaidAmount =
                                            _subscriptionTotalPaid(
                                              updated.details,
                                            );
                                        if (!mounted) return;
                                        Navigator.pop(context);
                                        setState(() {
                                          item.details = updated.details;
                                          item.paidAmount = newPaidAmount;
                                          item.progress =
                                              (newPaidAmount /
                                                      item.totalAmount)
                                                  .clamp(0.0, 1.0);
                                          item.lastUpdate =
                                              dateController.text;
                                          item.attachmentPath =
                                              updated.attachmentUrl;
                                          item.payments.insert(
                                            0,
                                            _SubscriptionPayment(
                                              payerName: payerController.text
                                                  .trim(),
                                              amount: paymentAmount,
                                              date: dateController.text,
                                              invoiceImagePath:
                                                  newPayment[_paymentInvoiceKey],
                                            ),
                                          );
                                        });
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'تم حفظ الدفعة بنجاح',
                                            ),
                                          ),
                                        );
                                      } catch (_) {
                                        setModalState(() => isSaving = false);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'تعذر حفظ الدفعة. حاول مرة أخرى.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text(
                                'حفظ الدفعة',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34A894),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      payerController.dispose();
      amountController.dispose();
      dateController.dispose();
    });
  }

  InputDecoration _paymentInputDecoration(
    String label,
    IconData icon, {
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
      prefixIcon: Icon(icon, size: 19, color: AppTheme.muted),
      suffixText: suffixText,
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF34A894), width: 1.5),
      ),
    );
  }

  Future<void> _openEditForm() async {
    final item = widget.item;
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: item.title);
    final amountController = TextEditingController(
      text: item.totalAmount.toString(),
    );
    final dueDateController = TextEditingController(text: item.dueDate);
    final detailControllers = <String, TextEditingController>{
      for (final entry in item.details.entries)
        if (!const {
          _addedAttachmentTypeKey,
          _addedAttachmentNameKey,
          _custodyTransactionsDetailKey,
          _subscriptionPaymentsDetailKey,
          _custodyLogKey,
        }.contains(entry.key))
          entry.key: TextEditingController(text: entry.value),
    };
    var selectedStatus = item.status;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: Directionality(
              textDirection: AppTr.uiDir,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD5DEDB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: item.iconBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(item.icon, color: item.iconColor),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تعديل الالتزام',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF022E2A),
                                  ),
                                ),
                                Text(
                                  'حدّث البيانات ثم احفظ التغييرات',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5C6B68),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: AppTr.tr('إغلاق'),
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: titleController,
                        decoration: _editInputDecoration(
                          'اسم الالتزام',
                          Icons.title_rounded,
                        ),
                        validator: trValidator((value) =>
                            value == null || value.trim().isEmpty
                            ? 'يرجى إدخال اسم الالتزام'
                            : null),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _editInputDecoration(
                          'المبلغ',
                          Icons.payments_outlined,
                          suffixText: widget.item.currency,
                        ),
                        validator: trValidator((value) {
                          final amount = double.tryParse(value?.trim() ?? '');
                          return amount == null || amount < 0
                              ? 'أدخل مبلغاً صحيحاً'
                              : null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: dueDateController,
                        readOnly: true,
                        decoration: _editInputDecoration(
                          'تاريخ الاستحقاق',
                          Icons.event_outlined,
                        ),
                        onTap: () async {
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: sheetContext,
                            initialDate: now,
                            firstDate: DateTime(now.year - 20),
                            lastDate: DateTime(now.year + 20),
                          );
                          if (date != null) {
                            dueDateController.text =
                                '${date.day}/${date.month}/${date.year}';
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: _editInputDecoration(
                          'الحالة',
                          Icons.flag_outlined,
                        ),
                        items:
                            // الحالة الحالية تُضاف دائمًا، فلا ينهار النموذج
                            // عند فتح التزام مؤرشف أو مسوّى أو ملغى.
                            <String>{
                                  'نشطة',
                                  'قريبة الاستحقاق',
                                  'متأخرة',
                                  'مكتملة',
                                  'مؤرشف',
                                  'ملغاة',
                                  'تمت التسوية',
                                  selectedStatus,
                                }
                                .map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) selectedStatus = value;
                        },
                      ),
                      if (detailControllers.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'بيانات الالتزام',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final entry in detailControllers.entries) ...[
                          TextFormField(
                            controller: entry.value,
                            obscureText: _isSensitiveDetail(entry.key),
                            minLines: entry.key.contains('ملاحظ') ? 3 : 1,
                            maxLines: entry.key.contains('ملاحظ') ? 4 : 1,
                            decoration: _editInputDecoration(
                              entry.key,
                              Icons.edit_note_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }
                                setModalState(() => isSaving = true);
                                try {
                                  final updated = await widget.repository.update(
                                    PersonalEntryRecord(
                                      id: item.id,
                                      category: item.category,
                                      entryType: item.entryType ?? '',
                                      title: titleController.text.trim(),
                                      amount: double.parse(
                                        amountController.text.trim(),
                                      ).round(),
                                      dueDate: dueDateController.text.trim(),
                                      status: selectedStatus,
                                      details: {
                                        for (final entry
                                            in detailControllers.entries)
                                          if (entry.value.text
                                              .trim()
                                              .isNotEmpty)
                                            entry.key: entry.value.text.trim(),
                                        // السجلات المحفوظة (دفعات الاشتراك
                                        // وصرفيات العهدة والمرفق) ليست ضمن
                                        // حقول التحرير، فتُنقل كما هي حتى لا
                                        // يمسحها التعديل.
                                        for (final key in const [
                                          _addedAttachmentTypeKey,
                                          _addedAttachmentNameKey,
                                          _custodyTransactionsDetailKey,
                                          _subscriptionPaymentsDetailKey,
                                          _custodyLogKey,
                                        ])
                                          if (item.details[key] != null)
                                            key: item.details[key]!,
                                      },
                                      attachmentUrl: item.attachmentPath,
                                    ),
                                  );
                                  if (!mounted) return;
                                  setState(() {
                                    item.title = updated.title;
                                    item.totalAmount = updated.amount;
                                    item.dueDate = updated.dueDate;
                                    item.status = updated.status;
                                    item.statusColor = _personalStatusColor(
                                      updated.status,
                                    );
                                    item.details = updated.details;
                                    item.lastUpdate = 'الآن';
                                  });
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم حفظ التعديل بنجاح'),
                                    ),
                                  );
                                } catch (_) {
                                  if (sheetContext.mounted) {
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تعذر تحديث الالتزام. حاول مرة أخرى.',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (sheetContext.mounted) {
                                    setModalState(() => isSaving = false);
                                  }
                                }
                              },
                        icon: isSaving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          isSaving ? 'جارٍ حفظ التغييرات...' : 'حفظ التغييرات',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFF0A5A50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    titleController.dispose();
    amountController.dispose();
    dueDateController.dispose();
    for (final controller in detailControllers.values) {
      controller.dispose();
    }
  }

  InputDecoration _editInputDecoration(
    String label,
    IconData icon, {
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF0A5A50)),
      suffixText: suffixText,
      filled: true,
      fillColor: AppTheme.field,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.rField),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0A5A50), width: 1.5),
      ),
    );
  }

  bool _isSensitiveDetail(String label) {
    return label.contains('كلمة المرور') ||
        label.contains('رقم الحساب') ||
        label.contains('الآيبان');
  }

  @override
  Widget build(BuildContext context) => _buildUnifiedDetails(context);

  Widget _buildUnifiedDetails(BuildContext context) {
    final item = widget.item;
    final color = _pageColor;

    return Scaffold(
      backgroundColor: AppTheme.page,
      // نفس شكل زر "+ إضافة" في صفحة الالتزامات الشخصية (مستطيل مدوّر
      // بأيقونة ونص)، لكن بلون مختلف وبدون خاصية السحب/التحول من مكانه —
      // زر ثابت في مكانه دائمًا، حسب الطلب.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-commitment-attachment'),
        tooltip: AppTr.tr('إضافة إلى الالتزام'),
        onPressed: _openAddAttachmentMenu,
        backgroundColor: const Color(0xFFF2A93F),
        foregroundColor: const Color(0xFF4A2F09),
        elevation: 7,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          '+ إضافة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F1F1C),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text(
          'تفاصيل ${item.entryType ?? 'الالتزام'}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F1F1C),
          ),
        ),
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: Stack(
          fit: StackFit.expand,
          children: [
        ListView(
          key: const ValueKey('compact-personal-details'),
          controller: _detailsScroll,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          children: [
            // مستطيل واحد موحّد (بدل مستطيلين منفصلين): صف العنوان/الحالة
            // متبوعًا بخط رفيع احترافي ثم صف بيانات الفئة (المبلغ/التاريخ/
            // جهة الصرف مثلًا)، بنفس لون النص في الجزأين.
            Container(
              key: const ValueKey('compact-details-header'),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CompactCommitmentHeader(
                    item: item,
                    color: color,
                    onAction: _handleMenuAction,
                  ),
                  Container(
                    height: 1,
                    color: const Color(0xFFF2F6F5),
                  ),
                  _CategoryHighlightBar(item: item, color: color),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _InlineDetailsTabs(
              sections: _sectionsFor(item),
              selectedIndex: _detailSectionIndex,
              color: color,
              onSelected: (index) =>
                  setState(() => _detailSectionIndex = index),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_detailSectionIndex),
                child: _buildSelectedSection(item, color),
              ),
            ),
          ],
        ),
            if (item.entryType == 'عهدة مالية')
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _compactHeader,
                  builder: (context, compact, _) => IgnorePointer(
                    ignoring: !compact,
                    child: AnimatedOpacity(
                      opacity: compact ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: _buildCompactScrollHeader(item, color),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// الشريط المختصر عند التمرير: الاسم، و«عهدة مالية» وحالتها فقط.
  Widget _buildCompactScrollHeader(_CommitmentItem item, Color color) {
    return Material(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                  Text(
                    item.entryType ?? 'التزام شخصي',
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: item.statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// أقسام صفحة التفاصيل لهذا الالتزام: العهدة المالية تنفرد بتبويب
  /// «إدارة العهدة» بجانب الملخص، وبقية الأنواع أربعة أقسام.
  List<({String label, IconData icon})> _sectionsFor(_CommitmentItem item) {
    final sections = [..._detailSections];
    if (item.entryType == 'عهدة مالية') {
      sections.insert(1, (
        label: _custodySectionLabel,
        icon: Icons.manage_accounts_outlined,
      ));
    }
    if (item.entryType == 'دين / قرض / سلفة') {
      sections.insert(1, (
        label: 'إدارة الديون',
        icon: Icons.handshake_outlined,
      ));
    }
    return sections;
  }

  Widget _buildSelectedSection(_CommitmentItem item, Color color) {
    final sections = _sectionsFor(item);
    final index = _detailSectionIndex.clamp(0, sections.length - 1);
    final label = sections[index].label;
    // المصروفات داخل البطاقة نفسها تحت خط رفيع.
    if (label == _custodySectionLabel) return _buildCustodyOverviewCard(item);
    if (label == 'إدارة الديون') return _buildDebtManagementSection(item);

    if (label.startsWith('المتابعة')) {
      return _buildFollowupPlanningSection(item, color);
    }
    if (label == 'المستندات') return _buildDocumentsSection(item, color);
    if (label == 'السجل') return _HistoryDetailsCard(item: item, color: color);
    return _SummaryDetailsCard(
      item: item,
      color: color,
      expanded: _showAllDetails,
      isSensitive: _isSensitiveDetail,
      onToggleExpanded: () =>
          setState(() => _showAllDetails = !_showAllDetails),
    );
  }

  /// بطاقة الطرف الثاني في الدين: اسمه ورقمه وحالة القبول، ومنها يقبل
  /// الطرف الثاني الدعوة فيصير سداده ظاهرًا عند صاحب الدين.
  Widget _buildSharedPartyCard(_CommitmentItem item) {
    final assignment = CustodyAssignment.decode(item.details);
    final role = assignment.roleFor(AppIdentity.id);
    final stateColor = switch (assignment.state) {
      CustodyAssignmentState.pending => AppTheme.goldDark,
      CustodyAssignmentState.accepted => AppTheme.brandMid,
      CustodyAssignmentState.rejected => AppTheme.danger,
      CustodyAssignmentState.none => AppTheme.muted,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.handshake_outlined,
                size: 19,
                color: AppTheme.brandMid,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'الطرف الثاني',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  assignment.stateLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: stateColor,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppTr.tr('تحديث من الخادم'),
                visualDensity: VisualDensity.compact,
                onPressed: _refreshItemFromServer,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 19,
                  color: AppTheme.brandMid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _leaseLikeRow(
            'الاسم',
            assignment.holderName.isEmpty ? 'غير محدد' : assignment.holderName,
          ),
          _leaseLikeRow('الرقم التعريفي', assignment.holderId),
          _leaseLikeRow('صاحب الدين', assignment.ownerName),
          if ((assignment.isAccepted || assignment.isRejected) &&
              (item.details[CustodyAssignment.kRespondedAt] ?? '').isNotEmpty)
            _leaseLikeRow(
              assignment.isAccepted ? 'تاريخ ووقت القبول' : 'تاريخ ووقت الرفض',
              item.details[CustodyAssignment.kRespondedAt]!,
            ),
          if (role == CustodyRole.holder && assignment.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandMid,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () =>
                        _respondToCustodyAssignment(accept: true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'قبول المشاركة',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size.fromHeight(42),
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                    onPressed: () =>
                        _respondToCustodyAssignment(accept: false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('رفض', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
          // صاحب الدين يرسل مطالبة أو تذكيرًا للطرف الثاني، ويُسجَّل ذلك
          // في متابعة الدين نفسه حتى يبقى له أثر.
          if (assignment.isAccepted && role != CustodyRole.holder) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.goldDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () => _sendDebtNotice(item, demand: true),
                    icon: const Icon(Icons.request_quote_outlined, size: 17),
                    label: const Text(
                      'إرسال مطالبة',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () => _sendDebtNotice(item, demand: false),
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 17,
                    ),
                    label: const Text(
                      'إرسال تذكير',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (assignment.isAccepted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'كل سداد يسجّله أحد الطرفين يظهر عند الآخر بعد التحديث.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// هل أنا الدائن في هذا الدين؟ الدائن هو من أنشأ الدين وأسنده، أو مَن
  /// لم يُسند دينه لأحد بعد.
  bool _isDebtCreditor(_CommitmentItem item) {
    final role = CustodyAssignment.decode(item.details).roleFor(AppIdentity.id);
    // «لي — يدين لي»: صاحب السجل هو الدائن. «له — أدين له»: الطرف الآخر.
    final ownerIsCreditor =
        !(item.details['نوع الدين'] ?? '').trim().startsWith('له');
    return switch (role) {
      CustodyRole.owner || CustodyRole.soleOwner => ownerIsCreditor,
      CustodyRole.holder => !ownerIsCreditor,
      CustodyRole.observer => false,
    };
  }

  /// من يسجّل سداد الدين: المدين، وبعد قبول الطرف الآخر للربط إن كان مرتبطًا.
  bool _canRepayDebt(_CommitmentItem item) {
    final assignment = CustodyAssignment.decode(item.details);
    final role = assignment.roleFor(AppIdentity.id);
    if (role == CustodyRole.observer) return false;
    if (role == CustodyRole.holder && !assignment.isAccepted) return false;
    // ربط لم يُقبل (أو رُفض): صاحب السجل يسجّل كل شيء بنفسه.
    if (!assignment.isAccepted) return true;
    return !_isDebtCreditor(item);
  }

  /// قسم «إدارة الديون»: حالة الإسناد، ثم أرقام الدين ودفعاته وفواتيره،
  /// وأزرار كل طرف حسب دوره — الدائن يزيد ويطالب، والمدين يسدّد ويرفق.
  Widget _buildDebtManagementSection(_CommitmentItem item) {
    final assignment = CustodyAssignment.decode(item.details);
    final isCreditor = _isDebtCreditor(item);
    final payments = _parseSubscriptionPayments(item.details);
    final paid = _subscriptionTotalPaid(item.details);
    final remaining = item.totalAmount - paid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assignment.isAssigned) ...[
          _buildSharedPartyCard(item),
          const SizedBox(height: 12),
        ] else
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppTheme.goldSoft,
              borderRadius: BorderRadius.circular(AppTheme.rCard),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 19,
                  color: AppTheme.goldDark,
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'هذا الدين غير مرتبط بأحد — اكتب الرقم التعريفي للمدين '
                    'في تعديل الدين ليصله طلب الموافقة.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.goldDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: AppTr.uiDir,
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 19,
                    color: AppTheme.brandMid,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الدفعات (${payments.length})',
                      textAlign: AppTr.alignEnd,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppTr.tr('تحديث من الخادم'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _refreshItemFromServer,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 19,
                      color: AppTheme.brandMid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: AppTheme.hairline),
              const SizedBox(height: 10),
              _leaseLikeRow(
                'إجمالي الدين',
                '${item.totalAmount} ${widget.item.currency}',
              ),
              _leaseLikeRow(
                'المسدَّد',
                '$paid ${widget.item.currency}',
              ),
              _leaseLikeRow(
                'المتبقي',
                '$remaining ${widget.item.currency}',
              ),
              const SizedBox(height: 10),
              if (payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'لا توجد دفعات بعد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                )
              else
                for (final payment in payments.reversed)
                  _custodyLogRow(
                    icon: Icons.check_circle_outline_rounded,
                    color: AppTheme.brandMid,
                    line1:
                        '${payment['المبلغ'] ?? '0'} '
                        '${widget.item.currency}',
                    line2: [
                      if ((payment['التاريخ'] ?? '').isNotEmpty)
                        _withTime(
                          payment['التاريخ']!,
                          payment[_recordTimeKey],
                        ),
                      if ((payment['سجّلها'] ?? '').isNotEmpty)
                        'سجّلها ${payment['سجّلها']}'
                      else if ((payment['الدافع'] ?? '').isNotEmpty)
                        payment['الدافع']!,
                    ].join(' · '),
                    invoicePath: payment[_paymentInvoiceKey],
                  ),
              const SizedBox(height: 6),
              // الدائن لا يسدّد دينه بنفسه: له الزيادة والمطالبة فقط،
              // والسداد وإرفاق فاتورته عند المدين.
              if (isCreditor)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: _openDebtIncreaseForm,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: const Text(
                    'زيادة على الدين',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                  ),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: _openSubscriptionPaymentForm,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text(
                    'تسجيل سداد / سداد جزئي',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// مطالبة مالية أو تذكير للطرف الثاني في الدين: تُشارَك برسالة عبر أي
  /// تطبيق، وتُسجَّل في متابعة الدين ليبقى لها أثر عند الطرفين.
  Future<void> _sendDebtNotice(
    _CommitmentItem item,
    {required bool demand}
  ) async {
    final assignment = CustodyAssignment.decode(item.details);
    final label = demand ? 'مطالبة مالية' : 'تذكير بالسداد';
    final ok = await confirmAction(
      context,
      title: label,
      message: demand
          ? 'ستُرسل مطالبة بسداد «${item.title}» إلى '
                '${assignment.holderName}، وتُسجَّل في متابعة الدين.'
          : 'سيُرسل تذكير بموعد «${item.title}» إلى '
                '${assignment.holderName}، ويُسجَّل في متابعة الدين.',
      confirmLabel: 'إرسال',
    );
    if (!ok || !mounted) return;
    final now = DateTime.now();
    final stamp =
        '${now.day}/${now.month}/${now.year}';
    final body = [
      '$label — ${item.title}',
      if (item.totalAmount > 0)
        'المبلغ: ${item.totalAmount} ${widget.item.currency}',
      if (item.dueDate.isNotEmpty) 'تاريخ الاستحقاق: ${item.dueDate}',
      'من: ${AppSettings.instance.publicName} (${AppIdentity.id})',
    ].join('\n');
    final rows = [
      ..._parseFollowupRows(item.details),
      {
        'النوع': label,
        'العنوان': '$label إلى ${assignment.holderName}',
        'التفاصيل': body,
        'التاريخ': stamp,
        'الوقت': _clockNow(),
      },
    ];
    final details = Map<String, String>.of(item.details)
      ..[_followupLogKey] = jsonEncode(rows);
    await _persistDetails(details);
    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(subject: label, text: body));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('أُرسلت $label وسُجّلت في المتابعة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// إضافة مستند: اختيار الملف ثم تاريخ انتهائه ليظهر في مستطيل المستند.
  Future<void> _addDocument() async {
    XFile? picked;
    try {
      picked = await DocumentStore.pickXFile(context, imageQuality: 88);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
      return;
    }
    if (picked == null || !mounted) return;
    final added = await _saveAddedAttachment('مستند', picked);
    if (added == null || !mounted) return;
    final now = DateTime.now();
    final expiry = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      helpText: AppTr.tr('تاريخ انتهاء المستند (اختياري)'),
    );
    if (expiry == null || !mounted) return;
    final stamp = '${expiry.day}/${expiry.month}/${expiry.year}';
    final details = Map<String, String>.of(widget.item.details);
    if (added.isEmpty) {
      details[_addedAttachmentExpiryKey] = stamp;
    } else {
      // تاريخ انتهاء المستند الإضافي نفسه.
      final rows = [
        for (final row in _parseExtraAttachments(details))
          row['id'] == added ? {...row, 'expiry': stamp} : row,
      ];
      details[_extraAttachmentsKey] = jsonEncode(rows);
    }
    await _persistDetails(details);
  }

  /// حذف المستند الأول بعد تأكيد — ثم يُرفع غيره من «+».
  Future<void> _deleteMainDocument() async {
    final ok = await confirmAction(
      context,
      title: 'حذف المستند',
      message: 'سيُحذف هذا المستند من الالتزام. هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !mounted) return;
    final item = widget.item;
    final previous = item.attachmentPath;
    item.attachmentPath = null;
    final details = Map<String, String>.of(item.details)
      ..remove(_addedAttachmentTypeKey)
      ..remove(_addedAttachmentNameKey)
      ..remove(_addedAttachmentExpiryKey);
    final saved = await _persistDetails(details);
    if (!mounted) return;
    if (!saved) {
      setState(() => item.attachmentPath = previous);
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف المستند')),
    );
  }

  /// حذف مستند إضافي بعد تأكيد.
  Future<void> _deleteExtraDocument(String id) async {
    if (id.isEmpty) return;
    final ok = await confirmAction(
      context,
      title: 'حذف المستند',
      message: 'سيُحذف هذا المستند من الالتزام. هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !mounted) return;
    final rows = _parseExtraAttachments(widget.item.details)
        .where((row) => row['id'] != id)
        .toList(growable: false);
    final details = Map<String, String>.of(widget.item.details);
    if (rows.isEmpty) {
      details.remove(_extraAttachmentsKey);
    } else {
      details[_extraAttachmentsKey] = jsonEncode(rows);
    }
    final saved = await _persistDetails(details);
    if (!saved || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف المستند')),
    );
  }

  /// قسم المستندات: العنوان وعلى يساره «+»، وتحته المستندات أو «لا توجد
  /// مستندات»، ومع كل مستند تاريخ انتهائه إن وُجد.
  Widget _buildDocumentsSection(_CommitmentItem item, Color color) {
    final path = item.attachmentPath;
    final hasDocument = path != null && path.trim().isNotEmpty;
    final extras = _parseExtraAttachments(item.details)
        .where((row) => (row['path'] ?? '').trim().isNotEmpty)
        .toList(growable: false);
    final name = (item.details[_addedAttachmentNameKey] ?? '').trim();
    final type = (item.details[_addedAttachmentTypeKey] ?? '').trim();
    final expiry = (item.details[_addedAttachmentExpiryKey] ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(Icons.folder_outlined, size: 19, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'المستندات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              Material(
                color: AppTheme.brandSoft,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _addDocument,
                  child: const SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: AppTheme.brandMid,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppTheme.hairline),
          const SizedBox(height: 10),
          if (!hasDocument && extras.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'لا توجد مستندات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else if (hasDocument)
            InkWell(
              onTap: () => _openInvoiceImage(context, path!),
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceInner,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                  border: Border.all(color: AppTheme.hairline),
                ),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Icon(Icons.description_outlined, size: 20, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            name.isEmpty
                                ? (type.isEmpty ? 'مستند محفوظ' : type)
                                : name,
                            textAlign: AppTr.alignEnd,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            expiry.isEmpty
                                ? 'اضغط لفتح المستند'
                                : 'تاريخ الانتهاء: $expiry',
                            textAlign: AppTr.alignEnd,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: expiry.isEmpty
                                  ? AppTheme.muted
                                  : AppTheme.goldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: AppTheme.brandMid,
                    ),
                    IconButton(
                      tooltip: AppTr.tr('حذف المستند'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _deleteMainDocument,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // المستندات الإضافية: كلها هنا، ولا يستبدل الجديد القديم.
          for (final row in extras) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openInvoiceImage(context, row['path']!.trim()),
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceInner,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                  border: Border.all(color: AppTheme.hairline),
                ),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Icon(Icons.description_outlined, size: 20, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            (row['name'] ?? '').trim().isEmpty
                                ? ((row['type'] ?? '').trim().isEmpty
                                      ? 'مستند محفوظ'
                                      : row['type']!.trim())
                                : row['name']!.trim(),
                            textAlign: AppTr.alignEnd,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (row['expiry'] ?? '').trim().isEmpty
                                ? 'اضغط لفتح المستند'
                                : '${AppTr.tr('تاريخ الانتهاء')}: '
                                      '${row['expiry']!.trim()}',
                            textAlign: AppTr.alignEnd,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: (row['expiry'] ?? '').trim().isEmpty
                                  ? AppTheme.muted
                                  : AppTheme.goldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: AppTheme.brandMid,
                    ),
                    IconButton(
                      tooltip: AppTr.tr('حذف المستند'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteExtraDocument(row['id'] ?? ''),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// حفظ التفاصيل كما هي — سجل المتابعة والمستندات يمرّان من هنا.
  Future<bool> _persistDetails(Map<String, String> details) =>
      _persistCustody(details);

  /// إضافة صف إلى سجل المتابعة والتنظيم (ملاحظة، تذكير، مهمة، أخرى...).
  Future<void> _addFollowupRow(String type) async {
    final titleController = TextEditingController();
    final detailsController = TextEditingController();
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إضافة $type',
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                textDirection: AppTr.uiDir,
                decoration: InputDecoration(
                  label: const Text('العنوان *'),
                  prefixIcon: const Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailsController,
                textDirection: AppTr.uiDir,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: AppTr.tr('التفاصيل'),
                  hintText: AppTr.tr('أوصف $type'),
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('التاريخ'),
                        prefixIcon: const Icon(Icons.event_outlined),
                      ),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null) {
                          dateController.text =
                              '${picked.day}/${picked.month}/${picked.year}';
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: timeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('الوقت'),
                        prefixIcon: const Icon(Icons.schedule_rounded),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          final hour = picked.hour.toString().padLeft(2, '0');
                          final minute = picked.minute.toString().padLeft(
                            2,
                            '0',
                          );
                          timeController.text = '$hour:$minute';
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('اكتب العنوان أولًا')),
                    );
                    return;
                  }
                  final confirmed = await confirmAction(
                    sheetContext,
                    title: 'تأكيد الحفظ',
                    message: 'هل تريد حفظ ${_savedLabel(type)}؟',
                    confirmLabel: 'تأكيد',
                  );
                  if (!confirmed || !sheetContext.mounted) return;
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('حفظ'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
    final row = <String, String>{
      'النوع': type,
      'العنوان': titleController.text.trim(),
      'التفاصيل': detailsController.text.trim(),
      'التاريخ': dateController.text.trim(),
      'الوقت': timeController.text.trim(),
    };
    titleController.dispose();
    detailsController.dispose();
    dateController.dispose();
    timeController.dispose();
    if (saved != true) return;
    final rows = [..._parseFollowupRows(widget.item.details), row];
    final details = Map<String, String>.of(widget.item.details)
      ..[_followupLogKey] = jsonEncode(rows);
    final ok = await _persistDetails(details);
    if (!ok || !mounted) return;
    setState(() => _detailSectionIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حفظ ${_savedLabel(type)} بنجاح'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// حذف صف من سجل المتابعة بعد تأكيد.
  Future<void> _deleteFollowupRow(Map<String, String> row) async {
    final ok = await confirmAction(
      context,
      title: 'حذف من المتابعة',
      message: 'سيُحذف «${row['العنوان'] ?? ''}» نهائيًا. هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok) return;
    final rows = _parseFollowupRows(widget.item.details).toList();
    rows.removeWhere(
      (existing) =>
          existing['العنوان'] == row['العنوان'] &&
          existing['النوع'] == row['النوع'] &&
          existing['التاريخ'] == row['التاريخ'],
    );
    final details = Map<String, String>.of(widget.item.details)
      ..[_followupLogKey] = jsonEncode(rows);
    final saved = await _persistDetails(details);
    if (!saved || !mounted) return;
    setState(() {});
  }

  /// فلترا قسم «المتابعة والتخطيط» — نفس شكل تفاصيل الفرد.
  String _followKind = 'الكل';
  String _followStatus = 'الأحدث أولاً';

  static const List<(String, IconData)> _followKinds = [
    ('مهمة', Icons.task_alt_outlined),
    ('موعد', Icons.event_outlined),
    ('عادة', Icons.repeat_rounded),
    ('تذكير', Icons.notifications_active_outlined),
    ('ملاحظات', Icons.sticky_note_2_outlined),
  ];

  static const List<String> _followStatuses = [
    'الأحدث أولاً',
    'نشطة',
    'قريبًا',
    'حان وقتها',
    'متأخرة',
  ];

  IconData _followKindIcon(String group) {
    for (final kind in _followKinds) {
      if (kind.$1 == group) return kind.$2;
    }
    return Icons.more_horiz_rounded;
  }

  /// الحالة من تاريخ البند: بلا تاريخ = نشطة دائمًا.
  bool _followMatchesStatus(Map<String, String> row) {
    if (_followStatus == 'الأحدث أولاً') return true;
    final date = _parseDayValue(row['التاريخ'] ?? '');
    if (date == null) return _followStatus == 'نشطة';
    final days = DateUtils.dateOnly(date)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    return switch (_followStatus) {
      'نشطة' => days >= 0,
      'قريبًا' => days > 0 && days <= 7,
      'حان وقتها' => days == 0,
      'متأخرة' => days < 0,
      _ => true,
    };
  }

  /// اختيار من قائمة سفلية (الفئة / الحالة).
  Future<void> _pickFollowFilter(
    List<String> options,
    String value,
    ValueChanged<String> onPick,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              for (final option in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    option == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: const Color(0xFF0E7161),
                  ),
                  title: Text(
                    option,
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => onPick(picked));
  }

  /// صندوق فلتر بعنوانه فوقه: «الفئة» أو «الحالة».
  Widget _followFilterBox(
    String label,
    IconData icon,
    String value,
    List<String> options,
    ValueChanged<String> onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF5C6B68)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                textAlign: AppTr.alignEnd,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5C6B68),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          onTap: () => _pickFollowFilter(options, value, onPick),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Expanded(
                  child: Text(
                    value,
                    textAlign: AppTr.alignEnd,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1F1C),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Color(0xFF0F1F1C),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// «+»: اختيار النوع (مهمة، موعد، عادة، تذكير، ملاحظات) ثم نموذجه.
  Future<void> _addFollowupFromPicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Text(
                'إضافة إلى المتابعة والتخطيط',
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 6),
              for (final kind in _followKinds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(kind.$2, color: const Color(0xFF0A5A50)),
                  title: Text(
                    kind.$1,
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, kind.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _addFollowupRow(picked);
  }

  /// صف واحد في قائمة المتابعة: نوعه وعنوانه وتفاصيله وتاريخه، وزر حذف.
  Widget _followupRowTile(Map<String, String> row, Color color) {
    final group = _followupGroupOf(row);
    final type = (row['النوع'] ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Icon(_followKindIcon(group), size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  row['العنوان'] ?? '',
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                if ((row['التفاصيل'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    row['التفاصيل']!,
                    textAlign: AppTr.alignEnd,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.body,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  [
                    AppTr.tr(type.isEmpty ? group : type),
                    if ((row['التاريخ'] ?? '').isNotEmpty) row['التاريخ']!,
                    if ((row['الوقت'] ?? '').isNotEmpty) row['الوقت']!,
                  ].join(' · '),
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppTr.tr('حذف'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteFollowupRow(row),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }

  /// قسم «المتابعة والتخطيط» بنفس شكل تفاصيل الفرد: فلترا الفئة والحالة،
  /// ثم العنوان وعدده وسهم النوع و«+»، ثم البنود في قائمة واحدة.
  Widget _buildFollowupPlanningSection(_CommitmentItem item, Color color) {
    final all = _parseFollowupRows(item.details).reversed.toList();
    final rows = all
        .where(
          (row) =>
              (_followKind == 'الكل' || _followupGroupOf(row) == _followKind) &&
              _followMatchesStatus(row),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // العنوان وعدده و«+» فقط، وتحته فلترا النوع والحالة.
        AppSectionAddRow(
          title: 'المتابعة والتخطيط',
          icon: Icons.event_note_outlined,
          accent: color,
          count: rows.length,
          onAdd: _addFollowupFromPicker,
        ),
        FollowFiltersRow(
          kind: _followKind,
          status: _followStatus,
          onKind: (value) => setState(() => _followKind = value),
          onStatus: (value) => setState(() => _followStatus = value),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              all.isEmpty
                  ? 'لا توجد مهمة - موعد - عادة - تذكير - ملاحظات، للإضافة اضغط +'
                  : 'لا توجد متابعة أو تخطيط مطابق للفلتر',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.6,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8C9A97),
              ),
            ),
          )
        else
          for (final row in rows) _followupRowTile(row, color),
      ],
    );
  }

  /// إعادة قراءة هذا السجل من الخادم: صرفيات الطرف الآخر وفواتيره تصل
  /// إلى صاحب العهدة بضغطة تحديث بلا خروج من الصفحة.
  Future<void> _refreshItemFromServer({bool quiet = false}) async {
    try {
      final rows = await widget.repository.fetchAll();
      PersonalEntryRecord? found;
      for (final row in rows) {
        if (row.id == widget.item.id) {
          found = row;
          break;
        }
      }
      if (found == null || !mounted) return;
      final record = found;
      setState(() {
        widget.item.title = record.title;
        widget.item.details = record.details;
        widget.item.totalAmount = record.amount;
        widget.item.dueDate = record.dueDate;
        widget.item.status = record.status;
        widget.item.statusColor = _personalStatusColor(record.status);
        widget.item.attachmentPath = record.attachmentUrl;
        widget.item.lastUpdate = 'الآن';
      });
      if (!mounted || quiet) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حُدِّثت البيانات'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted || quiet) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveErrorMessage(error))));
    }
  }

  /// مربع منفصل لمصروفات العهدة وتفاصيلها، تحت «سجل العهدة المالية».
  Widget _buildCustodyExpensesCard(
    _CommitmentItem item, {
    bool embedded = false,
  }) {
    final spends = _parseCustodyTransactions(item.details);
    final cancelled = item.status == 'ملغاة' ||
        item.status == 'تمت التسوية' ||
        item.status == 'مجمّدة';
    final canManage = _isCustodyOwnerView(item.details) && !cancelled;
    return Container(
      margin: embedded ? EdgeInsets.zero : const EdgeInsets.only(top: 12),
      padding: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rCard),
              border: Border.all(color: AppTheme.hairline),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 19,
                color: AppTheme.brandMid,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${AppTr.tr('مصروفات العهدة')} (${spends.length})',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (spends.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'لا توجد مصروفات مسجّلة بعد.',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Color(0xFF8C9A97)),
              ),
            )
          else
            for (var i = 0; i < spends.length; i++)
              _custodyLogRow(
                icon: Icons.receipt_long_outlined,
                color: _custodySpendCounts(spends[i])
                    ? const Color(0xFFC4392E)
                    : const Color(0xFF8C9A97),
                line1:
                    '-${spends[i]['المبلغ'] ?? '0'} ${item.currency}'
                    '${(spends[i]['الغرض'] ?? '').isEmpty ? '' : ' · ${spends[i]['الغرض']}'}',
                line2: _custodySpendLine2(spends[i]),
                invoicePath: spends[i][_paymentInvoiceKey],
                state: spends[i][_custodySpendStateKey] ?? '',
                details: spends[i],
                onApprove:
                    canManage &&
                        spends[i][_custodySpendStateKey] == _custodySpendPending
                    ? () => _setCustodySpendState(i, approve: true)
                    : null,
                onReject:
                    canManage &&
                        spends[i][_custodySpendStateKey] == _custodySpendPending
                    ? () => _setCustodySpendState(i, approve: false)
                    : null,
              ),
        ],
      ),
    );
  }

  /// تفاصيل مصروف كاملة قبل اعتماده: كل بياناته والمرفق.
  Future<void> _showSpendDetails(
    Map<String, String> row, {
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) async {
    final invoice = (row[_paymentInvoiceKey] ?? '').trim();
    final entries = [
      for (final entry in row.entries)
        if (!entry.key.startsWith('_') &&
            entry.key != _paymentInvoiceKey &&
            entry.key != _recordTimeKey &&
            entry.value.trim().isNotEmpty)
          entry.key == 'التاريخ'
              ? MapEntry(
                  'التاريخ والساعة',
                  _withTime(entry.value, row[_recordTimeKey]),
                )
              : entry,
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('تفاصيل المصروف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  _leaseLikeRow(
                    entry.key == _custodySpendStateKey ? 'الحالة' : entry.key,
                    entry.value,
                  ),
                if (invoice.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openInvoiceImage(dialogContext, invoice),
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: const Text('مرفق — اضغط لفتحه'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
            if (onReject != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onReject();
                },
                child: const Text('رفض'),
              ),
            if (onApprove != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E7161),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onApprove();
                },
                child: const Text('اعتماد'),
              ),
          ],
        ),
      ),
    );
  }

  /// بطاقة العهدة في الملخص: المسند إليه ورقمه التعريفي وحالة الإسناد
  /// والأرقام، وزر يفتح لوحة «إدارة العهدة» مباشرة.
  /// بيانات العهدة بعد إغلاقها: لمن كانت، وكم صُرف وأُعيد، ومتى وكيف سُوّيت.
  Widget _buildClosedCustodyData(
    _CommitmentItem item,
    CustodyAssignment assignment,
  ) {
    final spent = _custodyTotalSpent(item.details);
    final returned = (item.details['المبلغ المعاد عند التسوية'] ?? '').trim();
    final note =
        (item.details['ملاحظة التسوية'] ?? item.details['سبب التسوية'] ?? '')
            .trim();
    final currency = widget.item.currency;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _leaseLikeRow('حالة العهدة', AppTr.tr(item.status)),
          _leaseLikeRow(
            'المسند إليه',
            assignment.holderName.isNotEmpty
                ? assignment.holderName
                : (item.details['اسم المستلم'] ?? 'غير مسندة'),
          ),
          if (assignment.holderId.isNotEmpty)
            _leaseLikeRow('الرقم التعريفي', assignment.holderId),
          _leaseLikeRow('قيمة العهدة', '${item.totalAmount} $currency'),
          _leaseLikeRow('المصروف', '$spent $currency'),
          _leaseLikeRow(
            'المبلغ المعاد عند التسوية',
            '${returned.isEmpty ? '0' : returned} $currency',
          ),
          if ((item.details['تاريخ التسوية'] ?? '').trim().isNotEmpty)
            _leaseLikeRow(
              'تاريخ ووقت التسوية',
              item.details['تاريخ التسوية']!.trim(),
            ),
          if (note.isNotEmpty)
            _leaseLikeRow(
              item.details.containsKey('ملاحظة التسوية')
                  ? 'ملاحظة التسوية'
                  : 'سبب التسوية',
              note,
            ),
        ],
      ),
    );
  }

  Widget _buildCustodyOverviewCard(_CommitmentItem item) {
    final assignment = CustodyAssignment.decode(item.details);
    final myId = AppIdentity.id;
    final role = assignment.roleFor(myId);
    final stateColor = switch (assignment.state) {
      CustodyAssignmentState.pending => AppTheme.goldDark,
      CustodyAssignmentState.accepted => AppTheme.brandMid,
      CustodyAssignmentState.rejected => AppTheme.danger,
      CustodyAssignmentState.none => AppTheme.muted,
    };
    // أُغلقت العهدة (سُوّيت أو أُلغيت أو أُرشفت): لا إضافة ولا تسوية.
    final closed = const {
      'ملغاة',
      'تمت التسوية',
      'مؤرشف',
    }.contains(item.status);
    // إضافة المبلغ والتسوية لصاحب العهدة وهي قائمة.
    final ownerActions = _isCustodyOwnerView(item.details) && !closed;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 19,
                color: AppTheme.brandMid,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'سجل العهدة المالية والمصروفات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              if (!assignment.isAccepted)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  assignment.stateLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: stateColor,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppTr.tr('تحديث من الخادم'),
                onPressed: _refreshItemFromServer,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 19,
                  color: AppTheme.brandMid,
                ),
              ),
            ],
          ),
          // وقت القبول/الرفض سطرًا صغيرًا تحت العنوان (طُلب ظهوره).
          if ((item.details[CustodyAssignment.kRespondedAt] ?? '').isNotEmpty &&
              (assignment.isAccepted || assignment.isRejected))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${AppTr.tr(assignment.isAccepted ? 'قُبلت في' : 'رُفضت في')} '
                '${item.details[CustodyAssignment.kRespondedAt]!}',
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ),
          if (role == CustodyRole.holder && assignment.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandMid,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(42),
                    ),
                    onPressed: () =>
                        _respondToCustodyAssignment(accept: true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'قبول العهدة',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size.fromHeight(42),
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                    onPressed: () =>
                        _respondToCustodyAssignment(accept: false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text(
                      'رفض',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // صاحب العهدة: إضافة مبلغ وتسوية، والسجل تحتهما.
          if (ownerActions) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _openCustodyTopUpForm,
                    icon: const Icon(Icons.add_card_outlined, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'إضافة مبلغ على العهدة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brand,
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: const BorderSide(color: AppTheme.brand),
                    ),
                    onPressed: _settleCustody,
                    icon: const Icon(Icons.task_alt_rounded, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'تسوية العهدة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (closed)
            _buildClosedCustodyData(item, assignment)
          else
            // المفوَّض بها أنا: إضافة مصروف، ومعلومات العهدة المالية.
            Row(
              children: [
                if (assignment.canSpend(myId) &&
                    _isCustodyRecipient(item.details)) ...[
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _openCustodySpendForm,
                      icon: const Icon(Icons.add_card_outlined, size: 17),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'إضافة مصروف',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brand,
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: const BorderSide(color: AppTheme.brand),
                    ),
                    onPressed: _openCustodyManagementSheet,
                    icon: const Icon(Icons.info_outline_rounded, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'معلومات العهدة المالية',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          // خط رفيع ثم المصروفات وتفاصيلها.
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 12),
            color: AppTheme.hairline,
          ),
          _buildCustodyExpensesCard(item, embedded: true),
        ],
      ),
    );
  }

}

class _CompactCommitmentHeader extends StatelessWidget {
  const _CompactCommitmentHeader({
    required this.item,
    required this.color,
    required this.onAction,
  });

  final _CommitmentItem item;
  final Color color;
  final ValueChanged<_CommitmentMenuAction> onAction;

  /// العهدة: الحالة بلونها في سطر الاسم (يسارًا)، وتحتها مباشرة في سطر
  /// «عهدة مالية» دوري فيها («مفوَّض بها أنا» أو «فوّضت بها غيري»).
  Widget _custodyStateColumn() {
    final (label, stateColor) = _custodyStateLook(item.status);
    final role = _custodyRoleLabel(item.details);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: stateColor,
            ),
          ),
        ),
        if (role != null) ...[
          const SizedBox(height: 4),
          Text(
            role,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFFA6691A),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('compact-details-header-row'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: color, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F1F1C),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.entryType ?? 'التزام شخصي',
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.entryType == 'عهدة مالية')
                _custodyStateColumn()
              else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: item.statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: item.statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_CommitmentMenuAction>(
                key: const ValueKey('compact-details-edit'),
                tooltip: AppTr.tr('إجراءات الالتزام'),
                onSelected: onAction,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 23,
                  color: Color(0xFF46534F),
                ),
                itemBuilder: (context) => [
                  // مستلم العهدة أو الطرف الثاني في الدين لا يعدّل بيانات
                  // صاحبها: يقرأ ويسجّل ما يخصه فقط.
                  if (!_isSharedGuest(item))
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.edit,
                      child: _CommitmentMenuItem(
                        label: 'تعديل بيانات',
                        icon: Icons.edit_outlined,
                      ),
                    ),
                  // الأدوية: كورس جديد بنفس البيانات، والسابق إلى السجل.
                  if (item.entryType == 'أدوية')
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.newCourse,
                      child: _CommitmentMenuItem(
                        label: 'بدء كورس جديد',
                        icon: Icons.restart_alt_rounded,
                      ),
                    ),
                  // دواء آخر صرفه الطبيب في الزيارة نفسها.
                  if (item.entryType == 'أدوية')
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.samePrescription,
                      child: _CommitmentMenuItem(
                        label: 'دواء آخر من نفس الوصفة',
                        icon: Icons.medication_liquid_outlined,
                      ),
                    ),
                  // العهدة: عهدة جديدة بنفس البيانات — لصاحبها فقط.
                  if (item.entryType == 'عهدة مالية' &&
                      _isCustodyOwnerView(item.details))
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.newCustody,
                      child: _CommitmentMenuItem(
                        label: 'بدء عهدة جديدة',
                        icon: Icons.add_business_outlined,
                      ),
                    ),
                  // إلغاء الإسناد: هنا فقط (أُزيل من تحت حالة الإسناد).
                  if (item.entryType == 'عهدة مالية' &&
                      _isCustodyOwnerView(item.details) &&
                      CustodyAssignment.decode(item.details).isAssigned &&
                      item.status != 'ملغاة' &&
                      item.status != 'تمت التسوية')
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.cancelAssignment,
                      child: _CommitmentMenuItem(
                        label: 'إلغاء الإسناد',
                        icon: Icons.person_remove_outlined,
                        color: Color(0xFFA82F26),
                      ),
                    ),
                  // عهدة سُوّيت ولم تُؤرشف: يعيد صاحبها فتحها ليُكمل الصرف
                  // من المتبقي.
                  if (item.entryType == 'عهدة مالية' &&
                      _isCustodyOwnerView(item.details) &&
                      item.status == 'تمت التسوية')
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.reopenCustody,
                      child: _CommitmentMenuItem(
                        label: 'إعادة فتح العهدة',
                        icon: Icons.lock_open_rounded,
                      ),
                    ),
                  // تجميد العهدة (لصاحبها): يتوقف الصرف حتى يُلغى التجميد.
                  if (item.entryType == 'عهدة مالية' &&
                      _isCustodyOwnerView(item.details) &&
                      item.status != 'ملغاة' &&
                      item.status != 'تمت التسوية' &&
                      item.status != 'مؤرشف')
                    PopupMenuItem(
                      value: _CommitmentMenuAction.freezeCustody,
                      child: _CommitmentMenuItem(
                        label: item.status == 'مجمّدة'
                            ? 'إلغاء التجميد'
                            : 'تجميد العهدة',
                        icon: item.status == 'مجمّدة'
                            ? Icons.play_circle_outline_rounded
                            : Icons.ac_unit_rounded,
                      ),
                    ),
                  const PopupMenuItem(
                    value: _CommitmentMenuAction.share,
                    child: _CommitmentMenuItem(
                      label: 'مشاركة',
                      icon: Icons.share_outlined,
                    ),
                  ),
                  // العهدة المالية: «إلغاء» أولًا، وبعد إلغائها يظهر «حذف».
                  if (item.entryType == 'عهدة مالية' &&
                      item.status != 'ملغاة' &&
                      _isCustodyOwnerView(item.details))
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.cancel,
                      child: _CommitmentMenuItem(
                        label: 'إلغاء',
                        icon: Icons.cancel_outlined,
                        color: Color(0xFFA82F26),
                      ),
                    )
                  // المسند إليه لا يحذف سجل صاحبه ولا يؤرشفه.
                  else if (!_isSharedGuest(item))
                    const PopupMenuItem(
                      value: _CommitmentMenuAction.delete,
                      child: _CommitmentMenuItem(
                        label: 'حذف',
                        icon: Icons.delete_outline_rounded,
                        color: Color(0xFFA82F26),
                      ),
                    ),
                  if (!_isSharedGuest(item))
                  const PopupMenuItem(
                    value: _CommitmentMenuAction.archive,
                    child: _CommitmentMenuItem(
                      label: 'أرشيف',
                      icon: Icons.archive_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommitmentMenuItem extends StatelessWidget {
  const _CommitmentMenuItem({
    required this.label,
    required this.icon,
    this.color = const Color(0xFF2C3B38),
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// مستطيل مربّع مصغّر لخيارات "+ إضافة" في شاشة التفاصيل (دفعة/مستند/صورة
// ومجموعة تنظيم ومتابعة)، مطابق لشكل "3 مستطيلات بجانب بعض" في الشرح.
class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  // بلا ألوان مميِّزة لكل نوع، حسب الطلب: كل مستطيلات "+ إضافة" بنفس
  // اللون المحايد (رمادي/أسود فاتح) بلا تمييز لوني بينها.
  static const Color _neutral = Color(0xFF2C3B38);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _neutral, size: 22),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center, child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _neutral,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _InlineDetailsTabs extends StatelessWidget {
  const _InlineDetailsTabs({
    required this.sections,
    required this.selectedIndex,
    required this.color,
    required this.onSelected,
  });

  final List<({String label, IconData icon})> sections;
  final int selectedIndex;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // كانت هنا نسخة يدوية مطابقة لشريط التبويبات المشترك، فتخلّفت عنه عند
    // أي تعديل (آخرها: السماح بسطرين للعناوين الطويلة). الآن تستدعيه.
    return DetailPageTabs(
      key: const ValueKey('inline-details-tabs'),
      sections: [
        for (final section in sections)
          DetailSectionTab(label: section.label, icon: section.icon),
      ],
      selectedIndex: selectedIndex,
      color: color,
      onSelected: onSelected,
    );
  }
}

class _CategoryHighlightBar extends StatelessWidget {
  const _CategoryHighlightBar({required this.item, required this.color});

  final _CommitmentItem item;
  final Color color;

  String _valueOr(String? value, String fallback) =>
      (value == null || value.trim().isEmpty) ? fallback : value;

  List<(String, String, IconData)> _highlights() {
    final slug = _PersonalCommitmentsScreenState._entryTypeCategorySlug[item
        .entryType];
    final due = item.dueDate.isEmpty ? 'غير محدد' : item.dueDate;
    // الاشتراكات ليست تحت شريحة "financial" (بل "lifestyle")، لذا تُفحص هنا
    // أولاً حتى تظهر حالة السداد الفعلية (الكلي/المدفوع/المتبقي) وتتحدث فور
    // تسجيل أي دفعة، بدل الاكتفاء بعرض ثابت (الاسم/التاريخ) لا يعكس السداد.
    if (item.isSubscription) {
      if (item.paidAmount > 0) {
        return [
          ('المبلغ الكلي', '${item.totalAmount} ${item.currency}', Icons.payments_outlined),
          ('المدفوع', '${item.paidAmount} ${item.currency}', Icons.trending_down_rounded),
          (
            'المتبقي',
            '${item.amount} ${item.currency}',
            Icons.account_balance_wallet_outlined,
          ),
        ];
      }
      return [
        ('قيمة الاشتراك', '${item.totalAmount} ${item.currency}', Icons.payments_outlined),
        ('تاريخ الاستحقاق', due, Icons.event_outlined),
        (
          'عدد الأفراد',
          item.subscriptionMembers?.toString() ?? '—',
          Icons.groups_outlined,
        ),
      ];
    }
    switch (slug) {
      case 'financial':
        if (item.paidAmount > 0) {
          return [
            ('المبلغ الكلي', '${item.totalAmount} ${item.currency}', Icons.payments_outlined),
            ('المدفوع', '${item.paidAmount} ${item.currency}', Icons.trending_down_rounded),
            (
              'المتبقي',
              '${item.amount} ${item.currency}',
              Icons.account_balance_wallet_outlined,
            ),
          ];
        }
        return [
          ('المبلغ', '${item.totalAmount} ${item.currency}', Icons.payments_outlined),
          ('التاريخ', due, Icons.event_outlined),
          (
            'جهة الصرف',
            _valueOr(item.details['جهة الصرف'], '—'),
            Icons.storefront_outlined,
          ),
        ];
      case 'document':
        return [
          ('تاريخ الانتهاء', due, Icons.event_busy_outlined),
          ('اسم المستند', item.title, Icons.description_outlined),
          (
            'الملاحظات',
            _valueOr(item.details['ملاحظات'], '—'),
            Icons.notes_rounded,
          ),
        ];
      case 'organization':
        return [
          ('تاريخ الانتهاء', due, Icons.event_busy_outlined),
          ('الاسم', item.title, Icons.task_alt_outlined),
          (
            'الملاحظات',
            _valueOr(item.details['ملاحظات'], '—'),
            Icons.notes_rounded,
          ),
        ];
      case 'medical_accounts':
        return [
          (
            'النوع',
            item.entryType ?? 'غير محدد',
            Icons.medical_information_outlined,
          ),
          // الأدوية: لمن الدواء بدل تاريخ الإنشاء.
          if (item.entryType == 'أدوية')
            (
              'اسم المستفيد',
              _medicineBeneficiary(item),
              Icons.person_outline_rounded,
            )
          else
            (
              'تاريخ الإنشاء',
              item.lastUpdate.isEmpty ? 'غير محدد' : item.lastUpdate,
              Icons.event_outlined,
            ),
        ];
      case 'lifestyle':
        return [
          ('الاسم', item.title, Icons.celebration_outlined),
          ('التاريخ', due, Icons.event_outlined),
          (
            'الملاحظات',
            _valueOr(item.details['ملاحظات'], '—'),
            Icons.notes_rounded,
          ),
        ];
      case 'location':
        return [
          ('الاسم', item.title, Icons.place_outlined),
          (
            'الموقع',
            _valueOr(item.details['الموقع أو الرابط'], '—'),
            Icons.link_rounded,
          ),
        ];
      case 'custody':
        final spent = _custodyTotalSpent(item.details);
        final remaining = item.totalAmount - spent;
        return [
          ('قيمة العهدة', '${item.totalAmount} ${item.currency}', Icons.inventory_2_outlined),
          ('المصروف', '$spent ${item.currency}', Icons.trending_down_rounded),
          ('المتبقي', '$remaining ${item.currency}', Icons.account_balance_wallet_outlined),
        ];
      default:
        return [('التاريخ', due, Icons.event_outlined)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlights = _highlights();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          for (var i = 0; i < highlights.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 34,
                color: color.withValues(alpha: 0.18),
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
            Expanded(child: _buildHighlightTile(highlights[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildHighlightTile((String, String, IconData) highlight) {
    final (label, value, icon) = highlight;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F1F1C),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5C6B68),
          ),
        ),
      ],
    );
  }
}

class _SummaryDetailsCard extends StatelessWidget {
  final _CommitmentItem item;
  final Color color;
  final bool expanded;
  final bool Function(String label) isSensitive;
  final VoidCallback onToggleExpanded;

  const _SummaryDetailsCard({
    required this.item,
    required this.color,
    required this.expanded,
    required this.isSensitive,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final detailEntries = item.details.entries
        .where(
          // مفاتيح داخلية (سجلات وحالة الإسناد) لا تُعرض كصفوف في الملخص.
          (entry) =>
              !const {
                _addedAttachmentTypeKey,
                _addedAttachmentNameKey,
                _extraAttachmentsKey,
                _prescriptionGroupKey,
                _custodyTransactionsDetailKey,
                _subscriptionPaymentsDetailKey,
                _followupLogKey,
                _courseLogKey,
                _custodyLogKey,
                CustodyTopUps.key,
              }.contains(entry.key) &&
              !CustodyAssignment.keys.contains(entry.key) &&
              !TrashStore.keys.contains(entry.key),
        )
        .toList(growable: false);
    // كل ما أُدخل عند الإضافة يظهر في الملخص مباشرة.
    final visibleEntries = detailEntries;

    return _UnifiedDetailsCard(
      title: 'معلومات ${item.entryType ?? 'الالتزام'}',
      icon: Icons.info_rounded,
      color: color,
      children: [
        _UnifiedInfoRow(
          label: 'نوع الالتزام',
          value: item.entryType ?? 'التزام شخصي',
          icon: Icons.category_outlined,
        ),
        _UnifiedInfoRow(
          label: 'الحالة',
          value: item.status,
          icon: Icons.verified_user_outlined,
          valueColor: item.statusColor,
        ),
        _UnifiedInfoRow(
          label: 'تاريخ الاستحقاق',
          value: item.dueDate.isEmpty ? 'غير محدد' : item.dueDate,
          icon: Icons.event_outlined,
        ),
        ...visibleEntries.map(
          (entry) => _UnifiedInfoRow(
            label: entry.key,
            value: isSensitive(entry.key) ? '••••••••' : entry.value,
            icon: Icons.notes_rounded,
          ),
        ),
        _UnifiedInfoRow(
          label: 'المرفق',
          value: item.attachmentPath == null ? 'لا يوجد' : 'مستند مرفق',
          icon: Icons.attach_file_rounded,
        ),
      ],
    );
  }
}

class _HistoryDetailsCard extends StatelessWidget {
  final _CommitmentItem item;
  final Color color;

  const _HistoryDetailsCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final isCustody = item.entryType == 'عهدة مالية';
    final custodyTransactions = isCustody
        ? _parseCustodyTransactions(item.details)
        : const <Map<String, String>>[];
    final custodyRemaining = isCustody
        ? item.totalAmount - _custodyTotalSpent(item.details)
        : 0;
    return _UnifiedDetailsCard(
      title: 'سجل الالتزام',
      icon: Icons.schedule_rounded,
      color: color,
      children: [
        _TimelineEntry(
          title: 'آخر تحديث',
          subtitle: item.lastUpdate,
          icon: Icons.edit_note_rounded,
          color: color,
        ),
        _TimelineEntry(
          title: 'تم إنشاء الالتزام',
          subtitle: item.lastUpdate,
          icon: Icons.add_circle_outline_rounded,
          color: color,
        ),
        // كورسات الدواء السابقة، الأحدث أولًا.
        // العهد السابقة (بدء عهدة جديدة) — الضغط يعرض كل معلوماتها.
        for (final snapshot in _parseCustodyLog(item.details).reversed)
          _TimelineEntry(
            title: snapshot['العهدة'] ?? 'عهدة',
            subtitle: [
              if ((snapshot['تاريخ التسليم'] ?? '').isNotEmpty)
                snapshot['تاريخ التسليم']!,
              '${AppTr.tr('القيمة')} ${snapshot['قيمة العهدة'] ?? '0'} ${item.currency}',
              '${AppTr.tr('المصروف')} ${snapshot['المصروف'] ?? '0'}',
              '${AppTr.tr('المتبقي')} ${snapshot['المتبقي'] ?? '0'}',
            ].join(' • '),
            icon: Icons.inventory_2_outlined,
            color: color,
            onTap: () => _showCustodySnapshot(context, snapshot, item.currency),
          ),
        for (final course in _parseCourseLog(item.details).reversed)
          _TimelineEntry(
            title: course['الكورس'] ?? 'كورس',
            subtitle: [
              if ((course['من تاريخ'] ?? '').isNotEmpty)
                'من ${course['من تاريخ']}',
              if ((course['إلى تاريخ'] ?? '').isNotEmpty)
                'إلى ${course['إلى تاريخ']}',
              if ((course['الجرعة'] ?? '').isNotEmpty)
                'الجرعة ${course['الجرعة']} ${course['وحدة الجرعة'] ?? ''}'.trim(),
            ].join(' • '),
            icon: Icons.history_rounded,
            color: color,
          ),
        ...item.payments.map(
          (payment) => _TimelineEntry(
            title: 'دفعة بقيمة ${payment.amount} ${item.currency}',
            subtitle: payment.invoiceImagePath == null
                ? '${payment.payerName} • ${payment.date}'
                : '${payment.payerName} • ${payment.date} • اضغط لعرض الفاتورة',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF178F7B),
            onTap: payment.invoiceImagePath == null
                ? null
                : () => _openInvoiceImage(context, payment.invoiceImagePath!),
          ),
        ),
        // سجل صرفيات العهدة المالية: كل عملية صرف مسجَّلة من زر "+ إضافة"،
        // مع الرصيد المتبقي في الأعلى — الأحدث أولًا.
        if (isCustody) ...[
          if ((item.details[CustodyAssignment.kRespondedAt] ?? '').isNotEmpty)
            _TimelineEntry(
              title: CustodyAssignment.decode(item.details).isRejected
                  ? 'رفض المستلم العهدة'
                  : 'قبول المستلم العهدة',
              subtitle: item.details[CustodyAssignment.kRespondedAt]!,
              icon: Icons.how_to_reg_outlined,
              color: color,
            ),
          if ((item.details['تاريخ التسوية'] ?? '').isNotEmpty)
            _TimelineEntry(
              title: item.status == 'ملغاة' ? 'إلغاء العهدة بتسوية' : 'تسوية العهدة',
              subtitle: [
                item.details['تاريخ التسوية']!,
                if ((item.details['ملاحظة التسوية'] ??
                        item.details['سبب التسوية'] ??
                        '')
                    .trim()
                    .isNotEmpty)
                  (item.details['ملاحظة التسوية'] ??
                          item.details['سبب التسوية'])!
                      .trim(),
              ].join(' • '),
              icon: Icons.task_alt_rounded,
              color: color,
            ),
          _TimelineEntry(
            title: 'الرصيد المتبقي من العهدة',
            subtitle:
                '$custodyRemaining ${item.currency} من أصل ${item.totalAmount} ${item.currency}',
            icon: Icons.account_balance_wallet_outlined,
            color: color,
          ),
          ...custodyTransactions.reversed.map(
            (transaction) => _TimelineEntry(
              title: 'صرف ${transaction['المبلغ'] ?? '0'} ${item.currency}',
              subtitle:
                  '${(transaction['الغرض'] ?? '').isNotEmpty ? transaction['الغرض'] : 'بدون سبب محدد'} • ${_withTime(transaction['التاريخ'] ?? '', transaction[_recordTimeKey])}'
                  '${(transaction[_custodySpendStateKey] ?? '').isEmpty ? '' : ' • ${AppTr.tr(transaction[_custodySpendStateKey]!)}'}',
              icon: Icons.remove_circle_outline_rounded,
              color: const Color(0xFFC4392E),
            ),
          ),
        ],
      ],
    );
  }
}

class _DocumentsDetailsCard extends StatelessWidget {
  final _CommitmentItem item;
  final Color color;

  const _DocumentsDetailsCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final hasAttachment = item.attachmentPath != null;
    final attachmentType = item.details[_addedAttachmentTypeKey];
    final attachmentName = item.details[_addedAttachmentNameKey];
    return _UnifiedDetailsCard(
      title: 'المستندات',
      icon: Icons.folder_outlined,
      color: color,
      children: [
        InkWell(
          // المرفق المحفوظ يُفتح بالضغط بدل بطاقة عرض ميتة.
          onTap: hasAttachment
              ? () => _openInvoiceImage(context, item.attachmentPath!)
              : null,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  hasAttachment
                      ? Icons.description_outlined
                      : Icons.folder_open_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasAttachment
                          ? attachmentType == null
                                ? 'مستند الالتزام'
                                : '$attachmentType مرفقة'
                          : 'لا توجد مستندات',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    Text(
                      hasAttachment
                          ? attachmentName?.isNotEmpty == true
                                ? attachmentName!
                                : 'اضغط لفتح المرفق'
                          : 'استخدم زر + لإضافة فاتورة أو مستند',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasAttachment)
                Icon(Icons.open_in_new_rounded, size: 19, color: color),
            ],
          ),
        ),
        ),
      ],
    );
  }
}

/// قسم «التخطيط»: الجدول الزمني القادم للالتزام كما هو مسجَّل فعليًا —
/// الاستحقاق والتكرار والأقساط، بلا أي حقل وهمي.
class _PlanningDetailsCard extends StatelessWidget {
  final _CommitmentItem item;
  final Color color;

  const _PlanningDetailsCard({required this.item, required this.color});

  String _v(String key) {
    final value = item.details[key];
    return (value == null || value.trim().isEmpty) ? 'غير محدد' : value.trim();
  }

  @override
  Widget build(BuildContext context) {
    final repeatOn = (item.details['تفعيل عملية متكررة'] ?? '') == 'نعم';
    return _UnifiedDetailsCard(
      title: 'التخطيط',
      icon: Icons.event_note_outlined,
      color: color,
      children: [
        _UnifiedInfoRow(
          label: 'تاريخ الاستحقاق',
          value: item.dueDate.isEmpty ? _v('تاريخ الاستحقاق') : item.dueDate,
          icon: Icons.event_available_outlined,
        ),
        _UnifiedInfoRow(
          label: 'عملية متكررة',
          value: repeatOn ? 'مفعّلة' : 'غير مفعّلة',
          icon: Icons.autorenew_rounded,
          valueColor: repeatOn ? const Color(0xFF0E7161) : null,
        ),
        if (repeatOn)
          _UnifiedInfoRow(
            label: 'التكرار',
            value: _v('التكرار'),
            icon: Icons.repeat_rounded,
          ),
        if ((item.details['عدد الأقساط'] ?? '').trim().isNotEmpty) ...[
          _UnifiedInfoRow(
            label: 'عدد الأقساط',
            value: _v('عدد الأقساط'),
            icon: Icons.format_list_numbered_rounded,
          ),
          _UnifiedInfoRow(
            label: 'تكرار الأقساط',
            value: _v('تكرار الأقساط'),
            icon: Icons.repeat_on_rounded,
          ),
        ],
        _UnifiedInfoRow(
          label: 'الحالة',
          value: item.status,
          icon: Icons.flag_outlined,
          valueColor: item.statusColor,
        ),
      ],
    );
  }
}

class _FollowupDetailsCard extends StatelessWidget {
  final _CommitmentItem item;
  final Color color;

  const _FollowupDetailsCard({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return _UnifiedDetailsCard(
      title: 'المتابعة',
      icon: Icons.notifications_none_rounded,
      color: color,
      children: [
        _UnifiedInfoRow(
          label: 'حالة المتابعة',
          value: item.status,
          icon: Icons.flag_outlined,
          valueColor: item.statusColor,
        ),
        _UnifiedInfoRow(
          label: 'الموعد القادم',
          value: item.dueDate.isEmpty ? 'غير محدد' : item.dueDate,
          icon: Icons.event_available_outlined,
        ),
        _UnifiedInfoRow(
          label: 'آخر مراجعة',
          value: item.lastUpdate,
          icon: Icons.fact_check_outlined,
        ),
      ],
    );
  }
}

// غلافان رفيعان فوق مكوّني نظام التصميم: الشكل نفسه صار مشتركًا مع صفحات
// تفاصيل الأشخاص والجهات والعقارات، فلا يتفرّق مرة أخرى.
class _UnifiedDetailsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _UnifiedDetailsCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => AppDetailsCard(
    title: title,
    icon: icon,
    color: color,
    children: children,
  );
}

class _UnifiedInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _UnifiedInfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => AppDetailRow(
    label: label,
    value: value,
    icon: icon,
    valueColor: valueColor,
  );
}

class _TimelineEntry extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _TimelineEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C2C29),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5C6B68),
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.receipt_long_outlined, size: 18, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _SubscriptionAmountTile extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;

  const _SubscriptionAmountTile({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF5C6B68),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$amount ${AppSettings.currencySuffix}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FollowUpSubMetric {
  const _FollowUpSubMetric({
    required this.label,
    required this.icon,
    required this.items,
  });

  final String label;
  final IconData icon;
  final List<_CommitmentItem> items;

  int get count => items.length;
}

// مجموعة كاملة من مركز المتابعة (مثال: "الاستحقاقات") تضم عدة عناصر فرعية
class _FollowUpGroupData {
  const _FollowUpGroupData({
    required this.title,
    required this.icon,
    required this.color,
    required this.metrics,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_FollowUpSubMetric> metrics;

  int get total => metrics.fold(0, (sum, m) => sum + m.count);
}

class _CommitmentStatusBadge extends StatelessWidget {
  const _CommitmentStatusBadge({required this.status, required this.color});

  final String status;
  final Color color;

  String get _compactStatus => switch (status) {
    'متأخرة' => 'متأخر',
    'قريبة الاستحقاق' => 'قريب',
    'مكتملة' => 'مكتمل',
    'نشطة' => 'نشط',
    _ => status,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        _compactStatus,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _CommitmentCard extends StatelessWidget {
  final _CommitmentItem item;
  final VoidCallback onTap;

  const _CommitmentCard({
    required this.item,
    required this.onTap,
  });

  /// الدين والقسط: بطاقتهما تعرض المبلغ والمتبقي لا التاريخ.
  bool get _isDebtLike =>
      item.totalAmount > 0 &&
      (item.entryType == 'دين / قرض / سلفة' || item.entryType == 'قسط');

  /// سطر المبلغ — أو نص فارغ للبنود التي لا مبلغ لها أصلًا.
  ///
  /// كانت المناسبة والمهمة والمستند والدواء تعرض "المبلغ : 0.00 درهم"،
  /// وهي قيمة بلا معنى لبنود ليست مالية.
  String get _amountLine {
    // المدفوع بالكامل يعطي متبقيًا صفرًا — وهو نفس الصفر بلا معنى الذي
    // نتخلص منه هنا.
    if (item.paidAmount > 0 && item.amount > 0) {
      return 'المتبقي : ${item.amount.toStringAsFixed(2)} ${item.currency}';
    }
    if (item.totalAmount > 0) {
      return 'المبلغ : ${item.totalAmount.toStringAsFixed(2)} ${item.currency}';
    }
    if (item.amount > 0) {
      return 'المبلغ : ${item.amount.toStringAsFixed(2)} ${item.currency}';
    }
    return '';
  }

  /// فوق اسم العهدة المسندة: «بانتظار الموافقة من فلان» لمن أرسلها، و«بانتظار
  /// قبولك» لمن وصلته.
  String? get _custodyPendingLabel {
    if (!_sharedEntryTypes.contains(item.entryType)) return null;
    final assignment = CustodyAssignment.decode(item.details);
    if (!assignment.isPending) return null;
    final myId = AppIdentity.id;
    if (myId.isNotEmpty && assignment.holderId == myId) {
      final owner = assignment.ownerName.isNotEmpty
          ? assignment.ownerName
          : assignment.ownerId;
      return owner.isEmpty
          ? AppTr.tr('بانتظار قبولك')
          : '${AppTr.tr('بانتظار قبولك — من')} $owner';
    }
    final holder = assignment.holderName.isNotEmpty
        ? assignment.holderName
        : assignment.holderId;
    return holder.isEmpty
        ? AppTr.tr('بانتظار الموافقة')
        : '${AppTr.tr('بانتظار الموافقة من')} $holder';
  }

  @override
  Widget build(BuildContext context) {
    final pending = _custodyPendingLabel;
    final card = _buildCard();
    if (pending == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x1ACE8422),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x66CE8422)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 13,
                  color: Color(0xFFA6691A),
                ),
                const SizedBox(width: 4),
                Text(
                  pending,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFA6691A),
                  ),
                ),
              ],
            ),
          ),
        ),
        card,
      ],
    );
  }

  Widget _buildCard() {
    // بطاقة القائمة الموحَّدة نفسها المستعملة في الالتزامات المشتركة
    // وإدارة الأشخاص.
    return AppEntityCard(
      icon: item.icon,
      iconColor: item.iconColor,
      iconBackground: item.iconBackground,
      title: item.title,
      subtitle: item.entryType ?? 'التزام شخصي',
      // كل عهدة: حالتها بلونها فوق المبلغ (نشطة / مكتملة / ملغاة /
      // مؤرشفة)، ودوري فيها تحت «عهدة مالية» مقابل التاريخ.
      statsHeader: item.entryType == 'عهدة مالية'
          ? _custodyStatePill(item)
          : null,
      footer: item.entryType == 'عهدة مالية'
          ? _custodyRoleText(item)
          : null,
      statusColor: item.statusColor,
      stats: [
        // الدين والقسط: المبلغ ثم المتبقي — التاريخ لا يفيد هنا بقدر ما
        // يفيد ما بقي في الذمة.
        if (_isDebtLike)
          'المبلغ : ${item.totalAmount.toStringAsFixed(2)} '
              '${item.currency}'
        else
          _amountLine,
        if (_isDebtLike)
          'المتبقي : ${(item.totalAmount - item.paidAmount).toStringAsFixed(2)} '
              '${item.currency}'
        else if (item.dueDate.isNotEmpty)
          'التاريخ : ${item.dueDate}',
        // المستند يُعرف بتاريخ انتهائه، فيظهر على البطاقة من الخارج.
        if ((item.details['تاريخ الانتهاء'] ?? '').trim().isNotEmpty)
          'ينتهي : ${item.details['تاريخ الانتهاء']!.trim()}',
      ],
      onTap: onTap,
      // بلا زر "خيارات الالتزام" (النقاط الثلاث): التعديل والإضافة
      // متاحان داخل صفحة التفاصيل نفسها، وزر ثانٍ داخل البطاقة يزاحم
      // البيانات ويعطي طريقين لنفس الشيء.
    );
  }
}

class _EntryType {
  final String label;
  final IconData icon;

  const _EntryType(this.label, this.icon);
}

/// خط موحّد لنصوص حقول الإدخال والقوائم في كل نماذج الالتزامات.
const TextStyle _kFieldTextStyle = TextStyle(
  fontSize: 13.5,
  fontWeight: FontWeight.w700,
  color: AppTheme.title,
);

/// جلب الموقع الجغرافي من الجوال بعد طلب الإذن — يُعاد «خط العرض,خط الطول».
Future<String?> _fetchCurrentLocation(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خدمة الموقع مغلقة على الجهاز — فعّلها ثم أعد المحاولة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يُسمح بالوصول إلى الموقع'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    final position = await Geolocator.getCurrentPosition();
    final value =
        '${position.latitude.toStringAsFixed(6)},'
        '${position.longitude.toStringAsFixed(6)}';
    if (!context.mounted) return value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('حُفظ الموقع: $value'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return value;
  } catch (_) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر جلب الموقع'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }
}

String _saveErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('anonymous_provider_disabled') ||
      message.contains('Anonymous sign-ins are disabled')) {
    return 'الحفظ غير مفعّل: فعّل Anonymous Sign-Ins في Supabase.';
  }
  if (message.contains('personal_entries') || message.contains('PGRST205')) {
    return 'جدول personal_entries غير موجود. شغّل ملف SQL في Supabase.';
  }
  if (message.contains('TimeoutException')) {
    return 'انتهت مهلة الحفظ. تحقق من الإنترنت ثم حاول مجددًا.';
  }
  return 'تعذر حفظ البيانات. تحقق من إعداد Supabase ثم حاول مجددًا.';
}

enum _FinancialFieldKind {
  text,
  number,
  date,
  time,
  multiline,
  secret,
  select,
  toggle,

  /// عنوان قسم داخل النموذج (نص أسود عريض) لا يُحفظ مع البيانات.
  header,
}

class _FinancialField {
  final String label;
  final IconData icon;
  final _FinancialFieldKind kind;
  final bool required;
  final bool isPrimary;
  final bool isTitle;
  final bool isAmount;
  final List<String> options;

  /// هل تقبل هذه القائمة قيمة جديدة من المستخدم ("+ إضافة أخرى")؟
  ///
  /// كان الخيار يُضاف إلى **كل** قائمة اختيار بلا استثناء، فيظهر
  /// "+ إضافة أخرى" تحت "نعم / لا" وتحت التكرار وحالة العهدة. الملف
  /// المعتمد يضعه في قوائم التصنيف وطريقة الدفع فقط.
  final bool allowCustom;

  /// حقل بنصف السطر: يُجمع مع الحقل التالي إن كان نصفًا أيضًا.
  final bool half;

  /// حقل مخفي عن الواجهة يُحفظ مع السجل (مثل الإحداثيات).
  final bool hidden;

  /// نص إرشادي رمادي داخل الحقل (مثال: أحمد) — لا يُحفظ مع البيانات.
  final String hint;

  /// اسم يظهر للمستخدم بدل [label] (المفتاح المحفوظ يبقى كما هو).
  final String display;

  String get shown => display.isEmpty ? label : display;

  const _FinancialField(
    this.label,
    this.icon, {
    this.kind = _FinancialFieldKind.text,
    this.required = false,
    this.isPrimary = false,
    this.isTitle = false,
    this.isAmount = false,
    this.options = const [],
    this.allowCustom = false,
    this.half = false,
    this.hidden = false,
    this.hint = '',
    this.display = '',
  });
}

/// خيارات التذكير الموحّدة بجانب التاريخ.
const List<String> _kReminderOptions = [
  'بدون تذكير',
  'قبل يوم',
  'قبل أسبوع',
  'قبل أسبوعين',
  'مخصص',
];

const Set<String> _kReminderLabels = {'تذكيرات', 'تذكير', 'التذكيرات'};

/// «قبل N يوم» بصياغة عربية سليمة.
String _reminderLabelForDays(int days) {
  if (days == 1) return 'قبل يوم';
  if (days == 2) return 'قبل يومين';
  if (days >= 3 && days <= 10) return 'قبل $days أيام';
  return 'قبل $days يومًا';
}

class _FinancialEntryForm {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_FinancialField> fields;

  const _FinancialEntryForm({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.fields,
  });
}

const _primaryTitle = _FinancialField(
  'الاسم',
  Icons.title_rounded,
  required: true,
  isPrimary: true,
  isTitle: true,
);
const _primaryAmount = _FinancialField(
  'المبلغ',
  Icons.payments_outlined,
  kind: _FinancialFieldKind.number,
  required: true,
  isPrimary: true,
  isAmount: true,
);
const _primaryDate = _FinancialField(
  'التاريخ',
  Icons.event_outlined,
  kind: _FinancialFieldKind.date,
  required: true,
  isPrimary: true,
  half: true,
);
const _notesField = _FinancialField(
  'ملاحظات',
  Icons.notes_rounded,
  kind: _FinancialFieldKind.multiline,
);

// حقول متكرّرة في أكثر من نموذج، معرَّفة مرة واحدة حتى لا تتفرّق مسمياتها.
const _repeatToggleField = _FinancialField(
  'تفعيل عملية متكررة',
  Icons.autorenew_rounded,
  kind: _FinancialFieldKind.toggle,
);

/// إحداثيات الموقع المجلوبة من الجوال — تُحفظ ولا تُعرض كحقل مستقل.
const _geoField = _FinancialField(
  'الموقع الجغرافي',
  Icons.place_outlined,
  hidden: true,
);

const _repeatCycleField = _FinancialField(
  'التكرار',
  Icons.repeat_rounded,
  kind: _FinancialFieldKind.select,
  options: ['يومي', 'أسبوعي', 'شهري', 'سنوي'],
  half: true,
);

/// يوم تنفيذ العملية المتكررة — بجانب التكرار في السطر نفسه.
const _repeatDayField = _FinancialField(
  'اليوم',
  Icons.today_outlined,
  kind: _FinancialFieldKind.select,
  options: [
    'نفس يوم العملية',
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'أول الشهر',
    'منتصف الشهر',
    'آخر الشهر',
  ],
  allowCustom: true,
  half: true,
);

// بلا "أخرى" مجرّدة: الملف المعتمد ينص على حذفها وإبقاء "+ إضافة أخرى".
const _paymentMethodField = _FinancialField(
  'طريقة الدفع',
  Icons.wallet_outlined,
  kind: _FinancialFieldKind.select,
  options: ['نقداً', 'بطاقة بنكية', 'تحويل بنكي', 'محفظة إلكترونية'],
  allowCustom: true,
  half: true,
);

// حقول "التنظيم والمتابعة" الموحّدة (مهمة/موعد/عادة/تذكير/ملاحظات):
// جدول واحد في الملف المعتمد، فلا يصح أن يختلف نموذج المهمة عن الموعد.
const List<_FinancialField> _organizationFields = [
  _FinancialField(
    'العنوان',
    Icons.title_rounded,
    required: true,
    isPrimary: true,
    isTitle: true,
  ),
  // التلميح '#auto' يُستبدل وقت العرض باسم الإضافة: «أوصف المهمة»،
  // «أوصف الموعد»، وهكذا لكل نوع.
  _FinancialField(
    'الوصف',
    Icons.description_outlined,
    kind: _FinancialFieldKind.multiline,
    isPrimary: true,
    hint: '#auto',
  ),
  // التاريخ والوقت في سطر واحد، والوقت بلا أي كلمة إضافية.
  _FinancialField(
    'التاريخ',
    Icons.event_outlined,
    kind: _FinancialFieldKind.date,
    required: true,
    isPrimary: true,
    half: true,
  ),
  _FinancialField(
    'الوقت',
    Icons.schedule_rounded,
    kind: _FinancialFieldKind.time,
    isPrimary: true,
    half: true,
  ),
  // مفتاح التذكير: إذا فُعِّل ظهر التكرار وساعة التذكير بالضبط.
  _FinancialField(
    'تفعيل تذكير',
    Icons.notifications_outlined,
    kind: _FinancialFieldKind.toggle,
    isPrimary: true,
  ),
  // وقت التذكير يمينًا ثم التكرار، و«مخصص» يفتح خانة لكتابة التكرار.
  // وقت التذكير: كم قبل الموعد (قبل يوم، 12 ساعة، ساعة، أو مخصص).
  _FinancialField(
    'وقت التذكير',
    Icons.alarm_rounded,
    kind: _FinancialFieldKind.select,
    options: kReminderLeadOptions,
    isPrimary: true,
    half: true,
  ),
  _FinancialField(
    'التكرار',
    Icons.repeat_rounded,
    kind: _FinancialFieldKind.select,
    options: ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري', 'مخصص'],
    isPrimary: true,
    half: true,
  ),
  _notesField,
];

const _currencyField = _FinancialField(
  'العملة',
  Icons.currency_exchange_rounded,
  kind: _FinancialFieldKind.select,
  options: AppSettings.currencySuffixes,
  isPrimary: true,
  half: true,
);

const _phoneField = _FinancialField(
  'رقم الهاتف',
  Icons.phone_outlined,
  isPrimary: true,
);

const _emailField = _FinancialField(
  'البريد الإلكتروني',
  Icons.email_outlined,
  isPrimary: true,
);

// جداول التصنيف الرئيسي/الفرعي — مطابقة لملف متطلبات "هيكل وادخال التزامات شخصية"
const Map<String, List<String>> _expenseSubcategoriesByMainCategory = {
  'طعام ومشروبات': [
    'بقالة وسوبرماركت',
    'مطاعم وكوفيهات',
    'توصيل وطلبات',
    'لحوم ودواجن',
    'خضروات وفواكه',
    'مخبوزات ومعجنات',
  ],
  'مواصلات': ['تطبيقات توصيل', 'نقل عام وتاكسي'],
  'إيجار': [],
  'دفع فواتير': ['إنترنت واتصالات', 'تأمينات', 'رسوم دراسية'],
  'صحة': ['أدوية وصيدلية', 'أطباء وأشعة', 'تحاليل وفحوصات'],
  'تعليم': ['مصروفات مدرسية', 'دروس خصوصية', 'دورات تدريبية', 'كتب ومراجع'],
  'تسوق': [
    'ملابس',
    'مستلزمات منزلية',
    'تسوق إلكتروني',
    'إلكترونيات',
    'عناية وجمال',
  ],
  'مغسلة وكوي (مصبغة)': ['عادي', 'مستعجل'],
  'ترفيه': ['رياضة وجيم', 'ألعاب', 'سينما'],
  // سفر: كان غائبًا تمامًا عن التطبيق وهو في الملف المعتمد.
  'سفر': ['فنادق وإقامة', 'تذاكر ورسوم سفر'],
  'سيارة': [
    'وقود',
    'مواقف ورسوم طرق',
    'صيانة وإصلاح',
    'قطع غيار',
    'إكسسوارات سيارات',
    'غسيل وتلميع',
    'مخالفات',
  ],
  // الفئات التالية بلا تصنيف فرعي في الملف المعتمد (تُترك بلا قائمة فرعية).
  'غرامات (عام)': [],
  'رسوم بنكية': [],
  'سداد قروض': [],
  'سداد أقساط': [],
  'خدمات حكومية': [],
  'مصروفات أخرى': [],
};

const Map<String, List<String>> _incomeSubcategoriesByMainCategory = {
  'الراتب/معاش': ['الراتب', 'عمولات', 'عمل إضافي'],
  'تعويض واسترجاع مصروف': [],
  'كاش باك': [],
};

const Map<String, List<String>> _fineSubcategoriesByMainCategory = {
  'غرامات': ['مرور', 'حكومية', 'مالية', 'تعاقدية', 'خدمات'],
};

// بلا خيار "أخرى" المجرّد: الملف المعتمد يذكر "+ إضافة أخرى" وحدها، وخيار
// "أخرى" كان يُنتج بندًا بلا معنى في التقارير لأن كل ما تحته يندرج تحت اسم
// واحد لا يفرّق بين شيء وآخر.
List<String> _expenseSubcategories(String mainCategory) => [
  ...?_expenseSubcategoriesByMainCategory[mainCategory],
  '+ إضافة أخرى',
];

List<String> _incomeSubcategories(String mainCategory) => [
  ...?_incomeSubcategoriesByMainCategory[mainCategory],
  '+ إضافة أخرى',
];

List<String> _fineSubcategories(String mainCategory) => [
  ...?_fineSubcategoriesByMainCategory[mainCategory],
  '+ إضافة أخرى',
];

List<String> _subcategoriesForEntry(String entryLabel, String mainCategory) {
  if (entryLabel == 'إيراد') {
    return _incomeSubcategories(mainCategory);
  }
  if (entryLabel == 'غرامة') {
    return _fineSubcategories(mainCategory);
  }
  return _expenseSubcategories(mainCategory);
}

const Map<String, _FinancialEntryForm> _financialEntryForms = {
  // الحقول والترتيب مطابقان لملف "إدخالات الالتزام الشخصي" المعتمد:
  // المبلغ، التصنيف، التاريخ، الوقت، العنوان، الملاحظات، ثم المعلومات
  // الإضافية (تفعيل عملية متكررة والتكرار، جهة الصرف، طريقة الدفع، الموقع،
  // إرفاق مستند).
  'المصروفات الشخصية': _FinancialEntryForm(
    label: 'المصروفات الشخصية',
    subtitle: 'تسجيل المصروف وتصنيفه وتفاصيل الدفع',
    icon: Icons.trending_down,
    color: Color(0xFFC4392E),
    fields: [
      _primaryAmount,
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'طعام ومشروبات',
          'مواصلات',
          'إيجار',
          'دفع فواتير',
          'صحة',
          'تعليم',
          'تسوق',
          'مغسلة وكوي (مصبغة)',
          'ترفيه',
          'سفر',
          'سيارة',
          'غرامات (عام)',
          'رسوم بنكية',
          'سداد قروض',
          'سداد أقساط',
          'خدمات حكومية',
          'مصروفات أخرى',
        ],
        allowCustom: true,
      ),
      // غير إلزامي: تصنيفات مثل "إيجار" و"رسوم بنكية" بلا تصنيف فرعي في
      // الملف المعتمد، وإلزامه كان يجبر المستخدم على اختراع تصنيف.
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        allowCustom: true,
      ),
      _primaryDate,
      _FinancialField(
        'الوقت',
        Icons.schedule_rounded,
        kind: _FinancialFieldKind.time,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'الملاحظات',
        Icons.notes_rounded,
        kind: _FinancialFieldKind.multiline,
        isPrimary: true,
      ),
      _repeatToggleField,
      _repeatCycleField,
      _repeatDayField,
      _FinancialField(
        'جهة الصرف',
        Icons.storefront_outlined,
        half: true,
      ),
      _paymentMethodField,
      _geoField,
    ],
  ),
  'إيراد': _FinancialEntryForm(
    label: 'إيراد',
    subtitle: 'دخل مالي مع تصنيف رئيسي وفرعي',
    icon: Icons.trending_up,
    color: Color(0xFF178F7B),
    fields: [
      _primaryAmount,
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['الراتب/معاش', 'تعويض واسترجاع مصروف', 'كاش باك'],
        allowCustom: true,
      ),
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        allowCustom: true,
      ),
      _primaryDate,
      _FinancialField(
        'الوقت',
        Icons.schedule_rounded,
        kind: _FinancialFieldKind.time,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'الملاحظات',
        Icons.notes_rounded,
        kind: _FinancialFieldKind.multiline,
        isPrimary: true,
      ),
      _repeatToggleField,
      _repeatCycleField,
      _repeatDayField,
      _FinancialField(
        'جهة الصرف',
        Icons.storefront_outlined,
        half: true,
      ),
      _paymentMethodField,
      _geoField,
    ],
  ),
  'تحويل مالي': _FinancialEntryForm(
    label: 'تحويل مالي',
    subtitle: 'تحويل مبلغ من حساب أو جهة إلى أخرى',
    icon: Icons.swap_horiz,
    color: Color(0xFF0A5A50),
    fields: [
      _primaryAmount,
      // "تحويل من" هو عنوان العملية في القوائم: الملف المعتمد لا يذكر حقل
      // عنوان مستقل للتحويل.
      // «من» و«إلى» نصًّا (حساب أو بنك أو شخص)، والحقلان في سطر واحد.
      _FinancialField(
        'تحويل من',
        Icons.logout_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
        half: true,
        hint: 'مثال: حسابي البنكي',
      ),
      _FinancialField(
        'تحويل إلى',
        Icons.login_rounded,
        required: true,
        isPrimary: true,
        half: true,
        hint: 'مثال: حساب التوفير',
      ),
      _primaryDate,
      _FinancialField(
        'الوقت',
        Icons.schedule_rounded,
        kind: _FinancialFieldKind.time,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'الملاحظات',
        Icons.notes_rounded,
        kind: _FinancialFieldKind.multiline,
        isPrimary: true,
      ),
      _repeatToggleField,
      _repeatCycleField,
      _repeatDayField,
      _FinancialField('رقم الإيصال', Icons.receipt_long_outlined),
      _FinancialField(
        'اسم البنك',
        Icons.account_balance_outlined,
        half: true,
      ),
      _paymentMethodField,
    ],
  ),
  'دين / قرض / سلفة': _FinancialEntryForm(
    label: 'دين / قرض / سلفة',
    subtitle: 'تسجيل الدين وحالة السداد',
    icon: Icons.handshake_outlined,
    color: Color(0xFF0E7161),
    fields: [
      // "لي / له" أول ما يُسأل عنه في الملف المعتمد، وبقية الحقول واحدة
      // في الحالتين. بدونه لا يعرف التطبيق أهو دين لك أم عليك.
      _FinancialField(
        'نوع الدين',
        Icons.swap_vert_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['لي — يدين لي', 'له — أدين له'],
      ),
      _FinancialField(
        'اسم الجهة',
        Icons.business_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
        hint: 'مثال: أحمد',
        display: 'اسم الفرد / الجهة',
      ),
      // إشراك الطرف الثاني: يصله طلب قبول، وبعد قبوله يسجّل سداده فيظهر
      // عندك في السجل مباشرة.
      _FinancialField(
        _debtHolderIdLabel,
        Icons.badge_outlined,
        isPrimary: true,
        hint: 'اختياري — FND-XXXX-XXXX',
        display: 'الرقم التعريفي للربط بالدين / السلفة',
      ),
      _phoneField,
      _emailField,
      _FinancialField('العنوان', Icons.label_outline_rounded, isPrimary: true),
      _FinancialField(
        'تفاصيل الدين',
        Icons.info_outline_rounded,
        isPrimary: true,
      ),
      _FinancialField(
        'المبلغ',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
        half: true,
      ),
      _FinancialField(
        'العملة',
        Icons.currency_exchange_rounded,
        kind: _FinancialFieldKind.select,
        options: AppSettings.currencySuffixes,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'تاريخ الدين',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      // التذكير بجانب تاريخ الاستحقاق.
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'تذكير',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        half: true,
        options: _kReminderOptions,
      ),
      _FinancialField(
        'عدد الأقساط',
        Icons.format_list_numbered_rounded,
        kind: _FinancialFieldKind.number,
        half: true,
      ),
      _FinancialField(
        'تكرار الأقساط',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['شهري', 'ربع سنوي', 'سنوي'],
        half: true,
      ),
      _FinancialField(
        'إجمالي الأقساط',
        Icons.summarize_outlined,
        kind: _FinancialFieldKind.number,
      ),
      _notesField,
    ],
  ),
  'قسط': _FinancialEntryForm(
    label: 'قسط',
    subtitle: 'جدولة الأقساط ومتابعة السداد',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFFCE8422),
    fields: [
      _FinancialField(
        'الجهة',
        Icons.business_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
        display: 'الفرد / الجهة',
      ),
      _phoneField,
      _emailField,
      // المبلغ الإجمالي يُقسَّم على الأقساط (بالتساوي أو كما يعدّله المستخدم).
      _FinancialField(
        'المبلغ الإجمالي',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
        half: true,
      ),
      _currencyField,
      // بعد كتابة العدد تظهر خانة لكل قسط بتاريخه (جدول الأقساط).
      _FinancialField(
        'عدد الأقساط',
        Icons.format_list_numbered_rounded,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
      ),
      _notesField,
    ],
  ),
  'غرامة': _FinancialEntryForm(
    label: 'غرامة',
    subtitle: 'غرامة أو مخالفة مالية',
    icon: Icons.gavel_outlined,
    color: Color(0xFFA82F26),
    fields: [
      _FinancialField(
        'مبلغ الغرامة',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['غرامات'],
        allowCustom: true,
      ),
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        isTitle: true,
        allowCustom: true,
      ),
      _FinancialField('الجهة', Icons.business_outlined, isPrimary: true),
      _FinancialField(
        'تاريخ الغرامة',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'الملاحظات',
        Icons.notes_rounded,
        kind: _FinancialFieldKind.multiline,
        isPrimary: true,
      ),
      _FinancialField('رقم المخالفة', Icons.numbers_rounded),
    ],
  ),
  // مناسبة وهدية بنفس الجدول في الملف المعتمد: صورة، عنوان، نوع من
  // التصنيف الفرعي، أهمية، تاريخ، هاتف، تكرار، تذكيرات.
  'مناسبة': _FinancialEntryForm(
    label: 'مناسبة',
    subtitle: 'تسجيل مناسبة وما يرتبط بها',
    icon: Icons.celebration_outlined,
    color: Color(0xFFC4392E),
    fields: [
      _FinancialField(
        'النوع',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'عيد ميلاد',
          'ذكرى زواج / خطوبة',
          'تخرج',
          'وظيفة جديدة',
          'مناسبة عائلية',
          'مناسبة دينية',
        ],
        allowCustom: true,
      ),
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      // التذكير بجانب تاريخ المناسبة.
      _FinancialField(
        'تاريخ المناسبة',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        half: true,
        options: _kReminderOptions,
      ),
      _FinancialField('رقم الهاتف', Icons.phone_outlined, isPrimary: true),
      _FinancialField(
        'تكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'سنوي', 'شهري', 'أسبوعي'],
        allowCustom: true,
      ),
      _notesField,
    ],
  ),
  'هدية': _FinancialEntryForm(
    label: 'هدية',
    subtitle: 'هدية مرتبطة بمناسبة',
    icon: Icons.volunteer_activism_outlined,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'النوع',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'عيد ميلاد',
          'ذكرى زواج / خطوبة',
          'تخرج',
          'وظيفة جديدة',
          'مناسبة عائلية',
          'مناسبة دينية',
        ],
        allowCustom: true,
      ),
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'أهمية المناسبة',
        Icons.priority_high_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['عادية', 'مهمة', 'مهمة جداً'],
      ),
      // التذكير بجانب تاريخ المناسبة.
      _FinancialField(
        'تاريخ المناسبة',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        half: true,
        options: _kReminderOptions,
      ),
      _FinancialField('رقم الهاتف', Icons.phone_outlined, isPrimary: true),
      _FinancialField(
        'تكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'سنوي', 'شهري', 'أسبوعي'],
        allowCustom: true,
      ),
      _notesField,
    ],
  ),
  'عهدة مالية': _FinancialEntryForm(
    label: 'عهدة مالية',
    subtitle: 'تسجيل مبلغ تحت مسؤولية شخص ومتابعة تسويته',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF0E7161),
    fields: [
      _FinancialField(
        'اسم العهدة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'قيمة العهدة',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
        half: true,
      ),
      // تنبيه نسبة الصرف بجانب قيمة العهدة.
      _FinancialField(
        _custodyAlertLabel,
        Icons.notifications_active_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        half: true,
        options: _custodyAlertOptions,
      ),
      _FinancialField(
        'اسم المستلم',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      // العهدة لا تُفتح بلا مسؤول: الرقم التعريفي إلزامي، وعليه يُبنى
      // طلب القبول عند الطرف الآخر وصلاحية الصرف بعده.
      // يُكتب داخل خانة «المستلم» نفسها (مخفي كحقل مستقل).
      _FinancialField(
        _custodyHolderIdLabel,
        Icons.badge_outlined,
        isPrimary: true,
        hidden: true,
      ),
      // يُختار من مستطيل تحت خانة المستلم (مخفي كحقل مستقل).
      _FinancialField(
        _custodyApprovalLabel,
        Icons.verified_outlined,
        isPrimary: true,
        hidden: true,
      ),
      // تاريخ تسليم العهدة — بلا حقل تذكير بجانبه.
      _FinancialField(
        'تاريخ التسليم',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField('الغرض من العهدة', Icons.flag_outlined),
      _FinancialField(
        'حالة العهدة',
        Icons.fact_check_outlined,
        kind: _FinancialFieldKind.select,
        options: ['مستلمة', 'قيد الاستخدام', 'تمت التسوية', 'معادة', 'متأخرة'],
      ),
      _FinancialField('رقم المرجع أو المستند', Icons.numbers_rounded),
      _notesField,
    ],
  ),
  'الحسابات والبيانات': _FinancialEntryForm(
    label: 'الحسابات والبيانات',
    subtitle: 'كلمات المرور والحسابات المسجلة',
    icon: Icons.manage_accounts_outlined,
    color: Color(0xFF46534F),
    fields: [
      _FinancialField(
        'التصنيف / النوع',
        Icons.category_outlined,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'الاسم',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'اسم المستخدم',
        Icons.person_outline_rounded,
        isPrimary: true,
      ),
      _FinancialField(
        'كلمة المرور',
        Icons.password_rounded,
        kind: _FinancialFieldKind.secret,
        isPrimary: true,
      ),
      _notesField,
    ],
  ),
  'اشتراك': _FinancialEntryForm(
    label: 'اشتراك',
    subtitle: 'اشتراك دوري أو خدمة متكررة',
    icon: Icons.autorenew,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'الاسم',
        Icons.subscriptions_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'النوع',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'قنوات تلفزيونية',
          'الهاتف والإنترنت',
          'التطبيقات',
          'خصومات',
        ],
        allowCustom: true,
      ),
      _primaryAmount,
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'شهري',
          'ربع سنوي',
          'نصف سنوي',
          'سنوي',
          'شهر أختاره',
        ],
        allowCustom: true,
      ),
      // التذكير بجانب تاريخ الاستحقاق.
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        half: true,
        options: _kReminderOptions,
      ),
      _notesField,
    ],
  ),
  'جمعية': _FinancialEntryForm(
    label: 'جمعية',
    subtitle: 'تنظيم الأدوار والمدفوعات',
    icon: Icons.groups_outlined,
    color: Color(0xFF0A5A50),
    fields: [
      _FinancialField(
        'اسم الجمعية',
        Icons.groups_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'قيمة الاشتراك',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _FinancialField(
        'تاريخ البداية',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'عدد الأعضاء',
        Icons.group_outlined,
        kind: _FinancialFieldKind.number,
        isPrimary: true,
      ),
      _FinancialField(
        'رقم الدور',
        Icons.format_list_numbered_rounded,
        kind: _FinancialFieldKind.number,
      ),
      _FinancialField(
        'تاريخ الاستلام',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
      ),
      _FinancialField('طريقة الدفع', Icons.wallet_outlined),
      _notesField,
    ],
  ),
  'مستند': _FinancialEntryForm(
    label: 'مستند',
    subtitle: 'وثيقة أو عقد أو ملف مهم',
    icon: Icons.description_outlined,
    color: Color(0xFFCE8422),
    fields: [
      _FinancialField(
        'اسم المستند',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'نوع المستند',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'هوية',
          'جواز سفر',
          'اقامة وتأشيرة',
          'رخصة قيادة',
          'ملكية سيارة',
          'تأمين سيارة',
          'تأمين صحي',
          'مستند دراسي',
          'مستند سفر',
          'مستند بنكي',
          'تقرير طبي',
          'تصاريح',
          'ضمانات',
          'فواتير',
          'ايصالات',
        ],
        allowCustom: true,
      ),
      _FinancialField('رقم المستند', Icons.numbers_rounded, isPrimary: true),
      _FinancialField(
        'الجهة المصدرة',
        Icons.account_balance_outlined,
        isPrimary: true,
      ),
      _FinancialField(
        'تاريخ الإصدار',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField(
        'تاريخ الانتهاء',
        Icons.event_busy_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      // تذكير قبل انتهاء المستند — كان غائبًا رغم أنه سبب تسجيل المستند.
      _FinancialField(
        'تذكير',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['بدون تذكير', 'قبل أسبوع', 'قبل شهر', 'قبل شهرين'],
        hint: 'تذكير قبل تاريخ الانتهاء',
      ),
      _notesField,
    ],
  ),
  'متابعة': _FinancialEntryForm(
    label: 'متابعة',
    subtitle: 'مهمة أو موعد يحتاج متابعة',
    icon: Icons.fact_check_outlined,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'موضوع المتابعة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ المتابعة',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'الحالة',
        Icons.pending_actions_outlined,
        isPrimary: true,
      ),
      _FinancialField('الأولوية', Icons.priority_high_rounded, isPrimary: true),
      _FinancialField('المسؤول', Icons.person_outline_rounded),
      _FinancialField('التذكير', Icons.notifications_outlined),
      _notesField,
    ],
  ),
  'تسجيل / تخطيط': _FinancialEntryForm(
    label: 'تسجيل / تخطيط',
    subtitle: 'فكرة أو ملاحظة أو خطة مستقبلية',
    icon: Icons.edit_calendar_outlined,
    color: Color(0xFF0A5A50),
    fields: [
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'النوع',
        Icons.category_outlined,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'التاريخ',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField('الهدف', Icons.flag_outlined),
      _FinancialField(
        'التفاصيل',
        Icons.notes_rounded,
        kind: _FinancialFieldKind.multiline,
      ),
      _FinancialField('التذكير', Icons.notifications_outlined),
    ],
  ),
  'كلمات السر': _FinancialEntryForm(
    label: 'كلمات السر',
    subtitle: 'بيانات دخول خاصة بالحساب',
    icon: Icons.password_rounded,
    color: Color(0xFF46534F),
    fields: [
      _FinancialField(
        'اسم الحساب أو الخدمة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'اسم المستخدم',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'كلمة المرور',
        Icons.password_rounded,
        kind: _FinancialFieldKind.secret,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('رابط الموقع', Icons.link_rounded),
      _notesField,
    ],
  ),
  'الإيميلات': _FinancialEntryForm(
    label: 'الإيميلات',
    subtitle: 'حساب بريد إلكتروني وبيانات الاسترداد',
    icon: Icons.alternate_email_rounded,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'اسم الحساب',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'البريد الإلكتروني',
        Icons.email_outlined,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'كلمة المرور',
        Icons.password_rounded,
        kind: _FinancialFieldKind.secret,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('بريد الاسترداد', Icons.mark_email_read_outlined),
      _FinancialField('رقم الهاتف', Icons.phone_outlined),
      _notesField,
    ],
  ),
  'الحسابات البنكية': _FinancialEntryForm(
    label: 'الحسابات البنكية',
    subtitle: 'بيانات الحساب والآيبان',
    icon: Icons.account_balance_outlined,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'اسم البنك',
        Icons.account_balance_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'صاحب الحساب',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'رقم الحساب',
        Icons.pin_outlined,
        kind: _FinancialFieldKind.secret,
        isPrimary: true,
      ),
      _FinancialField(
        'رقم الآيبان',
        Icons.credit_card_outlined,
        kind: _FinancialFieldKind.secret,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('الفرع', Icons.location_city_outlined),
      _FinancialField(
        'العملة',
        Icons.currency_exchange_rounded,
        kind: _FinancialFieldKind.select,
        options: AppSettings.currencySuffixes,
      ),
      _notesField,
    ],
  ),
  'مهمة': _FinancialEntryForm(
    label: 'مهمة',
    subtitle: 'متابعة وتخطيط مهمة شخصية',
    icon: Icons.task_alt_outlined,
    color: Color(0xFF178F7B),
    fields: _organizationFields,
  ),
  'موعد': _FinancialEntryForm(
    label: 'موعد',
    subtitle: 'موعد شخصي مع تكرار وتذكيرات',
    icon: Icons.event_outlined,
    color: Color(0xFF0A5A50),
    fields: _organizationFields,
  ),
  'عادة': _FinancialEntryForm(
    label: 'عادة',
    subtitle: 'عادة متكررة للمتابعة اليومية أو الأسبوعية',
    icon: Icons.repeat_rounded,
    color: Color(0xFF178F7B),
    fields: _organizationFields,
  ),
  'ملاحظات': _FinancialEntryForm(
    label: 'ملاحظات',
    subtitle: 'ملاحظة أو فكرة تحتاج متابعة',
    icon: Icons.sticky_note_2_outlined,
    color: Color(0xFF5C6B68),
    fields: _organizationFields,
  ),
  'كلمات سر': _FinancialEntryForm(
    label: 'كلمات سر',
    subtitle: 'حفظ بيانات الحسابات وكلمات السر',
    icon: Icons.password_rounded,
    color: Color(0xFF46534F),
    fields: [
      _FinancialField(
        'اسم الحساب',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'نوع الحساب',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['إيميلات', 'حسابات بنكية', 'تطبيقات'],
        allowCustom: true,
      ),
      _FinancialField(
        'اسم المستخدم',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'كلمة السر',
        Icons.password_rounded,
        kind: _FinancialFieldKind.secret,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('الرابط', Icons.link_rounded, isPrimary: true),
      _notesField,
    ],
  ),
  'أدوية': _FinancialEntryForm(
    label: 'أدوية',
    subtitle: 'بيانات الدواء والجرعات والتذكيرات',
    icon: Icons.medication_outlined,
    color: Color(0xFFC4392E),
    fields: [
      // أول خانة: لمن هذا الدواء، حتى تُصنَّف الأدوية من أول لحظة.
      _FinancialField(
        'لمن هذا الدواء',
        Icons.person_outline_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['أدوية لي', 'أدوية لشخص آخر'],
        allowCustom: true,
      ),
      _FinancialField(
        'اسم الدواء',
        Icons.medication_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      // فترة الدواء في سطر واحد: من تاريخ إلى تاريخ.
      _FinancialField(
        'من تاريخ',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'إلى تاريخ',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
        half: true,
      ),
      // نمط الجرعات: كل اختيار يفتح حقله الخاص تحته.
      _FinancialField(
        'نمط الجرعات',
        Icons.schedule_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'مرة واحدة',
          'يومياً',
          'كل عدد من الساعات',
          'أيام أسبوع محددة',
          'كل عدد من الأيام',
          'تواريخ مخصصة',
        ],
      ),
      _FinancialField(
        'كل كم ساعة',
        Icons.hourglass_bottom_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: [
          'كل 4 ساعات',
          'كل 6 ساعات',
          'كل 8 ساعات',
          'كل 12 ساعة',
        ],
        allowCustom: true,
      ),
      _FinancialField(
        'أيام الأسبوع',
        Icons.calendar_view_week_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: [
          'السبت',
          'الأحد',
          'الاثنين',
          'الثلاثاء',
          'الأربعاء',
          'الخميس',
          'الجمعة',
        ],
        allowCustom: true,
      ),
      _FinancialField(
        'كل كم يوم',
        Icons.repeat_on_rounded,
        kind: _FinancialFieldKind.number,
        isPrimary: true,
        hint: 'مثال: 3',
      ),
      _FinancialField(
        'تواريخ مخصصة',
        Icons.event_repeat_outlined,
        isPrimary: true,
        hint: 'مثال: 5/1 و 12/1 و 19/1',
      ),
      // وقت الجرعة ووقت إضافي في سطر واحد.
      _FinancialField(
        'وقت الجرعة',
        Icons.alarm_rounded,
        kind: _FinancialFieldKind.time,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'وقت إضافي',
        Icons.more_time_rounded,
        kind: _FinancialFieldKind.time,
        isPrimary: true,
        half: true,
      ),
      // التذكيرات في الحقول الأساسية: مفتاح، وبعده خيار التذكير المسبق.
      _FinancialField(
        'تفعيل التذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.toggle,
        isPrimary: true,
      ),
      _FinancialField(
        'التذكير قبل الموعد',
        Icons.notifications_active_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: [
          'قبل 5 دقائق',
          'قبل ربع ساعة',
          'قبل نصف ساعة',
          'قبل ساعة',
        ],
        allowCustom: true,
      ),
      _FinancialField(
        'شكل الدواء',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: [
          'قرص',
          'كبسولة',
          'شراب',
          'حقن',
          'قطرات',
          'بخاخ',
          'كريم',
          'أخرى',
        ],
        allowCustom: true,
      ),
      // الجرعة ووحدتها في سطر واحد.
      _FinancialField(
        'الجرعة',
        Icons.medical_information_outlined,
        isPrimary: true,
        half: true,
      ),
      _FinancialField(
        'وحدة الجرعة',
        Icons.straighten_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: [
          'قرص',
          'كبسولة',
          'قطرات',
          'ml',
          'mg',
          'puffs',
          'units',
          'أخرى',
        ],
        allowCustom: true,
        half: true,
      ),
      _FinancialField(
        'تعليمات الطعام',
        Icons.restaurant_outlined,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['قبل الطعام', 'مع الطعام', 'بعد الطعام', 'دون تفصيل'],
      ),
      _FinancialField('الاسم العلمي', Icons.science_outlined),
      _FinancialField('التركيز', Icons.speed_outlined),
      // تفاصيل الرعاية: عنوان أسود تحته بيانات الطبيب والصيدلية والوصفة.
      _FinancialField('تفاصيل الرعاية', Icons.local_hospital_outlined,
          kind: _FinancialFieldKind.header),
      _FinancialField('اسم الطبيب', Icons.person_pin_outlined),
      _FinancialField('اسم الصيدلية', Icons.local_pharmacy_outlined),
      _FinancialField('رقم الوصفة', Icons.receipt_long_outlined),
      _notesField,
    ],
  ),
  'مواقع وأماكن': _FinancialEntryForm(
    label: 'مواقع وأماكن',
    subtitle: 'حفظ مكان مهم وبيانات الوصول إليه',
    icon: Icons.location_on_outlined,
    color: Color(0xFFCE8422),
    fields: [
      _FinancialField(
        'اسم المكان',
        Icons.place_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'الموقع أو الرابط',
        Icons.link_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('العنوان', Icons.signpost_outlined, isPrimary: true),
      _FinancialField(
        'التصنيف',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'المنزل',
          'العمل',
          'مطعم',
          'صديق',
          'عميل',
          'مهم',
        ],
        allowCustom: true,
      ),
      _geoField,
      _notesField,
    ],
  ),
  'تجديد': _FinancialEntryForm(
    label: 'تجديد',
    subtitle: 'تذكير بتجديد إجراء أو وثيقة مرتبطة بهذا الالتزام',
    icon: Icons.autorenew_rounded,
    color: Color(0xFF178F7B),
    fields: [
      _FinancialField(
        'عنوان التجديد',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ التجديد',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['بدون تكرار', 'شهري', 'كل 3 شهور', 'كل 6 شهور', 'سنوي'],
      ),
      _FinancialField(
        'التذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: [
          'بدون تذكير',
          'قبل يوم',
          'قبل 3 أيام',
          'قبل أسبوع',
          'قبل 10 أيام',
          'قبل أسبوعين',
          'قبل شهر',
        ],
        allowCustom: true,
      ),
      _notesField,
    ],
  ),
  'تذكير': _FinancialEntryForm(
    label: 'تذكير',
    subtitle: 'تذكير بموعد أو التزام',
    icon: Icons.notifications_active_outlined,
    color: Color(0xFF0E7161),
    fields: _organizationFields,
  ),
  'تفويض': _FinancialEntryForm(
    label: 'تفويض',
    subtitle: 'صلاحية بلا مبلغ — للصرف افتح عهدة مالية',
    icon: Icons.assignment_ind_outlined,
    color: Color(0xFF0E7161),
    fields: [
      // التفويض صلاحية لا مال: من سيصرف من مالك ويرسل لك الفواتير تُفتح
      // له عهدة مالية بالرقم التعريفي، لا تفويض.
      _FinancialField(
        'التفويض صلاحية بلا مبلغ — للصرف افتح عهدة مالية',
        Icons.info_outline_rounded,
        kind: _FinancialFieldKind.header,
      ),
      _FinancialField(
        'اسم المفوَّض',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField('رقم الهاتف', Icons.phone_outlined, isPrimary: true),
      _FinancialField(
        'نطاق التفويض',
        Icons.rule_folder_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'كل المصروفات الشخصية',
          'فئة محددة',
          'التزام واحد فقط',
          'مخصص',
        ],
      ),
      _FinancialField(
        'تاريخ بداية التفويض',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField(
        'تاريخ نهاية التفويض',
        Icons.event_busy_outlined,
        kind: _FinancialFieldKind.date,
      ),
      _notesField,
    ],
  ),
};

class _EntryCategory {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<_EntryType> types;

  const _EntryCategory({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.types,
  });
}

class _EntryCategoryCard extends StatelessWidget {
  final _EntryCategory category;
  final VoidCallback onTap;

  const _EntryCategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
        // بلا FittedBox: كان يصغّر المحتوى فيبقى أغلب الصندوق فارغًا.
        child: Center(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                  ),
                  child: Icon(category.icon, color: category.color, size: 30),
                ),
                PositionedDirectional(
                  top: -4,
                  start: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: category.color.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '${category.types.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: category.color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              // الاسم الطويل على سطرين بدل قصّه.
              category.title.replaceAll(' وكلمات سر', '\nوكلمات السر'),
              maxLines: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              // نقاط في آخر السطر للدلالة على أن الفئة تضم أكثر من المذكور.
              category.subtitle.endsWith('…')
                  ? category.subtitle
                  : '${category.subtitle} …',
              maxLines: 5,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _EntryTypeCard extends StatelessWidget {
  final _EntryType type;
  final Color color;
  final VoidCallback onTap;

  const _EntryTypeCard({
    required this.type,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
        // نسق واحد لكل أنواع الإدخال: نفس مقاس الأيقونة والخط في كل فئة.
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(type.icon, color: color, size: 24),
              ),
              const SizedBox(height: 7),
              Text(
                type.label,
                maxLines: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitmentItem {
  final String? id;
  final String category;
  String title;
  String status;
  Color statusColor;
  int totalAmount;
  int paidAmount;
  String dueDate;
  double progress;
  final int remainingInstallments;
  String lastUpdate;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final int? subscriptionMembers;
  final List<_SubscriptionPayment> payments;
  final String? entryType;
  Map<String, String> details;
  String? attachmentPath;

  int get amount => totalAmount - paidAmount;

  /// عملة هذا الالتزام: ما اختير له وحده، وإلا العملة الافتراضية للتطبيق.
  String get currency => AppSettings.currencyOf(details['العملة']);
  bool get isSubscription => subscriptionMembers != null;

  _CommitmentItem({
    this.id,
    this.category = 'financial',
    required this.title,
    required this.status,
    required this.statusColor,
    required int amount,
    required this.dueDate,
    required this.progress,
    required this.remainingInstallments,
    required this.lastUpdate,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.subscriptionMembers,
    List<_SubscriptionPayment>? payments,
    this.entryType,
    Map<String, String>? details,
    this.attachmentPath,
    int? paidAmount,
  }) : totalAmount = amount,
       paidAmount = paidAmount ?? 0,
       payments = payments ?? [],
       details = details ?? const {};
}

class _SubscriptionPayment {
  final String payerName;
  final int amount;
  final String date;
  final String? invoiceImagePath;

  const _SubscriptionPayment({
    required this.payerName,
    required this.amount,
    required this.date,
    this.invoiceImagePath,
  });
}

Color _personalStatusColor(String status) {
  return switch (status) {
    'متأخرة' => const Color(0xFFC4392E),
    'قريبة الاستحقاق' => const Color(0xFFCE8422),
    // المكتمل أسود والمتأخر أحمر في كل التطبيق.
    'مكتملة' => const Color(0xFF1E2725),
    'ملغاة' => const Color(0xFF5C6B68),
    _ => const Color(0xFF34A894),
  };
}