import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'data/home_dashboard_service.dart';
import 'data/home_pin_items_service.dart';
import 'data/home_pinned_shortcuts_store.dart';
import 'l10n/home_strings.dart';
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
import 'widgets/shared/search_matching.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: HomeStrings.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF1E3A8A)),
        useMaterial3: true,
      ),
      // ملاحظة مهمة: لا تفرض Directionality.rtl عامًا هنا. شاشات هذا التطبيق
      // مكتوبة على افتراض اتجاه افتراضي LTR مع تحديد rtl صراحةً داخل كل Row
      // يحتاجه، واستخدام CrossAxisAlignment.end بمعنى "المحاذاة لليمين".
      // فرض rtl عامًا يعكس كل هذه المحاذاة ويبعثر عناصر الشاشات بالكامل.
      home: const HomePage(),
      routes: {'/home': (context) => const HomePage()},
      debugShowCheckedModeBanner: false,
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
  String _selectedHomeFilter = HomeStrings.filterAll;
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

  @override
  void initState() {
    super.initState();
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
    try {
      final dashboardService = HomeDashboardService();
      metrics = await dashboardService.loadMetrics();
    } catch (_) {
      metrics = const HomeDashboardMetrics.empty();
    }
    if (!mounted) return;
    setState(() {
      _showCategoriesInTwoColumns = persistedLayout ?? true;
      _pinnedShortcuts = shortcuts;
      _metrics = metrics;
      _isLoadingMetrics = false;
    });
  }

  Future<void> _refreshHomeMetrics() async {
    HapticFeedback.mediumImpact();
    try {
      final dashboardService = HomeDashboardService();
      final metrics = await dashboardService.loadMetrics();
      if (!mounted) return;
      setState(() => _metrics = metrics);
    } catch (_) {
      // Keep the previously loaded metrics if the refresh fails.
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
    _searchController.dispose();
    _homeScrollController.dispose();
    _categoryFlashController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget _buildSummaryAndPinnedRow() {
    final pinButton = Tooltip(
      message: 'إدارة العناصر المثبتة',
      child: InkWell(
        key: const ValueKey('home-pin-picker'),
        onTap: () {
          HapticFeedback.selectionClick();
          _openPinPicker();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7BFF),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A2E7BFF),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.push_pin_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );

    return SizedBox(
      key: const ValueKey('home-summary-pin-panel'),
      // ارتفاع محسوب بدقة على المحتوى الفعلي: حشوة (24) + الصف العلوي
      // (74 = العنوان 20 + زر التثبيت 40 + المسافات) + فاصل (10) + سطر
      // العناصر المثبتة (70، وبطاقتها 50 فقط). هذا يرفع البطاقة للأعلى
      // ويزيل الفراغ الزائد الذي كان أسفل صندوق "الملخص الشامل".
      height: 178,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 18,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الصف العلوي: صندوق "الملخص الشامل" بحجم محتواه فقط (لم يعد
              // يمتد لكامل ارتفاع البطاقة) بجانبه العنوان وزر التثبيت.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'الملخص',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'الشامل',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      const Text(
                        'اختر ما تريد متابعته بسرعة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF173F63),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // زر إدارة العناصر المثبتة — نُقل إلى هنا ليكون مباشرةً
                      // تحت عنوان "اختر ما تريد متابعته بسرعة" بدل موضعه
                      // السابق داخل صندوق "الملخص الشامل".
                      Center(child: pinButton),
                    ],
                  ),
                ),
              ),
                ],
              ),
              const SizedBox(height: 10),
              // سطر العناصر المثبتة يمتد الآن على كامل عرض المستطيل بدل
              // انحصاره في العمود المجاور لصندوق الملخص.
              Expanded(
                child: _pinnedShortcuts.isEmpty
                            ? Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE8EEF3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.push_pin_outlined,
                                      size: 13,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'ابدأ بتثبيت العناصر المهمة',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                padding: EdgeInsets.zero,
                                itemCount: _pinnedShortcuts.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final shortcut = _pinnedShortcuts[index];
                                  return SizedBox(
                                    width: 118,
                                    child: _HomePinnedCard(
                                      key: ValueKey(
                                        'home-pinned-${shortcut.id}',
                                      ),
                                      shortcut: shortcut,
                                      onOpen: () => _openShortcut(shortcut),
                                      onRemove: () =>
                                          _removePinnedShortcut(shortcut.id),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGlobalSummarySheet() async {
    final m = _metrics;
    final comprehensiveItems = [
      (
        'income',
        HomeStrings.totalIncome,
        '${_formatAmount(m.totalIncome)} درهم',
        Icons.trending_up_rounded,
        const Color(0xFF07835C),
      ),
      (
        'expenses',
        HomeStrings.totalExpenses,
        '${_formatAmount(m.totalExpenses)} درهم',
        Icons.trending_down_rounded,
        const Color(0xFFD05A3A),
      ),
      (
        'debts',
        HomeStrings.totalDebts,
        '${_formatAmount(m.totalDebts)} درهم',
        Icons.credit_card_rounded,
        const Color(0xFFC2415D),
      ),
      (
        'documents',
        HomeStrings.expiringDocs,
        _formatCountWithUnit(m.expiringDocuments, 'مستند'),
        Icons.description_outlined,
        const Color(0xFFB56A09),
      ),
      (
        'commitments',
        HomeStrings.commitmentsTasks,
        _formatCountWithUnit(m.commitmentsAndTasks, 'عنصر'),
        Icons.fact_check_outlined,
        const Color(0xFF5B5BD6),
      ),
      (
        'assets',
        HomeStrings.totalAssets,
        _formatCountWithUnit(m.totalAssets, 'أصل'),
        Icons.account_balance_wallet_outlined,
        const Color(0xFF0F6AA8),
      ),
    ];

    final moduleItems = [
      (
        'personal',
        HomeStrings.modulePersonal,
        'لك ${_formatAmount(m.personalDebtsForYou)} · عليك ${_formatAmount(m.personalDebtsOnYou)} · متابعة ${_formatArabicNumber(m.personalNeedsFollowup)}',
        Icons.person_outline_rounded,
        const Color(0xFF3B82F6),
      ),
      (
        'shared',
        HomeStrings.moduleShared,
        'رحلات ${_formatArabicNumber(m.sharedActiveTrips)} · جمعيات ${_formatArabicNumber(m.sharedActiveCircles)} · متابعة ${_formatArabicNumber(m.sharedNeedsFollowup)}',
        Icons.groups_2_outlined,
        const Color(0xFF10B981),
      ),
      (
        'people',
        HomeStrings.modulePeople,
        'أفراد ${_formatArabicNumber(m.peopleCount)} · جهات ${_formatArabicNumber(m.entitiesCount)} · متابعة ${_formatArabicNumber(m.peopleNeedsFollowup)}',
        Icons.people_alt_outlined,
        const Color(0xFF7956A8),
      ),
      (
        'assets',
        HomeStrings.moduleAssets,
        'عقارات ${_formatArabicNumber(m.assetsCount)} · أنشطة ${_formatArabicNumber(m.businessCount)} · متابعة ${_formatArabicNumber(m.assetsNeedsFollowup)}',
        Icons.apartment_rounded,
        const Color(0xFFF59E0B),
      ),
    ];

    final allItems = [...comprehensiveItems, ...moduleItems];
    String? selectedSummaryId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF5F8FC),
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedItem = selectedSummaryId == null
              ? null
              : allItems
                    .where((item) => item.$1 == selectedSummaryId)
                    .firstOrNull;
          return Directionality(
            textDirection: TextDirection.rtl,
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
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          tooltip: 'إغلاق',
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const Expanded(
                          child: Text(
                            'الملخص العام',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('global-summary-sheet'),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: [
                        _buildSummaryGroup(
                          title: HomeStrings.fullSummarySection,
                          subtitle: 'قراءة موحّدة لكل البنود الأساسية',
                          items: comprehensiveItems,
                          selectedId: selectedSummaryId,
                          onSelected: (id) =>
                              setSheetState(() => selectedSummaryId = id),
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryGroup(
                          title: HomeStrings.modulesSection,
                          subtitle: 'اختر أي وحدة لقراءة ملخصها وإرساله',
                          items: moduleItems,
                          selectedId: selectedSummaryId,
                          onSelected: (id) =>
                              setSheetState(() => selectedSummaryId = id),
                        ),
                        if (selectedItem != null) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('send-selected-summary'),
                            onPressed: () => _shareSummary(
                              title: selectedItem.$2,
                              lines: [selectedItem.$3],
                            ),
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text(HomeStrings.summaryShareText),
                            style: FilledButton.styleFrom(
                              backgroundColor: selectedItem.$5,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('send-selected-summary-pdf'),
                            onPressed: () => _shareSummary(
                              title: selectedItem.$2,
                              lines: [selectedItem.$3],
                              asPdf: true,
                            ),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            label: const Text(HomeStrings.summarySharePdf),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('send-complete-summary'),
                          onPressed: () => _shareSummary(
                            title: HomeStrings.summaryTitle,
                            lines: allItems
                                .map((item) => '${item.$2}: ${item.$3}')
                                .toList(),
                          ),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text(HomeStrings.summaryShareText),
                        ),
                      ],
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

  Widget _buildSummaryGroup({
    required String title,
    required String subtitle,
    required List<(String, String, String, IconData, Color)> items,
    required String? selectedId,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            fontSize: 10.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 9),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _HomeSummaryItem(
              key: ValueKey('summary-${item.$1}'),
              title: item.$2,
              detail: item.$3,
              icon: item.$4,
              color: item.$5,
              selected: selectedId == item.$1,
              onTap: () => onSelected(item.$1),
            ),
          ),
        ),
      ],
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
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var output = value.toString();
    for (var i = 0; i < western.length; i++) {
      output = output.replaceAll(western[i], arabic[i]);
    }
    return output;
  }

  String _formatAmount(int value) => _formatArabicNumber(value);

  String _formatCountWithUnit(int value, String unit) {
    return '${_formatArabicNumber(value)} $unit';
  }

  Future<void> _openHomeFilterSheet() async {
    final options = [
      HomeStrings.filterAll,
      HomeStrings.filterPersonal,
      HomeStrings.filterShared,
      HomeStrings.filterPeople,
      HomeStrings.filterAssets,
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: options
                  .map(
                    (option) => RadioListTile<String>(
                      value: option,
                      groupValue: _selectedHomeFilter,
                      title: Text(option),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedHomeFilter = value);
                        Navigator.of(context).pop();
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
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
          textDirection: TextDirection.rtl,
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
                                tooltip: 'إغلاق',
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
      backgroundColor: const Color(0xFFF5F8FC),
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
                    backgroundColor: const Color(0xFFE0F2FE),
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFEAF7FF), Color(0xFFCDEBFB)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 7),
                            child: Directionality(
                              textDirection: TextDirection.rtl,
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
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0xFF8CC8E8),
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x1A1E40AF),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.person_rounded,
                                              color: Color(0xFF0F6AA8),
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
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 4,
                                                ),
                                                child: Text(
                                                  HomeStrings.userName,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF0B4A73),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      _HomeHeaderAction(
                                        tooltip: 'التقويم الذكي',
                                        icon: Icons.calendar_month_rounded,
                                        backgroundColor: const Color(
                                          0xFFDCFCE7,
                                        ),
                                        borderColor: const Color(0xFF86EFAC),
                                        iconColor: const Color(0xFF047857),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SmartCalendarScreen(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _HomeHeaderAction(
                                        tooltip: 'الإشعارات',
                                        icon: Icons.notifications_none_rounded,
                                        backgroundColor: const Color(
                                          0xFFFFEDD5,
                                        ),
                                        borderColor: const Color(0xFFFDBA74),
                                        iconColor: const Color(0xFFB45309),
                                        showBadge: true,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const NotificationsCenterScreen(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _HomeHeaderAction(
                                        tooltip: HomeStrings.raffle,
                                        icon: Icons.casino_outlined,
                                        backgroundColor: const Color(
                                          0xFFEDE9FE,
                                        ),
                                        borderColor: const Color(0xFFC4B5FD),
                                        iconColor: const Color(0xFF6D28D9),
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
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0B3555),
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
                      textDirection: TextDirection.rtl,
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
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE1E8F0),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x0F0F172A),
                                              blurRadius: 14,
                                              offset: Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: TextField(
                                          controller: _searchController,
                                          textDirection: TextDirection.rtl,
                                          decoration: InputDecoration(
                                            hintText: HomeStrings.searchHint,
                                            hintStyle: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.search_rounded,
                                              color: Color(0xFF0F6AA8),
                                              size: 22,
                                            ),
                                            suffixIcon:
                                                _searchController.text.isEmpty
                                                ? null
                                                : IconButton(
                                                    icon: const Icon(
                                                      Icons.close_rounded,
                                                      size: 18,
                                                      color: Color(0xFF94A3B8),
                                                    ),
                                                    onPressed: () {
                                                      HapticFeedback.selectionClick();
                                                      _searchController.clear();
                                                    },
                                                  ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 15,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _PressableScale(
                                      child: Material(
                                        color: const Color(0xFF0F6AA8),
                                        borderRadius: BorderRadius.circular(12),
                                        child: InkWell(
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            _openHomeFilterSheet();
                                          },
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: const SizedBox(
                                            width: 56,
                                            height: 52,
                                            child: Center(
                                              child: Text(
                                                HomeStrings.filterLabel,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  12,
                                ),
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    Tooltip(
                                      message: _showCategoriesInTwoColumns
                                          ? 'عرض بطاقة واحدة في كل صف'
                                          : 'عرض بطاقتين في كل صف',
                                      child: _PressableScale(
                                        child: Material(
                                          color: const Color(
                                            0xFF0F6AA8,
                                          ).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: InkWell(
                                            key: const ValueKey(
                                              'home-categories-layout-toggle',
                                            ),
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              _toggleLayout();
                                            },
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(9),
                                              child: Icon(
                                                _showCategoriesInTwoColumns
                                                    ? Icons.grid_view_rounded
                                                    : Icons.view_agenda_rounded,
                                                color: const Color(0xFF0F6AA8),
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'أدر أموالك وأملاكك باحترافية',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ],
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
            'ديون لك: ${_formatArabicNumber(_metrics.personalDebtsForYou)}',
            Icons.south_west_rounded,
            const Color(0xFF07835C),
          ),
          (
            'ديون عليك: ${_formatArabicNumber(_metrics.personalDebtsOnYou)}',
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        key: const ValueKey('home-categories-grid'),
        itemCount: filteredCategories.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _showCategoriesInTwoColumns ? 2 : 1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: _showCategoriesInTwoColumns ? 124 : 108,
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
        return _PressableScale(
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.white,
                color.withValues(alpha: 0.18),
                flash,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.1 + (flash * 0.25)),
                  blurRadius: 10 + (flash * 10),
                  offset: Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Color.lerp(color.withValues(alpha: 0.14), color, flash)!,
                width: 1.2 + (flash * 1.8),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('home-category-$categoryIndex'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _openPriorityScreen(title);
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: 10,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              _HomeCategoryIcon(icon: icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  key: ValueKey('home-category-title-$categoryIndex'),
                  title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _HomeCategoryArrow(color: color),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: compact
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SizedBox(
                        width: 116,
                        child: _HomeCategoryMetric(
                          label: item.$1,
                          icon: item.$2,
                          color: item.$3,
                          compact: true,
                        ),
                      );
                    },
                  )
                // بأكثر من ثلاث مقتطفات لا يتسع الصف الواحد إلا بتصغير الخط
                // إلى حدّ يصعب قراءته، لذا يتحول عندها إلى شريط أفقي قابل
                // للتمرير بعرض ثابت لكل مقتطف.
                : items.length > 3
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) => SizedBox(
                      width: 148,
                      child: _HomeCategoryMetric(
                        label: items[index].$1,
                        icon: items[index].$2,
                        color: items[index].$3,
                        compact: false,
                      ),
                    ),
                  )
                : Row(
                    textDirection: TextDirection.rtl,
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
            textDirection: TextDirection.rtl,
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
                textDirection: TextDirection.rtl,
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
                      textDirection: TextDirection.rtl,
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
                  textDirection: TextDirection.rtl,
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
      textDirection: TextDirection.rtl,
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
                  textDirection: TextDirection.rtl,
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
                  textDirection: TextDirection.rtl,
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
      textDirection: TextDirection.rtl,
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
            text: 'درهم',
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Directionality(
          textDirection: TextDirection.rtl,
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
    );
  }

  Widget _buildGlassNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    final isSelected = _selectedIndex == index;
    return _PressableScale(
      child: InkWell(
        onTap: () {
          if (_selectedIndex != index) {
            HapticFeedback.selectionClick();
          }
          setState(() => _selectedIndex = index);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGlassNavIcon(isSelected ? selectedIcon : icon, isSelected),
              const SizedBox(height: 8),
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
                      color: isSelected
                          ? const Color(0xFF0F4D86)
                          : const Color(0xFF64748B),
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

  Widget _buildGlassNavIcon(IconData icon, bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: selected
              ? const [Color(0xFF2E4F7D), Color(0xFF192F4B)]
              : const [Color(0xFF2A3E58), Color(0xFF182536)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: selected ? const Color(0xFF9BE8FF) : const Color(0xFF6B87A7),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? const Color(0x6600E5FF) : const Color(0x332F9BFF),
            blurRadius: selected ? 14 : 8,
            offset: const Offset(0, 3),
          ),
          const BoxShadow(
            color: Color(0x1AFFFFFF),
            blurRadius: 1,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 24,
        color: selected ? const Color(0xFFA7F3FF) : const Color(0xFF93C5FD),
      ),
    );
  }
}

class _HomeHeaderAction extends StatelessWidget {
  const _HomeHeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.backgroundColor = const Color(0xD1FFFFFF),
    this.iconColor = const Color(0xFF0F6AA8),
    this.borderColor = const Color(0xFFCCE5F4),
    this.showBadge = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color iconColor;
  final Color borderColor;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: tooltip,
          child: Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: 40,
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
              ),
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            top: 7,
            right: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFE5484D),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeSummaryItem extends StatelessWidget {
  const _HomeSummaryItem({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.11) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.55)
                  : const Color(0xFFE4EAF0),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? color : const Color(0xFFB6C1CD),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCategoryIcon extends StatelessWidget {
  const _HomeCategoryIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _HomeCategoryArrow extends StatelessWidget {
  const _HomeCategoryArrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.arrow_forward_ios_rounded, color: color, size: 12),
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
    final metricTextStyle = TextStyle(
      fontSize: compact ? 11.2 : 12.2,
      fontWeight: FontWeight.w800,
      height: 1.1,
      color: color,
      fontFamilyFallback: const ['Cairo', 'Noto Kufi Arabic', 'Tahoma'],
    );

    return SizedBox(
      width: double.infinity,
      height: compact ? 31 : 30,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, color: color, size: compact ? 14 : 16),
          SizedBox(width: compact ? 5 : 7),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(label, maxLines: 1, style: metricTextStyle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePinnedCard extends StatelessWidget {
  const _HomePinnedCard({
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
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: style.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            key: ValueKey('home-pinned-card-${shortcut.id}'),
            width: 152,
            height: 50,
            padding: const EdgeInsetsDirectional.fromSTEB(7, 4, 3, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: style.color.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(style.icon, size: 16, color: style.color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shortcut.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF17212B),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        shortcut.subtitle.isEmpty
                            ? style.label
                            : shortcut.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إلغاء التثبيت',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Color(0xFF94A3B8),
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
      color: const Color(0xFF0D9488),
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
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5ECEA)),
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

  final TextEditingController _reportTitleController = TextEditingController();
  final TextEditingController _reportSubjectController =
      TextEditingController();
  final TextEditingController _archiveSearchController =
      TextEditingController();
  final TextEditingController _archiveSubjectController =
      TextEditingController();
  final TextEditingController _archiveCreatorController =
      TextEditingController();
  final FocusNode _archiveSearchFocus = FocusNode();

  DateTime? _reportFromDate;
  DateTime? _reportToDate;
  DateTime? _archiveFromDate;
  DateTime? _archiveToDate;

  String _reportType = 'تقرير عام';
  String _reportMode = 'عام';
  String _archiveTypeFilter = 'الكل';

  final Set<String> _selectedDataFields = {..._reportDataFields};
  List<_GeneratedReport> _recentReports = [];
  List<_GeneratedReport> _archivedReports = [];

  /// أرقام لوحة المعلومات الحقيقية — منها يُبنى محتوى كل تقرير، بدل تقرير
  /// يحمل عنوانًا فقط بلا أي بيانات خلفه.
  HomeDashboardMetrics _metrics = const HomeDashboardMetrics.empty();
  bool _loadingMetrics = true;

  static const List<String> _reportTypes = [
    'تقرير عام',
    'الالتزامات الشخصية',
    'الالتزامات المشتركة',
    'إدارة الأشخاص والجهات',
    'العقارات / الأنشطة التجارية / المعدات وأخرى',
  ];

  // كل حقل هنا له بيانات حقيقية تقابله في HomeDashboardMetrics — لا تُعرض
  // أي خانة لا يمكن ملؤها فعليًا من قاعدة البيانات.
  static const List<String> _reportDataFields = [
    'الملخص المالي',
    'الديون',
    'الالتزامات والمهام',
    'المستندات',
    'الالتزامات المشتركة',
    'الأشخاص والجهات',
    'العقارات والأنشطة',
    'المواعيد القادمة',
  ];

  /// أي أقسام تخصّ أي نوع تقرير — يمنع ظهور قسم لا علاقة له بالنوع المختار.
  static const Map<String, List<String>> _sectionsByType = {
    'الالتزامات الشخصية': [
      'الملخص المالي',
      'الديون',
      'الالتزامات والمهام',
      'المستندات',
      'المواعيد القادمة',
    ],
    'الالتزامات المشتركة': ['الالتزامات المشتركة', 'المواعيد القادمة'],
    'إدارة الأشخاص والجهات': ['الأشخاص والجهات'],
    'العقارات / الأنشطة التجارية / المعدات وأخرى': [
      'العقارات والأنشطة',
      'المواعيد القادمة',
    ],
  };

  @override
  void initState() {
    super.initState();
    _archiveSearchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _restore();
    _loadMetrics();
  }

  @override
  void dispose() {
    _reportTitleController.dispose();
    _reportSubjectController.dispose();
    _archiveSearchController.dispose();
    _archiveSubjectController.dispose();
    _archiveCreatorController.dispose();
    _archiveSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    try {
      final metrics = await HomeDashboardService().loadMetrics();
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _loadingMetrics = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMetrics = false);
    }
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

  String _formatAmount(int value) {
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return '${value < 0 ? '-' : ''}$buffer';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    onSelected(picked);
  }

  // ===== محتوى التقرير الحقيقي =====

  /// الأقسام التي ستُعرض فعليًا في تقرير ما: تقاطع ما اختاره المستخدم مع ما
  /// يخصّ نوع التقرير المحدد.
  List<String> _sectionsFor(_GeneratedReport report) {
    final allowed = _sectionsByType[report.type] ?? _reportDataFields;
    return report.dataFields
        .where((field) => allowed.contains(field))
        .toList(growable: false);
  }

  /// يبني بنود قسم واحد من أرقام لوحة المعلومات الحقيقية.
  List<(String, String)> _sectionRows(String section) {
    final m = _metrics;
    switch (section) {
      case 'الملخص المالي':
        return [
          ('إجمالي الدخل', '${_formatAmount(m.totalIncome)} درهم'),
          ('إجمالي المصروفات', '${_formatAmount(m.totalExpenses)} درهم'),
          (
            'الصافي',
            '${_formatAmount(m.totalIncome - m.totalExpenses)} درهم',
          ),
        ];
      case 'الديون':
        return [
          ('إجمالي الديون', '${_formatAmount(m.totalDebts)} درهم'),
          ('ديون لك', '${_formatAmount(m.personalDebtsForYou)} درهم'),
          ('ديون عليك', '${_formatAmount(m.personalDebtsOnYou)} درهم'),
        ];
      case 'الالتزامات والمهام':
        return [
          ('التزامات ومهام مفتوحة', '${m.commitmentsAndTasks}'),
          ('تحتاج متابعة', '${m.personalNeedsFollowup}'),
        ];
      case 'المستندات':
        return [('مستندات تنتهي خلال 30 يومًا', '${m.expiringDocuments}')];
      case 'الالتزامات المشتركة':
        return [
          ('رحلات نشطة', '${m.sharedActiveTrips}'),
          ('جمعيات مالية نشطة', '${m.sharedActiveCircles}'),
          ('تحتاج متابعة', '${m.sharedNeedsFollowup}'),
        ];
      case 'الأشخاص والجهات':
        return [
          ('عدد الأفراد', '${m.peopleCount}'),
          ('عدد الجهات', '${m.entitiesCount}'),
          ('تحتاج متابعة', '${m.peopleNeedsFollowup}'),
        ];
      case 'العقارات والأنشطة':
        return [
          ('عدد العقارات', '${m.assetsCount}'),
          ('عدد الأنشطة التجارية', '${m.businessCount}'),
          ('عدد المعدات', '${m.equipmentCount}'),
          ('تحتاج متابعة', '${m.assetsNeedsFollowup}'),
        ];
      case 'المواعيد القادمة':
        final now = DateTime.now();
        final upcoming = m.calendarItems
            .where((item) => !item.date.isBefore(DateTime(now.year, now.month, now.day)))
            .take(5)
            .toList(growable: false);
        if (upcoming.isEmpty) {
          return const [('لا توجد مواعيد قادمة', '—')];
        }
        return upcoming
            .map((item) => (item.title, _formatDate(item.date)))
            .toList(growable: false);
      default:
        return const [];
    }
  }

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
    for (final section in _sectionsFor(report)) {
      buffer.writeln('');
      buffer.writeln('■ $section');
      for (final row in _sectionRows(section)) {
        buffer.writeln('  - ${row.$1}: ${row.$2}');
      }
    }
    return buffer.toString();
  }

  // ===== إجراءات التقارير =====

  Future<void> _createReport() async {
    final title = _reportTitleController.text.trim();
    if (title.isEmpty) {
      _toast('الرجاء إدخال عنوان التقرير');
      return;
    }
    // في النمط "عام" تُدرَج كل الأقسام تلقائيًا، وفي "مخصص" لا بد من اختيار
    // قسم واحد على الأقل وإلا كان التقرير فارغًا بلا معنى.
    final isGeneral = _reportMode == 'عام';
    final type = isGeneral ? 'تقرير عام' : _reportType;
    final allowed = _sectionsByType[type] ?? _reportDataFields;
    // يُحتسب ما سيظهر فعليًا (تقاطع المختار مع ما يخصّ النوع) لا مجرد ما
    // نُقر عليه: اختيار أقسام لا تخصّ النوع المحدد كان يُنشئ تقريرًا يمر
    // من التحقق ثم يخرج فارغًا عند العرض.
    final fields = (isGeneral ? _reportDataFields : _selectedDataFields)
        .where(allowed.contains)
        .toList(growable: false);
    if (fields.isEmpty) {
      _toast('اختر قسمًا واحدًا على الأقل يخصّ نوع التقرير المحدد');
      return;
    }
    final report = _GeneratedReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      type: type,
      subject: _reportSubjectController.text.trim(),
      mode: _reportMode,
      fromDate: _reportFromDate,
      toDate: _reportToDate,
      dataFields: fields,
      createdBy: HomeStrings.userName,
      createdAt: DateTime.now(),
    );
    setState(() {
      _recentReports.insert(0, report);
      // تفريغ النموذج بعد الإنشاء حتى لا يُنشئ الضغط التالي نسخة مطابقة
      // دون أن ينتبه المستخدم.
      _reportTitleController.clear();
      _reportSubjectController.clear();
      _reportFromDate = null;
      _reportToDate = null;
    });
    await _persist();
    if (!mounted) return;
    _toast('تم إنشاء التقرير وإضافته إلى آخر التقارير المنشأة');
  }

  Future<void> _archiveReport(_GeneratedReport report) async {
    setState(() {
      _recentReports.removeWhere((item) => item.id == report.id);
      _archivedReports.insert(0, report);
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
        textDirection: TextDirection.rtl,
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
    final sections = _sectionsFor(report);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
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
                      if (_loadingMetrics)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (sections.isEmpty)
                        const Text(
                          'لا توجد أقسام مطابقة لنوع هذا التقرير.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        )
                      else
                        for (final section in sections) ...[
                          _previewSection(section, _sectionRows(section)),
                          const SizedBox(height: 10),
                        ],
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
                            borderRadius: BorderRadius.circular(12),
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

  Widget _previewSection(String title, List<(String, String)> rows) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6ECF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_GeneratedReport> get _filteredArchivedReports {
    return _archivedReports
        .where((report) {
          final query = _archiveSearchController.text.trim();
          final subjectFilter = _archiveSubjectController.text.trim();
          final creatorFilter = _archiveCreatorController.text.trim();

          // مطابقة موحّدة عربيًا مثل باقي شاشات التطبيق.
          final matchesQuery =
              query.isEmpty ||
              matchesSearchQuery(
                query: query,
                fields: [
                  report.title,
                  report.type,
                  report.subject,
                  report.createdBy,
                  _formatDate(report.createdAt),
                ],
              );

          final matchesType =
              _archiveTypeFilter == 'الكل' || report.type == _archiveTypeFilter;
          final matchesSubject =
              subjectFilter.isEmpty ||
              matchesSearchQuery(
                query: subjectFilter,
                fields: [report.subject],
              );
          final matchesCreator =
              creatorFilter.isEmpty ||
              matchesSearchQuery(
                query: creatorFilter,
                fields: [report.createdBy],
              );
          final matchesFrom =
              _archiveFromDate == null ||
              !report.createdAt.isBefore(_archiveFromDate!);
          final matchesTo =
              _archiveToDate == null ||
              !report.createdAt.isAfter(
                DateTime(
                  _archiveToDate!.year,
                  _archiveToDate!.month,
                  _archiveToDate!.day,
                  23,
                  59,
                  59,
                ),
              );

          return matchesQuery &&
              matchesType &&
              matchesSubject &&
              matchesCreator &&
              matchesFrom &&
              matchesTo;
        })
        .toList(growable: false);
  }

  bool get _hasArchiveFilters =>
      _archiveSearchController.text.trim().isNotEmpty ||
      _archiveSubjectController.text.trim().isNotEmpty ||
      _archiveCreatorController.text.trim().isNotEmpty ||
      _archiveTypeFilter != 'الكل' ||
      _archiveFromDate != null ||
      _archiveToDate != null;

  // ===== عناصر الواجهة =====

  Widget _statChip(IconData icon, String label, int value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: _accent),
            const SizedBox(height: 5),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
    final sectionsCount = _sectionsFor(report).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
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
                              'الموضوع: ${report.subject}',
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
                      Icons.layers_outlined,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$sectionsCount أقسام',
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
                      tooltip: 'مشاركة / تصدير',
                      onPressed: () => _handleReportAction(report, 'share'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات',
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
                            child: Text('استعادة من الأرشيف'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'archive',
                            child: Text('أرشفة التقرير'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'حذف',
                            style: TextStyle(color: Color(0xFFEF4444)),
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

  /// نسخة بلا عنوان عائم: تمرير labelText: null إلى copyWith لا يمسح
  /// العنوان (لأنها تستخدم `?? this.labelText`)، فيبقى عنوان فارغ يشغل
  /// مساحة ويُخفي النص الإرشادي حتى يُركَّز على الحقل.
  InputDecoration _searchDecoration(String hint) =>
      _baseDecoration().copyWith(hintText: hint);

  InputDecoration _fieldDecoration(String label) =>
      _baseDecoration().copyWith(labelText: label);

  InputDecoration _baseDecoration() => InputDecoration(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _accent, width: 1.4),
    ),
  );

  Widget _buildReportsTab() {
    final isGeneral = _reportMode == 'عام';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            _statChip(
              Icons.description_outlined,
              'تقارير نشطة',
              _recentReports.length,
            ),
            const SizedBox(width: 10),
            _statChip(
              Icons.inventory_2_outlined,
              'مؤرشفة',
              _archivedReports.length,
            ),
            const SizedBox(width: 10),
            _statChip(
              Icons.layers_outlined,
              'أقسام متاحة',
              _reportDataFields.length,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle('إنشاء تقرير جديد'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'عام',
                    label: Text('تقرير عام'),
                    icon: Icon(Icons.auto_awesome_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'مخصص',
                    label: Text('تقرير مخصص'),
                    icon: Icon(Icons.tune_rounded, size: 16),
                  ),
                ],
                selected: {_reportMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _reportMode = selection.first),
              ),
              const SizedBox(height: 6),
              Text(
                isGeneral
                    ? 'التقرير العام يشمل كل الأقسام المتاحة تلقائيًا.'
                    : 'اختر نوع التقرير والأقسام التي تريد إظهارها.',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reportTitleController,
                decoration: _fieldDecoration('عنوان التقرير'),
              ),
              // في النمط العام لا معنى لاختيار نوع أو أقسام، فتُخفى هذه
              // الحقول بدل تركها ظاهرة دون أي أثر على الناتج.
              if (!isGeneral) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _reportType,
                  isExpanded: true,
                  decoration: _fieldDecoration('نوع التقرير'),
                  items: _reportTypes
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _reportType = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reportSubjectController,
                  decoration: _fieldDecoration('الموضوع / التصنيف (اختياري)'),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(
                        initial: _reportFromDate,
                        onSelected: (value) =>
                            setState(() => _reportFromDate = value),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        _reportFromDate == null
                            ? 'من تاريخ'
                            : 'من: ${_formatDate(_reportFromDate!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(
                        initial: _reportToDate,
                        onSelected: (value) =>
                            setState(() => _reportToDate = value),
                      ),
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _reportToDate == null
                            ? 'إلى تاريخ'
                            : 'إلى: ${_formatDate(_reportToDate!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isGeneral) ...[
                const SizedBox(height: 12),
                const Text(
                  'الأقسام المطلوب إظهارها',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reportDataFields.map((item) {
                    // الأقسام التي لا تخصّ النوع المختار تُعطَّل بدل أن
                    // تُختار ثم تُحذف بصمت عند بناء التقرير.
                    final allowed =
                        (_sectionsByType[_reportType] ?? _reportDataFields)
                            .contains(item);
                    return FilterChip(
                      label: Text(item),
                      selected: allowed && _selectedDataFields.contains(item),
                      onSelected: !allowed
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _selectedDataFields.add(item);
                              } else {
                                _selectedDataFields.remove(item);
                              }
                            }),
                    );
                  }).toList(growable: false),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _createReport,
                icon: const Icon(Icons.post_add_rounded, size: 18),
                label: const Text('إنشاء التقرير'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DocumentTemplatesScreen()),
          ),
          icon: const Icon(Icons.folder_copy_outlined, size: 18),
          label: const Text('نماذج المستندات والإيصالات'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle(
          'آخر التقارير المنشأة',
          trailing: _recentReports.isEmpty ? null : '${_recentReports.length}',
        ),
        if (_recentReports.isEmpty)
          _emptyCard(
            Icons.description_outlined,
            'لا توجد تقارير منشأة بعد.\nأنشئ تقريرك الأول من النموذج أعلاه.',
          )
        else
          ..._recentReports.map(
            (report) => _buildReportRow(report, archived: false),
          ),
      ],
    );
  }

  Widget _buildArchiveTab() {
    final archivedItems = _filteredArchivedReports;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        TextField(
          controller: _archiveSearchController,
          focusNode: _archiveSearchFocus,
          onChanged: (_) => setState(() {}),
          decoration: _searchDecoration(
            'ابحث بالاسم أو النوع أو التاريخ أو المنشئ',
          ).copyWith(
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _archiveSearchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(
                      () => _archiveSearchController.clear(),
                    ),
                  ),
          ),
        ),
        _buildArchiveSuggestions(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _archiveTypeFilter,
                isExpanded: true,
                decoration: _fieldDecoration('نوع التقرير'),
                items: ['الكل', ..._reportTypes]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _archiveTypeFilter = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _archiveSubjectController,
                onChanged: (_) => setState(() {}),
                decoration: _fieldDecoration('الموضوع'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _archiveCreatorController,
                onChanged: (_) => setState(() {}),
                decoration: _fieldDecoration('المستخدم الذي أنشأه'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(
                        initial: _archiveFromDate,
                        onSelected: (value) =>
                            setState(() => _archiveFromDate = value),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        _archiveFromDate == null
                            ? 'من تاريخ'
                            : 'من: ${_formatDate(_archiveFromDate!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(
                        initial: _archiveToDate,
                        onSelected: (value) =>
                            setState(() => _archiveToDate = value),
                      ),
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _archiveToDate == null
                            ? 'إلى تاريخ'
                            : 'إلى: ${_formatDate(_archiveToDate!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              // زر مسح الفلاتر يظهر فقط عند وجود فلتر فعّال — كان ظاهرًا
              // دائمًا حتى حين لا يوجد ما يُمسح.
              if (_hasArchiveFilters) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _archiveSearchController.clear();
                      _archiveSubjectController.clear();
                      _archiveCreatorController.clear();
                      _archiveTypeFilter = 'الكل';
                      _archiveFromDate = null;
                      _archiveToDate = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                    label: const Text('مسح الفلاتر'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle(
          'العناصر المؤرشفة',
          trailing: _archivedReports.isEmpty
              ? null
              : '${archivedItems.length} من ${_archivedReports.length}',
        ),
        if (archivedItems.isEmpty)
          _emptyCard(
            Icons.inventory_2_outlined,
            _archivedReports.isEmpty
                ? 'لا توجد عناصر مؤرشفة بعد.\nأرشف أي تقرير من قائمة التقارير.'
                : 'لا توجد عناصر مؤرشفة تطابق معايير البحث.',
          )
        else
          ...archivedItems.map(
            (report) => _buildReportRow(report, archived: true),
          ),
      ],
    );
  }

  /// اقتراحات إكمال لبحث الأرشيف بمجرد كتابة حرفين، من عناوين التقارير
  /// المؤرشفة نفسها — بنفس سلوك بقية خانات البحث في التطبيق.
  Widget _buildArchiveSuggestions() {
    if (!_archiveSearchFocus.hasFocus) return const SizedBox.shrink();
    final values = searchSuggestionsFor(
      query: _archiveSearchController.text,
      candidates: _archivedReports.map((report) => report.title),
    );
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
              InkWell(
                onTap: () {
                  final value = values[i];
                  _archiveSearchController.text = value;
                  _archiveSearchController.selection =
                      TextSelection.collapsed(offset: value.length);
                  _archiveSearchFocus.unfocus();
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          values[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // الاتجاه مفروض على الـScaffold كاملًا (وليس على الجسم فقط) حتى يبدأ
    // شريط التبويبات من اليمين: "التقارير" أولًا ثم "الأرشيف". كان الشريط
    // خارج نطاق الاتجاه فيظهر معكوسًا.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F8FC),
          appBar: AppBar(
            title: const Text(
              'التقارير / الأرشيف',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            foregroundColor: const Color(0xFF0F172A),
            elevation: 0,
            bottom: const TabBar(
              labelColor: _accent,
              unselectedLabelColor: Color(0xFF94A3B8),
              indicatorColor: _accent,
              indicatorWeight: 2.6,
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
  late final List<_DelegationRecord> _delegations = [
    _DelegationRecord(
      delegateName: 'أحمد محمد',
      delegationType: 'الالتزامات المالية',
      permissions: const ['عرض البيانات', 'إضافة السجلات', 'تعديل السجلات'],
      startDate: DateTime.now().subtract(const Duration(days: 45)),
      endDate: DateTime.now().add(const Duration(days: 180)),
      active: true,
    ),
    _DelegationRecord(
      delegateName: 'شركة الأمان',
      delegationType: 'العقارات والمشاريع',
      permissions: const ['عرض البيانات'],
      startDate: DateTime.now().subtract(const Duration(days: 120)),
      endDate: DateTime.now().add(const Duration(days: 14)),
      active: true,
    ),
    _DelegationRecord(
      delegateName: 'سارة عبدالله',
      delegationType: 'العقارات والمشاريع',
      permissions: const ['عرض البيانات', 'تعديل السجلات'],
      startDate: DateTime.now().subtract(const Duration(days: 90)),
      endDate: DateTime.now().add(const Duration(days: 90)),
      active: false,
    ),
  ];

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

  List<_DelegationRecord> _filteredDelegations() {
    if (_selectedFilter == 'active') {
      return _delegations
          .where((d) => _isActive(d) && !_isExpiringSoon(d))
          .toList(growable: false);
    }
    if (_selectedFilter == 'expiring') {
      return _delegations.where(_isExpiringSoon).toList(growable: false);
    }
    if (_selectedFilter == 'ended') {
      return _delegations.where(_isEnded).toList(growable: false);
    }
    if (_selectedFilter == 'paused') {
      return _delegations
          .where((d) => !d.active && !_isEnded(d))
          .toList(growable: false);
    }
    return List<_DelegationRecord>.from(_delegations);
  }

  Future<void> _openCreateSheet({
    _DelegationRecord? existing,
    int? index,
  }) async {
    final delegateController = TextEditingController(
      text: existing?.delegateName ?? '',
    );
    final types = const [
      'الالتزامات المالية',
      'العقارات والمشاريع',
      'الأفراد والجهات',
      'جميع الوحدات',
    ];
    String selectedType = existing?.delegationType ?? types.first;
    final allPermissions = const [
      'عرض البيانات',
      'إضافة السجلات',
      'تعديل السجلات',
      'حذف السجلات',
      'اعتماد العمليات',
    ];
    final selectedPermissions = <String>{
      ...?existing?.permissions,
      if (existing == null) 'عرض البيانات',
    };
    DateTime startDate = existing?.startDate ?? DateTime.now();
    DateTime endDate =
        existing?.endDate ?? DateTime.now().add(const Duration(days: 365));
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
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
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            hintText: 'اكتب اسم الشخص أو الجهة',
                            filled: true,
                            fillColor: const Color(0xFFF7F9F8),
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
                            fillColor: const Color(0xFFF7F9F8),
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
                            setModalState(() => selectedType = v);
                          },
                        ),
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
                                      }
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
                          onPressed: () {
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
                              delegateName: name,
                              delegationType: selectedType,
                              permissions: selectedPermissions.toList(
                                growable: false,
                              ),
                              startDate: startDate,
                              endDate: endDate,
                              active: existing?.active ?? true,
                            );
                            setState(() {
                              if (index != null && existing != null) {
                                _delegations[index] = record;
                              } else {
                                _delegations.insert(0, record);
                              }
                              _selectedFilter = 'all';
                            });
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF087F6A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
    final activeCount = _delegations.where(_isActive).length;
    final expiringCount = _delegations.where(_isExpiringSoon).length;
    final pausedCount = _delegations
        .where((d) => !d.active && !_isEnded(d))
        .length;
    final filtered = _filteredDelegations();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'التفويضات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F9F8),
        surfaceTintColor: Colors.transparent,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              key: const ValueKey('delegations-overview'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F3F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBE3DD)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF087F6A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'من يمكنه إدارة أعمالك؟',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF173B35),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'حدد الشخص أو الجهة، نطاق الإدارة، الصلاحيات، ومدة الوصول.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: Color(0xFF52716B),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          '${_delegations.length} تفويضات مسجلة',
                          style: const TextStyle(
                            fontSize: 11,
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
            Row(
              children: [
                Expanded(
                  child: _DelegationStatCard(
                    value: '$activeCount',
                    label: 'سارية الآن',
                    color: const Color(0xFF07835C),
                    icon: Icons.verified_user_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DelegationStatCard(
                    value: '$expiringCount',
                    label: 'قريبة الانتهاء',
                    color: const Color(0xFFD97706),
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DelegationStatCard(
                    value: '$pausedCount',
                    label: 'موقوفة',
                    color: const Color(0xFFDC2626),
                    icon: Icons.pause_circle_outline_rounded,
                  ),
                ),
              ],
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'إنشاء تفويض جديد',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'التفويضات المسجلة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF24332F),
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _DelegationFilterChip(
                  key: const ValueKey('delegation-filter-all'),
                  label: 'الكل',
                  count: _delegations.length,
                  selected: _selectedFilter == 'all',
                  onTap: () => setState(() => _selectedFilter = 'all'),
                ),
                _DelegationFilterChip(
                  key: const ValueKey('delegation-filter-active'),
                  label: 'النشطة',
                  count: activeCount - expiringCount,
                  selected: _selectedFilter == 'active',
                  onTap: () => setState(() => _selectedFilter = 'active'),
                ),
                _DelegationFilterChip(
                  key: const ValueKey('delegation-filter-expiring'),
                  label: 'قريبة الانتهاء',
                  count: expiringCount,
                  selected: _selectedFilter == 'expiring',
                  onTap: () => setState(() => _selectedFilter = 'expiring'),
                ),
                _DelegationFilterChip(
                  key: const ValueKey('delegation-filter-paused'),
                  label: 'الموقوفة',
                  count: pausedCount,
                  selected: _selectedFilter == 'paused',
                  onTap: () => setState(() => _selectedFilter = 'paused'),
                ),
                _DelegationFilterChip(
                  key: const ValueKey('delegation-filter-ended'),
                  label: 'المنتهية',
                  count: _delegations.where(_isEnded).length,
                  selected: _selectedFilter == 'ended',
                  onTap: () => setState(() => _selectedFilter = 'ended'),
                ),
              ],
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
                  key: ValueKey('delegation-${item.delegateName}'),
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
                  onAction: (action) {
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
                      setState(() {
                        _delegations[sourceIndex] = item.copyWith(
                          active: !item.active,
                        );
                      });
                      return;
                    }
                    if (action == 'delete') {
                      setState(() => _delegations.removeAt(sourceIndex));
                    }
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _DelegationRecord {
  const _DelegationRecord({
    required this.delegateName,
    required this.delegationType,
    required this.permissions,
    required this.startDate,
    required this.endDate,
    required this.active,
  });

  final String delegateName;
  final String delegationType;
  final List<String> permissions;
  final DateTime startDate;
  final DateTime endDate;
  final bool active;

  _DelegationRecord copyWith({
    String? delegateName,
    String? delegationType,
    List<String>? permissions,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
  }) {
    return _DelegationRecord(
      delegateName: delegateName ?? this.delegateName,
      delegationType: delegationType ?? this.delegationType,
      permissions: permissions ?? this.permissions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      active: active ?? this.active,
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8E6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
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
                      tooltip: 'خيارات التفويض',
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
                    color: const Color(0xFFF7F9F8),
                    borderRadius: BorderRadius.circular(9),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8E6)),
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

class _DelegationStatCard extends StatelessWidget {
  const _DelegationStatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegationFilterChip extends StatelessWidget {
  const _DelegationFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE6E9FF) : Colors.white,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            '$label  $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected
                  ? const Color(0xFF4338CA)
                  : const Color(0xFF475569),
            ),
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text(
          'تفاصيل التفويض',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F9F8),
        surfaceTintColor: Colors.transparent,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EBE9)),
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

class _ArchiveHubPage extends StatelessWidget {
  const _ArchiveHubPage();

  @override
  Widget build(BuildContext context) {
    const archiveSections = [
      (
        'الالتزامات المؤرشفة',
        '14 عنصر',
        Icons.inventory_2_outlined,
        Color(0xFF6366F1),
      ),
      (
        'الاشتراكات المنتهية',
        '6 عناصر',
        Icons.event_busy_outlined,
        Color(0xFFEA580C),
      ),
      (
        'المستندات القديمة',
        '21 ملف',
        Icons.folder_open_outlined,
        Color(0xFF0EA5A8),
      ),
      ('دفعات مكتملة', '33 عملية', Icons.paid_outlined, Color(0xFF16A34A)),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(title: const Text('الأرشيف'), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            const Text(
              'استرجاع ومراجعة العناصر السابقة بسرعة',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            ...archiveSections.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Icon(item.$3, color: item.$4, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.$4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletsHubPage extends StatelessWidget {
  const _WalletsHubPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(title: const Text('المحافظ'), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            const Text(
              'لوحة احترافية للأموال والبطاقات والدفعات والخطط والاشتراكات',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الرصيد الكلي',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '128,400 درهم',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.credit_card_rounded, color: Color(0xFF93C5FD)),
                      SizedBox(width: 6),
                      Text(
                        '4 بطاقات نشطة',
                        style: TextStyle(
                          color: Color(0xFFDBEAFE),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _WalletStatTile(
              title: 'دفعات هذا الأسبوع',
              value: '12 دفعة',
              subtitle: '4 دفعات قادمة خلال يومين',
              icon: Icons.payments_rounded,
              color: Color(0xFF0EA5E9),
            ),
            const _WalletStatTile(
              title: 'الخطة المالية',
              value: '83% التزام',
              subtitle: 'ضمن الميزانية الشهرية المحددة',
              icon: Icons.track_changes_outlined,
              color: Color(0xFF16A34A),
            ),
            const _WalletStatTile(
              title: 'الاشتراكات',
              value: '9 اشتراكات',
              subtitle: 'اشتراكان قريبان للتجديد',
              icon: Icons.subscriptions_outlined,
              color: Color(0xFF7C3AED),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletStatTile extends StatelessWidget {
  const _WalletStatTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 21),
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
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage();

  @override
  Widget build(BuildContext context) {
    const accountItems = [
      ('الملف الشخصي', Icons.person_outline_rounded),
      ('الأمان وتغيير كلمة المرور', Icons.lock_outline_rounded),
      ('طرق الدفع والمحافظ', Icons.account_balance_wallet_outlined),
      ('إدارة الاشتراكات', Icons.subscriptions_outlined),
      ('اللغة والمظهر', Icons.palette_outlined),
      ('الخصوصية والصلاحيات', Icons.verified_user_outlined),
      ('المساعدة والدعم', Icons.support_agent_outlined),
      ('تسجيل الخروج', Icons.logout_rounded),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(title: const Text('الحساب'), centerTitle: true),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFFDBEAFE),
                    child: Icon(Icons.person_rounded, color: Color(0xFF1D4ED8)),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'عبدالعزيز',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'حسابك جاهز لإدارة كل التزاماتك',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...accountItems.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  leading: Icon(item.$2, color: const Color(0xFF334155)),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  title: Text(
                    item.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
