import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_reminders_store.dart';
import '../data/user_signature_store.dart';
import 'signature_settings_screen.dart';

class DocumentTemplatesScreen extends StatefulWidget {
  const DocumentTemplatesScreen({super.key, this.linkedProperty});

  final String? linkedProperty;

  @override
  State<DocumentTemplatesScreen> createState() =>
      _DocumentTemplatesScreenState();
}

class _DocumentTemplatesScreenState extends State<DocumentTemplatesScreen> {
  static const _recordsKey = 'document_template_records_v1';

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

  List<Map<String, dynamic>> _savedRecords = const [];
  List<List<Offset>> _signature = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    final signature = await UserSignatureStore.load();
    var records = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        records = (jsonDecode(raw) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _savedRecords = records;
      _signature = signature;
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                    if (_signature.isNotEmpty) ...[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إضافة توقيعي إلى النموذج'),
                        subtitle: const Text('اختياري ويمكن تعطيله لكل نموذج'),
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
                          child: CustomPaint(
                            painter: UserSignaturePainter(_signature),
                          ),
                        ),
                    ] else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.draw_outlined),
                        title: const Text('لا يوجد توقيع محفوظ'),
                        trailing: TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SignatureSettingsScreen(),
                              ),
                            );
                            final signature = await UserSignatureStore.load();
                            if (!mounted) return;
                            setState(() => _signature = signature);
                            setSheetState(() {});
                          },
                          child: const Text('إضافة توقيع'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _saveTemplate(
                        sheetContext,
                        type,
                        controllers,
                        reminderLabel,
                        includeSignature,
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
  ) async {
    final firstField = _templateFields[type]!.first;
    if (controllers[firstField]!.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        sheetContext,
      ).showSnackBar(SnackBar(content: Text('أدخل $firstField')));
      return;
    }

    final id = 'template-${DateTime.now().microsecondsSinceEpoch}';
    final values = {
      for (final entry in controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final record = <String, dynamic>{
      'id': id,
      'type': type,
      'values': values,
      'reminder': reminderLabel,
      'includeSignature': includeSignature,
      'createdAt': DateTime.now().toIso8601String(),
    };
    final next = [record, ..._savedRecords];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, jsonEncode(next));

    final expiry = AppRemindersStore.parseDisplayDate(
      values['تاريخ الانتهاء'] ?? '',
    );
    if (expiry != null) {
      await AppRemindersStore.upsert(
        AppReminder(
          id: id,
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

    if (!mounted || !sheetContext.mounted) return;
    setState(() => _savedRecords = next);
    Navigator.of(sheetContext).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ النموذج وإضافة تذكير الانتهاء')),
    );
  }

  Future<void> _shareRecord(Map<String, dynamic> record) async {
    final values = Map<String, dynamic>.from(record['values'] as Map);
    final signature = record['includeSignature'] == true
        ? await UserSignatureStore.load()
        : <List<Offset>>[];
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
                      record['type']?.toString() ?? '',
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
                    if (signature.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'التوقيع',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(
                        height: 82,
                        child: CustomPaint(
                          painter: UserSignaturePainter(signature),
                        ),
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
                    text: record['type']?.toString(),
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

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final id = record['id']?.toString() ?? '';
    final next = _savedRecords
        .where((item) => item['id']?.toString() != id)
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, jsonEncode(next));
    await AppRemindersStore.remove(id);
    if (!mounted) return;
    setState(() => _savedRecords = next);
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
      body: Directionality(
        textDirection: TextDirection.rtl,
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
                      _templateIcons[record['type']] ??
                          Icons.description_outlined,
                    ),
                    title: Text(record['type']?.toString() ?? ''),
                    subtitle: Text(
                      (Map<String, dynamic>.from(
                                record['values'] as Map,
                              )['تاريخ الانتهاء']?.toString().isEmpty ??
                              true)
                          ? 'بدون تاريخ انتهاء'
                          : 'ينتهي: ${Map<String, dynamic>.from(record['values'] as Map)['تاريخ الانتهاء']}',
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
    );
  }
}
