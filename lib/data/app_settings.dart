import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات التطبيق — مصدر واحد لكل التفضيلات، يقرأه التطبيق فعليًا.
///
/// قبل هذا الملف كانت كل شاشات الإعدادات تكتب مفاتيحها في
/// SharedPreferences ولا يقرأها أحد إطلاقًا: حجم النص، العملة، إخفاء
/// المبالغ، قفل التطبيق، مدة التذكير... كلها مفاتيح "للكتابة فقط"، فيبدو
/// للمستخدم أنه غيّر شيئًا بينما لا يتغير أي سلوك في التطبيق.
///
/// الآن تُحمَّل كل الإعدادات مرة واحدة عند الإقلاع، وتُقرأ من هنا في كل
/// مكان، وأي تعديل يُحفظ ويُبلَّغ به المستمعون فورًا فينعكس على الشاشة
/// مباشرة دون إعادة تشغيل.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  // ===== مفاتيح التخزين =====
  static const _kName = 'settings_profile_name';
  static const _kGivenName = 'settings_profile_given_name';
  static const _kFamilyName = 'settings_profile_family_name';
  static const _kSharedNameMode = 'settings_shared_name_mode';
  static const _kSharedNickname = 'settings_shared_nickname';

  /// الاسم الظاهر للآخرين (في المشاركات والطلبات وعند كتابة الرقم التعريفي).
  static const sharedNameFull = 'الاسم الثلاثي';
  static const sharedNameFirst = 'الاسم الأول';
  static const sharedNameFirstFamily = 'الاسم الأول والقبيلة';
  static const sharedNameNick = 'اسم مستعار';
  static const sharedNameModes = [
    sharedNameFirst,
    sharedNameFull,
    sharedNameFirstFamily,
    sharedNameNick,
  ];
  static const _kPhone = 'settings_profile_phone';
  static const _kEmail = 'settings_profile_email';
  static const _kCity = 'settings_profile_city';
  static const _kBirthday = 'settings_profile_birthday';
  static const _kSocial = 'settings_profile_social';
  static const _kPhoto = 'settings_profile_photo';
  static const _kLanguage = 'settings_language';
  static const _kPlan = 'subscription_plan';
  // مدة الاشتراك: البداية والنهاية (yyyy-mm-dd)، والتجديد التلقائي، والمدة
  // (شهري/سنوي)، وهل هو هدية (الهدية لا تتجدد).
  static const _kPlanStart = 'subscription_plan_start';
  static const _kPlanEnd = 'subscription_plan_end';
  static const _kPlanAutoRenew = 'subscription_plan_auto_renew';
  static const _kPlanYearly = 'subscription_plan_yearly';
  static const _kPlanGift = 'subscription_plan_gift';

  /// الباقة الأساسية التي يعود إليها الحساب عند انتهاء اشتراك لم يُجدَّد.
  static const basePlan = 'silver';
  static const _kCurrency = 'settings_currency';
  static const _kCalendar = 'settings_calendar';
  static const _kTextScale = 'settings_text_scale';
  static const _kCompactLists = 'settings_compact_lists';
  static const _kAppLock = 'settings_app_lock';
  static const _kAppLockPin = 'settings_app_lock_pin';
  static const _kHideAmounts = 'settings_hide_amounts';
  static const _kNotificationsEnabled = 'settings_notifications_enabled';
  static const _kExpiryNotifications = 'settings_expiry_notifications';
  static const _kLeadTimeDays = 'settings_default_lead_time_days';

  static const defaultName = 'عبدالعزيز الهاجري';

  /// إصدار التطبيق كما في pubspec.yaml (version: 1.0.1+2).
  /// يُحدَّث هنا مع كل رفع للإصدار حتى لا تعرض شاشة "حول التطبيق" رقمًا
  /// قديمًا كما كانت تفعل سابقًا.
  static const appVersionName = '1.0.1';
  static const appBuildNumber = '2';
  static const appVersionLabel = 'الإصدار $appVersionName ($appBuildNumber)';
  static const supportEmail = 'support@fundly.app';

  // ===== العملات =====
  // كل عملة: التسمية الكاملة في الإعدادات، واللاحقة القصيرة التي تظهر
  // بجانب كل مبلغ داخل التطبيق.
  static const Map<String, String> currencies = {
    'درهم إماراتي (AED)': 'درهم',
    'ريال سعودي (SAR)': 'ريال',
    'دولار أمريكي (USD)': 'دولار',
    'دينار كويتي (KWD)': 'دينار',
    'ريال قطري (QAR)': 'ريال قطري',
    'دينار بحريني (BHD)': 'دينار بحريني',
    'ريال عماني (OMR)': 'ريال عماني',
    'يورو (EUR)': 'يورو',
    'جنيه مصري (EGP)': 'جنيه مصري',
    'جنيه سوداني (SDG)': 'جنيه سوداني',
    'يوان صيني (CNY)': 'يوان صيني',
    'روبية هندية (INR)': 'روبية هندية',
    'روبية باكستانية (PKR)': 'روبية باكستانية',
  };

  /// لواحق العملات بالترتيب نفسه — خيارات «العملة» في كل نماذج التطبيق
  /// وفي الفلاتر.
  static const List<String> currencySuffixes = [
    'درهم',
    'ريال',
    'دولار',
    'دينار',
    'ريال قطري',
    'دينار بحريني',
    'ريال عماني',
    'يورو',
    'جنيه مصري',
    'جنيه سوداني',
    'يوان صيني',
    'روبية هندية',
    'روبية باكستانية',
  ];

  /// عملة سجل بعينه: ما اختاره له المستخدم، وإلا العملة الافتراضية —
  /// فكل ما لم تُغيَّر عملته وحده يتبع العملة الافتراضية للتطبيق.
  static String currencyOf(String? recordCurrency) {
    final value = (recordCurrency ?? '').trim();
    return value.isEmpty ? currencySuffix : value;
  }

  /// ما يُحفظ في السجل: الفارغ إن كانت العملة هي الافتراضية (فيتبعها
  /// السجل لو تغيّرت لاحقًا)، وإلا العملة المختارة نفسها.
  static String currencyToStore(String? picked) {
    final value = (picked ?? '').trim();
    return value == currencySuffix ? '' : value;
  }

  static const languages = [
    'العربية',
    'English',
    'Français',
    'اردو',
    '中文',
  ];
  static const calendars = ['ميلادي', 'هجري'];

  /// معرّفات الباقات (تفاصيلها في subscription_plans.dart).
  static const plans = ['silver', 'gold', 'premium'];

  /// خيارات وقت التذكير الافتراضي: التسمية ← عدد الأيام.
  static const Map<String, int> leadTimeOptions = {
    'في نفس اليوم': 0,
    'قبل يوم': 1,
    'قبل 3 أيام': 3,
    'قبل أسبوع': 7,
    'قبل شهر': 30,
  };

  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.30;

  // ===== الحالة =====
  bool _loaded = false;
  bool get isLoaded => _loaded;

  String _name = defaultName;
  String _phone = '';
  String _email = '';
  String _city = '';
  String _birthday = '';
  String _social = '';
  Uint8List? _photo;
  String _language = 'العربية';
  String _currency = 'درهم إماراتي (AED)';
  String _calendar = 'ميلادي';
  double _textScale = 1.0;
  bool _compactLists = false;
  bool _appLock = false;
  String _appLockPin = '';
  bool _hideAmounts = false;
  bool _notificationsEnabled = true;
  bool _expiryNotifications = true;
  int _leadTimeDays = 7;

  String get name => _name.trim().isEmpty ? defaultName : _name.trim();

  /// الاسم كما كتبه (قد يكون ثلاثيًا) والقبيلة/العائلة — لحقول التعديل.
  /// الاسم الظاهر في كل التطبيق هو [name] المركّب منهما.
  String _givenName = '';
  String _familyName = '';

  String get givenName {
    if (_givenName.trim().isNotEmpty) return _givenName.trim();
    // حساب قديم بلا حقلين: كل ما قبل آخر كلمة اسم، وآخر كلمة العائلة.
    final parts = _nameParts(_name);
    return parts.length >= 2
        ? parts.sublist(0, parts.length - 1).join(' ')
        : parts.join(' ');
  }

  String get familyName {
    if (_givenName.trim().isNotEmpty) return _familyName.trim();
    final parts = _nameParts(_name);
    return parts.length >= 2 ? parts.last : '';
  }

  static List<String> _nameParts(String value) => value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();

  /// الاسم الظاهر: ثلاثي إن أمكن (الاسم الأول واسم الأب والقبيلة)، وإلا
  /// ثنائي. الرباعي فأكثر يُقصّ إلى ثلاثي.
  static String composeName(String given, String family) {
    final parts = _nameParts(given);
    final tribe = family.trim();
    if (tribe.isEmpty) return parts.take(3).join(' ');
    return [...parts.take(2), tribe].join(' ');
  }

  /// الاسم مطلوب، والقبيلة/العائلة اختيارية.
  static bool isValidNameParts(String given, String family) =>
      given.trim().length >= 2;

  String _sharedNameMode = sharedNameFull;
  String _sharedNickname = '';

  String get sharedNameMode => _sharedNameMode;
  String get sharedNickname => _sharedNickname;

  /// ما يراه الآخرون حسب الاختيار — اسمي الكامل يبقى عندي فقط.
  static String publicNameFor({
    required String mode,
    required String fullName,
    required String given,
    required String nickname,
    String family = '',
  }) {
    final parts = _nameParts(given.trim().isEmpty ? fullName : given);
    final first = parts.isEmpty ? fullName : parts.first;
    if (mode == sharedNameFirst) return first;
    if (mode == sharedNameFirstFamily) {
      return [first, family.trim()].where((p) => p.isNotEmpty).join(' ');
    }
    if (mode == sharedNameNick && nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    return fullName;
  }

  String get publicName => publicNameFor(
    mode: _sharedNameMode,
    fullName: name,
    given: givenName,
    nickname: _sharedNickname,
    family: familyName,
  );

  /// اسمي كما يُكتب في السجلات: الكامل أو الظاهر للآخرين.
  bool isMyName(String value) {
    final v = value.trim();
    return v.isNotEmpty && (v == name || v == publicName);
  }

  Future<void> setSharedName(String mode, String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    _sharedNameMode = sharedNameModes.contains(mode) ? mode : sharedNameFull;
    _sharedNickname = nickname.trim();
    await prefs.setString(_kSharedNameMode, _sharedNameMode);
    await prefs.setString(_kSharedNickname, _sharedNickname);
    notifyListeners();
  }

  Future<void> setNameParts(String given, String family) async {
    final prefs = await SharedPreferences.getInstance();
    _givenName = given.trim();
    _familyName = family.trim();
    await prefs.setString(_kGivenName, _givenName);
    await prefs.setString(_kFamilyName, _familyName);
  }
  String get phone => _phone;
  String get email => _email;
  String get city => _city;

  /// تاريخ ميلاد المستخدم بصيغة يوم/شهر/سنة — يُستعمل لتنبيه الميلاد.
  String get birthday => _birthday;

  /// عدد الأيام المتبقية للميلاد القادم، أو null إن لم يُسجَّل التاريخ.
  int? get daysToBirthday {
    final parts = _birthday.split('/');
    if (parts.length < 2) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (day == null || month == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(now.year, month, day);
    if (next.isBefore(today)) next = DateTime(now.year + 1, month, day);
    return next.difference(today).inDays;
  }

  Future<void> setBirthday(String value) async {
    final prefs = await SharedPreferences.getInstance();
    _birthday = value.trim();
    await prefs.setString(_kBirthday, _birthday);
    notifyListeners();
  }
  String get social => _social;
  Uint8List? get photo => _photo;
  String get language => _language;

  String _plan = 'silver';
  String _planStart = '';
  String _planEnd = '';
  bool _planAutoRenew = false;
  bool _planYearly = false;
  bool _planGift = false;

  /// الباقة الحالية: silver / gold / premium.
  String get plan => _plan;

  /// بداية الاشتراك الحالي ونهايته بصيغة يوم/شهر/سنة (فارغة بلا اشتراك).
  String get planStartLabel => _isoToLabel(_planStart);
  String get planEndLabel => _isoToLabel(_planEnd);
  bool get hasPlanPeriod => _planEnd.isNotEmpty;
  bool get planAutoRenew => _planAutoRenew;
  bool get planYearly => _planYearly;
  bool get planIsGift => _planGift;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _fromIso(String value) => DateTime.tryParse(value);

  static String _isoToLabel(String value) {
    final d = _fromIso(value);
    return d == null ? '' : '${d.day}/${d.month}/${d.year}';
  }

  /// شهر أو سنة بعد [from]، مع تثبيت آخر الشهر (31/1 ← 28 أو 29/2).
  static DateTime _addPeriod(DateTime from, bool yearly) {
    final months = yearly ? 12 : 1;
    final target = DateTime(from.year, from.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      from.day > lastDay ? lastDay : from.day,
    );
  }

  /// بدء اشتراك (أو تفعيل هدية) من اليوم: يسري فورًا ولمدة شهر أو سنة.
  /// المدفوع يتجدد تلقائيًا حتى يُلغى، والهدية تنتهي بنهاية مدتها.
  Future<void> startPlan(
    String value, {
    required bool yearly,
    bool gift = false,
  }) async {
    if (!plans.contains(value)) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _plan = value;
    _planStart = _iso(today);
    _planEnd = _iso(_addPeriod(today, yearly));
    _planAutoRenew = !gift;
    _planYearly = yearly;
    _planGift = gift;
    await prefs.setString(_kPlan, _plan);
    await prefs.setString(_kPlanStart, _planStart);
    await prefs.setString(_kPlanEnd, _planEnd);
    await prefs.setBool(_kPlanAutoRenew, _planAutoRenew);
    await prefs.setBool(_kPlanYearly, _planYearly);
    await prefs.setBool(_kPlanGift, _planGift);
    notifyListeners();
  }

  /// إلغاء التجديد التلقائي أو إعادته: الاشتراك يبقى فعّالًا حتى نهاية
  /// مدته المدفوعة ولا يُلغى فورًا.
  Future<void> setPlanAutoRenew(bool value) async {
    if (_planGift || _planEnd.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _planAutoRenew = value;
    await prefs.setBool(_kPlanAutoRenew, value);
    notifyListeners();
  }

  /// عند فتح التطبيق: اشتراك انتهت مدته يُجدَّد إن كان التجديد مفعّلًا،
  /// وإلا (ومنه الهدية) يعود الحساب إلى الباقة الأساسية.
  Future<void> _applyPlanExpiry(SharedPreferences prefs) async {
    final end = _fromIso(_planEnd);
    if (end == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!today.isAfter(end)) return;
    if (_planAutoRenew && !_planGift) {
      var start = end;
      var next = _addPeriod(end, _planYearly);
      while (!next.isAfter(today)) {
        start = next;
        next = _addPeriod(next, _planYearly);
      }
      _planStart = _iso(start);
      _planEnd = _iso(next);
      await prefs.setString(_kPlanStart, _planStart);
      await prefs.setString(_kPlanEnd, _planEnd);
      return;
    }
    _plan = basePlan;
    _planStart = '';
    _planEnd = '';
    _planAutoRenew = false;
    _planGift = false;
    await prefs.setString(_kPlan, _plan);
    for (final key in [_kPlanStart, _kPlanEnd]) {
      await prefs.remove(key);
    }
    await prefs.setBool(_kPlanAutoRenew, false);
    await prefs.setBool(_kPlanGift, false);
  }
  String get currency => _currency;
  String get calendar => _calendar;
  bool get useHijri => _calendar == 'هجري';
  double get textScale => _textScale;
  bool get compactLists => _compactLists;
  bool get appLock => _appLock;
  bool get hasPin => _appLockPin.length >= 4;
  bool get hideAmounts => _hideAmounts;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get expiryNotifications => _expiryNotifications;
  int get leadTimeDays => _leadTimeDays;

  String get leadTimeLabel => leadTimeOptions.entries
      .firstWhere(
        (e) => e.value == _leadTimeDays,
        orElse: () => const MapEntry('قبل أسبوع', 7),
      )
      .key;

  /// اللاحقة النقدية المستعملة بجانب كل مبلغ في التطبيق.
  ///
  /// تُقرأ ثابتةً (static) لأن آلاف المواضع تعرض المبالغ داخل نصوص
  /// مُدمَجة، وتمرير كائن الإعدادات إليها جميعًا غير عملي.
  static String get currencySuffix => currencies[instance._currency] ?? 'درهم';

  /// المبالغ الحساسة تُخفى عند تفعيل "إخفاء المبالغ".
  static String maskAmount(String formatted) =>
      instance._hideAmounts ? '••••' : formatted;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_kName) ?? defaultName;
    _givenName = prefs.getString(_kGivenName) ?? '';
    _familyName = prefs.getString(_kFamilyName) ?? '';
    final storedMode = prefs.getString(_kSharedNameMode);
    _sharedNameMode = _oneOf(
      // اسم الخيار قبل تعديله.
      storedMode == 'الاسم الأول فقط' ? sharedNameFirst : storedMode,
      sharedNameModes,
      sharedNameFull,
    );
    _sharedNickname = prefs.getString(_kSharedNickname) ?? '';
    _phone = prefs.getString(_kPhone) ?? '';
    _email = prefs.getString(_kEmail) ?? '';
    _city = prefs.getString(_kCity) ?? '';
    _birthday = prefs.getString(_kBirthday) ?? '';
    _social = prefs.getString(_kSocial) ?? '';
    final photo = prefs.getString(_kPhoto);
    _photo = null;
    if (photo != null && photo.isNotEmpty) {
      try {
        _photo = base64Decode(photo);
      } catch (_) {
        _photo = null;
      }
    }
    _language = _oneOf(prefs.getString(_kLanguage), languages, 'العربية');
    _plan = _oneOf(prefs.getString(_kPlan), plans, 'silver');
    _planStart = prefs.getString(_kPlanStart) ?? '';
    _planEnd = prefs.getString(_kPlanEnd) ?? '';
    _planAutoRenew = prefs.getBool(_kPlanAutoRenew) ?? false;
    _planYearly = prefs.getBool(_kPlanYearly) ?? false;
    _planGift = prefs.getBool(_kPlanGift) ?? false;
    await _applyPlanExpiry(prefs);
    _currency = currencies.containsKey(prefs.getString(_kCurrency))
        ? prefs.getString(_kCurrency)!
        : 'درهم إماراتي (AED)';
    _calendar = _oneOf(prefs.getString(_kCalendar), calendars, 'ميلادي');
    _textScale = (prefs.getDouble(_kTextScale) ?? 1.0).clamp(
      minTextScale,
      maxTextScale,
    );
    _compactLists = prefs.getBool(_kCompactLists) ?? false;
    _appLockPin = prefs.getString(_kAppLockPin) ?? '';
    // قفل بلا رمز محفوظ يعني قفلًا لا يمكن فتحه — يُعطَّل بدل أن يحبس
    // المستخدم خارج تطبيقه.
    _appLock = (prefs.getBool(_kAppLock) ?? false) && _appLockPin.length >= 4;
    _hideAmounts = prefs.getBool(_kHideAmounts) ?? false;
    _notificationsEnabled = prefs.getBool(_kNotificationsEnabled) ?? true;
    _expiryNotifications = prefs.getBool(_kExpiryNotifications) ?? true;
    // قيمة خارج الخيارات المتاحة تُسقط قائمة الاختيار بتأكيد
    // (DropdownButton يشترط تطابق القيمة مع أحد عناصره).
    final storedLead = prefs.getInt(_kLeadTimeDays);
    _leadTimeDays = leadTimeOptions.containsValue(storedLead)
        ? storedLead!
        : _migratedLeadTime(prefs);
    _loaded = true;
    notifyListeners();
  }

  /// النسخة السابقة كانت تحفظ وقت التذكير كنص ("قبل أسبوع")؛ يُحوَّل مرة
  /// واحدة إلى عدد أيام حتى لا يفقد المستخدم اختياره القديم.
  int _migratedLeadTime(SharedPreferences prefs) {
    final legacy = prefs.getString('settings_default_lead_time');
    return leadTimeOptions[legacy] ?? 7;
  }

  /// اسم المستخدم من اسمين على الأقل: الاسم الأول واسم العائلة.
  static bool isFullName(String name) =>
      name
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.trim().length >= 2)
          .length >=
      2;

  static String _oneOf(String? value, List<String> allowed, String fallback) =>
      value != null && allowed.contains(value) ? value : fallback;

  Future<void> saveProfile({
    required String name,
    required String phone,
    required String email,
    required String city,
    required String social,
    required Uint8List? photo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _name = name.trim();
    _phone = phone.trim();
    _email = email.trim();
    _city = city.trim();
    _social = social.trim();
    _photo = photo;
    await prefs.setString(_kName, _name);
    await prefs.setString(_kPhone, _phone);
    await prefs.setString(_kEmail, _email);
    await prefs.setString(_kCity, _city);
    await prefs.setString(_kSocial, _social);
    if (photo == null) {
      await prefs.remove(_kPhoto);
    } else {
      await prefs.setString(_kPhoto, base64Encode(photo));
    }
    notifyListeners();
  }

  Future<void> setLanguage(String value) =>
      _setString(_kLanguage, value, (v) => _language = v, languages);

  Future<void> setPlan(String value) =>
      _setString(_kPlan, value, (v) => _plan = v, plans);

  Future<void> setCurrency(String value) async {
    if (!currencies.containsKey(value)) return;
    final prefs = await SharedPreferences.getInstance();
    _currency = value;
    await prefs.setString(_kCurrency, value);
    notifyListeners();
  }

  Future<void> setCalendar(String value) =>
      _setString(_kCalendar, value, (v) => _calendar = v, calendars);

  Future<void> setTextScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    _textScale = value.clamp(minTextScale, maxTextScale);
    await prefs.setDouble(_kTextScale, _textScale);
    notifyListeners();
  }

  Future<void> setCompactLists(bool value) =>
      _setBool(_kCompactLists, value, (v) => _compactLists = v);

  Future<void> setHideAmounts(bool value) =>
      _setBool(_kHideAmounts, value, (v) => _hideAmounts = v);

  Future<void> setNotificationsEnabled(bool value) =>
      _setBool(_kNotificationsEnabled, value, (v) => _notificationsEnabled = v);

  Future<void> setExpiryNotifications(bool value) =>
      _setBool(_kExpiryNotifications, value, (v) => _expiryNotifications = v);

  Future<void> setLeadTimeDays(int value) async {
    if (!leadTimeOptions.containsValue(value)) return;
    final prefs = await SharedPreferences.getInstance();
    _leadTimeDays = value;
    await prefs.setInt(_kLeadTimeDays, value);
    notifyListeners();
  }

  /// تفعيل القفل يتطلّب رمزًا من أربعة أرقام — لا يُفعَّل قفل بلا مفتاح.
  Future<bool> enableAppLock(String pin) async {
    final digits = pin.trim();
    if (digits.length != 4 || int.tryParse(digits) == null) return false;
    final prefs = await SharedPreferences.getInstance();
    _appLockPin = digits;
    _appLock = true;
    await prefs.setString(_kAppLockPin, digits);
    await prefs.setBool(_kAppLock, true);
    notifyListeners();
    return true;
  }

  /// إيقاف القفل يتطلّب الرمز الحالي، وإلا لصار القفل بلا قيمة.
  Future<bool> disableAppLock(String pin) async {
    if (!verifyPin(pin)) return false;
    final prefs = await SharedPreferences.getInstance();
    _appLock = false;
    _appLockPin = '';
    await prefs.setBool(_kAppLock, false);
    await prefs.remove(_kAppLockPin);
    notifyListeners();
    return true;
  }

  bool verifyPin(String pin) =>
      _appLockPin.isNotEmpty && pin.trim() == _appLockPin;

  Future<void> _setBool(
    String key,
    bool value,
    void Function(bool) assign,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    assign(value);
    await prefs.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setString(
    String key,
    String value,
    void Function(String) assign,
    List<String> allowed,
  ) async {
    if (!allowed.contains(value)) return;
    final prefs = await SharedPreferences.getInstance();
    assign(value);
    await prefs.setString(key, value);
    notifyListeners();
  }
}
