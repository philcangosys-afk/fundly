import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications_center_screen.dart';

class ProfileDataSettingsPage extends StatefulWidget {
  const ProfileDataSettingsPage({super.key});

  @override
  State<ProfileDataSettingsPage> createState() =>
      _ProfileDataSettingsPageState();
}

class _ProfileDataSettingsPageState extends State<ProfileDataSettingsPage> {
  final _name = TextEditingController(text: 'عبدالعزيز الهاجري');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _social = TextEditingController();
  String _language = 'العربية';
  Uint8List? _photoBytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _name.text = prefs.getString('settings_profile_name') ?? _name.text;
    _phone.text = prefs.getString('settings_profile_phone') ?? '';
    _email.text = prefs.getString('settings_profile_email') ?? '';
    _city.text = prefs.getString('settings_profile_city') ?? '';
    _social.text = prefs.getString('settings_profile_social') ?? '';
    _language = prefs.getString('settings_profile_language') ?? 'العربية';
    final photo = prefs.getString('settings_profile_photo');
    if (photo != null && photo.isNotEmpty) {
      try {
        _photoBytes = base64Decode(photo);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 900,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _photoBytes = bytes);
  }

  void _openPhotoPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_profile_name', _name.text.trim());
    await prefs.setString('settings_profile_phone', _phone.text.trim());
    await prefs.setString('settings_profile_email', _email.text.trim());
    await prefs.setString('settings_profile_city', _city.text.trim());
    await prefs.setString('settings_profile_social', _social.text.trim());
    await prefs.setString('settings_profile_language', _language);
    if (_photoBytes == null) {
      await prefs.remove('settings_profile_photo');
    } else {
      await prefs.setString(
        'settings_profile_photo',
        base64Encode(_photoBytes!),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات الشخصية')));
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
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFAFBFC),
        surfaceTintColor: Colors.transparent,
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFF25313B),
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 20,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _photoBytes == null
                          ? const ColoredBox(
                              color: Color(0xFFF2F5F6),
                              child: Icon(
                                Icons.person_outline_rounded,
                                size: 82,
                                color: Color(0xFFEF6A72),
                              ),
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  PositionedDirectional(
                    end: -2,
                    bottom: 7,
                    child: Material(
                      color: const Color(0xFFEF4F5A),
                      shape: const CircleBorder(),
                      elevation: 3,
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
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('profile-language'),
                    initialValue: _language,
                    decoration: _profileInputDecoration(
                      hint: 'اختر اللغة',
                      icon: Icons.language_rounded,
                    ),
                    items: const ['العربية', 'English']
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
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4F5A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text(
                  'حفظ التعديلات',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            // Removed embedded settings links from profile edit page.
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
                color: Color(0xFF2D3748),
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
    hintStyle: const TextStyle(color: Color(0xFF9AA4AE), fontSize: 12.5),
    filled: true,
    fillColor: const Color(0xFFF0F2F4),
    suffixIcon: Icon(icon, size: 19, color: const Color(0xFFEF6670)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE8ECEF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFEF6670), width: 1.4),
    ),
  );
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _enabled = true;
  bool _expiry = true;
  String _leadTime = 'قبل أسبوع';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool('settings_notifications_enabled') ?? true;
      _expiry = prefs.getBool('settings_expiry_notifications') ?? true;
      _leadTime = prefs.getString('settings_default_lead_time') ?? 'قبل أسبوع';
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'التنبيهات والتذكير',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تفعيل التنبيهات داخل التطبيق'),
          value: _enabled,
          onChanged: (value) {
            setState(() => _enabled = value);
            _setBool('settings_notifications_enabled', value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تنبيهات انتهاء المستندات والعقود'),
          value: _expiry,
          onChanged: (value) {
            setState(() => _expiry = value);
            _setBool('settings_expiry_notifications', value);
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: _leadTime,
          decoration: const InputDecoration(
            labelText: 'وقت التذكير الافتراضي',
            border: OutlineInputBorder(),
          ),
          items:
              const [
                    'في نفس اليوم',
                    'قبل يوم',
                    'قبل 3 أيام',
                    'قبل أسبوع',
                    'قبل شهر',
                  ]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _leadTime = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('settings_default_lead_time', value);
          },
        ),
      ],
    );
  }
}

class LanguageCurrencySettingsPage extends StatefulWidget {
  const LanguageCurrencySettingsPage({super.key});

  @override
  State<LanguageCurrencySettingsPage> createState() =>
      _LanguageCurrencySettingsPageState();
}

