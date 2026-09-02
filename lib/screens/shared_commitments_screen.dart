import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/app_settings.dart';
import '../data/shared_entries_repository.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/detail_page_chrome.dart';
import '../widgets/shared/app_filter_sheet.dart';
import '../widgets/shared/followup_center_sheet.dart';
import '../widgets/shared/app_design.dart';
import 'smart_calendar_screen.dart';
import '../widgets/shared/module_shared_widgets.dart';
import '../widgets/shared/measured_pinned_header.dart';
import 'package:share_plus/share_plus.dart';

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
enum _SharedFieldKind { text, number, date, multiline, select, people }

// نفس _CommitmentMenuAction في الشخصية: تعديل/مشاركة/حذف/أرشفة من قائمة
// الثلاث نقاط في شاشة التفاصيل.
enum _SharedCommitmentMenuAction { edit, share, delete, archive }

// نفس _CommitmentMenuItem في الشخصية: أيقونة + تسمية داخل كل عنصر قائمة.
class _SharedCommitmentMenuItem extends StatelessWidget {
  const _SharedCommitmentMenuItem({required this.label, required this.icon, this.color = const Color(0xFF334155)});
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

  static const Color _neutral = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
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
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _neutral)),
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
  });
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
const _splitMethodOptions = ['بالتساوي', 'بالنسبة', 'بالمبلغ المحدد'];
const _notifyScopeOptions = ['الجميع', 'المسؤول فقط'];

