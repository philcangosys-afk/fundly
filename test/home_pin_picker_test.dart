import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens one PIN picker and pins a record from a module tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('الملخص الشامل'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-pin-picker')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-pin-picker')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('تثبيت عنصر في الصفحة الرئيسية'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-tab-personal')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-tab-shared')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-tab-people')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-tab-assets')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pin-tab-shared')));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة إلى دبي'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pin-item-shared:dubai-trip')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.push_pin_rounded), findsWidgets);

    await tester.tap(find.byTooltip('إغلاق'));
    await tester.pumpAndSettle();
    expect(find.text('الرحلة إلى دبي'), findsOneWidget);

    final panelRect = tester.getRect(
      find.byKey(const ValueKey('home-summary-pin-panel')),
    );
    final pinnedRect = tester.getRect(
      find.byKey(const ValueKey('home-pinned-card-shared:dubai-trip')),
    );
    expect(pinnedRect.top, greaterThan(panelRect.top));
    expect(pinnedRect.bottom, lessThanOrEqualTo(panelRect.bottom - 8));
    expect(pinnedRect.height, inInclusiveRange(48, 52));
    expect(pinnedRect.width, lessThanOrEqualTo(152));
    expect(panelRect.height, 144);
  });
}
