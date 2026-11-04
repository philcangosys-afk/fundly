import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/fundly_auth.dart';
import 'package:fundly/l10n/app_language.dart';
import 'package:fundly/screens/account_screens.dart';
import 'package:fundly/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// مسارات الضيف والتسجيل والخروج (اختبار تشغيل فعلي للواجهة).
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FundlyAuth.mode = null;
    FundlyAuth.languageChosen = false;
  });

  Widget app(Widget home) => MaterialApp(home: home);
  const home = Scaffold(body: Center(child: Text('HOME')));

  /// القائمة تبني عناصرها عند الاقتراب منها: تمرير حتى يُبنى العنصر، ثم
  /// إظهاره داخل الشاشة، ثم الضغط عليه.
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

  testWidgets('أول فتح: اختيار اللغة فقط ثم التطبيق كضيف', (tester) async {
    await tester.pumpWidget(app(const LoginGate(child: home)));
    await tester.pumpAndSettle();
    expect(find.byType(FirstLanguageScreen), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    // لا عملة افتراضية: «متابعة» معطّل حتى تُختار العملة.
    await tapVisible(tester, find.text('متابعة'));
    expect(find.text('HOME'), findsNothing);
    await tapVisible(tester, find.byKey(const ValueKey('first-run-currency')));
    await tester.tap(find.text('دولار أمريكي (USD)').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('متابعة'));
    expect(find.text('HOME'), findsOneWidget);
    expect(FundlyAuth.isGuest, isTrue);
    expect(FundlyAuth.languageChosen, isTrue);
  });

  testWidgets('الضيف يدخل التطبيق مباشرة في الفتح التالي', (tester) async {
    FundlyAuth.languageChosen = true;
    FundlyAuth.mode = FundlyAuth.modeGuest;
    await tester.pumpWidget(app(const LoginGate(child: home)));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(FirstLanguageScreen), findsNothing);
  });

  testWidgets('بعد الخروج: شاشة الدخول هي الأساس ولا رجوع منها', (
    tester,
  ) async {
    FundlyAuth.languageChosen = true;
    FundlyAuth.mode = null;
    await tester.pumpWidget(app(const LoginGate(child: home)));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);

    await tapVisible(tester, find.text('تصفّح كضيف'));
    expect(find.text('HOME'), findsOneWidget);
    expect(FundlyAuth.isGuest, isTrue);
  });

  testWidgets('التسجيل: الموافقة على الشروط إلزامية ثم رمز OTP 123456', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SignUpScreen()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'زين العابدين خلف');
    await tester.enterText(fields.at(2), 'test@example.com');
    await tester.enterText(fields.at(4), 'pass1234');
    await tester.enterText(fields.at(5), 'pass1234');

    await tapVisible(tester, find.text('إنشاء الحساب'));
    expect(
      find.text('وافق على شروط الاستخدام وسياسة الخصوصية للمتابعة'),
      findsOneWidget,
    );
    expect(find.text('رمز التحقق'), findsNothing);

    await tapVisible(tester, find.byType(Checkbox));
    await tapVisible(tester, find.text('إنشاء الحساب'));
    expect(find.text('رمز التحقق'), findsOneWidget);
    expect(find.text('الرمز الخاص بك: 123456'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '111111');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('رمز التحقق غير صحيح'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('رمز التحقق'), findsNothing);
  });

  test('تفاصيل الأخطاء التقنية لا تظهر للمستخدم', () {
    expect(
      AppTr.hideTechnicalForTest(
        'تعذّر الحفظ: PostgrestException(message: relation "x", code: 42P01)',
      ),
      'تعذّر الحفظ',
    );
    expect(
      AppTr.hideTechnicalForTest(
        'AuthException(message: لم يتم تسجيل الدخول — سجّل الدخول بحسابك, '
        'statusCode: null, code: null)',
      ),
      'لم يتم تسجيل الدخول — سجّل الدخول بحسابك',
    );
    expect(
      AppTr.hideTechnicalForTest('TimeoutException after 0:00:20.000000'),
      'حدث خطأ غير متوقع — حاول مرة أخرى',
    );
    expect(AppTr.hideTechnicalForTest('نص عادي: 123'), 'نص عادي: 123');
  });
}
