import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/document_store.dart';
import '../data/user_logo_store.dart';
import '../data/user_signature_store.dart';
import '../data/user_stamp_store.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import 'signature_settings_screen.dart';

const _accent = Color(0xFF0A5A50);

String _dmy(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime? _parseDmy(String value) {
  final parts = value.trim().split('/');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

/// نتيجة محرر الملاحظة.
class NoteEditorResult {
  const NoteEditorResult({
    required this.title,
    required this.data,
    required this.expiry,
    required this.remindDays,
  });

  final String title;
  final Map<String, dynamic> data;

  /// تاريخ التذكير «يوم/شهر/سنة» (فارغ = بلا تذكير).
  final String expiry;

  /// التذكير قبل التاريخ بالأيام؛ -1 = بلا تذكير.
  final int remindDays;
}

/// جزء من الملاحظة بالترتيب: نص، بند بعلامة صح، جدول، صورة.
class _NoteBlock {
  _NoteBlock(
    this.type, {
    String text = '',
    this.done = false,
    this.big = false,
    this.path = '',
    List<List<String>>? rows,
  }) : ctrl = TextEditingController(text: text),
       focus = FocusNode(),
       cells = [
         for (final row in rows ?? const <List<String>>[])
           [for (final cell in row) TextEditingController(text: cell)],
       ];

  final String type;
  final TextEditingController ctrl;
  final FocusNode focus;
  bool done;

  /// نص بخط كبير (زر Aa).
  bool big;
  final String path;
  final List<List<TextEditingController>> cells;

  bool get isEmpty => switch (type) {
    'img' || 'file' => path.isEmpty,
    'table' => cells.every(
      (row) => row.every((cell) => cell.text.trim().isEmpty),
    ),
    _ => ctrl.text.trim().isEmpty,
  };

  Map<String, dynamic> toJson() => switch (type) {
    'check' => {'t': 'check', 'v': ctrl.text, 'd': done},
    'table' => {
      't': 'table',
      'rows': [
        for (final row in cells) [for (final cell in row) cell.text],
      ],
    },
    'img' => {'t': 'img', 'p': path},
    'file' => {'t': 'file', 'p': path},
    _ => {'t': 'text', 'v': ctrl.text, if (big) 'h': true},
  };

  void dispose() {
    ctrl.dispose();
    focus.dispose();
    for (final row in cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
  }
}

/// ملاحظة مثل ملاحظات الآيفون: صفحة كتابة مباشرة، وشريط فوق الكيبورد
/// (خط كبير، قائمة بعلامات صح، جدول، صورة). عند «تم» يُطلب الاسم والتاريخ
/// والتذكير.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.title = '',
    this.data = const {},
    this.expiry = '',
    this.remindDays = -1,
    this.takenNames = const {},
    this.asFile = false,
  });

  final String title;
  final Map<String, dynamic> data;
  final String expiry;
  final int remindDays;

  /// «ملف» من «إضافة»: نفس صفحة الكتابة، ويُحفظ ملفًا في المكان الحالي.
  final bool asFile;

  /// أسماء موجودة في المكان نفسه — لا يتكرر الاسم.
  final Set<String> takenNames;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final List<_NoteBlock> _blocks = [];
  int _current = 0;
  String _initialJson = '';

  static const _reminderChoices = <String, int>{
    'بلا تذكير': -1,
    'في يوم الموعد': 0,
    'قبل يوم': 1,
    'قبل أسبوع': 7,
  };

  @override
  void initState() {
    super.initState();
    final blocks = widget.data['blocks'];
    if (blocks is List) {
      for (final raw in blocks.whereType<Map>()) {
        final type = '${raw['t'] ?? 'text'}';
        switch (type) {
          case 'check':
            _blocks.add(
              _NoteBlock(
                'check',
                text: '${raw['v'] ?? ''}',
                done: raw['d'] == true,
              ),
            );
          case 'table':
            final rows = <List<String>>[
              for (final row in (raw['rows'] is List ? raw['rows'] as List : const []))
                if (row is List) [for (final cell in row) '$cell'],
            ];
            if (rows.isNotEmpty) _blocks.add(_NoteBlock('table', rows: rows));
          case 'img':
            final path = '${raw['p'] ?? ''}';
            if (path.isNotEmpty) _blocks.add(_NoteBlock('img', path: path));
          case 'file':
            final path = '${raw['p'] ?? ''}';
            if (path.isNotEmpty) _blocks.add(_NoteBlock('file', path: path));
          default:
            _blocks.add(
              _NoteBlock(
                'text',
                text: '${raw['v'] ?? ''}',
                big: raw['h'] == true,
              ),
            );
        }
      }
    } else {
      // ملاحظات النسخة السابقة: نص، ثم بنود، ثم جدول، ثم صور.
      final text = '${widget.data['text'] ?? ''}';
      if (text.isNotEmpty) _blocks.add(_NoteBlock('text', text: text));
      final checks = widget.data['checks'];
      if (checks is List) {
        for (final entry in checks.whereType<Map>()) {
          _blocks.add(
            _NoteBlock(
              'check',
              text: '${entry['t'] ?? ''}',
              done: entry['d'] == true,
            ),
          );
        }
      }
      final table = widget.data['table'];
      if (table is List && table.isNotEmpty) {
        _blocks.add(
          _NoteBlock(
            'table',
            rows: [
              for (final row in table.whereType<List>())
                [for (final cell in row) '$cell'],
            ],
          ),
        );
      }
      final images = widget.data['images'];
      if (images is List) {
        for (final path in images) {
          _blocks.add(_NoteBlock('img', path: '$path'));
        }
      }
    }
    if (_blocks.isEmpty || _blocks.last.type != 'text') {
      _blocks.add(_NoteBlock('text'));
    }
    for (final block in _blocks) {
      _watch(block);
    }
    _initialJson = jsonEncode(_dataJson());
    // ملاحظة جديدة: الكيبورد جاهز للكتابة مباشرة.
    if (widget.title.isEmpty && _blocks.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _blocks.first.focus.requestFocus();
      });
    }
  }

  void _watch(_NoteBlock block) {
    block.focus.addListener(() {
      if (!block.focus.hasFocus) return;
      final index = _blocks.indexOf(block);
      if (index >= 0 && index != _current) setState(() => _current = index);
    });
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _dataJson() => {
    'blocks': [
      for (final block in _blocks)
        if (!(block.type == 'text' && block.isEmpty && _blocks.length > 1) &&
            !(block.type == 'check' && block.isEmpty))
          block.toJson(),
    ],
  };

  bool get _dirty => jsonEncode(_dataJson()) != _initialJson;

  /// يضيف جزءًا بعد مكان الكتابة الحالي، ومعه سطر نص بعده للمتابعة.
  void _insert(_NoteBlock block) {
    final at = (_current.clamp(0, _blocks.length - 1)) + 1;
    setState(() {
      _blocks.insert(at, block);
      _watch(block);
      final next = at + 1;
      if (block.type != 'check' &&
          (next >= _blocks.length || _blocks[next].type != 'text')) {
        final text = _NoteBlock('text');
        _blocks.insert(next, text);
        _watch(text);
      }
      _current = at;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (block.type == 'check') {
        block.focus.requestFocus();
      } else if (block.type == 'table' && block.cells.isNotEmpty) {
        // الخلية الأولى جاهزة للكتابة.
        FocusScope.of(context).unfocus();
      }
    });
  }

  void _addCheck() {
    final current = _blocks[_current.clamp(0, _blocks.length - 1)];
    // سطر نص فارغ يتحول بندًا بعلامة صح مكانه.
    if (current.type == 'text' && current.isEmpty) {
      final index = _blocks.indexOf(current);
      final check = _NoteBlock('check');
      setState(() {
        _blocks[index] = check;
        _watch(check);
      });
      current.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) check.focus.requestFocus();
      });
      return;
    }
    _insert(_NoteBlock('check'));
  }

  void _submitCheck(_NoteBlock block) {
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    if (block.isEmpty) {
      // بند فارغ + Enter: الرجوع للكتابة العادية.
      final text = _NoteBlock('text');
      setState(() {
        _blocks[index] = text;
        _watch(text);
      });
      block.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) text.focus.requestFocus();
      });
      return;
    }
    final next = _NoteBlock('check');
    setState(() {
      _blocks.insert(index + 1, next);
      _watch(next);
      _current = index + 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) next.focus.requestFocus();
    });
  }

  void _toggleBig() {
    final current = _blocks[_current.clamp(0, _blocks.length - 1)];
    if (current.type != 'text') return;
    setState(() => current.big = !current.big);
  }

  void _removeBlock(_NoteBlock block) {
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    setState(() {
      _blocks.removeAt(index);
      if (_blocks.isEmpty || _blocks.last.type != 'text') {
        final text = _NoteBlock('text');
        _blocks.add(text);
        _watch(text);
      }
      _current = (index - 1).clamp(0, _blocks.length - 1);
    });
    block.dispose();
  }

  Future<void> _addImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('من الاستديو'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('التقاط صورة'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('ملف من الجهاز'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _attachFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;
      final stored = await DocumentStore.copyIntoApp(picked.path, picked.name);
      if (stored == null || !mounted) return;
      _insert(_NoteBlock('img', path: stored));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الصور على هذا الجهاز')),
      );
    }
  }

  /// الاسم الافتراضي: «ملاحظة 13/10/2026 1:54 م» (أو «ملف …»).
  late final String _defaultName = () {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = AppTr.tr(now.hour < 12 ? 'ص' : 'م');
    return '${AppTr.tr(widget.asFile ? 'ملف' : 'ملاحظة')} '
        '${_dmy(now)} $hour:$minute $period';
  }();

  /// ملف من الجهاز (PDF، Word…) داخل الملاحظة.
  Future<void> _attachFile() async {
    final stored = await DocumentStore.pickAndStore();
    if (stored == null || !mounted) return;
    _insert(_NoteBlock('file', path: stored));
  }

  String _suggestedName() {
    if (widget.title.isNotEmpty) return widget.title;
    for (final block in _blocks) {
      if ((block.type == 'text' || block.type == 'check') && !block.isEmpty) {
        final line = block.ctrl.text.trim().split('\n').first.trim();
        return line.length > 40 ? line.substring(0, 40) : line;
      }
    }
    return _defaultName;
  }

  /// نص الملاحظة كاملًا للمشاركة (النص، البنود ☐/☑، الجدول).
  String _plainText() {
    final lines = <String>[];
    for (final block in _blocks) {
      switch (block.type) {
        case 'check':
          if (!block.isEmpty) {
            lines.add('${block.done ? '☑' : '☐'} ${block.ctrl.text.trim()}');
          }
        case 'table':
          for (final row in block.cells) {
            lines.add(row.map((cell) => cell.text.trim()).join(' | '));
          }
        case 'img':
        case 'file':
          break;
        default:
          if (!block.isEmpty) lines.add(block.ctrl.text.trim());
      }
    }
    return lines.join('\n');
  }

  /// ⋮ مشاركة: إيميل، واتساب، أو أي تطبيق — النص ومعه الصور والملفات.
  Future<void> _share() async {
    final title = widget.title.isEmpty ? _defaultName : widget.title;
    final files = [
      for (final block in _blocks)
        if ((block.type == 'img' || block.type == 'file') &&
            DocumentStore.existsSync(block.path))
          XFile(DocumentStore.localPathFor(block.path)),
    ];
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: title,
        text: '$title\n\n${_plainText()}',
        files: files.isEmpty ? null : files,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// «تم»: نافذة الاسم والتاريخ والتذكير، ثم الحفظ.
  Future<void> _finish() async {
    FocusScope.of(context).unfocus();
    final nameCtrl = TextEditingController(text: _suggestedName());
    DateTime? date = _parseDmy(widget.expiry);
    var days = widget.remindDays;
    String? nameError;
    final result = await showModalBottomSheet<NoteEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final reminderLabel = _reminderChoices.entries
              .firstWhere(
                (e) => e.value == days,
                orElse: () => const MapEntry('بلا تذكير', -1),
              )
              .key;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Directionality(
              textDirection: AppTr.uiDir,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'حفظ الملاحظة',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        autofocus: nameCtrl.text.isEmpty,
                        textDirection: AppTr.uiDir,
                        onChanged: (_) {
                          if (nameError != null) {
                            setSheet(() => nameError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: AppTr.tr('اسم الملف'),
                          prefixIcon: const Icon(Icons.title_rounded),
                          errorText: nameError == null
                              ? null
                              : AppTr.tr(nameError!),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // التاريخ والتذكير جنب بعض.
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: sheetContext,
                                  initialDate: date ?? now,
                                  firstDate: DateTime(now.year - 1),
                                  lastDate: DateTime(now.year + 20),
                                  helpText: AppTr.tr('تاريخ التذكير'),
                                );
                                if (picked == null) return;
                                setSheet(() {
                                  date = picked;
                                  if (days < 0) days = 0;
                                });
                              },
                              icon: const Icon(Icons.event_outlined, size: 18),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  date == null ? 'تاريخ التذكير' : _dmy(date!),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _accent,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: reminderLabel,
                              isExpanded: true,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: AppTr.tr('تذكير قبل'),
                                prefixIcon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: [
                                for (final label in _reminderChoices.keys)
                                  DropdownMenuItem(
                                    value: label,
                                    child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                      label,
                                      maxLines: 1,
                                    )),
                                  ),
                              ],
                              onChanged: (value) => setSheet(
                                () => days = _reminderChoices[value] ?? -1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          final name = nameCtrl.text.trim().isEmpty
                              ? AppTr.tr('ملاحظة')
                              : nameCtrl.text.trim();
                          if (widget.takenNames.contains(name.toLowerCase())) {
                            setSheet(
                              () => nameError =
                                  'الاسم موجود في هذا المكان — اختر اسمًا آخر',
                            );
                            return;
                          }
                          if (days >= 0 && date == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('اختر التاريخ للتذكير'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(
                            sheetContext,
                            NoteEditorResult(
                              title: name,
                              data: _dataJson(),
                              expiry: date == null || days < 0
                                  ? ''
                                  : _dmy(date!),
                              remindDays: date == null ? -1 : days,
                            ),
                          );
                        },
                        icon: const Icon(Icons.save_outlined, size: 19),
                        label: const Text(
                          'حفظ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          minimumSize: const Size.fromHeight(48),
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
    nameCtrl.dispose();
    if (result == null || !mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmAction(
      context,
      title: 'الخروج بدون حفظ؟',
      message: 'لن تُحفظ التغييرات على هذه الملاحظة. لحفظها اضغط «تم».',
      confirmLabel: 'خروج',
      cancelLabel: 'متابعة الكتابة',
      danger: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  InputDecoration _plain(String hint) => InputDecoration(
    isDense: true,
    hintText: hint.isEmpty ? null : AppTr.tr(hint),
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
  );

  Widget _blockView(_NoteBlock block, int index) {
    switch (block.type) {
      case 'check':
        return Row(
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => block.done = !block.done),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  block.done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: block.done ? const Color(0xFFE0A800) : AppTheme.muted,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: block.ctrl,
                focusNode: block.focus,
                textDirection: AppTr.uiDir,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _submitCheck(block),
                style: TextStyle(
                  fontSize: 15,
                  decoration: block.done ? TextDecoration.lineThrough : null,
                  color: block.done ? AppTheme.muted : AppTheme.title,
                ),
                decoration: _plain(''),
              ),
            ),
          ],
        );
      case 'table':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.hairline),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: Column(
            children: [
              for (var r = 0; r < block.cells.length; r++)
                Container(
                  decoration: BoxDecoration(
                    color: r == 0 ? const Color(0xFFF6F3E6) : null,
                    border: r == 0
                        ? null
                        : const Border(
                            top: BorderSide(color: AppTheme.hairline),
                          ),
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < block.cells[r].length; c++)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: c == 0
                                  ? null
                                  : const BorderDirectional(
                                      start: BorderSide(
                                        color: AppTheme.hairline,
                                      ),
                                    ),
                            ),
                            child: TextField(
                              controller: block.cells[r][c],
                              textDirection: AppTr.uiDir,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: r == 0
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                              decoration: _plain(''),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.hairline)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(
                        () => block.cells.add([
                          for (var c = 0; c < block.cells.first.length; c++)
                            TextEditingController(),
                        ]),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('صف', style: TextStyle(fontSize: 12)),
                    ),
                    if (block.cells.first.length < 4)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          for (final row in block.cells) {
                            row.add(TextEditingController());
                          }
                        }),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text(
                          'عمود',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: AppTr.tr('حذف الجدول'),
                      onPressed: () => _removeBlock(block),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'file':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: const Color(0xFFF4F6F5),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              onTap: () => DocumentStore.open(block.path),
              leading: const Icon(
                Icons.insert_drive_file_rounded,
                color: _accent,
              ),
              title: Text(
                DocumentStore.shortName(block.path, max: 30),
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: IconButton(
                tooltip: AppTr.tr('حذف'),
                onPressed: () => _removeBlock(block),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          ),
        );
      case 'img':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => DocumentStore.open(block.path),
                  child: Image.file(
                    File(DocumentStore.localPathFor(block.path)),
                    width: double.infinity,
                    height: 210,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: AppTheme.surface,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: InkWell(
                  onTap: () => _removeBlock(block),
                  child: const CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return TextField(
          controller: block.ctrl,
          focusNode: block.focus,
          textDirection: AppTr.uiDir,
          minLines: index == 0 ? 6 : 1,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontSize: block.big ? 21 : 15.5,
            height: 1.55,
            fontWeight: block.big ? FontWeight.w900 : FontWeight.w500,
            color: AppTheme.title,
          ),
          decoration: _plain(index == 0 ? 'اكتب ملاحظتك…' : ''),
        );
    }
  }

  Widget _toolButton(IconData? icon, String tip, VoidCallback onTap) =>
      IconButton(
        tooltip: AppTr.tr(tip),
        onPressed: onTap,
        icon: icon == null
            // «Aa» مثل ملاحظات الآيفون.
            ? const Text(
                'Aa',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              )
            : Icon(icon, size: 24, color: const Color(0xFF1C1C1E)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Center(
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: Colors.black26,
                  child: IconButton(
                    tooltip: AppTr.tr('رجوع'),
                    onPressed: _leave,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
              ),
            ),
            title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
              widget.title.isEmpty ? _defaultName : widget.title,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            )),
            centerTitle: true,
            actions: [
              // ⋮ إرسال الملاحظة/الملف: إيميل، واتساب، أو أي تطبيق.
              PopupMenuButton<String>(
                tooltip: AppTr.tr('خيارات'),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFF1C1C1E),
                ),
                onSelected: (_) => _share(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.ios_share_rounded, size: 19),
                        SizedBox(width: 10),
                        Text('إرسال / مشاركة'),
                      ],
                    ),
                  ),
                ],
              ),
              // ✓ أصفر مثل ملاحظات الآيفون: يحفظ ويطلب الاسم والتذكير.
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Material(
                  color: const Color(0xFFE0B400),
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: Colors.black26,
                  child: IconButton(
                    tooltip: AppTr.tr('تم'),
                    onPressed: _finish,
                    icon: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // الضغط في المساحة الفارغة يكتب في آخر سطر.
                  onTap: () {
                    final last = _blocks.last;
                    if (last.type == 'text') last.focus.requestFocus();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                    children: [
                      for (var i = 0; i < _blocks.length; i++)
                        _blockView(_blocks[i], i),
                    ],
                  ),
                ),
              ),
              // شريط الأدوات فوق الكيبورد مباشرة مثل ملاحظات الآيفون.
              SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F4),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _toolButton(null, 'خط كبير', _toggleBig),
                      _toolButton(
                        Icons.checklist_rounded,
                        'قائمة بعلامات صح',
                        _addCheck,
                      ),
                      _toolButton(
                        Icons.table_chart_outlined,
                        'جدول صغير',
                        () => _insert(
                          _NoteBlock(
                            'table',
                            rows: const [
                              ['', ''],
                              ['', ''],
                            ],
                          ),
                        ),
                      ),
                      _toolButton(
                        Icons.attach_file_rounded,
                        'صورة أو ملف',
                        _addImage,
                      ),
                      _toolButton(
                        Icons.keyboard_hide_outlined,
                        'إخفاء الكيبورد',
                        () => FocusScope.of(context).unfocus(),
                      ),
                    ],
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

