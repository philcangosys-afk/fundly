import 'dart:convert';

import 'package:fundly/data/personal_entries_repository.dart';
import 'package:fundly/data/project_assets_repository.dart';
import 'package:fundly/data/shared_entries_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_reminders_store.dart';
import 'reminder_lead.dart';
import 'custody_sharing.dart';
import 'shared_member_state.dart';
import 'delegations_repository.dart';
import 'calendar_items_store.dart';
import 'shared_alerts.dart';

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

  /// لكل قسم في الرئيسية: أمور مالية تحتاج متابعة، ومستندات تحتاج متابعة
  /// (منتهية أو تنتهي خلال 30 يومًا).
  final int personalMoneyFollowup;
  final int personalDocsFollowup;
  final int sharedMoneyFollowup;
  final int sharedDocsFollowup;
  final int peopleMoneyFollowup;
  final int peopleDocsFollowup;
  final int assetsMoneyFollowup;
  final int assetsDocsFollowup;

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
    this.personalMoneyFollowup = 0,
    this.personalDocsFollowup = 0,
    this.sharedMoneyFollowup = 0,
    this.sharedDocsFollowup = 0,
    this.peopleMoneyFollowup = 0,
    this.peopleDocsFollowup = 0,
    this.assetsMoneyFollowup = 0,
    this.assetsDocsFollowup = 0,
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
      calendarItems = const [],
      personalMoneyFollowup = 0,
      personalDocsFollowup = 0,
      sharedMoneyFollowup = 0,
      sharedDocsFollowup = 0,
      peopleMoneyFollowup = 0,
      peopleDocsFollowup = 0,
      assetsMoneyFollowup = 0,
      assetsDocsFollowup = 0;
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
    // القيمة السالبة تعني "لم تُحدَّد مدة تذكير لهذا العنصر" فتُستعمل
    // المدة الافتراضية من الإعدادات. كانت القيمة 7 ثابتة، فيبقى إعداد
    // "وقت التذكير الافتراضي" بلا أثر مهما غيّره المستخدم. ولا تصلح 0
    // للتمييز لأنها اختيار حقيقي متاح للمستخدم: "في نفس اليوم".
    this.remindBeforeDays = -1,
    this.type = 'موعد',
    this.status = 'قادمة',
    this.priority = 'متوسطة',
    this.time = '',
    this.description = '',
    this.notes = '',
    this.isUserCreated = false,
    this.isExpiry = false,
    this.entryType = '',
    this.repeat = '',
    this.leadMinutes = -1,
  });

  /// تذكير قبل الموعد بالدقائق (من «وقت التذكير»: قبل ساعة، قبل يوم...).
  final int leadMinutes;

  /// تكرار البند (يومي، أسبوعي، شهري...) — لجدولة إشعاره القادم.
  final String repeat;

  /// نوع السجل الأصلي (دين، قسط، اشتراك، مهمة...) — عليه يُقرَّر هل يبقى
  /// التنبيه بعد فوات الموعد.
  final String entryType;

  final int remindBeforeDays;
  final String type;
  final String status;
  final String priority;
  final String time;
  final String description;
  final String notes;
  final bool isUserCreated;

  /// تنبيه انتهاء صلاحية (مستند، ضمان، عقد، رخصة) — يميّزه مفتاح
  /// "تنبيهات انتهاء المستندات والعقود" في الإعدادات.
  final bool isExpiry;
}

class HomeDashboardService {
  /// «بدون تذكير» صراحةً — يختلف عن -1 (استعمل المدة الافتراضية).
  static const int noReminder = -2;

  /// حالات منتهية لا تُنبَّه ولا تُحسب مفتوحة.
  static const Set<String> closedStatuses = {
    'مكتملة',
    'مكتمل',
    'مؤرشف',
    'ملغاة',
    'ملغى',
    'محذوف',
    'تمت التسوية',
    'مسددة',
  };

