import 'package:flutter/material.dart';

import '../data/user_signature_store.dart';

class SignatureSettingsScreen extends StatefulWidget {
  const SignatureSettingsScreen({super.key});

  @override
  State<SignatureSettingsScreen> createState() =>
      _SignatureSettingsScreenState();
}

class _SignatureSettingsScreenState extends State<SignatureSettingsScreen> {
  final List<List<Offset>> _strokes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final saved = await UserSignatureStore.load();
    if (!mounted) return;
    setState(() {
      _strokes
        ..clear()
        ..addAll(saved.map((stroke) => List<Offset>.from(stroke)));
      _isLoading = false;
    });
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
      appBar: AppBar(title: const Text('التوقيع والختم'), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'التوقيع الاختياري',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ارسم توقيعك داخل المساحة. يبقى محفوظًا حتى تستخدمه في نموذج أو مستند تختاره أنت.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 230,
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
