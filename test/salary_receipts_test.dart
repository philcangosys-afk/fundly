import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/salary_income_sync.dart';
import 'package:fundly/data/salary_receipt_pdf.dart';
import 'package:fundly/data/salary_receipts.dart';
import 'package:fundly/screens/salary_receipts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// سند القبض / الراتب: اسم الموظف عند المرسل، ملف PDF، والإيراد عند المستلم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  final approved = SalaryReceipt(
    id: '6ae8539b-e83a-9019-991c-37b4aaaa0001',
    employeeFnd: 'FND-G6RE-9RDL',
    employeeName: 'عبدالعزيز حمود منصر',
    ownerName: 'زين العابدين خلف',
    period: '2026-11',
    receiptDate: '2/11/2026',
    basic: 2000,
    allowances: 200,
    overtime: 100,
    total: 2300,
    paid: 2300,
    currency: 'درهم',
    notes: 'راتب عن انجاز عمل شهر 10',
    signMode: SalaryReceipt.signRemote,
    status: SalaryReceipt.statusApproved,
    signature: '[[[0.1,0.2],[0.5,0.6],[0.8,0.3]],[[0.2,0.8],[0.7,0.8]]]',
    signedAt: DateTime(2026, 11, 2, 15, 44),
  );

  test('PDF: سند واحد وعدة سندات (صفحة لكل سند)', () async {
    final one = await buildSalaryReceiptsPdf([approved]);
    expect(String.fromCharCodes(one.take(4)), '%PDF');
    final pending = SalaryReceipt(
      id: '6ae8539b-e83a-9019-991c-37b4aaaa0002',
      kind: SalaryReceipt.kindGeneral,
      employeeName: 'سارة أحمد',
      ownerName: 'زين العابدين خلف',
      period: '2026-11',
      receiptDate: '3/11/2026',
      total: 500,
      paid: 500,
      description: 'دفعة مقدمة',
    );
    final two = await buildSalaryReceiptsPdf([approved, pending]);
    expect(String.fromCharCodes(two.take(4)), '%PDF');
    expect(two.length, greaterThan(one.length));
    expect(salaryPdfFileName([approved]), 'salary-receipt-2026-11.pdf');
    expect(salaryPdfFileName([approved, pending]), 'salary-receipts-2.pdf');
  });

  test('الإيراد عند المستلم مرتبط بالسند', () {
    final income = SalaryIncomeSync.incomeFor(approved);
    expect(income.entryType, 'إيراد');
    expect(income.amount, 2300);
    expect(income.details[SalaryIncomeSync.receiptKey], approved.id);
    expect(income.details['التصنيف الرئيسي'], 'الراتب/معاش');
    expect(income.title, 'راتب نوفمبر 2026 — زين العابدين خلف');
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> typeIn(
    WidgetTester tester,
    Finder finder,
    String text, {
    double delta = 200,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  testWidgets('المرسل: اسم الموظف إلزامي (اسمين على الأقل) في الحالتين', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SalaryReceiptFormScreen()),
    );
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('salary-employee-name'));
    expect(name, findsOneWidget);

    await typeIn(tester, name, 'زين');
    await typeIn(
      tester,
      find.widgetWithText(TextField, 'الراتب الأساسي'),
      '2000',
    );
    await tapVisible(tester, find.text('التوقيع والحفظ'));
    expect(
      find.text('اكتب اسم الموظف الحقيقي من اسمين على الأقل'),
      findsOneWidget,
    );

    // اسمين: يُقبل ويفتح التوقيع على هذا الجوال.
    await typeIn(tester, name, 'زين خلف', delta: -200);
    await tapVisible(tester, find.text('التوقيع والحفظ'));
    // نافذة التوقيع باسم الموظف كما كتبه المرسل.
    expect(find.text('توقيع زين خلف'), findsOneWidget);
  });

  testWidgets('الإرسال للاعتماد: حقل اسم الموظف ظاهر أيضًا', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SalaryReceiptFormScreen()),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('إرسال للاعتماد والتوقيع').first);
    expect(
      find.byKey(const ValueKey('salary-employee-name')),
      findsOneWidget,
    );
  });
}