  /// هل حان تنبيه هذا البند اليوم؟ مصدر واحد للنقطة الحمراء ومركز التنبيهات:
  /// من بداية نافذة التذكير، ويبقى ما فات موعده ولم يُغلق 30 يومًا.
  static bool isAlertDue(
    HomeCalendarItem item, {
    required DateTime today,
    required int defaultLead,
    required bool expiryEnabled,
  }) {
    if (!expiryEnabled && item.isExpiry) return false;
    if (item.remindBeforeDays == noReminder) return false;
    if (closedStatuses.contains(item.status.trim())) return false;
    final day = DateTime(today.year, today.month, today.day);
    final due = DateTime(item.date.year, item.date.month, item.date.day);
    final lead = item.remindBeforeDays >= 0 ? item.remindBeforeDays : defaultLead;
    final from = due.subtract(Duration(days: lead));
    // ما يبقى قائمًا بعد موعده (دين لم يُسدَّد، قسط، اشتراك، مستند منتهٍ،
    // مهمة لم تُنجز) يبقى تنبيهًا 30 يومًا. والموعد أو المناسبة أو الدواء
    // ينتهي تنبيهه بانتهاء يومه.
    const lingering = {
      'دين / قرض / سلفة',
      'ديون',
      'قسط',
      'اشتراك',
      'اشتراكات',
      'المصروفات الشخصية',
      'غرامة',
      'عهدة مالية',
      'مهمة',
    };
    final keep = item.isExpiry ||
        lingering.contains(item.entryType) ||
        lingering.contains(item.type) ||
        item.module == 'الالتزامات المشتركة';
    final until = keep ? due.add(const Duration(days: 30)) : due;
    return !day.isBefore(from) && !day.isAfter(until);
  }

