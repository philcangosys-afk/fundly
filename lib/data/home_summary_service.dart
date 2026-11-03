import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custody_sharing.dart';
import 'delegations_repository.dart';
import 'entry_status.dart';
import 'personal_entries_repository.dart';
import 'project_assets_repository.dart';
import 'scope_catalog.dart';
import 'shared_entries_repository.dart';
import 'shared_member_state.dart';

/// عنصر موحَّد يمثّل أي سجل في التطبيق (التزام شخصي أو مشترك، شخص/جهة،
/// تفويض، عقار/نشاط/معدة) داخل الملخص الشامل والتقارير والأرشيف.
///
/// توحيد الشكل هو ما يسمح ببناء تسلسل واحد (القسم ← الأقسام المطلوبة ←
/// التصفية ← التاريخ) على بيانات حقيقية بدل أرقام مجمّعة لا تقبل التصفية.
class SummaryItem {
  const SummaryItem({
    required this.scope,
    required this.section,
    required this.type,
    required this.title,
    this.amount = 0,
    this.date,
    this.status = '',
    this.person = '',
    this.payment = '',
    this.subtitle = '',
    this.createdAt,
    this.searchText = '',
    this.followsDate = true,
    this.followDate,
    this.canBeOverdue = true,
  });

  /// القسم الرئيسي كما في قائمة [ScopeCatalog.scopes].
  final String scope;

  /// القسم الفرعي داخل القسم (مالية، مستند، وحدات، ...).
  final String section;

  /// النوع داخل القسم الفرعي (المصروفات الشخصية، إيراد، ...).
  final String type;
  final String title;
  final int amount;

  /// التاريخ المرجعي: الاستحقاق للالتزامات، نهاية العقد للأصول، الإضافة
  /// للأشخاص، نهاية التفويض للتفويضات.
  final DateTime? date;
  final String status;

  /// الشخص أو الجهة المرتبطة بالسجل (إن وُجدت).
  final String person;

  /// طريقة الدفع كما أُدخلت في تفاصيل السجل.
  final String payment;
  final String subtitle;
  final DateTime? createdAt;

  /// نص إضافي للبحث (قيم التفاصيل، الموقع...) — لا يُعرض، يُبحث فيه فقط
  /// في التقارير والأرشيف.
  final String searchText;

  /// false: التاريخ للاطلاع فقط (تاريخ إضافة الشخص، مصروف تمّ) — لا يجعل
  /// العنصر «متأخرًا» ولا «قريبًا».
  final bool followsDate;

  /// موعد المتابعة إن اختلف عن [date] (المصروف المتكرر: موعده القادم).
  final DateTime? followDate;

  /// false: مرور التاريخ يعني «منتهي» لا «متأخر» (نهاية عقد أصل، تفويض).
  final bool canBeOverdue;

  /// يوم المتابعة (بلا ساعة) — نفس ما يُحسب في صفحة القسم عند فتح العنصر.
  DateTime? get followDay {
    if (!followsDate) return null;
    final day = followDate ?? date;
    return day == null ? null : DateTime(day.year, day.month, day.day);
  }

  bool get isClosed => _closedStatuses.contains(status.trim());

  /// متأخر: فات يوم موعده (اليوم نفسه «مستحق» لا «متأخر») ولم يُغلق.
  bool get isOverdue {
    final day = followDay;
    if (!canBeOverdue || day == null || isClosed) return false;
    final now = DateTime.now();
    return day.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// قريبة الاستحقاق: خلال 7 أيام بعد اليوم — نفس تعريف صفحات الأقسام
  /// (اليوم نفسه «مستحقة»).
  bool get isDueSoon {
    final day = followDay;
    if (day == null || isClosed) return false;
    final now = DateTime.now();
    final days = day.difference(DateTime(now.year, now.month, now.day)).inDays;
    return days >= 1 && days <= 7;
  }

  static const _closedStatuses = {
    'منتهية',
    'منتهي',
    'مغلقة',
    'مكتملة',
    'مكتمل',
    'مسددة',
    'مسدد',
    'ملغاة',
    'ملغى',
    'ملغي',
    'تمت التسوية',
    'مؤرشف',
    'مجمّدة',
    'محذوف',
  };
}

class HomeSummaryService {
  HomeSummaryService({
    PersonalEntriesRepository? personalRepository,
    ProjectAssetsRepository? assetsRepository,
    SharedEntriesRepository? sharedRepository,
    DelegationsRepository? delegationsRepository,
  }) : _personalRepository =
           personalRepository ?? SupabasePersonalEntriesRepository(),
       _assetsRepository =
           assetsRepository ?? SupabaseProjectAssetsRepository(),
       _sharedRepository =
           sharedRepository ?? SupabaseSharedEntriesRepository(),
       _delegationsRepository =
           delegationsRepository ?? SupabaseDelegationsRepository();

