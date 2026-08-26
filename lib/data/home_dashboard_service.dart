import 'dart:convert';

import 'package:fundly/data/personal_entries_repository.dart';
import 'package:fundly/data/project_assets_repository.dart';
import 'package:fundly/data/shared_entries_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_reminders_store.dart';
import 'calendar_items_store.dart';

class HomeDashboardMetrics {
  final int totalIncome;
  final int totalExpenses;
  final int totalDebts;
  final int expiringDocuments;
  final int commitmentsAndTasks;
  final int totalAssets;

  final int personalDebtsForYou;
  final int personalDebtsOnYou;
  final int personalNeedsFollowup;

  final int sharedActiveTrips;
  final int sharedActiveCircles;
  final int sharedNeedsFollowup;

  final int peopleCount;
  final int entitiesCount;
  final int peopleNeedsFollowup;

  final int assetsCount;
  final int businessCount;
  final int equipmentCount;
  final int assetsNeedsFollowup;

  final List<HomeCalendarItem> calendarItems;

  const HomeDashboardMetrics({
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalDebts,
    required this.expiringDocuments,
    required this.commitmentsAndTasks,
    required this.totalAssets,
    required this.personalDebtsForYou,
    required this.personalDebtsOnYou,
    required this.personalNeedsFollowup,
    required this.sharedActiveTrips,
    required this.sharedActiveCircles,
    required this.sharedNeedsFollowup,
    required this.peopleCount,
    required this.entitiesCount,
    required this.peopleNeedsFollowup,
    required this.assetsCount,
    required this.businessCount,
    required this.equipmentCount,
    required this.assetsNeedsFollowup,
    required this.calendarItems,
  });

  const HomeDashboardMetrics.empty()
    : totalIncome = 0,
      totalExpenses = 0,
      totalDebts = 0,
      expiringDocuments = 0,
      commitmentsAndTasks = 0,
      totalAssets = 0,
      personalDebtsForYou = 0,
      personalDebtsOnYou = 0,
      personalNeedsFollowup = 0,
      sharedActiveTrips = 0,
      sharedActiveCircles = 0,
      sharedNeedsFollowup = 0,
      peopleCount = 0,
      entitiesCount = 0,
      peopleNeedsFollowup = 0,
      assetsCount = 0,
      businessCount = 0,
      equipmentCount = 0,
      assetsNeedsFollowup = 0,
      calendarItems = const [];
}

class HomeCalendarItem {
  final String title;
  final String module;
  final DateTime date;
  final String sourceId;

  const HomeCalendarItem({
    required this.title,
    required this.module,
    required this.date,
    required this.sourceId,
    this.remindBeforeDays = 7,
    this.type = 'موعد',
    this.status = 'قادمة',
    this.priority = 'متوسطة',
    this.time = '',
    this.description = '',
    this.notes = '',
    this.isUserCreated = false,
  });

  final int remindBeforeDays;
  final String type;
  final String status;
  final String priority;
  final String time;
  final String description;
  final String notes;
  final bool isUserCreated;
}

class HomeDashboardService {
  HomeDashboardService({
    PersonalEntriesRepository? personalRepository,
    ProjectAssetsRepository? assetsRepository,
    SharedEntriesRepository? sharedRepository,
  }) : _personalRepository =
           personalRepository ?? SupabasePersonalEntriesRepository(),
       _assetsRepository =
           assetsRepository ?? SupabaseProjectAssetsRepository(),
       _sharedRepository =
           sharedRepository ?? SupabaseSharedEntriesRepository();

  /// مفتاح تخزين سجلات "إدارة الأشخاص والجهات" محليًا — نفس المفتاح
  /// المستخدم في people_management_screen.dart، تُقرأ منه الأعداد الحقيقية
  /// بدل تصفير بطاقة الأشخاص على الصفحة الرئيسية.
  static const _peopleStorageKey = 'people_management_records_v1';

  final PersonalEntriesRepository _personalRepository;
  final ProjectAssetsRepository _assetsRepository;
  final SharedEntriesRepository _sharedRepository;

