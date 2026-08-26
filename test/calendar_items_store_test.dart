import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/calendar_items_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists full calendar details and completion history', () async {
    final record = CalendarRecord(
      id: 'task-1',
      title: 'مراجعة عقد الإيجار',
      type: 'مهمة',
      date: DateTime(2026, 8, 20),
      time: '10:30 ص',
      priority: 'عالية',
      status: 'قادمة',
      description: 'مراجعة البنود مع المستأجر',
      notes: 'الاتصال قبل الموعد',
      remindBeforeDays: 3,
      createdAt: DateTime(2026, 8, 17),
    );

    await CalendarItemsStore.upsert(record);
    var saved = await CalendarItemsStore.load();
    expect(saved, hasLength(1));
    expect(saved.single.description, 'مراجعة البنود مع المستأجر');
    expect(saved.single.priority, 'عالية');

    await CalendarItemsStore.upsert(
      record.copyWith(status: 'مكتملة', completedAt: DateTime(2026, 8, 19, 12)),
    );
    saved = await CalendarItemsStore.load();
    expect(saved.single.status, 'مكتملة');
    expect(saved.single.completedAt, DateTime(2026, 8, 19, 12));

    await CalendarItemsStore.remove('task-1');
    expect(await CalendarItemsStore.load(), isEmpty);
  });
}