  static const _peopleStorageKey = 'people_management_records_v1';

  final PersonalEntriesRepository _personalRepository;
  final ProjectAssetsRepository _assetsRepository;
  final SharedEntriesRepository _sharedRepository;
  final DelegationsRepository _delegationsRepository;

  /// يجمع كل السجلات الحقيقية ويحوّلها إلى عناصر موحّدة. أي مصدر يفشل
  /// يُتجاوز بصمت حتى لا يفرغ الملخص كله بسبب قسم واحد.
  Future<List<SummaryItem>> loadItems() async {
    final items = <SummaryItem>[];

    try {
      for (final entry in await _personalRepository.fetchAll()) {
        // ما في سلة المهملات لا يدخل الملخصات ولا التقارير.
        if (entry.status == 'محذوف') continue;
        // عهدة أو دين مع حساب آخر: ما أراقبه فقط أو لم أقبله بعد ليس لي —
        // كالرئيسية.
        if (entry.entryType == 'عهدة مالية' ||
            entry.entryType == 'دين / قرض / سلفة') {
          final assignment = CustodyAssignment.decode(entry.details);
          final role = assignment.roleFor(AppIdentity.id);
          if (role == CustodyRole.observer ||
              (role == CustodyRole.holder && !assignment.isAccepted)) {
            continue;
          }
        }
        final due = _parseDdMmYyyy(entry.dueDate);
        // نفس حساب صفحة الالتزامات الشخصية (entry_status): موعد المتابعة
        // (المتكرر بموعده القادم، القسط بأول قسط لم يُسدَّد، والملاحظة
        // والعهدة والدواء والمصروف غير المتكرر بلا موعد)، ونتيجته (سُدِّد
        // كامله = مكتملة، مناسبة مرّ يومها = منتهية).
        final follow = entryFollowDate(
          type: entry.entryType,
          due: due,
          details: entry.details,
        );
        final outcome = entryOutcomeStatus(
          type: entry.entryType,
          due: due,
          details: entry.details,
          total: entry.amount,
        );
        items.add(
          SummaryItem(
            followsDate: follow != null,
            followDate: follow,
            scope: ScopeCatalog.personal,
            section: ScopeCatalog.sectionForType(
              ScopeCatalog.personal,
              entry.entryType,
              fallback: entry.category,
            ),
            type: entry.entryType.isEmpty ? 'غير مصنّف' : entry.entryType,
            title: entry.title,
            amount: entry.amount,
            date: due,
            // «منتهية» لما مرّ «إلى تاريخ» — كما تظهر في صفحتها.
            status: entryFinalStatuses.contains(entry.status)
                ? entry.status
                : (outcome ??
                      entryDerivedStatus(entry.status, entry.details)),
            person: _personOf(entry.details),
            payment: entry.details['طريقة الدفع'] ?? '',
            subtitle: entry.category,
            createdAt: entry.createdAt,
            searchText: entry.details.values.join(' '),
          ),
        );
      }
    } catch (error) {
      debugPrint('HomeSummaryService personal failed: $error');
    }

    try {
      for (final entry in await _sharedRepository.fetchAll()) {
        // ما أرشفته لنفسي من الالتزامات المشتركة لا يدخل الملخص.
        if (SharedMemberState.hasMine(
          entry.details,
          SharedMemberState.archivedKey,
        )) {
          continue;
        }
        final due = _parseDdMmYyyy(entry.dueDate);
        final isTransaction = entryTransactionTypes.contains(entry.entryType);
        final next = isTransaction && due != null
            ? entryNextRepeatDate(due, entry.details)
            : null;
        items.add(
          SummaryItem(
            followsDate: !isTransaction || next != null,
            followDate: next,
            scope: ScopeCatalog.shared,
            section: ScopeCatalog.sectionForType(
              ScopeCatalog.shared,
              entry.entryType,
              fallback: entry.category,
            ),
            type: entry.entryType.isEmpty ? 'غير مصنّف' : entry.entryType,
            title: entry.title,
            amount: entry.amount,
            date: due,
            status: entry.status,
            person: _personOf(entry.details),
            payment: entry.details['طريقة الدفع'] ?? '',
            subtitle: entry.category,
            createdAt: entry.createdAt,
            searchText: entry.details.values.join(' '),
          ),
        );
      }
    } catch (error) {
      debugPrint('HomeSummaryService shared failed: $error');
    }

    try {
      for (final asset in await _assetsRepository.fetchAssets()) {
        if (asset.status == 'محذوف') continue;
        final scope = switch (asset.category) {
          'real_estate' => ScopeCatalog.realEstate,
          'business' || 'activity' => ScopeCatalog.activities,
          _ => ScopeCatalog.equipment,
        };
        items.add(
          SummaryItem(
            // نهاية العقد/الرخصة: «منتهي» بعد مرورها لا «متأخر».
            canBeOverdue: false,
            scope: scope,
            section: asset.subType.isEmpty ? 'بيانات الأصل' : asset.subType,
            type: asset.subType.isEmpty ? 'أصل' : asset.subType,
            title: asset.title,
            date: _parseAnyDate(asset.endDate),
            status: asset.status.isEmpty ? 'نشط' : asset.status,
            person: asset.tenant ?? asset.owner ?? '',
            subtitle: asset.locationOrType ?? '',
            searchText: [
              asset.owner ?? '',
              asset.tenant ?? '',
              asset.description,
              asset.serialNumber ?? '',
            ].join(' '),
          ),
        );
      }
    } catch (error) {
      debugPrint('HomeSummaryService assets failed: $error');
    }

    try {
      for (final delegation in await _delegationsRepository
          .fetchDelegations()) {
        items.add(
          SummaryItem(
            canBeOverdue: false,
            scope: ScopeCatalog.delegations,
            section: DelegationRecord.mainScopeOf(delegation.scope),
            type:
                DelegationRecord.plainPermissions(delegation.permissions).isEmpty
                ? 'بلا صلاحيات'
                : DelegationRecord.plainPermissions(
                    delegation.permissions,
                  ).first,
            title: delegation.delegateName,
            date: delegation.endDate,
            status: delegation.statusLabel,
            person: delegation.delegateName,
            subtitle: delegation.scope,
            createdAt: delegation.startDate,
          ),
        );
      }
    } catch (error) {
      debugPrint('HomeSummaryService delegations failed: $error');
    }

    try {
      for (final person in await _loadPeopleRecords()) {
        final typeKey = (person['typeKey'] ?? '').toString();
        final isEntity = typeKey.startsWith('entity_');
        final category = (person['categoryName'] ?? '').toString();
        final name = (person['fullName'] ?? '').toString();
        items.add(
          SummaryItem(
            // تاريخ الإضافة للاطلاع فقط — كل شخص كان يُعدّ «متأخرًا».
            followsDate: false,
            scope: ScopeCatalog.people,
            section: isEntity ? 'الجهات والشركات' : 'الأفراد',
            type: category.isNotEmpty ? category : (isEntity ? 'جهة' : 'فرد'),
            title: name,
            amount:
                ((person['dueToYou'] as num?)?.round() ?? 0) +
                ((person['dueOnYou'] as num?)?.round() ?? 0),
            date: _parseDdMmYyyy((person['createdAt'] ?? '').toString()),
            status: isEntity ? 'جهة' : 'فرد',
            person: name,
            subtitle: (person['roleTitle'] ?? '').toString(),
            searchText: [
              person['nickName'],
              person['phone'],
              person['email'],
              person['city'],
              person['address'],
            ].whereType<Object>().join(' '),
          ),
        );
      }
    } catch (error) {
      debugPrint('HomeSummaryService people failed: $error');
    }

    return items;
  }

  static String _personOf(Map<String, String> details) {
    for (final key in const [
      'اسم الجهة',
      'الجهة',
      'اسم المستلم',
      'اسم المفوَّض',
      'الاسم',
    ]) {
      final value = details[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Future<List<Map<String, dynamic>>> _loadPeopleRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peopleStorageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }

  static DateTime? _parseDdMmYyyy(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return _parseAnyDate(value);
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  /// ISO أو يوم/شهر/سنة — تاريخ الأصل قد يُخزَّن بأيٍّ منهما.
  static DateTime? _parseAnyDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final iso = DateTime.tryParse(value.trim());
    if (iso != null) return iso;
    final parts = value.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }
}
