import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_settings.dart';
import '../widgets/shared/app_design.dart';
import 'data_status_screen.dart';
import 'notifications_center_screen.dart';

/// شاشات الإعدادات.
///
/// كانت كل شاشة هنا تكتب مفاتيحها في SharedPreferences ولا يقرأها أحد في
/// التطبيق: حجم النص والعملة والتقويم وإخفاء المبالغ وقفل التطبيق ومدة
/// التذكير — كلها أزرار تتحرك بلا أثر. الآن تمرّ كلها عبر [AppSettings]
/// الذي يقرأه التطبيق فعليًا، فينعكس أي تغيير فورًا على الواجهة.

// ===========================================================================
// البيانات الشخصية
// ===========================================================================

class ProfileDataSettingsPage extends StatefulWidget {
  const ProfileDataSettingsPage({super.key});

  @override
  State<ProfileDataSettingsPage> createState() =>
      _ProfileDataSettingsPageState();
}

class _ProfileDataSettingsPageState extends State<ProfileDataSettingsPage> {
  final _settings = AppSettings.instance;

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _social;
  late String _language;
  Uint8List? _photoBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // الإعدادات محمّلة مسبقًا عند إقلاع التطبيق، فتُملأ الحقول مباشرة بلا
    // ومضة قيم افتراضية تُستبدل بعد لحظة.
    _name = TextEditingController(text: _settings.name);
    _phone = TextEditingController(text: _settings.phone);
    _email = TextEditingController(text: _settings.email);
    _city = TextEditingController(text: _settings.city);
    _social = TextEditingController(text: _settings.social);
    _language = _settings.language;
    _photoBytes = _settings.photo;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 900,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الصور على هذا الجهاز')),
      );
    }
  }

  void _openPhotoPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تغيير الصورة الشخصية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('التقاط صورة'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('اختيار من الصور'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                if (_photoBytes != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    title: const Text('حذف الصورة'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() => _photoBytes = null);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    // الاسم يظهر في ترويسة الصفحة الرئيسية، فاسم فارغ يترك الترويسة خالية.
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل الاسم أولًا')));
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صيغة البريد الإلكتروني غير صحيحة')),
      );
      return;
    }
    setState(() => _saving = true);
    await _settings.saveProfile(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      city: _city.text,
      social: _social.text,
      photo: _photoBytes,
    );
    await _settings.setLanguage(_language);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ البيانات الشخصية')),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _social.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 142,
                    height: 142,
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surface,
                    ),
                    child: ClipOval(
                      child: _photoBytes == null
                          ? const ColoredBox(
                              color: AppTheme.field,
                              child: Icon(
                                Icons.person_outline_rounded,
                                size: 82,
                                color: AppTheme.chevron,
                              ),
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  PositionedDirectional(
                    end: -2,
                    bottom: 7,
                    child: Material(
                      color: AppTheme.accent,
                      shape: const CircleBorder(),
                      elevation: 0,
                      child: IconButton(
                        key: const ValueKey('profile-photo-picker'),
                        tooltip: 'تغيير الصورة الشخصية',
                        onPressed: _openPhotoPicker,
                        icon: const Icon(
                          Icons.photo_camera_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _ProfileEditField(
              controller: _name,
              label: 'الاسم بالكامل',
              hint: 'أدخل الاسم الكامل',
            ),
            _ProfileEditField(
              controller: _email,
              label: 'البريد الإلكتروني',
              hint: 'username@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
            _ProfileEditField(
              controller: _phone,
              label: 'رقم الهاتف',
              hint: 'أدخل رقم الهاتف',
              keyboardType: TextInputType.phone,
            ),
            _ProfileEditField(
              controller: _city,
              label: 'المدينة',
              hint: 'أدخل المدينة',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 10, bottom: 7),
                    child: Text(
                      'اللغة',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.body,
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('profile-language'),
                    // نفس لغة صفحة "اللغة والعملة" — كانت الصفحتان تحفظان
                    // اللغة في مفتاحين مختلفين فتتناقضان.
                    initialValue: _language,
                    decoration: _profileInputDecoration(
                      hint: 'اختر اللغة',
                      icon: Icons.language_rounded,
                    ),
                    items: AppSettings.languages
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _language = value);
                    },
                  ),
                ],
              ),
            ),
            _ProfileEditField(
              controller: _social,
              label: 'حسابات السوشيال ميديا',
              hint: 'أضف اسم المستخدم أو رابط الحساب',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                key: const ValueKey('save-profile-data'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileEditField extends StatelessWidget {
  const _ProfileEditField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.icon = Icons.edit_outlined,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, bottom: 7),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.body,
              ),
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: _profileInputDecoration(hint: hint, icon: icon),
          ),
        ],
      ),
    );
  }
}

