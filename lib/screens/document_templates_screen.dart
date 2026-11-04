import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_reminders_store.dart';
import '../data/delegations_repository.dart';
import '../data/project_assets_repository.dart';
import '../data/user_signature_store.dart';
import '../data/user_stamp_store.dart';
import '../data/user_logo_store.dart';
import 'signature_settings_screen.dart';
import '../widgets/shared/app_design.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/plan_gate.dart';
import '../data/template_print.dart';
import 'template_print_screen.dart';
import 'salary_receipts_screen.dart';

class DocumentTemplatesScreen extends StatefulWidget {
  const DocumentTemplatesScreen({super.key, this.linkedProperty});

  final String? linkedProperty;

  @override
  State<DocumentTemplatesScreen> createState() =>
      _DocumentTemplatesScreenState();
}

class _DocumentTemplatesScreenState extends State<DocumentTemplatesScreen> {
  // كانت السجلات تُحفظ محليًا فقط (SharedPreferences)، فتضيع عند حذف
  // التطبيق ولا تظهر على أي جهاز آخر — بخلاف بقية بيانات التطبيق.
  final DelegationsRepository _repository = SupabaseDelegationsRepository();
  final ProjectAssetsRepository _assetsRepository =
      SupabaseProjectAssetsRepository();

  /// الكيانات التي يمكن ربط المستند بها، مقروءة من بياناتها الحقيقية.
  List<({String kind, String label, String id})> _linkTargets = const [];

  /// المربعات في الشاشة: «عقد» يفتح قائمة أنواع العقود.
  static const List<String> _gridTypes = [
    'إيصال أمانة',
    'إيصال استلام وتسليم',
    'فاتورة',
    'تقرير ضريبي',
    'عقد',
    'إنذار',
  ];

  /// أنواع العقود المحكمة — تُختار عند الضغط على «عقد».
  static const List<String> _contractTypes = [
    'عقد إيجار عقار',
    'عقد إيجار نشاط تجاري',
    'عقد تأجير مركبة',
    'عقد عام',
  ];

  static const Map<String, String> _contractHints = {
    'عقد إيجار عقار': 'عقار سكني أو تجاري: الأجرة والتأمين والصيانة',
    'عقد إيجار نشاط تجاري': 'محل لنشاط تجاري: الرخصة وفترة التجهيز',
    'عقد تأجير مركبة': 'تأجير مركبة: العداد والوقود والمخالفات',
    'عقد عام': 'اتفاق بين طرفين بموضوع وشروط تحددها',
  };

  /// الحقول بترتيبها — ما يبدأ بـ «#» عنوان قسم لا حقل.
  static const Map<String, List<String>> _templateFields = {
    'إيصال أمانة': [
      '#بيانات المدين (المستلم)',
      'اسم المدين',
      'رقم هوية المدين',
      'رقم جواز المدين',
      'هاتف المدين',
      'عنوان المدين',
      '#بيانات الدائن (صاحب المبلغ)',
      'اسم الدائن',
      'رقم هوية الدائن',
      'رقم جواز الدائن',
      'هاتف الدائن',
      '#المبلغ',
      'نوع المبلغ',
      'المبلغ',
      'المبلغ كتابةً',
      'سبب الدين',
      'تاريخ الاستلام',
      '#السداد',
      'تاريخ السداد',
      'طريقة السداد',
      'عدد الأقساط',
      'قيمة القسط',
      '#الشهود',
      'الشاهد الأول',
      'الشاهد الثاني',
    ],
    // العقود بخانات نموذج العقود في العقارات والأنشطة والمركبات.
    'عقد إيجار عقار': [
      '#بيانات العقد',
      'رقم العقد',
      'رقم العقد المنتهي',
      'نمط مدة الإيجار',
      'تاريخ تحرير العقد',
      'مكان تحرير العقد',
      '#الطرف الأول (المؤجر)',
      'اسم المؤجر',
      'رقم هوية المؤجر',
      'رقم جواز المؤجر',
      'جنسية المؤجر',
      'تاريخ انتهاء هوية المؤجر',
      'هاتف المؤجر',
      'بريد المؤجر',
      'عنوان المؤجر',
      '#الطرف الثاني (المستأجر)',
      'اسم المستأجر',
      'رقم هوية المستأجر',
      'رقم جواز المستأجر',
      'جنسية المستأجر',
      'تاريخ انتهاء هوية المستأجر',
      'هاتف المستأجر',
      'بريد المستأجر',
      'عنوان المستأجر',
      '#ممثل المستأجر (إن وُجد)',
      'اسم ممثل المستأجر',
      'صفة الممثل',
      'رقم هوية الممثل',
      'رقم جواز الممثل',
      'رقم الوكالة',
      'تاريخ انتهاء الوكالة',
      '#بيانات العقار',
      'اسم العقار',
      'نوع العقار',
      'المدينة',
      'الحي',
      'عنوان العقار',
      'رقم الوحدة',
      'رقم صك الملكية',
      'مساحة العين (م٢)',
      'مكونات العين',
      'الغرض من الإيجار',
      '#المدة والقيمة',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      'قيمة الإيجار السنوي',
      'نسبة الضريبة %',
      'طريقة الدفع',
      'الدفعات',
      '#التأمين والرسوم',
      'مبلغ التأمين',
      'طريقة تحصيل التأمين',
      'الرسوم الإدارية',
      '#الالتزامات',
      'فواتير الخدمات على',
      'الصيانة البسيطة على',
      'الصيانة الأساسية على',
      'شروط إضافية',
    ],
    'عقد إيجار نشاط تجاري': [
      '#بيانات العقد',
      'رقم العقد',
      'نمط مدة الإيجار',
      'تاريخ تحرير العقد',
      'مكان تحرير العقد',
      '#الطرف الأول (المؤجر)',
      'اسم المؤجر',
      'رقم هوية المؤجر',
      'رقم جواز المؤجر',
      'جنسية المؤجر',
      'تاريخ انتهاء هوية المؤجر',
      'هاتف المؤجر',
      'بريد المؤجر',
      'عنوان المؤجر',
      '#الطرف الثاني (المستأجر)',
      'اسم المستأجر',
      'رقم هوية المستأجر',
      'رقم جواز المستأجر',
      'جنسية المستأجر',
      'هاتف المستأجر',
      'بريد المستأجر',
      '#ممثل المستأجر (إن وُجد)',
      'اسم ممثل المستأجر',
      'صفة الممثل',
      'رقم هوية الممثل',
      'رقم جواز الممثل',
      'رقم الوكالة',
      'تاريخ انتهاء الوكالة',
      '#الرخصة والنشاط',
      'الاسم التجاري',
      'رقم الرخصة التجارية',
      'تاريخ انتهاء الرخصة',
      'نوع النشاط',
      'الشكل القانوني',
      'رأس المال',
      'الأنشطة التجارية',
      '#بيانات المحل',
      'موقع المحل',
      'رقم المحل',
      'المساحة (م٢)',
      '#المدة والقيمة',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      'قيمة الإيجار السنوي',
      'نسبة الضريبة %',
      'طريقة الدفع',
      'فترة السماح للتجهيز',
      'الدفعات',
      '#التأمين والرسوم',
      'مبلغ التأمين',
      'طريقة تحصيل التأمين',
      'الرسوم الإدارية',
      '#الالتزامات',
      'فواتير الخدمات على',
      'الصيانة على',
      'اللوحات والديكور على',
      'شروط إضافية',
    ],
    'عقد تأجير مركبة': [
      '#بيانات العقد',
      'رقم العقد',
      'تاريخ تحرير العقد',
      'مكان تحرير العقد',
      '#الطرف الأول (المؤجر)',
      'اسم المؤجر',
      'رقم هوية المؤجر',
      'رقم جواز المؤجر',
      'هاتف المؤجر',
      'بريد المؤجر',
      'عنوان المؤجر',
      '#الطرف الثاني (المستأجر)',
      'اسم المستأجر',
      'رقم هوية المستأجر',
      'رقم جواز المستأجر',
      'جنسية المستأجر',
      'رقم رخصة القيادة',
      'تاريخ انتهاء رخصة القيادة',
      'هاتف المستأجر',
      'بريد المستأجر',
      '#بيانات المركبة',
      'المركبة',
      'نوع المركبة',
      'الموديل',
      'رقم اللوحة',
      'رقم الهيكل / الشاصي',
      'سنة الصنع',
      'اللون',
      'قراءة العداد عند التسليم',
      'مستوى الوقود عند التسليم',
      '#المدة والقيمة',
      'تاريخ بداية العقد',
      'من الساعة',
      'تاريخ نهاية العقد',
      'إلى الساعة',
      'أساس التأجير',
      'قيمة الإيجار',
      'نسبة الضريبة %',
      'الكيلومترات المسموحة',
      'رسوم الكيلومتر الإضافي',
      'الدفعات',
      '#السائق / القبطان (إن وُجد)',
      'اسم السائق',
      'رقم رخصة السائق',
      'تاريخ انتهاء رخصة السائق',
      '#التأمين والرسوم',
      'مبلغ التأمين',
      'طريقة تحصيل التأمين',
      'الرسوم الإدارية',
      '#الالتزامات',
      'الوقود على',
      'الصيانة الدورية على',
      'التأمين على المركبة',
      'شروط إضافية',
    ],
    'عقد عام': [
      '#بيانات العقد',
      'تاريخ تحرير العقد',
      '#الطرف الأول',
      'الطرف الأول',
      'رقم هوية الطرف الأول',
      'رقم جواز الطرف الأول',
      'هاتف الطرف الأول',
      '#الطرف الثاني',
      'الطرف الثاني',
      'رقم هوية الطرف الثاني',
      'رقم جواز الطرف الثاني',
      'هاتف الطرف الثاني',
      '#موضوع العقد وقيمته',
      'موضوع العقد',
      'قيمة العقد',
      'طريقة الدفع',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      '#الالتزامات',
      'التزامات الطرف الأول',
      'التزامات الطرف الثاني',
      'شروط إضافية',
    ],
    'إيصال استلام وتسليم': [
      '#الأطراف',
      'اسم المستلم',
      'رقم هوية المستلم',
      'رقم جواز المستلم',
      'اسم المسلّم',
      'رقم هوية المسلّم',
      'رقم جواز المسلّم',
      'مكان التسليم',
      'تاريخ التسليم',
      '#العناصر المسلّمة',
      'العناصر المسلّمة',
      '#حالة الاستلام',
      'حالة الاستلام',
    ],
    'فاتورة': [
      '#العميل',
      'اسم الجهة',
      'الرقم الضريبي',
      'عنوان العميل',
      '#بيانات الفاتورة',
      'رقم الفاتورة',
      'الرقم الضريبي للمُصدر',
      'عنوان المُصدر',
      '#البنود',
      'بنود الفاتورة',
      'نسبة الضريبة %',
      '#الدفع',
      'اسم البنك',
      'الآيبان',
    ],
    'تقرير ضريبي': [
      '#الفترة والمكلّف',
      'الفترة الضريبية',
      'اسم المكلّف',
      'الرقم الضريبي',
      'تاريخ استحقاق السداد',
      '#التفصيل الشهري',
      'التفصيل الشهري',
      'نسبة الضريبة %',
      '#الإجمالي (إن لم يُفصَّل شهريًا)',
      'الإيرادات',
      'الضريبة',
    ],
    'عقد': ['الطرف الأول', 'الطرف الثاني', 'موضوع العقد', 'قيمة العقد'],
    'إنذار': [
      '#المرسل إليه',
      'المرسل إليه',
      'رقم هوية المرسل إليه',
      'رقم جواز المرسل إليه',
      'عنوان المرسل إليه',
      '#الموضوع',
      'سبب الإنذار',
      'رقم العقد المرتبط',
      'نص الإنذار',
      'المبلغ المطالب به',
      '#المهلة والإجراء',
      'المهلة',
      'تاريخ انتهاء المهلة',
      'الإجراء المطلوب',
    ],
  };

