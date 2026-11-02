import 'package:flutter/material.dart' hide Text, Align;

import '../data/requests_data.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import 'personal_commitments_screen.dart';
import 'salary_receipts_screen.dart';
import 'shared_commitments_screen.dart';

/// بطاقة «الطلبات» في الرئيسية — بنفس شكل «الملخص الشامل»: عدد ما ينتظر
/// ردك أو اعتمادك، والضغط يفتح صفحة الطلبات كلها.
class RequestsCenterCard extends StatefulWidget {
  const RequestsCenterCard({
    super.key,
    required this.onOpenDelegations,
    this.refresh,
  });

  /// التفويض يُفتح في صفحة التفويضات (تُعرَّف في الرئيسية).
  final VoidCallback onOpenDelegations;

  /// يتغيّر عند وصول طلب جديد فيُعاد العدّ.
  final Listenable? refresh;

  @override
  State<RequestsCenterCard> createState() => _RequestsCenterCardState();
}

class _RequestsCenterCardState extends State<RequestsCenterCard> {
  int _awaiting = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await RequestsData.load();
    if (!mounted) return;
    setState(() {
      _total = rows.length;
      _awaiting = rows.where((r) => r.kind != RequestKind.sentByMe).length;
    });
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RequestsScreen(onOpenDelegations: widget.onOpenDelegations),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _total == 0
        ? AppTr.tr('لا توجد طلبات الآن')
        : _awaiting > 0
        ? '${AppTr.tr('بانتظار ردك أو اعتمادك')}: $_awaiting'
        : '${AppTr.tr('أرسلتها بانتظار الرد')}: $_total';
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const AppIconTile(
                  icon: Icons.move_to_inbox_outlined,
                  color: Color(0xFFA6691A),
                  size: 34,
                  iconSize: 18,
                ),
                const SizedBox(width: AppTheme.sMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('الطلبات', style: AppTheme.cardTitle),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppTheme.rowSubtitle),
                    ],
                  ),
                ),
                if (_awaiting > 0)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                    child: Text(
                      '$_awaiting',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const AppChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// صفحة «الطلبات»: كل ما ينتظر ردك، وما ينتظر اعتمادك، وما أرسلته وينتظر
/// رد غيرك — الأحدث أولًا، والضغط على أي طلب يفتحه.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.onOpenDelegations});

  final VoidCallback onOpenDelegations;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<RequestEntry>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await RequestsData.load();
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _open(RequestEntry entry) async {
    if (entry.source == 'delegations') {
      widget.onOpenDelegations();
      return;
    }
    if (entry.source == 'salary_receipts') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SalaryReceiptsScreen(openId: entry.recordId),
        ),
      );
      await _load();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => entry.source == 'shared_entries'
            ? SharedCommitmentsScreen(openEntryId: entry.recordId)
            : PersonalCommitmentsScreen(openEntryId: entry.recordId),
      ),
    );
    await _load();
  }

  static String _time(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _section(String title, IconData icon, Color color, RequestKind kind) {
    final rows = (_rows ?? const <RequestEntry>[])
        .where((r) => r.kind == kind)
        .toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${AppTr.tr(title)} (${rows.length})',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rField),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(row),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        AppIconTile(
                          icon: row.source == 'delegations'
                              ? Icons.verified_user_outlined
                              : row.source == 'shared_entries'
                              ? Icons.groups_2_outlined
                              : row.source == 'salary_receipts'
                              ? Icons.payments_outlined
                              : row.entryType == 'عهدة مالية'
                              ? Icons.inventory_2_outlined
                              : Icons.handshake_outlined,
                          color: color,
                          size: 34,
                          iconSize: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.title.isEmpty
                                    ? AppTr.tr(row.entryType)
                                    : row.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.title,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                row.subtitle,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.body,
                                ),
                              ),
                              if (row.at != null)
                                Text(
                                  _time(row.at),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const AppChevron(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('الطلبات', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: Text(
                            'لا توجد طلبات الآن',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    _section(
                      'بانتظار ردك',
                      Icons.move_to_inbox_outlined,
                      const Color(0xFFA6691A),
                      RequestKind.awaitingMe,
                    ),
                    _section(
                      'بانتظار اعتمادك',
                      Icons.fact_check_outlined,
                      AppTheme.brandMid,
                      RequestKind.approvals,
                    ),
                    _section(
                      'أرسلتها بانتظار الرد',
                      Icons.outbox_outlined,
                      AppTheme.muted,
                      RequestKind.sentByMe,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
