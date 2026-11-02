import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import '../data/page_customization_store.dart';
import '../widgets/shared/app_design.dart';
import 'home_layout_settings_screen.dart';

/// «تخصيص الصفحات»: الصفحة الرئيسية كما كانت، ثم الصفحات الأربع — في كل
/// صفحة تُخفى فئة كاملة أو عناصر محددة داخلها.
class PagesCustomizationScreen extends StatefulWidget {
  const PagesCustomizationScreen({super.key});

  @override
  State<PagesCustomizationScreen> createState() =>
      _PagesCustomizationScreenState();
}

class _PagesCustomizationScreenState extends State<PagesCustomizationScreen> {
  static const _icons = {
    PageCustomizationStore.personal: Icons.person_outline_rounded,
    PageCustomizationStore.shared: Icons.groups_2_outlined,
    PageCustomizationStore.people: Icons.people_alt_outlined,
    PageCustomizationStore.assets: Icons.apartment_rounded,
  };

  static const _colors = {
    PageCustomizationStore.personal: Color(0xFF0E7161),
    PageCustomizationStore.shared: Color(0xFF34A894),
    PageCustomizationStore.people: Color(0xFF5C6B68),
    PageCustomizationStore.assets: Color(0xFFF2A93F),
  };

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Widget _tile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            textDirection: AppTr.uiDir,
            children: [
              AppIconTile(
                icon: icon,
                color: color,
                size: AppTheme.iconTileSmall,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const AppChevron(size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('تخصيص الصفحات', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
              child: Text(
                'اختر الصفحة التي تريد تخصيصها: أخفِ ما لا تستخدمه من فئات، '
                'ويعود كل شيء متى أظهرته.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
            _tile(
              title: 'تخصيص الصفحة الرئيسية',
              subtitle: 'إخفاء الأقسام التي لا تستخدمها وترتيبها',
              icon: Icons.home_outlined,
              color: AppTheme.brand,
              onTap: () => _open(const HomeLayoutSettingsScreen()),
            ),
            for (final page in PageCustomizationStore.pages)
              _tile(
                title: 'تخصيص صفحة '
                    '${PageCustomizationStore.pageTitles[page] ?? page}',
                subtitle: PageCustomizationStore.hiddenCount(page) == 0
                    ? 'كل الفئات والعناصر ظاهرة'
                    : 'المخفي: ${PageCustomizationStore.hiddenCount(page)}',
                icon: _icons[page] ?? Icons.tune_rounded,
                color: _colors[page] ?? AppTheme.brandMid,
                onTap: () => _open(PageCategoriesScreen(page: page)),
              ),
          ],
        ),
      ),
    );
  }
}

/// تخصيص صفحة واحدة: مفتاح لكل فئة، وتحتها مفاتيح عناصرها.
class PageCategoriesScreen extends StatefulWidget {
  const PageCategoriesScreen({super.key, required this.page});

  final String page;

  @override
  State<PageCategoriesScreen> createState() => _PageCategoriesScreenState();
}

class _PageCategoriesScreenState extends State<PageCategoriesScreen> {
  final Set<String> _expanded = {};

  String get _page => widget.page;

  List<PageCategoryDef> get _categories =>
      PageCustomizationStore.catalog[_page] ?? const [];

  Future<void> _toggleCategory(String category, bool visible) async {
    // فئة واحدة على الأقل تبقى ظاهرة حتى لا تفرغ الصفحة.
    final visibleCount = _categories
        .where(
          (c) => !PageCustomizationStore.categoryHidden(_page, c.title),
        )
        .length;
    if (!visible && visibleCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب أن تبقى فئة واحدة على الأقل ظاهرة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    await PageCustomizationStore.setCategoryHidden(_page, category, !visible);
    if (mounted) setState(() {});
  }

  Future<void> _toggleItem(String category, String item, bool visible) async {
    HapticFeedback.selectionClick();
    await PageCustomizationStore.setItemHidden(
      _page,
      category,
      item,
      !visible,
    );
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    final ok = await confirmAction(
      context,
      title: 'إظهار الكل',
      message: 'ستظهر كل الفئات والعناصر في هذه الصفحة.',
      confirmLabel: 'إظهار الكل',
    );
    if (!ok) return;
    await PageCustomizationStore.reset(_page);
    if (mounted) setState(() {});
  }

  Widget _switch(bool value, ValueChanged<bool> onChanged) => Switch(
    value: value,
    activeThumbColor: Colors.white,
    activeTrackColor: AppTheme.brandMid,
    onChanged: onChanged,
  );

  Widget _categoryCard(PageCategoryDef category) {
    final visible = !PageCustomizationStore.categoryHidden(
      _page,
      category.title,
    );
    final hiddenItems = category.items
        .where(
          (item) => PageCustomizationStore.itemHiddenAlone(
            _page,
            category.title,
            item,
          ),
        )
        .length;
    final open = _expanded.contains(category.title);
    final hasItems = category.items.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            onTap: hasItems && visible
                ? () => setState(() {
                    if (!_expanded.remove(category.title)) {
                      _expanded.add(category.title);
                    }
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: Row(
                textDirection: AppTr.uiDir,
                children: [
                  _switch(visible, (v) => _toggleCategory(category.title, v)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          category.title,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: visible ? AppTheme.title : AppTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          !visible
                              ? 'الفئة كلها مخفية'
                              : !hasItems
                              ? 'ظاهرة في الصفحة'
                              : hiddenItems == 0
                              ? 'كل العناصر ظاهرة (${category.items.length})'
                              : 'مخفي $hiddenItems من ${category.items.length}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasItems && visible)
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.chevron,
                    ),
                ],
              ),
            ),
          ),
          if (hasItems && visible && open) ...[
            const Divider(height: 1, color: AppTheme.hairline),
            for (final item in category.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 22, 0),
                child: Row(
                  textDirection: AppTr.uiDir,
                  children: [
                    _switch(
                      !PageCustomizationStore.itemHiddenAlone(
                        _page,
                        category.title,
                        item,
                      ),
                      (v) => _toggleItem(category.title, item, v),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.title,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: Text(
          PageCustomizationStore.pageTitles[_page] ?? '',
          style: AppTheme.cardTitle,
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: AppTr.tr('إظهار الكل'),
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
              child: Text(
                'أخفِ الفئة كاملة بمفتاحها. المخفي يختفي من الصفحة وقوائم '
                'الإضافة والعدّادات، وبياناته لا تُحذف.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                ),
              ),
            ),
            for (final category in _categories) _categoryCard(category),
          ],
        ),
      ),
    );
  }
}
