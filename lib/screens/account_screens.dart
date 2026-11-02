import 'package:flutter/material.dart' hide Text, Align;

import '../data/app_settings.dart';
import '../data/fundly_account.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';

const Color _kGreen = Color(0xFF0E7161);
const Color _kDeep = Color(0xFF0A5A50);
const Color _kInk = Color(0xFF022E2A);
const Color _kMuted = Color(0xFF6B7A77);
const Color _kLine = Color(0xFFE1E9E6);
const Color _kField = Color(0xFFF4F8F7);
const Color _kDanger = Color(0xFFC4392E);

InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) =>
    InputDecoration(
      hintText: AppTr.tr(hint),
      hintStyle: const TextStyle(color: Color(0xFF9AA8A5), fontSize: 13),
      prefixIcon: Icon(icon, size: 19, color: _kGreen),
      suffixIcon: suffix,
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

/// إطار موحّد لشاشتي «إنشاء حساب» و«نسيت كلمة المرور».
class _AccountFrame extends StatelessWidget {
  const _AccountFrame({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _kInk,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3EF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 32, color: _kDeep),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _errorText(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            fontWeight: FontWeight.w800,
            color: _kDanger,
          ),
        ),
      );

Widget _primary(String label, bool busy, VoidCallback onTap) => SizedBox(
  height: 52,
  child: FilledButton(
    onPressed: busy ? null : onTap,
    style: FilledButton.styleFrom(
      backgroundColor: _kDeep,
      disabledBackgroundColor: _kDeep.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    child: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          )
        : Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
  ),
);

// ============================================================
// إنشاء حساب جديد
// ============================================================

/// يعيد true إن أُنشئ الحساب ودخل مباشرة.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController();
  final _family = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _family.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!AppSettings.isValidNameParts(_name.text, _family.text)) {
      setState(() => _error = 'اكتب اسمك');
      return;
    }
    final fullName = AppSettings.composeName(_name.text, _family.text);
    if (_password.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    // البريد وكلمة المرور قبل طلب الرمز، فلا يُطلب رمز لبيانات مرفوضة.
    final mail = _email.text.trim().toLowerCase();
    if (!mail.contains('@') || !mail.contains('.')) {
      setState(() => _error = 'صيغة البريد الإلكتروني غير صحيحة');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'كلمة المرور قصيرة — 6 أحرف على الأقل');
      return;
    }
    setState(() => _error = null);
    // رمز التحقق OTP قبل إنشاء الحساب.
    if (!await _verifyOtp() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool signedIn;
    try {
      signedIn = await FundlyAccount.signUp(
        name: fullName,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
      );
    } on FundlyAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
      return;
    }
    if (signedIn) {
      await AppSettings.instance.setNameParts(_name.text, _family.text);
    }
    if (!mounted) return;
    if (signedIn) {
      Navigator.of(context).pop(true);
      return;
    }
    // البريد يحتاج تفعيلًا: رسالة ثم الرجوع لشاشة الدخول.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          icon: const Icon(
            Icons.mark_email_read_outlined,
            size: 34,
            color: _kGreen,
          ),
          title: const Text('فعّل حسابك من بريدك'),
          content: const Text(
            'أرسلنا رابط التفعيل إلى بريدك الإلكتروني. افتحه ثم ارجع وسجّل '
            'الدخول بالبريد وكلمة المرور.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kDeep),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(false);
  }

  /// مرحلة الاختبار: رمز تحقق ثابت يظهر للمستخدم بخط واضح تحت الحقل.
  static const String _testOtp = '123456';

  Future<bool> _verifyOtp() async {
    final code = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            void confirm() {
              if (code.text.trim() == _testOtp) {
                Navigator.pop(dialogContext, true);
              } else {
                setDialogState(() => error = 'رمز التحقق غير صحيح');
              }
            }

            return AlertDialog(
              icon: const Icon(Icons.sms_outlined, size: 34, color: _kGreen),
              title: const Text('رمز التحقق'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'أدخل رمز التحقق المكوّن من 6 أرقام لإكمال إنشاء الحساب.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      maxLength: 6,
                      onSubmitted: (_) => confirm(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: _kInk,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        filled: true,
                        fillColor: _kField,
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
                          borderSide: const BorderSide(
                            color: _kGreen,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // الرمز ظاهر تحت الحقل بخط واضح (مرحلة الاختبار).
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF6E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCE8422)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${AppTr.tr('الرمز الخاص بك')}: $_testOtp',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF6B4A12),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'مرحلة الاختبار',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFA6691A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _kDanger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _kDeep),
                  onPressed: confirm,
                  child: const Text('تأكيد'),
                ),
              ],
            );
          },
        ),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final eye = IconButton(
      tooltip: AppTr.tr(_hide ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور'),
      onPressed: () => setState(() => _hide = !_hide),
      icon: Icon(
        _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 19,
        color: _kMuted,
      ),
    );
    return _AccountFrame(
      title: 'إنشاء حساب جديد',
      subtitle: 'حساب واحد تدخل به من أي جوال، ويولّد لك النظام رقمًا '
          'تعريفيًا ثابتًا للمعاملات المشتركة.',
      icon: Icons.person_add_alt_1_rounded,
      children: [
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'اسمك الثلاثي',
            Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _family,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'القبيلة / العائلة (اختياري)',
            Icons.family_restroom_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'البريد الإلكتروني',
            Icons.alternate_email_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'رقم الهاتف (اختياري — للدخول به)',
            Icons.smartphone_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: _hide,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            'كلمة المرور',
            Icons.lock_outline_rounded,
            suffix: eye,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirm,
          obscureText: _hide,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _submit(),
          decoration: _decoration(
            'تأكيد كلمة المرور',
            Icons.lock_outline_rounded,
          ),
        ),
        _errorText(_error),
        const SizedBox(height: 16),
        _primary('إنشاء الحساب', _busy, _submit),
      ],
    );
  }
}

