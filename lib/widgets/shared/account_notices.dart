import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/custody_sharing.dart';
import '../../data/fundly_account.dart';
import '../../data/people_directory_store.dart';
import '../../data/requests_data.dart';
import '../../data/shared_entries_repository.dart';
import '../../data/shared_member_state.dart';
import '../../data/shared_alerts.dart';
import '../../data/shared_expenses.dart';
import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';
import 'signature_pad.dart';
import '../../data/salary_receipts.dart';

/// تنبيهات الحساب عند فتح التطبيق:
/// 1) أول دخول لكل حساب: رقمك التعريفي وأين تجده («المزيد»).
/// 2) ما وصلك من حسابات أخرى (عهدة، دعوة رحلة أو مشاركة...) في نافذة
///    واضحة، مع زر يفتح القسم الذي فيه القبول أو الرفض.
class AccountNotices {
  AccountNotices._();

  static bool _showing = false;

  /// ما عُرض في النافذة خلال هذا التشغيل: لا تعود النافذة لنفس الطلبات كل
  /// فحص (كل 30 ثانية) أو عند الرجوع للتطبيق — تبقى في «الطلبات» ومركز
  /// المتابعة حتى يُرد عليها، وتظهر النافذة فقط لما يصل جديدًا.
  static final Set<String> _presented = <String>{};

  /// معرّفات الردود والإضافات التي عُرضت (للاطلاع فقط) — لا تُعرض ثانية.
  static const _shownInfoKey = 'fundly_inbox_shown_info_v1';

  /// الطلبات (دعوات، تفويض، رحلة...) التي عُرضت في النافذة مرة — لا تعود
  /// النافذة لها مع كل فتح للتطبيق؛ تبقى في «الطلبات» ومركز المتابعة حتى
  /// يُرد عليها.
  static const _shownInvitesKey = 'fundly_inbox_shown_invites_v1';

  /// [onOpen] يفتح القسم حسب مصدر الطلب (personal_entries / shared_entries
  /// / delegations) ونوعه.
  static Future<void> show(
    BuildContext context, {
    required void Function(String source, String entryType) onOpen,
  }) async {
    if (_showing) return;
    _showing = true;
    try {
      if (await FundlyAccount.takeIdNotice()) {
        if (!context.mounted) return;
        await _idNotice(context);
      }
      final all = await FundlyAccount.pendingInbox();
      // من قبِل ما أرسلته يُضاف إلى «الأفراد والجهات» فورًا.
      await _addAcceptedPeople(all);
      // الردود والإضافات للاطلاع فقط: تظهر مرة واحدة ثم لا تعود. ما عُرض
      // منها يُحفظ في الجوال أيضًا، فلا يعود ولو تعذّر تعليمه في الخادم.
      final prefs = await SharedPreferences.getInstance();
      final shownInfo =
          (prefs.getStringList(_shownInfoKey) ?? const <String>[]).toSet();
      final stale = [
        for (final item in all)
          if (item.isInfo && shownInfo.contains(item.id)) item.id,
      ];
      if (stale.isNotEmpty) await FundlyAccount.markSeen(stale);
      final shownInvites =
          (prefs.getStringList(_shownInvitesKey) ?? const <String>[]).toSet();
      final items = [
        for (final item in all)
          if (!_presented.contains(item.id) &&
              !(item.isInfo && shownInfo.contains(item.id)) &&
              !(!item.isInfo && shownInvites.contains(item.id)))
            item,
      ];
      // ما رُد عليه من قبل (من هذا الجوال أو غيره) أو لم يعد قائمًا لا
      // يُعرض، ويُعلَّم في الخادم فلا يعود.
      final answered = <FundlyInboxItem>[];
      for (final item in items) {
        if (item.isInfo || item.isHideNotice) continue;
        if (!await RequestsData.stillAwaiting(item)) answered.add(item);
      }
      if (answered.isNotEmpty) {
        _presented.addAll(answered.map((i) => i.id));
        await FundlyAccount.markSeen([for (final i in answered) i.id]);
        items.removeWhere(answered.contains);
      }
      if (items.isEmpty || !context.mounted) return;
      _presented.addAll(items.map((i) => i.id));
      final inviteIds = [
        for (final item in items)
          if (!item.isInfo) item.id,
      ];
      if (inviteIds.isNotEmpty) {
        final kept = [...shownInvites, ...inviteIds];
        await prefs.setStringList(
          _shownInvitesKey,
          kept.length > 300 ? kept.sublist(kept.length - 300) : kept,
        );
        // النافذة تعرض الطلب مرة واحدة في كل الأجهزة: يُعلَّم في الخادم
        // فور عرضه، ويبقى في «الطلبات» ومركز المتابعة حتى يُرد عليه.
        await FundlyAccount.markSeen([
          for (final item in items)
            if (!item.isInfo && !item.isHideNotice) item.id,
        ]);
      }
      final infoIds = [
        for (final item in items)
          if (item.isInfo) item.id,
      ];
      if (infoIds.isNotEmpty) {
        await FundlyAccount.markSeen(infoIds);
        final kept = [...shownInfo, ...infoIds];
        await prefs.setStringList(
          _shownInfoKey,
          kept.length > 300 ? kept.sublist(kept.length - 300) : kept,
        );
      }
      if (!context.mounted) return;
      final opened = await _inboxDialog(context, items);
      if (opened != null) onOpen(opened.source, opened.entryType);
    } finally {
      _showing = false;
    }
  }

