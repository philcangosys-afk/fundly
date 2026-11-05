import 'dart:convert';
import 'dart:typed_data';
import 'widgets/shared/module_shared_widgets.dart' show directOpenRoute;
import 'widgets/management_dashboard_chrome.dart' show moduleTintFill;

import 'package:flutter/material.dart' hide Text, Align;
import 'l10n/tr_widgets.dart';
import 'l10n/app_language.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'data/app_settings.dart';
import 'data/custody_sharing.dart';
import 'screens/birthday_screen.dart';
import 'data/archive_center.dart';
import 'data/home_dashboard_service.dart';
import 'data/home_summary_service.dart';
import 'data/people_directory_store.dart';
import 'data/report_document.dart';
import 'data/read_notifications_store.dart';
import 'data/home_pin_items_service.dart';
import 'data/home_pinned_shortcuts_store.dart';
import 'data/home_layout_store.dart';
import 'data/delegations_repository.dart';
import 'data/delegation_targets.dart';
import 'l10n/home_strings.dart';
import 'screens/app_lock_screen.dart';
import 'screens/login_screen.dart';
import 'data/document_store.dart';
import 'data/fundly_account.dart';
import 'data/fundly_push.dart';
import 'data/fundly_files.dart';
import 'data/fundly_auth.dart';
import 'data/install_guard.dart';
import 'data/page_customization_store.dart';
import 'widgets/shared/account_notices.dart';
import 'screens/received_delegations.dart';
import 'screens/salary_receipts_screen.dart';
import 'screens/notifications_center_screen.dart';
import 'screens/document_templates_screen.dart';
import 'screens/global_summary_screen.dart';
import 'screens/people_management_screen.dart';
import 'screens/personal_commitments_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'screens/settings_detail_screens.dart';
import 'screens/projects_activities_screen.dart';
import 'screens/raffle_screen.dart';
import 'screens/report_preview_screen.dart';
import 'screens/documents_hub_screen.dart';
import 'screens/shared_commitments_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/smart_calendar_screen.dart';
import 'data/fundly_notifications.dart';
import 'widgets/shared/app_design.dart';
import 'widgets/shared/fnd_lookup.dart';
import 'data/subscription_plans.dart';
import 'widgets/shared/plan_gate.dart';
import 'widgets/shared/app_filter_sheet.dart';
import 'widgets/shared/scope_builder_sheet.dart';
import 'widgets/shared/search_matching.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase: إشعارات الطلبات والتطبيق مغلق (لا يوقف الإقلاع إن فشل).
  await FundlyPush.init();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  // حذف التطبيق ثم تثبيته: شاشة الدخول حتى لو أبقى الجوال البيانات القديمة.
  await InstallGuard.check();
  // تُحمَّل الإعدادات قبل بناء الواجهة، فيبدأ التطبيق بحجم النص والعملة
  // وحالة القفل الصحيحة من أول إطار بلا ومضة قيم افتراضية.
  await AppSettings.instance.load();
  // الرقم التعريفي للمستخدم: يُولَّد مرة واحدة ويُستعمل في المعاملات
  // المشتركة بين شخصين (إسناد العهدة المالية مثلًا).
  await AppIdentity.load();
  // الدخول بحساب حقيقي: بلا جلسة تظهر شاشة الدخول.
  await FundlyAuth.load();
  // مجلد ملفات التطبيق: لفتح ملف حُفظ على جوال آخر ونُزّل من السحابة.
  await DocumentStore.init();
  if (FundlyAuth.isSignedIn) {
    // الرقم التعريفي والاسم من الخادم، ورفع بيانات الجهاز للسحابة،
    // وتنزيل الملفات الجديدة (ومنها ما رفعه الطرف الآخر).
    FundlyAccount.refreshProfile();
    FundlyAccount.startAutoSync();
    FundlyFiles.syncDown(force: true).then((_) => FundlyFiles.syncUp());
  }
  // ما أُخفي من الفئات والعناصر في «تخصيص الصفحات».
  await PageCustomizationStore.load();
  FundlyAuth.loginPrompt = promptGuestLogin;
  // «+» في تبويب التفويضات داخل تفاصيل فرد يفتح نموذج التفويض نفسه الموجود
  // في «المزيد ← التفويضات»، والمفوَّض معبّأ باسم الفرد.
  openDelegationFormForPerson = (context, name) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DelegationsHubPage(presetDelegate: name),
    ),
  );
  // «تفويض آخرين» من صفحة عقار أو وحدة أو مركبة أو نشاط: النموذج نفسه
  // والقسم والعنصر مختاران مسبقًا (ويمكن تغييرهما).
  openDelegationForTarget = (context, {required sub, required target}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DelegationsHubPage(
            presetDelegate: '',
            presetSub: sub,
            presetTarget: target,
          ),
        ),
      );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _language = AppSettings.instance.language;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// تغيير اللغة يعيد بناء كل الشاشات المفتوحة فورًا — بلا انتظار إغلاق
  /// التطبيق، في الاتجاهين (عربي ← لغة أخرى ← عربي).
  void _onSettingsChanged() {
    final language = AppSettings.instance.language;
    if (language == _language) return;
    _language = language;
    AppTr.rebuildAll();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppTr.rebuildAll());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.instance,
        FundlyAuth.sessionEpoch,
      ]),
      builder: (context, _) => MaterialApp(
        // الخروج يبني التطبيق من جديد فيظهر الدخول بلا بقايا الحساب السابق.
        key: ValueKey('app-session-${FundlyAuth.sessionEpoch.value}'),
        title: HomeStrings.appTitle,
        // سِمة واحدة تُوحّد الحقول والأزرار والنوافذ والشيتات في كل
        // التطبيق، بما فيها الشاشات التي لم نمرّ عليها يدويًا.
        theme: buildAppTheme(),
        // ملاحظة مهمة: لا تفرض Directionality.rtl عامًا هنا. شاشات هذا التطبيق
        // مكتوبة على افتراض اتجاه افتراضي LTR مع تحديد rtl صراحةً داخل كل Row
        // يحتاجه، واستخدام CrossAxisAlignment.end بمعنى "المحاذاة لليمين".
        // فرض rtl عامًا يعكس كل هذه المحاذاة ويبعثر عناصر الشاشات بالكامل.
        //
        // أما builder هنا فيطبّق حجم النص المختار في الإعدادات على التطبيق
        // كله؛ كان هذا الإعداد يُحفظ ولا يقرأه أحد.
        builder: (context, child) {
          final scaled = MediaQuery.withClampedTextScaling(
            minScaleFactor: AppSettings.instance.textScale,
            maxScaleFactor: AppSettings.instance.textScale,
            child: child ?? const SizedBox.shrink(),
          );
          // الآيفون: لوحة الأرقام بلا زر «تم»، فالضغط خارج الحقل يغلقها.
          if (defaultTargetPlatform != TargetPlatform.iOS) return scaled;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: scaled,
          );
        },
        home: const AppLockGate(child: LoginGate(child: HomePage())),
        routes: {'/home': (context) => const HomePage()},
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const _layoutPrefsKey = 'home_layout_grid_v1';
  static const double _homeHorizontalInset = 16;

  final TextEditingController _searchController = TextEditingController();

  int _selectedIndex = 0;
  bool _showCategoriesInTwoColumns = true;
  bool _isLoadingMetrics = true;

  /// رسالة فشل تحميل الأرقام من الخادم (null = نجح التحميل).
  String? _metricsError;
  String _selectedHomeFilter = HomeStrings.filterAll;

  /// آخر اختيار في الملخص الشامل — يعود كما تركه المستخدم.
  ScopeSelection? _summarySelection;

  /// قيم الفلتر الرئيسي للصفحة الرئيسية — نفس قالب بقية الشاشات، لكن
  /// بقسم واحد فقط (القسم) لأنه الفلتر الوحيد المنطقي على بطاقات الأقسام.
  final AppFilterValues _homeFilter = AppFilterValues();
  HomeDashboardMetrics _metrics = const HomeDashboardMetrics.empty();
  List<HomePinnedShortcut> _pinnedShortcuts = const [];
  final ScrollController _homeScrollController = ScrollController();
  late final AnimationController _categoryFlashController;
  late final Animation<double> _categoryFlashAnimation;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceCurve;
  int? _flashingCategoryIndex;
  final List<GlobalKey> _categoryKeys = List<GlobalKey>.generate(
    4,
    (_) => GlobalKey(),
  );

  /// الصورة الشخصية المحفوظة في الإعدادات (null = لا صورة).
  Uint8List? get _profilePhoto => AppSettings.instance.photo;

  /// عدد التنبيهات المستحقة فعلًا الآن — نفس منطق مركز التنبيهات:
  /// عنصر دخل نافذة تذكيره ولم يمرّ تاريخه بعد. يحترم إعدادات التنبيهات،
  /// فإن أوقفها المستخدم لم تظهر أي نقطة حمراء.
  /// عدد التنبيهات **غير المقروءة** فقط: النقطة الحمراء كانت تبقى مضاءة
  /// حتى بعد أن يقرأ المستخدم كل شيء في مركز التنبيهات.
  int get _alertsCount {
    final settings = AppSettings.instance;
    if (!settings.notificationsEnabled) return 0;
    final now = DateUtils.dateOnly(DateTime.now());
    final due = _metrics.calendarItems.where(
      (item) => HomeDashboardService.isAlertDue(
        item,
        today: now,
        defaultLead: settings.leadTimeDays,
        expiryEnabled: settings.expiryNotifications,
      ),
    );
    return ReadNotificationsStore.instance.unreadCount(due);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // الاسم والصورة وحالة إخفاء المبالغ تظهر في ترويسة الرئيسية وملخصها،
    // فأي تعديل في الإعدادات يجب أن ينعكس هنا فورًا.
    AppSettings.instance.addListener(_onSettingsChanged);
    // يوم الميلاد: تفتح نافذة التهنئة تلقائيًا مرة واحدة في ذلك اليوم.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await maybeCelebrateBirthday(context);
      // رقمك التعريفي (أول مرة) وما وصلك من حسابات أخرى.
      if (mounted) _checkAccountNotices();
      // إشعارات الجوال للتذكيرات: الإذن مرة، ثم الجدولة.
      FundlyNotifications.start();
    });
    // طلب أو رد وصل والتطبيق مفتوح: نافذة الطلبات فورًا (والإشعار بصوت
    // يظهر في الستارة من FundlyAccount.pollInbox).
    FundlyAccount.inboxArrivals.addListener(_checkAccountNotices);
    // عند الرجوع للتطبيق: الطلبات الجديدة تظهر فورًا.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _checkAccountNotices();
        FundlyNotifications.scheduleSoon();
      },
    );
    // قراءة تنبيه في مركز التنبيهات تُطفئ النقطة الحمراء فورًا.
    ReadNotificationsStore.instance.addListener(_onSettingsChanged);
    ReadNotificationsStore.instance.load();
    // ترتيب أقسام الرئيسية وإخفاؤها من «المزيد ← تخصيص الصفحة الرئيسية».
    HomeLayoutStore.notifier.addListener(_onSettingsChanged);
    HomeLayoutStore.load();
    _categoryFlashController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _categoryFlashAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_categoryFlashController);
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _entranceCurve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _searchController.addListener(() => setState(() {}));
    _bootstrapHomeState();
    _entranceController.forward();
  }

  AppLifecycleListener? _lifecycleListener;

  void _checkAccountNotices() {
    if (!mounted) return;
    AccountNotices.show(
      context,
      onOpen: (source, entryType) {
        if (source == 'delegations') {
          // تفويض وصلني ← «تفويضات وصلتني»، ورد المفوَّض ← «تفويضاتي».
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DelegationsHubPage(
                initialDirection: entryType == 'تفويض'
                    ? 'received'
                    : 'granted',
              ),
            ),
          );
          return;
        }
        // سند قبض (راتب أو عام): سندات القبض والرواتب.
        if (source == 'salary_receipts') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SalaryReceiptsScreen(),
            ),
          );
          return;
        }
        // ما فعله المفوَّض في عقار/مركبة/نشاط: يفتح العقارات والأنشطة.
        if (source == 'project_assets') {
          _openPriorityScreen('العقارات/الأنشطة التجارية/المعدات وأخرى');
          return;
        }
        _openPriorityScreen(
          source == 'shared_entries'
              ? 'الالتزامات المشتركة'
              : 'الالتزامات الشخصية',
        );
      },
    );
  }

  Future<void> _bootstrapHomeState() async {
    final prefs = await SharedPreferences.getInstance();
    final persistedLayout = prefs.getBool(_layoutPrefsKey);
    final shortcuts = await HomePinnedShortcutsStore.load();
    HomeDashboardMetrics metrics = const HomeDashboardMetrics.empty();
    String? loadError;
    try {
      final dashboardService = HomeDashboardService();
      metrics = await dashboardService.loadMetrics();
    } catch (error) {
      // كان الخطأ يُبتلع هنا صامتًا، فتظهر أصفار في كل مكان بلا أي إشارة
      // إلى أن التحميل فشل أصلًا — وهو ما جعل عطل الجلسة يبدو كأن البيانات
      // حُذفت. الآن يُحفظ الخطأ ويُعرض للمستخدم.
      metrics = const HomeDashboardMetrics.empty();
      loadError = error.toString();
    }
    if (!mounted) return;
    setState(() {
      // العرض كما اختاره المستخدم آخر مرة: مربعان في الصف أو أربعة
      // مستطيلات تحت بعض — والافتراضي المربعان.
      _showCategoriesInTwoColumns = persistedLayout ?? true;
      _pinnedShortcuts = shortcuts;
      _metrics = metrics;
      _metricsError = loadError;
      _isLoadingMetrics = false;
    });
  }

  Future<void> _refreshHomeMetrics() async {
    HapticFeedback.mediumImpact();
    try {
      final dashboardService = HomeDashboardService();
      final metrics = await dashboardService.loadMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _metricsError = null;
      });
    } catch (error) {
      // تبقى الأرقام السابقة كما هي، لكن يُعلَن الفشل بدل إخفائه.
      if (!mounted) return;
      setState(() => _metricsError = error.toString());
    }
  }

  /// تبديل العرض: مربعات (بطاقتان في الصف) أو قائمة (بطاقة في الصف)،
  /// والمختار بإطار وخلفية خضراء خفيفة.
  Widget _layoutToggle() {
    Widget option(bool twoColumns, IconData icon, String tooltip) {
      final selected = _showCategoriesInTwoColumns == twoColumns;
      return Tooltip(
        message: AppTr.tr(tooltip),
        child: InkWell(
          key: ValueKey('home-layout-${twoColumns ? 'grid' : 'list'}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            _toggleLayout();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 34,
            height: 30,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0E7161).withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFF0E7161) : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? const Color(0xFF0E7161) : AppTheme.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('home-categories-layout-toggle'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(true, Icons.grid_view_rounded, 'عرض بطاقتين في كل صف'),
          const SizedBox(width: 3),
          option(false, Icons.view_agenda_outlined, 'عرض بطاقة واحدة في كل صف'),
        ],
      ),
    );
  }

  Future<void> _toggleLayout() async {
    final next = !_showCategoriesInTwoColumns;
    setState(() => _showCategoriesInTwoColumns = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_layoutPrefsKey, next);
  }

  Future<void> _addPinnedShortcut(HomePinnedShortcut shortcut) async {
    if (_pinnedShortcuts.any((item) => item.id == shortcut.id)) return;
    final next = [..._pinnedShortcuts, shortcut];
    setState(() => _pinnedShortcuts = next);
    await HomePinnedShortcutsStore.save(next);
  }

  Future<void> _removePinnedShortcut(
    String shortcutId, {
    bool confirm = false,
  }) async {
    // زر ✕ في الرئيسية: تنبيه قبل الإزالة (من هنا فقط، لا من التطبيق).
    if (confirm) {
      final match = _pinnedShortcuts.where((item) => item.id == shortcutId);
      final name = match.isEmpty ? '' : match.first.title;
      final ok = await confirmAction(
        context,
        title: 'إزالة من المثبتة',
        message:
            '${name.isEmpty ? '' : '«$name»\n'}'
            '${AppTr.tr('سيُزال من هنا فقط ولن يُحذف من التطبيق، ويمكنك تثبيته مرة أخرى بزر +.')}',
        confirmLabel: 'إزالة',
        cancelLabel: 'رجوع',
      );
      if (!ok || !mounted) return;
    }
    final next = _pinnedShortcuts
        .where((item) => item.id != shortcutId)
        .toList(growable: false);
    setState(() => _pinnedShortcuts = next);
    await HomePinnedShortcutsStore.save(next);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    ReadNotificationsStore.instance.removeListener(_onSettingsChanged);
    HomeLayoutStore.notifier.removeListener(_onSettingsChanged);
    _lifecycleListener?.dispose();
    FundlyAccount.inboxArrivals.removeListener(_checkAccountNotices);
    _searchController.dispose();
    _homeScrollController.dispose();
    _categoryFlashController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  /// شريحة الفلتر النشط: تُظهر اسم الفلتر وتلغيه بضغطة واحدة.
  Widget _buildActiveFilterChip() {
    return Row(
      children: [
        Flexible(
          child: Material(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('home-active-filter-clear'),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(
                  () => _selectedHomeFilter = HomeStrings.filterAll,
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.filter_alt_rounded,
                      size: 16,
                      color: AppTheme.accentDark,
                    ),
                    const SizedBox(width: AppTheme.sSm),
                    Flexible(
                      child: Text(
                        'الفلتر: $_selectedHomeFilter',
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.sSm),
                    const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppTheme.accentDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// شريط فشل التحميل: يظهر فقط حين يفشل جلب الأرقام فعلًا، والضغط عليه
  /// يعيد المحاولة.
  Widget _buildMetricsErrorBanner() {
    return Material(
      color: AppTheme.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-metrics-error-banner'),
        onTap: () {
          HapticFeedback.selectionClick();
          _bootstrapHomeState();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.sLg),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 20,
                color: AppTheme.warning,
              ),
              const SizedBox(width: AppTheme.sSm),
              const Expanded(
                child: Text(
                  'تعذّر تحميل البيانات من الخادم، والأرقام أدناه غير '
                  'محدَّثة. اضغط لإعادة المحاولة.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
              ),
              const AppChevron(),
            ],
          ),
        ),
      ),
    );
  }

  // ===== ألوان وقياسات لوحة الملخص (رموز تصميم موحّدة في مكان واحد) =====
  static const _panelSurface = Color(0xFFF2F6F5);
  static const _panelBorder = Color(0xFFE4EAE8);
  // ألوان البطاقة المميّزة من نسق التطبيق نفسه (الأخضر المزرقّ) بدل
  // البنفسجي الغريب عن بقية الشاشات.
  static const _summaryAccentTop = AppTheme.accent;
  static const _summaryAccentBottom = AppTheme.accentDark;
  static const _rPanel = 22.0;
  static const _rInnerPanel = 18.0;

  /// لوحة الملخص الشامل: يمينًا مستطيل «ملخص شامل» بطول اللوحة ومحتواه في
  /// المنتصف، ويسارًا «+ ثبّت ما تستخدمه كثيرًا» والعناصر المثبتة تحته.
  Widget _buildSummaryAndPinnedRow() {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Container(
        key: const ValueKey('home-summary-pin-panel'),
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(_rPanel),
          border: Border.all(color: _panelBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: _buildSummaryBlock()),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPinHeader(),
                    const SizedBox(height: 8),
                    _buildPinnedTiles(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// مستطيل «ملخص شامل»: أيقونة أكبر وخط أكبر، والمحتوى في المنتصف.
  Widget _buildSummaryBlock() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 132),
      child: _PressableScale(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_rInnerPanel),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home-summary-open'),
            // الملخص يُفتح مباشرة: صفحة «الملخص» بتبويباتها وفلتر الفترة.
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GlobalSummaryScreen()),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_rInnerPanel),
                border: Border.all(color: _panelBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          _summaryAccentTop,
                          _summaryAccentTop,
                          _summaryAccentBottom,
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x335C6B68),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: 1.2,
                        child: const _SummaryFolderStarIcon(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'ملخص شامل',
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accentDark,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'عرض البيانات',
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// «+ ثبّت ما تستخدمه كثيرًا» — يفتح نافذة التثبيت.
  Widget _buildPinHeader() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_rInnerPanel),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-pin-picker'),
        onTap: () {
          HapticFeedback.selectionClick();
          _openPinPicker();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_rInnerPanel),
            border: Border.all(color: _panelBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: AppTheme.accentDark,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'ثبّت ما تستخدمه كثيرًا',
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// العناصر المثبتة: مربعات صغيرة تحت «ثبّت ما تستخدمه كثيرًا».
  Widget _buildPinnedTiles() {
    if (_pinnedShortcuts.isEmpty) {
      return Padding(
        key: const ValueKey('home-pin-empty'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          'لا توجد عناصر مثبتة — اضغط + لتثبيت ما تستخدمه كثيرًا',
          textAlign: TextAlign.center,
          maxLines: 4,
          style: AppTheme.emptyText.copyWith(fontSize: 10.5, height: 1.3),
        ),
      );
    }
    // صف واحد جنب بعض يُسحب أفقيًا — لا أسطر فوق بعض مهما زادت المثبتات.
    return SingleChildScrollView(
      key: const ValueKey('home-pinned-row'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _pinnedShortcuts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _HomePinnedTile(
              key: ValueKey('home-pinned-${_pinnedShortcuts[i].id}'),
              shortcut: _pinnedShortcuts[i],
              onOpen: () => _openShortcut(_pinnedShortcuts[i]),
              onRemove: () => _removePinnedShortcut(
                _pinnedShortcuts[i].id,
                confirm: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// الملخص الشامل: يفتح قالب الاختيار الموحّد (البحث ← القسم ← الأقسام
  /// المطلوب إظهارها ← الأنواع ← التصفية ← التاريخ ← العنوان)، ثم يعرض
  /// النتيجة التفصيلية من السجلات الحقيقية مع إمكانية إرسالها.
  Future<void> _openGlobalSummarySheet() async {
    final messenger = ScaffoldMessenger.of(context);
    List<SummaryItem> items;
    try {
      items = await HomeSummaryService().loadItems();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر تحميل البيانات. حاول مرة أخرى.')),
      );
      return;
    }
    if (!mounted) return;
    final selection = await showScopeBuilderSheet(
      context: context,
      kind: 'الملخص',
      accent: AppTheme.accent,
      items: items,
      initial: _summarySelection,
    );
    if (selection == null || !mounted) return;
    setState(() => _summarySelection = selection);
    final matched = items.where(selection.matches).toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.page,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: FractionallySizedBox(
          heightFactor: 1,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE4EAE8)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('close-global-summary'),
                      tooltip: AppTr.tr('إغلاق'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        selection.title.isEmpty
                            ? 'الملخص الشامل'
                            : selection.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF022E2A),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('global-summary-back'),
                      tooltip: AppTr.tr('تعديل الاختيار'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openGlobalSummarySheet();
                      },
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('global-summary-result'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    ScopeResultView(
                      selection: selection,
                      items: matched,
                      accent: AppTheme.accent,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('send-selected-summary'),
                      onPressed: () => _shareSummary(
                        title: selection.title.isEmpty
                            ? 'الملخص الشامل'
                            : selection.title,
                        lines: scopeResultLines(selection, matched),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text(HomeStrings.summaryShareText),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('send-selected-summary-pdf'),
                      onPressed: () => _shareSummary(
                        title: selection.title.isEmpty
                            ? 'الملخص الشامل'
                            : selection.title,
                        lines: scopeResultLines(selection, matched),
                        asPdf: true,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text(HomeStrings.summarySharePdf),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareSummary({
    required String title,
    required List<String> lines,
    bool asPdf = false,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final text = '$title\n\n${lines.join('\n')}';
    if (asPdf) {
      final file = XFile.fromData(
        Uint8List.fromList(text.codeUnits),
        mimeType: 'application/pdf',
        name: 'fondly-summary.pdf',
      );
      await SharePlus.instance.share(
        ShareParams(
          subject: title,
          text: title,
          files: [file],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: title,
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// الأرقام في الرئيسية بالإنجليزية (0-9) في كل اللغات، مثل بقية التطبيق.
  String _formatArabicNumber(int value) => value.toString();

  /// المبالغ تُخفى عند تفعيل "إخفاء المبالغ الحساسة" في الإعدادات — كان
  /// ذلك الإعداد يُحفظ ولا يؤثر في شيء.
  String _formatAmount(int value) =>
      AppSettings.maskAmount(_formatArabicNumber(value));

  String _formatCountWithUnit(int value, String unit) {
    return '${_formatArabicNumber(value)} $unit';
  }

  /// فلتر الصفحة الرئيسية: الأقسام بترتيبها، واختيار قسم يُظهر تحته فلترَه نفسه (كما في شاشته)،
  /// و«تطبيق الفلتر» يفتح القسم مطبَّقًا عليه ما اختير.
  void _openHomeFilterSheet() {
    const modules = [
      'الكل',
      'الالتزامات الشخصية',
      'الالتزامات المشتركة',
      'الأفراد والجهات',
      'العقارات',
      'الأنشطة التجارية',
      'المركبات ووسائل النقل',
    ];
    showAppFilterSheet(
      context: context,
      title: 'الصفحة الرئيسية',
      accent: AppTheme.accent,
      values: AppFilterValues(),
      sections: const [],
      onApply: (_) {},
      modules: modules,
      initialModule: 'الكل',
      moduleConfigFor: (module) => switch (module) {
        'الالتزامات الشخصية' => personalFilterModuleConfig(),
        'الالتزامات المشتركة' => sharedFilterModuleConfig(),
        'الأفراد والجهات' => peopleFilterModuleConfig(),
        'العقارات' ||
        'الأنشطة التجارية' ||
        'المركبات ووسائل النقل' => assetsFilterModuleConfig(module),
        // «الكل»: نفس فلاتر الأقسام (التاريخ، الحالة، المبلغ، الأفراد)
        // على كل البيانات.
        _ => const AppFilterModuleConfig(
          fixedMainCategory: 'الكل',
          sectionsFor: _allSectionsFor,
        ),
      },
      onApplyModule: _applyHomeModuleFilter,
    );
  }

  static List<AppFilterSection> _allSectionsFor(String _) => const [
    AppFilterSection.period,
    AppFilterSection.statusSelect,
    AppFilterSection.amountSelect,
    AppFilterSection.people,
  ];

  /// نتائج فلتر «الكل»: كل السجلات من كل الأقسام بحسب ما اختير.
  Future<void> _showAllFilterResults(AppFilterValues v) async {
    List<SummaryItem> items;
    try {
      items = await HomeSummaryService().loadItems();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحميل البيانات. حاول مرة أخرى.')),
      );
      return;
    }
    if (!mounted) return;
    bool closed(SummaryItem item) => const {
      'منتهية',
      'منتهي',
      'مغلقة',
      'مكتملة',
      'مسددة',
      'ملغاة',
      'تمت التسوية',
      'مؤرشف',
    }.contains(item.status);
    final from = v.dateFrom == null ? null : DateUtils.dateOnly(v.dateFrom!);
    final to = v.dateTo == null ? null : DateUtils.dateOnly(v.dateTo!);
    final person = v.personName.trim();
    final today = DateUtils.dateOnly(DateTime.now());
    final matched = items.where((item) {
      final date = item.date ?? item.createdAt;
      if (from != null || to != null) {
        if (date == null) return false;
        final day = DateUtils.dateOnly(date);
        if (from != null && day.isBefore(from)) return false;
        if (to != null && day.isAfter(to)) return false;
      }
      switch (v.status) {
        case 'نشط':
          if (closed(item)) return false;
        case 'قريبة الاستحقاق':
          if (!item.isDueSoon || closed(item)) return false;
        case 'مستحقة':
          if (item.followDay == null ||
              !DateUtils.isSameDay(item.followDay, today) ||
              closed(item)) {
            return false;
          }
        case 'متأخرة':
          if (!item.isOverdue) return false;
        case 'مكتملة':
          if (!closed(item)) return false;
      }
      if (v.amountShortcut == 'مخصص') {
        if (v.amountFrom != null && item.amount < v.amountFrom!) return false;
        if (v.amountTo != null && item.amount > v.amountTo!) return false;
      }
      if (person.isNotEmpty &&
          !matchesSearchQuery(
            query: person,
            fields: [item.person, item.title, item.subtitle],
          )) {
        return false;
      }
      return true;
    }).toList();
    if (v.status == 'الأحدث أولاً') {
      matched.sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );
    }
    if (v.amountShortcut == 'أعلى مبلغًا') {
      matched.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (v.amountShortcut == 'أقل مبلغًا') {
      matched.sort((a, b) => a.amount.compareTo(b.amount));
    }
    final selection = ScopeSelection(title: AppTr.tr('نتائج الفلتر — الكل'));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.page,
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: FractionallySizedBox(
          heightFactor: 1,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE4EAE8)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        selection.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF022E2A),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('تعديل الفلتر'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openHomeFilterSheet();
                      },
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: matched.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'لا توجد بيانات تطابق الفلتر.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          ScopeResultView(
                            selection: selection,
                            items: matched,
                            accent: AppTheme.accent,
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => _shareSummary(
                              title: selection.title,
                              lines: scopeResultLines(selection, matched),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text(HomeStrings.summaryShareText),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تطبيق فلتر الصفحة الرئيسية: «الكل» يُظهر كل البطاقات، وأي قسم آخر
  /// يُفتح بشاشته مطبَّقًا عليه الفلتر.
  void _applyHomeModuleFilter(String module, AppFilterValues values) {
    if (module == 'الكل') {
      setState(() {
        _selectedHomeFilter = HomeStrings.filterAll;
        _homeFilter.mainCategory = HomeStrings.filterAll;
      });
      // «الكل» بفلتر: نتائج من كل الأقسام (بعد إغلاق نافذة الفلتر).
      // بلا أي اختيار: كل الأقسام تظهر في الرئيسية فقط.
      final hasFilter =
          values.dateFrom != null ||
          values.dateTo != null ||
          (values.status.isNotEmpty && values.status != 'كل الحالات') ||
          values.amountShortcut != null ||
          values.personName.trim().isNotEmpty;
      if (hasFilter) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _showAllFilterResults(values);
        });
      }
      return;
    }
    const assetKeys = {
      'العقارات': 'real_estate',
      'الأنشطة التجارية': 'activity',
      'المركبات ووسائل النقل': 'equipment',
    };
    final Widget screen = switch (module) {
      'الالتزامات الشخصية' => PersonalCommitmentsScreen(initialFilter: values),
      'الالتزامات المشتركة' => SharedCommitmentsScreen(initialFilter: values),
      'الأفراد والجهات' => PeopleManagementScreen(initialFilter: values),
      _ => ProjectsActivitiesScreen(
        initialFilter: assetKeys[module] ?? 'all',
        initialValues: values,
      ),
    };
    // بعد إغلاق نافذة الفلتر، وإلا أغلق إغلاقُها الصفحةَ المفتوحة للتو.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    });
  }

  Future<void> _openPinPicker() async {
    if (!await FundlyAuth.requireLogin(context)) return;
    final itemsFuture = HomePinItemsService().load();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Container(
              key: const ValueKey('pin-picker-sheet'),
              height: MediaQuery.sizeOf(context).height * 0.76,
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF9),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26022E2A),
                    blurRadius: 30,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Map<String, List<HomePinnedShortcut>>>(
                future: itemsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const _PinPickerLoading();
                  }
                  final items = snapshot.data!;
                  return DefaultTabController(
                    length: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 16, 14, 15),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2F6F5),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE4EAE8)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E7161),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.push_pin_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تثبيت عنصر في الصفحة الرئيسية',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF04413B),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'اختر الوحدة وثبّت العناصر التي تحتاجها سريعًا',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF5C6B68),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: AppTr.tr('إغلاق'),
                                onPressed: () => Navigator.of(context).pop(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF5C6B68),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 64,
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                          color: Colors.white,
                          child: const TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerColor: Colors.transparent,
                            labelColor: Color(0xFF0E7161),
                            unselectedLabelColor: Color(0xFF76837F),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: Color(0xFFF2F6F5),
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                              border: Border.fromBorderSide(
                                BorderSide(color: Color(0xFFD5DEDB)),
                              ),
                            ),
                            tabs: [
                              Tab(
                                key: ValueKey('pin-tab-personal'),
                                icon: Icon(
                                  Icons.person_outline_rounded,
                                  size: 17,
                                ),
                                text: 'الشخصية',
                                iconMargin: EdgeInsets.only(bottom: 2),
                              ),
                              Tab(
                                key: ValueKey('pin-tab-shared'),
                                icon: Icon(Icons.groups_2_outlined, size: 17),
                                text: 'المشتركة',
                                iconMargin: EdgeInsets.only(bottom: 2),
                              ),
                              Tab(
                                key: ValueKey('pin-tab-people'),
                                icon: Icon(Icons.badge_outlined, size: 17),
                                text: 'الأفراد والجهات',
                                iconMargin: EdgeInsets.only(bottom: 2),
                              ),
                              Tab(
                                key: ValueKey('pin-tab-assets'),
                                icon: Icon(Icons.apartment_rounded, size: 17),
                                text: 'العقارات والأنشطة والمركبات',
                                iconMargin: EdgeInsets.only(bottom: 2),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: HomePinItemsService.moduleIds
                                .map(
                                  (moduleId) => _PinItemsList(
                                    moduleId: moduleId,
                                    items: items[moduleId] ?? const [],
                                    isPinned: (id) => _pinnedShortcuts.any(
                                      (shortcut) => shortcut.id == id,
                                    ),
                                    onToggle: (item) async {
                                      final pinned = _pinnedShortcuts.any(
                                        (shortcut) => shortcut.id == item.id,
                                      );
                                      if (pinned) {
                                        await _removePinnedShortcut(item.id);
                                      } else {
                                        await _addPinnedShortcut(item);
                                      }
                                    },
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openShortcut(HomePinnedShortcut shortcut) {
    final moduleId = shortcut.moduleId.isEmpty
        ? shortcut.id.split(':').first
        : shortcut.moduleId;
    // فئة كاملة مثبّتة: تُفتح وحدتها على تلك الفئة.
    if (shortcut.id.contains(':group:') && shortcut.group.isNotEmpty) {
      final group = shortcut.group;
      switch (moduleId) {
        case 'personal':
          _applyHomeModuleFilter(
            HomeStrings.filterPersonal,
            AppFilterValues(mainCategory: group),
          );
        case 'shared':
          _applyHomeModuleFilter(
            HomeStrings.filterShared,
            AppFilterValues(mainCategory: group),
          );
        case 'people':
          _applyHomeModuleFilter(
            HomeStrings.filterPeople,
            AppFilterValues(mainCategory: group),
          );
        default:
          _applyHomeModuleFilter(group, AppFilterValues());
      }
      return;
    }
    // عنصر بعينه مثبّت: يُفتح على ملخصه مباشرة، والرجوع منه للرئيسية.
    final colon = shortcut.id.indexOf(':');
    final itemKey = colon < 0 ? '' : shortcut.id.substring(colon + 1).trim();
    if (itemKey.isNotEmpty) {
      final Widget page = switch (moduleId) {
        'personal' => PersonalCommitmentsScreen(openEntryId: itemKey),
        'shared' => SharedCommitmentsScreen(openEntryId: itemKey),
        'people' => PeopleManagementScreen(openPersonName: itemKey),
        _ => ProjectsActivitiesScreen(openAssetId: itemKey),
      };
      // الالتزام أو الأصل يُفتح على تفاصيله مباشرة (صفحة واحدة).
      Navigator.of(context).push(
        moduleId == 'people'
            ? MaterialPageRoute(builder: (_) => page)
            : directOpenRoute(page),
      );
      return;
    }
    if (moduleId == 'personal') {
      _openPriorityScreen(HomeStrings.modulePersonal);
      return;
    }
    if (moduleId == 'shared') {
      _openPriorityScreen(HomeStrings.moduleShared);
      return;
    }
    if (moduleId == 'people') {
      _openPriorityScreen('إدارة الأشخاص والجهات');
      return;
    }
    _openPriorityScreen('العقارات/الأنشطة التجارية/المعدات وأخرى');
  }

  void _openAccountPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsHubPage()));
  }

  /// زر أيقونة داخل الترويسة الملوّنة: مربّع شفاف بحواف دائرية وأيقونة
  /// بيضاء — نفس شكل أزرار الترويسة في التصميم المعتمد.
  Widget _headerIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    bool badge = false,
    Key? key,
    String? label,
  }) {
    final button = _headerIconOnly(
      tooltip: tooltip,
      icon: icon,
      onTap: onTap,
      badge: badge,
      key: key,
    );
    if (label == null) return button;
    // اسم الزر تحته: التقويم، التنبيهات، القرعة.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 2),
        SizedBox(
          width: 40,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerIconOnly({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    bool badge = false,
    Key? key,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          // أصغر حتى لا تضيّق على اسم المستخدم.
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, size: 17, color: Colors.white)),
                if (badge)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5533D),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// تنبيه الميلاد: يظهر قبل الميلاد بخمسة أيام فأقل، وفي يوم الميلاد
  /// يصير تهنئة. يعتمد على تاريخ الميلاد المحفوظ في صفحة الحساب.
  Widget _buildBirthdayBanner() {
    final days = AppSettings.instance.daysToBirthday;
    if (days == null || days > 5) return const SizedBox.shrink();
    final isToday = days == 0;
    final message = isToday
        ? 'كل عام وأنت بخير — اليوم عيد ميلادك 🎂'
        : days == 1
        ? 'باقي يوم واحد على عيد ميلادك'
        : 'باقي $days أيام على عيد ميلادك';
    final color = isToday ? AppTheme.brandMid : AppTheme.goldDark;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        _homeHorizontalInset,
        0,
        _homeHorizontalInset,
        10,
      ),
      child: InkWell(
        onTap: () => showBirthdaySheet(context),
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              Icon(Icons.cake_outlined, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  textAlign: AppTr.alignEnd,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.chevron_left_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }

  /// لوحة الترويسة: مساحة بلون الهوية حوافها السفلية منحنية وتنتهي عند
  /// منتصف شريط البحث، فيبدو الشريط جالسًا على المنحنى ولا تبقى أي مساحة
  /// خضراء تحته.
  Widget _buildHomeHeaderPanel() {
    const searchHeight = 54.0;
    return Stack(
      children: [
        // الخلفية الملوّنة: تمتد سطرًا واحدًا تحت شريط البحث ثم تنحني.
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.brandMid, AppTheme.brand],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // دوائر زخرفية خفيفة كما في التصميم.
                Positioned(
                  top: -58,
                  left: -30,
                  child: Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  top: 22,
                  left: 96,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
              child: Directionality(
                textDirection: AppTr.uiDir,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الحساب: الشعار والاسم — نفس محتوى الترويسة السابق.
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const ValueKey('home-account-entry'),
                              // الضيف: الدخول أو التسجيل بدل الإعدادات.
                              onTap: FundlyAuth.isGuest
                                  ? () => openLoginScreen(context)
                                  : _openAccountPage,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      HomeStrings.homeTagline,
                                      maxLines: 3,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(
                                          alpha: 0.82,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      textDirection: AppTr.uiDir,
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          clipBehavior: Clip.antiAlias,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.18,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: FundlyAuth.isGuest
                                              ? const Icon(
                                                  Icons.login_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
                                              : _profilePhoto == null
                                              ? const Icon(
                                                  Icons.person_rounded,
                                                  size: 17,
                                                  color: Colors.white,
                                                )
                                              : Image.memory(
                                                  _profilePhoto!,
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        // الاسم كاملًا (يصغر خطه عند
                                        // الحاجة بدل قصّه).
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment:
                                                AlignmentDirectional.centerStart,
                                            child: Text(
                                              FundlyAuth.isGuest
                                                  ? 'تسجيل الدخول / إنشاء حساب'
                                                  : AppSettings.instance.name,
                                              maxLines: 3,
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _headerIconButton(
                          tooltip: AppTr.tr('التقويم الذكي'),
                          label: 'التقويم',
                          icon: Icons.calendar_month_rounded,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SmartCalendarScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _headerIconButton(
                          tooltip: AppTr.tr('الإشعارات'),
                          label: 'التنبيهات',
                          icon: _alertsCount > 0
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          badge: _alertsCount > 0,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const NotificationsCenterScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _headerIconButton(
                          tooltip: HomeStrings.raffle,
                          label: 'القرعة',
                          icon: Icons.casino_outlined,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RaffleScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // شريط البحث الأبيض جالس على حافة المنحنى، وزر الفلتر
                    // داخله يفصله خط رفيع.
                    Container(
                      height: searchHeight,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF022E2A,
                            ).withValues(alpha: 0.10),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        textDirection: AppTr.uiDir,
                        children: [
                          const SizedBox(width: 14),
                          const Icon(
                            Icons.search_rounded,
                            size: 22,
                            color: AppTheme.chevron,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textDirection: AppTr.uiDir,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.title,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: HomeStrings.searchHint,
                                hintStyle: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                suffixIcon: _searchController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: AppTheme.muted,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          _searchController.clear();
                                        },
                                      ),
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: AppTheme.line,
                          ),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: const ValueKey('home-filter-button'),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _openHomeFilterSheet();
                              },
                              child: SizedBox(
                                width: 52,
                                height: searchHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Center(
                                      child: Icon(
                                        Icons.tune_rounded,
                                        color: AppTheme.brandMid,
                                        size: 22,
                                      ),
                                    ),
                                    if (_selectedHomeFilter !=
                                        HomeStrings.filterAll)
                                      Positioned(
                                        top: 13,
                                        left: 11,
                                        child: Container(
                                          width: 9,
                                          height: 9,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2A93F),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: _selectedIndex == 0
          ? RefreshIndicator(
              onRefresh: _refreshHomeMetrics,
              color: const Color(0xFF0A5A50),
              child: CustomScrollView(
                controller: _homeScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 196,
                    toolbarHeight: 196,
                    floating: false,
                    pinned: true,
                    // خلفية الشريط بلون الصفحة: المساحة الخضراء نفسها
                    // داخل اللوحة وتنتهي عند المنحنى، فلا يظهر أخضر تحت
                    // شريط البحث. أيقونات شريط الحالة بيضاء فوق المنحنى.
                    backgroundColor: AppTheme.page,
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHomeHeaderPanel(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Directionality(
                      textDirection: AppTr.uiDir,
                      child: FadeTransition(
                        opacity: _entranceCurve,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(_entranceCurve),
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              _buildBirthdayBanner(),
                              // الفلتر النشط ظاهر دائمًا: كان اختيار فلتر
                              // يُخفي ثلاثة من أربعة صناديق بلا أي أثر مرئي،
                              // فيبدو كأن الأقسام اختفت من التطبيق.
                              if (_selectedHomeFilter != HomeStrings.filterAll)
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                    _homeHorizontalInset,
                                    0,
                                    _homeHorizontalInset,
                                    10,
                                  ),
                                  child: _buildActiveFilterChip(),
                                ),
                              if (_metricsError != null)
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                    _homeHorizontalInset,
                                    0,
                                    _homeHorizontalInset,
                                    10,
                                  ),
                                  child: _buildMetricsErrorBanner(),
                                ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  _homeHorizontalInset,
                                  0,
                                  _homeHorizontalInset,
                                  10,
                                ),
                                child: _buildSummaryAndPinnedRow(),
                              ),
                              // «الطلبات»: كل ما ينتظر ردك أو اعتمادك، وما
                              // أرسلته — بنفس شكل «الملخص الشامل».
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  _homeHorizontalInset,
                                  0,
                                  _homeHorizontalInset,
                                  10,
                                ),
                                child: RequestsCenterCard(
                                  refresh: FundlyAccount.inboxArrivals,
                                  onOpenDelegations: () =>
                                      Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const _DelegationsHubPage(
                                        initialDirection: 'received',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                // مسافة أقل أسفل العنوان منها أعلاه، فيلتصق
                                // بصفّ البطاقات الذي يعنونه بدل أن يطفو في
                                // منتصف الفراغ بين مركز المتابعة والبطاقات.
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.pageInset,
                                  8,
                                  AppTheme.pageInset,
                                  6,
                                ),
                                // عنوان القسم بنمط العناوين الموحّد: العنوان
                                // أقصى اليمين وزر تبديل العرض أقصى اليسار.
                                child: AppSectionTitle(
                                  text: HomeStrings.manageTitle,
                                  trailing: _layoutToggle(),
                                ),
                              ),
                              if (_isLoadingMetrics)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else
                                _buildTopCategories(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _buildSecondaryTabView(),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildSecondaryTabView() {
    if (_selectedIndex == 1) {
      return const _ReportsArchiveHubPage();
    }
    // «المستندات» مكان «المحافظ» (حُذفت صفحة المحافظ).
    if (_selectedIndex == 2) {
      return const DocumentsHubPage();
    }
    return const ProfileSettingsScreen(delegationsPage: _DelegationsHubPage());
  }

  Widget _buildTopCategories() {
    final categories = [
      (
        HomeStrings.modulePersonal,
        Icons.person_outline_rounded,
        const Color(0xFF0E7161),
        [
          (
            'مالية تحتاج متابعة: ${_formatArabicNumber(_metrics.personalMoneyFollowup)}',
            Icons.payments_outlined,
            const Color(0xFFA6691A),
          ),
          (
            'مستندات تحتاج متابعة: ${_formatArabicNumber(_metrics.personalDocsFollowup)}',
            Icons.description_outlined,
            const Color(0xFF0A5A50),
          ),
        ],
      ),
      (
        HomeStrings.moduleShared,
        Icons.groups_2_outlined,
        // لون الوحدة نفسه في ترويسة صفحتها (tint).
        const Color(0xFF2B8CB0),
        [
          (
            'مالية تحتاج متابعة: ${_formatArabicNumber(_metrics.sharedMoneyFollowup)}',
            Icons.payments_outlined,
            const Color(0xFFA6691A),
          ),
          (
            'مستندات تحتاج متابعة: ${_formatArabicNumber(_metrics.sharedDocsFollowup)}',
            Icons.description_outlined,
            const Color(0xFF0A5A50),
          ),
        ],
      ),
      (
        'إدارة الأشخاص والجهات',
        Icons.people_alt_outlined,
        const Color(0xFF6B6FC7),
        [
          (
            'مالية تحتاج متابعة: ${_formatArabicNumber(_metrics.peopleMoneyFollowup)}',
            Icons.payments_outlined,
            const Color(0xFFA6691A),
          ),
          (
            'مستندات تحتاج متابعة: ${_formatArabicNumber(_metrics.peopleDocsFollowup)}',
            Icons.description_outlined,
            const Color(0xFF0A5A50),
          ),
        ],
      ),
      (
        'العقارات/الأنشطة التجارية/المعدات وأخرى',
        Icons.apartment_rounded,
        const Color(0xFFD9902A),
        [
          (
            'مالية تحتاج متابعة: ${_formatArabicNumber(_metrics.assetsMoneyFollowup)}',
            Icons.payments_outlined,
            const Color(0xFFA6691A),
          ),
          (
            'مستندات تحتاج متابعة: ${_formatArabicNumber(_metrics.assetsDocsFollowup)}',
            Icons.description_outlined,
            const Color(0xFF0A5A50),
          ),
        ],
      ),
    ];

    // ترتيب المستخدم وإخفاؤه (من «تخصيص الصفحة الرئيسية»).
    final layout = HomeLayoutStore.notifier.value;
    String layoutIdOf(String title) {
      if (title == HomeStrings.modulePersonal) return HomeLayoutStore.personal;
      if (title == HomeStrings.moduleShared) return HomeLayoutStore.shared;
      if (title == 'إدارة الأشخاص والجهات') return HomeLayoutStore.people;
      return HomeLayoutStore.assets;
    }

    final orderedCategories = [
      for (final id in layout.order)
        if (layout.isVisible(id))
          ...categories.where((category) => layoutIdOf(category.$1) == id),
    ];

    final query = _searchController.text.trim();
    final filteredCategories = orderedCategories
        .where((category) {
          final matchesFilter =
              _selectedHomeFilter == HomeStrings.filterAll ||
              (_selectedHomeFilter == HomeStrings.filterPersonal &&
                  category.$1 == HomeStrings.modulePersonal) ||
              (_selectedHomeFilter == HomeStrings.filterShared &&
                  category.$1 == HomeStrings.moduleShared) ||
              (_selectedHomeFilter == HomeStrings.filterPeople &&
                  category.$1 == 'إدارة الأشخاص والجهات') ||
              (_selectedHomeFilter == HomeStrings.filterAssets &&
                  category.$1 == 'العقارات/الأنشطة التجارية/المعدات وأخرى');

          // مطابقة موحّدة عربيًا (تتجاهل فروق الهمزة والتاء المربوطة
          // والتشكيل) بدل مقارنة نصية خام كانت تفشل مع "الشخصيه"/"الشخصية".
          final matchesQuery =
              query.isEmpty ||
              matchesSearchQuery(
                query: query,
                fields: [
                  category.$1,
                  ...category.$4.map((metric) => metric.$1),
                ],
              );
          return matchesFilter && matchesQuery;
        })
        .toList(growable: false);

    if (filteredCategories.isEmpty) {
      // بلا هذه الحالة كانت الشاشة تظهر فارغة تمامًا بلا تفسير حين يستبعد
      // الفلتر أو البحث كل الأقسام.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageInset),
        child: AppInnerCard(
          // رمادي لا أبيض: خلفية الصفحة بيضاء، فالبطاقة البيضاء تختفي.
          background: AppTheme.surface,
          padding: const EdgeInsets.all(AppTheme.sXl),
          child: Center(
            child: Text(
              'لا يوجد قسم مطابق للبحث أو الفلتر الحالي.',
              textAlign: TextAlign.center,
              style: AppTheme.emptyText,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageInset),
      child: GridView.builder(
        key: const ValueKey('home-categories-grid'),
        itemCount: filteredCategories.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _showCategoriesInTwoColumns ? 2 : 1,
          crossAxisSpacing: AppTheme.cardGap,
          mainAxisSpacing: AppTheme.cardGap,
          // ارتفاع متوسط محسوب على المحتوى: حشوة (20) + شريط العنوان
          // (56) + فاصل (6) + رقما المتابعة (46) — في الوضعين.
          mainAxisExtent: _showCategoriesInTwoColumns ? 134 : 128,
        ),
        itemBuilder: (context, index) {
          final category = filteredCategories[index];
          return KeyedSubtree(
            key: _categoryKeys[index],
            child: _buildCategoryTileCompact(
              category.$1,
              category.$2,
              category.$3,
              category.$4,
              index,
              compact: _showCategoriesInTwoColumns,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryTileCompact(
    String title,
    IconData icon,
    Color color,
    List<(String, IconData, Color)> items,
    int categoryIndex, {
    required bool compact,
  }) {
    return AnimatedBuilder(
      animation: _categoryFlashAnimation,
      builder: (context, child) {
        final flash = _flashingCategoryIndex == categoryIndex
            ? _categoryFlashAnimation.value
            : 0.0;
        // بطاقة رمادية ناعمة بلا حدود ولا ظل — نفس البطاقة الخارجية
        // الموحّدة. الوميض عند الوصول من اختصار يلوّن الخلفية مؤقتًا فقط،
        // بدل حدّ ملوّن سميك يجعل كل بطاقة تبدو مختلفة عن أختها.
        return _PressableScale(
          child: Material(
            color: Color.lerp(
              AppTheme.surface,
              color.withValues(alpha: 0.16),
              flash,
            ),
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('home-category-$categoryIndex'),
              onTap: () {
                HapticFeedback.selectionClick();
                _openPriorityScreen(title);
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Directionality(
        textDirection: AppTr.uiDir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط العنوان: نفس لون ترويسة صفحة الوحدة من الداخل
            // (moduleTintFill بلون الوحدة)، فيبقى اللون واحدًا خارجها وداخلها.
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: moduleTintFill(color),
                borderRadius: BorderRadius.circular(AppTheme.rInner),
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 38 : 42,
                    height: compact ? 38 : 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, Color.lerp(color, Colors.black, 0.18)!],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: compact ? 21 : 23,
                    ),
                  ),
                  const SizedBox(width: AppTheme.sSm),
                  Expanded(
                    // العنوان كاملًا: سطران في المربع، وسطر واحد في
                    // المستطيل يصغر خطه بدل القص.
                    child: () {
                      final shown = switch (title) {
                        'العقارات/الأنشطة التجارية/المعدات وأخرى' =>
                          'العقارات والأنشطة والمركبات',
                        'إدارة الأشخاص والجهات' => 'الأفراد والجهات',
                        _ => title,
                      };
                      final style = TextStyle(
                        fontSize: compact ? 13 : 15.5,
                        height: compact ? 1.15 : 1.25,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      );
                      final key = ValueKey('home-category-title-$categoryIndex');
                      if (compact) {
                        return Text(
                          key: key,
                          shown,
                          maxLines: 3,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        );
                      }
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          key: key,
                          shown,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      );
                    }(),
                  ),
                  const SizedBox(width: AppTheme.sXs),
                  const AppChevron(size: 22),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // رقما المتابعة: الكلمة فوق، والأيقونة والرقم بخط كبير تحتها،
            // بينهما خط فاصل رفيع.
            Expanded(
              child: Row(
                children: [
                  for (
                    var index = 0;
                    index < (items.length < 3 ? items.length : 3);
                    index++
                  ) ...[
                    if (index > 0)
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        color: AppTheme.hairline,
                      ),
                    Expanded(
                      child: _HomeCategoryStat(
                        label: items[index].$1,
                        icon: items[index].$2,
                        color: items[index].$3,
                        large: !compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPriorityScreen(String title) {
    if (title == 'الالتزامات الشخصية') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PersonalCommitmentsScreen()),
      );
      return;
    }

    if (title == 'الالتزامات المشتركة') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SharedCommitmentsScreen()),
      );
      return;
    }

    if (title == 'إدارة الأشخاص' || title == 'إدارة الأشخاص والجهات') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PeopleManagementScreen()));
      return;
    }

    if (title == 'المشاريع' ||
        title == 'العقارات والمشاريع والأنشطة والمعدات' ||
        title == 'العقارات/الأنشطة التجارية/المعدات وأخرى') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProjectsActivitiesScreen()),
      );
      return;
    }

    return;
  }

  Widget _buildCategoryTile(
    String title,
    IconData icon,
    Color color,
    List<String> items,
    int categoryIndex,
  ) {
    final bool isPersonalCommitments = title == 'الالتزامات الشخصية';

    return AnimatedBuilder(
      animation: _categoryFlashAnimation,
      builder: (context, child) {
        final flash = _flashingCategoryIndex == categoryIndex
            ? _categoryFlashAnimation.value
            : 0.0;
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color.lerp(
              Colors.white,
              color.withValues(alpha: 0.18),
              flash,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12 + (flash * 0.25)),
                blurRadius: 16 + (flash * 10),
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: Color.lerp(color.withValues(alpha: 0.15), color, flash)!,
              width: 1.5 + (flash * 1.8),
            ),
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.2), width: 1),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F1F1C),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...items.map(
            (item) => Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.6)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: color.withOpacity(0.4), blurRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF46534F),
                        height: 1.4,
                      ),
                      textDirection: AppTr.uiDir,
                      maxLines: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isPersonalCommitments) ...[
            SizedBox(height: 6),
            _buildPersonalCommitmentCards(color),
          ],
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _openPriorityScreen(title),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.2), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: AppTr.uiDir,
                  children: [
                    Icon(Icons.arrow_forward, color: color, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'عرض المزيد',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalCommitmentCards(Color color) {
    return Row(
      textDirection: AppTr.uiDir,
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFBE7E4), Color(0xFFFDF4F2)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFFE88C83).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.south_east, color: Color(0xFFE88C83), size: 16),
                    Text(
                      'عليك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA82F26),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,000', Color(0xFFA82F26)),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFE9F4F1), Color(0xFFF3F9F7)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFF34A894).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: AppTr.uiDir,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.north_west, color: Color(0xFF34A894), size: 16),
                    Text(
                      'لك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E7161),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,500', Color(0xFF0E7161)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyAmount(String amount, Color amountColor) {
    return RichText(
      textDirection: AppTr.uiDir,
      text: TextSpan(
        children: [
          TextSpan(
            text: amount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
          WidgetSpan(child: SizedBox(width: 4)),
          TextSpan(
            text: AppTr.tr(AppSettings.currencySuffix),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: amountColor.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.page,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Row(
            children: [
              Expanded(
                child: _buildGlassNavItem(
                  index: 0,
                  label: 'الرئيسية',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                ),
              ),
              Expanded(
                child: _buildGlassNavItem(
                  index: 1,
                  label: 'التقارير/الأرشيف',
                  icon: Icons.analytics_outlined,
                  selectedIcon: Icons.analytics_rounded,
                ),
              ),
              Expanded(
                child: _buildGlassNavItem(
                  index: 2,
                  label: 'المستندات',
                  icon: Icons.folder_copy_outlined,
                  selectedIcon: Icons.folder_copy_rounded,
                ),
              ),
              Expanded(
                child: _buildGlassNavItem(
                  index: 3,
                  label: 'المزيد',
                  icon: Icons.more_horiz_rounded,
                  selectedIcon: Icons.more_horiz_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildGlassNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    final isSelected = _selectedIndex == index;
    // شريط تنقّل مسطّح: أيقونة ونص، والمحدَّد يتلوّن بلون التطبيق. كانت
    // كل أيقونة داخل مربّع متدرّج بحدود وظلّين، وهو شكل لا يتكرر في أي
    // مكان آخر من التطبيق.
    return _PressableScale(
      child: InkWell(
        onTap: () {
          if (_selectedIndex != index) {
            HapticFeedback.selectionClick();
          }
          setState(() => _selectedIndex = index);
        },
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 46,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.rIcon),
                ),
                child: Icon(
                  isSelected ? selectedIcon : icon,
                  size: 23,
                  color: isSelected ? AppTheme.accentDark : AppTheme.muted,
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 16,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected ? AppTheme.accentDark : AppTheme.muted,
                    ),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// رقم متابعة في مربع القسم: الكلمة في سطر، وتحتها الأيقونة والرقم بخط
/// كبير. النص يأتي «الكلمة: الرقم» فيُفصل عند آخر نقطتين.
class _HomeCategoryStat extends StatelessWidget {
  const _HomeCategoryStat({
    required this.label,
    required this.icon,
    required this.color,
    required this.large,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final at = label.lastIndexOf(':');
    final name = at > 0 ? label.substring(0, at).trim() : label;
    final value = at > 0 ? label.substring(at + 1).trim() : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // في المربع الكلمة على سطرين بدل أن تصغر جدًا؛ وفي المستطيل سطر.
          if (large)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                name,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            Text(
              name,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: large ? 20 : 18),
                const SizedBox(width: 5),
                Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: large ? 21 : 19,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// نمط الوحدة التي ينتمي إليها العنصر المثبَّت (اسم، أيقونة، لون) —
/// مصدر واحد تستخدمه شرائح التثبيت في الصفحة الرئيسية ونافذة الاختيار.
({String label, IconData icon, Color color}) _pinModuleStyle(String moduleId) {
  return switch (moduleId) {
    'personal' => (
      label: 'الالتزامات الشخصية',
      icon: Icons.person_outline_rounded,
      color: const Color(0xFF0A5A50),
    ),
    'shared' => (
      label: 'الالتزامات المشتركة',
      icon: Icons.groups_2_outlined,
      color: const Color(0xFF34A894),
    ),
    'people' => (
      label: 'الأفراد والجهات',
      icon: Icons.badge_outlined,
      color: const Color(0xFF0E7161),
    ),
    _ => (
      label: 'العقارات والأنشطة',
      icon: Icons.apartment_rounded,
      color: const Color(0xFFCE8422),
    ),
  };
}

/// مربع عنصر مثبَّت في الصفحة الرئيسية: أيقونة وحدته واسمه، وزر صغير
/// لإلغاء التثبيت في الزاوية.
class _HomePinnedTile extends StatelessWidget {
  const _HomePinnedTile({
    super.key,
    required this.shortcut,
    required this.onOpen,
    required this.onRemove,
  });

  final HomePinnedShortcut shortcut;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final moduleId = shortcut.moduleId.isEmpty
        ? shortcut.id.split(':').first
        : shortcut.moduleId;
    final style = _pinModuleStyle(moduleId);
    // مربع صغير ثابت الحجم، وزر الإلغاء داخل المربع في زاويته.
    return SizedBox(
      width: 62,
      height: 62,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4EAE8)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpen();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(style.icon, size: 18, color: style.color),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center, child: Text(
                          shortcut.title,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.title,
                            height: 1.1,
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 3,
                end: 3,
                child: Tooltip(
                  message: AppTr.tr('إلغاء التثبيت'),
                  child: InkWell(
                    onTap: onRemove,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F6F5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinItemsList extends StatefulWidget {
  const _PinItemsList({
    required this.moduleId,
    required this.items,
    required this.isPinned,
    required this.onToggle,
  });

  /// الوحدة: personal / shared / people / assets.
  final String moduleId;
  final List<HomePinnedShortcut> items;
  final bool Function(String id) isPinned;
  final Future<void> Function(HomePinnedShortcut item) onToggle;

  @override
  State<_PinItemsList> createState() => _PinItemsListState();
}

class _PinItemsListState extends State<_PinItemsList> {
  late final Set<String> _pinnedIds = widget.items
      .where((item) => widget.isPinned(item.id))
      .map((item) => item.id)
      .toSet();

  /// التبويب الفرعي المختار داخل الوحدة («الكل» = كل العناصر).
  String _group = 'الكل';

  /// تبويبات الوحدة كما في شاشتها، و«أخرى» لما لا يدخل في أي منها.
  List<String> get _groups {
    final defined = HomePinItemsService.groupsFor(widget.moduleId);
    final hasOther = widget.items.any(
      (item) => !defined.contains(item.group),
    );
    return ['الكل', ...defined, if (hasOther) 'أخرى'];
  }

  int _countOf(String group) {
    if (group == 'الكل') return widget.items.length;
    final defined = HomePinItemsService.groupsFor(widget.moduleId);
    if (group == 'أخرى') {
      return widget.items.where((item) => !defined.contains(item.group)).length;
    }
    return widget.items.where((item) => item.group == group).length;
  }

  List<HomePinnedShortcut> get _visible {
    if (_group == 'الكل') return widget.items;
    final defined = HomePinItemsService.groupsFor(widget.moduleId);
    if (_group == 'أخرى') {
      return widget.items
          .where((item) => !defined.contains(item.group))
          .toList(growable: false);
    }
    return widget.items
        .where((item) => item.group == _group)
        .toList(growable: false);
  }

  /// شريط تبويبات الوحدة (مالية، مستند… / مشاركات مشتركة، الرحلة / السفر…).
  Widget _groupTabs(Color color) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final group = _groups[index];
          final selected = group == _group;
          return Material(
            color: selected ? color.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('pin-group-${widget.moduleId}-$group'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _group = group),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? color.withValues(alpha: 0.45)
                        : const Color(0xFFE4EAE8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: selected ? color : const Color(0xFF5C6B68),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_countOf(group)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: selected ? color : const Color(0xFF8C9A97),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _groupPinCard(Color color) {
    final item = HomePinnedShortcut(
      id: '${widget.moduleId}:group:$_group',
      title: _group,
      moduleId: widget.moduleId,
      subtitle: 'فئة كاملة',
      group: _group,
    );
    final pinned = _pinnedIds.contains(item.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: pinned ? color.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('pin-whole-group-${widget.moduleId}-$_group'),
          onTap: () => _toggle(item),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pinned
                    ? color.withValues(alpha: 0.45)
                    : const Color(0xFFE4EAE8),
                width: pinned ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_special_outlined, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${AppTr.tr('تثبيت الفئة كاملة')}: ${AppTr.tr(_group)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2C3B38),
                    ),
                  ),
                ),
                Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: pinned ? color : const Color(0xFF8C9A97),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(HomePinnedShortcut item) async {
    setState(() {
      if (!_pinnedIds.add(item.id)) _pinnedIds.remove(item.id);
    });
    await widget.onToggle(item);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(AppTheme.sXxl),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rCard),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_add_outlined,
                size: 34,
                color: Color(0xFF8C9A97),
              ),
              SizedBox(height: 10),
              Text(
                'لا توجد عناصر محفوظة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2C3B38),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'أضف عنصرًا داخل هذه الوحدة ليظهر هنا',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF76837F)),
              ),
            ],
          ),
        ),
      );
    }
    final style = _pinModuleStyle(widget.moduleId);
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2C3B38),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${visible.length} عناصر',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: style.color,
                  ),
                ),
              ),
            ],
          ),
        ),
        _groupTabs(style.color),
        const SizedBox(height: 8),
        // تثبيت الفئة كاملة (الرحلة / السفر، العقارات...) لا عنصر واحد.
        if (_group != 'الكل' && _group != 'أخرى') _groupPinCard(style.color),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 30, 16, 0),
            child: Text(
              'لا توجد عناصر في «$_group»',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF76837F)),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = visible[index];
              final pinned = _pinnedIds.contains(item.id);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: pinned
                      ? style.color.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: pinned
                        ? style.color.withValues(alpha: 0.42)
                        : const Color(0xFFE4EAE8),
                    width: pinned ? 1.4 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A022E2A),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _toggle(item),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: style.color.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              style.icon,
                              color: style.color,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F1F1C),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle.isEmpty
                                      ? style.label
                                      : item.subtitle,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF76837F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: pinned ? 'إلغاء التثبيت' : 'تثبيت',
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: pinned
                                    ? style.color
                                    : const Color(0xFFF2F6F5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                key: ValueKey('pin-item-${item.id}'),
                                onPressed: () => _toggle(item),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  pinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  color: pinned
                                      ? Colors.white
                                      : const Color(0xFF5C6B68),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PinPickerLoading extends StatelessWidget {
  const _PinPickerLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        SizedBox(height: 14),
        Text(
          'جارٍ تجهيز العناصر المحفوظة...',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5C6B68),
          ),
        ),
      ],
    );
  }
}

/// أيقونة المجلد ذات النجمة داخل البطاقة المميّزة — مركّبة من طبقتين
/// لتعطي إحساس العمق بدل أيقونة مسطّحة.
class _SummaryFolderStarIcon extends StatelessWidget {
  const _SummaryFolderStarIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 30,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.32),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 36,
              height: 25,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.9),
                    AppTheme.accentSoft.withValues(alpha: 0.9),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.star_rounded,
                  size: 17,
                  color: AppTheme.gold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.child});

  final Widget child;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// فلتر التقارير والأرشيف: أقسام فلتر الصفحة الرئيسية نفسها وفلتر كل قسم
/// كما في شاشته، مقصورًا على ما يطبّقه التقرير فعلًا، والتاريخ ظاهر دائمًا.
AppFilterModuleConfig _reportModuleConfigFor(String module) {
  final base = switch (module) {
    'الالتزامات الشخصية' => personalFilterModuleConfig(),
    'الالتزامات المشتركة' => sharedFilterModuleConfig(),
    'الأفراد والجهات' => peopleFilterModuleConfig(),
    'العقارات' ||
    'الأنشطة التجارية' ||
    'المركبات ووسائل النقل' => assetsFilterModuleConfig(module),
    _ => null,
  };
  if (base == null) {
    // «الكل»: الفترة والحالة والمبلغ على كل الأقسام.
    return AppFilterModuleConfig(
      sectionsFor: (_) => const [
        AppFilterSection.period,
        AppFilterSection.statusSelect,
        AppFilterSection.amountSelect,
      ],
      selectStatuses: const [
        'الأحدث أولاً',
        'نشط',
        'قريبة الاستحقاق',
        'مستحقة',
        'متأخرة',
        'مكتملة',
      ],
    );
  }
  List<AppFilterSection> sectionsFor(String main) {
    final shown = base
        .sectionsFor(main)
        .where(kReportFilterSections.contains)
        .toList();
    if (!shown.contains(AppFilterSection.period) &&
        !shown.contains(AppFilterSection.date)) {
      final after = shown.lastIndexWhere(
        (section) =>
            section == AppFilterSection.mainCategory ||
            section == AppFilterSection.subCategory,
      );
      shown.insert(after + 1, AppFilterSection.period);
    }
    return shown;
  }

  return AppFilterModuleConfig(
    sectionsFor: sectionsFor,
    mainCategories: base.mainCategories,
    subCategoriesFor: base.subCategoriesFor,
    fixedMainCategory: base.fixedMainCategory,
    statuses: base.statuses,
    selectStatuses: base.selectStatuses,
    selectStatusesFor: base.selectStatusesFor,
    currencies: base.currencies,
    amountShortcuts: base.amountShortcuts,
    amountShortcutsFor: base.amountShortcutsFor,
    personCategories: base.personCategories,
    documentStates: base.documentStates,
    delegatesLabel: base.delegatesLabel,
    placeLabel: base.placeLabel,
    placeHint: base.placeHint,
  );
}

class _ReportsArchiveHubPage extends StatefulWidget {
  const _ReportsArchiveHubPage();

  @override
  State<_ReportsArchiveHubPage> createState() => _ReportsArchiveHubPageState();
}

class _ReportsArchiveHubPageState extends State<_ReportsArchiveHubPage> {
  static const _storageKey = 'reports_archive_records_v1';
  static const _accent = Color(0xFF0A5A50);

  /// السجلات الحقيقية التي تُبنى منها التقارير والأرشيف والملخصات.
  List<SummaryItem> _items = const [];
  bool _loadingItems = true;

  /// البحث أعلى صفحة التقارير (في التقارير المنشأة).
  final TextEditingController _reportsSearch = TextEditingController();

  /// فلتر قائمتَي «التقارير المنجزة» و«ملفات الأرشيف»: الأحدث أولاً، آخر
  /// أسبوع، آخر شهر، مخصص (من/إلى).
  static const _listFilters = ['الأحدث أولاً', 'آخر أسبوع', 'آخر شهر', 'مخصص'];
  String _reportsListFilter = 'الأحدث أولاً';
  DateTimeRange? _reportsRange;
  String _archiveListFilter = 'الأحدث أولاً';
  DateTimeRange? _archiveRange;
  List<_GeneratedReport> _recentReports = [];
  List<_GeneratedReport> _archivedReports = [];

  /// ما أُرشف فعلًا داخل الأقسام (التزامات، أفراد، عقارات) — يُجمع هنا
  /// ليُبحث فيه ويُستخرج ويُلغى أرشفته من مكان واحد.
  List<ArchivedRecord> _archivedRecords = const [];
  String _archivedSource = 'الكل';
  final TextEditingController _archivedSearch = TextEditingController();
  bool _loadingArchived = true;





  @override
  void initState() {
    super.initState();
    _restore();
    _loadItems();
    _loadArchivedRecords();
  }

  /// تحميل المؤرشفات من كل الأقسام.
  Future<void> _loadArchivedRecords() async {
    if (mounted) setState(() => _loadingArchived = true);
    final rows = await ArchiveCenter.loadAll();
    if (!mounted) return;
    setState(() {
      _archivedRecords = rows;
      _loadingArchived = false;
    });
  }

  /// المؤرشفات بعد تطبيق تبويب القسم ونص البحث.
  List<ArchivedRecord> get _visibleArchivedRecords {
    final query = _archivedSearch.text.trim();
    return _archivedRecords.where((row) {
      final sourceOk =
          _archivedSource == 'الكل' || row.source == _archivedSource;
      final queryOk =
          query.isEmpty ||
          row.title.contains(query) ||
          row.subtitle.contains(query);
      return sourceOk && queryOk;
    }).toList(growable: false);
  }

  /// ملف PDF بالمؤرشفات المعروضة الآن (القسم المختار + البحث).
  void _exportArchivedRecords() {
    final rows = _visibleArchivedRecords;
    if (_loadingArchived) {
      _toast('جارٍ تحميل البيانات...');
      return;
    }
    if (rows.isEmpty) {
      _toast('لا توجد عناصر مؤرشفة للتصدير');
      return;
    }
    final now = DateTime.now();
    final query = _archivedSearch.text.trim();
    final stamp = now.millisecondsSinceEpoch.toString();
    final document = ReportDocument(
      title: _archivedSource == 'الكل'
          ? 'سجل المؤرشفات'
          : 'سجل المؤرشفات — $_archivedSource',
      archive: true,
      reference: 'AR-${stamp.substring(stamp.length - 6)}',
      createdAt: now,
      createdBy: AppSettings.instance.name,
      criteria: [
        ('القسم', _archivedSource),
        if (query.isNotEmpty) ('كلمة البحث', query),
      ],
      items: [
        for (final row in rows)
          SummaryItem(
            scope: row.source,
            section: row.source,
            type: row.source,
            title: row.title,
            subtitle: row.subtitle,
            status: 'مؤرشف',
          ),
      ],
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(document: document),
      ),
    );
  }

  /// رقاقة قسم مع عدد مؤرشفاته.
  Widget _archiveSourcePill(String source, int count) {
    final selected = _archivedSource == source;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: InkWell(
        onTap: () => setState(() => _archivedSource = source),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: Border.all(
              color: selected ? _accent : AppTheme.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // القسم يضم المركبات ووسائل النقل أيضًا.
                source == ArchiveCenter.assetsSource
                    ? 'العقارات والأنشطة والمركبات ووسائل النقل'
                    : source,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.title,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppTheme.field,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : AppTheme.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unarchiveRecord(ArchivedRecord row) async {
    final ok = await confirmAction(
      context,
      title: 'إلغاء الأرشفة',
      message: 'سيعود «${row.title}» إلى ${row.source}. هل تريد المتابعة؟',
      confirmLabel: 'إلغاء الأرشفة',
    );
    if (!ok) return;
    final done = await row.unarchive();
    if (!mounted) return;
    if (!done) {
      _toast('تعذّر إلغاء الأرشفة');
      return;
    }
    _toast('أُلغيت أرشفة «${row.title}»');
    await _loadArchivedRecords();
  }

  /// حذف عنصر مؤرشف إلى سلة المهملات (وحدات العقارات).
  Future<void> _trashArchivedRecord(ArchivedRecord row) async {
    final move = row.moveToTrash;
    if (move == null) return;
    final ok = await confirmAction(
      context,
      title: 'حذف',
      message: 'سيُنقل «${row.title}» إلى سلة المهملات، ومنها يمكن استعادته '
          'أو حذفه نهائيًا. هل تريد المتابعة؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok) return;
    final done = await move();
    if (!mounted) return;
    if (!done) {
      _toast('تعذّر الحذف');
      return;
    }
    _toast('نُقل «${row.title}» إلى سلة المهملات');
    await _loadArchivedRecords();
  }

  /// بطاقة عنصر مؤرشف: أيقونة القسم، العنوان، القسم وتفاصيله، و«استعادة».
  Widget _archivedRecordCard(ArchivedRecord row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: const Color(0xFFE6EEEC)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF022E2A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: row.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rIcon),
            ),
            child: Icon(row.icon, size: 21, color: row.color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: row.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        row.source,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: row.color,
                        ),
                      ),
                    ),
                    if (row.subtitle.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          row.subtitle,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (row.moveToTrash != null)
            IconButton(
              tooltip: AppTr.tr('حذف'),
              onPressed: () => _trashArchivedRecord(row),
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.danger,
              ),
            ),
          TextButton.icon(
            onPressed: () => _unarchiveRecord(row),
            icon: const Icon(Icons.unarchive_outlined, size: 17),
            label: const Text(
              'استعادة',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              backgroundColor: AppTheme.brandSoft,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reportsSearch.dispose();
    _archivedSearch.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final items = await HomeSummaryService().loadItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadingItems = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingItems = false);
    }
  }

  /// عناصر تقرير/أرشيف بعينه = ما يطابق اختياره المحفوظ.
  List<SummaryItem> _reportItems(_GeneratedReport report) {
    final filter = report.filter;
    if (filter != null) return applyReportFilter(_items, filter);
    final selection = report.selection;
    if (selection == null) return const [];
    return _items.where(selection.matches).toList(growable: false);
  }


  // ===== الحفظ والاسترجاع =====
  // كانت التقارير تُخزَّن في قائمتين داخل الذاكرة فقط، فتضيع بالكامل بمجرد
  // إغلاق الصفحة. الآن تُحفظ محليًا وتُسترجع عند كل فتح.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final recent = (decoded['recent'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _GeneratedReport.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      final archived = (decoded['archived'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _GeneratedReport.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _recentReports = recent;
        _archivedReports = archived;
      });
    } catch (_) {
      // مخزون تالف: تُترك القوائم فارغة بدل إسقاط الشاشة.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'recent': _recentReports.map((r) => r.toMap()).toList(),
        'archived': _archivedReports.map((r) => r.toMap()).toList(),
      }),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }


  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ===== محتوى التقرير الحقيقي =====

  /// نص التقرير الكامل — يُستخدم للمشاركة والتصدير، وهو نفس ما يُعرض في
  /// المعاينة حتى لا يختلف المُصدَّر عمّا رآه المستخدم.
  String _reportAsText(_GeneratedReport report) {
    final buffer = StringBuffer()
      ..writeln(report.title)
      ..writeln('النوع: ${report.type}')
      ..writeln('النمط: تقرير ${report.mode}');
    if (report.subject.isNotEmpty) buffer.writeln('الموضوع: ${report.subject}');
    buffer.writeln('أنشئ بواسطة: ${report.createdBy}');
    buffer.writeln('تاريخ الإنشاء: ${_formatDate(report.createdAt)}');
    if (report.fromDate != null || report.toDate != null) {
      buffer.writeln(
        'الفترة: ${report.fromDate == null ? '—' : _formatDate(report.fromDate!)}'
        ' إلى ${report.toDate == null ? '—' : _formatDate(report.toDate!)}',
      );
    }
    final selection = report.selection;
    if (selection != null) {
      buffer.writeln('');
      for (final line in scopeResultLines(selection, _reportItems(report))) {
        buffer.writeln(line);
      }
    }
    final filter = report.filter;
    if (filter != null) {
      for (final (label, value) in filter.describe()) {
        buffer.writeln('$label: $value');
      }
      final items = _reportItems(report);
      buffer
        ..writeln('')
        ..writeln('عدد العناصر: ${items.length}');
      for (final item in items) {
        final amount = item.amount == 0
            ? ''
            : ' — ${reportAmount(item.amount)} ${AppSettings.currencySuffix}';
        final date = item.date == null ? '' : ' — ${_formatDate(item.date!)}';
        buffer.writeln('• ${item.title}$amount$date');
      }
    }
    return buffer.toString();
  }

  // ===== إجراءات التقارير =====

  /// فلتر الصفحة الرئيسية نفسه (الأقسام ← فلتر القسم)، وفي آخره عنوان
  /// التقرير وكلمة البحث (وسبب الأرشفة)، ثم زر «إنشاء تقرير» / «إنشاء
  /// أرشيف». بعد الإنشاء تُفتح معاينة الملف مباشرة.
  Future<void> _openReportFilter({required bool archive}) async {
    if (!await FundlyAuth.requireLogin(context)) return;
    if (_loadingItems) {
      _toast('جارٍ تحميل البيانات...');
      return;
    }
    final titleCtrl = TextEditingController();
    final queryCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? pickedModule;
    AppFilterValues? pickedValues;
    await showAppFilterSheet(
      context: context,
      title: archive ? 'البحث في الأرشيف' : 'إنشاء تقرير',
      icon: archive ? Icons.manage_search_rounded : Icons.description_outlined,
      accent: _accent,
      values: AppFilterValues(),
      sections: const [],
      onApply: (_) {},
      modules: kReportModules,
      initialModule: 'الكل',
      moduleConfigFor: _reportModuleConfigFor,
      // في الأرشيف الزر «ابحث»: النتيجة تُحفظ في ملفات الأرشيف وتُفتح.
      applyLabel: archive ? 'ابحث' : 'إنشاء تقرير',
      applyIcon: archive ? Icons.search_rounded : Icons.picture_as_pdf_rounded,
      extraFieldsLabel: archive ? 'بيانات الأرشيف' : 'بيانات التقرير',
      extraFields: [
        _sheetField(
          titleCtrl,
          archive ? 'عنوان الأرشيف (اختياري)' : 'عنوان التقرير (اختياري)',
          Icons.title_rounded,
        ),
        _sheetField(
          queryCtrl,
          'كلمة بحث داخل البيانات (اختياري)',
          Icons.search_rounded,
        ),
        if (archive)
          _sheetField(
            reasonCtrl,
            'سبب الأرشفة (اختياري)',
            Icons.notes_rounded,
          ),
      ],
      onApplyModule: (chosenModule, chosenValues) {
        pickedModule = chosenModule;
        pickedValues = chosenValues;
      },
    );
    final typedTitle = titleCtrl.text.trim();
    final query = queryCtrl.text.trim();
    final reason = reasonCtrl.text.trim();
    // التخلّص بعد انتهاء حركة الإغلاق، وإلا استُعملت المتحكّمات بعد تحريرها.
    Future.delayed(const Duration(milliseconds: 600), () {
      titleCtrl.dispose();
      queryCtrl.dispose();
      reasonCtrl.dispose();
    });
    final module = pickedModule;
    final values = pickedValues;
    if (module == null || values == null || !mounted) return;

    final filter = ReportFilter(module: module, values: values, query: query);
    final kind = archive ? 'أرشيف' : 'تقرير';
    final now = DateTime.now();
    final category =
        values.mainCategory != 'الكل' && values.mainCategory != module
        ? ' · ${values.mainCategory}'
        : '';
    final report = _GeneratedReport(
      id: now.microsecondsSinceEpoch.toString(),
      title: typedTitle.isEmpty
          ? '$kind ${module == 'الكل' ? 'شامل' : module}$category'
          : typedTitle,
      type: module,
      subject: filter
          .describe()
          .skip(1)
          .map((entry) => '${entry.$1}: ${entry.$2}')
          .join('، '),
      mode: kind,
      fromDate: values.dateFrom,
      toDate: values.dateTo,
      dataFields: const [],
      createdBy: AppSettings.instance.name,
      createdAt: now,
      filter: filter,
      archivedAt: archive ? now : null,
      archiveReason: archive ? reason : '',
    );
    setState(() {
      if (archive) {
        _archivedReports.insert(0, report);
      } else {
        _recentReports.insert(0, report);
      }
    });
    await _persist();
    if (!mounted) return;
    _toast(
      archive ? 'حُفظت نتيجة البحث في ملفات الأرشيف' : 'تم إنشاء التقرير',
    );
    _showReportPreview(report);
  }

  /// حقل كتابة داخل ورقة الفلتر (العنوان، كلمة البحث، سبب الأرشفة).
  Widget _sheetField(
    TextEditingController controller,
    String hint,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      textDirection: AppTr.uiDir,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.title,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: AppTr.tr(hint),
        hintStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.muted,
        ),
        prefixIcon: Icon(icon, size: 19, color: AppTheme.muted),
        filled: true,
        fillColor: AppTheme.field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// مستند التقرير/الأرشيف كما يُعرض ويُطبع ويُشارك.
  ReportDocument _documentFor(_GeneratedReport report) {
    final archived = report.archivedAt != null || report.mode == 'أرشيف';
    final criteria =
        report.filter?.describe() ??
        <(String, String)>[
          ('القسم', report.selection?.scope ?? report.type),
          if (report.subject.isNotEmpty) ('الأقسام', report.subject),
          if (report.fromDate != null || report.toDate != null)
            (
              'الفترة',
              '${report.fromDate == null ? '—' : _formatDate(report.fromDate!)}'
                  ' ← '
                  '${report.toDate == null ? '—' : _formatDate(report.toDate!)}',
            ),
        ];
    final digits = report.id.length > 6
        ? report.id.substring(report.id.length - 6)
        : report.id;
    return ReportDocument(
      title: report.title,
      archive: archived,
      reference: '${archived ? 'AR' : 'RP'}-$digits',
      createdAt: report.createdAt,
      createdBy: report.createdBy.trim().isEmpty
          ? AppSettings.instance.name
          : report.createdBy,
      criteria: criteria,
      items: _reportItems(report),
      archivedAt: report.archivedAt,
      archiveReason: report.archiveReason,
    );
  }

  /// هل يمكن بناء محتوى هذا التقرير الآن؟ (البيانات محمّلة ومعاييره محفوظة)
  bool _canBuild(_GeneratedReport report) {
    if (_loadingItems) {
      _toast('جارٍ تحميل البيانات...');
      return false;
    }
    if (report.filter == null && report.selection == null) {
      _toast(
        'هذا التقرير أُنشئ بنسخة سابقة بلا معايير محفوظة — أنشئ تقريرًا جديدًا.',
      );
      return false;
    }
    return true;
  }

  Future<void> _printReport(_GeneratedReport report) async {
    if (!_canBuild(report)) return;
    if (!PlanGate.hasFeature(context, PlanFeatures.pdf)) return;
    try {
      await printReportDocument(_documentFor(report));
    } catch (_) {
      if (!mounted) return;
      _toast('تعذّر فتح الطباعة');
    }
  }

  /// سبب الأرشفة — يظهر لاحقًا في بطاقة العنصر المؤرشف.
  Future<String?> _askArchiveReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('سبب الأرشفة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: AppTr.tr('مثال: انتهت الفترة / للحفظ المرجعي'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('تخطٍّ'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    // التخلّص بعد انتهاء حركة الإغلاق، وإلا استُعمل المتحكّم بعد تحريره.
    Future.delayed(const Duration(milliseconds: 600), controller.dispose);
    return reason;
  }

  Future<void> _archiveReport(_GeneratedReport report) async {
    final reason = await _askArchiveReason();
    if (!mounted) return;
    final archived = report.copyWith(
      archivedAt: DateTime.now(),
      archiveReason: reason ?? '',
    );
    setState(() {
      _recentReports.removeWhere((item) => item.id == report.id);
      _archivedReports.insert(0, archived);
    });
    await _persist();
    if (!mounted) return;
    _toast('تم نقل التقرير إلى الأرشيف');
  }

  Future<void> _restoreReport(_GeneratedReport report) async {
    setState(() {
      _archivedReports.removeWhere((item) => item.id == report.id);
      _recentReports.insert(0, report);
    });
    await _persist();
    if (!mounted) return;
    _toast('تمت استعادة التقرير من الأرشيف');
  }

  Future<void> _deleteReport(_GeneratedReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('حذف التقرير'),
          content: Text('سيُحذف "${report.title}" نهائيًا. هل تريد المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'حذف',
                style: TextStyle(color: Color(0xFFD95A4E)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _recentReports.removeWhere((item) => item.id == report.id);
      _archivedReports.removeWhere((item) => item.id == report.id);
    });
    await _persist();
    if (!mounted) return;
    _toast('تم حذف التقرير');
  }

  /// مشاركة/تصدير حقيقية عبر قائمة المشاركة في النظام (تتيح الحفظ أو
  /// الإرسال أو الطباعة من التطبيق الذي يختاره المستخدم). كانت أزرار
  /// "طباعة" و"تصدير PDF" سابقًا تعرض رسالة نجاح دون تنفيذ أي شيء.
  Future<void> _shareReport(_GeneratedReport report) async {
    if (!_canBuild(report)) return;
    if (!PlanGate.hasFeature(context, PlanFeatures.pdf)) return;
    // على الأجهزة اللوحية تحتاج قائمة المشاركة موضع انطلاق وإلا فشل النداء،
    // بنفس ما تفعله بقية مواضع المشاركة في هذا الملف.
    final box = context.findRenderObject() as RenderBox?;
    try {
      // ملف PDF بتصميم التقرير — يُرسل عبر واتساب أو البريد أو يُحفظ.
      await shareReportDocument(_documentFor(report));
      return;
    } catch (_) {
      // احتياط: إن تعذّر بناء الملف على هذا الجهاز تُشارك نسخة نصية.
    }
    if (!mounted) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _reportAsText(report),
          subject: report.title,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('تعذر فتح قائمة المشاركة');
    }
  }

  void _handleReportAction(_GeneratedReport report, String action) {
    switch (action) {
      case 'open':
        _showReportPreview(report);
      case 'share':
        _shareReport(report);
      case 'print':
        _printReport(report);
      case 'archive':
        _archiveReport(report);
      case 'restore':
        _restoreReport(report);
      case 'delete':
        _deleteReport(report);
    }
  }

  void _showReportPreview(_GeneratedReport report) {
    if (!_canBuild(report)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(document: _documentFor(report)),
      ),
    );
  }

  // ===== عناصر الواجهة =====

  Widget _sectionTitle(String text, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 17,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
          ),
          if (trailing != null)
            Flexible(
              child: Text(
                trailing,
                textAlign: AppTr.alignEnd,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8C9A97),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: const Color(0xFFD5DEDB)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8C9A97),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(_GeneratedReport report, {required bool archived}) {
    final itemsCount = _reportItems(report).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showReportPreview(report),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        archived
                            ? Icons.inventory_2_outlined
                            : Icons.description_outlined,
                        color: _accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report.title,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF022E2A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${report.type}  •  ${_formatDate(report.createdAt)}',
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5C6B68),
                            ),
                          ),
                          if (report.subject.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              report.filter != null
                                  ? report.subject
                                  : 'الأقسام: ${report.subject}',
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8C9A97),
                              ),
                            ),
                          ],
                          // العنصر المؤرشف يعرض تاريخ الأرشفة وسببها كما
                          // في المتطلبات، لا تاريخ الإنشاء وحده.
                          if (archived) ...[
                            const SizedBox(height: 2),
                            Text(
                              'تاريخ الأرشفة: ${report.archivedAt == null ? '—' : _formatDate(report.archivedAt!)}',
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8C9A97),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'سبب الأرشفة: ${report.archiveReason.isEmpty ? 'غير محدد' : report.archiveReason}',
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8C9A97),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (archived
                                ? const Color(0xFF5C6B68)
                                : const Color(0xFF34A894))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        archived ? 'مؤرشف' : 'نشط',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: archived
                              ? const Color(0xFF5C6B68)
                              : const Color(0xFF178F7B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF2F6F5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.list_alt_rounded,
                      size: 14,
                      color: Color(0xFF8C9A97),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$itemsCount عنصرًا',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8C9A97),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _handleReportAction(report, 'open'),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('فتح'),
                      style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('مشاركة / تصدير'),
                      onPressed: () => _handleReportAction(report, 'share'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        size: 18,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: AppTr.tr('خيارات'),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        size: 20,
                        color: Color(0xFF5C6B68),
                      ),
                      onSelected: (value) =>
                          _handleReportAction(report, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'print',
                          child: Text('طباعة'),
                        ),
                        if (archived)
                          const PopupMenuItem(
                            value: 'restore',
                            child: Text('استعادة'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'archive',
                            child: Text('أرشفة التقرير'),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            archived ? 'حذف نهائي' : 'حذف',
                            style: const TextStyle(color: Color(0xFFD95A4E)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _reportMatchesSearch(_GeneratedReport report, String query) =>
      query.isEmpty ||
      matchesSearchQuery(
        query: query,
        fields: [
          report.title,
          report.type,
          report.subject,
          report.archiveReason,
          _formatDate(report.createdAt),
        ],
      );

  /// فلتر القائمة: الأحدث أولًا دائمًا، مقصورًا على الفترة المختارة.
  List<_GeneratedReport> _applyListFilter(
    Iterable<_GeneratedReport> reports,
    String filter,
    DateTimeRange? range,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final from = switch (filter) {
      'آخر أسبوع' => today.subtract(const Duration(days: 7)),
      'آخر شهر' => DateTime(today.year, today.month - 1, today.day),
      'مخصص' => range?.start,
      _ => null,
    };
    final to = filter == 'مخصص' ? range?.end : null;
    return _newestFirst(
      reports.where((report) {
        final day = DateUtils.dateOnly(report.archivedAt ?? report.createdAt);
        if (from != null && day.isBefore(DateUtils.dateOnly(from))) {
          return false;
        }
        if (to != null && day.isAfter(DateUtils.dateOnly(to))) return false;
        return true;
      }),
    );
  }

  /// «ابحث أعلاه…» — سطر واحد صغير رمادي.
  Widget _searchHintLine() => const Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(
      'ابحث أعلاه للوصول إلى ما تحتاجه',
      maxLines: 3,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.muted,
      ),
    ),
  );

  /// عنوان قائمة بخط عمودي ملوّن وعددها — بلا فلتر.
  Widget _plainListTitle(String title, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 17,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${AppTr.tr(title)} ($count)',
            maxLines: 3,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF022E2A),
            ),
          ),
        ),
      ],
    ),
  );

  /// زر فلتر الفترة: الأحدث أولاً، آخر أسبوع، آخر شهر، مخصص.
  Widget _periodFilterButton({
    required String value,
    required DateTimeRange? range,
    required void Function(String value, DateTimeRange? range) onChanged,
    bool tall = false,
  }) {
    final label = value == 'مخصص' && range != null
        ? '${_formatDate(range.start)} - ${_formatDate(range.end)}'
        : value;
    return PopupMenuButton<String>(
      tooltip: AppTr.tr('الفترة'),
      onSelected: (selected) async {
        if (selected != 'مخصص') {
          onChanged(selected, null);
          return;
        }
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(now.year + 1),
          initialDateRange:
              range ??
              DateTimeRange(
                start: now.subtract(const Duration(days: 30)),
                end: now,
              ),
        );
        if (picked == null || !mounted) return;
        onChanged('مخصص', picked);
      },
      itemBuilder: (context) => [
        for (final option in _listFilters)
          PopupMenuItem(
            value: option,
            child: Text(
              option,
              style: TextStyle(
                fontWeight: option == value ? FontWeight.w900 : FontWeight.w600,
                color: option == value ? _accent : AppTheme.title,
              ),
            ),
          ),
      ],
      child: Container(
        height: tall ? 46 : null,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: tall ? 0 : 6),
        decoration: BoxDecoration(
          color: AppTheme.field,
          borderRadius: BorderRadius.circular(
            tall ? AppTheme.rField : AppTheme.rPill,
          ),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list_rounded, size: 16, color: _accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _accent,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: _accent,
            ),
          ],
        ),
      ),
    );
  }

  /// قسم ملف الأرشيف (لرقائق الأقسام): من القسم الذي اختير في فلتره.
  String? _archiveSourceOf(_GeneratedReport report) {
    final module = report.filter?.module ?? report.type;
    return switch (module) {
      'الالتزامات الشخصية' => ArchiveCenter.personalSource,
      'الالتزامات المشتركة' => ArchiveCenter.sharedSource,
      'الأفراد والجهات' => ArchiveCenter.peopleSource,
      'العقارات' ||
      'الأنشطة التجارية' ||
      'المركبات ووسائل النقل' ||
      'آليات ومعدات' => ArchiveCenter.assetsSource,
      _ => null,
    };
  }

  /// عنوان القائمة يمينًا، وفلتر الفترة يسارًا في السطر نفسه.
  Widget _listHeader({
    required String title,
    required int count,
    required String value,
    required DateTimeRange? range,
    required void Function(String value, DateTimeRange? range) onChanged,
  }) {
    final label = value == 'مخصص' && range != null
        ? '${_formatDate(range.start)} - ${_formatDate(range.end)}'
        : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 17,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title ($count)',
              maxLines: 3,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF022E2A),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: AppTr.tr('الفترة'),
            onSelected: (selected) async {
              if (selected != 'مخصص') {
                onChanged(selected, null);
                return;
              }
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 1),
                initialDateRange:
                    range ??
                    DateTimeRange(
                      start: now.subtract(const Duration(days: 30)),
                      end: now,
                    ),
              );
              if (picked == null || !mounted) return;
              onChanged('مخصص', picked);
            },
            itemBuilder: (context) => [
              for (final option in _listFilters)
                PopupMenuItem(
                  value: option,
                  child: Text(
                    option,
                    style: TextStyle(
                      fontWeight: option == value
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: option == value ? _accent : AppTheme.title,
                    ),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.field,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    size: 16,
                    color: _accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: _accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الأحدث أولًا (تاريخ الأرشفة للمؤرشف، وإلا تاريخ الإنشاء).
  List<_GeneratedReport> _newestFirst(Iterable<_GeneratedReport> reports) =>
      reports.toList()..sort(
        (a, b) => (b.archivedAt ?? b.createdAt).compareTo(
          a.archivedAt ?? a.createdAt,
        ),
      );

  /// المستطيل الموحّد أعلى التبويب: العنوان والشرح، وزر الفلتر في زاويته،
  /// وحقل البحث، وزر التنفيذ — البحث والفلتر والإنشاء من مكان واحد.
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required String buttonLabel,
    required IconData buttonIcon,
    required VoidCallback? onPressed,
    List<Widget> footer = const [],
    Widget? searchTrailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: const Color(0xFFE6EEEC)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF022E2A).withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: _accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF022E2A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C6B68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(child: TextField(
            controller: controller,
            textDirection: AppTr.uiDir,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.title,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: AppTr.tr(hint),
              hintStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppTheme.muted,
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.muted,
                      ),
                      onPressed: () {
                        controller.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: AppTheme.field,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
                borderSide: BorderSide.none,
              ),
            ),
          )),
              if (searchTrailing != null) ...[
                const SizedBox(width: 8),
                searchTrailing,
              ],
            ],
          ),
          const SizedBox(height: 12),
          // الزر وحده يفتح الفلتر — حُذفت علامة الفلتر المكررة بجانبه.
          Row(
            textDirection: AppTr.uiDir,
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(buttonIcon, size: 19),
                  label: Text(
                    onPressed == null ? 'جارٍ تحميل البيانات...' : buttonLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ...footer,
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    final query = _reportsSearch.text.trim();
    final reports = _applyListFilter(
      _recentReports.where((report) => _reportMatchesSearch(report, query)),
      _reportsListFilter,
      _reportsRange,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildActionCard(
          icon: Icons.description_outlined,
          title: 'التقارير',
          subtitle:
              'اختر القسم وفلتره كما في الصفحة الرئيسية، ثم «إنشاء تقرير» '
              'لتحصل على ملف PDF جاهز للمشاركة والطباعة.',
          controller: _reportsSearch,
          hint: 'ابحث في التقارير',
          buttonLabel: 'إنشاء تقرير',
          buttonIcon: Icons.add_rounded,
          onPressed: _loadingItems
              ? null
              : () => _openReportFilter(archive: false),
        ),
        const SizedBox(height: 20),
        _searchHintLine(),
        _listHeader(
          title: 'التقارير المنجزة',
          count: reports.length,
          value: _reportsListFilter,
          range: _reportsRange,
          onChanged: (value, range) => setState(() {
            _reportsListFilter = value;
            _reportsRange = range;
          }),
        ),
        if (_recentReports.isEmpty)
          _emptyCard(
            Icons.description_outlined,
            'لا توجد تقارير منشأة بعد.\nابدأ من زر "إنشاء تقرير" في الأعلى.',
          )
        else if (reports.isEmpty)
          _emptyCard(
            Icons.search_off_rounded,
            'لا توجد تقارير تطابق البحث أو الفترة.',
          )
        else
          ...reports.map(
            (report) => _buildReportRow(report, archived: false),
          ),
      ],
    );
  }

  Widget _buildArchiveTab() {
    final query = _archivedSearch.text.trim();
    final files = _applyListFilter(
      _archivedReports.where((report) => _reportMatchesSearch(report, query)),
      _archiveListFilter,
      _archiveRange,
    );
    bool inSource(_GeneratedReport report, String source) =>
        source == 'الكل' || _archiveSourceOf(report) == source;
    final shownFiles = files
        .where((report) => inSource(report, _archivedSource))
        .toList(growable: false);
    final rows = _visibleArchivedRecords;
    int countOf(String source) =>
        files.where((report) => inSource(report, source)).length +
        _archivedRecords
            .where(
              (row) =>
                  (source == 'الكل' || row.source == source) &&
                  (query.isEmpty ||
                      row.title.contains(query) ||
                      row.subtitle.contains(query)),
            )
            .length;
    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadArchivedRecords,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // البحث وبجانبه فلتر الفترة، ثم زر «البحث في الأرشيف» وعلامة
          // الفلتر — كلاهما يفتح نافذة الفلتر نفسها وزرّها الأخير «ابحث».
          _buildActionCard(
            icon: Icons.inventory_2_outlined,
            title: 'الأرشيف',
            subtitle:
                'اختر القسم وفلتره كما في الصفحة الرئيسية ثم «ابحث»؛ تُحفظ '
                'النتيجة ملفًا يمكن مشاركته وطباعته.',
            controller: _archivedSearch,
            hint: 'ابحث في الأرشيف',
            searchTrailing: _periodFilterButton(
              value: _archiveListFilter,
              range: _archiveRange,
              tall: true,
              onChanged: (value, range) => setState(() {
                _archiveListFilter = value;
                _archiveRange = range;
              }),
            ),
            buttonLabel: 'البحث في الأرشيف',
            buttonIcon: Icons.manage_search_rounded,
            onPressed: _loadingItems
                ? null
                : () => _openReportFilter(archive: true),
            footer: [
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _exportArchivedRecords,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text(
                  'تصدير المؤرشفات PDF',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // الجملة مكان «ملفات الأرشيف»، وتحتها الأقسام؛ ملفات الأرشيف
          // والمؤرشف من الأقسام في قائمة واحدة، كلٌّ تحت قسمه ومع «الكل».
          _searchHintLine(),
          _plainListTitle('ملفات الأرشيف', shownFiles.length + rows.length),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final source in ['الكل', ...ArchiveCenter.sources])
                  _archiveSourcePill(source, countOf(source)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingArchived && shownFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shownFiles.isEmpty && rows.isEmpty)
            _emptyCard(
              Icons.inventory_2_outlined,
              query.isEmpty
                  ? 'لا يوجد شيء مؤرشف في هذا القسم بعد.'
                  : 'لا يوجد ما يطابق البحث في هذا القسم.',
            )
          else ...[
            for (final report in shownFiles)
              _buildReportRow(report, archived: true),
            for (final row in rows) _archivedRecordCard(row),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // الاتجاه مفروض على الـScaffold كاملًا (وليس على الجسم فقط) حتى يبدأ
    // شريط التبويبات من اليمين: "التقارير" أولًا ثم "الأرشيف". كان الشريط
    // خارج نطاق الاتجاه فيظهر معكوسًا.
    return Directionality(
      textDirection: AppTr.uiDir,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppTheme.page,
          appBar: AppBar(
            title: const Text(
              'التقارير / الأرشيف',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            centerTitle: true,
            backgroundColor: AppTheme.page,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppTheme.title,
            elevation: 0,
            scrolledUnderElevation: 0,
            bottom: const TabBar(
              labelColor: _accent,
              unselectedLabelColor: AppTheme.muted,
              indicatorColor: _accent,
              indicatorWeight: 3,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              tabs: [
                Tab(icon: Icon(Icons.description_outlined, size: 19), text: 'التقارير'),
                Tab(icon: Icon(Icons.inventory_2_outlined, size: 19), text: 'الأرشيف'),
              ],
            ),
          ),
          body: TabBarView(
            children: [_buildReportsTab(), _buildArchiveTab()],
          ),
        ),
      ),
    );
  }
}

class _GeneratedReport {
  const _GeneratedReport({
    required this.id,
    required this.title,
    required this.type,
    required this.subject,
    required this.mode,
    required this.fromDate,
    required this.toDate,
    required this.dataFields,
    required this.createdBy,
    required this.createdAt,
    this.selection,
    this.filter,
    this.archivedAt,
    this.archiveReason = '',
  });

  final String id;
  final String title;
  final String type;
  final String subject;
  final String mode;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<String> dataFields;
  final String createdBy;
  final DateTime createdAt;

  /// اختيار المستخدم الكامل (القسم، الأقسام، الأنواع، التصفية، التاريخ)
  /// — هو ما يُبنى منه محتوى التقرير عند فتحه، فيبقى التقرير حيًّا يعكس
  /// البيانات لا صورة ثابتة بلا مصدر.
  final ScopeSelection? selection;

  /// معايير فلتر الصفحة الرئيسية (التقارير الجديدة) — بديل [selection].
  final ReportFilter? filter;

  /// تاريخ الأرشفة وسببها — يظهران في بطاقة العنصر المؤرشف.
  final DateTime? archivedAt;
  final String archiveReason;

  _GeneratedReport copyWith({DateTime? archivedAt, String? archiveReason}) =>
      _GeneratedReport(
        id: id,
        title: title,
        type: type,
        subject: subject,
        mode: mode,
        fromDate: fromDate,
        toDate: toDate,
        dataFields: dataFields,
        createdBy: createdBy,
        createdAt: createdAt,
        selection: selection,
        filter: filter,
        archivedAt: archivedAt ?? this.archivedAt,
        archiveReason: archiveReason ?? this.archiveReason,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'type': type,
    'subject': subject,
    'mode': mode,
    'fromDate': fromDate?.toIso8601String(),
    'toDate': toDate?.toIso8601String(),
    'dataFields': dataFields,
    'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
    'selection': selection?.toMap(),
    'filter': filter?.toMap(),
    'archivedAt': archivedAt?.toIso8601String(),
    'archiveReason': archiveReason,
  };

  factory _GeneratedReport.fromMap(Map<String, dynamic> map) {
    DateTime? parse(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return _GeneratedReport(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      type: (map['type'] ?? 'تقرير عام').toString(),
      subject: (map['subject'] ?? '').toString(),
      mode: (map['mode'] ?? 'عام').toString(),
      fromDate: parse(map['fromDate']),
      toDate: parse(map['toDate']),
      dataFields: (map['dataFields'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      createdBy: (map['createdBy'] ?? '').toString(),
      createdAt: parse(map['createdAt']) ?? DateTime.now(),
      selection: map['selection'] is Map
          ? ScopeSelection.fromMap(
              Map<String, dynamic>.from(map['selection'] as Map),
            )
          : null,
      filter: map['filter'] is Map
          ? ReportFilter.fromMap(
              Map<String, dynamic>.from(map['filter'] as Map),
            )
          : null,
      archivedAt: parse(map['archivedAt']),
      archiveReason: (map['archiveReason'] ?? '').toString(),
    );
  }
}

class _DelegationsHubPage extends StatefulWidget {
  const _DelegationsHubPage({
    this.presetDelegate,
    this.initialDirection = 'granted',
    this.presetSub,
    this.presetTarget,
  });

  /// «تفويض آخرين» من صفحة عنصر: القسم الفرعي والعنصر مختاران مسبقًا.
  final String? presetSub;
  final DelegationTarget? presetTarget;

  /// الاتجاه المعروض أولًا: granted (تفويضاتي) أو received (وصلتني).
  final String initialDirection;

  /// فتح «تفويض جديد» مباشرة لهذا المفوَّض، ثم الرجوع بعد إغلاق النموذج.
  final String? presetDelegate;

  @override
  State<_DelegationsHubPage> createState() => _DelegationsHubPageState();
}

class _DelegationsHubPageState extends State<_DelegationsHubPage> {
  String _selectedFilter = 'all';

  /// اتجاه التفويض المعروض: تفويضات منحتُها (granted) أو تفويضات مُنحت لي
  /// (received). الاتجاه محفوظ داخل السجل نفسه، فلا يضيع بين الجلسات.
  late String _direction = widget.initialDirection;

  // كانت هذه قائمة داخل الذاكرة مصحوبة بثلاثة تفويضات وهمية: كل إضافة أو
  // تعديل أو حذف يضيع بمجرد الخروج من الصفحة، وتعود البيانات الوهمية.
  final DelegationsRepository _repository = SupabaseDelegationsRepository();
  List<_DelegationRecord> _delegations = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
    final preset = widget.presetDelegate;
    if (preset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _openCreateSheet(
          presetDelegate: preset,
          presetSub: widget.presetSub,
          presetTarget: widget.presetTarget,
        );
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      // يُعرض مؤشر التحميل في أول تحميل فقط؛ إظهاره أثناء السحب للتحديث
      // يزيل القائمة ومعها مؤشر السحب نفسه قبل أن يكتمل.
      _loading = _delegations.isEmpty;
      _loadError = null;
    });
    try {
      // ومعها ما وصلني من حسابات أخرى بالرقم التعريفي.
      final rows = await _repository.fetchDelegations(includeIncoming: true);
      if (!mounted) return;
      setState(() {
        _delegations = rows.map(_DelegationRecord.fromRecord).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذّر تحميل التفويضات. تحقّق من الاتصال وحاول مجددًا.';
      });
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _persist(_DelegationRecord record, {String? notice}) async {
    try {
      await _repository.upsertDelegation(record.toRecord());
      await _load();
      if (notice != null) {
        _notify(notice.contains('بنجاح') ? notice : '$notice بنجاح');
      }
    } catch (error) {
      if (error is PlanLockedException) {
        if (mounted) PlanGate.canEdit(context, PlanModules.delegations);
        return;
      }
      _notify('تعذّر حفظ التفويض. حاول مرة أخرى.');
    }
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  bool _isExpiringSoon(_DelegationRecord d) {
    if (!d.active || _isEnded(d)) return false;
    final now = DateTime.now();
    final remaining = d.endDate.difference(now).inDays;
    return remaining >= 0 && remaining <= 30;
  }

  /// ساري طوال يوم نهايته (مقارنة بالتاريخ لا بالساعة).
  bool _isEnded(_DelegationRecord d) {
    return DateUtils.dateOnly(d.endDate)
        .isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  bool _isScheduled(_DelegationRecord d) {
    return d.active && d.startDate.isAfter(DateTime.now());
  }

  bool _isActive(_DelegationRecord d) {
    return d.active && !_isEnded(d) && !_isScheduled(d);
  }

  ({String label, Color color, IconData icon}) _statusOf(
    _DelegationRecord delegation,
  ) {
    // التفويض بالرقم التعريفي: رد المفوَّض قبل حالة المدة.
    final answer = DelegationRecord.acceptOf(delegation.permissions);
    // المفوَّض ألغى التفويض من عنده (ويستطيع العودة إليه).
    if (answer == 'withdrawn') {
      return (
        label: delegation.isIncoming ? 'ألغيتَه من عندك' : 'ألغاه المفوَّض',
        color: const Color(0xFFC4392E),
        icon: Icons.logout_rounded,
      );
    }
    if (answer == 'rejected') {
      return (
        label: delegation.isIncoming ? 'رفضتَه' : 'رفضه المفوَّض',
        color: const Color(0xFFC4392E),
        icon: Icons.block_rounded,
      );
    }
    if (answer == 'pending' && !_isEnded(delegation)) {
      return (
        label: delegation.isIncoming
            ? 'بانتظار ردك'
            : '${AppTr.tr('بانتظار قبول')} ${delegation.delegateName}',
        color: const Color(0xFFCE8422),
        icon: Icons.hourglass_top_rounded,
      );
    }
    if (_isEnded(delegation)) {
      return (
        label: 'منتهي',
        color: const Color(0xFF5C6B68),
        icon: Icons.event_busy_outlined,
      );
    }
    if (!delegation.active) {
      return (
        label: 'موقوف',
        color: const Color(0xFFC4392E),
        icon: Icons.pause_circle_outline_rounded,
      );
    }
    if (_isScheduled(delegation)) {
      return (
        label: 'مجدول',
        color: const Color(0xFF0A5A50),
        icon: Icons.schedule_rounded,
      );
    }
    if (_isExpiringSoon(delegation)) {
      return (
        label: 'ينتهي قريبًا',
        color: const Color(0xFFCE8422),
        icon: Icons.timer_outlined,
      );
    }
    return (
      label: 'نشط',
      color: const Color(0xFF178F7B),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  String _periodSummary(_DelegationRecord delegation) {
    if (_isEnded(delegation))
      return 'منتهي في ${_formatDate(delegation.endDate)}';
    if (_isScheduled(delegation)) {
      return 'يبدأ في ${_formatDate(delegation.startDate)}';
    }
    final days = delegation.endDate.difference(DateTime.now()).inDays + 1;
    return 'متبقي $days يوم';
  }

  /// تفويضات الاتجاه المعروض فقط — أساس كل الأعداد والفلاتر أدناه.
  List<_DelegationRecord> get _directionDelegations => _delegations
      .where((d) => _direction == 'received' ? d.isReceived : !d.isReceived)
      .toList(growable: false);

  List<_DelegationRecord> _filteredDelegations() {
    final source = _directionDelegations;
    if (_selectedFilter == 'active') {
      return source
          .where((d) => _isActive(d) && !_isExpiringSoon(d))
          .toList(growable: false);
    }
    if (_selectedFilter == 'expiring') {
      return source.where(_isExpiringSoon).toList(growable: false);
    }
    if (_selectedFilter == 'ended') {
      return source.where(_isEnded).toList(growable: false);
    }
    if (_selectedFilter == 'paused') {
      return source
          .where((d) => !d.active && !_isEnded(d))
          .toList(growable: false);
    }
    return source;
  }

  /// تسميات فلاتر الحالة الخمسة مع أعدادها — مصدر واحد للزر وللقائمة.
  List<({String key, String label, int count})> _statusFilterOptions() {
    final source = _directionDelegations;
    // "النشطة" = نشط وغير قارب على الانتهاء؛ تُحسب بالشرط نفسه المستخدم
    // في التصفية، فلا ينتج عدد سالب حين يكون تفويض مجدولًا وقريب الانتهاء.
    final active = source
        .where((d) => _isActive(d) && !_isExpiringSoon(d))
        .length;
    final expiring = source.where(_isExpiringSoon).length;
    return [
      (key: 'all', label: 'الكل', count: source.length),
      (key: 'active', label: 'النشطة', count: active),
      (key: 'expiring', label: 'قريبة الانتهاء', count: expiring),
      (
        key: 'paused',
        label: 'الموقوفة',
        count: source.where((d) => !d.active && !_isEnded(d)).length,
      ),
      (key: 'ended', label: 'المنتهية', count: source.where(_isEnded).length),
    ];
  }

  String _statusFilterLabel() => _statusFilterOptions()
      .firstWhere((option) => option.key == _selectedFilter)
      .label;

  /// قائمة فلاتر الحالة الخمسة — تُفتح من زر "التفويضات المسجلة" في منتصف
  /// الصفحة، بنفس أسلوب زر الفرز في بقية الشاشات.
  void _openStatusFilterMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'التفويضات المسجلة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1C2C29),
                    ),
                  ),
                ),
              ),
              for (final option in _statusFilterOptions())
                ListTile(
                  key: ValueKey('delegation-filter-${option.key}'),
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _selectedFilter == option.key
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: const Color(0xFF1C2C29),
                    ),
                  ),
                  trailing: Text(
                    '${option.count}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                  leading: Icon(
                    _selectedFilter == option.key
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 19,
                    color: _selectedFilter == option.key
                        ? const Color(0xFF0E7161)
                        : const Color(0xFF8C9A97),
                  ),
                  onTap: () {
                    setState(() => _selectedFilter = option.key);
                    Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// اختيار المفوَّض من «الأفراد والجهات».
  /// (الاسم، الرقم التعريفي المسجَّل له في «الأفراد والجهات» إن وُجد).
  Future<(String, String)?> _pickDelegateFromPeople() async {
    final entries = await PeopleDirectoryStore.load();
    if (!mounted) return null;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد أفراد أو جهات بعد — اضغط «شخص جديد»'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    var query = '';
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final q = query.trim();
          final filtered = entries
              .where(
                (e) =>
                    q.isEmpty ||
                    e.fullName.contains(q) ||
                    e.categoryName.contains(q),
              )
              .toList(growable: false);
          return Directionality(
            textDirection: AppTr.uiDir,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختر من الأفراد والجهات',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    textDirection: AppTr.uiDir,
                    onChanged: (value) => setSheet(() => query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppTr.tr('ابحث بالاسم أو التصنيف'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppTheme.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.line),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            entry.isEntity
                                ? Icons.business_rounded
                                : Icons.person_rounded,
                            color: const Color(0xFF0E7161),
                          ),
                          title: Text(
                            entry.fullName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            entry.categoryName,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(sheetContext, (
                            entry.fullName,
                            entry.detail('الرقم التعريفي').trim(),
                          )),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// «شخص جديد»: الاسم والجوال، ثم تنبيه أنه سيُحفظ في «الأفراد والجهات».
  /// «شخص جديد»: بالرقم التعريفي فقط — يظهر اسم صاحبه من الخادم ليتأكد
  /// المستخدم، ثم يُحفظ في «الأفراد والجهات» برقمه. (الاسم، الرقم).
  Future<(String, String)?> _addNewDelegatePerson() async {
    final found = await askFndPerson(
      context,
      title: 'شخص جديد بالرقم التعريفي',
      confirmLabel: 'التالي',
    );
    if (found == null || !mounted) return null;
    final (fnd, name) = found;
    final confirmed = await confirmAction(
      context,
      title: 'حفظ في الأفراد والجهات',
      message: 'سيُحفظ «$name» ($fnd) هنا في التفويض وفي «الأفراد والجهات» '
          'أيضًا. موافق؟',
      confirmLabel: 'موافق',
    );
    if (!confirmed) return null;
    await PeopleDirectoryStore.upsert(
      fullName: name,
      typeKey: 'person_other',
      categoryName: 'أخرى',
      roleTitle: 'مفوَّض',
      details: {'الرقم التعريفي': fnd},
      sourceNote: 'تفويض',
    );
    return (name, fnd);
  }

  Future<void> _openCreateSheet({
    _DelegationRecord? existing,
    int? index,
    String? presetDelegate,
    String? presetSub,
    DelegationTarget? presetTarget,
  }) async {
    if (!await FundlyAuth.requireLogin(context)) return;
    if (!mounted) return;
    final delegateController = TextEditingController(
      text: existing?.delegateName ?? presetDelegate ?? '',
    );
    // الرقم التعريفي للمفوَّض: به يصله التفويض في تطبيقه ليقبل أو يرفض.
    final delegateIdController = TextEditingController(
      text: DelegationRecord.delegateFndOf(
        existing?.permissions ?? const <String>[],
      ),
    );
    if (existing == null &&
        (presetDelegate ?? '').trim().isNotEmpty &&
        delegateIdController.text.trim().isEmpty) {
      final entries = await PeopleDirectoryStore.load();
      for (final entry in entries) {
        if (entry.fullName.trim() == presetDelegate!.trim()) {
          delegateIdController.text = entry.detail('الرقم التعريفي').trim();
          break;
        }
      }
      if (!mounted) return;
    }
    final previousAnswer = DelegationRecord.acceptOf(
      existing?.permissions ?? const <String>[],
    );
    // صاحب الرقم التعريفي يُعرض تحته، فيتأكد المستخدم أنه المفوَّض الصحيح.
    var fndChecked = '';
    String? fndOwner;
    var fndLooking = false;
    Future<void> lookupFnd(StateSetter setModalState) async {
      final id = AppIdentity.normalize(delegateIdController.text);
      if (!AppIdentity.isValid(id)) {
        setModalState(() {
          fndChecked = '';
          fndOwner = null;
          fndLooking = false;
        });
        return;
      }
      if (id == fndChecked) return;
      setModalState(() => fndLooking = true);
      final name = await FundlyAccount.nameForFnd(id);
      if (AppIdentity.normalize(delegateIdController.text) != id) return;
      setModalState(() {
        fndChecked = id;
        fndOwner = name;
        fndLooking = false;
      });
    }
    // القوائم الرسمية من طبقة البيانات بدل ثلاث قوائم متباينة (النموذج،
    // المستودع، القاعدة) لا يطابق بعضها بعضًا.
    final types = DelegationRecord.scopes;
    // النطاق المخزَّن نصٌّ مركّب "رئيسي — فرع، فرع"، فيُفكّ هنا إلى
    // اختيار رئيسي + أقسام فرعية حتى يعمل التعديل على تفويض قديم.
    String selectedType = DelegationRecord.mainScopeOf(
      existing?.delegationType,
    );
    final selectedSubScopes = <String>{
      ...DelegationRecord.subScopesOf(existing?.delegationType),
    };
    final selectedPermissions = <String>{
      ...?existing?.permissions.where((p) => !DelegationRecord.isMeta(p)),
      if (existing == null) 'عرض البيانات',
    };
    // عناصر بعينها (عهدة، بناية، مركبة، شخص...) بدل القسم الفرعي كاملًا.
    final selectedTargets = <DelegationTarget>{
      for (final p in existing?.permissions ?? const <String>[])
        if (DelegationTarget.decode(p) case final target?) target,
    };
    // من صفحة عقار/وحدة/مركبة/نشاط: القسم والعنصر مختاران مسبقًا.
    if (existing == null && presetSub != null && presetTarget != null) {
      selectedType = 'العقارات والأنشطة والمركبات';
      selectedSubScopes
        ..clear()
        ..add(presetSub);
      selectedTargets.add(presetTarget);
    }
    final existingLimit = DelegationRecord.limitOf(
      existing?.permissions ?? const <String>[],
    );
    final limitController = TextEditingController(
      text: existingLimit == null ? '' : '$existingLimit',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    // المستوى يحدد الإجراءات: الأساسية ثابتة له، والإضافية تُختار من
    // المسموح به فقط — «اطّلاع فقط» لا يسمح بإضافة سجلات.
    var selectedLevel = DelegationRecord.levelOf(selectedPermissions);
    void applyLevel(String level) {
      final approval = selectedPermissions.contains(
        DelegationRecord.kNeedsOwnerApproval,
      );
      final allowed = DelegationRecord.levelExtras[level] ?? const <String>[];
      final keptExtras = level == DelegationRecord.fullLevel
          ? DelegationRecord.extraPermissions
          : selectedPermissions.where(allowed.contains).toList();
      selectedLevel = level;
      selectedPermissions
        ..clear()
        ..addAll(DelegationRecord.coreOf(level))
        ..addAll(keptExtras);
      if (approval) {
        selectedPermissions.add(DelegationRecord.kNeedsOwnerApproval);
      }
    }

    applyLevel(selectedLevel);
    DateTime startDate = existing?.startDate ?? DateTime.now();
    // مدة التفويض الجاهزة المختارة من القائمة بجانب «مدة التفويض».
    var durationPreset = 'مخصص';
    DateTime endDate =
        existing?.endDate ?? DateTime.now().add(const Duration(days: 365));
    // اتجاه التفويض: صادر مني أو وارد إليّ — يحدّد أيّ من الخيارين
    // (فوّضتُ أشخاصًا / أشخاص فوّضوني) يظهر فيه السجل.
    bool isReceived = existing?.isReceived ?? _direction == 'received';
    String? validationMessage;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
                ),
                child: SingleChildScrollView(
                  child: Directionality(
                    textDirection: AppTr.uiDir,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                            Expanded(
                              child: Text(
                                existing == null
                                    ? 'إنشاء تفويض'
                                    : 'تعديل التفويض',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1C2C29),
                                ),
                              ),
                            ),
                            const SizedBox(width: 44),
                          ],
                        ),
                        const Text(
                          'امنح وصولًا محددًا ولمدة واضحة. يمكنك إيقاف التفويض في أي وقت.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Color(0xFF76837F),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // صفحة الإنشاء بلا «منحتُه / مُنح لي»: الاتجاه من
                        // التبويب المفتوح. يظهر الاختيار عند التعديل فقط.
                        if (existing != null)
                        Row(
                          children: [
                            Expanded(
                              child: _DelegationDirectionButton(
                                key: const ValueKey('sheet-direction-granted'),
                                label: 'تفويض منحتُه',
                                icon: Icons.person_add_alt_1_outlined,
                                selected: !isReceived,
                                onTap: () =>
                                    setModalState(() => isReceived = false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DelegationDirectionButton(
                                key: const ValueKey('sheet-direction-received'),
                                label: 'تفويض مُنح لي',
                                icon: Icons.how_to_reg_outlined,
                                selected: isReceived,
                                onTap: () =>
                                    setModalState(() => isReceived = true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '1. الشخص أو الجهة المفوضة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (delegateController.text.trim().isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9F4F1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFCFE5DF),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: Color(0xFF0E7161),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    delegateController.text.trim(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1C2C29),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: AppTr.tr('إزالة'),
                                  onPressed: () => setModalState(
                                    delegateController.clear,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked =
                                      await _pickDelegateFromPeople();
                                  if (picked == null) return;
                                  final (name, fnd) = picked;
                                  setModalState(() {
                                    delegateController.text = name;
                                    // رقمه التعريفي المسجَّل يُكتب تلقائيًا.
                                    if (fnd.isNotEmpty && !isReceived) {
                                      delegateIdController.text = fnd;
                                    }
                                  });
                                  await lookupFnd(setModalState);
                                },
                                icon: const Icon(
                                  Icons.person_search_rounded,
                                  size: 19,
                                ),
                                label: const Text('جلب من الأفراد'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0E7161),
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final added = await _addNewDelegatePerson();
                                  if (added == null) return;
                                  final (name, fnd) = added;
                                  setModalState(() {
                                    delegateController.text = name;
                                    if (!isReceived) {
                                      delegateIdController.text = fnd;
                                    }
                                  });
                                  await lookupFnd(setModalState);
                                },
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 19,
                                ),
                                label: const Text('شخص جديد'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF0E7161),
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isReceived) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: delegateIdController,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (_) => lookupFnd(setModalState),
                            decoration: InputDecoration(
                              labelText: AppTr.tr(
                                'الرقم التعريفي للمفوَّض (إلزامي — به يصله التفويض)',
                              ),
                              hintText: 'FND-XXXX-XXXX',
                              helperText: fndNameHint(),
                              helperMaxLines: 3,
                              prefixIcon: const Icon(Icons.badge_outlined),
                              filled: true,
                              fillColor: AppTheme.field,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          // صاحب الرقم: «الرقم التعريفي يخص: زين».
                          if (fndLooking)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'جارٍ التحقق من صاحب الرقم...',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5C6B68),
                                ),
                              ),
                            )
                          else if (fndChecked.isNotEmpty &&
                              fndChecked ==
                                  AppIdentity.normalize(
                                    delegateIdController.text,
                                  ))
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: fndOwner != null
                                    ? AppTheme.brandSoft
                                    : const Color(0xFFFFF6E8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    fndOwner != null
                                        ? Icons.verified_user_outlined
                                        : Icons.help_outline_rounded,
                                    size: 18,
                                    color: fndOwner != null
                                        ? AppTheme.brand
                                        : const Color(0xFFA6691A),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      fndOwner != null
                                          ? '${AppTr.tr('الرقم التعريفي يخص')}: '
                                                '$fndOwner — '
                                                '${AppTr.tr('تأكد أنه المفوَّض الصحيح')}'
                                          : AppTr.tr(
                                              'لم يُعثر على صاحب هذا الرقم — تأكد منه',
                                            ),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: fndOwner != null
                                            ? AppTheme.brand
                                            : const Color(0xFF6B4A12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (previousAnswer.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              previousAnswer == 'accepted'
                                  ? 'قبِل المفوَّض هذا التفويض'
                                  : previousAnswer == 'rejected'
                                  ? 'رفض المفوَّض هذا التفويض'
                                  : 'بانتظار قبول المفوَّض',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: previousAnswer == 'accepted'
                                    ? const Color(0xFF178F7B)
                                    : previousAnswer == 'rejected'
                                    ? const Color(0xFFC4392E)
                                    : const Color(0xFFCE8422),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // تنبيه: حالة كل مفوَّض تُتابع من صفحة التفويضات.
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF6E8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Color(0xFFA6691A),
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'بعد الإرسال تعرف حالة كل مفوَّض (بانتظار القبول، نشط، رفضه، ألغاه) وتستطيع إلغاء تفويضه من «المزيد ← التفويضات».',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.45,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6B4A12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          '2. نطاق التفويض',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: selectedType,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppTheme.field,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                          items: types
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) {
                            if (v == null) return;
                            setModalState(() {
                              selectedType = v;
                              // الأقسام الفرعية تخصّ نطاقًا بعينه، فتُمسح
                              // عند تغييره بدل بقاء اختيار لا ينتمي إليه.
                              selectedSubScopes.clear();
                              selectedTargets.clear();
                            });
                          },
                        ),
                        // الأقسام الفرعية للنطاق المختار: تفويض أدقّ من
                        // "قسم كامل" — وتركها فارغة يعني القسم بأكمله.
                        if ((DelegationRecord.subScopes[selectedType] ??
                                const <String>[])
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'أقسام فرعية داخل النطاق (اتركها فارغة = النطاق كاملًا)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5C6B68),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children:
                                (DelegationRecord.subScopes[selectedType] ??
                                        const <String>[])
                                    .map(
                                      (sub) => FilterChip(
                                        label: Text(sub),
                                        selected: selectedSubScopes.contains(
                                          sub,
                                        ),
                                        selectedColor: const Color(0xFFE4EAE8),
                                        checkmarkColor: const Color(0xFF0E7161),
                                        labelStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        onSelected: (selected) async {
                                          setModalState(() {
                                            if (selected) {
                                              selectedSubScopes.add(sub);
                                            } else {
                                              selectedSubScopes.remove(sub);
                                              selectedTargets.removeWhere(
                                                (t) => t.sub == sub,
                                              );
                                            }
                                          });
                                          // القسم الذي فيه عناصر (العهد،
                                          // العقارات...) يفتح قائمتها فورًا
                                          // لاختيار عنصر بعينه أو «الكل».
                                          if (!selected ||
                                              !DelegationTargets.supports(
                                                selectedType,
                                                sub,
                                              )) {
                                            return;
                                          }
                                          final picked =
                                              await _pickDelegationTargets(
                                                selectedType,
                                                sub,
                                                selectedTargets
                                                    .where((t) => t.sub == sub)
                                                    .toSet(),
                                              );
                                          if (picked == null) return;
                                          setModalState(() {
                                            selectedTargets
                                              ..removeWhere(
                                                (t) => t.sub == sub,
                                              )
                                              ..addAll(picked);
                                          });
                                        },
                                      ),
                                    )
                                    .toList(growable: false),
                          ),
                        ],
                        // ملخص العناصر المحددة لكل قسم فرعي يدعمها.
                        for (final sub in selectedSubScopes.where(
                          (s) => DelegationTargets.supports(selectedType, s),
                        ))
                          _delegationTargetsTile(
                            sub: sub,
                            targets: selectedTargets
                                .where((t) => t.sub == sub)
                                .toList(growable: false),
                            onChange: () async {
                              final picked = await _pickDelegationTargets(
                                selectedType,
                                sub,
                                selectedTargets
                                    .where((t) => t.sub == sub)
                                    .toSet(),
                              );
                              if (picked == null) return;
                              setModalState(() {
                                selectedTargets
                                  ..removeWhere((t) => t.sub == sub)
                                  ..addAll(picked);
                              });
                            },
                            onRemove: (target) =>
                                setModalState(() => selectedTargets.remove(target)),
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          '3. الصلاحيات',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final level
                                in DelegationRecord.permissionLevels.keys)
                              ChoiceChip(
                                label: Text(level),
                                selected: selectedLevel == level,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                selectedColor: const Color(0xFF0E7161),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: selectedLevel == level
                                      ? Colors.white
                                      : const Color(0xFF1C2C29),
                                ),
                                onSelected: (_) =>
                                    setModalState(() => applyLevel(level)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(
                          height: 1,
                          thickness: 0.8,
                          color: Color(0xFFDDE5E3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'الإجراءات',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'تتحدد حسب «$selectedLevel» — الرمادي غير مسموح به '
                          'في هذا المستوى.',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF76837F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: () {
                            final extras =
                                DelegationRecord.levelExtras[selectedLevel] ??
                                const <String>[];
                            // الإضافية: تُختار من المسموح به للمستوى فقط.
                            bool canPick(String permission) =>
                                selectedLevel != DelegationRecord.fullLevel &&
                                extras.contains(permission);
                            // المتاح (الممنوح أو القابل للاختيار) في الأعلى،
                            // والباهت غير المسموح به في الأسفل دائمًا.
                            bool usable(String permission, bool core) =>
                                selectedPermissions.contains(permission) ||
                                (!core && canPick(permission));
                            final all = [
                              // الأساسية: ثابتة للمستوى المختار.
                              for (final p in DelegationRecord.orderedPermissions)
                                (p, true),
                              for (final p in DelegationRecord.extraPermissions)
                                (p, false),
                            ];
                            final sorted = [
                              ...all.where((e) => usable(e.$1, e.$2)),
                              ...all.where((e) => !usable(e.$1, e.$2)),
                            ];
                            return [
                              for (final (permission, core) in sorted)
                                FilterChip(
                                  label: Text(permission),
                                  selected: selectedPermissions.contains(
                                    permission,
                                  ),
                                  selectedColor: const Color(0xFFE4EAE8),
                                  checkmarkColor: const Color(0xFF0E7161),
                                  // مسافة عادية بين الأسطر.
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  onSelected: core || !canPick(permission)
                                      ? null
                                      : (selected) => setModalState(() {
                                          if (selected) {
                                            selectedPermissions.add(permission);
                                          } else {
                                            selectedPermissions.remove(
                                              permission,
                                            );
                                          }
                                        }),
                                ),
                            ];
                          }(),
                        ),
                        // سقف مبلغ العملية الواحدة — يظهر مع صلاحية المدفوعات.
                        if (selectedPermissions.contains(
                          'تنفيذ المدفوعات والتحويلات',
                        )) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: limitController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textDirection: AppTr.uiDir,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: AppTheme.field,
                              labelText: AppTr.tr(
                                'سقف المبلغ للعملية الواحدة (اختياري)',
                              ),
                              helperText: AppTr.tr('اتركه فارغًا بلا سقف'),
                              suffixText: AppSettings.currencySuffix,
                              prefixIcon: const Icon(
                                Icons.payments_outlined,
                                size: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // هل يعتمد ما يكتبه المفوَّض مباشرة، أم ينتظر
                        // موافقة المالك؟
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F8F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE4EAE8)),
                          ),
                          child: SwitchListTile.adaptive(
                            value: selectedPermissions.contains(
                              DelegationRecord.kNeedsOwnerApproval,
                            ),
                            activeThumbColor: const Color(0xFF0E7161),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: const Text(
                              'يتطلب موافقة المالك',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1C2C29),
                              ),
                            ),
                            subtitle: Text(
                              selectedPermissions.contains(
                                    DelegationRecord.kNeedsOwnerApproval,
                                  )
                                  ? 'ما يدخله المفوَّض يُرسل للمالك ولا يُعتمد '
                                        'إلا بعد موافقته.'
                                  : 'المفوَّض يكتب ويعتمد مباشرة بلا موافقة '
                                        'المالك.',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5C6B68),
                              ),
                            ),
                            onChanged: (value) => setModalState(() {
                              if (value) {
                                selectedPermissions.add(
                                  DelegationRecord.kNeedsOwnerApproval,
                                );
                              } else {
                                selectedPermissions.remove(
                                  DelegationRecord.kNeedsOwnerApproval,
                                );
                              }
                            }),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // العنوان وبجانبه قائمة المدد الجاهزة (ومعها «مخصص»).
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '4. مدة التفويض',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1C2C29),
                                ),
                              ),
                            ),
                            PopupMenuButton<(String, int)>(
                              tooltip: AppTr.tr('مدة التفويض'),
                              position: PopupMenuPosition.under,
                              onSelected: (preset) => setModalState(() {
                                durationPreset = preset.$1;
                                if (preset.$2 > 0) {
                                  endDate = startDate.add(
                                    Duration(days: preset.$2),
                                  );
                                }
                              }),
                              itemBuilder: (context) => [
                                for (final preset in const [
                                  ('أسبوع', 7),
                                  ('شهر', 30),
                                  ('3 أشهر', 90),
                                  ('6 أشهر', 182),
                                  ('سنة', 365),
                                  ('مخصص', 0),
                                ])
                                  PopupMenuItem<(String, int)>(
                                    value: preset,
                                    child: Text(
                                      preset.$1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            preset.$1 == durationPreset
                                            ? FontWeight.w900
                                            : FontWeight.w600,
                                        color: preset.$1 == durationPreset
                                            ? const Color(0xFF0E7161)
                                            : const Color(0xFF1C2C29),
                                      ),
                                    ),
                                  ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F8F7),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE4EAE8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      durationPreset,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0E7161),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 20,
                                      color: Color(0xFF0E7161),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: _DateFieldTile(
                                label: 'تاريخ البداية',
                                value: _formatDate(startDate),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked == null) return;
                                  setModalState(() {
                                    startDate = picked;
                                    durationPreset = 'مخصص';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DateFieldTile(
                                label: 'تاريخ النهاية',
                                value: _formatDate(endDate),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: endDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked == null) return;
                                  setModalState(() {
                                    endDate = picked;
                                    durationPreset = 'مخصص';
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '5. الغرض من التفويض',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1C2C29),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: notesController,
                          maxLines: 2,
                          textDirection: AppTr.uiDir,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AppTheme.field,
                            hintText: AppTr.tr(
                              'مثال: متابعة تحصيل الإيجار أثناء سفري (اختياري)',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (validationMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDF4F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFF4C2BC),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFC4392E),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    validationMessage!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFA82F26),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () async {
                            final name = delegateController.text.trim();
                            if (name.isEmpty) {
                              setModalState(
                                () => validationMessage =
                                    'أدخل اسم الشخص أو الجهة المفوضة.',
                              );
                              return;
                            }
                            if (selectedPermissions.isEmpty) {
                              setModalState(
                                () => validationMessage =
                                    'اختر صلاحية واحدة على الأقل.',
                              );
                              return;
                            }
                            if (!endDate.isAfter(startDate)) {
                              setModalState(
                                () => validationMessage =
                                    'يجب أن يكون تاريخ النهاية بعد تاريخ البداية.',
                              );
                              return;
                            }
                            final delegateFnd = AppIdentity.normalize(
                              delegateIdController.text,
                            );
                            // الإضافة بالرقم التعريفي فقط: به يصل التفويض.
                            if (!isReceived && delegateFnd.isEmpty) {
                              setModalState(
                                () => validationMessage =
                                    'أدخل الرقم التعريفي للمفوَّض — التفويض '
                                    'يصل ويُقبل بالرقم التعريفي فقط.',
                              );
                              return;
                            }
                            if (!isReceived && delegateFnd.isNotEmpty) {
                              if (!AppIdentity.isValid(delegateFnd)) {
                                setModalState(
                                  () => validationMessage =
                                      'الرقم التعريفي بصيغة FND-XXXX-XXXX',
                                );
                                return;
                              }
                              if (delegateFnd == AppIdentity.id) {
                                setModalState(
                                  () => validationMessage =
                                      'لا يمكن تفويض نفسك',
                                );
                                return;
                              }
                            }
                            // رقم جديد ← بانتظار القبول؛ نفس الرقم ← يبقى رده.
                            final idMeta = <String>[
                              if (!isReceived &&
                                  AppIdentity.isValid(delegateFnd)) ...[
                                '${DelegationRecord.fndPrefix}$delegateFnd',
                                '${DelegationRecord.ownerNamePrefix}'
                                    '${AppSettings.instance.name}',
                                '${DelegationRecord.acceptPrefix}'
                                    '${DelegationRecord.delegateFndOf(existing?.permissions ?? const <String>[]) == delegateFnd && previousAnswer.isNotEmpty ? previousAnswer : 'pending'}',
                              ],
                            ];
                            // تأكيد قبل الحفظ، ثم رسالة «تم ... بنجاح».
                            final confirmed = await confirmAction(
                              context,
                              title: existing == null
                                  ? 'حفظ التفويض'
                                  : 'حفظ التعديل',
                              message: existing == null
                                  ? 'هل تريد حفظ تفويض «$name»؟'
                                  : 'هل تريد حفظ تعديل تفويض «$name»؟',
                              confirmLabel: 'تأكيد',
                            );
                            if (!confirmed || !context.mounted) return;
                            final record = _DelegationRecord(
                              // بدون تمرير المعرّف يُنشئ الحفظ سجلًا جديدًا
                              // في كل مرة بدل تعديل القائم — نسخة مكررة عند
                              // كل ضغطة "حفظ التعديل".
                              id: existing?.id,
                              notes: notesController.text.trim().isEmpty
                                  ? null
                                  : notesController.text.trim(),
                              // الاتجاه محفوظ داخل مرجع المفوَّض، فلا
                              // يحتاج عمودًا جديدًا في قاعدة البيانات.
                              delegateRef: isReceived
                                  ? _DelegationRecord.receivedMarker
                                  : (existing?.isReceived ?? false)
                                  ? null
                                  : existing?.delegateRef,
                              delegateName: name,
                              delegationType: DelegationRecord.composeScope(
                                selectedType,
                                selectedSubScopes,
                              ),
                              // العناصر المحددة والسقف والسجل تُحفظ مع
                              // الصلاحيات.
                              permissions: DelegationRecord.withLog([
                                ...selectedPermissions,
                                ...?existing?.permissions.where(
                                  (p) => p.startsWith(
                                    DelegationRecord.logPrefix,
                                  ),
                                ),
                                ...selectedTargets
                                    .where(
                                      (t) => selectedSubScopes.contains(t.sub),
                                    )
                                    .map((t) => t.encode()),
                                ...idMeta,
                                if (selectedPermissions.contains(
                                      'تنفيذ المدفوعات والتحويلات',
                                    ) &&
                                    (int.tryParse(
                                              limitController.text.trim(),
                                            ) ??
                                            0) >
                                        0)
                                  '${DelegationRecord.limitPrefix}'
                                      '${int.parse(limitController.text.trim())}',
                              ], () {
                                // سجل التعديل بما تغيّر فعلًا — ويصل نصه
                                // للمفوَّض إشعارًا.
                                final old = existing;
                                if (old == null) return 'إنشاء التفويض';
                                final before = DelegationRecord
                                    .plainPermissions(old.permissions)
                                    .toSet();
                                final after = selectedPermissions
                                    .where((p) => !DelegationRecord.isMeta(p))
                                    .toSet();
                                final addedPerms = after.difference(before);
                                final removedPerms = before.difference(after);
                                final scope = DelegationRecord.composeScope(
                                  selectedType,
                                  selectedSubScopes,
                                );
                                final oldTargets = {
                                  for (final p in old.permissions)
                                    if (p.startsWith(
                                      DelegationRecord.targetPrefix,
                                    ))
                                      p,
                                };
                                final newTargets = {
                                  for (final t in selectedTargets)
                                    if (selectedSubScopes.contains(t.sub))
                                      t.encode(),
                                };
                                final parts = <String>[
                                  if (addedPerms.isNotEmpty)
                                    'أُضيفت صلاحية: ${addedPerms.join('، ')}',
                                  if (removedPerms.isNotEmpty)
                                    'أُزيلت صلاحية: ${removedPerms.join('، ')}',
                                  if (!DateUtils.isSameDay(
                                        old.startDate,
                                        startDate,
                                      ) ||
                                      !DateUtils.isSameDay(
                                        old.endDate,
                                        endDate,
                                      ))
                                    'المدة: ${_formatDate(startDate)} - '
                                        '${_formatDate(endDate)}',
                                  if (old.delegationType != scope)
                                    'النطاق: $scope',
                                  if (oldTargets.length != newTargets.length ||
                                      !oldTargets.containsAll(newTargets))
                                    'تغيّرت العناصر المفوَّض بها',
                                  if (old.delegateName.trim() != name)
                                    'المفوَّض: $name',
                                ];
                                return parts.isEmpty
                                    ? 'تعديل التفويض'
                                    : 'تعديل التفويض — ${parts.join(' · ')}';
                              }()),
                              startDate: startDate,
                              endDate: endDate,
                              active: existing?.active ?? true,
                            );
                            // ينتقل العرض إلى اتجاه السجل المحفوظ، وإلا
                            // بدا كأن الحفظ لم ينشئ شيئًا.
                            setState(() {
                              _selectedFilter = 'all';
                              _direction = isReceived ? 'received' : 'granted';
                            });
                            Navigator.pop(context);
                            await _persist(
                              record,
                              notice: existing == null
                                  ? 'تمت إضافة التفويض'
                                  : 'تم حفظ التعديل',
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0E7161),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            index == null ? 'حفظ التفويض' : 'حفظ التعديل',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    delegateController.dispose();
    delegateIdController.dispose();
    limitController.dispose();
    notesController.dispose();
  }

  /// ملخص العناصر المحددة داخل قسم فرعي: «كل العهد» أو عدد المحدد مع
  /// رقائق قابلة للإزالة، وزر لتعديل الاختيار.
  Widget _delegationTargetsTile({
    required String sub,
    required List<DelegationTarget> targets,
    required VoidCallback onChange,
    required void Function(DelegationTarget target) onRemove,
  }) {
    final plural = DelegationTargets.pluralOf(sub);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E7161).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _delegationTargetIcon(sub),
                  size: 18,
                  color: const Color(0xFF0E7161),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1C2C29),
                      ),
                    ),
                    Text(
                      targets.isEmpty
                          ? '${AppTr.tr('التفويض على كل')} ${AppTr.tr(plural)}'
                          : '${targets.length} ${AppTr.tr('عنصر محدد فقط')}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF76837F),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onChange,
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: Text(
                  targets.isEmpty ? 'تحديد عناصر' : 'تعديل',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0E7161),
                ),
              ),
            ],
          ),
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final target in targets)
                  InputChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFDDE5E3)),
                    label: Text(
                      target.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C2C29),
                      ),
                    ),
                    deleteIconColor: const Color(0xFF76837F),
                    onDeleted: () => onRemove(target),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _delegationTargetIcon(String sub) => switch (sub) {
    'عهدة مالية' => Icons.inventory_2_outlined,
    'مالية' => Icons.account_balance_wallet_outlined,
    'مستند' => Icons.description_outlined,
    'المتابعة والتخطيط' => Icons.task_alt_outlined,
    'أدوية وبيانات وكلمات سر' => Icons.medication_outlined,
    'نمط الحياة' => Icons.celebration_outlined,
    'مواقع وأماكن' => Icons.location_on_outlined,
    'مشاركات مشتركة' => Icons.diversity_3_rounded,
    'الرحلة / السفر' => Icons.flight_takeoff_rounded,
    'جمعية مالية' => Icons.savings_outlined,
    'الأفراد' => Icons.person_outline_rounded,
    'الجهات والشركات' => Icons.apartment_outlined,
    'العقارات' => Icons.apartment_rounded,
    'الأنشطة التجارية' => Icons.storefront_outlined,
    'المركبات ووسائل النقل' => Icons.directions_car_outlined,
    _ => Icons.checklist_rounded,
  };

  /// قائمة عناصر القسم الفرعي (كل العهد، كل العقارات...) مع بحث واختيار
  /// متعدد. تُعيد: null = إلغاء، مجموعة فارغة = «الكل»، أو العناصر المحددة.
  Future<Set<DelegationTarget>?> _pickDelegationTargets(
    String main,
    String sub,
    Set<DelegationTarget> current,
  ) async {
    List<DelegationTarget> items;
    try {
      items = await DelegationTargets.load(main, sub);
    } catch (_) {
      _notify('تعذّر تحميل العناصر. تحقّق من الاتصال وحاول مجددًا.');
      return null;
    }
    if (!mounted) return null;
    final plural = DelegationTargets.pluralOf(sub);
    final icon = _delegationTargetIcon(sub);
    final chosen = <String>{for (final t in current) t.key};
    var query = '';
    return showModalBottomSheet<Set<DelegationTarget>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.rCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final q = query.trim();
          final shown = items
              .where(
                (t) =>
                    q.isEmpty ||
                    t.label.contains(q) ||
                    t.subtitle.contains(q),
              )
              .toList(growable: false);
          final allChosen =
              items.isNotEmpty && items.every((t) => chosen.contains(t.key));
          return Directionality(
            textDirection: AppTr.uiDir,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.86,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    12 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE5E3),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0E7161,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              icon,
                              color: const Color(0xFF0E7161),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${AppTr.tr('التفويض على')} ${AppTr.tr(plural)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1C2C29),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'اختر عنصرًا أو أكثر ليقتصر التفويض عليه، '
                                  'أو فوّض على الكل.',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF76837F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        textDirection: AppTr.uiDir,
                        onChanged: (value) => setSheet(() => query = value),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: AppTr.tr('ابحث بالاسم أو التفاصيل'),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: AppTheme.field,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.rField,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${items.length} ${AppTr.tr('عنصر')} • '
                              '${chosen.length} ${AppTr.tr('محدد')}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5C6B68),
                              ),
                            ),
                          ),
                          if (items.isNotEmpty)
                            TextButton(
                              onPressed: () => setSheet(() {
                                if (allChosen) {
                                  chosen.clear();
                                } else {
                                  chosen.addAll(items.map((t) => t.key));
                                }
                              }),
                              child: Text(
                                allChosen ? 'إلغاء التحديد' : 'تحديد الكل',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? Center(
                                child: Text(
                                  items.isEmpty
                                      ? '${AppTr.tr('لا توجد عناصر في')} '
                                            '${AppTr.tr(plural)} '
                                            '${AppTr.tr('بعد — سيشمل التفويض ما يُضاف لاحقًا.')}'
                                      : AppTr.tr('لا يوجد ما يطابق البحث.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF8C9A97),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: shown.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = shown[index];
                                  final on = chosen.contains(item.key);
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => setSheet(() {
                                      if (on) {
                                        chosen.remove(item.key);
                                      } else {
                                        chosen.add(item.key);
                                      }
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        10,
                                        10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: on
                                            ? const Color(0xFFE9F4F1)
                                            : const Color(0xFFF7FAF9),
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                        border: Border.all(
                                          color: on
                                              ? const Color(0xFF0E7161)
                                              : const Color(0xFFE4EAE8),
                                          width: on ? 1.4 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                            child: Icon(
                                              item.kind == 'unit'
                                                  ? Icons.meeting_room_outlined
                                                  : icon,
                                              size: 20,
                                              color: const Color(0xFF0E7161),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                                  item.label,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    color: Color(0xFF1C2C29),
                                                  ),
                                                )),
                                                if (item.subtitle.isNotEmpty)
                                                  FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                                    item.subtitle,
                                                    maxLines: 1,
                                                    style: const TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(
                                                        0xFF76837F,
                                                      ),
                                                    ),
                                                  )),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            on
                                                ? Icons.check_circle_rounded
                                                : Icons
                                                      .radio_button_unchecked_rounded,
                                            color: on
                                                ? const Color(0xFF0E7161)
                                                : const Color(0xFFB4BFBC),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                <DelegationTarget>{},
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0E7161),
                                minimumSize: const Size.fromHeight(46),
                                side: const BorderSide(
                                  color: Color(0xFFB9DFD6),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                                '${AppTr.tr('كل')} ${AppTr.tr(plural)}',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              )),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: chosen.isEmpty
                                  ? null
                                  : () => Navigator.pop(sheetContext, {
                                      for (final t in items)
                                        if (chosen.contains(t.key)) t,
                                    }),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0E7161),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                '${AppTr.tr('تأكيد')} (${chosen.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDelegations();

    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('التفويضات', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: AppTr.uiDir,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // شريط خطأ صريح بدل قائمة فارغة يظنّها المستخدم "لا توجد بيانات".
            if (_loadError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF4F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF4C2BC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFA82F26),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA82F26),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ],
            Container(
              key: const ValueKey('delegations-overview'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD5DEDB)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E7161),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'من يمكنه إدارة أعمالك؟',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF04413B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'المفوَّض ونطاقه وصلاحياته ومدته.',
                          maxLines: 3,
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF5C6B68),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_delegations.length} تفويضات مسجلة',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0E7161),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('create-delegation'),
              onPressed: _openCreateSheet,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0E7161),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'إنشاء تفويض جديد',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            // خياران واضحان: التفويضات التي منحتُها، والتفويضات التي
            // مُنحت لي — كل زر يعرض عدده ويبدّل القائمة أدناه فعليًا.
            Row(
              children: [
                Expanded(
                  child: _DelegationDirectionButton(
                    key: const ValueKey('delegation-direction-granted'),
                    label: 'فوّضتُ أشخاصًا',
                    icon: Icons.person_add_alt_1_outlined,
                    count: _delegations.where((d) => !d.isReceived).length,
                    selected: _direction == 'granted',
                    onTap: () => setState(() {
                      _direction = 'granted';
                      _selectedFilter = 'all';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DelegationDirectionButton(
                    key: const ValueKey('delegation-direction-received'),
                    label: 'أشخاص فوّضوني',
                    icon: Icons.how_to_reg_outlined,
                    count: _delegations.where((d) => d.isReceived).length,
                    selected: _direction == 'received',
                    onTap: () => setState(() {
                      _direction = 'received';
                      _selectedFilter = 'all';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // "التفويضات المسجلة" صار زرًا في منتصف الصفحة بأسلوب زر الفرز
            // في بقية الشاشات: الضغط عليه يفتح فلاتر الحالة الخمسة.
            InkWell(
              key: const ValueKey('delegations-status-filter-button'),
              onTap: () {
                HapticFeedback.selectionClick();
                _openStatusFilterMenu();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text(
                      'التفويضات المسجلة',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1C2C29),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${_statusFilterLabel()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E7161),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: Color(0xFF0E7161),
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF76837F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const _DelegationsEmptyState()
            else
              ...filtered.asMap().entries.map((entry) {
                final item = entry.value;
                final sourceIndex = _delegations.indexOf(item);
                final status = _statusOf(item);
                // تفويض وصلني: يظهر باسم من فوّضني.
                final owner = DelegationRecord.ownerNameOf(item.permissions);
                return _DelegationCard(
                  key: ValueKey('delegation-${item.id ?? item.delegateName}'),
                  record: item.isIncoming && owner.isNotEmpty
                      ? item.copyWith(delegateName: owner)
                      : item,
                  statusLabel: status.label,
                  statusColor: status.color,
                  statusIcon: status.icon,
                  periodSummary: _periodSummary(item),
                  formattedPeriod:
                      '${_formatDate(item.startDate)} - ${_formatDate(item.endDate)}',
                  incoming: item.isIncoming,
                  onTap: item.isIncoming
                      ? () => showIncomingDelegation(
                          context,
                          item.source!,
                          onChanged: _load,
                        )
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                _DelegationDetailsPage(record: item),
                          ),
                        ),
                  onAction: (action) async {
                    // تفويض وصلني من حساب آخر: الاطلاع والرد فقط.
                    if (item.isIncoming) {
                      await showIncomingDelegation(
                        context,
                        item.source!,
                        onChanged: _load,
                      );
                      return;
                    }
                    if (action == 'view') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _DelegationDetailsPage(record: item),
                        ),
                      );
                      return;
                    }
                    if (action == 'edit') {
                      _openCreateSheet(existing: item, index: sourceIndex);
                      return;
                    }
                    if (action == 'revoke') {
                      // إلغاء فوري: ينتهي أمس (فيُعدّ منتهيًا من الآن، لأن
                      // يوم النهاية نفسه ساري)، ويبقى في «المنتهية» مع سجله.
                      final yesterday = DateUtils.dateOnly(
                        DateTime.now(),
                      ).subtract(const Duration(days: 1));
                      await _persist(
                        item.copyWith(
                          active: true,
                          startDate: item.startDate.isAfter(yesterday)
                              ? yesterday
                              : null,
                          endDate: yesterday,
                          permissions: DelegationRecord.withLog(
                            item.permissions,
                            'إلغاء فوري للتفويض',
                          ),
                        ),
                        notice: 'تم إلغاء التفويض فورًا',
                      );
                      return;
                    }
                    if (action == 'extend') {
                      final today = DateUtils.dateOnly(DateTime.now());
                      final base = item.endDate.isAfter(today)
                          ? item.endDate
                          : today;
                      final newEnd = base.add(const Duration(days: 30));
                      await _persist(
                        item.copyWith(
                          endDate: newEnd,
                          permissions: DelegationRecord.withLog(
                            item.permissions,
                            'تمديد التفويض حتى ${_formatDate(newEnd)}',
                          ),
                        ),
                        notice: 'تم تمديد التفويض شهرًا',
                      );
                      return;
                    }
                    if (action == 'toggle') {
                      await _persist(
                        item.copyWith(
                          active: !item.active,
                          permissions: DelegationRecord.withLog(
                            item.permissions,
                            item.active
                                ? 'إيقاف التفويض مؤقتًا'
                                : 'إعادة تفعيل التفويض',
                          ),
                        ),
                        notice: item.active
                            ? 'تم إيقاف التفويض'
                            : 'تم تفعيل التفويض',
                      );
                      return;
                    }
                    if (action == 'delete') {
                      final id = item.id;
                      if (id == null) return;
                      try {
                        await _repository.deleteDelegation(id);
                        await _load();
                        _notify('تم حذف التفويض بنجاح');
                      } catch (_) {
                        _notify('تعذّر حذف التفويض');
                      }
                    }
                  },
                );
              }),
          ],
        ),
        ),
      ),
    );
  }
}

