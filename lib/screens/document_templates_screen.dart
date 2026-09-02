import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_reminders_store.dart';
import '../data/delegations_repository.dart';
import '../data/project_assets_repository.dart';
import '../data/user_signature_store.dart';
import '../data/user_stamp_store.dart';
import 'signature_settings_screen.dart';
import '../widgets/shared/app_design.dart';

class DocumentTemplatesScreen extends StatefulWidget {
  const DocumentTemplatesScreen({super.key, this.linkedProperty});

  final String? linkedProperty;

  @override
  State<DocumentTemplatesScreen> createState() =>
      _DocumentTemplatesScreenState();
}

class _DocumentTemplatesScreenState extends State<DocumentTemplatesScreen> {
  // كانت السجلات تُحفظ محليًا فقط (SharedPreferences)، فتضيع عند حذف
  // التطبيق ولا تظهر على أي جهاز آخر — بخلاف بقية بيانات التطبيق.
  final DelegationsRepository _repository = SupabaseDelegationsRepository();
  final ProjectAssetsRepository _assetsRepository =
      SupabaseProjectAssetsRepository();

  /// الكيانات التي يمكن ربط المستند بها، مقروءة من بياناتها الحقيقية.
  List<({String kind, String label, String id})> _linkTargets = const [];

  static const Map<String, List<String>> _templateFields = {
    'إيصال أمانة': ['اسم المدين', 'اسم الدائن', 'المبلغ', 'سبب الدين'],
    'إيصال استلام وتسليم': ['اسم المستلم', 'اسم المسلّم', 'العنصر', 'حالته'],
    'فاتورة': ['اسم الجهة', 'البيان', 'المبلغ', 'الرقم الضريبي'],
    'تقرير ضريبي': ['الفترة الضريبية', 'الرقم الضريبي', 'الإيرادات', 'الضريبة'],
    'عقد': ['الطرف الأول', 'الطرف الثاني', 'موضوع العقد', 'قيمة العقد'],
    'إنذار': ['المرسل إليه', 'سبب الإنذار', 'المهلة', 'الإجراء المطلوب'],
  };

  static const _templateIcons = {
    'إيصال أمانة': Icons.request_quote_outlined,
    'إيصال استلام وتسليم': Icons.swap_horiz_rounded,
    'فاتورة': Icons.receipt_long_outlined,
    'تقرير ضريبي': Icons.account_balance_outlined,
    'عقد': Icons.handshake_outlined,
    'إنذار': Icons.warning_amber_rounded,
  };

  List<DocumentRecordEntry> _savedRecords = const [];
  bool _loading = true;
  List<List<Offset>> _signature = const [];