  /// حقول جداول (أكثر من سطر): الاسم ← الأعمدة. تُحفظ JSON في الحقل نفسه.
  static const Map<String, List<String>> _tableFields = {
    'الدفعات': [
      'اسم الدفعة',
      'القيمة',
      'تاريخ الاستحقاق',
      'طريقة التحصيل',
      'رقم الشيك / البنك',
    ],
    'الرسوم الإدارية': ['نوع الرسم', 'القيمة', 'تاريخ الاستحقاق', 'يتحمّلها'],
    'العناصر المسلّمة': [
      'العنصر',
      'الوصف / الرقم التسلسلي',
      'الكمية',
      'الحالة',
    ],
    'بنود الفاتورة': ['البيان', 'الكمية', 'سعر الوحدة'],
    'التفصيل الشهري': ['الشهر', 'المبيعات', 'المشتريات'],
  };

  static const Set<String> _numericColumns = {
    'القيمة',
    'الكمية',
    'سعر الوحدة',
    'المبيعات',
    'المشتريات',
  };

  static const Set<String> _timeFields = {'من الساعة', 'إلى الساعة'};

  static const _templateIcons = {
    'إيصال أمانة': Icons.request_quote_outlined,
    'سند قبض': Icons.payments_outlined,
    'إيصال استلام وتسليم': Icons.swap_horiz_rounded,
    'فاتورة': Icons.receipt_long_outlined,
    'تقرير ضريبي': Icons.account_balance_outlined,
    'عقد': Icons.handshake_outlined,
    'إنذار': Icons.warning_amber_rounded,
    'عقد إيجار عقار': Icons.apartment_rounded,
    'عقد إيجار نشاط تجاري': Icons.storefront_outlined,
    'عقد تأجير مركبة': Icons.directions_car_outlined,
    'عقد عام': Icons.handshake_outlined,
  };

  static const Map<String, List<String>> _optionFields = {
    'نوع المبلغ': ['دين (قرض)', 'أمانة', 'سلفة'],
    'طريقة السداد': ['دفعة واحدة', 'أقساط شهرية', 'أقساط حسب الاتفاق'],
    'نوع العقار': [
      'شقة',
      'فيلا',
      'محل تجاري',
      'مكتب',
      'مستودع',
      'أرض',
      'أخرى',
    ],
    'الغرض من الإيجار': ['سكني', 'تجاري', 'سكني وتجاري'],
    'طريقة الدفع': ['دفعة واحدة', 'دفعتان', 'أربع دفعات', 'شهريًا'],
    'فواتير الخدمات على': ['المستأجر', 'المؤجر'],
    'الصيانة البسيطة على': ['المستأجر', 'المؤجر'],
    'الصيانة الأساسية على': ['المؤجر', 'المستأجر'],
    'الصيانة على': ['المستأجر', 'المؤجر'],
    'اللوحات والديكور على': ['المستأجر', 'المؤجر'],
    'الوقود على': ['المستأجر', 'المؤجر'],
    'الصيانة الدورية على': ['المؤجر', 'المستأجر'],
    'أساس التأجير': ['بالساعات', 'يومي', 'أسبوعي', 'شهري', 'سنوي'],
    'نمط مدة الإيجار': ['يومي', 'شهري', 'سنوي', 'مخصص'],
    'طريقة تحصيل التأمين': ['نقدًا', 'تحويل بنكي', 'شيك', 'مدى'],
    'حالة الاستلام': ['سليمة بالكامل', 'بها ملاحظات', 'ناقصة'],
    'صفة الممثل': ['وكيل', 'مفوّض', 'ولي أمر', 'أخرى'],
    'الشكل القانوني': [
      'مؤسسة فردية',
      'شركة ذات مسؤولية محدودة',
      'شركة مساهمة',
      'شركة تضامن',
      'أخرى',
    ],
    'مستوى الوقود عند التسليم': ['ممتلئ', 'ثلاثة أرباع', 'نصف', 'ربع'],
    'التأمين على المركبة': [
      'تأمين شامل',
      'تأمين ضد الغير',
      'بدون تأمين',
    ],
  };