/// توقيع أو ختم أو شعار على صورة أو ملف PDF: يُسحب كلٌّ إلى مكانه، ثم
/// يُحفظ نسخة موقّعة جديدة (الأصل يبقى كما هو).
class SignDocumentScreen extends StatefulWidget {
  const SignDocumentScreen({super.key, required this.path});

  final String path;

  static bool supports(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.pdf');
  }

  @override
  State<SignDocumentScreen> createState() => _SignDocumentScreenState();
}

class _SignDocumentScreenState extends State<SignDocumentScreen> {
  final GlobalKey _boundary = GlobalKey();
  bool get _isPdf => widget.path.toLowerCase().endsWith('.pdf');

  List<Uint8List> _pages = const [];
  List<Size> _pageSizes = const [];
  int _page = 0;
  bool _loading = true;
  bool _saving = false;

  List<List<Offset>> _signature = const [];
  Uint8List? _stamp;
  Uint8List? _logo;
  bool _showSignature = true;
  bool _showStamp = false;
  bool _showLogo = false;
  Offset _logoAt = const Offset(40, 140);
  double _logoScale = 1;
  Offset _signatureAt = const Offset(20, 20);
  Offset _stampAt = const Offset(140, 60);
  double _signatureScale = 1;
  double _stampScale = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final signature = await UserSignatureStore.load();
    final stamp = await UserStampStore.load();
    final logo = await UserLogoStore.load();
    final pages = <Uint8List>[];
    final sizes = <Size>[];
    try {
      final bytes = await File(
        DocumentStore.localPathFor(widget.path),
      ).readAsBytes();
      if (_isPdf) {
        var count = 0;
        await for (final raster in Printing.raster(bytes, dpi: 110)) {
          pages.add(await raster.toPng());
          sizes.add(Size(raster.width.toDouble(), raster.height.toDouble()));
          if (++count >= 30) break;
        }
      } else {
        pages.add(bytes);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        sizes.add(
          Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _signature = signature;
      _stamp = stamp;
      _logo = logo;
      _showSignature = signature.isNotEmpty;
      _showStamp = signature.isEmpty && stamp != null;
      _showLogo = signature.isEmpty && stamp == null && logo != null;
      _pages = pages;
      _pageSizes = sizes;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _pages.isEmpty) return;
    setState(() => _saving = true);
    // إطار جديد بلا حدود السحب قبل التقاط الصورة.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final shown = boundary.size.width;
      final ratio = shown <= 0 ? 2.0 : _pageSizes[_page].width / shown;
      final image = await boundary.toImage(pixelRatio: ratio.clamp(1.0, 4.0));
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no image');
      final signedPage = data.buffer.asUint8List();
      final base = DocumentStore.fileName(
        widget.path,
      ).replaceFirst(RegExp(r'^\d+_'), '').replaceFirst(RegExp(r'\.[^.]+$'), '');
      final Uint8List output;
      final String name;
      if (_isPdf) {
        final doc = pw.Document();
        for (var i = 0; i < _pages.length; i++) {
          final size = _pageSizes[i];
          final bytes = i == _page ? signedPage : _pages[i];
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(size.width, size.height),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
            ),
          );
        }
        output = await doc.save();
        name = '$base (موقّع).pdf';
      } else {
        output = signedPage;
        name = '$base (موقّع).png';
      }
      final temp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        '${DateTime.now().millisecondsSinceEpoch}.${_isPdf ? 'pdf' : 'png'}',
      );
      await temp.writeAsBytes(output);
      final stored = await DocumentStore.copyIntoApp(temp.path, name);
      if (!mounted) return;
      Navigator.of(context).pop(stored);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ النسخة الموقّعة')),
      );
    }
  }

  /// التوقيع والختم والشعار تُضاف من «المزيد ← التوقيع الإلكتروني والختم».
  Future<void> _openMarksSettings() async {
    final open = await confirmAction(
      context,
      title: 'التوقيع والختم والشعار',
      message:
          'تُضاف من «المزيد ← التوقيع الإلكتروني والختم». هل تريد فتحها الآن؟',
      confirmLabel: 'فتح',
      cancelLabel: 'لاحقًا',
    );
    if (!open || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignatureSettingsScreen()),
    );
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  Widget _draggable({
    required Offset at,
    required double scale,
    required Size base,
    required Widget child,
    required ValueChanged<Offset> onMove,
  }) {
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: GestureDetector(
        onPanUpdate: (details) => onMove(at + details.delta),
        child: Container(
          width: base.width * scale,
          height: base.height * scale,
          decoration: BoxDecoration(
            border: Border.all(
              color: _saving ? Colors.transparent : const Color(0x880E7161),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _scaleButtons(String label, double value, ValueChanged<double> set) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => set((value - 0.15).clamp(0.4, 3.0)),
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => set((value + 0.15).clamp(0.4, 3.0)),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final hasMarks =
        _signature.isNotEmpty || _stamp != null || _logo != null;
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text(
            'توقيع / ختم / شعار',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (!_loading && _pages.isNotEmpty && hasMarks)
              TextButton(
                onPressed: _saving ? null : _save,
                child: const Text(
                  'حفظ',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _accent,
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _pages.isEmpty
            ? const Center(child: Text('تعذّر فتح الملف للتوقيع'))
            : !hasMarks
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'لا يوجد توقيع أو ختم أو شعار محفوظ بعد.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignatureSettingsScreen(),
                            ),
                          );
                          setState(() => _loading = true);
                          await _load();
                        },
                        child: const Text('إضافة توقيع أو ختم أو شعار'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_signature.isNotEmpty)
                          FilterChip(
                            label: const Text('التوقيع'),
                            selected: _showSignature,
                            onSelected: (v) => setState(() => _showSignature = v),
                          ),
                        if (_stamp != null)
                          FilterChip(
                            label: const Text('الختم'),
                            selected: _showStamp,
                            onSelected: (v) => setState(() => _showStamp = v),
                          ),
                        if (_logo != null)
                          FilterChip(
                            label: const Text('الشعار'),
                            selected: _showLogo,
                            onSelected: (v) => setState(() => _showLogo = v),
                          ),
                        // غير المحفوظ بعد: زر يذهب لإضافته من «المزيد».
                        if (_signature.isEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('إضافة توقيع'),
                            onPressed: _openMarksSettings,
                          ),
                        if (_stamp == null)
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('إضافة ختم'),
                            onPressed: _openMarksSettings,
                          ),
                        if (_logo == null)
                          ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('إضافة شعار'),
                            onPressed: _openMarksSettings,
                          ),
                        if (_isPdf && _pages.length > 1)
                          DropdownButton<int>(
                            value: _page,
                            items: [
                              for (var i = 0; i < _pages.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text('${AppTr.tr('الصفحة')} ${i + 1}'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _page = v ?? 0),
                          ),
                      ],
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (_showSignature)
                        _scaleButtons(
                          'حجم التوقيع',
                          _signatureScale,
                          (v) => setState(() => _signatureScale = v),
                        ),
                      if (_showStamp)
                        _scaleButtons(
                          'حجم الختم',
                          _stampScale,
                          (v) => setState(() => _stampScale = v),
                        ),
                      if (_showLogo)
                        _scaleButtons(
                          'حجم الشعار',
                          _logoScale,
                          (v) => setState(() => _logoScale = v),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'اسحب التوقيع والختم والشعار إلى مكانها ثم اضغط «حفظ».',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: RepaintBoundary(
                          key: _boundary,
                          child: AspectRatio(
                            aspectRatio:
                                _pageSizes[_page].width /
                                _pageSizes[_page].height,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.memory(
                                    _pages[_page],
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                if (_showSignature && _signature.isNotEmpty)
                                  _draggable(
                                    at: _signatureAt,
                                    scale: _signatureScale,
                                    base: const Size(150, 70),
                                    onMove: (v) =>
                                        setState(() => _signatureAt = v),
                                    child: CustomPaint(
                                      painter: UserSignaturePainter(
                                        _signature,
                                      ),
                                    ),
                                  ),
                                if (_showStamp && _stamp != null)
                                  _draggable(
                                    at: _stampAt,
                                    scale: _stampScale,
                                    base: const Size(90, 90),
                                    onMove: (v) => setState(() => _stampAt = v),
                                    child: Image.memory(
                                      _stamp!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                if (_showLogo && _logo != null)
                                  _draggable(
                                    at: _logoAt,
                                    scale: _logoScale,
                                    base: const Size(110, 70),
                                    onMove: (v) => setState(() => _logoAt = v),
                                    child: Image.memory(
                                      _logo!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// عرض صورة داخل التطبيق، وتحتها: توقيع / ختم / شعار، أو الفتح بتطبيق آخر.
/// تُرجع 'sign' أو 'external' أو null.
class DocumentPreviewScreen extends StatelessWidget {
  const DocumentPreviewScreen({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  static bool isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
            title,
            maxLines: 1,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          )),
          centerTitle: true,
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.file(
              File(DocumentStore.localPathFor(path)),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop('sign'),
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('توقيع / ختم / شعار'),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('external'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('فتح بتطبيق آخر'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size.fromHeight(46),
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
}
