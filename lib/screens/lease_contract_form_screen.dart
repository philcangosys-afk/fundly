import 'package:flutter/material.dart' hide Text, Align;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/lease_contract_data.dart';
import '../data/people_directory_store.dart';
import '../data/project_assets_repository.dart';
import '../data/document_store.dart';
import '../data/app_reminders_store.dart';
import '../data/user_signature_store.dart';
import '../data/user_stamp_store.dart';
import 'signature_settings_screen.dart';
import '../widgets/shared/app_design.dart';
import 'rent_payments_view.dart' show syncLeasePaymentRecords;
import '../data/template_print.dart';
import 'template_print_screen.dart';

/// شاشة «عقد الإيجار الكامل».
///
/// تجمع كل أقسام العقد الرسمي في صفحة واحدة: بيانات العقد، بيانات العقار
/// (تُملأ تلقائيًا من العقار المسجّل)، المؤجر، المستأجر، ممثل المستأجر،
/// التأمين على العين، وجدول دفعات الإيجار بالشيكات ومجموعها.
///
/// كل شخص يُسجَّل هنا (مؤجر/مستأجر/ممثل) يُكتب تلقائيًا في «الأفراد
/// والجهات»، ويمكن سحبه منها بدل إعادة الكتابة.
class LeaseContractFormScreen extends StatefulWidget {
  const LeaseContractFormScreen({
    super.key,
    required this.repository,
    required this.assetId,
    required this.unitKey,
    required this.unitName,
    required this.propertyTitle,
    this.propertyMeta = const <String, String>{},
    this.existing,
    this.leaseType = PropertyUnitContractRecord.leaseTypeStandard,
    this.groupKey,
    this.vehicleFields = const <LeaseFieldSpec>[],
    this.title = 'عقد الإيجار',
    this.subjectLabel = 'الوحدة',
    this.templateNotes,
    this.renewStart,
    this.renewEnd,
    this.renewNewNo,
    this.renewOldNo,
    this.forActivity = false,
    this.prefillNotes,
    this.createActivity,
    this.activityClassOptions = const <String>[],
    this.propertyType = '',
    this.unitType = '',
    this.unitChoices = const <({String key, String name})>[],
  });

  /// للرأس: «نوع العقار / اسم العقار» ثم «نوع الوحدة / اسم الوحدة».
  final String propertyType;
  final String unitType;

  /// عقد متعدد الوحدات: الوحدات التي يُختار منها («اختر الوحدات المشمولة»)
  /// — نفس نموذج العقد كاملًا، ويُحفظ لكل وحدة مختارة سجلّ بمفتاح مجموعة
  /// واحد، والدفعات على أول وحدة مختارة.
  final List<({String key, String name})> unitChoices;

  bool get isMultiUnit => unitChoices.isNotEmpty;

  /// إضافة نشاط جديد من هذه الصفحة مباشرة ([assetId] فارغ): يُنشأ النشاط
  /// من «بيانات الرخصة» عند الحفظ، ويُعيد معرّفه ليُربط به العقد.
  final Future<String?> Function(LeaseContractData data)? createActivity;

  /// خيارات «تصنيف النشاط» في بيانات الرخصة.
  final List<String> activityClassOptions;

  /// عقد إيجار نشاط تجاري: صاحب النشاط هو المستأجر، و«بيانات عقد
  /// الإيجار» بحقول النشاط ([LeaseContractData.activityContractFields]).
  final bool forActivity;

  /// بيانات تُبدأ بها النسخة الجديدة كما هي (من شاشة إضافة النشاط).
  final String? prefillNotes;

  /// تجديد عقد منتهٍ: مدة العقد الجديد ورقماه (الجديد والقديم) معبّأة،
  /// وبقية بياناته من العقد السابق ([templateNotes]).
  final DateTime? renewStart;
  final DateTime? renewEnd;
  final String? renewNewNo;
  final String? renewOldNo;

  bool get isRenewal => templateNotes != null && renewStart != null;

  /// عقد تأجير مركبة: حقول «بيانات المركبة» مكان «بيانات العقار»، بلا ممثل
  /// المستأجر ولا «الغرض من الإيجار». فارغة = عقد عقار كالمعتاد.
  final List<LeaseFieldSpec> vehicleFields;

  /// عنوان الصفحة («عقد تأجير مركبات بحرية» مثلًا).
  final String title;

  /// ما يُكتب قبل اسم العين في الرأس («الوحدة» / «المركبة»).
  final String subjectLabel;

  /// بيانات عقد سابق تُبدأ منها نسخة جديدة (التجديد) — بلا تواريخ ودفعات.
  final String? templateNotes;

  bool get isVehicle => vehicleFields.isNotEmpty;

  final ProjectAssetsRepository repository;
  final String assetId;
  final String unitKey;
  final String unitName;
  final String propertyTitle;

  /// بيانات العقار الرسمية المسجّلة عند إضافة العقار (المدينة، المنطقة،
  /// حوض، قطعة، رقم العقار، معرف العقار...) — تُملأ في قسم بيانات العقار.
  final Map<String, String> propertyMeta;

  final PropertyUnitContractRecord? existing;
  final String leaseType;
  final String? groupKey;

  @override
  State<LeaseContractFormScreen> createState() =>
      _LeaseContractFormScreenState();
}

class _LeaseContractFormScreenState extends State<LeaseContractFormScreen> {
  late LeaseContractData _data;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  /// «رقم العقد المنتهي» مأخوذ من عقد سابق فعلي: لا يُعدَّل.
  bool _oldNoLocked = false;

  /// النشاط المُنشأ عند أول حفظ — فلا يُنشأ مرة ثانية إن أُعيد الحفظ.
  String? _createdAssetId;

  /// ما حُفظ فعلًا على الخادم في هذه الشاشة: إن فشل حفظ لاحق (انقطاع شبكة)
  /// وأُعيد الحفظ يُحدَّث نفس السجل بدل إنشاء عقد مكرر.
  String? _savedContractId;
  final Map<String, String> _savedUnitContractIds = {};
  String? _savedGroupKey;

  /// «الأنشطة التجارية» في الرخصة: ثلاثة أسطر، و«المزيد» يضيف سطرًا.
  final List<TextEditingController> _activityLines = [];

  /// الوحدات المختارة في العقد المتعدد (مفاتيحها).
  final Set<String> _chosenUnits = {};

  String get _tradeName =>
      (_data.license[LeaseContractData.kTradeName] ?? '').trim();

  /// اسم العين في العقد — للنشاط الجديد اسمه التجاري.
  String get _subjectName => widget.unitName.trim().isNotEmpty
      ? widget.unitName
      : (_tradeName.isEmpty ? widget.propertyTitle : _tradeName);

  @override
  void initState() {
    super.initState();
    _data = LeaseContractData.decode(
      widget.existing?.notes ?? widget.templateNotes ?? widget.prefillNotes,
    );
    if (widget.existing == null && widget.templateNotes != null) {
      // تجديد: المستأجر والمؤجر كما هما، ورقم العقد السابق يصير «المنتهي».
      final oldNo = (_data.contract[LeaseContractData.kNewNo] ?? '').trim();
      _data.contract
        ..remove(LeaseContractData.kStartDate)
        ..remove(LeaseContractData.kEndDate)
        ..remove(LeaseContractData.kNewNo)
        ..remove(LeaseContractData.kSignedAt)
        ..remove(LeaseContractData.kSignedBy);
      if (oldNo.isNotEmpty) _data.contract[LeaseContractData.kOldNo] = oldNo;
      _data.payments.clear();
      // رسوم العقد السابق سُدِّدت معه: لا تتكرر مستحقةً على الجديد.
      _data.adminFees.clear();
      // التأمين محفوظ لدى المؤجر وينتقل مع التجديد: شيكه بلا تاريخ
      // استحقاق قديم (كان يظهر «متأخرًا» من جديد).
      for (final row in _data.deposits) {
        if ((row[LeaseContractData.kCollectMethod] ?? '').trim() == 'شيك') {
          row
            ..remove(LeaseContractData.kPaymentChequeDate)
            ..remove(LeaseContractData.kPaymentDue);
        }
      }
      // تجديد من «إدارة الإيجار»: الرقمان والمدة الجديدة جاهزة للمراجعة.
      if (widget.isRenewal) {
        _data.contract[LeaseContractData.kStartDate] = _iso(widget.renewStart!);
        if (widget.renewEnd != null) {
          _data.contract[LeaseContractData.kEndDate] = _iso(widget.renewEnd!);
        }
        final renewOld = (widget.renewOldNo ?? '').trim();
        if (renewOld.isNotEmpty) {
          _data.contract[LeaseContractData.kOldNo] = renewOld;
        }
        final renewNew = (widget.renewNewNo ?? '').trim();
        if (renewNew.isNotEmpty) {
          _data.contract[LeaseContractData.kNewNo] = renewNew;
        }
      }
    }
    if (widget.isVehicle) {
      _data.contract[LeaseContractData.kSubject] =
          LeaseContractData.subjectVehicle;
      _data.contract.remove(LeaseContractData.kPurpose);
    }
    // أرقام العقد: الجديد رقم قصير متسلسل لعقود هذا الأصل، والمنتهي رقم آخر
    // عقد لنفس الوحدة/المركبة/النشاط ولا يُعدَّل إن وُجد.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fillContractNumbers(),
    );

