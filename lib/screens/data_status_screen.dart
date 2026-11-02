import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/app_session.dart';
import '../data/project_assets_repository.dart';
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
    ('التفويضات', 'delegations'),
    ('المستندات', 'document_records'),
  ];

  bool _running = false;

  /// نتيجة اختبار الحفظ، سطرًا سطرًا — تبقى معروضة وتُنسخ مع التقرير.
  String _writeReport = '';
  bool _writeTesting = false;

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

  /// يكتب صفَّي اختبار ثم يحذفهما، ويروي ما حدث بالتفصيل.
  Future<void> _runWriteTest() async {
    setState(() {
      _writeTesting = true;
      _writeReport = '';
    });
    final client = Supabase.instance.client;
    final log = StringBuffer();
    String uid;
    try {
      final user = await AppSession.ensureSignedIn();
      uid = user.id;
      log.writeln(AppSession.describeSession());
    } catch (error) {
      log.writeln('تعذّر الدخول: $error');
      if (!mounted) return;
      setState(() {
        _writeTesting = false;
        _writeReport = log.toString();
      });
      return;
    }

    // ٠) ما يراه الحساب فعلًا — بالعناوين، لا بالعدد وحده.
    try {
      final rows = await client
          .from('project_assets')
          .select('id,title,category,user_id')
          .timeout(const Duration(seconds: 20));
      log.writeln('');
      log.writeln('الصفوف المرئية: ${rows.length}');
      for (final row in rows) {
        final owner = (row['user_id'] ?? '').toString();
        final short = owner.length > 8 ? owner.substring(0, 8) : owner;
        log.writeln('• ${row['title']} · ${row['category']} · $short');
      }
    } catch (error) {
      log.writeln('تعذّرت القراءة: $error');
    }

    final createdIds = <String>[];

    // ١) أصغر صف ممكن: يفصل الصلاحيات عن الأعمدة.
    log.writeln('');
    try {
      final row = await client
          .from('project_assets')
          .insert({
            'user_id': uid,
            'title': 'اختبار حفظ — يُحذف تلقائيًا',
            'sub_type': 'اختبار',
            'category': 'real_estate',
            'status': 'نشط',
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 20));
      createdIds.add(row['id'].toString());
      log.writeln('١) صف مبسّط (٥ أعمدة): نجح');
    } catch (error) {
      log.writeln('١) صف مبسّط (٥ أعمدة): فشل');
      log.writeln('$error');
      log.writeln('');
      log.writeln(
        'فشل أبسط صف ممكن يعني أن العطل ليس في حقل بعينه: إما أن سياسة '
        'الكتابة (INSERT policy) غير موجودة على الجدول، أو أن الجدول أو '
        'عمود user_id غير موجود. انسخ التقرير وأرسله.',
      );
    }

    // ٢) صف بكل أعمدة النموذج: يكشف العمود المفقود باسمه.
    if (createdIds.isNotEmpty) {
      try {
        const record = ProjectAssetRecord(
          title: 'اختبار حفظ كامل — يُحذف تلقائيًا',
          subType: 'اختبار',
          category: 'real_estate',
        );
        final row = await client
            .from('project_assets')
            .insert(record.toJson(uid))
            .select()
            .single()
            .timeout(const Duration(seconds: 20));
        createdIds.add(row['id'].toString());
        log.writeln('٢) صف بكل الأعمدة: نجح');
        log.writeln('');
        log.writeln(
          'الكتابة سليمة تمامًا. إن كانت الإضافة لا تظهر رغم ذلك فالعطل '
          'في الشاشة لا في قاعدة البيانات.',
        );
      } catch (error) {
        log.writeln('٢) صف بكل الأعمدة: فشل');
        log.writeln('$error');
        log.writeln('');
        log.writeln(
          'نجاح المبسّط وفشل الكامل يعني أن عمودًا في النموذج لا وجود له '
          'في الجدول — اسمه مذكور في نص الخطأ أعلاه.',
        );
      }
    }

    // ٣) تنظيف: صفوف الاختبار لا تبقى في بيانات المستخدم.
    for (final id in createdIds) {
      try {
        await client
            .from('project_assets')
            .delete()
            .eq('id', id)
            .timeout(const Duration(seconds: 20));
      } catch (error) {
        log.writeln('تعذّر حذف صف الاختبار $id: $error');
      }
    }
    if (createdIds.isNotEmpty) {
      log.writeln('');
      log.writeln('حُذفت صفوف الاختبار (${createdIds.length}).');
    }

    if (!mounted) return;
    setState(() {
      _writeTesting = false;
      _writeReport = log.toString();
    });
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
    if (_writeReport.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('— اختبار الحفظ —')
        ..writeln(_writeReport);
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
                    fontSize: 12,
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
                    fontSize: 12,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: _totalRows > 0
                        ? AppTheme.accentDark
                        : AppTheme.warning,
                  ),
                ),
              ),
            const SizedBox(height: AppTheme.cardGap),
            AppCard(
              title: 'اختبار الحفظ',
              subtitle: 'يكتب صفَّي اختبار ثم يحذفهما',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _writeTesting ? null : _runWriteTest,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: Text(
                      _writeTesting ? 'جارٍ الاختبار...' : 'ابدأ اختبار الحفظ',
                    ),
                  ),
                  if (_writeReport.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.sLg),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppTheme.sLg),
                      decoration: BoxDecoration(
                        color: AppTheme.page,
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                      ),
                      child: SelectableText(
                        _writeReport,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.7,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                  ],
                ],
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
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.title,
            ),
          ),
        ),
      ],
    );
  }
}
