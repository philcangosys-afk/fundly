import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/app_settings.dart';
import '../data/shared_entries_repository.dart';
import '../data/fundly_auth.dart';
import '../data/shared_member_state.dart';
import '../data/fundly_account.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/shared/clear_date_suffix.dart';
import '../widgets/shared/app_filter_sheet.dart';
import 'global_summary_screen.dart';
import '../widgets/shared/followup_center_sheet.dart';
import '../widgets/shared/app_design.dart';
import '../widgets/shared/reminder_fields.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/plan_gate.dart';
import '../widgets/shared/archive_sheet.dart';
import '../data/page_customization_store.dart';
import 'smart_calendar_screen.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;
import '../data/template_print.dart' show buildRecordPdf, PrintSection;
import '../widgets/shared/pdf_share.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/custody_sharing.dart';
import '../data/shared_expenses.dart';
import '../data/rosca_cycles.dart';
import '../data/shared_alerts.dart';
import '../data/archive_center.dart';
import '../widgets/shared/category_picker_sheet.dart';
import '../data/document_store.dart';
import '../widgets/shared/maps_link_paste.dart';
import '../widgets/shared/fnd_lookup.dart';
import '../widgets/shared/follow_filters.dart';
import '../data/people_directory_store.dart';
import 'package:geolocator/geolocator.dart';

/// اسم النوع في العناوين: «جمعية مالية» تُعرض «تحديد أدوار».
String _sharedShownType(String type) =>
    type == 'جمعية مالية' ? 'تحديد أدوار' : type;

/// أسماء ظاهرة لبعض الحقول (المفتاح المحفوظ يبقى كما هو).
const Map<String, String> _sharedFieldDisplay = {
  'إجمالي المساهمة': 'إجمالي المساهمة على الكل',
  'الأعضاء / المشتركين': 'المسؤول / الأعضاء',
};

/// مفاتيح داخلية في نموذج الإضافة (لا تُحفظ).
const String _teamTotalKey = '__إجمالي المساهمة على الكل';

/// إيصالات المساهمات الأساسية (اختيارية) تُرفق عند الإضافة.
const String _balanceReceiptsKey = 'إيصالات الأرصدة';

List<String> _balanceReceipts(Map<String, String> details) {
  try {
    final decoded = jsonDecode(details[_balanceReceiptsKey] ?? '[]');
    if (decoded is List) {
      return [
        for (final v in decoded)
          if ('$v'.trim().isNotEmpty) '$v'.trim(),
      ];
    }
  } catch (_) {}
  return const [];
}

/// ترتيب الاستلام في تحديد الأدوار (المسؤول ضمنه ويُرتَّب مثل الجميع).
const String _roscaOrderKey = '__ترتيب الاستلام';

/// اسمي كما يُضاف في الأعضاء: الاسم الظاهر للآخرين ومعه رقمي التعريفي.
String _myTeamEntry() {
  final id = AppIdentity.id;
  final name = AppSettings.instance.publicName.trim().isNotEmpty
      ? AppSettings.instance.publicName.trim()
      : AppSettings.instance.name.trim();
  if (id.isEmpty) return name;
  return name.isEmpty ? id : '$name ($id)';
}
const String _splitManualFlag = '__تقسيم يدوي';

/// تنبيه داخل نموذج الإضافة: نافذة صغيرة فوق النموذج نفسه، لأن رسالة
/// أسفل الشاشة تختفي خلف النافذة المنبثقة.
Future<void> _sharedFormNotice(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
        ),
        title: const Text(
          'تنبيه',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF022E2A),
          ),
        ),
        content: Text(
          message,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.7,
            fontWeight: FontWeight.w600,
            color: Color(0xFF46534F),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    ),
  );
}

String _fmtShare(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

/// توزيع الإجمالي على الأشخاص بالتساوي (الفرق على آخر شخص)، ما لم يعدّل
/// المستخدم المبالغ يدويًا.
void _autoSplitShares({
  required String totalText,
  required List<String> people,
  required Map<String, String?> selectValues,
  required Map<String, String> splitValues,
  required Map<String, TextEditingController> splitControllers,
}) {
  if (selectValues[_splitManualFlag] == 'manual') return;
  final total = parseMoney(totalText.trim()) ?? 0;
  if (total <= 0 || people.isEmpty) return;
  final each = (total / people.length * 100).floorToDouble() / 100;
  for (var i = 0; i < people.length; i++) {
    final value = i == people.length - 1 ? total - each * (people.length - 1) : each;
    final text = _fmtShare(value);
    splitValues[people[i]] = text;
    splitControllers[people[i]]?.text = text;
  }
  splitValues.removeWhere((key, _) => !people.contains(key));
}

/// أعضاء تحديد الأدوار: المسؤول ثم الأعضاء بلا تكرار.
List<String> _roscaPeople(
  Map<String, TextEditingController> controllers,
  Map<String, List<String>> peopleValues,
) {
  final manager = controllers[_sharedManagerKey]?.text.trim() ?? '';
  return <String>[
    if (manager.isNotEmpty) manager,
    ...(peopleValues[_sharedMembersKey] ?? const <String>[])
        .where((m) => m != manager),
  ];
}

/// اختيار صورة إيصال/مستند وحفظ نسخة منها داخل التطبيق.
Future<String?> _pickReceiptFile(BuildContext context) async {
  try {
    final picked = await DocumentStore.pickXFile(context);
    if (picked == null) return null;
    return await DocumentStore.copyIntoApp(picked.path, picked.name) ??
        picked.path;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح المعرض — تحقق من إذن الوصول إلى الصور'),
        ),
      );
    }
    return null;
  }
}

/// زر «إرفاق» موحّد: يتحوّل إلى علامة صح بعد الاختيار.
Widget _receiptButton({
  required String label,
  required String path,
  required Color accent,
  required VoidCallback onTap,
  VoidCallback? onRemove,
}) => AppRemovableAttachment(
  attached: path.isNotEmpty && onRemove != null,
  onRemove: onRemove ?? () {},
  child: OutlinedButton.icon(
  onPressed: onTap,
  icon: Icon(
    path.isEmpty ? Icons.attach_file_rounded : Icons.check_circle_rounded,
    size: 18,
  ),
  label: Text(
    path.isEmpty ? label : 'تم الإرفاق',
    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
  ),
  style: OutlinedButton.styleFrom(
    foregroundColor: accent,
    minimumSize: const Size.fromHeight(46),
    side: BorderSide(color: accent.withValues(alpha: 0.45)),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
    ),
  ),
),
);

/// الموقع الحالي من الجوال (خط العرض، خط الطول).
Future<String?> _sharedFetchLocation(BuildContext context) async {
  void say(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      say('خدمة الموقع مغلقة على الجهاز — فعّلها ثم أعد المحاولة');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      say('لم يُسمح بالوصول إلى الموقع');
      return null;
    }
    final position = await Geolocator.getCurrentPosition();
    return '${position.latitude.toStringAsFixed(6)},'
        '${position.longitude.toStringAsFixed(6)}';
  } catch (_) {
    say('تعذر جلب الموقع');
    return null;
  }
}

// ============================================================================
// الالتزامات المشتركة — نفس قالب الالتزامات الشخصية (بحث + فلتر + مركز
// متابعة + فئات + نماذج إدخال ديناميكية + شاشة تفاصيل بتبويبات)، لكن مع
// مفردات وقواعد مختلفة: 4 أنواع التزام ثابتة بدل فئات ذات أنواع فرعية،
// وإدارة أعضاء/مسؤول/تقسيم مالي/موافقات بدل ذلك.
// ============================================================================

// ---------------------------------------------------------------------------
// أدوات مساعدة JSON: الأعضاء وسجل العمليات المالية (مصروفات/دفعات/ميزانية
// إضافية) يُخزَّنان كنص JSON داخل details، بنفس نمط "سجل صرفيات العهدة" في
// الشخصية — يتفادى الحاجة لجداول علائقية جديدة ويبقي كل شيء ضمن details.
const String _sharedMembersDetailKey = 'الأعضاء';
const String _sharedTransactionsDetailKey = 'سجل العمليات المالية';
const String _sharedNotifyScopeKey = 'إشعار المصروفات';
const String _sharedManagedByKey = 'المبلغ يدار عن طريق';
const String _sharedSplitMethodKey = 'التقسيم المالي';
const String _sharedManagerKey = 'المسؤول';
const String _sharedDeputyKey = 'نائب المسؤول';

class _SharedMember {
  final String name;
  final String role; // مسؤول / نائب المسؤول / عضو
  const _SharedMember({required this.name, required this.role});

  Map<String, String> toMap() => {'name': name, 'role': role};
  factory _SharedMember.fromMap(Map<String, String> map) =>
      _SharedMember(name: map['name'] ?? '', role: map['role'] ?? 'عضو');
}

List<_SharedMember> _parseSharedMembers(Map<String, String> details) {
  final raw = details[_sharedMembersDetailKey];
  if (raw == null || raw.trim().isEmpty) return <_SharedMember>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <_SharedMember>[];
    return decoded
        .whereType<Map>()
        .map(
          (e) => _SharedMember.fromMap(
            e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
          ),
        )
        .toList();
  } catch (_) {
    return <_SharedMember>[];
  }
}

String _encodeSharedMembers(List<_SharedMember> members) =>
    jsonEncode(members.map((m) => m.toMap()).toList());

// عملية مالية واحدة (دفعة/سداد، مصروف، ميزانية إضافية) — تحمل حالة موافقة:
// إن كانت الإدارة "المسؤول" فحقل approved يكفي (true/false)، وإن كانت "جميع
// الأعضاء" فـ approvedBy تحمل أسماء من وافق حتى الآن (والمطلوب 50% فأكثر).
class _SharedTransaction {
  final String kind; // دفعة / سداد / مصروف / ميزانية إضافية
  final String amount;
  final String submittedBy;
  final String purpose;
  final String date;
  final List<String> approvedBy;
  final bool managerApproved;

  const _SharedTransaction({
    required this.kind,
    required this.amount,
    required this.submittedBy,
    required this.purpose,
    required this.date,
    this.approvedBy = const [],
    this.managerApproved = false,
  });

  Map<String, dynamic> toMap() => {
    'kind': kind,
    'amount': amount,
    'submittedBy': submittedBy,
    'purpose': purpose,
    'date': date,
    'approvedBy': approvedBy,
    'managerApproved': managerApproved,
  };

  factory _SharedTransaction.fromMap(Map map) => _SharedTransaction(
    kind: map['kind']?.toString() ?? 'مصروف',
    amount: map['amount']?.toString() ?? '0',
    submittedBy: map['submittedBy']?.toString() ?? '',
    purpose: map['purpose']?.toString() ?? '',
    date: map['date']?.toString() ?? '',
    approvedBy:
        (map['approvedBy'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    managerApproved: map['managerApproved'] == true,
  );

  _SharedTransaction copyWith({
    List<String>? approvedBy,
    bool? managerApproved,
  }) => _SharedTransaction(
    kind: kind,
    amount: amount,
    submittedBy: submittedBy,
    purpose: purpose,
    date: date,
    approvedBy: approvedBy ?? this.approvedBy,
    managerApproved: managerApproved ?? this.managerApproved,
  );

  // معتمدة فعليًا: إمّا موافقة المسؤول (عند إدارة المسؤول)، أو موافقة 50%
  // فأكثر من الأعضاء (عند إدارة جميع الأعضاء).
  bool isApproved({required bool managedByAll, required int membersCount}) {
    if (!managedByAll) return managerApproved;
    if (membersCount <= 0) return approvedBy.isNotEmpty;
    return approvedBy.length / membersCount >= 0.5;
  }
}

List<_SharedTransaction> _parseSharedTransactions(
  Map<String, String> details,
) {
  final raw = details[_sharedTransactionsDetailKey];
  if (raw == null || raw.trim().isEmpty) return <_SharedTransaction>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <_SharedTransaction>[];
    return decoded
        .whereType<Map>()
        .map((e) => _SharedTransaction.fromMap(e))
        .toList();
  } catch (_) {
    return <_SharedTransaction>[];
  }
}

String _encodeSharedTransactions(List<_SharedTransaction> list) =>
    jsonEncode(list.map((t) => t.toMap()).toList());

// المجموع المعتمد فقط (وليس كل ما قُدّم) هو ما يُخصم فعليًا من الميزانية —
// حتى تعكس الأرقام حقيقة ما تمت الموافقة عليه لا مجرد ما قُدّم.
int _sharedApprovedSpent(
  Map<String, String> details, {
  required bool managedByAll,
  required int membersCount,
}) {
  final list = _parseSharedTransactions(details);
  return list
      .where(
        (t) =>
            t.kind == 'مصروف' &&
            t.isApproved(managedByAll: managedByAll, membersCount: membersCount),
      )
      .fold<int>(0, (sum, t) => sum + (int.tryParse(t.amount) ?? 0));
}

int _sharedApprovedExtraBudget(
  Map<String, String> details, {
  required bool managedByAll,
  required int membersCount,
}) {
  final list = _parseSharedTransactions(details);
  return list
      .where(
        (t) =>
            t.kind == 'ميزانية إضافية' &&
            t.isApproved(managedByAll: managedByAll, membersCount: membersCount),
      )
      .fold<int>(0, (sum, t) => sum + (int.tryParse(t.amount) ?? 0));
}

int _sharedApprovedPayments(
  Map<String, String> details, {
  required bool managedByAll,
  required int membersCount,
}) {
  final list = _parseSharedTransactions(details);
  return list
      .where(
        (t) =>
            (t.kind == 'دفعة' || t.kind == 'سداد') &&
            t.isApproved(managedByAll: managedByAll, membersCount: membersCount),
      )
      .fold<int>(0, (sum, t) => sum + (int.tryParse(t.amount) ?? 0));
}

// ---------------------------------------------------------------------------
// تعريف الحقول الديناميكية للنماذج الأربعة — نفس نمط _FinancialField في
// الشخصية، مع إضافة نوع حقل جديد (people) لاختيار الأعضاء/المشتركين كقائمة
// أسماء (chips) بدل حقل نصي واحد.
/// أنواع حقول نماذج الالتزامات المشتركة.
///
/// [header] عنوان قسم أسود، و[person] منتقي شخص من المحفوظين أو بالمعرّف،
/// و[attachment] إرفاق مستند مع الالتزام.
enum _SharedFieldKind {
  text,
  number,
  date,
  multiline,
  select,
  people,
  header,
  person,
  attachment,

  /// ترتيب استلام أعضاء الجمعية: رقم التسلسل بجانب كل عضو.
  order,

  /// تقسيم المبلغ على الأعضاء حسب طريقة التقسيم المختارة.
  split,

  /// طريقة تحصيل مبلغ الرحلة: عنوان بسهم يفتح خيارين بدائرة اختيار وشرح.
  collect,

  /// صندوق المدير والأعضاء: عنوان فيه العدد وزر +، ثم مستطيل لكل شخص.
  team,

  /// ملخّص الجمعية التلقائي: المساهمة على الشخص وعدد الدورات — يُحسبان
  /// من الإجمالي وعدد الأعضاء ولا يُكتبان.
  roscaInfo,
}

// نفس _CommitmentMenuAction في الشخصية: تعديل/مشاركة/حذف/أرشفة من قائمة
// الثلاث نقاط في شاشة التفاصيل.
enum _SharedCommitmentMenuAction {
  edit,
  share,
  delete,
  archive,
  memberJoin,
  memberLeave,
  // العضو (غير المسؤول): «مغادرة المشاركة» بدل الحذف.
  leave,
}

/// سجل أحداث الالتزام (تغيير الدور، التسليم، الإلغاء...) — يظهر في «السجل».
const String _eventsKey = 'سجل الأحداث';

Map<String, String> _withEvent(Map<String, String> details, String text) {
  var list = <dynamic>[];
  try {
    final decoded = jsonDecode(details[_eventsKey] ?? '[]');
    if (decoded is List) list = decoded;
  } catch (_) {}
  list.add({'t': text, 'at': recordStampNow()});
  return Map<String, String>.of(details)..[_eventsKey] = jsonEncode(list);
}

List<(String, String)> _eventsOf(Map<String, String> details) {
  try {
    final decoded = jsonDecode(details[_eventsKey] ?? '[]');
    if (decoded is! List) return const [];
    return [
      for (final e in decoded.whereType<Map>())
        ('${e['t'] ?? ''}', '${e['at'] ?? ''}'),
    ];
  } catch (_) {
    return const [];
  }
}

/// سبب إلغاء المسؤول للالتزام (يراه الأعضاء).
const String _cancelReasonKey = 'سبب الإلغاء';

// نفس _CommitmentMenuItem في الشخصية: أيقونة + تسمية داخل كل عنصر قائمة.
class _SharedCommitmentMenuItem extends StatelessWidget {
  const _SharedCommitmentMenuItem({required this.label, required this.icon, this.color = const Color(0xFF2C3B38)});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// مستطيل مربّع مصغّر لخيارات "+ إضافة" في شاشة تفاصيل الالتزام المشترك،
// مطابق تمامًا لـ _QuickAddTile في الشخصية (نفس الحجم واللون المحايد
// بلا تمييز لوني بين الأنواع).
class _SharedQuickAddTile extends StatelessWidget {
  const _SharedQuickAddTile({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

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
            Text(twoLineLabel(label), maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w800, color: _neutral)),
          ],
        ),
      ),
    );
  }
}

class _SharedField {
  final String label;
  final IconData icon;
  final _SharedFieldKind kind;
  final bool required;
  final bool optional; // فقط لعرض "(اختياري)" بجانب التسمية
  final List<String> options;
  final bool isPrimary; // يظهر في المستطيل الأول (الملخص العلوي)
  final bool isAmount;
  final bool isTitle;

  /// حقل بنصف السطر: يُجمع مع الحقل التالي إن كان نصفًا أيضًا.
  final bool half;

  /// مفتاح المسؤول في صندوق المسؤول/الأعضاء: «مدير الرحلة» في الرحلة،
  /// و«المسؤول» في المشاركات.
  final String managerKey;

  /// حقل يُحفظ ولا يُرسم (مسؤول الجمعية يُختار من «المسؤول / الأعضاء»).
  final bool hidden;

  /// مثال يظهر داخل الحقل الفارغ، مثل «مثال: مساعدة دراسية».
  final String hint;

  const _SharedField(
    this.label,
    this.icon, {
    this.kind = _SharedFieldKind.text,
    this.required = false,
    this.optional = false,
    this.options = const [],
    this.isPrimary = false,
    this.isAmount = false,
    this.isTitle = false,
    this.half = false,
    this.managerKey = _tripManagerKey,
    this.hidden = false,
    this.hint = '',
  });
}

/// طريقة تحصيل المبلغ: صندوق بعنوان وسهم، يفتح خيارين بدائرة اختيار
/// وشرح تحت كل خيار. حالة الفتح محلية فتحتاج ودجة بحالة خاصة بها.
class _CollectMethodField extends StatefulWidget {
  const _CollectMethodField({
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_CollectMethodField> createState() => _CollectMethodFieldState();
}

class _CollectMethodFieldState extends State<_CollectMethodField> {
  late bool _open = widget.value.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final value = widget.value.trim();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rField),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(widget.icon, size: 19, color: AppTheme.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value.isEmpty ? widget.label : '${widget.label}: $value',
                      textAlign: AppTr.alignEnd,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: value.isEmpty ? AppTheme.muted : AppTheme.title,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.title,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: AppTheme.hairline),
            for (final option in _collectMethodOptions)
              InkWell(
                onTap: () {
                  widget.onChanged(option);
                  setState(() => _open = false);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        value == option
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: value == option
                            ? widget.accent
                            : AppTheme.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              option,
                              textAlign: AppTr.alignEnd,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.title,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _collectMethodHints[option] ?? '',
                              textAlign: AppTr.alignEnd,
                              maxLines: 2,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
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
}

/// نموذج المصروف داخل تبويب الحركة المالية — بلا صندوق خارجي: رأسه نفس
/// رأس كل قسم (عنوان وخط، و× للإغلاق مكان +).
class _InlineExpenseForm extends StatefulWidget {
  const _InlineExpenseForm({
    required this.members,
    required this.payers,
    required this.currency,
    required this.accent,
    required this.onCancel,
    required this.onSave,
    this.activeOn,
    this.memberNote,
    this.lastRates = const {},
    this.potLeft = double.infinity,
    this.initialPayer,
  });

  /// من دفع افتراضيًا (إن كان ضمن [payers]).
  final String? initialPayer;

  /// المتبقي في الميزانية المشتركة: لا يُصرف منها أكثر منه.
  final double potLeft;

  /// هل كان العضو ضمن الرحلة يوم المصروف (انضمام/مغادرة بتاريخ).
  final bool Function(String member, DateTime day)? activeOn;

  /// ملاحظة بجانب اسم العضو: «غادر في ...» أو «انضم في ...».
  final String Function(String member)? memberNote;

  /// آخر سعر صرف لكل عملة في هذا الالتزام.
  final Map<String, double> lastRates;

  final List<String> members;

  /// من يمكن أن يكون قد دفع: الأعضاء، ومعهم الوعاء المشترك إن وُجد.
  final List<String> payers;
  final String currency;
  final Color accent;
  final VoidCallback onCancel;
  final void Function(SharedExpense expense) onSave;

  @override
  State<_InlineExpenseForm> createState() => _InlineExpenseFormState();
}

class _InlineExpenseFormState extends State<_InlineExpenseForm> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();

  /// قيمة كل مشارك حسب الطريقة: نسبة أو مبلغ أو عدد حصص.
  late final Map<String, TextEditingController> _shareControllers = {
    for (final name in widget.members) name: TextEditingController(),
  };
  late String _payer = widget.payers.contains(widget.initialPayer)
      ? widget.initialPayer!
      : (widget.payers.isEmpty ? '' : widget.payers.first);
  // المشاركون افتراضيًا: من كان ضمن الرحلة يوم المصروف.
  late final Set<String> _participants = {
    for (final name in widget.members)
      if (widget.activeOn?.call(name, DateTime.now()) ?? true) name,
  };

  /// عملة المصروف (افتراضيًا عملة الالتزام) وسعر صرفها إليها.
  late String _currency = widget.currency;
  final _rateController = TextEditingController();

  bool get _foreign => _currency != widget.currency;

  double get _rate =>
      _foreign ? (parseMoney(_rateController.text.trim()) ?? 0) : 1;

  void _setCurrency(String value) {
    setState(() {
      _currency = value;
      final last = widget.lastRates[value];
      // السعر كما هو بكل خاناته (0.075 مثلًا) حتى لا يختل الحساب.
      _rateController.text = last == null ? '' : '$last';
    });
  }

  /// تغيير التاريخ يعيد اختيار المشاركين حسب من كان ضمن الرحلة يومها.
  void _applyDate(DateTime day) {
    final activeOn = widget.activeOn;
    if (activeOn == null) return;
    _participants
      ..clear()
      ..addAll(widget.members.where((name) => activeOn(name, day)));
  }
  String _method = SharedExpense.methodEqual;
  String _category = '';
  String _subcategory = '';
  bool _showParticipants = false;

  /// صورة الفاتورة / الإيصال المرفقة مع المصروف.
  String _receipt = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateController.text = '${now.day}/${now.month}/${now.year}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _rateController.dispose();
    for (final controller in _shareControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _amount => parseMoney(_amountController.text.trim()) ?? 0;

  double _input(String name) =>
      parseMoney(_shareControllers[name]?.text.trim() ?? '') ?? 0;

  List<String> get _included =>
      widget.members.where(_participants.contains).toList(growable: false);

  String _fmt(double value) =>
      value.toStringAsFixed(value.abs() % 1 == 0 ? 0 : 2);

  /// نصيب المشارك بالعملة حسب الطريقة — يُعرض تحت اسمه لحظيًا.
  double _moneyFor(String name) {
    final included = _included;
    if (!included.contains(name)) return 0;
    switch (_method) {
      case SharedExpense.methodPercent:
        return _amount * _input(name) / 100;
      case SharedExpense.methodExact:
        return _input(name);
      case SharedExpense.methodShares:
        final total = included.fold<double>(0, (s, n) => s + _input(n));
        return total <= 0 ? 0 : _amount * _input(name) / total;
      default:
        return included.isEmpty ? 0 : _amount / included.length;
    }
  }

  /// حالة التقسيم: نص يشرح ما تبقّى، وهل يصلح للحفظ.
  (String, bool) _splitStatus() {
    final included = _included;
    if (included.isEmpty) return ('اختر مشاركًا واحدًا على الأقل', false);
    switch (_method) {
      case SharedExpense.methodPercent:
        final sum = included.fold<double>(0, (s, n) => s + _input(n));
        final ok = (sum - 100).abs() < 0.1;
        return (
          ok
              ? 'مجموع النِّسب 100% ✓'
              : 'مجموع النِّسب ${_fmt(sum)}% — يجب أن يكون 100% '
                    '(المتبقي ${_fmt(100 - sum)}%)',
          ok,
        );
      case SharedExpense.methodExact:
        final sum = included.fold<double>(0, (s, n) => s + _input(n));
        final ok = _amount > 0 && (sum - _amount).abs() < 0.01;
        return (
          ok
              ? 'المبالغ تساوي إجمالي المصروف ✓'
              : 'مجموع المبالغ ${_fmt(sum)} من ${_fmt(_amount)} '
                    '$_currency — المتبقي ${_fmt(_amount - sum)}',
          ok,
        );
      case SharedExpense.methodShares:
        final ok = included.every((n) => _input(n) > 0);
        return (
          ok
              ? 'مجموع الحصص ${_fmt(included.fold<double>(0, (s, n) => s + _input(n)))}'
              : 'اكتب عدد الحصص لكل مشارك',
          ok,
        );
      default:
        return (
          'نصيب كل مشارك ${_fmt(_amount / included.length)} '
              '$_currency',
          true,
        );
    }
  }

  void _changeMethod(String method) {
    setState(() {
      _method = method;
      _showParticipants = method != SharedExpense.methodEqual;
      final included = _included;
      // بداية معقولة بدل حقول فارغة: نِسب متساوية، أو حصة لكل واحد.
      for (final name in widget.members) {
        final controller = _shareControllers[name]!;
        if (method == SharedExpense.methodPercent) {
          controller.text = included.contains(name) && included.isNotEmpty
              ? _fmt(100 / included.length)
              : '';
        } else if (method == SharedExpense.methodShares) {
          controller.text = included.contains(name) ? '1' : '';
        } else {
          controller.text = '';
        }
      }
    });
  }

  Future<void> _pickCategory() async {
    final picked = await showCategoryPickerSheet(
      context: context,
      groups: [
        for (final entry in SharedExpense.categoryGroups.entries)
          CategoryGroup(main: entry.key, subs: entry.value),
      ],
      selectedMain: _category,
      selectedSub: _subcategory.isEmpty ? null : _subcategory,
      accent: widget.accent,
      title: 'فئة المصروف',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _category = picked.main;
      _subcategory = picked.sub ?? '';
    });
  }

  void _fail(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      _fail('اكتب اسم المصروف');
      return;
    }
    if (_category.isEmpty) {
      _fail('اختر فئة المصروف');
      return;
    }
    if (_amount <= 0) {
      _fail('اكتب مبلغ المصروف');
      return;
    }
    if (_payer.isEmpty) {
      _fail('اختر من دفع المصروف');
      return;
    }
    final (status, ok) = _splitStatus();
    if (!ok) {
      setState(() => _showParticipants = true);
      _fail(status);
      return;
    }
    if (_foreign && _rate <= 0) {
      _fail('اكتب سعر الصرف');
      return;
    }
    final baseAmount = _foreign ? _amount * _rate : _amount;
    if (_payer == SharedLedger.potPayer && baseAmount > widget.potLeft + 0.01) {
      _fail(
        '${AppTr.tr('المتبقي في الميزانية')} ${_fmt(widget.potLeft)} '
        '${widget.currency} — '
        '${AppTr.tr('اختر من دفع الفرق أو أضف ميزانية إضافية')}',
      );
      return;
    }
    widget.onSave(
      SharedExpense(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        description: _nameController.text.trim(),
        // الحساب كله بعملة الالتزام: المبلغ × سعر الصرف.
        amount: _foreign ? _amount * _rate : _amount,
        currency: _foreign ? _currency : '',
        originalAmount: _foreign ? _amount : 0,
        rate: _foreign ? _rate : 1,
        payer: _payer,
        date: _dateController.text.trim(),
        participants: _included,
        method: _method,
        shares: _method == SharedExpense.methodEqual
            ? const {}
            : {for (final name in _included) name: _input(name)},
        category: _category,
        subcategory: _subcategory,
        receipt: _receipt,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    alignment: AlignmentDirectional.centerEnd,
    iconEnabledColor: AppTheme.title,
    decoration: InputDecoration(
      isDense: true,
      label: Text(label, maxLines: 2, softWrap: true),
      prefixIcon: Icon(icon, size: 18),
    ),
    selectedItemBuilder: (context) => [
      for (final item in items)
        Container(
          alignment: AlignmentDirectional.centerEnd,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _shownName(item),
              maxLines: 3,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.title,
              ),
            ),
          ),
        ),
    ],
    items: [
      for (final item in items)
        DropdownMenuItem(
          value: item,
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            _shownName(item),
            maxLines: 2,
            softWrap: true,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ],
    onChanged: onChanged,
  );

  Widget _participantRow(String name) {
    final included = _participants.contains(name);
    final needsInput = _method != SharedExpense.methodEqual;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Checkbox(
            value: included,
            activeColor: widget.accent,
            visualDensity: VisualDensity.compact,
            onChanged: (value) => setState(() {
              if (value == true) {
                _participants.add(name);
              } else {
                _participants.remove(name);
              }
            }),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _shownName(name),
                  textAlign: AppTr.alignEnd,
                  maxLines: 2,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title,
                  ),
                ),
                if ((widget.memberNote?.call(name) ?? '').isNotEmpty)
                  Text(
                    widget.memberNote!(name),
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.goldDark,
                    ),
                  ),
                if (included)
                  Text(
                    'نصيبه ${_fmt(_moneyFor(name))} $_currency',
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
          if (needsInput && included) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _shareControllers[name],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _method == SharedExpense.methodPercent
                      ? '%'
                      : _method == SharedExpense.methodExact
                      ? AppTr.tr('المبلغ')
                      : AppTr.tr('الحصص'),
                  suffixText: _method == SharedExpense.methodPercent
                      ? '%'
                      : null,
                  filled: true,
                  fillColor: AppTheme.field,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (status, ok) = _splitStatus();
    final expanded =
        _showParticipants || _method != SharedExpense.methodEqual;
    final categoryLabel = _subcategory.isEmpty
        ? _category
        : '$_category › $_subcategory';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionAddRow(
          title: 'مصروف جديد',
          icon: Icons.add_card_outlined,
          accent: widget.accent,
          actionIcon: Icons.close_rounded,
          onAdd: widget.onCancel,
        ),
        const SizedBox(height: 12),
        // اسم المصروف حقل مستقل، والفئة حقل مستقل تحته (كلاهما إلزامي).
        TextField(
          controller: _nameController,
          textDirection: AppTr.uiDir,
          decoration: const InputDecoration(
            isDense: true,
            label: Text('اسم المصروف *'),
            prefixIcon: Icon(Icons.title_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        // فئة المصروف حقل مستقل إلزامي: يفتح منتقي الفئات نفسه.
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          onTap: _pickCategory,
          child: InputDecorator(
            isEmpty: _category.isEmpty,
            decoration: InputDecoration(
              isDense: true,
              label: const Text('فئة المصروف *'),
              prefixIcon: Icon(
                _category.isEmpty
                    ? Icons.category_outlined
                    : categoryIconFor(
                        _subcategory.isEmpty ? _category : _subcategory,
                      ),
                size: 18,
                color: _category.isEmpty ? null : widget.accent,
              ),
              suffixIcon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: widget.accent,
              ),
            ),
            child: Text(
              categoryLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: widget.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'من دفع المصروف',
                icon: Icons.person_outline_rounded,
                value: _payer.isEmpty ? null : _payer,
                items: widget.payers,
                onChanged: (value) => setState(() => _payer = value ?? ''),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: AppTr.tr('المبلغ'),
                  suffixText: _currency,
                  prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // عملة المصروف: إن اختلفت عن عملة الالتزام يُكتب سعر الصرف، ويُحسب
        // المبلغ بما يعادله.
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'عملة المصروف',
                icon: Icons.currency_exchange_rounded,
                value: _currency,
                items: [
                  widget.currency,
                  for (final c in _sharedCurrencyOptions)
                    if (c != widget.currency) c,
                ],
                onChanged: (value) =>
                    _setCurrency(value ?? widget.currency),
              ),
            ),
            if (_foreign) ...[
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '1 ${AppTr.tr(_currency)} =',
                    suffixText: widget.currency,
                    prefixIcon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_foreign) ...[
          const SizedBox(height: 6),
          Text(
            _rate > 0 && _amount > 0
                ? '${AppTr.tr('يعادل')} ${_fmt(_amount * _rate)} ${widget.currency}'
                : AppTr.tr('اكتب سعر الصرف ليُحسب ما يعادله بعملة الالتزام'),
            textAlign: AppTr.alignEnd,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: _rate > 0 ? widget.accent : AppTheme.danger,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dropdown(
                label: 'التقسيم',
                icon: Icons.pie_chart_outline_rounded,
                value: _method,
                items: SharedExpense.methods,
                onChanged: (value) =>
                    _changeMethod(value ?? SharedExpense.methodEqual),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _dateController,
                readOnly: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: AppTr.tr('التاريخ'),
                  prefixIcon: const Icon(Icons.event_outlined, size: 18),
                ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked == null) return;
                  setState(() {
                    _dateController.text =
                        '${picked.day}/${picked.month}/${picked.year}';
                    _applyDate(picked);
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // المشاركون: مع «بالتساوي» الكل محدّد ويُفتح للاستثناء، ومع بقية
        // الطرق يُفتح وحده ويظهر لكل مشارك حقل نسبته أو مبلغه أو حصته.
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          onTap: _method == SharedExpense.methodEqual
              ? () => setState(() => _showParticipants = !_showParticipants)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 18,
                  color: AppTheme.title,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المشاركون (${_included.length} من ${widget.members.length})',
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                ),
                if (_method == SharedExpense.methodEqual)
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.title,
                  ),
              ],
            ),
          ),
        ),
        Text(
          status,
          textAlign: AppTr.alignEnd,
          maxLines: 2,
          softWrap: true,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ok ? AppTheme.muted : AppTheme.danger,
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 6),
          for (final name in widget.members) _participantRow(name),
        ],
        const SizedBox(height: 12),
        _receiptButton(
          label: 'إرفاق فاتورة / إيصال',
          path: _receipt,
          accent: widget.accent,
          onTap: () async {
            final path = await _pickReceiptFile(context);
            if (path == null || !mounted) return;
            setState(() => _receipt = path);
          },
          onRemove: () => setState(() => _receipt = ''),
        ),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: _save,
          child: const Text(
            'حفظ المصروف',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _SharedForm {
  final String label; // = entryType
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_SharedField> fields;

  const _SharedForm({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.fields,
  });
}

const _paymentMethodOptions = ['كاش', 'تحويل', 'شيك', 'أخرى'];
const _managedByOptions = ['جميع الأعضاء', 'المسؤول'];
const _splitMethodOptions = ['بالنسبة', 'بالمبلغ المحدد', 'بالتساوي'];

/// تصنيف المشاركة: مشاركة ممتدة أو لقاء ليوم واحد — بديل نوع «اللقاءات»
/// الذي دُمج هنا.
const _shareKindOptions = ['مشاركة أكثر من يوم', 'لقاء قصير (يوم واحد)'];

/// العملات المعروضة في نماذج الالتزامات المشتركة.
const _sharedCurrencyOptions = AppSettings.currencySuffixes;

/// مفتاح قائمة الأعضاء المشترك بين كل النماذج.
const _sharedMembersKey = 'الأعضاء / المشتركين';

/// مدير الرحلة — يُحفظ بمفتاحه الخاص كما كان.
const _tripManagerKey = 'مدير الرحلة';

/// الرقم التعريفي لجهاز من أنشأ الالتزام — يديره من جهازه.
const _creatorIdKey = 'معرف المنشئ';

/// طريقة تحصيل مبلغ الرحلة: هي التي تقرّر هل للرحلة مساهمات مسبقة أصلًا.
///
/// «دفعة مقطوعة» يعني أن لكل عضو مساهمة يدفعها من البداية فتُخصم منها
/// المصروفات، و«دفع فردي» يعني ألّا مساهمة إطلاقًا: كل من دفع شيئًا يُسجَّل
/// له، وتُصفّى الحسابات في نهاية الرحلة.
const _collectMethodKey = 'طريقة تحصيل المبلغ';
const _collectLumpSum = 'دفعة مقطوعة';
const _collectIndividual = 'دفع فردي';
const _collectMethodOptions = [_collectLumpSum, _collectIndividual];
const _collectMethodHints = <String, String>{
  _collectLumpSum: 'كل عضو يدفع نفس المبلغ من البداية ثم يُخصم من الرصيد',
  _collectIndividual:
      'كل فرد يدفع المصروف منفردًا ثم تُعمل تسوية في نهاية الرحلة',
};

/// مع «دفعة مقطوعة»: هل يحتاج مصروف العضو موافقة المسؤول؟ (نعم افتراضيًا)
const _expenseApprovalKey = 'يحتاج المصروف موافقة المسؤول';
const _approvalYes = 'نعم';
const _approvalNo = 'لا';

/// ترتيب المصروفات وحالاتها في فلتر المصروفات.
const _expenseSorts = [
  'الأحدث أولاً',
  'الأقدم أولاً',
  'الأعلى مبلغًا',
  'الأقل مبلغًا',
];
const _expenseStatuses = ['الكل', 'معتمدة', 'بانتظار الموافقة', 'مرفوضة'];

/// خيار «يحتاج المصروف موافقة المسؤول لاعتماده» — بنفس شكل خيار العهدة.
Widget _expenseApprovalTile({
  required bool on,
  required ValueChanged<bool> onChanged,
}) {
  const green = Color(0xFF0E7161);
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
                'يحتاج المصروف موافقة المسؤول لاعتماده',
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
                    ? 'كل مصروف يضيفه عضو يصل للمسؤول ليعتمده أو يرفضه، ولا يُخصم من الميزانية قبل اعتماده.'
                    : 'مصروفات الأعضاء تُخصم من الميزانية مباشرة بلا موافقة.',
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
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

/// الاسم بلا الرقم التعريفي: «زين (FND-XXXX-XXXX)» ← «زين». الرقم يظهر في
/// تبويب الأعضاء والملخص فقط.
String _shownName(String name) => name
    .replaceAll(RegExp(r'\s*\(FND-[A-Z2-9]{4}-[A-Z2-9]{4}\)'), '')
    .trim();

/// مفاتيح قديمة تُقرأ عند فتح سجل أُنشئ قبل إعادة تسمية الحقل.
const _sharedLegacyKeys = <String, String>{
  'تاريخ الرحلة': 'تاريخ السفر',
};

/// تكرار مساهمة الجمعية.
const _contributionCycleOptions = ['شهري', 'نصف شهري', 'أسبوعي', 'سنوي'];
const _notifyScopeOptions = ['الجميع', 'المسؤول فقط'];

final Map<String, _SharedForm> _sharedEntryForms = {
  'مشاركات مشتركة': _SharedForm(
    label: 'مشاركات مشتركة',
    subtitle: 'نشاط جماعي',
    icon: Icons.diversity_3_rounded,
    color: const Color(0xFF0E7161),
    // نفس منطق الرحلة: لا مبلغ مسبق يُقسَّم، بل طريقة تحصيل ومساهمات
    // ومصروفات تُسجَّل ثم تُصفّى.
    fields: [
      _SharedField(
        'اسم المشاركة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'التصنيف',
        Icons.category_outlined,
        kind: _SharedFieldKind.select,
        required: true,
        options: _shareKindOptions,
      ),
      _SharedField(
        'تاريخ البداية',
        Icons.event_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'تاريخ النهاية',
        Icons.event_available_outlined,
        kind: _SharedFieldKind.date,
        optional: true,
      ),
      _SharedField(
        'المكان',
        Icons.place_outlined,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        _collectMethodKey,
        Icons.account_balance_wallet_outlined,
        kind: _SharedFieldKind.collect,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'المسؤول / الأعضاء',
        Icons.groups_2_outlined,
        kind: _SharedFieldKind.team,
        required: true,
        managerKey: _sharedManagerKey,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
      _SharedField(
        'إرفاق مستند',
        Icons.attach_file_rounded,
        kind: _SharedFieldKind.attachment,
        optional: true,
      ),
    ],
  ),
  'الرحلة / السفر': _SharedForm(
    label: 'الرحلة / السفر',
    subtitle: 'رحلة بمصروفات مشتركة',
    icon: Icons.flight_takeoff_rounded,
    color: const Color(0xFF0A5A50),
    fields: [
      _SharedField(
        'اسم الرحلة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'تاريخ الرحلة',
        Icons.flight_takeoff_rounded,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'تاريخ العودة',
        Icons.flight_land_rounded,
        kind: _SharedFieldKind.date,
        optional: true,
      ),
      _SharedField(
        'الوجهة',
        Icons.place_outlined,
        required: true,
        isPrimary: true,
      ),
      // طريقة التحصيل تُقرّر ظهور المساهمات من عدمه، فتأتي قبل الأعضاء.
      _SharedField(
        _collectMethodKey,
        Icons.account_balance_wallet_outlined,
        kind: _SharedFieldKind.collect,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'مدير الرحلة / الأعضاء',
        Icons.groups_2_outlined,
        kind: _SharedFieldKind.team,
        required: true,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
      _SharedField(
        'إرفاق مستند',
        Icons.attach_file_rounded,
        kind: _SharedFieldKind.attachment,
        optional: true,
      ),
    ],
  ),
  'جمعية مالية': _SharedForm(
    label: 'جمعية مالية',
    subtitle: 'تحديد أدوار دوري بترتيب استلام',
    icon: Icons.savings_outlined,
    color: const Color(0xFF178F7B),
    fields: [
      _SharedField(
        'اسم الجمعية المالية',
        Icons.title_rounded,
        hint: 'مثال: مساعدة دراسية',
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      // تاريخ البداية والنهاية أولًا، ثم إجمالي المساهمة والعملة، ثم ما
      // يُحسب منهما مع تكرار المساهمة وموعد الدفع.
      _SharedField(
        'تاريخ البداية',
        Icons.event_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
        half: true,
      ),
      _SharedField(
        'تاريخ النهاية',
        Icons.event_busy_outlined,
        kind: _SharedFieldKind.date,
        optional: true,
        half: true,
      ),
      _SharedField(
        'إجمالي المساهمة',
        Icons.payments_outlined,
        kind: _SharedFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
        half: true,
      ),
      _SharedField(
        'العملة',
        Icons.currency_exchange_rounded,
        kind: _SharedFieldKind.select,
        options: _sharedCurrencyOptions,
        half: true,
      ),
      // تكرار المساهمة وموعد الدفع في السطر تحت إجمالي المساهمة مباشرة.
      _SharedField(
        'تكرار المساهمة',
        Icons.event_repeat_outlined,
        kind: _SharedFieldKind.select,
        required: true,
        options: _contributionCycleOptions,
        half: true,
      ),
      _SharedField(
        'موعد الدفع الشهري',
        Icons.calendar_today_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        half: true,
      ),
      // بدل «المساهمة على الشخص» و«عدد الدورات»: يُحسبان تلقائيًا.
      _SharedField(
        'المساهمة على الشخص',
        Icons.calculate_outlined,
        kind: _SharedFieldKind.roscaInfo,
      ),
      // المسؤول يُحفظ في مفتاحه كما كان، لكنه يُختار من «المسؤول / الأعضاء»
      // نفسه (أول من يُضاف)، فلا يظهر اسمه في حقل منفصل.
      _SharedField(
        _sharedManagerKey,
        Icons.admin_panel_settings_outlined,
        kind: _SharedFieldKind.person,
        required: true,
        isPrimary: true,
        hidden: true,
      ),
      _SharedField(
        'الأعضاء / المشتركين',
        Icons.groups_outlined,
        kind: _SharedFieldKind.people,
        required: true,
      ),
      _SharedField(
        'ترتيب الاستلام',
        Icons.format_list_numbered_rounded,
        kind: _SharedFieldKind.order,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
      _SharedField(
        'إرفاق مستند',
        Icons.attach_file_rounded,
        kind: _SharedFieldKind.attachment,
        optional: true,
      ),
    ],
  ),
};

const List<(String, IconData, Color)> _sharedCategoryChips = [
  ('الكل', Icons.apps_rounded, Color(0xFF022E2A)),
  ('مشاركات مشتركة', Icons.diversity_3_rounded, Color(0xFF0E7161)),
  ('الرحلة / السفر', Icons.flight_takeoff_rounded, Color(0xFF0A5A50)),
  ('جمعية مالية', Icons.savings_outlined, Color(0xFF178F7B)),
];

/// فئة مخفية من «تخصيص الصفحات»: لا تظهر ولا سجلاتها ولا تُضاف.
bool _sharedTypeHidden(String entryType) =>
    PageCustomizationStore.categoryHidden(
      PageCustomizationStore.shared,
      _sharedCanonicalType(entryType),
    );

/// «اللقاءات» نوع قديم دُمج في «مشاركات مشتركة»: سجلاته تبقى ظاهرة
/// وتُعامل معاملة المشاركات في الألوان والأيقونات والفلاتر.
String _sharedCanonicalType(String entryType) =>
    entryType == 'اللقاءات' ? 'مشاركات مشتركة' : entryType;

/// اسم النوع كما يُقرأ في صفحة التفاصيل: «رحلة سفر» أوضح من «الرحلة / السفر».
String _sharedTypeDisplay(String entryType) {
  final canonical = _sharedCanonicalType(entryType);
  return switch (canonical) {
    'الرحلة / السفر' => 'رحلة سفر',
    // «جمعية مالية» تُعرض «تحديد أدوار» في كل مكان.
    'جمعية مالية' => 'تحديد أدوار',
    _ => canonical,
  };
}

Color _sharedTypeColor(String entryType) {
  final form = _sharedEntryForms[_sharedCanonicalType(entryType)];
  return form?.color ?? const Color(0xFF022E2A);
}

IconData _sharedTypeIcon(String entryType) {
  final form = _sharedEntryForms[_sharedCanonicalType(entryType)];
  return form?.icon ?? Icons.diversity_3_rounded;
}

// ---------------------------------------------------------------------------
// نموذج العنصر المعروض في الواجهة — يغلّف SharedEntryRecord بحقول محسوبة
// (الأعضاء، المعاملات، الرصيد...)، بنفس فكرة _CommitmentItem في الشخصية.
class _SharedItem {
  final String id;
  String entryType;
  String title;
  int amount;
  String dueDate;
  String status;
  Map<String, String> details;
  String lastUpdate;
  final DateTime? createdAt;

  _SharedItem({
    required this.id,
    required this.entryType,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.details,
    required this.lastUpdate,
    this.createdAt,
  });

  /// الجمعية التي اكتملت دوراتها وسُلِّمت كلها «مكتملة» في القائمة أيضًا —
  /// كانت تُصحَّح فقط عند فتح تفاصيلها (ولو أكملها عضو آخر).
  static String _listStatus(SharedEntryRecord r) {
    if (r.status != _sharedStatusActive) return r.status;
    if (_sharedCanonicalType(r.entryType) != 'جمعية مالية') return r.status;
    try {
      final names = <String>[];
      for (final member in _parseSharedMembers(r.details)) {
        final name = member.name.trim();
        if (name.isNotEmpty && !names.contains(name)) names.add(name);
      }
      final plan = RoscaLedger.plan(r.details, names);
      final done = plan.cycles.isNotEmpty &&
          plan.cycles.every((c) => c.isComplete && c.isPaidOut);
      return done ? _sharedStatusCompleted : r.status;
    } catch (_) {
      return r.status;
    }
  }

  factory _SharedItem.fromRecord(SharedEntryRecord r) => _SharedItem(
    id: r.id ?? '',
    entryType: r.entryType,
    title: r.title,
    amount: r.amount,
    dueDate: r.dueDate,
    status: _listStatus(r),
    details: r.details,
    // التاريخ والساعة (بالتوقيت المحلي).
    lastUpdate: r.createdAt == null
        ? ''
        : () {
            final at = r.createdAt!.toLocal();
            String two(int v) => v.toString().padLeft(2, '0');
            return '${at.day}/${at.month}/${at.year} '
                '${two(at.hour)}:${two(at.minute)}';
          }(),
    createdAt: r.createdAt,
  );

  Color get color => _sharedTypeColor(entryType);
  IconData get icon => _sharedTypeIcon(entryType);

  List<_SharedMember> get members => _parseSharedMembers(details);
  int get membersCount => members.length;
  bool get managedByAll => details[_sharedManagedByKey] != 'المسؤول';
  String get splitMethod => details[_sharedSplitMethodKey] ?? 'بالتساوي';

  /// العملة التي اختارها المستخدم في النموذج. كانت تُجمع ثم تُتجاهل، وكل
  /// مبلغ في الشاشة يُلحق به "درهم" ثابتة — فتظهر ميزانية باليورو بالدرهم.
  String get currency {
    final value = (details['العملة'] ?? '').trim();
    return value.isEmpty ? AppSettings.currencySuffix : value;
  }

  List<_SharedTransaction> get transactions => _parseSharedTransactions(details);

  int get approvedSpent => _sharedApprovedSpent(
    details,
    managedByAll: managedByAll,
    membersCount: membersCount,
  );
  int get approvedExtraBudget => _sharedApprovedExtraBudget(
    details,
    managedByAll: managedByAll,
    membersCount: membersCount,
  );
  int get approvedPayments => _sharedApprovedPayments(
    details,
    managedByAll: managedByAll,
    membersCount: membersCount,
  );
  int get remainingBudget => amount + approvedExtraBudget - approvedSpent;

  // عمليات بانتظار موافقة المستخدم الحالي (يُعرض عددها في بند "طلباتي" وفي
  // شريط التنبيه العلوي في الشاشة الرئيسية).
  int get pendingApprovalsCount =>
      transactions
          .where(
            (t) => !t.isApproved(
              managedByAll: managedByAll,
              membersCount: membersCount,
            ),
          )
          .length +
      SharedLedger.pendingCount(details);
}

const _sharedStatusActive = 'نشطة';
const _sharedStatusCompleted = 'مكتملة';
const _sharedStatusArchived = 'مؤرشف';

/// مؤرشف عندي: بحالته القديمة للجميع، أو برقمي في «مؤرشف عند».
bool _archivedForMe(_SharedItem item) =>
    item.status == _sharedStatusArchived ||
    SharedMemberState.hasMine(item.details, SharedMemberState.archivedKey);

SharedEntryRecord _recordOf(_SharedItem item) => SharedEntryRecord(
  id: item.id,
  entryType: item.entryType,
  title: item.title,
  amount: item.amount,
  dueDate: item.dueDate,
  status: item.status,
  details: item.details,
);

/// دعوة لم أرد عليها بعد: «بانتظار قبولك». والمنشئ ينتظر رد عضو أو أكثر:
/// «بانتظار الموافقة» — لا تصير «نشطة» حتى يوافق كل الأعضاء.
String? _awaitingStatus(_SharedItem item) {
  final me = AppIdentity.id;
  if (me.isEmpty) return null;
  final creator = (item.details[_creatorIdKey] ?? '').trim();
  final answered = _SharedCommitmentsScreenState._acceptances(item);
  final ids = [
    for (final m in item.members)
      if (_SharedCommitmentsScreenState._idInMemberName(m.name) case final id?)
        id,
  ];
  if (creator.isNotEmpty && creator != me) {
    if (ids.contains(me) && _inviteStateOf(item, me) == 'pending') {
      return 'بانتظار قبولك';
    }
    return null;
  }
  // بانتظار من لم يرد وما زالت دعوته سارية (24 ساعة).
  if (creator == me &&
      ids.any((id) => id != me && _inviteStateOf(item, id) == 'pending')) {
    return 'بانتظار الموافقة';
  }
  return null;
}

/// حالة دعوة عضو: accepted / rejected / cancelled / expired / pending.
String _inviteStateOf(_SharedItem item, String id) =>
    SharedMemberState.inviteState(item.details, id, createdAt: item.createdAt);

/// كلمة حالة الدعوة ولونها.
(String, Color) _inviteStateLook(String state) => switch (state) {
  'accepted' => ('وافق', const Color(0xFF0E7161)),
  'rejected' => ('رفض الدعوة', const Color(0xFFC4392E)),
  'cancelled' => ('أُلغيت دعوته', const Color(0xFF8C9A97)),
  'expired' => ('تأخر بالرد', const Color(0xFFC4392E)),
  _ => ('بانتظار الموافقة', const Color(0xFFA6691A)),
};

Color _sharedStatusColor(String status) => switch (status) {
  'بانتظار قبولك' || 'بانتظار الموافقة' => const Color(0xFFA6691A),
  'ملغاة' || 'ملغية' => const Color(0xFFC4392E),
  'نشطة' => const Color(0xFF0A5A50),
  'مكتملة' => const Color(0xFF1E2725),
  'مؤرشف' => const Color(0xFF8C9A97),
  _ => const Color(0xFF5C6B68),
};

// ---------------------------------------------------------------------------
/// أقسام الفلتر الكبير للالتزامات المشتركة — بنفس شكل الالتزامات الشخصية.
const List<AppFilterSection> _sharedFilterSections = [
  AppFilterSection.mainCategory,
  AppFilterSection.period,
  AppFilterSection.statusSelect,
  AppFilterSection.amountSelect,
  AppFilterSection.currency,
  AppFilterSection.paymentMethod,
  AppFilterSection.documentSelect,
  AppFilterSection.people,
  AppFilterSection.delegates,
  AppFilterSection.place,
];

/// خيارات الحالة حسب النوع — نفس الفلتر الصغير («الأحدث أولاً»).
List<String> _sharedStatusOptionsFor(String type) => type == 'جمعية مالية'
    ? const [
        'الأحدث أولاً',
        'نشط',
        'متأخرة',
        'مكتمل',
        'قريبة الاستحقاق',
        'مستحقة',
      ]
    : const ['الأحدث أولاً', 'نشط', 'متأخرة', 'مكتمل'];

/// فلتر الالتزامات المشتركة — لفلتر الصفحة الرئيسية.
AppFilterModuleConfig sharedFilterModuleConfig() => AppFilterModuleConfig(
  mainCategories: [for (final chip in _sharedCategoryChips) chip.$1],
  sectionsFor: (_) => _sharedFilterSections,
  selectStatusesFor: _sharedStatusOptionsFor,
  currencies: [
    ...kAppFilterCurrencies,
    if (AppSettings.currencySuffix.isNotEmpty &&
        !kAppFilterCurrencies.contains(AppSettings.currencySuffix))
      AppSettings.currencySuffix,
  ],
  delegatesLabel: 'التفويض',
  placeLabel: 'مواقع وأماكن',
  placeHint: 'اكتب اسم الموقع أو المكان',
);

class SharedCommitmentsScreen extends StatefulWidget {
  final SharedEntriesRepository? repository;

  /// فلتر يُطبَّق عند الفتح (من فلتر الصفحة الرئيسية).
  final AppFilterValues? initialFilter;

  /// فتح تفاصيل التزام بعينه مباشرة (من المثبّت في الرئيسية) ثم الرجوع.
  final String? openEntryId;

  const SharedCommitmentsScreen({
    super.key,
    this.repository,
    this.initialFilter,
    this.openEntryId,
  });

  @override
  State<SharedCommitmentsScreen> createState() =>
      _SharedCommitmentsScreenState();
}

class _SharedCommitmentsScreenState extends State<SharedCommitmentsScreen> {
  /// فتح مباشر لالتزام: لا تُرسم القائمة خلف التفاصيل (إلا إن لم يُعثر عليه).
  late bool _directOpen = (widget.openEntryId ?? '').trim().isNotEmpty;
  late final SharedEntriesRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _loading = true;
  String? _loadError;
  List<_SharedItem> _items = [];

  /// ما حذفته من عندي ولا يزال عند بقية الأعضاء.
  List<_SharedItem> _removedItems = [];

  /// مكتملة أخرجها المستخدم من الأرشيف فتعود إلى قائمته.
  Set<String> _completedShown = {};

  /// المؤرشف عندي والمكتمل ينتقلان إلى «الأرشيف» من الشريط السفلي،
  /// ويختفيان من هنا إلا عند اختيار الحالة «مؤرشف» أو «مكتمل».
  bool _inArchive(_SharedItem i) =>
      _archivedForMe(i) ||
      (i.status == _sharedStatusCompleted && !_completedShown.contains(i.id));

  /// في «السجل التاريخي» عندي (حُذف ولم تتم تسويته).
  bool _inHistory(_SharedItem i) =>
      SharedMemberState.hasMine(i.details, SharedMemberState.historyKey);

  List<_SharedItem> get _historyItems =>
      _items.where(_inHistory).toList(growable: false);

  bool get _showingArchive =>
      _filter.status == 'مؤرشف' ||
      _filter.status == 'مكتمل' ||
      _activeSort == 'مكتمل';
  String _selectedType = 'الكل';
  String _selectedSort = 'الأحدث أولاً';
  bool _requestBannerDismissed = false;
  int _requestBannerDismissedAtCount = -1;

  /// المؤشر المحدَّد في مركز المتابعة. لم تكن بطاقات المركز هنا قابلة
  /// للاختيار إطلاقًا (بلا onTap ولا حالة)، بخلاف بقية مراكز المتابعة.
  int _selectedFollowUpMetric = 0;

  // فلتر متقدم مبسّط (زر التصفية بجانب البحث): حالة الالتزام، نطاق التاريخ،
  // ونطاق المبلغ — تُطبَّق فوق فلتر الفئات وشريط البحث في _filteredItems().
  /// قيم الفلتر الرئيسي — نفس البنية في الشاشات الأربع.
  final AppFilterValues _filter = AppFilterValues();

  bool get _hasActiveAdvancedFilters => _filter.isActive;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseSharedEntriesRepository();
    final initial = widget.initialFilter;
    if (initial != null) {
      _selectedType = initial.mainCategory;
      _filter.assignFrom(initial);
    }
    // إعادة البناء عند تغيّر التركيز حتى تختفي قائمة الاقتراحات فور خروج
    // المؤشر من خانة البحث (الكتابة وحدها لا تكفي لالتقاط فقدان التركيز).
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    final openId = widget.openEntryId?.trim() ?? '';
    if (openId.isEmpty) {
      _load();
    } else {
      _load().then((_) => _openInitialEntry(openId));
    }
  }

  /// المثبّت في الرئيسية: تفاصيله مباشرة، وبعد إغلاقها رجوع للرئيسية.
  /// إن لم يُعثر عليه تبقى القائمة ظاهرة.
  Future<void> _openInitialEntry(String rawId) async {
    if (!mounted) return;
    // من التنبيه: «معرّف#لاحقة» — اللاحقة تحدد التبويب: f المتابعة،
    // d المستندات، r/a الحركة المالية، c/b الأرصدة.
    final id = sharedAlertEntryId(rawId);
    final tag = rawId.contains('#') ? rawId.split('#')[1] : '';
    final (tab, ledger) = switch (tag.isEmpty ? '' : tag[0]) {
      'f' => (2, 0),
      'd' => (4, 0),
      'r' || 'a' => (1, 0),
      'c' || 'b' => (1, 1),
      _ => (0, 0),
    };
    _SharedItem? found;
    for (final item in _items) {
      if (item.id == id) found = item;
    }
    if (found == null) {
      if (mounted) setState(() => _directOpen = false);
      return;
    }
    // دعوة لم أرد عليها: الأزرار أولًا.
    if (!await _inviteGate(found)) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final item = _items.firstWhere((i) => i.id == id, orElse: () => found!);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedCommitmentDetailsScreen(
          item: item,
          repository: _repository,
          initialTab: tab,
          initialLedgerView: ledger,
          onChanged: (updated) {
            if (!mounted) return;
            setState(() {
              final idx = _items.indexWhere((i) => i.id == updated.id);
              if (idx != -1) _items[idx] = updated;
            });
          },
          onDeleted: (removedId) {
            if (!mounted) return;
            setState(() => _items.removeWhere((i) => i.id == removedId));
          },
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ---------------- دعوات الأعضاء بالرقم التعريفي ----------------
  static const _memberAcceptKey = 'قبول الأعضاء';

  /// الرقم التعريفي داخل اسم العضو: «أحمد (FND-XXXX-XXXX)».
  static String? _idInMemberName(String name) => RegExp(
    r'\((FND-[A-Z2-9]{4}-[A-Z2-9]{4})\)',
  ).firstMatch(name)?.group(1);

  static Map<String, Map<String, String>> _acceptances(_SharedItem item) {
    try {
      final decoded = jsonDecode(item.details[_memberAcceptKey] ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            '${entry.key}': (entry.value as Map).map(
              (k, v) => MapEntry('$k', '$v'),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  /// دعوات وصلتني (اسمي برقمي في أعضاء التزام) ولم أرد عليها بعد.
  List<_SharedItem> get _pendingMemberInvites {
    final me = AppIdentity.id;
    if (me.isEmpty) return const [];
    return _items
        .where(
          (item) =>
              _isOpenItem(item) &&
              (item.details[_creatorIdKey] ?? '') != me &&
              item.members.any((m) => _idInMemberName(m.name) == me) &&
              // بعد 24 ساعة بلا رد: انتهت الدعوة ولا تظهر في طلباتي.
              _inviteStateOf(item, me) == 'pending',
        )
        .toList(growable: false);
  }

  Future<bool> _respondMemberInvite(_SharedItem item, bool accept) async {
    final state = _inviteStateOf(item, AppIdentity.id);
    if (state == 'expired' || state == 'cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            state == 'expired'
                ? 'انتهت صلاحية الدعوة (24 ساعة) — اطلب من المنشئ إعادتها'
                : 'ألغى المنشئ هذه الدعوة',
          ),
        ),
      );
      return false;
    }
    final confirmed = await confirmAction(
      context,
      title: accept ? 'قبول الدعوة' : 'رفض الدعوة',
      message: accept
          ? '${AppTr.tr('هل تريد الانضمام إلى')} «${item.title}»؟ '
                '${AppTr.tr('سيتم إظهار اسمك للآخرين')}: '
                '${AppSettings.instance.publicName}'
          : 'هل تريد رفض الدعوة إلى «${item.title}»؟',
      confirmLabel: accept ? 'قبول' : 'رفض',
      danger: !accept,
    );
    if (!confirmed || !mounted) return false;
    final me = AppIdentity.id;
    final now = DateTime.now();
    final map = _acceptances(item)
      ..[me] = {
        'name': AppSettings.instance.publicName,
        'state': accept ? 'accepted' : 'rejected',
        'at': recordStampNow(),
      };
    final details = Map<String, String>.of(item.details)
      ..[_memberAcceptKey] = jsonEncode(map);
    try {
      final saved = await _repository.update(
        SharedEntryRecord(
          id: item.id,
          entryType: item.entryType,
          title: item.title,
          amount: item.amount,
          dueDate: item.dueDate,
          status: item.status,
          details: details,
        ),
        planExempt: true,
      );
      // طلبها في «الطلبات» لم يعد جديدًا.
      unawaited(FundlyAccount.markSeenForRecord(item.id));
      if (!mounted) return true;
      setState(() {
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index >= 0) _items[index] = _SharedItem.fromRecord(saved);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            accept
                ? 'تم قبول الدعوة إلى «${item.title}» بنجاح'
                : 'تم رفض الدعوة إلى «${item.title}»',
          ),
        ),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.')),
      );
      return false;
    }
  }

  /// دعوة لم أرد عليها: لا تُفتح قبل الرد. نافذة بالأزرار أولًا — عرض
  /// التفاصيل، أو قبول (ثم يُفتح)، أو رفض. يعيد true لفتح الالتزام.
  Future<bool> _inviteGate(_SharedItem item) async {
    if (!_pendingMemberInvites.any((i) => i.id == item.id)) return true;
    var from = '';
    for (final m in item.members) {
      if (m.role == 'مسؤول') {
        from = _shownName(m.name);
        break;
      }
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: AppTheme.page,
          icon: const Icon(
            Icons.mark_email_unread_outlined,
            size: 32,
            color: AppTheme.gold,
          ),
          title: const Text('بانتظار قبولك', textAlign: TextAlign.center),
          content: Text(
            from.isEmpty
                ? '${AppTr.tr(_sharedShownType(item.entryType))} «${item.title}»\n'
                      '${AppTr.tr('اقبل الدعوة أو ارفضها قبل فتحها')}'
                : '${AppTr.tr('دعاك')} $from ${AppTr.tr('للمشاركة في')} '
                      '${AppTr.tr(_sharedShownType(item.entryType))} '
                      '«${item.title}»\n'
                      '${AppTr.tr('اقبل الدعوة أو ارفضها قبل فتحها')}',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'details'),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('عرض التفاصيل'),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brand,
                        ),
                        onPressed: () => Navigator.pop(dialogContext, 'accept'),
                        child: const Text('قبول'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, 'reject'),
                        child: const Text('رفض'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case 'details':
        return true;
      case 'accept':
        return _respondMemberInvite(item, true);
      case 'reject':
        await _respondMemberInvite(item, false);
        return false;
      default:
        return false;
    }
  }

  /// صاحب الالتزام: إشعار بقبول/رفض دعوته، ومع القبول يُضاف العضو إلى
  /// «الأفراد والجهات» باسمه ورقمه فقط.
  Future<void> _notifyInviteResponses() async {
    final me = AppIdentity.id;
    if (me.isEmpty) return;
    const key = 'notified_member_responses_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(key) ?? const <String>[]).toSet();
      final messages = <String>[];
      for (final item in List.of(_items)) {
        if ((item.details[_creatorIdKey] ?? '') != me) continue;
        for (final entry in _acceptances(item).entries) {
          final state = entry.value['state'] ?? '';
          final name = (entry.value['name'] ?? '').trim();
          final stamp = '${item.id}|${entry.key}|$state';
          if (notified.contains(stamp)) continue;
          notified.add(stamp);
          final who = name.isEmpty ? entry.key : name;
          if (state == 'accepted') {
            messages.add('قبل $who دعوتك إلى «${item.title}» — أُضيف إلى الأفراد والجهات، ويمكنك من هناك إضافة أي بيانات أخرى عنه');
            if (name.isNotEmpty) {
              await PeopleDirectoryStore.upsert(
                fullName: name,
                typeKey: 'person_other',
                categoryName: 'أخرى',
                details: {'الرقم التعريفي': entry.key},
                sourceNote: 'قبل دعوة «${item.title}»',
              );
            }
          } else if (state == 'rejected') {
            messages.add('رفض $who دعوتك إلى «${item.title}»');
          }
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

  Widget _buildMemberInvitesBanner() {
    final invites = _pendingMemberInvites;
    if (invites.isEmpty) return const SizedBox.shrink();
    // يومض حتى يُلاحَظ.
    return _BlinkingBox(child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFE5DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'دعوات بانتظارك (${invites.length})',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0A5A50),
            ),
          ),
          for (final item in invites)
            Row(
              textDirection: AppTr.uiDir,
              children: [
                Icon(item.icon, size: 18, color: item.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.title} · ${_sharedShownType(item.entryType)}',
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _respondMemberInvite(item, false),
                  child: const Text(
                    'رفض',
                    style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E7161),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _respondMemberInvite(item, true),
                  child: const Text('قبول'),
                ),
              ],
            ),
        ],
      ),
    ));
  }

  Future<void> _load() async {
    // الضيف بلا حساب: لا طلب للخادم ولا رسالة خطأ — القائمة فارغة.
    if (FundlyAuth.isGuest) {
      setState(() {
        _items = <_SharedItem>[];
        _removedItems = <_SharedItem>[];
        _loading = false;
        _loadError = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await _repository.fetchAll();
      try {
        final prefs = await SharedPreferences.getInstance();
        _completedShown =
            (prefs.getStringList(ArchiveCenter.sharedCompletedShownKey) ??
                    const <String>[])
                .toSet();
      } catch (_) {}
      var removed = const <SharedEntryRecord>[];
      final repository = _repository;
      if (repository is SupabaseSharedEntriesRepository) {
        try {
          removed = await repository.fetchRemovedByMe();
          // حذفه كل الأعضاء: يُحذف من الخادم نهائيًا.
          for (final record in removed) {
            await SharedMemberState.purgeIfRemovedByAll(repository, record);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _items = rows.map(_SharedItem.fromRecord).toList();
        _removedItems = removed.map(_SharedItem.fromRecord).toList();
        _loading = false;
      });
      await _notifyInviteResponses();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل الالتزامات المشتركة. اسحب للتحديث للمحاولة مرة أخرى.';
        _loading = false;
      });
    }
  }

  bool _isOpenItem(_SharedItem i) =>
      i.status != _sharedStatusCompleted &&
      i.status != 'ملغاة' &&
      !_archivedForMe(i);

  int _pendingRequestsCount() => _items
      .where(_isOpenItem)
      .fold<int>(0, (sum, i) => sum + i.pendingApprovalsCount);

  /// تطبيق أقسام الفلتر الرئيسي على بند مشترك.
  bool _matchesMainFilter(_SharedItem item) {
    switch (_filter.status) {
      // «الحالة ▼» الجديدة — نفس معاني الفلتر الصغير.
      case 'متأخرة':
      case 'قريبة الاستحقاق':
      case 'مستحقة':
        if (!_matchesQuickFilter(item, _filter.status)) return false;
      case 'المستحق بعد 7 أيام':
        {
          final due = _parseDueDate(item.dueDate);
          if (due == null) return false;
          final days = due
              .difference(DateUtils.dateOnly(DateTime.now()))
              .inDays;
          if (days < 0 || days > 7) return false;
        }
      case 'نشط':
        if (!_isOpenItem(item)) return false;
      case 'مكتمل':
        if (!item.status.contains('مكتمل')) return false;
      case 'متأخر':
        {
          final due = _parseDueDate(item.dueDate);
          if (due == null ||
              !due.isBefore(DateUtils.dateOnly(DateTime.now())) ||
              item.status.contains('مكتمل')) {
            return false;
          }
        }
      case 'ملغاة':
        if (!item.status.contains('ملغا')) return false;
      case 'مؤرشف':
        if (!_archivedForMe(item)) return false;
    }
    if (!_filter.matchesAmount(item.amount)) return false;
    if (!_filter.matchesDate(_parseDueDate(item.dueDate))) return false;
    if (_filter.documentName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.documentName, [
          item.title,
          ...item.details.values,
        ])) {
      return false;
    }
    // المستند — الفلتر ▼: من تواريخ مستندات الالتزام.
    if (_filter.documentState != null) {
      final today = DateUtils.dateOnly(DateTime.now());
      final dates = [
        for (final doc in _parseSimpleEntries(item.details, _documentsDetailsKey))
          if (_parseDueDate(doc.date) case final date?) date,
      ];
      final soon = _filter.documentState!.contains('قريب');
      final matches = dates.any((date) {
        final days = date.difference(today).inDays;
        return soon ? days >= 0 && days <= 30 : days < 0;
      });
      if (!matches) return false;
    }
    // العملة.
    if (_filter.currency != null && item.currency != _filter.currency) {
      return false;
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
    if (_filter.personName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.personName, [
          item.title,
          ...item.members.map((member) => member.name),
        ])) {
      return false;
    }
    if (_filter.delegateName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.delegateName, [
          item.details['اسم المفوَّض'] ?? '',
          ...item.members.map((member) => member.name),
        ])) {
      return false;
    }
    if (_filter.placeName.isNotEmpty &&
        !AppFilterValues.textMatches(_filter.placeName, [
          item.details['المكان'] ?? '',
          item.details['الموقع'] ?? '',
          item.details['الوجهة'] ?? '',
        ])) {
      return false;
    }
    return true;
  }

  List<_SharedItem> _filteredItems() {
    final query = _searchController.text.trim();
    final archiveView = _showingArchive;
    var list = _items.where((i) {
      if (_sharedTypeHidden(i.entryType)) return false;
      if (!archiveView && _inArchive(i)) return false;
      if (_inHistory(i)) return false;
      // اللقاءات القديمة تُطابق «مشاركات مشتركة» بعد الدمج.
      final typeMatches =
          _selectedType == 'الكل' ||
          _sharedCanonicalType(i.entryType) == _selectedType;
      if (!typeMatches) return false;
      if (!_matchesMainFilter(i)) return false;
      if (query.isEmpty) return true;
      // مطابقة موحّدة عربيًا بنفس معيار اقتراحات البحث. كانت المقارنة نصية
      // خام، فكتابة "احمد" أو اختيار اقتراح "أحمد" لا يُرجع أي نتيجة رغم
      // ظهور الاقتراح. كما استُبعدت مفاتيح JSON الداخلية من نطاق البحث،
      // إذ كان البحث فيها يجعل كلمات مثل "kind" أو "date" تُطابق كل بند.
      const internalKeys = {
        _sharedMembersDetailKey,
        _sharedTransactionsDetailKey,
        _followUpDetailsKey,
        _documentsDetailsKey,
        _placesDetailsKey,
        SharedLedger.expensesKey,
        SharedLedger.settlementsKey,
        SharedLedger.contributionsKey,
        RoscaLedger.cyclesKey,
        SharedLedger.baseSharesKey,
        _creatorIdKey,
        SharedMemberState.archivedKey,
        SharedMemberState.removedKey,
      };
      return matchesSearchQuery(
        query: query,
        fields: [
          i.title,
          i.entryType,
          i.status,
          i.dueDate,
          for (final entry in i.details.entries)
            if (!internalKeys.contains(entry.key)) entry.value,
          ...i.members.map((m) => m.name),
        ],
      );
    }).toList();

    // الفلتر الصغير: كل خيار يُظهر ما يطابقه فقط، و«الأحدث أولاً» ترتيب.
    final sort = _activeSort;
    list = list.where((item) => _matchesQuickFilter(item, sort)).toList();

    list.sort((a, b) {
      // "أعلى/أقل مبلغ" من الفلتر الكبير يتقدّم على ترتيب الفلتر الصغير.
      final order = _filter.amountShortcut;
      if (order == 'أعلى مبلغ' || order == 'أعلى مبلغًا') {
        final byAmount = b.amount.compareTo(a.amount);
        if (byAmount != 0) return byAmount;
      } else if (order == 'أقل مبلغ' || order == 'أقل مبلغًا') {
        final byAmount = a.amount.compareTo(b.amount);
        if (byAmount != 0) return byAmount;
      }
      return (b.createdAt ?? DateTime(2000)).compareTo(
        a.createdAt ?? DateTime(2000),
      );
    });
    return list;
  }

  /// خيارات الفلتر الصغير حسب النوع المختار (حسب الورقة المعتمدة).
  List<String> get _sortOptions => _selectedType == 'جمعية مالية'
      ? const [
          'الأحدث أولاً',
          'نشط',
          'متأخرة',
          'مكتمل',
          'قريبة الاستحقاق',
          'مستحقة',
        ]
      : const ['الأحدث أولاً', 'نشط', 'متأخرة', 'مكتمل'];

  /// الخيار المفعّل — يعود إلى «الأحدث أولاً» إن لم يكن ضمن خيارات النوع.
  String get _activeSort =>
      _sortOptions.contains(_selectedSort) ? _selectedSort : 'الأحدث أولاً';

  bool _matchesQuickFilter(_SharedItem item, String label) {
    final cancelled = item.status.contains('ملغا');
    final open = _isOpenItem(item) && !cancelled;
    final due = _parseDueDate(item.dueDate);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = due == null ? null : due.difference(today).inDays;
    switch (label) {
      case 'نشط':
        return open;
      case 'متأخرة':
        return open && days != null && days < 0;
      case 'مكتمل':
        return item.status.contains('مكتمل');
      case 'ملغاة':
        return cancelled;
      case 'قريبة الاستحقاق':
        return open && days != null && days >= 0 && days <= 7;
      case 'مستحقة':
        return open && days == 0;
      default:
        return true;
    }
  }

  int _countForType(String type) => type == 'الكل'
      ? _items
            .where(
              (i) =>
                  !_sharedTypeHidden(i.entryType) &&
                  !_inArchive(i) &&
                  !_inHistory(i),
            )
            .length
      : _items
            .where(
              (i) => i.entryType == type && !_inArchive(i) && !_inHistory(i),
            )
            .length;

  Future<void> _openDetails(
    _SharedItem item, {
    int tab = 0,
    int ledger = 0,
  }) async {
    if (!await _inviteGate(item) || !mounted) return;
    final fresh = _items.firstWhere((i) => i.id == item.id, orElse: () => item);
    item = fresh;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedCommitmentDetailsScreen(
          item: item,
          repository: _repository,
          initialTab: tab,
          initialLedgerView: ledger,
          onChanged: (updated) {
            setState(() {
              final idx = _items.indexWhere((i) => i.id == updated.id);
              if (idx != -1) _items[idx] = updated;
            });
          },
          onDeleted: (id) {
            setState(() => _items.removeWhere((i) => i.id == id));
            // المحذوف عندي فقط يظهر في «المحذوفة عندي».
            _load();
          },
        ),
      ),
    );
  }

  int _pendingCountForBanner() => _pendingRequestsCount();

  @override
  Widget build(BuildContext context) {
    if (_directOpen) return const DirectOpenPlaceholder();
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _buildScreenBody(),
      ),
      floatingActionButton: AddFab(
        screenId: 'shared_commitments',
        onPressed: _openTypePickerSheet,
        label: 'إضافة',
        backgroundColor: const Color(0xFF0E7161),
      ),
    );
  }

  // نفس منهج الشخصية: أي خطأ غير متوقع أثناء البناء يظهر برسالة واضحة بدل
  // شاشة بيضاء صامتة.
  Widget _buildScreenBody() {
    try {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final filtered = _filteredItems();
      return RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            ManagementDashboardHeader(
              title: 'الالتزامات المشتركة',
              subtitle: 'إدارة ومتابعة التزاماتك مع الآخرين',
              icon: Icons.diversity_3_rounded,
              colors: const [Color(0xFF0A5A50), Color(0xFF0E7161)],
              // لمسة لون الوحدة.
              tint: const Color(0xFF2B8CB0),
              onSmartCalendarTap: _openSmartCalendar,
              onClose: () => Navigator.of(context).pop(),
            ),
            // مستطيل الوحدة الملوّن: الترويسة والبحث ومركز المتابعة
            // والملخص الشامل بلون الوحدة الخفيف.
            moduleTintedGroup(
              tint: const Color(0xFF2B8CB0),
              slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                child: _buildSearchControl(),
              ),
            ),
            if (_loadError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _buildErrorBanner(),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _buildRequestsBanner(),
              ),
            ),
            // دعوات بالرقم التعريفي تنتظر قبولي.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _buildMemberInvitesBanner(),
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
    const ModuleSummaryCard(tab: 2, subtitle: 'ملخص الالتزامات المشتركة'),
  ],
),
                ),
              ),
            ),
            // عنوان "الفئات" يمرّ مع الصفحة، وشريط الشرائح وحده يثبت.
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
                    // سطر عنوان القائمة مثبَّت مع الفئات، كالالتزامات
                    // الشخصية تمامًا.
                    _buildListHeader(filtered.length),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (filtered.isEmpty)
                    _buildEmptyState()
                  else
                    ...filtered.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SharedCommitmentCard(
                          item: item,
                          onTap: () => _openDetails(item),
                        ),
                      ),
                    ),
                  if (_historyItems.isNotEmpty) _buildHistoryLink(),
                  if (_removedItems.isNotEmpty) _buildRemovedLink(),
                ]),
              ),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('shared_commitments_screen build error: $error\n$stackTrace');
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
            const SizedBox(height: 10),
            const Text(
              'حدث خطأ غير متوقع أثناء عرض الشاشة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => setState(() {}),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF4F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF4C2BC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFA82F26), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadError ?? '',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA82F26), fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  /// زر «سجل تاريخي»: ما حُذف ولم تتم تسويته.
  Widget _buildHistoryLink() {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: AppTheme.goldDark),
        onPressed: _openHistorySheet,
        icon: const Icon(Icons.history_edu_outlined, size: 18),
        label: Text(
          '${AppTr.tr('سجل تاريخي')} (${_historyItems.length})',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  /// داخل «السجل التاريخي»: كل عنصر يُفتح لمتابعته وتسويته، أو يُعاد
  /// إلى القائمة.
  Future<void> _openHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  const Text(
                    'سجل تاريخي',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'حذفتها ولم تتم تسويتها، فلا تُمسح: تبقى هنا حفظًا لحقوق '
                    'الأعضاء، وتتابعها وتسوّيها لاحقًا.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_historyItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'لا توجد عناصر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  for (final entry in _historyItems)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            textDirection: AppTr.uiDir,
                            children: [
                              Icon(entry.icon, size: 20, color: entry.color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${entry.title} · ${_sharedShownType(entry.entryType)}',
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.title,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'لم تتم التسوية',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.danger,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: entry.color,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    _openDetails(entry);
                                  },
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('فتح ومتابعة'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () async {
                                    await _setHistory(entry, false);
                                    if (sheetContext.mounted) {
                                      setSheetState(() {});
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.restore_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('إعادة للقائمة'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setHistory(_SharedItem target, bool add) async {
    try {
      final saved = await SharedMemberState.markMine(
        _repository,
        _recordOf(target),
        SharedMemberState.historyKey,
        add: add,
      );
      if (!mounted || saved == null) return;
      setState(() {
        final index = _items.indexWhere((i) => i.id == target.id);
        if (index >= 0) _items[index] = _SharedItem.fromRecord(saved);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ. حاول مرة أخرى.')),
      );
    }
  }

  /// ما حذفته من عندي ولا يزال عند بقية الأعضاء — يُستعاد من هنا.
  Widget _buildRemovedLink() {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: _openRemovedSheet,
        icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
        label: Text(
          '${AppTr.tr('المحذوفة عندي')} (${_removedItems.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<bool> _restoreRemoved(_SharedItem item) async {
    final ok = await confirmAction(
      context,
      title: 'استعادة',
      message: 'سيعود «${item.title}» إلى قائمتك. هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
    );
    if (!ok || !mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await SharedMemberState.markMine(
        _repository,
        _recordOf(item),
        SharedMemberState.removedKey,
        add: false,
      );
      if (!mounted) return false;
      setState(() {
        _removedItems.removeWhere((i) => i.id == item.id);
        if (saved != null) _items.insert(0, _SharedItem.fromRecord(saved));
      });
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            saved == null
                ? 'لم يعد «${item.title}» موجودًا'
                : 'تمت استعادة «${item.title}» بنجاح',
          ),
        ),
      );
      return true;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.'),
        ),
      );
      return false;
    }
  }

  Future<void> _openRemovedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  const Text(
                    'المحذوفة عندي',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'حذفتها من عندك وما زالت عند بقية الأعضاء. الاستعادة تعيدها إلى قائمتك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_removedItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'لا توجد عناصر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  for (final item in List.of(_removedItems))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.hairline),
                      ),
                      child: Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          Icon(item.icon, size: 20, color: item.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item.title} · ${_sharedShownType(item.entryType)}',
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.title,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0E7161),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final done = await _restoreRemoved(item);
                              if (done && sheetContext.mounted) {
                                setSheetState(() {});
                              }
                            },
                            icon: const Icon(Icons.restore_rounded, size: 17),
                            label: const Text('استعادة'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// الالتزامات المشتركة المؤرشفة — مصدر زر «الأرشيف».
  List<_SharedItem> get _archivedItems =>
      _items.where(_archivedForMe).toList(growable: false);

  /// نافذة الأرشيف: إلغاء الأرشفة يعيد الالتزام إلى القائمة النشطة.
  Future<void> _openArchiveSheet() async {
    final changed = await showArchiveSheet(
      context,
      title: 'الالتزامات المشتركة',
      entries: [
        for (final item in _archivedItems)
          ArchiveEntry(
            title: item.title,
            subtitle: item.entryType,
            icon: item.icon,
            color: item.color,
            onUnarchive: () async {
              try {
                // مؤرشف عندي وحدي: يُزال رقمي فقط.
                if (SharedMemberState.hasMine(
                  item.details,
                  SharedMemberState.archivedKey,
                )) {
                  await SharedMemberState.markMine(
                    _repository,
                    _recordOf(item),
                    SharedMemberState.archivedKey,
                    add: false,
                  );
                  return true;
                }
                await _repository.update(
                  SharedEntryRecord(
                    id: item.id,
                    entryType: item.entryType,
                    title: item.title,
                    amount: item.amount,
                    dueDate: item.dueDate,
                    status: _sharedStatusActive,
                    details: item.details,
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
    await _load();
  }

  Widget _buildSearchControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
        Expanded(
          child: TextField(
            key: const ValueKey('shared-search-field'),
            controller: _searchController,
            focusNode: _searchFocusNode,
            textDirection: AppTr.uiDir,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              // حقل ممتلئ بلا حدود بنفس نصف قطر ولون حقول التطبيق.
              hintText: AppTr.tr('بحث في الالتزامات المشتركة'),
              hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13, fontWeight: FontWeight.w600),
              prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppTheme.chevron),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AppTr.tr('مسح البحث'),
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.muted),
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
          key: const ValueKey('shared-filter-button'),
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

  /// اقتراحات إكمال تظهر بمجرد كتابة حرفين، مبنيّة على عناوين الالتزامات
  /// المشتركة المسجّلة فعلًا (لم تكن هذه الشاشة تعرض أي اقتراحات سابقًا).
  Widget _buildSearchSuggestions() {
    if (!_searchFocusNode.hasFocus) return const SizedBox.shrink();
    final values = searchSuggestionsFor(
      query: _searchController.text,
      candidates: _items.map((item) => item.title),
    );
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
              if (i > 0)
                const Divider(height: 1, color: Color(0xFFF2F6F5)),
              InkWell(
                key: ValueKey('shared-search-suggestion-${values[i]}'),
                onTap: () {
                  final value = values[i];
                  _searchController.text = value;
                  _searchController.selection = TextSelection.collapsed(
                    offset: value.length,
                  );
                  _searchFocusNode.unfocus();
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Color(0xFF8C9A97),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          values[i],
                          textAlign: TextAlign.right,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 12,
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
          ],
        ),
      ),
    );
  }

  // الفلتر الرئيسي: نفس قالب الشاشات الأربع، والأقسام وترتيبها مطابقة
  // لملف "فلاتر فوندلي" لصفحة الالتزامات المشتركة.
  void _openAdvancedFilterSheet() {
    showAppFilterSheet(
      context: context,
      title: 'الالتزامات المشتركة',
      accent: const Color(0xFF0A5A50),
      values: _filter..mainCategory = _selectedType,
      mainCategories: _sharedCategoryChips
          .map((chip) => chip.$1)
          .toList(growable: false),
      sections: _sharedFilterSections,
      selectStatusesFor: _sharedStatusOptionsFor,
      currencies: [
        ...kAppFilterCurrencies,
        for (final currency in {for (final item in _items) item.currency})
          if (!kAppFilterCurrencies.contains(currency)) currency,
      ],
      delegatesLabel: 'التفويض',
      placeLabel: 'مواقع وأماكن',
      placeHint: 'اكتب اسم الموقع أو المكان',
      onApply: (values) => setState(() {
        _selectedType = values.mainCategory;
        _filter.assignFrom(values);
      }),
    );
  }

  // شريط "طلب بانتظار إجراء" — يظهر عند وجود عمليات مالية (مصروف/دفعة/ميزانية
  // إضافية) بانتظار موافقة الأعضاء أو المسؤول، بنفس نمط بند "طلباتي" في
  // الشخصية. يمكن إخفاؤه بـ(✕) ويظهر تلقائيًا من جديد إن زاد العدد.
  Widget _buildRequestsBanner() {
    final count = _pendingCountForBanner();
    if (count == 0) return const SizedBox.shrink();
    if (_requestBannerDismissed && _requestBannerDismissedAtCount >= count) {
      return const SizedBox.shrink();
    }
    // الشريط يطلب من المستخدم مراجعة "طلباتي" لكنه لم يكن قابلًا للضغط
    // إطلاقًا — الضغط عليه لا يفعل شيئًا. أصبح يفتح مركز المتابعة مباشرة،
    // مثل نظيره في شاشة الالتزامات الشخصية.
    return Material(
      color: const Color(0xFFFEF7EE),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openFollowUpSheet,
        borderRadius: BorderRadius.circular(12),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBDEB6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFA6691A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? 'طلب واحد بانتظار إجراء — راجع "طلباتي" في مركز المتابعة'
                  : '$count طلبات بانتظار إجراء — راجع "طلباتي" في مركز المتابعة',
              maxLines: 4,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFA6691A)),
            ),
          ),
          InkWell(
            onTap: () => setState(() {
              _requestBannerDismissed = true;
              _requestBannerDismissedAtCount = count;
            }),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 17, color: Color(0xFFA6691A)),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildCategoriesBlock() {
    final visibleChips = [
      for (final chip in _sharedCategoryChips)
        if (chip.$1 == 'الكل' || !_sharedTypeHidden(chip.$1)) chip,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // بلا عنوان "الفئات" — كبقية الشاشات.
        SizedBox(
          // نفس ارتفاع شريط الفئات في بقية الشاشات.
          height: 46,
          child: ListView.separated(
            key: const ValueKey('shared-category-tabs'),
            scrollDirection: Axis.horizontal,
            itemCount: visibleChips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final chip = visibleChips[index];
              final selected = _selectedType == chip.$1;
              return _SharedCategoryTab(
                label: chip.$1,
                count: _countForType(chip.$1),
                icon: chip.$2,
                color: chip.$3,
                selected: selected,
                onTap: () => setState(() => _selectedType = chip.$1),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader(int count) {
    return Row(
      textDirection: AppTr.uiDir,
      children: [
        // مثل الشخصية: الجملة أولًا ثم العدد بعدها (يسارها)، وزر الترتيب
        // في أقصى الطرف دائمًا.
        Expanded(
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
        Flexible(
          child: Text(
            _selectedType == 'الكل' ? 'جميع الالتزامات' : _selectedType,
            maxLines: 3,
            style: AppTheme.cardTitle,
          ),
        ),
        const SizedBox(width: AppTheme.sMd),
        Container(
          constraints: const BoxConstraints(minWidth: 36),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0E7161).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.rIcon),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E7161)),
          ),
        ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          key: const ValueKey('shared-sort-button'),
          tooltip: AppTr.tr('ترتيب الالتزامات'),
          offset: const Offset(0, 8),
          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
          onSelected: (value) => setState(() => _selectedSort = value),
          // عناصر القائمة تُبنى في مسار عرض مستقل خارج غلاف اتجاه الشاشة،
          // فتظهر بمحاذاة يسارية. كما لم يكن هناك أي مؤشر على الخيار
          // المفعّل حاليًا.
          itemBuilder: (context) =>
              // الفلتر الصغير — كما في ملف "فلاتر فوندلي".
              _sortOptions.map((o) {
                final selected = o == _activeSort;
                return PopupMenuItem(
                  value: o,
                  child: Directionality(
                    textDirection: AppTr.uiDir,
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 17,
                          color: selected
                              ? const Color(0xFF0E7161)
                              : const Color(0xFFD5DEDB),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          o,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: selected
                                ? const Color(0xFF0E7161)
                                : const Color(0xFF2C3B38),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _activeSort,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF0E7161)),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF0E7161)),
            ],
          ),
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
              color: const Color(0xFF0E7161).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diversity_3_rounded, size: 32, color: Color(0xFF0E7161)),
          ),
          const SizedBox(height: 10),
          const Text(
            'لا توجد التزامات مشتركة مطابقة',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF022E2A)),
          ),
          const SizedBox(height: 4),
          const Text(
            'ابدأ بإضافة مشاركة، رحلة، تحديد أدوار، أو لقاء',
            style: TextStyle(fontSize: 11, color: Color(0xFF5C6B68), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------
  // مركز المتابعة: نفس فكرة الشخصية (مجموعات + عناصر فرعية قابلة للفتح في
  // صفحة منبثقة صغيرة)، لكن بمجموعات تلائم طبيعة الالتزامات المشتركة.
  List<_SharedFollowUpGroupData> _buildFollowUpGroups() {
    // ثابت في كل الفئات: يعرض دائمًا كل الالتزامات المشتركة، بنفس مجموعات
    // مركز المتابعة في الالتزامات الشخصية.
    final open = _items.where(_isOpenItem).toList();
    final today = DateUtils.dateOnly(DateTime.now());

    int? daysTo(String value) {
      final date = _parseDueDate(value);
      return date?.difference(today).inDays;
    }

    // tab: التبويب الذي يُفتح عند الضغط (0 الملخص، 1 الحركة المالية،
    // 2 المتابعة والتخطيط، 3 الأعضاء، 4 مستندات)، وledger 1 = الأرصدة.
    List<_SharedCommitmentItemRef> refs(
      bool Function(_SharedItem) test, {
      int tab = 0,
      int ledger = 0,
    }) => [
      for (final i in open.where(test))
        _SharedCommitmentItemRef(i, null, tab, ledger),
    ];

    // ---- الطلبات: ما ينتظر قبولي (دعوات بالرقم التعريفي، ومصروفات
    // وميزانيات إضافية بانتظار الموافقة)، وما أرسلته وينتظر قبول غيري.
    final myId = AppIdentity.id;
    final invites = _pendingMemberInvites.toSet();
    final incoming = [
      for (final i in open)
        if (invites.contains(i) || i.pendingApprovalsCount > 0)
          // طلبات الموافقة في الحركة المالية، والدعوة في الملخص.
          _SharedCommitmentItemRef(
            i,
            null,
            i.pendingApprovalsCount > 0 ? 1 : 0,
          ),
    ];
    final outgoing = refs(tab: 3, (i) {
      if (myId.isEmpty || (i.details[_creatorIdKey] ?? '') != myId) {
        return false;
      }
      final answered = _acceptances(i);
      return i.members.any((m) {
        final id = _idInMemberName(m.name);
        return id != null && id != myId && !answered.containsKey(id);
      });
    });

    // ---- المتابعة والتخطيط: بنود «متابعة وتخطيط» داخل كل التزام، ومعها
    // موعد الالتزام نفسه إن لم يكن ماليًا. يُعتمد أقرب موعد قادم، وإلا آخر
    // موعد فات.
    // الرحلة والمشاركة: تاريخها تاريخ النشاط لا موعد دفع، والمساهمات ليست
    // مستحقات — فلا تدخل «متأخرة / مستحقة / قريبة الاستحقاق». الجمعية
    // وحدها لها موعد دفع (موعد دورتها).
    bool isFinancial(_SharedItem i) =>
        _sharedCanonicalType(i.entryType) == 'جمعية مالية';

    int? planDay(_SharedItem i) {
      final days = <int>[];
      for (final entry in _parseSimpleEntries(i.details, _followUpDetailsKey)) {
        final d = daysTo(entry.date);
        if (d == null) continue;
        if ((entry.extra['الحالة'] ?? '') == 'مكتملة') continue;
        // الملاحظات والعادة وما يتكرر لا تُعدّ «متأخرة» — كالشخصية.
        final repeat = (entry.extra['التكرار'] ?? '').trim();
        final noDeadline = entry.kind == 'ملاحظات' ||
            entry.kind == 'عادة' ||
            (repeat.isNotEmpty &&
                !repeat.contains('بدون') &&
                !repeat.contains('لا يتكرر'));
        if (noDeadline && d < 0) continue;
        days.add(d);
      }
      // بنود «المتابعة والتخطيط» وحدها — تاريخ الرحلة أو المشاركة نفسه ليس
      // متابعة.
      if (days.isEmpty) return null;
      final upcoming = days.where((d) => d >= 0).toList()..sort();
      if (upcoming.isNotEmpty) return upcoming.first;
      days.sort();
      return days.last;
    }

    // ---- مالية: موعد الاستحقاق (في الجمعية: موعد الدورة الجارية)، وما لي
    // وما عليّ حسب رصيدي بين الأعضاء.
    final myName = AppSettings.instance.name.trim();
    String? meIn(_SharedItem i) {
      for (final member in i.members) {
        final name = member.name.trim();
        if (name.isEmpty) continue;
        if (myId.isNotEmpty && _idInMemberName(name) == myId) return name;
        if (myName.isNotEmpty && AppSettings.instance.isMyName(name)) {
          return name;
        }
      }
      return null;
    }

    List<String> namesOf(_SharedItem i) => [
      for (final m in i.members)
        if (m.name.trim().isNotEmpty) m.name.trim(),
    ];

    bool isRosca(_SharedItem i) =>
        _sharedCanonicalType(i.entryType) == 'جمعية مالية';

    int? financeDay(_SharedItem i) {
      if (!isFinancial(i)) return null;
      if (isRosca(i)) {
        final due = RoscaLedger.plan(i.details, namesOf(i)).current?.dueDate;
        if (due != null) return DateUtils.dateOnly(due).difference(today).inDays;
      }
      return daysTo(i.dueDate);
    }

    /// رصيدي في الالتزام: موجب لي، سالب عليّ.
    double myBalance(_SharedItem i) {
      final me = meIn(i);
      if (me == null) return 0;
      if (isRosca(i)) {
        final plan = RoscaLedger.plan(i.details, namesOf(i));
        final current = plan.current;
        if (plan.overdueOf(me) > 0) return -1;
        if (current != null && current.receiver == me && !current.isPaidOut) {
          return 1;
        }
        return 0;
      }
      // رصيدي تجاه الأعضاء فقط: المتبقي في الوعاء ليس لي ولا عليّ.
      return SharedLedger.memberNet(i.details, me);
    }

    /// تحديد الأدوار: ما عليّ (مساهمات حلّ موعدها ولم أدفعها) أو ما لي
    /// (مبلغ الدورة التي حان دوري فيها).
    String? roscaMoney(_SharedItem i) {
      final me = meIn(i);
      if (me == null) return null;
      final plan = RoscaLedger.plan(i.details, namesOf(i));
      var value = 0.0;
      if (myBalance(i) < 0) {
        for (final cycle in plan.cycles) {
          final due = cycle.dueDate;
          if (due == null || DateUtils.dateOnly(due).isAfter(today)) continue;
          final left = cycle.shareOf(me) - cycle.paidBy(me);
          if (left > 0.01) value += left;
        }
      } else {
        value = plan.cycleTotal;
      }
      if (value <= 0.01) return null;
      final v = (value * 100).round() / 100;
      return '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)} ${i.currency}';
    }

    /// «مبالغ لي / عليّ»: يظهر مبلغي أنا، لا إجمالي مساهمات الأعضاء.
    List<_SharedCommitmentItemRef> moneyRefs(bool Function(double) test) => [
      for (final i in open)
        if (test(myBalance(i)))
          _SharedCommitmentItemRef(
            i,
            isRosca(i)
                ? roscaMoney(i)
                : () {
                    final v = (myBalance(i).abs() * 100).round() / 100;
                    return '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)} '
                        '${i.currency}';
                  }(),
            1,
            isRosca(i) ? 0 : 1,
          ),
    ];

    // ---- مستندات
    bool docsWhere(_SharedItem i, bool Function(int days) test) =>
        _parseSimpleEntries(i.details, _documentsDetailsKey).any((doc) {
          final days = daysTo(doc.date);
          return days != null && test(days);
        });

    // نفس ترتيب ومسميات مركز المتابعة في الالتزامات الشخصية.
    return [
      _SharedFollowUpGroupData(
        title: 'الطلبات',
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFA6691A),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'بانتظار قبولي',
            icon: Icons.move_to_inbox_outlined,
            items: incoming,
          ),
          _SharedFollowUpSubMetric(
            label: 'أرسلتها بانتظار القبول',
            icon: Icons.outbox_outlined,
            items: outgoing,
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'المتابعة والتخطيط',
        icon: Icons.checklist_rounded,
        color: const Color(0xFF0E7161),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'متأخرة',
            icon: Icons.error_outline_rounded,
            items: refs(tab: 2, (i) => (planDay(i) ?? 0) < 0),
          ),
          _SharedFollowUpSubMetric(
            label: 'حان وقتها',
            icon: Icons.today_outlined,
            items: refs(tab: 2, (i) => planDay(i) == 0),
          ),
          _SharedFollowUpSubMetric(
            label: 'قريبة',
            icon: Icons.hourglass_bottom_rounded,
            items: refs(tab: 2, (i) {
              final d = planDay(i);
              return d != null && d > 0 && d <= 7;
            }),
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'مالية (عام)',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF34A894),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'متأخرة',
            icon: Icons.error_outline_rounded,
            items: refs(tab: 1, (i) => (financeDay(i) ?? 0) < 0),
          ),
          _SharedFollowUpSubMetric(
            label: 'مستحقة',
            icon: Icons.payments_outlined,
            items: refs(tab: 1, (i) => financeDay(i) == 0),
          ),
          _SharedFollowUpSubMetric(
            label: 'قريبة الاستحقاق',
            icon: Icons.hourglass_bottom_rounded,
            items: refs(tab: 1, (i) {
              final d = financeDay(i);
              return d != null && d > 0 && d <= 7;
            }),
          ),
          _SharedFollowUpSubMetric(
            label: 'مبالغ لي',
            icon: Icons.south_west_rounded,
            items: moneyRefs((b) => b > 0.01),
          ),
          _SharedFollowUpSubMetric(
            label: 'مبالغ عليّ',
            icon: Icons.north_east_rounded,
            items: moneyRefs((b) => b < -0.01),
          ),
        ],
      ),
      // الميزانية المقطوعة كالعهدة: المستنفدة ما صُرفت كلها أو تجاوزها
      // الصرف، والقريبة ما بقي منها 20% فأقل.
      _SharedFollowUpGroupData(
        title: 'الميزانية',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0A5A50),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'مستنفدة',
            icon: Icons.money_off_csred_outlined,
            items: refs(tab: 1, ledger: 1, (i) => sharedPotDrained(i.details)),
          ),
          _SharedFollowUpSubMetric(
            label: 'قريبة الاستنفاد',
            icon: Icons.trending_down_rounded,
            items: refs(
              tab: 1,
              ledger: 1,
              (i) => sharedPotNearlyDrained(i.details),
            ),
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'مستندات (عام)',
        icon: Icons.description_outlined,
        color: const Color(0xFFCE8422),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'منتهية',
            icon: Icons.assignment_late_outlined,
            items: refs(tab: 4, (i) => docsWhere(i, (d) => d < 0)),
          ),
          _SharedFollowUpSubMetric(
            label: 'قريبة الانتهاء',
            icon: Icons.event_busy_outlined,
            items: refs(tab: 4, (i) => docsWhere(i, (d) => d >= 0 && d <= 30)),
          ),
        ],
      ),
    ];
  }

  DateTime? _parseDueDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  void _openSmartCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(
        builder: (_) => const SmartCalendarScreen(
          modules: SmartCalendarScreen.sharedModules,
          scopeLabel: 'الالتزامات المشتركة',
        ),
      ));
  }

  Widget _buildFollowUpCenter() {
    final groups = _buildFollowUpGroups();
    const accent = Color(0xFF0A5A50);
    // ثابت في كل الفئات: نفس المؤشرات دائمًا.
    final metrics = [
      (
        'الطلبات',
        groups[0].total,
        Icons.hourglass_top_rounded,
        const Color(0xFFA6691A),
      ),
      (
        'المتابعة والتخطيط',
        groups[1].total,
        Icons.fact_check_outlined,
        const Color(0xFF0A5A50),
      ),
      (
        'مستحقات مالية',
        groups[2].total,
        Icons.account_balance_wallet_outlined,
        const Color(0xFF178F7B),
      ),
    ];

    // نفس بطاقة مركز المتابعة الموحّدة في بقية الشاشات: رمادية ناعمة،
    // نصف قطر كبير، بلا حدود ولا ظل.
    return AppCard(
      key: const ValueKey('shared-follow-up-center'),
      leading: const AppIconTile(
        icon: Icons.dashboard_customize_outlined,
        color: accent,
      ),
      title: 'مركز المتابعة',
      subtitle: 'الأهم في الالتزامات المشتركة',
      onTap: _openFollowUpSheet,
      // بلا شارة «يحتاج متابعة»: الأرقام في الشريط تكفي.
      trailing: const AppMoreAction(key: ValueKey('shared-follow-up-more')),
      child: SizedBox(
        height: AppMetricChip.stripHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spacing = AppTheme.sSm * (metrics.length - 1);
            final chipWidth =
                ((constraints.maxWidth - spacing) / metrics.length)
                    .clamp(74.0, 132.0);
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
                    onTap: () =>
                        setState(() => _selectedFollowUpMetric = index),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _openFollowUpSheet() {
    // القالب مشترك مع بقية الوحدات؛ هذه الشاشة تمرّر بياناتها ومسمياتها.
    showFollowUpCenterSheet(
      context: context,
      accent: const Color(0xFF0A5A50),
      title: 'مركز المتابعة',
      subtitle: 'الالتزامات المشتركة',
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
                    for (final ref in metric.items)
                      FollowUpEntry(
                        title: ref.item.title,
                        subtitle: ref.item.dueDate.isEmpty
                            ? _sharedTypeDisplay(ref.item.entryType)
                            : '${_sharedTypeDisplay(ref.item.entryType)} · '
                                  '${ref.item.dueDate}',
                        icon: ref.item.icon,
                        color: ref.item.color,
                        trailingText: ref.amountText ??
                            (ref.item.amount > 0
                                ? '${ref.item.amount} ${ref.item.currency}'
                                : null),
                        onTap: () => _openDetails(
                          ref.item,
                          tab: ref.tab,
                          ledger: ref.ledger,
                        ),
                      ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  // --------------------------------------------------------------------
  // تدفّق "+ إضافة التزام": اختيار الفئة ثم فتح النموذج الديناميكي المطابق.
  // نفس تصميم "اختيار نوع الإضافة" في الشخصية (عنوان + عنوان فرعي + زر إغلاق
  // + شبكة بطاقات 3 أعمدة داخل حاوية رمادية فاتحة) — الشخصية هي المرجع
  // الأساسي للتصميم، وهذه الشاشة لا تحتاج مستوى فئات ثم أنواع فرعية لأن
  // الالتزامات المشتركة أربعة أنواع ثابتة فقط بلا فئات فرعية.
  void _openTypePickerSheet() {
    if (!PlanGate.canAdd(context, PlanModules.shared, _items.length)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, -4))],
          ),
          child: Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                // داخل غلاف rtl تعني .end اليسار — فكان عنوان النافذة
                // يلتصق بالحافة اليسرى خلافًا لكل نوافذ التطبيق.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(color: const Color(0xFFE4EAE8), borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: AppTr.uiDir,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('اختيار نوع الإضافة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF022E2A))),
                            SizedBox(height: 4),
                            Text('اختر نوع الالتزام المشترك المناسب', style: TextStyle(fontSize: 13, color: Color(0xFF5C6B68), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => Navigator.pop(sheetContext),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFFF2F6F5), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF46534F)),
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
                        children: _sharedEntryForms.values
                            .where((form) => !_sharedTypeHidden(form.label))
                            .map(
                              (form) => _SharedTypeCard(
                                form: form,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openEntryForm(form);
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

  // النموذج الديناميكي: يبني حقول الإدخال من _SharedForm.fields، مطابقًا
  // لأسلوب _buildDynamicField في الشخصية، مع دعم حقل "الأعضاء" كقائمة
  // أسماء (chips) بدل حقل نصي واحد.
  Future<void> _openEntryForm(_SharedForm form, {_SharedItem? editing}) async {
    await _openSharedEntryForm(
      context,
      _repository,
      form,
      editing: editing,
      onSaved: (savedItem, {required isNew}) {
        setState(() {
          if (isNew) {
            _items.insert(0, savedItem);
          } else {
            final idx = _items.indexWhere((i) => i.id == savedItem.id);
            if (idx != -1) _items[idx] = savedItem;
          }
        });
      },
    );
  }
}

// نُقلت خارج الصنف لتصبح قابلة للاستخدام من شاشة القائمة (الإضافة) وشاشة
// التفاصيل (التعديل) معًا عبر callback بدل الاعتماد المباشر على _repository/
// _items الخاصين بشاشة القائمة فقط.
Future<void> _openSharedEntryForm(
  BuildContext outerContext,
  SharedEntriesRepository repository,
  _SharedForm form, {
  _SharedItem? editing,
  required void Function(_SharedItem item, {required bool isNew}) onSaved,
}) async {
  final controllers = <String, TextEditingController>{};
    final selectValues = <String, String?>{};
    final peopleValues = <String, List<String>>{};
    for (final field in form.fields) {
      var existing = editing?.details[field.label] ?? '';
      if (existing.isEmpty) {
        // سجل أُنشئ قبل إعادة تسمية الحقل يُقرأ من مفتاحه القديم.
        final legacy = _sharedLegacyKeys[field.label];
        if (legacy != null) existing = editing?.details[legacy] ?? '';
      }
      if (field.kind == _SharedFieldKind.collect) {
        selectValues[field.label] = existing.isNotEmpty ? existing : null;
        selectValues[_expenseApprovalKey] =
            (editing?.details[_expenseApprovalKey] ?? '').trim() == _approvalNo
            ? _approvalNo
            : _approvalYes;
        final alert = (editing?.details[sharedBudgetAlertKey] ?? '').trim();
        selectValues[sharedBudgetAlertKey] =
            sharedBudgetAlertOptions.contains(alert)
            ? alert
            : sharedBudgetAlertOptions.first;
      } else if (field.kind == _SharedFieldKind.team) {
        // صندوق واحد يدير مفتاحين: المدير وقائمة الأعضاء.
        controllers[field.managerKey] = TextEditingController(
          text: editing?.details[field.managerKey] ?? '',
        );
        final rawMembers = editing?.details[_sharedMembersKey] ?? '';
        peopleValues[_sharedMembersKey] = rawMembers.isNotEmpty
            ? rawMembers
                  .split('،')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
            : <String>[];
        controllers[field.label] = TextEditingController();
      } else if (field.kind == _SharedFieldKind.select) {
        selectValues[field.label] = existing.isNotEmpty
            ? existing
            // العملة تبدأ بالعملة الافتراضية للتطبيق، وتُغيَّر لهذا السجل وحده.
            : (field.label == 'العملة' && AppSettings.currencySuffix.isNotEmpty
                ? AppSettings.currencySuffix
                : null);
      } else if (field.kind == _SharedFieldKind.people) {
        peopleValues[field.label] = existing.isNotEmpty ? existing.split('،').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : <String>[];
        controllers[field.label] = TextEditingController();
      } else {
        controllers[field.label] = TextEditingController(text: existing);
      }
    }
    // مرفق واحد لكل التزام، يُرفع مع الحفظ.
    final attachments = <String, XFile?>{};
    // نصيب كل عضو حسب طريقة التقسيم — يُحفظ في تفاصيل الالتزام.
    final splitValues = <String, String>{
      ...?() {
        final raw = editing?.details['تقسيم الأعضاء'];
        if (raw == null || raw.trim().isEmpty) return null;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) return null;
          return decoded.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
        } catch (_) {
          return null;
        }
      }(),
    };
    final splitControllers = <String, TextEditingController>{};
    // من ينشئ المشاركة أو الرحلة أو تحديد الأدوار هو المسؤول تلقائيًا،
    // ويغيّره لاحقًا إن أراد.
    if (editing == null) {
      final me = _myTeamEntry();
      if (me.isNotEmpty) {
        for (final field in form.fields) {
          final key = field.kind == _SharedFieldKind.team
              ? field.managerKey
              : field.label == _sharedManagerKey
              ? _sharedManagerKey
              : null;
          final controller = key == null ? null : controllers[key];
          if (controller != null && controller.text.trim().isEmpty) {
            controller.text = me;
          }
        }
      }
    }
    if (editing != null) {
      peopleValues[_balanceReceiptsKey] = List<String>.of(
        _balanceReceipts(editing.details),
      );
    }
    if (editing != null &&
        form.fields.any((f) => f.kind == _SharedFieldKind.order)) {
      // ترتيب الاستلام المحفوظ.
      peopleValues[_roscaOrderKey] = [
        for (final m in _parseSharedMembers(editing.details))
          if (m.name.trim().isNotEmpty) m.name.trim(),
      ];
    }
    final titleField = form.fields.firstWhere((f) => f.isTitle, orElse: () => form.fields.first);
    final amountField = form.fields.firstWhere((f) => f.isAmount, orElse: () => form.fields.first);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    // مسودة النموذج: الخروج من التطبيق لنسخ رقم تعريفي ثم الرجوع لا يُضيّع
    // ما سُجّل. تُحفظ على الجهاز وحده (لا تُرفع للسحابة) أثناء الكتابة وعند
    // مغادرة التطبيق، وتُمحى بالحفظ أو بزر الإغلاق. إن أغلق النظام التطبيق
    // في الخلفية، يُعرض استكمالها عند فتح النموذج نفسه مرة أخرى.
    final draftKey =
        'fundly_draft_shared_${AppIdentity.id}_${editing?.id ?? 'new'}_${form.label}';
    String draftJson() => jsonEncode({
      'c': {for (final e in controllers.entries) e.key: e.value.text},
      's': selectValues,
      'p': peopleValues,
      'v': splitValues,
    });
    final pristineDraft = draftJson();
    var lastDraft = pristineDraft;
    // مسودة تستحق السؤال: فيها ما كتبه المستخدم فعلًا — لا اسمي الذي يُضاف
    // تلقائيًا مسؤولًا ولا قيم النموذج الأولى. كانت «استكمال / بدء من جديد»
    // تظهر في كل مرة وليس فيها إلا اسمي.
    final pristineData = jsonDecode(pristineDraft) as Map;
    final meEntry = _myTeamEntry();
    bool isMe(String value) {
      final v = value.trim();
      if (v.isEmpty || v == meEntry) return true;
      final id = AppIdentity.id;
      return id.isNotEmpty && v.contains('($id)');
    }

    bool hasUserData(Object? decoded) {
      if (decoded is! Map) return false;
      final texts = decoded['c'];
      final baseTexts = pristineData['c'];
      if (texts is Map) {
        for (final entry in texts.entries) {
          final value = '${entry.value ?? ''}'.trim();
          final base = baseTexts is Map
              ? '${baseTexts[entry.key] ?? ''}'.trim()
              : '';
          if (value != base && !isMe(value)) return true;
        }
      }
      final people = decoded['p'];
      final basePeople = pristineData['p'];
      if (people is Map) {
        for (final entry in people.entries) {
          final baseList = basePeople is Map ? basePeople[entry.key] : null;
          final base = <String>{
            if (baseList is List)
              for (final name in baseList) '$name',
          };
          final list = entry.value;
          if (list is List &&
              list.any((name) => !base.contains('$name') && !isMe('$name'))) {
            return true;
          }
        }
      }
      final selects = decoded['s'];
      final baseSelects = pristineData['s'];
      if (selects is Map) {
        for (final entry in selects.entries) {
          final value = '${entry.value ?? ''}';
          final base = baseSelects is Map
              ? '${baseSelects[entry.key] ?? ''}'
              : '';
          if (value != base) return true;
        }
      }
      return false;
    }
    var formSaved = false;
    var formDiscarded = false;
    Future<void> writeDraft() async {
      final now = draftJson();
      if (now == lastDraft) return;
      lastDraft = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (now == pristineDraft ||
            (editing == null && !hasUserData(jsonDecode(now)))) {
          await prefs.remove(draftKey);
        } else {
          await prefs.setString(draftKey, now);
        }
      } catch (_) {}
    }

    Future<void> removeDraft() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(draftKey);
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(draftKey);
      // مسودة ليس فيها إلا اسمي: تُمحى بلا سؤال.
      if (raw != null &&
          raw.trim().isNotEmpty &&
          editing == null &&
          !hasUserData(jsonDecode(raw))) {
        await prefs.remove(draftKey);
        raw = null;
      }
      if (raw != null && raw.trim().isNotEmpty && outerContext.mounted) {
        final resume = await confirmAction(
          outerContext,
          title: 'بيانات لم تُحفظ',
          message:
              'سجّلت بيانات في هذا النموذج ولم تُحفظ بعد. هل تريد استكمالها؟',
          confirmLabel: 'استكمال',
          cancelLabel: 'بدء من جديد',
        );
        if (resume) {
          final data = jsonDecode(raw);
          if (data is Map) {
            final texts = data['c'];
            if (texts is Map) {
              texts.forEach((key, value) {
                controllers
                    .putIfAbsent('$key', () => TextEditingController())
                    .text = '${value ?? ''}';
              });
            }
            final selects = data['s'];
            if (selects is Map) {
              selects.forEach(
                (key, value) => selectValues['$key'] = value?.toString(),
              );
            }
            final people = data['p'];
            if (people is Map) {
              people.forEach((key, value) {
                if (value is List) {
                  peopleValues['$key'] = [for (final v in value) '$v'];
                }
              });
            }
            final splits = data['v'];
            if (splits is Map) {
              splitValues
                ..clear()
                ..addAll(
                  splits.map((k, v) => MapEntry('$k', '${v ?? ''}')),
                );
            }
            lastDraft = draftJson();
          }
        } else {
          await prefs.remove(draftKey);
        }
      }
    } catch (_) {}
    if (!outerContext.mounted) return;
    final draftTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(writeDraft()),
    );
    final draftLifecycle = AppLifecycleListener(
      onInactive: () => unawaited(writeDraft()),
      onHide: () => unawaited(writeDraft()),
      onPause: () => unawaited(writeDraft()),
    );

    await showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> save() async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            // النهاية / العودة لا تسبق البداية / الرحلة — في كل الأنواع.
            for (final (endKey, startKey) in const [
              ('تاريخ النهاية', 'تاريخ البداية'),
              ('تاريخ العودة', 'تاريخ الرحلة'),
            ]) {
              final from = roscaParseDate(controllers[startKey]?.text ?? '');
              final to = roscaParseDate(controllers[endKey]?.text ?? '');
              if (from != null && to != null && to.isBefore(from)) {
                await _sharedFormNotice(
                  context,
                  '«${AppTr.tr(endKey)}» ${AppTr.tr('قبل')} «${AppTr.tr(startKey)}» — ${AppTr.tr('صحّح التاريخين')}',
                );
                return;
              }
            }
            // الاسم إلزامي في كل الأنواع (اسم المجموعة في تحديد الأدوار).
            if ((controllers[titleField.label]?.text.trim() ?? '').isEmpty) {
              await _sharedFormNotice(
                context,
                '${AppTr.tr('اكتب')} «${AppTr.tr(_sharedFieldDisplay[titleField.label] ?? titleField.label)}» ${AppTr.tr('أولًا — حقل إلزامي')}',
              );
              return;
            }
            for (final field in form.fields) {
              if (field.kind == _SharedFieldKind.person &&
                  field.required &&
                  (controllers[field.label]?.text.trim() ?? '').isEmpty) {
                await _sharedFormNotice(
                  context,
                  'اختر المسؤول أولًا من «المسؤول / الأعضاء»',
                );
                return;
              }
              if (field.kind == _SharedFieldKind.people && field.required && (peopleValues[field.label] ?? const <String>[]).isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${field.label} مطلوب — أضف عضوًا واحدًا على الأقل')));
                return;
              }
              if (field.kind == _SharedFieldKind.team && field.required) {
                final manager =
                    controllers[field.managerKey]?.text.trim() ?? '';
                final members = peopleValues[_sharedMembersKey] ?? const [];
                if (manager.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('اختر ${field.managerKey} أولًا')),
                  );
                  return;
                }
                if (members.where((m) => m != manager).isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('أضف عضوًا واحدًا على الأقل'),
                    ),
                  );
                  return;
                }
                // الدفعة المقطوعة: مساهمة كل عضو إلزامية.
                if (selectValues[_collectMethodKey] == _collectLumpSum) {
                  final missing = [
                    manager,
                    ...members.where((m) => m != manager),
                  ].where(
                    (n) => (parseMoney(splitValues[n]?.trim() ?? '') ?? 0) <= 0,
                  );
                  if (missing.isNotEmpty) {
                    await _sharedFormNotice(
                      context,
                      'المساهمة إلزامية مع «دفعة مقطوعة» — أدخل مبلغ مساهمة كل عضو',
                    );
                    return;
                  }
                }
              }
              if (field.kind == _SharedFieldKind.collect &&
                  field.required &&
                  (selectValues[field.label] ?? '').isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('اختر طريقة تحصيل المبلغ')),
                );
                return;
              }
            }
            final confirmed = await confirmAction(
              context,
              title: editing == null ? 'تأكيد الحفظ' : 'تأكيد التعديل',
              message: editing == null
                  ? 'هل تريد حفظ ${_sharedShownType(form.label)}؟'
                  : 'هل تريد حفظ تعديل ${_sharedShownType(form.label)}؟',
              confirmLabel: 'تأكيد',
            );
            if (!confirmed || !context.mounted) return;
            setSheetState(() => isSaving = true);
            // يبدأ من التفاصيل القائمة بدل خريطة فارغة: نموذج التعديل لا
            // يملك أقسام "متابعة وتخطيط" و"مستندات" و"مواقع وأماكن"
            // و"الإجراءات"، فكان إعادة بنائه من الصفر يمحوها جميعًا من
            // قاعدة البيانات بمجرد الضغط على "حفظ التعديلات".
            final details = <String, String>{...?editing?.details};
            // من أنشأ الالتزام يديره من جهازه (إضافة الأعضاء مثلًا).
            if (editing == null && AppIdentity.id.isNotEmpty) {
              details[_creatorIdKey] = AppIdentity.id;
            }
            for (final field in form.fields) {
              if (field.kind == _SharedFieldKind.team) {
                details[field.managerKey] =
                    controllers[field.managerKey]?.text.trim() ?? '';
                details[_sharedMembersKey] =
                    (peopleValues[_sharedMembersKey] ?? const []).join('، ');
              } else if (field.kind == _SharedFieldKind.select ||
                  field.kind == _SharedFieldKind.collect) {
                details[field.label] = field.label == 'العملة'
                    // عملة الالتزام تُحفظ صراحةً: الأعضاء على حسابات مختلفة
                    // وعملاتهم الافتراضية مختلفة، فلا يتبع السجل جهاز كل منهم.
                    ? ((selectValues[field.label] ?? '').trim().isEmpty
                          ? AppSettings.currencySuffix
                          : selectValues[field.label]!.trim())
                    : selectValues[field.label] ?? '';
                if (field.kind == _SharedFieldKind.collect) {
                  final receipts =
                      peopleValues[_balanceReceiptsKey] ?? const <String>[];
                  if (selectValues[field.label] == _collectLumpSum &&
                      receipts.isNotEmpty) {
                    details[_balanceReceiptsKey] = jsonEncode(receipts);
                  } else {
                    details.remove(_balanceReceiptsKey);
                  }
                  if (selectValues[field.label] == _collectLumpSum) {
                    details[_expenseApprovalKey] =
                        selectValues[_expenseApprovalKey] ?? _approvalYes;
                    details[sharedBudgetAlertKey] =
                        selectValues[sharedBudgetAlertKey] ??
                        sharedBudgetAlertOptions.first;
                  } else {
                    details.remove(_expenseApprovalKey);
                    details.remove(sharedBudgetAlertKey);
                  }
                }
              } else if (field.kind == _SharedFieldKind.people) {
                details[field.label] = (peopleValues[field.label] ?? const []).join('، ');
              } else {
                details[field.label] = controllers[field.label]?.text.trim() ?? '';
              }
            }
            // ترحيل قائمة الأعضاء إلى صيغة JSON منظّمة (details['الأعضاء'])
            // لاستخدامها في حسابات التقسيم والموافقات، مع إضافة المسؤول/نائب
            // المسؤول تلقائيًا كأعضاء بأدوارهم.
            final memberNames = peopleValues['الأعضاء / المشتركين'] ?? const <String>[];
            final manager = details[_sharedManagerKey]?.trim() ?? details['مدير الرحلة']?.trim() ?? '';
            final deputy = details[_sharedDeputyKey]?.trim() ?? details['نائب مدير الرحلة']?.trim() ?? '';
            // أدوار الأعضاء القائمة تُحفَظ كما هي بدل إعادة تعيين الجميع
            // إلى "عضو" عند كل تعديل.
            // تُستعاد الأدوار غير القيادية فقط. استعادة "مسؤول" قديم لشخص
            // لم يعد مسؤولًا كانت تُنتج مسؤولَين في القائمة نفسها.
            final previousRoles = <String, String>{
              for (final m in (editing == null
                  ? const <_SharedMember>[]
                  : _parseSharedMembers(editing.details)))
                if (m.role != 'مسؤول' && m.role != 'نائب المسؤول')
                  m.name.trim(): m.role,
            };
            final members = <_SharedMember>[
              if (manager.isNotEmpty) _SharedMember(name: manager, role: 'مسؤول'),
              if (deputy.isNotEmpty) _SharedMember(name: deputy, role: 'نائب المسؤول'),
              ...memberNames
                  .where((n) => n != manager && n != deputy)
                  .map(
                    (n) => _SharedMember(
                      name: n,
                      role: previousRoles[n.trim()] ?? 'عضو',
                    ),
                  ),
            ];
            // (سجل العمليات المالية وبقية الأقسام محفوظة تلقائيًا الآن لأن
            // الخريطة تبدأ من تفاصيل السجل القائم.)
            details[_sharedMembersDetailKey] = _encodeSharedMembers(members);
            // الجمعية: المساهمة على الشخص = الإجمالي ÷ الأعضاء بالتساوي،
            // وعدد الدورات = عدد الأعضاء — محسوبان لا مكتوبان.
            if (form.fields.any((f) => f.kind == _SharedFieldKind.roscaInfo)) {
              final total =
                  parseMoney((details['إجمالي المساهمة'] ?? '').trim()) ??
                  0;
              if (members.length < 2) {
                setSheetState(() => isSaving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تحديد الأدوار يحتاج عضوين على الأقل مع المسؤول'),
                  ),
                );
                return;
              }
              // المدة بين البداية والنهاية تكفي كل الدورات بتكرارها.
              final start = roscaParseDate(details['تاريخ البداية'] ?? '');
              final end = roscaParseDate(details['تاريخ النهاية'] ?? '');
              final frequency =
                  (details['تكرار المساهمة'] ?? '').trim().isEmpty
                  ? 'شهري'
                  : details['تكرار المساهمة']!.trim();
              if (start != null && end != null && end.isBefore(start)) {
                setSheetState(() => isSaving = false);
                await _sharedFormNotice(
                  context,
                  'تاريخ النهاية قبل تاريخ البداية — صحّح التاريخين',
                );
                return;
              }
              if (start != null && end != null) {
                final last = roscaCycleDate(
                  start,
                  frequency,
                  members.length > 1 ? members.length - 1 : 1,
                );
                if (end.isBefore(last)) {
                  setSheetState(() => isSaving = false);
                  await _sharedFormNotice(
                    context,
                    '${AppTr.tr('المدة بين تاريخ البداية والنهاية لا تكفي')}: '
                    '${members.length} ${AppTr.tr('دورات')} '
                    '${AppTr.tr(frequency)} — ${AppTr.tr('آخر دورة في')} '
                    '${roscaFormatDate(last)}',
                  );
                  return;
                }
              }
              // ترتيب الاستلام كما رُتِّب بالأسهم (المسؤول ضمنه).
              final order = peopleValues[_roscaOrderKey] ?? const <String>[];
              if (order.isNotEmpty) {
                int rank(String name) {
                  final i = order.indexOf(name.trim());
                  return i < 0 ? order.length : i;
                }
                members.sort((a, b) => rank(a.name).compareTo(rank(b.name)));
                details[_sharedMembersDetailKey] =
                    _encodeSharedMembers(members);
              }
              final share = total / members.length;
              details['المساهمة على الشخص'] =
                  share.toStringAsFixed(share % 1 == 0 ? 0 : 2);
              details['عدد الدورات'] = '${members.length}';
            }
            // نصيب كل عضو حسب طريقة التقسيم (للأعضاء الحاليين فقط).
            splitValues.removeWhere(
              (name, _) => !members.any((m) => m.name == name),
            );
            details['تقسيم الأعضاء'] = jsonEncode(splitValues);

            final amountText = controllers[amountField.label]?.text.trim() ?? '0';
            // أرقام عربية وكسور وفواصل (2,500.5) تُقرأ — كان يُحفظ 0.
            var recordAmount = (parseMoney(amountText) ?? 0).round();
            // الرحلة بلا ميزانية مسبقة: مبلغها هو مجموع مساهمات الأعضاء عند
            // «دفعة مقطوعة»، وصفر عند «دفع فردي» حيث لا مساهمة أصلًا.
            if (form.fields.any((f) => f.kind == _SharedFieldKind.team)) {
              if (selectValues[_collectMethodKey] == _collectLumpSum) {
                var total = 0.0;
                for (final value in splitValues.values) {
                  total += parseMoney(value.trim()) ?? 0;
                }
                recordAmount = total.round();
              } else {
                recordAmount = 0;
                splitValues.clear();
              }
              details['إجمالي المساهمة'] = '$recordAmount';
            }
            final record = SharedEntryRecord(
              id: editing?.id,
              entryType: form.label,
              title: controllers[titleField.label]?.text.trim() ?? '',
              amount: recordAmount,
              dueDate: () {
                for (final f in form.fields) {
                  if (f.kind == _SharedFieldKind.date && f.isPrimary) {
                    return controllers[f.label]?.text.trim() ?? '';
                  }
                }
                return '';
              }(),
              status: editing?.status ?? _sharedStatusActive,
              details: details,
            );
            try {
              // المرفق المختار يُرفع مع السجل (مرفق واحد لكل التزام).
              XFile? attachment;
              for (final file in attachments.values) {
                if (file != null) attachment = file;
              }
              // حذف المستند من النموذج بلا اختيار غيره: يُحذف من الالتزام.
              final removeAttachment = attachment == null &&
                  attachments.isNotEmpty &&
                  attachments.values.every((file) => file == null);
              final repo = repository;
              final saved = editing == null
                  ? await repo.create(record, attachment: attachment)
                  : repo is SupabaseSharedEntriesRepository
                  ? await repo.update(
                      record,
                      attachment: attachment,
                      removeAttachment: removeAttachment,
                    )
                  : await repo.update(record, attachment: attachment);
              if (!outerContext.mounted) return;
              formSaved = true;
              Navigator.pop(sheetContext);
              onSaved(_SharedItem.fromRecord(saved), isNew: editing == null);
              ScaffoldMessenger.of(outerContext).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    '${editing == null ? '${AppTr.tr('تم حفظ')} ${AppTr.tr(_sharedShownType(form.label))} «${saved.title}» ${AppTr.tr('بنجاح')}' : 'تم حفظ التعديل بنجاح'}'
                    // أعضاء بالرقم التعريفي: كيف سيظهر اسمي لهم.
                    '${RegExp(r'FND-[A-Z2-9]{4}-[A-Z2-9]{4}').hasMatch(saved.details[_sharedMembersKey] ?? '') ? '\n${fndSentNote()}' : ''}',
                  ),
                ),
              );
            } catch (error) {
              debugPrint('shared_commitments save error: $error');
              setSheetState(() => isSaving = false);
              if (!outerContext.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تعذر الحفظ: $error'), duration: const Duration(seconds: 6)),
              );
            }
          }

          return Directionality(
            textDirection: AppTr.uiDir,
            child: DraggableScrollableSheet(
              initialChildSize: 0.9,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (context, scrollController) => Container(
                decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
                child: Form(
                  key: formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(color: const Color(0xFFE4EAE8), borderRadius: BorderRadius.circular(999)),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: form.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(form.icon, color: form.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  editing == null
                                      ? 'إضافة ${_sharedShownType(form.label)}'
                                      : 'تعديل ${_sharedShownType(form.label)}',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF022E2A)),
                                ),
                                Text(form.subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF5C6B68), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: AppTr.tr('إغلاق'),
                            // الإغلاق بالزر يعني ترك ما كُتب: تُمحى المسودة.
                            onPressed: () {
                              formDiscarded = true;
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _sharedFormSectionTitle('الحقول الأساسية', Icons.edit_note_rounded),
                      const SizedBox(height: 12),
                      // الحقول النصفية تُجمع اثنين في سطر واحد.
                      ..._buildSharedFieldRows(
                        context,
                        form,
                        controllers,
                        selectValues,
                        peopleValues,
                        setSheetState,
                        attachments,
                        splitValues,
                        splitControllers,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSaving ? null : save,
                          style: ElevatedButton.styleFrom(backgroundColor: form.color, padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(editing == null ? 'حفظ الالتزام' : 'حفظ التعديلات', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    draftTimer.cancel();
    draftLifecycle.dispose();
    if (formSaved || formDiscarded) {
      await removeDraft();
    } else {
      // أُغلقت بالسحب أو بالرجوع: يبقى ما كُتب لاستكماله لاحقًا.
      await writeDraft();
    }
    // التخلص بعد انتهاء حركة إغلاق الورقة: التخلص الفوري كان يترك
    // عناصر الواجهة تستعمل متحكمات محرَّرة فيظهر الخطأ الأحمر
    // «_dependents.isEmpty» عند الرجوع خطوة إلى الوراء.
    final openControllers = <TextEditingController>[
      ...controllers.values,
      ...splitControllers.values,
    ];
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final c in openControllers) {
        c.dispose();
      }
    });
}

// نُقلت خارج الصنف لتصبح قابلة للاستخدام من شاشة القائمة (الإضافة) وشاشة
// التفاصيل (التعديل) معًا، بدل أن تبقى حكرًا على صنف State واحد فقط.
/// أسماء الأفراد والجهات المحفوظة — نفس مخزن شاشة «الأفراد والجهات».
Future<List<String>> _loadDirectoryNames() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('people_management_records_v1');
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => (row['fullName'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// اختيار شخص: من المحفوظين، أو دعوة شخص جديد برقمه التعريفي.
Future<String?> _pickSharedPerson(BuildContext context, Color accent) async {
  final names = await _loadDirectoryNames();
  if (!context.mounted) return null;
  final searchController = TextEditingController();
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Directionality(
      textDirection: AppTr.uiDir,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            // العنوان وزر × للخروج من الصفحة.
            Row(
              textDirection: AppTr.uiDir,
              children: [
                const Expanded(
                  child: Text(
                    'اختيار شخص',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppTr.tr('إغلاق'),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.title,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // خانة بشكل حقل كتابة: إطار ونقاط مكان الأرقام.
            FndEntryBox(
              accent: accent,
              onTap: () async {
                // يكتب الرقم فيظهر تحته اسم صاحبه من الخادم.
                final person = await askFndPerson(sheetContext);
                if (person == null || !sheetContext.mounted) return;
                Navigator.pop(sheetContext, '${person.$2} (${person.$1})');
              },
            ),
            const Divider(height: 18, color: AppTheme.hairline),
            // بحث داخل الأفراد المحفوظين.
            TextField(
              controller: searchController,
              textDirection: AppTr.uiDir,
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: AppTr.tr('ابحث في الأفراد'),
                hintStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: AppTheme.muted,
                ),
                filled: true,
                fillColor: AppTheme.field,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // اسم غير موجود في الأفراد: يُضاف كما كُتب.
            if (searchController.text.trim().isNotEmpty &&
                !names.contains(searchController.text.trim()))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_add_alt_1_rounded, color: accent),
                title: Text(
                  'إضافة «${searchController.text.trim()}» كاسم جديد',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                onTap: () =>
                    Navigator.pop(sheetContext, searchController.text.trim()),
              ),
            if (names.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'لا يوجد أفراد محفوظون بعد',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              )
            else
              for (final name in names.where(
                (n) => n.contains(searchController.text.trim()),
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.muted,
                  ),
                  title: Text(
                    name,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, name),
                ),
          ],
        ),
      ),
    ),
    ),
  );
  // التخلص بعد انتهاء حركة الإغلاق حتى لا يُستعمل متحكم محرَّر.
  Future.delayed(const Duration(milliseconds: 600), searchController.dispose);
  return picked;
}

/// يبني حقول النموذج، ويجمع كل حقلين نصفيين متتاليين في سطر واحد.
List<Widget> _buildSharedFieldRows(
  BuildContext context,
  _SharedForm form,
  Map<String, TextEditingController> controllers,
  Map<String, String?> selectValues,
  Map<String, List<String>> peopleValues,
  StateSetter setSheetState,
  Map<String, XFile?> attachments,
  Map<String, String> splitValues,
  Map<String, TextEditingController> splitControllers,
) {
  Widget one(_SharedField field) => _buildSharedField(
    context,
    field,
    controllers,
    selectValues,
    peopleValues,
    setSheetState,
    form.color,
    attachments: attachments,
    splitValues: splitValues,
    splitControllers: splitControllers,
  );

  final rows = <Widget>[];
  var i = 0;
  while (i < form.fields.length) {
    final field = form.fields[i];
    if (field.hidden) {
      i += 1;
      continue;
    }
    final next = i + 1 < form.fields.length ? form.fields[i + 1] : null;
    if (field.half && next != null && next.half) {
      rows.add(
        Row(
          textDirection: AppTr.uiDir,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: one(field)),
            const SizedBox(width: 10),
            Expanded(child: one(next)),
          ],
        ),
      );
      i += 2;
    } else {
      rows.add(one(field));
      i += 1;
    }
    rows.add(const SizedBox(height: 12));
  }
  return rows;
}

Widget _buildSharedField(
  BuildContext context,
  _SharedField field,
  Map<String, TextEditingController> controllers,
  Map<String, String?> selectValues,
  Map<String, List<String>> peopleValues,
  StateSetter setSheetState,
  Color accent, {
  Map<String, XFile?> attachments = const {},
  Map<String, String> splitValues = const {},
  Map<String, TextEditingController> splitControllers = const {},
}) {
  // العنوان بنجمة للإلزامي، و«(اختياري)» سطر صغير تحت الحقل.
  final shownLabel = _sharedFieldDisplay[field.label] ?? field.label;
  final labelText = field.required ? '$shownLabel *' : shownLabel;
    switch (field.kind) {
      // عنوان قسم أسود يفصل مجموعة الحقول عمّا قبلها.
      case _SharedFieldKind.header:
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
            ],
          ),
        );
      // طريقة تحصيل المبلغ: خياران بدائرة اختيار وشرح تحت كل واحد.
      // المساهمة على الشخص = الإجمالي ÷ عدد الأعضاء (بالتساوي دائمًا)،
      // وعدد الدورات = عدد الأعضاء — يتحدّثان مع كل عضو يُضاف.
      case _SharedFieldKind.roscaInfo:
        {
          final total = parseMoney(
                controllers['إجمالي المساهمة']?.text.trim() ?? '',
              ) ??
              0;
          final currency = (selectValues['العملة'] ?? '').trim().isEmpty
              ? AppSettings.currencySuffix
              : selectValues['العملة']!;
          final manager = controllers[_sharedManagerKey]?.text.trim() ?? '';
          final people = <String>{
            if (manager.isNotEmpty) manager,
            ...(peopleValues[_sharedMembersKey] ?? const <String>[]),
          };
          final count = people.length;
          String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
          final ready = total > 0 && count > 0;
          final manual = selectValues[_splitManualFlag] == 'manual';
          final ordered = _roscaPeople(controllers, peopleValues);
          // أول عرض (أو عضو جديد بلا مبلغ): توزيع بالتساوي في القيم فقط.
          if (!manual &&
              ready &&
              ordered.any((p) => !splitValues.containsKey(p))) {
            final each = (total / ordered.length * 100).floorToDouble() / 100;
            for (var i = 0; i < ordered.length; i++) {
              splitValues[ordered[i]] = _fmtShare(
                i == ordered.length - 1
                    ? total - each * (ordered.length - 1)
                    : each,
              );
            }
          }
          final infoBox = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Icon(field.icon, size: 19, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        ready
                            ? 'المساهمة على الشخص: ${fmt(total / count)} $currency'
                            : 'المساهمة على الشخص تُحسب تلقائيًا',
                        textAlign: AppTr.alignEnd,
                        maxLines: 2,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ready
                            ? 'بالتساوي على $count أعضاء · $count دورات '
                                  '(يستلم كل عضو ${fmt(total)} $currency في دوره)'
                            : 'اكتب إجمالي المساهمة على الكل وأضف الأعضاء: '
                                  'يُوزَّع بالتساوي، ودورة لكل عضو',
                        textAlign: AppTr.alignEnd,
                        maxLines: 3,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          // تحقق فوري: النهاية بعد البداية، والمدة تكفي الدورات بتكرارها
          // (دورة واحدة على الأقل قبل إضافة الأعضاء).
          final start = roscaParseDate(
            controllers['تاريخ البداية']?.text ?? '',
          );
          final end = roscaParseDate(controllers['تاريخ النهاية']?.text ?? '');
          final frequency = (selectValues['تكرار المساهمة'] ?? '').trim();
          String? problem;
          if (start != null && end != null) {
            if (end.isBefore(start)) {
              problem = 'تاريخ النهاية قبل تاريخ البداية — صحّح التاريخين';
            } else if (frequency.isNotEmpty) {
              final last = roscaCycleDate(
                start,
                frequency,
                count > 1 ? count - 1 : 1,
              );
              if (end.isBefore(last)) {
                problem =
                    '${AppTr.tr('المدة بين تاريخ البداية والنهاية لا تكفي')} '
                    '${AppTr.tr('مع تكرار')} «${AppTr.tr(frequency)}» — '
                    '${AppTr.tr('يجب أن تكون النهاية في')} '
                    '${roscaFormatDate(last)} ${AppTr.tr('أو بعده')}';
              }
            }
          }
          if (problem == null) return infoBox;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              infoBox,
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.dangerSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Text(
                  problem,
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            ],
          );
        }
      case _SharedFieldKind.collect:
        {
          final collect = _CollectMethodField(
            label: field.required ? '${field.label} *' : field.label,
            icon: field.icon,
            accent: accent,
            value: selectValues[field.label] ?? '',
            onChanged: (value) =>
                setSheetState(() => selectValues[field.label] = value),
          );
          // مع «دفعة مقطوعة» فقط: هل يحتاج مصروف العضو موافقة المسؤول؟
          if (selectValues[field.label] != _collectLumpSum) return collect;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              collect,
              const SizedBox(height: 10),
              _expenseApprovalTile(
                on: selectValues[_expenseApprovalKey] != _approvalNo,
                onChanged: (value) => setSheetState(
                  () => selectValues[_expenseApprovalKey] = value
                      ? _approvalYes
                      : _approvalNo,
                ),
              ),
              const SizedBox(height: 10),
              // نفس خيار العهدة: حين يبلغ المصروف هذه النسبة من الميزانية
              // يصل تنبيه في مركز التنبيهات والكلندر.
              DropdownButtonFormField<String>(
                initialValue: selectValues[sharedBudgetAlertKey] ??
                    sharedBudgetAlertOptions.first,
                isExpanded: true,
                alignment: AlignmentDirectional.centerEnd,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.title,
                ),
                iconEnabledColor: AppTheme.title,
                decoration: _sharedFieldDecoration(
                  sharedBudgetAlertKey,
                  Icons.notifications_active_outlined,
                  accent,
                ),
                items: [
                  for (final option in sharedBudgetAlertOptions)
                    DropdownMenuItem(
                      value: option,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        option,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) => setSheetState(
                  () => selectValues[sharedBudgetAlertKey] = value,
                ),
              ),
              if ((peopleValues[_sharedMembersKey] ?? const <String>[])
                  .isEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'سيظهر مبلغ المساهمة بعد إضافة الأعضاء',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ],
          );
        }
      // المدير والأعضاء في صندوق واحد: العنوان فيه العدد وزر +، وتحته
      // مستطيل لكل شخص في أوله اسمه وفي آخره مساهمته. المساهمة وإجماليها
      // لا يظهران إلا مع «دفعة مقطوعة» — «دفع فردي» بلا مساهمات أصلًا.
      case _SharedFieldKind.team:
        {
          final managerController = controllers[field.managerKey];
          final manager = managerController?.text.trim() ?? '';
          final members = peopleValues[_sharedMembersKey] ?? <String>[];
          final lumpSum = selectValues[_collectMethodKey] == _collectLumpSum;
          // لا يُضاف المسؤول ولا الأعضاء قبل اختيار طريقة تحصيل المبلغ.
          final needsCollect = selectValues.containsKey(_collectMethodKey) &&
              (selectValues[_collectMethodKey] ?? '').isEmpty;
          final people = <String>[
            if (manager.isNotEmpty) manager,
            ...members.where((m) => m != manager),
          ];
          var totalShare = 0.0;
          for (final name in people) {
            totalShare += parseMoney(splitValues[name]?.trim() ?? '') ?? 0;
          }
          // الإجمالي على الكل يُكتب مرة ويُوزَّع بالتساوي، ويمكن تعديل أي عضو.
          final totalController = controllers.putIfAbsent(
            _teamTotalKey,
            () => TextEditingController(
              text: totalShare > 0 ? _fmtShare(totalShare) : '',
            ),
          );
          final manual = selectValues[_splitManualFlag] == 'manual';
          // الرحلة والمشاركات المشتركة: بلا «إجمالي المساهمة على الكل»؛
          // كل عضو يُكتب مبلغه، والمجموع أسفل القائمة.
          final hideTotal = field.managerKey == _tripManagerKey ||
              field.managerKey == _sharedManagerKey;
          void redistribute() {
            if (hideTotal) return;
            final mgr = managerController?.text.trim() ?? '';
            _autoSplitShares(
              totalText: totalController.text,
              people: <String>[
                if (mgr.isNotEmpty) mgr,
                ...(peopleValues[_sharedMembersKey] ?? const <String>[])
                    .where((m) => m != mgr),
              ],
              selectValues: selectValues,
              splitValues: splitValues,
              splitControllers: splitControllers,
            );
          }

          final totalTyped = parseMoney(totalController.text.trim()) ?? 0;
          final sumMatches =
              totalTyped <= 0 || (totalShare - totalTyped).abs() < 0.01;
          // الرحلة والمشاركات المشتركة: إجمالي المساهمة على الكل تحت طريقة
          // التحصيل مباشرة، ثم المسؤول والأعضاء.
          final totalFirst = field.managerKey == _tripManagerKey ||
              field.managerKey == _sharedManagerKey;
          final totalBlock = <Widget>[
            if (lumpSum) ...[
                TextField(
                  controller: totalController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setSheetState(() {
                    selectValues[_splitManualFlag] = null;
                    redistribute();
                  }),
                  decoration: _sharedFieldDecoration(
                    'إجمالي المساهمة على الكل',
                    Icons.payments_outlined,
                    accent,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Expanded(
                      child: Text(
                        manual
                            ? 'عدّلت مبالغ الأعضاء يدويًا'
                            : 'يُوزَّع بالتساوي على الأعضاء، ويمكنك تعديل '
                                  'مبلغ أي عضو',
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    if (manual)
                      TextButton(
                        onPressed: () => setSheetState(() {
                          selectValues[_splitManualFlag] = null;
                          redistribute();
                        }),
                        child: const Text(
                          'توزيع بالتساوي',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
            ],
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totalFirst && !hideTotal) ...totalBlock,
              Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(field.icon, size: 18, color: AppTheme.title),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${field.label}${field.required ? ' *' : ''} (${people.length})',
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                    onTap: () async {
                      if (needsCollect) {
                        await _sharedFormNotice(
                          context,
                          'اختر طريقة تحصيل المبلغ أولًا',
                        );
                        return;
                      }
                      final picked = await _pickSharedPerson(context, accent);
                      if (picked == null) return;
                      setSheetState(() {
                        if (manager.isEmpty) {
                          managerController?.text = picked;
                        } else if (picked != manager &&
                            !members.contains(picked)) {
                          members.add(picked);
                          peopleValues[_sharedMembersKey] = members;
                        }
                        redistribute();
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (needsCollect ? AppTheme.muted : accent)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.rIcon),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: needsCollect ? AppTheme.muted : accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                needsCollect
                    ? 'اختر طريقة تحصيل المبلغ أولًا، ثم أضف ${field.managerKey} والأعضاء'
                    : manager.isEmpty
                    ? 'اضغط + لاختيار ${field.managerKey} أولًا'
                    : 'اضغط + لإضافة عضو — من الأفراد أو بالرقم التعريفي',
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 8),
              if (!totalFirst) ...totalBlock,
              for (final name in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
                    decoration: BoxDecoration(
                      color: AppTheme.field,
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                    // الاسم سطر كامل (قد يكون ثلاثيًا مع الرقم التعريفي)،
                    // وتحته الدور والمساهمة.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                textAlign: AppTr.alignEnd,
                                maxLines: 3,
                                softWrap: true,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.title,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: AppTheme.muted,
                              ),
                              onPressed: () => setSheetState(() {
                                if (name == manager) {
                                  managerController?.text = '';
                                } else {
                                  members.remove(name);
                                  peopleValues[_sharedMembersKey] = members;
                                }
                                splitValues.remove(name);
                                redistribute();
                              }),
                            ),
                          ],
                        ),
                        if (name == manager || lumpSum || manager.isNotEmpty)
                          Row(
                            textDirection: AppTr.uiDir,
                            children: [
                              // تغيير المسؤول: أي عضو يصير المسؤول بضغطة.
                              if (name != manager && manager.isNotEmpty)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.goldDark,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                  ),
                                  onPressed: () => setSheetState(() {
                                    members.remove(name);
                                    if (!members.contains(manager)) {
                                      members.add(manager);
                                    }
                                    peopleValues[_sharedMembersKey] = members;
                                    managerController?.text = name;
                                  }),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    field.managerKey == _tripManagerKey
                                        ? 'اجعله المدير'
                                        : 'اجعله المسؤول',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              if (name == manager)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.goldSoft,
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.rPill,
                                    ),
                                  ),
                                  child: Text(
                                    field.managerKey == _tripManagerKey
                                        ? 'المدير'
                                        : 'المسؤول',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.goldDark,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (lumpSum)
                                SizedBox(
                                  width: 130,
                                  child: TextField(
                                    controller: splitControllers.putIfAbsent(
                                      name,
                                      () => TextEditingController(
                                        text: splitValues[name] ?? '',
                                      ),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    onChanged: (value) => setSheetState(() {
                                      splitValues[name] = value.trim();
                                      selectValues[_splitManualFlag] = 'manual';
                                    }),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: AppTr.tr('المساهمة *'),
                                      hintStyle: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.muted,
                                      ),
                                      filled: true,
                                      fillColor: AppTheme.page,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.rField,
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (lumpSum && people.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: Text(
                          'مجموع مساهمات الأعضاء',
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      Text(
                        totalTyped > 0 && !hideTotal
                            ? '${_fmtShare(totalShare)} / ${_fmtShare(totalTyped)}'
                            : _fmtShare(totalShare),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: sumMatches || hideTotal
                              ? accent
                              : AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              // تحت مجموع المساهمات: إيصالات الأرصدة (اختيارية).
              if (lumpSum && people.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final path in List<String>.of(
                  peopleValues[_balanceReceiptsKey] ?? const <String>[],
                ))
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: AppTheme.field,
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 17,
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path.split(RegExp(r'[\\/]')).last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: AppTheme.muted,
                          ),
                          onPressed: () => setSheetState(() {
                            final list = List<String>.of(
                              peopleValues[_balanceReceiptsKey] ??
                                  const <String>[],
                            )..remove(path);
                            peopleValues[_balanceReceiptsKey] = list;
                          }),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.4)),
                    minimumSize: const Size.fromHeight(42),
                  ),
                  onPressed: () async {
                    final path = await _pickReceiptFile(context);
                    if (path == null) return;
                    setSheetState(() {
                      peopleValues[_balanceReceiptsKey] = [
                        ...?peopleValues[_balanceReceiptsKey],
                        path,
                      ];
                    });
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text(
                    'إضافة إيصالات الأرصدة (اختياري)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          );
        }
      // منتقي شخص: صندوق بسهم أسود يفتح المحفوظين أو الدعوة بالمعرّف.
      case _SharedFieldKind.person:
        {
          final controller = controllers[field.label]!;
          final value = controller.text.trim();
          return InkWell(
            onTap: () async {
              final picked = await _pickSharedPerson(context, accent);
              if (picked == null) return;
              setSheetState(() {
                controller.text = picked;
                if (controllers.containsKey('إجمالي المساهمة')) {
                  _autoSplitShares(
                    totalText: controllers['إجمالي المساهمة']!.text,
                    people: _roscaPeople(controllers, peopleValues),
                    selectValues: selectValues,
                    splitValues: splitValues,
                    splitControllers: splitControllers,
                  );
                }
              });
            },
            borderRadius: BorderRadius.circular(AppTheme.rField),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rField),
              ),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(field.icon, size: 19, color: AppTheme.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value.isEmpty ? labelText : value,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: value.isEmpty ? AppTheme.muted : AppTheme.title,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.title,
                  ),
                ],
              ),
            ),
          );
        }
      // ترتيب الاستلام: المسؤول أولًا بشارته، ثم الأعضاء بأرقام تسلسلهم
      // وأسهم لتغيير الترتيب — الترتيب المحفوظ هو ترتيب الاستلام فعلًا.
      // قائمة واحدة احترافية: كل عضو يظهر مرة واحدة فقط ومعه دوره، وشارة
      // «المسؤول» إن كان هو، ومساهمته (قابلة للتعديل)، وموعد استلامه.
      case _SharedFieldKind.order:
        {
          final members = peopleValues['الأعضاء / المشتركين'] ?? <String>[];
          final managerController =
              controllers[_sharedManagerKey] ?? controllers['مدير الرحلة'];
          final manager = managerController?.text.trim() ?? '';
          // الترتيب المحفوظ أولًا (يشمل المسؤول)، ثم من أُضيف بعده.
          final base = <String>[
            if (manager.isNotEmpty && !members.contains(manager)) manager,
            ...members,
          ];
          final savedOrder = peopleValues[_roscaOrderKey] ?? const <String>[];
          final rows = <String>[
            ...savedOrder.where(base.contains),
            ...base.where((n) => !savedOrder.contains(n)),
          ];
          final totalController = controllers['إجمالي المساهمة'];
          final total =
              parseMoney(totalController?.text.trim() ?? '') ?? 0;
          final showShares = totalController != null && total > 0;
          final currency = (selectValues['العملة'] ?? '').trim().isEmpty
              ? AppSettings.currencySuffix
              : selectValues['العملة']!;
          final start = roscaParseDate(
            controllers['تاريخ البداية']?.text ?? '',
          );
          final frequency = (selectValues['تكرار المساهمة'] ?? '').trim();
          final manual = selectValues[_splitManualFlag] == 'manual';
          var sum = 0.0;
          for (final name in rows) {
            sum += parseMoney(splitValues[name] ?? '') ?? 0;
          }
          String fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
          void redistribute() => _autoSplitShares(
            totalText: totalController?.text ?? '',
            people: _roscaPeople(controllers, peopleValues),
            selectValues: selectValues,
            splitValues: splitValues,
            splitControllers: splitControllers,
          );
          void move(String name, int step) {
            final from = rows.indexOf(name);
            final to = from + step;
            if (from < 0 || to < 0 || to >= rows.length) return;
            setSheetState(() {
              final order = List<String>.of(rows)
                ..removeAt(from)
                ..insert(to, name);
              peopleValues[_roscaOrderKey] = order;
              // الأول في الترتيب هو المسؤول، وشارته تنتقل معه.
              final first = order.first;
              if (first != manager && managerController != null) {
                members.remove(first);
                if (manager.isNotEmpty && !members.contains(manager)) {
                  members.add(manager);
                }
                peopleValues['الأعضاء / المشتركين'] = members;
                managerController.text = first;
              }
            });
          }

          Widget arrow(IconData icon, VoidCallback? onTap) => InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rIcon),
            onTap: onTap,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: onTap == null
                    ? Colors.transparent
                    : accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.rIcon),
              ),
              child: Icon(
                icon,
                size: 20,
                color: onTap == null ? AppTheme.hairline : accent,
              ),
            ),
          );

          Widget memberRow(int index) {
            final name = rows[index];
            final isManager = name == manager;
            final receiveDate = start == null
                ? null
                : roscaCycleDate(start, frequency, index);
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rField),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الاسم سطر كامل.
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        tooltip: AppTr.tr('حذف'),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: AppTheme.muted,
                        ),
                        onPressed: () => setSheetState(() {
                          if (isManager) managerController?.text = '';
                          members.remove(name);
                          peopleValues['الأعضاء / المشتركين'] = members;
                          splitValues.remove(name);
                          redistribute();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      const SizedBox(width: 40),
                      if (isManager) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.goldSoft,
                            borderRadius: BorderRadius.circular(
                              AppTheme.rPill,
                            ),
                          ),
                          child: const Text(
                            'المسؤول',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.goldDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          receiveDate == null
                              ? 'يستلم في الدورة ${index + 1}'
                              : 'يستلم في الدورة ${index + 1} · '
                                    '${roscaFormatDate(receiveDate)}',
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      const SizedBox(width: 40),
                      if (showShares)
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: splitControllers.putIfAbsent(
                              name,
                              () => TextEditingController(
                                text: splitValues[name] ?? '',
                              ),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                            onChanged: (value) => setSheetState(() {
                              splitValues[name] = value.trim();
                              selectValues[_splitManualFlag] = 'manual';
                            }),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: AppTheme.page,
                              suffixText: currency,
                              suffixStyle: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 6,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rField,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      // أسهم الترتيب: أعلى / أسفل — للمسؤول أيضًا.
                      arrow(
                        Icons.keyboard_arrow_up_rounded,
                        index > 0 ? () => move(name, -1) : null,
                      ),
                      const SizedBox(width: 6),
                      arrow(
                        Icons.keyboard_arrow_down_rounded,
                        index < rows.length - 1 ? () => move(name, 1) : null,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            );
          }

          // بلا عنوان مستقل: القائمة تتبع «المسؤول / الأعضاء» مباشرة.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const Text(
                  'أضف الأعضاء ليظهر ترتيب الاستلام',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                )
              else if (showShares)
                const Text(
                  'رتّب بالأسهم، ويمكنك تعديل مساهمة أي عضو',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              for (var index = 0; index < rows.length; index++)
                memberRow(index),
              if (showShares && rows.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: Text(
                          '${AppTr.tr('مجموع المساهمات')}: '
                          '${fmt(sum)} / ${fmt(total)} $currency',
                          textAlign: AppTr.alignEnd,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: (sum - total).abs() < 0.01
                                ? accent
                                : AppTheme.danger,
                          ),
                        ),
                      ),
                      if (manual)
                        TextButton(
                          onPressed: () => setSheetState(() {
                            selectValues[_splitManualFlag] = null;
                            redistribute();
                          }),
                          child: const Text(
                            'توزيع بالتساوي',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }
      // تقسيم المبلغ على الأعضاء: يتغيّر شكله بتغيّر طريقة التقسيم،
      // ويعيد الحساب تلقائيًا كلما أُضيف عضو أو تغيّر المبلغ.
      case _SharedFieldKind.split:
        {
          final method = selectValues[_sharedSplitMethodKey] ?? '';
          final members = peopleValues['الأعضاء / المشتركين'] ?? <String>[];
          final manager =
              controllers[_sharedManagerKey]?.text.trim() ??
              controllers['مدير الرحلة']?.text.trim() ??
              '';
          final people = <String>[
            if (manager.isNotEmpty && !members.contains(manager)) manager,
            ...members,
          ];
          final rawAmount =
              controllers['المبلغ']?.text.trim() ??
              controllers['الميزانية']?.text.trim() ??
              '';
          final total = parseMoney(rawAmount) ?? 0;
          final share = people.isEmpty ? 0.0 : total / people.length;
          if (method.isEmpty || people.isEmpty) {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rInner),
              ),
              child: Text(
                method.isEmpty
                    ? 'اختر طريقة التقسيم أولًا'
                    : 'أضف الأعضاء ليظهر نصيب كل عضو',
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(field.icon, size: 18, color: AppTheme.title),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نصيب كل عضو ($method)',
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
              const SizedBox(height: 8),
              for (final name in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: method == 'بالتساوي'
                            ? Container(
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.rField,
                                  ),
                                ),
                                child: Text(
                                  share.toStringAsFixed(
                                    share == share.roundToDouble() ? 0 : 2,
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: accent,
                                  ),
                                ),
                              )
                            : TextField(
                                controller: splitControllers.putIfAbsent(
                                  name,
                                  () => TextEditingController(
                                    text: splitValues[name] ?? '',
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                                onChanged: (value) =>
                                    splitValues[name] = value.trim(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: method == 'بالنسبة'
                                      ? '%'
                                      : 'المبلغ',
                                  hintStyle: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.muted,
                                  ),
                                  filled: true,
                                  fillColor: AppTheme.field,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.rField,
                                    ),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              if (method == 'بالتساوي')
                Text(
                  'إجمالي $total على ${people.length} '
                  '= ${share.toStringAsFixed(2)} لكل عضو',
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
            ],
          );
        }
      // إرفاق مستند مع الالتزام.
      case _SharedFieldKind.attachment:
        {
          final controller = controllers[field.label]!;
          final name = controller.text.trim();
          return AppRemovableAttachment(
            attached: name.isNotEmpty,
            onRemove: () => setSheetState(() {
                attachments[field.label] = null;
                controller.text = '';
              }),
            child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.4)),
            ),
            onPressed: () async {
              try {
                final picked = await DocumentStore.pickXFile(
                  context,
                  imageQuality: 88,
                );
                if (picked == null) return;
                attachments[field.label] = picked;
                setSheetState(() => controller.text = picked.name);
              } catch (_) {
                // تعذّر فتح المعرض: يبقى الحقل فارغًا بلا إسقاط النموذج.
              }
            },
            icon: Icon(
              name.isEmpty ? Icons.attach_file_rounded : Icons.check_rounded,
              size: 18,
            ),
            label: Text(
              name.isEmpty ? 'إرفاق مستند' : name,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          );
        }
      case _SharedFieldKind.select:
        return DropdownButtonFormField<String>(
          initialValue: selectValues[field.label],
          isExpanded: true,
          alignment: AlignmentDirectional.centerEnd,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.title,
          ),
          iconEnabledColor: AppTheme.title,
          decoration: _sharedFieldDecoration(
            labelText,
            field.icon,
            accent,
            optional: field.optional,
          ),
          // الخيارات تبدأ من اليمين كبقية نصوص التطبيق.
          items: field.options
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    o,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.title,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setSheetState(() => selectValues[field.label] = v),
          validator: trValidator(field.required ? (v) => v == null || v.isEmpty ? 'مطلوب' : null : null),
        );
      case _SharedFieldKind.people:
        {
        final names = peopleValues[field.label] ?? const <String>[];
        // الجمعية: الأعضاء يُضافون من هنا فقط، ويظهرون مرة واحدة في
        // «ترتيب الاستلام»، ولا يُضافون قبل إجمالي المساهمة، وأولهم المسؤول.
        final isRosca = controllers.containsKey('إجمالي المساهمة');
        final needsTotal = isRosca &&
            (parseMoney(
                      controllers['إجمالي المساهمة']!.text.trim(),
                    ) ??
                    0) <=
                0;
        final roscaManager = controllers[_sharedManagerKey];
        final needsManager =
            isRosca && (roscaManager?.text.trim() ?? '').isEmpty;
        return StatefulBuilder(
          builder: (context, setFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labelText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF2C3B38))),
              // الجمعية: السطر تحت «المسؤول / الأعضاء» هو «ترتيب الاستلام»،
              // والقائمة نفسها تحت زر الإضافة مباشرة.
              if (isRosca) ...[
                const SizedBox(height: 4),
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Icon(
                      Icons.format_list_numbered_rounded,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ترتيب الاستلام — الأول يستلم أولًا',
                        textAlign: AppTr.alignEnd,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              // الإضافة دائمًا من المنتقي: بحث في الأفراد، أو كتابة اسم
              // جديد، أو دعوة بالرقم التعريفي — لا إدخال حرّ بلا مرجع.
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                onTap: () async {
                  if (needsTotal) {
                    await _sharedFormNotice(
                      context,
                      'أدخل إجمالي المساهمة على الكل أولًا',
                    );
                    return;
                  }
                  final picked = await _pickSharedPerson(context, accent);
                  if (picked == null || names.contains(picked)) return;
                  if (isRosca && roscaManager?.text.trim() == picked) return;
                  setSheetState(() {
                    setFieldState(() {
                      // أول من يُضاف في الجمعية هو المسؤول.
                      if (needsManager && roscaManager != null) {
                        roscaManager.text = picked;
                      } else {
                        names.add(picked);
                        peopleValues[field.label] = names;
                      }
                    });
                    if (controllers.containsKey('إجمالي المساهمة')) {
                      _autoSplitShares(
                        totalText: controllers['إجمالي المساهمة']!.text,
                        people: _roscaPeople(controllers, peopleValues),
                        selectValues: selectValues,
                        splitValues: splitValues,
                        splitControllers: splitControllers,
                      );
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.field,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Icon(
                        Icons.person_add_alt_1_outlined,
                        size: 19,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          needsTotal
                              ? 'أدخل إجمالي المساهمة على الكل أولًا'
                              : needsManager
                              ? 'اختر المسؤول أولًا — من الأفراد أو بالرقم التعريفي'
                              : 'إضافة عضو — من الأفراد أو بالرقم التعريفي',
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.add_circle_rounded,
                        size: 21,
                        color: needsTotal ? AppTheme.muted : accent,
                      ),
                    ],
                  ),
                ),
              ),
              if (names.isNotEmpty && !isRosca)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: names
                        .map(
                          (n) => Chip(
                            label: Text(n, style: const TextStyle(fontSize: 11)),
                            onDeleted: () => setSheetState(() {
                              setFieldState(() {
                                names.remove(n);
                                peopleValues[field.label] = names;
                              });
                              splitValues.remove(n);
                              if (controllers.containsKey('إجمالي المساهمة')) {
                                _autoSplitShares(
                                  totalText:
                                      controllers['إجمالي المساهمة']!.text,
                                  people: _roscaPeople(controllers, peopleValues),
                                  selectValues: selectValues,
                                  splitValues: splitValues,
                                  splitControllers: splitControllers,
                                );
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (field.required && names.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('أضف عضوًا واحدًا على الأقل', style: TextStyle(fontSize: 10, color: Color(0xFFA82F26))),
                ),
            ],
          ),
        );
        }
      case _SharedFieldKind.date:
        final controller = controllers[field.label]!;
        return TextFormField(
          controller: controller,
          readOnly: true,
          // التاريخ الاختياري يُمسح بزر × بعد اختياره.
          decoration: _sharedFieldDecoration(labelText, field.icon, accent, optional: field.optional).copyWith(
            suffixIcon: field.required
                ? null
                : clearDateSuffix(controller, onCleared: () => setSheetState(() {})),
          ),
          validator: trValidator(field.required ? (v) => v == null || v.isEmpty ? 'مطلوب' : null : null),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (pickerContext, child) => Directionality(textDirection: AppTr.uiDir, child: child!));
            if (picked == null) return;
            controller.text = '${picked.day}/${picked.month}/${picked.year}';
            setSheetState(() {});
          },
        );
      case _SharedFieldKind.multiline:
        return TextFormField(
          controller: controllers[field.label],
          maxLines: 3,
          decoration: _sharedFieldDecoration(labelText, field.icon, accent, optional: field.optional),
        );
      case _SharedFieldKind.number:
        return TextFormField(
          controller: controllers[field.label],
          keyboardType: TextInputType.number,
          onChanged: field.label == 'إجمالي المساهمة'
              ? (_) => setSheetState(() {
                  selectValues[_splitManualFlag] = null;
                  _autoSplitShares(
                    totalText: controllers[field.label]?.text ?? '',
                    people: _roscaPeople(controllers, peopleValues),
                    selectValues: selectValues,
                    splitValues: splitValues,
                    splitControllers: splitControllers,
                  );
                })
              : null,
          decoration: _sharedFieldDecoration(labelText, field.icon, accent, optional: field.optional),
          validator: trValidator(field.required ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null : null),
        );
      case _SharedFieldKind.text:
        return TextFormField(
          controller: controllers[field.label],
          decoration: field.hint.isEmpty
              ? _sharedFieldDecoration(labelText, field.icon, accent, optional: field.optional)
              : _sharedFieldDecoration(
                  labelText,
                  field.icon,
                  accent,
                  optional: field.optional,
                ).copyWith(
                  hintText: AppTr.tr(field.hint),
                  hintStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
          validator: trValidator(field.required ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null : null),
        );
    }
}

/// نموذج «المتابعة والتخطيط» نفسه الموجود في الالتزامات المشتركة (العنوان،
/// الوصف، التاريخ والوقت، التذكير، ملاحظات، إرفاق مستند) — يُستعمل في
/// العقارات والأنشطة والمركبات أيضًا ليكون الإدخال واحدًا في التطبيق.
/// يعيد القيم المدخلة، أو null عند الإغلاق.
Future<Map<String, String>?> showSharedFollowUpForm(
  BuildContext context, {
  required String kind,
  required Color color,
  Map<String, String> initial = const {},
}) async {
  final c = <String, TextEditingController>{
    'title': TextEditingController(text: initial['العنوان'] ?? ''),
    'desc': TextEditingController(text: initial['الوصف'] ?? ''),
    'date': TextEditingController(text: initial['التاريخ'] ?? ''),
    'time': TextEditingController(text: initial['الوقت'] ?? ''),
    'repeat': TextEditingController(text: initial['التكرار'] ?? ''),
    'remindTime': TextEditingController(text: initial['وقت التذكير'] ?? ''),
    'notes': TextEditingController(text: initial['ملاحظات'] ?? ''),
  };
  var remind = (initial['تفعيل تذكير'] ?? '') == 'نعم';
  var filePath = initial['المرفق'] ?? '';
  final formKey = GlobalKey<FormState>();
  final icon = switch (kind) {
    'مهمة' => Icons.task_alt_outlined,
    'موعد' => Icons.event_outlined,
    'عادة' || 'عادة يومية' => Icons.repeat_rounded,
    'تذكير' => Icons.notifications_active_outlined,
    _ => Icons.sticky_note_2_outlined,
  };
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        InputDecoration deco(
          String text,
          IconData icon, {
          bool required = false,
          String hint = '',
        }) => _sharedFieldDecoration(
          required ? '$text *' : text,
          icon,
          color,
        ).copyWith(hintText: hint.isEmpty ? null : hint);
        Widget textField(
          String key,
          String text,
          IconData icon, {
          bool required = false,
          int lines = 1,
          String hint = '',
        }) => TextFormField(
          controller: c[key],
          minLines: lines > 1 ? 2 : 1,
          maxLines: lines,
          textDirection: AppTr.uiDir,
          decoration: deco(text, icon, required: required, hint: hint),
          validator: trValidator(required
              ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null
              : null),
        );
        Widget dateField(String key, String text, IconData icon,
            {bool required = false}) => TextFormField(
          controller: c[key],
          readOnly: true,
          decoration: deco(text, icon, required: required).copyWith(
            suffixIcon: required ? null : clearDateSuffix(c[key]!),
          ),
          validator: trValidator(required
              ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null
              : null),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(now.year - 20),
              lastDate: DateTime(now.year + 20),
            );
            if (picked == null) return;
            setSheetState(
              () => c[key]!.text =
                  '${picked.day}/${picked.month}/${picked.year}',
            );
          },
        );
        Widget timeField(String key, String text, IconData icon) =>
            TextFormField(
              controller: c[key],
              readOnly: true,
              decoration: deco(text, icon).copyWith(
                suffixIcon: clearDateSuffix(c[key]!),
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (picked == null) return;
                setSheetState(
                  () => c[key]!.text =
                      '${picked.hour.toString().padLeft(2, '0')}:'
                      '${picked.minute.toString().padLeft(2, '0')}',
                );
              },
            );
        Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
        const gap = SizedBox(height: 12);
        const repeats = ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري'];
        final fields = <Widget>[
          textField('title', 'العنوان', Icons.title_rounded, required: true),
          gap,
          textField(
            'desc',
            'الوصف',
            Icons.description_outlined,
            lines: 3,
            hint: 'أوصف $kind',
          ),
          gap,
          pair(
            dateField('date', 'التاريخ', Icons.event_outlined, required: true),
            timeField('time', 'الوقت', Icons.schedule_rounded),
          ),
          gap,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  size: 20,
                  color: Color(0xFF34A894),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'تفعيل تذكير',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C2C29),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: remind,
                  activeThumbColor: const Color(0xFF0E7161),
                  onChanged: (value) => setSheetState(() => remind = value),
                ),
              ],
            ),
          ),
          if (remind) ...[
            gap,
            // وقت التذكير يمينًا (كم قبل الموعد) ثم التكرار مع «مخصص».
            pair(
              ReminderLeadField(
                controller: c['remindTime']!,
                decoration: deco('وقت التذكير', Icons.alarm_rounded),
              ),
              CustomOptionField(
                controller: c['repeat']!,
                options: repeats,
                decoration: deco('التكرار', Icons.repeat_rounded),
                customHint: 'مثال: كل 3 أيام',
              ),
            ),
          ],
          gap,
          textField('notes', 'ملاحظات', Icons.notes_rounded, lines: 3),
          gap,
          _receiptButton(
            label: 'إرفاق مستند',
            path: filePath,
            accent: color,
            onTap: () async {
              final path = await _pickReceiptFile(context);
              if (path == null) return;
              setSheetState(() => filePath = path);
            },
            onRemove: () => setSheetState(() => filePath = ''),
          ),
        ];
        return Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.92,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.rCard),
                ),
              ),
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
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  initial.isEmpty ? 'إضافة $kind' : 'تعديل $kind',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF022E2A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'متابعة وتخطيط ضمن هذا الالتزام',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5C6B68),
                                    fontWeight: FontWeight.w600,
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
                      _sharedFormSectionTitle(
                        'الحقول الأساسية',
                        Icons.edit_note_rounded,
                      ),
                      const SizedBox(height: 12),
                      ...fields,
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          final confirmed = await confirmAction(
                            sheetContext,
                            title: 'تأكيد الحفظ',
                            message: 'هل تريد حفظ $kind؟',
                            confirmLabel: 'تأكيد',
                          );
                          if (!confirmed || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext, true);
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          'حفظ $kind',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.rField,
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
    ),
  );
  String v(String key) => c[key]!.text.trim();
  final result = saved == true
      ? <String, String>{
          'العنوان': v('title'),
          'الوصف': v('desc'),
          'التاريخ': v('date'),
          'الوقت': v('time'),
          'تفعيل تذكير': remind ? 'نعم' : '',
          'التكرار': remind ? v('repeat') : '',
          'وقت التذكير': remind ? v('remindTime') : '',
          'ملاحظات': v('notes'),
          'المرفق': filePath,
        }
      : null;
  for (final controller in c.values) {
    Future.delayed(const Duration(milliseconds: 600), controller.dispose);
  }
  return result;
}

InputDecoration _sharedFieldDecoration(
  String label,
  IconData icon,
  Color accent, {
  bool optional = false,
}) => InputDecoration(
  // العنوان يلتف على سطرين عند اللزوم («إجمالي المساهمة») بدل قصّه،
  // ونجمة الإلزامي ظاهرة دائمًا بجانبه حتى لو طال العنوان.
  label: label.endsWith(' *')
      ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label.substring(0, label.length - 2),
                maxLines: 2,
                softWrap: true,
                textAlign: TextAlign.right,
              ),
            ),
            const Text(
              ' *',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        )
      : Text(
          label,
          maxLines: 2,
          softWrap: true,
          textAlign: TextAlign.right,
        ),
  // «(اختياري)» سطر صغير تحت الحقل بدل إلصاقه بالعنوان فيقصّه.
  helperText: optional ? '(اختياري)' : null,
  helperStyle: const TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppTheme.muted,
  ),
  // خط أصغر وحيّز أيقونة أضيق ليظهر كل عنوان كاملًا.
  isDense: true,
  labelStyle: const TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: AppTheme.muted,
  ),
  floatingLabelStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: accent,
  ),
  prefixIcon: Icon(icon, size: 18, color: AppTheme.muted),
  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent, width: 1.5)),
);

Widget _sharedFormSectionTitle(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 19, color: const Color(0xFF0E7161)),
      const SizedBox(width: 7),
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1C2C29))),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: Color(0xFFE4EAE8))),
    ],
  );
}

// ============================================================================
// عناصر بيانات مركز المتابعة
// ============================================================================
class _SharedCommitmentItemRef {
  final _SharedItem item;

  /// مبلغ يُعرض بدل مبلغ الالتزام (مبلغي في «مبالغ لي / عليّ»).
  final String? amountText;

  /// المكان الذي يُفتح عند الضغط: التبويب، و1 للأرصدة في الحركة المالية.
  final int tab;
  final int ledger;
  const _SharedCommitmentItemRef(
    this.item, [
    this.amountText,
    this.tab = 0,
    this.ledger = 0,
  ]);
}

class _SharedFollowUpSubMetric {
  final String label;
  final IconData icon;
  final List<_SharedCommitmentItemRef> items;
  const _SharedFollowUpSubMetric({required this.label, required this.icon, required this.items});
  int get count => items.length;
}

class _SharedFollowUpGroupData {
  final String title;
  final IconData icon;
  final Color color;
  final List<_SharedFollowUpSubMetric> metrics;
  const _SharedFollowUpGroupData({required this.title, required this.icon, required this.color, required this.metrics});
  int get total => metrics.fold(0, (sum, m) => sum + m.count);
}
class _SharedUnifiedCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  /// زر + في رأس البطاقة — كل تبويب له عنوان وخط تحته وزر إضافة.
  final VoidCallback? onAdd;

  const _SharedUnifiedCard({required this.title, required this.icon, required this.color, required this.children, this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            title: title,
            icon: icon,
            accent: color,
            onAdd: onAdd,
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

// نفس _UnifiedInfoRow في الشخصية: أيقونة + تسمية + قيمة، مفصولة بخط سفلي
// رفيع بدل صندوق منفصل لكل عنصر.
class _SharedInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _SharedInfoRow({required this.label, required this.value, required this.icon, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF2F6F5)))),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF8C9A97)),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF5C6B68), fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: AppTr.uiDir,
              style: TextStyle(color: valueColor ?? const Color(0xFF1C2C29), fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// نفس _TimelineEntry في الشخصية: أيقونة دائرية + عنوان/عنوان فرعي، تُستخدم
// في صفوف السجل الزمني بدل صناديق منفصلة لكل عملية.
class _SharedTimelineEntry extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SharedTimelineEntry({required this.title, required this.subtitle, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1C2C29))),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF5C6B68))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// بطاقة نوع الالتزام في صندوق "اختيار نوع الإضافة" — نفس تصميم
// _EntryCategoryCard في الشخصية (المرجع الأساسي للتصميم) بلا شارة العدد
// لأن كل بطاقة هنا تمثل نوعًا واحدًا مباشرة وليست فئة تحوي أنواعًا فرعية.
class _SharedTypeCard extends StatelessWidget {
  final _SharedForm form;
  final VoidCallback onTap;

  const _SharedTypeCard({required this.form, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      // نفس مقاسات بطاقات «اختيار نوع الإضافة» في الالتزامات الشخصية.
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: form.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(form.icon, color: form.color, size: 30),
              ),
              const SizedBox(height: 9),
              Text(
                twoLineLabel(form.label),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                form.subtitle,
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

/// يومض بهدوء (يخفت ويعود) ليلفت النظر.
class _BlinkingBox extends StatefulWidget {
  const _BlinkingBox({required this.child});
  final Widget child;

  @override
  State<_BlinkingBox> createState() => _BlinkingBoxState();
}

class _BlinkingBoxState extends State<_BlinkingBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
    child: widget.child,
  );
}

class _SharedCategoryTab extends StatelessWidget {
  const _SharedCategoryTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // شريحة الفئة الموحّدة في كل التطبيق — بلا عدّاد داخلها: العدد يظهر
    // في رأس القائمة أسفلها فقط.
    return AppCategoryChip(
      label: twoLineLabel(label),
      count: count,
      icon: icon,
      color: color,
      selected: selected,
      onTap: onTap,
    );
  }
}

// شكل الصندوق الخارجي مطابق لملف المتطلبات (الصورة المرفقة تمامًا): اسم
// الالتزام أعلى الصف اليمين ونوعه تحته، وفي صف اليسار "الميزانية/المبلغ"
// أعلى ثم التاريخ تحته، مع سهم تصفّح عند الحافة القائدة (يسار الصندوق في
// RTL) في مكان مربّع المبلغ القديم — بدل التصميم السابق (سطر واحد مدمج
// للنوع/الأعضاء/التاريخ، ومربّع المبلغ+الحالة على اليسار).
class _SharedCommitmentCard extends StatelessWidget {
  const _SharedCommitmentCard({required this.item, required this.onTap});
  final _SharedItem item;
  final VoidCallback onTap;

  Widget _statePill() {
    final archived = _archivedForMe(item);
    final awaiting = _awaitingStatus(item);
    final (label, color) = archived
        ? ('مؤرشفة', const Color(0xFF8C9A97))
        : awaiting != null && item.status == _sharedStatusActive
        ? (awaiting, const Color(0xFFA6691A))
        : switch (item.status) {
            'مكتملة' => ('مكتملة', const Color(0xFF1E2725)),
            'ملغاة' || 'ملغية' => ('ملغاة', const Color(0xFFC4392E)),
            _ => ('نشطة', const Color(0xFF178F7B)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  String get _amountLabel =>
      item.entryType == 'الرحلة / السفر' ||
          (item.details[_collectMethodKey] ?? '').trim().isNotEmpty
      ? 'الميزانية'
      : 'المبلغ';

  /// «أحمد (FND-XXXX-XXXX)» ← «أحمد».
  static String _plainName(String name) => name
      .replaceAll(RegExp(r'\s*\(FND-[A-Z2-9]{4}-[A-Z2-9]{4}\)'), '')
      .trim();

  /// فوق اسم الالتزام: «بانتظار الموافقة من فلان» لمن أرسل الدعوة،
  /// و«بانتظار قبولك — من فلان» لمن وصلته، وعدد الطلبات المالية المعلّقة.
  String? get _pendingLabel {
    final me = AppIdentity.id;
    final creator = (item.details[_creatorIdKey] ?? '').trim();
    final answered = _SharedCommitmentsScreenState._acceptances(item);
    if (me.isNotEmpty && creator.isNotEmpty && creator != me) {
      final invited = item.members.any(
        (m) => _SharedCommitmentsScreenState._idInMemberName(m.name) == me,
      );
      // الدعوة لي: «بانتظار قبولك» فقط، بلا اسم المرسل.
      if (invited && _inviteStateOf(item, me) == 'pending') {
        return AppTr.tr('بانتظار قبولك');
      }
    }
    if (me.isNotEmpty && creator == me) {
      final waiting = [
        for (final m in item.members)
          if (_SharedCommitmentsScreenState._idInMemberName(m.name)
              case final id?)
            if (id != me && _inviteStateOf(item, id) == 'pending')
              _plainName(m.name),
      ];
      if (waiting.isNotEmpty) {
        return '${AppTr.tr('بانتظار الموافقة من')} ${waiting.join('، ')}';
      }
    }
    final requests = item.pendingApprovalsCount;
    if (requests > 0) {
      return '${AppTr.tr('طلبات بانتظار الموافقة')} ($requests)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingLabel;
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
                Flexible(
                  child: Text(
                    pending,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFA6691A),
                    ),
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
    // بطاقة القائمة الموحَّدة نفسها المستعملة في الالتزامات الشخصية
    // وإدارة الأشخاص.
    // الرحلة: نوع التحصيل ظاهر تحت الاسم (دفعة مقطوعة / دفع فردي).
    final method = (item.details[_collectMethodKey] ?? '').trim();
    // النوع في سطر وطريقة التحصيل تحته — كاملة بلا «دفعة مقط…».
    final subtitle = method.isEmpty
        ? _sharedTypeDisplay(item.entryType)
        : '${_sharedTypeDisplay(item.entryType)}\n$method';
    return AppEntityCard(
      icon: item.icon,
      iconColor: item.color,
      title: item.title,
      subtitle: subtitle,
      statusColor: _sharedStatusColor(
        _archivedForMe(item) ? _sharedStatusArchived : item.status,
      ),
      // خانتان ثابتتان: المبلغ في السطر الأول (أو فراغ)، والتاريخ دائمًا
      // على مستوى السطر الثاني.
      keepStatSlots: true,
      subtitleMaxLines: 2,
      // كل قيمة يسارًا في سطر واحد (يصغر الخط إن طالت): الحالة ثم المبلغ
      // ثم التاريخ — ثلاثة أسطر كالاسم والنوع وطريقة التحصيل يمينًا.
      statsSingleLine: true,
      // الحالة بلونها فوق المبلغ: نشطة أخضر، مكتملة أزرق، مؤرشفة رمادي.
      statsHeader: _statePill(),
      stats: [
        item.amount > 0 ? '$_amountLabel : ${item.amount} ${item.currency}' : '',
        item.dueDate.isNotEmpty ? 'التاريخ : ${item.dueDate}' : '',
      ],
      onTap: onTap,
    );
  }
}

// ============================================================================
// عناصر بسيطة قابلة لإعادة الاستخدام لأقسام (متابعة وتخطيط / مستندات /
// مواقع وأماكن): كل قسم قائمة عناصر {kind, title, note, date} مخزّنة كـJSON
// داخل details تحت مفتاح خاص بالقسم — بلا حاجة لثلاث بنى بيانات منفصلة.
class _SimpleEntry {
  final String kind;
  final String title;
  final String note;
  final String date;

  /// بقية الحقول (الوصف، الوقت، التذكير، رقم المستند، الرابط، المرفق...).
  final Map<String, String> extra;
  const _SimpleEntry({
    required this.kind,
    required this.title,
    this.note = '',
    this.date = '',
    this.extra = const {},
  });

  Map<String, dynamic> toMap() => {
    'kind': kind,
    'title': title,
    'note': note,
    'date': date,
    if (extra.isNotEmpty) 'extra': extra,
  };
  factory _SimpleEntry.fromMap(Map map) => _SimpleEntry(
    kind: map['kind']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    note: map['note']?.toString() ?? '',
    date: map['date']?.toString() ?? '',
    extra: map['extra'] is Map
        ? (map['extra'] as Map).map((k, v) => MapEntry('$k', '$v'))
        : const {},
  );
}

List<_SimpleEntry> _parseSimpleEntries(Map<String, String> details, String key) {
  final raw = details[key];
  if (raw == null || raw.trim().isEmpty) return <_SimpleEntry>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <_SimpleEntry>[];
    return decoded.whereType<Map>().map((e) => _SimpleEntry.fromMap(e)).toList();
  } catch (_) {
    return <_SimpleEntry>[];
  }
}

String _encodeSimpleEntries(List<_SimpleEntry> list) => jsonEncode(list.map((e) => e.toMap()).toList());

const _followUpDetailsKey = 'متابعة وتخطيط';
const _documentsDetailsKey = 'مستندات';
const _placesDetailsKey = 'مواقع وأماكن';

// «تفويض» و«الإجراءات» أُلغيت من الإضافة.
const _followUpKinds = ['مهمة', 'موعد', 'عادة', 'تذكير', 'ملاحظات'];
const _documentKinds = ['مستند عام', 'وثائق شخصية'];
const _placeKinds = ['موقع', 'رابط موقع'];

// ============================================================================
// شاشة تفاصيل الالتزام المشترك — 7 تبويبات مطابقة للملف.
// ============================================================================
class SharedCommitmentDetailsScreen extends StatefulWidget {
  const SharedCommitmentDetailsScreen({
    super.key,
    required this.item,
    required this.repository,
    required this.onChanged,
    required this.onDeleted,
    this.initialTab = 0,
    this.initialLedgerView = 0,
  });

  /// يُفتح على تبويب بعينه (من مركز المتابعة مثلًا)، و1 للأرصدة.
  final int initialTab;
  final int initialLedgerView;

  final _SharedItem item;
  final SharedEntriesRepository repository;
  final ValueChanged<_SharedItem> onChanged;
  final ValueChanged<String> onDeleted;

  @override
  State<SharedCommitmentDetailsScreen> createState() => _SharedCommitmentDetailsScreenState();
}

class _SharedCommitmentDetailsScreenState extends State<SharedCommitmentDetailsScreen> {
  late _SharedItem item;
  int _tabIndex = 0;

  /// أي المستطيلين مفتوح في «الحركات المالية»: 0 المصروفات، 1 الأرصدة.
  int _ledgerView = 0;

  /// نموذج المصروف مفتوح داخل التبويب — يحجب المستطيلين حتى يُغلق.
  bool _expenseFormOpen = false;

  /// سهم الفلتر في المتابعة والتخطيط: الكل / مهمة / موعد / عادة / تذكير /
  /// ملاحظات.
  String _followUpKindFilter = 'الكل';

  /// فلتر حالة المتابعة: الأحدث أولاً، نشطة، قريبًا، حان وقتها، متأخرة.
  String _followUpStatusFilter = followStatusFilterOptions.first;

  /// فلتر فئة المصروفات: «الكل» أو إحدى الفئات.
  String _expenseCategoryFilter = 'الكل';

  /// فلتر «من دفع» في المصروفات — فارغ يعني الجميع.
  String _expensePayerFilter = '';

  /// فلتر حالة المصروف وترتيبه.
  String _expenseStatusFilter = 'الكل';
  String _expenseSort = _expenseSorts.first;

  /// نص البحث في تبويب الأعضاء.
  String _memberQuery = '';

  /// موضع زر «+ إضافة» العائم في الملخص بعد سحبه — فارغ = أسفل اليمين.
  Offset? _summaryFabOffset;

  /// دفعة مقطوعة أم دفع فردي — من اختيار النموذج، وإلا من وجود ميزانية.
  /// هل يحتاج مصروف العضو موافقة المسؤول؟ يُلغى فقط مع «دفعة مقطوعة».
  bool get _expenseNeedsApproval =>
      !_isLumpSum ||
      (item.details[_expenseApprovalKey] ?? '').trim() != _approvalNo;

  bool get _isLumpSum {
    final method = (item.details[_collectMethodKey] ?? '').trim();
    if (method.isNotEmpty) return method == _collectLumpSum;
    return SharedLedger.hasBudget(item.details);
  }

  /// هل صاحب هذا الجهاز هو مسؤول الرحلة؟ يُطابَق اسم المسؤول مع الاسم
  /// المسجّل في الملف الشخصي، فإضافة الأعضاء له وحده.
  bool get _isManagerHere {
    // من أنشأ الالتزام من هذا الجهاز يديره.
    final creator = (item.details[_creatorIdKey] ?? '').trim();
    if (creator.isNotEmpty && creator == AppIdentity.id) return true;
    var manager = '';
    for (final member in item.members) {
      if (member.role == 'مسؤول') {
        manager = member.name.trim();
        break;
      }
    }
    if (manager.isEmpty) {
      manager = (item.details[_tripManagerKey] ??
              item.details[_sharedManagerKey] ??
              '')
          .trim();
    }
    // المسؤول المسجّل برقمه التعريفي: يُطابَق بالرقم لا بالاسم.
    final managerId = RegExp(
      r'FND-[A-Z2-9]{4}-[A-Z2-9]{4}',
    ).firstMatch(manager)?.group(0);
    if (managerId != null) return managerId == AppIdentity.id;
    // المنشئ معروف وليس أنا، والمسؤول بلا رقم: لا يكفي تشابه الاسم.
    if (creator.isNotEmpty) return false;
    if (manager.isEmpty) return true;
    return AppSettings.instance.isMyName(manager);
  }

  /// اسم مسؤول الالتزام لرسالة من لا يملك الإضافة.
  String get _managerName {
    for (final member in item.members) {
      if (member.role == 'مسؤول') return member.name.trim();
    }
    return (item.details[_tripManagerKey] ??
            item.details[_sharedManagerKey] ??
            '')
        .trim();
  }
  // الجمعية المالية منطقها مختلف عن بقية الالتزامات: لا مصروفات متفرقة
  // يدفعها من حضر، بل مساهمة ثابتة متكررة ودور استلام. فيحلّ تبويب
  // «الدورات والمساهمات» محلّ «المصروفات والأرصدة» فيها وحدها.
  bool get _isRosca => _sharedCanonicalType(item.entryType) == 'جمعية مالية';

  // تبويب «الميزانية» حُذف: مصروفاته هي نفسها مصروفات الحركة المالية،
  // فكان يعرض الشيء مرتين بمنطقين مختلفين.
  List<String> get _tabs => [
    'الملخص',
    _isRosca ? 'المساهمات والاستحقاقات' : 'الحركة المالية',
    'المتابعة والتخطيط',
    'الأعضاء',
    'مستندات',
    'مواقع وأماكن',
    'السجل',
  ];

  List<IconData> get _tabIcons => [
    Icons.summarize_outlined,
    _isRosca ? Icons.autorenew_rounded : Icons.receipt_long_outlined,
    Icons.fact_check_outlined,
    Icons.groups_outlined,
    Icons.description_outlined,
    Icons.place_outlined,
    Icons.history_rounded,
  ];

  @override
  void initState() {
    super.initState();
    item = widget.item;
    _tabIndex = widget.initialTab.clamp(0, 6);
    _ledgerView = widget.initialLedgerView.clamp(0, 1);
    // التزام انتهى قبل هذا التحديث (سُوّي حسابه) يُصحَّح إلى «مكتملة».
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncStatus());
  }

  /// «مكتملة» للالتزام كله حين ينتهي فعلًا: الحساب مسوّى بالكامل بعد تسوية
  /// مسجّلة، أو كل دورات الجمعية جُمعت وسُلِّمت. ويعود «نشطة» إن أُضيف
  /// بعدها ما يفتحه من جديد. المؤرشف والملغى لا يُمسّان.
  String _resolvedStatus(Map<String, String> details, String base) {
    if (base != _sharedStatusActive && base != _sharedStatusCompleted) {
      return base;
    }
    final members = _ledgerMembers;
    final bool done;
    if (_isRosca) {
      final plan = RoscaLedger.plan(details, members);
      done = plan.cycles.isNotEmpty &&
          plan.cycles.every((c) => c.isComplete && c.isPaidOut);
    } else {
      done = SharedLedger.settlements(details).isNotEmpty &&
          SharedLedger.settleTransfers(details, members).isEmpty;
    }
    return done ? _sharedStatusCompleted : _sharedStatusActive;
  }

  /// عند الفتح: تصحيح الحالة بصمت إن اختلفت عمّا يجب.
  Future<void> _syncStatus() async {
    if (!mounted) return;
    final wanted = _resolvedStatus(item.details, item.status);
    if (wanted == item.status) return;
    try {
      final saved = await widget.repository.update(
        SharedEntryRecord(
          id: item.id,
          entryType: item.entryType,
          title: item.title,
          amount: item.amount,
          dueDate: item.dueDate,
          status: wanted,
          details: item.details,
        ),
      );
      final updated = _SharedItem.fromRecord(saved);
      if (!mounted) return;
      setState(() => item = updated);
      widget.onChanged(updated);
    } catch (error) {
      debugPrint('shared status sync failed: $error');
    }
  }

  /// لون مستطيل التفاصيل حين ينتهي الالتزام: مكتملة قريب من الأسود،
  /// وملغاة أحمر داكن — نصوصه بيضاء على الحالتين.
  Color? get _headerTone => switch (_shownStatus) {
    _sharedStatusCompleted => const Color(0xFF1E2725),
    'ملغاة' || 'ملغية' => const Color(0xFF7A1F18),
    _ => null,
  };

  bool get _finished => _headerTone != null;

  bool get _isCancelled =>
      item.status == 'ملغاة' || item.status == 'ملغية';

  /// اسمي كما في أعضاء الالتزام (برقمي أولًا ثم بالاسم).
  String? get _myMemberName {
    final me = AppIdentity.id;
    for (final m in item.members) {
      final name = m.name.trim();
      if (me.isNotEmpty && name.contains('($me)')) return name;
    }
    for (final m in item.members) {
      final name = m.name.trim();
      if (name.isNotEmpty && AppSettings.instance.isMyName(name)) return name;
    }
    return null;
  }

  /// حساب لم يُسوَّ: مبالغ معلّقة بين الأعضاء أو في الميزانية، وفي تحديد
  /// الأدوار: دورات بدأت ولم تكتمل وتُسلَّم كلها.
  bool get _hasUnsettled {
    if (_isRosca) {
      final cycles = _roscaPlan.cycles;
      final started = cycles.any((c) => c.collected > 0.01 || c.isPaidOut);
      final finished =
          cycles.isNotEmpty && cycles.every((c) => c.isComplete && c.isPaidOut);
      return started && !finished;
    }
    return SharedLedger.settleTransfers(item.details, _ledgerMembers).isNotEmpty;
  }

  /// لا حذف ولا أرشفة قبل التسوية: نافذة بزر «تسوية الحساب».
  Future<void> _blockUnsettled(String action) async {
    final settle = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: AppTheme.page,
          icon: const Icon(
            Icons.handshake_outlined,
            size: 32,
            color: AppTheme.goldDark,
          ),
          title: Text(
            '${AppTr.tr('لا يمكن')} ${AppTr.tr(action)} '
            '${AppTr.tr('قبل تسوية الحساب')}',
            textAlign: TextAlign.center,
          ),
          content: Text(
            _isRosca
                ? 'دورات تحديد الأدوار بدأت ولم تكتمل وتُسلَّم كلها بعد.'
                : 'توجد مبالغ معلّقة بين الأعضاء أو في الميزانية المشتركة. '
                      'سوِّ الحساب أولًا ثم احذف أو أرشف.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            if (!_isRosca)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: item.color),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('تسوية الحساب'),
              ),
          ],
        ),
      ),
    );
    if (settle == true && mounted) await _openSettleUpSheet();
  }

  bool get _inHistoryHere =>
      SharedMemberState.hasMine(item.details, SharedMemberState.historyKey);

  /// لم تتم التسوية: لا يُمسح. ينتقل إلى «السجل التاريخي» للمتابعة لاحقًا
  /// حفظًا لحقوق الأعضاء — أو يسوّي الحساب الآن. يعيد true إن نُقل.
  Future<bool> _moveToHistoryInstead() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: AppTheme.page,
          icon: const Icon(
            Icons.history_edu_outlined,
            size: 32,
            color: AppTheme.goldDark,
          ),
          title: const Text(
            'لم تتم تسوية الحساب',
            textAlign: TextAlign.center,
          ),
          content: Text(
            '⚠️ ${AppTr.tr('ما لم تتم تسويته لا يُمسح')}. '
            '${AppTr.tr('سينتقل')} «${item.title}» '
            '${AppTr.tr('إلى «السجل التاريخي» للمتابعة لاحقًا، حفظًا لحقوق الأعضاء')}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            if (!_isRosca)
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext, 'settle'),
                child: const Text('تسوية الحساب'),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.goldDark,
              ),
              onPressed: () => Navigator.pop(dialogContext, 'history'),
              child: const Text('نقله للسجل التاريخي'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return false;
    if (choice == 'settle') {
      await _openSettleUpSheet();
      return false;
    }
    final messenger = ScaffoldMessenger.of(context);
    final title = item.title;
    try {
      final saved = await SharedMemberState.markMine(
        widget.repository,
        _recordOf(item),
        SharedMemberState.historyKey,
        add: true,
      );
      if (!mounted) return false;
      if (saved != null) widget.onChanged(_SharedItem.fromRecord(saved));
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${AppTr.tr('نُقل')} «$title» '
            '${AppTr.tr('إلى «السجل التاريخي» — تجده أسفل قائمة الالتزامات المشتركة')}',
          ),
        ),
      );
      return true;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ. حاول مرة أخرى.')),
      );
      return false;
    }
  }

  /// في السجل التاريخي: شريط يوضح ذلك ويعيده إلى القائمة.
  Widget _buildHistoryBanner() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppTheme.goldSoft,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
    ),
    child: Row(
      textDirection: AppTr.uiDir,
      children: [
        const Icon(
          Icons.history_edu_outlined,
          size: 18,
          color: AppTheme.goldDark,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'في السجل التاريخي — لم تتم التسوية',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.goldDark,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            final saved = await SharedMemberState.markMine(
              widget.repository,
              _recordOf(item),
              SharedMemberState.historyKey,
              add: false,
            );
            if (!mounted || saved == null) return;
            final updated = _SharedItem.fromRecord(saved);
            setState(() => item = updated);
            widget.onChanged(updated);
          },
          child: const Text(
            'إعادة للقائمة',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  /// حذف المسؤول: لا يُحذف إلا بعد التسوية، مع سبب، ونصيحة الأرشفة
  /// للحفاظ على التقارير. مع أعضاء آخرين يُلغى عندهم ويُحذف نهائيًا بعد
  /// موافقتهم جميعًا؛ ووحده ينتقل إلى سلة المهملات.
  Future<void> _deleteFlow() async {
    // ملغى: «موافق على الحذف» لأي عضو.
    if (_isCancelled && !_isManagerHere) {
      await _approveCancelledDelete();
      return;
    }
    if (!_isManagerHere) {
      await _leaveCommitment();
      return;
    }
    // لم تتم التسوية: لا يُمسح — ينتقل للسجل التاريخي.
    if (_hasUnsettled) {
      await _moveToHistoryInstead();
      return;
    }
    final shared = SharedMemberState.sharedWithOthers(item.details);
    final reason = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Directionality(
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            backgroundColor: AppTheme.page,
            title: const Text('حذف الالتزام', textAlign: TextAlign.center),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.goldSoft,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                    ),
                    child: Text(
                      '⚠️ ${AppTr.tr('أرشف لكي تحافظ على تقاريرك، الحذف يفقدك المعلومات')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.goldDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    shared
                        ? 'سيُلغى «${item.title}» عند بقية الأعضاء ويصلهم إشعار، '
                              'ويُحذف نهائيًا بعد موافقتهم جميعًا.'
                        : 'سينتقل «${item.title}» إلى سلة المهملات، ويمكنك '
                              'استعادته منها.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: AppTr.tr('سبب الحذف *'),
                      filled: true,
                      fillColor: AppTheme.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'archive'),
                icon: const Icon(Icons.archive_outlined, size: 17),
                label: const Text('أرشفة'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA82F26),
                ),
                onPressed: reason.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, 'delete'),
                child: const Text('حذف'),
              ),
            ],
          ),
        ),
      ),
    );
    final why = reason.text.trim();
    if (!mounted || choice == null) return;
    if (choice == 'archive') {
      await _archiveCommitment();
      return;
    }
    final title = item.title;
    final messenger = ScaffoldMessenger.of(context);
    if (shared) {
      // ملغى عند الجميع بسببه، ثم من عندي.
      final me = _myMemberName ?? AppSettings.instance.publicName;
      final details = _withEvent(
        Map<String, String>.of(item.details)..[_cancelReasonKey] = why,
        '${_shownName(me)} ${AppTr.tr('ألغى الالتزام')}: $why',
      );
      final ok = await _persist(details, status: 'ملغاة');
      if (!ok || !mounted) return;
    }
    try {
      await SharedMemberState.markMine(
        widget.repository,
        _recordOf(item),
        SharedMemberState.removedKey,
        add: true,
      );
      if (!mounted) return;
      widget.onDeleted(item.id);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            shared
                ? 'أُلغي «$title» عند الأعضاء، ويُحذف نهائيًا بعد موافقتهم'
                : 'نُقل «$title» إلى سلة المهملات',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر حذف الالتزام. حاول مرة أخرى.')),
      );
    }
  }

  /// عضو يوافق على حذف ما ألغاه المسؤول: يُحذف من عنده.
  Future<void> _approveCancelledDelete() async {
    if (_hasUnsettled) {
      await _moveToHistoryInstead();
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'موافق على الحذف',
      message: 'سيُحذف «${item.title}» من عندك وينتقل إلى سلة المهملات. '
          'الأرشفة تحافظ عليه في تقاريرك.',
      confirmLabel: 'موافق',
      danger: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final title = item.title;
    try {
      await SharedMemberState.markMine(
        widget.repository,
        _recordOf(item),
        SharedMemberState.removedKey,
        add: true,
      );
      if (!mounted) return;
      widget.onDeleted(item.id);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم حذف «$title» من عندك'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ. حاول مرة أخرى.')),
      );
    }
  }

  /// «مغادرة المشاركة» للعضو: بعد تسوية حسابه، ويصل الأعضاء إشعار.
  Future<void> _leaveCommitment() async {
    // بقي فيه حساب لم يُسوَّ: لا يُمسح — ينتقل للسجل التاريخي.
    final me = _myMemberName;
    final myOpen = _isRosca
        ? _hasUnsettled
        : me != null &&
              SharedLedger.memberNet(item.details, me).abs() > 0.01;
    if (myOpen) {
      await _moveToHistoryInstead();
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'مغادرة المشاركة',
      message: 'هل تريد مغادرة «${item.title}»؟ يصل المسؤول وبقية الأعضاء '
          'إشعار، ويبقى سجلك عندهم.',
      confirmLabel: 'مغادرة',
      danger: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final title = item.title;
    try {
      await SharedMemberState.markMine(
        widget.repository,
        _recordOf(item),
        SharedMemberState.removedKey,
        add: true,
      );
      if (!mounted) return;
      widget.onDeleted(item.id);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('غادرت «$title»'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ. حاول مرة أخرى.')),
      );
    }
  }

  /// الملغى: سببه، و«موافق على الحذف» أو «أرشفة عندي» للأعضاء.
  Widget _buildCancelBanner() {
    final reason = (item.details[_cancelReasonKey] ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ألغى المسؤول هذا الالتزام',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.danger,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${AppTr.tr('السبب')}: $reason',
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.title,
              ),
            ),
          ],
          if (!_isManagerHere) ...[
            const SizedBox(height: 4),
            const Text(
              'وافق على حذفه، أو أرشفه عندك لتحافظ عليه في تقاريرك.',
              style: TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                    ),
                    onPressed: _approveCancelledDelete,
                    child: const Text('موافق على الحذف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _archiveCommitment,
                    icon: const Icon(Icons.archive_outlined, size: 17),
                    label: const Text('أرشفة عندي'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// [done]: رسالة تأكيد تظهر بعد نجاح الحفظ («تمت إضافة مستند»…) — كل
  /// إضافة أو إجراء يُخبر المستخدم أنه تمّ فعلًا.
  Future<bool> _persist(
    Map<String, String> details, {
    String? status,
    String? done,
    String? ask,
  }) async {
    // تأكيد قبل الإجراء إن طُلب، ثم رسالة الإتمام.
    if (ask != null) {
      final confirmed = await confirmAction(
        context,
        title: 'تأكيد',
        message: ask,
        confirmLabel: 'تأكيد',
      );
      if (!confirmed || !mounted) return false;
    }
    final record = SharedEntryRecord(
      id: item.id,
      entryType: item.entryType,
      title: item.title,
      amount: item.amount,
      dueDate: item.dueDate,
      status: _resolvedStatus(details, status ?? item.status),
      details: details,
    );
    // كل نداءات الحفظ الفرعية (عملية مالية، عضو، متابعة، مستند، موقع) تمرّ
    // من هنا، وكانت بلا أي معالجة خطأ: فشل الشبكة أو صلاحيات RLS يرمي
    // استثناءً غير مُلتقَط بينما تكون النافذة قد أُغلقت ورسالة النجاح قد
    // ظهرت — فيظن المستخدم أن العملية سُجّلت وهي لم تُكتب إطلاقًا.
    try {
      final saved = await widget.repository.update(record);
      final updated = _SharedItem.fromRecord(saved);
      if (!mounted) return true;
      final before = sharedSpentPercent(item.details);
      setState(() => item = updated);
      widget.onChanged(updated);
      // بلوغ نسبة التنبيه المختارة من الميزانية — مرة عند تجاوزها.
      final limit = sharedBudgetAlertPercent(updated.details);
      final after = sharedSpentPercent(updated.details);
      if (limit > 0 && before + 0.001 < limit && after + 0.001 >= limit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.danger,
            content: Text(
              '${AppTr.tr('الميزانية')} «${updated.title}»: '
              '${AppTr.tr('صُرف')} ${after.round()}% '
              '${AppTr.tr('من قيمتها')}',
            ),
          ),
        );
      }
      if (done != null) {
        _notify(
          done.contains('بنجاح') || done.startsWith('أُرسل')
              ? done
              : '$done بنجاح',
        );
      }
      return true;
    } catch (error) {
      debugPrint('shared commitment persist failed: $error');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  // ---------------- حالة دعوات الأعضاء ----------------

  /// الأعضاء المدعوون بأرقامهم (بلا المنشئ): (الاسم الظاهر، الرقم).
  List<(String, String)> get _invitedMembers {
    final creator = (item.details[_creatorIdKey] ?? '').trim();
    return [
      for (final m in item.members)
        if (_SharedCommitmentsScreenState._idInMemberName(m.name)
            case final id?)
          if (id != creator) (_plainName(m.name), id),
    ];
  }

  static String _plainName(String name) => name
      .replaceAll(RegExp(r'\s*\(FND-[A-Z2-9]{4}-[A-Z2-9]{4}\)'), '')
      .trim();

  /// تحت اسم الالتزام: «بانتظار الموافقة — وافق 3 من 10». يختفي حين يوافق
  /// الجميع (صاروا كلهم أعضاء).
  String? _inviteSummary() {
    final invited = _invitedMembers;
    if (invited.isEmpty) return null;
    var accepted = 0;
    var pending = 0;
    for (final (_, id) in invited) {
      final state = _inviteStateOf(item, id);
      if (state == 'accepted') accepted++;
      if (state == 'pending') pending++;
    }
    if (accepted == invited.length) return null;
    final count = '${AppTr.tr('وافق')} $accepted ${AppTr.tr('من')} '
        '${invited.length}';
    return pending > 0
        ? '${AppTr.tr('بانتظار الموافقة')} — $count'
        : '${AppTr.tr('الدعوات')} — $count';
  }

  String _hoursLeft(Duration left) {
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    return hours > 0
        ? '${AppTr.tr('باقي')} $hours ${AppTr.tr('ساعة')}'
        : '${AppTr.tr('باقي')} $minutes ${AppTr.tr('دقيقة')}';
  }

  /// كل عضو وحالته: وافق / بانتظار الموافقة / رفض الدعوة / تأخر بالرد.
  /// والمنشئ يلغي دعوة من تأخر، أو يعيدها لمن انتهت دعوته أو رفض.
  Future<void> _openInviteStatusSheet() async {
    final me = AppIdentity.id;
    final isCreator = me.isNotEmpty &&
        (item.details[_creatorIdKey] ?? '').trim() == me;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final invited = _invitedMembers;
        final answers = _SharedCommitmentsScreenState._acceptances(item);
        return Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                children: [
                  const Text(
                    'حالة الأعضاء',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'صلاحية الدعوة 24 ساعة؛ بعدها تُلغى تلقائيًا ويبقى الاسم '
                    'مكتوبًا بجانبه «تأخر بالرد».',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final (name, id) in invited)
                    Builder(
                      builder: (_) {
                        final state = _inviteStateOf(item, id);
                        final (label, color) = _inviteStateLook(state);
                        final at = (answers[id]?['at'] ?? '').trim();
                        final left = state == 'pending'
                            ? SharedMemberState.inviteRemaining(
                                item.details,
                                id,
                                createdAt: item.createdAt,
                              )
                            : null;
                        final sub = switch (state) {
                          'pending' when left != null => _hoursLeft(left),
                          'accepted' || 'rejected' || 'cancelled'
                              when at.isNotEmpty =>
                            at,
                          'expired' => AppTr.tr('انتهت صلاحية الدعوة'),
                          _ => '',
                        };
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.rField,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isEmpty ? id : name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.title,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (sub.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    sub,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ),
                              if (isCreator &&
                                  (state == 'pending' || state == 'expired'))
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _cancelMemberInvite(id, name);
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.danger,
                                    ),
                                    icon: const Icon(
                                      Icons.block_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('إلغاء الدعوة'),
                                  ),
                                ),
                              if (isCreator &&
                                  (state == 'expired' ||
                                      state == 'cancelled' ||
                                      state == 'rejected'))
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _reinviteMember(id, name);
                                    },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('إعادة الدعوة'),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// المنشئ يلغي دعوة عضو (تأخر بالرد مثلًا): يبقى اسمه مع «أُلغيت دعوته».
  Future<void> _cancelMemberInvite(String id, String name) async {
    final answers = _SharedCommitmentsScreenState._acceptances(item)
      ..[id] = {
        'name': name,
        'state': 'cancelled',
        'at': recordStampNow(),
      };
    await _persist(
      Map<String, String>.of(item.details)
        ..['قبول الأعضاء'] = jsonEncode(answers),
      ask: '${AppTr.tr('إلغاء دعوة')} «$name»؟ '
          '${AppTr.tr('يبقى اسمه مكتوبًا بجانبه «أُلغيت دعوته».')}',
      done: 'أُلغيت الدعوة',
    );
  }

  /// إعادة الدعوة: تُمسح الإجابة السابقة وتبدأ 24 ساعة جديدة.
  Future<void> _reinviteMember(String id, String name) async {
    final answers = _SharedCommitmentsScreenState._acceptances(item)
      ..remove(id);
    final times = SharedMemberState.inviteTimes(item.details)
      ..[id] = DateTime.now().toUtc().toIso8601String();
    await _persist(
      Map<String, String>.of(item.details)
        ..['قبول الأعضاء'] = jsonEncode(answers)
        ..[SharedMemberState.inviteAtKey] = jsonEncode(times),
      ask: '${AppTr.tr('إعادة دعوة')} «$name»؟ '
          '${AppTr.tr('تبدأ صلاحية جديدة 24 ساعة.')}',
      done: 'أُعيدت الدعوة',
    );
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          textDirection: AppTr.uiDir,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  // مطابق تمامًا لـ _handleMenuAction في الشخصية: تعديل/مشاركة/حذف/أرشفة.
  /// كل إجراءات قائمة النقاط الثلاث تمرّ بنافذة تأكيد قبل التنفيذ.
  Future<void> _handleMenuAction(_SharedCommitmentMenuAction action) async {
    // انضمام عضو أو مغادرته بتاريخ: لهما نوافذهما وتأكيدهما.
    if (action == _SharedCommitmentMenuAction.memberJoin) {
      await _memberJoin();
      return;
    }
    if (action == _SharedCommitmentMenuAction.memberLeave) {
      await _memberLeave();
      return;
    }
    if (action == _SharedCommitmentMenuAction.leave) {
      await _leaveCommitment();
      return;
    }
    if (action == _SharedCommitmentMenuAction.delete) {
      await _deleteFlow();
      return;
    }
    // المسؤول لا يؤرشف قبل التسوية.
    if (action == _SharedCommitmentMenuAction.archive &&
        !_archivedForMe(item) &&
        _isManagerHere &&
        _hasUnsettled) {
      await _blockUnsettled('الأرشفة');
      return;
    }
    final title = item.title;
    final (label, message, danger) = switch (action) {
      _SharedCommitmentMenuAction.memberJoin ||
      _SharedCommitmentMenuAction.memberLeave ||
      _SharedCommitmentMenuAction.leave => ('', '', false),
      _SharedCommitmentMenuAction.edit => (
        'تعديل الالتزام',
        'سيُفتح نموذج التعديل لـ«$title». هل تريد المتابعة؟',
        false,
      ),
      _SharedCommitmentMenuAction.share => (
        'مشاركة الالتزام',
        'ستُشارك بيانات «$title» عبر تطبيق تختاره. هل تريد المتابعة؟',
        false,
      ),
      _SharedCommitmentMenuAction.delete =>
        SharedMemberState.sharedWithOthers(item.details)
            ? (
                'حذف الالتزام',
                'هل تريد حذف «$title» من عندك؟ يبقى عند بقية الأعضاء ويصلهم '
                    'إشعار بذلك، ويمكنك استعادته من «المحذوفة عندي».',
                true,
              )
            : (
                'حذف الالتزام',
                'سيُحذف «$title» نهائيًا ولا يمكن التراجع. هل تريد الحذف؟',
                true,
              ),
      _SharedCommitmentMenuAction.archive => _archivedForMe(item)
          ? (
              'إلغاء الأرشفة',
              'سيعود «$title» إلى قائمتك النشطة. هل تريد المتابعة؟',
              false,
            )
          : SharedMemberState.sharedWithOthers(item.details)
          ? (
              'أرشفة الالتزام',
              'هل تريد أرشفة «$title» عندك؟ سيختفي تمامًا من الالتزامات '
                  'المشتركة، وتجده في «الأرشيف» من الشريط السفلي في الصفحة '
                  'الرئيسية. يبقى عند بقية الأعضاء ويصلهم إشعار بذلك.',
              false,
            )
          : (
              'أرشفة الالتزام',
              'سيختفي «$title» تمامًا من الالتزامات المشتركة، وتجده في '
                  '«الأرشيف» من الشريط السفلي في الصفحة الرئيسية، ويمكنك '
                  'إخراجه لاحقًا. هل تريد الأرشفة؟',
              false,
            ),
    };
    final ok = await confirmAction(
      context,
      title: label,
      message: message,
      confirmLabel: danger ? 'حذف' : 'تأكيد',
      danger: danger,
    );
    if (!ok || !mounted) return;
    switch (action) {
      case _SharedCommitmentMenuAction.edit:
        await _openEditForm();
      case _SharedCommitmentMenuAction.share:
        await _shareCommitment();
      case _SharedCommitmentMenuAction.delete:
        await _deleteCommitment();
      case _SharedCommitmentMenuAction.archive:
        await _archiveCommitment();
      case _SharedCommitmentMenuAction.memberJoin:
      case _SharedCommitmentMenuAction.memberLeave:
      case _SharedCommitmentMenuAction.leave:
        break;
    }
  }

  Future<void> _openEditForm() async {
    final form = _sharedEntryForms[item.entryType];
    if (form == null) return;
    await _openSharedEntryForm(
      context,
      widget.repository,
      form,
      editing: item,
      onSaved: (updated, {required isNew}) {
        setState(() => item = updated);
        widget.onChanged(updated);
      },
    );
  }

  /// المشاركة مستند PDF (لا نصًا): بترويسة Fundly أو بدونها.
  Future<void> _shareCommitment() async {
    final letterhead = await askPdfLetterhead(context);
    if (letterhead == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final budget = SharedLedger.hasBudget(item.details);
    final pairs = <(String, String)>[
      ('النوع', pdfSafeText(AppTr.tr(item.entryType))),
      if (item.amount > 0) ('المبلغ', '${item.amount} ${item.currency}'),
      (
        'التاريخ',
        item.dueDate.isEmpty ? pdfSafeText(AppTr.tr('غير محدد')) : item.dueDate,
      ),
      ('الحالة', pdfSafeText(AppTr.tr(item.status))),
      if (_managerName.isNotEmpty)
        ('المسؤول', pdfSafeText(_shownName(_managerName))),
      if (budget)
        ('إجمالي المساهمة', _money(SharedLedger.budget(item.details))),
      if (budget)
        (
          'المتبقي من المساهمة',
          _money(SharedLedger.remaining(item.details)),
        ),
    ];
    final members = [
      for (final m in item.members)
        if (m.name.trim().isNotEmpty)
          [
            pdfSafeText(_shownName(m.name)),
            pdfSafeText(AppTr.tr(m.role)),
            if (budget) _money(_memberMath(m.name).put),
          ],
    ];
    try {
      final bytes = await buildRecordPdf(
        title: pdfSafeText(item.title),
        subtitle: 'SHARED COMMITMENT',
        letterhead: letterhead,
        format: PdfPageFormat.a4,
        sections: [
          PrintSection('البيانات', pairs: pairs),
          if (members.isNotEmpty)
            PrintSection(
              'الأعضاء',
              heads: [
                'العضو',
                'الدور',
                if (budget) 'المساهمة',
              ],
              rows: members,
            ),
        ],
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${pdfSafeText(item.title).isEmpty ? 'Fundly' : pdfSafeText(item.title)}.pdf',
      );
    } catch (error) {
      debugPrint('Shared PDF failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّر تجهيز ملف PDF. حاول مرة أخرى.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// مستند التسوية PDF رسميًا: التحويلات، وإجمالي المساهمة والمتبقي منها،
  /// ومساهمة كل عضو.
  Future<void> _shareSettlementPdf(
    List<SharedTransfer> transfers,
    String date,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final sum = transfers.fold<double>(0, (s, t) => s + t.amount);
    final budget = SharedLedger.hasBudget(item.details);
    try {
      final bytes = await buildRecordPdf(
        title: '${AppTr.tr('تسوية حساب')} — ${pdfSafeText(item.title)}',
        subtitle: 'SETTLEMENT',
        format: PdfPageFormat.a4,
        sections: [
          PrintSection(
            'البيانات',
            pairs: [
              ('الالتزام', pdfSafeText(item.title)),
              ('التاريخ', date),
              ('مجموع التسوية', _money(sum)),
              if (budget)
                ('إجمالي المساهمة', _money(SharedLedger.budget(item.details))),
              if (budget)
                (
                  'المتبقي من المساهمة',
                  _money(SharedLedger.remaining(item.details)),
                ),
            ],
          ),
          if (transfers.isNotEmpty)
            PrintSection(
              'التحويلات',
              heads: const ['من', 'إلى', 'المبلغ'],
              rows: [
                for (final t in transfers)
                  [
                    pdfSafeText(_shownName(t.from)),
                    pdfSafeText(_shownName(t.to)),
                    _money(t.amount),
                  ],
              ],
            ),
          if (budget)
            PrintSection(
              'مساهمة الأعضاء',
              heads: const ['العضو', 'المساهمة', 'نصيبه من المصروفات'],
              rows: [
                for (final name in _ledgerMembers)
                  [
                    pdfSafeText(_shownName(name)),
                    _money(_memberMath(name).put),
                    _money(_memberMath(name).share),
                  ],
              ],
            ),
        ],
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'settlement-${pdfSafeText(item.title)}.pdf',
      );
    } catch (error) {
      debugPrint('Settlement PDF failed: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّر تجهيز ملف PDF. حاول مرة أخرى.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// الأرشفة أصبحت تبديلًا: كانت تُثبّت الحالة على "مؤرشف" بلا أي وسيلة
  /// للتراجع، فيخرج الالتزام نهائيًا من كل الحسابات والقوائم المفتوحة.
  /// الحالة الظاهرة لي: «مؤرشف» إن أرشفته عندي.
  String get _shownStatus =>
      _archivedForMe(item) ? _sharedStatusArchived : item.status;

  Future<void> _archiveCommitment() async {
    // فيه أعضاء آخرون بأرقامهم: الأرشفة عندي وحدي ويصلهم إشعار.
    final mine = SharedMemberState.hasMine(
      item.details,
      SharedMemberState.archivedKey,
    );
    if (mine ||
        (item.status != _sharedStatusArchived &&
            SharedMemberState.sharedWithOthers(item.details))) {
      final title = item.title;
      try {
        final saved = await SharedMemberState.markMine(
          widget.repository,
          _recordOf(item),
          SharedMemberState.archivedKey,
          add: !mine,
        );
        if (!mounted) return;
        if (saved == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لم يعد هذا الالتزام موجودًا')),
          );
          return;
        }
        final updated = _SharedItem.fromRecord(saved);
        setState(() => item = updated);
        widget.onChanged(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              mine
                  ? 'تم إخراج «$title» من أرشيفك'
                  : 'تمت أرشفة «$title» عندك، وأُرسل إشعار لبقية الأعضاء',
            ),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تنفيذ العملية. حاول مرة أخرى.')));
      }
      return;
    }
    final archived = item.status == _sharedStatusArchived;
    final nextStatus = archived ? _sharedStatusActive : _sharedStatusArchived;
    try {
      final ok = await _persist(item.details, status: nextStatus);
      if (!mounted || !ok) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived ? 'تم إخراج الالتزام من الأرشيف' : 'تمت أرشفة الالتزام',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تنفيذ العملية. حاول مرة أخرى.')));
    }
  }

  Future<void> _deleteCommitment() async {
    // فيه أعضاء آخرون بأرقامهم: يُحذف من عندي وحدي (تأكيد القائمة يكفي)،
    // ويبقى عندهم ويصلهم إشعار. آخر من يحذفه يحذفه من الخادم.
    if (SharedMemberState.sharedWithOthers(item.details)) {
      final messenger = ScaffoldMessenger.of(context);
      final title = item.title;
      try {
        await SharedMemberState.markMine(
          widget.repository,
          _recordOf(item),
          SharedMemberState.removedKey,
          add: true,
        );
        if (!mounted) return;
        widget.onDeleted(item.id);
        Navigator.pop(context, true);
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('تم حذف «$title» من عندك، وأُرسل إشعار لبقية الأعضاء'),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('تعذر حذف الالتزام. حاول مرة أخرى.')));
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('حذف الالتزام'),
          content: Text('هل تريد حذف «${item.title}» نهائيًا؟ لا يمكن التراجع عن هذا الإجراء.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F26)),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.delete(item.id);
      if (!mounted) return;
      widget.onDeleted(item.id);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حذف الالتزام. حاول مرة أخرى.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // القالب مطابق تمامًا لـ _buildUnifiedDetails في الشخصية: AppBar بعنوان
    // في المنتصف وسهم رجوع في الترويسة (بدل صف داخلي)، ثم ListView واحد
    // خارجي يحوي: صندوق موحّد واحد (الترويسة المدمجة + خط رفيع + شريط
    // البيانات المميزة)، ثم فاصل مسافة، ثم صف التبويبات، ثم فاصل مسافة،
    // ثم محتوى التبويب المختار — بدل الأعمدة/الصفوف المنفصلة كما كان سابقًا.
    return Scaffold(
      backgroundColor: AppTheme.page,
      // لا زر عائم: الإضافة من زر + في رأس كل تبويب.
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F1F1C),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text(_isRosca ? 'تفاصيل تحديد الأدوار' : 'تفاصيل ${item.entryType}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F1F1C))),
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: ListView(
          key: const ValueKey('shared-compact-details'),
          // مساحة تحت آخر سطر في الملخص حتى لا يغطيه الزر العائم.
          padding: EdgeInsets.fromLTRB(14, 14, 14, _tabIndex == 0 ? 96 : 28),
          children: [
            Container(
              key: const ValueKey('shared-compact-details-header'),
              decoration: BoxDecoration(
            color: _headerTone ?? AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  // التسوية هي ما يفعله المستخدم فعلًا في نهاية الرحلة،
                  // فمكانها المستطيل الأول لا تبويبًا داخليًا.
                  if (!_isRosca) _buildSettleButton(),
                  Container(
                    height: 1,
                    color: _finished
                        ? const Color(0x22FFFFFF)
                        : const Color(0xFFF2F6F5),
                  ),
                  _buildHighlightBar(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_isCancelled) _buildCancelBanner(),
            if (_inHistoryHere) _buildHistoryBanner(),
            _buildTabsRow(),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(_tabIndex), child: _buildTabContent()),
            ),
          ],
        ),
              ),
              // الملخص وحده: زر «+ إضافة» عائم أسفل اليمين، ويُسحب لأي مكان.
              if (_tabIndex == 0) _buildSummaryFab(constraints),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryFab(BoxConstraints constraints) {
    const width = 118.0;
    const height = 48.0;
    const margin = 16.0;
    double fit(double value, double low, double high) =>
        high < low ? low : value.clamp(low, high).toDouble();
    final maxX = constraints.maxWidth - width - margin;
    final maxY = constraints.maxHeight - height - margin;
    // الموضع الافتراضي أسفل اليمين.
    final offset = _summaryFabOffset ?? Offset(maxX, maxY);
    final dx = fit(offset.dx, margin, maxX);
    final dy = fit(offset.dy, margin, maxY);
    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        onPanUpdate: (drag) => setState(
          () => _summaryFabOffset = Offset(
            fit(dx + drag.delta.dx, margin, maxX),
            fit(dy + drag.delta.dy, margin, maxY),
          ),
        ),
        child: Material(
          color: item.color,
          elevation: 7,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rField),
            onTap: _openQuickAddSheet,
            child: SizedBox(
              width: width,
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                textDirection: AppTr.uiDir,
                children: const [
                  Icon(Icons.add_rounded, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'إضافة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // زر "+ إضافة" في شاشة تفاصيل الالتزام المشترك: مطابق تمامًا لقالب
  // _openAddAttachmentMenu في الشخصية (صف علوي من 3 مستطيلات + قسم
  // "تنظيم ومتابعة" قابل للطي بصف مستطيلات إضافي)، مع تغيير المعطيات فقط
  // لتناسب مسارات الإضافة في المشتركة بدل الشخصية.
  Future<void> _openQuickAddSheet() async {
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
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFD5DEDB), borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('إضافة إلى الالتزام', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F1F1C))),
                    const SizedBox(height: 4),
                    const Text('اختر ما تريد إضافته لهذا الالتزام', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5C6B68))),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SharedQuickAddTile(
                            key: const ValueKey('shared-add-finance-option'),
                            label: 'عملية مالية',
                            icon: Icons.payments_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'عملية مالية'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SharedQuickAddTile(
                            key: const ValueKey('shared-add-member-option'),
                            label: 'عضو / مسؤول',
                            icon: Icons.person_add_alt_1_rounded,
                            onTap: () => Navigator.pop(sheetContext, 'عضو / مسؤول'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SharedQuickAddTile(
                            key: const ValueKey('shared-add-document-option'),
                            label: 'مستند',
                            icon: Icons.description_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'مستند'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => setSheetState(() => orgExpanded = !orgExpanded),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.event_note_outlined, size: 18, color: item.color),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('المتابعة والتخطيط', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0F1F1C))),
                            ),
                            Icon(orgExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: item.color),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      // نفس أنواع المتابعة والتخطيط في الشخصية، ثم موقع.
                      for (final row in const [
                        [
                          ('مهمة', Icons.task_alt_outlined),
                          ('موعد', Icons.event_outlined),
                          ('عادة', Icons.repeat_rounded),
                        ],
                        [
                          ('تذكير', Icons.notifications_active_outlined),
                          ('ملاحظات', Icons.sticky_note_2_outlined),
                          ('موقع', Icons.place_outlined),
                        ],
                      ]) ...[
                        Row(
                          children: [
                            for (var i = 0; i < row.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _SharedQuickAddTile(
                                  label: row[i].$1,
                                  icon: row[i].$2,
                                  onTap: () =>
                                      Navigator.pop(sheetContext, row[i].$1),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
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
    switch (action) {
      case 'عملية مالية':
        _openTransactionForm();
      case 'عضو / مسؤول':
        _openAddMemberSheet();
      case 'مستند':
        _openSimpleEntrySheet(sectionKey: _documentsDetailsKey, kinds: _documentKinds);
      case 'عنصر متابعة':
        _openSimpleEntrySheet(sectionKey: _followUpDetailsKey, kinds: _followUpKinds);
      case 'مهمة' || 'موعد' || 'عادة' || 'تذكير' || 'ملاحظات':
        _openSimpleEntrySheet(
          sectionKey: _followUpDetailsKey,
          kinds: _followUpKinds,
          initialKind: action,
        );
      case 'موقع':
        _openSimpleEntrySheet(sectionKey: _placesDetailsKey, kinds: _placeKinds);
    }
  }

  // مطابق تمامًا لـ _CompactCommitmentHeader في الشخصية: صندوق أيقونة
  // 44×44، عنوان+نوع الالتزام، شارة الحالة، وقائمة الثلاث نقاط — بلا زر
  // رجوع داخل الصف (الرجوع أصبح من AppBar كما في الشخصية تمامًا).
  Widget _buildHeader() {
    final dark = _finished;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: dark ? Colors.white.withValues(alpha: 0.1) : item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(item.icon, color: dark ? Colors.white70 : item.color, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, softWrap: true, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: dark ? Colors.white : const Color(0xFF0F1F1C))),
                const SizedBox(height: 3),
                Text(_sharedTypeDisplay(item.entryType), maxLines: 2, softWrap: true, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dark ? const Color(0xFFB8C4C1) : const Color(0xFF5C6B68))),
                // حالة الدعوات: الضغط يعرض كل عضو وحالته.
                if (_inviteSummary() case final summary?) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _openInviteStatusSheet,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
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
                          Flexible(
                            child: Text(
                              summary,
                              maxLines: 2,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFA6691A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: Color(0xFFA6691A),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final shown = item.status == _sharedStatusActive &&
                      !_archivedForMe(item)
                  ? (_awaitingStatus(item) ?? _shownStatus)
                  : _shownStatus;
              final color = _sharedStatusColor(shown);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: dark ? Colors.white.withValues(alpha: 0.14) : color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(shown, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: dark ? Colors.white : color)),
                  ),
                  const SizedBox(height: 4),
                  // دوري في الالتزام.
                  Text(
                    _isManagerHere ? 'المسؤول' : 'عضو',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      // المسؤول بلونه الذهبي نفسه في كل مكان.
                      color: dark
                          ? const Color(0xFFB8C4C1)
                          : _isManagerHere
                          ? AppTheme.goldDark
                          : AppTheme.muted,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_SharedCommitmentMenuAction>(
            tooltip: AppTr.tr('إجراءات الالتزام'),
            onSelected: _handleMenuAction,
            icon: Icon(Icons.more_vert_rounded, size: 23, color: _finished ? Colors.white70 : const Color(0xFF46534F)),
            // لم تعد القائمة const لأن عنوان الأرشفة يتبدّل حسب حالة البند.
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _SharedCommitmentMenuAction.edit,
                child: _SharedCommitmentMenuItem(label: 'تعديل', icon: Icons.edit_outlined),
              ),
              const PopupMenuItem(
                value: _SharedCommitmentMenuAction.share,
                child: _SharedCommitmentMenuItem(label: 'مشاركة', icon: Icons.share_outlined),
              ),
              // الانضمام والمغادرة انتقلا إلى + في تبويب الأعضاء.
              if (_isManagerHere || _isCancelled)
                const PopupMenuItem(
                  value: _SharedCommitmentMenuAction.delete,
                  child: _SharedCommitmentMenuItem(label: 'حذف', icon: Icons.delete_outline_rounded, color: Color(0xFFA82F26)),
                )
              else
                const PopupMenuItem(
                  value: _SharedCommitmentMenuAction.leave,
                  child: _SharedCommitmentMenuItem(label: 'مغادرة المشاركة', icon: Icons.logout_rounded, color: Color(0xFFA82F26)),
                ),
              PopupMenuItem(
                value: _SharedCommitmentMenuAction.archive,
                child: _SharedCommitmentMenuItem(
                  label: _archivedForMe(item)
                      ? 'إلغاء الأرشفة'
                      : 'أرشيف',
                  icon: _archivedForMe(item)
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettleButton() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: _finished ? Colors.white70 : item.color,
        side: BorderSide(
          color: _finished
              ? Colors.white24
              : item.color.withValues(alpha: 0.35),
        ),
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      ),
      onPressed: _openSettleUpSheet,
      icon: const Icon(Icons.handshake_outlined, size: 18),
      label: const Text(
        'تسوية الحساب',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
      ),
    ),
  );

  List<(String, String, IconData)> _highlights() {
    switch (item.entryType) {
      case 'مشاركات مشتركة':
        {
          final method = (item.details[_collectMethodKey] ?? '').trim();
          return [
            ('التاريخ', item.dueDate.isEmpty ? '—' : item.dueDate, Icons.event_outlined),
            ('طريقة التحصيل', method.isEmpty ? '—' : method, Icons.account_balance_wallet_outlined),
            ('عدد الأعضاء', '${item.membersCount}', Icons.groups_outlined),
          ];
        }
      case 'الرحلة / السفر':
        {
          // لا ميزانية للرحلة: ما يهمّ هو تاريخها وطريقة تحصيلها، ثم
          // إجمالي المساهمة إن كانت «دفعة مقطوعة» أصلًا.
          final method = (item.details[_collectMethodKey] ?? '').trim();
          return [
            (
              'تاريخ الرحلة',
              item.dueDate.isEmpty ? '—' : item.dueDate,
              Icons.flight_takeoff_outlined,
            ),
            (
              'طريقة التحصيل',
              method.isEmpty ? '—' : method,
              Icons.account_balance_wallet_outlined,
            ),
            // الميزانية انتقلت إلى الملخص، فلا تتكرّر هنا.
            ('عدد الأعضاء', '${item.membersCount}', Icons.groups_outlined),
          ];
        }
      case 'جمعية مالية':
        return [
          ('إجمالي المساهمة', '${item.amount} ${item.currency}', Icons.payments_outlined),
          ('موعد الدفع الشهري', item.details['موعد الدفع الشهري']?.isNotEmpty == true ? item.details['موعد الدفع الشهري']! : '—', Icons.event_repeat_outlined),
          ('عدد المشتركين', '${item.membersCount}', Icons.groups_outlined),
        ];
      // نوع قديم مدموج: يُعرض بنفس بطاقة المشاركات المشتركة.
      case 'اللقاءات':
        {
          final method = (item.details[_collectMethodKey] ?? '').trim();
          return [
            ('التاريخ', item.dueDate.isEmpty ? '—' : item.dueDate, Icons.event_outlined),
            ('طريقة التحصيل', method.isEmpty ? '—' : method, Icons.account_balance_wallet_outlined),
            ('عدد الأعضاء', '${item.membersCount}', Icons.groups_outlined),
          ];
        }
      default:
        return [('المبلغ', '${item.amount} ${item.currency}', Icons.payments_outlined)];
    }
  }

  Widget _buildHighlightBar() {
    final highlights = _highlights();
    final dark = _finished;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          for (var i = 0; i < highlights.length; i++) ...[
            if (i > 0) Container(width: 1, height: 34, color: dark ? Colors.white24 : item.color.withValues(alpha: 0.18), margin: const EdgeInsets.symmetric(horizontal: 8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(highlights[i].$3, size: 16, color: dark ? Colors.white70 : item.color),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(highlights[i].$2, maxLines: 3, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: dark ? Colors.white : const Color(0xFF0F1F1C))),
                  ),
                  const SizedBox(height: 2),
                  Text(highlights[i].$1, maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: dark ? const Color(0xFFB8C4C1) : const Color(0xFF5C6B68))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // مطابق تمامًا لـ _InlineDetailsTabs في الشخصية: صندوق أبيض واحد
  // بحدود رفيعة يحوي كل التبويبات بعرض متساوٍ (أيقونة فوق نص فوق خط
  // سفلي متحرك)، بدل صف مستطيلات قابل للتمرير الأفقي كما كان سابقًا.
  Widget _buildTabsRow() {
    // كانت هنا نسخة يدوية مطابقة لشريط التبويبات المشترك فتخلّفت عنه عند
    // أي تعديل (آخرها: السماح بسطرين للعناوين الطويلة). الآن تستدعيه.
    // تُقرأ مرة واحدة: العناوين والأيقونات صارت getters تتغيّر بنوع الالتزام.
    final tabs = _tabs;
    final icons = _tabIcons;
    return DetailPageTabs(
      key: const ValueKey('shared-inline-details-tabs'),
      twoLineLabels: true,
      sections: [
        for (var i = 0; i < tabs.length; i++)
          DetailSectionTab(label: tabs[i], icon: icons[i]),
      ],
      selectedIndex: _tabIndex,
      color: item.color,
      onSelected: (index) => setState(() => _tabIndex = index),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildSummaryTab();
      case 1:
        return _isRosca ? _buildRoscaTab() : _buildLedgerTab();
      case 2:
        return _buildSimpleListTab(sectionKey: _followUpDetailsKey, kinds: _followUpKinds, icon: Icons.fact_check_outlined, emptyText: 'لا توجد عناصر متابعة أو مهام بعد', title: 'المتابعة والتخطيط');
      case 3:
        return _buildMembersTab();
      case 4:
        return _buildSimpleListTab(sectionKey: _documentsDetailsKey, kinds: _documentKinds, icon: Icons.description_outlined, emptyText: 'لا توجد مستندات بعد', title: 'مستندات');
      case 5:
        return _buildSimpleListTab(sectionKey: _placesDetailsKey, kinds: _placeKinds, icon: Icons.place_outlined, emptyText: 'لا توجد مواقع أو أماكن بعد', title: 'مواقع وأماكن');
      case 6:
        return _buildHistoryTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ------------------------------------------- الجمعية: الدورات والمساهمات
  /// خطة الجمعية: الدورات مشتقّة من إعداداتها، والمدفوعات مما سُجّل فعلًا.
  RoscaPlan get _roscaPlan => RoscaLedger.plan(item.details, _ledgerMembers);

  RoscaCycle? _roscaCycleAt(RoscaPlan plan, int index) {
    for (final cycle in plan.cycles) {
      if (cycle.index == index) return cycle;
    }
    return null;
  }

  /// شارة حالة الدورة: مكتملة / متأخرة / جارية / قادمة.
  Widget _roscaStatusChip(String status) {
    final (Color color, Color background) = switch (status) {
      RoscaCycle.statusDone => (AppTheme.brandMid, AppTheme.brandSoft),
      RoscaCycle.statusLate => (AppTheme.danger, AppTheme.dangerSoft),
      RoscaCycle.statusOpen => (AppTheme.warning, AppTheme.goldSoft),
      _ => (AppTheme.muted, AppTheme.field),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _roscaMetric(String label, String value, Color color) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 3,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
          ),
        ),
      ],
    ),
  );

  Widget _roscaBar(double ratio, Color color) {
    final value = ratio < 0 ? 0.0 : (ratio > 1 ? 1.0 : ratio);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rPill),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
        backgroundColor: AppTheme.field,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  /// غلاف محتوى التبويب: بلا صندوق — رأس القسم على الصفحة مباشرة.
  Widget _tabPanel({required Widget child}) => child;

  Widget _roscaCard({required Widget child}) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rCard),
      border: Border.all(color: AppTheme.hairline),
    ),
    child: child,
  );

  /// تبويب الجمعية: خطة الدورات، الدورة الجارية، كل الدورات، ثم الأعضاء.
  Widget _buildRoscaTab() {
    final members = _ledgerMembers;
    final plan = _roscaPlan;
    if (members.isEmpty || plan.isEmpty) {
      return _roscaCard(
        child: Column(
          children: [
            const Icon(
              Icons.groups_2_outlined,
              size: 34,
              color: AppTheme.muted,
            ),
            const SizedBox(height: 10),
            const Text(
              'أضف الأعضاء وحدّد عدد الدورات والمساهمة على الشخص '
              'ليُبنى جدول الدورات تلقائيًا',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      );
    }
    final current = plan.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // + : مساهمة إضافية لعضو (تظهر بجانب مساهمته: 10000 + 200).
        AppSectionAddRow(
          title: 'المساهمات والاستحقاقات',
          icon: Icons.autorenew_rounded,
          accent: item.color,
          onAdd: _openContributionForm,
        ),
        const SizedBox(height: 12),
        _buildRoscaSummaryCard(plan),
        const SizedBox(height: 12),
        // المساهمات الإضافية بانتظار موافقة المسؤول.
        _buildPendingRequests(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: item.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المساهمات والاستحقاقات',
                  textAlign: AppTr.alignEnd,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: item.color,
                  ),
                ),
              ),
              // كشف يُرسل: من استلم ومن بقي، والتواريخ والمبالغ.
              IconButton(
                tooltip: AppTr.tr('إرسال كشف'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _shareRoscaStatement(plan),
                icon: Icon(
                  Icons.summarize_outlined,
                  size: 21,
                  color: item.color,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: AppTheme.hairline),
        const SizedBox(height: 10),
        _buildRoscaDuesContent(plan, members),
      ],
    );
  }

  /// النافذة المنبثقة لـ«المساهمات والاستحقاقات» — نفس ما في التبويب.
  Future<void> _openRoscaDuesSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    const Expanded(
                      child: Text(
                        'المساهمات والاستحقاقات',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.muted,
                    ),
                  ],
                ),
                _buildRoscaDuesContent(
                  _roscaPlan,
                  _ledgerMembers,
                  sheetContext: sheetContext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// حالة واحدة لكل دورة بترتيبها: «قادمة» لم يحن وقتها، «حان وقتها» يوم
  /// موعدها، «متأخرة» فات موعدها ولم تُسدَّد (يُسلَّم مبلغها)، «مكتملة»
  /// سُلِّم مبلغها.
  String _roscaTurnStatus(RoscaPlan plan, int? turn) {
    if (turn == null) return 'بلا دور';
    for (final cycle in plan.cycles) {
      if (cycle.index != turn) continue;
      if (cycle.isPaidOut) return 'مكتملة';
      final due = cycle.dueDate;
      if (due == null) return 'قادمة';
      final day = DateUtils.dateOnly(due);
      final today = DateUtils.dateOnly(DateTime.now());
      if (day.isBefore(today)) return 'متأخرة';
      if (day == today) return 'حان وقتها';
      return 'قادمة';
    }
    return 'قادمة';
  }

  Widget _roscaStatusPill(String status) {
    final color = switch (status) {
      'حان وقتها' => AppTheme.brandMid,
      // المكتمل أسود والمتأخر أحمر في كل التطبيق.
      'متأخرة' => AppTheme.danger,
      'مكتملة' => const Color(0xFF1E2725),
      _ => AppTheme.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Text(
        // في تحديد الأدوار: من سُلِّم مبلغه «استلم حصته».
        status == 'مكتملة' ? 'استلم حصته' : status,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  String _memberRole(String name) {
    for (final m in item.members) {
      if (m.name.trim() == name.trim()) return m.role;
    }
    return 'عضو';
  }

  /// صف عضو: الاسم ودوره (مسؤول/عضو)، ثم مساهمته وتاريخ استلامه، ثم رقم
  /// دورة استلامه وحالتها. في «المساهمات والاستحقاقات» ([run] موجود): من
  /// حان دوره أو تأخر يصير مستطيله ملوّنًا بالمبلغ الإجمالي وزرّي «تسليم
  /// المبلغ» و«تغيير الدور»، ومن استلم حصته يُلغى تسليمه فقط.
  Widget _roscaDueRow(
    RoscaPlan plan,
    String name, {
    bool showId = false,
    Widget? action,
    void Function(VoidCallback action)? run,
  }) {
    // يُنفَّذ الإجراء عبر [run] (يغلق النافذة المنبثقة أولًا).
    void go(VoidCallback action) {
      final runner = run;
      if (runner == null) {
        action();
      } else {
        runner(action);
      }
    }
    final turn = plan.turnOf(name);
    // تاريخ دوره هو: يتغيّر مع «تغيير الدور».
    RoscaCycle? turnCycle;
    for (final cycle in plan.cycles) {
      if (cycle.index == turn) turnCycle = cycle;
    }
    final turnDate = turnCycle?.dueText ?? '—';
    final role = _memberRole(name);
    final status = _roscaTurnStatus(plan, turn);
    final due = run != null &&
        turnCycle != null &&
        (status == 'حان وقتها' || status == 'متأخرة');
    final manager = _isManagerHere;
    final cycle = turnCycle;
    // لون الصندوق من حالته: متأخرة أحمر خفيف، حان وقتها بلون الالتزام
    // الخفيف، قادمة أبيض، مكتملة رمادي.
    final (Color boxColor, Color boxBorder) = switch (status) {
      'متأخرة' => (
        const Color(0xFFFDF2F0),
        AppTheme.danger.withValues(alpha: 0.25),
      ),
      'حان وقتها' => (
        item.color.withValues(alpha: 0.08),
        item.color.withValues(alpha: 0.25),
      ),
      'مكتملة' => (const Color(0xFFECEFEE), const Color(0xFFD5DBD9)),
      _ => (Colors.white, AppTheme.hairline),
    };
    // كل من لم يستلم: زرّا «استلام المبلغ» و«تغيير الدور» (للمسؤول).
    final actions =
        run != null && manager && cycle != null && !cycle.isPaidOut;
    Widget? trailing = action;
    if (run != null &&
        manager &&
        cycle != null &&
        cycle.isPaidOut &&
        trailing == null) {
      trailing = TextButton(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.danger,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
        onPressed: () => go(() => _roscaTogglePayout(cycle.index)),
        child: const Text(
          'إلغاء التسليم',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      );
    }
    final body = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: boxBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _shownName(name),
                      textAlign: AppTr.alignEnd,
                      maxLines: 2,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    if (showId) _memberIdLine(name),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: role == 'عضو' ? AppTheme.field : AppTheme.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: role == 'عضو' ? AppTheme.body : AppTheme.goldDark,
                  ),
                ),
              ),
            ],
          ),
          if (due) ...[
            const SizedBox(height: 3),
            Text(
              '${AppTr.tr('المبلغ الإجمالي')}: ${_money(plan.cycleTotal)}',
              textAlign: AppTr.alignEnd,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: item.color,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${AppTr.tr('المساهمة')}: ${() {
              final base = plan.shareOf(name);
              final extra = SharedLedger.extraOf(item.details, name);
              return extra > 0.01
                  ? '${_plainNum(base)} + ${_plainNum(extra)} = ${_money(base + extra)}'
                  : _money(base);
            }()}   ·   '
            '${AppTr.tr('تاريخ الاستلام')}: $turnDate',
            textAlign: AppTr.alignEnd,
            maxLines: 2,
            softWrap: true,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.body,
            ),
          ),
          if (cycle != null && cycle.isPaidOut) ...[
            const SizedBox(height: 2),
            Text(
              '${AppTr.tr('سُلِّم المبلغ في')} ${cycle.payoutDate}',
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Text(
                '${AppTr.tr('الدورة رقم')}: ${turn ?? '—'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(width: 8),
              _roscaStatusPill(status),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          // كل من لم يستلم: «استلام المبلغ» و«تغيير الدور» جنبًا إلى جنب.
          if (actions && cycle != null) ...[
            const SizedBox(height: 10),
            Row(
              textDirection: AppTr.uiDir,
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => go(() => _roscaTogglePayout(cycle.index)),
                    icon: const Icon(Icons.payments_outlined, size: 17),
                    label: const Text(
                      'استلام المبلغ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: item.color,
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: BorderSide(color: item.color),
                    ),
                    onPressed: () =>
                        go(() => _roscaChangeReceiver(cycle.index)),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    label: const Text(
                      'تغيير الدور',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (!due || cycle == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      onTap: () => go(() => _openRoscaCycleSheet(cycle.index)),
      child: body,
    );
  }

  /// كشف تحديد الأدوار نصًا يُرسل: كل دورة بصاحبها وتاريخها وحالتها وما
  /// جُمع فيها، ثم من استلم ومن بقي، والمتأخرون في الدفع.
  Future<void> _shareRoscaStatement(RoscaPlan plan) async {
    final members = _ledgerMembers;
    final today = DateTime.now();
    final lines = <String>[
      '${AppTr.tr('كشف تحديد الأدوار')}: ${item.title}',
      '${AppTr.tr('التاريخ')}: ${roscaFormatDate(today)}',
      '${AppTr.tr('المبلغ الإجمالي')}: ${_money(plan.cycleTotal)} · '
          '${plan.cycles.length} ${AppTr.tr('دورات')} · '
          '${AppTr.tr(plan.frequency)}',
      '',
    ];
    for (final cycle in plan.cycles) {
      final status = _roscaTurnStatus(plan, cycle.index);
      lines.add(
        '${AppTr.tr('الدورة رقم')} ${cycle.index}: '
        '${_shownName(cycle.receiver)} — ${cycle.dueText} — '
        '${AppTr.tr(status)}'
        '${cycle.isPaidOut ? ' (${AppTr.tr('سُلِّم المبلغ في')} ${cycle.payoutDate})' : ''}',
      );
      lines.add(
        '   ${AppTr.tr('جُمع')}: ${_money(cycle.collected)} '
        '${AppTr.tr('من')} ${_money(cycle.target)}',
      );
    }
    final received = [
      for (final m in members)
        if (plan.receivedBy(m)) _shownName(m),
    ];
    final waiting = [
      for (final m in members)
        if (!plan.receivedBy(m)) _shownName(m),
    ];
    final lateList = [
      for (final m in members)
        if (plan.overdueOf(m) > 0)
          '${_shownName(m)} (${plan.overdueOf(m)})',
    ];
    lines
      ..add('')
      ..add(
        '${AppTr.tr('استلموا')}: '
        '${received.isEmpty ? '—' : received.join('، ')}',
      )
      ..add(
        '${AppTr.tr('باقٍ')}: ${waiting.isEmpty ? '—' : waiting.join('، ')}',
      )
      ..add(
        '${AppTr.tr('متأخرون في الدفع')}: '
        '${lateList.isEmpty ? '—' : lateList.join('، ')}',
      );
    // يُعرض الكشف أولًا، ثم «إرسال».
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Icon(Icons.summarize_outlined, color: item.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppTr.tr('كشف تحديد الأدوار'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                        color: AppTheme.muted,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    children: [
                      Text(
                        lines.take(3).join('\n'),
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final cycle in plan.cycles)
                        Builder(
                          builder: (_) {
                            final status = _roscaTurnStatus(plan, cycle.index);
                            final (bg, fg) = switch (status) {
                              'متأخرة' => (
                                const Color(0xFFFDF2F0),
                                AppTheme.danger,
                              ),
                              'مكتملة' => (
                                const Color(0xFFECEFEE),
                                const Color(0xFF1E2725),
                              ),
                              'حان وقتها' => (
                                item.color.withValues(alpha: 0.08),
                                item.color,
                              ),
                              _ => (Colors.white, AppTheme.muted),
                            };
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rInner,
                                ),
                                border: Border.all(color: AppTheme.hairline),
                              ),
                              child: Row(
                                textDirection: AppTr.uiDir,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${AppTr.tr('الدورة رقم')} ${cycle.index}: '
                                      '${_shownName(cycle.receiver)}\n'
                                      '${cycle.dueText} · ${AppTr.tr('جُمع')} '
                                      '${_money(cycle.collected)} '
                                      '${AppTr.tr('من')} ${_money(cycle.target)}',
                                      textAlign: AppTr.alignEnd,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.title,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    AppTr.tr(status),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: fg,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 6),
                      Text(
                        lines.skip(lines.length - 3).join('\n'),
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.title,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text(
                      'إرسال',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (send != true || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: item.title,
        text: lines.join('\n'),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// الأعضاء بترتيب دوراتهم، ولون كل صندوق من حالته.
  Widget _buildRoscaDuesContent(
    RoscaPlan plan,
    List<String> members, {
    BuildContext? sheetContext,
  }) {
    // من النافذة المنبثقة: تُغلق أولًا ثم يُنفَّذ الإجراء، فتتحدّث الصفحة.
    void run(VoidCallback action) {
      if (sheetContext != null) Navigator.pop(sheetContext);
      action();
    }

    // بترتيب الدورات 1، 2، 3...: المكتمل يبقى مكانه وتتغيّر حالته فقط.
    int rank(String name) => plan.turnOf(name) ?? 9999;

    final ordered = List<String>.of(members)
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final name in ordered) _roscaDueRow(plan, name, run: run),
      ],
    );
  }

  Widget _buildRoscaSummaryCard(RoscaPlan plan) {
    return _roscaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _roscaMetric(
                'دورات مكتملة',
                '${plan.completedCount} من ${plan.cycles.length}',
                AppTheme.title,
              ),
              // المحصّل: كم عضوًا سدّد في الدورة الجارية من الأعضاء.
              _roscaMetric(
                'المحصّل',
                () {
                  final open = plan.current;
                  final paid = open == null
                      ? plan.members.length
                      : open.paidOf(plan.members).length;
                  return '$paid من ${plan.members.length}';
                }(),
                AppTheme.brandMid,
              ),
              _roscaMetric(
                'إجمالي المساهمة',
                _money(plan.cycleTotal),
                AppTheme.title,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoscaCurrentCard(
    RoscaPlan plan,
    RoscaCycle cycle,
    List<String> members,
  ) {
    final status = plan.statusOf(cycle);
    final unpaid = cycle.unpaidOf(members);
    return _roscaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Text(
                  'الدورة الجارية · رقم ${cycle.index}',
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _roscaStatusChip(status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(Icons.event_outlined, size: 15, color: AppTheme.muted),
              const SizedBox(width: 5),
              Text(
                'الاستحقاق ${cycle.dueText}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.redeem_outlined,
                size: 15,
                color: AppTheme.muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  cycle.receiver.isEmpty
                      ? 'المستلم غير محدد'
                      : 'المستلم: ${cycle.receiver}',
                  textAlign: AppTr.alignEnd,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _roscaBar(cycle.progress, item.color),
          const SizedBox(height: 6),
          Text(
            '${_money(cycle.collected)} من ${_money(cycle.target)}'
            '${cycle.remaining > 0 ? ' · باقٍ ${_money(cycle.remaining)}' : ''}',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.hairline),
          const SizedBox(height: 10),
          // من سدّد ومن لم يسدّد — مع تسجيل الدفع مباشرة من هنا.
          for (final name in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(
                    cycle.memberPaid(name)
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: cycle.memberPaid(name)
                        ? AppTheme.brandMid
                        : AppTheme.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.title,
                      ),
                    ),
                  ),
                  if (cycle.receiver == name) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.goldSoft,
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: const Text(
                        'صاحب الدور',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.goldDark,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (cycle.memberPaid(name))
                    Text(
                      _money(cycle.paidBy(name)),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.brandMid,
                      ),
                    )
                  else
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: item.color,
                      ),
                      onPressed: () =>
                          _openRoscaPaymentForm(cycle.index, member: name),
                      child: const Text(
                        'تسجيل دفع',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: item.color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => _openRoscaPaymentForm(cycle.index),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'تسجيل مساهمة',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.title,
                    side: const BorderSide(color: AppTheme.hairline),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: unpaid.isEmpty
                      ? null
                      : () => _roscaMarkAllPaid(cycle.index),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text(
                    'سدّد الجميع',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          if (cycle.isComplete && !cycle.isPaidOut) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandMid,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => _roscaTogglePayout(cycle.index),
              icon: const Icon(Icons.redeem_rounded, size: 18),
              label: const Text(
                'تسليم المبلغ لصاحب الدور',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoscaCyclesCard(RoscaPlan plan) {
    return _tabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            title: 'كل الدورات',
            icon: Icons.view_timeline_outlined,
            accent: item.color,
            trailingText: '${plan.cycles.length}',
            onAdd: null,
          ),
          const SizedBox(height: 4),
          for (final cycle in plan.cycles)
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              onTap: () => _openRoscaCycleSheet(cycle.index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cycle.isPaidOut
                            ? AppTheme.brandSoft
                            : AppTheme.field,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${cycle.index}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: cycle.isPaidOut
                              ? AppTheme.brandMid
                              : AppTheme.title,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            cycle.receiver.isEmpty
                                ? 'بلا مستلم محدد'
                                : cycle.receiver,
                            textAlign: AppTr.alignEnd,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.title,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${cycle.dueText} · ${_money(cycle.collected)} '
                            'من ${_money(cycle.target)}',
                            textAlign: AppTr.alignEnd,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _roscaStatusChip(plan.statusOf(cycle)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoscaMembersCard(RoscaPlan plan, List<String> members) {
    return _tabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            title: 'الأعضاء والدور',
            icon: Icons.groups_outlined,
            accent: item.color,
            trailingText: '${members.length}',
          ),
          const SizedBox(height: 10),
          for (final name in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          name,
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan.overdueOf(name) > 0
                              ? 'سدّد ${plan.paidCountOf(name)} من '
                                    '${plan.cycles.length} · متأخر عن '
                                    '${plan.overdueOf(name)} دورة'
                              : 'سدّد ${plan.paidCountOf(name)} من '
                                    '${plan.cycles.length} دورة · '
                                    '${_money(plan.paidTotalOf(name))}',
                          textAlign: AppTr.alignEnd,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: plan.overdueOf(name) > 0
                                ? AppTheme.danger
                                : AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: plan.receivedBy(name)
                          ? AppTheme.brandSoft
                          : AppTheme.field,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                    child: Text(
                      plan.turnOf(name) == null
                          ? 'بلا دور'
                          : plan.receivedBy(name)
                          ? 'استلم حصته · ${plan.turnOf(name)}'
                          : 'دوره ${plan.turnOf(name)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: plan.receivedBy(name)
                            ? AppTheme.brandMid
                            : AppTheme.title,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// تفاصيل دورة واحدة: مساهماتها، تغيير صاحب الدور، وتسليم المبلغ.
  Future<void> _openRoscaCycleSheet(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final plan = _roscaPlan;
          final cycle = _roscaCycleAt(plan, index);
          if (cycle == null) return const SizedBox.shrink();
          final members = _ledgerMembers;
          return Directionality(
            textDirection: AppTr.uiDir,
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                children: [
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: Text(
                          'الدورة رقم ${cycle.index}',
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // حالة الدور نفسها: حان وقتها / متأخرة / قادمة /
                      // مكتملة.
                      _roscaStatusPill(_roscaTurnStatus(plan, cycle.index)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الاستحقاق ${cycle.dueText} · '
                    '${_money(cycle.collected)} من ${_money(cycle.target)}',
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // صاحب الدور: افتراضه ترتيب الأعضاء، ويمكن تبديله.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.field,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                    ),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        const Icon(
                          Icons.redeem_outlined,
                          size: 18,
                          color: AppTheme.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cycle.receiver.isEmpty
                                ? 'صاحب الدور غير محدد'
                                : 'صاحب الدور: ${cycle.receiver}'
                                      '${cycle.isPaidOut ? ' · سُلّم ${cycle.payoutDate}' : ''}',
                            textAlign: AppTr.alignEnd,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: item.color,
                          ),
                          onPressed: () async {
                            await _roscaChangeReceiver(index);
                            setSheetState(() {});
                          },
                          child: const Text(
                            'تغيير',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'المساهمات المسجّلة',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (cycle.payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'لم تُسجَّل أي مساهمة في هذه الدورة بعد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.muted,
                        ),
                      ),
                    )
                  else
                    for (final payment in cycle.payments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    payment.member,
                                    textAlign: AppTr.alignEnd,
                                    maxLines: 3,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.title,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    payment.note.trim().isEmpty
                                        ? _withClock(payment.date, payment.id)
                                        : '${_withClock(payment.date, payment.id)} · ${payment.note}',
                                    textAlign: AppTr.alignEnd,
                                    maxLines: 3,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _money(payment.amount),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.brandMid,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                              onPressed: () async {
                                await _roscaDeletePayment(index, payment);
                                setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () async {
                      await _openRoscaPaymentForm(index);
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'تسجيل مساهمة',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.title,
                            side: const BorderSide(color: AppTheme.hairline),
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: cycle.unpaidOf(members).isEmpty
                              ? null
                              : () async {
                                  await _roscaMarkAllPaid(index);
                                  setSheetState(() {});
                                },
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text(
                            'سدّد الجميع',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cycle.isPaidOut
                                ? AppTheme.danger
                                : AppTheme.brandMid,
                            side: const BorderSide(color: AppTheme.hairline),
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: () async {
                            await _roscaTogglePayout(index);
                            setSheetState(() {});
                          },
                          icon: Icon(
                            cycle.isPaidOut
                                ? Icons.undo_rounded
                                : Icons.redeem_rounded,
                            size: 18,
                          ),
                          label: Text(
                            cycle.isPaidOut ? 'إلغاء التسليم' : 'تسليم المبلغ',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// تسجيل مساهمة عضو في دورة: المبلغ يأتي معبّأً بحصته المقرّرة.
  Future<void> _openRoscaPaymentForm(int index, {String? member}) async {
    final members = _ledgerMembers;
    if (members.isEmpty) return;
    final plan = _roscaPlan;
    final cycle = _roscaCycleAt(plan, index);
    final unpaid = cycle == null ? members : cycle.unpaidOf(members);
    var payer = member ?? (unpaid.isEmpty ? members.first : unpaid.first);
    final due = cycle == null
        ? plan.shareOf(payer)
        : plan.shareOf(payer) - cycle.paidBy(payer);
    var receiptPath = '';
    final amountController = TextEditingController(
      text: due > 0 ? due.toStringAsFixed(due % 1 == 0 ? 0 : 2) : '',
    );
    final noteController = TextEditingController();
    final now = DateTime.now();
    final dateController = TextEditingController(text: roscaFormatDate(now));

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تسجيل مساهمة — الدورة $index',
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'من العضو؟',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in members)
                        ChoiceChip(
                          label: Text(
                            cycle != null && cycle.memberPaid(name)
                                ? '$name ✓'
                                : name,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          selected: payer == name,
                          onSelected: (_) {
                            setSheetState(() {
                              payer = name;
                              final rest = cycle == null
                                  ? plan.shareOf(name)
                                  : plan.shareOf(name) - cycle.paidBy(name);
                              amountController.text = rest > 0
                                  ? rest.toStringAsFixed(
                                      rest % 1 == 0 ? 0 : 2,
                                    )
                                  : '';
                            });
                          },
                          selectedColor: AppTheme.brandSoft,
                          backgroundColor: AppTheme.field,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.rPill),
                          ),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            label: const Text('المبلغ *'),
                            suffixText: item.currency,
                            prefixIcon: const Icon(
                              Icons.payments_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: dateController,
                          readOnly: true,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: AppTr.tr('التاريخ'),
                            prefixIcon: const Icon(
                              Icons.event_outlined,
                              size: 18,
                            ),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (picked == null) return;
                            setSheetState(
                              () => dateController.text = roscaFormatDate(
                                picked,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    textDirection: AppTr.uiDir,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: AppTr.tr('ملاحظة'),
                      prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _receiptButton(
                    label: 'إرفاق مستند',
                    path: receiptPath,
                    accent: AppTheme.brand,
                    onTap: () async {
                      final path = await _pickReceiptFile(sheetContext);
                      if (path == null) return;
                      setSheetState(() => receiptPath = path);
                    },
                    onRemove: () => setSheetState(() => receiptPath = ''),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      final value =
                          parseMoney(amountController.text.trim()) ?? 0;
                      if (value <= 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('اكتب مبلغ المساهمة'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                    child: const Text('حفظ المساهمة'),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final payment = RoscaPayment(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      member: payer,
      amount: parseMoney(amountController.text.trim()) ?? 0,
      date: dateController.text.trim(),
      note: noteController.text.trim(),
      receipt: receiptPath,
    );
    // التخلص بعد انتهاء حركة الإغلاق حتى لا يُستعمل متحكم محرَّر.
    final openControllers = <TextEditingController>[
      amountController,
      noteController,
      dateController,
    ];
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final c in openControllers) {
        c.dispose();
      }
    });
    if (saved != true) return;
    final details = Map<String, String>.of(item.details)
      ..[RoscaLedger.cyclesKey] = RoscaLedger.withPayment(
        item.details,
        index,
        payment,
      );
    final ok = await _persist(
      details,
      ask: 'هل تريد تسجيل المساهمة؟',
      done: 'تم تسجيل المساهمة',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// تسجيل بقية الأعضاء كمن سدّدوا حصتهم في هذه الدورة دفعة واحدة.
  Future<void> _roscaMarkAllPaid(int index) async {
    final plan = _roscaPlan;
    final cycle = _roscaCycleAt(plan, index);
    if (cycle == null) return;
    final members = _ledgerMembers;
    final unpaid = cycle.unpaidOf(members);
    if (unpaid.isEmpty) return;
    if (plan.share <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدّد «المساهمة على الشخص» في بيانات تحديد الأدوار أولًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'تسجيل سداد الجميع',
      message:
          'سيُسجَّل ${unpaid.length} عضوًا كمن سدّدوا حصتهم في الدورة $index.',
      confirmLabel: 'تسجيل',
    );
    if (!confirmed || !mounted) return;
    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;
    final date = roscaFormatDate(now);
    final payments = <RoscaPayment>[];
    for (var i = 0; i < unpaid.length; i++) {
      final rest = plan.shareOf(unpaid[i]) - cycle.paidBy(unpaid[i]);
      if (rest <= 0) continue;
      payments.add(
        RoscaPayment(
          id: '${stamp + i}',
          member: unpaid[i],
          amount: rest,
          date: date,
        ),
      );
    }
    if (payments.isEmpty) return;
    final details = Map<String, String>.of(item.details)
      ..[RoscaLedger.cyclesKey] = RoscaLedger.withPayments(
        item.details,
        index,
        payments,
      );
    final ok = await _persist(details, done: 'تم تسجيل سداد الجميع');
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _roscaDeletePayment(int index, RoscaPayment payment) async {
    final confirmed = await confirmAction(
      context,
      title: 'حذف المساهمة',
      message:
          'سيُحذف سداد ${payment.member} بمبلغ ${_money(payment.amount)} '
          'من الدورة $index.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final details = Map<String, String>.of(item.details)
      ..[RoscaLedger.cyclesKey] = RoscaLedger.withoutPayment(
        item.details,
        index,
        payment.id,
      );
    final ok = await _persist(details, done: 'تم حذف المساهمة');
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// تسليم مبلغ الدورة لصاحب الدور — أو التراجع عنه.
  Future<void> _roscaTogglePayout(int index) async {
    final plan = _roscaPlan;
    final cycle = _roscaCycleAt(plan, index);
    if (cycle == null) return;
    String value;
    if (cycle.isPaidOut) {
      final confirmed = await confirmAction(
        context,
        title: 'إلغاء التسليم',
        message: 'سيُلغى تسجيل تسليم مبلغ الدورة $index.',
        confirmLabel: 'إلغاء التسليم',
        danger: true,
      );
      if (!confirmed || !mounted) return;
      value = '';
    } else {
      if (cycle.receiver.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدّد صاحب الدور أولًا'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final confirmed = await confirmAction(
        context,
        title: 'تسليم المبلغ',
        // مبلغ الدورة كاملًا (ما يستلمه صاحب الدور)، لا ما جُمع حتى الآن.
        message:
            '${AppTr.tr('سيتم تسجيل استلام')} ${_money(plan.cycleTotal)} '
            '${AppTr.tr('إلى')} ${_shownName(cycle.receiver)}\n'
            '${AppTr.tr('الدورة رقم')}: $index\n'
            '${AppTr.tr('تاريخ استلام المبلغ')}: '
            '${roscaFormatDate(DateTime.now())}',
        confirmLabel: 'تأكيد التسليم',
      );
      if (!confirmed || !mounted) return;
      value = roscaFormatDate(DateTime.now());
    }
    final details = _withEvent(
      Map<String, String>.of(item.details)
        ..[RoscaLedger.cyclesKey] = RoscaLedger.withPayout(
          item.details,
          index,
          value,
        ),
      value.isEmpty
          ? '${AppTr.tr('إلغاء تسليم مبلغ الدورة')} $index'
          : '${AppTr.tr('تسليم')} ${_money(plan.cycleTotal)} '
                '${AppTr.tr('إلى')} ${_shownName(cycle.receiver)} — '
                '${AppTr.tr('الدورة رقم')}: $index',
    );
    final ok = await _persist(details, done: 'تم تحديث تسليم الدورة');
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// تبديل صاحب الدور في دورة بعينها (مبادلة أو تأجيل بين الأعضاء).
  Future<void> _roscaChangeReceiver(int index) async {
    final members = _ledgerMembers;
    if (members.isEmpty) return;
    // سُلِّم مبلغ هذه الدورة: لا تغيير للدور (أُلغِ التسليم أولًا).
    if (_roscaCycleAt(_roscaPlan, index)?.isPaidOut ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('سُلِّم مبلغ هذه الدورة — لا يمكن تغيير الدور'),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              const Text(
                'تغيير الدور: اختر صاحب الدور الجديد',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 4),
              for (final name in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_outline_rounded,
                    size: 19,
                    color: AppTheme.muted,
                  ),
                  title: Text(
                    _shownName(name),
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  subtitle: Text(
                    '${AppTr.tr('الدورة رقم')}: ${_roscaPlan.turnOf(name) ?? '—'}',
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                  onTap: () => Navigator.pop(sheetContext, name),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // تبديل: الجديد يأخذ هذه الدورة، وصاحبها السابق يأخذ دورة الجديد.
    final plan = _roscaPlan;
    var old = '';
    int? otherIndex;
    var otherPaid = false;
    for (final cycle in plan.cycles) {
      if (cycle.index == index) old = cycle.receiver;
      if (cycle.index != index && cycle.receiver == picked) {
        otherIndex = cycle.index;
        otherPaid = cycle.isPaidOut;
      }
    }
    if (picked == old) return;
    // من استلم مبلغه لا يتغيّر دوره.
    if (otherPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${_shownName(picked)} ${AppTr.tr('استلم مبلغه — لا يمكن تغيير دوره')}',
          ),
        ),
      );
      return;
    }
    var store = RoscaLedger.withReceiver(item.details, index, picked);
    if (otherIndex != null && old.isNotEmpty) {
      store = RoscaLedger.withReceiver(
        {...item.details, RoscaLedger.cyclesKey: store},
        otherIndex,
        old,
      );
    }
    final details = _withEvent(
      Map<String, String>.of(item.details)..[RoscaLedger.cyclesKey] = store,
      otherIndex != null && old.isNotEmpty
          ? '${AppTr.tr('تغيير الدور')}: ${_shownName(picked)} '
                '${AppTr.tr('صاحب الدورة')} $index، ${_shownName(old)} '
                '${AppTr.tr('صاحب الدورة')} $otherIndex'
          : '${AppTr.tr('تغيير الدور')}: ${_shownName(picked)} '
                '${AppTr.tr('صاحب الدورة')} $index',
    );
    final ok = await _persist(
      details,
      ask: otherIndex != null && old.isNotEmpty
          ? 'هل تريد جعل ${_shownName(picked)} صاحب الدورة $index، '
                'و${_shownName(old)} صاحب الدورة $otherIndex؟'
          : 'هل تريد جعل ${_shownName(picked)} صاحب الدورة $index؟',
      done: 'تم تغيير الدور',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  // ------------------------------------------- المصروفات والأرصدة
  /// أسماء أعضاء هذا الالتزام (المسؤول أولًا) — أساس كل الحسابات.
  List<String> get _ledgerMembers {
    final names = <String>[];
    for (final member in item.members) {
      final name = member.name.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  String _money(double value) =>
      '${value.abs().toStringAsFixed(value.abs() % 1 == 0 ? 0 : 2)} '
      '${item.currency}';

  /// «الحركات المالية»: مستطيلان يتبادلان — المصروفات أو الأرصدة — أو
  /// نموذج المصروف وحده حين يكون مفتوحًا.
  Widget _buildLedgerTab() {
    if (_expenseFormOpen) {
      return _InlineExpenseForm(
        members: _ledgerMembers,
        // مع وجود ميزانية، الأصل أن يُصرف منها لا من جيب أحد.
        payers: [
          if (SharedLedger.hasBudget(item.details)) SharedLedger.potPayer,
          ..._ledgerMembers,
        ],
        currency: item.currency,
        accent: item.color,
        // المسؤول: من الميزانية المشتركة. العضو: باسمه — ويغيّره من يشاء.
        initialPayer: _isManagerHere && SharedLedger.hasBudget(item.details)
            ? SharedLedger.potPayer
            : _myMemberName,
        onCancel: () => setState(() => _expenseFormOpen = false),
        onSave: _saveInlineExpense,
        activeOn: (name, day) => SharedLedger.activeOn(item.details, name, day),
        memberNote: _memberDateNote,
        lastRates: SharedLedger.lastRates(item.details),
        potLeft: SharedLedger.hasBudget(item.details)
            ? SharedLedger.remaining(item.details)
            : double.infinity,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPendingRequests(),
        _buildLedgerSwitch(),
        const SizedBox(height: 12),
        if (_ledgerView == 0) _buildExpensesView() else _buildBalancesView(),
      ],
    );
  }

  /// طلبات تنتظر موافقة المسؤول: مصروفات وميزانيات إضافية أرسلها الأعضاء.
  /// المسؤول يوافق أو يرفض من هنا، وغيره يرى أنها بانتظار الموافقة.
  Widget _buildPendingRequests() {
    final expenses = SharedLedger.expenses(item.details)
        .where((e) => e.isPending)
        .toList();
    final contributions = SharedLedger.contributions(item.details)
        .where((c) => c.isPending)
        .toList();
    if (expenses.isEmpty && contributions.isEmpty) {
      return const SizedBox.shrink();
    }
    final manager = _isManagerHere;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: AppTheme.goldSoft,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 18,
                color: AppTheme.goldDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'طلبات بانتظار موافقة المسؤول '
                  '(${expenses.length + contributions.length})',
                  textAlign: AppTr.alignEnd,
                  maxLines: 2,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.goldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final expense in expenses)
            _pendingRow(
              title: 'مصروف: ${expense.description}',
              subtitle:
                  'أرسله ${_shownName(expense.submittedBy.isEmpty ? expense.payer : expense.submittedBy)}'
                  ' · ${_withClock(expense.date, expense.id)}',
              amount: expense.amount,
              onDetails: () => _showExpenseRequestDetails(
                expense,
                onApprove: manager
                    ? () => _decideExpense(expense, true)
                    : null,
                onReject: manager
                    ? () => _decideExpense(expense, false)
                    : null,
              ),
              onApprove: manager ? () => _decideExpense(expense, true) : null,
              onReject: manager ? () => _decideExpense(expense, false) : null,
            ),
          for (final contribution in contributions)
            _pendingRow(
              title: '${_shownName(contribution.member)} ${AppTr.tr('أضاف')} '
                  '${AppTr.tr('ميزانية إضافية')}',
              subtitle:
                  'أرسلها ${_shownName(contribution.submittedBy.isEmpty ? contribution.member : contribution.submittedBy)}'
                  ' · ${_withClock(contribution.date, contribution.id)}',
              amount: contribution.amount,
              onDetails: () => _showContributionRequestDetails(
                contribution,
                onApprove: manager
                    ? () => _decideContribution(contribution, true)
                    : null,
                onReject: manager
                    ? () => _decideContribution(contribution, false)
                    : null,
              ),
              onApprove: manager
                  ? () => _decideContribution(contribution, true)
                  : null,
              onReject: manager
                  ? () => _decideContribution(contribution, false)
                  : null,
            ),
          if (!manager)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'يوافق عليها أو يرفضها مسؤول الالتزام ($_managerName)',
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.goldDark,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pendingRow({
    required String title,
    required String subtitle,
    required double amount,
    VoidCallback? onDetails,
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: AppTheme.page,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money(amount),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.title,
              ),
            ),
          ],
        ),
        // يُراجع الطلب كاملًا قبل الموافقة.
        if (onDetails != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.brandMid,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: onDetails,
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text(
                'عرض التفاصيل',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        if (onApprove != null) ...[
          const SizedBox(height: 8),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandMid,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(36),
                  ),
                  onPressed: onApprove,
                  child: const Text(
                    'موافقة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size.fromHeight(36),
                  ),
                  onPressed: onReject,
                  child: const Text(
                    'رفض',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  /// نافذة تفاصيل طلب مالي: كل الحقول، و«مرفق» يفتح الإيصال، والموافقة
  /// أو الرفض من داخلها للمسؤول.
  Future<void> _showRequestDetails({
    required String title,
    required List<(String, String)> rows,
    String receipt = '',
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                if (row.$2.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            row.$1,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 2,
                          child: Text(
                            row.$2,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (receipt.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final error = await DocumentStore.open(receipt.trim());
                    if (error == null || !dialogContext.mounted) return;
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(error)));
                  },
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
                backgroundColor: AppTheme.brandMid,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onApprove();
              },
              child: const Text('موافقة'),
            ),
        ],
      ),
    );
  }

  Future<void> _showExpenseRequestDetails(
    SharedExpense expense, {
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) => _showRequestDetails(
    title: AppTr.tr('تفاصيل المصروف'),
    rows: [
      (AppTr.tr('الوصف'), expense.description),
      (
        AppTr.tr('الفئة'),
        expense.subcategory.isEmpty
            ? expense.category
            : '${expense.category} › ${expense.subcategory}',
      ),
      (
        AppTr.tr('المبلغ'),
        expense.isForeign
            ? '${_money(expense.amount)} '
                  '(${_plainNum(expense.originalAmount)} ${expense.currency} × ${expense.rate})'
            : _money(expense.amount),
      ),
      (AppTr.tr('دفعه'), expense.payer),
      (AppTr.tr('التاريخ'), expense.date),
      (AppTr.tr('وقت التسجيل'), recordClock(expense.id)),
      (AppTr.tr('أرسله'), expense.submittedBy),
      (AppTr.tr('طريقة التقسيم'), expense.method),
      (AppTr.tr('المشاركون'), expense.participants.join('، ')),
      (AppTr.tr('ملاحظات'), expense.note),
      (AppTr.tr('الحالة'), expense.status),
      (
        AppTr.tr(expense.isRejected ? 'تاريخ ووقت الرفض' : 'تاريخ ووقت الموافقة'),
        expense.decidedAt,
      ),
    ],
    receipt: expense.receipt,
    onApprove: onApprove,
    onReject: onReject,
  );

  Future<void> _showContributionRequestDetails(
    SharedContribution contribution, {
    VoidCallback? onApprove,
    VoidCallback? onReject,
  }) => _showRequestDetails(
    title: AppTr.tr('تفاصيل الميزانية الإضافية'),
    rows: [
      (AppTr.tr('العضو'), contribution.member),
      (AppTr.tr('المبلغ'), _money(contribution.amount)),
      (AppTr.tr('التاريخ'), contribution.date),
      (AppTr.tr('وقت التسجيل'), recordClock(contribution.id)),
      (AppTr.tr('أرسلها'), contribution.submittedBy),
      (AppTr.tr('ملاحظات'), contribution.note),
      (AppTr.tr('الحالة'), contribution.status),
      (
        AppTr.tr(
          contribution.isRejected ? 'تاريخ ووقت الرفض' : 'تاريخ ووقت الموافقة',
        ),
        contribution.decidedAt,
      ),
    ],
    receipt: contribution.receipt,
    onApprove: onApprove,
    onReject: onReject,
  );

  Future<void> _decideExpense(SharedExpense expense, bool approve) async {
    final rows = [
      for (final row in SharedLedger.expenses(item.details))
        row.id == expense.id
            ? row.withStatus(
                approve
                    ? SharedExpense.statusApproved
                    : SharedExpense.statusRejected,
                at: recordStampNow(),
              )
            : row,
    ];
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.expensesKey] = SharedLedger.encodeExpenses(rows);
    final ok = await _persist(
      details,
      ask: approve ? 'هل تريد الموافقة على المصروف؟' : 'هل تريد رفض المصروف؟',
      done: approve ? 'تمت الموافقة على المصروف' : 'تم رفض المصروف',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _decideContribution(
    SharedContribution contribution,
    bool approve,
  ) async {
    final rows = [
      for (final row in SharedLedger.contributions(item.details))
        row.id == contribution.id
            ? row.withStatus(
                approve
                    ? SharedExpense.statusApproved
                    : SharedExpense.statusRejected,
                at: recordStampNow(),
              )
            : row,
    ];
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.contributionsKey] = SharedLedger.encodeContributions(
        rows,
      );
    final ok = await _persist(
      details,
      ask: approve
          ? 'هل تريد الموافقة على الميزانية الإضافية؟'
          : 'هل تريد رفض الميزانية الإضافية؟',
      done: approve
          ? 'تمت الموافقة على الميزانية الإضافية'
          : 'تم رفض الميزانية الإضافية',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Widget _buildLedgerSwitch() {
    Widget box(int index, String label, IconData icon) {
      final selected = _ledgerView == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          onTap: () => setState(() => _ledgerView = index),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? item.color.withValues(alpha: 0.12)
                  : AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              textDirection: AppTr.uiDir,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? item.color : AppTheme.muted,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? item.color : AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      textDirection: AppTr.uiDir,
      children: [
        box(0, 'المصروفات', Icons.receipt_long_outlined),
        const SizedBox(width: 10),
        box(1, 'الأرصدة', Icons.balance_rounded),
      ],
    );
  }

  Widget _buildExpensesView() {
    final all = SharedLedger.expenses(item.details).reversed.toList();
    final category = _expenseCategoryFilter;
    final payer = _expensePayerFilter;
    final status = _expenseStatusFilter;
    bool statusMatch(SharedExpense e) => switch (status) {
      'معتمدة' => e.isApproved,
      'بانتظار الموافقة' => e.isPending,
      'مرفوضة' => e.isRejected,
      _ => true,
    };
    final expenses = all
        .where(
          (e) =>
              (category == 'الكل' || e.category == category) &&
              (payer.isEmpty || e.payer == payer) &&
              statusMatch(e),
        )
        .toList();
    if (_expenseSort == _expenseSorts[1]) {
      final oldest = expenses.reversed.toList();
      expenses
        ..clear()
        ..addAll(oldest);
    } else if (_expenseSort == _expenseSorts[2]) {
      expenses.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (_expenseSort == _expenseSorts[3]) {
      expenses.sort((a, b) => a.amount.compareTo(b.amount));
    }
    // مع فلتر «بانتظار الموافقة» أو «مرفوضة» يُجمع ما ظهر؛ وإلا المعتمد فقط.
    final spent = expenses
        .where((e) => status == 'الكل' || status == 'معتمدة' ? e.isApproved : true)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final filtered =
        category != 'الكل' || payer.isNotEmpty || status != 'الكل';
    final filterLabel = [
      if (payer.isNotEmpty)
        payer == SharedLedger.potPayer
            ? 'ما صُرف من الميزانية المشتركة'
            : 'ما دفعه ${_shownName(payer)}',
      if (category != 'الكل') category,
      if (status != 'الكل') status,
    ].join(' · ');
    return _tabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            // فلتر عضو: «إجمالي المصروفات» = كل ما دفعه؛ فلتر فئة: باسمها.
            title: filtered && payer.isEmpty
                ? 'إجمالي $filterLabel: ${_money(spent)}'
                : 'إجمالي المصروفات: ${_money(spent)}',
            icon: Icons.receipt_long_outlined,
            accent: item.color,
            onAdd: () => setState(() => _expenseFormOpen = true),
          ),
          const SizedBox(height: 8),
          // سطر خفيف تحت +: جملة تدعو للتحليل، وزر الفلتر في آخر السطر.
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: filtered
                    ? Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: item.color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rPill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                textDirection: AppTr.uiDir,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'عرض: $filterLabel',
                                      maxLines: 2,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: item.color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => setState(() {
                                      _expenseCategoryFilter = 'الكل';
                                      _expensePayerFilter = '';
                                      _expenseStatusFilter = 'الكل';
                                    }),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: item.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : InkWell(
                        onTap: _openExpenseInsights,
                        child: Text(
                          'اعرف من دفع وأين تركّز الإنفاق',
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rIcon),
                // زر الفلتر: من دفع، الفئة، الحالة، الترتيب.
                onTap: _openExpenseFilter,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filtered
                        ? item.color
                        : item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rIcon),
                  ),
                  child: Icon(
                    Icons.filter_list_rounded,
                    size: 19,
                    color: filtered ? Colors.white : item.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text(
                filtered
                    ? 'لا توجد مصروفات ضمن هذا الفلتر'
                    : 'لا توجد مصاريف بعد\nأضف أول مصروف لتبدأ متابعة الحساب',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            for (final expense in expenses) _buildExpenseRow(expense),
        ],
      ),
    );
  }

  /// «من دفع وأين تركّز الإنفاق»: مستطيلان — «حسب العضو» يمينًا و«حسب
  /// الفئة» يسارًا — مع ترتيب من الأعلى للأدنى أو العكس. الضغط على أي سطر
  /// يصفّي القائمة عليه، ويمكن الجمع بين عضو وفئة.
  Future<void> _openExpenseInsights() async {
    final expenses = SharedLedger.approvedExpenses(item.details);
    final total = SharedLedger.total(item.details);
    // كل الأعضاء يظهرون ولو لم يدفعوا شيئًا (صفر)، فيُرى الأعلى والأقل
    // دفعًا معًا. والميزانية المشتركة تظهر فقط إن صُرف منها.
    final byPayer = <String, double>{
      for (final name in _ledgerMembers) name: 0,
    };
    for (final expense in expenses) {
      byPayer[expense.payer] = (byPayer[expense.payer] ?? 0) + expense.amount;
    }
    // كل الفئات كذلك — ما لم يُصرف فيها يظهر بصفر في آخر الترتيب — ومعها
    // أي فئة مخصّصة أُضيفت من «إضافة أخرى».
    final byCategory = <String, double>{
      for (final name in SharedExpense.categoryGroups.keys) name: 0,
    };
    for (final entry in SharedLedger.totalsByCategory(item.details)) {
      byCategory[entry.key] = entry.value;
    }
    var byMember = true;
    var highestFirst = true;

    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final source = byMember ? byPayer : byCategory;
          final rows = source.entries.toList()
            ..sort(
              (a, b) => highestFirst
                  ? b.value.compareTo(a.value)
                  : a.value.compareTo(b.value),
            );
          Widget modeBox(bool member, String label, IconData icon) {
            final selected = byMember == member;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                onTap: () => setSheetState(() => byMember = member),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? item.color.withValues(alpha: 0.12)
                        : AppTheme.field,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    textDirection: AppTr.uiDir,
                    children: [
                      Icon(
                        icon,
                        size: 17,
                        color: selected ? item.color : AppTheme.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: selected ? item.color : AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Directionality(
            textDirection: AppTr.uiDir,
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  children: [
                    const Text(
                      'من دفع وأين تركّز الإنفاق',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'إجمالي المصروفات ${_money(total)} — اضغط أي سطر '
                      'لعرض مصروفاته وحدها',
                      textAlign: AppTr.alignEnd,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // يمين: حسب العضو — يسار: حسب الفئة.
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        modeBox(true, 'حسب العضو', Icons.person_outline_rounded),
                        const SizedBox(width: 10),
                        modeBox(false, 'حسب الفئة', Icons.category_outlined),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                      onTap: () =>
                          setSheetState(() => highestFirst = !highestFirst),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            Icon(
                              highestFirst
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              size: 17,
                              color: item.color,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                highestFirst
                                    ? 'الترتيب: من الأعلى للأدنى'
                                    : 'الترتيب: من الأدنى للأعلى',
                                textAlign: AppTr.alignEnd,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: item.color,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.swap_vert_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'لا توجد مصروفات معتمدة بعد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted,
                          ),
                        ),
                      )
                    else
                      for (final entry in rows)
                        InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.rInner),
                          // مصروفاته في نافذة منبثقة فوق هذه — بلا خروج.
                          onTap: () => _showExpensesSheet(
                            payer: byMember ? entry.key : '',
                            category: byMember ? '' : entry.key,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  textDirection: AppTr.uiDir,
                                  children: [
                                    Icon(
                                      byMember
                                          ? (entry.key == SharedLedger.potPayer
                                                ? Icons
                                                      .account_balance_wallet_outlined
                                                : Icons.person_outline_rounded)
                                          : categoryIconFor(entry.key),
                                      size: 17,
                                      color: item.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _shownName(entry.key),
                                        textAlign: AppTr.alignEnd,
                                        maxLines: 2,
                                        softWrap: true,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.title,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_money(entry.value)} · '
                                      '${total <= 0 ? 0 : (entry.value / total * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: item.color,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.rPill,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: total <= 0
                                        ? 0.0
                                        : (entry.value / total).clamp(0.0, 1.0).toDouble(),
                                    minHeight: 5,
                                    backgroundColor: AppTheme.field,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      item.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    if (_expenseCategoryFilter != 'الكل' ||
                        _expensePayerFilter.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, ('clear', '')),
                        child: const Text(
                          'عرض كل المصروفات',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.$1 == 'payer') {
        _expensePayerFilter = picked.$2;
      } else if (picked.$1 == 'category') {
        _expenseCategoryFilter = picked.$2;
      } else {
        _expenseCategoryFilter = 'الكل';
        _expensePayerFilter = '';
        _expenseStatusFilter = 'الكل';
      }
    });
  }

  /// بطاقة المصروف: الاسم الذي كتبه المستخدم وطريقة التقسيم، ثم الفئة،
  /// ثم التاريخ، ثم من دفع والمبلغ.
  Widget _buildExpenseRow(SharedExpense expense) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: AppTheme.page,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      border: Border.all(color: AppTheme.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                expense.description.trim().isEmpty
                    ? expense.category
                    : expense.description.trim(),
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
            // «مرفق» بنص وأيقونة: يُفهم أن الضغط يفتح الإيصال.
            if (expense.receipt.trim().isNotEmpty) ...[
              const SizedBox(width: 6),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: item.color,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () async {
                  final error = await DocumentStore.open(expense.receipt);
                  if (error == null || !mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                },
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: const Text(
                  'مرفق',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Text(
                expense.method,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.body,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Icon(
              categoryIconFor(
                expense.subcategory.isEmpty
                    ? expense.category
                    : expense.subcategory,
              ),
              size: 15,
              color: item.color,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                expense.subcategory.isEmpty
                    ? expense.category
                    : '${expense.category} › ${expense.subcategory}',
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: item.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // التاريخ والساعة في سطر الفئة نفسه.
            Text(
              _withClock(expense.date, expense.id),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
        if (!expense.isApproved) ...[
          const SizedBox(height: 6),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: expense.isRejected
                      ? AppTheme.dangerSoft
                      : AppTheme.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  expense.isRejected
                      ? 'مرفوض — لا يدخل الحساب'
                      : 'بانتظار موافقة المسؤول',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: expense.isRejected
                        ? AppTheme.danger
                        : AppTheme.goldDark,
                  ),
                ),
              ),
            ],
          ),
        ],

        if (expense.decidedAt.isNotEmpty && !expense.isPending)
          Text(
            '${AppTr.tr(expense.isRejected ? 'رُفض في' : 'اعتُمد في')} '
            '${expense.decidedAt}',
            textAlign: AppTr.alignEnd,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: expense.isRejected ? AppTheme.danger : AppTheme.brandMid,
            ),
          ),
        const SizedBox(height: 4),
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                'بواسطة ${_shownName(expense.payer)}',
                textAlign: AppTr.alignEnd,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.body,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money(expense.amount),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                // صُرف بعملة أخرى: المبلغ الأصلي وسعر الصرف.
                if (expense.isForeign)
                  Text(
                    '${_plainNum(expense.originalAmount)} ${AppTr.tr(expense.currency)}'
                    ' × ${expense.rate}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
              ],
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppTheme.danger,
              ),
              onPressed: () => _deleteExpense(expense),
            ),
          ],
        ),
      ],
    ),
  );

  /// الأرصدة كما رُسمت: نوع التحصيل، ثم الأرقام الإجمالية، ثم بطاقة لكل
  /// عضو (ما دفعه وله/عليه)، ثم تصفية الحساب للعرض فقط — التسوية نفسها
  /// من زر «تسوية الحساب» في أعلى الصفحة.
  Widget _buildBalancesView() {
    final members = _ledgerMembers;
    final balances = SharedLedger.balances(item.details, members);
    final transfers = SharedLedger.settleTransfers(item.details, members);
    final lump = _isLumpSum;
    final budget = SharedLedger.budget(item.details);
    final spent = SharedLedger.total(item.details);
    // يشمل ما رُدّ من الميزانية لعضو غادر.
    final left = SharedLedger.remaining(item.details);
    return _tabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            title: 'الأرصدة',
            icon: Icons.balance_rounded,
            accent: item.color,
            // مع الدفعة المقطوعة: + يضيف مساهمة إضافية. مع الدفع الفردي لا
            // مساهمات، فيضيف مصروفًا دفعه أحدهم.
            onAdd: lump ? _openContributionForm : _openExpenseForm,
          ),
          const SizedBox(height: 10),
          Text(
            lump ? _collectLumpSum : _collectIndividual,
            textAlign: AppTr.alignEnd,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: item.color,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            child: lump
                ? Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      _roscaMetric(
                        'إجمالي الميزانية',
                        _money(budget),
                        AppTheme.title,
                      ),
                      _roscaMetric(
                        'إجمالي المصروفات',
                        _money(spent),
                        AppTheme.danger,
                      ),
                      _roscaMetric(
                        left < 0 ? 'العجز' : 'المتبقي',
                        _money(left),
                        left < 0 ? AppTheme.danger : AppTheme.brandMid,
                      ),
                    ],
                  )
                : Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: Text(
                          'إجمالي ما دُفع',
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      Text(
                        _money(spent),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: item.color,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            'الأعضاء:',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'أضف الأعضاء أولًا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            // رابط المصروفات في تبويب الأعضاء والمصروفات فقط.
            for (final name in members)
              _buildMemberMoneyCard(name, balances[name] ?? 0, lump),
          // المساهمات والتسويات المسجّلة بإيصالاتها في نافذة منبثقة.
          InkWell(
            onTap: _showBalanceReceipts,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 16,
                    color: item.color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'عرض إيصالات الأرصدة',
                      textAlign: AppTr.alignEnd,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: item.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: AppTheme.hairline),
          const SizedBox(height: 12),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              const Icon(
                Icons.handshake_outlined,
                size: 18,
                color: AppTheme.title,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تصفية الحساب',
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
          const SizedBox(height: 8),
          if (transfers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا توجد مبالغ معلّقة بين الأعضاء',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else ...[
            ?_potHolderLine(),
            const SizedBox(height: 8),
            _netTable(members),
            const SizedBox(height: 10),
            if (!SharedLedger.hasBudget(item.details))
              if (_pairDebts(members) case final pairs when pairs.isNotEmpty)
                ...[_pairsBox(pairs), const SizedBox(height: 10)],
          ],
        ],
      ),
    );
  }

  String _plain(double value) =>
      value.toStringAsFixed(value.abs() % 1 == 0 ? 0 : 2);

  /// بطاقة العضو المالية — تُستعمل في الأرصدة وفي تبويب الأعضاء:
  /// مع الدفعة المقطوعة «المساهمة 3000 + 1000 = 4000»، ومع الدفع الفردي
  /// «إجمالي ما دفعه 4000»، ثم صندوقا «له» و«عليه» دائمًا.
  /// سطر الرقم التعريفي تحت اسم العضو (FND-XXXX-XXXX).
  Widget _memberIdLine(String name) {
    final id = _SharedCommitmentsScreenState._idInMemberName(name);
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        id,
        textAlign: AppTr.alignEnd,
        maxLines: 1,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.muted,
        ),
      ),
    );
  }

  Widget _buildMemberMoneyCard(
    String name,
    double net,
    bool lump, {
    String role = '',
    bool linkToExpenses = false,
    bool showId = false,
  }) {
    final base = SharedLedger.baseOf(item.details, name);
    final extra = SharedLedger.extraOf(item.details, name);
    final paid = SharedLedger.paidInOf(item.details, name);
    final pocket = paid - base - extra;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.page,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _shownName(name),
                      textAlign: AppTr.alignEnd,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    // الرقم التعريفي في تبويب الأعضاء فقط، في سطر تحت الاسم.
                    if (showId) _memberIdLine(name),
                  ],
                ),
              ),
              if (role.isNotEmpty)
                // لون الدور موحّد في كل مكان: المسؤول ونائبه ذهبي، والعضو
                // رمادي — كبطاقة الجمعية.
                Builder(
                  builder: (context) {
                    final member =
                        role.split(' · ').first.trim() == AppTr.tr('عضو');
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: member ? AppTheme.field : AppTheme.goldSoft,
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: member ? AppTheme.body : AppTheme.goldDark,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lump
                ? (extra > 0.01
                      ? 'المساهمة ${_plain(base)} + ${_plain(extra)} = '
                            '${_money(base + extra)}'
                      : 'المساهمة ${_money(base)}')
                : 'إجمالي ما دفعه ${_money(paid)}',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.body,
            ),
          ),
          if (lump && pocket > 0.01) ...[
            const SizedBox(height: 2),
            Text(
              'ودفع من جيبه ${_money(pocket)}',
              textAlign: AppTr.alignEnd,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              _moneyBox('له', net > 0.01 ? net : 0, AppTheme.brandMid),
              const SizedBox(width: 8),
              _moneyBox('عليه', net < -0.01 ? -net : 0, AppTheme.danger),
            ],
          ),
          if (linkToExpenses) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showPayerExpenses(name),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 15,
                    color: item.color,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'عرض مصروفات العضو',
                      textAlign: AppTr.alignEnd,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: item.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ميزانية إضافية في الأرصدة: من أضافها، والمبلغ، والوقت، وحالتها،
  /// وإيصالها يُفتح بالضغط.
  Widget _contributionRow(SharedContribution c) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
    decoration: BoxDecoration(
      color: AppTheme.page,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      border: Border.all(color: AppTheme.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                '${_shownName(c.member)} ${AppTr.tr('أضاف')} '
                '${_money(c.amount)}',
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
            if (!c.isApproved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.isRejected ? AppTheme.dangerSoft : AppTheme.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  c.isRejected ? 'مرفوضة' : 'بانتظار الموافقة',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: c.isRejected ? AppTheme.danger : AppTheme.goldDark,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                c.note.trim().isEmpty
                    ? _withClock(c.date, c.id)
                    : '${_withClock(c.date, c.id)} · ${c.note}',
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
            if (c.receipt.trim().isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: item.color,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () async {
                  final error = await DocumentStore.open(c.receipt);
                  if (error == null || !mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                },
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text(
                  'الإيصال',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  /// «عرض إيصالات الأرصدة»: المساهمات والتسويات المسجّلة، الأحدث أولًا،
  /// وإيصال كل منها يُفتح بالضغط.
  Future<void> _showBalanceReceipts() {
    final contributions = SharedLedger.contributions(item.details)
        .reversed
        .toList();
    final settlements = SharedLedger.settlements(item.details)
        .reversed
        .toList();
    final baseReceipts = _balanceReceipts(item.details);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        text,
        textAlign: AppTr.alignEnd,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: AppTheme.title,
        ),
      ),
    );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    const Expanded(
                      child: Text(
                        'إيصالات الأرصدة',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.muted,
                    ),
                  ],
                ),
                if (baseReceipts.isNotEmpty) ...[
                  label('إيصالات المساهمات الأساسية'),
                  for (final path in baseReceipts)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.rInner),
                        border: Border.all(color: AppTheme.hairline),
                      ),
                      child: Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          Expanded(
                            child: Text(
                              path.split(RegExp(r'[\\/]')).last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: AppTr.alignEnd,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.title,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: item.color,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () async {
                              final error = await DocumentStore.open(path);
                              if (error == null || !mounted) return;
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(error)));
                            },
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 16,
                            ),
                            label: const Text(
                              'الإيصال',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (contributions.isEmpty &&
                    settlements.isEmpty &&
                    baseReceipts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'لا توجد إيصالات بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                if (contributions.isNotEmpty) ...[
                  label('المساهمات'),
                  for (final c in contributions) _contributionRow(c),
                ],
                if (settlements.isNotEmpty) ...[
                  label('التسويات'),
                  for (final s in settlements) _settlementReceiptRow(s),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// تسوية مسجّلة: من دفع لمن، والمبلغ، والتاريخ، وإيصالها.
  Widget _settlementReceiptRow(SharedSettlement s) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      border: Border.all(color: AppTheme.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                _transferText(
                  SharedTransfer(from: s.from, to: s.to, amount: s.amount),
                ),
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money(s.amount),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: item.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                s.date,
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
            if (s.receipt.trim().isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: item.color,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () async {
                  final error = await DocumentStore.open(s.receipt);
                  if (error == null || !mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                },
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text(
                  'الإيصال',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  'بلا إيصال',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  /// من الأعضاء أو الأرصدة: ما دفعه هذا العضو في نافذة منبثقة، بلا انتقال.
  void _showPayerExpenses(String name) =>
      _showExpensesSheet(payer: name, withShare: true);

  /// مصروف واحد داخل النافذة المنبثقة: الاسم والمبلغ، ثم الفئة والتاريخ،
  /// ثم من دفع، وحالته إن لم يُعتمد.
  Widget _expenseSheetRow(SharedExpense e) {
    final pending = e.isPending;
    final rejected = e.isRejected;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: Text(
                  e.description.trim().isEmpty
                      ? e.category
                      : e.description.trim(),
                  textAlign: AppTr.alignEnd,
                  maxLines: 2,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _money(e.amount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: rejected ? AppTheme.muted : item.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(
                categoryIconFor(
                  e.subcategory.isEmpty ? e.category : e.subcategory,
                ),
                size: 14,
                color: item.color,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  e.subcategory.isEmpty
                      ? e.category
                      : '${e.category} › ${e.subcategory}',
                  textAlign: AppTr.alignEnd,
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: item.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _withClock(e.date, e.id),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'بواسطة ${_shownName(e.payer)}',
            textAlign: AppTr.alignEnd,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.body,
            ),
          ),
          if (pending || rejected) ...[
            const SizedBox(height: 6),
            Row(
              textDirection: AppTr.uiDir,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: rejected ? AppTheme.dangerSoft : AppTheme.goldSoft,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    rejected
                        ? 'مرفوض — لا يدخل الحساب'
                        : 'بانتظار موافقة المسؤول',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: rejected ? AppTheme.danger : AppTheme.goldDark,
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

  /// مصروفات عضو أو فئة في نافذة منبثقة فوق الصفحة نفسها — لا انتقال إلى
  /// تبويب آخر. مع العضو يظهر أيضًا نصيبه من كل المصروفات.
  Future<void> _showExpensesSheet({
    String payer = '',
    String category = '',
    bool withShare = false,
  }) {
    final rows = SharedLedger.expenses(item.details)
        .reversed
        .where(
          (e) =>
              (payer.isEmpty || e.payer == payer) &&
              (category.isEmpty || e.category == category),
        )
        .toList();
    final approved = rows
        .where((e) => e.isApproved)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final title = payer.isNotEmpty
        ? (payer == SharedLedger.potPayer
              ? AppTr.tr('ما صُرف من الميزانية المشتركة')
              : '${AppTr.tr('ما دفعه')} ${_shownName(payer)}')
        : '${AppTr.tr('مصروفات')} $category';
    final share = withShare && payer.isNotEmpty && payer != SharedLedger.potPayer
        ? SharedLedger.shareOfMember(item.details, payer)
        : null;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        textAlign: AppTr.alignEnd,
                        maxLines: 2,
                        softWrap: true,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.muted,
                    ),
                  ],
                ),
                // إجمالي المصروفات، وبجانبه ما ينتظر الاعتماد، ثم كلها.
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Expanded(
                      child: Text(
                        '${AppTr.tr('إجمالي المصروفات')}: ${_money(approved)}',
                        textAlign: AppTr.alignEnd,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: item.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${AppTr.tr('مصروفات بانتظار الاعتماد')}: '
                      '${rows.where((e) => e.isPending).length}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.goldDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'لا توجد مصروفات هنا بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  )
                else
                  for (final e in rows) _expenseSheetRow(e),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// فلتر المصروفات: ترتيب النتائج، ومن دفع، والفئة بقوائم منسدلة، وحالة
  /// المصروف بأربعة خيارات، ثم «عرض النتيجة» و«مسح الفلاتر».
  Future<void> _openExpenseFilter() async {
    final all = SharedLedger.expenses(item.details);
    final payers = <String>[
      ..._ledgerMembers,
      if (all.any((e) => e.payer == SharedLedger.potPayer))
        SharedLedger.potPayer,
    ];
    final categories = {for (final e in all) e.category}.toList();
    var payer = _expensePayerFilter;
    var category = _expenseCategoryFilter;
    var status = _expenseStatusFilter;
    var sort = _expenseSort;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget section(String title, String hint, Widget child) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          );

          final fieldBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.rField),
            borderSide: const BorderSide(color: AppTheme.hairline),
          );
          Widget box(
            String key,
            String value,
            List<String> options,
            ValueChanged<String> onPick, {
            String Function(String value)? labelOf,
          }) => DropdownButtonFormField<String>(
            // المفتاح يتغيّر مع القيمة فتُعاد القائمة بعد «مسح الفلاتر».
            key: ValueKey('$key|$value'),
            initialValue: options.contains(value) ? value : options.first,
            isExpanded: true,
            iconEnabledColor: AppTheme.title,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppTheme.surface,
              border: fieldBorder,
              enabledBorder: fieldBorder,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    labelOf?.call(option) ?? option,
                    maxLines: 2,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
            onChanged: (picked) =>
                setSheetState(() => onPick(picked ?? options.first)),
          );

          Widget statusTile(String value) {
            final selected = status == value;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                onTap: () => setSheetState(() => status = value),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? item.color.withValues(alpha: 0.10)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                    border: Border.all(
                      color: selected ? item.color : AppTheme.hairline,
                    ),
                  ),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 18,
                        color: selected ? item.color : AppTheme.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          value,
                          maxLines: 2,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: selected ? item.color : AppTheme.body,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Directionality(
            textDirection: AppTr.uiDir,
            child: SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD5DEDB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          const Expanded(
                            child: Text(
                              'فلتر المصروفات',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: AppTr.tr('إغلاق'),
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      section(
                        'ترتيب النتائج',
                        'اختر طريقة ترتيب المصروفات',
                        box('sort', sort, _expenseSorts, (v) => sort = v),
                      ),
                      section(
                        'من دفع؟',
                        'اختر عضوًا أو الكل',
                        box(
                          'payer',
                          payer,
                          ['', ...payers],
                          (v) => payer = v,
                          labelOf: (v) =>
                              v.isEmpty ? AppTr.tr('الكل') : _shownName(v),
                        ),
                      ),
                      section(
                        'الفئة',
                        'اختر فئة أو جميع الفئات',
                        box(
                          'category',
                          category,
                          ['الكل', ...categories],
                          (v) => category = v,
                          labelOf: (v) =>
                              v == 'الكل' ? AppTr.tr('جميع الفئات') : v,
                        ),
                      ),
                      section(
                        'حالة المصروف',
                        'اختر حالة واحدة',
                        Column(
                          children: [
                            Row(
                              textDirection: AppTr.uiDir,
                              children: [
                                statusTile(_expenseStatuses[0]),
                                const SizedBox(width: 8),
                                statusTile(_expenseStatuses[2]),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              textDirection: AppTr.uiDir,
                              children: [
                                statusTile(_expenseStatuses[1]),
                                const SizedBox(width: 8),
                                statusTile(_expenseStatuses[3]),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: item.color,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.rField,
                              ),
                            ),
                          ),
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: const Text(
                            'عرض النتيجة',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: () => setSheetState(() {
                            payer = '';
                            category = 'الكل';
                            status = 'الكل';
                            sort = _expenseSorts.first;
                          }),
                          child: const Text(
                            'مسح الفلاتر',
                            style: TextStyle(
                              fontSize: 12.5,
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
          );
        },
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _expensePayerFilter = payer;
      _expenseCategoryFilter = category;
      _expenseStatusFilter = status;
      _expenseSort = sort;
    });
  }

  Widget _moneyBox(String label, double value, Color color) {
    final active = value > 0.01;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.10) : AppTheme.field,
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _money(value),
                textAlign: TextAlign.left,
                maxLines: 3,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: active ? color : AppTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «تسوية الحساب»: التحويلات المقترحة كلها محدّدة، يُلغى تحديد ما لم يتم،
  /// وتُسجَّل الباقية تسويات دفعة واحدة. أو تسوية يدوية بمبلغ آخر.
  Future<void> _openSettleUpSheet() async {
    final members = _ledgerMembers;
    // مع الدفعة المقطوعة: يُرد المتبقي في الميزانية لكل عضو من رصيده، ثم
    // ما بين الأعضاء. «مسوّى» فقط إن لم يبقَ شيء من الاثنين.
    final transfers = SharedLedger.settleTransfers(item.details, members);
    // التحديد بالعضو: من له أو عليه شيء، وكلهم محدَّدون. تُسجَّل كل
    // تحويلات العضو المحدَّد.
    bool involves(SharedTransfer t, String name) =>
        t.from == name || t.to == name;
    final involved = <String>{
      for (final name in members)
        if (transfers.any((t) => involves(t, name))) name,
    };
    final picked = <String>{...involved};
    var receiptPath = '';
    // قبل المقاصة (دفع فردي): من يعطي من وكم، ثم النتيجة النهائية.
    final pairs = SharedLedger.hasBudget(item.details)
        ? const <(String, String, double, double)>[]
        : _pairDebts(members);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                const Text(
                  'تسوية الحساب',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 4),
                // بدل «تسوية الحساب للكل…»: عند من الميزانية المشتركة.
                if (transfers.isEmpty)
                  const Text(
                    'الحساب مسوّى — لا توجد مبالغ معلّقة بين الأعضاء',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  )
                else if (_potHolderLine() case final line?)
                  line,
                const SizedBox(height: 10),
                if (transfers.isNotEmpty) ...[
                  _netTable(
                    members,
                    selected: picked,
                    selectable: involved,
                    onToggle: (name, on) => setSheetState(() {
                      if (on) {
                        picked.add(name);
                      } else {
                        picked.remove(name);
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                if (pairs.isNotEmpty) ...[
                  _pairsBox(pairs),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                if (transfers.isNotEmpty) ...[
                  _receiptButton(
                    label: 'إرفاق إيصال',
                    path: receiptPath,
                    accent: item.color,
                    onTap: () async {
                      final path = await _pickReceiptFile(sheetContext);
                      if (path == null) return;
                      setSheetState(() => receiptPath = path);
                    },
                    onRemove: () => setSheetState(() => receiptPath = ''),
                  ),
                  const SizedBox(height: 10),
                ],
                if (transfers.isNotEmpty)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: picked.isEmpty
                        ? null
                        : () => Navigator.pop(sheetContext, 'record'),
                    child: Text(
                      'تسجيل التسوية (${picked.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    final selected = [
      for (var i = 0; i < transfers.length; i++)
        if (picked.any((name) => involves(transfers[i], name))) i,
    ];
    if (action != 'record' || selected.isEmpty) return;
    final now = DateTime.now();
    final stamp = now.millisecondsSinceEpoch;
    final rows = [
      ...SharedLedger.settlements(item.details),
      for (final i in selected)
        SharedSettlement(
          id: '${stamp + i}',
          from: transfers[i].from,
          to: transfers[i].to,
          amount: transfers[i].amount,
          date: '${now.day}/${now.month}/${now.year}',
          receipt: receiptPath,
        ),
    ];
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.settlementsKey] = SharedLedger.encodeSettlements(rows);
    // لم يبقَ شيء بعد هذه التسوية: يصير الالتزام «مكتملة».
    final fullySettled =
        SharedLedger.settleTransfers(details, members).isEmpty;
    final ok = await _persist(
      details,
      status: fullySettled ? 'مكتملة' : null,
      ask: 'هل تريد تسجيل التسوية؟',
      done: fullySettled
          ? 'تمت تسوية الحساب بالكامل — الحالة: مكتملة'
          : 'تم تسجيل التسوية',
    );
    if (!ok || !mounted) return;
    setState(() {});
    await _showSettlementReceipt(
      [for (final i in selected) transfers[i]],
      '${now.day}/${now.month}/${now.year}',
    );
  }

  /// الاسم ومعه صفته: «زين (عضو)» / «عبدالعزيز (المسؤول)».
  String _who(String name) {
    final role = _memberRole(name);
    final label = role == 'مسؤول' ? 'المسؤول' : role;
    return '${_shownName(name)} (${AppTr.tr(label)})';
  }

  /// حساب العضو: ما وضعه في الميزانية، وما دفعه من جيبه، ونصيبه من
  /// المصروفات، وما سُوّي له/منه سابقًا — ومجموعها رصيده (له/عليه).
  ({
    double base,
    double extra,
    double put,
    double pocket,
    double share,
    double potShare,
    double settled,
  })
  _memberMath(String name) {
    final base = SharedLedger.baseShares(item.details)[name] ?? 0;
    var extra = 0.0;
    for (final c in SharedLedger.approvedContributions(item.details)) {
      if (c.member == name) extra += c.amount;
    }
    final put = base + extra;
    var pocket = 0.0;
    var share = 0.0;
    var potShare = 0.0;
    for (final e in SharedLedger.approvedExpenses(item.details)) {
      if (e.payer == name) pocket += e.amount;
      final mine = e.shareOf()[name] ?? 0;
      share += mine;
      if (e.payer == SharedLedger.potPayer) potShare += mine;
    }
    var settled = 0.0;
    for (final s in SharedLedger.settlements(item.details)) {
      if (s.from == name) settled += s.amount;
      if (s.to == name) settled -= s.amount;
    }
    return (
      base: base,
      extra: extra,
      put: put,
      pocket: pocket,
      share: share,
      potShare: potShare,
      settled: settled,
    );
  }

  /// المال الموجود فعلًا في الميزانية المشتركة الآن.
  double _potCash() {
    var cash = SharedLedger.budget(item.details) +
        SharedLedger.potSettlementsNet(item.details);
    for (final e in SharedLedger.approvedExpenses(item.details)) {
      if (e.payer == SharedLedger.potPayer) cash -= e.amount;
    }
    return cash;
  }

  /// «له 350» / «عليه 150» / «متوازن».
  (String, Color) _netLook(double net) => net > 0.009
      ? ('${AppTr.tr('له')} ${_money(net)}', AppTheme.brandMid)
      : net < -0.009
      ? ('${AppTr.tr('عليه')} ${_money(-net)}', AppTheme.danger)
      : (AppTr.tr('متوازن'), AppTheme.muted);

  /// جدول «صافي المبالغ المستحقة»: العضو وصافي تسويته، وبجانب كل رقم زر
  /// يعرض كيف جاء.
  Widget _netTable(
    List<String> members, {
    Set<String> selected = const <String>{},
    Set<String> selectable = const <String>{},
    void Function(String name, bool on)? onToggle,
  }) {
    const head = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w900,
      color: AppTheme.muted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'النتيجة النهائية للتسوية',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: AppTheme.title,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: AppTr.uiDir,
                children: [
                  if (onToggle != null) const SizedBox(width: 34),
                  Expanded(
                    child: Text(
                      'العضو',
                      textAlign: AppTr.alignEnd,
                      style: head,
                    ),
                  ),
                  const Text('صافي التسوية', style: head),
                  const SizedBox(width: 26),
                ],
              ),
              for (final name in members) ...[
                Container(height: 1, color: AppTheme.hairline),
                InkWell(
                  onTap: () => _showMemberMath(name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        // تحديد العضو لتسجيل تسويته (من له أو عليه شيء).
                        if (onToggle != null)
                          SizedBox(
                            width: 34,
                            child: Checkbox(
                              value: selected.contains(name),
                              activeColor: item.color,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: selectable.contains(name)
                                  ? (value) => onToggle(name, value == true)
                                  : null,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            _who(name),
                            textAlign: AppTr.alignEnd,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        if (_netLook(_memberNet(name)) case (final label, final color))
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        const SizedBox(width: 6),
                        // زر التفاصيل: كيف جاء صافي التسوية.
                        Icon(
                          Icons.info_outline_rounded,
                          size: 19,
                          color: item.color,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// «الميزانية المشتركة عند (عبدالعزيز المسؤول) — الموجود فيها الآن 975».
  Widget? _potHolderLine() {
    final holder = _managerName;
    if (!SharedLedger.hasBudget(item.details) || holder.isEmpty) return null;
    return Text(
      '${AppTr.tr('الميزانية المشتركة عند')} '
      '(${_shownName(holder)} ${AppTr.tr('المسؤول')}) — '
      '${AppTr.tr('الموجود فيها الآن')} ${_money(_potCash())}',
      textAlign: AppTr.alignEnd,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.45,
        fontWeight: FontWeight.w700,
        color: AppTheme.muted,
      ),
    );
  }

  double _memberNet(String name) {
    final m = _memberMath(name);
    return m.put + m.pocket - m.share + m.settled;
  }

  /// نافذة «كيف جاء صافي التسوية» لعضو: المساهمة + الإضافي + ما دفعه من
  /// جيبه − حصته من المصروفات = صافي التسوية. علامة × لإغلاقها.
  Future<void> _showMemberMath(String name) {
    final m = _memberMath(name);
    final lump = SharedLedger.hasBudget(item.details);
    final rows = <(String, double, String)>[
      if (lump) ('المساهمة', m.base, '+'),
      if (lump && m.extra > 0.009) ('مبلغ إضافي للمساهمة', m.extra, '+'),
      if (!lump || m.pocket > 0.009) ('مبلغ دفعه من جيبه', m.pocket, '+'),
      ('حصته من المصروفات', m.share, '−'),
      if (m.settled > 0.009) ('دفعه في تسويات سابقة', m.settled, '+'),
      if (m.settled < -0.009) ('استلمه في تسويات سابقة', -m.settled, '−'),
    ];
    final (netLabel, netColor) = _netLook(_memberNet(name));
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Dialog(
          backgroundColor: AppTheme.page,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Expanded(
                      child: Text(
                        _who(name),
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    // × في الأعلى على اليسار.
                    IconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Text(
                  'كيف جاء صافي التسوية',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            textDirection: AppTr.uiDir,
                            children: [
                              Expanded(
                                child: Text(
                                  AppTr.tr(rows[i].$1),
                                  textAlign: AppTr.alignEnd,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.body,
                                  ),
                                ),
                              ),
                              Text(
                                i == 0
                                    ? _money(rows[i].$2)
                                    : '${rows[i].$3} ${_money(rows[i].$2)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: rows[i].$3 == '−' && i > 0
                                      ? AppTheme.danger
                                      : AppTheme.title,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1),
                      ),
                      Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          const Expanded(
                            child: Text(
                              '= صافي التسوية',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.title,
                              ),
                            ),
                          ),
                          Text(
                            netLabel,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: netColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «ما على كل عضو قبل المقاصة» (دفع فردي): أ يعطي ب، ب يعطي أ، ثم الصافي.
  Widget _pairsBox(List<(String, String, double, double)> pairs) {
    const infoStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: AppTheme.body,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ما على كل عضو قبل المقاصة',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 6),
          for (final (a, b, ab, ba) in pairs) ...[
            if (ab >= 0.01)
              Text(
                '${_shownName(a)} ${AppTr.tr('يعطي')} '
                '${_shownName(b)} ${_money(ab)}',
                textAlign: AppTr.alignEnd,
                style: infoStyle,
              ),
            if (ba >= 0.01)
              Text(
                '${_shownName(b)} ${AppTr.tr('يعطي')} '
                '${_shownName(a)} ${_money(ba)}',
                textAlign: AppTr.alignEnd,
                style: infoStyle,
              ),
            if (ab >= 0.01 && ba >= 0.01)
              Text(
                (ab - ba).abs() < 0.01
                    ? AppTr.tr('متساويان — لا أحد يعطي الآخر شيئًا')
                    : '${AppTr.tr('الصافي:')} '
                          '${_shownName(ab > ba ? a : b)} '
                          '${AppTr.tr('يعطي')} '
                          '${_shownName(ab > ba ? b : a)} '
                          '${_money((ab - ba).abs())}',
                textAlign: AppTr.alignEnd,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w900,
                  color: item.color,
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  /// قبل المقاصة (دفع فردي): كم يعطي كل عضو الآخر من المصروفات بعد خصم
  /// التسويات المسجّلة — «هو يعطيني 100 وأنا أعطيه 50». (أ، ب، أ←ب، ب←أ).
  List<(String, String, double, double)> _pairDebts(List<String> members) {
    final names = members.toSet();
    final owe = <String, Map<String, double>>{};
    double get(String a, String b) => owe[a]?[b] ?? 0;
    void put(String a, String b, double v) => (owe[a] ??= {})[b] = v;
    for (final e in SharedLedger.approvedExpenses(item.details)) {
      if (!names.contains(e.payer)) continue;
      e.shareOf().forEach((name, share) {
        if (name == e.payer || !names.contains(name) || share <= 0) return;
        put(name, e.payer, get(name, e.payer) + share);
      });
    }
    for (final s in SharedLedger.settlements(item.details)) {
      if (!names.contains(s.from) || !names.contains(s.to)) continue;
      final owed = get(s.from, s.to);
      final take = owed < s.amount ? owed : s.amount;
      put(s.from, s.to, owed - take);
      final extra = s.amount - take;
      if (extra > 0.009) put(s.to, s.from, get(s.to, s.from) + extra);
    }
    double round(double v) => (v * 100).round() / 100;
    final list = members.toList(growable: false);
    return [
      for (var i = 0; i < list.length; i++)
        for (var j = i + 1; j < list.length; j++)
          if (round(get(list[i], list[j])) >= 0.01 ||
              round(get(list[j], list[i])) >= 0.01)
            (
              list[i],
              list[j],
              round(get(list[i], list[j])),
              round(get(list[j], list[i])),
            ),
    ];
  }

  /// «زين يدفع لـ أحمد» / «يُرد من الميزانية المشتركة لـ زين».
  String _transferText(SharedTransfer t) {
    if (t.from == SharedLedger.potPayer) {
      return '${AppTr.tr('يُرد من الميزانية المشتركة لـ')} ${_shownName(t.to)}';
    }
    if (t.to == SharedLedger.potPayer) {
      return '${_shownName(t.from)} ${AppTr.tr('يدفع للميزانية المشتركة')}';
    }
    return '${_shownName(t.from)} ${AppTr.tr('يدفع لـ')} ${_shownName(t.to)}';
  }

  String _settlementText(List<SharedTransfer> transfers, String date) {
    final sum = transfers.fold<double>(0, (s, t) => s + t.amount);
    return [
      'تسوية حساب: ${item.title}',
      'التاريخ: $date',
      '',
      for (final t in transfers)
        '• ${_shownName(t.from)} دفع لـ ${_shownName(t.to)}: ${_money(t.amount)}',
      '',
      'المجموع: ${_money(sum)}',
    ].join('\n');
  }

  /// بعد التسوية: نافذة بمعلوماتها، وفي أعلاها يسارًا زر مشاركة — مع
  /// الأعضاء (تُحفظ في مستندات الالتزام فيراها الجميع) أو عبر واتساب.
  Future<void> _showSettlementReceipt(
    List<SharedTransfer> transfers,
    String date,
  ) async {
    final text = _settlementText(transfers, date);
    final sum = transfers.fold<double>(0, (s, t) => s + t.amount);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Dialog(
          backgroundColor: AppTheme.page,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Icon(Icons.verified_rounded, color: item.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تمت تسوية الحساب',
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                    // أعلى اليسار: المشاركة.
                    PopupMenuButton<String>(
                      tooltip: AppTr.tr('مشاركة'),
                      icon: Icon(Icons.share_outlined, color: item.color),
                      onSelected: (value) async {
                        if (value == 'members') {
                          await _saveSettlementDocument(text, date);
                        } else {
                          // مستند PDF رسمي بدل النص.
                          await _shareSettlementPdf(transfers, date);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'members',
                          child: _SharedCommitmentMenuItem(
                            label: 'مشاركة مع الأعضاء (المستندات)',
                            icon: Icons.groups_outlined,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'whatsapp',
                          child: _SharedCommitmentMenuItem(
                            label: 'مشاركة كمستند PDF',
                            icon: Icons.picture_as_pdf_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  '${item.title} · $date',
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                for (final transfer in transfers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 6),
                    child: Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: Text(
                            '${_shownName(transfer.from)} دفع لـ ${_shownName(transfer.to)}',
                            textAlign: AppTr.alignEnd,
                            maxLines: 2,
                            softWrap: true,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _money(transfer.amount),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: item.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(height: 1, color: AppTheme.hairline),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      const Expanded(
                        child: Text(
                          'المجموع',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                      Text(
                        _money(sum),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text(
                      'تم',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// مشاركة التسوية مع الأعضاء: تُحفظ مستندًا في الالتزام نفسه، فتظهر في
  /// تبويب المستندات عند كل الأعضاء.
  Future<void> _saveSettlementDocument(String text, String date) async {
    final list = _parseSimpleEntries(item.details, _documentsDetailsKey)
      ..add(
        _SimpleEntry(
          kind: 'تسوية حساب',
          title: 'تسوية حساب — ${item.title}',
          note: text,
          date: date,
        ),
      );
    final details = Map<String, String>.of(item.details)
      ..[_documentsDetailsKey] = _encodeSimpleEntries(list);
    await _persist(
      details,
      ask: 'هل تريد إضافة التسوية إلى مستندات الأعضاء؟',
      done: 'تمت إضافة التسوية إلى مستندات الأعضاء',
    );
  }

  /// مساهمة إضافية: دفعة يضيفها عضو فوق مساهمته الأساسية حين لا تكفي
  /// الميزانية — تظهر بجانب اسمه بصيغة «+200».
  Future<void> _openContributionForm() async {
    final members = _ledgerMembers;
    if (members.isEmpty) return;
    var member = members.first;
    var receiptPath = '';
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final now = DateTime.now();
    final dateController = TextEditingController(
      text: '${now.day}/${now.month}/${now.year}',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ميزانية إضافية',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'دفعة فوق المساهمة الأساسية حين لا تكفي الميزانية',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // الاسم المختار هو من دفع المساهمة، ويُسجَّل باسمه.
                  const Text(
                    'من دفع المساهمة؟ *',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in members)
                        ChoiceChip(
                          label: Text(
                            _shownName(name),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          selected: member == name,
                          onSelected: (_) =>
                              setSheetState(() => member = name),
                          selectedColor: AppTheme.brandSoft,
                          backgroundColor: AppTheme.field,
                          showCheckmark: false,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.rPill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            label: const Text('المبلغ *'),
                            suffixText: item.currency,
                            prefixIcon: const Icon(
                              Icons.savings_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: dateController,
                          readOnly: true,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: AppTr.tr('التاريخ'),
                            prefixIcon: const Icon(
                              Icons.event_outlined,
                              size: 18,
                            ),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (picked == null) return;
                            setSheetState(
                              () => dateController.text =
                                  '${picked.day}/${picked.month}/${picked.year}',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    textDirection: AppTr.uiDir,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: AppTr.tr('ملاحظة'),
                      prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _receiptButton(
                    // من غير المسؤول: صورة الفاتورة/الإيصال إلزامية، وتصل
                    // معها للمسؤول ليوافق، وتبقى في الأرصدة إثباتًا.
                    label: _isManagerHere
                        ? 'إرفاق صورة الإيصال'
                        : 'إرفاق صورة الإيصال *',
                    path: receiptPath,
                    accent: AppTheme.brand,
                    onTap: () async {
                      final path = await _pickReceiptFile(sheetContext);
                      if (path == null) return;
                      setSheetState(() => receiptPath = path);
                    },
                    onRemove: () => setSheetState(() => receiptPath = ''),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      final value =
                          parseMoney(amountController.text.trim()) ?? 0;
                      if (value <= 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('اكتب مبلغ المساهمة')),
                        );
                        return;
                      }
                      if (!_isManagerHere && receiptPath.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'أرفق صورة الإيصال أو الفاتورة لإثبات المبلغ',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                    child: const Text('حفظ المساهمة'),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final manager = _isManagerHere;
    final contribution = SharedContribution(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      member: member,
      amount: parseMoney(amountController.text.trim()) ?? 0,
      date: dateController.text.trim(),
      note: noteController.text.trim(),
      // الميزانية الإضافية تحتاج موافقة المسؤول كالمصروف.
      status: manager
          ? SharedExpense.statusApproved
          : SharedExpense.statusPending,
      submittedBy: AppSettings.instance.publicName,
      receipt: receiptPath,
    );
    final openControllers = <TextEditingController>[
      amountController,
      noteController,
      dateController,
    ];
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final c in openControllers) {
        c.dispose();
      }
    });
    if (saved != true) return;
    final rows = [
      ...SharedLedger.contributions(item.details),
      contribution,
    ];
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.contributionsKey] = SharedLedger.encodeContributions(
        rows,
      );
    // باسم من دفعها: «عبدالعزيز أضاف 300 درهم كميزانية إضافية».
    final added =
        '${_shownName(contribution.member)} ${AppTr.tr('أضاف')} '
        '${_money(contribution.amount)} ${AppTr.tr('كميزانية إضافية')}';
    final ok = await _persist(
      details,
      ask: '${AppTr.tr('هل تريد تسجيل')}: $added؟',
      done: manager
          ? added
          : '$added — ${AppTr.tr('أُرسلت لموافقة المسؤول')}',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _saveInlineExpense(SharedExpense expense) async {
    // تأكيد قبل إغلاق النموذج حتى لا يضيع ما كُتب عند الإلغاء.
    final confirmed = await confirmAction(
      context,
      title: 'تأكيد الحفظ',
      message: 'هل تريد حفظ المصروف «${expense.description}»؟',
      confirmLabel: 'تأكيد',
    );
    if (!confirmed || !mounted) return;
    // المسؤول يعتمد مصروفه مباشرة؛ غيره يُرسَل لموافقة المسؤول — إلا إذا
    // أُلغي خيار «يحتاج المصروف موافقة المسؤول» مع الدفعة المقطوعة.
    final manager = _isManagerHere || !_expenseNeedsApproval;
    final row = expense.withStatus(
      manager ? SharedExpense.statusApproved : SharedExpense.statusPending,
      by: AppSettings.instance.publicName,
    );
    final rows = [...SharedLedger.expenses(item.details), row];
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.expensesKey] = SharedLedger.encodeExpenses(rows);
    setState(() => _expenseFormOpen = false);
    final ok = await _persist(
      details,
      done: manager
          ? 'تمت إضافة المصروف'
          : 'أُرسل المصروف لموافقة المسؤول',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// زر الإضافة العائم يفتح نموذج المصروف داخل التبويب نفسه.
  void _openExpenseForm() {
    setState(() {
      _tabIndex = 1;
      _ledgerView = 0;
      _expenseFormOpen = true;
    });
  }

  Future<void> _deleteExpense(SharedExpense expense) async {
    // حذف مصروف معتمد للمسؤول وحده؛ والعضو يحذف ما أرسله ولم يُعتمد بعد.
    final mine = !expense.isApproved &&
        AppSettings.instance.isMyName(expense.submittedBy);
    if (!_isManagerHere && !mine) return _managerOnly();
    final ok = await confirmAction(
      context,
      title: 'حذف المصروف',
      message: 'سيُحذف «${expense.description}» وتتغيّر الأرصدة تبعًا له. '
          'هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok) return;
    final rows = SharedLedger.expenses(item.details)
        .where((e) => e.id != expense.id)
        .toList();
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.expensesKey] = SharedLedger.encodeExpenses(rows);
    await _persist(details, done: 'تم حذف المصروف');
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------- الملخص
  // يسجّل كل شيء أُدخل عند "+ إضافة التزام" بالإضافة إلى تاريخ الإنشاء —
  // حسب نص الملف بالضبط.
  Widget _buildSummaryTab() {
    final form = _sharedEntryForms[item.entryType];
    // الميزانية أول ما يُقرأ تحت اسم الالتزام، ولا تظهر إطلاقًا إن لم
    // تكن هناك ميزانية أصلًا («دفع فردي»).
    final budget = SharedLedger.budget(item.details);
    final rows = <(String, String, IconData)>[
      // مساهمات الأعضاء مع الإضافية المعتمدة.
      if (budget > 0.01)
        ('إجمالي المساهمات', _money(budget), Icons.account_balance_wallet_outlined),
      if (item.lastUpdate.isNotEmpty) ('تاريخ إنشاء الالتزام', item.lastUpdate, Icons.event_available_outlined),
      for (final field in form?.fields ?? const <_SharedField>[])
        if ((item.details[field.label] ?? '').isNotEmpty && field.kind != _SharedFieldKind.people)
          (field.label, item.details[field.label]!, field.icon),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SharedUnifiedCard(
          title: 'الملخص',
          icon: Icons.summarize_outlined,
          color: item.color,
          children: [
            for (final row in rows) _SharedInfoRow(label: row.$1, value: row.$2, icon: row.$3),
            // الأعضاء تحت عنوانهم مباشرة، كل عضو في سطر.
            if (item.membersCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        const Icon(Icons.groups_outlined, size: 19, color: Color(0xFF8C9A97)),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'الأعضاء (${item.membersCount})',
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(color: Color(0xFF5C6B68), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final member in item.members)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 28, bottom: 4),
                        child: Text(
                          // بلا رقم تعريفي: يظهر في تبويب الأعضاء وحده.
                          '${_shownName(member.name)} — ${AppTr.tr(member.role)}',
                          textAlign: AppTr.alignEnd,
                          textDirection: AppTr.uiDir,
                          style: const TextStyle(color: Color(0xFF1C2C29), fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------- المالية
  // حُذف تبويب «الميزانية» وبطاقاته: أرقامه صارت في الملخص والأرصدة،
  // وسجل عملياته صار سطورًا في تبويب السجل.
  // اعتماد العمليات كان يُعرض في بطاقة تبويب الميزانية المحذوف.
  /// «عملية مالية»: نوعان فقط — مصروف، وميزانية إضافية (مع الدفعة
  /// المقطوعة وحدها؛ الدفع الفردي بلا ميزانية أصلًا). «دفعة» القديمة صارت
  /// الميزانية الإضافية، و«سداد» صار «تسوية الحساب».
  Future<void> _openTransactionForm() async {
    // الجمعية بلا مصروفات: العملية المالية فيها مساهمة في الدورة الجارية.
    if (_isRosca) {
      final open = _roscaPlan.current;
      if (open != null) await _openRoscaPaymentForm(open.index);
      return;
    }
    final lump = _isLumpSum;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              const Text(
                'عملية مالية',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              if (!_isManagerHere)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'تُرسَل لموافقة مسؤول الالتزام ($_managerName) قبل أن '
                    'تدخل الحساب',
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.receipt_long_outlined, color: item.color),
                title: const Text(
                  'مصروف',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                subtitle: const Text(
                  'مصروف دفعه أحد الأعضاء أو صُرف من الميزانية',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
                onTap: () => Navigator.pop(sheetContext, 'expense'),
              ),
              if (lump)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.savings_outlined, color: item.color),
                  title: const Text(
                    'ميزانية إضافية',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  subtitle: const Text(
                    'مبلغ يضيفه عضو فوق مساهمته حين لا تكفي الميزانية',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'budget'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'expense') {
      _openExpenseForm();
    } else if (choice == 'budget') {
      await _openContributionForm();
    }
  }

  // -------------------------------------------------------------- السجل
  // نفس تصميم _HistoryDetailsCard في الشخصية تمامًا: صندوق موحّد واحد
  // برأس أيقونة+عنوان، وصفوف _TimelineEntry (أيقونة دائرية) بدل صناديق
  // منفصلة لكل عملية.
  Widget _buildHistoryTab() {
    final transactions = item.transactions.reversed.toList();
    // السجل يجمع كل ما وقع على الالتزام: مصروفات الدفتر، والمساهمات
    // الإضافية، والتسويات، والعمليات المالية القديمة.
    final entries = <(String, String, IconData, Color)>[
      if (item.lastUpdate.isNotEmpty) ('تم إنشاء الالتزام', item.lastUpdate, Icons.add_circle_outline_rounded, item.color),
      // قبول الدعوات ورفضها بتاريخها ووقتها.
      for (final answer
          in _SharedCommitmentsScreenState._acceptances(item).entries)
        if ((answer.value['state'] ?? '') == 'accepted' ||
            (answer.value['state'] ?? '') == 'rejected')
          (
            '${_shownName((answer.value['name'] ?? '').trim().isEmpty ? answer.key : answer.value['name']!)} '
                '${AppTr.tr(answer.value['state'] == 'accepted' ? 'قبل الدعوة' : 'رفض الدعوة')}',
            (answer.value['at'] ?? '').trim(),
            answer.value['state'] == 'accepted'
                ? Icons.how_to_reg_outlined
                : Icons.person_off_outlined,
            answer.value['state'] == 'accepted'
                ? AppTheme.brandMid
                : AppTheme.danger,
          ),
      // تغيير الدور، تسليم المبلغ وإلغاؤه، إلغاء الالتزام...
      for (final event in _eventsOf(item.details).reversed)
        (event.$1, event.$2, Icons.history_edu_outlined, item.color),
      // مساهمات دورات تحديد الأدوار.
      if (_isRosca)
        for (final cycle in _roscaPlan.cycles.reversed)
          for (final payment in cycle.payments.reversed)
            (
              '${_shownName(payment.member)} ${AppTr.tr('دفع مساهمة الدورة')} '
                  '${cycle.index} — ${_money(payment.amount)}',
              payment.date,
              Icons.payments_outlined,
              AppTheme.brandMid,
            ),
      for (final expense in SharedLedger.expenses(item.details).reversed)
        (
          'مصروف: ${expense.description} — ${_money(expense.amount)}'
          '${expense.isForeign ? ' (${_plainNum(expense.originalAmount)} ${expense.currency})' : ''}',
          '${expense.payer.isEmpty ? '' : 'دفعه ${_shownName(expense.payer)} · '}'
              '${_withClock(expense.date, expense.id)}',
          Icons.receipt_outlined,
          AppTheme.danger,
        ),
      for (final contribution
          in SharedLedger.contributions(item.details).reversed)
        (
          '${_shownName(contribution.member)} ${AppTr.tr('أضاف')} '
              '${_money(contribution.amount)} ${AppTr.tr('كميزانية إضافية')}',
          contribution.note.trim().isEmpty
              ? _withClock(contribution.date, contribution.id)
              : '${_withClock(contribution.date, contribution.id)} · ${contribution.note}',
          Icons.savings_outlined,
          AppTheme.goldDark,
        ),
      for (final settlement in SharedLedger.settlements(item.details).reversed)
        (
          'تسوية: ${_shownName(settlement.from)} دفع لـ ${_shownName(settlement.to)} '
              '${_money(settlement.amount)}',
          _withClock(settlement.date, settlement.id),
          Icons.handshake_outlined,
          AppTheme.brandMid,
        ),
      for (final t in transactions)
        ('${t.kind} بقيمة ${t.amount} ${item.currency}', '${t.submittedBy.isEmpty ? '' : '${t.submittedBy} · '}${t.date}', t.kind == 'مصروف' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, t.kind == 'مصروف' ? const Color(0xFFA82F26) : const Color(0xFF178F7B)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SharedUnifiedCard(
          title: 'السجل',
          icon: Icons.history_rounded,
          color: item.color,
          children: [
            if (entries.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text('لا يوجد سجل بعد', style: TextStyle(color: Color(0xFF5C6B68)))))
            else
              for (final e in entries) _SharedTimelineEntry(title: e.$1, subtitle: e.$2, icon: e.$3, color: e.$4),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------- الأعضاء
  /// عضو الجمعية: اسمه، ومساهمته، ومتى دوره — لا مصروفات ولا له/عليه.
  Widget _buildRoscaMemberCard(_SharedMember member) =>
      _roscaDueRow(_roscaPlan, member.name, showId: true);

  Widget _buildMembersTab() {
    final members = item.members;
    final balances = SharedLedger.balances(item.details, _ledgerMembers);
    final lump = _isLumpSum;
    final query = _memberQuery.trim();
    final shown = query.isEmpty
        ? members
        : members.where((m) => m.name.contains(query)).toList();
    return _tabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionAddRow(
            title: 'الأعضاء (${members.length})',
            icon: Icons.groups_outlined,
            accent: item.color,
            // الزر ظاهر دائمًا، والإضافة نفسها لمسؤول الرحلة وحده.
            onAdd: _openMemberActions,
          ),
          const SizedBox(height: 10),
          TextField(
            textDirection: AppTr.uiDir,
            onChanged: (value) => setState(() => _memberQuery = value),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              hintText: AppTr.tr('ابحث عن عضو'),
              hintStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: AppTheme.muted,
              ),
              filled: true,
              fillColor: AppTheme.page,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                borderSide: const BorderSide(color: AppTheme.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                borderSide: const BorderSide(color: AppTheme.hairline),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                members.isEmpty ? 'لا يوجد أعضاء بعد' : 'لا يوجد عضو بهذا الاسم',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            for (final member in shown)
              if (_isRosca)
                _buildRoscaMemberCard(member)
              else
                _buildMemberMoneyCard(
                  member.name,
                  balances[member.name] ?? 0,
                  lump,
                  role: [
                    AppTr.tr(member.role),
                    _memberDateNote(member.name),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  linkToExpenses: true,
                  showId: true,
                ),
        ],
      ),
    );
  }

  String _plainNum(double value) =>
      value.toStringAsFixed(value.abs() % 1 == 0 ? 0 : 2);

  /// «غادر في 3/10/2026» أو «انضم في 5/10/2026».
  String _memberDateNote(String name) {
    final invite = _memberInviteNote(name);
    final leave = SharedLedger.leaveOf(item.details, name);
    final join = SharedLedger.joinOf(item.details, name);
    final dates = leave.isNotEmpty
        ? '${AppTr.tr('غادر في')} $leave'
        : join.isNotEmpty
        ? '${AppTr.tr('انضم في')} $join'
        : '';
    return [invite, dates].where((s) => s.isNotEmpty).join(' · ');
  }

  /// العضو المدعو برقمه التعريفي: بانتظار الموافقة، أو قبل/رفض في (التاريخ والوقت).
  String _memberInviteNote(String name) {
    final id = _SharedCommitmentsScreenState._idInMemberName(name);
    if (id == null || id == (item.details[_creatorIdKey] ?? '').trim()) {
      return '';
    }
    final answer = _SharedCommitmentsScreenState._acceptances(item)[id];
    final at = (answer?['at'] ?? '').trim();
    final state = _inviteStateOf(item, id);
    // الموافق عضو عادي: لا تُكتب بجانبه «وافق».
    if (state == 'accepted') return '';
    final label = AppTr.tr(_inviteStateLook(state).$1);
    if (state == 'rejected' && at.isNotEmpty) {
      return '${AppTr.tr('رفض الدعوة في')} $at';
    }
    return label;
  }

  /// تاريخ الحركة ومعه وقت تسجيلها (من معرّفها).
  String _withClock(String date, String id) {
    final clock = recordClock(id);
    if (clock.isEmpty) return date;
    return date.isEmpty ? clock : '$date $clock';
  }

  void _managerOnly() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppTr.tr('هذا الإجراء لمسؤول الالتزام فقط')} ($_managerName)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<DateTime?> _pickDay(String help) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      helpText: AppTr.tr(help),
    );
  }

  /// مغادرة عضو بتاريخ: لا تُحسب عليه المصروفات بعده، ويُعرض رصيده
  /// للتسوية معه وحده عبر المسؤول، والرحلة تكمل للباقين.
  Future<void> _memberLeave() async {
    if (!_isManagerHere) return _managerOnly();
    final manager = _managerName;
    final candidates = [
      for (final m in item.members)
        if (m.name.trim() != manager &&
            SharedLedger.leaveOf(item.details, m.name.trim()).isEmpty)
          m.name.trim(),
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عضو يمكن تسجيل مغادرته'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              const Text(
                'من غادر؟',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final candidate in candidates)
                ListTile(
                  leading: const Icon(Icons.flight_takeoff_rounded),
                  title: Text(_shownName(candidate)),
                  onTap: () => Navigator.pop(sheetContext, candidate),
                ),
            ],
          ),
        ),
      ),
    );
    if (name == null || !mounted) return;
    final day = await _pickDay('تاريخ المغادرة');
    if (day == null || !mounted) return;
    // مصروفات بعد تاريخ المغادرة تشمله، أو معلّقة: تُعدَّل أولًا، وإلا
    // أُغلق حسابه على رقم خاطئ.
    final blocking = SharedLedger.expenses(item.details).where((e) {
      if (!(e.participants.contains(name) || e.payer == name)) return false;
      if (e.isPending) return true;
      final at = SharedLedger.parseDay(e.date);
      return e.isApproved && at != null && at.isAfter(day);
    }).length;
    if (blocking > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppTr.tr('مصروفات تشمله بعد تاريخ المغادرة أو بانتظار الموافقة')}: '
            '$blocking — ${AppTr.tr('عدّلها أولًا')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final dates = SharedLedger.memberDates(item.details);
    dates[name] = {...?dates[name], 'leave': SharedLedger.formatDay(day)};
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.memberDatesKey] = SharedLedger.encodeMemberDates(dates);

    // رصيده حتى الآن: له (موجب) أو عليه (سالب).
    final net = SharedLedger.balances(item.details, _ledgerMembers)[name] ?? 0;
    final owes = net < -0.01;
    final due = net.abs() > 0.01;
    String choice = 'leave';
    if (due) {
      final picked = await showDialog<String>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            title: Text('${AppTr.tr('مغادرة')} ${_shownName(name)}'),
            content: Text(
              _isLumpSum
                  ? (owes
                        ? '${AppTr.tr('عليه')} ${_money(net)} — '
                              '${AppTr.tr('يدفعها للميزانية المشتركة')} '
                              '${AppTr.tr('وتُغلق حسابه في الرحلة')}.'
                        : '${AppTr.tr('له')} ${_money(net)} — '
                              '${AppTr.tr('تُرد له من الميزانية المشتركة وتنقص من المتبقي')} '
                              '${AppTr.tr('وتُغلق حسابه في الرحلة')}.')
                  : owes
                  ? '${AppTr.tr('عليه')} ${_money(net)} — '
                        '${AppTr.tr('يدفعها للمسؤول')} ($manager) '
                        '${AppTr.tr('وتُغلق حسابه في الرحلة')}.'
                  : '${AppTr.tr('له')} ${_money(net)} — '
                        '${AppTr.tr('يدفعها له المسؤول')} ($manager) '
                        '${AppTr.tr('وتُغلق حسابه في الرحلة')}.',
              style: const TextStyle(height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'leave'),
                child: const Text('المغادرة فقط'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: item.color),
                onPressed: () => Navigator.pop(dialogContext, 'settle'),
                child: const Text('المغادرة مع التسوية'),
              ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      choice = picked;
    }
    if (choice == 'settle') {
      final now = DateTime.now();
      // مع الدفعة المقطوعة الطرف الآخر هو الميزانية المشتركة: ما يُرد له
      // يخرج منها فينقص المتبقي، وما عليه يدخلها.
      final party = _isLumpSum ? SharedLedger.potPayer : manager;
      details[SharedLedger.settlementsKey] = SharedLedger.encodeSettlements([
        ...SharedLedger.settlements(item.details),
        SharedSettlement(
          id: '${now.millisecondsSinceEpoch}',
          from: owes ? name : party,
          to: owes ? party : name,
          amount: net.abs(),
          date: SharedLedger.formatDay(now),
          note: AppTr.tr('تسوية عند المغادرة'),
        ),
      ]);
    }
    final ok = await _persist(
      details,
      ask: due
          ? null
          : 'هل تريد تسجيل مغادرة ${_shownName(name)} بتاريخ ${SharedLedger.formatDay(day)}؟',
      done: choice == 'settle'
          ? 'سُجّلت مغادرة ${_shownName(name)} وتسويته'
          : 'سُجّلت مغادرة ${_shownName(name)}',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// انضمام عضو بتاريخ: يُضاف للأعضاء، ولا تُحسب عليه المصروفات قبله.
  Future<void> _memberJoin() async {
    if (!_isManagerHere) return _managerOnly();
    final picked = await _pickSharedPerson(context, item.color);
    if (picked == null || !mounted) return;
    final name = picked.trim();
    if (name.isEmpty) return;
    final exists = item.members.any((m) => m.name.trim() == name);
    final day = await _pickDay('تاريخ الانضمام');
    if (day == null || !mounted) return;
    final dates = SharedLedger.memberDates(item.details);
    // عاد بعد مغادرته: تُمحى المغادرة ويبدأ من التاريخ الجديد.
    dates[name] = {'join': SharedLedger.formatDay(day)};
    final details = Map<String, String>.of(item.details)
      ..[SharedLedger.memberDatesKey] = SharedLedger.encodeMemberDates(dates);
    if (!exists) {
      final names = (item.details[_sharedMembersKey] ?? '')
          .split('،')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
        ..add(name);
      details
        ..[_sharedMembersDetailKey] = _encodeSharedMembers([
          ...item.members,
          _SharedMember(name: name, role: 'عضو'),
        ])
        ..[_sharedMembersKey] = names.join('، ');
    }
    final ok = await _persist(
      details,
      ask: 'هل تريد تسجيل انضمام ${_shownName(name)} بتاريخ ${SharedLedger.formatDay(day)}؟',
      done: 'سُجّل انضمام ${_shownName(name)}',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  /// إضافة عضو — لمسؤول الرحلة فقط، ومن المنتقي دائمًا: بحث في الأفراد،
  /// أو اسم جديد، أو دعوة بالرقم التعريفي.
  /// + في الأعضاء (الرحلة والمشاركة): انضمام عضو جديد، أو مغادرة عضو
  /// يُختار من الأعضاء الحاليين.
  Future<void> _openMemberActions() async {
    if (_isRosca) return _openRoscaMemberActions();
    if (!_isManagerHere) return _managerOnly();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              const Text(
                'الأعضاء',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.person_add_alt_1_outlined,
                  color: item.color,
                ),
                title: const Text(
                  'انضمام عضو جديد',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'يُضاف من تاريخ انضمامه، ولا تُحسب عليه المصروفات قبله',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(sheetContext, 'join'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flight_takeoff_rounded, color: item.color),
                title: const Text(
                  'مغادرة عضو',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'تختار من الأعضاء الحاليين من سيغادر وتاريخ مغادرته',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(sheetContext, 'leave'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'join') await _memberJoin();
    if (choice == 'leave') await _memberLeave();
  }

  /// + في أعضاء تحديد الأدوار: إضافة عضو جديد، أو إلغاء عضو.
  Future<void> _openRoscaMemberActions() async {
    if (!_isManagerHere) return _managerOnly();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              const Text(
                'الأعضاء',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.person_add_alt_1_outlined,
                  color: item.color,
                ),
                title: const Text(
                  'إضافة عضو جديد',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () => Navigator.pop(sheetContext, 'add'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: AppTheme.danger,
                ),
                title: const Text(
                  'إلغاء عضو',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'add') await _openAddMemberSheet();
    if (choice == 'remove') await _removeRoscaMember();
  }

  /// إلغاء عضو من تحديد الأدوار — لا يُلغى المسؤول، ولا من سجّل دفعات أو
  /// استلم دوره. تُبنى الدورات من جديد بعدد الأعضاء الباقين.
  Future<void> _removeRoscaMember() async {
    final plan = _roscaPlan;
    final candidates = [
      for (final m in item.members)
        if (m.role != 'مسؤول' && m.name.trim().isNotEmpty) m.name.trim(),
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عضو يمكن إلغاؤه'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              const Text(
                'من تريد إلغاءه؟',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 8),
              for (final name in candidates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(_shownName(name)),
                  subtitle: Text(
                    '${AppTr.tr('الدورة رقم')}: ${plan.turnOf(name) ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                  ),
                  onTap: () => Navigator.pop(sheetContext, name),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (plan.paidTotalOf(picked) > 0.01 || plan.receivedBy(picked)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إلغاء عضو سجّل دفعات أو استلم دوره'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final members = [
      for (final m in item.members)
        if (m.name.trim() != picked) m,
    ];
    final names = (item.details[_sharedMembersKey] ?? '')
        .split('،')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != picked)
        .toList();
    // دورة كان صاحبها: يعود لترتيب الأعضاء الافتراضي.
    var store = item.details[RoscaLedger.cyclesKey] ?? '';
    for (final cycle in plan.cycles) {
      if (cycle.receiver != picked) continue;
      store = RoscaLedger.withReceiver(
        {...item.details, RoscaLedger.cyclesKey: store},
        cycle.index,
        '',
      );
    }
    final details = Map<String, String>.of(item.details)
      ..[_sharedMembersDetailKey] = _encodeSharedMembers(members)
      ..[_sharedMembersKey] = names.join('، ')
      ..[RoscaLedger.cyclesKey] = store;
    final ok = await _persist(
      details,
      ask: 'هل تريد إلغاء ${_shownName(picked)} من الأعضاء؟ '
          'تُبنى الدورات من جديد بعدد الأعضاء الباقين.',
      done: 'تم إلغاء ${_shownName(picked)}',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  Future<void> _openAddMemberSheet() async {
    if (!_isManagerHere) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'إضافة الأعضاء لمسؤول الرحلة ($_managerName) فقط — '
            'الاسم المسجّل على هذا الجهاز: ${AppSettings.instance.name}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final picked = await _pickSharedPerson(context, item.color);
    if (picked == null || !mounted) return;
    final name = picked.trim();
    if (name.isEmpty) return;
    if (item.members.any((m) => m.name.trim() == name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name موجود في الأعضاء'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final members = [
      ...item.members,
      _SharedMember(name: name, role: 'عضو'),
    ];
    final names = (item.details[_sharedMembersKey] ?? '')
        .split('،')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList()
      ..add(name);
    final details = Map<String, String>.of(item.details)
      ..[_sharedMembersDetailKey] = _encodeSharedMembers(members)
      ..[_sharedMembersKey] = names.join('، ');
    final ok = await _persist(
      details,
      ask: 'هل تريد إضافة $name إلى الأعضاء؟',
      done: 'تمت إضافة $name إلى الأعضاء',
    );
    if (!ok || !mounted) return;
    setState(() {});
  }

  // ----------------------------------------------- متابعة وتخطيط / مستندات / مواقع وأماكن
  Widget _buildSimpleListTab({required String sectionKey, required List<String> kinds, required IconData icon, required String emptyText, String? title}) {
    final isFollowUp = sectionKey == _followUpDetailsKey;
    final stored = _parseSimpleEntries(item.details, sectionKey);
    // موضع كل عنصر في المحفوظ — للتعديل والإكمال والحذف.
    final indexOf = <_SimpleEntry, int>{
      for (var i = 0; i < stored.length; i++) stored[i]: i,
    };
    final allEntries = stored.reversed.toList();
    final entries = isFollowUp
        ? allEntries
              .where(
                (e) =>
                    (_followUpKindFilter == 'الكل' ||
                        e.kind == _followUpKindFilter) &&
                    followStatusMatches(_followUpStatusFilter, e.date),
              )
              .toList()
        : allEntries;
    return _tabPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // رأس القسم الموحّد: العنوان وعدده في أوّل السطر، + في آخره، وخط
        // رصاصي رفيع تحتهما — نفس شكل كل قسم قابل للإضافة في التطبيق.
        AppSectionAddRow(
          title: title ?? sectionKey,
          icon: icon,
          accent: item.color,
          trailingText: entries.isEmpty ? '' : '${entries.length}',
          onAdd: () =>
              _openSimpleEntrySheet(sectionKey: sectionKey, kinds: kinds),
        ),
        // المتابعة: فلترا النوع والحالة تحت العنوان.
        if (isFollowUp)
          FollowFiltersRow(
            kind: _followUpKindFilter,
            status: _followUpStatusFilter,
            onKind: (value) => setState(() => _followUpKindFilter = value),
            onStatus: (value) =>
                setState(() => _followUpStatusFilter = value),
          ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(isFollowUp && allEntries.isNotEmpty ? 'لا توجد متابعة أو تخطيط مطابق للفلتر' : emptyText, style: const TextStyle(color: Color(0xFF5C6B68)))))
        else
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showSimpleEntryDetails(e, icon),
                child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE4EAE8))),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, size: 17, color: item.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 3,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF022E2A),
                              decoration: _entryDone(e)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (_entryDone(e))
                            Text(
                              'مكتملة',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.brandMid,
                              ),
                            ),
                          Text(
                            '${e.kind}${e.date.isNotEmpty ? ' · ${e.date}' : ''}${e.note.isNotEmpty ? ' · ${e.note}' : ''}',
                            maxLines: 3,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF5C6B68), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if ((e.extra['المرفق'] ?? '').isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file_rounded, size: 15, color: item.color),
                          Text(
                            'مرفق',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: item.color),
                          ),
                        ],
                      ),
                    // المتابعة: عرض التفاصيل، اكتمال، تعديل، حذف.
                    if (isFollowUp && indexOf[e] != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _entryAction(
                            Icons.visibility_outlined,
                            'عرض التفاصيل',
                            () => _showSimpleEntryDetails(e, icon),
                          ),
                          _entryAction(
                            _entryDone(e)
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            _entryDone(e) ? 'إلغاء الاكتمال' : 'اكتمال',
                            () => _toggleEntryDone(sectionKey, indexOf[e]!),
                            color: AppTheme.brandMid,
                          ),
                          _entryAction(
                            Icons.edit_outlined,
                            'تعديل',
                            () => _openSimpleEntrySheet(
                              sectionKey: sectionKey,
                              kinds: kinds,
                              initialKind: e.kind,
                              editing: e,
                              editIndex: indexOf[e],
                            ),
                          ),
                          _entryAction(
                            Icons.delete_outline_rounded,
                            'حذف',
                            () => _deleteSimpleEntry(sectionKey, indexOf[e]!),
                            color: AppTheme.danger,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              ),
            ),
      ],
    ));
  }

  /// عنصر متابعة مكتمل؟
  bool _entryDone(_SimpleEntry e) => (e.extra['الحالة'] ?? '') == 'مكتملة';

  Widget _entryAction(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) => IconButton(
    tooltip: AppTr.tr(tooltip),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    icon: Icon(icon, size: 18, color: color ?? item.color),
    onPressed: onTap,
  );

  /// اكتمال عنصر متابعة أو إلغاؤه — بتأكيد.
  Future<void> _toggleEntryDone(String sectionKey, int index) async {
    final list = _parseSimpleEntries(item.details, sectionKey);
    if (index < 0 || index >= list.length) return;
    final e = list[index];
    final done = _entryDone(e);
    final extra = Map<String, String>.of(e.extra);
    if (done) {
      extra.remove('الحالة');
    } else {
      extra['الحالة'] = 'مكتملة';
    }
    list[index] = _SimpleEntry(
      kind: e.kind,
      title: e.title,
      note: e.note,
      date: e.date,
      extra: extra,
    );
    final details = _withEvent(
      Map<String, String>.of(item.details)
        ..[sectionKey] = _encodeSimpleEntries(list),
      '${AppTr.tr(done ? 'إلغاء اكتمال' : 'اكتمال')} ${AppTr.tr(e.kind)}: ${e.title}',
    );
    await _persist(
      details,
      ask: done
          ? 'هل تريد إلغاء اكتمال «${e.title}»؟'
          : 'هل تريد تحديد «${e.title}» كمكتمل؟',
      done: done ? 'تم إلغاء الاكتمال' : 'تم تحديده كمكتمل',
    );
  }

  /// حذف عنصر — بتأكيد.
  Future<void> _deleteSimpleEntry(String sectionKey, int index) async {
    final list = _parseSimpleEntries(item.details, sectionKey);
    if (index < 0 || index >= list.length) return;
    final e = list.removeAt(index);
    final ok = await confirmAction(
      context,
      title: 'حذف',
      message: 'سيُحذف «${e.title}» نهائيًا. هل تريد الحذف؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !mounted) return;
    final details = _withEvent(
      Map<String, String>.of(item.details)
        ..[sectionKey] = _encodeSimpleEntries(list),
      '${AppTr.tr('حذف')} ${AppTr.tr(e.kind)}: ${e.title}',
    );
    await _persist(details, done: 'تم الحذف');
  }

  /// تفاصيل عنصر (متابعة/مستند/موقع) كما أُدخل، مع فتح المرفق.
  Future<void> _showSimpleEntryDetails(_SimpleEntry e, IconData icon) async {
    final rows = <(String, String)>[
      ('النوع', e.kind),
      if (e.date.isNotEmpty) ('التاريخ', e.date),
      for (final entry in e.extra.entries)
        if (entry.value.trim().isNotEmpty &&
            entry.key != 'المرفق' &&
            entry.key != 'صورة المكان')
          (entry.key, entry.value),
      if (e.note.isNotEmpty && !e.extra.containsValue(e.note))
        ('ملاحظات', e.note),
    ];
    final attachment = e.extra['المرفق'] ?? '';
    final photo = e.extra['صورة المكان'] ?? '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Row(
                children: [
                  Icon(icon, color: item.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.$2,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final file in [photo, attachment])
                if (file.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final error = await DocumentStore.open(file);
                        if (error == null || !sheetContext.mounted) return;
                        ScaffoldMessenger.of(
                          sheetContext,
                        ).showSnackBar(SnackBar(content: Text(error)));
                      },
                      icon: Icon(
                        file == photo
                            ? Icons.image_outlined
                            : Icons.attach_file_rounded,
                      ),
                      label: Text(file == photo ? 'عرض الصورة' : 'فتح المرفق'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: item.color,
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickFollowUpKind() => showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'ماذا تريد أن تضيف؟',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
            for (final option in const [
              ('مهمة', Icons.task_alt_outlined),
              ('موعد', Icons.event_outlined),
              ('عادة', Icons.repeat_rounded),
              ('تذكير', Icons.notifications_active_outlined),
              ('ملاحظات', Icons.sticky_note_2_outlined),
            ])
              ListTile(
                leading: Icon(option.$2, color: item.color),
                title: Text(
                  option.$1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );

  /// إضافة متابعة/مستند/موقع بنفس صفحات الالتزامات الشخصية: مهمة وموعد
  /// وعادة وتذكير وملاحظات، ومستند بلا «نوع المستند»، وموقع بطريقة الإدخال.
  Future<void> _openSimpleEntrySheet({
    required String sectionKey,
    required List<String> kinds,
    String? initialKind,
    _SimpleEntry? editing,
    int? editIndex,
  }) async {
    var kind = initialKind;
    if (sectionKey == _followUpDetailsKey && kind == null) {
      kind = await _pickFollowUpKind();
      if (kind == null || !mounted) return;
    }
    final isFollowUp = sectionKey == _followUpDetailsKey;
    final isDoc = sectionKey == _documentsDetailsKey;
    final label = isFollowUp ? kind! : isDoc ? 'مستند' : 'مواقع وأماكن';
    final formIcon = isFollowUp
        ? switch (label) {
            'مهمة' => Icons.task_alt_outlined,
            'موعد' => Icons.event_outlined,
            'عادة' => Icons.repeat_rounded,
            'تذكير' => Icons.notifications_active_outlined,
            _ => Icons.sticky_note_2_outlined,
          }
        : isDoc
        ? Icons.description_outlined
        : Icons.location_on_outlined;
    final subtitle = isFollowUp
        ? 'متابعة وتخطيط ضمن هذا الالتزام'
        : isDoc
        ? 'وثيقة أو عقد أو ملف مهم'
        : 'حفظ مكان مهم وبيانات الوصول إليه';
    final c = <String, TextEditingController>{
      for (final key in const [
        'title', 'desc', 'date', 'time', 'repeat', 'remindTime', 'notes',
        'number', 'issuer', 'issued', 'expiry', 'reminder', 'link',
        'address', 'category', 'categoryCustom',
      ])
        key: TextEditingController(),
    };
    var remind = false;
    var placeMode = 'manual';
    var filePath = '';
    var photoPath = '';
    // تعديل عنصر متابعة: الحقول بقيمه.
    if (editing != null) {
      c['title']!.text = editing.title;
      c['desc']!.text = editing.extra['الوصف'] ?? '';
      c['date']!.text = editing.date;
      c['time']!.text = editing.extra['الوقت'] ?? '';
      c['repeat']!.text = editing.extra['التكرار'] ?? '';
      c['remindTime']!.text = editing.extra['وقت التذكير'] ?? '';
      c['notes']!.text = editing.extra['ملاحظات'] ?? '';
      remind = (editing.extra['تفعيل تذكير'] ?? '') == 'نعم';
      filePath = editing.extra['المرفق'] ?? '';
    }
    final formKey = GlobalKey<FormState>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          InputDecoration deco(String text, IconData icon, {bool required = false, String hint = ''}) =>
              _sharedFieldDecoration(required ? '$text *' : text, icon, item.color)
                  .copyWith(hintText: hint.isEmpty ? null : hint);
          Widget textField(String key, String text, IconData icon, {bool required = false, int lines = 1, String hint = ''}) => TextFormField(
            controller: c[key],
            minLines: lines > 1 ? 2 : 1,
            maxLines: lines,
            textDirection: AppTr.uiDir,
            decoration: deco(text, icon, required: required, hint: hint),
            validator: trValidator(required
                ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null
                : null),
          );
          Widget dateField(String key, String text, IconData icon, {bool required = false}) => TextFormField(
            controller: c[key],
            readOnly: true,
            decoration: deco(text, icon, required: required).copyWith(
              suffixIcon: required ? null : clearDateSuffix(c[key]!),
            ),
            validator: trValidator(required
                ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null
                : null),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (picked == null) return;
              setSheetState(() => c[key]!.text = '${picked.day}/${picked.month}/${picked.year}');
            },
          );
          Widget timeField(String key, String text, IconData icon) => TextFormField(
            controller: c[key],
            readOnly: true,
            decoration: deco(text, icon).copyWith(
              suffixIcon: clearDateSuffix(c[key]!),
            ),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (picked == null) return;
              setSheetState(() => c[key]!.text =
                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            },
          );
          Widget select(String key, String text, IconData icon, List<String> options, {bool required = false, bool custom = false, String hint = ''}) {
            final all = [...options, if (custom) '+ إضافة أخرى'];
            return DropdownButtonFormField<String>(
              initialValue: all.contains(c[key]!.text) ? c[key]!.text : null,
              isExpanded: true,
              alignment: AlignmentDirectional.centerEnd,
              decoration: deco(text, icon, required: required, hint: hint),
              items: [
                for (final option in all)
                  DropdownMenuItem(
                    value: option,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(option, textAlign: TextAlign.right),
                  ),
              ],
              onChanged: (v) => setSheetState(() => c[key]!.text = v ?? ''),
              validator: trValidator(required
                  ? (v) => v == null || v.isEmpty ? 'مطلوب' : null
                  : null),
            );
          }
          Widget pair(Widget a, Widget b) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
          );
          const gap = SizedBox(height: 12);
          final fields = <Widget>[
            if (isFollowUp) ...[
              textField('title', 'العنوان', Icons.title_rounded, required: true),
              gap,
              textField('desc', 'الوصف', Icons.description_outlined, lines: 3, hint: 'أوصف $label'),
              gap,
              pair(
                dateField('date', 'التاريخ', Icons.event_outlined, required: true),
                timeField('time', 'الوقت', Icons.schedule_rounded),
              ),
              gap,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.field,
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    const Icon(Icons.notifications_outlined, size: 20, color: Color(0xFF34A894)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'تفعيل تذكير',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1C2C29)),
                      ),
                    ),
                    Switch.adaptive(
                      value: remind,
                      activeThumbColor: const Color(0xFF0E7161),
                      onChanged: (value) => setSheetState(() => remind = value),
                    ),
                  ],
                ),
              ),
              if (remind) ...[
                gap,
                pair(
                  ReminderLeadField(
                    controller: c['remindTime']!,
                    decoration: deco('وقت التذكير', Icons.alarm_rounded),
                  ),
                  CustomOptionField(
                    controller: c['repeat']!,
                    options: const ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري'],
                    decoration: deco('التكرار', Icons.repeat_rounded),
                    customHint: 'مثال: كل 3 أيام',
                  ),
                ),
              ],
              gap,
              textField('notes', 'ملاحظات', Icons.notes_rounded, lines: 3),
            ] else if (isDoc) ...[
              textField('title', 'اسم المستند', Icons.title_rounded, required: true),
              gap,
              textField('number', 'رقم المستند', Icons.numbers_rounded),
              gap,
              textField('issuer', 'الجهة المصدرة', Icons.account_balance_outlined),
              gap,
              dateField('issued', 'تاريخ الإصدار', Icons.event_outlined),
              gap,
              dateField('expiry', 'تاريخ الانتهاء', Icons.event_busy_outlined, required: true),
              gap,
              select('reminder', 'تذكير', Icons.notifications_outlined,
                  const ['بدون تذكير', 'قبل أسبوع', 'قبل شهر', 'قبل شهرين'],
                  hint: 'تذكير قبل تاريخ الانتهاء'),
              gap,
              textField('notes', 'ملاحظات', Icons.notes_rounded, lines: 3),
            ] else ...[
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final mode in const [
                    ('current', 'أنا في المكان الآن', Icons.my_location_rounded),
                    ('link', 'لصق رابط خرائط جوجل', Icons.link_rounded),
                    ('manual', 'كتابة العنوان بنفسي', Icons.edit_location_alt_outlined),
                  ])
                    ChoiceChip(
                      label: Text(mode.$2),
                      avatar: Icon(mode.$3, size: 16),
                      selected: placeMode == mode.$1,
                      // «أنا في المكان الآن» يجلب الموقع فورًا.
                      onSelected: (_) async {
                        setSheetState(() => placeMode = mode.$1);
                        if (mode.$1 == 'link') {
                          final link = await pasteMapsLink(context);
                          if (link == null) return;
                          setSheetState(() => c['link']!.text = link);
                          return;
                        }
                        if (mode.$1 != 'current') return;
                        final value = await _sharedFetchLocation(context);
                        if (value == null) return;
                        setSheetState(() => c['link']!.text = value);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                switch (placeMode) {
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

              if (placeMode == 'link') ...[
                gap,
                OutlinedButton.icon(
                  onPressed: () async {
                    final link = await pasteMapsLink(context);
                    if (link == null) return;
                    setSheetState(() => c['link']!.text = link);
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('لصق الرابط المنسوخ'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: item.color,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
              if (placeMode == 'current') ...[
                gap,
                OutlinedButton.icon(
                  onPressed: () async {
                    final value = await _sharedFetchLocation(context);
                    if (value == null) return;
                    setSheetState(() => c['link']!.text = value);
                  },
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('جلب موقعي الآن مرة أخرى'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: item.color,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
              gap,
              _receiptButton(
                label: 'اختيار صورة للمكان',
                path: photoPath,
                accent: item.color,
                onTap: () async {
                  final path = await _pickReceiptFile(context);
                  if (path == null) return;
                  setSheetState(() => photoPath = path);
                },
                onRemove: () => setSheetState(() => photoPath = ''),
              ),
              gap,
              textField('title', 'اسم المكان', Icons.place_outlined, required: true),
              gap,
              textField('link', 'الموقع أو الرابط', Icons.link_rounded, required: true),
              gap,
              textField('address', 'العنوان', Icons.signpost_outlined),
              gap,
              select('category', 'التصنيف', Icons.category_outlined,
                  const ['المنزل', 'العمل', 'مطعم', 'صديق', 'عميل', 'مهم'],
                  required: true, custom: true),
              if (c['category']!.text == '+ إضافة أخرى') ...[
                gap,
                textField('categoryCustom', 'التصنيف — القيمة الجديدة', Icons.add_rounded, required: true),
              ],
              gap,
              textField('notes', 'ملاحظات', Icons.notes_rounded, lines: 3),
            ],
            gap,
            _receiptButton(
              label: 'إرفاق مستند',
              path: filePath,
              accent: item.color,
              onTap: () async {
                final path = await _pickReceiptFile(context);
                if (path == null) return;
                setSheetState(() => filePath = path);
              },
              onRemove: () => setSheetState(() => filePath = ''),
            ),
          ];
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
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
                                color: item.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(formIcon, color: item.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'إضافة $label',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF022E2A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF5C6B68), fontWeight: FontWeight.w600),
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
                        _sharedFormSectionTitle('الحقول الأساسية', Icons.edit_note_rounded),
                        const SizedBox(height: 12),
                        ...fields,
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: () async {
                            if (!(formKey.currentState?.validate() ?? false)) return;
                            final confirmed = await confirmAction(
                              sheetContext,
                              title: 'تأكيد الحفظ',
                              message: 'هل تريد حفظ $label؟',
                              confirmLabel: 'تأكيد',
                            );
                            if (!confirmed || !sheetContext.mounted) return;
                            Navigator.pop(sheetContext, true);
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: Text('حفظ $label', style: const TextStyle(fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: item.color,
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
      ),
    );
    String v(String key) => c[key]!.text.trim();
    if (saved == true && mounted) {
      Map<String, String> clean(Map<String, String> map) => {
        for (final entry in map.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
      };
      late final _SimpleEntry entry;
      if (isFollowUp) {
        entry = _SimpleEntry(
          kind: label,
          title: v('title'),
          note: v('notes').isNotEmpty ? v('notes') : v('desc'),
          date: v('date'),
          extra: clean({
            'الوصف': v('desc'),
            'الوقت': v('time'),
            if (remind) 'تفعيل تذكير': 'نعم',
            if (remind) 'التكرار': v('repeat'),
            if (remind) 'وقت التذكير': v('remindTime'),
            'ملاحظات': v('notes'),
            'المرفق': filePath,
          }),
        );
      } else if (isDoc) {
        entry = _SimpleEntry(
          kind: 'مستند',
          title: v('title'),
          note: v('notes'),
          // تاريخ الانتهاء هو ما يتابعه مركز المتابعة.
          date: v('expiry'),
          extra: clean({
            'رقم المستند': v('number'),
            'الجهة المصدرة': v('issuer'),
            'تاريخ الإصدار': v('issued'),
            'تاريخ الانتهاء': v('expiry'),
            'تذكير': v('reminder'),
            'المرفق': filePath,
          }),
        );
      } else {
        final category = v('category') == '+ إضافة أخرى' ? v('categoryCustom') : v('category');
        entry = _SimpleEntry(
          kind: category,
          title: v('title'),
          note: v('notes'),
          extra: clean({
            'الموقع أو الرابط': v('link'),
            'العنوان': v('address'),
            'التصنيف': category,
            'صورة المكان': photoPath,
            'المرفق': filePath,
          }),
        );
      }
      final list = _parseSimpleEntries(item.details, sectionKey);
      final at = editIndex;
      if (at != null && at >= 0 && at < list.length) {
        // التعديل يحتفظ بحالة الاكتمال.
        final status = list[at].extra['الحالة'] ?? '';
        list[at] = _SimpleEntry(
          kind: entry.kind,
          title: entry.title,
          note: entry.note,
          date: entry.date,
          extra: {...entry.extra, if (status.isNotEmpty) 'الحالة': status},
        );
      } else {
        list.add(entry);
      }
      final details = Map<String, String>.of(item.details)
        ..[sectionKey] = _encodeSimpleEntries(list);
      await _persist(
        details,
        done: at != null
            ? 'تم حفظ التعديل'
            : isFollowUp
            ? 'تم حفظ $label'
            : isDoc
            ? 'تم حفظ المستند'
            : 'تم حفظ الموقع',
      );
    }
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final controller in c.values) {
        controller.dispose();
      }
    });
  }
}
