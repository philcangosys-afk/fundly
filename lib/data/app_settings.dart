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
  static const _kPhone = 'settings_profile_phone';
  static const _kEmail = 'settings_profile_email';
  static const _kCity = 'settings_profile_city';
  static const _kSocial = 'settings_profile_social';
  static const _kPhoto = 'settings_profile_photo';
  static const _kLanguage = 'settings_language';
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
  };

  static const languages = ['العربية', 'English'];
  static const calendars = ['ميلادي', 'هجري'];

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
  String get phone => _phone;
  String get email => _email;
  String get city => _city;
  String get social => _social;
  Uint8List? get photo => _photo;
  String get language => _language;
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
    _phone = prefs.getString(_kPhone) ?? '';
    _email = prefs.getString(_kEmail) ?? '';
    _city = prefs.getString(_kCity) ?? '';
    _social = prefs.getString(_kSocial) ?? '';
    final photo = prefs.getString(_kPhoto);
    if (photo != null && photo.isNotEmpty) {
      try {
        _photo = base64Decode(photo);
      } catch (_) {
        _photo = null;
      }
    }
    _language = _oneOf(prefs.getString(_kLanguage), languages, 'العربية');
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
