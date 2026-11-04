import 'package:flutter/material.dart' hide Text, Align;

import '../data/app_settings.dart';
import '../widgets/shared/module_shared_widgets.dart' show directOpenRoute;
import '../data/delegation_targets.dart';
import '../data/delegations_repository.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import 'projects_activities_screen.dart' show ProjectsActivitiesScreen;

/// تفويض وصلني من حساب آخر بالرقم التعريفي: من فوّضني، على ماذا،
/// بأي صلاحيات ولأي مدة — مع القبول أو الرفض، وبعد القبول عرض البيانات
/// المفوَّضة.
Future<void> showIncomingDelegation(
  BuildContext context,
  DelegationRecord record, {
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _IncomingDelegationSheet(
      record: record,
      onChanged: onChanged,
    ),
  );
}

String _date(DateTime? date) => date == null
    ? '—'
    : '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// حالة التفويض كما يراها المفوَّض.
({String label, Color color}) incomingStatusOf(DelegationRecord record) {
  final answer = DelegationRecord.acceptOf(record.permissions);
  if (answer == 'withdrawn') {
    return (label: 'ألغيتَه من عندك', color: AppTheme.danger);
  }
  if (answer == 'rejected') {
    return (label: 'رفضتَه', color: AppTheme.danger);
  }
  if (answer != 'accepted') {
    return (label: 'بانتظار ردك', color: AppTheme.gold);
  }
  if (record.isEnded) return (label: 'منتهي', color: AppTheme.muted);
  if (record.isPaused) return (label: 'موقوف', color: AppTheme.danger);
  if (record.isScheduled) return (label: 'مجدول', color: AppTheme.brand);
  return (label: 'قبلتَه — ساري', color: AppTheme.brandMid);
}

class _IncomingDelegationSheet extends StatefulWidget {
  const _IncomingDelegationSheet({
    required this.record,
    required this.onChanged,
  });

  final DelegationRecord record;
  final VoidCallback onChanged;

  @override
  State<_IncomingDelegationSheet> createState() =>
      _IncomingDelegationSheetState();
}

class _IncomingDelegationSheetState extends State<_IncomingDelegationSheet> {
  bool _busy = false;

