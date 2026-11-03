import 'dart:async';

import 'package:flutter/material.dart' hide Text, Align;

import '../../data/app_settings.dart';
import '../../data/custody_sharing.dart';
import '../../data/fundly_account.dart';
import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// ملاحظة رمادية تحت كل خانة رقم تعريفي: كيف سيظهر اسمي للطرف الآخر.
String fndNameHint() =>
    '${AppTr.tr('سيظهر اسمك للآخرين حسب إعدادات ملفك الشخصي')}: '
    '«${AppSettings.instance.publicName}»';

/// بعد الإضافة أو الإرسال: كيف ظهر اسمي للطرف الآخر.
String fndSentNote() =>
    '${AppTr.tr('سيظهر اسمك للطرف الآخر')}: «${AppSettings.instance.publicName}» '
    '(${AppTr.tr('حسب إعدادات ملفك الشخصي')})';

/// الملاحظة نفسها كسطر مستقل تحت خانة لا تقبل نصًا مساعدًا.
class FndNameNotice extends StatelessWidget {
  const FndNameNotice({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 6, top: 4, bottom: 2),
    child: Text(
      fndNameHint(),
      style: const TextStyle(
        fontSize: 11,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
    ),
  );
}

/// خانة «الرقم التعريفي» بشكل حقل كتابة واضح (إطار ونقاط مكان الأرقام)،
/// فيعرف المستخدم أنه يكتب فيها. الضغط يفتح نافذة الكتابة نفسها.
class FndEntryBox extends StatelessWidget {
  const FndEntryBox({
    super.key,
    required this.onTap,
    this.accent = AppTheme.brand,
    this.title = 'دعوة بالرقم التعريفي',
  });

  final VoidCallback onTap;
  final Color accent;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.badge_outlined, size: 18, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          child: InkWell(
            key: const ValueKey('fnd-entry-box'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.rField),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                border: Border.all(
                  color: accent.withValues(alpha: 0.6),
                  width: 1.4,
                ),
              ),
              // الرقم يُكتب من اليسار دائمًا: FND ثم مكان الأرقام نقاطًا.
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  Container(width: 2, height: 22, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'FND',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      letterSpacing: 1,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      ' - • • • •  - • • • •',
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFB5C3C0),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  Icon(Icons.edit_rounded, size: 19, color: accent),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'اضغط واكتب رقم الشخص — يظهر اسمه لتتأكد منه',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          fndNameHint(),
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.muted,
          ),
        ),
      ],
    );
  }
}

/// نافذة الرقم التعريفي: يكتب المستخدم الرقم فيظهر تحته الاسم المرتبط به
/// من الخادم، فيتأكد أنه الشخص الصحيح قبل الدعوة أو الإسناد.
/// تعيد (الرقم، الاسم) أو null عند الإلغاء.
Future<(String, String)?> askFndPerson(
  BuildContext context, {
  String title = 'دعوة بالرقم التعريفي',
  String confirmLabel = 'دعوة',
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (_) => _FndLookupDialog(title: title, confirmLabel: confirmLabel),
  );
}

class _FndLookupDialog extends StatefulWidget {
  const _FndLookupDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_FndLookupDialog> createState() => _FndLookupDialogState();
}

class _FndLookupDialogState extends State<_FndLookupDialog> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  Timer? _debounce;
  String _checked = '';
  String? _foundName;
  bool _looking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _normalized => AppIdentity.normalize(_idController.text);

  void _onChanged(String _) {
    _debounce?.cancel();
    final id = _normalized;
    if (!AppIdentity.isValid(id)) {
      setState(() {
        _checked = '';
        _foundName = null;
        _looking = false;
      });
      return;
    }
    setState(() => _looking = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final name = await FundlyAccount.nameForFnd(id);
      if (!mounted || _normalized != id) return;
      setState(() {
        _checked = id;
        _foundName = name;
        _looking = false;
      });
    });
  }

  void _confirm() {
    final id = _normalized;
    if (!AppIdentity.isValid(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الصيغة الصحيحة FND-XXXX-XXXX')),
      );
      return;
    }
    // لا يُضاف رقمي التعريفي أنا (تفويض نفسي أو عضوية لنفسي).
    if (AppIdentity.id.isNotEmpty && id == AppIdentity.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا رقمك التعريفي — اكتب رقم الشخص الآخر')),
      );
      return;
    }
    final found = _checked == id ? (_foundName ?? '').trim() : '';
    final typed = _nameController.text.trim();
    final name = found.isNotEmpty ? found : (typed.isNotEmpty ? typed : id);
    Navigator.pop(context, (id, name));
  }

  @override
  Widget build(BuildContext context) {
    final id = _normalized;
    final valid = AppIdentity.isValid(id);
    final found = _checked == id ? _foundName : null;
    final notFound = valid && !_looking && _checked == id && found == null;
    return Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        backgroundColor: AppTheme.page,
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _idController,
              autofocus: true,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onChanged,
              decoration: InputDecoration(
                labelText: AppTr.tr('الرقم التعريفي'),
                hintText: 'FND-XXXX-XXXX',
                prefixIcon: const Icon(Icons.badge_outlined),
                helperText: fndNameHint(),
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 10),
            if (_looking)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'جارٍ البحث عن صاحب الرقم...',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              )
            else if (found != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        found,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (notFound) ...[
              const Text(
                'لم يُعثر على اسم لهذا الرقم — تأكد منه، أو اكتب الاسم الظاهر',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.goldDark,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppTr.tr('الاسم الظاهر'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
            ] else if (!valid)
              const Text(
                'اكتب الرقم بصيغة FND-XXXX-XXXX ويظهر الاسم المرتبط به',
                style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: valid && !_looking ? _confirm : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
