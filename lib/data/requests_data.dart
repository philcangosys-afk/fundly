import 'dart:convert';

import 'app_settings.dart';
import 'custody_sharing.dart';
import 'delegations_repository.dart';
import 'fundly_account.dart';
import 'personal_entries_repository.dart';
import 'salary_income_sync.dart';
import 'salary_receipts.dart';
import 'shared_entries_repository.dart';
import 'shared_expenses.dart';
import 'shared_member_state.dart';

/// مفاتيح مشتركة مع شاشتي الالتزامات (نفس النصوص المحفوظة في details).
const String _custodySpendsKey = 'سجل صرفيات العهدة';
const String _spendStateKey = 'حالة الاعتماد';
const String _spendPending = 'بانتظار الاعتماد';
const String _memberAcceptKey = 'قبول الأعضاء';
const String _creatorIdKey = 'معرف المنشئ';

String _stampNow() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.day}/${now.month}/${now.year} '
      '${two(now.hour)}:${two(now.minute)}';
}

/// نوع الطلب في صفحة «الطلبات».
enum RequestKind { awaitingMe, approvals, sentByMe }

/// طلب واحد في صفحة «الطلبات»: من أين، وماذا ينتظر، وأين يُفتح.
class RequestEntry {
  const RequestEntry({
    required this.kind,
    required this.source,
    required this.recordId,
    required this.title,
    required this.subtitle,
    required this.entryType,
    this.at,
  });

  final RequestKind kind;

  /// personal_entries / shared_entries / delegations
  final String source;
  final String recordId;
  final String title;
  final String subtitle;
  final String entryType;
  final DateTime? at;
}

/// الرد على الطلبات وجمعها من مصادرها الحقيقية (لا من الإشعارات وحدها).
class RequestsData {
  RequestsData._();

  /// ردود تعني أن الطلب لم يعد ينتظر ردًا: يُغلق في النافذة ولا يعود.
  static const closedMessages = <String>{
    'سبق أن رددت على هذه الدعوة',
    'لم يعد هذا الطلب قائمًا',
    'انتهت صلاحية الدعوة (24 ساعة) — اطلب من المنشئ إعادتها',
  };

  /// قبول طلب أو رفضه من نافذة «وصلك طلب جديد» مباشرة.
  /// يعيد null عند النجاح، أو رسالة توضح السبب.
  /// [signature]: توقيع الموافقة على سند قبض (خطوط JSON).
  static Future<String?> respond(
    FundlyInboxItem item,
    bool accept, {
    String signature = '',
    String name = '',
  }) async {
    final error = await _respond(
      item,
      accept,
      signature: signature,
      name: name,
    );
    // سبق الرد عليه أو لم يعد قائمًا: إشعاره لا يبقى «جديدًا» فيعود.
    if (error != null && closedMessages.contains(error)) {
      await FundlyAccount.markSeen([item.id]);
    }
    return error;
  }

  /// هل ما زال الطلب ينتظر ردي؟ ما رُد عليه (من هذا الجوال أو غيره) أو
  /// لم يعد قائمًا لا يُعرض في النافذة. عند تعذّر التحقق يُعرض كما هو.
  static Future<bool> stillAwaiting(FundlyInboxItem item) async {
    final me = AppIdentity.id;
    try {
      switch (item.source) {
        case 'personal_entries':
          final fresh = await SupabasePersonalEntriesRepository().fetchOne(
            item.recordId,
          );
          if (fresh == null) return false;
          final assignment = CustodyAssignment.decode(fresh.details);
          return assignment.isPending && assignment.holderId == me;
        case 'shared_entries':
          final fresh = await SupabaseSharedEntriesRepository().fetchOne(
            item.recordId,
          );
          if (fresh == null) return false;
          if (_acceptances(fresh.details).containsKey(me)) return false;
          return SharedMemberState.inviteState(
                fresh.details,
                me,
                createdAt: fresh.createdAt,
              ) !=
              'expired';
        default:
          return true;
      }
    } catch (_) {
      return true;
    }
  }