final Map<String, _SharedForm> _sharedEntryForms = {
  'مشاركات مشتركة': _SharedForm(
    label: 'مشاركات مشتركة',
    subtitle: 'نشاط جماعي مشترك',
    icon: Icons.diversity_3_rounded,
    color: const Color(0xFF7C3AED),
    fields: [
      _SharedField(
        'اسم المشاركة المشتركة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'المبلغ',
        Icons.payments_outlined,
        kind: _SharedFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _SharedField(
        'العملة',
        Icons.currency_exchange_rounded,
        optional: true,
      ),
      _SharedField(
        _sharedManagedByKey,
        Icons.admin_panel_settings_outlined,
        kind: _SharedFieldKind.select,
        required: true,
        options: _managedByOptions,
      ),
      _SharedField(
        _sharedSplitMethodKey,
        Icons.pie_chart_outline_rounded,
        kind: _SharedFieldKind.select,
        required: true,
        options: _splitMethodOptions,
      ),
      _SharedField(
        _sharedManagerKey,
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'الأعضاء / المشتركين',
        Icons.groups_outlined,
        kind: _SharedFieldKind.people,
        required: true,
      ),
      _SharedField(_sharedDeputyKey, Icons.person_2_outlined, optional: true),
      _SharedField('المكان', Icons.place_outlined),
      _SharedField(
        'تاريخ البداية',
        Icons.event_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'تاريخ النهاية',
        Icons.event_busy_outlined,
        kind: _SharedFieldKind.date,
        optional: true,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        _sharedNotifyScopeKey,
        Icons.notifications_outlined,
        kind: _SharedFieldKind.select,
        options: _notifyScopeOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
    ],
  ),
  'الرحلة / السفر': _SharedForm(
    label: 'الرحلة / السفر',
    subtitle: 'رحلة بميزانية مشتركة',
    icon: Icons.flight_takeoff_rounded,
    color: const Color(0xFF2563EB),
    fields: [
      _SharedField(
        'اسم الرحلة / السفر',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'الميزانية',
        Icons.payments_outlined,
        kind: _SharedFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _SharedField('العملة', Icons.currency_exchange_rounded, optional: true),
      _SharedField(
        _sharedManagedByKey,
        Icons.admin_panel_settings_outlined,
        kind: _SharedFieldKind.select,
        required: true,
        options: _managedByOptions,
      ),
      _SharedField(
        _sharedSplitMethodKey,
        Icons.pie_chart_outline_rounded,
        kind: _SharedFieldKind.select,
        required: true,
        options: _splitMethodOptions,
      ),
      _SharedField(
        'مدير الرحلة',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'الأعضاء / المشتركين',
        Icons.groups_outlined,
        kind: _SharedFieldKind.people,
        required: true,
      ),
      _SharedField(
        'نائب مدير الرحلة',
        Icons.person_2_outlined,
        optional: true,
      ),
      _SharedField('الوجهة', Icons.pin_drop_outlined, required: true),
      _SharedField(
        'تاريخ السفر',
        Icons.flight_takeoff_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'تاريخ العودة',
        Icons.flight_land_outlined,
        kind: _SharedFieldKind.date,
        optional: true,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        _sharedNotifyScopeKey,
        Icons.notifications_outlined,
        kind: _SharedFieldKind.select,
        options: _notifyScopeOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
    ],
  ),
  'جمعية مالية': _SharedForm(
    label: 'جمعية مالية',
    subtitle: 'جمعية مالية دورية',
    icon: Icons.savings_outlined,
    color: const Color(0xFF0D9488),
    fields: [
      _SharedField(
        'اسم الجمعية المالية',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'قيمة المبلغ',
        Icons.payments_outlined,
        kind: _SharedFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _SharedField('العملة', Icons.currency_exchange_rounded, optional: true),
      _SharedField(
        _sharedManagedByKey,
        Icons.admin_panel_settings_outlined,
        kind: _SharedFieldKind.select,
        required: true,
        options: _managedByOptions,
      ),
      _SharedField(
        _sharedSplitMethodKey,
        Icons.pie_chart_outline_rounded,
        kind: _SharedFieldKind.select,
        required: true,
        options: _splitMethodOptions,
      ),
      _SharedField(
        _sharedManagerKey,
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'الأعضاء / المشتركين',
        Icons.groups_outlined,
        kind: _SharedFieldKind.people,
        required: true,
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
        Icons.event_busy_outlined,
        kind: _SharedFieldKind.date,
        optional: true,
      ),
      _SharedField(
        'عدد أشهر الجمعية المالية',
        Icons.calendar_month_outlined,
        kind: _SharedFieldKind.number,
        required: true,
      ),
      _SharedField(
        'موعد الدفع الشهري',
        Icons.event_repeat_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        _sharedNotifyScopeKey,
        Icons.notifications_outlined,
        kind: _SharedFieldKind.select,
        options: _notifyScopeOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
    ],
  ),
  'اللقاءات': _SharedForm(
    label: 'اللقاءات',
    subtitle: 'لقاء دوري بتكلفة مشتركة',
    icon: Icons.groups_2_outlined,
    color: const Color(0xFFDB2777),
    fields: [
      _SharedField(
        'اسم اللقاء',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _SharedField(
        'المبلغ',
        Icons.payments_outlined,
        kind: _SharedFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _SharedField('العملة', Icons.currency_exchange_rounded, optional: true),
      _SharedField(
        _sharedSplitMethodKey,
        Icons.pie_chart_outline_rounded,
        kind: _SharedFieldKind.select,
        required: true,
        options: _splitMethodOptions,
      ),
      _SharedField(
        _sharedManagerKey,
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'الأعضاء / المشتركين',
        Icons.groups_outlined,
        kind: _SharedFieldKind.people,
        required: true,
      ),
      _SharedField(_sharedDeputyKey, Icons.person_2_outlined, optional: true),
      _SharedField('مكان التجمع', Icons.place_outlined, required: true),
      _SharedField(
        'تاريخ التجمع',
        Icons.event_outlined,
        kind: _SharedFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _SharedField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _SharedFieldKind.select,
        options: _paymentMethodOptions,
      ),
      _SharedField(
        _sharedNotifyScopeKey,
        Icons.notifications_outlined,
        kind: _SharedFieldKind.select,
        options: _notifyScopeOptions,
      ),
      _SharedField(
        'ملاحظات',
        Icons.notes_rounded,
        kind: _SharedFieldKind.multiline,
        optional: true,
      ),
    ],
  ),
};

const List<(String, IconData, Color)> _sharedCategoryChips = [
  ('الكل', Icons.apps_rounded, Color(0xFF0B3A78)),
  ('مشاركات مشتركة', Icons.diversity_3_rounded, Color(0xFF7C3AED)),
  ('الرحلة / السفر', Icons.flight_takeoff_rounded, Color(0xFF2563EB)),
  ('اللقاءات', Icons.groups_2_outlined, Color(0xFFDB2777)),
  ('جمعية مالية', Icons.savings_outlined, Color(0xFF0D9488)),
];

Color _sharedTypeColor(String entryType) {
  final form = _sharedEntryForms[entryType];
  return form?.color ?? const Color(0xFF0B3A78);
}

IconData _sharedTypeIcon(String entryType) {
  final form = _sharedEntryForms[entryType];
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

  factory _SharedItem.fromRecord(SharedEntryRecord r) => _SharedItem(
    id: r.id ?? '',
    entryType: r.entryType,
    title: r.title,
    amount: r.amount,
    dueDate: r.dueDate,
    status: r.status,
    details: r.details,
    lastUpdate: r.createdAt == null
        ? ''
        : '${r.createdAt!.day}/${r.createdAt!.month}/${r.createdAt!.year}',
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
  int get pendingApprovalsCount => transactions
      .where(
        (t) => !t.isApproved(
          managedByAll: managedByAll,
          membersCount: membersCount,
        ),
      )
      .length;
}

const _sharedStatusActive = 'نشطة';
const _sharedStatusCompleted = 'مكتملة';
const _sharedStatusArchived = 'مؤرشف';

Color _sharedStatusColor(String status) => switch (status) {
  'نشطة' => const Color(0xFF2563EB),
  'مكتملة' => const Color(0xFF059669),
  'مؤرشف' => const Color(0xFF94A3B8),
  _ => const Color(0xFF64748B),
};

// ---------------------------------------------------------------------------
class SharedCommitmentsScreen extends StatefulWidget {
  final SharedEntriesRepository? repository;
  const SharedCommitmentsScreen({super.key, this.repository});

  @override
  State<SharedCommitmentsScreen> createState() =>
      _SharedCommitmentsScreenState();
}

class _SharedCommitmentsScreenState extends State<SharedCommitmentsScreen> {
  late final SharedEntriesRepository _repository;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _loading = true;
  String? _loadError;
  List<_SharedItem> _items = [];
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
    // إعادة البناء عند تغيّر التركيز حتى تختفي قائمة الاقتراحات فور خروج
    // المؤشر من خانة البحث (الكتابة وحدها لا تكفي لالتقاط فقدان التركيز).
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await _repository.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = rows.map(_SharedItem.fromRecord).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل الالتزامات المشتركة. اسحب للتحديث للمحاولة مرة أخرى.';
        _loading = false;
      });
    }
  }

  bool _isOpenItem(_SharedItem i) =>
      i.status != _sharedStatusCompleted && i.status != _sharedStatusArchived;

  int _pendingRequestsCount() => _items
      .where(_isOpenItem)
      .fold<int>(0, (sum, i) => sum + i.pendingApprovalsCount);

  /// تطبيق أقسام الفلتر الرئيسي على بند مشترك.
  bool _matchesMainFilter(_SharedItem item) {
    switch (_filter.status) {
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
        if (!item.status.contains('مؤرشف')) return false;
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
    var list = _items.where((i) {
      final typeMatches = _selectedType == 'الكل' || i.entryType == _selectedType;
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

    // الفلتر الصغير يُقدّم المطابق ولا يُخفي غيره، ثم ترتيب ثانوي ثابت
    // (الأحدث إنشاءً) حتى لا تتبدّل مواضع البنود المتساوية عشوائيًا.
    int rank(_SharedItem item) {
      switch (_selectedSort) {
        case 'نشط':
          return _isOpenItem(item) ? 0 : 1;
        case 'مكتمل':
          return item.status.contains('مكتمل') ? 0 : 1;
        case 'ملغاة':
          return item.status.contains('ملغا') ? 0 : 1;
        default:
          return 0;
      }
    }

    list.sort((a, b) {
      // "أعلى/أقل مبلغ" من الفلتر الكبير يتقدّم على ترتيب الفلتر الصغير.
      if (_filter.amountShortcut == 'أعلى مبلغ') {
        final byAmount = b.amount.compareTo(a.amount);
        if (byAmount != 0) return byAmount;
      } else if (_filter.amountShortcut == 'أقل مبلغ') {
        final byAmount = a.amount.compareTo(b.amount);
        if (byAmount != 0) return byAmount;
      }
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (b.createdAt ?? DateTime(2000)).compareTo(
        a.createdAt ?? DateTime(2000),
      );
    });
    return list;
  }

  int _countForType(String type) => type == 'الكل'
      ? _items.length
      : _items.where((i) => i.entryType == type).length;

  void _openDetails(_SharedItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedCommitmentDetailsScreen(
          item: item,
          repository: _repository,
          onChanged: (updated) {
            setState(() {
              final idx = _items.indexWhere((i) => i.id == updated.id);
              if (idx != -1) _items[idx] = updated;
            });
          },
          onDeleted: (id) {
            setState(() => _items.removeWhere((i) => i.id == id));
          },
        ),
      ),
    );
  }

  int _pendingCountForBanner() => _pendingRequestsCount();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _buildScreenBody(),
      ),
      floatingActionButton: AddFab(
        screenId: 'shared_commitments',
        onPressed: _openTypePickerSheet,
        label: 'إضافة التزام',
        backgroundColor: const Color(0xFF7C3AED),
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
              colors: const [Color(0xFF6D28D9), Color(0xFF7C3AED)],
              onSmartCalendarTap: _openSmartCalendar,
              onClose: () => Navigator.of(context).pop(),
            ),
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
            // مركز المتابعة يتحرّك مع الصفحة ويختفي عند النزول لأسفل.
            SliverToBoxAdapter(
              child: ColoredBox(
                color: AppTheme.page,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _buildFollowUpCenter(),
                ),
              ),
            ),
            // عنوان "الفئات" يمرّ مع الصفحة، وشريط الشرائح وحده يثبت.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                child: const Text(
                  'الفئات',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF334155),
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
              color: Color(0xFFB42318),
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
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadError ?? '',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB42318), fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
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
            textDirection: TextDirection.rtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              // حقل ممتلئ بلا حدود بنفس نصف قطر ولون حقول التطبيق.
              hintText: 'بحث في الالتزامات المشتركة',
              hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13, fontWeight: FontWeight.w600),
              prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppTheme.chevron),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.muted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: AppTheme.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                borderSide: BorderSide.none,
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
              color: const Color(0xFF7C3AED),
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
                        color: const Color(0xFFF59E0B),
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
              color: Color(0x1416232B),
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
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          values[i],
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
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
      accent: const Color(0xFF6D28D9),
      values: _filter..mainCategory = _selectedType,
      mainCategories: _sharedCategoryChips
          .map((chip) => chip.$1)
          .toList(growable: false),
      amountShortcuts: const ['أعلى مبلغ', 'أقل مبلغ'],
      documentStates: const [],
      sections: const [
        AppFilterSection.mainCategory,
        AppFilterSection.date,
        AppFilterSection.status,
        AppFilterSection.amount,
        AppFilterSection.document,
        AppFilterSection.people,
        AppFilterSection.delegates,
        AppFilterSection.place,
      ],
      onApply: (values) => setState(() {
        _selectedType = values.mainCategory;
        _filter
          ..mainCategory = values.mainCategory
          ..subCategory = values.subCategory
          ..dateFrom = values.dateFrom
          ..dateTo = values.dateTo
          ..status = values.status
          ..amountFrom = values.amountFrom
          ..amountTo = values.amountTo
          ..amountShortcut = values.amountShortcut
          ..documentName = values.documentName
          ..documentState = values.documentState
          ..personName = values.personName
          ..personCategory = values.personCategory
          ..delegateName = values.delegateName
          ..placeName = values.placeName;
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
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openFollowUpSheet,
        borderRadius: BorderRadius.circular(12),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? 'طلب واحد بانتظار إجراء — راجع "طلباتي" في مركز المتابعة'
                  : '$count طلبات بانتظار إجراء — راجع "طلباتي" في مركز المتابعة',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
            ),
          ),
          InkWell(
            onTap: () => setState(() {
              _requestBannerDismissed = true;
              _requestBannerDismissedAtCount = count;
            }),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 17, color: Color(0xFFB45309)),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildCategoriesBlock() {
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
            itemCount: _sharedCategoryChips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final chip = _sharedCategoryChips[index];
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
      textDirection: TextDirection.rtl,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 36),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.rIcon),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF7C3AED)),
          ),
        ),
        const SizedBox(width: AppTheme.sMd),
        Expanded(
          child: Text(
            _selectedType == 'الكل' ? 'جميع الالتزامات' : _selectedType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardTitle,
          ),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('shared-sort-button'),
          tooltip: 'ترتيب الالتزامات',
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
              ['الأحدث أولاً', 'نشط', 'مكتمل', 'ملغاة'].map((o) {
                final selected = o == _selectedSort;
                return PopupMenuItem(
                  value: o,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 17,
                          color: selected
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          o,
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: selected
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF334155),
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
                _selectedSort,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED)),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF7C3AED)),
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
              color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diversity_3_rounded, size: 32, color: Color(0xFF7C3AED)),
          ),
          const SizedBox(height: 10),
          const Text(
            'لا توجد التزامات مشتركة مطابقة',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          const Text(
            'ابدأ بإضافة مشاركة، رحلة، جمعية، أو لقاء',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------
  // مركز المتابعة: نفس فكرة الشخصية (مجموعات + عناصر فرعية قابلة للفتح في
  // صفحة منبثقة صغيرة)، لكن بمجموعات تلائم طبيعة الالتزامات المشتركة.
  List<_SharedFollowUpGroupData> _buildFollowUpGroups() {
    final items = _selectedType == 'الكل'
        ? _items
        : _items.where((i) => i.entryType == _selectedType).toList();

    final pendingApprovals = <_SharedCommitmentItemRef>[];
    for (final item in items.where(_isOpenItem)) {
      if (item.pendingApprovalsCount > 0) {
        pendingApprovals.add(_SharedCommitmentItemRef(item));
      }
    }

    bool isDueSoonOrOverdue(_SharedItem i) {
      final due = _parseDueDate(i.dueDate);
      if (due == null) return false;
      final diff = due.difference(DateUtils.dateOnly(DateTime.now())).inDays;
      return diff <= 7;
    }

    final dueItems = items.where((i) => _isOpenItem(i) && isDueSoonOrOverdue(i)).map(_SharedCommitmentItemRef.new).toList();

    final membersOwing = <_SharedCommitmentItemRef>[];
    for (final item in items.where(_isOpenItem)) {
      final hasOwing = item.members.any((m) => _memberBalance(item, m) > 0);
      if (hasOwing) membersOwing.add(_SharedCommitmentItemRef(item));
    }

    final renewing = items
        .where((i) => _isOpenItem(i) && (i.entryType == 'جمعية مالية' || i.entryType == 'الرحلة / السفر') && isDueSoonOrOverdue(i))
        .map(_SharedCommitmentItemRef.new)
        .toList();

    return [
      _SharedFollowUpGroupData(
        title: 'طلباتي',
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFB45309),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'بانتظار الموافقة',
            icon: Icons.pending_actions_outlined,
            items: pendingApprovals,
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'الاستحقاقات',
        icon: Icons.event_busy_outlined,
        color: const Color(0xFFB42318),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'قريبة الاستحقاق',
            icon: Icons.schedule_outlined,
            items: dueItems,
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'الأعضاء',
        icon: Icons.groups_outlined,
        color: const Color(0xFF0EA5E9),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'عليهم مستحقات',
            icon: Icons.account_balance_wallet_outlined,
            items: membersOwing,
          ),
        ],
      ),
      _SharedFollowUpGroupData(
        title: 'التجديدات والانتهاءات',
        icon: Icons.autorenew_rounded,
        color: const Color(0xFF7C3AED),
        metrics: [
          _SharedFollowUpSubMetric(
            label: 'قريبة الانتهاء',
            icon: Icons.event_repeat_outlined,
            items: renewing,
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

  // نصيب العضو من إجمالي المصروفات المعتمدة ناقص ما دفعه فعليًا: موجب يعني
  // أن عليه مبلغًا متبقيًا، سالب يعني أن له مبلغًا زائدًا لدى المجموعة.
  int _memberBalance(_SharedItem item, _SharedMember member) {
    final totalSpent = item.approvedSpent;
    final share = totalSpent <= 0 || item.membersCount == 0
        ? 0
        : (totalSpent / item.membersCount).round();
    final paid = item.transactions
        .where(
          (t) =>
              (t.kind == 'دفعة' || t.kind == 'سداد') &&
              t.submittedBy == member.name &&
              t.isApproved(managedByAll: item.managedByAll, membersCount: item.membersCount),
        )
        .fold<int>(0, (sum, t) => sum + (int.tryParse(t.amount) ?? 0));
    return share - paid;
  }

  void _openSmartCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SmartCalendarScreen()));
  }

  Widget _buildFollowUpCenter() {
    final groups = _buildFollowUpGroups();
    final pendingTotal = groups[0].total;
    final dueTotal = groups[1].total;
    final renewalsTotal = groups[3].total;
    const accent = Color(0xFF6D28D9);
    final metrics = [
      (
        'طلبات',
        pendingTotal,
        Icons.hourglass_top_rounded,
        const Color(0xFF2563EB),
      ),
      ('مستحقات', dueTotal, Icons.payments_outlined, const Color(0xFF07835C)),
      (
        'تجديدات',
        renewalsTotal,
        Icons.autorenew_rounded,
        const Color(0xFFB56A09),
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
      subtitle: _selectedType == 'الكل'
          ? 'الأهم والأقرب من جميع الالتزامات المشتركة'
          : 'متابعة $_selectedType',
      onTap: _openFollowUpSheet,
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
      accent: const Color(0xFF6D28D9),
      title: _selectedType == 'الكل'
          ? 'مركز المتابعة'
          : 'متابعة $_selectedType',
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
                            ? ref.item.entryType
                            : '${ref.item.entryType} · ${ref.item.dueDate}',
                        icon: ref.item.icon,
                        color: ref.item.color,
                        trailingText: ref.item.amount > 0
                            ? '${ref.item.amount} ${ref.item.currency}'
                            : null,
                        onTap: () => _openDetails(ref.item),
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
            textDirection: TextDirection.rtl,
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
                      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('اختيار نوع الإضافة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                            SizedBox(height: 4),
                            Text('اختر نوع الالتزام المشترك المناسب', style: TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => Navigator.pop(sheetContext),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF475569)),
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
                        childAspectRatio: 0.78,
                        children: _sharedEntryForms.values
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
      final existing = editing?.details[field.label] ?? '';
      if (field.kind == _SharedFieldKind.select) {
        selectValues[field.label] = existing.isNotEmpty ? existing : (field.options.isNotEmpty ? null : null);
      } else if (field.kind == _SharedFieldKind.people) {
        peopleValues[field.label] = existing.isNotEmpty ? existing.split('،').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : <String>[];
        controllers[field.label] = TextEditingController();
      } else {
        controllers[field.label] = TextEditingController(text: existing);
      }
    }
    final titleField = form.fields.firstWhere((f) => f.isTitle, orElse: () => form.fields.first);
    final amountField = form.fields.firstWhere((f) => f.isAmount, orElse: () => form.fields.first);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> save() async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            for (final field in form.fields) {
              if (field.kind == _SharedFieldKind.people && field.required && (peopleValues[field.label] ?? const <String>[]).isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${field.label} مطلوب — أضف عضوًا واحدًا على الأقل')));
                return;
              }
            }
            setSheetState(() => isSaving = true);
            // يبدأ من التفاصيل القائمة بدل خريطة فارغة: نموذج التعديل لا
            // يملك أقسام "متابعة وتخطيط" و"مستندات" و"مواقع وأماكن"
            // و"الإجراءات"، فكان إعادة بنائه من الصفر يمحوها جميعًا من
            // قاعدة البيانات بمجرد الضغط على "حفظ التعديلات".
            final details = <String, String>{...?editing?.details};
            for (final field in form.fields) {
              if (field.kind == _SharedFieldKind.select) {
                details[field.label] = selectValues[field.label] ?? '';
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

            final amountText = controllers[amountField.label]?.text.trim() ?? '0';
            final record = SharedEntryRecord(
              id: editing?.id,
              entryType: form.label,
              title: controllers[titleField.label]?.text.trim() ?? '',
              amount: int.tryParse(amountText) ?? 0,
              dueDate: controllers.entries
                      .firstWhere(
                        (e) => form.fields.firstWhere((f) => f.label == e.key).kind == _SharedFieldKind.date && form.fields.firstWhere((f) => f.label == e.key).isPrimary,
                        orElse: () => MapEntry('', TextEditingController()),
                      )
                      .value
                      .text
                      .trim(),
              status: editing?.status ?? _sharedStatusActive,
              details: details,
            );
            try {
              final saved = editing == null ? await repository.create(record) : await repository.update(record);
              if (!outerContext.mounted) return;
              Navigator.pop(sheetContext);
              onSaved(_SharedItem.fromRecord(saved), isNew: editing == null);
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
            textDirection: TextDirection.rtl,
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
                          decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(99)),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: form.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                            child: Icon(form.icon, color: form.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  editing == null ? 'إضافة ${form.label}' : 'تعديل ${form.label}',
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                ),
                                Text(form.subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _sharedFormSectionTitle('الحقول الأساسية', Icons.edit_note_rounded),
                      const SizedBox(height: 12),
                      for (final field in form.fields) ...[
                        _buildSharedField(context, field, controllers, selectValues, peopleValues, setSheetState, form.color),
                        const SizedBox(height: 12),
                      ],
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
    for (final c in controllers.values) {
      c.dispose();
    }
}

// نُقلت خارج الصنف لتصبح قابلة للاستخدام من شاشة القائمة (الإضافة) وشاشة
// التفاصيل (التعديل) معًا، بدل أن تبقى حكرًا على صنف State واحد فقط.
Widget _buildSharedField(
  BuildContext context,
  _SharedField field,
  Map<String, TextEditingController> controllers,
  Map<String, String?> selectValues,
  Map<String, List<String>> peopleValues,
  StateSetter setSheetState,
  Color accent,
) {
  final labelText = field.label + (field.optional ? ' (اختياري)' : '');
    switch (field.kind) {
      case _SharedFieldKind.select:
        return DropdownButtonFormField<String>(
          initialValue: selectValues[field.label],
          decoration: _sharedFieldDecoration(labelText, field.icon, accent),
          items: field.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setSheetState(() => selectValues[field.label] = v),
          validator: field.required ? (v) => v == null || v.isEmpty ? 'مطلوب' : null : null,
        );
      case _SharedFieldKind.people:
        {
        final names = peopleValues[field.label] ?? const <String>[];
        final controller = controllers[field.label]!;
        return StatefulBuilder(
          builder: (context, setFieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labelText, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: _sharedFieldDecoration('اسم العضو ثم اضغط إضافة', Icons.person_add_alt_1_outlined, accent),
                      onSubmitted: (v) {
                        final name = v.trim();
                        if (name.isEmpty) return;
                        setSheetState(() {
                          setFieldState(() {
                            names.add(name);
                            peopleValues[field.label] = names;
                            controller.clear();
                          });
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      setSheetState(() {
                        setFieldState(() {
                          names.add(name);
                          peopleValues[field.label] = names;
                          controller.clear();
                        });
                      });
                    },
                    icon: Icon(Icons.add_circle_rounded, color: accent),
                  ),
                ],
              ),
              if (names.isNotEmpty)
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
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (field.required && names.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('أضف عضوًا واحدًا على الأقل', style: TextStyle(fontSize: 10.5, color: Color(0xFFB42318))),
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
          decoration: _sharedFieldDecoration(labelText, field.icon, accent),
          validator: field.required ? (v) => v == null || v.isEmpty ? 'مطلوب' : null : null,
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (pickerContext, child) => Directionality(textDirection: TextDirection.rtl, child: child!));
            if (picked == null) return;
            controller.text = '${picked.day}/${picked.month}/${picked.year}';
            setSheetState(() {});
          },
        );
      case _SharedFieldKind.multiline:
        return TextFormField(
          controller: controllers[field.label],
          maxLines: 3,
          decoration: _sharedFieldDecoration(labelText, field.icon, accent),
        );
      case _SharedFieldKind.number:
        return TextFormField(
          controller: controllers[field.label],
          keyboardType: TextInputType.number,
          decoration: _sharedFieldDecoration(labelText, field.icon, accent),
          validator: field.required ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null : null,
        );
      case _SharedFieldKind.text:
        return TextFormField(
          controller: controllers[field.label],
          decoration: _sharedFieldDecoration(labelText, field.icon, accent),
          validator: field.required ? (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null : null,
        );
    }
}

InputDecoration _sharedFieldDecoration(String label, IconData icon, Color accent) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, color: accent),
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
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: accent, width: 1.5)),
);

Widget _sharedFormSectionTitle(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 19, color: const Color(0xFF7C3AED)),
      const SizedBox(width: 7),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
    ],
  );
}