  Future<HomeDashboardMetrics> loadMetrics() async {
    List<PersonalEntryRecord> personalEntries = const [];
    List<ProjectAssetRecord> assets = const [];
    List<SharedEntryRecord> sharedEntries = const [];
    List<Map<String, dynamic>> peopleRecords = const [];
    List<AppReminder> savedReminders = const [];
    List<CalendarRecord> calendarRecords = const [];

    try {
      personalEntries = await _personalRepository.fetchAll();
    } catch (error) {
      debugPrint('HomeDashboardService personal fetch failed: $error');
    }

    try {
      assets = await _assetsRepository.fetchAssets();
    } catch (error) {
      debugPrint('HomeDashboardService assets fetch failed: $error');
    }

    try {
      sharedEntries = await _sharedRepository.fetchAll();
    } catch (error) {
      debugPrint('HomeDashboardService shared fetch failed: $error');
    }

    try {
      peopleRecords = await _loadPeopleRecords();
    } catch (error) {
      debugPrint('HomeDashboardService people load failed: $error');
    }

    try {
      savedReminders = await AppRemindersStore.load();
    } catch (error) {
      debugPrint('HomeDashboardService reminders load failed: $error');
    }

    try {
      calendarRecords = await CalendarItemsStore.load();
    } catch (error) {
      debugPrint('HomeDashboardService calendar load failed: $error');
    }

    var totalIncome = 0;
    var totalExpenses = 0;
    var totalDebts = 0;
    var expiringDocuments = 0;
    var commitmentsAndTasks = 0;
    var personalDebtsForYou = 0;
    var personalDebtsOnYou = 0;
    var personalNeedsFollowup = 0;

    final now = DateTime.now();
    final in30Days = now.add(const Duration(days: 30));

    final calendarItems = <HomeCalendarItem>[];

    for (final entry in personalEntries) {
      final amount = entry.amount;
      final due = _parseDdMmYyyy(entry.dueDate);

      if (entry.entryType == 'إيراد' || entry.entryType == 'دخل') {
        totalIncome += amount;
      }
      if (entry.entryType == 'مصروف' ||
          entry.entryType == 'غرامة' ||
          entry.entryType == 'قسط') {
        totalExpenses += amount;
      }
      if (entry.entryType == 'دين / قرض / سلفة' || entry.entryType == 'ديون') {
        totalDebts += amount;
        final debtDirection =
            entry.details['نوع الدين'] ?? entry.details['الاتجاه'] ?? '';
        if (debtDirection.contains('يدين لي')) {
          personalDebtsForYou += amount;
        } else {
          personalDebtsOnYou += amount;
        }
      }

      if ((entry.entryType == 'مستند' || entry.entryType == 'ضمانات') &&
          due != null) {
        if (!due.isBefore(now) && !due.isAfter(in30Days)) {
          expiringDocuments += 1;
        }
      }

      if (entry.status != 'مكتملة') {
        commitmentsAndTasks += 1;
      }

      if (entry.status == 'متأخرة' || entry.status == 'قريبة الاستحقاق') {
        personalNeedsFollowup += 1;
      }

      if (due != null) {
        calendarItems.add(
          HomeCalendarItem(
            title: entry.title.isEmpty ? entry.entryType : entry.title,
            module: 'الالتزامات الشخصية',
            date: due,
            sourceId: entry.id ?? '',
            remindBeforeDays:
                (entry.details['التذكير قبل الانتهاء'] ?? '').isEmpty
                ? 7
                : AppRemindersStore.reminderDaysFromLabel(
                    entry.details['التذكير قبل الانتهاء']!,
                  ),
          ),
        );
      }
    }

    var assetsNeedsFollowup = 0;
    var businessCount = 0;
    var equipmentCount = 0;

    for (final asset in assets) {
      if (asset.needsAttention) {
        assetsNeedsFollowup += 1;
      }
      // القيم المخزَّنة في قاعدة البيانات هي 'business' و'equipment'
      // و'real_estate' و'project' (انظر _toDatabaseCategory في شاشة
      // العقارات). كانت المقارنة سابقًا بـ'activity' — وهي قيمة واجهة لا
      // تُخزَّن أبدًا — فكان عدّاد الأنشطة التجارية يظهر صفرًا دائمًا.
      if (asset.category == 'business') {
        businessCount += 1;
      }
      if (asset.category == 'equipment') {
        equipmentCount += 1;
      }
      final due = _parseDdMmYyyy(asset.endDate ?? '');
      if (due != null) {
        calendarItems.add(
          HomeCalendarItem(
            title: asset.title,
            module: 'العقارات والأنشطة التجارية',
            date: due,
            sourceId: asset.id ?? '',
          ),
        );
      }
    }

    for (final reminder in savedReminders) {
      calendarItems.add(
        HomeCalendarItem(
          title: reminder.title,
          module: reminder.module,
          date: reminder.expiryDate,
          sourceId: reminder.id,
          remindBeforeDays: reminder.remindBeforeDays,
        ),
      );
    }

    for (final record in calendarRecords) {
      calendarItems.add(
        HomeCalendarItem(
          title: record.title,
          module: 'التقويم الذكي',
          date: record.date,
          sourceId: record.id,
          remindBeforeDays: record.remindBeforeDays,
          type: record.type,
          status: record.status,
          priority: record.priority,
          time: record.time,
          description: record.description,
          notes: record.notes,
          isUserCreated: true,
        ),
      );
    }

    // ===== الالتزامات المشتركة: أعداد حقيقية من shared_entries =====
    // تُطابق تمامًا منطق شاشة الالتزامات المشتركة نفسها: البند "مفتوح" ما لم
    // يكن مكتملًا أو مؤرشفًا (_isOpenItem)، و"يحتاج متابعة" يُشتق من التاريخ
    // (يستحق خلال 7 أيام أو تجاوز موعده) وليس من الحالة — لأن حالات
    // "متأخرة"/"قريبة الاستحقاق" تخص الالتزامات الشخصية ولا تُخزَّن هنا أبدًا.
    var sharedActiveTrips = 0;
    var sharedActiveCircles = 0;
    var sharedNeedsFollowup = 0;
    const sharedStatusCompleted = 'مكتملة';
    const sharedStatusArchived = 'مؤرشف';
    const sharedTypeTrip = 'الرحلة / السفر';
    const sharedTypeCircle = 'جمعية مالية';
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in sharedEntries) {
      final open =
          entry.status != sharedStatusCompleted &&
          entry.status != sharedStatusArchived;
      if (open && entry.entryType == sharedTypeTrip) {
        sharedActiveTrips += 1;
      }
      if (open && entry.entryType == sharedTypeCircle) {
        sharedActiveCircles += 1;
      }
      if (open) {
        final due = _parseDdMmYyyy(entry.dueDate);
        if (due != null && due.difference(today).inDays <= 7) {
          sharedNeedsFollowup += 1;
        }
      }

      final sharedDue = _parseDdMmYyyy(entry.dueDate);
      if (sharedDue != null) {
        calendarItems.add(
          HomeCalendarItem(
            title: entry.title.isEmpty ? entry.entryType : entry.title,
            module: 'الالتزامات المشتركة',
            date: sharedDue,
            sourceId: entry.id ?? '',
          ),
        );
      }
    }

