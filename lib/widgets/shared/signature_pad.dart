import 'package:flutter/material.dart' hide Text, Align;

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// رسم التوقيع: خطوط بنقاط نسبية (0..1) داخل المربع.
class SignatureStrokesPainter extends CustomPainter {
  const SignatureStrokesPainter(
    this.strokes, {
    this.color = const Color(0xFF022E2A),
  });

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      if (stroke.length == 1) {
        path.lineTo(
          stroke.first.dx * size.width + 0.5,
          stroke.first.dy * size.height + 0.5,
        );
      }
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignatureStrokesPainter oldDelegate) => true;
}

/// عرض توقيع محفوظ داخل مربع.
class SignatureView extends StatelessWidget {
  const SignatureView({super.key, required this.strokes, this.size = 140});

  final List<List<Offset>> strokes;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rInner),
      border: Border.all(color: AppTheme.hairline),
    ),
    child: CustomPaint(painter: SignatureStrokesPainter(strokes)),
  );
}

/// نافذة صغيرة: الاسم الثلاثي (الأول والثاني والأخير) قبل إكمال الاعتماد.
Future<String?> askFullName(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialog) {
        final parts = ctrl.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .length;
        final ok = parts >= 3;
        return Directionality(
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            backgroundColor: AppTheme.page,
            title: const Text('اسمك الثلاثي'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اكتب اسمك الأول والثاني والأخير كما في الهوية أو الإقامة '
                  'ليُكتب في السند.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textDirection: AppTr.uiDir,
                  onChanged: (_) => setDialog(() {}),
                  decoration: InputDecoration(
                    labelText: AppTr.tr('الاسم الثلاثي *'),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (ctrl.text.trim().isNotEmpty && !ok)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'ثلاثة أسماء على الأقل',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.brand),
                onPressed: ok
                    ? () => Navigator.pop(
                        dialogContext,
                        ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' '),
                      )
                    : null,
                child: const Text('إكمال الاعتماد'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// شاشة مربعة للتوقيع باللمس. تعيد الخطوط، أو null عند الإلغاء.
Future<List<List<Offset>>?> showSignaturePad(
  BuildContext context, {
  required String title,
  String subtitle = '',
  String confirmLabel = 'اعتماد التوقيع',
}) {
  return showDialog<List<List<Offset>>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SignaturePadDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
    ),
  );
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  final String title;
  final String subtitle;
  final String confirmLabel;

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<List<Offset>> _strokes = [];

  Offset _normalize(Offset point, double side) => Offset(
    (point.dx / side).clamp(0.0, 1.0),
    (point.dy / side).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Dialog(
        backgroundColor: AppTheme.page,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                textAlign: AppTr.alignEnd,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.muted,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // المربع: التوقيع بالإصبع.
              AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.maxWidth;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppTheme.rInner),
                        border: Border.all(
                          color: AppTheme.brand.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => setState(
                          () => _strokes.add([_normalize(e.localPosition, side)]),
                        ),
                        onPointerMove: (e) {
                          if (_strokes.isEmpty) return;
                          setState(
                            () => _strokes.last.add(
                              _normalize(e.localPosition, side),
                            ),
                          );
                        },
                        child: Stack(
                          children: [
                            if (_strokes.isEmpty)
                              const Center(
                                child: Text(
                                  'وقّع هنا بإصبعك',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: SignatureStrokesPainter(_strokes),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _strokes.isEmpty
                        ? null
                        : () => setState(_strokes.clear),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('مسح'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                    ),
                    onPressed: _strokes.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            [for (final s in _strokes) List<Offset>.of(s)],
                          ),
                    child: Text(widget.confirmLabel),
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