// ============================================================================
// عناصر بيانات مركز المتابعة
// ============================================================================
class _SharedCommitmentItemRef {
  final _SharedItem item;
  const _SharedCommitmentItemRef(this.item);
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

  const _SharedUnifiedCard({required this.title, required this.icon, required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w900))),
            ],
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
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: valueColor ?? const Color(0xFF1E293B), fontSize: 12, fontWeight: FontWeight.w900),
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
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppTheme.surfaceInner,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
          ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: form.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(form.icon, color: form.color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                form.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), height: 1.2),
              ),
              const SizedBox(height: 3),
              Text(
                form.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      label: label,
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

  String get _amountLabel =>
      item.entryType == 'الرحلة / السفر' ? 'الميزانية' : 'المبلغ';

  @override
  Widget build(BuildContext context) {
    // بطاقة القائمة الموحَّدة نفسها المستعملة في الالتزامات الشخصية
    // وإدارة الأشخاص.
    return AppEntityCard(
      icon: item.icon,
      iconColor: item.color,
      title: item.title,
      subtitle: item.entryType,
      statusColor: _sharedStatusColor(item.status),
      stats: [
        // المبلغ يظهر فقط إن وُجد فعلًا.
        if (item.amount > 0) '$_amountLabel : ${item.amount} ${item.currency}',
        if (item.dueDate.isNotEmpty) 'التاريخ : ${item.dueDate}',
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
  const _SimpleEntry({required this.kind, required this.title, this.note = '', this.date = ''});

  Map<String, String> toMap() => {'kind': kind, 'title': title, 'note': note, 'date': date};
  factory _SimpleEntry.fromMap(Map map) => _SimpleEntry(
    kind: map['kind']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    note: map['note']?.toString() ?? '',
    date: map['date']?.toString() ?? '',
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

const _followUpKinds = ['مهمة', 'تذكير', 'موعد', 'عادة', 'ملاحظات', 'تفويض'];
const _actionKinds = ['تسوية مالية', 'تصويت', 'اعتراض', 'استبيان'];
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
  });

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
  static const _tabs = ['الملخص', 'المالية', 'السجل', 'متابعة وتخطيط', 'الأعضاء', 'مستندات', 'مواقع وأماكن'];
  static const _tabIcons = [
    Icons.summarize_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.history_rounded,
    Icons.fact_check_outlined,
    Icons.groups_outlined,
    Icons.description_outlined,
    Icons.place_outlined,
  ];

  @override
  void initState() {
    super.initState();
    item = widget.item;
  }

  Future<bool> _persist(Map<String, String> details, {String? status}) async {
    final record = SharedEntryRecord(
      id: item.id,
      entryType: item.entryType,
      title: item.title,
      amount: item.amount,
      dueDate: item.dueDate,
      status: status ?? item.status,
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
      setState(() => item = updated);
      widget.onChanged(updated);
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

  // مطابق تمامًا لـ _handleMenuAction في الشخصية: تعديل/مشاركة/حذف/أرشفة.
  Future<void> _handleMenuAction(_SharedCommitmentMenuAction action) async {
    switch (action) {
      case _SharedCommitmentMenuAction.edit:
        await _openEditForm();
      case _SharedCommitmentMenuAction.share:
        await _shareCommitment();
      case _SharedCommitmentMenuAction.delete:
        await _deleteCommitment();
      case _SharedCommitmentMenuAction.archive:
        await _archiveCommitment();
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

  Future<void> _shareCommitment() async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: item.title,
        text: [
          item.title,
          'النوع: ${item.entryType}',
          'المبلغ: ${item.amount} ${item.currency}',
          'الاستحقاق: ${item.dueDate.isEmpty ? 'غير محدد' : item.dueDate}',
          'الحالة: ${item.status}',
        ].join('\n'),
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// الأرشفة أصبحت تبديلًا: كانت تُثبّت الحالة على "مؤرشف" بلا أي وسيلة
  /// للتراجع، فيخرج الالتزام نهائيًا من كل الحسابات والقوائم المفتوحة.
  Future<void> _archiveCommitment() async {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
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
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
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

  int _memberBalance(_SharedMember member) {
    final totalSpent = item.approvedSpent;
    final share = totalSpent <= 0 || item.membersCount == 0 ? 0 : (totalSpent / item.membersCount).round();
    final paid = item.transactions
        .where((t) => (t.kind == 'دفعة' || t.kind == 'سداد') && t.submittedBy == member.name && t.isApproved(managedByAll: item.managedByAll, membersCount: item.membersCount))
        .fold<int>(0, (sum, t) => sum + (int.tryParse(t.amount) ?? 0));
    return share - paid;
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
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'shared-details-add',
        tooltip: 'إضافة إلى الالتزام',
        backgroundColor: item.color,
        foregroundColor: Colors.white,
        elevation: 7,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(_fabLabelForTab(), style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: _fabActionForTab(),
      ),
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text('تفاصيل ${item.entryType}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
        leading: IconButton(
          tooltip: 'رجوع',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          key: const ValueKey('shared-compact-details'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          children: [
            Container(
              key: const ValueKey('shared-compact-details-header'),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  Container(height: 1, color: const Color(0xFFEEF2F7)),
                  _buildHighlightBar(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildTabsRow(),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(_tabIndex), child: _buildTabContent()),
            ),
          ],
        ),
      ),
    );
  }

  String _fabLabelForTab() {
    switch (_tabIndex) {
      case 1:
        return 'عملية مالية';
      case 3:
        return 'عنصر متابعة';
      case 4:
        return 'عضو / مسؤول';
      case 5:
        return 'مستند';
      case 6:
        return 'موقع';
      default:
        return 'إضافة';
    }
  }

  VoidCallback _fabActionForTab() {
    switch (_tabIndex) {
      case 1:
        return () => _openTransactionForm();
      case 3:
        return () => _openSimpleEntrySheet(sectionKey: _followUpDetailsKey, kinds: _followUpKinds);
      case 4:
        return _openAddMemberSheet;
      case 5:
        return () => _openSimpleEntrySheet(sectionKey: _documentsDetailsKey, kinds: _documentKinds);
      case 6:
        return () => _openSimpleEntrySheet(sectionKey: _placesDetailsKey, kinds: _placeKinds);
      default:
        return _openQuickAddSheet;
    }
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
        textDirection: TextDirection.rtl,
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
                        decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('إضافة إلى الالتزام', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
                    const SizedBox(height: 4),
                    const Text('اختر ما تريد إضافته لهذا الالتزام', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
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
                              child: Text('تنظيم ومتابعة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
                            ),
                            Icon(orgExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: item.color),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _SharedQuickAddTile(
                              key: const ValueKey('shared-add-followup-option'),
                              label: 'عنصر متابعة',
                              icon: Icons.fact_check_outlined,
                              onTap: () => Navigator.pop(sheetContext, 'عنصر متابعة'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SharedQuickAddTile(
                              key: const ValueKey('shared-add-action-option'),
                              label: 'إجراء',
                              icon: Icons.gavel_outlined,
                              onTap: () => Navigator.pop(sheetContext, 'إجراء'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SharedQuickAddTile(
                              key: const ValueKey('shared-add-place-option'),
                              label: 'موقع',
                              icon: Icons.place_outlined,
                              onTap: () => Navigator.pop(sheetContext, 'موقع'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // تفويض: بند مستقل في قائمة "+ إضافة" حسب ملف المتطلبات،
                      // لكن بياناته تُخزَّن ضمن "متابعة وتخطيط" مباشرة (نفس
                      // نمط تخزين عناصر المتابعة)، مع إدارة تفصيلية لاحقًا من
                      // تبويب "المزيد".
                      Row(
                        children: [
                          Expanded(
                            child: _SharedQuickAddTile(
                              key: const ValueKey('shared-add-delegation-option'),
                              label: 'تفويض',
                              icon: Icons.assignment_ind_outlined,
                              onTap: () => Navigator.pop(sheetContext, 'تفويض'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                          const SizedBox(width: 8),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
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
      case 'إجراء':
        // كانت الإجراءات تُحفَظ في مفتاح 'الإجراءات' الذي لا تقرأه أي شاشة،
        // فيختفي ما يسجّله المستخدم نهائيًا رغم نجاح الحفظ. تُحفَظ الآن في
        // قسم "متابعة وتخطيط" الذي يعرضها فعليًا — وهو نفس المكان الذي تصل
        // إليه الأنواع الأربعة ذاتها عند إضافتها من زر المتابعة.
        _openSimpleEntrySheet(sectionKey: _followUpDetailsKey, kinds: _actionKinds);
      case 'موقع':
        _openSimpleEntrySheet(sectionKey: _placesDetailsKey, kinds: _placeKinds);
      case 'تفويض':
        _openSimpleEntrySheet(sectionKey: _followUpDetailsKey, kinds: _followUpKinds, initialKind: 'تفويض');
    }
  }

  // مطابق تمامًا لـ _CompactCommitmentHeader في الشخصية: صندوق أيقونة
  // 44×44، عنوان+نوع الالتزام، شارة الحالة، وقائمة الثلاث نقاط — بلا زر
  // رجوع داخل الصف (الرجوع أصبح من AppBar كما في الشخصية تمامًا).
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
                const SizedBox(height: 3),
                Text(item.entryType, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: _sharedStatusColor(item.status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(item.status, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: _sharedStatusColor(item.status))),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_SharedCommitmentMenuAction>(
            tooltip: 'إجراءات الالتزام',
            onSelected: _handleMenuAction,
            icon: const Icon(Icons.more_vert_rounded, size: 23, color: Color(0xFF475569)),
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
              const PopupMenuItem(
                value: _SharedCommitmentMenuAction.delete,
                child: _SharedCommitmentMenuItem(label: 'حذف', icon: Icons.delete_outline_rounded, color: Color(0xFFB42318)),
              ),
              PopupMenuItem(
                value: _SharedCommitmentMenuAction.archive,
                child: _SharedCommitmentMenuItem(
                  label: item.status == _sharedStatusArchived
                      ? 'إلغاء الأرشفة'
                      : 'أرشيف',
                  icon: item.status == _sharedStatusArchived
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

  List<(String, String, IconData)> _highlights() {
    switch (item.entryType) {
      case 'مشاركات مشتركة':
        return [
          ('المبلغ', '${item.amount} ${item.currency}', Icons.payments_outlined),
          ('التاريخ', item.dueDate.isEmpty ? '—' : item.dueDate, Icons.event_outlined),
          ('عدد المشتركين', '${item.membersCount}', Icons.groups_outlined),
        ];
      case 'الرحلة / السفر':
        return [
          ('الميزانية', '${item.amount} ${item.currency}', Icons.payments_outlined),
          ('تاريخ الرحلة', item.dueDate.isEmpty ? '—' : item.dueDate, Icons.flight_takeoff_outlined),
          ('عدد الأعضاء', '${item.membersCount}', Icons.groups_outlined),
        ];
      case 'جمعية مالية':
        return [
          ('المبلغ', '${item.amount} ${item.currency}', Icons.payments_outlined),
          ('موعد الدفع الشهري', item.details['موعد الدفع الشهري']?.isNotEmpty == true ? item.details['موعد الدفع الشهري']! : '—', Icons.event_repeat_outlined),
          ('عدد المشتركين', '${item.membersCount}', Icons.groups_outlined),
        ];
      case 'اللقاءات':
        return [
          ('المبلغ', '${item.amount} ${item.currency}', Icons.payments_outlined),
          ('التاريخ', item.dueDate.isEmpty ? '—' : item.dueDate, Icons.event_outlined),
          ('عدد المشتركين', '${item.membersCount}', Icons.groups_outlined),
        ];
      default:
        return [('المبلغ', '${item.amount} ${item.currency}', Icons.payments_outlined)];
    }
  }

  Widget _buildHighlightBar() {
    final highlights = _highlights();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          for (var i = 0; i < highlights.length; i++) ...[
            if (i > 0) Container(width: 1, height: 34, color: item.color.withValues(alpha: 0.18), margin: const EdgeInsets.symmetric(horizontal: 8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(highlights[i].$3, size: 16, color: item.color),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(highlights[i].$2, maxLines: 1, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
                  ),
                  const SizedBox(height: 2),
                  Text(highlights[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
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
    return DetailPageTabs(
      key: const ValueKey('shared-inline-details-tabs'),
      sections: [
        for (var i = 0; i < _tabs.length; i++)
          DetailSectionTab(label: _tabs[i], icon: _tabIcons[i]),
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
        return _buildFinanceTab();
      case 2:
        return _buildHistoryTab();
      case 3:
        return _buildSimpleListTab(sectionKey: _followUpDetailsKey, kinds: _followUpKinds, icon: Icons.fact_check_outlined, emptyText: 'لا توجد عناصر متابعة أو مهام بعد');
      case 4:
        return _buildMembersTab();
      case 5:
        return _buildSimpleListTab(sectionKey: _documentsDetailsKey, kinds: _documentKinds, icon: Icons.description_outlined, emptyText: 'لا توجد مستندات بعد');
      case 6:
        return _buildSimpleListTab(sectionKey: _placesDetailsKey, kinds: _placeKinds, icon: Icons.place_outlined, emptyText: 'لا توجد مواقع أو أماكن بعد');
      default:
        return const SizedBox.shrink();
    }
  }

  // -------------------------------------------------------------- الملخص
  // يسجّل كل شيء أُدخل عند "+ إضافة التزام" بالإضافة إلى تاريخ الإنشاء —
  // حسب نص الملف بالضبط.
  Widget _buildSummaryTab() {
    final form = _sharedEntryForms[item.entryType];
    final rows = <(String, String, IconData)>[
      if (item.lastUpdate.isNotEmpty) ('تاريخ إنشاء الالتزام', item.lastUpdate, Icons.event_available_outlined),
      for (final field in form?.fields ?? const <_SharedField>[])
        if ((item.details[field.label] ?? '').isNotEmpty && field.kind != _SharedFieldKind.people)
          (field.label, item.details[field.label]!, field.icon),
      if (item.membersCount > 0) ('الأعضاء / المشتركين', item.members.map((m) => '${m.name} (${m.role})').join('، '), Icons.groups_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SharedUnifiedCard(
          title: 'ملخص الالتزام',
          icon: Icons.summarize_outlined,
          color: item.color,
          children: [
            for (final row in rows) _SharedInfoRow(label: row.$1, value: row.$2, icon: row.$3),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------- المالية
  Widget _buildFinanceTab() {
    final transactions = item.transactions.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFinanceSummaryCard(),
        const SizedBox(height: 14),
        _SharedUnifiedCard(
          title: 'سجل العمليات',
          icon: Icons.receipt_long_outlined,
          color: item.color,
          children: [
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: Text('لا توجد عمليات مالية بعد', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600))),
              )
            else
              for (final t in transactions) Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildTransactionTile(t)),
          ],
        ),
      ],
    );
  }

  Widget _buildFinanceSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [item.color.withValues(alpha: 0.14), item.color.withValues(alpha: 0.06)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(child: _financeStat('الميزانية الأصلية', '${item.amount}', item.color)),
          Expanded(child: _financeStat('ميزانية إضافية معتمدة', '${item.approvedExtraBudget}', item.color)),
          Expanded(child: _financeStat('المصروف المعتمد', '${item.approvedSpent}', const Color(0xFFB42318))),
          Expanded(child: _financeStat('الرصيد المتبقي', '${item.remainingBudget}', const Color(0xFF059669))),
        ],
      ),
    );
  }

  Widget _financeStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildTransactionTile(_SharedTransaction t) {
    final approved = t.isApproved(managedByAll: item.managedByAll, membersCount: item.membersCount);
    final approvalLabel = item.managedByAll
        ? '${t.approvedBy.length}/${item.membersCount} موافقة'
        : (t.managerApproved ? 'وافق المسؤول' : 'بانتظار موافقة المسؤول');
    final kindColor = t.kind == 'مصروف' ? const Color(0xFFB42318) : const Color(0xFF059669);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(t.kind == 'مصروف' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, size: 18, color: kindColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${t.kind} — ${t.amount} ${item.currency}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: (approved ? const Color(0xFF059669) : const Color(0xFFB45309)).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(approved ? 'معتمد' : 'بانتظار', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: approved ? const Color(0xFF059669) : const Color(0xFFB45309))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t.submittedBy.isEmpty ? '—' : t.submittedBy} · ${t.date} ${t.purpose.isNotEmpty ? '· ${t.purpose}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(approvalLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const Spacer(),
              if (!approved)
                TextButton(onPressed: () => _approveTransaction(t), child: const Text('تسجيل موافقة')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approveTransaction(_SharedTransaction target) async {
    if (item.managedByAll) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اختر العضو الموافِق', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                for (final m in item.members.where((m) => !target.approvedBy.contains(m.name)))
                  ListTile(title: Text(m.name), onTap: () => Navigator.pop(sheetContext, m.name)),
              ],
            ),
          ),
        ),
      );
      if (choice == null) return;
      final updatedList = item.transactions.map((t) => identical(t, target) || (t.kind == target.kind && t.date == target.date && t.amount == target.amount && t.submittedBy == target.submittedBy) ? t.copyWith(approvedBy: [...t.approvedBy, choice]) : t).toList();
      final details = Map<String, String>.of(item.details)..[_sharedTransactionsDetailKey] = _encodeSharedTransactions(updatedList);
      await _persist(details);
    } else {
      final updatedList = item.transactions.map((t) => (t.kind == target.kind && t.date == target.date && t.amount == target.amount && t.submittedBy == target.submittedBy) ? t.copyWith(managerApproved: true) : t).toList();
      final details = Map<String, String>.of(item.details)..[_sharedTransactionsDetailKey] = _encodeSharedTransactions(updatedList);
      await _persist(details);
    }
  }

  Future<void> _openTransactionForm() async {
    final kinds = ['دفعة', 'سداد', 'مصروف', 'ميزانية إضافية'];
    var kind = kinds[2];
    final customKindCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final now = DateTime.now();
    final dateCtrl = TextEditingController(text: '${now.day}/${now.month}/${now.year}');
    String? submittedBy = item.members.isNotEmpty ? item.members.first.name : null;
    final formKey = GlobalKey<FormState>();
    final rootContext = context;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('إضافة عملية مالية', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: _sharedFieldDecoration('نوع العملية', Icons.category_outlined, item.color),
                      items: [...kinds, '+ إضافة أخرى'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                      onChanged: (v) => setSheetState(() => kind = v ?? kind),
                    ),
                    if (kind == '+ إضافة أخرى') ...[
                      const SizedBox(height: 10),
                      TextFormField(controller: customKindCtrl, decoration: _sharedFieldDecoration('اكتب نوع العملية', Icons.edit_outlined, item.color)),
                    ],
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _sharedFieldDecoration('المبلغ', Icons.payments_outlined, item.color),
                      validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 10),
                    if (item.members.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: submittedBy,
                        decoration: _sharedFieldDecoration('مقدَّم من', Icons.person_outline_rounded, item.color),
                        items: item.members.map((m) => DropdownMenuItem(value: m.name, child: Text(m.name))).toList(),
                        onChanged: (v) => setSheetState(() => submittedBy = v),
                      ),
                    const SizedBox(height: 10),
                    TextFormField(controller: purposeCtrl, decoration: _sharedFieldDecoration('الغرض (اختياري)', Icons.notes_rounded, item.color)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: dateCtrl,
                      readOnly: true,
                      decoration: _sharedFieldDecoration('التاريخ', Icons.event_outlined, item.color),
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (pickerContext, child) => Directionality(textDirection: TextDirection.rtl, child: child!));
                        if (picked == null) return;
                        dateCtrl.text = '${picked.day}/${picked.month}/${picked.year}';
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: item.color, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          final resolvedKind = kind == '+ إضافة أخرى' ? customKindCtrl.text.trim() : kind;
                          if (resolvedKind.isEmpty) return;
                          final list = item.transactions
                            ..add(_SharedTransaction(kind: resolvedKind, amount: amountCtrl.text.trim(), submittedBy: submittedBy ?? '', purpose: purposeCtrl.text.trim(), date: dateCtrl.text.trim()));
                          final details = Map<String, String>.of(item.details)..[_sharedTransactionsDetailKey] = _encodeSharedTransactions(list);
                          Navigator.pop(sheetContext);
                          final ok = await _persist(details);
                          // الرسالة تصف ما حدث فعلًا فقط. كانت تَعِد بإرسال
                          // تنبيه لجميع الأعضاء أو للمسؤول بينما لا يوجد في
                          // التطبيق أي مسار إشعارات — وعد غير منفَّذ.
                          if (ok && mounted) {
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              const SnackBar(
                                content: Text('تم تسجيل العملية — بانتظار الموافقة'),
                              ),
                            );
                          }
                        },
                        child: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    amountCtrl.dispose();
    purposeCtrl.dispose();
    dateCtrl.dispose();
    customKindCtrl.dispose();
  }

  // -------------------------------------------------------------- السجل
  // نفس تصميم _HistoryDetailsCard في الشخصية تمامًا: صندوق موحّد واحد
  // برأس أيقونة+عنوان، وصفوف _TimelineEntry (أيقونة دائرية) بدل صناديق
  // منفصلة لكل عملية.
  Widget _buildHistoryTab() {
    final transactions = item.transactions.reversed.toList();
    final entries = <(String, String, IconData, Color)>[
      if (item.lastUpdate.isNotEmpty) ('تم إنشاء الالتزام', item.lastUpdate, Icons.add_circle_outline_rounded, item.color),
      for (final t in transactions)
        ('${t.kind} بقيمة ${t.amount} ${item.currency}', '${t.submittedBy.isEmpty ? '' : '${t.submittedBy} · '}${t.date}', t.kind == 'مصروف' ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded, t.kind == 'مصروف' ? const Color(0xFFB42318) : const Color(0xFF059669)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SharedUnifiedCard(
          title: 'سجل الالتزام',
          icon: Icons.schedule_rounded,
          color: item.color,
          children: [
            if (entries.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text('لا يوجد سجل بعد', style: TextStyle(color: Color(0xFF64748B)))))
            else
              for (final e in entries) _SharedTimelineEntry(title: e.$1, subtitle: e.$2, icon: e.$3, color: e.$4),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------- الأعضاء
  Widget _buildMembersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.members.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('لا يوجد أعضاء بعد', style: TextStyle(color: Color(0xFF64748B)))))
        else
          for (final m in item.members)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: item.color.withValues(alpha: 0.14), child: Icon(m.role == 'عضو' ? Icons.person_outline_rounded : Icons.shield_outlined, color: item.color, size: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text(m.role, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Builder(builder: (context) {
                      final balance = _memberBalance(m);
                      final color = balance > 0 ? const Color(0xFFB42318) : balance < 0 ? const Color(0xFF059669) : const Color(0xFF64748B);
                      final text = balance > 0 ? 'عليه ${balance.abs()}' : balance < 0 ? 'له ${balance.abs()}' : 'مسدَّد';
                      return Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color));
                    }),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _openAddMemberSheet() async {
    final nameCtrl = TextEditingController();
    var role = 'عضو';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('إضافة عضو', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  TextField(controller: nameCtrl, decoration: _sharedFieldDecoration('الاسم', Icons.person_outline_rounded, item.color)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: _sharedFieldDecoration('الدور', Icons.badge_outlined, item.color),
                    items: const ['عضو', 'مسؤول', 'نائب المسؤول'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setSheetState(() => role = v ?? role),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: item.color, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('أدخل اسم العضو أولاً')),
                          );
                          return;
                        }
                        // منع التكرار: اسم مكرر يضخّم عدد الأعضاء فيختل
                        // نصاب الموافقات وحصة كل عضو في التقسيم.
                        if (item.members.any((m) => m.name.trim() == name)) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('هذا العضو مضاف مسبقًا')),
                          );
                          return;
                        }
                        final updated = [...item.members, _SharedMember(name: name, role: role)];
                        final details = Map<String, String>.of(item.details)
                          ..[_sharedMembersDetailKey] = _encodeSharedMembers(updated);
                        // تُحدَّث أيضًا الحقول التي يقرأ منها نموذج التعديل،
                        // وإلا اختفى كل من يُضاف من هنا عند أول تعديل:
                        // الأعضاء العاديون في القائمة النصية، وصاحب دور
                        // المسؤول/النائب في حقله المخصّص.
                        details['الأعضاء / المشتركين'] = updated
                            .where((m) => m.role == 'عضو')
                            .map((m) => m.name)
                            .join('، ');
                        if (role == 'مسؤول') {
                          details[_sharedManagerKey] = name;
                        } else if (role == 'نائب المسؤول') {
                          details[_sharedDeputyKey] = name;
                        }
                        Navigator.pop(sheetContext);
                        await _persist(details);
                      },
                      child: const Text('إضافة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  // ----------------------------------------------- متابعة وتخطيط / مستندات / مواقع وأماكن
  Widget _buildSimpleListTab({required String sectionKey, required List<String> kinds, required IconData icon, required String emptyText}) {
    final entries = _parseSimpleEntries(item.details, sectionKey).reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(emptyText, style: const TextStyle(color: Color(0xFF64748B)))))
        else
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                      child: Icon(icon, size: 17, color: item.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text(
                            '${e.kind}${e.date.isNotEmpty ? ' · ${e.date}' : ''}${e.note.isNotEmpty ? ' · ${e.note}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _openSimpleEntrySheet({required String sectionKey, required List<String> kinds, String? initialKind}) async {
    var kind = initialKind ?? kinds.first;
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final customKindCtrl = TextEditingController();
    final now = DateTime.now();
    final dateCtrl = TextEditingController(text: '${now.day}/${now.month}/${now.year}');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sectionKey == _followUpDetailsKey ? 'إضافة عنصر متابعة' : sectionKey == _documentsDetailsKey ? 'إضافة مستند' : 'إضافة موقع', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: _sharedFieldDecoration('النوع', Icons.category_outlined, item.color),
                    items: [...kinds, if (sectionKey == _followUpDetailsKey) ..._actionKinds, '+ إضافة أخرى'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                    onChanged: (v) => setSheetState(() => kind = v ?? kind),
                  ),
                  if (kind == '+ إضافة أخرى') ...[
                    const SizedBox(height: 10),
                    TextField(controller: customKindCtrl, decoration: _sharedFieldDecoration('اكتب النوع', Icons.edit_outlined, item.color)),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: titleCtrl, decoration: _sharedFieldDecoration('العنوان', Icons.title_rounded, item.color)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dateCtrl,
                    readOnly: true,
                    decoration: _sharedFieldDecoration('التاريخ (اختياري)', Icons.event_outlined, item.color),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2000), lastDate: DateTime(2100), builder: (pickerContext, child) => Directionality(textDirection: TextDirection.rtl, child: child!));
                      if (picked == null) return;
                      dateCtrl.text = '${picked.day}/${picked.month}/${picked.year}';
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: noteCtrl, decoration: _sharedFieldDecoration('ملاحظة (اختياري)', Icons.notes_rounded, item.color)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: item.color, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final resolvedKind = kind == '+ إضافة أخرى' ? customKindCtrl.text.trim() : kind;
                        if (resolvedKind.isEmpty) return;
                        final list = _parseSimpleEntries(item.details, sectionKey)..add(_SimpleEntry(kind: resolvedKind, title: title, note: noteCtrl.text.trim(), date: dateCtrl.text.trim()));
                        final details = Map<String, String>.of(item.details)..[sectionKey] = _encodeSimpleEntries(list);
                        Navigator.pop(sheetContext);
                        await _persist(details);
                      },
                      child: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    titleCtrl.dispose();
    noteCtrl.dispose();
    customKindCtrl.dispose();
    dateCtrl.dispose();
  }
}
