import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/calendar_items_store.dart';
import 'package:fundly/data/home_dashboard_service.dart';
import 'package:fundly/screens/smart_calendar_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows saved day item, activity log, and full add form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final today = DateTime.now();
    await CalendarItemsStore.upsert(
      CalendarRecord(
        id: 'visible-task',
        title: 'مهمة ظاهرة في التقويم',
        type: 'مهمة',
        date: today,
        time: '10:00 ص',
        priority: 'عالية',
        status: 'قادمة',
        description: 'تفاصيل المهمة',
        notes: '',
        remindBeforeDays: 1,
        createdAt: today,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SmartCalendarScreen(
          metricsLoader: () async => const HomeDashboardMetrics.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مهمة ظاهرة في التقويم'), findsWidgets);
    expect(find.text('سجل النشاط'), findsOneWidget);
    expect(find.textContaining('تمت إضافة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-calendar-record')));
    await tester.pumpAndSettle();

    expect(find.text('إضافة عنصر جديد'), findsOneWidget);
    expect(find.text('التفاصيل'), findsOneWidget);
    expect(find.text('الأولوية'), findsOneWidget);
    expect(find.text('التذكير قبل الموعد'), findsOneWidget);
    expect(find.text('ملاحظات'), findsOneWidget);
  });
}
