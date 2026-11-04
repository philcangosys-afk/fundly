import 'package:flutter/material.dart' hide Text, Align;

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// قبل مشاركة مستند PDF: بترويسة Fundly (الشعار والاسم ورقم المستند
/// والتاريخ) أو بدونها. يعيد null إن أُغلقت النافذة.
Future<bool?> askPdfLetterhead(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (sheetContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                'مشاركة كمستند PDF',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.verified_outlined,
                color: AppTheme.brand,
              ),
              title: const Text('بترويسة Fundly'),
              subtitle: const Text('الشعار والاسم ورقم المستند والتاريخ'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('بدون ترويسة'),
              subtitle: const Text('مستند أبيض بالبيانات فقط'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// التشكيل يُسقط سطور PDF العربية أحيانًا — يُحذف من النصوص قبل الطباعة.
String pdfSafeText(String value) =>
    value.replaceAll(RegExp('[\u064B-\u0652\u0670]'), '').trim();
