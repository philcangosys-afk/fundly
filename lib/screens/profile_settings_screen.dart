import 'package:flutter/material.dart';

import 'document_templates_screen.dart';
import 'notifications_center_screen.dart';
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
        title: 'التوقيع والختم',
        subtitle: 'إدارة التوقيع المستخدم في المستندات',
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            InkWell(
              key: const ValueKey('settings-profile-header'),
              onTap: () => _open(context, const ProfileDataSettingsPage()),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Color(0xFFDDF3EE),
                      child: Icon(
                        Icons.person_rounded,
                        color: Color(0xFF087F6A),
                        size: 27,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'عبدالعزيز الهاجري',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF17212B),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'عرض وتعديل البيانات الشخصية',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                      color: Color(0xFFB7C2C0),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6ECEA)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _SettingsRow(
                      item: items[index],
                      onTap: () => _open(context, items[index].page),
                    ),
                    if (index != items.length - 1)
                      const Divider(
                        height: 1,
                        indent: 68,
                        endIndent: 14,
                        color: Color(0xFFEDF1F0),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Fundly  •  الإصدار 1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
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
    return ListTile(
      key: ValueKey('settings-row-${item.title}'),
      minTileHeight: 67,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(item.icon, color: item.color, size: 22),
      ),
      title: Text(
        item.title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF25313B),
        ),
      ),
      subtitle: Text(
        item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, color: Color(0xFF84918F)),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 15,
        color: Color(0xFFB7C2C0),
      ),
    );
  }
}
