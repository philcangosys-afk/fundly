import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:image_picker/image_picker.dart';

import '../data/user_signature_store.dart';
import '../data/user_stamp_store.dart';

class SignatureSettingsScreen extends StatefulWidget {
  const SignatureSettingsScreen({super.key});

  @override
  State<SignatureSettingsScreen> createState() =>
      _SignatureSettingsScreenState();
}

class _SignatureSettingsScreenState extends State<SignatureSettingsScreen> {
  final List<List<Offset>> _strokes = [];
  bool _isLoading = true;

  /// صورة الختم المعروضة حاليًا، و_savedStamp هي النسخة المحفوظة فعليًا
  /// على الجهاز — الفرق بينهما هو ما يجعل زر "حفظ الختم" يعمل أو يُعطَّل.
  Uint8List? _stampBytes;
  Uint8List? _savedStamp;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final saved = await UserSignatureStore.load();
    final stamp = await UserStampStore.load();
    if (!mounted) return;
    setState(() {
      _strokes
        ..clear()
        ..addAll(saved.map((stroke) => List<Offset>.from(stroke)));
      _stampBytes = stamp;
      _savedStamp = stamp;
      _isLoading = false;
    });
  }

  Future<void> _pickStamp(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 900,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _stampBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الصور على هذا الجهاز')),
      );
    }
  }

  void _openStampSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('اختيار من المعرض'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickStamp(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('التقاط صورة للختم'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickStamp(ImageSource.camera);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveStamp() async {
    final bytes = _stampBytes;
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await UserStampStore.save(bytes);
    if (!mounted) return;
    setState(() => _savedStamp = bytes);
    messenger.showSnackBar(const SnackBar(content: Text('تم حفظ الختم')));
  }

  Future<void> _removeStamp() async {
    final messenger = ScaffoldMessenger.of(context);
    await UserStampStore.clear();
    if (!mounted) return;
    setState(() {
      _stampBytes = null;
      _savedStamp = null;
    });
    messenger.showSnackBar(const SnackBar(content: Text('تم حذف الختم')));
  }

  void _startStroke(Offset point, Size size) {
    setState(() => _strokes.add([_normalize(point, size)]));
  }

  void _continueStroke(Offset point, Size size) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(_normalize(point, size)));
  }

  Offset _normalize(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0, 1),
    (point.dy / size.height).clamp(0, 1),
  );

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    await UserSignatureStore.save(_strokes);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('تم حفظ التوقيع')));
  }

  Future<void> _clear() async {
    setState(_strokes.clear);
    await UserSignatureStore.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: const Text('التوقيع الإلكتروني والختم'),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'التوقيع الإلكتروني والختم',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ارسم توقيعك داخل المساحة، وارفع صورة ختمك أسفلها. يبقيان محفوظين حتى تستخدمهما في نموذج أو مستند تختاره أنت.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 165,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) =>
                              _startStroke(details.localPosition, size),
                          onPanUpdate: (details) =>
                              _continueStroke(details.localPosition, size),
                          child: CustomPaint(
                            painter: UserSignaturePainter(_strokes),
                            size: Size.infinite,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _strokes.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('مسح'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _strokes.isEmpty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ التوقيع'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'الختم',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'أضف صورة ختمك أو ارفعها من المعرض، ثم احفظها لتظهر مع التوقيع في المستندات.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            // مساحة الختم: فارغة = منطقة قابلة للضغط ترفع صورة، وممتلئة =
            // معاينة الختم نفسه.
            GestureDetector(
              onTap: _openStampSourceSheet,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: _stampBytes == null
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.approval_outlined,
                            size: 30,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'اضغط لإضافة أو رفع صورة الختم',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      )
                    : Image.memory(_stampBytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_stampBytes == null && _savedStamp == null)
                        ? null
                        : _removeStamp,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('حذف الختم'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    // يُعطَّل حين لا توجد صورة، أو حين تكون الصورة
                    // المعروضة هي المحفوظة أصلًا فلا شيء جديد ليُحفظ.
                    onPressed:
                        (_stampBytes == null || _stampBytes == _savedStamp)
                        ? null
                        : _saveStamp,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ الختم'),
                  ),
                ),
              ],
            ),
            if (_stampBytes != null) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _openStampSourceSheet,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('استبدال صورة الختم'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UserSignaturePainter extends CustomPainter {
  const UserSignaturePainter(
    this.strokes, {
    this.color = const Color(0xFF0F172A),
  });

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      final first = stroke.first;
      path.moveTo(first.dx * size.width, first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant UserSignaturePainter oldDelegate) => true;
}
