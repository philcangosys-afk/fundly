import 'dart:math';

import 'package:flutter/material.dart' hide Text, Align;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../data/app_settings.dart';
import '../widgets/shared/app_design.dart';

/// كل ما يُحسب من تاريخ ميلاد واحد: العمر، العدّ التنازلي، البرج، حجر
/// الميلاد، الفصل، وتاريخ الميلاد القادم ويومه.
///
/// المستخدم يكتب اسمه وتاريخ ميلاده في صفحة الحساب فقط، والباقي يُشتقّ
/// هنا بلا أي إدخال إضافي.
class BirthdayInfo {
  const BirthdayInfo({
    required this.name,
    required this.birthDate,
    required this.nextBirthday,
    required this.currentAge,
    required this.nextAge,
    required this.daysLeft,
  });

  final String name;
  final DateTime birthDate;
  final DateTime nextBirthday;
  final int currentAge;
  final int nextAge;
  final int daysLeft;

  bool get isToday => daysLeft == 0;

  static const List<String> _weekdays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static String weekdayOf(DateTime date) => _weekdays[date.weekday - 1];

  static String format(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';

  /// يقرأ التاريخ المحفوظ بصيغة يوم/شهر/سنة ويحسب كل شيء، أو null إن لم
  /// يسجّل المستخدم تاريخ ميلاده بعد.
  static BirthdayInfo? fromSettings() {
    final raw = AppSettings.instance.birthday.trim();
    final parts = raw.split('/');
    if (parts.length < 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final birth = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(today.year, month, day);
    if (next.isBefore(today)) next = DateTime(today.year + 1, month, day);
    var age = today.year - year;
    final hadBirthday =
        today.month > month || (today.month == month && today.day >= day);
    if (!hadBirthday) age -= 1;
    return BirthdayInfo(
      name: AppSettings.instance.name,
      birthDate: birth,
      nextBirthday: next,
      currentAge: age < 0 ? 0 : age,
      nextAge: (age < 0 ? 0 : age) + 1,
      daysLeft: next.difference(today).inDays,
    );
  }

  /// البرج ورمزه من يوم الميلاد وشهره.
  (String, String) get zodiac {
    final d = birthDate.day;
    final m = birthDate.month;
    bool inRange(int m1, int d1, int m2, int d2) =>
        (m == m1 && d >= d1) || (m == m2 && d <= d2);
    if (inRange(3, 21, 4, 19)) return ('الحمل', '♈');
    if (inRange(4, 20, 5, 20)) return ('الثور', '♉');
    if (inRange(5, 21, 6, 20)) return ('الجوزاء', '♊');
    if (inRange(6, 21, 7, 22)) return ('السرطان', '♋');
    if (inRange(7, 23, 8, 22)) return ('الأسد', '♌');
    if (inRange(8, 23, 9, 22)) return ('العذراء', '♍');
    if (inRange(9, 23, 10, 22)) return ('الميزان', '♎');
    if (inRange(10, 23, 11, 21)) return ('العقرب', '♏');
    if (inRange(11, 22, 12, 21)) return ('القوس', '♐');
    if (inRange(12, 22, 1, 19)) return ('الجدي', '♑');
    if (inRange(1, 20, 2, 18)) return ('الدلو', '♒');
    return ('الحوت', '♓');
  }

  /// حجر الميلاد حسب شهر الميلاد.
  String get birthstone => switch (birthDate.month) {
    1 => 'العقيق الأحمر',
    2 => 'الجمشت',
    3 => 'الأكوامارين',
    4 => 'الألماس',
    5 => 'الزمرد',
    6 => 'اللؤلؤ',
    7 => 'الياقوت الأحمر',
    8 => 'الزبرجد',
    9 => 'الياقوت الأزرق',
    10 => 'الأوبال',
    11 => 'التوباز',
    _ => 'الفيروز',
  };

  /// الفصل الذي وُلد فيه.
  String get season => switch (birthDate.month) {
    3 || 4 || 5 => 'ربيع',
    6 || 7 || 8 => 'صيف',
    9 || 10 || 11 => 'خريف',
    _ => 'شتاء',
  };

  /// نص العدّ التنازلي بصيغة عربية سليمة.
  String get countdown {
    if (daysLeft == 0) return 'اليوم';
    if (daysLeft == 1) return 'باقي يوم واحد';
    if (daysLeft == 2) return 'باقي يومان';
    if (daysLeft <= 10) return 'باقي $daysLeft أيام';
    return 'باقي $daysLeft يومًا';
  }
}

/// مفتاح «احتُفل بميلاد هذه السنة» حتى لا تتكرر النافذة في اليوم نفسه.
const String _kBirthdayShownKey = 'birthday_celebrated_year';

/// يفتح نافذة الميلاد تلقائيًا مرة واحدة في يوم الميلاد نفسه.
Future<void> maybeCelebrateBirthday(BuildContext context) async {
  final info = BirthdayInfo.fromSettings();
  if (info == null || !info.isToday) return;
  final prefs = await SharedPreferences.getInstance();
  final year = DateTime.now().year;
  if (prefs.getInt(_kBirthdayShownKey) == year) return;
  await prefs.setInt(_kBirthdayShownKey, year);
  if (!context.mounted) return;
  await showBirthdaySheet(context);
}

/// نافذة الميلاد: تهنئة وقصاصات ملوّنة، ثم بطاقة المعلومات المشتقّة.
Future<void> showBirthdaySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _BirthdaySheet(),
  );
}

