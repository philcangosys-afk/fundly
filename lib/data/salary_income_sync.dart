import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'custody_sharing.dart';
import 'fundly_auth.dart';
import 'personal_entries_repository.dart';
import 'salary_receipts.dart';

/// المستلم: كل سند قبض / راتب معتمد وصله يظهر عنده في «مالية» كإيراد
/// مرتبط بالسند — مرة واحدة لكل سند (لو حذفه من هناك لا يعود).
class SalaryIncomeSync {
  SalaryIncomeSync._();

  /// مفتاح السند في تفاصيل البند (نفسه في مصروف صاحب العمل).
  static const receiptKey = 'سند القبض';

  static Future<int>? _running;

  /// يعيد عدد الإيرادات التي أُضيفت الآن.
  static Future<int> syncReceived({List<PersonalEntryRecord>? existing}) =>
      _running ??= _sync(existing).whenComplete(() => _running = null);

  static Future<int> _sync(List<PersonalEntryRecord>? existing) async {
    if (!FundlyAuth.isSignedIn) return 0;
    final me = AppIdentity.id.trim();
    final user = Supabase.instance.client.auth.currentUser;
    if (me.isEmpty || user == null) return 0;
    try {
      final approved = [
        for (final r in await SalaryReceiptsRepository().fetchSentToMe(me))
          if (r.isApproved && (r.id ?? '').isNotEmpty) r,
      ];
      if (approved.isEmpty) return 0;
      final prefs = await SharedPreferences.getInstance();
      final doneKey = 'fundly_salary_income_${user.id}';
      final done = (prefs.getStringList(doneKey) ?? const <String>[]).toSet();
      final pending = approved.where((r) => !done.contains(r.id)).toList();
      if (pending.isEmpty) return 0;
      final repo = SupabasePersonalEntriesRepository();
      final records = existing ?? await repo.fetchAll();
      final linked = {
        for (final record in records)
          if (record.entryType == 'إيراد' &&
              (record.details[receiptKey] ?? '').isNotEmpty)
            record.details[receiptKey]!,
      };
      var created = 0;
      for (final r in pending) {
        if (!linked.contains(r.id)) {
          await repo.create(incomeFor(r));
          created++;
        }
        done.add(r.id!);
      }
      await prefs.setStringList(doneKey, done.toList());
      return created;
    } catch (error) {
      debugPrint('SalaryIncomeSync failed: $error');
      return 0;
    }
  }

  /// بند الإيراد عند المستلم.
  static PersonalEntryRecord incomeFor(SalaryReceipt r) {
    String plain(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
    final from = r.ownerName.trim();
    final title = from.isEmpty ? r.title : '${r.title} — $from';
    return PersonalEntryRecord(
      category: 'financial',
      entryType: 'إيراد',
      title: title,
      amount: r.paid.round(),
      dueDate: r.receiptDate,
      status: 'نشطة',
      details: {
        'المبلغ': plain(r.paid),
        'التصنيف الرئيسي': r.isSalary ? 'الراتب/معاش' : 'سند قبض',
        if (r.isSalary) 'التصنيف الفرعي': 'الراتب',
        'التاريخ': r.receiptDate,
        'العنوان': title,
        if (r.notes.trim().isNotEmpty) 'الملاحظات': r.notes.trim(),
        if (from.isNotEmpty) 'جهة الصرف': from,
        receiptKey: r.id ?? '',
      },
    );
  }
}
