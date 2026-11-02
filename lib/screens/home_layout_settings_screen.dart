import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import '../data/home_layout_store.dart';
import '../widgets/shared/app_design.dart';

/// تخصيص الصفحة الرئيسية: إظهار/إخفاء كل قسم وترتيبه بالسحب.
class HomeLayoutSettingsScreen extends StatefulWidget {
  const HomeLayoutSettingsScreen({super.key});

  @override
  State<HomeLayoutSettingsScreen> createState() =>
      _HomeLayoutSettingsScreenState();
}

class _HomeLayoutSettingsScreenState extends State<HomeLayoutSettingsScreen> {
  List<String> _order = List<String>.of(HomeLayoutStore.defaultOrder);
  Set<String> _hidden = <String>{};
  bool _loading = true;

  static const _icons = {
    HomeLayoutStore.personal: Icons.person_outline_rounded,
    HomeLayoutStore.shared: Icons.groups_2_outlined,
    HomeLayoutStore.people: Icons.people_alt_outlined,
    HomeLayoutStore.assets: Icons.apartment_rounded,
  };

  static const _colors = {
    HomeLayoutStore.personal: Color(0xFF0E7161),
    HomeLayoutStore.shared: Color(0xFF34A894),
    HomeLayoutStore.people: Color(0xFF5C6B68),
    HomeLayoutStore.assets: Color(0xFFF2A93F),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final layout = await HomeLayoutStore.load();
    if (!mounted) return;
    setState(() {
      _order = List<String>.of(layout.order);
      _hidden = Set<String>.of(layout.hidden);
      _loading = false;
    });
  }

  Future<void> _persist() => HomeLayoutStore.save(_order, _hidden);

  void _toggle(String id, bool visible) {
    // قسم واحد على الأقل يبقى ظاهرًا حتى لا تفرغ الرئيسية.
    if (!visible && _order.length - _hidden.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب أن يبقى قسم واحد على الأقل ظاهرًا'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (visible) {
        _hidden.remove(id);
      } else {
        _hidden.add(id);
      }
    });
    _persist();
  }

  void _move(String id, int delta) {
    final from = _order.indexOf(id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _order.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _order.removeAt(from);
      _order.insert(to, id);
    });
    _persist();
  }

  Future<void> _reset() async {
    final ok = await confirmAction(
      context,
      title: 'استعادة الترتيب الافتراضي',
      message: 'ستظهر كل الأقسام بترتيبها الأصلي.',
      confirmLabel: 'استعادة',
    );
    if (!ok) return;
    await HomeLayoutStore.reset();
    if (!mounted) return;
    setState(() {
      _order = List<String>.of(HomeLayoutStore.defaultOrder);
      _hidden = <String>{};
    });
  }

  Widget _row(String id, int index) {
    final visible = !_hidden.contains(id);
    final color = _colors[id] ?? AppTheme.brandMid;
    return Container(
      key: ValueKey('home-layout-$id'),
      margin: const EdgeInsets.only(bottom: AppTheme.cardGap),
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: AppTheme.chevron,
              ),
            ),
          ),
          Opacity(
            opacity: visible ? 1 : 0.4,
            child: AppIconTile(
              icon: _icons[id] ?? Icons.widgets_outlined,
              color: color,
              size: AppTheme.iconTileSmall,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  HomeLayoutStore.titles[id] ?? id,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: visible ? AppTheme.title : AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  visible ? 'ظاهر في الرئيسية' : 'مخفي من الرئيسية',
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
          IconButton(
            tooltip: AppTr.tr('أعلى'),
            visualDensity: VisualDensity.compact,
            onPressed: index == 0 ? null : () => _move(id, -1),
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: AppTr.tr('أسفل'),
            visualDensity: VisualDensity.compact,
            onPressed: index == _order.length - 1 ? null : () => _move(id, 1),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          Switch(
            value: visible,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.brandMid,
            onChanged: (value) => _toggle(id, value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('تخصيص الصفحة الرئيسية', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: AppTr.tr('استعادة الترتيب الافتراضي'),
            onPressed: _loading ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: Text(
                      'أخفِ الأقسام التي لا تستخدمها، ورتّبها بالسحب أو '
                      'بالأسهم؛ يظهر الترتيب نفسه في الصفحة الرئيسية.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        if (oldIndex == newIndex) return;
                        setState(() {
                          final id = _order.removeAt(oldIndex);
                          _order.insert(newIndex, id);
                        });
                        _persist();
                      },
                      children: [
                        for (var i = 0; i < _order.length; i++)
                          _row(_order[i], i),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
