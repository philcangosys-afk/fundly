import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';

import '../data/app_settings.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/app_design.dart';
import 'settings_detail_screens.dart' show ContactUsPage;

/// سعر الهدية (الباقة الذهبية) — الأسعار كلها في [PlanAccess.plans].
final int kMonthlyPlanPrice = PlanAccess.gold.monthly;
final int kYearlyPlanPrice = PlanAccess.gold.yearly;

/// الاشتراكات الشهرية والسنوية والهدايا.
///
/// بوابة الدفع (Google Play Billing / خادم الاشتراكات) غير مربوطة بعد،
/// لذا لا تُفعِّل هذه الشاشة اشتراكًا ولا تتحقق من أكواد الهدايا؛ كل زر
/// دفع يوضّح ذلك بدل أن يوهم المستخدم بعملية تمّت.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  bool _yearly = true;

  /// الباقة المعروضة تفاصيلها (تبدأ بالحالية).
  late String _shownPlan = PlanAccess.current.id;

  String get _currency => AppSettings.currencySuffix;

  Future<void> _paymentNotice(String title) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 36,
                  color: AppTheme.goldDark,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'الدفع داخل التطبيق لم يُفعَّل بعد. ستعمل الاشتراكات '
                  'والهدايا فور ربط بوابة الدفع، ولن يُخصم منك أي مبلغ الآن.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.body,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                  ),
                  child: const Text(
                    'حسنًا',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, Color? color, Color? border}) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sLg),
      decoration: BoxDecoration(
        color: color ?? AppTheme.paper,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: border ?? AppTheme.hairline),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: AppTheme.title,
      ),
    ),
  );

  Widget _currentPlan() {
    final plan = PlanAccess.current;
    final settings = AppSettings.instance;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      Row(
        textDirection: AppTr.uiDir,
        children: [
          AppIconTile(icon: plan.icon, color: plan.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'باقتك الحالية',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  plan.name,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: plan.color,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: plan.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: Text(
              'مفعّلة',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: plan.color,
              ),
            ),
          ),
        ],
      ),
          // مدة الاشتراك والتجديد: يظهران متى كان هناك اشتراك بمدة.
          if (settings.hasPlanPeriod) ...[
            const SizedBox(height: 12),
            _periodRow('بدأ في', settings.planStartLabel),
            _periodRow(
              settings.planIsGift || !settings.planAutoRenew
                  ? 'ينتهي في'
                  : 'يتجدد تلقائيًا في',
              settings.planEndLabel,
            ),
            _periodRow(
              'المدة',
              AppTr.tr(settings.planYearly ? 'سنوي' : 'شهري'),
            ),
            _periodRow(
              'التجديد التلقائي',
              AppTr.tr(
                settings.planIsGift
                    ? 'هدية — لا تتجدد'
                    : settings.planAutoRenew
                    ? 'مفعّل'
                    : 'ملغى — يبقى فعّالًا حتى نهاية المدة',
              ),
            ),
            if (!settings.planIsGift) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: settings.planAutoRenew
                      ? AppTheme.danger
                      : AppTheme.brandMid,
                  side: BorderSide(
                    color: settings.planAutoRenew
                        ? AppTheme.danger
                        : AppTheme.brandMid,
                  ),
                  minimumSize: const Size.fromHeight(42),
                ),
                onPressed: _toggleAutoRenew,
                icon: Icon(
                  settings.planAutoRenew
                      ? Icons.event_busy_outlined
                      : Icons.autorenew_rounded,
                  size: 18,
                ),
                label: Text(
                  settings.planAutoRenew
                      ? 'إلغاء التجديد التلقائي'
                      : 'إعادة تفعيل التجديد التلقائي',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _periodRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      textDirection: AppTr.uiDir,
      children: [
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppTheme.title,
          ),
        ),
      ],
    ),
  );

  /// إلغاء التجديد لا يقطع الاشتراك: يبقى حتى نهاية المدة المدفوعة.
  Future<void> _toggleAutoRenew() async {
    final settings = AppSettings.instance;
    final cancelling = settings.planAutoRenew;
    final ok = await confirmAction(
      context,
      title: cancelling ? 'إلغاء التجديد التلقائي' : 'إعادة تفعيل التجديد',
      message: cancelling
          ? '${AppTr.tr('يبقى اشتراكك فعّالًا حتى')} ${settings.planEndLabel}'
                '${AppTr.tr('، ثم يعود حسابك إلى الباقة الأساسية وتبقى بياناتك محفوظة. لا تُسترد المبالغ المدفوعة عن المدة الحالية.')}'
          : '${AppTr.tr('سيتجدد اشتراكك تلقائيًا في')} ${settings.planEndLabel} '
                '${AppTr.tr('بنفس السعر والمدة.')}',
      confirmLabel: cancelling ? 'إلغاء التجديد' : 'تفعيل',
      cancelLabel: 'رجوع',
      danger: cancelling,
    );
    if (!ok || !mounted) return;
    await settings.setPlanAutoRenew(!cancelling);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cancelling
              ? '${AppTr.tr('أُلغي التجديد — الاشتراك فعّال حتى')} ${settings.planEndLabel}'
              : AppTr.tr('أُعيد تفعيل التجديد التلقائي'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// شروط الاشتراك والدفع: التجديد والإلغاء والاسترداد والرسوم والتواصل.
  static const _policyPoints = <(IconData, String, String)>[
    (
      Icons.autorenew_rounded,
      'التجديد',
      'الاشتراك الشهري أو السنوي يتجدد تلقائيًا في نهاية كل مدة بنفس السعر حتى تلغي التجديد. الهدية لا تتجدد وتنتهي بنهاية مدتها.',
    ),
    (
      Icons.play_circle_outline_rounded,
      'متى يبدأ الاشتراك',
      'يبدأ فور تأكيد الدفع وتُحسب مدته من يوم الدفع. والهدية تبدأ يوم تفعيل كودها من المُهدى إليه، لا يوم شرائها.',
    ),
    (
      Icons.event_busy_outlined,
      'إلغاء التجديد',
      'من هذه الصفحة بزر «إلغاء التجديد التلقائي»، أو من إدارة الاشتراكات في متجر التطبيقات الذي دفعت منه، قبل موعد التجديد بيوم على الأقل.',
    ),
    (
      Icons.hourglass_bottom_rounded,
      'بعد الإلغاء',
      'لا يُقطع الاشتراك فورًا: يبقى فعّالًا حتى نهاية المدة المدفوعة، ثم يعود حسابك إلى الباقة الأساسية وتبقى كل بياناتك محفوظة.',
    ),
    (
      Icons.money_off_rounded,
      'الاسترداد',
      'لا تُسترد المبالغ المدفوعة عن مدة بدأت، ولا قيمة الهدية بعد شرائها أو تفعيلها، إلا ما يوجبه النظام أو سياسة المتجر الذي تمت منه عملية الدفع.',
    ),
    (
      Icons.receipt_long_outlined,
      'الرسوم والضرائب',
      'الأسعار المعروضة نهائية وتشمل ضريبة القيمة المضافة حيث تنطبق، ولا يضيف التطبيق أي رسوم أخرى. قد يطبّق البنك أو المتجر رسوم تحويل العملة.',
    ),
    (
      Icons.support_agent_outlined,
      'التواصل بشأن المدفوعات',
      'لأي استفسار عن الدفع أو الفواتير أو الاسترداد راسلنا من «تواصل معنا» على بريد الدعم، مع تاريخ العملية ورقم الإصدار.',
    ),
  ];

  Widget _policy() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final point in _policyPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                textDirection: AppTr.uiDir,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(point.$1, size: 18, color: AppTheme.brandMid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          point.$2,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.title,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          point.$3,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brandMid,
              side: const BorderSide(color: AppTheme.brandMid),
              minimumSize: const Size.fromHeight(42),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ContactUsPage()),
            ),
            icon: const Icon(Icons.support_agent_outlined, size: 18),
            label: const Text(
              'تواصل بشأن المدفوعات',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodToggle() {
    Widget option(String label, bool yearly, {String? badge}) {
      final selected = _yearly == yearly;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _yearly = yearly),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : AppTheme.body,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.goldLight : AppTheme.goldSoft,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.goldDark,
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

    final shown = PlanAccess.byId(_shownPlan);
    final saving = shown.monthly * 12 - shown.yearly;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.field,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          option('شهري', false),
          option(
            'سنوي',
            true,
            badge: saving > 0 ? '${AppTr.tr('وفّر')} $saving' : null,
          ),
        ],
      ),
    );
  }

  /// اختيار الباقة المعروضة: ثلاثة أزرار.
  Widget _planTabs() {
    return Row(
      textDirection: AppTr.uiDir,
      children: [
        for (final plan in PlanAccess.plans) ...[
          if (plan != PlanAccess.plans.first) const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _shownPlan = plan.id),
              borderRadius: BorderRadius.circular(AppTheme.rInner),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _shownPlan == plan.id ? plan.color : AppTheme.paper,
                  borderRadius: BorderRadius.circular(AppTheme.rInner),
                  border: Border.all(
                    color: _shownPlan == plan.id
                        ? plan.color
                        : AppTheme.hairline,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      plan.icon,
                      size: 20,
                      color: _shownPlan == plan.id ? Colors.white : plan.color,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: _shownPlan == plan.id
                            ? Colors.white
                            : AppTheme.title,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// أيقونة ونص ولون مستوى الصلاحية.
  (IconData, String, Color) _levelLook(PlanAccessLevel level) =>
      switch (level) {
        PlanAccessLevel.full => (
          Icons.check_circle_rounded,
          'إدخال بلا حد',
          AppTheme.brandMid,
        ),
        PlanAccessLevel.view => (
          Icons.edit_note_rounded,
          'إدخال محدود (حتى ${PlanAccess.limitedRecords})',
          AppTheme.goldDark,
        ),
        PlanAccessLevel.locked => (
          Icons.lock_outline_rounded,
          'غير متاح',
          AppTheme.muted,
        ),
      };

  Widget _accessRow(String label, PlanAccessLevel level) {
    final (icon, text, color) = _levelLook(level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        textDirection: AppTr.uiDir,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.body,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard() {
    final plan = PlanAccess.byId(_shownPlan);
    final isCurrent = plan.id == PlanAccess.current.id;
    final price = _yearly ? plan.yearly : plan.monthly;
    final period = _yearly ? 'سنويًا' : 'شهريًا';
    return _card(
      color: plan.color.withValues(alpha: 0.06),
      border: plan.color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: AppTr.uiDir,
            children: [
              AppIconTile(icon: plan.icon, color: plan.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${AppTr.tr('الباقة')} ${AppTr.tr(plan.name)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.tagline,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price $_currency',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: plan.color,
                    ),
                  ),
                  Text(
                    period,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final module in PlanModules.order)
            _accessRow(
              PlanModules.labels[module] ?? module,
              plan.levelOf(module),
            ),
          for (final feature in PlanFeatures.order)
            _accessRow(
              PlanFeatures.labels[feature] ?? feature,
              plan.features.contains(feature)
                  ? PlanAccessLevel.full
                  : PlanAccessLevel.locked,
            ),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: isCurrent ? null : () => _choosePlan(plan),
            style: ElevatedButton.styleFrom(
              backgroundColor: plan.color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: plan.color.withValues(alpha: 0.25),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rField),
              ),
            ),
            child: Text(
              isCurrent
                  ? 'باقتك الحالية'
                  : '${AppTr.tr('اشترك في الباقة')} ${AppTr.tr(plan.name)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  /// مقارنة الباقات الثلاث في جدول واحد.
  Widget _comparison() {
    Widget cell(PlanAccessLevel level) {
      final (icon, _, color) = _levelLook(level);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Icon(icon, size: 17, color: color),
      );
    }

    Widget label(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.body,
        ),
      ),
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Table(
            textDirection: AppTr.uiDir,
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.hairline)),
                ),
                children: [
                  const SizedBox.shrink(),
                  for (final plan in PlanAccess.plans)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        plan.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: plan.color,
                        ),
                      ),
                    ),
                ],
              ),
              for (final module in PlanModules.order)
                TableRow(
                  children: [
                    label(PlanModules.labels[module] ?? module),
                    for (final plan in PlanAccess.plans)
                      cell(plan.levelOf(module)),
                  ],
                ),
              for (final feature in PlanFeatures.order)
                TableRow(
                  children: [
                    label(PlanFeatures.labels[feature] ?? feature),
                    for (final plan in PlanAccess.plans)
                      cell(
                        plan.features.contains(feature)
                            ? PlanAccessLevel.full
                            : PlanAccessLevel.locked,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final level in PlanAccessLevel.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_levelLook(level).$1, size: 14, color: _levelLook(level).$3),
                    const SizedBox(width: 4),
                    Text(
                      _levelLook(level).$2,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// بوابة الدفع غير مربوطة بعد: تُفعَّل الباقة الآن تجريبيًا بلا خصم،
  /// وعند الربط يمرّ هذا الزر بالدفع أولًا.
  Future<void> _choosePlan(SubscriptionPlan plan) async {
    final ok = await confirmAction(
      context,
      title: '${AppTr.tr('تفعيل الباقة')} ${AppTr.tr(plan.name)}',
      message:
          'الدفع داخل التطبيق لم يُفعَّل بعد، فتُفعَّل الباقة الآن تجريبيًا '
          'بلا أي خصم. يبدأ الاشتراك فورًا ويتجدد تلقائيًا في نهاية المدة '
          'حتى تلغي التجديد، وتتغير صلاحيات الأقسام فورًا.',
      confirmLabel: 'تفعيل',
    );
    if (!ok || !mounted) return;
    await AppSettings.instance.startPlan(plan.id, yearly: _yearly);
    if (!mounted) return;
    setState(() => _shownPlan = plan.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${AppTr.tr('فُعّلت الباقة')} ${AppTr.tr(plan.name)}',
        ),
      ),
    );
  }

  Future<void> _openGiftForm() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final note = TextEditingController();
    var yearly = _yearly;
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: AppTr.uiDir,
        child: StatefulBuilder(
          builder: (sheetContext, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'أهدِ اشتراكًا',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    textDirection: AppTr.uiDir,
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text(
                            '${AppTr.tr('شهر')} • $kMonthlyPlanPrice $_currency',
                          ),
                          selected: !yearly,
                          onSelected: (_) => setSheet(() => yearly = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text(
                            '${AppTr.tr('سنة')} • $kYearlyPlanPrice $_currency',
                          ),
                          selected: yearly,
                          onSelected: (_) => setSheet(() => yearly = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    textDirection: AppTr.uiDir,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('اسم المُهدى إليه'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('رقم الهاتف'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    textDirection: AppTr.uiDir,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: AppTr.tr('رسالة مع الهدية (اختياري)'),
                      prefixIcon: const Icon(Icons.card_giftcard_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (name.text.trim().isEmpty) return;
                      Navigator.pop(sheetContext, true);
                    },
                    icon: const Icon(Icons.redeem_rounded),
                    label: const Text(
                      'متابعة الإهداء',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
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
    name.dispose();
    phone.dispose();
    note.dispose();
    if (send == true && mounted) {
      await _paymentNotice('إهداء اشتراك');
    }
  }

  Future<void> _openRedeem() async {
    final code = await askTextDialog(
      context,
      title: 'استخدام كود هدية',
      label: 'كود الهدية',
      confirmLabel: 'تحقق',
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _paymentNotice('التحقق من كود الهدية');
  }

  Widget _giftTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rInner),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(AppTheme.rInner),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppIconTile(
                  icon: icon,
                  color: color,
                  size: AppTheme.iconTileSmall,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.title,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.4,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        title: const Text('الاشتراكات والهدايا', style: AppTheme.cardTitle),
        centerTitle: true,
        backgroundColor: AppTheme.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Directionality(
        textDirection: AppTr.uiDir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _currentPlan(),
            const SizedBox(height: 22),
            _sectionTitle('الباقات'),
            _planTabs(),
            const SizedBox(height: 12),
            _periodToggle(),
            const SizedBox(height: 12),
            _planCard(),
            const SizedBox(height: 22),
            _sectionTitle('مقارنة الصلاحيات'),
            _comparison(),
            const SizedBox(height: 22),
            _sectionTitle('الهدايا'),
            Row(
              textDirection: AppTr.uiDir,
              children: [
                _giftTile(
                  icon: Icons.card_giftcard_rounded,
                  color: AppTheme.gold,
                  title: 'أهدِ اشتراكًا',
                  subtitle: 'اشترِ شهرًا أو سنة لشخص آخر',
                  onTap: _openGiftForm,
                ),
                const SizedBox(width: AppTheme.cardGap),
                _giftTile(
                  icon: Icons.redeem_rounded,
                  color: AppTheme.brandMid,
                  title: 'استخدم كود هدية',
                  subtitle: 'فعّل اشتراكًا أُهدي إليك',
                  onTap: _openRedeem,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _sectionTitle('شروط الاشتراك والدفع'),
            _policy(),
            const SizedBox(height: 16),
            const Text(
              'الدفع داخل التطبيق لم يُفعَّل بعد؛ الأسعار مبدئية.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}
