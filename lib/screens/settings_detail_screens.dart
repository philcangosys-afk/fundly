import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_settings.dart';
import '../data/fundly_account.dart';
import '../data/fundly_files.dart';
import '../data/fundly_auth.dart';
import '../data/custody_sharing.dart';
import '../data/subscription_plans.dart';
import 'subscriptions_screen.dart';
import '../widgets/shared/app_design.dart';
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
  late final TextEditingController _family;
  late final TextEditingController _nick;
  late String _sharedMode;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _city;
  late final TextEditingController _social;
  late final TextEditingController _birthday;
  late String _language;
  Uint8List? _photoBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // الإعدادات محمّلة مسبقًا عند إقلاع التطبيق، فتُملأ الحقول مباشرة بلا
    // ومضة قيم افتراضية تُستبدل بعد لحظة.
    _name = TextEditingController(text: _settings.givenName);
    _family = TextEditingController(text: _settings.familyName);
    _nick = TextEditingController(text: _settings.sharedNickname);
    _sharedMode = _settings.sharedNameMode;
    // معاينة «يظهر للآخرين» تتحدّث أثناء الكتابة.
    _name.addListener(_refreshPreview);
    _family.addListener(_refreshPreview);
    _nick.addListener(_refreshPreview);
    _phone = TextEditingController(text: _settings.phone);
    _email = TextEditingController(text: _settings.email);
    _city = TextEditingController(text: _settings.city);
    _social = TextEditingController(text: _settings.social);
    _birthday = TextEditingController(text: _settings.birthday);
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
        textDirection: AppTr.uiDir,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تغيير الصورة الشخصية',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
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
                      color: Color(0xFFC4392E),
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

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    // الاسم يظهر في ترويسة الصفحة الرئيسية، فاسم فارغ يترك الترويسة خالية.
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل الاسم أولًا')));
      return;
    }
    if (!AppSettings.isValidNameParts(_name.text, _family.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسمك')),
      );
      return;
    }
    final fullName = AppSettings.composeName(_name.text, _family.text);
    if (_sharedMode == AppSettings.sharedNameNick &&
        _nick.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب الاسم المستعار')),
      );
      return;
    }
    // الحقول الإلزامية: تاريخ الميلاد والهاتف والمدينة.
    final missing = [
      if (_birthday.text.trim().isEmpty) 'تاريخ الميلاد',
      if (_phone.text.trim().isEmpty) 'رقم الهاتف',
      if (_city.text.trim().isEmpty) 'المدينة',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppTr.tr('أكمل الحقول الإلزامية')}: '
            '${missing.map(AppTr.tr).join('، ')}',
          ),
        ),
      );
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صيغة البريد الإلكتروني غير صحيحة')),
      );
      return;
    }
    final birthdayText = _birthday.text.trim();
    final birthday = birthdayText.isEmpty
        ? null
        : _parseBirthday(birthdayText);
    if (birthdayText.isNotEmpty && birthday == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تاريخ الميلاد غير صحيح — اكتبه يوم/شهر/سنة مثل 17/9/1984',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    await _settings.setNameParts(_name.text, _family.text);
    await _settings.setSharedName(_sharedMode, _nick.text);
    await _settings.saveProfile(
      name: fullName,
      phone: _phone.text,
      email: _email.text,
      city: _city.text,
      social: _social.text,
      photo: _photoBytes,
    );
    await _settings.setLanguage(_language);
    await _settings.setBirthday(
      birthday == null
          ? ''
          : '${birthday.day}/${birthday.month}/${birthday.year}',
    );
    // الاسم يظهر للطرف الآخر في الطلبات، والهاتف يُدخل به.
    await FundlyAccount.pushProfile(name: fullName, phone: _phone.text);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ البيانات الشخصية')),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _family.dispose();
    _nick.dispose();
    _phone.dispose();
    _email.dispose();
    _city.dispose();
    _social.dispose();
    _birthday.dispose();
    super.dispose();
  }

  /// «17/9/1984» أو «17-9-1984» أو بالأرقام العربية ← تاريخ، أو null.
  static DateTime? _parseBirthday(String raw) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var text = raw.trim();
    for (var i = 0; i < arabic.length; i++) {
      text = text.replaceAll(arabic[i], '$i');
    }
    final parts = text
        .split(RegExp(r'[/\-.\s]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 1900) {
      return null;
    }
    final date = DateTime(year, month, day);
    // 31/2 مثلًا يتحول لتاريخ آخر: يُرفض بدل حفظ تاريخ لم يكتبه المستخدم.
    if (date.day != day || date.month != month) return null;
    if (date.isAfter(DateTime.now())) return null;
    return date;
  }

  /// التقويم يبدأ بالتاريخ المكتوب، ويُختار منه باليوم والشهر والسنة.
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final current = _parseBirthday(_birthday.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: AppTr.tr('تاريخ ميلادك'),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _birthday.text = '${picked.day}/${picked.month}/${picked.year}',
    );
  }

  Widget _buildBirthdayField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 10, bottom: 7),
            child: Text(
              'تاريخ الميلاد *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.body,
              ),
            ),
          ),
          TextField(
            key: const ValueKey('profile-birthday'),
            controller: _birthday,
            keyboardType: TextInputType.datetime,
            decoration: _profileInputDecoration(
              hint: AppTr.tr('يوم/شهر/سنة — مثل 17/9/1984'),
              icon: Icons.cake_outlined,
            ).copyWith(
              suffixIcon: IconButton(
                tooltip: AppTr.tr('اختيار من التقويم'),
                onPressed: _pickBirthday,
                icon: const Icon(
                  Icons.edit_calendar_outlined,
                  size: 19,
                  color: AppTheme.chevron,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
        textDirection: AppTr.uiDir,
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
                        tooltip: AppTr.tr('تغيير الصورة الشخصية'),
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
            const SizedBox(height: 22),
            // الاشتراكات والهدايا في الملف الشخصي (لا في «المزيد»).
            const _ProfileSubscriptionCard(),
            const SizedBox(height: 18),
            // الاسم الظاهر يُركَّب منهما: ثلاثي (الاسم الأول واسم الأب
            // والقبيلة/العائلة)، أو ثنائي إن كُتب اسم واحد.
            _ProfileEditField(
              controller: _name,
              label: 'اسمك الثلاثي *',
              hint: 'مثل: عبدالعزيز حمود سالم',
            ),
            _ProfileEditField(
              controller: _family,
              label: 'القبيلة / العائلة (اختياري)',
              hint: 'اسم القبيلة أو العائلة',
            ),
            // ما يراه الآخرون في المشاركات والطلبات وعند كتابة رقمك
            // التعريفي — اسمك الكامل يبقى عندك فقط.
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 10, bottom: 7),
              child: Text(
                'اسمي الظاهر للآخرين عند المشاركة',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.body,
                ),
              ),
            ),
            // الخيارات الأربعة في صف واحد يُسحب يمينًا ويسارًا — نفس شريط
            // الفئات في الالتزامات الشخصية وحركته.
            SizedBox(
              height: 46,
              child: ListView.separated(
                key: const ValueKey('profile-shared-name-modes'),
                scrollDirection: Axis.horizontal,
                itemCount: AppSettings.sharedNameModes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final mode = AppSettings.sharedNameModes[index];
                  return AppCategoryDropdownChip(
                    key: ValueKey('profile-shared-name-$mode'),
                    label: mode,
                    icon: switch (index) {
                      0 => Icons.person_outline_rounded,
                      1 => Icons.badge_outlined,
                      2 => Icons.groups_outlined,
                      _ => Icons.theater_comedy_outlined,
                    },
                    color: AppTheme.brand,
                    selected: _sharedMode == mode,
                    onTap: () => setState(() => _sharedMode = mode),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (_sharedMode == AppSettings.sharedNameNick)
              _ProfileEditField(
                controller: _nick,
                label: 'الاسم المستعار',
                hint: 'مثل: أم محمد',
              ),
            // ما يراه الآخرون بارزًا: يراجعه عند تغيير الاسم أو الاختيار.
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.brandSoft,
                borderRadius: BorderRadius.circular(AppTheme.rField),
                border: Border.all(color: AppTheme.brand.withValues(alpha: 0.35)),
              ),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 20,
                    color: AppTheme.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'يظهر للآخرين',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.body,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppSettings.publicNameFor(
                            mode: _sharedMode,
                            fullName: AppSettings.composeName(
                              _name.text,
                              _family.text,
                            ),
                            given: _name.text,
                            nickname: _nick.text,
                            family: _family.text,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _ProfileEditField(
              controller: _email,
              label: 'البريد الإلكتروني',
              hint: 'username@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
            _buildBirthdayField(),
            _ProfileEditField(
              controller: _phone,
              label: 'رقم الهاتف *',
              hint: 'أدخل رقم الهاتف',
              keyboardType: TextInputType.phone,
            ),
            _ProfileEditField(
              controller: _city,
              label: 'المدينة *',
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
                      'اللغة *',
                      style: TextStyle(
                        fontSize: 12,
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
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                key: const ValueKey('change-password'),
                onPressed: () => showChangePasswordDialog(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                ),
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text(
                  'تغيير كلمة المرور',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة الاشتراك في الملف الشخصي: الباقة ومدتها، ومنها صفحة الاشتراكات،
/// وتنبيه عدم الاسترداد.
class _ProfileSubscriptionCard extends StatelessWidget {
  const _ProfileSubscriptionCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        final plan = PlanAccess.current;
        final period = !settings.hasPlanPeriod
            ? AppTr.tr('الخطط الشهرية والسنوية وإهداء اشتراك')
            : settings.planIsGift || !settings.planAutoRenew
            ? '${AppTr.tr('ينتهي في')} ${settings.planEndLabel}'
            : '${AppTr.tr('يتجدد في')} ${settings.planEndLabel}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('profile-subscriptions'),
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                  border: Border.all(color: AppTheme.hairline),
                ),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    AppIconTile(
                      icon: Icons.workspace_premium_outlined,
                      color: plan.color,
                      size: AppTheme.iconTileSmall,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'الاشتراكات والهدايا',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${AppTr.tr('الباقة')} ${AppTr.tr(plan.name)} · $period',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const AppChevron(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: AppTr.uiDir,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppTheme.goldDark,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'تنبيه: عند إلغاء الاشتراك أو الهدية لا تُسترد المبالغ '
                    'المدفوعة، ويبقى الاشتراك فعّالًا حتى نهاية مدته.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.goldDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
                fontSize: 12,
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
    hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
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
            decoration: InputDecoration(
              labelText: AppTr.tr('وقت التذكير الافتراضي'),
              helperText:
                  AppTr.tr('يُستخدم للعناصر التي لم تُحدَّد لها مدة تذكير خاصة بها'),
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
        title: 'اللغة والعملة والتقويم',
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('settings-language'),
            initialValue: _settings.language,
            decoration: InputDecoration(
              labelText: AppTr.tr('لغة التطبيق'),
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
          // الترجمة الإنجليزية أصبحت فعلية — الإشعار القديم "قيد
          // الإعداد" حُذف: تغيير اللغة يترجم الواجهة ويقلب الاتجاه فورًا.
          DropdownButtonFormField<String>(
            key: const ValueKey('settings-currency'),
            initialValue: _settings.currency,
            decoration: InputDecoration(
              labelText: AppTr.tr('العملة الافتراضية'),
              helperText: AppTr.tr('تظهر بجانب كل مبلغ في التطبيق'),
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
                  style: TextStyle(fontSize: 12, color: Color(0xFF5C6B68)),
                ),
                const SizedBox(width: 8),
                Text(
                  '1,250 ${AppSettings.currencySuffix}',
                  style: const TextStyle(
                    fontSize: 13,
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
            decoration: InputDecoration(
              labelText: AppTr.tr('نوع التقويم الافتراضي'),
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
          textDirection: AppTr.uiDir,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5C6B68),
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
                  decoration: InputDecoration(
                    labelText: AppTr.tr('الرمز'),
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
                    decoration: InputDecoration(
                      labelText: AppTr.tr('تأكيد الرمز'),
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
                      color: Color(0xFFC4392E),
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
          color: Color(0xFF0E7161),
        ),
        Text(
          'Fundly',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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

  static const _updated = 'آخر تحديث: 12 أكتوبر 2026';

  static const _intro =
      'توضح هذه السياسة كيف يجمع تطبيق Fundly بياناتك ويستخدمها ويحميها، '
      'وحقوقك عليها. باستخدامك التطبيق فأنت توافق على ما ورد فيها.';

  static const _sections = <(String, String)>[
    (
      'من نحن ونطاق السياسة',
      'تطبيق Fundly («التطبيق»، «نحن») لإدارة الأموال والالتزامات والأصول والعلاقات. تسري هذه السياسة على كل ما يُجمع أو يُعالَج عبر التطبيق وخدماته، وتُطبَّق وفق نظام حماية البيانات الشخصية في المملكة العربية السعودية ولائحته التنفيذية، وأنظمة حماية البيانات المعمول بها في بلد المستخدم بالقدر الذي ينطبق عليه.',
    ),
    (
      'البيانات التي نجمعها',
      '• بيانات الحساب: الاسم، ورقم الهاتف أو البريد الإلكتروني المستخدم في الدخول، والرقم التعريفي الذي يُنشئه التطبيق لك.\n• البيانات التي تدخلها بنفسك: الالتزامات والمصروفات والدخل والديون والعهد والأقساط، وبيانات العقارات والأنشطة والمركبات وعقود الإيجار والدفعات، والمستندات والمرفقات والنماذج والتقارير.\n• بيانات أشخاص آخرين تسجّلها أنت: مثل المستأجرين والمؤجرين والأفراد والجهات وأرقام هوياتهم وهواتفهم.\n• الموقع الجغرافي: عند ضغطك زر جلب الموقع فقط، وبعد إذنك.\n• بيانات تقنية محدودة يلزمها التشغيل، مثل سجلات الاتصال لدى مزوّد الاستضافة لأغراض الأمان.\nلا نستخدم أدوات إعلانات أو تتبّع أو تحليلات سلوكية من أطراف ثالثة.',
    ),
    (
      'لماذا نعالج بياناتك',
      '• تقديم خدمات التطبيق وحفظ سجلاتك ومزامنتها بين أجهزتك.\n• إنشاء التذكيرات والتنبيهات والتقارير التي تطلبها.\n• تنفيذ المشاركة التي تختارها مع مستخدمين آخرين (العهد والديون والالتزامات المشتركة والتفويضات).\n• الرد على طلبات الدعم.\n• حماية الحسابات ومنع الاستخدام غير المشروع والالتزام بالأنظمة.\nنعالج البيانات لتنفيذ الخدمة التي طلبتها، وبموافقتك فيما يحتاج موافقة (الموقع والكاميرا والصور)، وللوفاء بالتزاماتنا النظامية. ولا نستخدمها لأي غرض آخر دون إبلاغك.',
    ),
    (
      'أين تُحفظ بياناتك',
      '• السجلات الأساسية والمرفقات المرفوعة تُحفظ لدى مزوّد الاستضافة السحابية (Supabase)، مقيّدة بحسابك بضوابط وصول على مستوى السجل، فلا يطّلع عليها حساب آخر إلا ما تشاركه أنت.\n• تُحفظ على جهازك فقط: التفضيلات، وصورة الملف الشخصي، ورمز قفل التطبيق، والتوقيع والختم والشعار، ودليل الأفراد والجهات، والمستندات العامة، والتذكيرات المحلية. حذف التطبيق يحذف هذه البيانات من الجهاز.\n• قد تُعالَج البيانات على خوادم خارج بلدك، ونلتزم عندئذ بالضمانات التي تشترطها الأنظمة لنقل البيانات خارج الحدود.',
    ),
    (
      'مشاركة البيانات والإفصاح عنها',
      '• لا نبيع بياناتك ولا نؤجّرها ولا نشاركها لأغراض تسويقية.\n• المشاركة داخل التطبيق تتم بطلبك: عند إسناد عهدة أو دين أو إضافة عضو بالرقم التعريفي يرى الطرف الآخر العنصر المشترك واسمك فقط، ولا يُكشف هاتفك أو عنوانك إلا بموافقتك.\n• ما تشاركه عبر زر المشاركة أو الطباعة (PDF أو صورة) يخرج بإرادتك وعبر التطبيق الذي تختاره.\n• نستعين بمزوّدي خدمة (الاستضافة والتخزين) يعالجون البيانات نيابةً عنّا وفق التزامات تعاقدية بالسرية والأمان.\n• قد نفصح عن البيانات إذا ألزمنا بذلك نظام أو أمر قضائي أو جهة مختصة.',
    ),
    (
      'الأذونات',
      '• الكاميرا والصور والملفات: لإرفاق المستندات والصور والختم والشعار وصورة الملف الشخصي.\n• الموقع: لتعبئة حقل الموقع عند طلبك فقط.\n• الإنترنت: لمزامنة بياناتك.\nيمكنك سحب أي إذن من إعدادات جهازك في أي وقت، وتبقى بقية خصائص التطبيق تعمل.',
    ),
    (
      'الاحتفاظ بالبيانات',
      'نحتفظ ببياناتك ما دام حسابك قائمًا. ما تحذفه ينتقل إلى سلة المهملات حتى تحذفه نهائيًا. وعند حذف الحساب تُحذف بياناته من أنظمتنا خلال مدة لا تتجاوز 30 يومًا، عدا ما يلزم الاحتفاظ به نظامًا، وتُزال من النسخ الاحتياطية وفق دورتها.',
    ),
    (
      'أمن البيانات',
      '• تشفير الاتصال بين التطبيق والخوادم (TLS).\n• ضوابط وصول تقصر كل سجل على صاحبه ومن يشاركه.\n• قفل التطبيق برمز، وخيار إخفاء المبالغ.\nلا توجد وسيلة نقل أو تخزين آمنة تمامًا، لذا نوصيك بحماية جهازك وعدم مشاركة رمز القفل.',
    ),
    (
      'حقوقك',
      'وفق الأنظمة المعمول بها لك الحق في:\n• العلم بكيفية جمع بياناتك ومعالجتها.\n• الوصول إلى بياناتك والحصول على نسخة منها.\n• تصحيحها أو تحديثها.\n• طلب حذفها أو إتلافها.\n• الرجوع عن موافقتك فيما بُني عليها.\n• تقديم شكوى إلى الجهة المختصة بحماية البيانات في بلدك (في المملكة العربية السعودية: الهيئة السعودية للبيانات والذكاء الاصطناعي «سدايا»).\nنرد على طلبك خلال 30 يومًا من استلامه.',
    ),
    (
      'حذف الحساب',
      'يمكنك حذف أي سجل من داخل شاشته في أي وقت. ولحذف حسابك وكل بياناته استخدم «حذف الحساب» في الإعدادات تحت «تسجيل الخروج»، أو راسلنا على بريد الدعم من البريد أو الرقم المرتبط بحسابك، وسنتحقق من الطلب وننفّذه.',
    ),
    (
      'بيانات الآخرين التي تدخلها',
      'عند تسجيلك بيانات أشخاص آخرين (كالمستأجرين أو الأفراد أو أطراف العقود) فأنت مسؤول عن أن يكون لديك أساس نظامي لذلك، وأن تستخدمها لأغراضك المشروعة فقط.',
    ),
    (
      'الاشتراكات والمدفوعات',
      'عند تفعيل الاشتراكات المدفوعة تتم عمليات الدفع عبر متاجر التطبيقات أو بوابات دفع مرخّصة، ولا نحفظ بيانات بطاقتك.',
    ),
    (
      'الأطفال',
      'التطبيق موجّه لمن بلغ 18 عامًا، ولا نجمع عن قصد بيانات من هم دون ذلك.',
    ),
    (
      'التعديلات على السياسة',
      'قد نحدّث هذه السياسة، ونُبلغك داخل التطبيق بأي تغيير جوهري قبل سريانه. واستمرارك في الاستخدام بعد السريان يعني موافقتك على النسخة المحدّثة.',
    ),
    (
      'التواصل معنا',
      'لأي سؤال أو طلب يتعلق بخصوصيتك راسلنا على بريد الدعم: support@fundly.app',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'سياسة الخصوصية',
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.sLg),
          decoration: BoxDecoration(
            color: const Color(0xFF0E7161).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppTheme.rField),
            border: Border.all(
              color: const Color(0xFF0E7161).withValues(alpha: 0.22),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 20,
                    color: Color(0xFF0E7161),
                  ),
                  SizedBox(width: 8),
                  Text(
                    _updated,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                _intro,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Color(0xFF46534F),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < _sections.length; i++)
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
                  '${i + 1}. ${AppTr.tr(_sections[i].$1)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _sections[i].$2,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Color(0xFF46534F),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  static const _updated = 'آخر تحديث: 17 أكتوبر 2026';

  static const _intro =
      'تنظّم هذه الشروط استخدامك تطبيق Fundly وخدماته. باستخدامك التطبيق '
      'فأنت توافق عليها وعلى سياسة الخصوصية، فإن لم توافق فتوقف عن الاستخدام.';

  static const _sections = <(String, String)>[
    (
      'الأهلية والحساب',
      '• التطبيق لمن بلغ 18 عامًا.\n• أنت مسؤول عن صحة بيانات حسابك، وعن سرية كلمة المرور ورمز قفل التطبيق، وعن كل ما يتم من حسابك.\n• أبلغنا فورًا إن اشتبهت في استخدام حسابك دون إذنك.',
    ),
    (
      'طبيعة الخدمة',
      'التطبيق أداة لتنظيم وتسجيل الأموال والالتزامات والأصول والعلاقات. ما يعرضه من أرقام وتنبيهات وتقارير مبني على ما تدخله أنت، ولا يُعد استشارة مالية أو قانونية أو محاسبية أو ضريبية.',
    ),
    (
      'بياناتك ومحتواك',
      '• ما تدخله من بيانات ومستندات يبقى ملكك، وتمنحنا حق معالجته بالقدر اللازم لتقديم الخدمة فقط وفق سياسة الخصوصية.\n• أنت مسؤول عن مشروعية ما تسجّله من بيانات أشخاص آخرين وعن حصولك على ما يلزم لذلك.',
    ),
    (
      'المشاركة مع مستخدمين آخرين',
      'عند إسناد عهدة أو ربط دين أو إضافة أعضاء إلى التزام مشترك، يرى الطرف الآخر العنصر المشترك وما يسجّله فيه. كل طرف مسؤول عمّا يسجّله أو يعتمده، والتطبيق وسيلة توثيق ولا يضمن وفاء أي طرف بالتزاماته تجاه الآخر.',
    ),
    (
      'الاشتراكات والمدفوعات',
      '• يبدأ الاشتراك فور تأكيد الدفع وتُحسب مدته من يوم الدفع.\n• يتجدد الاشتراك الشهري أو السنوي تلقائيًا بنفس السعر حتى تلغي التجديد من صفحة الاشتراكات أو من متجر التطبيقات قبل موعد التجديد بيوم على الأقل.\n• إلغاء التجديد لا يقطع الاشتراك فورًا: يبقى فعّالًا حتى نهاية المدة المدفوعة ثم يعود الحساب إلى الباقة الأساسية وتبقى البيانات محفوظة.\n• لا تُسترد المبالغ المدفوعة عن مدة بدأت، إلا ما يوجبه النظام أو سياسة المتجر الذي تمت منه عملية الدفع.\n• الأسعار المعروضة نهائية وتشمل ضريبة القيمة المضافة حيث تنطبق، وقد يطبّق البنك أو المتجر رسوم تحويل العملة.',
    ),
    (
      'الهدايا',
      'الاشتراك المُهدى يبدأ يوم تفعيل كوده من المُهدى إليه، وينتهي بنهاية مدته دون تجديد. لا تُسترد قيمة الهدية بعد شرائها أو تفعيلها، ولا تُستبدل نقدًا.',
    ),
    (
      'الاستخدام المقبول',
      'يُمنع استخدام التطبيق في أي نشاط مخالف للأنظمة أو في الاحتيال أو انتحال الشخصية، أو محاولة الوصول إلى حسابات أو بيانات غيرك، أو تعطيل الخدمة، أو نسخ التطبيق أو تفكيكه أو إعادة بيعه.',
    ),
    (
      'التوفر والتعديلات على الخدمة',
      'نعمل على أن تكون الخدمة متاحة باستمرار، لكن قد تتوقف مؤقتًا للصيانة أو لأسباب خارجة عن إرادتنا. وقد نطوّر الميزات أو نعدّلها، ونُبلغك داخل التطبيق بأي تغيير جوهري يمس اشتراكك.',
    ),
    (
      'حدود المسؤولية',
      'تُقدَّم الخدمة «كما هي». وبالقدر الذي تسمح به الأنظمة لا نتحمل المسؤولية عن أي خسارة غير مباشرة، أو عن قرارات اتخذتها بناءً على بيانات أدخلتها، أو عن فقد بيانات محفوظة على جهازك فقط.',
    ),
    (
      'إيقاف الحساب وحذفه',
      'يمكنك حذف حسابك في أي وقت من الإعدادات. ويحق لنا تعليق الحساب أو إيقافه عند مخالفة هذه الشروط، مع إبلاغك بالسبب ما لم يمنع ذلك نظام.',
    ),
    (
      'النظام الواجب التطبيق',
      'تخضع هذه الشروط لأنظمة المملكة العربية السعودية، وتختص محاكمها بالنظر في أي نزاع ينشأ عنها، دون إخلال بحقوقك النظامية في بلد إقامتك.',
    ),
    (
      'التعديلات على الشروط',
      'قد نحدّث هذه الشروط، ونُبلغك داخل التطبيق بأي تغيير جوهري قبل سريانه. واستمرارك في الاستخدام بعد السريان يعني موافقتك على النسخة المحدّثة.',
    ),
    (
      'التواصل معنا',
      'لأي سؤال عن هذه الشروط أو عن الاشتراكات والمدفوعات راسلنا على بريد الدعم: support@fundly.app',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsDetailPage(
      title: 'شروط الاستخدام',
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.sLg),
          decoration: BoxDecoration(
            color: const Color(0xFF0E7161).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppTheme.rField),
            border: Border.all(
              color: const Color(0xFF0E7161).withValues(alpha: 0.22),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.gavel_rounded,
                    size: 20,
                    color: Color(0xFF0E7161),
                  ),
                  SizedBox(width: 8),
                  Text(
                    _updated,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                _intro,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Color(0xFF46534F),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < _sections.length; i++)
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
                  '${i + 1}. ${AppTr.tr(_sections[i].$1)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _sections[i].$2,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Color(0xFF46534F),
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
        textDirection: AppTr.uiDir,
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

/// «مزامنة البيانات»: حالة المزامنة الحقيقية (آخر مزامنة أو الخطأ) وأعداد
/// السجلات في الخادم وعلى الجوال — تُفتح في الجوالين وتُقارن الأرقام.
class SyncStatusPage extends StatefulWidget {
  const SyncStatusPage({super.key});

  @override
  State<SyncStatusPage> createState() => _SyncStatusPageState();
}

class _SyncStatusPageState extends State<SyncStatusPage> {
  bool _busy = false;
  Map<String, int> _counts = const {};
  int _localKeys = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final counts = await FundlyAccount.serverCounts();
    final local = await FundlyAccount.localKeyCount();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _localKeys = local;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    await FundlyAccount.syncCloud();
    try {
      await FundlyFiles.syncUp();
      await FundlyFiles.syncDown(force: true);
    } catch (_) {}
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    final error = FundlyAccount.lastSyncError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          error == null ? 'تمت المزامنة بنجاح' : 'تعذّرت المزامنة: $error',
        ),
      ),
    );
  }

  String _when(DateTime? at) {
    if (at == null) return AppTr.tr('لم تتم بعد في هذا التشغيل');
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.day}/${at.month}/${at.year}  ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.title,
            ),
          ),
        ),
      ],
    ),
  );

  String _count(String table) {
    final value = _counts[table];
    if (value == null) return '…';
    if (value < 0) return AppTr.tr('تعذّرت القراءة');
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final user = FundlyAccount.currentUser;
    final error = FundlyAccount.lastSyncError;
    return ValueListenableBuilder<int>(
      valueListenable: FundlyAccount.syncStatus,
      builder: (context, _, _) => SettingsDetailPage(
        title: 'مزامنة البيانات',
        children: [
          const SettingsNotice(
            text: 'بياناتك محفوظة في حسابك وتظهر في أي جوال تدخل منه بنفس '
                'الحساب. تتم المزامنة تلقائيًا كل 30 ثانية وعند فتح التطبيق '
                'والخروج منه. افتح هذه الصفحة في الجوالين: يجب أن يكون '
                'الحساب والأرقام نفسها.',
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Column(
              children: [
                _row('الحساب', user?.email ?? AppTr.tr('غير مسجّل الدخول')),
                _row('الرقم التعريفي', AppIdentity.id),
                // معرّف الحساب في الخادم: يجب أن يكون نفسه في الجوالين.
                _row('معرّف الحساب', user == null ? '' : user.id.substring(0, 8)),
                if (FundlyAuth.isGuest)
                  _row(
                    'الوضع',
                    AppTr.tr('ضيف — البيانات على هذا الجوال فقط'),
                    color: AppTheme.danger,
                  ),
                _row('آخر مزامنة', _when(FundlyAccount.lastSyncAt)),
                _row(
                  'الحالة',
                  error == null
                      ? AppTr.tr(
                          FundlyAccount.lastSyncAt == null
                              ? '—'
                              : 'تمت المزامنة بنجاح',
                        )
                      : error,
                  color: error == null
                      ? const Color(0xFF0E7161)
                      : AppTheme.danger,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Column(
              children: [
                _row('الالتزامات الشخصية (الخادم)', _count('personal_entries')),
                _row('الالتزامات المشتركة (الخادم)', _count('shared_entries')),
                _row(
                  'العقارات والأنشطة والمركبات (الخادم)',
                  _count('project_assets'),
                ),
                _row('بيانات الجوال المحفوظة سحابيًا', _count('fundly_user_store')),
                _row('بيانات على هذا الجوال', '$_localKeys'),
              ],
            ),
          ),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _busy || user == null ? null : _syncNow,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_busy ? 'جارٍ المزامنة...' : 'مزامنة الآن'),
            ),
          ),
        ],
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
          fontSize: 12,
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
            color: const Color(0xFF0A5A50),
            onTap: () => _open(context, const ProfileDataSettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'التنبيهات والتذكير',
            subtitle: settings.notificationsEnabled
                ? 'مفعّلة · التذكير الافتراضي ${settings.leadTimeLabel}'
                : 'موقوفة حاليًا',
            icon: Icons.notifications_none_rounded,
            color: const Color(0xFFCE8422),
            onTap: () => _open(context, const NotificationSettingsPage()),
          ),
          // «مركز التنبيهات» هو جرس الصفحة الرئيسية — لا يتكرر هنا.
          _SettingsLinkRow(
            title: 'اللغة والعملة والتقويم',
            subtitle: '${settings.language} · ${AppSettings.currencySuffix}'
                ' · ${settings.calendar}',
            icon: Icons.language_rounded,
            color: const Color(0xFF178F7B),
            onTap: () => _open(context, const LanguageCurrencySettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'المظهر',
            subtitle: 'حجم النص ${(settings.textScale * 100).round()}%'
                '${settings.compactLists ? ' · قوائم مضغوطة' : ''}',
            icon: Icons.palette_outlined,
            color: const Color(0xFF0A5A50),
            onTap: () => _open(context, const AppearanceSettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'الأمان والخصوصية',
            subtitle: [
              settings.appLock ? 'القفل مفعّل' : 'القفل موقوف',
              if (settings.hideAmounts) 'المبالغ مخفية',
            ].join(' · '),
            icon: Icons.shield_outlined,
            color: const Color(0xFF46534F),
            onTap: () => _open(context, const SecuritySettingsPage()),
          ),
          _SettingsLinkRow(
            title: 'حول التطبيق',
            subtitle: AppSettings.appVersionLabel,
            icon: Icons.info_outline_rounded,
            color: const Color(0xFF5C6B68),
            onTap: () => _open(context, const AboutAppPage()),
          ),
          _SettingsLinkRow(
            title: 'سياسة الخصوصية',
            subtitle: 'بياناتك وحقوقك',
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF46534F),
            onTap: () => _open(context, const PrivacyPolicyPage()),
          ),
          _SettingsLinkRow(
            title: 'شروط الاستخدام',
            subtitle: 'شروط الخدمة والاشتراكات والمدفوعات',
            icon: Icons.gavel_rounded,
            color: const Color(0xFF46534F),
            onTap: () => _open(context, const TermsOfUsePage()),
          ),
          _SettingsLinkRow(
            title: 'تواصل معنا',
            subtitle: 'إرسال ملاحظة أو طلب دعم',
            icon: Icons.support_agent_outlined,
            color: const Color(0xFF0A5A50),
            onTap: () => _open(context, const ContactUsPage()),
          ),
          _SettingsLinkRow(
            title: 'مزامنة البيانات',
            subtitle: 'نفس بياناتك في كل جوال تدخل منه',
            icon: Icons.sync_rounded,
            color: const Color(0xFF0E7161),
            onTap: () => _open(context, const SyncStatusPage()),
          ),
          _SettingsLinkRow(
            title: 'تسجيل الخروج',
            subtitle: 'الخروج من الحساب على هذا الجهاز',
            icon: Icons.logout_rounded,
            color: const Color(0xFFC4392E),
            onTap: () => _confirmSignOut(context),
          ),
          // حذف الحساب مع تسجيل الخروج (كان في سياسة الخصوصية).
          _SettingsLinkRow(
            title: 'حذف الحساب',
            subtitle: 'طلب حذف حسابك وكل بياناته نهائيًا',
            icon: Icons.delete_forever_outlined,
            color: AppTheme.danger,
            onTap: () => _requestAccountDeletion(context),
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
            textDirection: AppTr.uiDir,
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
                    maxLines: 3,
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
                    maxLines: 3,
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


/// طلب حذف الحساب وكل بياناته — رسالة جاهزة إلى بريد الدعم.
Future<void> _requestAccountDeletion(BuildContext context) async {
  const email = AppSettings.supportEmail;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await confirmAction(
    context,
    title: 'طلب حذف الحساب',
    message:
        'سيُفتح بريدك برسالة جاهزة لطلب حذف حسابك وكل بياناته نهائيًا. '
        'أرسلها من البريد أو الرقم المرتبط بحسابك. هل تريد المتابعة؟',
    confirmLabel: 'متابعة',
    danger: true,
  );
  if (!ok) return;
  var opened = false;
  try {
    opened = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: email,
        query:
            'subject=${Uri.encodeComponent('طلب حذف الحساب — Fundly')}'
            '&body=${Uri.encodeComponent('أطلب حذف حسابي وكل بياناته نهائيًا.\nالاسم: ${AppSettings.instance.name}')}',
      ),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    await Clipboard.setData(const ClipboardData(text: email));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تعذّر فتح البريد — نُسخ بريد الدعم لتراسلنا منه'),
      ),
    );
  }
}

/// تأكيد ثم تسجيل الخروج والرجوع لشاشة الدخول (للدخول بنفس الحساب أو
/// بحساب آخر).
Future<void> _confirmSignOut(BuildContext context) async {
  final ok = await confirmAction(
    context,
    title: 'تسجيل الخروج',
    message: 'سيتم تسجيل خروجك من الحساب على هذا الجهاز. هل تريد المتابعة؟',
    confirmLabel: 'تسجيل الخروج',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  await FundlyAccount.signOut();
}

/// تغيير كلمة المرور: الحالية ثم الجديدة مرتين.
Future<void> showChangePasswordDialog(BuildContext context) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  String? error;
  var busy = false;
  var hide = true;
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Directionality(
      textDirection: AppTr.uiDir,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          InputDecoration decoration(String label) => InputDecoration(
            labelText: AppTr.tr(label),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setDialogState(() => hide = !hide),
              icon: Icon(
                hide
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
              ),
            ),
          );

          Future<void> submit() async {
            if (next.text != confirm.text) {
              setDialogState(
                () => error = 'كلمتا المرور الجديدتان غير متطابقتين',
              );
              return;
            }
            setDialogState(() {
              busy = true;
              error = null;
            });
            try {
              await FundlyAccount.changePassword(
                current: current.text,
                next: next.text,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } on FundlyAccountException catch (failure) {
              setDialogState(() {
                busy = false;
                error = failure.message;
              });
            }
          }

          return AlertDialog(
            backgroundColor: AppTheme.page,
            title: const Text('تغيير كلمة المرور'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: current,
                    obscureText: hide,
                    textDirection: TextDirection.ltr,
                    decoration: decoration('كلمة المرور الحالية'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: next,
                    obscureText: hide,
                    textDirection: TextDirection.ltr,
                    decoration: decoration('كلمة المرور الجديدة'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirm,
                    obscureText: hide,
                    textDirection: TextDirection.ltr,
                    decoration: decoration('تأكيد كلمة المرور الجديدة'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (changed == true) {
    messenger.showSnackBar(
      const SnackBar(content: Text('تم تغيير كلمة المرور')),
    );
  }
}