  static DateTime _addMonthsClamped(DateTime date, int months) {
    final total = date.month - 1 + months;
    final year = date.year + total ~/ 12;
    final month = total % 12 + 1;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day > last ? last : date.day);
  }

  /// الموعد القادم لبند متكرر (شهري، سنوي...) — يُحسب من التاريخ الأصلي
  /// كل مرة حتى لا يزحف 31 ← 28 ← 28. غير المتكرر يبقى كما هو.
  static DateTime nextOccurrence(DateTime due, String repeat, DateTime today) {
    final r = repeat.trim();
    final months = switch (r) {
      'شهري' || 'شهريًا' => 1,
      'ربع سنوي' || 'كل 3 شهور' => 3,
      'نصف سنوي' || 'كل 6 شهور' => 6,
      'سنوي' || 'سنويًا' => 12,
      _ => 0,
    };
    final days = switch (r) {
      'يومي' || 'يوميًا' => 1,
      'أسبوعي' || 'أسبوعيًا' => 7,
      _ => 0,
    };
    if (months == 0 && days == 0) return due;
    final day = DateTime(today.year, today.month, today.day);
    var next = due;
    for (var i = 1; next.isBefore(day) && i < 5000; i++) {
      next = months > 0
          ? _addMonthsClamped(due, months * i)
          : DateTime(due.year, due.month, due.day + days * i);
    }
    return next;
  }

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
    List<DelegationRecord> delegations = const [];

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

    try {
      delegations = await SupabaseDelegationsRepository().fetchDelegations();
    } catch (error) {
      debugPrint('HomeDashboardService delegations fetch failed: $error');
    }

    var totalIncome = 0;
    var totalExpenses = 0;
    var totalDebts = 0;
    var expiringDocuments = 0;
    var commitmentsAndTasks = 0;
    var personalDebtsForYou = 0;
    var personalDebtsOnYou = 0;
    var personalNeedsFollowup = 0;
    var personalMoneyFollowup = 0;
    var personalDocsFollowup = 0;

    final now = DateTime.now();
    final in30Days = now.add(const Duration(days: 30));

    final calendarItems = <HomeCalendarItem>[];

    final today = DateTime(now.year, now.month, now.day);
    final myId = AppIdentity.id;
    for (final entry in personalEntries) {
      // المحذوف (في السلة) لا يدخل أي رقم.
      if (entry.status == 'محذوف') continue;
      final cancelled = entry.status == 'ملغاة' || entry.status == 'ملغى';
      final closed = closedStatuses.contains(entry.status);
      final amount = cancelled ? 0 : entry.amount;
      final due = _parseDdMmYyyy(entry.dueDate);
      // عهدة أو دين مع حساب آخر: يُقرأ من جهتي، وما لم أقبله لا يُحسب.
      var flipDebt = false;
      if (entry.entryType == 'عهدة مالية' ||
          entry.entryType == 'دين / قرض / سلفة') {
        final assignment = CustodyAssignment.decode(entry.details);
        final role = assignment.roleFor(myId);
        if (role == CustodyRole.observer ||
            (role == CustodyRole.holder && !assignment.isAccepted)) {
          continue;
        }
        flipDebt = role == CustodyRole.holder;
      }

      if (entry.entryType == 'إيراد' || entry.entryType == 'دخل') {
        totalIncome += amount;
      }
      // 'مصروف' اسم قديم لنفس النوع قبل توحيد المسميات مع ملف الإدخالات.
      if (entry.entryType == 'المصروفات الشخصية' ||
          entry.entryType == 'مصروف' ||
          entry.entryType == 'غرامة' ||
          entry.entryType == 'قسط') {
        totalExpenses += amount;
      }
      if ((entry.entryType == 'دين / قرض / سلفة' ||
              entry.entryType == 'ديون') &&
          !closed) {
        totalDebts += amount;
        final debtDirection =
            entry.details['نوع الدين'] ?? entry.details['الاتجاه'] ?? '';
        final forOwner = debtDirection.contains('يدين لي') ||
            debtDirection.trim().startsWith('لي');
        if (forOwner != flipDebt) {
          personalDebtsForYou += amount;
        } else {
          personalDebtsOnYou += amount;
        }
      }

      if ((entry.entryType == 'مستند' || entry.entryType == 'ضمانات') &&
          due != null) {
        // يوم الانتهاء نفسه ضمن «قريب الانتهاء» (المقارنة بالتاريخ لا بالساعة).
        if (!due.isBefore(today) && !due.isAfter(in30Days)) {
          expiringDocuments += 1;
        }
      }

      if (!closed) {
        commitmentsAndTasks += 1;
      }

      // يحتاج متابعة: موعده خلال 7 أيام أو فات — يُحسب من التاريخ، لأن
      // الحالة المخزّنة تبقى «نشطة» ولا تتحوّل وحدها إلى «متأخرة».
      final needsFollowup =
          !closed && due != null && due.difference(today).inDays <= 7;
      if (needsFollowup) personalNeedsFollowup += 1;
      final isDocument =
          entry.entryType == 'مستند' || entry.entryType == 'ضمانات';
      if (isDocument) {
        if (!closed && due != null && due.isBefore(in30Days)) {
          personalDocsFollowup += 1;
        }
      } else if (needsFollowup) {
        personalMoneyFollowup += 1;
      }

      if (due != null && !closed) {
        // البند المتكرر (اشتراك شهري مثلًا): التنبيه على موعده القادم.
        final repeat = (entry.details['التكرار'] ?? '').trim();
        final recurring = repeat.isNotEmpty &&
            entry.entryType != 'قسط' &&
            entry.entryType != 'دين / قرض / سلفة';
        calendarItems.add(
          HomeCalendarItem(
            title: entry.title.isEmpty ? entry.entryType : entry.title,
            module: 'الالتزامات الشخصية',
            date: recurring ? nextOccurrence(due, repeat, today) : due,
            sourceId: entry.id ?? '',
            status: entry.status,
            entryType: entry.entryType,
            time: _entryTimeOf(entry.details),
            repeat: recurring ? repeat : '',
            leadMinutes: _leadMinutesOf(entry.details),
            isExpiry:
                entry.entryType == 'مستند' || entry.entryType == 'ضمانات',
            remindBeforeDays: () {
              final days = _reminderDaysOf(entry.details);
              final lead = _leadMinutesOf(entry.details);
              // تذكير بالساعات: يظهر في التنبيهات من اليوم الذي يقع فيه.
              if (days == -1 && lead > 0) return (lead + 1439) ~/ 1440;
              return days;
            }(),
          ),
        );
      }
    }

    var assetsNeedsFollowup = 0;
    var businessCount = 0;
    var equipmentCount = 0;

    var assetsDocsFollowup = 0;
    for (final asset in assets) {
      if (asset.needsAttention) {
        assetsNeedsFollowup += 1;
      }
      // انتهاء العقد/الرخصة خلال 30 يومًا = مستند يحتاج متابعة.
      final assetEnd = _parseDdMmYyyy(asset.endDate ?? '');
      if (assetEnd != null && assetEnd.isBefore(in30Days)) {
        assetsDocsFollowup += 1;
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
            // تاريخ نهاية العقد/الرخصة = تنبيه انتهاء صلاحية.
            isExpiry: true,
          ),
        );
      }
    }

    const assetModules = {
      'العقارات والأنشطة التجارية',
      'الأنشطة التجارية',
      'العقارات',
      'المركبات ووسائل النقل',
    };
    for (final reminder in savedReminders) {
      if (assetModules.contains(reminder.module) &&
          reminder.expiryDate.isBefore(in30Days)) {
        assetsDocsFollowup += 1;
      }
      calendarItems.add(
        HomeCalendarItem(
          title: reminder.title,
          module: reminder.module,
          date: reminder.expiryDate,
          sourceId: reminder.id,
          remindBeforeDays: reminder.remindBeforeDays,
          // نوع التذكير المحفوظ لتصنيفه في الكلندر (لا يغيّر استحقاقه).
          entryType: _savedReminderKind(reminder),
        ),
      );
    }

    // انتهاء التفويض: يظهر في مركز التنبيهات والكلندر قبل أسبوع من نهايته.
    for (final delegation in delegations) {
      final end = delegation.endDate;
      if (end == null || delegation.isPaused || delegation.isEnded) continue;
      final received = (delegation.delegateRef ?? '').startsWith(
        'dir:received',
      );
      calendarItems.add(
        HomeCalendarItem(
          title: received
              ? 'ينتهي تفويض ${delegation.delegateName} لك'
              : 'ينتهي تفويض ${delegation.delegateName}',
          module: 'التفويضات',
          date: end,
          sourceId: 'delegation-${delegation.id ?? delegation.delegateName}',
          remindBeforeDays: 7,
          type: 'تفويض',
          description: delegation.scope,
          isExpiry: true,
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
    var sharedDocsFollowup = 0;
    const sharedStatusCompleted = 'مكتملة';
    const sharedStatusArchived = 'مؤرشف';
    const sharedTypeTrip = 'الرحلة / السفر';
    const sharedTypeCircle = 'جمعية مالية';

    for (final entry in sharedEntries) {
      final open =
          entry.status != sharedStatusCompleted &&
          entry.status != sharedStatusArchived &&
          entry.status != 'ملغاة' &&
          !SharedMemberState.hasMine(
            entry.details,
            SharedMemberState.archivedKey,
          );
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

      final docEnd = _parseDdMmYyyy(
        entry.details['تاريخ انتهاء المستند'] ?? '',
      );
      if (docEnd != null && docEnd.isBefore(in30Days)) sharedDocsFollowup += 1;
      final sharedDue = _parseDdMmYyyy(entry.dueDate);
      // بنود المتابعة والمستندات ودورة الجمعية والاعتمادات والميزانية.
      if (open) calendarItems.addAll(sharedAlertItems(entry));
      if (sharedDue != null && open) {
        calendarItems.add(
          HomeCalendarItem(
            title: entry.title.isEmpty ? entry.entryType : entry.title,
            module: 'الالتزامات المشتركة',
            date: sharedDue,
            sourceId: entry.id ?? '',
            status: entry.status,
            // موعد الالتزام نفسه (الرحلة، المشاركة...) — لتصنيفه في الكلندر.
            entryType: entry.entryType,
            remindBeforeDays: _reminderDaysOf(entry.details),
          ),
        );
      }
    }

    // ===== إدارة الأشخاص والجهات: أعداد حقيقية من التخزين المحلي =====
    var peopleCount = 0;
    var entitiesCount = 0;
    var peopleNeedsFollowup = 0;
    var peopleDocsFollowup = 0;

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
      final details = record['details'];
      if (details is Map) {
        final expiring = details.entries.any((entry) {
          if (!'${entry.key}'.startsWith('انتهاء ')) return false;
          final date = _parseDdMmYyyy('${entry.value ?? ''}');
          return date != null && date.isBefore(in30Days);
        });
        if (expiring) peopleDocsFollowup += 1;
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
      personalMoneyFollowup: personalMoneyFollowup,
      personalDocsFollowup: personalDocsFollowup,
      sharedMoneyFollowup: sharedNeedsFollowup,
      sharedDocsFollowup: sharedDocsFollowup,
      peopleMoneyFollowup: peopleNeedsFollowup,
      peopleDocsFollowup: peopleDocsFollowup,
      assetsMoneyFollowup: assetsNeedsFollowup,
      assetsDocsFollowup: assetsDocsFollowup,
    );
  }

  /// تصنيف التذكير المحفوظ: تنبيه صرف العهدة، أو استحقاق دفعة، أو بند
  /// متابعة، وإلا فهو انتهاء صلاحية (مستند، عقد، رخصة...).
  static String _savedReminderKind(AppReminder reminder) {
    if (reminder.id.startsWith('custody_percent_')) {
      return sharedBudgetAlertType;
    }
    final title = reminder.title.trim();
    if (title.startsWith('استحقاق')) return 'استحقاق';
    for (final kind in const ['مهمة', 'موعد', 'عادة', 'تذكير', 'ملاحظات']) {
      if (title.startsWith(kind)) return kind;
    }
    if (title.startsWith('ملاحظة')) return 'ملاحظات';
    return 'انتهاء';
  }

  /// ساعة البند: «الوقت»؛ و«وقت التذكير» القديم إن كان ساعة (18:06).
  static String _entryTimeOf(Map<String, String> details) {
    final reminder = (details['وقت التذكير'] ?? '').trim();
    if ((details['تفعيل تذكير'] ?? '').trim() == 'نعم' &&
        RegExp(r'^\d{1,2}:\d{2}').hasMatch(reminder)) {
      return reminder;
    }
    return (details['الوقت'] ?? '').trim();
  }

  /// «وقت التذكير» بالدقائق قبل الموعد — حين يكون التذكير مفعّلًا.
  static int _leadMinutesOf(Map<String, String> details) {
    if ((details['تفعيل تذكير'] ?? '').trim() != 'نعم') return -1;
    return reminderLeadMinutes(details['وقت التذكير'] ?? '');
  }

  /// أيام التذكير من حقل التذكير في السجل (قبل يوم/أسبوع/أسبوعين/مخصص).
  static int _reminderDaysOf(Map<String, String> details) {
    const keys = ['التذكير قبل الانتهاء', 'تذكيرات', 'تذكير', 'التذكيرات'];
    for (final key in keys) {
      var raw = (details[key] ?? '').trim();
      if (raw.isEmpty) continue;
      if (raw.contains('بدون')) return noReminder;
      const arabic = '٠١٢٣٤٥٦٧٨٩';
      for (var i = 0; i < arabic.length; i++) {
        raw = raw.replaceAll(arabic[i], '$i');
      }
      final known = AppRemindersStore.reminderDaysFromLabel(raw);
      if (known > 0) return known;
      if (raw.contains('يومين')) return 2;
      if (raw.contains('شهرين')) return 60;
      final number = int.tryParse(RegExp(r'\d+').firstMatch(raw)?.group(0) ?? '');
      final unit = raw.contains('شهر')
          ? 30
          : (raw.contains('أسبوع') || raw.contains('اسبوع'))
          ? 7
          : 1;
      if (number != null) return number * unit;
      if (raw.contains('شهر')) return 30;
    }
    return -1;
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

  /// تاريخ بأي صيغة مخزّنة: يوم/شهر/سنة، أو سنة-شهر-يوم (ومعه وقت)،
  /// وبالأرقام العربية. التاريخ غير الصحيح (31/2) يُرفض بدل أن ينزلق.
  DateTime? _parseDdMmYyyy(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabic[i], '$i');
    }
    final parts = value.split(RegExp(r'[/\-]'));
    if (parts.length < 3) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2].split(RegExp(r'[ T]')).first);
    if (a == null || b == null || c == null) return null;
    final (year, month, day) = parts[0].length == 4 ? (a, b, c) : (c, b, a);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