  static const Set<String> _dateFields = {
    'تاريخ الاستلام',
    'تاريخ السداد',
    'تاريخ تحرير العقد',
    'تاريخ بداية العقد',
    'تاريخ نهاية العقد',
    'تاريخ انتهاء الرخصة',
    'تاريخ انتهاء رخصة القيادة',
    'تاريخ انتهاء هوية المؤجر',
    'تاريخ انتهاء هوية المستأجر',
    'تاريخ انتهاء الوكالة',
    'تاريخ انتهاء رخصة السائق',
    'تاريخ التسليم',
    'تاريخ استحقاق السداد',
    'تاريخ انتهاء المهلة',
  };

  static const Set<String> _numberFields = {
    'المبلغ',
    'عدد الأقساط',
    'قيمة القسط',
    'قيمة الإيجار السنوي',
    'مبلغ التأمين',
    'قيمة الإيجار',
    'الكيلومترات المسموحة',
    'رسوم الكيلومتر الإضافي',
    'قراءة العداد عند التسليم',
    'المساحة (م٢)',
    'قيمة العقد',
    'سنة الصنع',
    'نسبة الضريبة %',
    'مساحة العين (م٢)',
    'رأس المال',
    'المبلغ المطالب به',
    'الإيرادات',
    'الضريبة',
  };

  static const Set<String> _multiFields = {
    'شروط إضافية',
    'موضوع العقد',
    'التزامات الطرف الأول',
    'التزامات الطرف الثاني',
    'مكونات العين',
    'الأنشطة التجارية',
    'نص الإنذار',
  };

  /// حقل الاسم الإلزامي (وعنوان التذكير) لكل نموذج — وإلا أول حقل.
  static const Map<String, String> _primaryField = {
    'عقد إيجار عقار': 'اسم المستأجر',
    'عقد إيجار نشاط تجاري': 'الاسم التجاري',
    'عقد تأجير مركبة': 'اسم المستأجر',
  };

  /// الحقل الذي يُملأ باسم العقار/النشاط حين تُفتح النماذج منه.
  static const Map<String, String> _linkField = {
    'عقد إيجار عقار': 'اسم العقار',
    'عقد إيجار نشاط تجاري': 'الاسم التجاري',
    'عقد تأجير مركبة': 'المركبة',
  };

  /// تاريخ الانتهاء (للتذكير) من حقل النموذج نفسه.
  static const Map<String, String> _expiryAlias = {
    'إيصال أمانة': 'تاريخ السداد',
    'عقد إيجار عقار': 'تاريخ نهاية العقد',
    'عقد إيجار نشاط تجاري': 'تاريخ نهاية العقد',
    'عقد تأجير مركبة': 'تاريخ نهاية العقد',
    'عقد عام': 'تاريخ نهاية العقد',
  };

  static const String _partiesIntro =
      'إنه في يوم {تاريخ تحرير العقد} بمدينة {مكان تحرير العقد} تم الاتفاق '
      'بين كلٍّ من الطرف الأول (المؤجر): {اسم المؤجر}، والطرف الثاني '
      '(المستأجر): {اسم المستأجر}، وقد أقرّ الطرفان بأهليتهما للتعاقد '
      'واتفقا على ما يلي:';

  /// صيغة الإقرار في رأس المستند — {الحقل} يُستبدل بقيمته.
  static const Map<String, String> _templateIntro = {
    // {@المدين}: رقم الهوية و/أو الجواز بين قوسين إن كُتب أيٌّ منهما.
    'إيصال أمانة':
        'أقرّ أنا الموقّع أدناه {اسم المدين}{@المدين}، بأنني استلمت من '
        '{اسم الدائن}{@الدائن}، مبلغًا وقدره {المبلغ} ({المبلغ كتابةً}) على '
        'سبيل {نوع المبلغ}، وذلك بتاريخ {تاريخ الاستلام}.',
    'عقد إيجار عقار': _partiesIntro,
    'عقد إيجار نشاط تجاري': _partiesIntro,
    'عقد تأجير مركبة': _partiesIntro,
    'عقد عام':
        'إنه في يوم {تاريخ تحرير العقد} تم الاتفاق بين كلٍّ من الطرف '
        'الأول: {الطرف الأول}، والطرف الثاني: {الطرف الثاني}، وقد أقرّ '
        'الطرفان بأهليتهما للتعاقد واتفقا على ما يلي:',
  };

  static const String _clauseDeposit =
      '?دفع المستأجر مبلغ تأمين قدره {مبلغ التأمين}، يُردّ إليه عند انتهاء '
      'العقد بعد خصم قيمة أي أضرار أو مستحقات قائمة.';
  static const String _clauseExtra = '?شروط إضافية: {شروط إضافية}';
  static const String _clauseCopies =
      'حُرِّر هذا العقد من نسختين، بيد كل طرف نسخة للعمل بموجبها.';
  static const String _clauseTerm =
      'مدة العقد من {تاريخ بداية العقد} إلى {تاريخ نهاية العقد}، ولا '
      'يُجدَّد إلا باتفاق مكتوب بين الطرفين.';
  static const String _clauseRent =
      'الأجرة السنوية {قيمة الإيجار السنوي}، تُدفع {طريقة الدفع} مقدمًا في '
      'مواعيد استحقاقها، ولا يحق للمستأجر تأخيرها أو الامتناع عنها.';
  static const String _clauseBreach =
      'إذا تأخر المستأجر عن سداد الأجرة أو أخلّ بأي من التزاماته، يحق '
      'للمؤجر المطالبة بفسخ العقد وبما يستحقه وفق الأنظمة المعمول بها.';