class _DelegationRecord {
  const _DelegationRecord({
    this.id,
    this.source,
    this.delegateRef,
    required this.delegateName,
    required this.delegationType,
    required this.permissions,
    required this.startDate,
    required this.endDate,
    required this.active,
    this.notes,
  });

  /// معرّف السجل في قاعدة البيانات — بدونه لا يمكن تعديل أو حذف التفويض
  /// فعليًا، وكان غيابه سبب بقاء كل شيء في الذاكرة فقط.
  final String? id;

  /// مرجع الشخص/الجهة في إدارة الأفراد. كان يُمحى من قاعدة البيانات عند كل
  /// تعديل أو إيقاف لأنه لم يكن يُنقل ذهابًا وإيابًا.
  ///
  /// يحمل أيضًا اتجاه التفويض ببادئة [receivedMarker]: تفويض وارد إليّ
  /// مقابل تفويض منحتُه أنا. خُزِّن هنا لأنه لا يحتاج عمودًا جديدًا في
  /// قاعدة البيانات، فيعمل فورًا دون ترحيل يدوي.
  final String? delegateRef;

  /// بادئة تُميّز التفويضات الواردة إليّ داخل [delegateRef].
  static const receivedMarker = 'dir:received';

  /// السجل كما جاء من قاعدة البيانات (لتفويض وصلني من حساب آخر).
  final DelegationRecord? source;

