import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import '../data/app_settings.dart';
import '../data/fundly_account.dart';
import '../data/fundly_auth.dart';
import 'account_screens.dart';

/// بوابة الدخول: أول فتح على الجوال يُسأل عن اللغة فقط، ثم يفتح التطبيق
/// مباشرة — بالحساب إن كان داخلًا، وإلا يتصفّح كضيف ويُطلب منه الدخول أو
/// التسجيل عند أول إدخال.
class LoginGate extends StatefulWidget {
  const LoginGate({super.key, required this.child});

  final Widget child;

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  @override
  Widget build(BuildContext context) {
    if (FundlyAuth.isSignedIn) return widget.child;
    if (!FundlyAuth.languageChosen) {
      return FirstLanguageScreen(
        onDone: () async {
          await FundlyAuth.markLanguageChosen();
          await FundlyAuth.setMode(FundlyAuth.modeGuest);
          if (mounted) setState(() {});
        },
      );
    }
    if (FundlyAuth.isGuest) return widget.child;
    // بعد تسجيل الخروج: شاشة الدخول هي أساس التطبيق نفسه — لا صفحة قبلها
    // يرجع إليها السهم، ومنها «تصفّح كضيف» أو الدخول أو إنشاء حساب.
    return LoginScreen(
      onDone: (mode) async {
        await FundlyAuth.setMode(mode);
        if (mounted) setState(() {});
      },
    );
  }
}

/// أول فتح للتطبيق على الجوال: اختيار اللغة والعملة الافتراضية، ثم يدخل
/// التطبيق (وتُغيَّران لاحقًا من الإعدادات).
class FirstLanguageScreen extends StatefulWidget {
  const FirstLanguageScreen({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  State<FirstLanguageScreen> createState() => _FirstLanguageScreenState();
}

class _FirstLanguageScreenState extends State<FirstLanguageScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final current = AppSettings.instance.language;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8F3EF), Color(0xFFF8FBFA), Colors.white],
              stops: [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _kGold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/logo_mark.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'اختر اللغة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose your language',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 20),
                for (final language in AppSettings.languages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: language == current ? _kField : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: language == current ? _kGreen : _kLine,
                          width: language == current ? 1.6 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _busy
                            ? null
                            : () async {
                                await AppSettings.instance.setLanguage(
                                  language,
                                );
                                if (mounted) setState(() {});
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  language,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: _kInk,
                                  ),
                                ),
                              ),
                              Icon(
                                language == current
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: language == current ? _kGreen : _kLine,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // العملة الافتراضية: تظهر بجانب كل مبلغ، وكل سجل جديد يبدأ
                // بها (ويُغيَّر لسجل بعينه من نموذجه).
                const Text(
                  'العملة الافتراضية',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Default currency',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('first-run-currency'),
                  initialValue: AppSettings.instance.hasCurrency
                      ? AppSettings.instance.currency
                      : null,
                  isExpanded: true,
                  // لا عملة مختارة مسبقًا: يختارها المستخدم بنفسه.
                  hint: const Text(
                    'اختر العملة الافتراضية',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kMuted,
                    ),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(
                      Icons.payments_outlined,
                      color: _kGreen,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kLine),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kLine),
                    ),
                  ),
                  items: [
                    for (final currency in AppSettings.currencies.keys)
                      DropdownMenuItem(
                        value: currency,
                        child: Text(
                          currency,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) async {
                          if (value == null) return;
                          await AppSettings.instance.setCurrency(value);
                          if (mounted) setState(() {});
                        },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kDeep,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  // «متابعة» تُفعَّل بعد اختيار العملة.
                  onPressed: _busy || !AppSettings.instance.hasCurrency
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await widget.onDone();
                          if (mounted) setState(() => _busy = false);
                        },
                  child: const Text(
                    'متابعة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شاشة الدخول فوق التطبيق (للضيف). بعد الدخول أو التسجيل يُبنى التطبيق
/// من جديد ببيانات الحساب. تُعيد true إن دخل.
Future<bool> openLoginScreen(BuildContext context) async {
  final mode = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (routeContext) => LoginScreen(
        fromGuest: true,
        onDone: (mode) => Navigator.of(routeContext).pop(mode),
      ),
    ),
  );
  if (mode != FundlyAuth.modeUser) return false;
  await FundlyAuth.setMode(FundlyAuth.modeUser);
  FundlyAuth.restartApp();
  return true;
}

