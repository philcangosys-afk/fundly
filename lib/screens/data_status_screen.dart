import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/app_session.dart';
import '../widgets/shared/app_design.dart';

/// شاشة "حالة البيانات والاتصال".
///
/// حين تفتح الشاشات فارغة لا يعرف المستخدم السبب: هل انقطع الاتصال؟ أم
/// دخل التطبيق بحساب آخر؟ أم أن البيانات فعلًا غير موجودة؟ الفرق جوهري
/// (الأول والثاني قابلان للإصلاح فورًا) لكن الشاشة الفارغة تبدو واحدة في
/// الحالات الثلاث. هذه الشاشة تفصل بينها في ضغطة واحدة.
class DataStatusScreen extends StatefulWidget {
  const DataStatusScreen({super.key});

  @override
  State<DataStatusScreen> createState() => _DataStatusScreenState();
}

class _DataStatusScreenState extends State<DataStatusScreen> {
  /// الجداول التي يقرأ منها التطبيق، بأسمائها كما يراها المستخدم.
  static const _tables = <(String label, String table)>[
    ('العقارات والأنشطة', 'project_assets'),
    ('سجلات العقارات', 'project_asset_entries'),
    ('الالتزامات الشخصية', 'personal_entries'),
    ('الالتزامات المشتركة', 'shared_entries'),
    ('عقود الوحدات', 'property_unit_contracts'),
    ('المحافظ', 'wallets'),
    ('حركات المحافظ', 'wallet_transactions'),
    ('التفويضات', 'delegations'),
    ('المستندات', 'document_records'),
  ];

  bool _running = false;
  String? _accountEmail;
  String? _accountId;
  String? _sessionError;
  final Map<String, String> _results = {};

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
      _sessionError = null;
      _accountEmail = null;
      _accountId = null;
    });

    final client = Supabase.instance.client;

    // 1) الجلسة: أهم سؤال — بأي حساب يقرأ التطبيق؟
    try {
      final user = await AppSession.ensureSignedIn();
      if (!mounted) return;
      setState(() {
        _accountEmail = user.email ?? '(بلا بريد)';
        _accountId = user.id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionError = error.toString();
        _running = false;
      });
      return;
    }

    // 2) عدد الصفوف التي يراها هذا الحساب في كل جدول.
    for (final entry in _tables) {
      try {
        final rows = await client
            .from(entry.$2)
            .select('id')
            .timeout(const Duration(seconds: 15));
        if (!mounted) return;
        setState(() => _results[entry.$2] = '${rows.length}');
      } catch (error) {
        if (!mounted) return;
        final text = error.toString();
        setState(
          () => _results[entry.$2] = text.contains('PGRST205')
              ? 'الجدول غير موجود'
              : 'خطأ',
        );
      }
    }

    if (mounted) setState(() => _running = false);
  }

  Future<void> _copyReport() async {
    final buffer = StringBuffer()
      ..writeln('Fundly — حالة البيانات')
      ..writeln('الحساب: ${_accountEmail ?? '—'}')
      ..writeln('المعرّف: ${_accountId ?? '—'}')
      ..writeln('الخادم: ${SupabaseConfig.url}');
    if (_sessionError != null) buffer.writeln('خطأ الجلسة: $_sessionError');
    for (final entry in _tables) {
      buffer.writeln('${entry.$1} (${entry.$2}): ${_results[entry.$2] ?? '—'}');
    }
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('تم نسخ التقرير')),
    );
  }

  int get _totalRows => _results.values
      .map((value) => int.tryParse(value) ?? 0)
      .fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('حالة البيانات والاتصال'),
        actions: [
          IconButton(
            tooltip: AppTr.tr('إعادة الفحص'),
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.pageInset,
            AppTheme.sLg,
            AppTheme.pageInset,
            28,
          ),
          children: [
            if (_running) const LinearProgressIndicator(minHeight: 3),
            if (_sessionError != null)
              Container(
                padding: const EdgeInsets.all(AppTheme.sLg),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Text(
                  'تعذّر الدخول إلى حساب التطبيق، ولهذا تظهر كل الشاشات '
                  'فارغة. البيانات في الخادم لم تُحذف.\n\n$_sessionError',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
              )
            else
              AppCard(
                title: 'الحساب الحالي',
                subtitle: 'كل البيانات مرتبطة بهذا الحساب',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row('البريد', _accountEmail ?? '...'),
                    const SizedBox(height: AppTheme.sSm),
                    _row('المعرّف', _accountId ?? '...'),
                    const SizedBox(height: AppTheme.sSm),
                    _row('الخادم', SupabaseConfig.url),
                  ],
                ),
              ),
            const SizedBox(height: AppTheme.cardGap),
            AppCard(
              title: 'عدد السجلات',
              subtitle: 'ما يراه هذا الحساب فعلًا في الخادم',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in _tables) ...[
                    _row(entry.$1, _results[entry.$2] ?? '...'),
                    if (entry != _tables.last)
                      const SizedBox(height: AppTheme.sSm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTheme.cardGap),
            if (!_running && _sessionError == null)
              Container(
                padding: const EdgeInsets.all(AppTheme.sLg),
                decoration: BoxDecoration(
                  color: _totalRows > 0
                      ? AppTheme.accentSoft
                      : AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rField),
                ),
                child: Text(
                  _totalRows > 0
                      ? 'الاتصال سليم وهذا الحساب يرى $_totalRows سجلًا. '
                            'إن كانت شاشة بعينها فارغة فالمشكلة في تلك '
                            'الشاشة لا في الاتصال.'
                      : 'الاتصال سليم، لكن هذا الحساب لا يملك أي سجل. '
                            'هذا يعني غالبًا أن البيانات محفوظة تحت حساب '
                            'آخر (حساب مجهول قديم) — شغّل ملف '
                            '_recover_old_data.sql في Supabase لنقل الملكية '
                            'إلى المعرّف الظاهر أعلاه.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: _totalRows > 0
                        ? AppTheme.accentDark
                        : AppTheme.warning,
                  ),
                ),
              ),
            const SizedBox(height: AppTheme.cardGap),
            OutlinedButton.icon(
              onPressed: _running ? null : _copyReport,
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('نسخ التقرير'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(label, style: AppTheme.rowSubtitle),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.title,
            ),
          ),
        ),
      ],
    );
  }
}