    // بيانات العقار تأتي من العقار نفسه، وبيانات العقد الأساسية من العقد
    // المحفوظ سابقًا في الأعمدة الحقيقية (المبلغ والتواريخ والمستأجر).
    _data.fillPropertyFrom(widget.propertyMeta);
    final existing = widget.existing;
    if (existing != null) {
      if ((_data.contract[LeaseContractData.kValue] ?? '').isEmpty &&
          existing.annualRent > 0) {
        _data.contract[LeaseContractData.kValue] =
            existing.annualRent.toStringAsFixed(2);
      }
      if ((_data.contract[LeaseContractData.kStartDate] ?? '').isEmpty &&
          existing.startDate != null) {
        _data.contract[LeaseContractData.kStartDate] = _iso(existing.startDate!);
      }
      if ((_data.contract[LeaseContractData.kEndDate] ?? '').isEmpty &&
          existing.endDate != null) {
        _data.contract[LeaseContractData.kEndDate] = _iso(existing.endDate!);
      }
      if ((_data.tenant[LeaseContractData.kName] ?? '').isEmpty &&
          (existing.tenantName ?? '').isNotEmpty) {
        _data.tenant[LeaseContractData.kName] = existing.tenantName!;
      }
      if ((_data.tenant[LeaseContractData.kPhone] ?? '').isEmpty &&
          (existing.tenantPhone ?? '').isNotEmpty) {
        _data.tenant[LeaseContractData.kPhone] = existing.tenantPhone!;
      }
    }
    if (widget.forActivity) {
      final lines = (_data.license[LeaseContractData.kActivities] ?? '')
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      while (lines.length < 3) {
        lines.add('');
      }
      _activityLines.addAll(lines.map((t) => TextEditingController(text: t)));
      if (widget.existing == null) {
        for (final key in const [
          LeaseContractData.kLeaseReminder,
          LeaseContractData.kLicenseReminder,
        ]) {
          if ((_data.license[key] ?? '').trim().isEmpty) {
            _data.license[key] = 'قبل شهر';
          }
        }
      }
      // النشاط: «بيانات الرخصة» مكان «بيانات العقار».
      return;
    }
    if (widget.isVehicle) return;
    // رقم عداد واحد قديم ← «عدد العدادات» 1 ورقمه.
    LeaseContractData.migrateMeters(_data.property);
    // العقد المتعدد الجديد: نمط المدة سنوي، فتكون النهاية بعد سنة من
    // البداية تلقائيًا (وتبقى قابلة للتعديل).
    if (widget.isMultiUnit && widget.existing == null) {
      if ((_data.contract[LeaseContractData.kTermMode] ?? '').trim().isEmpty) {
        _data.contract[LeaseContractData.kTermMode] = 'سنوي';
      }
      _syncContractEndDate(_data.contract);
    }
    if (widget.isMultiUnit) return;
    if ((_data.property['رقم العين'] ?? '').isEmpty) {
      _data.property['رقم العين'] = widget.unitName;
    }
    // العين المؤجرة هي هذه الوحدة بعينها، والمستخدم يعرفها باسمها («محل
    // 1») لا برقمها. كان الحقل يُترك فارغًا فيُطبع العقد بلا وصف للعين.
    if ((_data.property['بيانات العين المؤجرة'] ?? '').trim().isEmpty) {
      _data.property['بيانات العين المؤجرة'] = widget.unitName;
    }
  }

  /// رقم العقد كما يُعرض: المكتوب فيه، وإلا مختصر معرّفه.
  static String _numberOf(PropertyUnitContractRecord contract) {
    final written = (LeaseContractData.decode(contract.notes)
                .contract[LeaseContractData.kNewNo] ??
            '')
        .trim();
    if (written.isNotEmpty) return written;
    final id = contract.id;
    if (id == null) return '';
    final digits = id.replaceAll(RegExp('[^0-9]'), '');
    final source = digits.isEmpty ? id.replaceAll('-', '') : digits;
    return source.length <= 11 ? source : source.substring(0, 11);
  }

  /// «رقم العقد الجديد»: رقم قصير (0001، 0002...) يلي أكبر رقم قصير بين
  /// عقود هذا الأصل. «رقم العقد المنتهي»: رقم آخر عقد سابق لنفس العين،
  /// ويُقفل فلا يُكتب فيه إن وُجد عقد سابق.
  Future<void> _fillContractNumbers() async {
    var all = const <PropertyUnitContractRecord>[];
    if (widget.assetId.trim().isNotEmpty) {
      try {
        all = await widget.repository.fetchUnitContracts(widget.assetId);
      } catch (_) {
        // بلا اتصال: يبقى الحقلان كما هما ويكتبهما المستخدم.
      }
    }
    if (!mounted) return;
    final existing = widget.existing;
    PropertyUnitContractRecord? previous;
    for (final contract in all) {
      if (contract.unitKey != widget.unitKey) continue;
      if (existing != null) {
        if (contract.id == existing.id) continue;
        final mine = existing.startDate;
        final theirs = contract.startDate;
        if (mine != null && theirs != null && !theirs.isBefore(mine)) {
          continue;
        }
      }
      final at = contract.startDate ?? DateTime(1900);
      if (previous == null || at.isAfter(previous.startDate ?? DateTime(1900))) {
        previous = contract;
      }
    }
    final previousNo = previous == null ? '' : _numberOf(previous);
    var maxNo = 0;
    for (final contract in all) {
      final n = int.tryParse(_numberOf(contract));
      if (n != null && n < 100000 && n > maxNo) maxNo = n;
    }
    final next = '${maxNo + 1}'.padLeft(4, '0');
    final renewOld = (widget.renewOldNo ?? '').trim();
    const newKey = LeaseContractData.kNewNo;
    const oldKey = LeaseContractData.kOldNo;
    setState(() {
      if (existing == null) {
        final current = (_data.contract[newKey] ?? '').trim();
        if (current.isEmpty || current.length > 6) {
          _data.contract[newKey] = next;
          _controllers['contract.$newKey']?.text = next;
        }
        if ((_data.contract[oldKey] ?? '').trim().isEmpty &&
            previousNo.isNotEmpty) {
          _data.contract[oldKey] = previousNo;
          _controllers['contract.$oldKey']?.text = previousNo;
        }
      }
      _oldNoLocked = (previousNo.isNotEmpty || renewOld.isNotEmpty) &&
          (_data.contract[oldKey] ?? '').trim().isNotEmpty;
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _activityLines) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// يوم/شهر/سنة برقمين — الترتيب الذي يقرأه المستخدم من اليمين.
  ///
  /// بلا تصفير كان 3/8 و8/3 يبدوان سواءً فلا يُعرف أيّهما اليوم.
  static String _pretty(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}';
  }

  /// نهاية العقد تُشتق من بدايته ونمط مدته.
  ///
  /// «شهري» = شهر ناقص يوم، و«سنوي» = سنة ناقص يوم: عقد يبدأ 01/01 ينتهي
  /// 31/12، لا 01/01 من العام التالي — وإلا حُسب يوم واحد مرتين في كل
  /// تجديد. «يومي» = يوم واحد (النهاية يوم البداية نفسه)، و«مخصص» بيد
  /// المستخدم.
  ///
  /// لا يُكتب فوق نهاية أدخلها المستخدم إلا إن كان هو من غيّر البداية أو
  /// النمط — وهذان هما المصدران الوحيدان اللذان يستدعيان هذا التابع.
  void _syncContractEndDate(Map<String, String> store) {
    if (!identical(store, _data.contract)) return;
    final start = DateTime.tryParse(
      _data.contract[LeaseContractData.kStartDate] ?? '',
    );
    if (start == null) return;
    final mode = (_data.contract[LeaseContractData.kTermMode] ?? '').trim();
    final DateTime? end = switch (mode) {
      // يومي وبالساعات: النهاية يوم البداية (والساعتان تحددان المدة).
      'يومي' || 'بالساعات' => start,
      'شهري' => DateTime(
        start.year,
        start.month + 1,
        start.day,
      ).subtract(const Duration(days: 1)),
      'سنوي' => DateTime(
        start.year + 1,
        start.month,
        start.day,
      ).subtract(const Duration(days: 1)),
      _ => null,
    };
    if (end == null) return;
    _data.contract[LeaseContractData.kEndDate] = _iso(end);
  }

  TextEditingController _controllerFor(
    String scope,
    Map<String, String> store,
    String key,
  ) {
    final id = '$scope.$key';
    return _controllers.putIfAbsent(
      id,
      () => TextEditingController(text: store[key] ?? ''),
    );
  }

  void _commitControllers() {
    _controllers.forEach((id, controller) {
      final parts = id.split('.');
      if (parts.length < 2) return;
      final scope = parts.first;
      final key = parts.sublist(1).join('.');
      final store = _storeOf(scope);
      if (store == null) return;
      store[key] = controller.text.trim();
    });
    if (widget.forActivity) {
      _data.license[LeaseContractData.kActivities] = _activityLines
          .map((c) => c.text.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
    }
  }

  Map<String, String>? _storeOf(String scope) {
    switch (scope) {
      case 'contract':
        return _data.contract;
      case 'property':
        return _data.property;
      case 'lessor':
        return _data.lessor;
      case 'tenant':
        return _data.tenant;
      case 'rep':
        return _data.representative;
      case 'license':
        return _data.license;
      default:
        return null;
    }
  }

  /// حقول إلزامية: بجانب عنوانها نجمة حمراء.
  static const _requiredLabels = <String>{
    'تاريخ بداية عقد الإيجار',
    'تاريخ نهاية عقد الإيجار',
    'اسم الدفعة',
    'قيمة الدفعة',
    'قيمة الرسم',
    'مبلغ التأمين',
    'تاريخ الاستحقاق',
    // الدفع بشيك: رقمه وتاريخه وبنكه ورقم الحساب.
    'رقم الشيك',
    'تاريخ الشيك',
    'اسم البنك',
    'رقم الحساب',
  };

  /// حقل اختياري (بلا نجمة): التاريخ فيه يُمسح بزر ×.
  static bool _optionalField(LeaseFieldSpec spec) {
    final label = spec.label;
    if (label.endsWith(' *')) return false;
    return !_requiredLabels.contains(label);
  }

  /// يمسح تاريخًا اختياريًا. مع «شيك» تاريخ الشيك والاستحقاق نسختان من
  /// تاريخ واحد ([_syncChequeDue])، فيُمسحان معًا وإلا أعادته المزامنة.
  static void _clearDate(Map<String, String> row, String key) {
    final old = (row[key] ?? '').trim();
    row[key] = '';
    final other = switch (key) {
      LeaseContractData.kPaymentChequeDate => LeaseContractData.kPaymentDue,
      LeaseContractData.kPaymentDue => LeaseContractData.kPaymentChequeDate,
      _ => null,
    };
    if (other != null && (row[other] ?? '').trim() == old) row[other] = '';
  }

  /// زر × داخل حقل التاريخ الاختياري حين يكون فيه تاريخ.
  Widget? _clearDateButton(
    LeaseFieldSpec spec,
    String raw,
    VoidCallback onClear,
  ) {
    if (raw.trim().isEmpty || !_optionalField(spec)) return null;
    return IconButton(
      tooltip: AppTr.tr('مسح التاريخ'),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.muted),
      onPressed: onClear,
    );
  }

  /// [sheet]: نوافذ الإضافة (دفعة/رسم/تأمين) — العنوان داخل الحقل دائمًا،
  /// حتى في النشاط التجاري، وإلا ظهرت المستطيلات فارغة بلا عناوين.
  InputDecoration _decoration(String label, {bool sheet = false}) {
    final inline = sheet || !widget.forActivity;
    // «عنوان *»: إلزامي بحسب القسم ([LeaseContractData.contractRequired]).
    final starred = label.endsWith(' *');
    final base = starred ? label.substring(0, label.length - 2) : label;
    final required = inline && (starred || _requiredLabels.contains(base));
    return _baseDecoration(
      labelText: inline && !required ? AppTr.tr(base) : null,
      label: required
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    base,
                    maxLines: 3,
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
          : null,
    );
  }

  InputDecoration _baseDecoration({String? labelText, Widget? label}) =>
      InputDecoration(
        labelText: labelText,
        label: label,
        isDense: true,
        filled: true,
        fillColor: AppTheme.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rIcon),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.body,
        ),
      );

  /// عنوان الحقل فوقه بكلماته كاملة (عقد النشاط التجاري).
  Widget _labeled(String label, Widget field, {String? note}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
        // الحقل الإلزامي بنجمة حمراء.
        child: Row(
          children: [
            Flexible(
              child: Text(
                label.endsWith('*')
                    ? label.substring(0, label.length - 1).trim()
                    : label,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.body,
                ),
              ),
            ),
            if (label.endsWith('*'))
              const Text(
                ' *',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      ),
      field,
      if (note != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, top: 3),
          child: Text(
            note,
            softWrap: true,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ),
    ],
  );

  Widget _fieldWidget(
    String scope,
    Map<String, String> store,
    LeaseFieldSpec spec,
  ) {
    if (!widget.forActivity) {
      // عقد العقار والمركبة: الحقل الإلزامي في قسمه بنجمة حمراء.
      final required = widget.isVehicle
          ? (LeaseContractData.vehicleRequired[scope]?.contains(spec.key) ??
                    false) ||
                (scope != 'property' &&
                    (LeaseContractData.contractRequired[scope]
                            ?.contains(spec.key) ??
                        false))
          : (LeaseContractData.contractRequired[scope]?.contains(spec.key) ??
                false);
      return _fieldInput(
        scope,
        store,
        required ? spec.withLabel('${spec.label} *') : spec,
      );
    }
    final field = _fieldInput(scope, store, spec);
    // الحقل الإلزامي في عقد النشاط بنجمة حمراء.
    final required =
        LeaseContractData.activityRequired[scope]?.contains(spec.key) ?? false;
    final label = spec.label.trim();
    return _labeled(
      required && !label.endsWith('*') ? '$label *' : label,
      field,
    );
  }

  Widget _fieldInput(
    String scope,
    Map<String, String> store,
    LeaseFieldSpec spec,
  ) {
    if (spec.options.isNotEmpty) {
      final current = store[spec.key];
      return DropdownButtonFormField<String>(
        initialValue:
            current != null && spec.options.contains(current) ? current : null,
        isExpanded: true,
        decoration: _decoration(spec.label),
        hint: widget.forActivity
            ? const Text('اختر', style: TextStyle(fontSize: 12))
            : null,
        items: spec.options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(
                  option,
                  // النشاط: الخيار كاملًا ولو في سطرين.
                  maxLines: widget.forActivity ? 2 : 1,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() {
          store[spec.key] = value ?? '';
          // تغيير نمط المدة يعيد حساب تاريخ النهاية فورًا.
          if (spec.key == LeaseContractData.kTermMode) {
            _syncContractEndDate(store);
          }
        }),
      );
    }

    if (spec.time) {
      final raw = store[spec.key] ?? '';
      return InkWell(
        onTap: () async {
          final parts = raw.split(':');
          final initial = parts.length == 2
              ? TimeOfDay(
                  hour: int.tryParse(parts[0]) ?? 9,
                  minute: int.tryParse(parts[1]) ?? 0,
                )
              : TimeOfDay.now();
          final picked = await showTimePicker(
            context: context,
            initialTime: initial,
          );
          if (picked != null) {
            setState(
              () => store[spec.key] =
                  '${picked.hour.toString().padLeft(2, '0')}:'
                  '${picked.minute.toString().padLeft(2, '0')}',
            );
          }
        },
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        child: InputDecorator(
          decoration: _decoration(spec.label),
          child: Text(
            raw.isEmpty ? 'غير محدد' : raw,
            maxLines: 3,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: raw.isEmpty ? AppTheme.muted : AppTheme.title,
            ),
          ),
        ),
      );
    }

    if (spec.date) {
      final raw = store[spec.key] ?? '';
      return InkWell(
        onTap: () async {
          final initial = DateTime.tryParse(raw) ?? DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(2000),
            lastDate: DateTime(2070),
          );
          if (picked != null) {
            setState(() {
              store[spec.key] = _iso(picked);
              if (spec.key == LeaseContractData.kStartDate) {
                _syncContractEndDate(store);
              }
            });
          }
        },
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        child: InputDecorator(
          decoration: _decoration(spec.label).copyWith(
            suffixIcon: _clearDateButton(
              spec,
              raw,
              () => setState(() => _clearDate(store, spec.key)),
            ),
          ),
          child: Text(
            raw.isEmpty ? 'غير محدد' : _pretty(raw),
            maxLines: 3,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: raw.isEmpty ? AppTheme.muted : AppTheme.title,
            ),
          ),
        ),
      );
    }

    // رقم العقد المنتهي من عقد سابق فعلي: للقراءة فقط.
    final locked = _oldNoLocked &&
        scope == 'contract' &&
        spec.key == LeaseContractData.kOldNo;
    return TextField(
      controller: _controllerFor(scope, store, spec.key),
      readOnly: locked,
      textAlign: AppTr.alignEnd,
      maxLines: spec.multiline ? 3 : 1,
      keyboardType: spec.numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: locked ? AppTheme.muted : null,
      ),
      decoration: locked
          ? _decoration(spec.label).copyWith(
              fillColor: const Color(0xFFE6ECEA),
              suffixIcon: const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppTheme.muted,
              ),
            )
          : _decoration(spec.label),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required String scope,
    required Map<String, String> store,
    required List<LeaseFieldSpec> fields,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              Icon(icon, size: 17, color: AppTheme.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: AppTheme.sMd),
          LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final spec in fields)
                    if (scope == 'property' &&
                        !widget.isVehicle &&
                        LeaseContractData.meterGroups.containsKey(spec.key))
                      SizedBox(
                        width: constraints.maxWidth,
                        child: _meterBlock(store, spec),
                      )
                    else
                    SizedBox(
                      // الاسم سطر كامل: يظهر كله فيُراجَع، لا مقصوصًا.
                      width: spec.multiline ||
                              spec.key == LeaseContractData.kName ||
                              spec.key == LeaseContractData.kLessorCapacity ||
                              spec.key == LeaseContractData.kRepName ||
                              // المركبة: نمط المدة وحده في سطره، فيبقى
                              // التاريخان جنب بعض تحته.
                              (widget.isVehicle &&
                                  scope == 'contract' &&
                                  spec.key == LeaseContractData.kTermMode)
                          ? constraints.maxWidth
                          : half,
                      child: _fieldWidget(scope, store, spec),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// «عدد عدادات الكهرباء/المياه»، وتحته لكل عداد: رقمه، وعلى من (المستأجر
  /// أو المؤجر). الأرقام وعلى من سطر لكل عداد في مفتاحيهما.
  Widget _meterBlock(Map<String, String> store, LeaseFieldSpec spec) {
    final group = LeaseContractData.meterGroups[spec.key]!;
    final count = LeaseContractData.meterCountOf(store, spec.key);
    final numbers = LeaseContractData.meterLines(store[group.$1], count);
    final payers = LeaseContractData.meterLines(store[group.$2], count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey('lease-meter-count-${spec.key}'),
          initialValue: count == 0 ? '' : '$count',
          textAlign: AppTr.alignEnd,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          decoration: _decoration(spec.label),
          onChanged: (value) => setState(() {
            final raw = int.tryParse(value.trim()) ?? 0;
            final n = raw < 0 ? 0 : (raw > 20 ? 20 : raw);
            if (n == 0) {
              store.remove(spec.key);
              store.remove(group.$1);
              store.remove(group.$2);
              return;
            }
            store[spec.key] = '$n';
            store[group.$1] =
                LeaseContractData.meterLines(store[group.$1], n).join('\n');
            store[group.$2] =
                LeaseContractData.meterLines(store[group.$2], n).join('\n');
          }),
        ),
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('lease-meter-${spec.key}-$i'),
                    initialValue: numbers[i],
                    textAlign: AppTr.alignEnd,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _decoration('${group.$3} ${i + 1}'),
                    onChanged: (value) {
                      // يُقرأ من المخزن عند كل حرف: خانة أخرى قد تكون
                      // كُتبت بعد آخر بناء.
                      final lines = LeaseContractData.meterLines(
                        store[group.$1],
                        LeaseContractData.meterCountOf(store, spec.key),
                      );
                      if (i < lines.length) lines[i] = value.trim();
                      store[group.$1] = lines.join('\n');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('lease-meter-payer-${spec.key}-$i'),
                    initialValue:
                        LeaseContractData.utilityPayers.contains(payers[i])
                        ? payers[i]
                        : null,
                    isExpanded: true,
                    decoration: _decoration('على من'),
                    items: [
                      for (final option in LeaseContractData.utilityPayers)
                        DropdownMenuItem<String>(
                          value: option,
                          child: Text(
                            option,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      final lines = LeaseContractData.meterLines(
                        store[group.$2],
                        LeaseContractData.meterCountOf(store, spec.key),
                      );
                      if (i < lines.length) lines[i] = value ?? '';
                      store[group.$2] = lines.join('\n');
                    }),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// «اختر الوحدات المشمولة بالعقد» — أعلى نموذج العقد المتعدد.
  Widget _unitsPickerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              const Icon(
                Icons.apartment_rounded,
                size: 17,
                color: AppTheme.brand,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'اختر الوحدات المشمولة بالعقد *',
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              Text(
                '${_chosenUnits.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.sMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final unit in widget.unitChoices)
                FilterChip(
                  label: Text(unit.name),
                  selected: _chosenUnits.contains(unit.key),
                  selectedColor: AppTheme.brand.withValues(alpha: 0.16),
                  onSelected: (value) => setState(() {
                    if (value) {
                      _chosenUnits.add(unit.key);
                    } else {
                      _chosenUnits.remove(unit.key);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'اختر وحدتين على الأقل. الدفعات والتأمين تُسجَّل على أول وحدة '
            'مختارة، والإيجار السنوي يُوزَّع على الوحدات بالتساوي.',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }

  /// أسماء الوحدات المختارة بترتيب ظهورها.
  List<({String key, String name})> get _chosenList => [
    for (final unit in widget.unitChoices)
      if (_chosenUnits.contains(unit.key)) unit,
  ];

  // ================= عقد إيجار النشاط التجاري =================
  // الحقول يمينًا ويسارًا كما في ورقة «إضافة نشاط تجاري».

  /// صندوق قسم بعنوانه، ومحتواه أسطر جاهزة.
  Widget _activityCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              Icon(icon, size: 17, color: AppTheme.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.sMd),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }

  /// سطر بحقلين: الأول يمينًا والثاني يسارًا (أو فراغ).
  Widget _pair(Widget? right, Widget? left) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: right ?? const SizedBox.shrink()),
      const SizedBox(width: 10),
      Expanded(child: left ?? const SizedBox.shrink()),
    ],
  );

  Widget _act(
    String scope,
    Map<String, String> store,
    String key,
    String label, {
    bool date = false,
    bool numeric = false,
    List<String> options = const <String>[],
  }) => _fieldWidget(
    scope,
    store,
    LeaseFieldSpec(
      key,
      label,
      date: date,
      numeric: numeric,
      options: options,
    ),
  );

  /// التذكير: قائمة بمُدد ثابتة أو مخصص — لا يظهر في العقد.
  Widget _reminderField(String key, String label) {
    final store = _data.license;
    final current = store[key];
    return _labeled(
      label,
      DropdownButtonFormField<String>(
        initialValue: current != null &&
                LeaseContractData.activityReminders.contains(current)
            ? current
            : null,
        isExpanded: true,
        decoration: _decoration(label),
        hint: const Text('اختر', style: TextStyle(fontSize: 12)),
        items: [
          for (final option in LeaseContractData.activityReminders)
            DropdownMenuItem<String>(
              value: option,
              child: Text(option, style: const TextStyle(fontSize: 12)),
            ),
        ],
        onChanged: (value) => setState(() => store[key] = value ?? ''),
      ),
      note: 'لا يظهر في العقد',
    );
  }

  /// عدد الأيام للتذكير المخصص — يظهر حين يُختار «مخصص».
  Widget? _customDays(String choiceKey, String daysKey) =>
      (_data.license[choiceKey] ?? '') == 'مخصص'
      ? _act(
          'license',
          _data.license,
          daysKey,
          'عدد الأيام قبل الانتهاء',
          numeric: true,
        )
      : null;

  Widget _activityContractCard() {
    final c = _data.contract;
    return _activityCard(
      title: 'بيانات عقد الإيجار',
      icon: Icons.assignment_rounded,
      children: [
        // الرقمان جنب بعض (تلقائيان)، وحُذف «تصنيف المستأجر».
        _pair(
          _act('contract', c, LeaseContractData.kNewNo, 'رقم العقد الجديد'),
          _act('contract', c, LeaseContractData.kOldNo, 'رقم العقد المنتهي'),
        ),
        _pair(
          _act(
            'contract',
            c,
            LeaseContractData.kTermMode,
            'نمط مدة الإيجار',
            options: LeaseContractData.termModes,
          ),
          _act(
            'contract',
            c,
            LeaseContractData.kPurpose,
            'الغرض من الإيجار',
            options: LeaseContractData.purposes,
          ),
        ),
        _pair(
          _act(
            'contract',
            c,
            LeaseContractData.kStartDate,
            'تاريخ بداية العقد',
            date: true,
          ),
          _act(
            'contract',
            c,
            LeaseContractData.kEndDate,
            'تاريخ نهاية العقد',
            date: true,
          ),
        ),
        _pair(
          _reminderField(LeaseContractData.kLeaseReminder, 'التذكير'),
          _customDays(
            LeaseContractData.kLeaseReminder,
            LeaseContractData.kLeaseReminderDays,
          ),
        ),
      ],
    );
  }

  Widget _activityLicenseCard() {
    final l = _data.license;
    final classes = <String>[
      ...widget.activityClassOptions,
      // تصنيف محفوظ لم يعد في القائمة يبقى ظاهرًا.
      if ((l[LeaseContractData.kActivityClass] ?? '').isNotEmpty &&
          !widget.activityClassOptions.contains(
            l[LeaseContractData.kActivityClass],
          ))
        l[LeaseContractData.kActivityClass]!,
    ];
    final customDays = _customDays(
      LeaseContractData.kLicenseReminder,
      LeaseContractData.kLicenseReminderDays,
    );
    return _activityCard(
      title: 'بيانات الرخصة',
      icon: Icons.verified_rounded,
      children: [
        _act(
          'license',
          l,
          LeaseContractData.kTradeName,
          'الاسم التجاري',
        ),
        _act(
          'license',
          l,
          LeaseContractData.kActivityLocation,
          'موقع النشاط',
        ),
        _pair(
          _act(
            'license',
            l,
            LeaseContractData.kActivityClass,
            'تصنيف النشاط',
            options: classes,
          ),
          _act(
            'license',
            l,
            LeaseContractData.kLegalForm,
            'الشكل القانوني',
            options: LeaseContractData.legalForms,
          ),
        ),
        _pair(
          _act('license', l, LeaseContractData.kLicenseNo, 'رقم الرخصة التجارية'),
          _act(
            'license',
            l,
            LeaseContractData.kLicenseIssue,
            'تاريخ الإصدار',
            date: true,
          ),
        ),
        _pair(
          _act(
            'license',
            l,
            LeaseContractData.kLicenseEnd,
            'تاريخ الانتهاء',
            date: true,
          ),
          _reminderField(LeaseContractData.kLicenseReminder, 'التذكير'),
        ),
        if (customDays != null) _pair(null, customDays),
        _pair(
          _act('license', l, LeaseContractData.kChamber, 'عضوية الغرفة'),
          _act(
            'license',
            l,
            LeaseContractData.kLicenseClass,
            'فئة الرخصة',
            options: LeaseContractData.licenseClasses,
          ),
        ),
        _labeled(
          'الأنشطة التجارية',
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _activityLines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.body,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _activityLines[i],
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: AppTheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rIcon,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _activityLines.add(TextEditingController()),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text(
                      'المزيد',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _pair(
          _act(
            'license',
            l,
            LeaseContractData.kCapital,
            'رأس المال',
            numeric: true,
          ),
          null,
        ),
      ],
    );
  }

  Widget _pickButton(VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.goldDark,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
      ),
      icon: const Icon(Icons.person_search_rounded, size: 17),
      label: const Text(
        'جلب من الأفراد',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _pickFromDirectory(
    String scope,
    Map<String, String> store,
    String nameKey,
  ) async {
    final entries = await PeopleDirectoryStore.load();
    if (!mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد أفراد أو جهات مسجّلة بعد'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var query = '';
    final picked = await showModalBottomSheet<PeopleDirectoryEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final filtered = entries
                .where(
                  (entry) => query.trim().isEmpty ||
                      entry.fullName.contains(query.trim()) ||
                      entry.categoryName.contains(query.trim()),
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
                      'اختر من الأفراد والجهات',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      textAlign: AppTr.alignEnd,
                      style: const TextStyle(fontSize: 12),
                      decoration: _decoration('ابحث بالاسم أو التصنيف'),
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 320,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppTheme.line),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final phone = entry.firstOf(
                            const ['رقم الجوال', 'رقم الهاتف'],
                          );
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: AppIconTile(
                              icon: entry.isEntity
                                  ? Icons.apartment_rounded
                                  : Icons.person_rounded,
                              color: AppTheme.brand,
                              size: AppTheme.iconTileSmall,
                            ),
                            title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              entry.fullName,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.title,
                              ),
                            )),
                            subtitle: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                              phone.isEmpty
                                  ? entry.categoryName
                                  : '${entry.categoryName} · $phone',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.muted,
                              ),
                            )),
                            onTap: () =>
                                Navigator.of(sheetContext).pop(entry),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      store[nameKey] = picked.fullName;
      picked.details.forEach((key, value) {
        if (value.trim().isEmpty) return;
        store[key] = value.trim();
      });
      // حقل هاتف واحد: «رقم الجوال» المنقول يصبح «رقم الهاتف».
      if (scope == 'lessor' || scope == 'tenant') {
        LeaseContractData.mergeMobileIntoPhone(store);
      }
      // الحقول المعروضة عبر متحكمات نصية تحتاج تحديثًا مباشرًا.
      _controllers.forEach((id, controller) {
        if (!id.startsWith('$scope.')) return;
        final key = id.substring(scope.length + 1);
        final value = store[key];
        if (value != null && controller.text != value) {
          controller.text = value;
        }
      });
    });
  }

  /// مفتاح داخلي يخبر [_rowsCard] أن يفتح سطرًا جديدًا بعد هذا.
  ///
  /// لا يُخزَّن: يُقرأ ثم يُحذف فورًا، فلا يظهر في العقد ولا في المشاركة.
  static const _kAddAnother = '__another__';

  /// ما يمنع حفظ السطر، أو `null` إن كان سليمًا.
  ///
  /// الدفعة والرسم كلاهما مبلغ مستحق: بلا قيمة لا معنى لتسجيله، وبلا اسم
  /// لا يُعرف في كشف الحساب أيّهما هو.
  String? _rowProblem(
    List<LeaseFieldSpec> fields,
    Map<String, String> row,
  ) {
    final keys = fields.map((spec) => spec.key).toSet();
    if (keys.contains(LeaseContractData.kPaymentFee) &&
        (row[LeaseContractData.kPaymentFee] ?? '').trim().isEmpty) {
      return 'اكتب اسم الدفعة أولًا.';
    }
    for (final key in [
      LeaseContractData.kPaymentAmount,
      LeaseContractData.kAdminFeeAmount,
      LeaseContractData.kDepositAmount,
    ]) {
      if (!keys.contains(key)) continue;
      final raw = (row[key] ?? '').trim().replaceAll(',', '');
      final value = double.tryParse(raw) ?? 0;
      if (value <= 0) return 'أدخل مبلغًا أكبر من صفر في «$key».';
    }
    // تاريخ الاستحقاق إلزامي في الدفعة والرسم (مع الشيك تاريخ الشيك هو
    // الاستحقاق).
    if (keys.contains(LeaseContractData.kPaymentDue) &&
        (row[LeaseContractData.kCollectMethod] ?? '').trim() != 'شيك' &&
        (row[LeaseContractData.kPaymentDue] ?? '').trim().isEmpty) {
      return 'اختر تاريخ الاستحقاق.';
    }
    // الدفع بشيك: رقم الشيك وبنكه إلزاميان، وتاريخه ورقم الحساب في
    // الدفعات (التأمين بشيك بلا تاريخ: مجرد ضمان).
    if ((row[LeaseContractData.kCollectMethod] ?? '').trim() == 'شيك') {
      final deposit = keys.contains(LeaseContractData.kDepositAmount);
      String v(String key) => (row[key] ?? '').trim();
      if (keys.contains(LeaseContractData.kPaymentCheque) &&
          v(LeaseContractData.kPaymentCheque).isEmpty) {
        return 'اكتب رقم الشيك.';
      }
      if (!deposit &&
          keys.contains(LeaseContractData.kPaymentChequeDate) &&
          v(LeaseContractData.kPaymentChequeDate).isEmpty) {
        return 'اختر تاريخ الشيك.';
      }
      if (keys.contains(LeaseContractData.kPaymentBank) &&
          v(LeaseContractData.kPaymentBank).isEmpty) {
        return 'اكتب اسم البنك.';
      }
      if (keys.contains(LeaseContractData.kBankAccount) &&
          v(LeaseContractData.kBankAccount).isEmpty) {
        return 'اكتب رقم الحساب.';
      }
    }
    return null;
  }

  /// «شيك»: تاريخ الشيك هو تاريخ الاستحقاق (حقل الاستحقاق مخفي معه)،
  /// فيُنسخ إليه لتبقى التذكيرات وجدول الدفعات على تاريخ صحيح.
  static void _syncChequeDue(Map<String, String> row) {
    if ((row[LeaseContractData.kCollectMethod] ?? '').trim() != 'شيك') return;
    // التأمين بشيك مجرد ضمان: لا «تاريخ تحصيل» له.
    if (row.containsKey(LeaseContractData.kDepositAmount)) {
      row.remove('تاريخ تحصيل التأمين');
    }
    final cheque = (row[LeaseContractData.kPaymentChequeDate] ?? '').trim();
    final due = (row[LeaseContractData.kPaymentDue] ?? '').trim();
    if (cheque.isNotEmpty) {
      row[LeaseContractData.kPaymentDue] = cheque;
    } else if (due.isNotEmpty) {
      row[LeaseContractData.kPaymentChequeDate] = due;
    }
  }

  /// عنوان نافذة الإضافة بترتيب السطر: «تسجيل الدفعة الثانية» مثلًا،
  /// فيُفهم بعد «حفظ وإضافة دفعة أخرى» أن السابقة حُفظت وهذه التالية.
  static ({String title, String note}) _sequenceTitle(
    String addLabel,
    int number,
  ) {
    const fem = [
      'الأولى', 'الثانية', 'الثالثة', 'الرابعة', 'الخامسة',
      'السادسة', 'السابعة', 'الثامنة', 'التاسعة', 'العاشرة',
    ];
    const masc = [
      'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس',
      'السادس', 'السابع', 'الثامن', 'التاسع', 'العاشر',
    ];
    final (noun, feminine) = switch (addLabel) {
      'تسجيل دفعة' => ('الدفعة', true),
      'تسجيل رسم إداري' => ('الرسم الإداري', false),
      'تسجيل تأمين' => ('التأمين', false),
      _ => ('', true),
    };
    if (noun.isEmpty) return (title: addLabel, note: '');
    String nth(int n) {
      final list = feminine ? fem : masc;
      return n >= 1 && n <= list.length ? list[n - 1] : 'رقم $n';
    }

    return (
      title: 'تسجيل $noun ${nth(number)}',
      note: number > 1 ? 'تم حفظ $noun ${nth(number - 1)} ✓' : '',
    );
  }

  Future<Map<String, String>?> _editRow(
    String title,
    List<LeaseFieldSpec> fields,
    Map<String, String>? initial, {
    String note = '',
  }) async {
    final row = Map<String, String>.from(initial ?? const <String, String>{});
    final controllers = <String, TextEditingController>{};
    for (final spec in fields) {
      if (spec.options.isEmpty && !spec.date) {
        controllers[spec.key] =
            TextEditingController(text: row[spec.key] ?? '');
      }
    }

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) {
        // خطأ التحقّق يبقى مكتوبًا تحت الزر حتى يُصحَّح، لا شريطًا عابرًا.
        var rowError = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Widget build(LeaseFieldSpec spec) {
              // اسم الدفعة صار حقلًا نصيًّا حرًّا، فلا رقّاقات ترقيم هنا
              // بعد اليوم — يسقط السطر إلى حقل النص في آخر هذا التابع.
              if (spec.options.isNotEmpty) {
                final current = row[spec.key];
                return DropdownButtonFormField<String>(
                  initialValue: current != null &&
                          spec.options.contains(current)
                      ? current
                      : null,
                  isExpanded: true,
                  decoration: _decoration(spec.label, sheet: true),
                  items: spec.options
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(
                            option,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setSheetState(() => row[spec.key] = value ?? ''),
                );
              }
              if (spec.date) {
                final raw = row[spec.key] ?? '';
                return InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: DateTime.tryParse(raw) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2070),
                    );
                    if (picked != null) {
                      setSheetState(() => row[spec.key] = _iso(picked));
                    }
                  },
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                  child: InputDecorator(
                    decoration: _decoration(spec.label, sheet: true).copyWith(
                      suffixIcon: _clearDateButton(
                        spec,
                        raw,
                        () => setSheetState(() => _clearDate(row, spec.key)),
                      ),
                    ),
                    child: Text(
                      raw.isEmpty ? 'غير محدد' : _pretty(raw),
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: raw.isEmpty ? AppTheme.muted : AppTheme.title,
                      ),
                    ),
                  ),
                );
              }
              return TextField(
                controller: controllers[spec.key],
                textAlign: AppTr.alignEnd,
                maxLines: spec.multiline ? 3 : 1,
                keyboardType: spec.numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                decoration: _decoration(spec.label, sheet: true),
              );
            }

            // حجم ثابت (نحو نصف الشاشة) لا يتمدد عند الكتابة: النافذة ترتفع
            // فوق لوحة المفاتيح بالحجم نفسه، والحقول تُمرَّر داخلها. كانت
            // ثلثي الشاشة، فلا تتسع فوق لوحة المفاتيح فتملأ الشاشة كلها.
            final media = MediaQuery.of(sheetContext);
            final keyboard = media.viewInsets.bottom;
            final room = media.size.height - keyboard - media.padding.top - 24;
            final preferred = media.size.height * 0.46;
            return Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: SizedBox(
              height: room < preferred ? room : preferred,
              child: Directionality(
              textDirection: AppTr.uiDir,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // العنوان وزر الإغلاق (X) للخروج بلا حفظ.
                      Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.title,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: AppTr.tr('إغلاق'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 22),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0E7161),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      for (final spec in fields)
                        // حقول الشيك لا معنى لها مع الكاش أو التحويل،
                        // فتظهر عند اختيار «شيك» وحده.
                        // وعدد أيام التذكير يظهر مع «مخصص» وحده.
                        if ((!spec.chequeOnly ||
                                (row[LeaseContractData.kCollectMethod] ??
                                        '') ==
                                    'شيك') &&
                            (!spec.hideForCheque ||
                                (row[LeaseContractData.kCollectMethod] ??
                                        '') !=
                                    'شيك') &&
                            (!spec.customReminderOnly ||
                                (row[LeaseContractData.kPaymentReminder] ??
                                        '') ==
                                    LeaseContractData.reminderCustom)) ...[
                          build(spec),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 4),
                      if (rowError.isNotEmpty) ...[
                        Text(
                          rowError,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.danger,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (fields.any(
                        (spec) => spec.key == LeaseContractData.kPaymentFee,
                      ))
                        OutlinedButton.icon(
                          onPressed: () {
                            controllers.forEach((key, controller) {
                              row[key] = controller.text.trim();
                            });
                            _syncChequeDue(row);
                            final problem = _rowProblem(fields, row);
                            if (problem != null) {
                              setSheetState(() => rowError = problem);
                              return;
                            }
                            if ((row[LeaseContractData.kPaymentStatus] ?? '')
                                .trim()
                                .isEmpty) {
                              row[LeaseContractData.kPaymentStatus] = 'مستحقة';
                            }
                            row[_kAddAnother] = '1';
                            Navigator.of(sheetContext).pop(row);
                          },
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text(
                            'حفظ وإضافة دفعة أخرى',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, height: 1.3),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          controllers.forEach((key, controller) {
                            row[key] = controller.text.trim();
                          });
                          _syncChequeDue(row);
                          final problem = _rowProblem(fields, row);
                          if (problem != null) {
                            // دفعة بلا مبلغ كانت تُحفظ وتدخل في العقد
                            // بصفر — فيُطبع عقد بدفعات لا قيمة لها،
                            // ويظهر «إجمالي الدفعات» أقلّ من الحقيقة.
                            setSheetState(() => rowError = problem);
                            return;
                          }
                          // كل دفعة تُسجَّل مستحقة؛ حالتها تتغيّر عند
                          // السداد لا عند كتابتها.
                          if (row.containsKey(
                                LeaseContractData.kPaymentAmount,
                              ) &&
                              (row[LeaseContractData.kPaymentStatus] ?? '')
                                  .trim()
                                  .isEmpty) {
                            row[LeaseContractData.kPaymentStatus] = 'مستحقة';
                          }
                          Navigator.of(sheetContext).pop(row);
                        },
                        child: const Text('حفظ'),
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

    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  /// مستطيل الضريبة: النسبة ومفتاح التفعيل **داخله** ليُعرف أن المفتاح
  /// للضريبة لا لشيء آخر. كان المفتاح ملقىً بجانب الحقل بلا عنوان.
  Widget _taxBox({
    required String rateKey,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rIcon),
        border: Border.all(
          color: enabled ? AppTheme.brand : Colors.transparent,
        ),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          const Icon(Icons.percent_rounded, size: 16, color: AppTheme.brand),
          const SizedBox(width: 6),
          const Text(
            'الضريبة',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(width: 10),
          if (enabled)
            SizedBox(
              width: 76,
              child: TextField(
                controller: _controllerFor('contract', _data.contract, rateKey),
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                onChanged: (value) {
                  _data.contract[rateKey] = value;
                  setState(() {});
                },
                // مستطيل أبيض ظاهر: يُعرف أنه مكان كتابة النسبة.
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0',
                  suffixText: '%',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.brand),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Switch.adaptive(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }

  /// مبلغ مشتق للقراءة فقط — لا يُكتب لأنه محسوب.
  Widget _derivedBox(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.field,
      borderRadius: BorderRadius.circular(AppTheme.rIcon),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.body,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppTheme.title,
          ),
        ),
      ],
    ),
  );

  /// رأس مستطيل الدفعات.
  ///
  /// قيمة العقد وعدد الدفعات **محسوبان** من الدفعات المسجَّلة: القيمة
  /// مجموعها والعدد عددها. كتابتهما يدويًا كانت تسمح بعقد قيمته لا تساوي
  /// مجموع دفعاته، وهو خطأ لا يُكتشف إلا متأخرًا.
  Widget _rentHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _taxBox(
            rateKey: LeaseContractData.kTaxRate,
            enabled: _data.rentTaxable,
            onToggle: (on) => setState(
              () => _data.contract[LeaseContractData.kRentTaxable] =
                  on ? 'نعم' : 'لا',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: _derivedBox(
                  'قيمة عقد الإيجار',
                  _data.contractValue.toStringAsFixed(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _derivedBox(
                  'عدد الدفعات',
                  '${_data.installmentsCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'القيمة والعدد يُحسبان تلقائيًا من الدفعات التي تسجّلها.',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.muted,
            ),
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }

  /// السطران اللذان يقرأهما الطرفان: بدون ضريبة، وبضريبة.
  Widget _netAndGross(double net, double tax) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _totalLine('الإجمالي بدون ضريبة', net, strong: tax <= 0),
      if (tax > 0) ...[
        _totalLine('الضريبة', tax),
        _totalLine('الإجمالي بضريبة', net + tax, strong: true),
      ],
    ],
  );

  /// سطر مبلغ داخل تذييل المستطيل.
  Widget _totalLine(String label, double value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          textDirection: AppTr.uiDir,
          children: [
            Expanded(
              child: Text(
                label,
                textAlign: AppTr.alignEnd,
                style: TextStyle(
                  fontSize: strong ? 12.5 : 11.5,
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                  color: AppTheme.body,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: strong ? 14 : 12.5,
                fontWeight: FontWeight.w900,
                color: strong ? AppTheme.brandDark : AppTheme.body,
              ),
            ),
          ],
        ),
      );

  Widget _rowsCard({
    required String title,
    required IconData icon,
    required List<Map<String, String>> rows,
    required List<LeaseFieldSpec> fields,
    required String addLabel,
    required String Function(Map<String, String> row) lineOne,
    required String Function(Map<String, String> row) lineTwo,
    String Function(Map<String, String> row)? lineThree,
    required double total,
    required String totalLabel,
    Widget? header,
    Widget? footer,
    bool hideTotal = false,
    String? bottomAddLabel,
    Future<bool> Function()? beforeAdd,
    Widget? headerAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              Icon(icon, size: 17, color: AppTheme.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              if (headerAction != null) headerAction,
              TextButton.icon(
                onPressed: () async {
                  if (beforeAdd != null && !await beforeAdd()) return;
                  // «حفظ وإضافة دفعة أخرى» يعيد فتح النافذة فورًا، فتُكتب
                  // سلسلة الدفعات كلها دون العودة إلى الصفحة بينها.
                  var again = true;
                  var saved = 0;
                  while (again && mounted) {
                    final seq = _sequenceTitle(addLabel, rows.length + 1);
                    final added = await _editRow(
                      seq.title,
                      fields,
                      null,
                      note: saved > 0 ? seq.note : '',
                    );
                    if (added == null) break;
                    saved++;
                    again = added.remove(_kAddAnother) != null;
                    setState(() => rows.add(added));
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.goldDark,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'إضافة',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.sMd),
          if (header != null) header,
          if (rows.isEmpty)
            const Text(
              'لا يوجد تسجيل بعد',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
            )
          else
            for (var index = 0; index < rows.length; index++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceInner,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                ),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    // رقم تسلسل السطر.
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppTheme.brandSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lineOne(rows[index]),
                            maxLines: 3,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            lineTwo(rows[index]),
                            maxLines: 4,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.body,
                            ),
                          ),
                          if (lineThree != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              lineThree(rows[index]),
                              maxLines: 3,
                              textAlign: AppTr.alignEnd,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('تعديل'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: AppTheme.brandMid,
                      onPressed: () async {
                        final edited =
                            await _editRow(addLabel, fields, rows[index]);
                        if (edited != null) {
                          // «حفظ وإضافة أخرى» لا معنى له أثناء التعديل:
                          // المفتاح يُنزع حتى لا يُخزَّن في السطر.
                          edited.remove(_kAddAnother);
                          setState(() => rows[index] = edited);
                        }
                      },
                    ),
                    IconButton(
                      tooltip: AppTr.tr('حذف'),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: AppTheme.danger,
                      onPressed: () => setState(() => rows.removeAt(index)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.brandSoft,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hideTotal) _totalLine(totalLabel, total, strong: true),
                if (footer != null) footer,
              ],
            ),
          ),
          if (bottomAddLabel != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                if (beforeAdd != null && !await beforeAdd()) return;
                var again = true;
                var saved = 0;
                while (again && mounted) {
                  final seq = _sequenceTitle(addLabel, rows.length + 1);
                  final added = await _editRow(
                    seq.title,
                    fields,
                    null,
                    note: saved > 0 ? seq.note : '',
                  );
                  if (added == null) break;
                  saved++;
                  again = added.remove(_kAddAnother) != null;
                  setState(() => rows.add(added));
                }
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                bottomAddLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// حارس واحد لكل مستطيل مبالغ: لا يُضاف بند قبل حسم الضريبة.
  ///
  /// • مفعّلة والنسبة فارغة ← رفض: نسبة صفر تعني بندًا بلا ضريبة وهو
  ///   عكس ما اختاره المستخدم، فالسكوت عنه يُنتج عقدًا خاطئًا.
  /// • مفعّلة والنسبة مكتوبة ← تأكيد بالنسبة قبل المتابعة.
  /// • مقفلة ← تنبيه أن البند سيُسجَّل بلا ضريبة، مع طريق التفعيل.
  Future<bool> _taxGate({
    required String label,
    required bool enabled,
    required double rate,
  }) async {
    if (enabled && rate <= 0) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اكتب نسبة الضريبة في مستطيل $label أولًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('تأكيد الضريبة'),
          content: Text(
            enabled
                ? 'سيُسجَّل البند بضريبة ${_rateText(rate)}%. هل تريد '
                      'المتابعة؟'
                : 'الضريبة غير مفعّلة، فسيُسجَّل البند بلا ضريبة. إن أردت '
                      'ضريبة فعّل خيار الضريبة في أعلى المستطيل.',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  /// توزيع تلقائي: الإجمالي وعدد الدفعات ودوريتها وتاريخ أولها، فتُكتب
  /// الدفعات متساوية (الفرق الناتج عن التقريب على آخر دفعة). بعدها تظهر
  /// في القائمة لتُراجَع ويُعدَّل أيٌّ منها بالقلم — واليدوي باقٍ كما هو.
  Future<void> _autoDistributePayments() async {
    if (!await _confirmRentTax() || !mounted) return;
    const periods = <String, int>{
      'شهري': 1,
      'كل شهرين': 2,
      'ربع سنوي': 3,
      'نصف سنوي': 6,
      'سنوي': 12,
    };
    const ordinals = [
      'الأولى', 'الثانية', 'الثالثة', 'الرابعة', 'الخامسة', 'السادسة',
      'السابعة', 'الثامنة', 'التاسعة', 'العاشرة', 'الحادية عشرة',
      'الثانية عشرة',
    ];
    final totalCtrl = TextEditingController(
      text: _data.contract[LeaseContractData.kValue] ?? '',
    );
    final countCtrl = TextEditingController(text: '12');
    var period = 'شهري';
    var method = 'كاش';
    var first = DateTime.tryParse(
          _data.contract[LeaseContractData.kStartDate] ?? '',
        ) ??
        DateTime.now();
    var error = '';

    final result = await showModalBottomSheet<List<Map<String, String>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final total = double.tryParse(
                totalCtrl.text.replaceAll(',', '').trim(),
              ) ??
              0;
          final count = int.tryParse(countCtrl.text.trim()) ?? 0;
          final each = count > 0 ? total / count : 0;
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'توزيع الدفعات تلقائيًا',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'اكتب الإجمالي وعدد الدفعات، ويوزّعها النظام بالتساوي '
                      'على التواريخ. بعدها راجعها وعدّل أيّ دفعة كما تريد.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: totalCtrl,
                      textAlign: AppTr.alignEnd,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setSheet(() {}),
                      decoration: _decoration('إجمالي مبلغ الإيجار'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: countCtrl,
                            textAlign: AppTr.alignEnd,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setSheet(() {}),
                            decoration: _decoration('عدد الدفعات'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: period,
                            isExpanded: true,
                            decoration: _decoration('كل دفعة'),
                            items: [
                              for (final option in periods.keys)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(option),
                                ),
                            ],
                            onChanged: (value) =>
                                setSheet(() => period = value ?? period),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: first,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2070),
                          helpText: AppTr.tr('تاريخ أول دفعة'),
                        );
                        if (picked != null) setSheet(() => first = picked);
                      },
                      child: InputDecorator(
                        decoration: _decoration('تاريخ أول دفعة'),
                        child: Text(
                          _pretty(_iso(first)),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      isExpanded: true,
                      decoration: _decoration('طريقة التحصيل'),
                      items: [
                        for (final option in LeaseContractData.collectMethods)
                          DropdownMenuItem(value: option, child: Text(option)),
                      ],
                      onChanged: (value) =>
                          setSheet(() => method = value ?? method),
                    ),
                    if (count > 0 && total > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '$count دفعات × ${each.toStringAsFixed(2)} — '
                        '${period == 'شهري' ? 'كل شهر' : period}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brand,
                        ),
                      ),
                    ],
                    if (_data.payments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'تنبيه: سيحلّ التوزيع محلّ الدفعات المسجلة '
                        '(${_data.payments.length}).',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.goldDark,
                        ),
                      ),
                    ],
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        error,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () {
                        if (total <= 0) {
                          setSheet(() => error = 'اكتب إجمالي المبلغ.');
                          return;
                        }
                        if (count < 1 || count > 120) {
                          setSheet(
                            () => error = 'عدد الدفعات من 1 إلى 120.',
                          );
                          return;
                        }
                        final step = periods[period]!;
                        final base =
                            (total / count * 100).floorToDouble() / 100;
                        final rows = <Map<String, String>>[];
                        for (var i = 0; i < count; i++) {
                          final monthIndex = first.month + i * step;
                          final year =
                              first.year + (monthIndex - 1) ~/ 12;
                          final month = (monthIndex - 1) % 12 + 1;
                          final lastDay = DateTime(year, month + 1, 0).day;
                          final day =
                              first.day > lastDay ? lastDay : first.day;
                          final amount = i == count - 1
                              ? total - base * (count - 1)
                              : base;
                          rows.add(<String, String>{
                            LeaseContractData.kPaymentFee: i < ordinals.length
                                ? 'الدفعة ${ordinals[i]}'
                                : 'الدفعة ${i + 1}',
                            LeaseContractData.kPaymentAmount:
                                amount.toStringAsFixed(2),
                            LeaseContractData.kPaymentDue:
                                _iso(DateTime(year, month, day)),
                            LeaseContractData.kCollectMethod: method,
                            LeaseContractData.kPaymentStatus: 'مستحقة',
                          });
                        }
                        Navigator.of(sheetContext).pop(rows);
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('توزيع الدفعات'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      totalCtrl.dispose();
      countCtrl.dispose();
    });
    if (result == null || !mounted) return;
    setState(() {
      _data.payments
        ..clear()
        ..addAll(result);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم توزيع ${result.length} دفعات بالتساوي — راجعها، وعدّل أيّ دفعة '
          'بالقلم بجانبها.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmRentTax() => _taxGate(
    label: 'مبالغ دفعات الإيجار',
    enabled: _data.rentTaxable,
    rate: _data.taxRate,
  );

  Future<bool> _confirmAdminFeeTax() => _taxGate(
    label: 'مبالغ رسوم إدارية',
    enabled: _data.adminFeesTaxable,
    rate: _data.adminFeesTaxRate,
  );

  String _rateText(double rate) =>
      rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2);

  /// الرسوم الإدارية تُدفع مرة واحدة عند التوقيع وتبقى خارج قيمة
  /// الإيجار: الإيجار مبلغ متكرر يُقسَّط على مدة العقد، والرسم حدث واحد
  /// لا يتكرر. ضمّه لقيمة الإيجار يفسد كل ما يُبنى عليها — الدفعات
  /// والعائد السنوي والتجديد. فلا خيار هنا؛ ما يُختار عند الحفظ هو
  /// أيُذكر في ورقة العقد أم لا، لا أيُضاف إلى الإيجار.
  Widget _adminFeesFooter() => const Padding(
    padding: EdgeInsets.only(top: 8),
    child: Text(
      'تُدفع مرة واحدة عند التوقيع، وخارج قيمة الإيجار — لأن الإيجار مبلغ '
      'متكرر يُقسَّط، والرسم حدث واحد لا يتكرر.',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
    ),
  );

  /// الملخص المالي: إجمالي العقد بحسب ما اختير أن يتضمّنه، بدون ضريبة
  /// وبضريبة. التأمين معروض خارج الإجمالي لأنه يُرد.
  Widget _financialSummaryCard() {
    // «محتوى العقد» يُختار في كل العقود (العقار والنشاط والمركبة).
    const showScope = true;
    final withFees = _data.contractIncludesAdminFees;
    String money(double value) => value.toStringAsFixed(2);
    Widget line(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: strong ? 13.5 : 12.5,
              fontWeight: FontWeight.w900,
              color: strong ? AppTheme.brandDark : AppTheme.title,
            ),
          ),
        ],
      ),
    );
    Widget column(String title, double net, double tax) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.brand,
              ),
            ),
            const Divider(height: 12, color: AppTheme.hairline),
            line(title == 'الرسوم الإدارية' ? 'قيمة الرسوم' : 'قيمة الدفعات',
                money(net)),
            line('قيمة الضريبة', money(tax)),
            line('الإجمالي', money(net + tax), strong: true),
          ],
        ),
      ),
    );
    Widget scopeOption(String option) {
      // لا اختيار افتراضي: حقل إلزامي يختاره المستخدم.
      final selected =
          (_data.contract[LeaseContractData.kContractScope] ?? '').trim() ==
          option;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          onTap: () => setState(
            () => _data.contract[LeaseContractData.kContractScope] = option,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(
                color: selected ? AppTheme.brand : AppTheme.line,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: selected ? AppTheme.brand : AppTheme.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    option,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppTheme.title : AppTheme.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.brandSoft,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              const Icon(
                Icons.calculate_rounded,
                size: 17,
                color: AppTheme.brand,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'الملخص المالي للعقد *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
            ],
          ),
          if (showScope) ...[
            const SizedBox(height: 10),
            const Text(
              'محتوى العقد *',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.body,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                scopeOption(LeaseContractData.scopePaymentsOnly),
                const SizedBox(width: 8),
                scopeOption(LeaseContractData.scopeWithAdminFees),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // عمودان: الدفعات الإيجارية | الرسوم الإدارية.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                'الدفعات الإيجارية',
                _data.paymentsTotal,
                _data.paymentsTax,
              ),
              if (withFees) ...[
                const SizedBox(width: 8),
                column(
                  'الرسوم الإدارية',
                  _data.adminFeesTotal,
                  _data.adminFeesTax,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppTheme.line),
          const SizedBox(height: 4),
          _totalLine('إجمالي المبلغ', _data.contractGrossTotal, strong: true),
          if (_data.depositsTotal > 0)
            _totalLine(
              'التأمين (مسترد، خارج الإجمالي)',
              _data.depositsTotal,
            ),
        ],
      ),
    );
  }

  /// خيارا الحفظ: بختم، بتوقيع، بكليهما، أو بلا شيء. يستعمل التوقيع
  /// والختم المحفوظين في إعدادات «التوقيع الإلكتروني والختم» فلا آلية
  /// موازية. يُرجع null إن ألغى المستخدم.
  /// نافذة واحدة قبل الحفظ: يختار «بتوقيع إلكتروني» و/أو «بختم إلكتروني»،
  /// أو «بدون توقيع ولا ختم»، ثم «تأكيد» أو «حفظ كمسودة».
  Future<({bool stamp, bool sign, bool draft})?> _askSignature() async {
    final strokes = await UserSignatureStore.load();
    final stampBytes = await UserStampStore.load();
    if (!mounted) return null;
    final hasSign = strokes.isNotEmpty;
    final hasStamp = stampBytes != null;
    var wantSign = hasSign;
    var wantStamp = hasStamp;
    var wantNone = !hasSign && !hasStamp;

    Widget option({
      required String title,
      required bool value,
      required bool enabled,
      required ValueChanged<bool> onChanged,
      String? note,
      required IconData icon,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: value ? AppTheme.brandSoft : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(
                color: value ? AppTheme.brand : AppTheme.line,
                width: value ? 1.4 : 1,
              ),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                Icon(
                  value
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 21,
                  color: !enabled
                      ? AppTheme.muted.withValues(alpha: 0.5)
                      : (value ? AppTheme.brand : AppTheme.muted),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: AppTheme.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note == null ? title : '$title ($note)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: enabled ? AppTheme.title : AppTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<({bool stamp, bool sign, bool draft})>(
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
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final chosen = wantSign || wantStamp || wantNone;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'كيف تريد حفظ العقد؟',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 12),
                    option(
                      title: 'بتوقيع إلكتروني',
                      note: hasSign ? null : 'غير مسجَّل في المزيد',
                      icon: Icons.draw_outlined,
                      value: wantSign,
                      enabled: hasSign,
                      onChanged: (v) => setSheetState(() {
                        wantSign = v;
                        if (v) wantNone = false;
                      }),
                    ),
                    option(
                      title: 'بختم إلكتروني',
                      note: hasStamp ? null : 'غير مسجَّل في المزيد',
                      icon: Icons.approval_outlined,
                      value: wantStamp,
                      enabled: hasStamp,
                      onChanged: (v) => setSheetState(() {
                        wantStamp = v;
                        if (v) wantNone = false;
                      }),
                    ),
                    option(
                      title: 'بدون توقيع ولا ختم',
                      icon: Icons.block_outlined,
                      value: wantNone,
                      enabled: true,
                      onChanged: (v) => setSheetState(() {
                        wantNone = v;
                        if (v) {
                          wantSign = false;
                          wantStamp = false;
                        }
                      }),
                    ),
                    if ((wantSign && hasSign) || (wantStamp && hasStamp)) ...[
                      const SizedBox(height: 2),
                      Container(
                        height: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.rInner),
                          border: Border.all(color: AppTheme.line),
                        ),
                        child: Row(
                          textDirection: AppTr.uiDir,
                          children: [
                            if (wantSign && hasSign)
                              Expanded(
                                child: CustomPaint(
                                  painter: UserSignaturePainter(strokes),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            if (wantStamp && stampBytes != null)
                              Expanded(
                                child: Image.memory(
                                  stampBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: chosen
                          ? () => Navigator.pop(sheetContext, (
                              stamp: wantStamp,
                              sign: wantSign,
                              draft: false,
                            ))
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('متابعة'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// مراجعة العقد كاملًا قبل التأكيد — النص نفسه الذي يُطبع ويُشارك،
  /// فما تراه هنا هو ما يُحفظ حرفيًا.
  Future<bool> _reviewBeforeSave({bool asDraft = false}) async {
    final draftNote = _data.missingRequired;
    final ok = await showModalBottomSheet<bool>(
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
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (sheetContext2, controller) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'مراجعة العقد قبل الحفظ',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ),
              // الدفعات أولًا وصريحة: هي ما يُراجَع فعلًا قبل التوقيع،
              // وكانت مدفونة وسط نصّ العقد الكامل أسفل الورقة.
              if (_data.payments.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الدفعات الإيجارية (${_data.payments.length})',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.brandDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final row in _data.payments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            [
                              row[LeaseContractData.kPaymentFee] ?? 'دفعة',
                              row[LeaseContractData.kPaymentAmount] ?? '0',
                              if ((row[LeaseContractData.kPaymentDue] ?? '')
                                  .isNotEmpty)
                                _pretty(row[LeaseContractData.kPaymentDue]!),
                              if ((row[LeaseContractData.kCollectMethod] ?? '')
                                  .isNotEmpty)
                                row[LeaseContractData.kCollectMethod]!,
                            ].join(' · '),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.6,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.body,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (draftNote.isNotEmpty || asDraft)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.goldSoft,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: Text(
                    draftNote.isEmpty
                        ? 'سيُحفظ العقد كمسودة كما اخترت.'
                        : 'سيُحفظ العقد كمسودة لوجود حقول إلزامية لم تُعبّأ: '
                              '${draftNote.join('، ')}.',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.goldDark,
                    ),
                  ),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Text(
                      _data.toShareText(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11.5, height: 1.8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                // نقص حقول (أو اختيار المسودة): «احفظ كمسودة» ظاهر،
                // و«تأكيد الحفظ» رمادي لا يُضغط حتى تكتمل الحقول.
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetContext2, false),
                        child: const Text(
                          'رجوع للتعديل',
                          maxLines: 3,
                        ),
                      ),
                    ),
                    if (draftNote.isNotEmpty || asDraft) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext2, true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.goldDark,
                            side: const BorderSide(color: AppTheme.goldDark),
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          child: const Text(
                            'احفظ كمسودة',
                            maxLines: 3,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: draftNote.isNotEmpty || asDraft
                            ? null
                            : () => Navigator.pop(sheetContext2, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          disabledBackgroundColor: const Color(0xFFD5DBDA),
                          disabledForegroundColor: const Color(0xFF8C9A97),
                        ),
                        child: const Text(
                          'تأكيد الحفظ',
                          maxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ok == true;
  }

  /// تذكير لكل دفعة اختير لها تذكير وتاريخ استحقاق — يظهر في التذكيرات
  /// قبل الاستحقاق بالمدة المختارة. الدفعة بلا تذكير يُزال تذكيرها.
  Future<void> _registerPaymentReminders(String tenantName) async {
    try {
      for (final row in _data.payments) {
        final rowId = (row[LeaseContractData.kRowId] ?? '').trim();
        if (rowId.isEmpty) continue;
        final id = 'lease_payment_$rowId';
        final days = LeaseContractData.reminderDaysOf(row);
        final due = DateTime.tryParse(
          (row[LeaseContractData.kPaymentDue] ?? '').trim(),
        );
        if (days <= 0 || due == null) {
          await AppRemindersStore.remove(id);
          continue;
        }
        final name = (row[LeaseContractData.kPaymentFee] ?? '').trim();
        await AppRemindersStore.upsert(
          AppReminder(
            id: id,
            title: [
              'استحقاق ${name.isEmpty ? 'دفعة إيجار' : name}',
              if (_subjectName.trim().isNotEmpty) _subjectName.trim(),
              if (tenantName.isNotEmpty) tenantName,
            ].join(' — '),
            module: 'العقارات',
            expiryDate: due,
            remindBeforeDays: days,
          ),
        );
      }
    } catch (_) {
      // فشل التذكير لا يُفشل حفظ العقد.
    }
  }

  /// أسماء الحقول الإلزامية الفارغة في عقد النشاط، مع اسم القسم.
  List<String> _activityMissing() {
    const sections = <String, String>{
      'contract': 'عقد الإيجار',
      'license': 'الرخصة',
      'lessor': 'المؤجر',
      'tenant': 'المستأجر',
    };
    final labels = <String, String>{
      LeaseContractData.kTermMode: 'نمط مدة الإيجار',
      LeaseContractData.kStartDate: 'تاريخ بداية العقد',
      LeaseContractData.kEndDate: 'تاريخ نهاية العقد',
      LeaseContractData.kTradeName: 'الاسم التجاري',
      LeaseContractData.kLicenseIssue: 'تاريخ الإصدار',
      LeaseContractData.kLicenseEnd: 'تاريخ الانتهاء',
      LeaseContractData.kName: 'الإسم',
      LeaseContractData.kPhone: 'رقم الهاتف',
    };
    final missing = <String>[];
    sections.forEach((scope, section) {
      final store = _storeOf(scope);
      if (store == null) return;
      for (final key in LeaseContractData.activityRequired[scope]!) {
        if ((store[key] ?? '').trim().isNotEmpty) continue;
        missing.add('${labels[key] ?? key} ($section)');
      }
    });
    return missing;
  }

  /// [asDraft]: زر «حفظ كمسودة» أسفل الصفحة — بلا توقيع ولا ختم، وبلا
  /// اشتراط الحقول الإلزامية؛ يُراجَع ثم يُحفظ مسودة تُكمَل لاحقًا.
  Future<void> _save({bool asDraft = false}) async {
    _commitControllers();
    // نهاية العقد قبل بدايته لا تُقبل (ولا في المسودة).
    final startAt = DateTime.tryParse(
      (_data.contract[LeaseContractData.kStartDate] ?? '').trim(),
    );
    final endAt = DateTime.tryParse(
      (_data.contract[LeaseContractData.kEndDate] ?? '').trim(),
    );
    if (startAt != null && endAt != null && endAt.isBefore(startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تاريخ نهاية العقد قبل تاريخ بدايته — صحّحه أولًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (widget.isMultiUnit && widget.existing == null && _chosenUnits.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر وحدتين على الأقل في «اختر الوحدات المشمولة»'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (widget.isMultiUnit && widget.existing == null) {
      final names = _chosenList.map((u) => u.name).join('، ');
      _data.contract[LeaseContractData.kMultiUnits] = names;
      if ((_data.property['بيانات العين المؤجرة'] ?? '').trim().isEmpty) {
        _data.property['بيانات العين المؤجرة'] = names;
      }
    }
    // نشاط جديد: الاسم التجاري هو اسم النشاط، فلا يُحفظ بدونه.
    if (widget.forActivity && widget.assetId.isEmpty && _tradeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اكتب الاسم التجاري في «بيانات الرخصة»'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // صاحب النشاط هو المستأجر.
    if (widget.forActivity &&
        (_data.tenant[LeaseContractData.kName] ?? '').trim().isEmpty &&
        _tradeName.isNotEmpty) {
      _data.tenant[LeaseContractData.kName] = _tradeName;
    }
    // عقد النشاط: الحقول الإلزامية قبل الحفظ.
    if (widget.forActivity && !asDraft) {
      final missing = _activityMissing();
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('أكمل الحقول الإلزامية: ${missing.join('، ')}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    // قيمة العقد وعدد الدفعات مشتقّان — يُكتبان قبل الحفظ ليظهرا في
    // العقد المطبوع وفي سجلّ الوحدة.
    _data.syncDerivedContractValues();

    // التوقيع والختم أولًا، فيظهران في نص المراجعة.
    final marks = asDraft
        ? (stamp: false, sign: false, draft: true)
        : await _askSignature();
    if (marks == null || !mounted) return;
    if (marks.sign || marks.stamp) {
      final now = DateTime.now();
      _data.contract[LeaseContractData.kSignedAt] =
          '${now.day}/${now.month}/${now.year}';
      _data.contract[LeaseContractData.kSignedBy] = [
        if (marks.sign) 'توقيع',
        if (marks.stamp) 'ختم',
      ].join(' و');
    } else {
      _data.contract.remove(LeaseContractData.kSignedAt);
      _data.contract.remove(LeaseContractData.kSignedBy);
    }

    // مراجعة ورقة العقد كاملة ثم تأكيد.
    if (!await _reviewBeforeSave(asDraft: marks.draft) || !mounted) return;

    // العقد الناقص لا يُرفض: يُحفظ مسودة فلا يضيع ما أُدخل، ويُعلَم
    // المستخدم بذلك. كان نقص اسم المستأجر يُسقط كل العمل.
    // مسودة: باختيار «حفظ كمسودة»، أو لنقص حقل إلزامي.
    final draft = _data.isDraft || marks.draft;
    final tenantName = (_data.tenant[LeaseContractData.kName] ?? '').trim();
    // لكل سطر معرّف قبل الحفظ، فيرتبط بسجلّه في جدول الدفعات ولا يتكرر.
    _data.ensureRowIds();

    setState(() => _saving = true);
    try {
      final start = DateTime.tryParse(
        _data.contract[LeaseContractData.kStartDate] ?? '',
      );
      final end = DateTime.tryParse(
        _data.contract[LeaseContractData.kEndDate] ?? '',
      );
      final value = double.tryParse(
            (_data.contract[LeaseContractData.kValue] ?? '')
                .replaceAll(',', '')
                .trim(),
          ) ??
          _data.paymentsTotal;
      final installments =
          int.tryParse(_data.contract[LeaseContractData.kInstallments] ?? '') ??
              _data.payments.length;
      final cycle = switch (installments) {
        1 => 'سنوي',
        2 => 'نصف سنوي',
        4 => 'ربع سنوي',
        12 => 'شهري',
        _ => widget.existing?.paymentCycle ?? 'سنوي',
      };

      // نشاط جديد: يُنشأ النشاط أولًا ثم يُربط به العقد.
      var assetId = widget.assetId;
      if (assetId.isEmpty) {
        assetId = _createdAssetId ?? '';
        if (assetId.isEmpty && widget.createActivity != null) {
          assetId = await widget.createActivity!(_data) ?? '';
          if (assetId.isNotEmpty) _createdAssetId = assetId;
        }
        if (assetId.isEmpty) {
          throw StateError('تعذّر إنشاء النشاط التجاري');
        }
      }

      final record = PropertyUnitContractRecord(
        id: widget.existing?.id ?? _savedContractId,
        assetId: assetId,
        unitKey: widget.unitKey,
        unitName: _subjectName,
        tenantName: tenantName.isEmpty ? 'بلا اسم' : tenantName,
        tenantPhone: _data.tenant[LeaseContractData.kPhone]?.trim().isNotEmpty ==
                true
            ? _data.tenant[LeaseContractData.kPhone]!.trim()
            : _data.tenant[LeaseContractData.kMobile]?.trim(),
        leaseType: widget.existing?.leaseType ?? widget.leaseType,
        groupKey: widget.existing?.groupKey ?? widget.groupKey,
        annualRent: value,
        paymentCycle: cycle,
        startDate: start,
        endDate: end,
        status: draft
            ? PropertyUnitContractRecord.statusPending
            : PropertyUnitContractRecord.statusActive,
        notes: _data.encode(),
      );

      final PropertyUnitContractRecord saved;
      if (widget.isMultiUnit && widget.existing == null) {
        // سجل لكل وحدة مختارة بمفتاح مجموعة واحد. الأولى تحمل الدفعات
        // والرسوم والتأمين، والبقية نسخة العقد بلا مبالغ (فلا تتكرر
        // الدفعات)، والإيجار السنوي موزّع بالتساوي.
        final chosen = _chosenList;
        // مفتاح المجموعة نفسه في إعادة الحفظ بعد فشل.
        final groupKey = widget.groupKey ??
            (_savedGroupKey ??= 'grp_${DateTime.now().microsecondsSinceEpoch}');
        final share = value / chosen.length;
        PropertyUnitContractRecord? primary;
        for (var i = 0; i < chosen.length; i++) {
          final unit = chosen[i];
          var notes = record.notes;
          if (i > 0) {
            final copy = LeaseContractData.decode(_data.encode());
            copy.payments.clear();
            copy.adminFees.clear();
            copy.deposits.clear();
            copy.contract[LeaseContractData.kMultiPrimary] = chosen.first.name;
            notes = copy.encode();
          }
          final one = await widget.repository.upsertUnitContract(
            record.copyWith(
              // ما حُفظ من هذه الوحدات قبل الفشل يُحدَّث لا يُكرَّر.
              id: _savedUnitContractIds[unit.key],
              unitKey: unit.key,
              unitName: unit.name,
              leaseType: PropertyUnitContractRecord.leaseTypeMultiUnit,
              groupKey: groupKey,
              annualRent: share,
              notes: notes,
            ),
          );
          if (one.id != null) _savedUnitContractIds[unit.key] = one.id!;
          primary ??= one;
        }
        saved = primary!;
      } else {
        saved = await widget.repository.upsertUnitContract(record);
        if (saved.id != null) _savedContractId = saved.id;
      }
      await _registerPaymentReminders(tenantName);
      // الدفعات والرسوم والتأمين تصير سجلات قابلة للتحصيل. كانت تبقى نصًّا
      // داخل العقد وحده، فتظهر الوحدة بلا دفعات وكل إجمالي صفرًا.
      // فشل التوليد لا يُفشل حفظ العقد: العقد محفوظ، والتوليد يُعاد
      // تلقائيًا عند فتح الوحدة.
      try {
        await syncLeasePaymentRecords(
          repository: widget.repository,
          contract: saved,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'حُفظ العقد، وتعذّر توليد الدفعات الآن ($error) — '
                'ستُولَّد عند فتح الوحدة.',
              ),
              duration: const Duration(seconds: 8),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      await _syncPeopleDirectory();
      if (!mounted) return;
      if (draft) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _data.missingRequired.isEmpty
                  ? 'حُفظ العقد كمسودة.'
                  : 'حُفظ العقد كمسودة — ينقصه: '
                        '${_data.missingRequired.join('، ')}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذّر حفظ العقد: $error'),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// كل من يُسجَّل في العقد يذهب إلى «الأفراد والجهات» تلقائيًا.
  Future<void> _syncPeopleDirectory() async {
    final source = widget.forActivity
        ? 'عقد إيجار النشاط — $_subjectName'
        : 'عقد إيجار ${widget.unitName} — ${widget.propertyTitle}';

    final lessorName = (_data.lessor[LeaseContractData.kName] ?? '').trim();
    if (lessorName.isNotEmpty) {
      final details = Map<String, String>.from(_data.lessor)
        ..remove(LeaseContractData.kName);
      await PeopleDirectoryStore.upsert(
        fullName: lessorName,
        typeKey: PeopleDirectoryStore.typeLandlord,
        categoryName: PeopleDirectoryStore.categoryLandlord,
        roleTitle: 'مؤجر',
        details: details,
        sourceNote: source,
      );
    }

    final tenantName = (_data.tenant[LeaseContractData.kName] ?? '').trim();
    if (tenantName.isNotEmpty) {
      final details = Map<String, String>.from(_data.tenant)
        ..remove(LeaseContractData.kName);
      // مستأجر برخصة تجارية واسم تجاري = جهة/شركة لا فرد.
      final isCompany = (_data.tenant['رخصة رقم'] ?? '').trim().isNotEmpty ||
          (_data.tenant['الاسم التجاري'] ?? '').trim().isNotEmpty;
      await PeopleDirectoryStore.upsert(
        fullName: tenantName,
        typeKey: isCompany
            ? PeopleDirectoryStore.typeCompany
            : PeopleDirectoryStore.typeTenant,
        categoryName: isCompany
            ? PeopleDirectoryStore.categoryCompany
            : PeopleDirectoryStore.categoryTenant,
        roleTitle: 'مستأجر',
        details: details,
        sourceNote: source,
      );
    }

    final repName =
        (_data.representative[LeaseContractData.kRepName] ?? '').trim();
    if (repName.isNotEmpty) {
      final details = Map<String, String>.from(_data.representative)
        ..remove(LeaseContractData.kRepName);
      if (tenantName.isNotEmpty) details['يمثّل'] = tenantName;
      await PeopleDirectoryStore.upsert(
        fullName: repName,
        typeKey: PeopleDirectoryStore.typeRepresentative,
        categoryName: PeopleDirectoryStore.categoryRepresentative,
        roleTitle: 'ممثل مستأجر',
        details: details,
        sourceNote: source,
      );
    }
  }

  /// المستندات المرفقة بالعقد (أسماء من «مستندات» العقار).
  List<String> get _attachedDocs => [
    for (final name
        in (_data.contract[LeaseContractData.kAttachedDocs] ?? '').split('\n'))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  /// مستند جديد للعقد: يُختار من الملفات أو الاستوديو أو الكاميرا، يُسمّى،
  /// ويُحفظ في «المستندات» للعقار نفسه. يعيد اسمه أو null.
  Future<String?> _addNewContractDocument(BuildContext sheetContext) async {
    final path = await DocumentStore.pickAndStore(context: sheetContext);
    if (path == null || !sheetContext.mounted) return null;
    var suggested = DocumentStore.fileName(path)
        .replaceFirst(RegExp(r'^[0-9]+_'), '');
    final dot = suggested.lastIndexOf('.');
    if (dot > 0) suggested = suggested.substring(0, dot);
    final nameCtrl = TextEditingController(text: suggested);
    final name = await showDialog<String>(
      context: sheetContext,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('اسم المستند'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textAlign: AppTr.alignEnd,
            decoration: _decoration('مثال: شروط العقد', sheet: true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, nameCtrl.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), nameCtrl.dispose);
    final finalName = (name ?? '').trim();
    if (finalName.isEmpty) return null;
    try {
      await widget.repository.upsertEntry(
        ProjectAssetEntryRecord(
          assetId: widget.assetId,
          kind: ProjectAssetEntryRecord.kindDocument,
          data: <String, String>{
            'اسم المستند': finalName,
            'نوع المستند': 'عقود',
            DocumentStore.kFileField: path,
          },
        ),
      );
    } catch (_) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ المستند. تحقّق من الاتصال وحاول مرة أخرى.'),
          ),
        );
      }
      return null;
    }
    if (sheetContext.mounted) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('أُضيف «$finalName» إلى المستندات'),
        ),
      );
    }
    return finalName;
  }

  /// نصف صفحة بمستندات العقار: يُختار منها ما يُرفق بالعقد (شروطك مثلًا).
  Future<void> _pickContractDocuments() async {
    final selected = _attachedDocs.toSet();
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) {
        final docs = widget.repository.fetchEntries(widget.assetId);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => Directionality(
            textDirection: AppTr.uiDir,
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      textDirection: AppTr.uiDir,
                      children: [
                        Expanded(
                          child: Text(
                            _docsLabel,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppTr.tr('إغلاق'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded, size: 22),
                        ),
                      ],
                    ),
                    const Text(
                      'اختر من مستندات العقار، أو أضف مستندًا جديدًا من '
                      'الملفات أو الاستوديو أو التصوير',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // مستند جديد: من الملفات أو الاستوديو أو الكاميرا، يُحفظ
                    // في «المستندات» ويُختار للإرفاق مباشرة.
                    OutlinedButton.icon(
                      onPressed: () async {
                        final name = await _addNewContractDocument(
                          sheetContext,
                        );
                        if (name != null && sheetContext.mounted) {
                          setSheetState(() => selected.add(name));
                        }
                      },
                      icon: const Icon(Icons.note_add_outlined, size: 19),
                      label: const Text('إضافة مستند (ملف / استوديو / تصوير)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<ProjectAssetEntryRecord>>(
                        future: docs,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final names = <String>[
                            for (final entry
                                in snapshot.data ??
                                    const <ProjectAssetEntryRecord>[])
                              if (entry.kind ==
                                  ProjectAssetEntryRecord.kindDocument)
                                if ((entry.data['اسم المستند'] ??
                                        entry.data['نوع المستند'] ??
                                        '')
                                    .trim()
                                    .isNotEmpty)
                                  (entry.data['اسم المستند'] ??
                                          entry.data['نوع المستند'] ??
                                          '')
                                      .trim(),
                          ];
                          // ما أُرفق سابقًا يبقى ظاهرًا ولو تغيّر اسمه.
                          for (final name in selected) {
                            if (!names.contains(name)) names.add(name);
                          }
                          if (names.isEmpty) {
                            return const Center(
                              child: Text(
                                'لا توجد مستندات بعد — أضف مستند شروطك في '
                                '«المستندات» ثم ارفقه هنا',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.muted,
                                ),
                              ),
                            );
                          }
                          return ListView(
                            children: [
                              for (final name in names)
                                CheckboxListTile(
                                  value: selected.contains(name),
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    name,
                                    textAlign: AppTr.alignEnd,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  onChanged: (on) => setSheetState(() {
                                    if (on == true) {
                                      selected.add(name);
                                    } else {
                                      selected.remove(name);
                                    }
                                  }),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(selected),
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: const Text('إرفاق بالعقد'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.isEmpty) {
        _data.contract.remove(LeaseContractData.kAttachedDocs);
      } else {
        _data.contract[LeaseContractData.kAttachedDocs] = picked.join('\n');
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          picked.isEmpty
              ? 'لا مستندات مرفقة بالعقد'
              : 'تم إرفاق ${picked.length} مستند بالعقد',
        ),
      ),
    );
  }

  /// مركبة بحرية؟ (من تصنيفها، وإلا من عنوان العقد).
  bool get _isMarineVehicle =>
      (widget.propertyMeta['تصنيف المركبة'] ?? '').trim() == 'مركبات بحرية' ||
      widget.title.contains('بحري');

  /// «المركبة البحرية» / «المركبة البرية».
  String get _vehicleWord =>
      _isMarineVehicle ? 'المركبة البحرية' : 'المركبة البرية';

  /// عنوان مستندات العين: العقار، أو المركبة البحرية/البرية.
  String get _docsLabel =>
      widget.isVehicle ? 'مستندات $_vehicleWord' : 'مستندات العقار';

  /// «بسائق» / «بدون سائق» — قائمة صغيرة بجانب عنوان بيانات العقد.
  Widget _driverPicker() {
    final current = (_data.contract[LeaseContractData.kDriver] ?? '').trim();
    return PopupMenuButton<String>(
      tooltip: AppTr.tr('بسائق أو بدون سائق'),
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          setState(() => _data.contract[LeaseContractData.kDriver] = value),
      itemBuilder: (context) => [
        for (final option in LeaseContractData.driverOptions)
          PopupMenuItem<String>(
            value: option,
            child: Text(
              option,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight:
                    option == current ? FontWeight.w900 : FontWeight.w600,
                color: option == current ? AppTheme.brand : AppTheme.title,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.brandSoft,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              current == 'بدون سائق'
                  ? Icons.no_accounts_outlined
                  : Icons.person_pin_outlined,
              size: 16,
              color: AppTheme.brand,
            ),
            const SizedBox(width: 4),
            Text(
              current.isEmpty ? 'بسائق أو بدون سائق *' : current,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.brand,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: AppTheme.brand,
            ),
          ],
        ),
      ),
    );
  }

  /// زر مستندات العقار تحت ملاحظات العقد، وملاحظة صغيرة تحته.
  Widget _contractDocumentsBox() {
    final attached = _attachedDocs;
    return Container(
      margin: const EdgeInsets.only(top: AppTheme.cardGap),
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickContractDocuments,
            icon: const Icon(Icons.folder_open_rounded, size: 19),
            label: Text(
              attached.isEmpty
                  ? AppTr.tr(_docsLabel)
                  : '${AppTr.tr(_docsLabel)} (${attached.length})',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أرفق مستند شروطك من $_docsLabel، أو من ملف أو الاستوديو أو '
            'التصوير',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
          if (attached.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final name in attached)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      size: 15,
                      color: AppTheme.brandMid,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        textAlign: AppTr.alignEnd,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.title,
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

  /// عنوان العقد: «عقد مستثمر» إن اختير «مستثمر» في عقد العقار.
  String get _shownTitle =>
      !widget.isVehicle && !widget.forActivity && _data.isInvestor
      ? 'عقد مستثمر'
      : widget.title;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: Text(_shownTitle),
          actions: [
            // طباعة العقد بكل إدخالاته على ورقة A4.
            IconButton(
              tooltip: AppTr.tr('طباعة العقد'),
              icon: const Icon(Icons.print_rounded, size: 21),
              onPressed: () {
                _commitControllers();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TemplatePrintScreen(
                      title: _shownTitle,
                      fileName: _shownTitle,
                      buildPdf: (format) => buildLeasePdf(
                        _data,
                        format,
                        title: _shownTitle,
                        activity: widget.forActivity,
                        assetMeta: widget.propertyMeta,
                      ),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: AppTr.tr('مشاركة العقد'),
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              // المشاركة بنموذج العقد المعتمد كملف PDF (لا نصًّا) — نفس ما
              // في معاينة الطباعة، على أندرويد والآيفون.
              onPressed: () async {
                _commitControllers();
                try {
                  final bytes = await buildLeasePdf(
                    _data,
                    PdfPageFormat.a4,
                    title: _shownTitle,
                    activity: widget.forActivity,
                    assetMeta: widget.propertyMeta,
                  );
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: '$_shownTitle.pdf',
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعذّرت مشاركة العقد'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.pageInset,
            AppTheme.sMd,
            AppTheme.pageInset,
            110,
          ),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
              padding: const EdgeInsets.all(AppTheme.sLg),
              decoration: BoxDecoration(
                color: AppTheme.brandSoft,
                borderRadius: BorderRadius.circular(AppTheme.rCard),
              ),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  const AppIconTile(
                    icon: Icons.description_rounded,
                    color: AppTheme.brand,
                  ),
                  const SizedBox(width: AppTheme.sMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            if (widget.propertyType.trim().isNotEmpty)
                              widget.propertyType.trim(),
                            widget.propertyTitle,
                          ].join(' / '),
                          maxLines: 3,
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (widget.isMultiUnit)
                          Text(
                            _chosenUnits.isEmpty
                                ? 'عقد متعدد الوحدات'
                                : 'الوحدات: ${_chosenList.map((u) => u.name).join('، ')}',
                            maxLines: 3,
                            textAlign: AppTr.alignEnd,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.body,
                            ),
                          )
                        else if (widget.unitName.trim().isNotEmpty)
                        Text(
                          widget.unitType.trim().isNotEmpty
                              ? '${widget.unitType.trim()} / ${widget.unitName}'
                              : '${widget.subjectLabel}: ${widget.unitName}',
                          maxLines: 3,
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isMultiUnit) _unitsPickerCard(),
            if (widget.forActivity) ...[
              _activityContractCard(),
              _activityLicenseCard(),
            ] else ...[
            _sectionCard(
              title: 'بيانات عقد الإيجار',
              icon: Icons.assignment_rounded,
              scope: 'contract',
              store: _data.contract,
              fields: widget.isVehicle
                  ? LeaseContractData.vehicleContractFields
                  : LeaseContractData.contractFields,
              // المركبة: بسائق أو بدون سائق بجانب العنوان.
              action: widget.isVehicle ? _driverPicker() : null,
            ),
            _sectionCard(
              title: widget.isVehicle ? 'بيانات المركبة' : 'بيانات العقار',
              icon: widget.isVehicle
                  ? Icons.directions_car_rounded
                  : Icons.apartment_rounded,
              scope: 'property',
              store: _data.property,
              fields: widget.isVehicle
                  ? widget.vehicleFields
                  : LeaseContractData.leasePropertyFields,
            ),
            ],
            _sectionCard(
              title: 'بيانات المؤجر',
              icon: Icons.account_balance_rounded,
              scope: 'lessor',
              store: _data.lessor,
              fields: LeaseContractData.lessorFields,
              action: _pickButton(
                () => _pickFromDirectory(
                  'lessor',
                  _data.lessor,
                  LeaseContractData.kName,
                ),
              ),
            ),
            _sectionCard(
              title: 'بيانات المستأجر',
              icon: Icons.person_rounded,
              scope: 'tenant',
              store: _data.tenant,
              fields: LeaseContractData.tenantFields,
              action: _pickButton(
                () => _pickFromDirectory(
                  'tenant',
                  _data.tenant,
                  LeaseContractData.kName,
                ),
              ),
            ),
            // النشاط التجاري: بلا ممثل المستأجر.
            if (!widget.isVehicle && !widget.forActivity)
            _sectionCard(
              title: 'بيانات ممثل المستأجر',
              icon: Icons.badge_rounded,
              scope: 'rep',
              store: _data.representative,
              fields: LeaseContractData.representativeFields,
              action: _pickButton(
                () => _pickFromDirectory(
                  'rep',
                  _data.representative,
                  LeaseContractData.kRepName,
                ),
              ),
            ),
            _rowsCard(
              title: 'قيمة التأمين على العين',
              icon: Icons.shield_rounded,
              rows: _data.deposits,
              fields: LeaseContractData.depositFields,
              addLabel: 'تسجيل تأمين',
              lineOne: (row) =>
                  '${row[LeaseContractData.kDepositAmount] ?? '0'} · '
                  '${row[LeaseContractData.kCollectMethod] ?? ''}',
              lineTwo: (row) {
                final receipt = row['رقم الإيصال'] ?? '';
                if ((row[LeaseContractData.kCollectMethod] ?? '') == 'شيك') {
                  final no = (row[LeaseContractData.kPaymentCheque] ?? '')
                      .trim();
                  final chequeDate =
                      (row[LeaseContractData.kPaymentChequeDate] ?? '').trim();
                  return [
                    if (no.isNotEmpty) 'شيك رقم $no',
                    chequeDate.isEmpty
                        ? 'بلا تاريخ'
                        : 'تاريخ الشيك: ${_pretty(chequeDate)}',
                    if (receipt.isNotEmpty) 'إيصال رقم $receipt',
                  ].join(' · ');
                }
                final date = row['تاريخ تحصيل التأمين'] ?? '';
                return 'تاريخ التحصيل: ${date.isEmpty ? 'غير محدد' : _pretty(date)}'
                    '${receipt.isEmpty ? '' : ' · إيصال رقم $receipt'}';
              },
              total: _data.depositsTotal,
              totalLabel: 'مجموع التأمين',
              // بلا ضريبة: التأمين مبلغ مُحتجز يُرد، ليس إيرادًا.
              footer: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'مبلغ مُحتجز يُرد عند انتهاء العقد بعد خصم ما يستحق — '
                  'لا ضريبة عليه ولا يدخل في قيمة العقد.',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              ),
            ),
            _rowsCard(
              title: 'مبالغ دفعات الإيجار *',
              icon: Icons.payments_rounded,
              rows: _data.payments,
              fields: LeaseContractData.paymentFields,
              addLabel: 'تسجيل دفعة',
              beforeAdd: _confirmRentTax,
              // الإجمالي وعدد الدفعات ← توزيع متساوٍ يُراجَع ويُعدَّل.
              headerAction: TextButton.icon(
                onPressed: _autoDistributePayments,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.auto_awesome_motion_rounded, size: 17),
                label: const Text(
                  'توزيع تلقائي',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              // ثلاثة أسطر: اسم الدفعة / المبلغ + الضريبة = الإجمالي /
              // تاريخ الاستحقاق فقط.
              lineOne: (row) {
                final name = (row[LeaseContractData.kPaymentFee] ?? '').trim();
                return name.isEmpty ? 'دفعة' : name;
              },
              lineTwo: (row) {
                final amount = double.tryParse(
                      (row[LeaseContractData.kPaymentAmount] ?? '')
                          .replaceAll(',', '')
                          .trim(),
                    ) ??
                    0;
                final tax = _data.paymentTaxOf(row);
                return 'المبلغ ${amount.toStringAsFixed(2)} + الضريبة '
                    '${tax.toStringAsFixed(2)} = الإجمالي '
                    '${(amount + tax).toStringAsFixed(2)}';
              },
              lineThree: (row) {
                final cheque =
                    (row[LeaseContractData.kCollectMethod] ?? '') == 'شيك'
                    ? (row[LeaseContractData.kPaymentChequeDate] ?? '').trim()
                    : '';
                final due = cheque.isNotEmpty
                    ? cheque
                    : (row[LeaseContractData.kPaymentDue] ?? '').trim();
                return 'تاريخ الاستحقاق: '
                    '${due.isEmpty ? 'غير محدد' : _pretty(due)}';
              },
              total: _data.paymentsTotal,
              totalLabel: 'المجموع',
              hideTotal: true,
              header: _rentHeader(),
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _netAndGross(_data.paymentsTotal, _data.paymentsTax),
                  const SizedBox(height: 10),
                  // ملاحظات الدفعات — الكلمة بالرمادي داخل الحقل.
                  TextField(
                    controller: _controllerFor(
                      'contract',
                      _data.contract,
                      LeaseContractData.kPaymentsNote,
                    ),
                    textAlign: AppTr.alignEnd,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: AppTr.tr('ملاحظات'),
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.field,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rIcon),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // الرسوم الإدارية: تُسجَّل مستقلة عن الإيجار لأنها تُدفع مرة
            // واحدة عند التوقيع، ولها مفتاح يقرّر أتدخل في إجمالي العقد أم
            // تبقى خارجه.
            _rowsCard(
              title: 'مبالغ رسوم إدارية',
              icon: Icons.receipt_long_rounded,
              rows: _data.adminFees,
              fields: LeaseContractData.adminFeeFields,
              addLabel: 'تسجيل رسم إداري',
              beforeAdd: _confirmAdminFeeTax,
              lineOne: (row) {
                final tax = _data.adminFeeTaxOf(row);
                final amount = row[LeaseContractData.kAdminFeeAmount] ?? '0';
                return '${row[LeaseContractData.kAdminFeeType] ?? 'رسم'} · '
                    '$amount'
                    '${tax > 0 ? ' + ضريبة ${tax.toStringAsFixed(2)}' : ''}';
              },
              lineTwo: (row) {
                final due = row[LeaseContractData.kAdminFeeDue] ?? '';
                final method = row[LeaseContractData.kCollectMethod] ?? '';
                final who = row['على من'] ?? '';
                final receipt = row['رقم الإيصال'] ?? '';
                return 'الاستحقاق: ${due.isEmpty ? 'غير محدد' : _pretty(due)}'
                    '${method.isEmpty ? '' : ' · $method'}'
                    '${who.isEmpty ? '' : ' · يتحمّلها $who'}'
                    '${receipt.isEmpty ? '' : ' · إيصال $receipt'}';
              },
              total: _data.adminFeesTotal,
              totalLabel: 'مجموع الرسوم الإدارية',
              hideTotal: true,
              // مستطيل ضريبة خاص بالرسوم: قرارها ونسبتها غير قرار الإيجار.
              header: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _taxBox(
                  rateKey: LeaseContractData.kAdminFeesTaxRate,
                  enabled: _data.adminFeesTaxable,
                  onToggle: (on) => setState(
                    () => _data.contract[
                        LeaseContractData.kAdminFeesTaxable] = on
                        ? 'نعم'
                        : 'لا',
                  ),
                ),
              ),
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _netAndGross(_data.adminFeesTotal, _data.adminFeesTax),
                  _adminFeesFooter(),
                ],
              ),
            ),
            _financialSummaryCard(),
            Container(
              padding: const EdgeInsets.all(AppTheme.sLg),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rCard),
              ),
              child: TextField(
                controller: _controllers.putIfAbsent(
                  'note.note',
                  () => TextEditingController(text: _data.note),
                ),
                textAlign: AppTr.alignEnd,
                maxLines: 3,
                style: const TextStyle(fontSize: 12),
                decoration: _decoration('ملاحظات على العقد'),
                onChanged: (value) => _data.note = value,
              ),
            ),
            // المركبة: شروط التأجير جزء من العقد نفسه (الموقع، من عليه
            // الصيانة والوقود والنقل، ونص الشروط).
            if (widget.isVehicle)
              _sectionCard(
                title: 'شروط التأجير',
                icon: Icons.rule_rounded,
                scope: 'contract',
                store: _data.contract,
                fields: LeaseContractData.vehicleTermsFields,
              ),
            // مستندات العقار (شروطك مثلًا) تُختار وتُرفق بالعقد.
            if (widget.assetId.isNotEmpty) _contractDocumentsBox(),
          ],
        ),
        // زرّان: «حفظ كمسودة» مباشرة، و«حفظ العقد» بالتوقيع والختم.
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(asDraft: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.goldDark,
                    side: const BorderSide(color: AppTheme.goldDark),
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text(
                    'حفظ كمسودة',
                    maxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text(
                    _saving
                        ? 'جارٍ الحفظ...'
                        : widget.isRenewal
                        ? 'تجديد العقد'
                        : widget.forActivity
                        ? 'حفظ عقد النشاط'
                        : 'حفظ العقد',
                    maxLines: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