/// للضيف قبل أي عملية: تنبيه ثم شاشة الدخول. تُعيد true إن سجّل الدخول.
Future<bool> promptGuestLogin(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        icon: const Icon(
          Icons.lock_person_outlined,
          color: _kGreen,
          size: 34,
        ),
        title: const Text('سجّل الدخول للمتابعة'),
        content: const Text(
          'أنت تتصفّح كضيف. لإضافة أي عملية أو حفظها سجّل الدخول، أو أنشئ '
          'حسابًا جديدًا إن لم يكن لديك حساب.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kGreen),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تسجيل الدخول'),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  // بعد الدخول يُعاد بناء التطبيق بالحساب، فلا تُكمل العملية القديمة.
  await openLoginScreen(context);
  return false;
}

const Color _kGreen = Color(0xFF0E7161);
const Color _kDeep = Color(0xFF0A5A50);
const Color _kGold = Color(0xFFCE8422);
const Color _kInk = Color(0xFF022E2A);
const Color _kMuted = Color(0xFF6B7A77);
const Color _kLine = Color(0xFFE1E9E6);
const Color _kField = Color(0xFFF4F8F7);

/// شاشة الدخول: بالهاتف أو البريد أو الرقم التعريفي مع كلمة المرور.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone, this.fromGuest = false});

  /// يُستدعى بطريقة الدخول: [FundlyAuth.modeUser] أو [FundlyAuth.modeGuest].
  final ValueChanged<String> onDone;

  /// فُتحت من تنبيه الضيف: بلا «تصفّح كضيف» ومع زر إغلاق.
  final bool fromGuest;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  /// طريقة الدخول: phone / email / id.
  String _method = 'email';
  bool _hidePassword = true;
  String? _busy;
  String? _error;

  // مرتبة أبجديًا، بلا دولة مختارة مسبقًا.
  static const _codes = <(String, String, String)>[
    ('🇦🇪', '+971', 'الإمارات'),
    ('🇧🇭', '+973', 'البحرين'),
    ('🇸🇦', '+966', 'السعودية'),
    ('🇸🇩', '+249', 'السودان'),
    ('🇴🇲', '+968', 'عُمان'),
    ('🇶🇦', '+974', 'قطر'),
    ('🇰🇼', '+965', 'الكويت'),
    ('🇪🇬', '+20', 'مصر'),
  ];

  /// رمز الدولة يبدأ من عملة المستخدم إن طابقت دولة، وإلا يبقى فارغًا
  /// حتى يختاره — لا افتراض لدولة بعينها.
  (String, String, String)? _code = _codeForCurrency();

  static (String, String, String)? _codeForCurrency() {
    final currency = AppSettings.instance.currency;
    const byIso = {
      'AED': '+971',
      'BHD': '+973',
      'SAR': '+966',
      'SDG': '+249',
      'OMR': '+968',
      'QAR': '+974',
      'KWD': '+965',
      'EGP': '+20',
    };
    for (final entry in byIso.entries) {
      if (currency.contains('(${entry.key})')) {
        for (final code in _codes) {
          if (code.$2 == entry.value) return code;
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// دخول حقيقي بالحساب: البريد مباشرة، والهاتف أو الرقم التعريفي
  /// يُبحث عن بريده في الخادم ثم يدخل بكلمة المرور.
  Future<void> _signIn() async {
    if (_busy != null) return;
    FocusScope.of(context).unfocus();
    if (_method == 'phone' &&
        _code == null &&
        _phoneCtrl.text.trim().isNotEmpty) {
      setState(() => _error = 'اختر رمز الدولة');
      return;
    }
    final value = switch (_method) {
      'phone' => _phoneCtrl.text.trim().isEmpty
          ? ''
          : '${_code?.$2 ?? ''}${_phoneCtrl.text.trim()}',
      'id' => _idCtrl.text,
      _ => _emailCtrl.text,
    };
    setState(() {
      _busy = 'main';
      _error = null;
    });
    try {
      await FundlyAccount.signIn(
        method: _method,
        value: value,
        password: _passwordCtrl.text,
      );
    } on FundlyAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = error.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);
    widget.onDone(FundlyAuth.modeUser);
  }

  Future<void> _openSignUp() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
    if (ok == true && mounted) widget.onDone(FundlyAuth.modeUser);
  }

  Future<void> _openReset() async {
    final initial = switch (_method) {
      'phone' => _phoneCtrl.text.trim().isEmpty
          ? ''
          : '${_code?.$2 ?? ''}${_phoneCtrl.text.trim()}',
      'id' => _idCtrl.text,
      _ => _emailCtrl.text,
    };
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(initial: initial.trim()),
      ),
    );
    if (ok == true && mounted) widget.onDone(FundlyAuth.modeUser);
  }

  void _soon(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickCode() async {
    final picked = await showModalBottomSheet<(String, String, String)>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              const Text(
                'رمز الدولة',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 8),
              for (final code in _codes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(code.$1, style: const TextStyle(fontSize: 22)),
                  title: Text(code.$3),
                  trailing: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      code.$2,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(code),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _code = picked);
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            for (final language in AppSettings.languages)
              ListTile(
                title: Text(language, textAlign: TextAlign.center),
                trailing: language == AppSettings.instance.language
                    ? const Icon(Icons.check_rounded, color: _kGreen)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(language),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await AppSettings.instance.setLanguage(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: Stack(
          children: [
            // خلفية هادئة بلون الهوية.
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE8F3EF), Color(0xFFF8FBFA), Colors.white],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -90,
              right: -70,
              child: _glow(220, _kGreen.withValues(alpha: 0.10)),
            ),
            Positioned(
              top: 120,
              left: -80,
              child: _glow(180, _kGold.withValues(alpha: 0.10)),
            ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _topBar(),
                  const SizedBox(height: 18),
                  _brand(),
                  const SizedBox(height: 22),
                  _card(),
                  const SizedBox(height: 18),
                  const Text(
                    'باستمرارك فأنت توافق على شروط الاستخدام وسياسة الخصوصية',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                      color: _kMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double size, Color color) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );

  Widget _roundButton({
    required Widget child,
    required VoidCallback onTap,
    required String tooltip,
  }) => Tooltip(
    message: AppTr.tr(tooltip),
    child: Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: _kLine)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: child,
        ),
      ),
    ),
  );

  Widget _topBar() {
    return Row(
      children: [
        _roundButton(
          tooltip: AppTr.tr('اللغة'),
          onTap: _pickLanguage,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded, size: 18, color: _kGreen),
              const SizedBox(width: 6),
              Text(
                AppTr.code.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _kInk,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (widget.fromGuest) ...[
          _roundButton(
            tooltip: AppTr.tr('إغلاق'),
            onTap: () => Navigator.of(context).maybePop(),
            child: const Icon(Icons.close_rounded, size: 18, color: _kInk),
          ),
          const SizedBox(width: 8),
        ],
        _roundButton(
          tooltip: AppTr.tr('المساعدة'),
          onTap: () => _soon('مركز المساعدة قريبًا'),
          child: const Icon(
            Icons.support_agent_rounded,
            size: 19,
            color: _kGreen,
          ),
        ),
      ],
    );
  }

  Widget _brand() {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _kGold.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: _kDeep.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: 12),
        const Text(
          'فوندلي',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _kDeep,
            height: 1.2,
          ),
        ),
        const Text(
          'F U N D L Y',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _kGold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kLine),
        boxShadow: [
          BoxShadow(
            color: _kDeep.withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'أموالك وأملاكك… في مكان واحد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'سجّل دخولك بهاتفك أو بريدك أو رقمك التعريفي',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
          const SizedBox(height: 18),
          _segment(),
          const SizedBox(height: 14),
          switch (_method) {
            'phone' => _phoneField(),
            'id' => _idField(),
            _ => _emailField(),
          },
          const SizedBox(height: 10),
          _passwordField(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFC4392E),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _primaryButton(),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _busy == null ? _openReset : null,
                style: TextButton.styleFrom(foregroundColor: _kMuted),
                child: const Text(
                  'نسيت كلمة المرور؟',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy == null ? _openSignUp : null,
                style: TextButton.styleFrom(foregroundColor: _kGreen),
                child: const Text(
                  'إنشاء حساب جديد',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _biometricButton(
                  'بصمة الوجه',
                  Icons.face_retouching_natural_rounded,
                  'face',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _biometricButton(
                  'بصمة الإصبع',
                  Icons.fingerprint_rounded,
                  'finger',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider(color: _kLine)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'أو تابع عبر',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: _kLine)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _socialButton(
                  'Google',
                  const Text(
                    'G',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _socialButton(
                  'Apple',
                  const Icon(Icons.apple, size: 21, color: Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _socialButton(
                  'Facebook',
                  const Icon(
                    Icons.facebook_rounded,
                    size: 21,
                    color: Color(0xFF1877F2),
                  ),
                ),
              ),
            ],
          ),
          // شاشة الدخول الأساسية (بعد الخروج): التصفّح بلا حساب.
          if (!widget.fromGuest) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy == null
                  ? () => widget.onDone(FundlyAuth.modeGuest)
                  : null,
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text(
                'تصفّح كضيف',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kDeep,
                minimumSize: const Size.fromHeight(46),
                side: const BorderSide(color: _kLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment() {
    Widget tab(String label, IconData icon, String method) {
      final selected = _method == method;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _method = method;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? _kGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : _kMuted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                  label,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : _kMuted,
                  ),
                ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        children: [
          tab('البريد', Icons.alternate_email_rounded, 'email'),
          const SizedBox(width: 4),
          tab('الهاتف', Icons.smartphone_rounded, 'phone'),
          const SizedBox(width: 4),
          tab('الرقم التعريفي', Icons.badge_outlined, 'id'),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: AppTr.tr(hint),
    hintStyle: const TextStyle(color: Color(0xFF9AA8A5), fontSize: 13),
    prefixIcon: Icon(icon, size: 19, color: _kGreen),
    filled: true,
    fillColor: _kField,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _kLine),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _kLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _kGreen, width: 1.4),
    ),
  );

  Widget _phoneField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: AppTr.isEnglish ? TextAlign.left : TextAlign.right,
            decoration: _decoration('رقم الهاتف', Icons.phone_rounded),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _pickCode,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _kField,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kLine),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _code?.$1 ?? '🌐',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 5),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _code?.$2 ?? 'رمز',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: _kInk,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _kMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emailField() {
    return TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      textDirection: TextDirection.ltr,
      textAlign: AppTr.isEnglish ? TextAlign.left : TextAlign.right,
      decoration: _decoration('name@example.com', Icons.mail_outline_rounded),
    );
  }

  Widget _idField() {
    return TextField(
      controller: _idCtrl,
      textDirection: TextDirection.ltr,
      textCapitalization: TextCapitalization.characters,
      textAlign: AppTr.isEnglish ? TextAlign.left : TextAlign.right,
      decoration: _decoration('FND-XXXX-XXXX', Icons.badge_outlined),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _hidePassword,
      textDirection: TextDirection.ltr,
      textAlign: AppTr.isEnglish ? TextAlign.left : TextAlign.right,
      onSubmitted: (_) => _signIn(),
      decoration: _decoration('كلمة المرور', Icons.lock_outline_rounded)
          .copyWith(
            suffixIcon: IconButton(
              tooltip: AppTr.tr(
                _hidePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
              ),
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: _kMuted,
              ),
            ),
          ),
    );
  }

  Widget _spinner(Color color) => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
  );

  Widget _primaryButton() {
    final busy = _busy == 'main';
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kDeep, _kGreen]),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: _kGreen.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _signIn,
            child: Center(
              child: busy
                  ? _spinner(Colors.white)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          AppTr.isEnglish
                              ? Icons.arrow_forward_rounded
                              : Icons.arrow_back_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _biometricButton(String label, IconData icon, String key) {
    final busy = _busy == key;
    return OutlinedButton(
      onPressed: () => _soon('الدخول بالبصمة قريبًا — ادخل الآن بكلمة المرور'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _kGreen,
        backgroundColor: const Color(0xFFF0F7F5),
        side: BorderSide(color: _kGreen.withValues(alpha: 0.25)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: busy
          ? _spinner(_kGreen)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _socialButton(String label, Widget icon) {
    final busy = _busy == label;
    return OutlinedButton(
      onPressed: () => _soon('هذه الطريقة قريبًا — ادخل الآن بكلمة المرور'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _kInk,
        side: const BorderSide(color: _kLine),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: busy
          ? _spinner(_kGreen)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