InputDecoration _profileInputDecoration({
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
    filled: true,
    fillColor: AppTheme.field,
    suffixIcon: Icon(icon, size: 19, color: AppTheme.chevron),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
    ),
  );
}

// ===========================================================================
// التنبيهات والتذكير
// ===========================================================================

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => SettingsDetailPage(
        title: 'التنبيهات والتذكير',
        children: [
          SwitchListTile(
            key: const ValueKey('settings-notifications-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('تفعيل التنبيهات داخل التطبيق'),
            subtitle: const Text(
              'عند الإيقاف يتوقف مركز التنبيهات وشارة الجرس عن العرض',
            ),
            value: _settings.notificationsEnabled,
            onChanged: _settings.setNotificationsEnabled,
          ),
          SwitchListTile(
            key: const ValueKey('settings-expiry-notifications'),
            contentPadding: EdgeInsets.zero,
            title: const Text('تنبيهات انتهاء المستندات والعقود'),
            subtitle: const Text(
              'تنبيهات انتهاء الإقامات والرخص والعقود والتأمين',
            ),
            value: _settings.expiryNotifications,
            // لا معنى لتفعيل نوع تنبيه بينما التنبيهات كلها موقوفة.
            onChanged: _settings.notificationsEnabled
                ? _settings.setExpiryNotifications
                : null,
          ),
          DropdownButtonFormField<int>(
            key: const ValueKey('settings-lead-time'),
            initialValue: _settings.leadTimeDays,
            decoration: const InputDecoration(
              labelText: 'وقت التذكير الافتراضي',
              helperText:
                  'يُستخدم للعناصر التي لم تُحدَّد لها مدة تذكير خاصة بها',
              border: OutlineInputBorder(),
            ),
            items: AppSettings.leadTimeOptions.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.value,
                    child: Text(entry.key),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _settings.setLeadTimeDays(value);
            },
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsCenterScreen(),
              ),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('فتح مركز التنبيهات الآن'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// اللغة والعملة والتقويم
// ===========================================================================

class LanguageCurrencySettingsPage extends StatefulWidget {
  const LanguageCurrencySettingsPage({super.key});

  @override
  State<LanguageCurrencySettingsPage> createState() =>
      _LanguageCurrencySettingsPageState();
}

class _LanguageCurrencySettingsPageState
    extends State<LanguageCurrencySettingsPage> {
  final _settings = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => SettingsDetailPage(
        title: 'اللغة والعملة',
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('settings-language'),
            initialValue: _settings.language,
            decoration: const InputDecoration(
              labelText: 'لغة التطبيق',
              border: OutlineInputBorder(),
            ),
            items: AppSettings.languages
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _settings.setLanguage(value);
            },
          ),
          if (_settings.language != 'العربية')
            const SettingsNotice(
              text:
                  'واجهة التطبيق مكتوبة بالعربية حاليًا؛ الترجمة الإنجليزية قيد الإعداد.',
            ),
          DropdownButtonFormField<String>(
            key: const ValueKey('settings-currency'),
            initialValue: _settings.currency,
            decoration: const InputDecoration(
              labelText: 'العملة الافتراضية',
              helperText: 'تظهر بجانب كل مبلغ في التطبيق',
              border: OutlineInputBorder(),
            ),
            items: AppSettings.currencies.keys
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _settings.setCurrency(value);
            },
          ),
          Container(
            padding: const EdgeInsets.all(AppTheme.sLg),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              children: [
                const Text(
                  'معاينة المبلغ:',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 8),
                Text(
                  '1,250 ${AppSettings.currencySuffix}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
              ],
            ),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('settings-calendar'),
            initialValue: _settings.calendar,
            decoration: const InputDecoration(
              labelText: 'نوع التقويم الافتراضي',
              border: OutlineInputBorder(),
            ),
            items: AppSettings.calendars
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _settings.setCalendar(value);
            },
          ),
          if (_settings.useHijri)
            const SettingsNotice(
              text:
                  'التواريخ المدخلة والمخزّنة تبقى ميلادية؛ التقويم الهجري خيار عرض سيُطبَّق تدريجيًا على الشاشات.',
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// المظهر — حجم النص وكثافة القوائم
// ===========================================================================

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  final _settings = AppSettings.instance;
  late double _draft = _settings.textScale;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => SettingsDetailPage(
        title: 'المظهر',
        children: [
          const Text(
            'حجم النص',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Slider(
            key: const ValueKey('settings-text-scale'),
            value: _draft,
            min: AppSettings.minTextScale,
            max: AppSettings.maxTextScale,
            divisions: 9,
            label: '${(_draft * 100).round()}%',
            // التغيير يُطبَّق مباشرةً على التطبيق كله أثناء السحب، فيرى
            // المستخدم الحجم الحقيقي قبل أن يترك المؤشر.
            onChanged: (value) {
              setState(() => _draft = value);
              _settings.setTextScale(value);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الحجم الحالي: ${(_draft * 100).round()}%'),
              TextButton(
                onPressed: () {
                  setState(() => _draft = 1.0);
                  _settings.setTextScale(1.0);
                },
                child: const Text('إعادة الحجم الافتراضي'),
              ),
            ],
          ),
          const Text(
            'هذا نص تجريبي لمعاينة حجم الخط في التطبيق.',
            style: AppTheme.bodyText,
          ),
          SwitchListTile(
            key: const ValueKey('settings-compact-lists'),
            contentPadding: EdgeInsets.zero,
            title: const Text('عرض القوائم بشكل مضغوط'),
            subtitle: const Text('تقليل المسافات في قوائم الإعدادات'),
            value: _settings.compactLists,
            onChanged: _settings.setCompactLists,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// الأمان والخصوصية
// ===========================================================================

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final _settings = AppSettings.instance;

  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      final pin = await _askPin(
        title: 'تعيين رمز القفل',
        message: 'اختر رمزًا من أربعة أرقام يُطلب عند فتح التطبيق.',
        confirm: true,
      );
      if (pin == null) return;
      final ok = await _settings.enableAppLock(pin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'تم تفعيل قفل التطبيق' : 'تعذّر تفعيل القفل'),
        ),
      );
      return;
    }
    final pin = await _askPin(
      title: 'إيقاف قفل التطبيق',
      message: 'أدخل الرمز الحالي لإيقاف القفل.',
      confirm: false,
    );
    if (pin == null) return;
    final ok = await _settings.disableAppLock(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'تم إيقاف القفل' : 'الرمز غير صحيح')),
    );
  }

  /// حوار إدخال الرمز. يُعيد الرمز عند التأكيد، أو null عند الإلغاء أو
  /// عدم تطابق التأكيد.
  Future<String?> _askPin({
    required String title,
    required String message,
    required bool confirm,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'الرمز',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: second,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'تأكيد الرمز',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final value = first.text.trim();
                  if (value.length != 4) {
                    setDialogState(() => error = 'الرمز أربعة أرقام');
                    return;
                  }
                  if (confirm && second.text.trim() != value) {
                    setDialogState(() => error = 'الرمزان غير متطابقين');
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => SettingsDetailPage(
        title: 'الأمان والخصوصية',
        children: [
          SwitchListTile(
            key: const ValueKey('settings-app-lock'),
            contentPadding: EdgeInsets.zero,
            title: const Text('قفل التطبيق'),
            subtitle: const Text('طلب رمز من أربعة أرقام عند فتح التطبيق'),
            value: _settings.appLock,
            onChanged: _toggleAppLock,
          ),
          if (_settings.appLock)
            OutlinedButton.icon(
              onPressed: () async {
                final current = await _askPin(
                  title: 'تغيير الرمز',
                  message: 'أدخل الرمز الحالي.',
                  confirm: false,
                );
                // الإلغاء ليس رمزًا خاطئًا — كان يُظهر رسالة خطأ للمستخدم
                // الذي تراجع فحسب.
                if (current == null) return;
                if (!_settings.verifyPin(current)) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرمز الحالي غير صحيح')),
                  );
                  return;
                }
                if (!mounted) return;
                final next = await _askPin(
                  title: 'الرمز الجديد',
                  message: 'اختر رمزًا جديدًا من أربعة أرقام.',
                  confirm: true,
                );
                if (next == null) return;
                await _settings.enableAppLock(next);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تغيير الرمز')),
                );
              },
              icon: const Icon(Icons.password_rounded),
              label: const Text('تغيير رمز القفل'),
            ),
          SwitchListTile(
            key: const ValueKey('settings-hide-amounts'),
            contentPadding: EdgeInsets.zero,
            title: const Text('إخفاء المبالغ الحساسة'),
            subtitle: const Text('استبدال مبالغ الملخص في الرئيسية بـ ••••'),
            value: _settings.hideAmounts,
            onChanged: _settings.setHideAmounts,
          ),
          const SettingsNotice(
            text:
                'الرمز محفوظ على هذا الجهاز فقط ولا يُرفع إلى الخادم. بياناتك المخزّنة في قاعدة البيانات محمية بصلاحيات مرتبطة بحسابك.',
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// حول التطبيق / الخصوصية / التواصل
// ===========================================================================

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsDetailPage(
      title: 'حول التطبيق',
      children: [
        Icon(
          Icons.account_balance_wallet_rounded,
          size: 54,
          color: Color(0xFF087F6A),
        ),
        Text(
          'Fundly',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        Text(
          // يُقرأ من ثابت واحد يُحدَّث مع pubspec، بدل رقم مكتوب يدويًا
          // في الشاشة كان قد تقادم.
          AppSettings.appVersionLabel,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SettingsNotice(
          text:
              'تطبيق عربي لإدارة الأموال والأصول والالتزامات والعلاقات في مكان واحد.',
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const _sections = <(String, String)>[
    (
      'ما الذي يُخزَّن؟',
      'الالتزامات والأشخاص والعقارات والأنشطة والمحافظ والمستندات التي تدخلها بنفسك، إضافة إلى تفضيلاتك داخل التطبيق.',
    ),
    (
      'أين يُخزَّن؟',
      'البيانات الأساسية تُحفظ في قاعدة بيانات Supabase الخاصة بالتطبيق ومقيّدة بحسابك، ولا يصل إليها حساب آخر. التفضيلات وصورة الملف الشخصي ورمز القفل تبقى على جهازك فقط.',
    ),
    (
      'المشاركة',
      'لا تُشارَك بياناتك مع أي طرف ثالث ولا تُستخدم في الإعلانات. ما تشاركه أنت عبر زر المشاركة يخرج بإرادتك ووسيلتك أنت.',
    ),
    (
      'الأذونات',
      'الكاميرا والصور تُستخدمان لاختيار صورة الملف الشخصي ومرفقات المستندات فقط. الاتصال بالإنترنت يُستخدم لمزامنة بياناتك مع قاعدة البيانات.',
    ),
    (
      'حذف بياناتك',
      'يمكنك حذف أي سجل من داخل شاشته. لحذف الحساب وكل بياناته دفعةً واحدة راسلنا من صفحة "تواصل معنا".',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'سياسة الخصوصية',
      children: [
        for (final section in _sections)
          Container(
            padding: const EdgeInsets.all(AppTheme.sLg),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.$1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.$2,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  Future<void> _launch(BuildContext context, Uri uri, String fallback) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    // بلا هذا الفرع كان الزر يبدو ناجحًا دائمًا حتى حين لا يوجد تطبيق
    // بريد على الجهاز؛ الآن يُنسخ العنوان ليبقى في يد المستخدم.
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: fallback));
      messenger.showSnackBar(
        SnackBar(content: Text('تعذّر فتح التطبيق. نُسخ: $fallback')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const email = AppSettings.supportEmail;
    return SettingsDetailPage(
      title: 'تواصل معنا',
      children: [
        const SettingsNotice(
          text:
              'لأي ملاحظة أو مشكلة أو اقتراح، راسلنا وسنرد في أقرب وقت. أرفق وصفًا لما حدث ورقم الإصدار يساعدنا كثيرًا.',
        ),
        ListTile(
          tileColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.sLg,
            vertical: AppTheme.sXs,
          ),
          leading: const Icon(Icons.mail_outline_rounded),
          title: const Text('مراسلة الدعم بالبريد'),
          subtitle: const Text(email),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _launch(
            context,
            Uri(
              scheme: 'mailto',
              path: email,
              query:
                  'subject=${Uri.encodeComponent('دعم Fundly — ${AppSettings.appVersionLabel}')}',
            ),
            email,
          ),
        ),
        ListTile(
          tileColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.sLg,
            vertical: AppTheme.sXs,
          ),
          leading: const Icon(Icons.copy_all_rounded),
          title: const Text('نسخ بريد الدعم'),
          subtitle: const Text('لصقه في أي تطبيق مراسلة'),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(const ClipboardData(text: email));
            messenger.showSnackBar(
              const SnackBar(content: Text('تم نسخ بريد الدعم')),
            );
          },
        ),
        ListTile(
          tileColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.sLg,
            vertical: AppTheme.sXs,
          ),
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('معلومات تفيد الدعم'),
          subtitle: Text('Fundly · ${AppSettings.appVersionLabel}'),
          trailing: const Icon(Icons.copy_rounded, size: 18),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(
              const ClipboardData(
                text: 'Fundly · ${AppSettings.appVersionLabel}',
              ),
            );
            messenger.showSnackBar(
              const SnackBar(content: Text('تم نسخ معلومات الإصدار')),
            );
          },
        ),
      ],
    );
  }
}

// ===========================================================================
// عناصر مشتركة
// ===========================================================================

class SettingsDetailPage extends StatelessWidget {
  const SettingsDetailPage({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: Text(title, style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, index) => children[index],
        ),
      ),
    );
  }
}

class SettingsNotice extends StatelessWidget {
  const SettingsNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.6,
          fontWeight: FontWeight.w600,
          color: AppTheme.accentDark,
        ),
      ),
    );
  }
}