  static Future<void> _idNotice(BuildContext context) {
    final id = AppIdentity.id;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: AppTheme.page,
          icon: const Icon(
            Icons.badge_outlined,
            size: 34,
            color: AppTheme.brandMid,
          ),
          title: const Text('رقمك التعريفي', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    id,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'شارِك هذا الرقم ليرسل لك الآخرون عهدة مالية أو دعوة '
                'مشاركة أو رحلة. تجده دائمًا في «المزيد» أعلى الصفحة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('نسخ الرقم'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.brand),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      ),
    );
  }

  static const _peopleDoneKey = 'fundly_inbox_people_done';

  /// من قبِل عهدة أو دَينًا أو دعوة أو تفويضًا أرسلته: يُضاف مرة واحدة إلى
  /// «الأفراد والجهات» باسمه ورقمه التعريفي، ويعدّل بقية بياناته بنفسه.
  static Future<void> _addAcceptedPeople(List<FundlyInboxItem> items) async {
    final accepted = [
      for (final item in items)
        if (item.action == 'accepted' &&
            item.senderName.trim().isNotEmpty &&
            // الموظف أُضيف عند إصدار السند.
            item.source != 'salary_receipts')
          item,
    ];
    if (accepted.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = (prefs.getStringList(_peopleDoneKey) ?? const <String>[])
          .toSet();
      for (final item in accepted) {
        if (!done.add(item.id)) continue;
        final what = item.source == 'delegations'
            ? 'التفويض'
            : item.entryType;
        await PeopleDirectoryStore.upsert(
          fullName: item.senderName.trim(),
          typeKey: 'person_other',
          categoryName: 'أخرى',
          details: {
            if (item.senderFnd.isNotEmpty) 'الرقم التعريفي': item.senderFnd,
          },
          sourceNote: 'قبل $what «${item.title}»',
        );
      }
      await prefs.setStringList(_peopleDoneKey, done.toList());
    } catch (_) {
      // تُعاد المحاولة عند الفتح التالي.
    }
  }

  /// نص الطلب حسب نوعه.
  static String _describe(FundlyInboxItem item) {
    final who = item.sender;
    if (item.isActivity) return item.activityText;
    if (item.isHideNotice) {
      return '$who ${AppTr.tr(item.action == 'removed' ? 'حذف هذا الالتزام من عنده' : 'أرشف هذا الالتزام عنده')}';
    }
    if (item.isResponse && item.source != 'delegations') {
      final accepted = item.action == 'accepted';
      return '$who ${AppTr.tr(accepted ? 'قبِل' : 'رفضَ')} '
          '${AppTr.tr(item.entryType)}'
          '${accepted ? ' — ${AppTr.tr('أُضيف إلى الأفراد والجهات، ويمكنك من هناك إضافة أي بيانات أخرى عنه')}' : ''}';
    }
    if (item.source == 'delegations') {
      return switch (item.entryType) {
        'قبول تفويض' =>
          '${AppTr.tr('قبِل التفويض')}: $who — '
              '${AppTr.tr('أُضيف إلى الأفراد والجهات، ويمكنك من هناك إضافة أي بيانات أخرى عنه')}',
        'رفض تفويض' => '${AppTr.tr('رفض التفويض')}: $who',
        'انسحاب من تفويض' => '${AppTr.tr('ألغى التفويض من عنده')}: $who',
        _ => '${AppTr.tr('فوّضك')} $who',
      };
    }
    if (item.source == 'shared_entries') {
      return '${AppTr.tr('دعاك')} $who ${AppTr.tr('للمشاركة في')} '
          '${AppTr.tr(item.entryType)}';
    }
    if (item.source == 'salary_receipts') {
      return '${AppTr.tr('أرسل إليك')} $who '
          '${AppTr.tr('سند قبض للاعتماد والتوقيع')}';
    }
    if (item.entryType.contains('عهدة')) {
      return '${AppTr.tr('أسند إليك')} $who ${AppTr.tr('عهدة مالية')}';
    }
    return '${AppTr.tr('أرسل إليك')} $who ${AppTr.tr(item.entryType)}';
  }