  /// تفويض وصلني من حساب آخر بالرقم التعريفي.
  bool get isIncoming => source?.isIncoming ?? false;

  bool get isReceived =>
      isIncoming || (delegateRef ?? '').startsWith(receivedMarker);
  final String delegateName;
  final String delegationType;
  final List<String> permissions;
  final DateTime startDate;
  final DateTime endDate;
  final bool active;
  final String? notes;

  /// تحويل من/إلى سجل قاعدة البيانات.
  factory _DelegationRecord.fromRecord(DelegationRecord r) => _DelegationRecord(
    id: r.id,
    source: r,
    delegateRef: r.delegateRef,
    delegateName: r.delegateName,
    delegationType: r.scope,
    permissions: r.permissions,
    startDate: r.startDate ?? DateTime.now(),
    endDate: r.endDate ?? DateTime.now().add(const Duration(days: 365)),
    active: !r.isPaused,
    notes: r.notes,
  );

  DelegationRecord toRecord() => DelegationRecord(
    id: id,
    delegateRef: delegateRef,
    delegateName: delegateName,
    scope: delegationType,
    permissions: permissions,
    startDate: startDate,
    endDate: endDate,
    isPaused: !active,
    notes: notes,
  );

  _DelegationRecord copyWith({
    String? id,
    String? delegateRef,
    String? delegateName,
    String? delegationType,
    List<String>? permissions,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
    String? notes,
  }) {
    return _DelegationRecord(
      id: id ?? this.id,
      source: source,
      delegateRef: delegateRef ?? this.delegateRef,
      delegateName: delegateName ?? this.delegateName,
      delegationType: delegationType ?? this.delegationType,
      permissions: permissions ?? this.permissions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      active: active ?? this.active,
      notes: notes ?? this.notes,
    );
  }
}

