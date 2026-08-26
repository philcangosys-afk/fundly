import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/screens/document_templates_screen.dart';
import 'package:fundly/screens/profile_settings_screen.dart';
import 'package:fundly/screens/projects_activities_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'document center exposes all requested templates and expiry fields',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DocumentTemplatesScreen()),
      );

      for (final type in const [
        'إيصال أمانة',
        'إيصال استلام وتسليم',
        'فاتورة',
        'تقرير ضريبي',
        'عقد',
        'إنذار',
      ]) {
        expect(find.text(type), findsOneWidget);
      }

      await tester.tap(find.text('فاتورة'));
      await tester.pumpAndSettle();
      expect(find.text('اسم الجهة'), findsOneWidget);
      expect(find.text('الرقم الضريبي'), findsOneWidget);
      expect(find.text('تاريخ الانتهاء'), findsOneWidget);
      expect(find.text('التذكير قبل الانتهاء'), findsOneWidget);
    },
  );

  testWidgets('profile opens the optional signature canvas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileSettingsScreen()));

    await tester.tap(find.text('التوقيع والختم'));
    await tester.pumpAndSettle();
    expect(find.text('التوقيع الاختياري'), findsOneWidget);
    expect(find.text('حفظ التوقيع'), findsOneWidget);
  });

  testWidgets('property form contains structured annex checklist', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProjectsActivitiesScreen()),
    );

    await tester.tap(find.text('إضافة').last);
    await tester.pumpAndSettle();
    expect(find.text('ملحقات العقار'), findsOneWidget);

    await tester.tap(find.text('ملحقات العقار'));
    await tester.pumpAndSettle();
    expect(find.text('ممرات'), findsOneWidget);
    expect(find.text('درج'), findsOneWidget);
    expect(find.text('سطح'), findsOneWidget);
    expect(find.text('بلكونات'), findsOneWidget);
    expect(find.text('غرفة الاتصالات'), findsOneWidget);
    expect(find.text('غرفة الكهرباء'), findsOneWidget);
    expect(find.text('غرفة الدفاع المدني'), findsOneWidget);
    expect(find.text('إضافة ملحق آخر'), findsOneWidget);
  });
}