// ============================================================
// نسيت كلمة المرور
// ============================================================

/// رمز من أرقام يصل إلى البريد المرتبط بالحساب، ثم كلمة مرور جديدة.
/// يعيد true بعد التغيير والدخول.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initial = ''});

  /// ما كُتب في شاشة الدخول (بريد أو هاتف أو رقم تعريفي).
  final String initial;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _identifier = TextEditingController(text: widget.initial);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _sentTo = '';
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = await FundlyAccount.sendResetCode(_identifier.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sentTo = email;
      });
    } on FundlyAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (_password.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FundlyAccount.resetWithCode(
        email: _sentTo,
        code: _code.text,
        newPassword: _password.text,
      );
    } on FundlyAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// a***@gmail.com
  String _masked(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}${'*' * (at - 1).clamp(1, 6).toInt()}${email.substring(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo.isNotEmpty;
    final eye = IconButton(
      tooltip: AppTr.tr(_hide ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور'),
      onPressed: () => setState(() => _hide = !_hide),
      icon: Icon(
        _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 19,
        color: _kMuted,
      ),
    );
    return _AccountFrame(
      title: 'نسيت كلمة المرور',
      subtitle: sent
          ? '${AppTr.tr('أرسلنا رمزًا إلى')} ${_masked(_sentTo)}'
          : 'اكتب بريدك أو رقم هاتفك أو رقمك التعريفي، ونرسل رمزًا إلى '
                'البريد المرتبط بحسابك.',
      icon: Icons.lock_reset_rounded,
      children: [
        if (!sent) ...[
          TextField(
            controller: _identifier,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _send(),
            decoration: _decoration(
              'البريد أو الهاتف أو الرقم التعريفي',
              Icons.person_search_outlined,
            ),
          ),
          _errorText(_error),
          const SizedBox(height: 16),
          _primary('إرسال الرمز', _busy, _send),
        ] else ...[
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              letterSpacing: 6,
              fontWeight: FontWeight.w900,
            ),
            decoration: _decoration('الرمز', Icons.pin_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            textDirection: TextDirection.ltr,
            decoration: _decoration(
              'كلمة المرور الجديدة',
              Icons.lock_outline_rounded,
              suffix: eye,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: _hide,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _reset(),
            decoration: _decoration(
              'تأكيد كلمة المرور الجديدة',
              Icons.lock_outline_rounded,
            ),
          ),
          _errorText(_error),
          const SizedBox(height: 16),
          _primary('تغيير كلمة المرور والدخول', _busy, _reset),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : _send,
            style: TextButton.styleFrom(foregroundColor: _kGreen),
            child: const Text('إعادة إرسال الرمز'),
          ),
        ],
      ],
    );
  }
}
