import 'package:flutter/material.dart' hide Text, Align;

import '../../data/subscription_plans.dart';
import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import '../../screens/subscriptions_screen.dart';
import 'app_design.dart';

/// بوابة الباقة في الواجهة: قبل فتح نموذج إضافة/تعديل أو قسم أو ميزة،
/// تُظهر نافذة الترقية إن لم تسمح الباقة الحالية.
class PlanGate {
  PlanGate._();

  /// أثناء التجارب ([PlanAccess.enforced] = false): ملاحظة صغيرة بالباقة
  /// المطلوبة، ويستمر المستخدم بلا قيد.
  static bool _note(
    BuildContext context,
    String subject,
    SubscriptionPlan needed,
  ) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${AppTr.tr(subject)} · ${AppTr.tr('يتطلب الباقة')} '
            '${AppTr.tr(needed.name)} · ${AppTr.tr('مفتوح للتجربة')}',
            style: const TextStyle(fontSize: 12),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    return true;
  }

  /// التحكم (إضافة، تعديل، حذف) في القسم.
  static bool canEdit(BuildContext context, String module) {
    if (PlanAccess.canEdit(module)) return true;
    if (!PlanAccess.enforced) {
      return _note(
        context,
        PlanModules.labels[module] ?? module,
        PlanAccess.requiredFor(module),
      );
    }
    final viewOnly = PlanAccess.canView(module);
    showUpgrade(
      context,
      message: viewOnly
          ? 'الإدخال في هذا القسم محدود في باقتك الحالية — للإدخال بلا حد رقِّ باقتك.'
          : 'هذا القسم غير متاح في باقتك الحالية.',
      subject: PlanModules.labels[module] ?? module,
      needed: PlanAccess.requiredFor(module),
    );
    return false;
  }

  /// إضافة سجل جديد: في «الإدخال المحدود» حتى [PlanAccess.limitedRecords].
  static bool canAdd(BuildContext context, String module, int count) {
    if (PlanAccess.canAdd(module, count)) return true;
    final needed = PlanAccess.requiredFor(module);
    if (!PlanAccess.enforced) {
      return _note(context, PlanModules.labels[module] ?? module, needed);
    }
    showUpgrade(
      context,
      message: PlanAccess.canView(module)
          ? 'وصلت إلى حد الإدخال في باقتك الحالية — للمزيد رقِّ باقتك.'
          : 'هذا القسم غير متاح في باقتك الحالية.',
      subject: PlanModules.labels[module] ?? module,
      needed: needed,
    );
    return false;
  }

  /// فتح القسم للعرض.
  static bool canView(BuildContext context, String module) {
    if (PlanAccess.canView(module)) return true;
    if (!PlanAccess.enforced) {
      return _note(
        context,
        PlanModules.labels[module] ?? module,
        PlanAccess.requiredFor(module, edit: false),
      );
    }
    showUpgrade(
      context,
      message: 'هذا القسم غير متاح في باقتك الحالية.',
      subject: PlanModules.labels[module] ?? module,
      needed: PlanAccess.requiredFor(module, edit: false),
    );
    return false;
  }

  /// ميزة مثل العقود المحكمة أو تقارير PDF.
  static bool hasFeature(BuildContext context, String feature) {
    if (PlanAccess.has(feature)) return true;
    if (!PlanAccess.enforced) {
      return _note(
        context,
        PlanFeatures.labels[feature] ?? feature,
        PlanAccess.requiredForFeature(feature),
      );
    }
    showUpgrade(
      context,
      message: 'هذه الميزة غير متاحة في باقتك الحالية.',
      subject: PlanFeatures.labels[feature] ?? feature,
      needed: PlanAccess.requiredForFeature(feature),
    );
    return false;
  }

  static Future<void> showUpgrade(
    BuildContext context, {
    required String message,
    required String subject,
    required SubscriptionPlan needed,
  }) {
    final current = PlanAccess.current;
    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.muted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.title,
            ),
          ),
        ],
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline_rounded, size: 34, color: needed.color),
                const SizedBox(height: 8),
                const Text(
                  'رقِّ باقتك',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.body,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rField),
                  ),
                  child: Column(
                    children: [
                      row('القسم / الميزة', subject),
                      row('باقتك الحالية', current.name, color: current.color),
                      row('متاح من باقة', needed.name, color: needed.color),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text(
                    'عرض الباقات',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: needed.color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('لاحقًا'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