  /// صورة الختم المحفوظة (إن وُجدت) — تُعرض مع التوقيع في النموذج.
  Uint8List? _stamp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // مؤشر التحميل في أول تحميل فقط، وإلا أزال السحبُ للتحديث القائمةَ
    // ومعها مؤشر السحب نفسه.
    setState(() => _loading = _savedRecords.isEmpty);
    final signature = await UserSignatureStore.load();
    final stamp = await UserStampStore.load();
    var records = <DocumentRecordEntry>[];
    try {
      records = await _repository.fetchDocuments();
    } catch (_) {
      // تُترك القائمة فارغة؛ يظهر الخطأ عند محاولة الحفظ.
    }
    // كيانات الربط الحقيقية: الأشخاص/الجهات من إدارة الأفراد، والعقارات
    // والأنشطة من قاعدة البيانات — فيرتبط الإيصال أو العقد بسجل فعلي بدل
    // أن يكون ورقة معزولة لا يعرف التطبيق علاقتها بشيء.
    final targets = <({String kind, String label, String id})>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawPeople = prefs.getString('people_management_records_v1');
      if (rawPeople != null && rawPeople.trim().isNotEmpty) {
        final decoded = jsonDecode(rawPeople);
        if (decoded is List) {
          var index = 0;
          for (final entry in decoded.whereType<Map>()) {
            final name = (entry['fullName'] ?? '').toString().trim();
            index++;
            if (name.isEmpty) continue;
            // المعرّف يجب أن يكون فريدًا: شخصان بنفس الاسم كانا سيُنتجان
            // خيارين بنفس القيمة، وهو ما يُسقط القائمة المنسدلة بتأكيد
            // داخلي فور اختيار أحدهما.
            targets.add((kind: 'شخص/جهة', label: name, id: 'person:$index:$name'));
          }
        }
      }
    } catch (_) {
      // مخزون تالف — تُتخطّى قائمة الأشخاص فقط.
    }
    try {
      final assets = await _assetsRepository.fetchAssets();
      for (final asset in assets) {
        if (asset.id == null || asset.title.trim().isEmpty) continue;
        targets.add((
          kind: 'عقار/نشاط',
          label: asset.title.trim(),
          id: 'asset:${asset.id!}',
        ));
      }
    } catch (_) {
      // تعذّر جلب الأصول — تبقى قائمة الأشخاص متاحة.
    }
    if (!mounted) return;
    setState(() {
      _savedRecords = records;
      _signature = signature;
      _stamp = stamp;
      _linkTargets = targets;
      _loading = false;
    });
  
  }

  Future<void> _openTemplate(String type) async {
    final controllers = {
      for (final field in _templateFields[type]!)
        field: TextEditingController(),
      'تاريخ الإصدار': TextEditingController(text: _formatDate(DateTime.now())),
      'تاريخ الانتهاء': TextEditingController(),
      'ملاحظات': TextEditingController(),
    };
    if (widget.linkedProperty != null) {
      controllers[_templateFields[type]!.first]!.text = widget.linkedProperty!;
    }
    var reminderLabel = 'قبل أسبوع';
    var includeSignature = false;
    ({String kind, String label, String id})? link;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      type,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final field in _templateFields[type]!) ...[
                      _textField(controllers[field]!, field),
                      const SizedBox(height: 9),
                    ],
                    _dateField(
                      sheetContext,
                      controllers['تاريخ الإصدار']!,
                      'تاريخ الإصدار',
                    ),
                    const SizedBox(height: 9),
                    _dateField(
                      sheetContext,
                      controllers['تاريخ الانتهاء']!,
                      'تاريخ الانتهاء',
                    ),
                    const SizedBox(height: 9),
                    DropdownButtonFormField<String>(
                      initialValue: reminderLabel,
                      decoration: const InputDecoration(
                        labelText: 'التذكير قبل الانتهاء',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items:
                          const [
                                'في يوم الانتهاء',
                                'قبل يوم',
                                'قبل 3 أيام',
                                'قبل أسبوع',
                                'قبل أسبوعين',
                                'قبل شهر',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => reminderLabel = value);
                        }
                      },
                    ),
                    const SizedBox(height: 9),
                    _textField(controllers['ملاحظات']!, 'ملاحظات', maxLines: 3),
                    if (_signature.isNotEmpty || _stamp != null) ...[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إضافة توقيعي وختمي إلى النموذج'),
                        subtitle: const Text(
                          'اختياري ويمكن تعطيله لكل نموذج',
                        ),
                        value: includeSignature,
                        onChanged: (value) =>
                            setSheetState(() => includeSignature = value),
                      ),
                      if (includeSignature)
                        Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _signature.isEmpty && _stamp != null
                              ? Image.memory(_stamp!, fit: BoxFit.contain)
                              : CustomPaint(
                                  painter: UserSignaturePainter(_signature),
                                ),
                        ),
                    ] else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.draw_outlined),
                        title: const Text('لا يوجد توقيع أو ختم محفوظ'),
                        trailing: TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SignatureSettingsScreen(),
                              ),
                            );
                            final signature = await UserSignatureStore.load();
                            final stamp = await UserStampStore.load();
                            if (!mounted) return;
                            setState(() {
                              _signature = signature;
                              _stamp = stamp;
                            });
                            setSheetState(() {});
                          },
                          child: const Text('إضافة توقيع أو ختم'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // ربط المستند بسجل حقيقي في التطبيق (شخص/جهة أو
                    // عقار/نشاط) بدل أن يبقى ورقة معزولة لا يعرف التطبيق
                    // علاقتها بشيء.
                    if (_linkTargets.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.link_off_rounded),
                        title: Text('لا توجد سجلات للربط بها بعد'),
                        subtitle: Text(
                          'أضف شخصًا أو عقارًا ليمكن ربط المستند به',
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: link?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'ربط المستند بـ (اختياري)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('بدون ربط'),
                          ),
                          ..._linkTargets.map(
                            (t) => DropdownMenuItem<String>(
                              value: t.id,
                              child: Text(
                                '${t.kind}: ${t.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() {
                          link = value == null
                              ? null
                              : _linkTargets.firstWhere((t) => t.id == value);
                        }),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _saveTemplate(
                        sheetContext,
                        type,
                        controllers,
                        reminderLabel,
                        includeSignature,
                        link,
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ النموذج'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _saveTemplate(
    BuildContext sheetContext,
    String type,
    Map<String, TextEditingController> controllers,
    String reminderLabel,
    bool includeSignature,
    ({String kind, String label, String id})? link,
  ) async {
    final firstField = _templateFields[type]!.first;
    if (controllers[firstField]!.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        sheetContext,
      ).showSnackBar(SnackBar(content: Text('أدخل $firstField')));
      return;
    }

    final values = {
      for (final entry in controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    values['includeSignature'] = includeSignature ? '1' : '0';
    values['reminder'] = reminderLabel;

    final expiry = AppRemindersStore.parseDisplayDate(
      values['تاريخ الانتهاء'] ?? '',
    );

    DocumentRecordEntry saved;
    try {
      saved = await _repository.upsertDocument(
        DocumentRecordEntry(
          docType: type,
          fields: values,
          linkedKind: link?.kind,
          linkedLabel: link?.label,
          linkedId: link?.id,
          issuedOn: DateTime.now(),
        ),
      );
    } catch (_) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ النموذج. حاول مرة أخرى.')),
      );
      return;
    }

    if (expiry != null && saved.id != null) {
      await AppRemindersStore.upsert(
        AppReminder(
          id: saved.id!,
          title: '$type: ${values[firstField]}',
          module: widget.linkedProperty == null
              ? 'النماذج والمستندات'
              : 'العقارات والأنشطة التجارية',
          expiryDate: expiry,
          remindBeforeDays: AppRemindersStore.reminderDaysFromLabel(
            reminderLabel,
          ),
        ),
      );
    }

    await _load();
    if (!mounted || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    // الرسالة تصف ما حدث فعلًا: التذكير لا يُنشأ إلا عند إدخال تاريخ
    // انتهاء. كانت تُعلن إنشاء تذكير في كل مرة حتى بلا تاريخ.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          expiry == null
              ? 'تم حفظ النموذج'
              : 'تم حفظ النموذج وإضافة تذكير الانتهاء',
        ),
      ),
    );
  }

  Future<void> _shareRecord(DocumentRecordEntry record) async {
    // تُستبعد الحقول الداخلية من المعاينة حتى لا تظهر أسطر مثل
    // "includeSignature: 1" داخل المستند المُشارَك.
    const internal = {'includeSignature', 'reminder'};
    final values = <String, dynamic>{
      for (final e in record.fields.entries)
        if (!internal.contains(e.key)) e.key: e.value,
      if ((record.linkedLabel ?? '').isNotEmpty)
        'مرتبط بـ': '${record.linkedKind}: ${record.linkedLabel}',
    };
    final withSignature = record.fields['includeSignature'] == '1';
    final signature = withSignature
        ? await UserSignatureStore.load()
        : <List<Offset>>[];
    // الختم المحفوظ في صفحة "التوقيع الإلكتروني والختم" يظهر بجانب
    // التوقيع، فلا يبقى الختم صورة محفوظة لا تُستخدم في شيء.
    final stamp = withSignature ? await UserStampStore.load() : null;
    if (!mounted) return;
    final previewKey = GlobalKey();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('معاينة النموذج'),
          content: SingleChildScrollView(
            child: RepaintBoundary(
              key: previewKey,
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      record.docType,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Divider(height: 28),
                    for (final entry in values.entries)
                      if (entry.value.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                    if (signature.isNotEmpty || stamp != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (signature.isNotEmpty)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'التوقيع',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 82,
                                    child: CustomPaint(
                                      painter: UserSignaturePainter(signature),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (signature.isNotEmpty && stamp != null)
                            const SizedBox(width: 12),
                          if (stamp != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'الختم',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 82,
                                    child: Image.memory(
                                      stamp,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerRight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final boundary =
                    previewKey.currentContext?.findRenderObject()
                        as RenderRepaintBoundary?;
                if (boundary == null) return;
                final image = await boundary.toImage(pixelRatio: 3);
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (data == null || !dialogContext.mounted) return;
                await SharePlus.instance.share(
                  ShareParams(
                    text: record.docType,
                    files: [
                      XFile.fromData(
                        data.buffer.asUint8List(),
                        mimeType: 'image/png',
                        name: 'fundly-document.png',
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('مشاركة كصورة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRecord(DocumentRecordEntry record) async {
    final id = record.id;
    if (id == null) return;
    try {
      await _repository.deleteDocument(id);
      // يُحذف تذكير الانتهاء المرتبط أيضًا، وإلا بقي ينبّه عن مستند محذوف.
      await AppRemindersStore.remove(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حذف النموذج')),
      );
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف النموذج')));
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _dateField(
    BuildContext context,
    TextEditingController controller,
    String label,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.event_outlined),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2045),
        );
        if (selected != null) controller.text = _formatDate(selected);
      },
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: Text(
          widget.linkedProperty == null
              ? 'نماذج المستندات والإيصالات'
              : 'نماذج ${widget.linkedProperty}',
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: TextDirection.rtl,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              'اختر نموذجًا جاهزًا واملأ بياناته',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: _templateFields.keys
                  .map(
                    (type) => Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _openTemplate(type),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _templateIcons[type],
                                color: const Color(0xFF0F6AA8),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                type,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (_savedRecords.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                'النماذج المحفوظة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final record in _savedRecords)
                Card(
                  child: ListTile(
                    leading: Icon(
                      _templateIcons[record.docType] ??
                          Icons.description_outlined,
                    ),
                    title: Text(record.docType),
                    subtitle: Text(
                      [
                        (record.fields['تاريخ الانتهاء'] ?? '').isEmpty
                            ? 'بدون تاريخ انتهاء'
                            : 'ينتهي: ${record.fields['تاريخ الانتهاء']}',
                        if ((record.linkedLabel ?? '').isNotEmpty)
                          '${record.linkedKind}: ${record.linkedLabel}',
                      ].join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'share') _shareRecord(record);
                        if (action == 'delete') _deleteRecord(record);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'share', child: Text('مشاركة')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