    // ===== إدارة الأشخاص والجهات: أعداد حقيقية من التخزين المحلي =====
    var peopleCount = 0;
    var entitiesCount = 0;
    var peopleNeedsFollowup = 0;

    for (final record in peopleRecords) {
      final typeKey = (record['typeKey'] ?? '').toString();
      if (typeKey.startsWith('entity_')) {
        entitiesCount += 1;
      } else {
        peopleCount += 1;
      }
      final openTasks = (record['openTasks'] as num?)?.toInt() ?? 0;
      if (openTasks > 0) {
        peopleNeedsFollowup += 1;
      }
    }

    calendarItems.sort((a, b) => a.date.compareTo(b.date));

    return HomeDashboardMetrics(
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      totalDebts: totalDebts,
      expiringDocuments: expiringDocuments,
      commitmentsAndTasks: commitmentsAndTasks,
      totalAssets: assets.length,
      personalDebtsForYou: personalDebtsForYou,
      personalDebtsOnYou: personalDebtsOnYou,
      personalNeedsFollowup: personalNeedsFollowup,
      sharedActiveTrips: sharedActiveTrips,
      sharedActiveCircles: sharedActiveCircles,
      sharedNeedsFollowup: sharedNeedsFollowup,
      peopleCount: peopleCount,
      entitiesCount: entitiesCount,
      peopleNeedsFollowup: peopleNeedsFollowup,
      assetsCount: assets
          .where((item) => item.category == 'real_estate')
          .length,
      businessCount: businessCount,
      equipmentCount: equipmentCount,
      assetsNeedsFollowup: assetsNeedsFollowup,
      calendarItems: calendarItems,
    );
  }

  /// يقرأ سجلات الأشخاص/الجهات من نفس مخزن شاشة إدارة الأفراد.
  Future<List<Map<String, dynamic>>> _loadPeopleRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peopleStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  DateTime? _parseDdMmYyyy(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }
}
