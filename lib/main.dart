import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, Align;
import 'l10n/tr_widgets.dart';
import 'l10n/app_language.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'data/app_settings.dart';
import 'data/home_dashboard_service.dart';
import 'data/home_summary_service.dart';
import 'data/read_notifications_store.dart';
import 'data/home_pin_items_service.dart';
import 'data/home_pinned_shortcuts_store.dart';
import 'data/delegations_repository.dart';
import 'data/wallets_repository.dart';
import 'l10n/home_strings.dart';
import 'screens/app_lock_screen.dart';
import 'screens/data_status_screen.dart';
import 'screens/notifications_center_screen.dart';
import 'screens/document_templates_screen.dart';
import 'screens/people_management_screen.dart';
import 'screens/personal_commitments_screen.dart';
import 'screens/profile_settings_screen.dart';
import 'screens/settings_detail_screens.dart';
import 'screens/projects_activities_screen.dart';
import 'screens/raffle_screen.dart';
import 'screens/shared_commitments_screen.dart';
import 'screens/smart_calendar_screen.dart';
import 'widgets/shared/app_design.dart';
import 'widgets/shared/app_filter_sheet.dart';
import 'widgets/shared/scope_builder_sheet.dart';
import 'widgets/shared/search_matching.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  // تُحمَّل الإعدادات قبل بناء الواجهة، فيبدأ التطبيق بحجم النص والعملة
  // وحالة القفل الصحيحة من أول إطار بلا ومضة قيم افتراضية.
  await AppSettings.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: AppSettings.instance.textScale,
          maxScaleFactor: AppSettings.instance.textScale,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AppLockGate(child: HomePage()),
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
    final due = _metrics.calendarItems.where((item) {
      if (!settings.expiryNotifications && item.isExpiry) return false;
      final dueDate = DateUtils.dateOnly(item.date);
      final lead = item.remindBeforeDays >= 0
          ? item.remindBeforeDays
          : settings.leadTimeDays;
      final from = dueDate.subtract(Duration(days: lead));
      return !now.isBefore(from) && !now.isAfter(dueDate);
    });
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
    // قراءة تنبيه في مركز التنبيهات تُطفئ النقطة الحمراء فورًا.
    ReadNotificationsStore.instance.addListener(_onSettingsChanged);
    ReadNotificationsStore.instance.load();
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
      // العرض الافتراضي: أربعة مستطيلات تحت بعضها. عرض المربعين جنبًا
      // إلى جنب يبقى خيارًا يختاره المستخدم من زر التبديل ويُحفظ.
      _showCategoriesInTwoColumns = persistedLayout ?? false;
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

  Future<void> _removePinnedShortcut(String shortcutId) async {
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
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

  /// شريط فشل التحميل: يظهر فقط حين يفشل جلب الأرقام فعلًا، ويفتح شاشة
  /// "حالة البيانات والاتصال" التي تفصل بين عطل الجلسة وعطل الشبكة وغياب
  /// السجلات.
  Widget _buildMetricsErrorBanner() {
    return Material(
      color: AppTheme.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppTheme.rField),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-metrics-error-banner'),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DataStatusScreen()),
          );
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
                  'محدَّثة. اضغط لمعرفة السبب.',
                  style: TextStyle(
                    fontSize: 12.5,
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
  static const _panelSurface = Color(0xFFF7F6F5);
  static const _panelInner = Color(0xFFFAFAFA);
  static const _panelBorder = Color(0xFFEEEEEE);
  // ألوان البطاقة المميّزة من نسق التطبيق نفسه (الأخضر المزرقّ) بدل
  // البنفسجي الغريب عن بقية الشاشات.
  static const _summaryAccentTop = AppTheme.accent;
  static const _summaryAccentBottom = AppTheme.accentDark;
  static const _rPanel = 22.0;
  static const _rInnerPanel = 18.0;

  /// لوحة الملخص الشامل: صندوق واحد كبير يضم عمودين — يمينًا البطاقة
  /// البنفسجية المميّزة، ويسارًا صندوق تثبيت الفئات يعلو صفّ اختصارات
  /// الأقسام. كل عنصر هنا يفتح شاشة حقيقية: البطاقة تفتح الملخص الشامل،
  /// الصندوق يفتح نافذة التثبيت، وكل بطاقة صغيرة تفتح قسمها.
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
        child: SizedBox(
          height: 112,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // البطاقة المميّزة أقصى اليمين (الاتجاه هنا RTL).
              // أنحف من قبل: بعرض يقارب عرض الجملة داخله.
              Expanded(flex: 27, child: _buildFeaturedSummaryCard()),
              const SizedBox(width: 8),
              Expanded(
                flex: 73,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // الصندوق أنحف من قبل: ارتفاع ثابت صغير بدل ملء
                    // المساحة، والباقي لصفّ الاختصارات.
                    SizedBox(height: 38, child: _buildPinnedBox()),
                    const SizedBox(height: 8),
                    Expanded(child: Center(child: _buildQuickModulesRow())),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// البطاقة البنفسجية المميّزة — تفتح شيت الملخص الشامل.
  Widget _buildFeaturedSummaryCard() {
    return _PressableScale(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_rInnerPanel),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_rInnerPanel),
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
                color: Color(0x332C6B69),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: InkWell(
            key: const ValueKey('home-summary-open'),
            onTap: () {
              HapticFeedback.selectionClick();
              _openGlobalSummarySheet();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _SummaryFolderStarIcon(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ملخص شامل',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        HomeStrings.summarySubtitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  // زر دائري أبيض بسهم لليسار كما في النموذج.
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x2E000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    // السهم معكوس الاتجاه (نحو اليمين) كما طُلب.
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: AppTheme.accentDark,
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

  /// صندوق الفئات المثبتة. فارغًا: نصّ إرشادي وضغطة تفتح نافذة التثبيت.
  /// ممتلئًا: شريط أفقي بالعناصر المثبتة مع زر لإدارتها.
  Widget _buildPinnedBox() {
    final isEmpty = _pinnedShortcuts.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: _panelInner,
        borderRadius: BorderRadius.circular(_rInnerPanel),
        border: Border.all(color: _panelBorder),
      ),
      padding: const EdgeInsets.all(6),
      child: isEmpty
          // صفّ واحد نحيف: زر التثبيت أقصى اليمين والنصّ الإرشادي بجانبه.
          ? InkWell(
              key: const ValueKey('home-pin-empty'),
              borderRadius: BorderRadius.circular(_rInnerPanel),
              onTap: () {
                HapticFeedback.selectionClick();
                _openPinPicker();
              },
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.push_pin_outlined,
                      size: 12,
                      color: AppTheme.accentDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      HomeStrings.pinHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.emptyText.copyWith(
                        fontSize: 9,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            )
          // الصندوق نحيف (30 بكسل داخليًا)، فالبطاقة المثبتة هنا شريحة
          // مضغوطة بدل بطاقة كاملة، وزر الإدارة بحجم يناسب الارتفاع.
          : Row(
              children: [
                AppIconButton(
                  key: const ValueKey('home-pin-picker'),
                  icon: Icons.push_pin_outlined,
                  tooltip: AppTr.tr('إدارة العناصر المثبتة'),
                  size: 24,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _openPinPicker();
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  // بلا reverse: العناصر المثبتة تبدأ من اليمين كبقية
                  // الأشرطة في التطبيق.
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: _pinnedShortcuts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final shortcut = _pinnedShortcuts[index];
                      return _HomePinnedChip(
                        key: ValueKey('home-pinned-${shortcut.id}'),
                        shortcut: shortcut,
                        onOpen: () => _openShortcut(shortcut),
                        onRemove: () => _removePinnedShortcut(shortcut.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  /// صفّ اختصارات الأقسام الخمسة أسفل صندوق التثبيت. كل بطاقة تفتح
  /// شاشتها الحقيقية (والعقارات/الأنشطة تفتحان شاشة الأصول على الفئة
  /// الموافقة، والمالية تنقل إلى تبويب المحافظ).
  Widget _buildQuickModulesRow() {
    final tiles = <Widget>[
      _HomeQuickTile(
        key: const ValueKey('home-quick-real-estate'),
        label: 'العقارات',
        icon: Icons.home_rounded,
        color: const Color(0xFF3F51B5),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const ProjectsActivitiesScreen(initialFilter: 'real_estate'),
          ),
        ),
      ),
      _HomeQuickTile(
        key: const ValueKey('home-quick-activities'),
        label: 'الأنشطة',
        icon: Icons.work_rounded,
        color: const Color(0xFF4CAF50),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const ProjectsActivitiesScreen(initialFilter: 'activity'),
          ),
        ),
      ),
      _HomeQuickTile(
        key: const ValueKey('home-quick-people'),
        label: 'الأشخاص',
        icon: Icons.groups_rounded,
        color: const Color(0xFFF5A623),
        onTap: () => _openPriorityScreen('إدارة الأشخاص والجهات'),
      ),
      _HomeQuickTile(
        key: const ValueKey('home-quick-commitments'),
        label: 'الالتزامات',
        icon: Icons.description_rounded,
        color: const Color(0xFF673AB7),
        onTap: () => _openPriorityScreen(HomeStrings.modulePersonal),
      ),
      _HomeQuickTile(
        key: const ValueKey('home-quick-finance'),
        label: 'المالية',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFE91E63),
        onTap: () => setState(() => _selectedIndex = 2),
      ),
    ];
    // قابل للتمرير أفقيًا: خمس بطاقات لا تتسع لعرض الهاتف الضيق، فبدل
    // ضغطها حتى يختفي النص تنزلق البطاقات.
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => tiles[index],
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
                    bottom: BorderSide(color: Color(0xFFE1E8F0)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
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

  String _formatArabicNumber(int value) {
    // بالإنجليزية تُعرض الأرقام الغربية كما هي.
    if (AppTr.isEnglish) return value.toString();
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var output = value.toString();
    for (var i = 0; i < western.length; i++) {
      output = output.replaceAll(western[i], arabic[i]);
    }
    return output;
  }

  /// المبالغ تُخفى عند تفعيل "إخفاء المبالغ الحساسة" في الإعدادات — كان
  /// ذلك الإعداد يُحفظ ولا يؤثر في شيء.
  String _formatAmount(int value) =>
      AppSettings.maskAmount(_formatArabicNumber(value));

  String _formatCountWithUnit(int value, String unit) {
    return '${_formatArabicNumber(value)} $unit';
  }

  /// فلتر الصفحة الرئيسية بنفس قالب الفلاتر في الشاشات الأربع، لكن
  /// بالأقسام المنطقية لمحتوى هذه الصفحة فقط: بطاقات الأقسام لا تحمل
  /// تاريخًا ولا مبلغًا ولا حالة، فالقسم هو الفلتر الحقيقي الوحيد — وأي
  /// قسم آخر هنا سيكون حقلًا لا يؤثر في شيء.
  void _openHomeFilterSheet() {
    showAppFilterSheet(
      context: context,
      title: 'الصفحة الرئيسية',
      accent: AppTheme.accent,
      values: _homeFilter..mainCategory = _selectedHomeFilter,
      mainCategories: const [
        HomeStrings.filterAll,
        HomeStrings.filterPersonal,
        HomeStrings.filterShared,
        HomeStrings.filterPeople,
        HomeStrings.filterAssets,
      ],
      sections: const [AppFilterSection.mainCategory],
      onApply: (values) => setState(() {
        _selectedHomeFilter = values.mainCategory;
        _homeFilter.mainCategory = values.mainCategory;
      }),
    );
  }

  Future<void> _openPinPicker() async {
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
                    color: Color(0x260F172A),
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
                            color: Color(0xFFEAF6F3),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFD8EAE6)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF087F6A),
                                  borderRadius: BorderRadius.circular(13),
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
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF173B35),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'اختر الوحدة وثبّت العناصر التي تحتاجها سريعًا',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF52716B),
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
                                  foregroundColor: const Color(0xFF52716B),
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
                            labelColor: Color(0xFF087F6A),
                            unselectedLabelColor: Color(0xFF718096),
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                            unselectedLabelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: Color(0xFFE5F3EF),
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                              border: Border.fromBorderSide(
                                BorderSide(color: Color(0xFFC6E4DC)),
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
                                text: 'العقارات والأنشطة',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      body: _selectedIndex == 0
          ? RefreshIndicator(
              onRefresh: _refreshHomeMetrics,
              color: const Color(0xFF0F6AA8),
              child: CustomScrollView(
                controller: _homeScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 88,
                    toolbarHeight: 88,
                    floating: false,
                    pinned: true,
                    backgroundColor: AppTheme.page,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        // ترويسة بيضاء نظيفة بدل تدرّج أزرق؛ العناصر
                        // فوقها تأخذ ألوان النظام الموحّد نفسه.
                        decoration: const BoxDecoration(color: AppTheme.page),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 7),
                            child: Directionality(
                              textDirection: AppTr.uiDir,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Material(
                                        color: Colors.transparent,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          key: const ValueKey(
                                            'home-account-avatar-entry',
                                          ),
                                          onTap: _openAccountPage,
                                          customBorder: const CircleBorder(),
                                          child: Container(
                                            width: 34,
                                            height: 34,
                                            clipBehavior: Clip.antiAlias,
                                            decoration: const BoxDecoration(
                                              color: AppTheme.field,
                                              shape: BoxShape.circle,
                                            ),
                                            // الصورة الشخصية المحفوظة فعليًا
                                            // بدل أيقونة ثابتة لا تتغير.
                                            child: _profilePhoto == null
                                                ? const Icon(
                                                    Icons.person_rounded,
                                                    size: 20,
                                                    color: AppTheme.chevron,
                                                  )
                                                : Image.memory(
                                                    _profilePhoto!,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              key: const ValueKey(
                                                'home-account-entry',
                                              ),
                                              onTap: _openAccountPage,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                // الاسم المحفوظ في البيانات
                                                // الشخصية، لا نص ثابت.
                                                child: Text(
                                                  AppSettings.instance.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppTheme.title,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // أزرار الترويسة بمقاس ونصف قطر
                                      // ولون موحّد مع بقية أزرار التطبيق
                                      // بدل ثلاثة أشكال مختلفة بحدود ملوّنة.
                                      AppIconButton(
                                        tooltip: AppTr.tr('التقويم الذكي'),
                                        icon: Icons.calendar_month_rounded,
                                        background: AppTheme.field,
                                        color: const Color(0xFF2E7D62),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SmartCalendarScreen(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppTheme.sSm),
                                      AppIconButton(
                                        tooltip: AppTr.tr('الإشعارات'),
                                        icon: _alertsCount > 0
                                            ? Icons.notifications_active_rounded
                                            : Icons.notifications_none_rounded,
                                        background: AppTheme.field,
                                        color: const Color(0xFFB4741A),
                                        // النقطة الحمراء كانت مضاءة دائمًا
                                        // حتى بلا تنبيه واحد؛ الآن تعكس
                                        // عدد الاستحقاقات القريبة فعلًا.
                                        badge: _alertsCount > 0,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NotificationsCenterScreen(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppTheme.sSm),
                                      AppIconButton(
                                        tooltip: HomeStrings.raffle,
                                        icon: Icons.casino_outlined,
                                        background: AppTheme.field,
                                        color: const Color(0xFF6D5BC4),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RaffleScreen(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    key: ValueKey('home-header-tagline'),
                                    HomeStrings.homeTagline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  _homeHorizontalInset,
                                  0,
                                  _homeHorizontalInset,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    // حقل بحث ممتلئ بلا حدود ولا ظل، بنفس
                                    // نصف قطر ولون حقول التطبيق الموحّدة.
                                    Expanded(
                                      child: SizedBox(
                                        height: 52,
                                        child: TextField(
                                          controller: _searchController,
                                          textDirection: AppTr.uiDir,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.title,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: HomeStrings.searchHint,
                                            hintStyle: const TextStyle(
                                              color: AppTheme.muted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            filled: true,
                                            fillColor: AppTheme.field,
                                            prefixIcon: const Icon(
                                              Icons.search_rounded,
                                              color: AppTheme.chevron,
                                              size: 21,
                                            ),
                                            suffixIcon:
                                                _searchController.text.isEmpty
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
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppTheme.rField,
                                                  ),
                                              borderSide: BorderSide.none,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 15,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppTheme.sSm),
                                    // زر الفلتر: أيقونة موحّدة مع بقية
                                    // الشاشات (بلا كلمة "فلتر")، ونقطة
                                    // برتقالية تظهر متى كان هناك فلتر فعّال.
                                    _PressableScale(
                                      child: Material(
                                        color: AppTheme.accent,
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.rField,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          key: const ValueKey(
                                            'home-filter-button',
                                          ),
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            _openHomeFilterSheet();
                                          },
                                          child: SizedBox(
                                            width: 52,
                                            height: 52,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                const Center(
                                                  child: Icon(
                                                    Icons.tune_rounded,
                                                    color: Colors.white,
                                                    size: 22,
                                                  ),
                                                ),
                                                if (_selectedHomeFilter !=
                                                    HomeStrings.filterAll)
                                                  Positioned(
                                                    top: 10,
                                                    left: 10,
                                                    child: Container(
                                                      width: 9,
                                                      height: 9,
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFF59E0B,
                                                        ),
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
                                    ),
                                  ],
                                ),
                              ),
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
                                  trailing: AppIconButton(
                                    key: const ValueKey(
                                      'home-categories-layout-toggle',
                                    ),
                                    tooltip: _showCategoriesInTwoColumns
                                        ? 'عرض بطاقة واحدة في كل صف'
                                        : 'عرض بطاقتين في كل صف',
                                    icon: _showCategoriesInTwoColumns
                                        ? Icons.grid_view_rounded
                                        : Icons.view_agenda_rounded,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _toggleLayout();
                                    },
                                  ),
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
    if (_selectedIndex == 2) {
      return const _WalletsHubPage();
    }
    return const ProfileSettingsScreen(delegationsPage: _DelegationsHubPage());
  }

  Widget _buildTopCategories() {
    final categories = [
      (
        HomeStrings.modulePersonal,
        Icons.person_outline_rounded,
        const Color(0xFF3B82F6),
        [
          (
            'ديون لك: ${_formatAmount(_metrics.personalDebtsForYou)}',
            Icons.south_west_rounded,
            const Color(0xFF07835C),
          ),
          (
            'ديون عليك: ${_formatAmount(_metrics.personalDebtsOnYou)}',
            Icons.north_east_rounded,
            const Color(0xFFC73E4D),
          ),
          (
            'تحتاج متابعة: ${_formatArabicNumber(_metrics.personalNeedsFollowup)}',
            Icons.task_alt_rounded,
            const Color(0xFF2563B8),
          ),
        ],
      ),
      (
        HomeStrings.moduleShared,
        Icons.groups_2_outlined,
        const Color(0xFF10B981),
        [
          (
            'رحلات نشطة: ${_formatArabicNumber(_metrics.sharedActiveTrips)}',
            Icons.flight_takeoff_rounded,
            const Color(0xFF087F6A),
          ),
          (
            'جمعيات نشطة: ${_formatArabicNumber(_metrics.sharedActiveCircles)}',
            Icons.groups_rounded,
            const Color(0xFF0F766E),
          ),
          (
            'تحتاج متابعة: ${_formatArabicNumber(_metrics.sharedNeedsFollowup)}',
            Icons.warning_amber_rounded,
            const Color(0xFFB56A09),
          ),
        ],
      ),
      (
        'إدارة الأشخاص والجهات',
        Icons.people_alt_outlined,
        const Color(0xFF7956A8),
        [
          (
            'عدد الأفراد: ${_formatArabicNumber(_metrics.peopleCount)}',
            Icons.person_outline_rounded,
            const Color(0xFF6D28D9),
          ),
          (
            'عدد الجهات: ${_formatArabicNumber(_metrics.entitiesCount)}',
            Icons.apartment_outlined,
            const Color(0xFF7C3AED),
          ),
          (
            'تحتاج متابعة: ${_formatArabicNumber(_metrics.peopleNeedsFollowup)}',
            Icons.warning_amber_rounded,
            const Color(0xFFC05A15),
          ),
        ],
      ),
      (
        'العقارات/الأنشطة التجارية/المعدات وأخرى',
        Icons.apartment_rounded,
        const Color(0xFFF59E0B),
        [
          (
            'عدد العقارات: ${_formatArabicNumber(_metrics.assetsCount)}',
            Icons.home_work_outlined,
            const Color(0xFFB45309),
          ),
          (
            'عدد الأنشطة التجارية: ${_formatArabicNumber(_metrics.businessCount)}',
            Icons.storefront_outlined,
            const Color(0xFFB45309),
          ),
          (
            'عدد المعدات: ${_formatArabicNumber(_metrics.equipmentCount)}',
            Icons.construction_outlined,
            const Color(0xFF92400E),
          ),
          (
            'تحتاج متابعة: ${_formatArabicNumber(_metrics.assetsNeedsFollowup)}',
            Icons.event_busy_outlined,
            const Color(0xFFC2415D),
          ),
        ],
      ),
    ];

    final query = _searchController.text.trim();
    final filteredCategories = categories
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
          // ارتفاع محسوب على المحتوى الفعلي:
          //   عمودان: حشوة (24) + ترويسة (36) + فاصل (8) + مقتطفان
          //           (28 + 6 + 28) = 130.
          //   عمود واحد: حشوة (24) + ترويسة (40) + فاصل (8) + شريط (32).
          mainAxisExtent: _showCategoriesInTwoColumns ? 134 : 106,
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
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
            Row(
              children: [
                AppIconTile(
                  icon: icon,
                  color: color,
                  size: compact ? 36 : 40,
                  iconSize: compact ? 18 : 20,
                ),
                const SizedBox(width: AppTheme.sSm),
                Expanded(
                  child: Text(
                    key: ValueKey('home-category-title-$categoryIndex'),
                    title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.title,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.sXs),
                const AppChevron(size: 22),
              ],
            ),
            const SizedBox(height: AppTheme.sSm),
            // في عرض المربعين: مقتطفان تحت بعضهما بعرض المربع كاملًا، بدل
            // شريط أفقي يُخفي ما بعد المقتطف الأول ويتطلّب سحبًا لرؤيته.
            if (compact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var index = 0;
                    index < (items.length < 2 ? items.length : 2);
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: _HomeCategoryMetric(
                        label: items[index].$1,
                        icon: items[index].$2,
                        color: items[index].$3,
                        compact: true,
                      ),
                    ),
                  ],
                ],
              )
            else
              SizedBox(
                height: 32,
                child: items.length > 3
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 7),
                      itemBuilder: (context, index) => SizedBox(
                        width: 152,
                        child: _HomeCategoryMetric(
                          label: items[index].$1,
                          icon: items[index].$2,
                          color: items[index].$3,
                          compact: false,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        for (var index = 0; index < items.length; index++) ...[
                          if (index > 0) const SizedBox(width: 7),
                          Expanded(
                            child: _HomeCategoryMetric(
                              label: items[index].$1,
                              icon: items[index].$2,
                              color: items[index].$3,
                              compact: false,
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.2), width: 1),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.3,
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
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      textDirection: AppTr.uiDir,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                  borderRadius: BorderRadius.circular(10),
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
                colors: [Color(0xFFFEE2E2), Color(0xFFFFF1F2)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color(0xFFFB7185).withOpacity(0.3),
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
                    Icon(Icons.south_east, color: Color(0xFFFB7185), size: 16),
                    Text(
                      'عليك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9F1239),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,000', Color(0xFFBE123C)),
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
                colors: [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color(0xFF10B981).withOpacity(0.35),
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
                    Icon(Icons.north_west, color: Color(0xFF10B981), size: 16),
                    Text(
                      'لك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,500', Color(0xFF047857)),
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
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
          WidgetSpan(child: SizedBox(width: 4)),
          TextSpan(
            text: AppSettings.currencySuffix,
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
                  label: 'المحافظ',
                  icon: Icons.account_balance_wallet_outlined,
                  selectedIcon: Icons.account_balance_wallet_rounded,
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
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected ? AppTheme.accentDark : AppTheme.muted,
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

class _HomeCategoryMetric extends StatelessWidget {
  const _HomeCategoryMetric({
    required this.label,
    required this.icon,
    required this.color,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // بلا صندوق حول المقتطف: أيقونة ونص فقط. الصندوق الأبيض داخل بطاقة
    // رمادية كان يُضاعف الإطارات ويضيّق النص بلا فائدة.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 2 : 3,
        vertical: compact ? 5 : 6,
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Icon(icon, color: color, size: compact ? 14 : 16),
          SizedBox(width: compact ? 5 : 7),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: color,
                    fontFamilyFallback: const [
                      'Cairo',
                      'Noto Kufi Arabic',
                      'Tahoma',
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
}

/// شريحة مضغوطة للعنصر المثبَّت داخل الصندوق النحيف في الصفحة الرئيسية:
/// أيقونة + الاسم + زر إلغاء التثبيت، بارتفاع يناسب 30 بكسل.
/// نمط الوحدة التي ينتمي إليها العنصر المثبَّت (اسم، أيقونة، لون) —
/// مصدر واحد تستخدمه شرائح التثبيت في الصفحة الرئيسية ونافذة الاختيار.
({String label, IconData icon, Color color}) _pinModuleStyle(String moduleId) {
  return switch (moduleId) {
    'personal' => (
      label: 'التزامات شخصية',
      icon: Icons.person_outline_rounded,
      color: const Color(0xFF2563EB),
    ),
    'shared' => (
      label: 'التزامات مشتركة',
      icon: Icons.groups_2_outlined,
      color: const Color(0xFF10B981),
    ),
    'people' => (
      label: 'الأفراد والجهات',
      icon: Icons.badge_outlined,
      color: const Color(0xFF7C3AED),
    ),
    _ => (
      label: 'العقارات والأنشطة',
      icon: Icons.apartment_rounded,
      color: const Color(0xFFEA580C),
    ),
  };
}

class _HomePinnedChip extends StatelessWidget {
  const _HomePinnedChip({
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 2, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 13, color: style.color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  shortcut.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title,
                    height: 1.1,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppTr.tr('إلغاء التثبيت'),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 13,
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

class _PinItemsList extends StatefulWidget {
  const _PinItemsList({
    required this.items,
    required this.isPinned,
    required this.onToggle,
  });

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
                color: Color(0xFF94A3B8),
              ),
              SizedBox(height: 10),
              Text(
                'لا توجد عناصر محفوظة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF334155),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'أضف عنصرًا داخل هذه الوحدة ليظهر هنا',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      );
    }
    final moduleId = widget.items.first.moduleId.isEmpty
        ? widget.items.first.id.split(':').first
        : widget.items.first.moduleId;
    final style = _pinModuleStyle(moduleId);
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
                    color: Color(0xFF334155),
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
                  '${widget.items.length} عناصر',
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
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final pinned = _pinnedIds.contains(item.id);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: pinned
                      ? style.color.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pinned
                        ? style.color.withValues(alpha: 0.42)
                        : const Color(0xFFE5ECEA),
                    width: pinned ? 1.4 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A0F172A),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _toggle(item),
                    borderRadius: BorderRadius.circular(14),
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF17212B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle.isEmpty
                                      ? style.label
                                      : item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF718096),
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
                                    : const Color(0xFFF1F5F4),
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
                                      : const Color(0xFF64748B),
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
            color: Color(0xFF64748B),
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
                  top: Radius.circular(5),
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
                borderRadius: BorderRadius.circular(9),
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
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة اختصار قسم صغيرة أسفل صندوق التثبيت.
class _HomeQuickTile extends StatelessWidget {
  const _HomeQuickTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            width: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.title,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
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

class _ReportsArchiveHubPage extends StatefulWidget {
  const _ReportsArchiveHubPage();

  @override
  State<_ReportsArchiveHubPage> createState() => _ReportsArchiveHubPageState();
}

class _ReportsArchiveHubPageState extends State<_ReportsArchiveHubPage> {
  static const _storageKey = 'reports_archive_records_v1';
  static const _accent = Color(0xFF0F6AA8);

  /// السجلات الحقيقية التي تُبنى منها التقارير والأرشيف والملخصات.
  List<SummaryItem> _items = const [];
  bool _loadingItems = true;

  /// آخر اختيار في كل من نافذتي التقرير والأرشيف — يعود كما تركه المستخدم.
  ScopeSelection? _reportSelection;
  ScopeSelection? _archiveSelection;
  List<_GeneratedReport> _recentReports = [];
  List<_GeneratedReport> _archivedReports = [];





  @override
  void initState() {
    super.initState();
    _restore();
    _loadItems();
  }

  @override
  void dispose() {
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
    return buffer.toString();
  }

  // ===== إجراءات التقارير =====

  /// يفتح قالب الاختيار الموحّد (نفس تسلسل الملخص الشامل) ثم ينشئ منه
  /// تقريرًا أو عنصر أرشيف حقيقيًا.
  Future<void> _openScopeBuilder({required bool archive}) async {
    final kind = archive ? 'الأرشيف' : 'التقرير';
    final selection = await showScopeBuilderSheet(
      context: context,
      kind: kind,
      accent: _accent,
      items: _items,
      initial: archive ? _archiveSelection : _reportSelection,
    );
    if (selection == null || !mounted) return;
    setState(() {
      if (archive) {
        _archiveSelection = selection;
      } else {
        _reportSelection = selection;
      }
    });

    var reason = '';
    if (archive) {
      reason = await _askArchiveReason() ?? '';
      if (!mounted) return;
    }

    final title = selection.title.trim().isEmpty
        ? '$kind ${selection.scope}'
        : selection.title.trim();
    final report = _GeneratedReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      type: selection.scope,
      subject: selection.sections.join('، '),
      mode: archive ? 'أرشيف' : 'تقرير',
      fromDate: selection.from,
      toDate: selection.to,
      dataFields: selection.sections.toList(growable: false),
      createdBy: AppSettings.instance.name,
      createdAt: DateTime.now(),
      selection: selection,
      archivedAt: archive ? DateTime.now() : null,
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
    _toast(archive ? 'تمت إضافة العنصر إلى الأرشيف' : 'تم إنشاء التقرير');
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
    controller.dispose();
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
                style: TextStyle(color: Color(0xFFEF4444)),
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
    // على الأجهزة اللوحية تحتاج قائمة المشاركة موضع انطلاق وإلا فشل النداء،
    // بنفس ما تفعله بقية مواضع المشاركة في هذا الملف.
    final box = context.findRenderObject() as RenderBox?;
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
      case 'archive':
        _archiveReport(report);
      case 'restore':
        _restoreReport(report);
      case 'delete':
        _deleteReport(report);
    }
  }

  void _showReportPreview(_GeneratedReport report) {
    final selection = report.selection;
    final matched = _reportItems(report);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: AppTr.uiDir,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, scrollController) => Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                    children: [
                      Text(
                        report.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${report.type} • ${_formatDate(report.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      if (report.subject.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'الموضوع: ${report.subject}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      if (report.fromDate != null || report.toDate != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'الفترة: ${report.fromDate == null ? '—' : _formatDate(report.fromDate!)} إلى ${report.toDate == null ? '—' : _formatDate(report.toDate!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (_loadingItems)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (selection == null)
                        const Text(
                          'هذا التقرير أُنشئ بنسخة سابقة بلا معايير محفوظة — أنشئ تقريرًا جديدًا لعرض محتواه.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        )
                      else
                        ScopeResultView(
                          selection: selection,
                          items: matched,
                          accent: _accent,
                        ),
                      const SizedBox(height: 10),
                      const SizedBox(height: 6),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _shareReport(report);
                        },
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('مشاركة / تصدير التقرير'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
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
          Icon(icon, size: 30, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${report.type}  •  ${_formatDate(report.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          if (report.subject.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'الأقسام: ${report.subject}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                          // العنصر المؤرشف يعرض تاريخ الأرشفة وسببها كما
                          // في المتطلبات، لا تاريخ الإنشاء وحده.
                          if (archived) ...[
                            const SizedBox(height: 2),
                            Text(
                              'تاريخ الأرشفة: ${report.archivedAt == null ? '—' : _formatDate(report.archivedAt!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'سبب الأرشفة: ${report.archiveReason.isEmpty ? 'غير محدد' : report.archiveReason}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
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
                                ? const Color(0xFF64748B)
                                : const Color(0xFF10B981))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        archived ? 'مؤرشف' : 'نشط',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: archived
                              ? const Color(0xFF64748B)
                              : const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.list_alt_rounded,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$itemsCount عنصرًا',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
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
                        color: Color(0xFF64748B),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: AppTr.tr('خيارات'),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                      onSelected: (value) =>
                          _handleReportAction(report, value),
                      itemBuilder: (context) => [
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
                            style: const TextStyle(color: Color(0xFFEF4444)),
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

  Widget _buildReportsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildScopeIntroCard(
          icon: Icons.description_outlined,
          title: 'إنشاء تقرير جديد',
          subtitle:
              'اختر القسم ثم الأقسام المطلوب إظهارها وصفِّ عناصرك بالتاريخ والحالة.',
          buttonLabel: 'إنشاء تقرير جديد',
          onPressed: _loadingItems
              ? null
              : () => _openScopeBuilder(archive: false),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
          'آخر التقارير المنشأة',
          trailing: _recentReports.isEmpty ? null : '${_recentReports.length}',
        ),
        if (_recentReports.isEmpty)
          _emptyCard(
            Icons.description_outlined,
            'لا توجد تقارير منشأة بعد.\nابدأ من زر "إنشاء تقرير جديد" في الأعلى.',
          )
        else
          ..._recentReports.map(
            (report) => _buildReportRow(report, archived: false),
          ),
      ],
    );
  }

  /// بطاقة تمهيدية موحّدة أعلى صفحتَي التقارير والأرشيف: عنوان وشرح وزر
  /// واحد يفتح قالب الاختيار.
  Widget _buildScopeIntroCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: _accent),
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
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add_rounded, size: 18),
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
        ],
      ),
    );
  }

  Widget _buildArchiveTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildScopeIntroCard(
          icon: Icons.inventory_2_outlined,
          title: 'إستخراج أرشيف جديد',
          subtitle:
              'اختر القسم والأقسام والفترة، ثم استخرج العنصر إلى الأرشيف مع سبب الأرشفة.',
          buttonLabel: 'إستخراج أرشيف جديد',
          onPressed: _loadingItems ? null : () => _openScopeBuilder(archive: true),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
          'العناصر المؤرشفة',
          trailing: _archivedReports.isEmpty
              ? null
              : '${_archivedReports.length}',
        ),
        if (_archivedReports.isEmpty)
          _emptyCard(
            Icons.inventory_2_outlined,
            'لا توجد عناصر مؤرشفة بعد.\nأنشئ أرشيفًا جديدًا أو أرشف تقريرًا من صفحة التقارير.',
          )
        else
          ..._archivedReports.map(
            (report) => _buildReportRow(report, archived: true),
          ),
      ],
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
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 13.5,
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
      archivedAt: parse(map['archivedAt']),
      archiveReason: (map['archiveReason'] ?? '').toString(),
    );
  }
}

class _DelegationsHubPage extends StatefulWidget {
  const _DelegationsHubPage();

  @override
  State<_DelegationsHubPage> createState() => _DelegationsHubPageState();
}

class _DelegationsHubPageState extends State<_DelegationsHubPage> {
  String _selectedFilter = 'all';

  /// اتجاه التفويض المعروض: تفويضات منحتُها (granted) أو تفويضات مُنحت لي
  /// (received). الاتجاه محفوظ داخل السجل نفسه، فلا يضيع بين الجلسات.
  String _direction = 'granted';

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
      final rows = await _repository.fetchDelegations();
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
      if (notice != null) _notify(notice);
    } catch (_) {
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

  bool _isEnded(_DelegationRecord d) {
    return d.endDate.isBefore(DateTime.now());
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
    if (_isEnded(delegation)) {
      return (
        label: 'منتهي',
        color: const Color(0xFF64748B),
        icon: Icons.event_busy_outlined,
      );
    }
    if (!delegation.active) {
      return (
        label: 'موقوف',
        color: const Color(0xFFDC2626),
        icon: Icons.pause_circle_outline_rounded,
      );
    }
    if (_isScheduled(delegation)) {
      return (
        label: 'مجدول',
        color: const Color(0xFF2563EB),
        icon: Icons.schedule_rounded,
      );
    }
    if (_isExpiringSoon(delegation)) {
      return (
        label: 'ينتهي قريبًا',
        color: const Color(0xFFD97706),
        icon: Icons.timer_outlined,
      );
    }
    return (
      label: 'نشط',
      color: const Color(0xFF07835C),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  String _periodSummary(_DelegationRecord delegation) {
    if (_isEnded(delegation))
      return 'انتهى في ${_formatDate(delegation.endDate)}';
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF24332F),
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
                      color: const Color(0xFF24332F),
                    ),
                  ),
                  trailing: Text(
                    '${option.count}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF087F6A),
                    ),
                  ),
                  leading: Icon(
                    _selectedFilter == option.key
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 19,
                    color: _selectedFilter == option.key
                        ? const Color(0xFF087F6A)
                        : const Color(0xFF94A3B8),
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

  Future<void> _openCreateSheet({
    _DelegationRecord? existing,
    int? index,
  }) async {
    final delegateController = TextEditingController(
      text: existing?.delegateName ?? '',
    );
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
    final allPermissions = DelegationRecord.allPermissions;
    final selectedPermissions = <String>{
      ...?existing?.permissions,
      if (existing == null) 'عرض البيانات',
    };
    DateTime startDate = existing?.startDate ?? DateTime.now();
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
                                  color: Color(0xFF1F2D29),
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
                            fontSize: 11.5,
                            height: 1.4,
                            color: Color(0xFF71807C),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF24332F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: delegateController,
                          textDirection: AppTr.uiDir,
                          decoration: InputDecoration(
                            hintText: AppTr.tr('اكتب اسم الشخص أو الجهة'),
                            filled: true,
                            fillColor: AppTheme.field,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDDE5E2),
                              ),
                            ),
                            suffixIcon: const Icon(
                              Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '2. نطاق التفويض',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF24332F),
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
                              color: Color(0xFF52716B),
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
                                        selectedColor: const Color(0xFFDDF1EC),
                                        checkmarkColor: const Color(0xFF087F6A),
                                        labelStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        onSelected: (selected) {
                                          setModalState(() {
                                            if (selected) {
                                              selectedSubScopes.add(sub);
                                            } else {
                                              selectedSubScopes.remove(sub);
                                            }
                                          });
                                        },
                                      ),
                                    )
                                    .toList(growable: false),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          '3. الصلاحيات المسموحة',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF24332F),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // مستويات جاهزة تختصر الاختيار وتوضّح التدرّج.
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: DelegationRecord.permissionLevels.entries
                              .map(
                                (level) => ChoiceChip(
                                  label: Text(level.key),
                                  selected:
                                      selectedPermissions.length ==
                                          level.value.length &&
                                      selectedPermissions.containsAll(
                                        level.value,
                                      ),
                                  selectedColor: const Color(0xFF087F6A),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        selectedPermissions.length ==
                                                level.value.length &&
                                            selectedPermissions.containsAll(
                                              level.value,
                                            )
                                        ? Colors.white
                                        : const Color(0xFF24332F),
                                  ),
                                  onSelected: (_) => setModalState(() {
                                    selectedPermissions
                                      ..clear()
                                      ..addAll(level.value);
                                  }),
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: allPermissions
                              .map(
                                (permission) => FilterChip(
                                  label: Text(permission),
                                  selected: selectedPermissions.contains(
                                    permission,
                                  ),
                                  selectedColor: const Color(0xFFDDF1EC),
                                  checkmarkColor: const Color(0xFF087F6A),
                                  labelStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      if (selected) {
                                        selectedPermissions.add(permission);
                                      } else {
                                        selectedPermissions.remove(permission);
                                        // إلغاء صلاحية أدنى يلغي ما فوقها،
                                        // فلا يبقى "حذف" بلا "عرض".
                                        final index = DelegationRecord
                                            .orderedPermissions
                                            .indexOf(permission);
                                        if (index >= 0) {
                                          selectedPermissions.removeAll(
                                            DelegationRecord.orderedPermissions
                                                .skip(index),
                                          );
                                          if (permission == 'عرض البيانات') {
                                            selectedPermissions.clear();
                                          }
                                        }
                                      }
                                      final applied =
                                          DelegationRecord.applyHierarchy(
                                            selectedPermissions,
                                          );
                                      selectedPermissions
                                        ..clear()
                                        ..addAll(applied);
                                    });
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '4. مدة التفويض',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF24332F),
                          ),
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
                                  setModalState(() => startDate = picked);
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
                                  setModalState(() => endDate = picked);
                                },
                              ),
                            ),
                          ],
                        ),
                        if (validationMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    validationMessage!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB91C1C),
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
                            final record = _DelegationRecord(
                              // بدون تمرير المعرّف يُنشئ الحفظ سجلًا جديدًا
                              // في كل مرة بدل تعديل القائم — نسخة مكررة عند
                              // كل ضغطة "حفظ التعديل".
                              id: existing?.id,
                              notes: existing?.notes,
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
                              permissions: selectedPermissions.toList(
                                growable: false,
                              ),
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
                            backgroundColor: const Color(0xFF087F6A),
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
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFB42318),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB42318),
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
                color: const Color(0xFFE7F3F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBE3DD)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF087F6A),
                      borderRadius: BorderRadius.circular(10),
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
                            color: Color(0xFF173B35),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'المفوَّض ونطاقه وصلاحياته ومدته.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF52716B),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_delegations.length} تفويضات مسجلة',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF087F6A),
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
                backgroundColor: const Color(0xFF087F6A),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'إنشاء تفويض جديد',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF24332F),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${_statusFilterLabel()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF087F6A),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 19,
                      color: Color(0xFF087F6A),
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF71807C),
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
                return _DelegationCard(
                  key: ValueKey('delegation-${item.id ?? item.delegateName}'),
                  record: item,
                  statusLabel: status.label,
                  statusColor: status.color,
                  statusIcon: status.icon,
                  periodSummary: _periodSummary(item),
                  formattedPeriod:
                      '${_formatDate(item.startDate)} - ${_formatDate(item.endDate)}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _DelegationDetailsPage(record: item),
                    ),
                  ),
                  onAction: (action) async {
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
                    if (action == 'toggle') {
                      await _persist(
                        item.copyWith(active: !item.active),
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
                        _notify('تم حذف التفويض');
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

  bool get isReceived => (delegateRef ?? '').startsWith(receivedMarker);
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
  });

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
          borderRadius: BorderRadius.circular(14),
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
                        color: const Color(0xFFE7F3F0),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF087F6A),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.delegateName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1F2D29),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            record.delegationType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF71807C),
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
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 13, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: AppTr.tr('خيارات التفويض'),
                      onSelected: onAction,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('عرض التفاصيل'),
                        ),
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
                          value: 'delete',
                          child: Text('حذف التفويض'),
                        ),
                      ],
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Color(0xFF84918D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceInner,
                    borderRadius: BorderRadius.circular(AppTheme.rInner),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          formattedPeriod,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      Text(
                        periodSummary,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Icon(
                      Icons.key_outlined,
                      size: 16,
                      color: Color(0xFF71807C),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.permissions.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: Color(0xFFB3BEBA),
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
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 9),
          Text(
            'لا توجد تفويضات ضمن هذه الحالة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF334155),
            ),
          ),
          SizedBox(height: 3),
          Text(
            'اختر حالة أخرى أو أنشئ تفويضًا جديدًا.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
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
    const accent = Color(0xFF087F6A);
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
              color: selected ? accent : const Color(0xFFDDE5E2),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF24332F),
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
                        : const Color(0xFFEFF4F3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
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
            color: Color(0xFF334155),
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
            color: const Color(0xFF64748B),
            icon: Icons.event_busy_outlined,
          )
        : !record.active
        ? (
            label: 'موقوف',
            color: const Color(0xFFDC2626),
            icon: Icons.pause_circle_outline_rounded,
          )
        : scheduled
        ? (
            label: 'مجدول',
            color: const Color(0xFF2563EB),
            icon: Icons.schedule_rounded,
          )
        : expiring
        ? (
            label: 'ينتهي قريبًا',
            color: const Color(0xFFD97706),
            icon: Icons.timer_outlined,
          )
        : (
            label: 'نشط',
            color: const Color(0xFF07835C),
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
                color: const Color(0xFFE7F3F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBE3DD)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EBFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: Color(0xFF087F6A),
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
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'نطاق التفويض: ${record.delegationType}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...record.permissions.map(
                    (permission) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              permission,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
              Icon(icon, size: 15, color: const Color(0xFF71807C)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF71807C)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletsHubPage extends StatefulWidget {
  const _WalletsHubPage();

  @override
  State<_WalletsHubPage> createState() => _WalletsHubPageState();
}

class _WalletsHubPageState extends State<_WalletsHubPage> {
  static const _accent = Color(0xFF0F172A);
  static const _incomeColor = Color(0xFF10B981);
  static const _expenseColor = Color(0xFFEF4444);
  static const _transferColor = Color(0xFF0EA5E9);
  static const _hideBalancesKey = 'wallets_hide_balances_v1';

  final WalletsRepository _repository = SupabaseWalletsRepository();

  List<WalletRecord> _wallets = const [];
  List<WalletTransactionRecord> _transactions = const [];
  bool _loading = true;
  String? _error;

  /// إخفاء المبالغ بنقرة واحدة — سلوك قياسي في التطبيقات المالية عند فتح
  /// التطبيق أمام الآخرين. يُحفظ الاختيار محليًا لأنه تفضيل عرض لا بيانات.
  bool _hideBalances = false;

  /// null = كل المحافظ.
  String? _selectedWalletId;

  @override
  void initState() {
    super.initState();
    _restorePreference();
    _load();
  }

  Future<void> _restorePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(
        () => _hideBalances = prefs.getBool(_hideBalancesKey) ?? false,
      );
    } catch (_) {
      // تفضيل عرض فقط — تجاهله بأمان.
    }
  }

  Future<void> _toggleHideBalances() async {
    final next = !_hideBalances;
    setState(() => _hideBalances = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hideBalancesKey, next);
    } catch (_) {
      // لا يمنع تغيير العرض.
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallets = await _repository.fetchWallets();
      final transactions = await _repository.fetchTransactions();
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _transactions = transactions;
        // محفظة مختارة حُذفت: يعود العرض إلى الكل بدل قائمة فارغة أبدية.
        if (_selectedWalletId != null &&
            !wallets.any((w) => w.id == _selectedWalletId)) {
          _selectedWalletId = null;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل المحافظ. تحقّق من الاتصال وحاول مرة أخرى.';
      });
    }
  }

  // ===== حسابات حقيقية =====

  List<WalletRecord> get _activeWallets =>
      _wallets.where((w) => !w.isArchived).toList(growable: false);

  /// رصيد محفظة = الرصيد الافتتاحي + كل الحركات الموقَّعة عليها.
  double _balanceOf(WalletRecord wallet) {
    final moves = _transactions
        .where((t) => t.walletId == wallet.id)
        .fold<double>(0, (sum, t) => sum + t.signedAmount);
    return wallet.openingBalance + moves;
  }

  double get _totalBalance =>
      _activeWallets.fold<double>(0, (sum, w) => sum + _balanceOf(w));

  List<WalletTransactionRecord> get _visibleTransactions {
    final id = _selectedWalletId;
    final list = id == null
        ? _transactions
        : _transactions.where((t) => t.walletId == id).toList();
    return list;
  }

  /// إجماليات الشهر الحالي — تُحسب من الحركات الفعلية. التحويلات الداخلية
  /// مستبعدة عمدًا: نقل المال بين محفظتين ليس دخلًا ولا مصروفًا، واحتسابه
  /// يضخّم الرقمين معًا ويعطي صورة مالية خاطئة.
  (double income, double expense) get _monthTotals {
    final now = DateTime.now();
    var income = 0.0;
    var expense = 0.0;
    for (final t in _visibleTransactions) {
      final date = t.occurredOn;
      if (date == null || date.year != now.year || date.month != now.month) {
        continue;
      }
      if (t.kind == WalletTransactionRecord.kindIncome) income += t.amount;
      if (t.kind == WalletTransactionRecord.kindExpense) expense += t.amount;
    }
    return (income, expense);
  }

  String _money(double value) {
    if (_hideBalances) return '•••••';
    if (!value.isFinite) return '—';
    final negative = value < 0;
    final text = value.abs().toStringAsFixed(2);
    final parts = text.split('.');
    final buffer = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buffer.write(',');
      buffer.write(parts[0][i]);
    }
    return '${negative ? '-' : ''}$buffer.${parts[1]}';
  }

  String _fmtDate(DateTime? date) {
    if (date == null) return 'بدون تاريخ';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}'
        '/${date.day.toString().padLeft(2, '0')}';
  }

  String get _currency => _activeWallets.isEmpty
      ? AppSettings.currencySuffix
      : _activeWallets.first.currencyLabel;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Color _walletColor(WalletRecord wallet) =>
      wallet.color == null ? _accent : Color(wallet.color!);

  IconData _walletIcon(String kind) => switch (kind) {
    WalletRecord.kindBank => Icons.account_balance_rounded,
    WalletRecord.kindCard => Icons.credit_card_rounded,
    WalletRecord.kindDigital => Icons.account_balance_wallet_rounded,
    _ => Icons.payments_rounded,
  };

  // ===== نماذج =====

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppTheme.field,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.rField),
      borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 1.4),
    ),
  );

  Future<void> _openWalletForm({WalletRecord? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final issuerCtrl = TextEditingController(text: existing?.issuer ?? '');
    final last4Ctrl = TextEditingController(text: existing?.last4 ?? '');
    final openingCtrl = TextEditingController(
      text: existing == null || existing.openingBalance == 0
          ? ''
          : existing.openingBalance.toStringAsFixed(2),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var kind = existing?.kind ?? WalletRecord.kindCash;
    var color = existing?.color ?? 0xFF0F172A;

    const palette = [
      0xFF0F172A,
      0xFF0EA5E9,
      0xFF10B981,
      0xFF7C3AED,
      0xFFF59E0B,
      0xFFEF4444,
    ];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    existing == null ? 'إضافة محفظة' : 'تعديل المحفظة',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final k in WalletRecord.kinds) ...[
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() => kind = k),
                            borderRadius: BorderRadius.circular(
                              AppTheme.rIcon,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 4,
                              ),
                              // بلا حدود؛ المحدَّد يتلوّن كبقية الشرائح.
                              decoration: BoxDecoration(
                                color: kind == k
                                    ? const Color(
                                        0xFF0EA5E9,
                                      ).withValues(alpha: 0.13)
                                    : AppTheme.field,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rIcon,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _walletIcon(k),
                                    size: 19,
                                    color: kind == k
                                        ? const Color(0xFF0EA5E9)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    WalletRecord.kindLabel(k),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: kind == k
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: kind == k
                                          ? const Color(0xFF0EA5E9)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (k != WalletRecord.kinds.last)
                          const SizedBox(width: 7),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _field('اسم المحفظة'),
                  ),
                  if (kind != WalletRecord.kindCash) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: issuerCtrl,
                      textAlign: AppTr.alignEnd,
                      decoration: _field(
                        kind == WalletRecord.kindDigital
                            ? 'المزوّد'
                            : 'اسم البنك',
                      ),
                    ),
                  ],
                  if (kind == WalletRecord.kindCard) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: last4Ctrl,
                      textAlign: AppTr.alignEnd,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: _field('آخر 4 أرقام'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: openingCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: _field('الرصيد الافتتاحي'),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'لون البطاقة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final c in palette) ...[
                        InkWell(
                          onTap: () => setSheetState(() => color = c),
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c
                                    ? const Color(0xFF0F172A)
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    decoration: _field('ملاحظات (اختياري)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                    ),
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('أدخل اسم المحفظة أولاً'),
                          ),
                        );
                        return;
                      }
                      final record = WalletRecord(
                        id: existing?.id,
                        name: name,
                        kind: kind,
                        issuer: issuerCtrl.text.trim().isEmpty
                            ? null
                            : issuerCtrl.text.trim(),
                        last4: last4Ctrl.text.trim().isEmpty
                            ? null
                            : last4Ctrl.text.trim(),
                        openingBalance:
                            double.tryParse(openingCtrl.text.trim()) ?? 0,
                        // المحافظ الجديدة تتبع عملة الإعدادات ولا تُثبَّت
                        // على عملة مكتوبة في الشيفرة.
                        currency: existing?.currency ?? '',
                        color: color,
                        isArchived: existing?.isArchived ?? false,
                        isDefault: existing?.isDefault ?? false,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      );
                      try {
                        await _repository.upsertWallet(record);
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop(true);
                      } catch (_) {
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('تعذّر حفظ المحفظة')),
                        );
                      }
                    },
                    child: Text(existing == null ? 'إضافة' : 'حفظ التعديل'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        _toast(existing == null ? 'تمت إضافة المحفظة' : 'تم حفظ التعديل');
      }
    }
  }

  Future<void> _openTransactionForm({
    required String kind,
    WalletTransactionRecord? existing,
  }) async {
    if (_activeWallets.isEmpty) {
      _toast('أضف محفظة أولاً قبل تسجيل أي حركة');
      return;
    }
    final income = kind == WalletTransactionRecord.kindIncome;
    final amountCtrl = TextEditingController(
      text: existing == null || existing.amount == 0
          ? ''
          : existing.amount.toStringAsFixed(2),
    );
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    // قائمة محافظ النموذج = المحافظ النشطة، مضافًا إليها محفظة الحركة
    // الحالية إن كانت مؤرشفة. بدون ذلك تكون قيمة القائمة المنسدلة خارج
    // عناصرها فيسقط التطبيق بتأكيد (assert) عند تعديل حركة على محفظة
    // مؤرشفة، أو عند اختيار محفظة مؤرشفة من شريط التصفية ثم تسجيل حركة.
    final preferredId =
        existing?.walletId ?? _selectedWalletId ?? _activeWallets.first.id!;
    final formWallets = <WalletRecord>[
      ..._activeWallets,
      ..._wallets.where(
        (w) => w.id == preferredId && !_activeWallets.any((a) => a.id == w.id),
      ),
    ];
    var walletId = formWallets.any((w) => w.id == preferredId)
        ? preferredId
        : formWallets.first.id!;
    DateTime date = existing?.occurredOn ?? DateTime.now();
    final accent = income ? _incomeColor : _expenseColor;
    final suggestions = income
        ? const ['راتب', 'إيجار', 'مبيعات', 'هدية', 'دخل آخر']
        : const ['طعام', 'مواصلات', 'فواتير', 'تسوّق', 'صيانة', 'مصروف آخر'];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        income
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        existing == null
                            ? (income ? 'إضافة دخل' : 'إضافة مصروف')
                            : (income ? 'تعديل الدخل' : 'تعديل المصروف'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _field('المبلغ'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: walletId,
                    isExpanded: true,
                    decoration: _field('المحفظة'),
                    items: formWallets
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(
                              w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => walletId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2060),
                        builder: (pickerContext, child) => Directionality(
                          textDirection: AppTr.uiDir,
                          child: child!,
                        ),
                      );
                      if (picked != null && sheetContext.mounted) {
                        setSheetState(() => date = picked);
                      }
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_fmtDate(date)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: categoryCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _field('التصنيف'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in suggestions)
                        ActionChip(
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          onPressed: () =>
                              setSheetState(() => categoryCtrl.text = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    textAlign: AppTr.alignEnd,
                    maxLines: 2,
                    decoration: _field('ملاحظات (اختياري)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                    ),
                    onPressed: () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('أدخل مبلغًا صحيحًا أكبر من صفر'),
                          ),
                        );
                        return;
                      }
                      try {
                        await _repository.upsertTransaction(
                          WalletTransactionRecord(
                            id: existing?.id,
                            walletId: walletId,
                            kind: kind,
                            amount: amount,
                            occurredOn: date,
                            category: categoryCtrl.text.trim().isEmpty
                                ? null
                                : categoryCtrl.text.trim(),
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          ),
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop(true);
                      } catch (_) {
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('تعذّر حفظ الحركة')),
                        );
                      }
                    },
                    child: Text(existing == null ? 'حفظ' : 'حفظ التعديل'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openTransferForm() async {
    // التحويل يتطلّب محفظتين على الأقل — بدون هذا الشرط يظهر النموذج ثم
    // يفشل عند الحفظ، أو يسمح بالتحويل من محفظة إلى نفسها بلا أي معنى.
    if (_activeWallets.length < 2) {
      _toast('التحويل يحتاج محفظتين على الأقل');
      return;
    }
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var fromId = _activeWallets.first.id!;
    var toId = _activeWallets[1].id!;
    DateTime date = DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        color: _transferColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'تحويل بين المحافظ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: fromId,
                    isExpanded: true,
                    decoration: _field('من محفظة'),
                    items: _activeWallets
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(
                              w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        fromId = value;
                        // منع التحويل إلى نفس المحفظة تلقائيًا.
                        if (toId == fromId) {
                          toId = _activeWallets
                              .firstWhere((w) => w.id != fromId)
                              .id!;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: toId,
                    isExpanded: true,
                    decoration: _field('إلى محفظة'),
                    items: _activeWallets
                        .where((w) => w.id != fromId)
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(
                              w.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() => toId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    textAlign: AppTr.alignEnd,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _field('المبلغ'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2060),
                        builder: (pickerContext, child) => Directionality(
                          textDirection: AppTr.uiDir,
                          child: child!,
                        ),
                      );
                      if (picked != null && sheetContext.mounted) {
                        setSheetState(() => date = picked);
                      }
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_fmtDate(date)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    textAlign: AppTr.alignEnd,
                    decoration: _field('ملاحظات (اختياري)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _transferColor,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rField),
        ),
                    ),
                    onPressed: () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('أدخل مبلغًا صحيحًا أكبر من صفر'),
                          ),
                        );
                        return;
                      }
                      if (fromId == toId) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text('اختر محفظتين مختلفتين'),
                          ),
                        );
                        return;
                      }
                      try {
                        await _repository.transfer(
                          fromWalletId: fromId,
                          toWalletId: toId,
                          amount: amount,
                          occurredOn: date,
                          note: noteCtrl.text.trim().isEmpty
                              ? null
                              : noteCtrl.text.trim(),
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop(true);
                      } catch (_) {
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('تعذّر تنفيذ التحويل')),
                        );
                      }
                    },
                    child: const Text('تنفيذ التحويل'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) _toast('تم تنفيذ التحويل');
    }
  }

  Future<void> _walletMenu(WalletRecord wallet) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('تعديل المحفظة'),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: Icon(
                  wallet.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  wallet.isArchived ? 'إلغاء الأرشفة' : 'أرشفة المحفظة',
                ),
                onTap: () => Navigator.of(sheetContext).pop('archive'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
                title: const Text(
                  'حذف المحفظة',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'edit') {
      await _openWalletForm(existing: wallet);
      return;
    }
    if (action == 'archive') {
      try {
        await _repository.upsertWallet(
          wallet.copyWith(isArchived: !wallet.isArchived),
        );
        // إلغاء تصفية القائمة إن كانت على المحفظة التي أُرشفت للتو.
        if (!wallet.isArchived && _selectedWalletId == wallet.id) {
          _selectedWalletId = null;
        }
        await _load();
        if (mounted) {
          _toast(
            wallet.isArchived ? 'تم إخراجها من الأرشيف' : 'تمت أرشفة المحفظة',
          );
        }
      } catch (_) {
        if (mounted) _toast('تعذّر تنفيذ العملية');
      }
      return;
    }

    final own = _transactions.where((t) => t.walletId == wallet.id).toList();
    final count = own.length;
    // حذف المحفظة يحذف أيضًا الطرف المقابل لكل تحويل يخصّها من المحفظة
    // الأخرى، وإلا بقي خصمٌ بلا إيداع مقابل. يجب أن يعرف المستخدم ذلك.
    final transfers = own.where((t) => t.isTransfer).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: AlertDialog(
          title: const Text('حذف المحفظة'),
          // تحذير صريح بعدد الحركات التي ستُحذف معها — الحذف يُسقط كل
          // حركاتها عبر cascade في قاعدة البيانات.
          content: Text(
            [
              count == 0
                  ? 'سيتم حذف "${wallet.name}" نهائيًا.'
                  : 'سيتم حذف "${wallet.name}" و $count حركة مسجّلة عليها نهائيًا.',
              if (transfers > 0)
                'ومن بينها $transfers تحويلًا سيُحذف طرفه المقابل من المحفظة الأخرى أيضًا، فيتغيّر رصيدها.',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'حذف',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteWallet(wallet.id!);
      await _load();
      if (mounted) _toast('تم حذف المحفظة');
    } catch (_) {
      if (mounted) _toast('تعذّر حذف المحفظة');
    }
  }

  Future<void> _transactionMenu(WalletTransactionRecord t) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // التحويل لا يُعدَّل طرفًا واحدًا: تعديل جهة أو مبلغ طرف دون
              // الآخر يترك المحفظتين بأرصدة غير متطابقة. يُحذف ويُعاد.
              if (!t.isTransfer)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('تعديل الحركة'),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
                title: Text(
                  t.isTransfer ? 'حذف التحويل (الطرفين)' : 'حذف الحركة',
                  style: const TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _openTransactionForm(kind: t.kind, existing: t);
      return;
    }
    try {
      await _repository.deleteTransaction(t);
      await _load();
      if (mounted) _toast('تم الحذف');
    } catch (_) {
      if (mounted) _toast('تعذّر الحذف');
    }
  }

  // ===== الواجهة =====

  @override
  Widget build(BuildContext context) {
    final totals = _monthTotals;
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        appBar: AppBar(
          title: const Text(
            'المحافظ',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppTheme.title,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              tooltip: _hideBalances ? 'إظهار المبالغ' : 'إخفاء المبالغ',
              onPressed: _toggleHideBalances,
              icon: Icon(
                _hideBalances
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
            IconButton(
              tooltip: AppTr.tr('تحديث'),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openWalletForm(),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('محفظة'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                  children: [
                    if (_error != null) ...[
                      _errorBanner(),
                      const SizedBox(height: 12),
                    ],
                    _totalCard(totals.$1, totals.$2),
                    const SizedBox(height: 14),
                    _quickActions(),
                    const SizedBox(height: 18),
                    _sectionTitle(
                      'محافظي',
                      trailing: _activeWallets.isEmpty
                          ? null
                          : '${_activeWallets.length}',
                    ),
                    if (_wallets.isEmpty)
                      _emptyCard(
                        Icons.account_balance_wallet_outlined,
                        'لا توجد محافظ بعد.\nأضف محفظتك الأولى من زر "+ محفظة".',
                      )
                    else
                      SizedBox(
                        height: 152,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _wallets.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) =>
                              _walletCard(_wallets[index]),
                        ),
                      ),
                    const SizedBox(height: 18),
                    _sectionTitle(
                      _selectedWalletId == null
                          ? 'آخر الحركات'
                          : 'حركات المحفظة المحددة',
                      trailing: _visibleTransactions.isEmpty
                          ? null
                          // القائمة تعرض 60 حركة كحدّ أقصى، فيُظهر العنوان
                          // العدد المعروض فعلًا لا العدد الكلي.
                          : _visibleTransactions.length > 60
                          ? '60 من ${_visibleTransactions.length}'
                          : '${_visibleTransactions.length}',
                    ),
                    if (_wallets.isNotEmpty) _walletFilterChips(),
                    if (_visibleTransactions.isEmpty)
                      _emptyCard(
                        Icons.receipt_long_outlined,
                        'لا توجد حركات مسجّلة بعد.\nاستخدم أزرار الدخل والمصروف والتحويل أعلاه.',
                      )
                    else
                      for (final t in _visibleTransactions.take(60))
                        _transactionTile(t),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _errorBanner() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _error!,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB42318),
            ),
          ),
        ),
        TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      ],
    ),
  );

  Widget _totalCard(double income, double expense) {
    final cards = _activeWallets
        .where((w) => w.kind == WalletRecord.kindCard)
        .length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'الرصيد الكلي',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              ),
              const Spacer(),
              if (_activeWallets.isNotEmpty)
                Text(
                  '${_activeWallets.length} محفظة'
                  '${cards > 0 ? ' · $cards بطاقة' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF93C5FD),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_money(_totalBalance)} $_currency',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _totalMini(
                  'دخل هذا الشهر',
                  income,
                  Icons.arrow_downward_rounded,
                  const Color(0xFF6EE7B7),
                ),
              ),
              Container(width: 1, height: 30, color: const Color(0x33FFFFFF)),
              Expanded(
                child: _totalMini(
                  'مصروف هذا الشهر',
                  expense,
                  Icons.arrow_upward_rounded,
                  const Color(0xFFFCA5A5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalMini(String label, double value, IconData icon, Color color) =>
      Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _money(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      );

  Widget _quickActions() => Row(
    children: [
      Expanded(
        child: _actionButton(
          'دخل',
          Icons.add_circle_outline_rounded,
          _incomeColor,
          () => _openTransactionForm(
            kind: WalletTransactionRecord.kindIncome,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _actionButton(
          'مصروف',
          Icons.remove_circle_outline_rounded,
          _expenseColor,
          () => _openTransactionForm(
            kind: WalletTransactionRecord.kindExpense,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _actionButton(
          'تحويل',
          Icons.swap_horiz_rounded,
          _transferColor,
          _openTransferForm,
        ),
      ),
    ],
  );

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(AppTheme.rField),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionTitle(String text, {String? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 17,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
      ],
    ),
  );

  Widget _emptyCard(IconData icon, String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
    decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
    child: Column(
      children: [
        Icon(icon, size: 30, color: const Color(0xFFCBD5E1)),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    ),
  );

  Widget _walletCard(WalletRecord wallet) {
    final color = _walletColor(wallet);
    final selected = _selectedWalletId == wallet.id;
    return SizedBox(
      width: 210,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // الضغط يصفّي قائمة الحركات على هذه المحفظة، والضغط مجددًا يلغي
          // التصفية — ربط مباشر بين البطاقة والقائمة أسفلها.
          onTap: () => setState(
            () => _selectedWalletId = selected ? null : wallet.id,
          ),
          onLongPress: () => _walletMenu(wallet),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _walletIcon(wallet.kind),
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        wallet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _walletMenu(wallet),
                      borderRadius: BorderRadius.circular(99),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white70,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _money(_balanceOf(wallet)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  wallet.currencyLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      wallet.kind == WalletRecord.kindCard &&
                              (wallet.last4 ?? '').isNotEmpty
                          ? '•••• ${wallet.last4}'
                          : WalletRecord.kindLabel(wallet.kind),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    if (wallet.isArchived)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'مؤرشفة',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
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
  }

  Widget _walletFilterChips() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('الكل', style: TextStyle(fontSize: 11)),
            selected: _selectedWalletId == null,
            onSelected: (_) => setState(() => _selectedWalletId = null),
          ),
          for (final w in _wallets) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(w.name, style: const TextStyle(fontSize: 11)),
              selected: _selectedWalletId == w.id,
              onSelected: (_) => setState(() => _selectedWalletId = w.id),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _transactionTile(WalletTransactionRecord t) {
    final wallet = _wallets.where((w) => w.id == t.walletId).toList();
    final walletName = wallet.isEmpty ? '' : wallet.first.name;
    final color = t.isTransfer
        ? _transferColor
        : (t.isCredit ? _incomeColor : _expenseColor);
    final icon = t.isTransfer
        ? (t.kind == WalletTransactionRecord.kindTransferIn
              ? Icons.call_received_rounded
              : Icons.call_made_rounded)
        : (t.isCredit
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded);
    final title = (t.category ?? '').trim().isNotEmpty
        ? t.category!.trim()
        : (t.isTransfer
              ? 'تحويل'
              : (t.isCredit ? 'دخل' : 'مصروف'));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rField),
          ),
      clipBehavior: Clip.antiAlias,
      // Material شفافة بين الحاوية وInkWell حتى يظهر أثر اللمس فوق
      // خلفية البطاقة بدل أن يُرسم خلفها فلا يُرى.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: () => _transactionMenu(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _fmtDate(t.occurredOn),
                        if (walletName.isNotEmpty) walletName,
                        if ((t.note ?? '').trim().isNotEmpty) t.note!.trim(),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _hideBalances
                    ? _money(t.amount)
                    : '${t.isCredit ? '+' : '-'}${_money(t.amount)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

