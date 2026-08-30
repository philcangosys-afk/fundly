import 'package:flutter/material.dart';

import 'app_design.dart';

/// رأس مثبَّت (sticky) يقيس ارتفاع محتواه الفعلي وقت التشغيل.
///
/// خلفية هذا المكوّن: جرى سابقًا تثبيت صف "الفئات" عبر
/// `SliverPersistentHeader` بارتفاع **ثابت مفترض**، فنتجت شاشة بيضاء فارغة
/// (انظر التعليق في personal_commitments_screen.dart)، وتم التراجع عن
/// التثبيت انتظارًا لآلية "تقيس الارتفاع الفعلي بدل افتراضه". هذا المكوّن
/// هو تلك الآلية.
///
/// كيف يعمل بأمان:
///  • في أول إطار يُعرض المحتوى كعنصر عادي ([SliverToBoxAdapter]) يأخذ
///    حجمه الطبيعي — أي أن السلوك في أسوأ الأحوال مطابق تمامًا للسلوك
///    الآمن الحالي، ولا يمكن أن ينتج عنه شاشة فارغة.
///  • بعد اكتمال الإطار يُقاس الارتفاع الحقيقي، ثم يُعاد البناء كرأس
///    مثبَّت بذلك الارتفاع بالضبط.
///  • داخل الرأس المثبَّت يُلَفّ المحتوى بـ[OverflowBox] + [ClipRect]، فلو
///    نما المحتوى لاحقًا (تغيّر عدد الفئات مثلًا) يُقصّ بصريًا بدل أن يرمي
///    استثناء تجاوز حدود، ثم تُصحَّح القياسات في الإطار التالي.
class MeasuredPinnedHeader extends StatefulWidget {
  const MeasuredPinnedHeader({
    super.key,
    required this.child,
    this.background = AppTheme.page,
  });

  final Widget child;

  /// خلفية صريحة مطلوبة: الرأس المثبَّت يطفو فوق المحتوى المتحرّك تحته،
  /// وبدون خلفية معتمة يظهر النص متراكبًا مع البطاقات المارّة خلفه.
  final Color background;

  @override
  State<MeasuredPinnedHeader> createState() => _MeasuredPinnedHeaderState();
}

class _MeasuredPinnedHeaderState extends State<MeasuredPinnedHeader> {
  final GlobalKey _measureKey = GlobalKey();
  double? _height;

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _measureKey.currentContext;
      if (context == null) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final measured = box.size.height;
      if (measured <= 0) return;
      if (_height == null || (_height! - measured).abs() > 0.5) {
        setState(() => _height = measured);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: widget.background,
      child: KeyedSubtree(key: _measureKey, child: widget.child),
    );

    // يُعاد القياس في كل إطار: المحتوى داخل الرأس المثبَّت يُبنى بارتفاع
    // غير محدود (OverflowBox) فيُقاس دائمًا بحجمه الطبيعي لا بالارتفاع
    // المثبَّت، لذا يصحّح نفسه تلقائيًا إن تغيّر المحتوى (دوران الشاشة أو
    // تكبير الخط أو نص يلتفّ لسطرين). شرط الفرق (> 0.5) يمنع أي تذبذب.
    _scheduleMeasure();

    // لم يُقَس بعد: يُعرض كعنصر عادي بحجمه الطبيعي (السلوك الآمن).
    if (_height == null) {
      return SliverToBoxAdapter(child: content);
    }

    return SliverPersistentHeader(
      pinned: true,
      delegate: _MeasuredHeaderDelegate(
        height: _height!,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _MeasuredHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _MeasuredHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    // ظل خفيف يفصل الشريط المثبَّت عن المحتوى المارّ تحته، بنفس سلوك
    // ManagementPinnedControls السابق.
    elevation: overlapsContent ? 2 : 0,
    color: Colors.transparent,
    child: SizedBox(height: height, child: child),
  );

  @override
  bool shouldRebuild(_MeasuredHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
