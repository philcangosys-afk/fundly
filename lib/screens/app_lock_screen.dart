import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../widgets/shared/app_design.dart';

/// بوابة قفل التطبيق.
///
/// كان مفتاح "قفل التطبيق" في الإعدادات يُحفظ ولا يُقرأ في أي مكان، فيظهر
/// للمستخدم أنه فعّل حماية بينما التطبيق يُفتح كما هو. الآن يمرّ الإقلاع
/// من هنا: إن كان القفل مفعّلًا لا يظهر المحتوى قبل إدخال الرمز الصحيح.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  /// تُحسم الحاجة إلى القفل مرة واحدة عند الإقلاع فقط.
  ///
  /// لو أُعيد تقييمها مع كل تغيير في الإعدادات لانقفل التطبيق في وجه
  /// المستخدم لحظة تفعيله القفل من صفحة الأمان — وهو آخر ما يتوقعه.
  late final bool _lockRequired = AppSettings.instance.appLock;
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    if (!_lockRequired || _unlocked) return widget.child;
    return _AppLockScreen(onUnlocked: () => setState(() => _unlocked = true));
  }
}

class _AppLockScreen extends StatefulWidget {
  const _AppLockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<_AppLockScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (AppSettings.instance.verifyPin(_controller.text)) {
      widget.onUnlocked();
      return;
    }
    setState(() => _error = 'الرمز غير صحيح');
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 62,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'التطبيق مقفل',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'أدخل رمز القفل من أربعة أرقام للمتابعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      key: const ValueKey('app-lock-pin'),
                      controller: _controller,
                      autofocus: true,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w900,
                      ),
                      decoration: const InputDecoration(counterText: ''),
                      onChanged: (value) {
                        if (_error != null) setState(() => _error = null);
                        // الفتح فور اكتمال أربعة أرقام صحيحة، بلا ضغط زر.
                        if (value.length == 4) _submit();
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(180, 46),
                    ),
                    child: const Text('فتح'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