  static IconData _icon(FundlyInboxItem item) {
    if (item.isActivity) {
      return item.note.contains('contribution')
          ? Icons.savings_outlined
          : Icons.receipt_long_outlined;
    }
    if (item.action == 'removed') return Icons.delete_outline_rounded;
    if (item.action == 'archived') return Icons.archive_outlined;
    if (item.action == 'accepted') return Icons.check_circle_outline_rounded;
    if (item.action == 'rejected') return Icons.cancel_outlined;
    if (item.source == 'delegations') return Icons.verified_user_outlined;
    if (item.source == 'shared_entries') return Icons.groups_2_outlined;
    if (item.source == 'salary_receipts') return Icons.payments_outlined;
    if (item.entryType.contains('عهدة')) return Icons.inventory_2_outlined;
    return Icons.mark_email_unread_outlined;
  }

  static String _time(DateTime? at) {
    if (at == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.day}/${at.month}/${at.year}  ${two(at.hour)}:${two(at.minute)}';
  }

  /// عضو أرشف الالتزام المشترك أو حذفه من عنده: أنا أقرر لنفسي — حذف
  /// عندي، أو أرشفة عندي، أو إبقاؤه ([key] = null). يعيد true إذا تمّ.
  static Future<bool> _applyHideChoice(
    BuildContext context,
    FundlyInboxItem item,
    String? key,
  ) async {
    final remove = key == SharedMemberState.removedKey;
    var toHistory = false;
    if (key != null) {
      final ok = await confirmAction(
        context,
        title: remove ? 'حذف عندي' : 'أرشفة عندي',
        message: remove
            ? 'هل تريد حذف «${item.title}» من عندك؟ يبقى عند بقية الأعضاء، '
                  'ويمكنك استعادته من «المحذوفة عندي».'
            : 'هل تريد أرشفة «${item.title}» عندك؟ يبقى عند بقية الأعضاء.',
        confirmLabel: remove ? 'حذف' : 'أرشفة',
        danger: remove,
      );
      if (!ok) return false;
      try {
        if (item.recordId.isNotEmpty) {
          final repository = SupabaseSharedEntriesRepository();
          final current = await repository.fetchOne(item.recordId);
          if (current != null) {
            // لم تتم تسويته: لا يُمسح — ينتقل إلى «السجل التاريخي».
            var target = key;
            if (remove &&
                SharedLedger.settleTransfers(
                  current.details,
                  sharedMemberNames(current.details),
                ).isNotEmpty) {
              target = SharedMemberState.historyKey;
              toHistory = true;
            }
            await SharedMemberState.markMine(
              repository,
              current,
              target,
              add: true,
            );
          }
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('تعذّر الحفظ. تحقّق من الاتصال وحاول مرة أخرى.'),
            ),
          );
        }
        return false;
      }
    }
    await FundlyAccount.markSeen([item.id]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            key == null
                ? 'بقي «${item.title}» عندك كما هو'
                : toHistory
                ? '${AppTr.tr('لم تتم التسوية')} — «${item.title}» '
                      '${AppTr.tr('إلى «السجل التاريخي» — تجده أسفل قائمة الالتزامات المشتركة')}'
                : remove
                ? 'تم حذف «${item.title}» من عندك'
                : 'تمت أرشفة «${item.title}» عندك',
          ),
        ),
      );
    }
    return true;
  }

  /// أزرار إشعار الأرشفة أو الحذف: حذف عندي / أرشفة عندي / إبقاؤه.
  static Widget _hideChoiceButtons(
    BuildContext dialogContext,
    FundlyInboxItem item,
    void Function() onDone,
  ) {
    Future<void> choose(String? key) async {
      final done = await _applyHideChoice(dialogContext, item, key);
      if (done) onDone();
    }

    Widget buttons({required bool cancelled}) => Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 4,
      children: [
        // ألغاه المسؤول: لا معنى لإبقائه نشطًا — موافقة على الحذف أو
        // أرشفة للتقارير. وإن غادره عضو فقط: يبقى كما هو.
        if (!cancelled)
          TextButton(
            onPressed: () => choose(null),
            child: const Text('إبقاؤه'),
          ),
        OutlinedButton.icon(
          onPressed: () => choose(SharedMemberState.archivedKey),
          icon: const Icon(Icons.archive_outlined, size: 17),
          label: const Text('أرشفة عندي'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => choose(SharedMemberState.removedKey),
          icon: const Icon(Icons.delete_outline_rounded, size: 17),
          label: Text(cancelled ? 'موافق على الحذف' : 'حذف عندي'),
        ),
      ],
    );

    if (item.action != 'removed' || item.recordId.isEmpty) {
      return buttons(cancelled: false);
    }
    return FutureBuilder<SharedEntryRecord?>(
      future: SupabaseSharedEntriesRepository()
          .fetchOne(item.recordId)
          .catchError((_) => null),
      builder: (context, snapshot) {
        final status = snapshot.data?.status ?? '';
        final cancelled = status == 'ملغاة' || status == 'ملغية';
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 36,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cancelled)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${AppTr.tr('ألغى المسؤول هذا الالتزام')}'
                  '${(snapshot.data?.details['سبب الإلغاء'] ?? '').trim().isEmpty ? '' : ' — ${snapshot.data!.details['سبب الإلغاء']!.trim()}'}',
                  textAlign: AppTr.alignEnd,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            buttons(cancelled: cancelled),
          ],
        );
      },
    );
  }

  /// أزرار الطلب: «عرض التفاصيل» للاطلاع فقط، ثم قبول / رفض / لاحقًا.
  static Widget _inviteActions(
    BuildContext dialogContext,
    FundlyInboxItem item, {
    required VoidCallback onDone,
  }) {
    var busy = false;
    return StatefulBuilder(
      builder: (context, setBusy) {
        Future<void> answer(bool accept) async {
          if (busy) return;
          if (!accept) {
            final ok = await confirmAction(
              context,
              title: 'رفض الطلب',
              message: 'هل تريد رفض «${item.title}»؟',
              confirmLabel: 'رفض',
              danger: true,
            );
            if (!ok) return;
          }
          // سند القبض: الموافقة لا تتم إلا بالتوقيع.
          var signature = '';
          if (accept && item.source == 'salary_receipts') {
            final strokes = await showSignaturePad(
              context,
              title: 'التوقيع للموافقة',
              subtitle:
                  '${AppTr.tr('توقيعك يعني أنك استلمت')}: ${item.title}',
            );
            if (strokes == null || strokes.isEmpty || !context.mounted) {
              return;
            }
            // الاسم كتبه المرسل ويبقى كما هو — لا يُطلب من الموظف.
            signature = SalaryReceipt.encodeStrokes(strokes);
          }
          setBusy(() => busy = true);
          final error = await RequestsData.respond(
            item,
            accept,
            signature: signature,
          );
          if (!context.mounted) return;
          setBusy(() => busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                error != null
                    ? AppTr.tr(error)
                    : accept
                    ? '${AppTr.tr('تم قبول')} «${item.title}»'
                    : '${AppTr.tr('تم رفض')} «${item.title}»',
              ),
            ),
          );
          // نجح الرد، أو سبق الرد عليه / لم يعد قائمًا: يُغلق ولا يعود.
          if (error == null || RequestsData.closedMessages.contains(error)) {
            onDone();
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.goldDark,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _showDetails(context, item),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text(
                  'عرض التفاصيل',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: busy ? null : () => answer(true),
                    child: const Text('قبول'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: busy ? null : () => answer(false),
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  // يبقى الطلب قائمًا ويظهر في «الطلبات» حتى يُرد عليه.
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: busy
                        ? null
                        : () {
                            _laterNote(context);
                            onDone();
                          },
                    child: const Text('لاحقًا'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// «لاحقًا»: النافذة لا تعود لهذا الطلب، ومكانه صفحة «الطلبات».
  static void _laterNote(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('تجد الطلب في «الطلبات» حتى ترد عليه'),
      ),
    );
  }

  /// تفاصيل الطلب للاطلاع فقط، وسهم الرجوع يعيد إلى نافذة الطلبات.
  static Future<void> _showDetails(BuildContext context, FundlyInboxItem item) {
    final future = RequestsData.details(item);
    return showDialog<void>(
      context: context,
      builder: (detailsContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Dialog(
          backgroundColor: AppTheme.page,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: AppTr.tr('رجوع'),
                      onPressed: () => Navigator.pop(detailsContext),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        'تفاصيل الطلب',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: FutureBuilder<List<(String, String)>>(
                    future: future,
                    builder: (context, snapshot) {
                      final rows = snapshot.data;
                      if (rows == null) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      AppTr.tr(row.$1),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      row.$2,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.title,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// يعيد الطلب الذي ضغط «فتح»، أو null.
  static Future<FundlyInboxItem?> _inboxDialog(
    BuildContext context,
    List<FundlyInboxItem> items,
  ) {
    // نسخة قابلة للتعديل: ما يُقرَّر فيه من الإشعارات يختفي من النافذة.
    final rows = List<FundlyInboxItem>.of(items);
    return showDialog<FundlyInboxItem>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          backgroundColor: AppTheme.page,
          icon: const Icon(
            Icons.notifications_active_outlined,
            size: 34,
            color: AppTheme.gold,
          ),
          title: Text(
            // ردود فقط: «تم قبول طلبك» / «تم رفض طلبك».
            rows.isNotEmpty && rows.every((i) => i.isActivity)
                ? AppTr.tr('إضافات جديدة')
                : rows.isNotEmpty && rows.every((i) => i.isResponse)
                ? rows.every((i) => i.action == 'accepted')
                      ? AppTr.tr('تم قبول طلبك')
                      : rows.every((i) => i.action == 'rejected')
                      ? AppTr.tr('تم رفض طلبك')
                      : AppTr.tr('ردود على طلباتك')
                : rows.length == 1
                ? AppTr.tr('وصلك طلب جديد')
                : '${AppTr.tr('وصلتك طلبات جديدة')} (${rows.length})',
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = rows[index];
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // نوع الطلب فوقه بنفس الشكل لكل الأنواع: «عهدة مالية»،
                      // «الرحلة / السفر»، «تفويض»...
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          AppTr.tr(
                            item.source == 'delegations'
                                ? 'تفويض'
                                : item.entryType.trim().isEmpty
                                ? 'طلب'
                                : item.entryType,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.goldDark,
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppIconTile(
                            icon: _icon(item),
                            color: AppTheme.brandMid,
                            size: AppTheme.iconTileSmall,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _describe(item),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.title,
                                  ),
                                ),
                                if (item.title.trim().isNotEmpty)
                                  Text(
                                    '«${item.title}»',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.brand,
                                    ),
                                  ),
                                Text(
                                  '${AppTr.tr(item.isHideNotice ? 'يبقى عندك حتى تقرر' : item.isActivity ? 'للاطلاع' : item.isResponse ? (item.source == 'delegations' ? 'رد على تفويضك' : 'رد على ما أرسلته') : 'بانتظار قبولك أو رفضك')} · '
                                  '${_time(item.createdAt)}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (item.isHideNotice)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _hideChoiceButtons(dialogContext, item, () {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => rows.remove(item));
                            if (rows.isEmpty) Navigator.pop(dialogContext);
                          }),
                        )
                      else if (item.isInfo)
                        // الرد والنشاط للاطلاع فقط: زر «تم» أسفل النافذة.
                        const SizedBox.shrink()
                      else if (!item.isResponse)
                        _inviteActions(
                          dialogContext,
                          item,
                          onDone: () {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => rows.remove(item));
                            if (rows.isEmpty) Navigator.pop(dialogContext);
                          },
                        )
                      else
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () async {
                            await FundlyAccount.markSeen([item.id]);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, item);
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: Text(item.isResponse ? 'فتح' : 'فتح والرد'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // الطلب الواحد أزراره داخله (قبول / رفض / لاحقًا). الأسفل لإغلاق
          // النافذة كلها، و«تم الاطلاع» للردود والإشعارات فقط — الطلبات
          // تبقى حتى يُرد عليها.
          actions: [
            if (rows.any((i) => !i.isInfo) &&
                (rows.length > 1 || rows.any((i) => i.isHideNotice)))
              TextButton(
                onPressed: () {
                  _laterNote(dialogContext);
                  Navigator.pop(dialogContext);
                },
                child: const Text('لاحقًا'),
              ),
            if (rows.any((i) => i.isInfo))
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.brand),
                onPressed: () async {
                  final seen = [
                    for (final i in rows)
                      if (i.isInfo) i,
                  ];
                  await FundlyAccount.markSeen([for (final i in seen) i.id]);
                  if (!dialogContext.mounted) return;
                  setDialogState(() => rows.removeWhere(seen.contains));
                  if (rows.isEmpty) Navigator.pop(dialogContext);
                },
                child: const Text('تم'),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