class _BirthdaySheet extends StatefulWidget {
  const _BirthdaySheet();

  @override
  State<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<_BirthdaySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    final info = BirthdayInfo.fromSettings();
    // القصاصات تتساقط في يوم الميلاد فقط؛ وقبله تُعرض المعلومات بهدوء.
    if (info != null && info.isToday) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = BirthdayInfo.fromSettings();
    return Directionality(
      textDirection: AppTr.uiDir,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.95,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.page,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.rCard),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: info == null
              ? _buildEmpty(context)
              : Stack(
                  children: [
                    ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.hairline,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildGreeting(info),
                        const SizedBox(height: 14),
                        _buildInfoCard(info),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.brand,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'تمام',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (info.isToday)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) => CustomPaint(
                              painter: _ConfettiPainter(_controller.value),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cake_outlined, size: 44, color: AppTheme.goldDark),
          const SizedBox(height: 12),
          const Text(
            'لم تسجّل تاريخ ميلادك بعد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'اكتب «تاريخ الميلاد» في تعديل الملف الشخصي — والباقي يحسبه '
            'التطبيق لك.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              fontWeight: FontWeight.w600,
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting(BirthdayInfo info) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            info.name,
            textAlign: TextAlign.center,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.title,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            info.isToday
                ? 'كل عام وأنت بخير يا ${info.name} — نتمنى لك سنة مليئة '
                      'بالسعادة والنجاح!'
                : 'اقترب ميلادك يا ${info.name} — استعد للاحتفال!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.7,
              fontWeight: FontWeight.w700,
              color: AppTheme.body,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
            ),
            child: Text(
              info.countdown,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BirthdayInfo info) {
    final (sign, symbol) = info.zodiac;
    final rows = <(IconData, String, String)>[
      (
        Icons.calendar_month_outlined,
        'تاريخ الميلاد',
        '${BirthdayInfo.weekdayOf(info.birthDate)} · '
            '${BirthdayInfo.format(info.birthDate)}',
      ),
      (Icons.cake_outlined, 'عمرك الآن', '${info.currentAge} سنة'),
      (Icons.celebration_outlined, 'العمر القادم', '${info.nextAge} سنة'),
      (Icons.hourglass_bottom_rounded, 'العدّ التنازلي', info.countdown),
      (Icons.star_rounded, 'البرج', '$symbol $sign'),
      (Icons.diamond_outlined, 'حجر الميلاد', info.birthstone),
      (Icons.wb_sunny_outlined, 'الفصل', info.season),
      (
        Icons.event_available_outlined,
        'ميلادك القادم',
        '${BirthdayInfo.weekdayOf(info.nextBirthday)} · '
            '${BirthdayInfo.format(info.nextBirthday)}',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: AppTheme.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppTheme.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(AppTheme.rIcon),
                    ),
                    child: Icon(
                      rows[i].$1,
                      size: 19,
                      color: AppTheme.brandMid,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          rows[i].$2,
                          textAlign: AppTr.alignEnd,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rows[i].$3,
                          textAlign: AppTr.alignEnd,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                      ],
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
}

/// قصاصات ملوّنة متساقطة — مرسومة بالكود بلا أي حزمة خارجية.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);

  final double progress;

  static const _colors = [
    Color(0xFF0E7161),
    Color(0xFFCE8422),
    Color(0xFFC4392E),
    Color(0xFF1F6FEB),
    Color(0xFF178F7B),
    Color(0xFFF2A93F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 46; i++) {
      final x = random.nextDouble() * size.width;
      final speed = 0.6 + random.nextDouble() * 0.8;
      final drift = (random.nextDouble() - 0.5) * 40;
      final start = random.nextDouble();
      final phase = (progress * speed + start) % 1.0;
      final y = phase * (size.height + 80) - 40;
      final angle = (phase * 10 + i) % (pi * 2);
      final width = 5 + random.nextDouble() * 5;
      final height = 9 + random.nextDouble() * 7;
      paint.color = _colors[i % _colors.length].withValues(
        alpha: 0.85 - phase * 0.35,
      );
      canvas.save();
      canvas.translate(x + drift * phase, y);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: width,
            height: height,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