/// النطاق مع عدد العناصر المحددة: «الالتزامات الشخصية — عهدة مالية • 2».
String _delegationScopeLabel(_DelegationRecord record) {
  final count = DelegationRecord.targetCountOf(record.permissions);
  if (count == 0) return record.delegationType;
  return '${record.delegationType} • $count ${AppTr.tr('عنصر محدد')}';
}

/// في تفاصيل التفويض: العناصر المحددة، وسقف المبلغ، والغرض.
List<Widget> _delegationExtraDetails(_DelegationRecord record) {
  final targets = [
    for (final p in record.permissions)
      if (DelegationTarget.decode(p) case final target?) target,
  ];
  final limit = DelegationRecord.limitOf(record.permissions);
  final notes = (record.notes ?? '').trim();
  final log = DelegationRecord.logOf(record.permissions);
  String two(int v) => v.toString().padLeft(2, '0');
  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: Color(0xFF022E2A),
      ),
    ),
  );
  Widget line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF34A894)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C3B38),
            ),
          ),
        ),
      ],
    ),
  );
  return [
    if (targets.isNotEmpty) ...[
      title('العناصر المحددة'),
      for (final target in targets)
        line(Icons.push_pin_outlined, '${target.label} — ${target.sub}'),
    ],
    if (limit != null) ...[
      title('سقف المبلغ للعملية الواحدة'),
      line(
        Icons.payments_outlined,
        AppSettings.maskAmount('$limit ${AppSettings.currencySuffix}'),
      ),
    ],
    if (notes.isNotEmpty) ...[
      title('الغرض من التفويض'),
      line(Icons.notes_rounded, notes),
    ],
    title('سجل التفويض'),
    if (log.isEmpty)
      line(Icons.history_rounded, 'لا توجد أحداث مسجلة بعد')
    else
      // أحداث المفوَّض يكتبها الخادم بتوقيت UTC: تُعرض بالتوقيت المحلي.
      for (final (stamp, what) in log)
        if (stamp.toLocal() case final at)
          line(
            Icons.history_rounded,
            '${AppTr.tr(what)} — ${two(at.day)}/${two(at.month)}/'
            '${at.year} ${two(at.hour)}:${two(at.minute)}',
          ),
  ];
}