  /// البنود — ما يبدأ بـ «?» لا يظهر إلا إن امتلأت حقوله.
  static const Map<String, List<String>> _templateClauses = {
    'إيصال أمانة': [
      '?سبب الدين: {سبب الدين}.',
      'أتعهد بردّ المبلغ كاملًا إلى الدائن أو من يفوّضه في موعد أقصاه '
          '{تاريخ السداد}، وطريقة السداد: {طريقة السداد}.',
      '?يُسدَّد المبلغ على {عدد الأقساط} أقساط، قيمة كل قسط {قيمة القسط}.',
      'يُعدّ هذا الإيصال سندًا بالمبلغ، ويحق للدائن عند التأخر عن السداد '
          'المطالبة به بالطرق النظامية.',
      'وهذا إقرار مني بذلك وأنا بكامل أهليتي المعتبرة شرعًا ونظامًا.',
    ],
    'عقد إيجار عقار': [
      _clauseTerm,
      _clauseRent,
      _clauseDeposit,
      'يستعمل المستأجر العقار للغرض المتفق عليه ({الغرض من الإيجار}) '
          'فقط، ولا يحق له التأجير من الباطن أو التنازل عن العقد إلا '
          'بموافقة كتابية من المؤجر.',
      'فواتير الخدمات (الكهرباء والماء والاتصالات) على '
          '{فواتير الخدمات على}، والصيانة البسيطة على '
          '{الصيانة البسيطة على}، والصيانة الأساسية والإنشائية على '
          '{الصيانة الأساسية على}.',
      'لا يجوز للمستأجر إجراء أي تعديلات أو إنشاءات في العقار إلا '
          'بموافقة كتابية من المؤجر.',
      'يلتزم المستأجر بالمحافظة على العقار وتسليمه عند انتهاء العقد '
          'بالحالة التي استلمه بها، عدا الاستهلاك المعتاد.',
      _clauseBreach,
      _clauseExtra,
      _clauseCopies,
    ],
    'عقد إيجار نشاط تجاري': [
      _clauseTerm,
      _clauseRent,
      _clauseDeposit,
      '?منح المؤجر المستأجر فترة سماح للتجهيز مدتها '
          '{فترة السماح للتجهيز} لا تُحتسب فيها أجرة.',
      'يستعمل المستأجر المحل لممارسة نشاط ({نوع النشاط}) تحت الاسم '
          'التجاري ({الاسم التجاري}) فقط، ولا يحق له تغيير النشاط أو '
          'التأجير من الباطن إلا بموافقة كتابية من المؤجر.',
      'يلتزم المستأجر باستخراج التراخيص اللازمة لنشاطه وتجديدها قبل '
          'انتهائها، ويتحمّل وحده أي مخالفات أو غرامات تنشأ عن نشاطه.',
      'فواتير الخدمات على {فواتير الخدمات على}، والصيانة على '
          '{الصيانة على}، واللوحات والديكور على {اللوحات والديكور على}.',
      'عند انتهاء العقد يسلّم المستأجر المحل خاليًا من الشواغل وبالحالة '
          'التي استلمه بها، وتؤول التحسينات الثابتة للمؤجر ما لم يُتفق '
          'على غير ذلك.',
      _clauseBreach,
      _clauseExtra,
      _clauseCopies,
    ],
    'عقد تأجير مركبة': [
      'مدة الإيجار من {تاريخ بداية العقد} إلى {تاريخ نهاية العقد}، '
          'وأجرة المركبة {قيمة الإيجار} على أساس {أساس التأجير}.',
      '?دفع المستأجر مبلغ تأمين قدره {مبلغ التأمين}، يُردّ عند إعادة '
          'المركبة سليمة بعد خصم أي مستحقات.',
      'استلم المستأجر المركبة بحالة جيدة، وقراءة العداد '
          '{قراءة العداد عند التسليم} كم، ومستوى الوقود '
          '{مستوى الوقود عند التسليم}، ويعيدها بالحالة نفسها.',
      '?الكيلومترات المسموحة {الكيلومترات المسموحة} كم، وما زاد عليها '
          'يُحتسب بواقع {رسوم الكيلومتر الإضافي} لكل كيلومتر.',
      'المستأجر مسؤول عن المخالفات المرورية والحوادث وما يترتب عليها '
          'طوال مدة الإيجار، وعليه إبلاغ المؤجر والجهات المختصة فور وقوع '
          'أي حادث.',
      'لا يحق للمستأجر السماح لغيره بقيادة المركبة، أو استعمالها في غير '
          'الغرض المعتاد، أو الخروج بها خارج الدولة إلا بموافقة كتابية من '
          'المؤجر.',
      'الوقود على {الوقود على}، والصيانة الدورية على '
          '{الصيانة الدورية على}، ونوع التأمين على المركبة: '
          '{التأمين على المركبة}.',
      'التأخر في إعادة المركبة عن الموعد المحدد يُحتسب بأجرة يوم كامل عن '
          'كل يوم تأخير أو جزء منه.',
      _clauseExtra,
      _clauseCopies,
    ],
    'عقد عام': [
      'موضوع العقد: {موضوع العقد}',
      '?قيمة العقد {قيمة العقد}، تُدفع {طريقة الدفع}.',
      '?مدة العقد من {تاريخ بداية العقد} إلى {تاريخ نهاية العقد}.',
      '?يلتزم الطرف الأول بما يلي: {التزامات الطرف الأول}',
      '?يلتزم الطرف الثاني بما يلي: {التزامات الطرف الثاني}',
      'في حال إخلال أي طرف بالتزاماته يحق للطرف الآخر المطالبة بالتعويض '
          'وفسخ العقد وفق الأنظمة المعمول بها.',
      _clauseExtra,
      _clauseCopies,
    ],
  };

  /// خانات التوقيع: (الصفة، حقل الاسم).
  static const Map<String, List<(String, String)>> _templateSigners = {
    'إيصال أمانة': [
      ('المدين', 'اسم المدين'),
      ('الدائن', 'اسم الدائن'),
      ('الشاهد الأول', 'الشاهد الأول'),
      ('الشاهد الثاني', 'الشاهد الثاني'),
    ],
    'عقد إيجار عقار': [
      ('الطرف الأول (المؤجر)', 'اسم المؤجر'),
      ('الطرف الثاني (المستأجر)', 'اسم المستأجر'),
    ],
    'عقد إيجار نشاط تجاري': [
      ('الطرف الأول (المؤجر)', 'اسم المؤجر'),
      ('الطرف الثاني (المستأجر)', 'اسم المستأجر'),
    ],
    'عقد تأجير مركبة': [
      ('الطرف الأول (المؤجر)', 'اسم المؤجر'),
      ('الطرف الثاني (المستأجر)', 'اسم المستأجر'),
    ],
    'عقد عام': [
      ('الطرف الأول', 'الطرف الأول'),
      ('الطرف الثاني', 'الطرف الثاني'),
    ],
  };

  /// نموذج محكم: بإقرار وبنود وخانات توقيع.
  static bool _isFormal(String type) => _templateClauses.containsKey(type);

  static List<String> _inputsOf(String type) => _templateFields[type]!
      .where((field) => !field.startsWith('#'))
      .toList(growable: false);

  static String _primaryOf(String type) =>
      _primaryField[type] ?? _inputsOf(type).first;

  /// الحقول الإلزامية لكل نموذج — عليها نجمة، ولا يُحفظ النموذج (غير
  /// المسودة) بدونها. حقل الاسم الأساسي إلزامي دائمًا.
  static const Map<String, List<String>> _requiredFields = {
    'إيصال أمانة': [
      'اسم المدين',
      'اسم الدائن',
      'المبلغ',
      'تاريخ الاستلام',
    ],
    'عقد إيجار عقار': [
      'اسم المؤجر',
      'اسم المستأجر',
      'اسم العقار',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      'قيمة الإيجار السنوي',
    ],
    'عقد إيجار نشاط تجاري': [
      'اسم المؤجر',
      'اسم المستأجر',
      'الاسم التجاري',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      'قيمة الإيجار السنوي',
    ],
    'عقد تأجير مركبة': [
      'اسم المؤجر',
      'اسم المستأجر',
      'رقم رخصة القيادة',
      'المركبة',
      'رقم اللوحة',
      'تاريخ بداية العقد',
      'تاريخ نهاية العقد',
      'قيمة الإيجار',
    ],
    'عقد عام': [
      'تاريخ تحرير العقد',
      'الطرف الأول',
      'الطرف الثاني',
      'موضوع العقد',
    ],
    'إيصال استلام وتسليم': ['اسم المستلم', 'اسم المسلّم', 'تاريخ التسليم'],
    'فاتورة': ['اسم الجهة', 'رقم الفاتورة'],
    'تقرير ضريبي': ['الفترة الضريبية', 'اسم المكلّف', 'الرقم الضريبي'],
    'إنذار': ['المرسل إليه', 'سبب الإنذار', 'نص الإنذار'],
  };

  static bool _isRequired(String type, String field) =>
      field == _primaryOf(type) ||
      (_requiredFields[type]?.contains(field) ?? false);

  List<DocumentRecordEntry> _savedRecords = const [];
  bool _loading = true;
  List<List<Offset>> _signature = const [];

  /// صورة الختم المحفوظة (إن وُجدت) — تُعرض مع التوقيع في النموذج.
  Uint8List? _stamp;

  /// شعار المستخدم — في رأس الصفحة وأعلى كل نموذج.
  Uint8List? _logo;

  static const Map<String, String> _templateHints = {
    'إيصال أمانة': 'إقرار دين أو أمانة بين طرفين مع الشهود',
    'سند قبض': 'راتب شهري لموظف أو سند عام، بتوقيع المستلم',
    'إيصال استلام وتسليم': 'إثبات تسليم عنصر وحالته',
    'فاتورة': 'البيان والمبلغ والرقم الضريبي',
    'تقرير ضريبي': 'الإيرادات والضريبة لفترة محددة',
    'عقد': 'عقار، نشاط تجاري، مركبة، أو عقد عام',
    'إنذار': 'إنذار رسمي بمهلة وإجراء مطلوب',
  };

