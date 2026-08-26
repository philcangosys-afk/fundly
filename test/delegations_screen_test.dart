import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delegations has clear hierarchy, statuses, and creation flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();
    final delegationsRow = find.byKey(const ValueKey('settings-row-التفويضات'));
    await tester.ensureVisible(delegationsRow);
    await tester.pumpAndSettle();
    await tester.tap(delegationsRow);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('delegations-overview')), findsOneWidget);
    expect(find.text('من يمكنه إدارة أعمالك؟'), findsOneWidget);
    expect(find.text('سارية الآن'), findsOneWidget);
    expect(find.text('قريبة الانتهاء'), findsWidgets);
    expect(find.text('موقوفة'), findsOneWidget);
    expect(find.text('3 تفويضات مسجلة'), findsOneWidget);
    expect(find.text('أحمد محمد'), findsOneWidget);

    final delegateName = tester.widget<Text>(find.text('أحمد محمد'));
    expect(delegateName.style?.fontSize, lessThanOrEqualTo(15));
    expect(tester.takeException(), isNull);

    final pausedFilter = find.byKey(const ValueKey('delegation-filter-paused'));
    await tester.ensureVisible(pausedFilter);
    await tester.pumpAndSettle();
    await tester.tap(pausedFilter);
    await tester.pumpAndSettle();
    expect(find.text('سارة عبدالله'), findsOneWidget);
    expect(find.text('أحمد محمد'), findsNothing);

    final createButton = find.byKey(const ValueKey('create-delegation'));
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('إنشاء تفويض'), findsOneWidget);
    expect(find.text('1. الشخص أو الجهة المفوضة'), findsOneWidget);
    expect(find.text('2. نطاق التفويض'), findsOneWidget);
    expect(find.text('3. الصلاحيات المسموحة'), findsOneWidget);
    expect(find.text('4. مدة التفويض'), findsOneWidget);
    expect(find.text('إدارة كاملة'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
