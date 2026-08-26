import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/screens/profile_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'settings rows are lightweight, arrowed, and navigate logically',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileSettingsScreen(
            delegationsPage: Scaffold(body: Text('صفحة إدارة التفويضات')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNWidgets(10));
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
      expect(find.text('البيانات الشخصية'), findsOneWidget);
      expect(find.text('قوالب المستندات'), findsOneWidget);
      expect(find.text('التفويضات'), findsOneWidget);
      expect(find.text('التقويم'), findsNothing);
      expect(find.text('المظهر'), findsNothing);
      expect(find.text('النسخ الاحتياطي والتصدير'), findsNothing);

      await tester.ensureVisible(find.text('التفويضات'));
      await tester.tap(find.text('التفويضات'));
      await tester.pumpAndSettle();
      expect(find.text('صفحة إدارة التفويضات'), findsOneWidget);

      Navigator.of(tester.element(find.text('صفحة إدارة التفويضات'))).pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('اللغة والعملة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اللغة والعملة'));
      await tester.pumpAndSettle();
      expect(find.text('لغة التطبيق'), findsOneWidget);
      expect(find.text('العملة الافتراضية'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('الأمان والخصوصية'));
      await tester.tap(find.text('الأمان والخصوصية'));
      await tester.pumpAndSettle();
      expect(find.text('قفل التطبيق'), findsOneWidget);
      expect(find.text('إخفاء المبالغ الحساسة'), findsOneWidget);
    },
  );

  testWidgets('personal data opens the redesigned profile editor', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('البيانات الشخصية'));
    await tester.pumpAndSettle();

    expect(find.text('تعديل الملف الشخصي'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-photo-picker')), findsOneWidget);
    expect(find.text('الاسم بالكامل'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('المدينة'), findsOneWidget);
    expect(find.text('اللغة'), findsOneWidget);
    expect(find.text('حسابات السوشيال ميديا'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-profile-data')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-profile-data')));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings_profile_name'), 'عبدالعزيز الهاجري');
    expect(preferences.getString('settings_profile_language'), 'العربية');
  });
}
