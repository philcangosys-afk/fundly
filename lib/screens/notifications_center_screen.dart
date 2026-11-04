import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../widgets/shared/module_shared_widgets.dart' show directOpenRoute;
import '../l10n/app_language.dart';

import '../data/app_settings.dart';
import '../data/home_dashboard_service.dart';
import '../data/read_notifications_store.dart';
import '../l10n/home_strings.dart';
import '../widgets/shared/app_design.dart';
import 'personal_commitments_screen.dart';
import 'projects_activities_screen.dart';
import 'shared_commitments_screen.dart';

enum _NotificationsTab { all, unread, attention, updates, activity }

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() =>
      _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  /// يفتح البند الذي جاء منه التنبيه (الالتزام أو العقار...) على تفاصيله.
  Future<void> _openAlert(HomeCalendarItem item) async {
    _readStore.markRead(item, read: true);
    var id = item.sourceId.trim();
    // تنبيه نسبة صرف العهدة: معرّفه «custody_percent_» ثم معرّف العهدة.
    const custodyPrefix = 'custody_percent_';
    if (id.startsWith(custodyPrefix)) id = id.substring(custodyPrefix.length);
    if (id.isEmpty) return;
    final Widget? page = switch (item.module) {
      'الالتزامات الشخصية' => PersonalCommitmentsScreen(openEntryId: id),
      'الالتزامات المشتركة' => SharedCommitmentsScreen(openEntryId: id),
      'العقارات والأنشطة التجارية' => ProjectsActivitiesScreen(openAssetId: id),
      _ => null,
    };
    if (page == null) return;
    // التفاصيل مباشرة: الرجوع منها يعيد إلى التنبيهات (صفحة واحدة).
    await Navigator.of(context).push(directOpenRoute(page));
  }

  /// مسح تنبيه واحد: يختفي من القائمة ولا يعود حتى يتجدد استحقاقه.
  Future<void> _dismissOne(HomeCalendarItem item) async {
    await _readStore.dismissAll([item]);
    if (!mounted) return;
    setState(() {
      _alerts = _alerts
          .where((a) => !identical(a, item))
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح التنبيه')),
    );
  }

  final HomeDashboardService _dashboardService = HomeDashboardService();
  final ReadNotificationsStore _readStore = ReadNotificationsStore.instance;
  bool _isLoading = true;
  List<HomeCalendarItem> _alerts = const [];
  _NotificationsTab _selectedTab = _NotificationsTab.all;

  @override
  void initState() {
    super.initState();
    _readStore.addListener(_onReadChanged);
    _load();
  }

  @override
  void dispose() {
    _readStore.removeListener(_onReadChanged);
    super.dispose();
  }

  void _onReadChanged() {
    if (mounted) setState(() {});
  }

  bool _isNeedsAttention(HomeCalendarItem item) {
    final now = DateUtils.dateOnly(DateTime.now());
    final dueDate = DateUtils.dateOnly(item.date);
    final daysLeft = dueDate.difference(now).inDays;
    return daysLeft <= 1;
  }

  bool _isActivity(HomeCalendarItem item) {
    return item.module.contains('المهام') ||
        item.module.contains('نشاط') ||
        item.title.contains('مهمة') ||
        item.title.contains('نشاط');
  }

  int get _unreadCount => _readStore.unreadCount(_alerts);

  List<HomeCalendarItem> _filteredAlerts() {
    switch (_selectedTab) {
      case _NotificationsTab.all:
        return _alerts;
      case _NotificationsTab.unread:
        return _alerts
            .where((item) => !_readStore.isRead(item))
            .toList(growable: false);
      case _NotificationsTab.attention:
        return _alerts.where(_isNeedsAttention).toList(growable: false);
      case _NotificationsTab.updates:
        return _alerts
            .where((item) => !_isNeedsAttention(item) && !_isActivity(item))
            .toList(growable: false);
      case _NotificationsTab.activity:
        return _alerts.where(_isActivity).toList(growable: false);
    }
  }

  Widget _buildTab({
    required String label,
    required _NotificationsTab tab,
    required IconData icon,
  }) {
    final selected = _selectedTab == tab;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : const Color(0xFF46534F),
          ),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _selectedTab = tab),
      selectedColor: const Color(0xFF0A5A50),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF2C3B38),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
      side: BorderSide(
        color: selected ? const Color(0xFF0A5A50) : const Color(0xFFE4EAE8),
      ),
      showCheckmark: false,
    );
  }

  Future<void> _load() async {
    await _readStore.load();
    final metrics = await _dashboardService.loadMetrics();
    if (!mounted) return;
    final settings = AppSettings.instance;
    final now = DateUtils.dateOnly(DateTime.now());
    // إعدادات التنبيهات كانت تُحفظ ولا يقرأها أحد: تُوقف التنبيهات فلا
    // يتغير شيء، وتُغيَّر مدة التذكير الافتراضية بلا أثر. الآن تُطبَّق هنا.
    final dueSoon = settings.notificationsEnabled
        ? (metrics.calendarItems
                // مصدر واحد مع النقطة الحمراء: يستبعد المكتمل والملغى
                // و«بدون تذكير»، ويُبقي المتأخر غير المغلق ظاهرًا.
                .where(
                  (item) => HomeDashboardService.isAlertDue(
                    item,
                    today: now,
                    defaultLead: settings.leadTimeDays,
                    expiryEnabled: settings.expiryNotifications,
                  ),
                )
                .toList(growable: false)
              ..sort((a, b) => a.date.compareTo(b.date)))
        : const <HomeCalendarItem>[];

    setState(() {
      // ما مُسح بـ«مسح الكل» لا يعود حتى يتجدد استحقاقه.
      _alerts = dueSoon
          .where((item) => !_readStore.isDismissed(item))
          .toList(growable: false);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleAlerts = _filteredAlerts();
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        // سهم الرجوع نفسه في الكلندر والقرعة والتنبيهات.
        leading: IconButton(
          tooltip: AppTr.tr('رجوع'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: const Text(HomeStrings.notifications),
        centerTitle: true,
        actions: [
          if (_alerts.isNotEmpty)
            PopupMenuButton<String>(
              key: const ValueKey('notifications-read-menu'),
              tooltip: AppTr.tr('التحكم بالتنبيهات'),
              icon: const Icon(Icons.done_all_rounded),
              onSelected: (value) async {
                if (value == 'clear') {
                  final ok = await confirmAction(
                    context,
                    title: 'مسح الكل',
                    message: 'ستُمسح كل التنبيهات الحالية من القائمة، وتعود '
                        'فقط عند استحقاق جديد. هل تريد المتابعة؟',
                    confirmLabel: 'مسح الكل',
                    danger: true,
                  );
                  if (!ok || !mounted) return;
                  await _readStore.dismissAll(_alerts);
                  if (!mounted) return;
                  setState(() => _alerts = const []);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم مسح كل التنبيهات')),
                  );
                  return;
                }
                final ok = await confirmAction(
                  context,
                  title: value == 'read'
                      ? 'وضع الكل كمقروء'
                      : 'وضع الكل كغير مقروء',
                  message: 'سيُطبَّق هذا على كل التنبيهات المعروضة. '
                      'هل تريد المتابعة؟',
                );
                if (!ok || !mounted) return;
                if (value == 'read') {
                  await _readStore.markAllRead(_alerts);
                } else {
                  await _readStore.markAllUnread(_alerts);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value == 'read'
                          ? 'تم وضع كل التنبيهات كمقروءة'
                          : 'تم وضع كل التنبيهات كغير مقروءة',
                    ),
                  ),
                );
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'read',
                  child: Directionality(
                    textDirection: AppTr.uiDir,
                    child: Row(
                      children: [
                        Icon(Icons.done_all_rounded, size: 19),
                        SizedBox(width: 8),
                        Text('وضع الكل كمقروء'),
                      ],
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'unread',
                  child: Directionality(
                    textDirection: AppTr.uiDir,
                    child: Row(
                      children: [
                        Icon(Icons.mark_email_unread_outlined, size: 19),
                        SizedBox(width: 8),
                        Text('إلغاء القراءة عن الكل'),
                      ],
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Directionality(
                    textDirection: AppTr.uiDir,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_sweep_outlined,
                          size: 19,
                          color: AppTheme.danger,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'مسح الكل من التنبيهات',
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  Text(
                    _alerts.isEmpty
                        ? 'كل التنبيهات القادمة من الالتزامات والمستندات والمهام'
                        : 'غير مقروءة: $_unreadCount من ${_alerts.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5C6B68),
                    ),
                  ),
                  if (!AppSettings.instance.notificationsEnabled)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDEFDC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF7C378)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'التنبيهات موقوفة من الإعدادات، لذلك لا تظهر هنا.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7A4E10),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await AppSettings.instance
                                  .setNotificationsEnabled(true);
                              await _load();
                            },
                            child: const Text('تفعيل'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        _buildTab(
                          label: 'الكل',
                          tab: _NotificationsTab.all,
                          icon: Icons.apps_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildTab(
                          label: 'غير المقروءة',
                          tab: _NotificationsTab.unread,
                          icon: Icons.mark_email_unread_outlined,
                        ),
                        const SizedBox(width: 8),
                        _buildTab(
                          label: 'يحتاج انتباهك',
                          tab: _NotificationsTab.attention,
                          icon: Icons.priority_high_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildTab(
                          label: 'التحديثات',
                          tab: _NotificationsTab.updates,
                          icon: Icons.update_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildTab(
                          label: 'النشاط',
                          tab: _NotificationsTab.activity,
                          icon: Icons.local_activity_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // التنبيه المقروء يبقى ظاهرًا لكن باهتًا وبأيقونة مختلفة،
                  // ويمكن إرجاعه غير مقروء بالضغطة نفسها.
                  ...visibleAlerts.map((item) {
                    final isRead = _readStore.isRead(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                      ),
                      child: ListTile(
                        // الضغط يفتح البند نفسه ويجعله مقروءًا، وزر اليسار
                        // يبدّل مقروء/غير مقروء.
                        onTap: () => _openAlert(item),
                        leading: Icon(
                          isRead
                              ? Icons.notifications_none_rounded
                              : Icons.notifications_active_outlined,
                          color: isRead
                              ? AppTheme.muted
                              : const Color(0xFF0A5A50),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isRead
                                ? FontWeight.w700
                                : FontWeight.w900,
                            color: isRead
                                ? AppTheme.muted
                                : const Color(0xFF022E2A),
                          ),
                        ),
                        subtitle: Text(
                          '${item.module} · ${item.date.day}/${item.date.month}/${item.date.year}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isRead
                                ? AppTheme.muted
                                : const Color(0xFF5C6B68),
                          ),
                        ),
                        // مقروء/غير مقروء، ومسح هذا التنبيه وحده.
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: isRead
                                  ? 'وضع كغير مقروء'
                                  : 'وضع كمقروء',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                isRead
                                    ? Icons.mark_email_unread_outlined
                                    : Icons.done_rounded,
                                size: 20,
                                color: isRead
                                    ? AppTheme.muted
                                    : const Color(0xFF0E7161),
                              ),
                              onPressed: () =>
                                  _readStore.markRead(item, read: !isRead),
                            ),
                            IconButton(
                              tooltip: AppTr.tr('مسح التنبيه'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: AppTheme.danger,
                              ),
                              onPressed: () => _dismissOne(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (visibleAlerts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        HomeStrings.noData,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5C6B68),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
