import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import 'app_translations.dart';
import 'app_translations_fr.dart';
import 'app_translations_ur.dart';
import 'app_translations_zh.dart';

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

  // ===== اللغات =====
  // لإضافة لغة جديدة: اسمها في [AppSettings.languages]، وقاموسها هنا في
  // [_dictionaries] (عربي ← اللغة)، ورمزها في [_codes]، وإن كانت تُكتب من
  // اليمين (أردو، فارسي...) تُضاف إلى [_rtlLanguages].

  /// قاموس كل لغة غير العربية: النص العربي ← ترجمته.
  //
  static const Map<String, Map<String, String>> _dictionaries = {
    'English': kArToEn,
    'Français': kArToFr,
    'اردو': kArToUr,
    '中文': kArToZh,
  };

  /// رمز اللغة (للتقارير وما شابه).
  static const Map<String, String> _codes = {
    'العربية': 'ar',
    'English': 'en',
    'Français': 'fr',
    'اردو': 'ur',
    '中文': 'zh',
  };

  /// اللغات التي تُكتب من اليمين إلى اليسار.
  static const Set<String> _rtlLanguages = {'العربية', 'اردو'};

  static String get language => AppSettings.instance.language;

  static bool get isArabic => language == 'العربية';

  /// اتجاه الكتابة للغة الحالية.
  static bool get isRtl => _rtlLanguages.contains(language);

  /// واجهة من اليسار إلى اليمين (الإنجليزية وكل لغة مثلها). الاسم باقٍ
  /// كما هو لأن مواضع كثيرة تقرأه لقلب المحاذاة.
  static bool get isEnglish => !isRtl;

  static String get code => _codes[language] ?? 'en';

  /// إعادة بناء الواجهة كلها فورًا بعد تغيير اللغة.
  ///
  /// العناصر الثابتة (const Text مثلًا) لا يعيد فلاتر بناءها عند إعادة
  /// بناء ما فوقها، فكانت تبقى بلغتها القديمة حتى يُغلق التطبيق. هنا يُعلَّم
  /// كل عنصر في الشجرة — الصفحات المفتوحة والنوافذ — ليُبنى من جديد.
  static void rebuildAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
  }

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
  /// أسماء ظاهرة تغيّرت والقيمة المخزّنة باقية كما هي (قاعدة البيانات
  /// تقيّد أنواع الالتزامات المشتركة) — تُبدَّل عند العرض فقط.
  static const Map<String, String> _arDisplay = {
    'جمعية مالية': 'تحديد أدوار',
    'جمعية': 'تحديد أدوار',
    'اسم الجمعية المالية': 'اسم المجموعة',
    'اسم الجمعية': 'اسم المجموعة',
    'عدد أشهر الجمعية المالية': 'عدد الأشهر',
    'سجل دورات الجمعية': 'سجل الدورات',
    // تذكيرات ونطاقات تفويض مخزّنة بالاسم القديم.
    'الآليات والمعدات': 'المركبات ووسائل النقل',
    'آليات ومعدات': 'المركبات ووسائل النقل',
    // «أدوية وبيانات وكلمات سر» تُعرض بلا «وبيانات».
    'أدوية وبيانات وكلمات سر': 'أدوية وكلمات سر',
    'أدوية وبيانات\nكلمات سر': 'أدوية\nكلمات سر',
  };

  /// كلمات الحالات الموحّدة في كل التطبيق: المعنى الواحد بكلمة واحدة.
  /// العرض وحده — القيم المخزّنة والمقارنات في الكود كما هي، فلا تتأثر
  /// البيانات القديمة. تُطبَّق على النص كاملًا أو على مقطع منه بين فواصل
  /// (« · » « — » « / » «: » والأقواس)، لا داخل الجمل.
  static const Map<String, String> _arStatusWords = {
    // مستحقة: يوم الموعد نفسه (وبعده متأخرة).
    'حان وقتها': 'مستحقة',
    'حان وقته': 'مستحق',
    'حان دورها': 'مستحقة',
    'مستحق اليوم': 'مستحق',
    'مستحقة اليوم': 'مستحقة',
    // قبل الموعد.
    'قريبة الاستحقاق': 'مستحقة قريبًا',
    'قريب الاستحقاق': 'مستحق قريبًا',
    // قرب الانتهاء.
    'تنتهي قريبًا': 'قارب على الانتهاء',
    'ينتهي قريبًا': 'قارب على الانتهاء',
    'قريبة الانتهاء': 'قارب على الانتهاء',
    'قريب الانتهاء': 'قارب على الانتهاء',
    'قارب الانتهاء': 'قارب على الانتهاء',
    'تقارب الانتهاء': 'قارب على الانتهاء',
    // التسوية.
    'مسوّى': 'تمت التسوية',
    'مسوّاة': 'تمت التسوية',
    'يحتاج تسوية': 'تحتاج تسوية',
    // القبول والرفض.
    'بانتظار قبول المفوَّض': 'بانتظار القبول',
    'بانتظار قبولك': 'بانتظار القبول',
    'بانتظار قبوله': 'بانتظار القبول',
    'بانتظار ردك': 'بانتظار القبول',
    'رفضه المفوَّض': 'مرفوض',
    'رفضتَه': 'مرفوض',
    // الصيانة والإنجاز والدفع.
    'تحت الصيانة': 'تحت صيانة',
    'منجزة': 'مكتملة',
    'جارية': 'نشطة',
    'جزئي': 'مدفوع جزئيًا',
    // التفويض: «بها» في العقارات والأنشطة والمركبات والعهدة.
    'مفوَّض أنا بإدارته': 'مفوَّض أنا بها',
    'فوّضت غيري بإدارته': 'فوّضت غيري بها',
    'مفوَّض بها أنا': 'مفوَّض أنا بها',
    'فوّضت بها غيري': 'فوّضت غيري بها',
  };

  static final RegExp _statusSep = RegExp(r' · | — | / |: |\(|\)|\n');

  static String _arStatus(String text) {
    final hit = _arStatusWords[text] ?? _arStatusWords[text.trim()];
    if (hit != null) return text.replaceFirst(text.trim(), hit);
    if (!_statusSep.hasMatch(text)) return text;
    return text.splitMapJoin(
      _statusSep,
      onNonMatch: (part) {
        final word = part.trim();
        if (word.isEmpty) return part;
        final mapped = _arStatusWords[word];
        return mapped == null ? part : part.replaceFirst(word, mapped);
      },
    );
  }

  /// كلمات محلية تُعرض بلفظ عام: «الجوال» ← «الهاتف»، «حوالة» ← «تحويل».
  /// العرض وحده — المفاتيح المخزّنة كما هي.
  static final RegExp _arWordRun = RegExp('حوالة بنكية|حوالات|حوالة|جوال');

  static String _arWords(String text) {
    // نوع الوحدة «دور كامل» يُعرض «دور» (المخزّن كما هو).
    if (text.contains('دور كامل')) text = text.replaceAll('دور كامل', 'دور');
    // صيغ إملائية موحّدة: ملغى ← ملغي، ملغية ← ملغاة، منتهٍ ← منتهي.
    if (text.contains('ملغى')) text = text.replaceAll('ملغى', 'ملغي');
    if (text.contains('ملغية')) text = text.replaceAll('ملغية', 'ملغاة');
    if (text.contains('منتهٍ')) text = text.replaceAll('منتهٍ', 'منتهي');
    if (!text.contains('جوال') && !text.contains('حوال')) return text;
    return text.replaceAllMapped(_arWordRun, (match) {
      switch (match.group(0)) {
        case 'حوالة بنكية':
          return 'تحويل بنكي';
        case 'حوالات':
          return 'تحويلات';
        case 'حوالة':
          return 'تحويل';
        default:
          return 'هاتف';
      }
    });
  }

  /// علامات الأخطاء التقنية: أسماء الاستثناءات ورموز الخادم وتفاصيله.
  static final RegExp _technical = RegExp(
    r'(Exception|statusCode|code: ?null|PGRST|JWT|XMLHttpRequest|'
    r'Null check|is not a subtype|relation "|Error\()',
  );

  static final RegExp _exceptionMessage = RegExp(
    r'(?:message: ?|Exception: ?)([^,()]*[\u0600-\u06FF][^,()]*)',
  );

  /// النسخة النهائية لا تعرض للمستخدم تفاصيل الأخطاء التقنية (أسماء
  /// الاستثناءات، statusCode، code: null...) — تبقى في وضع التطوير فقط
  /// لاكتشاف الأخطاء. السطر التقني يُحذف، ويبقى منه ما قبل «:» إن كان
  /// مفهومًا، أو الرسالة العربية التي داخل الاستثناء.
  static String _hideTechnical(String text, {bool force = false}) {
    if ((!kReleaseMode && !force) || !_technical.hasMatch(text)) return text;
    final kept = <String>[];
    for (final line in text.split('\n')) {
      if (!_technical.hasMatch(line)) {
        kept.add(line);
        continue;
      }
      final colon = line.indexOf(':');
      final head = colon > 0 ? line.substring(0, colon).trim() : '';
      if (head.isNotEmpty && !_technical.hasMatch(head)) {
        kept.add(head);
        continue;
      }
      final inner = _exceptionMessage.firstMatch(line)?.group(1)?.trim();
      if (inner != null && inner.isNotEmpty && !_technical.hasMatch(inner)) {
        kept.add(inner);
      }
    }
    final result = kept.where((l) => l.trim().isNotEmpty).join('\n').trim();
    return result.isEmpty ? 'حدث خطأ غير متوقع — حاول مرة أخرى' : result;
  }

  /// للاختبارات: نفس إخفاء النسخة النهائية في أي وضع.
  static String hideTechnicalForTest(String text) =>
      _hideTechnical(text, force: true);

  static String tr(String text) {
    if (text.isEmpty) return text;
    text = _hideTechnical(text);
    if (isArabic) return _arWords(_arStatus(_arDisplay[text] ?? text));
    final dict = _dictionaries[language] ?? kArToEn;
    // الاسم الظاهر الجديد أولًا (القيمة المخزّنة قديمة)، ثم ترجمته.
    final shown = _arStatus(_arDisplay[text] ?? text);
    final direct = dict[shown] ?? dict[text];
    if (direct != null) return direct;
    final trimmed = shown.trim();
    final trimmedHit = dict[trimmed];
    if (trimmedHit != null) return shown.replaceFirst(trimmed, trimmedHit);
    return shown.replaceAllMapped(_arabicRun, (match) {
      final run = match.group(0)!;
      final hit = dict[run] ?? dict[run.trim()];
      return hit ?? run;
    });
  }

  static String? trN(String? text) => text == null ? null : tr(text);
}

/// رسالة خطأ الحقل (validator) تُعرض مترجمة — فلاتر يعرضها كما هي.
FormFieldValidator<T>? trValidator<T>(FormFieldValidator<T>? validator) {
  if (validator == null) return null;
  return (value) => AppTr.trN(validator(value));
}
