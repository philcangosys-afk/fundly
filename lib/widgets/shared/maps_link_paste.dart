import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';

/// «لصق رابط خرائط جوجل»: يقرأ الرابط المنسوخ في الجوال ويُعيده ليُكتب في
/// «الموقع أو الرابط». كان الزر يغيّر النص التوضيحي فقط ولا يلصق شيئًا.
///
/// بلا رابط منسوخ: نافذة تشرح الطريقة، وزر يفتح خرائط جوجل لنسخه.
Future<String?> pasteMapsLink(BuildContext context) async {
  var text = '';
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    text = (data?.text ?? '').trim();
  } catch (_) {
    text = '';
  }
  final link = RegExp(r'https?://\S+').firstMatch(text)?.group(0) ?? '';
  if (!context.mounted) return null;
  if (link.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم لصق الرابط في «الموقع أو الرابط»'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return link;
  }
  final open = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: AlertDialog(
        title: const Text('لا يوجد رابط منسوخ'),
        content: const Text(
          'افتح المكان في خرائط جوجل ← مشاركة ← نسخ الرابط، ثم ارجع واضغط '
          '«لصق رابط خرائط جوجل» مرة أخرى.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('فتح خرائط جوجل'),
          ),
        ],
      ),
    ),
  );
  if (open == true) {
    try {
      await launchUrl(
        Uri.parse('https://www.google.com/maps'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // لا تطبيق خرائط ولا متصفح: يبقى الشرح في النافذة كافيًا.
    }
  }
  return null;
}
