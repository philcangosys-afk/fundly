import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import 'app_translations.dart';

/// محرّك الترجمة واتجاه الواجهة.
///
/// اللغة تُقرأ من إعداد "اللغة" الموجود أصلًا في الإعدادات
/// ([AppSettings.language])، وتغييرها يعيد بناء التطبيق كاملًا لأن
/// MaterialApp يستمع إلى AppSettings.instance.
///
/// - العربية: النصوص كما هي والاتجاه يمين ← يسار.
/// - English: النصوص تُترجم عبر قاموس [kArToEn] والاتجاه يسار ← يمين.
///
/// الترجمة تتم عند العرض فقط (عبر عنصر Text الظلّي في tr_widgets.dart)،
/// فكل القيم المخزّنة في قاعدة البيانات والمقارنات المنطقية تبقى
/// بالعربية ولا يتأثر أي منطق داخلي.
class AppTr {
  AppTr._();

  static bool get isEnglish => AppSettings.instance.language == 'English';

  /// اتجاه الواجهة الحالي — بديل ديناميكي عن TextDirection.rtl الثابت.
  static TextDirection get uiDir =>
      isEnglish ? TextDirection.ltr : TextDirection.rtl;

  /// محاذاة "بداية السطر" الفيزيائية: يمين بالعربية ويسار بالإنجليزية.
  static TextAlign get alignEnd =>
      isEnglish ? TextAlign.left : TextAlign.right;

  /// قلب محاذاة نص فيزيائية (يمين/يسار) عند الإنجليزية — start/end
  /// تنقلب وحدها مع الاتجاه فلا تُمسّ.
  static TextAlign? mapTextAlign(TextAlign? align) {
    if (!isEnglish || align == null) return align;
    if (align == TextAlign.right) return TextAlign.left;
    if (align == TextAlign.left) return TextAlign.right;
    return align;
  }

  /// قلب Alignment فيزيائي (centerRight...) عند الإنجليزية.
  static AlignmentGeometry mapAlignment(AlignmentGeometry alignment) {
    if (!isEnglish) return alignment;
    if (alignment == Alignment.centerRight) return Alignment.centerLeft;
    if (alignment == Alignment.centerLeft) return Alignment.centerRight;
    if (alignment == Alignment.topRight) return Alignment.topLeft;
    if (alignment == Alignment.topLeft) return Alignment.topRight;
    if (alignment == Alignment.bottomRight) return Alignment.bottomLeft;
    if (alignment == Alignment.bottomLeft) return Alignment.bottomRight;
    return alignment;
  }

  /// مقاطع عربية داخل نص (حروف عربية مع ما بينها من فراغات وترقيم
  /// عربي) — تُستخدم لترجمة النصوص المركّبة وقت التشغيل
  /// ('العدد: 5' مثلًا) مقطعًا مقطعًا.
  static final RegExp _arabicRun = RegExp(
    r'[؀-ۿݐ-ݿ][؀-ۿݐ-ݿ\s،؛ـ/ً-ْ]*'
    r'[؀-ۿݐ-ݿ]|[؀-ۿݐ-ݿ]',
  );

  /// ترجمة نص للعرض. بالعربية يعود كما هو. بالإنجليزية: بحث عن النص
  /// كاملًا في القاموس، ثم عن نسخته المشذّبة، وإلا تُترجم مقاطعه
  /// العربية كلٌّ على حدة، وما لم يُعرف يبقى كما هو.
  static String tr(String text) {
    if (!isEnglish || text.isEmpty) return text;
    final direct = kArToEn[text];
    if (direct != null) return direct;
    final trimmed = text.trim();
    final trimmedHit = kArToEn[trimmed];
    if (trimmedHit != null) return text.replaceFirst(trimmed, trimmedHit);
    return text.replaceAllMapped(_arabicRun, (match) {
      final run = match.group(0)!;
      final hit = kArToEn[run] ?? kArToEn[run.trim()];
      return hit ?? run;
    });
  }

  static String? trN(String? text) => text == null ? null : tr(text);
}