class _SettingsLinkRow extends StatelessWidget {
  const _SettingsLinkRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // مستطيل الإعدادات الموحَّد: أيقونة ملوّنة في مربّعها أقصى اليمين،
    // عنوان ووصف، وسهم رفيع أقصى اليسار — نفس صفوف القوائم في التطبيق.
    return AppListRow(
      key: ValueKey('settings-hub-$title'),
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      compact: AppSettings.instance.compactLists,
    );
  }
}

// ===========================================================================
// صفحة الإعدادات (تُفتح بالضغط على الاسم/البروفايل)
// ===========================================================================

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final items = <Widget>[
          _SettingsLinkRow(
            title: 'البيانات الشخصية',
            subtitle: 'الاسم والصورة ووسائل التواصل',
            icon: Icons.person_outline_rounded,
            color: const Color(0xFF2563EB),
            onTap: () => _open(context, const ProfileDataSettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'التنبيهات والتذكير',
            subtitle: settings.notificationsEnabled
                ? 'مفعّلة · التذكير الافتراضي ${settings.leadTimeLabel}'
                : 'موقوفة حاليًا',
            icon: Icons.notifications_none_rounded,
            color: const Color(0xFFEA580C),
            onTap: () => _open(context, const NotificationSettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'مركز التنبيهات',
            subtitle: 'الاستحقاقات والتنبيهات القريبة',
            icon: Icons.notifications_active_outlined,
            color: const Color(0xFFDC2626),
            onTap: () => _open(context, const NotificationsCenterScreen()),
          ),
          _SettingsLinkRow(
            title: 'اللغة والعملة',
            subtitle: '${settings.language} · ${AppSettings.currencySuffix}'
                ' · ${settings.calendar}',
            icon: Icons.language_rounded,
            color: const Color(0xFF059669),
            onTap: () => _open(context, const LanguageCurrencySettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'المظهر',
            subtitle: 'حجم النص ${(settings.textScale * 100).round()}%'
                '${settings.compactLists ? ' · قوائم مضغوطة' : ''}',
            icon: Icons.palette_outlined,
            color: const Color(0xFF2563EB),
            onTap: () => _open(context, const AppearanceSettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'الأمان والخصوصية',
            subtitle: [
              settings.appLock ? 'القفل مفعّل' : 'القفل موقوف',
              if (settings.hideAmounts) 'المبالغ مخفية',
            ].join(' · '),
            icon: Icons.shield_outlined,
            color: const Color(0xFF475569),
            onTap: () => _open(context, const SecuritySettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'حالة البيانات والاتصال',
            subtitle: 'الحساب الحالي وعدد السجلات في الخادم',
            icon: Icons.cloud_done_outlined,
            color: const Color(0xFF0EA5A4),
            onTap: () => _open(context, const DataStatusScreen()),
          ),
          _SettingsLinkRow(
            title: 'حول التطبيق',
            subtitle: AppSettings.appVersionLabel,
            icon: Icons.info_outline_rounded,
            color: const Color(0xFF64748B),
            onTap: () => _open(context, const AboutAppPage()),
          ),
          _SettingsLinkRow(
            title: 'سياسة الخصوصية',
            subtitle: 'ما يُخزَّن وأين ومع من يُشارَك',
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF475569),
            onTap: () => _open(context, const PrivacyPolicyPage()),
          ),
          _SettingsLinkRow(
            title: 'تواصل معنا',
            subtitle: 'إرسال ملاحظة أو طلب دعم',
            icon: Icons.support_agent_outlined,
            color: const Color(0xFF2563EB),
            onTap: () => _open(context, const ContactUsPage()),
          ),
        ];

        return Scaffold(
          backgroundColor: AppTheme.page,
          appBar: AppBar(
            title: const Text('الإعدادات', style: AppTheme.cardTitle),
            centerTitle: true,
            backgroundColor: AppTheme.page,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) =>
                  SizedBox(height: settings.compactLists ? 8 : 12),
              itemBuilder: (_, index) {
                if (index == 0) return const _SettingsProfileHeader();
                return items[index - 1];
              },
            ),
          ),
        );
      },
    );
  }
}

/// ترويسة الإعدادات — تعرض الاسم والصورة المحفوظين فعليًا، لا اسمًا مكتوبًا
/// في الشيفرة كما كان.
class _SettingsProfileHeader extends StatelessWidget {
  const _SettingsProfileHeader();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final photo = settings.photo;
    return InkWell(
      key: const ValueKey('settings-profile-header'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileDataSettingsPage()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: AppTheme.field,
              backgroundImage: photo == null ? null : MemoryImage(photo),
              child: photo != null
                  ? null
                  : const Icon(
                      Icons.person_rounded,
                      color: AppTheme.chevron,
                      size: 27,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    settings.email.isNotEmpty
                        ? settings.email
                        : settings.phone.isNotEmpty
                        ? settings.phone
                        : 'عرض وتعديل البيانات الشخصية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowSubtitle,
                  ),
                ],
              ),
            ),
            const AppChevron(),
          ],
        ),
      ),
    );
  }
}