class _DelegationCard extends StatelessWidget {
  const _DelegationCard({
    super.key,
    required this.record,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.periodSummary,
    required this.formattedPeriod,
    required this.onTap,
    required this.onAction,
    this.incoming = false,
  });

  /// تفويض وصلني: الاطلاع فقط — التعديل والإيقاف والتمديد والإنهاء لمن
  /// فوّضني وحده.
  final bool incoming;

  final _DelegationRecord record;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;
  final String periodSummary;
  final String formattedPeriod;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F6F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF0E7161),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // الاسم والحالة في سطر واحد.
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  record.delegateName,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1C2C29),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      statusIcon,
                                      size: 13,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _delegationScopeLabel(record),
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF76837F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: AppTr.tr('خيارات التفويض'),
                      onSelected: (action) => _confirmAndRun(context, action),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('عرض التفاصيل'),
                        ),
                        // ما عدا العرض لمن فوّض وحده.
                        if (!incoming) ...[
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('تعديل التفويض'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(
                              record.active ? 'إيقاف مؤقت' : 'إعادة التفعيل',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'extend',
                            child: Text('تمديد شهر'),
                          ),
                          // واحد منهما فقط: الساري يُنهى (ويبقى سجله في
                          // «المنتهية»)، والمنتهي يُحذف.
                          if (statusLabel != 'منتهي')
                            const PopupMenuItem(
                              value: 'revoke',
                              child: Text('إلغاء فوري'),
                            )
                          else
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف التفويض'),
                            ),
                        ],
                      ],
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Color(0xFF8C9A97),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                // ١. العناصر والفئات المفوَّض بها.
                _delegationBlock(
                  Icons.push_pin_outlined,
                  'العناصر والفئات المفوَّض بها:',
                  _delegationItemsOf(record),
                ),
                const SizedBox(height: 8),
                // ٢. مدة التفويض: من، إلى، الباقي.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceInner,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: Color(0xFF5C6B68),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'مدة التفويض:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1C2C29),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            periodSummary,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${AppTr.tr('من')} ${formattedPeriod.split(' - ').first}'
                        '   ${AppTr.tr('إلى')} ${formattedPeriod.split(' - ').last}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF46534F),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ٣. الصلاحيات: سطر بسهم يفتح نافذة فيها كلها.
                InkWell(
                  onTap: () => _showPermissions(
                    context,
                    DelegationRecord.plainPermissions(record.permissions),
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceInner,
                      borderRadius: BorderRadius.circular(AppTheme.rInner),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.key_outlined,
                          size: 16,
                          color: Color(0xFF76837F),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${AppTr.tr('الصلاحيات')} '
                            '(${DelegationRecord.plainPermissions(record.permissions).length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1C2C29),
                            ),
                          ),
                        ),
                        const AppChevron(size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// نافذة الصلاحيات مرقّمة، وعلامة × لإغلاقها.
  Future<void> _showPermissions(BuildContext context, List<String> items) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: Dialog(
          backgroundColor: AppTheme.page,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'الصلاحيات',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1C2C29),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppTr.tr('إغلاق'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (items.isEmpty)
                  const Text('—')
                else
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: 10,
                        top: 5,
                      ),
                      child: Text(
                        '${i + 1}. ${AppTr.tr(items[i])}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF46534F),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// عنوان وتحته عناصر مرقّمة: ١. ٢. ٣.
  Widget _delegationBlock(IconData icon, String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF76837F)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1C2C29),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 22),
            child: Text(
              '—',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF5C6B68)),
            ),
          )
        else
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 22, top: 2),
              child: Text(
                '${i + 1}. ${AppTr.tr(items[i])}',
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF46534F),
                ),
              ),
            ),
      ],
    );
  }

  /// ما فُوِّض به: العناصر المحددة، وإلا الفئات، وإلا القسم كاملًا.
  static List<String> _delegationItemsOf(_DelegationRecord record) {
    final targets = [
      for (final p in record.permissions)
        if (DelegationTarget.decode(p) case final target?) target,
    ];
    if (targets.isNotEmpty) {
      return [for (final t in targets) '${t.label} (${t.sub})'];
    }
    final parts = record.delegationType.split(' — ');
    final subs = parts.length > 1
        ? [
            for (final s in parts[1].split('،'))
              if (s.trim().isNotEmpty) s.trim(),
          ]
        : const <String>[];
    return subs.isNotEmpty ? subs : [parts.first.trim()];
  }

  /// تأكيد قبل أي إجراء على التفويض ثم تنفيذه.
  Future<void> _confirmAndRun(BuildContext context, String action) async {
    final danger = action == 'delete' || action == 'revoke';
    final ok = await confirmAction(
      context,
      title: switch (action) {
        'view' => 'عرض التفاصيل',
        'edit' => 'تعديل التفويض',
        'toggle' => record.active
            ? 'إيقاف التفويض مؤقتًا'
            : 'إعادة تفعيل التفويض',
        'extend' => 'تمديد التفويض شهرًا',
        'revoke' => 'إلغاء التفويض فورًا',
        _ => 'حذف التفويض',
      },
      message: switch (action) {
        'delete' => 'سيُحذف التفويض نهائيًا ولا يمكن التراجع. هل تريد الحذف؟',
        'revoke' =>
          'سينتهي تفويض «${record.delegateName}» اليوم ويُنقل إلى المنتهية '
              'مع بقاء سجله. هل تريد الإلغاء؟',
        'extend' => 'ستُضاف 30 يومًا إلى تاريخ نهاية التفويض.',
        _ => 'هل تريد تنفيذ هذا الإجراء على التفويض؟',
      },
      confirmLabel: switch (action) {
        'delete' => 'حذف',
        'revoke' => 'إلغاء التفويض',
        _ => 'تأكيد',
      },
      danger: danger,
    );
    if (!ok || !context.mounted) return;
    onAction(action);
  }
}

