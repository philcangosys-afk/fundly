import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/home_strings.dart';

class RaffleScreen extends StatefulWidget {
  const RaffleScreen({super.key});

  @override
  State<RaffleScreen> createState() => _RaffleScreenState();
}

class _RaffleScreenState extends State<RaffleScreen>
    with SingleTickerProviderStateMixin {
  static const _savedResultKey = 'raffle_saved_result_v1';
  static const _baseSpinTurns = 10;

  final List<TextEditingController> _nameControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  late final AnimationController _spinController;
  late Animation<double> _rotationAnimation;

  final Random _random = Random();
  double _currentRotation = 0;
  bool _isSpinning = false;
  String? _winner;
  List<String> _result = const [];

  static const List<Color> _wheelPalette = [
    Color(0xFF2DD4BF),
    Color(0xFF111827),
    Color(0xFFFFFFFF),
    Color(0xFFE2E8F0),
  ];

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7600),
    );
    _rotationAnimation = AlwaysStoppedAnimation<double>(_currentRotation);
    _spinController.addListener(() {
      if (!mounted) return;
      setState(() {
        _currentRotation = _rotationAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addNameRow() {
    setState(() => _nameControllers.add(TextEditingController()));
  }

  void _removeNameRow(int index) {
    if (_nameControllers.length <= 1) return;
    final controller = _nameControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  List<String> _enteredNames() {
    return _nameControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  double _positiveAngle(double value) {
    final mod = value % (2 * pi);
    return mod < 0 ? mod + (2 * pi) : mod;
  }

  void _spinWheel() {
    final names = _nameControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (names.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسمين على الأقل لتنفيذ القرعة')),
      );
      return;
    }
    if (_isSpinning) return;

    final winnerIndex = _random.nextInt(names.length);
    final extraTurns = _random.nextInt(4);
    final totalTurns = _baseSpinTurns + extraTurns;
    final sectionAngle = (2 * pi) / names.length;
    final offsetToWinnerCenter =
        -(winnerIndex * sectionAngle + (sectionAngle / 2));
    final normalizedOffset = _positiveAngle(offsetToWinnerCenter);
    final targetRotation =
        _currentRotation + (totalTurns * 2 * pi) + normalizedOffset;

    _rotationAnimation =
        Tween<double>(begin: _currentRotation, end: targetRotation).animate(
          CurvedAnimation(parent: _spinController, curve: Curves.easeOutQuart),
        );

    setState(() {
      _winner = null;
      _isSpinning = true;
    });

    _spinController
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        final winner = names[winnerIndex];
        final others = names.where((name) => name != winner).toList()
          ..shuffle(_random);
        setState(() {
          _winner = winner;
          _result = [winner, ...others];
          _isSpinning = false;
          _currentRotation = _positiveAngle(targetRotation);
        });
      });
  }

  Future<void> _saveResult() async {
    if (_result.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedResultKey, jsonEncode(_result));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ نتيجة القرعة')));
  }

  Future<void> _shareResult() async {
    if (_result.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    final lines = [
      HomeStrings.raffleResult,
      for (var i = 0; i < _result.length; i++) '${i + 1}. ${_result[i]}',
    ];
    await SharePlus.instance.share(
      ShareParams(
        subject: HomeStrings.raffle,
        text: lines.join('\n'),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(title: const Text(HomeStrings.raffle), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            const SizedBox(height: 2),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    height: 320,
                    child: CustomPaint(
                      painter: _WheelPainter(
                        labels: _enteredNames().isEmpty
                            ? const ['أضف أسماء']
                            : _enteredNames(),
                        rotation: _currentRotation,
                        colors: _wheelPalette,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    child: Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 54,
                      color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                    ),
                  ),
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: ElevatedButton(
                      onPressed: _spinWheel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 6,
                      ),
                      child: _isSpinning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Spin',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (_winner != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFDE68A),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الفائز: $_winner',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              HomeStrings.raffleHint,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),
            ..._nameControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'الاسم ${index + 1}',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'حذف',
                      onPressed: () => _removeNameRow(index),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _addNameRow,
              icon: const Icon(Icons.add_rounded),
              label: const Text(HomeStrings.raffleAddName),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _spinWheel,
              icon: const Icon(Icons.casino_outlined),
              label: const Text(HomeStrings.raffleDraw),
            ),
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      HomeStrings.raffleResult,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _result.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${i + 1}. ${_result[i]}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saveResult,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text(HomeStrings.raffleSave),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _shareResult,
                            icon: const Icon(Icons.ios_share_rounded),
                            label: const Text(HomeStrings.raffleShare),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.labels,
    required this.rotation,
    required this.colors,
  });

  final List<String> labels;
  final double rotation;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final shadowPaint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center.translate(0, 6), radius - 2, shadowPaint);

    final count = max(labels.length, 1);
    final sweep = (2 * pi) / count;

    for (var i = 0; i < count; i++) {
      final start = -pi / 2 + (i * sweep) + rotation;
      final color = colors[i % colors.length];
      final paint = Paint()..color = color;
      canvas.drawArc(rect, start, sweep, true, paint);

      final borderPaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(rect, start, sweep, true, borderPaint);

      _paintLabel(
        canvas,
        center,
        radius,
        start + (sweep / 2),
        labels[i % labels.length],
        color,
      );
    }

    final innerRing = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawCircle(center, radius * 0.13, innerRing);
    canvas.drawCircle(
      center,
      radius * 0.13,
      Paint()
        ..color = const Color(0xFF0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String text,
    Color segmentColor,
  ) {
    final normalized = (angle % (2 * pi) + (2 * pi)) % (2 * pi);
    final upsideDown = normalized > pi / 2 && normalized < (3 * pi / 2);
    final textAngle = upsideDown ? angle + pi : angle;

    final isDark = segmentColor.computeLuminance() < 0.45;
    final labelRadius = radius * 0.56;
    final dx = center.dx + cos(angle) * labelRadius;
    final dy = center.dy + sin(angle) * labelRadius;

    final textPainter = TextPainter(
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: isDark ? Colors.white : const Color(0xFF0B1324),
        ),
      ),
    )..layout(maxWidth: radius * 0.52);

    canvas.save();
    canvas.translate(dx, dy);
    canvas.rotate(textAngle);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    if (oldDelegate.rotation != rotation) return true;
    if (oldDelegate.labels.length != labels.length) return true;
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != oldDelegate.labels[i]) return true;
    }
    return false;
  }
}