class _LanguageCurrencySettingsPageState
    extends State<LanguageCurrencySettingsPage> {
  String _language = 'العربية';
  String _currency = 'درهم إماراتي (AED)';
  String _calendar = 'ميلادي';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('settings_language') ?? _language;
      _currency = prefs.getString('settings_currency') ?? _currency;
      _calendar = prefs.getString('settings_calendar') ?? _calendar;
    });
  }

  Future<void> _save(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'اللغة والعملة',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: const InputDecoration(
            labelText: 'لغة التطبيق',
            border: OutlineInputBorder(),
          ),
          items: const ['العربية', 'English']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _language = value);
            _save('settings_language', value);
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: const InputDecoration(
            labelText: 'العملة الافتراضية',
            border: OutlineInputBorder(),
          ),
          items:
              const [
                    'درهم إماراتي (AED)',
                    'ريال سعودي (SAR)',
                    'دولار أمريكي (USD)',
                    'دينار كويتي (KWD)',
                  ]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _currency = value);
            _save('settings_currency', value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _calendar,
          decoration: const InputDecoration(
            labelText: 'نوع التقويم الافتراضي',
            border: OutlineInputBorder(),
          ),
          items: const ['ميلادي', 'هجري']
              .map((value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _calendar = value);
            _save('settings_calendar', value);
          },
        ),
      ],
    );
  }
}

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  double _textScale = 1;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _textScale = prefs.getDouble('settings_text_scale') ?? 1;
      _compact = prefs.getBool('settings_compact_lists') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'المظهر',
      children: [
        const Text('حجم النص', style: TextStyle(fontWeight: FontWeight.w800)),
        Slider(
          value: _textScale,
          min: 0.85,
          max: 1.25,
          divisions: 4,
          label: '${(_textScale * 100).round()}%',
          onChanged: (value) => setState(() => _textScale = value),
          onChangeEnd: (value) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('settings_text_scale', value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('عرض القوائم بشكل مضغوط'),
          value: _compact,
          onChanged: (value) async {
            setState(() => _compact = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('settings_compact_lists', value);
          },
        ),
      ],
    );
  }
}

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _appLock = false;
  bool _hideAmounts = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _appLock = prefs.getBool('settings_app_lock') ?? false;
      _hideAmounts = prefs.getBool('settings_hide_amounts') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'الأمان والخصوصية',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('قفل التطبيق'),
          subtitle: const Text('حماية فتح التطبيق على هذا الجهاز'),
          value: _appLock,
          onChanged: (value) async {
            setState(() => _appLock = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('settings_app_lock', value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إخفاء المبالغ الحساسة'),
          subtitle: const Text('إخفاء الأرقام في ملخص الصفحة الرئيسية'),
          value: _hideAmounts,
          onChanged: (value) async {
            setState(() => _hideAmounts = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('settings_hide_amounts', value);
          },
        ),
        const SettingsNotice(
          text:
              'القفل الحيوي ببصمة الجهاز يحتاج تفعيلًا أصليًا منفصلًا لكل نظام تشغيل.',
        ),
      ],
    );
  }
}

class BackupExportSettingsPage extends StatelessWidget {
  const BackupExportSettingsPage({super.key});

  Future<void> _export() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      data[key] = prefs.get(key);
    }
    await SharePlus.instance.share(
      ShareParams(
        text: const JsonEncoder.withIndent('  ').convert(data),
        subject: 'نسخة إعدادات Fundly',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'النسخ الاحتياطي والتصدير',
      children: [
        const SettingsNotice(
          text:
              'التصدير الحالي يشمل الإعدادات والبيانات المحلية على هذا الجهاز.',
        ),
        FilledButton.icon(
          onPressed: _export,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('تصدير نسخة الآن'),
        ),
      ],
    );
  }
}

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
        Text('الإصدار 1.0.0 (1)', textAlign: TextAlign.center),
        SettingsNotice(
          text:
              'تطبيق عربي لإدارة الأموال والأصول والالتزامات والعلاقات في مكان واحد.',
        ),
      ],
    );
  }
}

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
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7FAF9),
        surfaceTintColor: Colors.transparent,
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

class SettingsTextField extends StatelessWidget {
  const SettingsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6F3),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: Color(0xFF35635B),
        ),
      ),
    );
  }
}

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsDetailPage(
      title: 'الاشتراك',
      children: [
        SettingsNotice(text: 'واجهة إدارة الاشتراك وخطط الدفع. (مؤقت)'),
      ],
    );
  }
}

class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsDetailPage(
      title: 'تواصل معنا',
      children: [
        SettingsNotice(text: 'راسل فريق الدعم عبر البريد: support@fundly.app'),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsDetailPage(
      title: 'سياسة الخصوصية',
      children: [
        SettingsNotice(text: 'نص سياسة الخصوصية وسياسات الاستخدام هنا.'),
      ],
    );
  }
}

