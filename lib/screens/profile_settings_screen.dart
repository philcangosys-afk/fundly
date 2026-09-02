import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../widgets/shared/app_design.dart';
import 'document_templates_screen.dart';
import 'settings_detail_screens.dart';
import 'signature_settings_screen.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key, this.delegationsPage});

  final Widget? delegationsPage;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    // Keep only the requested items on the More page.
    final items = <_SettingsItem>[
      if (delegationsPage != null)
        _SettingsItem(
          title: 'التفويضات',
          subtitle: 'إدارة المفوضين والصلاحيات وفترات التفويض',
          icon: Icons.manage_accounts_outlined,
          color: const Color(0xFF4F46E5),
          page: delegationsPage!,
        ),
      const _SettingsItem(
        title: 'التوقيع الإلكتروني والختم',
        subtitle: 'إدارة التوقيع والختم المستخدمَين في المستندات',
        icon: Icons.draw_outlined,
        color: Color(0xFF7C3AED),
        page: SignatureSettingsScreen(),
      ),
      const _SettingsItem(
        title: 'قوالب المستندات والايصالات',
        subtitle: 'العقود والإيصالات والفواتير الجاهزة',
        icon: Icons.receipt_long_outlined,
        color: Color(0xFF0D9488),
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
        textDirection: TextDirection.rtl,
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
                  onTap: () => _open(context, const ProfileDataSettingsPage()),
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
                          backgroundImage: photo == null
                              ? null
                              : MemoryImage(photo),
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
                              const Text(
                                'عرض وتعديل البيانات الشخصية',
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
              style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
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