  static const Map<String, Color> _templateColors = {
    'إيصال أمانة': Color(0xFF0E7161),
    'سند قبض': Color(0xFF0A5A50),
    'إيصال استلام وتسليم': Color(0xFF178F7B),
    'فاتورة': Color(0xFFA6691A),
    'تقرير ضريبي': Color(0xFF5C6B68),
    'عقد': Color(0xFF0A5A50),
    'إنذار': Color(0xFFC4392E),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // مؤشر التحميل في أول تحميل فقط، وإلا أزال السحبُ للتحديث القائمةَ
    // ومعها مؤشر السحب نفسه.
    setState(() => _loading = _savedRecords.isEmpty);
    final signature = await UserSignatureStore.load();
    final stamp = await UserStampStore.load();
    final logo = await UserLogoStore.load();
    var records = <DocumentRecordEntry>[];
    try {
      records = await _repository.fetchDocuments();
    } catch (_) {
      // تُترك القائمة فارغة؛ يظهر الخطأ عند محاولة الحفظ.
    }
    // كيانات الربط الحقيقية: الأشخاص/الجهات من إدارة الأفراد، والعقارات
    // والأنشطة من قاعدة البيانات — فيرتبط الإيصال أو العقد بسجل فعلي بدل
    // أن يكون ورقة معزولة لا يعرف التطبيق علاقتها بشيء.
    final targets = <({String kind, String label, String id})>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawPeople = prefs.getString('people_management_records_v1');
      if (rawPeople != null && rawPeople.trim().isNotEmpty) {
        final decoded = jsonDecode(rawPeople);
        if (decoded is List) {
          var index = 0;
          for (final entry in decoded.whereType<Map>()) {
            final name = (entry['fullName'] ?? '').toString().trim();
            index++;
            if (name.isEmpty) continue;
            // المعرّف يجب أن يكون فريدًا: شخصان بنفس الاسم كانا سيُنتجان
            // خيارين بنفس القيمة، وهو ما يُسقط القائمة المنسدلة بتأكيد
            // داخلي فور اختيار أحدهما.
            targets.add((kind: 'شخص/جهة', label: name, id: 'person:$index:$name'));
          }
        }
      }
    } catch (_) {
      // مخزون تالف — تُتخطّى قائمة الأشخاص فقط.
    }
    try {
      final assets = await _assetsRepository.fetchAssets();
      for (final asset in assets) {
        if (asset.id == null || asset.title.trim().isEmpty) continue;
        targets.add((
          kind: 'عقار/نشاط',
          label: asset.title.trim(),
          id: 'asset:${asset.id!}',
        ));
      }
    } catch (_) {
      // تعذّر جلب الأصول — تبقى قائمة الأشخاص متاحة.
    }
    if (!mounted) return;
    setState(() {
      _savedRecords = records;
      _signature = signature;
      _stamp = stamp;
      _logo = logo;
      _linkTargets = targets;
      _loading = false;
    });
  
  }

  Future<void> _openTemplate(
    String type, {
    DocumentRecordEntry? existing,
  }) async {
    final formal = _isFormal(type);
    final controllers = {
      for (final field in _inputsOf(type)) field: TextEditingController(),
      // النموذج المحكم له تواريخه في حقوله نفسها.
      if (!formal)
        'تاريخ الإصدار': TextEditingController(
          text: _formatDate(DateTime.now()),
        ),
      if (!formal) 'تاريخ الانتهاء': TextEditingController(),
      'ملاحظات': TextEditingController(),
    };
    if (formal) {
      controllers['تاريخ تحرير العقد']?.text = _formatDate(DateTime.now());
      controllers['تاريخ الاستلام']?.text = _formatDate(DateTime.now());
    }
    if (widget.linkedProperty != null) {
      controllers[_linkField[type] ?? _inputsOf(type).first]!.text =
          widget.linkedProperty!;
    }
    var reminderLabel = 'قبل أسبوع';
    var includeSignature = false;
    ({String kind, String label, String id})? link;
    // فتح مسودة أو نموذج محفوظ: تُملأ الحقول بقيمه.
    if (existing != null) {
      existing.fields.forEach((key, value) {
        controllers[key]?.text = value;
      });
      reminderLabel = existing.fields['reminder']?.isNotEmpty == true
          ? existing.fields['reminder']!
          : reminderLabel;
      includeSignature = existing.fields['includeSignature'] == '1';
      if ((existing.linkedId ?? '').isNotEmpty) {
        for (final target in _linkTargets) {
          if (target.id == existing.linkedId) link = target;
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // النموذج الطويل لا يصعد تحت شريط الحالة والنتوء: زر الإغلاق يبقى
      // في متناول الإصبع.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
            ),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: AppTr.uiDir,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            type,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        // حفظ ثم معاينة الطباعة مباشرة.
                        IconButton(
                          tooltip: AppTr.tr('حفظ وطباعة'),
                          onPressed: () => _saveTemplate(
                            sheetContext,
                            type,
                            controllers,
                            reminderLabel,
                            includeSignature,
                            link,
                            existingId: existing?.id,
                            andPrint: true,
                          ),
                          icon: const Icon(Icons.print_rounded),
                        ),
                        IconButton(
                          tooltip: AppTr.tr('إغلاق'),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final field in _templateFields[type]!)
                      if (field.startsWith('#'))
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            field.substring(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0A5A50),
                            ),
                          ),
                        )
                      else ...[
                        _inputFor(
                          sheetContext,
                          field,
                          controllers[field]!,
                          setSheetState,
                          required: _isRequired(type, field),
                        ),
                        const SizedBox(height: 9),
                      ],
                    if (!formal) ...[
                      _dateField(
                        sheetContext,
                        controllers['تاريخ الإصدار']!,
                        'تاريخ الإصدار',
                      ),
                      const SizedBox(height: 9),
                      _dateField(
                        sheetContext,
                        controllers['تاريخ الانتهاء']!,
                        'تاريخ الانتهاء',
                      ),
                      const SizedBox(height: 9),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: reminderLabel,
                      decoration: InputDecoration(
                        labelText: AppTr.tr('التذكير قبل الانتهاء'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items:
                          const [
                                'في يوم الانتهاء',
                                'قبل يوم',
                                'قبل 3 أيام',
                                'قبل أسبوع',
                                'قبل أسبوعين',
                                'قبل شهر',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => reminderLabel = value);
                        }
                      },
                    ),
                    const SizedBox(height: 9),
                    _textField(controllers['ملاحظات']!, 'ملاحظات', maxLines: 3),
                    if (_signature.isNotEmpty || _stamp != null) ...[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إضافة توقيعي وختمي إلى النموذج'),
                        subtitle: const Text(
                          'اختياري ويمكن تعطيله لكل نموذج',
                        ),
                        value: includeSignature,
                        onChanged: (value) =>
                            setSheetState(() => includeSignature = value),
                      ),
                      if (includeSignature)
                        Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAF9),
                            border: Border.all(color: const Color(0xFFE4EAE8)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _signature.isEmpty && _stamp != null
                              ? Image.memory(_stamp!, fit: BoxFit.contain)
                              : CustomPaint(
                                  painter: UserSignaturePainter(_signature),
                                ),
                        ),
                    ] else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.draw_outlined),
                        title: const Text('لا يوجد توقيع أو ختم محفوظ'),
                        trailing: TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SignatureSettingsScreen(),
                              ),
                            );
                            final signature = await UserSignatureStore.load();
                            final stamp = await UserStampStore.load();
                            if (!mounted) return;
                            setState(() {
                              _signature = signature;
                              _stamp = stamp;
                            });
                            setSheetState(() {});
                          },
                          child: const Text('إضافة توقيع أو ختم'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // ربط المستند بسجل حقيقي في التطبيق (شخص/جهة أو
                    // عقار/نشاط) بدل أن يبقى ورقة معزولة لا يعرف التطبيق
                    // علاقتها بشيء.
                    if (_linkTargets.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.link_off_rounded),
                        title: Text('لا توجد سجلات للربط بها بعد'),
                        subtitle: Text(
                          'أضف شخصًا أو عقارًا ليمكن ربط المستند به',
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: link?.id,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: AppTr.tr('ربط المستند بـ (اختياري)'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('بدون ربط'),
                          ),
                          ..._linkTargets.map(
                            (t) => DropdownMenuItem<String>(
                              value: t.id,
                              child: Text(
                                '${t.kind}: ${t.label}',
                                maxLines: 3,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setSheetState(() {
                          link = value == null
                              ? null
                              : _linkTargets.firstWhere((t) => t.id == value);
                        }),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _saveTemplate(
                              sheetContext,
                              type,
                              controllers,
                              reminderLabel,
                              includeSignature,
                              link,
                              draft: true,
                              existingId: existing?.id,
                            ),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('حفظ كمسودة'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _saveTemplate(
                              sheetContext,
                              type,
                              controllers,
                              reminderLabel,
                              includeSignature,
                              link,
                              existingId: existing?.id,
                            ),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('حفظ النموذج'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _saveTemplate(
    BuildContext sheetContext,
    String type,
    Map<String, TextEditingController> controllers,
    String reminderLabel,
    bool includeSignature,
    ({String kind, String label, String id})? link, {
    bool draft = false,
    String? existingId,
    bool andPrint = false,
  }) async {
    final firstField = _primaryOf(type);
    // المسودة تُحفظ ناقصة ويُرجع إليها لاحقًا. غيرها: كل حقل عليه نجمة.
    if (!draft) {
      for (final field in _inputsOf(type)) {
        if (!_isRequired(type, field)) continue;
        if ((controllers[field]?.text ?? '').trim().isNotEmpty) continue;
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text('${AppTr.tr('أدخل')} ${AppTr.tr(field)}')),
        );
        return;
      }
    }

    final values = {
      for (final entry in controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    values['includeSignature'] = includeSignature ? '1' : '0';
    values['reminder'] = reminderLabel;
    if (draft) values['__draft'] = '1';
    if (_isFormal(type)) {
      // الصيغة المحكمة (إقرار وبنود وتوقيعات) في المعاينة.
      values['__v'] = '2';
      final alias = _expiryAlias[type];
      if (alias != null) values['تاريخ الانتهاء'] = values[alias] ?? '';
    }

    final expiry = draft
        ? null
        : AppRemindersStore.parseDisplayDate(values['تاريخ الانتهاء'] ?? '');

    DocumentRecordEntry saved;
    try {
      saved = await _repository.upsertDocument(
        DocumentRecordEntry(
          id: existingId,
          docType: type,
          fields: values,
          linkedKind: link?.kind,
          linkedLabel: link?.label,
          linkedId: link?.id,
          issuedOn: DateTime.now(),
        ),
      );
    } catch (_) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ النموذج. حاول مرة أخرى.')),
      );
      return;
    }

    if (expiry != null && saved.id != null) {
      await AppRemindersStore.upsert(
        AppReminder(
          id: saved.id!,
          title: '$type: ${values[firstField]}',
          module: widget.linkedProperty == null
              ? 'النماذج والمستندات'
              : 'العقارات والأنشطة التجارية',
          expiryDate: expiry,
          remindBeforeDays: AppRemindersStore.reminderDaysFromLabel(
            reminderLabel,
          ),
        ),
      );
    }

    await _load();
    if (!mounted || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    // الرسالة تصف ما حدث فعلًا: التذكير لا يُنشأ إلا عند إدخال تاريخ
    // انتهاء. كانت تُعلن إنشاء تذكير في كل مرة حتى بلا تاريخ.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          draft
              ? 'حُفظت المسودة — افتحها من «النماذج المحفوظة» لإكمالها'
              : expiry == null
              ? 'تم حفظ النموذج — اسحب الصفحة للأعلى لمشاهدة النماذج المحفوظة'
              : 'تم حفظ النموذج وإضافة تذكير الانتهاء — اسحب الصفحة للأعلى لمشاهدة النماذج المحفوظة',
        ),
      ),
    );
    if (andPrint && !draft) await _printRecord(saved);
  }

  Future<void> _shareRecord(DocumentRecordEntry record) async {
    // النماذج المعروفة تُشارَك مستند PDF رسميًا (كالطباعة)، لا صورة.
    if (_templateFields.containsKey(record.docType)) {
      await _printRecord(record, shareOnly: true);
      return;
    }
    // تُستبعد الحقول الداخلية من المعاينة حتى لا تظهر أسطر مثل
    // "includeSignature: 1" داخل المستند المُشارَك.
    const internal = {'includeSignature', 'reminder', '__v', '__draft'};
    final logo = await UserLogoStore.load();
    final formal =
        record.fields['__v'] == '2' && _isFormal(record.docType);
    final values = <String, dynamic>{
      for (final e in record.fields.entries)
        if (!internal.contains(e.key) && !_tableFields.containsKey(e.key))
          e.key: e.value,
      if ((record.linkedLabel ?? '').isNotEmpty)
        'مرتبط بـ': '${record.linkedKind}: ${record.linkedLabel}',
    };
    final withSignature = record.fields['includeSignature'] == '1';
    final signature = withSignature
        ? await UserSignatureStore.load()
        : <List<Offset>>[];
    // الختم المحفوظ في صفحة "التوقيع الإلكتروني والختم" يظهر بجانب
    // التوقيع، فلا يبقى الختم صورة محفوظة لا تُستخدم في شيء.
    final stamp = withSignature ? await UserStampStore.load() : null;
    if (!mounted) return;
    final previewKey = GlobalKey();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('معاينة النموذج'),
          content: SingleChildScrollView(
            child: RepaintBoundary(
              key: previewKey,
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // الشعار في منتصف أعلى الصفحة.
                    if (logo != null) ...[
                      Center(
                        child: Image.memory(
                          logo,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      record.docType,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const Divider(height: 28),
                    if (formal)
                      ..._formalBody(record)
                    else
                    for (final entry in values.entries)
                      if (entry.value.toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Color(0xFF1C2C29),
                            ),
                          ),
                        ),
                    if (signature.isNotEmpty || stamp != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (signature.isNotEmpty)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'التوقيع',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 82,
                                    child: CustomPaint(
                                      painter: UserSignaturePainter(signature),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (signature.isNotEmpty && stamp != null)
                            const SizedBox(width: 12),
                          if (stamp != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'الختم',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 82,
                                    child: Image.memory(
                                      stamp,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerRight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final boundary =
                    previewKey.currentContext?.findRenderObject()
                        as RenderRepaintBoundary?;
                if (boundary == null) return;
                final image = await boundary.toImage(pixelRatio: 3);
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (data == null || !dialogContext.mounted) return;
                await SharePlus.instance.share(
                  ShareParams(
                    text: record.docType,
                    files: [
                      XFile.fromData(
                        data.buffer.asUint8List(),
                        mimeType: 'image/png',
                        name: 'fundly-document.png',
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('مشاركة كصورة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRecord(DocumentRecordEntry record) async {
    final id = record.id;
    if (id == null) return;
    try {
      await _repository.deleteDocument(id);
      // يُحذف تذكير الانتهاء المرتبط أيضًا، وإلا بقي ينبّه عن مستند محذوف.
      await AppRemindersStore.remove(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حذف النموذج')),
      );
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف النموذج')));
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      textDirection: AppTr.uiDir,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(
        labelText: AppTr.tr(label),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  /// حقل النموذج بنوعه: قائمة، تاريخ، رقم، أو نص.
  Widget _inputFor(
    BuildContext sheetContext,
    String field,
    TextEditingController controller,
    StateSetter setSheetState, {
    bool required = false,
  }) {
    if (_tableFields.containsKey(field)) {
      return _rowsEditor(sheetContext, field, controller, setSheetState);
    }
    final label = required ? '$field *' : field;
    if (_timeFields.contains(field)) {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: AppTr.tr(label),
          suffixIcon: const Icon(Icons.schedule_rounded),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onTap: () async {
          final picked = await showTimePicker(
            context: sheetContext,
            initialTime: TimeOfDay.now(),
          );
          if (picked == null) return;
          controller.text =
              '${picked.hour.toString().padLeft(2, '0')}:'
              '${picked.minute.toString().padLeft(2, '0')}';
        },
      );
    }
    final options = _optionFields[field];
    if (options != null) {
      return DropdownButtonFormField<String>(
        initialValue:
            options.contains(controller.text) ? controller.text : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: AppTr.tr(label),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (value) =>
            setSheetState(() => controller.text = value ?? ''),
      );
    }
    if (_dateFields.contains(field)) {
      return _dateField(sheetContext, controller, label);
    }
    return _textField(
      controller,
      label,
      maxLines: _multiFields.contains(field) ? 3 : 1,
      numeric: _numberFields.contains(field),
    );
  }

  /// جدول بأسطر: كل سطر بأعمدته، وزر «إضافة سطر». يُحفظ JSON في الحقل.
  Widget _rowsEditor(
    BuildContext sheetContext,
    String field,
    TextEditingController controller,
    StateSetter setSheetState,
  ) {
    final columns = _tableFields[field]!;
    var rows = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(controller.text);
      if (decoded is List) {
        rows = [
          for (final row in decoded.whereType<Map>())
            Map<String, dynamic>.from(row),
        ];
      }
    } catch (_) {}
    void save() => controller.text = jsonEncode(rows);
    Widget cell(int r, String column) {
      final id = rows[r]['__id'] ?? r;
      final value = '${rows[r][column] ?? ''}';
      final decoration = InputDecoration(
        labelText: AppTr.tr(column),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
      );
      if (column.contains('تاريخ')) {
        return InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: DateTime.now(),
              firstDate: DateTime(2015),
              lastDate: DateTime(2070),
            );
            if (picked == null) return;
            rows[r][column] = _formatDate(picked);
            save();
            setSheetState(() {});
          },
          child: InputDecorator(
            decoration: decoration.copyWith(
              suffixIcon: const Icon(Icons.event_outlined, size: 18),
            ),
            child: Text(value.isEmpty ? '—' : value),
          ),
        );
      }
      return TextFormField(
        key: ValueKey('$field-$id-$column'),
        initialValue: value,
        textDirection: AppTr.uiDir,
        keyboardType: _numericColumns.contains(column)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: decoration,
        onChanged: (text) {
          rows[r][column] = text;
          save();
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAF9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            field,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0A5A50),
            ),
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < rows.length; r++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${AppTr.tr('سطر')} ${r + 1}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.muted,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: AppTr.tr('حذف'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          rows.removeAt(r);
                          save();
                          setSheetState(() {});
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final column in columns)
                        FractionallySizedBox(
                          widthFactor: columns.length == 1 ? 1 : 0.48,
                          child: cell(r, column),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                rows.add({'__id': DateTime.now().microsecondsSinceEpoch});
                save();
                setSheetState(() {});
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة سطر'),
            ),
          ),
        ],
      ),
    );
  }

  /// طباعة نموذج محفوظ: ورقة A4 بكل خاناته (الفارغ لا يُطبع).
  /// [shareOnly]: المستند نفسه PDF رسميًا يُشارَك مباشرة بلا شاشة الطباعة.
  Future<void> _printRecord(
    DocumentRecordEntry record, {
    bool shareOnly = false,
  }) async {
    final type = record.docType;
    final spec = _templateFields[type];
    if (spec == null) return;
    String val(String key) => (record.fields[key] ?? '').toString().trim();
    String fill(String template) =>
        AppTr.tr(template).replaceAllMapped(_slot, (match) {
          final key = match.group(1)!;
          if (key.startsWith('@')) return _idPhrase(val, key.substring(1));
          final value = val(key);
          return value.isEmpty ? '..........' : value;
        });
    bool complete(String template) => _slot
        .allMatches(template)
        .every((match) => val(match.group(1)!).isNotEmpty);
    final formal = _isFormal(type);
    // الحقول الطويلة التي تذكرها البنود لا تتكرر في الأقسام.
    final inClauses = <String>{
      for (final clause in _templateClauses[type] ?? const <String>[])
        for (final match in _slot.allMatches(clause)) match.group(1)!,
    };
    final signerSpec = _templateSigners[type] ?? const <(String, String)>[];
    final witnessKeys = {
      for (final (role, key) in signerSpec)
        if (role.startsWith('الشاهد')) key,
    };
    final sections = <(String, List<String>)>[];
    var heading = 'البيانات';
    var keys = <String>[];
    for (final field in spec) {
      if (field.startsWith('#')) {
        if (keys.isNotEmpty) sections.add((heading, keys));
        heading = field.substring(1);
        keys = <String>[];
        continue;
      }
      if (witnessKeys.contains(field)) continue;
      if (formal && _multiFields.contains(field) && inClauses.contains(field)) {
        continue;
      }
      keys.add(field);
    }
    if (keys.isNotEmpty) sections.add((heading, keys));
    if (!formal) {
      sections.add(('التواريخ', const ['تاريخ الإصدار', 'تاريخ الانتهاء']));
    }
    final clauses = <String>[
      for (final clause in _templateClauses[type] ?? const <String>[])
        if (!clause.startsWith('?'))
          fill(clause)
        else if (complete(clause.substring(1)))
          fill(clause.substring(1)),
    ];
    final intro = _templateIntro[type];
    final signers = <(String, String)>[
      for (final (role, key) in signerSpec)
        if (!role.startsWith('الشاهد')) (role, val(key)),
    ];
    final witnesses = <(String, String)>[
      for (final (role, key) in signerSpec)
        if (role.startsWith('الشاهد')) (role, val(key)),
    ];
    final id = (record.id ?? '').replaceAll('-', '');
    final docNo = (record.docNumber ?? '').isNotEmpty
        ? record.docNumber!
        : id.isEmpty
        ? ''
        : 'FND-${id.substring(0, id.length < 8 ? id.length : 8).toUpperCase()}';
    final input = TemplatePrintInput(
      type: type,
      fields: {
        for (final entry in record.fields.entries)
          entry.key: entry.value.toString(),
      },
      sections: sections,
      tables: _tableFields,
      intro: intro == null ? '' : fill(intro),
      clauses: clauses,
      signers: signers,
      witnesses: witnesses,
      userSigner: type == 'إيصال أمانة' ? 1 : 0,
      withSignature: record.fields['includeSignature'] == '1',
      linked: (record.linkedLabel ?? '').isEmpty
          ? ''
          : '${record.linkedKind}: ${record.linkedLabel}',
      docNo: docNo,
      issued: record.issuedOn,
    );
    if (!mounted) return;
    final fileName = '$type ${val(_primaryOf(type))}'.trim();
    if (shareOnly) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final bytes = await buildTemplatePdf(input, PdfPageFormat.a4);
        await Printing.sharePdf(bytes: bytes, filename: '$fileName.pdf');
      } catch (error) {
        debugPrint('Template PDF failed: $error');
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذّر تجهيز ملف PDF. حاول مرة أخرى.')),
        );
      }
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatePrintScreen(
          title: type,
          fileName: fileName,
          buildPdf: (format) => buildTemplatePdf(input, format),
        ),
      ),
    );
  }

  static final RegExp _slot = RegExp(r'\{([^}]+)\}');

  /// « (رقم الهوية: … · رقم الجواز: …)» للطرف — فارغ إن لم يُكتب أيٌّ منهما.
  static String _idPhrase(String Function(String) val, String party) {
    final parts = [
      if (val('رقم هوية $party').isNotEmpty)
        '${AppTr.tr('رقم الهوية')}: ${val('رقم هوية $party')}',
      if (val('رقم جواز $party').isNotEmpty)
        '${AppTr.tr('رقم الجواز')}: ${val('رقم جواز $party')}',
    ];
    return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
  }

  /// معاينة النموذج المحكم: الإقرار، ثم البيانات تحت أقسامها، ثم البنود
  /// مرقّمة، ثم الملاحظات وخانات التوقيع.
  List<Widget> _formalBody(DocumentRecordEntry record) {
    final type = record.docType;
    String val(String key) => (record.fields[key] ?? '').toString().trim();
    String fill(String template) =>
        AppTr.tr(template).replaceAllMapped(_slot, (match) {
          final key = match.group(1)!;
          if (key.startsWith('@')) return _idPhrase(val, key.substring(1));
          final value = val(key);
          return value.isEmpty ? '..........' : value;
        });
    bool complete(String template) => _slot
        .allMatches(template)
        .every((match) => val(match.group(1)!).isNotEmpty);
    const ink = Color(0xFF1C2C29);
    const deep = Color(0xFF0A5A50);
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: deep,
        ),
      ),
    );
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: TextAlign.justify,
        style: const TextStyle(fontSize: 12, height: 1.65, color: ink),
      ),
    );

    final body = <Widget>[];
    final intro = _templateIntro[type];
    if (intro != null) body.add(paragraph(fill(intro)));

    // البيانات تحت عناوين أقسامها — الفارغ لا يظهر، والنصوص الطويلة
    // في البنود.
    String? heading;
    for (final field in _templateFields[type]!) {
      if (field.startsWith('#')) {
        heading = field.substring(1);
        continue;
      }
      final value = val(field);
      if (value.isEmpty ||
          _multiFields.contains(field) ||
          _tableFields.containsKey(field)) {
        continue;
      }
      if (heading != null) {
        body.add(title(heading));
        heading = null;
      }
      body.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '$field: $value',
            style: const TextStyle(fontSize: 12, height: 1.45, color: ink),
          ),
        ),
      );
    }

    final clauses = <String>[
      for (final clause in _templateClauses[type] ?? const <String>[])
        if (!clause.startsWith('?'))
          clause
        else if (complete(clause.substring(1)))
          clause.substring(1),
    ];
    if (clauses.isNotEmpty) {
      body.add(title('البنود والشروط'));
      for (var i = 0; i < clauses.length; i++) {
        body.add(paragraph('${i + 1}. ${fill(clauses[i])}'));
      }
    }
    if (val('ملاحظات').isNotEmpty) {
      body.add(title('ملاحظات'));
      body.add(paragraph(val('ملاحظات')));
    }
    if ((record.linkedLabel ?? '').isNotEmpty) {
      body.add(
        paragraph('مرتبط بـ: ${record.linkedKind}: ${record.linkedLabel}'),
      );
    }

    final signers = _templateSigners[type] ?? const <(String, String)>[];
    if (signers.isNotEmpty) {
      body.add(const SizedBox(height: 14));
      body.add(
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final (role, key) in signers)
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: deep,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      val(key).isEmpty ? '..........' : val(key),
                      style: const TextStyle(fontSize: 11.5, color: ink),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'التوقيع: ..................',
                      style: TextStyle(fontSize: 11, color: ink),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return body;
  }

  /// «عقد»: اختيار نوع العقد المحكم أولًا.
  Future<void> _pickContractType() async {
    if (!PlanGate.hasFeature(context, PlanFeatures.contracts)) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر نوع العقد',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                for (final type in _contractTypes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _templateIcons[type],
                      color: const Color(0xFF0A5A50),
                    ),
                    title: Text(
                      type,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _contractHints[type] ?? '',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: const AppChevron(),
                    onTap: () => Navigator.pop(sheetContext, type),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _openTemplate(picked);
  }

  Widget _dateField(
    BuildContext context,
    TextEditingController controller,
    String label,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: AppTr.tr(label),
        suffixIcon: const Icon(Icons.event_outlined),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2045),
        );
        if (selected != null) controller.text = _formatDate(selected);
      },
    );
  }

  /// رأس الصفحة: الشعار والعنوان وسطر يوضح ما يُطبع مع النموذج.
  Widget _templatesHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF022E2A), Color(0xFF0E7161)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _logo == null
                ? const Icon(
                    Icons.description_rounded,
                    color: Color(0xFF0E7161),
                    size: 30,
                  )
                : Image.memory(_logo!, fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نماذج جاهزة باسمك',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _logo == null
                      ? 'أضف شعارك من «المزيد» ليظهر أعلى كل نموذج — ومتوفر أيضًا التوقيع والختم'
                      : 'يُطبع كل نموذج بشعارك، ومعه توقيعك وختمك إن اخترت',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// قسم بعنوانه ومربعات نماذجه (مربعان في الصف).
  Widget _templateSection(String title, List<String> types) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 17,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.18,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [for (final type in types) _templateTile(type)],
        ),
      ],
    );
  }

  Widget _templateTile(String type) {
    final color = _templateColors[type] ?? const Color(0xFF0A5A50);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => type == 'عقد'
            ? _pickContractType()
            // سند القبض (راتب أو عام): شاشته الخاصة بالتوقيع والإرسال.
            : type == 'سند قبض'
            ? Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SalaryReceiptsScreen(),
                ),
              )
            : _openTemplate(type),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4EAE8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_templateIcons[type], color: color, size: 21),
                  ),
                  const Spacer(),
                  Icon(
                    AppTr.isRtl
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: const Color(0xFF8C9A97),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                type,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF022E2A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _templateHints[type] ?? '',
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5C6B68),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9F4F1),
      appBar: AppBar(
        title: Text(
          widget.linkedProperty == null
              ? 'نماذج المستندات والإيصالات'
              : 'نماذج ${widget.linkedProperty}',
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: AppTr.uiDir,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _templatesHeader(),
            const SizedBox(height: 18),
            _templateSection('الإيصالات والفواتير', const [
              'سند قبض',
              'إيصال أمانة',
              'إيصال استلام وتسليم',
              'فاتورة',
              'تقرير ضريبي',
            ]),
            const SizedBox(height: 14),
            _templateSection('العقود والإنذارات', const ['عقد', 'إنذار']),
            if (_savedRecords.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                'النماذج المحفوظة',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final record in _savedRecords)
                Card(
                  child: ListTile(
                    leading: Icon(
                      _templateIcons[record.docType] ??
                          Icons.description_outlined,
                    ),
                    title: Text(record.docType),
                    // الضغط يفتح النموذج لإكماله أو تعديله.
                    onTap: _templateFields.containsKey(record.docType)
                        ? () => _openTemplate(record.docType, existing: record)
                        : null,
                    subtitle: Text(
                      [
                        if (record.fields['__draft'] == '1') 'مسودة',
                        (record.fields['تاريخ الانتهاء'] ?? '').isEmpty
                            ? 'بدون تاريخ انتهاء'
                            : 'ينتهي: ${record.fields['تاريخ الانتهاء']}',
                        if ((record.linkedLabel ?? '').isNotEmpty)
                          '${record.linkedKind}: ${record.linkedLabel}',
                      ].join('  •  '),
                      maxLines: 3,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'print') {
                          await _printRecord(record);
                          return;
                        }
                        final danger = action == 'delete';
                        if (action == 'edit') {
                          _openTemplate(record.docType, existing: record);
                          return;
                        }
                        final ok = await confirmAction(
                          context,
                          title: danger ? 'حذف المستند' : 'مشاركة المستند',
                          message: danger
                              ? 'سيُحذف المستند نهائيًا ولا يمكن التراجع. '
                                    'هل تريد الحذف؟'
                              : 'ستُشارك بيانات المستند عبر تطبيق تختاره. '
                                    'هل تريد المتابعة؟',
                          confirmLabel: danger ? 'حذف' : 'تأكيد',
                          danger: danger,
                        );
                        if (!ok || !context.mounted) return;
                        if (action == 'edit') {
                          _openTemplate(record.docType, existing: record);
                        }
                        if (action == 'share') _shareRecord(record);
                        if (action == 'delete') _deleteRecord(record);
                      },
                      itemBuilder: (_) => [
                        if (_templateFields.containsKey(record.docType))
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('فتح / إكمال'),
                          ),
                        if (_templateFields.containsKey(record.docType))
                          const PopupMenuItem(
                            value: 'print',
                            child: Text('طباعة'),
                          ),
                        const PopupMenuItem(value: 'share', child: Text('مشاركة')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