class _DelegationsEmptyState extends StatelessWidget {
  const _DelegationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.manage_accounts_outlined,
            size: 32,
            color: Color(0xFF8C9A97),
          ),
          SizedBox(height: 9),
          Text(
            'لا توجد تفويضات ضمن هذه الحالة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2C3B38),
            ),
          ),
          SizedBox(height: 3),
          Text(
            'اختر حالة أخرى أو أنشئ تفويضًا جديدًا.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF76837F)),
          ),
        ],
      ),
    );
  }
}

/// زر اتجاه التفويض (فوّضتُ / فوّضوني) — يعرض العدد ويبدّل القائمة.
class _DelegationDirectionButton extends StatelessWidget {
  const _DelegationDirectionButton({
    super.key,
    required this.label,
    required this.icon,
    this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// null = بلا شارة عدد (داخل نافذة الإنشاء لا معنى للعدد).
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0E7161);
    return Material(
      color: selected ? accent : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rField),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE4EAE8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : accent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF1C2C29),
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFFF2F6F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateFieldTile extends StatelessWidget {
  const _DateFieldTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3B38),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.rField),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.field,
              borderRadius: BorderRadius.circular(AppTheme.rField),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DelegationDetailsPage extends StatelessWidget {
  const _DelegationDetailsPage({required this.record});

  final _DelegationRecord record;

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ended = record.endDate.isBefore(now);
    final scheduled = record.active && record.startDate.isAfter(now);
    final expiring =
        record.active && !ended && record.endDate.difference(now).inDays <= 30;
    final status = ended
        ? (
            label: 'منتهي',
            color: const Color(0xFF5C6B68),
            icon: Icons.event_busy_outlined,
          )
        : !record.active
        ? (
            label: 'موقوف',
            color: const Color(0xFFC4392E),
            icon: Icons.pause_circle_outline_rounded,
          )
        : scheduled
        ? (
            label: 'مجدول',
            color: const Color(0xFF0A5A50),
            icon: Icons.schedule_rounded,
          )
        : expiring
        ? (
            label: 'ينتهي قريبًا',
            color: const Color(0xFFCE8422),
            icon: Icons.timer_outlined,
          )
        : (
            label: 'نشط',
            color: const Color(0xFF178F7B),
            icon: Icons.check_circle_outline_rounded,
          );
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('تفاصيل التفويض', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD5DEDB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB9DFD6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: Color(0xFF0E7161),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          record.delegateName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF022E2A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'نطاق التفويض: ${record.delegationType}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5C6B68),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(status.icon, size: 14, color: status.color),
                        const SizedBox(width: 4),
                        Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: status.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'فترة التفويض',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DelegationDetailValue(
                          label: 'يبدأ في',
                          value: _formatDate(record.startDate),
                          icon: Icons.play_circle_outline_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DelegationDetailValue(
                          label: 'ينتهي في',
                          value: _formatDate(record.endDate),
                          icon: Icons.event_busy_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الصلاحيات',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...DelegationRecord.plainPermissions(record.permissions).map(
                    (permission) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: Color(0xFF34A894),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              permission,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C3B38),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ..._delegationExtraDetails(record),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DelegationDetailValue extends StatelessWidget {
  const _DelegationDetailValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sMd),
      // بطاقة داخلية بيضاء داخل البطاقة الرمادية.
      decoration: BoxDecoration(
        color: AppTheme.surfaceInner,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF76837F)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF76837F)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2C3B38),
            ),
          ),
        ],
      ),
    );
  }
}
