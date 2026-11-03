import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/entry_status.dart';

/// حالة البنود من تواريخها: المنتهي «منتهية»، والمتكرر بموعده القادم.
void main() {
  final now = DateTime(2026, 11, 3);

  test('الدواء الذي انتهى «إلى تاريخ» يظهر منتهية لا نشطة', () {
    expect(
      entryDerivedStatus('نشطة', {
        'من تاريخ': '25/10/2026',
        'إلى تاريخ': '29/10/2026',
      }, now: now),
      'منتهية',
    );
  });

  test('ما لم ينتهِ بعد يبقى نشطة، والممدَّد بعد انتهائه يعود نشطة', () {
    expect(
      entryDerivedStatus('نشطة', {'إلى تاريخ': '30/11/2026'}, now: now),
      'نشطة',
    );
    expect(
      entryDerivedStatus('منتهية', {'إلى تاريخ': '30/11/2026'}, now: now),
      'نشطة',
    );
    // آخر يوم ما زال نشطًا.
    expect(
      entryDerivedStatus('نشطة', {'إلى تاريخ': '3/11/2026'}, now: now),
      'نشطة',
    );
  });

  test('المستند المنتهي «تاريخ الانتهاء» منتهية، والحالات النهائية كما هي', () {
    expect(
      entryDerivedStatus('نشطة', {'تاريخ الانتهاء': '2026-10-01'}, now: now),
      'منتهية',
    );
    expect(
      entryDerivedStatus('مكتملة', {'إلى تاريخ': '1/1/2026'}, now: now),
      'مكتملة',
    );
    expect(entryDerivedStatus('نشطة', const {}, now: now), 'نشطة');
  });

  test('الراتب الشهري: موعده القادم لا «متأخر»', () {
    final monthly = {'التكرار': 'شهري', 'تفعيل عملية متكررة': 'نعم'};
    expect(
      entryNextRepeatDate(DateTime(2026, 11, 1), monthly, now: now),
      DateTime(2026, 12, 1),
    );
    expect(
      entryNextRepeatDate(
        DateTime(2026, 11, 1),
        monthly,
        now: DateTime(2026, 11, 1),
      ),
      DateTime(2026, 11, 1),
    );
    // يوم 31 في شهر أقصر: آخر يوم فيه.
    expect(
      entryNextRepeatDate(
        DateTime(2026, 1, 31),
        monthly,
        now: DateTime(2026, 2, 10),
      ),
      DateTime(2026, 2, 28),
    );
  });

  test('غير المتكرر: لا موعد قادم', () {
    expect(
      entryNextRepeatDate(DateTime(2026, 11, 1), const {}, now: now),
      isNull,
    );
    expect(
      entryNextRepeatDate(
        DateTime(2026, 11, 1),
        {'التكرار': 'شهري', 'تفعيل عملية متكررة': 'لا'},
        now: now,
      ),
      isNull,
    );
  });

  test('الاشتراك ربع السنوي والتذكير «بدون تكرار»', () {
    expect(
      entryNextRepeatDate(
        DateTime(2026, 1, 15),
        {'التكرار': 'ربع سنوي'},
        now: DateTime(2026, 5, 1),
      ),
      DateTime(2026, 7, 15),
    );
    expect(entryIsRepeating({'التكرار': 'بدون تكرار'}), isFalse);
    expect(
      entryFollowDate(
        type: 'مهمة',
        due: DateTime(2026, 10, 1),
        details: {'التكرار': 'بدون تكرار'},
        now: DateTime(2026, 11, 2),
      ),
      DateTime(2026, 10, 1),
    );
  });

  test('القسط: الموعد أول قسط لم يُسدَّد، والمسدَّد كامله مكتملة', () {
    final details = {
      'القسط 1': '1/10/2026 — 500 درهم',
      'القسط 2': '1/11/2026 — 500 درهم',
      'القسط 3': '1/12/2026 — 500 درهم',
      entryPaymentsKey: '[{"المبلغ":"500"}]',
    };
    expect(
      entryFollowDate(
        type: 'قسط',
        due: DateTime(2026, 10, 1),
        details: details,
        now: DateTime(2026, 10, 20),
      ),
      DateTime(2026, 11, 1),
    );
    expect(
      entryOutcomeStatus(
        type: 'قسط',
        due: DateTime(2026, 10, 1),
        details: {...details, entryPaymentsKey: '[{"المبلغ":"1,500"}]'},
        total: 1500,
      ),
      'مكتملة',
    );
  });

  test('الملاحظة والعهدة والدواء بلا موعد، والمناسبة الماضية منتهية', () {
    for (final type in ['ملاحظات', 'عهدة مالية', 'أدوية']) {
      expect(
        entryFollowDate(type: type, due: DateTime(2026, 1, 1), details: const {}),
        isNull,
        reason: type,
      );
    }
    expect(
      entryOutcomeStatus(
        type: 'مناسبة',
        due: DateTime(2026, 10, 1),
        details: const {},
        total: 0,
        now: DateTime(2026, 11, 2),
      ),
      'منتهية',
    );
  });
}