  /// العودة إلى تفويض ألغيتُه من عندي — ما دام صاحبه لم يُنهِه.
  Future<void> _rejoin() async {
    final id = widget.record.id;
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'العودة للتفويض',
      message: 'ستعود لإدارة ما فُوِّضتَ به بنفس الصلاحيات والمدة، ويصل '
          'لصاحبه إشعار بعودتك. هل تريد المتابعة؟',
      confirmLabel: 'عودة',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseDelegationsRepository().setIncomingAnswer(id, 'accepted');
      widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('عدتَ للتفويض'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّرت العودة — ربما أنهى صاحبه التفويض.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _respond(bool accept) async {
    final ok = await confirmAction(
      context,
      title: accept ? 'قبول التفويض' : 'رفض التفويض',
      message: accept
          ? 'بقبولك تستطيع الاطلاع على البيانات المفوَّضة خلال مدة التفويض، '
                'ويصل للمالك إشعار بقبولك. هل تريد المتابعة؟'
          : 'سيصل للمالك إشعار برفضك. هل تريد المتابعة؟',
      confirmLabel: accept ? 'قبول' : 'رفض',
      danger: !accept,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseDelegationsRepository().respondIncoming(
        widget.record,
        accept,
      );
      widget.onChanged();
      if (!mounted) return;
      if (accept) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Directionality(
            textDirection: AppTr.uiDir,
            child: AlertDialog(
              backgroundColor: AppTheme.page,
              icon: const Icon(
                Icons.verified_user_outlined,
                size: 32,
                color: AppTheme.brandMid,
              ),
              title: const Text('تم قبول التفويض', textAlign: TextAlign.center),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'يتم إدارة التفويض من: المزيد > التفويضات.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'وما فُوِّضتَ به من عقارات ومركبات وأنشطة تجده في قسمه '
                    'بعلامة «مفوَّض» (دائرة بنفسجية)، وكل ما تقوم به يصل '
                    'إشعاره لمن فوّضك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.6),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('حسنًا'),
                ),
              ],
            ),
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(accept ? 'تم قبول التفويض' : 'تم رفض التفويض'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّر إرسال الرد. حاول مرة أخرى.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.brandMid),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.title,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final owner = DelegationRecord.ownerNameOf(record.permissions);
    final main = DelegationRecord.mainScopeOf(record.scope);
    final subs = DelegationRecord.subScopesOf(record.scope);
    final targets = [
      for (final p in record.permissions)
        if (DelegationTarget.decode(p) case final target?) target.label,
    ];
    final permissions = DelegationRecord.plainPermissions(record.permissions)
        .where((p) => p != DelegationRecord.kNeedsOwnerApproval)
        .toList();
    final needsApproval = record.permissions.contains(
      DelegationRecord.kNeedsOwnerApproval,
    );
    final limit = DelegationRecord.limitOf(record.permissions);
    final answer = DelegationRecord.acceptOf(record.permissions);
    final status = incomingStatusOf(record);
    final canView =
        answer == 'accepted' &&
        record.isActive &&
        record.permissions.contains('عرض البيانات');

    return Directionality(
      textDirection: AppTr.uiDir,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            children: [
              Row(
                children: [
                  const AppIconTile(
                    icon: Icons.verified_user_outlined,
                    color: AppTheme.brandMid,
                    size: AppTheme.iconTileSmall,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تفويض وصلك',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                        Text(
                          '${AppTr.tr('من')}: ${owner.isEmpty ? '—' : owner}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: status.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _row(Icons.account_tree_outlined, 'القسم', AppTr.tr(main)),
              if (subs.isNotEmpty)
                _row(
                  Icons.segment_rounded,
                  'الأقسام الفرعية',
                  subs.map(AppTr.tr).join('، '),
                ),
              if (targets.isNotEmpty)
                _row(
                  Icons.push_pin_outlined,
                  'عناصر محددة',
                  targets.join('، '),
                ),
              _row(
                Icons.key_rounded,
                'الصلاحيات',
                permissions.isEmpty
                    ? '—'
                    : permissions.map(AppTr.tr).join('، '),
              ),
              if (limit != null)
                _row(
                  Icons.payments_outlined,
                  'سقف المبلغ',
                  '$limit ${AppSettings.currencySuffix}',
                ),
              _row(
                Icons.rule_rounded,
                'موافقة المالك',
                AppTr.tr(
                  needsApproval
                      ? 'ما تُدخله يحتاج موافقة المالك'
                      : 'لا يحتاج موافقة',
                ),
              ),
              _row(
                Icons.date_range_rounded,
                'المدة',
                '${_date(record.startDate)} — ${_date(record.endDate)}',
              ),
              if ((record.notes ?? '').trim().isNotEmpty)
                _row(Icons.notes_rounded, 'الغرض', record.notes!.trim()),
              const SizedBox(height: 8),
              // ألغيتُه من عندي: أعود إليه ما دام صاحبه لم يُنهِه.
              if (answer == 'withdrawn' && !record.isEnded)
                FilledButton.icon(
                  onPressed: _busy ? null : _rejoin,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 19),
                  label: const Text('العودة للتفويض'),
                ),
              if (answer == 'withdrawn' && record.isEnded)
                const Text(
                  'انتهى التفويض — لا يمكن العودة إليه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
              if (answer != 'accepted' &&
                  answer != 'rejected' &&
                  answer != 'withdrawn')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _respond(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('رفض'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _respond(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brand,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('قبول'),
                      ),
                    ),
                  ],
                ),
              if (canView)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DelegatedRecordsScreen(record: record),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 19),
                  label: const Text('عرض البيانات المفوَّضة'),
                ),
              if (answer == 'accepted' && !canView)
                const Text(
                  'عرض البيانات متاح أثناء مدة التفويض وما دام غير موقوف.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// سجلات المالك في نطاق التفويض — للاطلاع فقط.
class DelegatedRecordsScreen extends StatefulWidget {
  const DelegatedRecordsScreen({super.key, required this.record});

  final DelegationRecord record;

  @override
  State<DelegatedRecordsScreen> createState() => _DelegatedRecordsScreenState();
}

class _DelegatedRecordsScreenState extends State<DelegatedRecordsScreen> {
  late Future<List<Map<String, dynamic>>> _rows = _load();

  static const _purple = Color(0xFF6A4C93);

  List<String> get _perms => widget.record.permissions;
  bool get _canEdit => _perms.contains('تعديل السجلات');
  bool get _canAct =>
      _canEdit ||
      _perms.contains('إضافة السجلات') ||
      _perms.contains('تنفيذ المدفوعات والتحويلات');
  bool get _canDelete => _perms.contains('حذف السجلات');
  bool get _manages => _canAct || _canDelete;

  /// الضغط على سجل: العقار يُفتح في قسمه، والالتزام يُدار هنا.
  Future<void> _openRow(Map<String, dynamic> row) async {
    final source = '${row['source'] ?? ''}';
    final id = '${row['id'] ?? ''}';
    if (id.isEmpty || id == 'null') return;
    if (source == 'project_assets') {
      await Navigator.of(context).push(
        directOpenRoute<void>(ProjectsActivitiesScreen(openAssetId: id)),
      );
      return;
    }
    if (source != 'personal_entries' && source != 'shared_entries') return;
    if (!_manages) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _DelegatedEntrySheet(
        delegationId: widget.record.id ?? '',
        row: row,
        canEdit: _canEdit,
        canAct: _canAct,
        canDelete: _canDelete,
      ),
    );
    if (changed == true && mounted) {
      setState(() => _rows = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppTr.tr('تم الحفظ وإشعار')} '
            '${DelegationRecord.ownerNameOf(widget.record.permissions)} '
            '${AppTr.tr('بما قمت به')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    final id = widget.record.id;
    if (id == null) return Future.value(const []);
    return SupabaseDelegationsRepository().delegatedRecords(id);
  }

  static String _sourceLabel(String source) => switch (source) {
    'personal_entries' => 'الالتزامات الشخصية',
    'shared_entries' => 'الالتزامات المشتركة',
    'project_assets' => 'العقارات والأنشطة والمركبات',
    'people' => 'الأفراد والجهات',
    _ => source,
  };

  static IconData _sourceIcon(String source) => switch (source) {
    'personal_entries' => Icons.person_outline_rounded,
    'shared_entries' => Icons.groups_2_outlined,
    'project_assets' => Icons.apartment_rounded,
    'people' => Icons.people_alt_outlined,
    _ => Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final owner = DelegationRecord.ownerNameOf(widget.record.permissions);
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('البيانات المفوَّضة', style: AppTheme.cardTitle),
            if (owner.isNotEmpty)
              Text(
                owner,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
          ],
        ),
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _rows = _load());
            await _rows;
          },
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _rows,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    Text(
                      'تعذّر تحميل البيانات. اسحب للتحديث.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    Text(
                      'لا توجد سجلات في نطاق هذا التفويض.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _manages
                          ? 'اضغط على السجل لإدارته حسب صلاحياتك، والعقار '
                                'يُفتح في قسمه — وكل ما تفعله يصل إشعاره '
                                'للمالك.'
                          : 'للاطلاع فقط — تظهر هنا سجلات المالك في نطاق '
                                'التفويض وأثناء مدته.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                  for (final row in rows)
                    InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openRow(row),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _purple.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          // دائرة «مفوَّض».
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            decoration: const BoxDecoration(
                              color: _purple,
                              shape: BoxShape.circle,
                            ),
                          ),
                          AppIconTile(
                            icon: _sourceIcon('${row['source']}'),
                            color: AppTheme.brandMid,
                            size: AppTheme.iconTileSmall,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['title'] ?? ''}'.trim().isEmpty
                                      ? '${row['kind'] ?? ''}'
                                      : '${row['title']}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.title,
                                  ),
                                ),
                                Text(
                                  [
                                    AppTr.tr(_sourceLabel('${row['source']}')),
                                    AppTr.tr('${row['kind'] ?? ''}'),
                                    AppTr.tr('${row['status'] ?? ''}'),
                                    '${row['due'] ?? ''}',
                                  ].where((s) => s.trim().isNotEmpty).join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if ((num.tryParse('${row['amount']}') ?? 0) != 0)
                            Text(
                              AppSettings.maskAmount(
                                '${num.tryParse('${row['amount']}')!.round()} '
                                '${AppSettings.currencySuffix}',
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.brand,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// إدارة سجل شخصي أو مشترك من المفوَّض: التعديل (بصلاحية التعديل)،
/// والحالة والملاحظة (بأي صلاحية عمل)، والنقل لسلة المالك (بصلاحية الحذف).
class _DelegatedEntrySheet extends StatefulWidget {
  const _DelegatedEntrySheet({
    required this.delegationId,
    required this.row,
    required this.canEdit,
    required this.canAct,
    required this.canDelete,
  });

  final String delegationId;
  final Map<String, dynamic> row;
  final bool canEdit;
  final bool canAct;
  final bool canDelete;

  @override
  State<_DelegatedEntrySheet> createState() => _DelegatedEntrySheetState();
}

class _DelegatedEntrySheetState extends State<_DelegatedEntrySheet> {
  static const _statuses = ['نشطة', 'مكتملة', 'تمت التسوية', 'ملغاة'];

  late final TextEditingController _title = TextEditingController(
    text: '${widget.row['title'] ?? ''}',
  );
  late final TextEditingController _amount = TextEditingController(
    text: () {
      final n = num.tryParse('${widget.row['amount']}') ?? 0;
      return n == 0 ? '' : (n % 1 == 0 ? '${n.round()}' : '$n');
    }(),
  );
  final TextEditingController _note = TextEditingController();
  late String _due = '${widget.row['due'] ?? ''}';
  late String _status = '${widget.row['status'] ?? ''}';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _source => '${widget.row['source'] ?? ''}';
  String get _id => '${widget.row['id'] ?? ''}';

  Future<void> _pickDue() async {
    final initial = DateTime.tryParse(_due) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _due = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save() async {
    final ok = await confirmAction(
      context,
      title: 'حفظ التغيير',
      message: 'سيُحفظ التغيير في سجل المالك ويصله إشعار به. هل تريد المتابعة؟',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await SupabaseDelegationsRepository().editDelegatedEntry(
        delegationId: widget.delegationId,
        source: _source,
        entryId: _id,
        title: widget.canEdit ? _title.text.trim() : null,
        amount: widget.canEdit
            ? num.tryParse(_amount.text.trim().replaceAll(',', ''))
            : null,
        dueDate: widget.canEdit ? _due : null,
        status: _status,
        note: _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر الحفظ — قد تكون الصلاحية أو مدة التفويض انتهت.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _trash() async {
    final ok = await confirmAction(
      context,
      title: 'نقل إلى سلة المالك',
      message: 'سيُنقل السجل إلى سلة المهملات عند المالك (يستطيع استعادته)، '
          'ويصله إشعار بذلك. هل تريد المتابعة؟',
      confirmLabel: 'نقل',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await SupabaseDelegationsRepository().trashDelegatedEntry(
        delegationId: widget.delegationId,
        source: _source,
        entryId: _id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر النقل — قد تكون الصلاحية أو مدة التفويض انتهت.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: AppTr.tr(label),
    filled: true,
    fillColor: AppTheme.field,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final statuses = [
      ..._statuses,
      if (_status.isNotEmpty && !_statuses.contains(_status)) _status,
    ];
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6A4C93),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${AppTr.tr('مفوَّض')} — ${AppTr.tr('${widget.row['kind'] ?? ''}')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6A4C93),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.canEdit) ...[
                TextField(
                  controller: _title,
                  textAlign: AppTr.alignEnd,
                  decoration: _decoration('العنوان'),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: _amount,
                  textAlign: AppTr.alignEnd,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('المبلغ'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDue,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _due.isEmpty
                        ? AppTr.tr('تاريخ الاستحقاق')
                        : '${AppTr.tr('تاريخ الاستحقاق')}: $_due',
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Text(
                  '${widget.row['title'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.canAct) ...[
                const Text(
                  'الحالة',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final s in statuses)
                      ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  textAlign: AppTr.alignEnd,
                  maxLines: 2,
                  decoration: _decoration('ملاحظة للمالك'),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(_busy ? 'جارٍ الحفظ...' : 'حفظ'),
                ),
              ],
              if (widget.canDelete) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _trash,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('نقل إلى سلة المالك'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