  static Future<String?> _respond(
    FundlyInboxItem item,
    bool accept, {
    String signature = '',
    String name = '',
  }) async {
    final me = AppIdentity.id;
    try {
      switch (item.source) {
        case 'salary_receipts':
          final error = await SalaryReceiptsRepository().respond(
            item.recordId,
            accept,
            signature: signature,
            name: name,
          );
          if (error != null) return error;
          // المعتمد يظهر عند المستلم في «مالية» كإيراد.
          if (accept) await SalaryIncomeSync.syncReceived();
        case 'personal_entries':
          final repo = SupabasePersonalEntriesRepository();
          final fresh = await repo.fetchOne(item.recordId);
          if (fresh == null) return 'لم يعد هذا الطلب قائمًا';
          final assignment = CustodyAssignment.decode(fresh.details);
          if (!assignment.isPending || assignment.holderId != me) {
            return 'لم يعد هذا الطلب قائمًا';
          }
          final updated = assignment.copyWith(
            state: accept
                ? CustodyAssignmentState.accepted
                : CustodyAssignmentState.rejected,
            holderName: accept
                ? AppSettings.instance.publicName
                : assignment.holderName,
          );
          await repo.update(
            PersonalEntryRecord(
              id: fresh.id,
              category: fresh.category,
              entryType: fresh.entryType,
              title: fresh.title,
              amount: fresh.amount,
              dueDate: fresh.dueDate,
              status: fresh.status,
              details: updated.applyTo(fresh.details)
                ..[CustodyAssignment.kRespondedAt] = _stampNow(),
              attachmentUrl: fresh.attachmentUrl,
            ),
          );
        case 'shared_entries':
          final repo = SupabaseSharedEntriesRepository();
          final fresh = await repo.fetchOne(item.recordId);
          if (fresh == null) return 'لم يعد هذا الطلب قائمًا';
          final map = _acceptances(fresh.details);
          if (map.containsKey(me)) return 'سبق أن رددت على هذه الدعوة';
          if (SharedMemberState.inviteState(
                fresh.details,
                me,
                createdAt: fresh.createdAt,
              ) ==
              'expired') {
            return 'انتهت صلاحية الدعوة (24 ساعة) — اطلب من المنشئ إعادتها';
          }
          map[me] = {
            'name': AppSettings.instance.publicName,
            'state': accept ? 'accepted' : 'rejected',
            'at': _stampNow(),
          };
          await repo.update(
            SharedEntryRecord(
              id: fresh.id,
              entryType: fresh.entryType,
              title: fresh.title,
              amount: fresh.amount,
              dueDate: fresh.dueDate,
              status: fresh.status,
              details: Map<String, String>.of(fresh.details)
                ..[_memberAcceptKey] = jsonEncode(map),
            ),
            planExempt: true,
          );
        case 'delegations':
          final repo = SupabaseDelegationsRepository();
          final rows = await repo.fetchDelegations(includeIncoming: true);
          DelegationRecord? found;
          for (final row in rows) {
            if (row.id == item.recordId) found = row;
          }
          if (found == null) return 'لم يعد هذا الطلب قائمًا';
          await repo.respondIncoming(found, accept);
        default:
          return 'افتح القسم للرد على هذا الطلب';
      }
      await FundlyAccount.markSeen([item.id]);
      return null;
    } catch (_) {
      return 'تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.';
    }
  }

