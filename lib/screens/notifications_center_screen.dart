import 'package:flutter/material.dart';

import '../data/home_dashboard_service.dart';
import '../l10n/home_strings.dart';

enum _NotificationsTab { all, attention, updates, activity }

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() =>
      _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  final HomeDashboardService _dashboardService = HomeDashboardService();
  bool _isLoading = true;
  List<HomeCalendarItem> _alerts = const [];
  _NotificationsTab _selectedTab = _NotificationsTab.all;

  @override
  void initState() {
    super.initState();
    _load();
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

  List<HomeCalendarItem> _filteredAlerts() {
    switch (_selectedTab) {
      case _NotificationsTab.all:
        return _alerts;
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
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _selectedTab = tab),
      selectedColor: const Color(0xFF0F6AA8),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF334155),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      side: BorderSide(
        color: selected ? const Color(0xFF0F6AA8) : const Color(0xFFE2E8F0),
      ),
      showCheckmark: false,
    );
  }

  Future<void> _load() async {
    final metrics = await _dashboardService.loadMetrics();
    if (!mounted) return;
    final now = DateUtils.dateOnly(DateTime.now());
    final dueSoon =
        metrics.calendarItems
            .where((item) {
              final expiry = DateUtils.dateOnly(item.date);
              final reminderDate = expiry.subtract(
                Duration(days: item.remindBeforeDays),
              );
              return !now.isBefore(reminderDate) && !now.isAfter(expiry);
            })
            .toList(growable: false)
          ..sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _alerts = dueSoon;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleAlerts = _filteredAlerts();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: const Text(HomeStrings.notifications),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  const Text(
                    'كل التنبيهات القادمة من الالتزامات والمستندات والمهام',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
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
                  ...visibleAlerts.map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                          color: Color(0xFF0F6AA8),
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Text(
                          '${item.module} · ${item.date.day}/${item.date.month}/${item.date.year}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (visibleAlerts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        HomeStrings.noData,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
