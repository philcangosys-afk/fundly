import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/home_summary_service.dart';

/// «متأخر» في الملخص الشامل والتقارير يطابق ما يظهر عند فتح العنصر.
void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  SummaryItem item({
    String scope = 'الالتزامات الشخصية',
    DateTime? date,
    String status = 'نشطة',
    bool followsDate = true,
    DateTime? followDate,
    bool canBeOverdue = true,
  }) => SummaryItem(
    scope: scope,
    section: 's',
    type: 't',
    title: 'x',
    date: date,
    status: status,
    followsDate: followsDate,
    followDate: followDate,
    canBeOverdue: canBeOverdue,
  );

  test('فات موعده ولم يُغلق = متأخر', () {
    expect(item(date: yesterday).isOverdue, isTrue);
  });

  test('موعده اليوم: مستحق لا متأخر', () {
    expect(item(date: today).isOverdue, isFalse);
    // «قريبة» = خلال 7 أيام بعد اليوم، واليوم نفسه «مستحقة».
    expect(item(date: today).isDueSoon, isFalse);
    expect(item(date: today.add(const Duration(days: 3))).isDueSoon, isTrue);
    expect(item(date: today.add(const Duration(days: 20))).isDueSoon, isFalse);
  });

  test('المغلق والملغى والمؤرشف لا يتأخر', () {
    for (final s in ['مكتملة', 'ملغاة', 'مؤرشف', 'تمت التسوية', 'منتهية']) {
      expect(item(date: yesterday, status: s).isOverdue, isFalse, reason: s);
    }
  });

  test('تاريخ إضافة الشخص لا يجعله متأخرًا', () {
    expect(
      item(scope: 'الأفراد والجهات', date: yesterday, followsDate: false)
          .isOverdue,
      isFalse,
    );
  });

  test('مصروف تمّ (غير متكرر) لا يتأخر، والمتكرر بموعده القادم', () {
    expect(item(date: yesterday, followsDate: false).isOverdue, isFalse);
    final next = today.add(const Duration(days: 5));
    final repeating = item(date: yesterday, followDate: next);
    expect(repeating.isOverdue, isFalse);
    expect(repeating.isDueSoon, isTrue);
    expect(repeating.followDay, next);
  });

  test('نهاية عقد الأصل: منتهٍ لا متأخر', () {
    expect(item(date: yesterday, canBeOverdue: false).isOverdue, isFalse);
  });
}
