import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/personal_entries_repository.dart';
import 'smart_calendar_screen.dart';
import '../widgets/management_dashboard_chrome.dart';
import '../widgets/shared/module_shared_widgets.dart';

const _addedAttachmentTypeKey = 'نوع المرفق الإضافي';
const _addedAttachmentNameKey = 'اسم المرفق الإضافي';

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

int _custodyTotalSpent(Map<String, String> details) {
  final transactions = _parseCustodyTransactions(details);
  final custodySpent = transactions.fold<int>(
    0,
    (sum, transaction) => sum + (int.tryParse(transaction['المبلغ'] ?? '') ?? 0),
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
    (sum, payment) => sum + (int.tryParse(payment['المبلغ'] ?? '') ?? 0),
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
                backgroundColor: Colors.black45,
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

enum _CommitmentMenuAction { edit, share, delete, archive }

class PersonalCommitmentsScreen extends StatefulWidget {
  final PersonalEntriesRepository? repository;

  const PersonalCommitmentsScreen({super.key, this.repository});

  @override
  State<PersonalCommitmentsScreen> createState() =>
      _PersonalCommitmentsScreenState();
}

class _PersonalCommitmentsScreenState extends State<PersonalCommitmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final PersonalEntriesRepository _repository;
  String _selectedEntryType = 'الكل';
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
  String? _advFilterSubType; // نوع إدخال محدد ضمن الفئة الرئيسية
  DateTime? _advFilterDateFrom;
  DateTime? _advFilterDateTo;
  String? _advFilterStatus; // المستحق بعد 7 أيام | مكتمل | متأخر | مؤرشف
  num? _advFilterAmountFrom;
  num? _advFilterAmountTo;
  String _advFilterAmountSort = 'بدون ترتيب'; // بدون ترتيب | الأعلى | الأقل
  String _advFilterDocumentName = '';
  String _advFilterPlaceName = '';

  bool get _hasActiveAdvancedFilters =>
      _advFilterSubType != null ||
      _advFilterDateFrom != null ||
      _advFilterDateTo != null ||
      _advFilterStatus != null ||
      _advFilterAmountFrom != null ||
      _advFilterAmountTo != null ||
      _advFilterAmountSort != 'بدون ترتيب' ||
      _advFilterDocumentName.isNotEmpty ||
      _advFilterPlaceName.isNotEmpty;

  void _clearAdvancedFilters() {
    setState(() {
      _advFilterSubType = null;
      _advFilterDateFrom = null;
      _advFilterDateTo = null;
      _advFilterStatus = null;
      _advFilterAmountFrom = null;
      _advFilterAmountTo = null;
      _advFilterAmountSort = 'بدون ترتيب';
      _advFilterDocumentName = '';
      _advFilterPlaceName = '';
    });
  }

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
      color: Color(0xFF0EA5E9),
      icon: Icons.account_balance_wallet,
      types: [
        _EntryType('مصروف', Icons.trending_down),
        _EntryType('إيراد', Icons.trending_up),
        _EntryType('تحويل مالي', Icons.swap_horiz),
        _EntryType('دين / قرض / سلفة', Icons.handshake),
        _EntryType('قسط', Icons.calendar_month),
        _EntryType('غرامة', Icons.gavel),
      ],
    ),
    _EntryCategory(
      title: 'مستند',
      subtitle: 'وثائق وملفات مهمة',
      color: Color(0xFFD97706),
      icon: Icons.description_outlined,
      types: [_EntryType('مستند', Icons.description_outlined)],
    ),
    _EntryCategory(
      title: 'تنظيم ومتابعة',
      subtitle: 'مهام ومواعيد وعادات',
      color: Color(0xFF7C3AED),
      icon: Icons.event_note_outlined,
      types: [
        _EntryType('مهمة', Icons.task_alt_outlined),
        _EntryType('موعد', Icons.event_outlined),
        _EntryType('عادة', Icons.repeat_rounded),
        _EntryType('ملاحظات', Icons.sticky_note_2_outlined),
        _EntryType('تجديد', Icons.autorenew_rounded),
        _EntryType('تفويض', Icons.assignment_ind_outlined),
        _EntryType('تذكير', Icons.notifications_active_outlined),
        _EntryType('متابعة', Icons.fact_check_outlined),
        _EntryType('تسجيل / تخطيط', Icons.edit_calendar_outlined),
      ],
    ),
    _EntryCategory(
      title: 'أدوية وبيانات وكلمات سر',
      subtitle: 'الأدوية والحسابات وكلمات المرور',
      color: Color(0xFFDC2626),
      icon: Icons.medical_information_outlined,
      types: [
        _EntryType('أدوية وبياناتها', Icons.medication_outlined),
        _EntryType('حسابات', Icons.password_rounded),
      ],
    ),
    _EntryCategory(
      title: 'نمط حياة',
      subtitle: 'مناسبات واشتراكات وهدايا',
      color: Color(0xFFDB2777),
      icon: Icons.celebration_outlined,
      types: [
        _EntryType('مناسبة', Icons.celebration_outlined),
        _EntryType('اشتراكات', Icons.autorenew),
        _EntryType('هدية', Icons.volunteer_activism_outlined),
        _EntryType('جمعية', Icons.groups_outlined),
      ],
    ),
    _EntryCategory(
      title: 'مواقع وأماكن',
      subtitle: 'أماكن ومواقع مهمة',
      color: Color(0xFF0F766E),
      icon: Icons.location_on_outlined,
      types: [_EntryType('مواقع وأماكن', Icons.location_on_outlined)],
    ),
    _EntryCategory(
      title: 'عهدة مالية',
      subtitle: 'مبالغ تحت مسؤولية شخص',
      color: Color(0xFFB45309),
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
    _loadEntries();
    _loadRecentSearches();
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

  _CommitmentItem _itemFromRecord(PersonalEntryRecord record) {
    final form = _financialEntryForms[record.entryType];
    final color = form?.color ?? const Color(0xFF475569);
    final createdAt = record.createdAt?.toLocal() ?? DateTime.now();
    final payments = _parseSubscriptionPayments(record.details)
        .map(
          (payment) => _SubscriptionPayment(
            payerName: payment['الدافع'] ?? '',
            amount: int.tryParse(payment['المبلغ'] ?? '') ?? 0,
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
      lastUpdate: '${createdAt.day}/${createdAt.month}/${createdAt.year}',
      icon: form?.icon ?? Icons.description_outlined,
      iconColor: color,
      iconBackground: color.withValues(alpha: 0.12),
      subscriptionMembers: record.entryType == 'اشتراكات'
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<_CommitmentItem> _filteredItems() {
    final q = _searchController.text.trim();
    var filtered = _items.where((item) {
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

    if (_advFilterAmountSort == 'الأعلى') {
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (_advFilterAmountSort == 'الأقل') {
      filtered.sort((a, b) => a.amount.compareTo(b.amount));
    } else if (_selectedSort == 'الأحدث أولاً') {
      filtered.sort((a, b) => _itemDate(b).compareTo(_itemDate(a)));
    } else {
      final selectedPriority = _sortStatusForLabel(_selectedSort);
      filtered.sort((a, b) {
        final aSelected = a.status == selectedPriority ? 0 : 1;
        final bSelected = b.status == selectedPriority ? 0 : 1;
        if (aSelected != bSelected) return aSelected.compareTo(bSelected);
        final pa = _statusPriority[a.status] ?? 99;
        final pb = _statusPriority[b.status] ?? 99;
        return pa.compareTo(pb);
      });
    }

    return filtered;
  }

  // يطبّق فلاتر شاشة "الفلتر المتقدم" (الفئة الفرعية، التاريخ، الحالة،
  // المبلغ، المستند، المكان) فوق فلتر الفئة الرئيسية وشريط البحث.
  List<_CommitmentItem> _applyAdvancedFilters(List<_CommitmentItem> items) {
    if (!_hasActiveAdvancedFilters) return items;
    return items.where((item) {
      if (_advFilterSubType != null) {
        // فئة "مستند" الفرعية مجموعات عرض (وثائق شخصية/ضمانات/مستندات
        // عامة) وليست أنواع إدخال منفصلة، فتُطابَق عبر حقل "نوع المستند"
        // داخل التفاصيل بدل مطابقة نوع الإدخال نفسه.
        final documentGroup = _documentSubtypeGroups[_advFilterSubType];
        if (documentGroup != null) {
          if (item.entryType != 'مستند' ||
              !documentGroup.contains(item.details['نوع المستند'] ?? '')) {
            return false;
          }
        } else if (item.entryType != _advFilterSubType) {
          return false;
        }
      }
      final itemDate = _parseDueDate(item.dueDate) ?? _itemDate(item);
      if (_advFilterDateFrom != null &&
          itemDate.isBefore(_advFilterDateFrom!)) {
        return false;
      }
      if (_advFilterDateTo != null &&
          itemDate.isAfter(_advFilterDateTo!)) {
        return false;
      }
      if (_advFilterStatus != null) {
        switch (_advFilterStatus) {
          case 'المستحق بعد 7 أيام':
            if (_effectiveStatus(item) != _statusDueSoon) return false;
            break;
          case 'مكتمل':
            if (item.status != _statusCompleted) return false;
            break;
          case 'متأخر':
            if (_effectiveStatus(item) != _statusOverdue) return false;
            break;
          case 'مؤرشف':
            if (item.status != 'مؤرشف') return false;
            break;
        }
      }
      if (_advFilterAmountFrom != null && item.amount < _advFilterAmountFrom!) {
        return false;
      }
      if (_advFilterAmountTo != null && item.amount > _advFilterAmountTo!) {
        return false;
      }
      if (_advFilterDocumentName.isNotEmpty) {
        final matchesDoc =
            item.title.contains(_advFilterDocumentName) ||
            (item.details['اسم المستند'] ?? '').contains(
              _advFilterDocumentName,
            );
        if (!matchesDoc) return false;
      }
      if (_advFilterPlaceName.isNotEmpty) {
        final matchesPlace =
            item.title.contains(_advFilterPlaceName) ||
            (item.details['اسم الموقع'] ?? '').contains(_advFilterPlaceName) ||
            (item.details['العنوان'] ?? '').contains(_advFilterPlaceName);
        if (!matchesPlace) return false;
      }
      return true;
    }).toList();
  }

  // مصدر الحقيقة الوحيد لتصنيف كل نوع إدخال ضمن إحدى الفئات السبع.
  // يُستخدم في: عرض/فلترة القائمة، عدّاد الفئات، وتحديد category عند الحفظ.
  static const Map<String, String> _entryTypeCategorySlug = {
    // مالية
    'مصروف': 'financial',
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
    'أدوية وبياناتها': 'medical_accounts',
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
    'organization': 'تنظيم ومتابعة',
    'medical_accounts': 'أدوية وبيانات وكلمات سر',
    'lifestyle': 'نمط حياة',
    'location': 'مواقع وأماكن',
    'custody': 'عهدة مالية',
  };

  bool _entryTypeMatches(String? entryType, String filter) {
    final slug = _entryTypeCategorySlug[entryType];
    return slug != null && _categorySlugFilterLabel[slug] == filter;
  }

  // سطر الملخص الوحيد الذي يظهر فيه رقم عدد الالتزامات (وليس على رقائق
  // الفئات نفسها)، حسب الفئة المختارة، أو الفئة الفرعية إن وُجدت.
  String _categorySummaryLabel() {
    if (_advFilterSubType != null) return _advFilterSubType!;
    return _selectedEntryType == 'الكل'
        ? 'جميع الالتزامات الشخصية'
        : _selectedEntryType;
  }

  // يجب أن يطابق هذا الرقم دائمًا عدد العناصر التي تظهر فعليًا في القائمة
  // أسفله؛ لذلك يُحسَب من نفس نتيجة _filteredItems() (تشمل فلتر البحث
  // والفلتر المتقدم)، لا من عدد الفئة الخام فقط — لتفادي ظهور رقم لا يطابق
  // القائمة الفعلية (مثال: كتابة نص بحث ثم نسيانه يجعل القائمة فارغة رغم
  // أن الرقم كان يعرض إجمالي الفئة).
  int _categorySummaryCount() => _filteredItems().length;

  List<_CommitmentItem> _itemsForSelectedEntryType() {
    if (_selectedEntryType == 'الكل') return List.of(_items);
    return _items
        .where((item) => _entryTypeMatches(item.entryType, _selectedEntryType))
        .toList();
  }

  DateTime _itemDate(_CommitmentItem item) {
    final parts = (item.lastUpdate.isEmpty ? item.dueDate : item.lastUpdate)
        .split('/');
    if (parts.length != 3) return DateTime(1970);
    final first = int.tryParse(parts[0]) ?? 1;
    final second = int.tryParse(parts[1]) ?? 1;
    final third = int.tryParse(parts[2]) ?? 1970;
    return first > 31
        ? DateTime(first, second, third)
        : DateTime(third, second, first);
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
  String _effectiveStatus(_CommitmentItem item) {
    if (item.status == _statusCompleted || item.status == 'مؤرشف') {
      return item.status;
    }
    final due = _parseDueDate(item.dueDate);
    if (due == null) return item.status;
    final days = due
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    if (days < 0) return _statusOverdue;
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
      item.status != _statusCompleted && item.status != 'مؤرشف';

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
    final items = _itemsForSelectedEntryType();

    const financialTypes = {
      'مصروف',
      'إيراد',
      'تحويل مالي',
      'دين / قرض / سلفة',
      'قسط',
      'غرامة',
    };

    bool isDueSoonOrOverdue(_CommitmentItem i) {
      final s = _effectiveStatus(i);
      return s == _statusOverdue || s == _statusDueSoon;
    }

    final overdueItems = items
        .where((i) => _isOpenItem(i) && _effectiveStatus(i) == _statusOverdue)
        .toList();
    final dueSoonItems = items
        .where((i) => _isOpenItem(i) && _effectiveStatus(i) == _statusDueSoon)
        .toList();
    final dueTodayItems = items
        .where((i) => _isOpenItem(i) && _isDueToday(i))
        .toList();
    final duePayments = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              financialTypes.contains(i.entryType) &&
              isDueSoonOrOverdue(i),
        )
        .toList();
    final installments = items
        .where((i) => _isOpenItem(i) && i.entryType == 'قسط')
        .toList();

    final pendingExpenses = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              const {'مصروف', 'قسط', 'غرامة'}.contains(i.entryType),
        )
        .toList();
    final pendingIncome = items
        .where((i) => _isOpenItem(i) && i.entryType == 'إيراد')
        .toList();
    final pendingTransfers = items
        .where((i) => _isOpenItem(i) && i.entryType == 'تحويل مالي')
        .toList();
    final pendingCustodySettlements = items
        .where(
          (i) =>
              i.entryType == 'عهدة مالية' &&
              !const {
                'تمت التسوية',
                'معادة',
              }.contains(i.details['حالة العهدة'] ?? '') &&
              _isOpenItem(i),
        )
        .toList();

    final renewingSubscriptions = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              i.entryType == 'اشتراكات' &&
              isDueSoonOrOverdue(i),
        )
        .toList();
    final expiringDocuments = items
        .where(
          (i) => _isOpenItem(i) && i.entryType == 'مستند' && isDueSoonOrOverdue(i),
        )
        .toList();

    final unfinishedTasks = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              const {'مهمة', 'عادة', 'ملاحظات'}.contains(i.entryType),
        )
        .toList();
    final pendingActions = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              const {'متابعة', 'تسجيل / تخطيط'}.contains(i.entryType),
        )
        .toList();
    // عناصر تحتاج مراجعة: من نفس مجموعة المهام والإجراءات لكنها تجاوزت
    // موعدها ولم تُنجز بعد، فهي تحتاج مراجعة عاجلة بخلاف "غير المكتملة"
    // التي تشمل كل ما هو مفتوح بغض النظر عن الموعد.
    final tasksNeedingReview = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              const {
                'مهمة',
                'عادة',
                'ملاحظات',
                'متابعة',
                'تسجيل / تخطيط',
              }.contains(i.entryType) &&
              _effectiveStatus(i) == _statusOverdue,
        )
        .toList();

    final upcomingAppointments = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              i.entryType == 'موعد' &&
              _effectiveStatus(i) != _statusOverdue,
        )
        .toList();
    final missedAppointments = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              i.entryType == 'موعد' &&
              _effectiveStatus(i) == _statusOverdue,
        )
        .toList();

    final dueDebts = items
        .where((i) => _isOpenItem(i) && i.entryType == 'دين / قرض / سلفة')
        .toList();
    final dueInstallments = items
        .where((i) => _isOpenItem(i) && i.entryType == 'قسط')
        .toList();
    final dueFines = items
        .where((i) => _isOpenItem(i) && i.entryType == 'غرامة')
        .toList();
    final openCustody = items
        .where((i) => i.entryType == 'عهدة مالية' && _isOpenItem(i))
        .toList();

    // "طلباتي": كل نوع إدخال يمثّل طلبًا ينتظر إجراء من شخص آخر (التفويض
    // حاليًا، وأي نوع طلب آخر يُضاف لاحقًا يكفي إضافته لهذه القائمة) — يظهر
    // في مركز المتابعة بدل أن يكون له مكان منفصل في الصفحة الرئيسية.
    final pendingRequests = items
        .where(
          (i) =>
              _isOpenItem(i) &&
              _requestEntryTypes.contains(i.entryType),
        )
        .toList();

    return [
      _FollowUpGroupData(
        title: 'الاستحقاقات',
        icon: Icons.event_busy_outlined,
        color: const Color(0xFFB42318),
        metrics: [
          _FollowUpSubMetric(
            label: 'متأخر',
            icon: Icons.error_outline_rounded,
            items: overdueItems,
          ),
          _FollowUpSubMetric(
            label: 'مستحق اليوم',
            icon: Icons.today_outlined,
            items: dueTodayItems,
          ),
          _FollowUpSubMetric(
            label: 'قريب الاستحقاق',
            icon: Icons.schedule_outlined,
            items: dueSoonItems,
          ),
          _FollowUpSubMetric(
            label: 'دفعات مستحقة',
            icon: Icons.payments_outlined,
            items: duePayments,
          ),
          _FollowUpSubMetric(
            label: 'أقساط مالية',
            icon: Icons.calendar_month_outlined,
            items: installments,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'العمليات المالية',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0EA5E9),
        metrics: [
          _FollowUpSubMetric(
            label: 'بانتظار الدفع',
            icon: Icons.arrow_upward_rounded,
            items: pendingExpenses,
          ),
          _FollowUpSubMetric(
            label: 'بانتظار التحصيل',
            icon: Icons.arrow_downward_rounded,
            items: pendingIncome,
          ),
          _FollowUpSubMetric(
            label: 'بانتظار الاسترداد',
            icon: Icons.sync_alt_rounded,
            items: pendingTransfers,
          ),
          _FollowUpSubMetric(
            label: 'تسويات معلقة',
            icon: Icons.inventory_2_outlined,
            items: pendingCustodySettlements,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'التجديدات والانتهاءات',
        icon: Icons.autorenew_rounded,
        color: const Color(0xFF7C3AED),
        metrics: [
          _FollowUpSubMetric(
            label: 'اشتراكات قريبة التجديد',
            icon: Icons.subscriptions_outlined,
            items: renewingSubscriptions,
          ),
          _FollowUpSubMetric(
            label: 'مستندات قريبة الانتهاء',
            icon: Icons.description_outlined,
            items: expiringDocuments,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'المهام والإجراءات',
        icon: Icons.task_alt_outlined,
        color: const Color(0xFF07835C),
        metrics: [
          _FollowUpSubMetric(
            label: 'مهام غير مكتملة',
            icon: Icons.checklist_rounded,
            items: unfinishedTasks,
          ),
          _FollowUpSubMetric(
            label: 'إجراءات معلقة',
            icon: Icons.pending_actions_outlined,
            items: pendingActions,
          ),
          _FollowUpSubMetric(
            label: 'عناصر تحتاج مراجعة',
            icon: Icons.fact_check_outlined,
            items: tasksNeedingReview,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'المواعيد',
        icon: Icons.event_outlined,
        color: const Color(0xFF2563EB),
        metrics: [
          _FollowUpSubMetric(
            label: 'مواعيد قادمة',
            icon: Icons.event_available_outlined,
            items: upcomingAppointments,
          ),
          _FollowUpSubMetric(
            label: 'مواعيد فائتة',
            icon: Icons.event_busy_outlined,
            items: missedAppointments,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'المتابعة الخاصة',
        icon: Icons.bookmark_outline_rounded,
        color: const Color(0xFFB45309),
        metrics: [
          _FollowUpSubMetric(
            label: 'ديون مستحقة',
            icon: Icons.handshake_outlined,
            items: dueDebts,
          ),
          _FollowUpSubMetric(
            label: 'قروض ودفعات قادمة',
            icon: Icons.calendar_month_outlined,
            items: dueInstallments,
          ),
          _FollowUpSubMetric(
            label: 'غرامات مستحقة',
            icon: Icons.gavel_outlined,
            items: dueFines,
          ),
          _FollowUpSubMetric(
            label: 'عهد مالية مفتوحة',
            icon: Icons.inventory_2_outlined,
            items: openCustody,
          ),
        ],
      ),
      _FollowUpGroupData(
        title: 'طلباتي',
        icon: Icons.forward_to_inbox_outlined,
        color: const Color(0xFF9333EA),
        metrics: [
          _FollowUpSubMetric(
            label: 'طلبات بانتظار الإجراء',
            icon: Icons.hourglass_top_rounded,
            items: pendingRequests,
          ),
        ],
      ),
    ];
  }

  // أنواع الإدخال التي تمثّل "طلبًا" ينتظر إجراء (وليس مجرد التزام عادي) —
  // التفويض حاليًا هو المثال الوحيد، وأي نوع طلب جديد يُضاف مستقبلًا يكفي
  // إدراجه هنا ليظهر تلقائيًا ضمن بند "طلباتي" في مركز المتابعة.
  static const Set<String> _requestEntryTypes = {'تفويض'};

  String _sortStatusForLabel(String label) => switch (label) {
    'متأخرة' => _statusOverdue,
    'قريبة الاستحقاق' => _statusDueSoon,
    'مكتملة' => _statusCompleted,
    'نشطة' => _statusActive,
    _ => '',
  };

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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
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
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'اختيار نوع الإضافة',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'اختر الفئة ثم نوع الإضافة المناسب',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
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
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Color(0xFF475569),
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
                        color: const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E6EA)),
                      ),
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.78,
                        children: _entryCategories
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
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
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: category.color,
                          borderRadius: BorderRadius.circular(14),
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              category.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${category.types.length} نوع إدخال',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
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
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: Color(0xFF475569),
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
                        color: const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E6EA)),
                      ),
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.86,
                        children: category.types
                            .map(
                              (type) => _EntryTypeCard(
                                type: type,
                                color: category.color,
                                onTap: () {
                                  Navigator.pop(context);
                                  final form = _financialEntryForms[type.label];
                                  if (form != null) {
                                    Future<void>.delayed(
                                      Duration.zero,
                                      () => _openFinancialEntryForm(form),
                                    );
                                  }
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

  Future<void> _openFinancialEntryForm(_FinancialEntryForm form) async {
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in form.fields) field.label: TextEditingController(),
    };
    final customSubcategoryController = TextEditingController();
    final customMainCategoryController = TextEditingController();
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
    final savedPeopleNames = isCustodyForm
        ? await _loadSavedPeopleNames()
        : const <String>[];
    if (!mounted) return;

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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
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
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(99),
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
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(form.icon, color: form.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إضافة ${form.label}',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      form.subtitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'إغلاق',
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
                                          'استخدام مكاني الحالي',
                                          Icons.my_location_rounded,
                                        ),
                                        (
                                          'link',
                                          'إضافة من الرابط',
                                          Icons.link_rounded,
                                        ),
                                        (
                                          'manual',
                                          'إدخال يدوي',
                                          Icons.edit_location_alt_outlined,
                                        ),
                                      ]
                                      .map(
                                        (mode) => ChoiceChip(
                                          label: Text(mode.$2),
                                          avatar: Icon(mode.$3, size: 16),
                                          selected: locationMode == mode.$1,
                                          onSelected: (_) => setModalState(
                                            () => locationMode = mode.$1,
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                            const SizedBox(height: 10),
                            if (locationMode == 'current')
                              InkWell(
                                onTap: () {
                                  setModalState(() {
                                    controllers['الموقع أو الرابط']!.text =
                                        'الموقع الحالي';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'تحديد الموقع تلقائيًا عبر GPS سيُضاف لاحقًا. تم وضع "الموقع الحالي" مؤقتًا — يمكنك تعديله يدويًا.',
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(13),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: form.color.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(13),
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
                                          'تحديد موقعي الحالي',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_left_rounded,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          if (form.label == 'مناسبة' ||
                              form.label == 'مواقع وأماكن') ...[
                            InkWell(
                              onTap: () async {
                                final image = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 82,
                                );
                                if (image != null) {
                                  setModalState(() => attachment = image);
                                }
                              },
                              borderRadius: BorderRadius.circular(13),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: form.color.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: attachment == null
                                        ? const Color(0xFFE2E8F0)
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
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_left_rounded,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          for (final field in form.fields.where(
                            (field) => field.isPrimary,
                          )) ...[
                            _buildDynamicField(
                              field,
                              controllers[field.label]!,
                              entryLabel: form.label,
                              controllers: controllers,
                              customMainCategoryController:
                                  customMainCategoryController,
                              customSubcategoryController:
                                  customSubcategoryController,
                              setModalState: setModalState,
                              savedPeopleNames: savedPeopleNames,
                            ),
                            const SizedBox(height: 12),
                          ],
                          InkWell(
                            onTap: () => setModalState(
                              () =>
                                  showAdditionalFields = !showAdditionalFields,
                            ),
                            borderRadius: BorderRadius.circular(13),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'الحقول الإضافية',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: showAdditionalFields ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (showAdditionalFields)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final field in form.fields.where(
                                    (field) => !field.isPrimary,
                                  )) ...[
                                    _buildDynamicField(
                                      field,
                                      controllers[field.label]!,
                                      entryLabel: form.label,
                                      controllers: controllers,
                                      customMainCategoryController:
                                          customMainCategoryController,
                                      customSubcategoryController:
                                          customSubcategoryController,
                                      setModalState: setModalState,
                                      savedPeopleNames: savedPeopleNames,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final image = await ImagePicker()
                                          .pickImage(
                                            source: ImageSource.gallery,
                                            imageQuality: 82,
                                          );
                                      if (image != null && context.mounted) {
                                        setModalState(() => attachment = image);
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
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 18),
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
                                      await _saveFinancialEntry(
                                        form,
                                        controllers,
                                        attachment,
                                        customMainCategory:
                                            customMainCategoryController.text,
                                        customSubcategory:
                                            customSubcategoryController.text,
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context);
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
                              isSaving ? 'جارٍ الحفظ...' : 'حفظ ${form.label}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: form.color,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
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
      for (final controller in controllers.values) {
        controller.dispose();
      }
      customMainCategoryController.dispose();
      customSubcategoryController.dispose();
    });
  }

  Widget _buildFormSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF2563EB)),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
      ],
    );
  }

  Widget _buildDynamicField(
    _FinancialField field,
    TextEditingController controller, {
    required String entryLabel,
    required Map<String, TextEditingController> controllers,
    required TextEditingController customMainCategoryController,
    required TextEditingController customSubcategoryController,
    required StateSetter setModalState,
    List<String> savedPeopleNames = const [],
  }) {
    // ربط العهدة المالية بشخص: بدل كتابة "اسم المستلم" يدويًا، يمكن
    // الاختيار من قائمة الأشخاص المحفوظين مسبقًا (نفس قائمة "المفوَّضين")
    // أو كتابة اسم جديد وسيُحفظ تلقائيًا بعد الحفظ الناجح.
    if (entryLabel == 'عهدة مالية' && field.label == 'اسم المستلم') {
      return TextFormField(
        controller: controller,
        decoration: _expenseInputDecoration(field.label, field.icon).copyWith(
          suffixIcon: savedPeopleNames.isEmpty
              ? null
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: PopupMenuButton<String>(
                    tooltip: 'اختر من الأسماء المحفوظة',
                    icon: const Icon(
                      Icons.arrow_drop_down_circle_outlined,
                      color: Color(0xFF0F766E),
                    ),
                    position: PopupMenuPosition.under,
                    color: Colors.white,
                    surfaceTintColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) =>
                        setModalState(() => controller.text = value),
                    itemBuilder: (context) => [
                      for (final name in savedPeopleNames)
                        PopupMenuItem<String>(
                          value: name,
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_outline_rounded,
                                  size: 18,
                                  color: Color(0xFF0F766E),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 13,
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
                  ),
                ),
        ),
        validator: (value) {
          if (field.required && (value == null || value.trim().isEmpty)) {
            return 'يرجى إدخال ${field.label}';
          }
          return null;
        },
      );
    }
    if (field.kind == _FinancialFieldKind.select) {
      final mainCategoryValue = controllers['التصنيف الرئيسي']?.text ?? '';
      final effectiveMainCategory = mainCategoryValue == '+ إضافة أخرى'
          ? customMainCategoryController.text.trim()
          : mainCategoryValue;
      final options = field.label == 'التصنيف الفرعي'
          ? _subcategoriesForEntry(
              entryLabel,
              effectiveMainCategory,
            )
          : [
              ...field.options,
              if (!field.options.contains('+ إضافة أخرى')) '+ إضافة أخرى',
            ];
      final value = options.contains(controller.text) ? controller.text : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            alignment: AlignmentDirectional.centerEnd,
            decoration: _expenseInputDecoration(field.label, field.icon),
            items: options
                .map(
                  (option) => DropdownMenuItem(
                    value: option,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(option, textAlign: TextAlign.right),
                  ),
                )
                .toList(),
            onChanged: (selected) {
              setModalState(() {
                controller.text = selected ?? '';
                if (field.label == 'التصنيف الرئيسي') {
                  controllers['التصنيف الفرعي']?.clear();
                  customMainCategoryController.clear();
                  customSubcategoryController.clear();
                } else if (selected != '+ إضافة أخرى') {
                  customSubcategoryController.clear();
                }
              });
            },
            validator: (selected) {
              if (field.required &&
                  (selected == null || selected.trim().isEmpty)) {
                return 'يرجى اختيار ${field.label}';
              }
              return null;
            },
          ),
          if (field.label == 'التصنيف الرئيسي' &&
              controller.text == '+ إضافة أخرى') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: customMainCategoryController,
              decoration: _expenseInputDecoration(
                'اسم التصنيف الرئيسي الجديد',
                Icons.add_rounded,
              ),
              validator: (text) => text == null || text.trim().isEmpty
                  ? 'يرجى إدخال اسم التصنيف الرئيسي'
                  : null,
            ),
          ],
          if (field.label == 'التصنيف الفرعي' &&
              controller.text == '+ إضافة أخرى') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: customSubcategoryController,
              decoration: _expenseInputDecoration(
                'اسم التصنيف الجديد',
                Icons.add_rounded,
              ),
              validator: (text) => text == null || text.trim().isEmpty
                  ? 'يرجى إدخال اسم التصنيف الجديد'
                  : null,
            ),
          ],
        ],
      );
    }
    return TextFormField(
      controller: controller,
      readOnly: field.kind == _FinancialFieldKind.date,
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
        field.label,
        field.icon,
        suffixText: field.kind == _FinancialFieldKind.number && field.isAmount
            ? 'درهم'
            : null,
      ),
      onTap: field.kind == _FinancialFieldKind.date
          ? () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 20),
                lastDate: DateTime(now.year + 20),
              );
              if (date != null) {
                controller.text = '${date.day}/${date.month}/${date.year}';
              }
            }
          : null,
      validator: (value) {
        if (field.required && (value == null || value.trim().isEmpty)) {
          return 'يرجى إدخال ${field.label}';
        }
        if (field.kind == _FinancialFieldKind.number &&
            value != null &&
            value.trim().isNotEmpty) {
          final number = double.tryParse(value.trim());
          if (number == null || number < 0) return 'أدخل رقماً صحيحاً';
        }
        return null;
      },
    );
  }

  Future<void> _saveFinancialEntry(
    _FinancialEntryForm form,
    Map<String, TextEditingController> controllers,
    XFile? attachment,
    {
    String? customMainCategory,
    String? customSubcategory,
  }
  ) async {
    String valueFor(bool Function(_FinancialField field) predicate) {
      for (final field in form.fields) {
        if (predicate(field)) return controllers[field.label]!.text.trim();
      }
      return '';
    }

    final titleValue = valueFor((field) => field.isTitle);
    final amountValue = valueFor((field) => field.isAmount);
    final dateValue = valueFor(
      (field) => field.kind == _FinancialFieldKind.date,
    );
    final details = <String, String>{
      for (final field in form.fields)
        if (controllers[field.label]!.text.trim().isNotEmpty)
          field.label: controllers[field.label]!.text.trim(),
    };

    final trimmedMain = (customMainCategory ?? '').trim();
    final trimmedSub = (customSubcategory ?? '').trim();
    if (details['التصنيف الرئيسي'] == '+ إضافة أخرى' && trimmedMain.isNotEmpty) {
      details['التصنيف الرئيسي'] = trimmedMain;
    }
    if (details['التصنيف الفرعي'] == '+ إضافة أخرى' && trimmedSub.isNotEmpty) {
      details['التصنيف الفرعي'] = trimmedSub;
    }

    final fallbackTitle = details['التصنيف الفرعي']?.trim().isNotEmpty == true
        ? details['التصنيف الفرعي']!.trim()
        : details['التصنيف الرئيسي']?.trim().isNotEmpty == true
        ? details['التصنيف الرئيسي']!.trim()
        : form.label;

    final saved = await _repository.create(
      PersonalEntryRecord(
        category: _categoryFor(form.label),
        entryType: form.label,
        title: titleValue.isEmpty ? fallbackTitle : titleValue,
        amount: double.tryParse(amountValue)?.round() ?? 0,
        dueDate: dateValue,
        status: _statusActive,
        details: details,
      ),
      attachment: attachment,
    );
    if (form.label == 'عهدة مالية') {
      final recipientName = valueFor((field) => field.label == 'اسم المستلم');
      if (recipientName.isNotEmpty) {
        await _savePersonName(recipientName);
      }
    }
    if (!mounted) return;
    setState(() {
      _items.insert(0, _itemFromRecord(saved));
      _selectedEntryType = 'الكل';
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تم حفظ ${form.label} بنجاح')));
  }

  String _categoryFor(String entryType) {
    return _entryTypeCategorySlug[entryType] ?? 'organization';
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

  InputDecoration _expenseInputDecoration(
    String label,
    IconData icon, {
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF0EA5E9)),
      suffixText: suffixText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 1.5),
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
    }
    setState(() {});
  }

  void _addEntryLike(_CommitmentItem item) {
    final form = item.entryType == null
        ? null
        : _financialEntryForms[item.entryType];
    if (form == null) {
      _openNewEntrySheet();
      return;
    }
    _openFinancialEntryForm(form);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _buildScreenBody(),
      ),
      floatingActionButton: AddFab(
        screenId: 'personal_commitments',
        onPressed: _openNewEntrySheet,
        label: 'إضافة التزام',
        backgroundColor: const Color(0xFF3B82F6),
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
      return CustomScrollView(
        slivers: [
          ManagementDashboardHeader(
            title: 'الالتزامات الشخصية',
            subtitle: 'إدارة ومتابعة كل التزاماتك في مكان واحد',
            icon: Icons.account_balance_wallet_rounded,
            colors: const [Color(0xFF1D4ED8), Color(0xFF2563EB)],
            onSmartCalendarTap: _openSmartCalendar,
          ),
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
          // ملاحظة مهمة: تم اختبار تثبيت صف "الفئات" في أعلى الشاشة (سلوك
          // sticky) عبر SliverPersistentHeader بارتفاع ثابت، لكنه تسبّب في
          // شاشة بيضاء فارغة (نفس فئة العطل التي حدثت سابقًا مع نفس الآلية).
          // لأن هذا الملف عانى من هذه المشكلة أكثر من مرة، تم التراجع عن
          // التثبيت والعودة إلى المحتوى العادي الآمن (SliverToBoxAdapter)
          // الذي يأخذ حجمه الطبيعي دائمًا ولا يفترض ارتفاعًا مسبقًا — إلى
          // حين تطوير آلية تثبيت أكثر أمانًا (بقياس الارتفاع الفعلي وقت
          // التشغيل بدل افتراضه).
          SliverToBoxAdapter(
            child: ColoredBox(
              color: const Color(0xFFF5F8FC),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFollowUpCenter(),
                    const SizedBox(height: 14),
                    _buildCategoriesBlock(),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildListHeader(filtered.length),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  _buildEmptyState()
                else
                  ...filtered.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CommitmentCard(
                        item: item,
                        onTap: () => _openDetails(item),
                        onEdit: () => _openDetails(item, openEdit: true),
                        onAdd: () => _addEntryLike(item),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
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
              color: Color(0xFFB42318),
            ),
            const SizedBox(height: 12),
            const Text(
              'حدث خطأ غير متوقع أثناء عرض الشاشة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const ValueKey('personal-commitments-retry'),
              onPressed: () => setState(() {}),
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D0F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isRecent ? Icons.history_rounded : Icons.search_rounded,
              size: 16,
              color: const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
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
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
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
                key: const ValueKey('personal-search-field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                textDirection: TextDirection.rtl,
                onChanged: (_) => setState(() {}),
                onSubmitted: _saveRecentSearch,
                decoration: InputDecoration(
                  // أيقونة العدسة ثابتة على يمين الحقل (بداية القراءة بالعربية)،
                  // وزر المسح (X) يظهر في الطرف الآخر فقط عند وجود نص بحث،
                  // حتى لا يبقى نص بحث قديم منسيًا يُخفي التزامات موجودة فعلًا
                  // دون أن يلاحظ المستخدم السبب.
                  hintText: 'بحث',
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF64748B),
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey('personal-search-clear'),
                          tooltip: 'مسح البحث',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 9),
            InkWell(
              key: const ValueKey('personal-filter-button'),
              onTap: _openAdvancedFilterSheet,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF1677FF),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Color(0x293B82F6), blurRadius: 12, offset: Offset(0, 5))],
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

  static const List<String> _advFilterQuickRanges = [
    'آخر 3 أيام',
    'آخر أسبوعين',
    'آخر شهر',
    'آخر شهرين',
    'آخر 3 شهور',
  ];

  static const List<String> _advFilterStatusOptions = [
    'المستحق بعد 7 أيام',
    'مكتمل',
    'متأخر',
    'مؤرشف',
  ];

  String _formatAdvDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year}';
  }

  // يفتح شاشة "الفلتر المتقدم" الكاملة: الفئة الرئيسية/الفرعية، التاريخ
  // (مع اختصارات سريعة)، الحالة، نطاق المبلغ (مع فرز أعلى/أقل)، والبحث
  // باسم المستند أو المكان — حسب ملف المتطلبات.
  void _openAdvancedFilterSheet() {
    // نسخ محلية (مسودة) من الفلاتر الحالية، تُطبَّق فقط عند الضغط على
    // "تطبيق الفلتر" حتى لا تتغيّر القائمة أثناء التعديل داخل الشاشة.
    var draftMainCategory = _selectedEntryType;
    var draftSubType = _advFilterSubType;
    var draftDateFrom = _advFilterDateFrom;
    var draftDateTo = _advFilterDateTo;
    var draftStatus = _advFilterStatus;
    var draftAmountSort = _advFilterAmountSort;
    final amountFromCtrl = TextEditingController(
      text: _advFilterAmountFrom?.toStringAsFixed(0) ?? '',
    );
    final amountToCtrl = TextEditingController(
      text: _advFilterAmountTo?.toStringAsFixed(0) ?? '',
    );
    final documentCtrl = TextEditingController(text: _advFilterDocumentName);
    final placeCtrl = TextEditingController(text: _advFilterPlaceName);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            // فئة "مستند" ليس لها أنواع إدخال فرعية فعلية (كلها بنفس نوع
            // الإدخال 'مستند')؛ تصنيفها الفرعي هنا هو نفس المجموعات الثلاث
            // (وثائق شخصية / ضمانات / مستندات عامة) المستخدمة في رقاقة
            // الفئات وفي مطابقة الفلترة، حتى تبقى الخيارات متطابقة بينهما.
            final subTypeOptions = draftMainCategory == 'الكل'
                ? const <String>[]
                : draftMainCategory == 'مستند'
                ? _documentSubtypeGroups.keys.toList()
                : _entryCategories
                      .firstWhere((c) => c.title == draftMainCategory)
                      .types
                      .map((t) => t.label)
                      .toList();
            if (draftSubType != null &&
                !subTypeOptions.contains(draftSubType)) {
              draftSubType = null;
            }

            Future<void> pickDate({required bool isFrom}) async {
              final picked = await showDatePicker(
                context: sheetContext,
                initialDate:
                    (isFrom ? draftDateFrom : draftDateTo) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              setSheetState(() {
                if (isFrom) {
                  draftDateFrom = picked;
                } else {
                  draftDateTo = picked;
                }
              });
            }

            void applyQuickRange(String label) {
              final now = DateUtils.dateOnly(DateTime.now());
              final days = switch (label) {
                'آخر 3 أيام' => 3,
                'آخر أسبوعين' => 14,
                'آخر شهر' => 30,
                'آخر شهرين' => 60,
                'آخر 3 شهور' => 90,
                _ => 0,
              };
              setSheetState(() {
                draftDateFrom = now.subtract(Duration(days: days));
                draftDateTo = now;
              });
            }

            return FractionallySizedBox(
              heightFactor: 0.92,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'التزامات شخصية',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draftMainCategory = 'الكل';
                                draftSubType = null;
                                draftDateFrom = null;
                                draftDateTo = null;
                                draftStatus = null;
                                draftAmountSort = 'بدون ترتيب';
                                amountFromCtrl.clear();
                                amountToCtrl.clear();
                                documentCtrl.clear();
                                placeCtrl.clear();
                              });
                              _clearAdvancedFilters();
                              setState(() => _selectedEntryType = 'الكل');
                            },
                            child: const Text('مسح الكل'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        children: [
                          _advFilterSectionLabel('الفئة الرئيسية'),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: _personalDashboardFilters.map((filter) {
                              final selected = draftMainCategory == filter.$1;
                              return ChoiceChip(
                                label: Text(filter.$1),
                                selected: selected,
                                onSelected: (_) => setSheetState(
                                  () => draftMainCategory = filter.$1,
                                ),
                                selectedColor: filter.$3.withValues(
                                  alpha: 0.16,
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? filter.$3
                                      : const Color(0xFF475569),
                                ),
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: selected
                                      ? filter.$3
                                      : const Color(0xFFE2E8F0),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('الفئة الفرعية'),
                          DropdownButtonFormField<String>(
                            value: draftSubType,
                            decoration: _advFilterFieldDecoration(
                              subTypeOptions.isEmpty
                                  ? 'اختر الفئة الرئيسية أولاً'
                                  : 'كل الأنواع ضمن الفئة',
                            ),
                            items: subTypeOptions
                                .map(
                                  (label) => DropdownMenuItem(
                                    value: label,
                                    child: Text(label),
                                  ),
                                )
                                .toList(),
                            onChanged: subTypeOptions.isEmpty
                                ? null
                                : (value) => setSheetState(
                                    () => draftSubType = value,
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('التاريخ'),
                          Row(
                            children: [
                              Expanded(
                                child: _advFilterDateField(
                                  label: 'من',
                                  value: _formatAdvDate(draftDateFrom),
                                  onTap: () => pickDate(isFrom: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _advFilterDateField(
                                  label: 'إلى',
                                  value: _formatAdvDate(draftDateTo),
                                  onTap: () => pickDate(isFrom: false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          PopupMenuButton<String>(
                            onSelected: applyQuickRange,
                            itemBuilder: (context) => _advFilterQuickRanges
                                .map(
                                  (label) => PopupMenuItem<String>(
                                    value: label,
                                    child: Text(label),
                                  ),
                                )
                                .toList(),
                            child: _advFilterMenuField(
                              'اختصار سريع للتاريخ',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('الحالة'),
                          DropdownButtonFormField<String?>(
                            value: draftStatus,
                            decoration: _advFilterFieldDecoration(
                              'كل الحالات',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('كل الحالات'),
                              ),
                              ..._advFilterStatusOptions.map(
                                (label) => DropdownMenuItem<String?>(
                                  value: label,
                                  child: Text(label),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setSheetState(() => draftStatus = value),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('المبلغ'),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: amountFromCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _advFilterFieldDecoration('من'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: amountToCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _advFilterFieldDecoration('إلى'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          PopupMenuButton<String>(
                            onSelected: (value) => setSheetState(
                              () => draftAmountSort = switch (value) {
                                'أعلى مبلغاً' => 'الأعلى',
                                'أقل مبلغاً' => 'الأقل',
                                _ => 'بدون ترتيب',
                              },
                            ),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'بدون ترتيب',
                                child: Text('بدون ترتيب'),
                              ),
                              PopupMenuItem(
                                value: 'أعلى مبلغاً',
                                child: Text('أعلى مبلغاً'),
                              ),
                              PopupMenuItem(
                                value: 'أقل مبلغاً',
                                child: Text('أقل مبلغاً'),
                              ),
                            ],
                            child: _advFilterMenuField(
                              switch (draftAmountSort) {
                                'الأعلى' => 'أعلى مبلغاً',
                                'الأقل' => 'أقل مبلغاً',
                                _ => 'ترتيب حسب المبلغ',
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('المستند'),
                          TextField(
                            controller: documentCtrl,
                            decoration: _advFilterFieldDecoration(
                              'اكتب اسم المستند',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _advFilterSectionLabel('المكان'),
                          TextField(
                            controller: placeCtrl,
                            decoration: _advFilterFieldDecoration(
                              'اكتب اسم المكان',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1677FF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            final amountFrom = num.tryParse(
                              amountFromCtrl.text.trim(),
                            );
                            final amountTo = num.tryParse(
                              amountToCtrl.text.trim(),
                            );
                            setState(() {
                              _selectedEntryType = draftMainCategory;
                              _advFilterSubType = draftSubType;
                              _advFilterDateFrom = draftDateFrom;
                              _advFilterDateTo = draftDateTo;
                              _advFilterStatus = draftStatus;
                              _advFilterAmountFrom = amountFrom;
                              _advFilterAmountTo = amountTo;
                              _advFilterAmountSort = draftAmountSort;
                              _advFilterDocumentName = documentCtrl.text
                                  .trim();
                              _advFilterPlaceName = placeCtrl.text.trim();
                            });
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text(
                            'تطبيق الفلتر',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      amountFromCtrl.dispose();
      amountToCtrl.dispose();
      documentCtrl.dispose();
      placeCtrl.dispose();
    });
  }

  Widget _advFilterSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  InputDecoration _advFilterFieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.4),
      ),
    );
  }

  // حقل "زر فيه سهم" — مطابق للشكل الموصوف في ملف المتطلبات لاختصار
  // التاريخ وترتيب المبلغ: مستطيل بحدود يعرض القيمة الحالية مع سهم للأسفل،
  // يُستخدم كـ child لـ PopupMenuButton فيفتح قائمة عند الضغط عليه.
  Widget _advFilterMenuField(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _advFilterDateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '$label: $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _personalDashboardFilters = [
    ('الكل', Icons.grid_view_rounded, Color(0xFF1677FF)),
    ('مالية', Icons.account_balance_wallet_rounded, Color(0xFF0EA5E9)),
    ('مستند', Icons.description_outlined, Color(0xFFD97706)),
    ('تنظيم ومتابعة', Icons.checklist_rounded, Color(0xFF7C3AED)),
    (
      'أدوية وبيانات وكلمات سر',
      Icons.medical_information_outlined,
      Color(0xFFDC2626),
    ),
    ('نمط حياة', Icons.celebration_outlined, Color(0xFFDB2777)),
    ('مواقع وأماكن', Icons.location_on_outlined, Color(0xFF0F766E)),
    ('عهدة مالية', Icons.inventory_2_outlined, Color(0xFFB45309)),
  ];

  Widget _buildCategoriesBlock() {
    final selectedFilter = _personalDashboardFilters.firstWhere(
      (filter) => filter.$1 == _selectedEntryType,
      orElse: () => _personalDashboardFilters.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'الفئات',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        // صف الرقائق الأفقي كما كان بالتصميم السابق. أي فئة فيها أكثر من
        // نوع فرعي واحد (مثل "مالية") تحمل سهمًا صغيرًا (▾) يفتح قائمة
        // منسدلة بنمط "Posts ▾" (قائمة رأسية بعلامة ✓ أمام النوع المختار)
        // بدل توسيع صف رقائق أسفل الفئات بالكامل.
        SizedBox(
          height: 42,
          child: ListView.separated(
            key: const ValueKey('personal-category-tabs'),
            scrollDirection: Axis.horizontal,
            reverse: false,
            itemCount: _personalDashboardFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = _personalDashboardFilters[index];
              final selected = _selectedEntryType == filter.$1;
              final categorySubtypes = filter.$1 == 'الكل'
                  ? const <_EntryType>[]
                  : filter.$1 == 'مستند'
                  ? [
                      for (final label in _documentSubtypeGroups.keys)
                        _EntryType(
                          label,
                          _documentSubtypeGroupIcons[label] ??
                              Icons.description_outlined,
                        ),
                    ]
                  : _entryCategories
                        .firstWhere(
                          (c) => c.title == filter.$1,
                          orElse: () => _entryCategories.first,
                        )
                        .types;
              return _PersonalCategoryTab(
                key: ValueKey('personal-category-tab-${filter.$1}'),
                label: filter.$1,
                icon: filter.$2,
                color: filter.$3,
                selected: selected,
                onTap: () => setState(() {
                  _selectedEntryType = filter.$1;
                  _advFilterSubType = null;
                }),
                subtypes: categorySubtypes,
                selectedSubtype: selected ? _advFilterSubType : null,
                onSubtypeSelected: (value) => setState(() {
                  _selectedEntryType = filter.$1;
                  _advFilterSubType = value;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_categorySummaryCount()} ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: selectedFilter.$3,
                  ),
                ),
                TextSpan(
                  text: _categorySummaryLabel(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
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
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.forward_to_inbox_outlined,
                color: Color(0xFF7C3AED),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? 'لديك طلب واحد بانتظار الإجراء'
                      : 'لديك $count طلبات بانتظار الإجراء',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5B21B6),
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
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowUpCenter() {
    // البطاقة المصغّرة تعرض 3 مؤشرات سريعة مبنية من نفس بيانات مركز
    // المتابعة الكامل (6 مجموعات)، حتى تبقى الأرقام متطابقة بين البطاقة
    // المصغّرة والشاشة الكاملة التي يفتحها زر السهم.
    final groups = _buildFollowUpGroups();
    final duesTotal = groups[0].total; // الاستحقاقات
    final tasksTotal = groups[3].total + groups[4].total; // المهام + المواعيد
    final renewalsTotal = groups[2].total; // التجديدات والانتهاءات
    final metrics = [
      (
        'مستحقات',
        duesTotal,
        Icons.payments_outlined,
        const Color(0xFF2563EB),
      ),
      (
        'مهام',
        tasksTotal,
        Icons.task_alt_rounded,
        const Color(0xFF07835C),
      ),
      (
        'تجديدات',
        renewalsTotal,
        Icons.autorenew_rounded,
        const Color(0xFFB56A09),
      ),
    ];

    return Container(
      key: const ValueKey('personal-follow-up-center'),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        // لمسة جمالية بسيطة: تدرّج لوني ناعم بدل اللون المسطّح، وظل أعمق
        // قليلًا وحدود أنعم — بدون أي تغيير في الهيكل أو المحتوى.
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFDF9EC), Color(0xFFF6EDD6)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DCB5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A8A6D1F),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEFE2B8), Color(0xFFE0CE97)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F8A6D1F),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.dashboard_customize_outlined,
                  color: Color(0xFF8A6D1F),
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مركز المتابعة',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF8A6D1F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedEntryType == 'الكل'
                          ? 'الأهم والأقرب من جميع الالتزامات'
                          : 'متابعة $_selectedEntryType',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A6D1F),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const ValueKey('personal-follow-up-more'),
                onTap: _openFollowUpSheet,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'المزيد',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A6D1F),
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                        color: Color(0xFF8A6D1F),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(right: 2, bottom: 6),
            child: Text(
              'اختر ما تريد متابعته بسرعة',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8A6D1F),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: metrics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final metric = metrics[index];
                return SizedBox(
                  width: 112,
                  child: _FollowUpMetric(
                    label: metric.$1,
                    count: metric.$2,
                    icon: metric.$3,
                    selected: _selectedFollowUpMetric == index,
                    onTap: () =>
                        setState(() => _selectedFollowUpMetric = index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // يفتح مركز المتابعة المفصّل: 6 مجموعات قابلة للطي مطابقة لملف
  // المتطلبات، كل مجموعة تعرض عناصرها الفرعية مع عدّاد، ويمكن فتح أي
  // عنصر فرعي لعرض الالتزامات المطابقة له والانتقال إلى تفاصيلها.
  void _openFollowUpSheet() {
    final groups = _buildFollowUpGroups();
    final grandTotal = groups.fold<int>(0, (sum, g) => sum + g.total);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.dashboard_customize_outlined,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _selectedEntryType == 'الكل'
                              ? 'مركز المتابعة الشامل'
                              : 'متابعة $_selectedEntryType',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (grandTotal > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$grandTotal',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: grandTotal == 0
                      ? const Center(
                          child: Text(
                            'لا توجد عناصر تحتاج إلى متابعة حالياً',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        )
                      // شبكة من عمودين (بطاقتين جنب بعض) بدل عمود واحد
                      // تتكدس فيه كل البطاقات فوق بعض، حسب الطلب.
                      : ListView.separated(
                          key: const ValueKey('personal-follow-up-groups'),
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                          itemCount: (groups.length / 2).ceil(),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, rowIndex) {
                            final firstIndex = rowIndex * 2;
                            final secondIndex = firstIndex + 1;
                            Widget cardFor(_FollowUpGroupData group) {
                              return _FollowUpGroupCard(
                                group: group,
                                onItemTap: (item) {
                                  Navigator.of(sheetContext).pop();
                                  Future<void>.delayed(
                                    Duration.zero,
                                    () => _openDetails(item),
                                  );
                                },
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: cardFor(groups[firstIndex])),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: secondIndex < groups.length
                                      ? cardFor(groups[secondIndex])
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<(String, IconData)> _sortOptions = [
    ('الأحدث أولاً', Icons.schedule_rounded),
    ('متأخرة', Icons.error_outline_rounded),
    ('قريبة الاستحقاق', Icons.hourglass_bottom_rounded),
    ('مكتملة', Icons.check_circle_outline_rounded),
    ('نشطة', Icons.play_circle_outline_rounded),
  ];

  // زر ترتيب القائمة، بنفس شكل زر قائمة الفئات المنسدلة (حدود واضحة +
  // أيقونة + سهم)، وقائمته مُغلَّفة صراحةً باتجاه RTL حتى لا تظهر عناصرها
  // بترتيب واتجاه معكوس (كانت تعتمد على الاتجاه الافتراضي للقائمة المنبثقة
  // وهو LTR بشكل مستقل عن اتجاه الشاشة، فيظهر شكلها غير احترافي).
  Widget _buildSortDropdownButton() {
    return PopupMenuButton<String>(
      key: const ValueKey('personal-sort-button'),
      tooltip: 'ترتيب الالتزامات',
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) => setState(() => _selectedSort = value),
      itemBuilder: (context) => _sortOptions.map((option) {
        final selected = _selectedSort == option.$1;
        return PopupMenuItem<String>(
          value: option.$1,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                Icon(
                  option.$2,
                  size: 17,
                  color: selected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.$1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: Color(0xFF2563EB),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFD6E6FE)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedSort,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF2563EB),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListHeader(int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 36),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1677FF),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _selectedEntryType == 'الكل'
                    ? 'جميع الالتزامات'
                    : _selectedEntryType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 32,
              color: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'لا توجد التزامات مطابقة',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'جرّب تغيير الفلتر أو مسح البحث',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
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

  const _PersonalCommitmentDetailsScreen({
    required this.item,
    required this.repository,
    this.openEditOnStart = false,
  });

  @override
  State<_PersonalCommitmentDetailsScreen> createState() =>
      _PersonalCommitmentDetailsScreenState();
}

class _PersonalCommitmentDetailsScreenState
    extends State<_PersonalCommitmentDetailsScreen> {
  int _detailSectionIndex = 0;
  bool _showAllDetails = false;

  static const _detailSections = [
    (label: 'الملخص', icon: Icons.bar_chart_rounded),
    (label: 'السجل', icon: Icons.schedule_rounded),
    (label: 'المستندات', icon: Icons.folder_outlined),
    (label: 'المتابعة', icon: Icons.notifications_none_rounded),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.openEditOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openEditForm();
      });
    }
  }

  Color get _pageColor =>
      Color.lerp(widget.item.iconColor, const Color(0xFF073B67), 0.38)!;

  String _detailValue(List<String> labels, {String fallback = 'غير محدد'}) {
    for (final label in labels) {
      final value = widget.item.details[label]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  // زر "+ إضافة" في شاشة التفاصيل: يعرض 3 مستطيلات بجانب بعض (دفعة، مستند،
  // صورة)، وتحتهم قسم "تنظيم ومتابعة" القابل للفتح ويحوي 3+3 مستطيلات
  // أخرى (مهمة، موعد، عادة، ملاحظات، تجديد، تفويض) — حسب ملف المتطلبات.
  Future<void> _openAddAttachmentMenu() async {
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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'إضافة إلى الالتزام',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اختر ما تريد إضافته لهذا الالتزام',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // زر "دفعة" مخصص لتسجيل دفعة تُخصم من رصيد متبقٍ
                        // (اشتراك، قسط، دين...). لا يظهر للعهدة المالية لأن
                        // لها زرها المخصص "تسجيل صرف من العهدة" بالأسفل —
                        // إظهار الاثنين معًا يسجّل المبلغ في سجل منفصل لا
                        // يظهر ضمن "المصروف/المتبقي" الخاص بالعهدة.
                        if (widget.item.entryType != 'عهدة مالية')
                          Expanded(
                            child: _QuickAddTile(
                              key: const ValueKey('add-payment-option'),
                              label: 'دفعة',
                              icon: Icons.payments_outlined,
                              onTap: () => Navigator.pop(sheetContext, 'دفعة'),
                            ),
                          ),
                        if (widget.item.entryType != 'عهدة مالية')
                          const SizedBox(width: 8),
                        Expanded(
                          child: _QuickAddTile(
                            key: const ValueKey('add-document-option'),
                            label: 'مستند',
                            icon: Icons.description_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'مستند'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickAddTile(
                            key: const ValueKey('add-photo-option'),
                            label: 'صورة',
                            icon: Icons.photo_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'صورة'),
                          ),
                        ),
                      ],
                    ),
                    // زر خاص بالعهد المالية فقط: يظهر عند فتح "+ إضافة" من
                    // داخل التزام من نوع "عهدة مالية"، ويسمح بتسجيل مبلغ
                    // مصروف من العهدة (يُخصم من رصيدها المتبقي تلقائيًا).
                    if (widget.item.entryType == 'عهدة مالية') ...[
                      const SizedBox(height: 8),
                      _QuickAddTile(
                        key: const ValueKey('add-custody-spend-option'),
                        label: 'تسجيل صرف من العهدة',
                        icon: Icons.remove_circle_outline_rounded,
                        onTap: () => Navigator.pop(sheetContext, 'صرف من عهدة'),
                      ),
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
                              color: Color(0xFF7C3AED),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'تنظيم ومتابعة',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF172033),
                                ),
                              ),
                            ),
                            Icon(
                              orgExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF7C3AED),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (orgExpanded) ...[
                      const SizedBox(height: 6),
                      _buildOrgRow(sheetContext, [
                        ('مهمة', Icons.task_alt_outlined),
                        ('موعد', Icons.event_outlined),
                        ('عادة', Icons.repeat_rounded),
                      ]),
                      const SizedBox(height: 8),
                      _buildOrgRow(sheetContext, [
                        ('ملاحظات', Icons.sticky_note_2_outlined),
                        ('تجديد', Icons.autorenew_rounded),
                        ('تفويض', Icons.assignment_ind_outlined),
                      ]),
                      const SizedBox(height: 8),
                      _buildOrgRow(sheetContext, [
                        ('تذكير', Icons.notifications_active_outlined),
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

    if (action == 'دفعة') {
      _openSubscriptionPaymentForm();
      return;
    }
    if (action == 'صرف من عهدة') {
      _openCustodySpendForm();
      return;
    }
    if (action != 'مستند' && action != 'صورة') {
      _openQuickOrganizationForm(action);
      return;
    }

    final attachmentType = action;
    final attachment = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (attachment == null || !mounted) return;
    await _saveAddedAttachment(attachmentType, attachment);
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

  Future<void> _handleMenuAction(_CommitmentMenuAction action) async {
    switch (action) {
      case _CommitmentMenuAction.edit:
        await _openEditForm();
      case _CommitmentMenuAction.share:
        await _shareCommitment();
      case _CommitmentMenuAction.delete:
        await _deleteCommitment();
      case _CommitmentMenuAction.archive:
        await _archiveCommitment();
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
          'المبلغ: ${item.totalAmount} درهم',
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
        item.statusColor = const Color(0xFF64748B);
        item.lastUpdate = 'الآن';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت أرشفة الالتزام')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر أرشفة الالتزام. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _deleteCommitment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الالتزام'),
          content: Text(
            'هل تريد حذف «${widget.item.title}» نهائيًا؟ لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.item.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الالتزام غير المحفوظ.')),
      );
      return;
    }
    try {
      await widget.repository.delete(id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الالتزام. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _saveAddedAttachment(String type, XFile attachment) async {
    final item = widget.item;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
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
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        item.details = updated.details;
        item.attachmentPath = updated.attachmentUrl;
        item.lastUpdate = 'الآن';
        _detailSectionIndex = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة $type إلى الالتزام بنجاح')),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع المرفق. حاول مرة أخرى.')),
      );
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
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
  Future<void> _openCustodySpendForm() async {
    final item = widget.item;
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final purposeController = TextEditingController();
    final now = DateTime.now();
    final dateController = TextEditingController(
      text: '${now.day}/${now.month}/${now.year}',
    );
    var isSaving = false;
    const color = Color(0xFF0F766E);
    final currentRemaining = item.totalAmount - _custodyTotalSpent(item.details);

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
              final transactions = _parseCustodyTransactions(item.details)
                ..add({
                  'المبلغ': amountController.text.trim(),
                  'الغرض': purposeController.text.trim(),
                  'التاريخ': dateController.text.trim(),
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
                );
                if (!mounted) return;
                Navigator.pop(sheetContext);
                setState(() {
                  item.details = updated.details;
                  item.status = newStatus;
                  item.statusColor = _personalStatusColor(newStatus);
                  item.lastUpdate = 'الآن';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newRemaining <= 0
                          ? 'تم تسجيل الصرف — تمت تسوية العهدة بالكامل'
                          : 'تم تسجيل الصرف، الرصيد المتبقي: $newRemaining درهم',
                    ),
                  ),
                );
              } catch (_) {
                setModalState(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تعذر الحفظ. حاول مرة أخرى.'),
                  ),
                );
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
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
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(99),
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
                                  borderRadius: BorderRadius.circular(13),
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
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      'الرصيد المتبقي حاليًا: $currentRemaining درهم من أصل ${item.totalAmount} درهم',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
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
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'أدخل مبلغ الصرف';
                              }
                              final number = double.tryParse(value.trim());
                              if (number == null || number <= 0) {
                                return 'أدخل رقمًا صحيحًا أكبر من صفر';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: purposeController,
                            decoration: _custodyFieldDecoration(
                              'الغرض من الصرف',
                              Icons.flag_outlined,
                              color,
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'أدخل الغرض من الصرف'
                                : null,
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
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isSaving ? null : save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
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

  // إنشاء سريع لأحد أنواع "تنظيم ومتابعة" (مهمة، موعد، عادة، ملاحظات، تجديد،
  // تفويض) من داخل شاشة تفاصيل الالتزام، مبني على نفس تعريف الحقول في
  // _financialEntryForms لكن بنموذج مبسّط بدون الحقول الإضافية القابلة للطي.
  Future<void> _openQuickOrganizationForm(String entryType) async {
    final form = _financialEntryForms[entryType];
    if (form == null) return;
    final formKey = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in form.fields) field.label: TextEditingController(),
    };
    var isSaving = false;
    final isDelegateForm = entryType == 'تفويض';
    final delegateNames = isDelegateForm
        ? await _loadSavedPeopleNames()
        : const <String>[];
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
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
              try {
                await widget.repository.create(
                  PersonalEntryRecord(
                    category:
                        _PersonalCommitmentsScreenState
                            ._entryTypeCategorySlug[entryType] ??
                        'organization',
                    entryType: entryType,
                    title: titleValue.isEmpty ? entryType : titleValue,
                    amount: 0,
                    dueDate: dateValue,
                    status: 'نشطة',
                    details: details,
                  ),
                );
                if (isDelegateForm && titleValue.isNotEmpty) {
                  await _savePersonName(titleValue);
                }
                if (!mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم إنشاء $entryType بنجاح')),
                );
              } catch (_) {
                setModalState(() => isSaving = false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تعذر الحفظ. حاول مرة أخرى.'),
                  ),
                );
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
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
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(99),
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
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(form.icon, color: form.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إضافة ${form.label}',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      form.subtitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
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
                          for (final field in form.fields) ...[
                            if (isDelegateForm && field.label == 'اسم المفوَّض')
                              _buildDelegateNameField(
                                field,
                                controllers[field.label]!,
                                color: form.color,
                                delegateNames: delegateNames,
                                setModalState: setModalState,
                              )
                            else
                              _buildQuickAddField(
                                field,
                                controllers[field.label]!,
                                color: form.color,
                                setModalState: setModalState,
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
                                  borderRadius: BorderRadius.circular(13),
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
  }) {
    final decoration = InputDecoration(
      labelText: field.label + (field.required ? ' *' : ''),
      prefixIcon: Icon(field.icon, color: color, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
        return DropdownButtonFormField<String>(
          value: controller.text.isEmpty ? null : controller.text,
          isExpanded: true,
          decoration: decoration,
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setModalState(() => controller.text = v ?? ''),
          validator: validator,
        );
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
      labelText: field.label + (field.required ? ' *' : ''),
      hintText: 'اكتب اسمًا جديدًا أو اختر من القائمة المحفوظة',
      prefixIcon: Icon(field.icon, color: color, size: 20),
      suffixIcon: delegateNames.isEmpty
          ? null
          : Directionality(
              textDirection: TextDirection.rtl,
              child: PopupMenuButton<String>(
                tooltip: 'اختر من الأسماء المحفوظة',
                icon: Icon(Icons.arrow_drop_down_circle_outlined, color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) =>
                    setModalState(() => controller.text = value),
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        'أسماء محفوظة مسبقًا',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                  for (final name in delegateNames)
                    PopupMenuItem<String>(
                      value: name,
                      child: Directionality(
                        textDirection: TextDirection.rtl,
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
                                  color: Color(0xFF334155),
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
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1.4),
      ),
    );
    return TextFormField(
      controller: controller,
      decoration: decoration,
      validator: (value) {
        if (!field.required) return null;
        if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب';
        return null;
      },
    );
  }

  void _openSubscriptionPaymentForm() {
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
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
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(99),
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
                                    0xFF0EA5E9,
                                  ).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.add_card_rounded,
                                  color: Color(0xFF0EA5E9),
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
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      'المتبقي ${widget.item.amount} درهم',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
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
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'أدخل اسم الشخص الذي دفع'
                                : null,
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
                              suffixText: 'درهم',
                            ),
                            validator: (value) {
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
                            },
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
                            validator: (value) => value == null || value.isEmpty
                                ? 'حدد تاريخ الدفع'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () async {
                              final image = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 82,
                              );
                              if (image != null) {
                                setModalState(() => invoiceImage = image);
                              }
                            },
                            borderRadius: BorderRadius.circular(13),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: invoiceImage == null
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFF0EA5E9),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    invoiceImage == null
                                        ? Icons.add_photo_alternate_outlined
                                        : Icons.check_circle_rounded,
                                    color: const Color(0xFF0EA5E9),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      invoiceImage?.name ??
                                          'إضافة صورة من الفاتورة',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_left_rounded,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ],
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
                                      final newPayment = {
                                        'الدافع': payerController.text.trim(),
                                        'المبلغ': '$paymentAmount',
                                        'التاريخ': dateController.text.trim(),
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
                                              'تم حفظ الدفعة وخصمها بنجاح',
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
                                backgroundColor: const Color(0xFF0EA5E9),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
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
      prefixIcon: Icon(icon, color: const Color(0xFF0EA5E9)),
      suffixText: suffixText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 1.5),
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
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
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(99),
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
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'حدّث البيانات ثم احفظ التغييرات',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
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
                      TextFormField(
                        controller: titleController,
                        decoration: _editInputDecoration(
                          'اسم الالتزام',
                          Icons.title_rounded,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'يرجى إدخال اسم الالتزام'
                            : null,
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
                          suffixText: 'درهم',
                        ),
                        validator: (value) {
                          final amount = double.tryParse(value?.trim() ?? '');
                          return amount == null || amount < 0
                              ? 'أدخل مبلغاً صحيحاً'
                              : null;
                        },
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
                            const [
                                  'نشطة',
                                  'قريبة الاستحقاق',
                                  'متأخرة',
                                  'مكتملة',
                                ]
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
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E293B),
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
                                        if (item.details[_addedAttachmentTypeKey] !=
                                            null)
                                          _addedAttachmentTypeKey: item
                                              .details[_addedAttachmentTypeKey]!,
                                        if (item.details[_addedAttachmentNameKey] !=
                                            null)
                                          _addedAttachmentNameKey: item
                                              .details[_addedAttachmentNameKey]!,
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
                                      content: Text('تم تحديث الالتزام بنجاح'),
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
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
      prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
      suffixText: suffixText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
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
      backgroundColor: const Color(0xFFF5F7FA),
      // نفس شكل زر "+ إضافة" في صفحة الالتزامات الشخصية (مستطيل مدوّر
      // بأيقونة ونص)، لكن بلون مختلف وبدون خاصية السحب/التحول من مكانه —
      // زر ثابت في مكانه دائمًا، حسب الطلب.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-commitment-attachment'),
        tooltip: 'إضافة إلى الالتزام',
        onPressed: _openAddAttachmentMenu,
        backgroundColor: const Color(0xFFE5B22E),
        foregroundColor: const Color(0xFF3D2E08),
        elevation: 7,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text(
          'تفاصيل ${item.entryType ?? 'الالتزام'}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF172033),
          ),
        ),
        leading: IconButton(
          tooltip: 'رجوع',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          key: const ValueKey('compact-personal-details'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          children: [
            // مستطيل واحد موحّد (بدل مستطيلين منفصلين): صف العنوان/الحالة
            // متبوعًا بخط رفيع احترافي ثم صف بيانات الفئة (المبلغ/التاريخ/
            // جهة الصرف مثلًا)، بنفس لون النص في الجزأين.
            Container(
              key: const ValueKey('compact-details-header'),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE1E7EF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
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
                    color: const Color(0xFFEEF2F7),
                  ),
                  _CategoryHighlightBar(item: item, color: color),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _InlineDetailsTabs(
              sections: _detailSections,
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
      ),
    );
  }

  Widget _buildSelectedSection(_CommitmentItem item, Color color) {
    return switch (_detailSectionIndex) {
      1 => _HistoryDetailsCard(item: item, color: color),
      2 => _DocumentsDetailsCard(item: item, color: color),
      3 => _FollowupDetailsCard(item: item, color: color),
      _ => _SummaryDetailsCard(
        item: item,
        color: color,
        expanded: _showAllDetails,
        isSensitive: _isSensitiveDetail,
        onToggleExpanded: () =>
            setState(() => _showAllDetails = !_showAllDetails),
      ),
    };
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.entryType ?? 'التزام شخصي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: item.statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.status,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: item.statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_CommitmentMenuAction>(
                key: const ValueKey('compact-details-edit'),
                tooltip: 'إجراءات الالتزام',
                onSelected: onAction,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 23,
                  color: Color(0xFF475569),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _CommitmentMenuAction.edit,
                    child: _CommitmentMenuItem(
                      label: 'تعديل',
                      icon: Icons.edit_outlined,
                    ),
                  ),
                  PopupMenuItem(
                    value: _CommitmentMenuAction.share,
                    child: _CommitmentMenuItem(
                      label: 'مشاركة',
                      icon: Icons.share_outlined,
                    ),
                  ),
                  PopupMenuItem(
                    value: _CommitmentMenuAction.delete,
                    child: _CommitmentMenuItem(
                      label: 'حذف',
                      icon: Icons.delete_outline_rounded,
                      color: Color(0xFFB42318),
                    ),
                  ),
                  PopupMenuItem(
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
    this.color = const Color(0xFF334155),
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _neutral, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _neutral,
              ),
            ),
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
    return Container(
      key: const ValueKey('inline-details-tabs'),
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Row(
        children: List.generate(sections.length, (index) {
          final section = sections[index];
          final selected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              key: ValueKey('inline-details-tab-$index'),
              onTap: () => onSelected(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    section.icon,
                    size: 18,
                    color: selected ? color : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: selected ? color : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: selected ? 28 : 0,
                    height: 2,
                    color: selected ? color : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// شريط تمييز أعلى شاشة التفاصيل، يعرض 2-3 حقول مختلفة حسب فئة الالتزام،
// مطابقًا لجدول "المستطيل الأول" في ملف المتطلبات (مالية: المبلغ/التاريخ/
// جهة الصرف، مستند: تاريخ الانتهاء/اسم المستند/الملاحظات... إلخ).
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
          ('المبلغ الكلي', '${item.totalAmount} درهم', Icons.payments_outlined),
          ('المدفوع', '${item.paidAmount} درهم', Icons.trending_down_rounded),
          (
            'المتبقي',
            '${item.amount} درهم',
            Icons.account_balance_wallet_outlined,
          ),
        ];
      }
      return [
        ('قيمة الاشتراك', '${item.totalAmount} درهم', Icons.payments_outlined),
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
            ('المبلغ الكلي', '${item.totalAmount} درهم', Icons.payments_outlined),
            ('المدفوع', '${item.paidAmount} درهم', Icons.trending_down_rounded),
            (
              'المتبقي',
              '${item.amount} درهم',
              Icons.account_balance_wallet_outlined,
            ),
          ];
        }
        return [
          ('المبلغ', '${item.totalAmount} درهم', Icons.payments_outlined),
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
          ('قيمة العهدة', '${item.totalAmount} درهم', Icons.inventory_2_outlined),
          ('المصروف', '$spent درهم', Icons.trending_down_rounded),
          ('المتبقي', '$remaining درهم', Icons.account_balance_wallet_outlined),
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
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF172033),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
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
          (entry) => !const {
            _addedAttachmentTypeKey,
            _addedAttachmentNameKey,
            _custodyTransactionsDetailKey,
            _subscriptionPaymentsDetailKey,
          }.contains(entry.key),
        )
        .toList(growable: false);
    final visibleEntries = expanded
        ? detailEntries
        : detailEntries.take(4).toList(growable: false);

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
        if (detailEntries.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: onToggleExpanded,
              iconAlignment: IconAlignment.end,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(expanded ? 'عرض أقل' : 'عرض كل التفاصيل'),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                foregroundColor: color,
                backgroundColor: color.withValues(alpha: 0.07),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
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
        ...item.payments.map(
          (payment) => _TimelineEntry(
            title: 'دفعة بقيمة ${payment.amount} درهم',
            subtitle: payment.invoiceImagePath == null
                ? '${payment.payerName} • ${payment.date}'
                : '${payment.payerName} • ${payment.date} • اضغط لعرض الفاتورة',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF059669),
            onTap: payment.invoiceImagePath == null
                ? null
                : () => _openInvoiceImage(context, payment.invoiceImagePath!),
          ),
        ),
        // سجل صرفيات العهدة المالية: كل عملية صرف مسجَّلة من زر "+ إضافة"،
        // مع الرصيد المتبقي في الأعلى — الأحدث أولًا.
        if (isCustody) ...[
          _TimelineEntry(
            title: 'الرصيد المتبقي من العهدة',
            subtitle:
                '$custodyRemaining درهم من أصل ${item.totalAmount} درهم',
            icon: Icons.account_balance_wallet_outlined,
            color: color,
          ),
          ...custodyTransactions.reversed.map(
            (transaction) => _TimelineEntry(
              title: 'صرف ${transaction['المبلغ'] ?? '0'} درهم',
              subtitle:
                  '${(transaction['الغرض'] ?? '').isNotEmpty ? transaction['الغرض'] : 'بدون سبب محدد'} • ${transaction['التاريخ'] ?? ''}',
              icon: Icons.remove_circle_outline_rounded,
              color: const Color(0xFFDC2626),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
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
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      hasAttachment
                          ? attachmentName?.isNotEmpty == true
                                ? attachmentName!
                                : 'تم حفظ المرفق مع هذا الالتزام'
                          : 'استخدم زر + لإضافة فاتورة أو مستند',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? const Color(0xFF1E293B),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
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
      borderRadius: BorderRadius.circular(10),
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
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$amount درهم',
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

class _PersonalCategoryTab extends StatefulWidget {
  const _PersonalCategoryTab({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.subtypes = const [],
    this.selectedSubtype,
    this.onSubtypeSelected,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  // فئات فرعية اختيارية: إن وُجد أكثر من نوع فرعي واحد يظهر سهم صغير (▾)
  // يفتح قائمة منسدلة بنمط "Posts ▾" (قائمة رأسية بعلامة ✓ أمام النوع
  // المختار حاليًا)، بدل توسيع صف كامل من الرقائق أسفل الفئات.
  final List<_EntryType> subtypes;
  final String? selectedSubtype;
  final ValueChanged<String?>? onSubtypeSelected;

  @override
  State<_PersonalCategoryTab> createState() => _PersonalCategoryTabState();
}

class _PersonalCategoryTabState extends State<_PersonalCategoryTab> {
  // نستخدم OverlayEntry + CompositedTransformTarget/Follower بدل
  // PopupMenuButton: قائمة PopupMenuButton تعتمد على خوارزمية Flutter
  // الداخلية لتفادي خروج القائمة عن حدود الشاشة، وهذه الخوارزمية تُزيح
  // القائمة أفقيًا كلما اقترب الزر من حافة الشاشة (وهذا ما كان يحصل مع
  // "المالية" فتظهر القائمة بعيدة عن السهم بدل أن تكون تحته مباشرة، بينما
  // "تنظيم ومتابعة" أبعد عن الحافة فلا يحتاج إزاحة). بهذا الأسلوب اليدوي
  // تبقى القائمة دائمًا مرتبطة بموضع السهم مباشرة تحته، بلا إزاحة.
  final LayerLink _link = LayerLink();
  OverlayEntry? _menuEntry;
  bool _menuOpen = false;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
    _menuOpen = false;
  }

  void _toggleMenu() {
    if (_menuOpen) {
      setState(_closeMenu);
      return;
    }
    final overlay = Overlay.of(context);
    _menuEntry = OverlayEntry(builder: (context) => _buildMenuOverlay());
    overlay.insert(_menuEntry!);
    setState(() => _menuOpen = true);
  }

  void _selectSubtype(String? value) {
    widget.onSubtypeSelected?.call(value);
    if (mounted) setState(_closeMenu);
  }

  Widget _buildMenuOverlay() {
    final entries = <MapEntry<String?, _EntryType?>>[
      const MapEntry(null, null),
      ...widget.subtypes.map((t) => MapEntry<String?, _EntryType?>(t.label, t)),
    ];
    return Positioned.fill(
      child: Stack(
        children: [
          // طبقة شفافة لإغلاق القائمة عند الضغط خارجها.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (mounted) setState(_closeMenu);
              },
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 6),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 200,
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      // لون فاتح بدل الأبيض الصرف حتى تتضح حدود القائمة.
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x260F172A),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFE7ECF2),
                              ),
                            _subtypeMenuTile(
                              value: entries[i].key,
                              label: entries[i].value?.label ?? 'الكل',
                              icon: entries[i].value?.icon ?? Icons.apps_rounded,
                              selectedNow: widget.selectedSubtype == entries[i].key,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtypeMenuTile({
    required String? value,
    required String label,
    required IconData icon,
    required bool selectedNow,
  }) {
    return InkWell(
      onTap: () => _selectSubtype(value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: selectedNow ? widget.color.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: selectedNow ? widget.color : const Color(0xFF64748B),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selectedNow ? FontWeight.w900 : FontWeight.w600,
                  color: selectedNow ? widget.color : const Color(0xFF334155),
                ),
              ),
            ),
            if (selectedNow)
              Icon(Icons.check_rounded, size: 17, color: widget.color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSubtypes = widget.subtypes.length > 1;
    final fg = widget.selected ? Colors.white : widget.color;
    return CompositedTransformTarget(
      link: _link,
      child: Material(
        color: widget.selected ? widget.color : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: widget.selected ? widget.color : const Color(0xFFDCE5EF),
            width: widget.selected ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsets.only(
                  right: 11,
                  left: hasSubtypes ? 2 : 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: widget.selected
                            ? Colors.white
                            : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasSubtypes)
              InkWell(
                onTap: _toggleMenu,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: Icon(
                    _menuOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: fg,
                  ),
                ),
              )
            else
              const SizedBox(width: 11),
          ],
        ),
      ),
    );
  }
}

class _FollowUpMetric extends StatelessWidget {
  const _FollowUpMetric({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const followUpColor = Color(0xFF8A6D1F);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(7, 3, 7, 0),
        decoration: const BoxDecoration(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: followUpColor, size: 17),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: followUpColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: followUpColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowUpListItem extends StatelessWidget {
  const _FollowUpListItem({required this.item, required this.onTap});

  final _CommitmentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.iconBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.entryType ?? 'التزام'} · ${item.dueDate.isEmpty ? 'بلا تاريخ' : item.dueDate}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _CommitmentStatusBadge(
                status: item.status,
                color: item.statusColor,
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// عنصر فرعي واحد داخل مجموعة مركز المتابعة (مثال: "متأخر"، "مستحق اليوم")
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

// بطاقة قابلة للطي تعرض مجموعة من مركز المتابعة مع عناصرها الفرعية،
// وتفتح كل عنصر فرعي عند الضغط عليه لعرض العناصر المطابقة له.
class _FollowUpGroupCard extends StatefulWidget {
  const _FollowUpGroupCard({required this.group, required this.onItemTap});

  final _FollowUpGroupData group;
  final ValueChanged<_CommitmentItem> onItemTap;

  @override
  State<_FollowUpGroupCard> createState() => _FollowUpGroupCardState();
}

class _FollowUpGroupCardState extends State<_FollowUpGroupCard> {
  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final hasItems = group.total > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(13, 12, 13, hasItems ? 4 : 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(group.icon, color: group.color, size: 18),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${group.total}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: group.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasItems)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
              child: Column(
                children: [
                  for (var i = 0; i < group.metrics.length; i++)
                    _buildSubMetricRow(group.metrics[i], i),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // بدل توسيع عنصر داخل البطاقة نفسها (كان يسبب اختلاف ارتفاع البطاقتين
  // المتجاورتين في شبكة العمودين ومساحات فارغة غير متناسقة)، يفتح الضغط
  // على أي بند فرعي صفحة منبثقة صغيرة ومرتّبة تعرض عناصره فقط، فتبقى
  // البطاقات في الشبكة بارتفاع ثابت ومرتّب دائمًا.
  Widget _buildSubMetricRow(_FollowUpSubMetric metric, int index) {
    final enabled = metric.count > 0;
    return InkWell(
      onTap: enabled ? () => _openSubMetricSheet(metric) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              metric.icon,
              size: 16,
              color: enabled
                  ? const Color(0xFF475569)
                  : const Color(0xFFCBD5E1),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? const Color(0xFF334155)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
            Text(
              '${metric.count}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: enabled
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // الصفحة المنبثقة الصغيرة الخاصة ببند فرعي واحد: عنوان واضح + عدّاد،
  // وقائمة مرتّبة بمسافات ثابتة بين عناصرها (بلا مساحات فارغة عشوائية)،
  // بارتفاع محدود حتى لا تُغطّي الشاشة كاملة.
  void _openSubMetricSheet(_FollowUpSubMetric metric) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.62,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(metric.icon, size: 18, color: widget.group.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metric.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.group.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${metric.count}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: widget.group.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    shrinkWrap: true,
                    itemCount: metric.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = metric.items[i];
                      return _FollowUpListItem(
                        item: item,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onItemTap(item);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          fontSize: 9.5,
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
  final VoidCallback onEdit;
  final VoidCallback onAdd;

  const _CommitmentCard({
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 94,
          padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 4, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFE6ECF3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: item.iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 23),
              ),
              const SizedBox(width: 10),
              // نفس ترتيب صندوق الالتزام المشترك تمامًا: اسم الالتزام أعلى
              // اليمين (مع نقطة حالة صغيرة) ونوعه تحته، ثم المبلغ أعلى
              // اليسار والتاريخ تحته، ثم سهم تصفّح عند الحافة القائدة.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(color: item.statusColor, shape: BoxShape.circle),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.entryType ?? 'التزام شخصي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: item.iconColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.paidAmount > 0
                          ? 'المتبقي : ${item.amount.toStringAsFixed(2)} درهم'
                          : 'المبلغ : ${item.totalAmount.toStringAsFixed(2)} درهم',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'التاريخ : ${item.dueDate.isEmpty ? '—' : item.dueDate}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 22),
              PopupMenuButton<String>(
                tooltip: 'خيارات الالتزام',
                padding: const EdgeInsets.all(8),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'add') {
                    onAdd();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 19),
                          SizedBox(width: 8),
                          Text('تعديل'),
                        ],
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add',
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 19),
                          SizedBox(width: 8),
                          Text('إضافة'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String text;
  final IconData icon;

  const _MetricTile({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6C9B8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        textDirection: TextDirection.rtl,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B3621),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 12, color: const Color(0xFF6B4C2A)),
        ],
      ),
    );
  }
}

class _EntryType {
  final String label;
  final IconData icon;

  const _EntryType(this.label, this.icon);
}

enum _FinancialFieldKind { text, number, date, multiline, secret, select }

class _FinancialField {
  final String label;
  final IconData icon;
  final _FinancialFieldKind kind;
  final bool required;
  final bool isPrimary;
  final bool isTitle;
  final bool isAmount;
  final List<String> options;

  const _FinancialField(
    this.label,
    this.icon, {
    this.kind = _FinancialFieldKind.text,
    this.required = false,
    this.isPrimary = false,
    this.isTitle = false,
    this.isAmount = false,
    this.options = const [],
  });
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
);
const _notesField = _FinancialField(
  'ملاحظات',
  Icons.notes_rounded,
  kind: _FinancialFieldKind.multiline,
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
  'سيارة': [
    'وقود',
    'مواقف ورسوم طرق',
    'صيانة وإصلاح',
    'قطع غيار',
    'إكسسوارات سيارات',
    'غسيل وتلميع',
    'مخالفات',
  ],
  // الفئات التالية بلا تصنيف فرعي محدد في المصدر (اختر "أخرى" أو أضف تصنيفاً مخصصاً)
  'إيجار': [],
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

List<String> _expenseSubcategories(String mainCategory) => [
  ...?_expenseSubcategoriesByMainCategory[mainCategory],
  'أخرى',
  '+ إضافة أخرى',
];

List<String> _incomeSubcategories(String mainCategory) => [
  ...?_incomeSubcategoriesByMainCategory[mainCategory],
  'أخرى',
  '+ إضافة أخرى',
];

List<String> _fineSubcategories(String mainCategory) => [
  ...?_fineSubcategoriesByMainCategory[mainCategory],
  'أخرى',
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
  'مصروف': _FinancialEntryForm(
    label: 'مصروف',
    subtitle: 'تسجيل المصروف وتصنيفه وتفاصيل الدفع',
    icon: Icons.trending_down,
    color: Color(0xFFDC2626),
    fields: [
      _primaryAmount,
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        isTitle: true,
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
          'سيارة',
          'غرامات (عام)',
          'رسوم بنكية',
          'سداد قروض',
          'سداد أقساط',
          'خدمات حكومية',
          'مصروفات أخرى',
        ],
      ),
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
      ),
      _primaryDate,
      _FinancialField('جهة الصرف', Icons.storefront_outlined),
      _FinancialField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _FinancialFieldKind.select,
        options: [
          'نقداً',
          'بطاقة بنكية',
          'تحويل بنكي',
          'محفظة إلكترونية',
          'أخرى',
        ],
      ),
      _FinancialField('الموقع', Icons.location_on_outlined),
      _notesField,
    ],
  ),
  'إيراد': _FinancialEntryForm(
    label: 'إيراد',
    subtitle: 'دخل مالي مع تصنيف رئيسي وفرعي',
    icon: Icons.trending_up,
    color: Color(0xFF059669),
    fields: [
      _primaryAmount,
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        isTitle: true,
        options: ['الراتب/معاش', 'تعويض واسترجاع مصروف', 'كاش باك'],
      ),
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
      ),
      _primaryDate,
      _FinancialField('جهة الصرف', Icons.storefront_outlined),
      _FinancialField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _FinancialFieldKind.select,
        options: [
          'نقداً',
          'بطاقة بنكية',
          'تحويل بنكي',
          'محفظة إلكترونية',
          'أخرى',
        ],
      ),
      _FinancialField('الموقع', Icons.location_on_outlined),
      _notesField,
    ],
  ),
  'تحويل مالي': _FinancialEntryForm(
    label: 'تحويل مالي',
    subtitle: 'تحويل بين الحسابات أو الأشخاص',
    icon: Icons.swap_horiz,
    color: Color(0xFF2563EB),
    fields: [
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _primaryAmount,
      _primaryDate,
      _FinancialField('تحويل من', Icons.logout_rounded, isPrimary: true),
      _FinancialField('إلى', Icons.login_rounded, isPrimary: true),
      _FinancialField(
        'تفعيل عملية متكررة',
        Icons.autorenew_rounded,
        kind: _FinancialFieldKind.select,
        options: ['نعم', 'لا'],
      ),
      _FinancialField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _FinancialFieldKind.select,
        options: ['تحويل بنكي', 'محفظة إلكترونية', 'نقداً', 'أخرى'],
      ),
      _notesField,
    ],
  ),
  'دين / قرض / سلفة': _FinancialEntryForm(
    label: 'دين / قرض / سلفة',
    subtitle: 'تسجيل الدين وحالة السداد',
    icon: Icons.handshake_outlined,
    color: Color(0xFF7C3AED),
    fields: [
      _FinancialField('اسم الجهة', Icons.business_outlined, required: true, isPrimary: true, isTitle: true),
      _FinancialField('العملة', Icons.currency_exchange_rounded, isPrimary: true),
      _FinancialField('رقم الهاتف', Icons.phone_outlined, isPrimary: true),
      _FinancialField('البريد الإلكتروني', Icons.email_outlined, isPrimary: true),
      _primaryAmount,
      _FinancialField('تفاصيل الدين', Icons.info_outline_rounded, isPrimary: true),
      _FinancialField('تاريخ الدين', Icons.event_outlined, kind: _FinancialFieldKind.date, required: true, isPrimary: true),
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('تقسيم المبلغ إلى (عدد الأقساط)', Icons.format_list_numbered_rounded),
      _notesField,
    ],
  ),
  'قسط': _FinancialEntryForm(
    label: 'قسط',
    subtitle: 'جدولة الأقساط ومتابعة السداد',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFFD97706),
    fields: [
      _primaryTitle,
      _FinancialField(
        'قيمة القسط',
        Icons.payments_outlined,
        kind: _FinancialFieldKind.number,
        required: true,
        isPrimary: true,
        isAmount: true,
      ),
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'عدد الأقساط',
        Icons.format_list_numbered_rounded,
        kind: _FinancialFieldKind.number,
        isPrimary: true,
      ),
      _FinancialField('القسط الحالي', Icons.low_priority_rounded),
      _FinancialField(
        'تاريخ البداية',
        Icons.first_page_rounded,
        kind: _FinancialFieldKind.date,
      ),
      _FinancialField(
        'تاريخ النهاية',
        Icons.last_page_rounded,
        kind: _FinancialFieldKind.date,
      ),
      _notesField,
    ],
  ),
  'اشتراك': _FinancialEntryForm(
    label: 'اشتراك',
    subtitle: 'اشتراك دوري أو خدمة متكررة',
    icon: Icons.autorenew_rounded,
    color: Color(0xFF0891B2),
    fields: [
      _FinancialField(
        'اسم الاشتراك',
        Icons.subscriptions_outlined,
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
        'تاريخ النهاية',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField('دورة التكرار', Icons.repeat_rounded),
      _FinancialField('طريقة الدفع', Icons.wallet_outlined),
      _notesField,
    ],
  ),
  'غرامة': _FinancialEntryForm(
    label: 'غرامة',
    subtitle: 'غرامة أو مخالفة مالية',
    icon: Icons.gavel_outlined,
    color: Color(0xFFB91C1C),
    fields: [
      _primaryAmount,
      _FinancialField(
        'التصنيف الرئيسي',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['غرامات'],
      ),
      _FinancialField(
        'التصنيف الفرعي',
        Icons.subdirectory_arrow_left_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('الجهة', Icons.business_outlined, isPrimary: true),
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'نوع الغرامة',
        Icons.info_outline_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField('رقم المخالفة', Icons.numbers_rounded),
      _notesField,
    ],
  ),
  'مناسبة': _FinancialEntryForm(
    label: 'مناسبة',
    subtitle: 'تسجيل مناسبة وما يرتبط بها',
    icon: Icons.celebration_outlined,
    color: Color(0xFFDB2777),
    fields: [
      _FinancialField(
        'نوع المناسبة',
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
      ),
      _FinancialField(
        'عنوان المناسبة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ المناسبة',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'اهمية المناسبة',
        Icons.priority_high_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['عادية', 'مهمة', 'مهمة جداً'],
      ),
      _FinancialField('رقم الهاتف', Icons.phone_outlined),
      _FinancialField(
        'تكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'سنوي', 'شهري', 'أسبوعي', 'مخصص'],
      ),
      _FinancialField(
        'تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['بدون تذكير', 'قبل يوم', 'قبل 3 أيام', 'قبل أسبوع', 'مخصص'],
      ),
      _notesField,
    ],
  ),
  'هدية': _FinancialEntryForm(
    label: 'هدية',
    subtitle: 'هدية، تبرع أو زكاة',
    icon: Icons.volunteer_activism_outlined,
    color: Color(0xFF0D9488),
    fields: [
      _primaryTitle,
      _FinancialField(
        'النوع',
        Icons.category_outlined,
        required: true,
        isPrimary: true,
      ),
      _primaryAmount,
      _primaryDate,
      _FinancialField('الجهة', Icons.groups_outlined, isPrimary: true),
      _FinancialField('المناسبة', Icons.celebration_outlined),
      _notesField,
    ],
  ),
  'عهدة مالية': _FinancialEntryForm(
    label: 'عهدة مالية',
    subtitle: 'تسجيل مبلغ تحت مسؤولية شخص ومتابعة تسويته',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF0F766E),
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
      ),
      _FinancialField(
        'اسم المستلم',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'نوع العهدة',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['مؤقتة', 'مستديمة'],
      ),
      _FinancialField(
        'تاريخ الاستحقاق والإرجاع',
        Icons.event_repeat_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'تاريخ التسليم',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
      ),
      _FinancialField(
        'تاريخ الاستلام',
        Icons.event_repeat_outlined,
        kind: _FinancialFieldKind.date,
      ),
      _FinancialField('الجهة أو القسم', Icons.apartment_outlined),
      _FinancialField('الغرض من العهدة', Icons.flag_outlined, required: true),
      _FinancialField(
        'حالة العهدة',
        Icons.fact_check_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
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
    color: Color(0xFF475569),
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
  'اشتراكات': _FinancialEntryForm(
    label: 'اشتراكات',
    subtitle: 'خدمة دورية أو اشتراك متكرر',
    icon: Icons.autorenew_rounded,
    color: Color(0xFF7C3AED),
    fields: [
      _FinancialField(
        'نوع الاشتراك',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['قنوات تلفزيونية', 'الهاتف والانترنت', 'التطبيقات', 'خصومات'],
      ),
      _FinancialField(
        'اسم الاشتراك',
        Icons.subscriptions_outlined,
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
        'تاريخ الاستحقاق',
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
        options: ['شهري', 'سنوي', 'أسبوعي', 'ربع سنوي', 'مخصص'],
      ),
      _FinancialField(
        'تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['بدون تذكير', 'قبل يوم', 'قبل 3 أيام', 'قبل أسبوع', 'مخصص'],
      ),
      _FinancialField(
        'عدد الأفراد',
        Icons.groups_outlined,
        kind: _FinancialFieldKind.number,
      ),
      _FinancialField(
        'طريقة الدفع',
        Icons.wallet_outlined,
        kind: _FinancialFieldKind.select,
        options: ['نقداً', 'بطاقة بنكية', 'تحويل بنكي', 'محفظة إلكترونية', 'خصم تلقائي'],
      ),
      _notesField,
    ],
  ),
  'جمعية': _FinancialEntryForm(
    label: 'جمعية',
    subtitle: 'تنظيم الجمعية والأدوار والمدفوعات',
    icon: Icons.groups_outlined,
    color: Color(0xFF4F46E5),
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
    color: Color(0xFFD97706),
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
      ),
      _FinancialField('رقم المستند', Icons.numbers_rounded, isPrimary: true),
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
      ),
      _FinancialField('الجهة المصدرة', Icons.account_balance_outlined),
      _notesField,
    ],
  ),
  'متابعة': _FinancialEntryForm(
    label: 'متابعة',
    subtitle: 'مهمة أو موعد يحتاج متابعة',
    icon: Icons.fact_check_outlined,
    color: Color(0xFF0D9488),
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
    color: Color(0xFF2563EB),
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
    color: Color(0xFF475569),
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
    color: Color(0xFF0891B2),
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
    color: Color(0xFF059669),
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
      _FinancialField('العملة', Icons.currency_exchange_rounded),
      _notesField,
    ],
  ),
  'مهمة': _FinancialEntryForm(
    label: 'مهمة',
    subtitle: 'متابعة وتخطيط مهمة شخصية',
    icon: Icons.task_alt_outlined,
    color: Color(0xFF0D9488),
    fields: [
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'وقت الاستحقاق',
        Icons.schedule_outlined,
        isPrimary: true,
      ),
      _FinancialField(
        'الأولوية',
        Icons.priority_high_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['منخفضة', 'متوسطة', 'عالية', 'عاجلة'],
      ),
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري', 'سنوي', 'مخصص'],
      ),
      _FinancialField(
        'الوصف',
        Icons.description_outlined,
        kind: _FinancialFieldKind.multiline,
      ),
      _notesField,
    ],
  ),
  'موعد': _FinancialEntryForm(
    label: 'موعد',
    subtitle: 'موعد شخصي مع تكرار وتذكيرات',
    icon: Icons.event_outlined,
    color: Color(0xFF2563EB),
    fields: [
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'التاريخ',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField('الوقت', Icons.schedule_outlined, isPrimary: true),
      _FinancialField('الموقع', Icons.location_on_outlined, isPrimary: true),
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري', 'سنوي', 'مخصص'],
      ),
      _FinancialField(
        'التذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['بدون تذكير', 'قبل 15 دقيقة', 'قبل ساعة', 'قبل يوم', 'مخصص'],
      ),
      _notesField,
    ],
  ),
  'عادة': _FinancialEntryForm(
    label: 'عادة',
    subtitle: 'عادة متكررة للمتابعة اليومية أو الأسبوعية',
    icon: Icons.repeat_rounded,
    color: Color(0xFF0891B2),
    fields: [
      _FinancialField(
        'اسم العادة',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ البداية',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: ['يومي', 'أيام محددة أسبوعياً', 'أسبوعي', 'شهري', 'مخصص'],
      ),
      _FinancialField('وقت التذكير', Icons.schedule_outlined, isPrimary: true),
      _FinancialField(
        'تفعيل التذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['نعم', 'لا'],
      ),
      _notesField,
    ],
  ),
  'ملاحظات': _FinancialEntryForm(
    label: 'ملاحظات',
    subtitle: 'ملاحظة أو تذكير شخصي للمتابعة',
    icon: Icons.sticky_note_2_outlined,
    color: Color(0xFF7C3AED),
    fields: [
      _FinancialField(
        'العنوان',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ الاستحقاق',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField(
        'وقت الاستحقاق',
        Icons.schedule_outlined,
        isPrimary: true,
      ),
      _FinancialField(
        'الأولوية',
        Icons.priority_high_rounded,
        kind: _FinancialFieldKind.select,
        isPrimary: true,
        options: ['منخفضة', 'متوسطة', 'عالية', 'عاجلة'],
      ),
      _FinancialField(
        'التكرار',
        Icons.repeat_rounded,
        kind: _FinancialFieldKind.select,
        options: ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري', 'سنوي', 'مخصص'],
      ),
      _FinancialField(
        'الوصف',
        Icons.description_outlined,
        kind: _FinancialFieldKind.multiline,
      ),
      _FinancialField(
        'تفعيل تذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['نعم', 'لا'],
      ),
    ],
  ),
  'حسابات': _FinancialEntryForm(
    label: 'حسابات',
    subtitle: 'حفظ بيانات الحسابات وكلمات السر',
    icon: Icons.password_rounded,
    color: Color(0xFF475569),
    fields: [
      _FinancialField(
        'اسم الحساب',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'التصنيف',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'إيميلات وكلمات سر',
          'حسابات بنكية',
          'تطبيقات',
          'كلمات سر أخرى',
        ],
      ),
      _FinancialField(
        'اسم المستخدم',
        Icons.person_outline_rounded,
        isPrimary: true,
      ),
      _FinancialField(
        'كلمة السر',
        Icons.password_rounded,
        kind: _FinancialFieldKind.secret,
        isPrimary: true,
      ),
      _FinancialField('الرابط', Icons.link_rounded),
      _notesField,
    ],
  ),
  'أدوية وبياناتها': _FinancialEntryForm(
    label: 'أدوية وبياناتها',
    subtitle: 'بيانات الدواء والجرعات والتذكيرات',
    icon: Icons.medication_outlined,
    color: Color(0xFFDC2626),
    fields: [
      _FinancialField(
        'اسم الدواء',
        Icons.medication_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'لمن هذا الدواء',
        Icons.person_outline_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'من تاريخ',
        Icons.event_outlined,
        kind: _FinancialFieldKind.date,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'إلى تاريخ',
        Icons.event_available_outlined,
        kind: _FinancialFieldKind.date,
        isPrimary: true,
      ),
      _FinancialField(
        'أوقات الجرعات',
        Icons.schedule_outlined,
        isPrimary: true,
      ),
      _FinancialField('الاسم العلمي', Icons.science_outlined),
      _FinancialField(
        'شكل الدواء',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        options: ['قرص', 'كبسولة', 'شراب', 'حقنة', 'مرهم', 'قطرة', 'أخرى'],
      ),
      _FinancialField('التركيز', Icons.speed_outlined),
      _FinancialField('الجرعة', Icons.medical_information_outlined),
      _FinancialField(
        'تفعيل التذكيرات',
        Icons.notifications_outlined,
        kind: _FinancialFieldKind.select,
        options: ['نعم', 'لا'],
      ),
      _notesField,
    ],
  ),
  'مواقع وأماكن': _FinancialEntryForm(
    label: 'مواقع وأماكن',
    subtitle: 'حفظ مكان مهم وبيانات الوصول إليه',
    icon: Icons.location_on_outlined,
    color: Color(0xFFD97706),
    fields: [
      _FinancialField(
        'اسم المكان',
        Icons.place_outlined,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'التصنيف',
        Icons.category_outlined,
        kind: _FinancialFieldKind.select,
        required: true,
        isPrimary: true,
        options: [
          'المنزل',
          'العمل',
          'سفر',
          'مطعم',
          'صديق',
          'عميل',
          'مهم',
          'مخصص',
        ],
      ),
      _FinancialField(
        'الموقع أو الرابط',
        Icons.link_rounded,
        required: true,
        isPrimary: true,
      ),
      _FinancialField(
        'الوصف',
        Icons.description_outlined,
        kind: _FinancialFieldKind.multiline,
      ),
      _notesField,
    ],
  ),
  'تجديد': _FinancialEntryForm(
    label: 'تجديد',
    subtitle: 'تذكير بتجديد إجراء أو وثيقة مرتبطة بهذا الالتزام',
    icon: Icons.autorenew_rounded,
    color: Color(0xFF0891B2),
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
        options: ['بدون تذكير', 'قبل يوم', 'قبل 3 أيام', 'قبل أسبوع'],
      ),
      _notesField,
    ],
  ),
  'تذكير': _FinancialEntryForm(
    label: 'تذكير',
    subtitle: 'تذكير مرتبط بهذا الالتزام في تاريخ محدد',
    icon: Icons.notifications_active_outlined,
    color: Color(0xFFEA580C),
    fields: [
      _FinancialField(
        'عنوان التذكير',
        Icons.title_rounded,
        required: true,
        isPrimary: true,
        isTitle: true,
      ),
      _FinancialField(
        'تاريخ ووقت التذكير',
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
        options: ['بدون تكرار', 'يومي', 'أسبوعي', 'شهري', 'سنوي'],
      ),
      _notesField,
    ],
  ),
  'تفويض': _FinancialEntryForm(
    label: 'تفويض',
    subtitle: 'تفويض شخص لإدارة مصروفاتك الشخصية أو غيرها',
    icon: Icons.assignment_ind_outlined,
    color: Color(0xFF7C3AED),
    fields: [
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE2E7)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(category.icon, color: category.color, size: 22),
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
                      borderRadius: BorderRadius.circular(10),
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
            const SizedBox(height: 8),
            Text(
              category.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              category.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
                height: 1.2,
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
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFDDE2E7)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(type.icon, color: color, size: 19),
              ),
              const SizedBox(height: 5),
              Text(
                type.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  height: 1.2,
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
    'متأخرة' => const Color(0xFFDC2626),
    'قريبة الاستحقاق' => const Color(0xFFD97706),
    'مكتملة' => const Color(0xFF2563EB),
    _ => const Color(0xFF0F9F6E),
  };
}