class FontSizeSettingsPage extends StatefulWidget {
  const FontSizeSettingsPage({super.key});

  @override
  State<FontSizeSettingsPage> createState() => _FontSizeSettingsPageState();
}

class _FontSizeSettingsPageState extends State<FontSizeSettingsPage> {
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final s = prefs.getDouble('settings_font_scale') ?? 1.0;
      if (!mounted) return;
      setState(() => _scale = s);
    });
  }

  Future<void> _save(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('settings_font_scale', value);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'حجم الخط',
      children: [
        Slider(
          value: _scale,
          min: 0.8,
          max: 1.4,
          divisions: 6,
          label: '${(_scale * 100).round()}%',
          onChanged: (v) => setState(() => _scale = v),
          onChangeEnd: (v) => _save(v),
        ),
        const SizedBox(height: 8),
        Text('معاينة النص بحجم ${( _scale * 100 ).round()}%'),
      ],
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      minVerticalPadding: 8,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, color: Color(0xFF84918F)),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFFB7C2C0)),
    );
  }
}

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _SettingsLinkRow(
        title: 'البيانات الشخصية',
        subtitle: 'عرض وتعديل الملف الشخصي',
        icon: Icons.person_outline_rounded,
        color: const Color(0xFF2563EB),
        onTap: () => _open(context, const ProfileDataSettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'الاشتراك',
        subtitle: 'ادارة الاشتراك وخطط الدفع',
        icon: Icons.workspace_premium_outlined,
        color: const Color(0xFF0F6AA8),
        onTap: () => _open(context, const SubscriptionPage()),
      ),
      _SettingsLinkRow(
        title: 'التنبيهات والتذكير',
        subtitle: 'التنبيهات ومدة التذكير الافتراضية',
        icon: Icons.notifications_none_rounded,
        color: const Color(0xFFEA580C),
        onTap: () => _open(context, const NotificationSettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'مركز التنبيهات',
        subtitle: 'عرض الاستحقاقات والتنبيهات الحالية',
        icon: Icons.notifications_active_outlined,
        color: const Color(0xFFDC2626),
        onTap: () => _open(context, const NotificationsCenterScreen()),
      ),
      _SettingsLinkRow(
        title: 'اللغة والعملة',
        subtitle: 'العربية والعملة الافتراضية للتطبيق',
        icon: Icons.language_rounded,
        color: const Color(0xFF059669),
        onTap: () => _open(context, const LanguageCurrencySettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'الأمان والخصوصية',
        subtitle: 'قفل التطبيق وإخفاء البيانات الحساسة',
        icon: Icons.shield_outlined,
        color: const Color(0xFF475569),
        onTap: () => _open(context, const SecuritySettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'النسخ الاحتياطي والتصدير',
        subtitle: 'تصدير إعدادات وبيانات الجهاز المحلية',
        icon: Icons.ios_share_rounded,
        color: const Color(0xFF64748B),
        onTap: () => _open(context, const BackupExportSettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'المظهر',
        subtitle: 'حجم النص وخيارات العرض',
        icon: Icons.palette_outlined,
        color: const Color(0xFF2563EB),
        onTap: () => _open(context, const AppearanceSettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'حجم الخط',
        subtitle: 'تكبير أو تصغير واجهة التطبيق',
        icon: Icons.format_size,
        color: const Color(0xFF0EA5A4),
        onTap: () => _open(context, const FontSizeSettingsPage()),
      ),
      _SettingsLinkRow(
        title: 'حول التطبيق',
        subtitle: 'الإصدار والمعلومات القانونية',
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF64748B),
        onTap: () => _open(context, const AboutAppPage()),
      ),
      _SettingsLinkRow(
        title: 'سياسة الخصوصية',
        subtitle: 'اطلع على سياسة الخصوصية وشروط الاستخدام',
        icon: Icons.privacy_tip_outlined,
        color: const Color(0xFF475569),
        onTap: () => _open(context, const PrivacyPolicyPage()),
      ),
      _SettingsLinkRow(
        title: 'تواصل معنا',
        subtitle: 'إرسال ملاحظات أو طلب دعم',
        icon: Icons.support_agent_outlined,
        color: const Color(0xFF2563EB),
        onTap: () => _open(context, const ContactUsPage()),
      ),
      _SettingsLinkRow(
        title: 'تسجيل الخروج',
        subtitle: 'إنهاء الجلسة الحالية',
        icon: Icons.logout_rounded,
        color: const Color(0xFFDC2626),
        onTap: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          if (!context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SizedBox()),
            (route) => false,
          );
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7FAF9),
        surfaceTintColor: Colors.transparent,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => items[index],
        ),
      ),
    );
  }
}
