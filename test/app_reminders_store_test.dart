import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/app_reminders_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores, updates and removes expiry reminders', () async {
    final expiry = DateTime(2027, 3, 10);
    await AppRemindersStore.upsert(
      AppReminder(
        id: 'document-1',
        title: 'ضمان المصعد',
        module: 'العقارات والأنشطة التجارية',
        expiryDate: expiry,
        remindBeforeDays: 14,
      ),
    );

    var reminders = await AppRemindersStore.load();
    expect(reminders, hasLength(1));
    expect(reminders.single.expiryDate, expiry);
    expect(reminders.single.reminderDate, DateTime(2027, 2, 24));

    await AppRemindersStore.upsert(
      AppReminder(
        id: 'document-1',
        title: 'ضمان المصعد المحدث',
        module: 'العقارات والأنشطة التجارية',
        expiryDate: expiry,
        remindBeforeDays: 30,
      ),
    );
    reminders = await AppRemindersStore.load();
    expect(reminders, hasLength(1));
    expect(reminders.single.title, 'ضمان المصعد المحدث');
    expect(reminders.single.remindBeforeDays, 30);

    await AppRemindersStore.remove('document-1');
    expect(await AppRemindersStore.load(), isEmpty);
  });

  test('parses display dates and reminder labels', () {
    expect(
      AppRemindersStore.parseDisplayDate('07/11/2028'),
      DateTime(2028, 11, 7),
    );
    expect(AppRemindersStore.parseDisplayDate('غير محدد'), isNull);
    expect(AppRemindersStore.reminderDaysFromLabel('قبل أسبوعين'), 14);
    expect(AppRemindersStore.reminderDaysFromLabel('قبل شهر'), 30);
  });
}