  static Map<String, Map<String, String>> _acceptances(
    Map<String, String> details,
  ) {
    try {
      final decoded = jsonDecode(details[_memberAcceptKey] ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map)
            '${entry.key}': (entry.value as Map).map(
              (k, v) => MapEntry('$k', '$v'),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  /// تفاصيل الطلب للعرض فقط قبل القبول أو الرفض.
  static Future<List<(String, String)>> details(FundlyInboxItem item) async {
    final rows = <(String, String)>[
      ('المرسل', item.sender),
      if (item.senderFnd.isNotEmpty) ('الرقم التعريفي', item.senderFnd),
      ('النوع', item.entryType),
      if (item.title.trim().isNotEmpty) ('العنوان', item.title),
    ];
    try {
      Map<String, String> data = const {};
      int amount = 0;
      String due = '';
      switch (item.source) {
        case 'salary_receipts':
          final s = await SalaryReceiptsRepository().fetchOne(item.recordId);
          if (s != null) {
            String m(double v) =>
                '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)} ${s.currency}';
            if (s.isSalary) rows.add(('الشهر', s.periodLabel));
            if (s.isSalary) {
              rows.add(('الراتب الأساسي', m(s.basic)));
              if (s.allowances > 0) rows.add(('العلاوات', m(s.allowances)));
              if (s.overtime > 0) rows.add(('العمل الإضافي', m(s.overtime)));
              if (s.loan > 0) rows.add(('السلفة', m(s.loan)));
              if (s.deductions > 0) rows.add(('الخصومات', m(s.deductions)));
              rows.add(('المجموع', m(s.total)));
            }
            rows.add(('المبلغ المدفوع', m(s.paid)));
            rows.add(('التاريخ', s.receiptDate));
            if (s.notes.isNotEmpty) rows.add(('ملاحظات', s.notes));
            rows.add(('الحالة', s.status));
          }
        case 'personal_entries':
          final fresh = await SupabasePersonalEntriesRepository().fetchOne(
            item.recordId,
          );
          if (fresh != null) {
            data = fresh.details;
            amount = fresh.amount;
            due = fresh.dueDate;
          }
        case 'shared_entries':
          final fresh = await SupabaseSharedEntriesRepository().fetchOne(
            item.recordId,
          );
          if (fresh != null) {
            data = fresh.details;
            amount = fresh.amount;
            due = fresh.dueDate;
          }
        case 'delegations':
          final all = await SupabaseDelegationsRepository().fetchDelegations(
            includeIncoming: true,
          );
          for (final d in all) {
            if (d.id != item.recordId) continue;
            rows.add(('النطاق', d.scope));
            final plain = DelegationRecord.plainPermissions(d.permissions);
            if (plain.isNotEmpty) rows.add(('الصلاحيات', plain.join('، ')));
            String day(DateTime? x) =>
                x == null ? '' : '${x.day}/${x.month}/${x.year}';
            if (d.startDate != null) rows.add(('من', day(d.startDate)));
            rows.add(('إلى', d.endDate == null ? 'مفتوح' : day(d.endDate)));
            if ((d.notes ?? '').trim().isNotEmpty) {
              rows.add(('ملاحظات', d.notes!.trim()));
            }
          }
      }
      if (amount != 0) {
        rows.add(('المبلغ', '$amount ${AppSettings.currencySuffix}'));
      }
      if (due.trim().isNotEmpty) rows.add(('التاريخ', due.trim()));
      for (final entry in data.entries) {
        final key = entry.key.trim();
        final value = entry.value.trim();
        if (value.isEmpty || key.isEmpty) continue;
        // مفاتيح داخلية وسجلات JSON لا تُعرض.
        if (key.startsWith('عهدة_') || key.startsWith('_')) continue;
        if (value.startsWith('[') || value.startsWith('{')) continue;
        if (value.length > 160) continue;
        if (rows.any((r) => r.$1 == key)) continue;
        rows.add((key, value));
      }
    } catch (_) {
      // بلا اتصال: تُعرض بيانات الإشعار وحدها.
    }
    return rows;
  }

  /// كل الطلبات القائمة الآن: ما ينتظر ردي، وما ينتظر اعتمادي، وما أرسلته.
  static Future<List<RequestEntry>> load() async {
    final me = AppIdentity.id;
    final out = <RequestEntry>[];
    if (me.isEmpty) return out;
    try {
      final personal = await SupabasePersonalEntriesRepository().fetchAll();
      for (final r in personal) {
        if (r.id == null) continue;
        final a = CustodyAssignment.decode(r.details);
        final custody = r.entryType == 'عهدة مالية';
        if (a.isPending && a.holderId == me) {
          final from = a.ownerName.isNotEmpty ? a.ownerName : a.ownerId;
          out.add(
            RequestEntry(
              kind: RequestKind.awaitingMe,
              source: 'personal_entries',
              recordId: r.id!,
              title: r.title,
              entryType: r.entryType,
              subtitle: custody
                  ? 'أسند إليك $from عهدة مالية'
                  : 'أرسل إليك $from ${r.entryType}',
              at: r.createdAt,
            ),
          );
        } else if (a.isPending && a.ownerId == me) {
          final to = a.holderName.isNotEmpty ? a.holderName : a.holderId;
          out.add(
            RequestEntry(
              kind: RequestKind.sentByMe,
              source: 'personal_entries',
              recordId: r.id!,
              title: r.title,
              entryType: r.entryType,
              subtitle: 'بانتظار الموافقة من $to',
              at: r.createdAt,
            ),
          );
        }
        if (custody && a.ownerId == me) {
          final pending = _pendingSpends(r.details);
          if (pending > 0) {
            out.add(
              RequestEntry(
                kind: RequestKind.approvals,
                source: 'personal_entries',
                recordId: r.id!,
                title: r.title,
                entryType: r.entryType,
                subtitle: 'مصروفات بانتظار اعتمادك: $pending',
                at: r.createdAt,
              ),
            );
          }
        }
      }
    } catch (_) {}
    try {
      final shared = await SupabaseSharedEntriesRepository().fetchAll();
      for (final r in shared) {
        if (r.id == null) continue;
        final creator = (r.details[_creatorIdKey] ?? '').trim();
        final answered = _acceptances(r.details);
        final invited = r.details.entries.any(
          (e) => e.key != _memberAcceptKey && e.value.contains(me),
        );
        if (creator.isNotEmpty &&
            creator != me &&
            invited &&
            !answered.containsKey(me) &&
            SharedMemberState.inviteState(
                  r.details,
                  me,
                  createdAt: r.createdAt,
                ) ==
                'pending') {
          out.add(
            RequestEntry(
              kind: RequestKind.awaitingMe,
              source: 'shared_entries',
              recordId: r.id!,
              title: r.title,
              entryType: r.entryType,
              subtitle: 'دعوة للمشاركة في ${r.entryType}',
              at: r.createdAt,
            ),
          );
        }
        if (creator == me) {
          final pending = SharedLedger.pendingCount(r.details);
          if (pending > 0) {
            out.add(
              RequestEntry(
                kind: RequestKind.approvals,
                source: 'shared_entries',
                recordId: r.id!,
                title: r.title,
                entryType: r.entryType,
                subtitle: 'طلبات بانتظار موافقتك: $pending',
                at: r.createdAt,
              ),
            );
          }
        }
      }
    } catch (_) {}
    // سندات القبض: ما ينتظر توقيعي، وما أرسلته بانتظار اعتماد الموظف.
    try {
      final salary = SalaryReceiptsRepository();
      for (final s in await salary.fetchSentToMe(me)) {
        if (!s.isPending || s.id == null) continue;
        out.add(
          RequestEntry(
            kind: RequestKind.awaitingMe,
            source: 'salary_receipts',
            recordId: s.id!,
            title: s.title,
            entryType: s.isSalary ? 'سند قبض راتب' : 'سند قبض',
            subtitle: 'أرسل إليك ${s.ownerName} سند قبض للاعتماد والتوقيع',
            at: s.createdAt,
          ),
        );
      }
      for (final s in await salary.fetchMine()) {
        if (!s.isPending || s.id == null) continue;
        out.add(
          RequestEntry(
            kind: RequestKind.sentByMe,
            source: 'salary_receipts',
            recordId: s.id!,
            title: s.title,
            entryType: s.isSalary ? 'سند قبض راتب' : 'سند قبض',
            subtitle: 'بانتظار اعتماد ${s.employeeName}',
            at: s.createdAt,
          ),
        );
      }
    } catch (_) {}
    try {
      final delegations = await SupabaseDelegationsRepository()
          .fetchDelegations(includeIncoming: true);
      for (final d in delegations) {
        if (d.id == null || !d.isIncoming) continue;
        final answer = DelegationRecord.acceptOf(d.permissions);
        if (answer == 'accepted' || answer == 'rejected') continue;
        final owner = DelegationRecord.ownerNameOf(d.permissions);
        out.add(
          RequestEntry(
            kind: RequestKind.awaitingMe,
            source: 'delegations',
            recordId: d.id!,
            title: d.scope,
            entryType: 'تفويض',
            subtitle: owner.isEmpty ? 'تفويض وصلك' : 'فوّضك $owner',
            at: d.startDate,
          ),
        );
      }
    } catch (_) {}
    // الأحدث أولًا.
    out.sort(
      (a, b) => (b.at ?? DateTime(1970)).compareTo(a.at ?? DateTime(1970)),
    );
    return out;
  }

  static int _pendingSpends(Map<String, String> details) {
    try {
      final decoded = jsonDecode(details[_custodySpendsKey] ?? '[]');
      if (decoded is! List) return 0;
      return decoded
          .whereType<Map>()
          .where((row) => '${row[_spendStateKey] ?? ''}' == _spendPending)
          .length;
    } catch (_) {
      return 0;
    }
  }
}
