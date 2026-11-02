import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import '../data/app_settings.dart';
import '../data/custody_sharing.dart';
import '../data/fundly_account.dart';
import '../data/fundly_auth.dart';
import 'login_screen.dart';
import 'birthday_screen.dart';
import 'trash_screen.dart';
import '../widgets/shared/app_design.dart';
import 'document_templates_screen.dart';
import 'settings_detail_screens.dart';
import 'signature_settings_screen.dart';
import 'pages_customization_screen.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key, this.delegationsPage});

  final Widget? delegationsPage;

  /// الضيف يُطلب منه الدخول أو التسجيل قبل فتح أي بند.
  Future<void> _open(BuildContext context, Widget page) async {
    if (!await FundlyAuth.requireLogin(context)) return;
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    // Keep only the requested items on the More page.
    final items = <_SettingsItem>[
      // «تخصيص الصفحات»: الصفحة الرئيسية كما كانت، والصفحات الأربع.
      const _SettingsItem(
        title: 'تخصيص الصفحات',
        subtitle: 'الصفحة الرئيسية وإخفاء الفئات والعناصر في كل صفحة',
        icon: Icons.dashboard_customize_outlined,
        color: Color(0xFF0E7161),
        page: PagesCustomizationScreen(),
      ),
      if (delegationsPage != null)
        _SettingsItem(
          title: 'التفويضات',
          subtitle: 'إدارة المفوضين والصلاحيات وفترات التفويض',
          icon: Icons.manage_accounts_outlined,
          color: const Color(0xFF0A5A50),
          page: delegationsPage!,
        ),
      const _SettingsItem(
        title: 'التوقيع الإلكتروني والختم الإلكتروني',
        subtitle: 'إدارة التوقيع والختم المستخدمَين في المستندات',
        icon: Icons.draw_outlined,
        color: Color(0xFF0E7161),
        page: SignatureSettingsScreen(),
      ),
      const _SettingsItem(
        title: 'سلة المهملات',
        subtitle: 'استعادة ما حذفته أو حذفه نهائيًا',
        icon: Icons.delete_outline_rounded,
        color: Color(0xFFC4392E),
        page: TrashScreen(),
      ),
      const _SettingsItem(
        title: 'قوالب المستندات والايصالات',
        subtitle: 'العقود والإيصالات والفواتير الجاهزة',
        icon: Icons.receipt_long_outlined,
        color: Color(0xFF178F7B),
        page: DocumentTemplatesScreen(),
      ),
    ];

    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('المزيد', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // الاسم والصورة يُقرآن من البيانات الشخصية المحفوظة، لا من نص
            // مكتوب في الشيفرة كان يبقى كما هو مهما عدّل المستخدم ملفه.
            ListenableBuilder(
              listenable: AppSettings.instance,
              builder: (context, _) {
                final settings = AppSettings.instance;
                final photo = settings.photo;
                return InkWell(
                  key: const ValueKey('settings-profile-header'),
                  onTap: () => FundlyAuth.isGuest
                      ? openLoginScreen(context)
                      : _open(context, const ProfileDataSettingsPage()),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: AppTheme.field,
                          backgroundImage: photo == null || FundlyAuth.isGuest
                              ? null
                              : MemoryImage(photo),
                          child: photo != null && !FundlyAuth.isGuest
                              ? null
                              : Icon(
                                  FundlyAuth.isGuest
                                      ? Icons.login_rounded
                                      : Icons.person_rounded,
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
                                FundlyAuth.isGuest
                                    ? 'تسجيل الدخول / إنشاء حساب'
                                    : settings.name,
                                maxLines: 3,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.title,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                FundlyAuth.isGuest
                                    ? 'سجّل الدخول أو أنشئ حسابًا'
                                    : 'عرض وتعديل البيانات الشخصية',
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
              },
            ),
            const SizedBox(height: 8),
            // الرقم التعريفي والاسم: هوية هذا الجهاز في المعاملات
            // المشتركة، وكلاهما قابل للتعديل من داخل البطاقة.
            // الضيف بلا رقم تعريفي حتى يسجّل.
            if (!FundlyAuth.isGuest) ...[
              const _IdentityCard(),
              const SizedBox(height: AppTheme.cardGap),
            ],
            // مستطيلات منفصلة بنفس نمط صفحة الإعدادات، بدل صندوق واحد
            // تفصل بنوده خطوط رفيعة.
            for (var index = 0; index < items.length; index++) ...[
              _SettingsRow(
                item: items[index],
                onTap: () => _open(context, items[index].page),
              ),
              if (index != items.length - 1)
                const SizedBox(height: AppTheme.cardGap),
            ],
            const SizedBox(height: 18),
            const Text(
              // رقم الإصدار من ثابت واحد يُحدَّث مع pubspec، بدل رقم ثابت
              // في الشاشة كان قد تقادم بعد رفع الإصدار.
              'Fundly  •  ${AppSettings.appVersionLabel}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _SettingsItem {
  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget page;
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.item, required this.onTap});

  final _SettingsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // نفس مستطيل الإعدادات الموحَّد في كل التطبيق.
    return AppListRow(
      key: ValueKey('settings-row-${item.title}'),
      icon: item.icon,
      iconColor: item.color,
      title: item.title,
      subtitle: item.subtitle,
      onTap: onTap,
      compact: AppSettings.instance.compactLists,
    );
  }
}


/// بطاقة الهوية: الرقم التعريفي للحساب (من النظام، للنسخ فقط) والاسم
/// الظاهر للطرف الآخر.
class _IdentityCard extends StatefulWidget {
  const _IdentityCard();

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  /// «اسمي الظاهر للآخرين» يُعدَّل من صفحة البيانات الشخصية.
  Future<void> _openPublicName() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileDataSettingsPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = AppIdentity.id;
    final birthday = AppSettings.instance.birthday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          const AppIconTile(
            icon: Icons.qr_code_2_rounded,
            color: AppTheme.brandMid,
            size: AppTheme.iconTileSmall,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الرقم التعريفي',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  id.isEmpty ? '—' : id,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'شارِك هذا الرقم مع الطرف الآخر ليُسند إليك عهدة أو معاملة '
                  'مشتركة.',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          // الرقم للعرض والنسخ فقط — تعديل الاسم في «اسمي الظاهر للآخرين».
          IconButton(
            tooltip: AppTr.tr('نسخ الرقم'),
            onPressed: id.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: id));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('نُسخ الرقم التعريفي'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            icon: const Icon(
              Icons.copy_rounded,
              size: 20,
              color: AppTheme.brandMid,
            ),
          ),
        ],
      ),
        ),
        const SizedBox(height: 8),
        // «اسمي الظاهر للآخرين»: ما يراه الطرف الآخر، وقلم يعدّله.
        InkWell(
          onTap: _openPublicName,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              textDirection: AppTr.uiDir,
              children: [
                const AppIconTile(
                  icon: Icons.badge_outlined,
                  color: AppTheme.brandMid,
                  size: AppTheme.iconTileSmall,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'اسمي الظاهر للآخرين',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        AppSettings.instance.publicName.trim().isEmpty
                            ? '—'
                            : AppSettings.instance.publicName,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppTr.tr('تعديل الاسم'),
                  onPressed: _openPublicName,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: AppTheme.brandMid,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // تاريخ الميلاد: يُقرأ من الملف الشخصي ويُعدَّل من هناك فقط.
        // يُنبّه في الرئيسية قبل خمسة أيام ويوم الميلاد.
        InkWell(
          onTap: birthday.isEmpty
              ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileDataSettingsPage(),
                  ),
                )
              : null,
          borderRadius: BorderRadius.circular(AppTheme.rInner),
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
                const AppIconTile(
                  icon: Icons.cake_outlined,
                  color: AppTheme.goldDark,
                  size: AppTheme.iconTileSmall,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'تاريخ الميلاد',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        birthday.isEmpty
                            ? 'أضفه من تعديل الملف الشخصي'
                            : birthday,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: birthday.isEmpty
                              ? AppTheme.muted
                              : AppTheme.title,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppTr.tr('بطاقة الميلاد'),
                  visualDensity: VisualDensity.compact,
                  onPressed: birthday.isEmpty
                      ? null
                      : () => showBirthdaySheet(context),
                  icon: const Icon(
                    Icons.cake_rounded,
                    size: 19,
                    color: AppTheme.goldDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
