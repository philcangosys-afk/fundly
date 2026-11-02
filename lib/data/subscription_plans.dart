import 'package:flutter/material.dart';

import 'app_settings.dart';

/// مستوى الصلاحية في قسم: غير متاح، إدخال محدود (عرض + عدد محدود من
/// السجلات [PlanAccess.limitedRecords])، أو إدخال وتحكم كامل.
enum PlanAccessLevel { locked, view, full }

/// الأقسام التي تختلف صلاحياتها بين الباقات. مفاتيح أقسام الأصول هي نفسها
/// تصنيفاتها في قاعدة البيانات (real_estate / activity / equipment).
class PlanModules {
  PlanModules._();

  static const personal = 'personal';
  static const people = 'people';
  static const shared = 'shared';
  static const realEstate = 'real_estate';
  static const equipment = 'equipment';
  static const activity = 'activity';
  static const documents = 'documents';
  static const delegations = 'delegations';

  static const order = <String>[
    personal,
    people,
    shared,
    realEstate,
    equipment,
    activity,
    documents,
    delegations,
  ];

  static const labels = <String, String>{
    personal: 'الالتزامات الشخصية',
    people: 'الأفراد والجهات',
    shared: 'الالتزامات المشتركة',
    realEstate: 'العقارات',
    equipment: 'المركبات ووسائل النقل',
    activity: 'الأنشطة التجارية',
    documents: 'مركز المستندات',
    delegations: 'التفويضات',
  };
}

/// مزايا تُفتح بالباقة (ليست أقسامًا).
class PlanFeatures {
  PlanFeatures._();

  /// قوالب العقود المحكمة (عقار، نشاط، مركبة، عام).
  static const contracts = 'contracts';

  /// طباعة التقارير ومشاركتها PDF.
  static const pdf = 'pdf';

  static const order = <String>[contracts, pdf];

  static const labels = <String, String>{
    contracts: 'قوالب العقود المحكمة',
    pdf: 'طباعة التقارير ومشاركتها PDF',
  };
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.monthly,
    required this.yearly,
    required this.color,
    required this.icon,
    required this.access,
    required this.features,
  });

  final String id;
  final String name;
  final String tagline;
  final int monthly;
  final int yearly;
  final Color color;
  final IconData icon;
  final Map<String, PlanAccessLevel> access;
  final Set<String> features;

  PlanAccessLevel levelOf(String module) =>
      access[module] ?? PlanAccessLevel.full;
}

/// العملية مرفوضة لأن الباقة الحالية لا تسمح بها.
class PlanLockedException implements Exception {
  const PlanLockedException(this.module);

  final String module;

  @override
  String toString() =>
      'هذه العملية غير متاحة في باقتك الحالية — رقِّ باقتك من «الاشتراكات».';
}

/// الباقات الثلاث وصلاحياتها، والتحقق منها في كل مكان في التطبيق.
class PlanAccess {
  PlanAccess._();

  /// مفتاح التفعيل الحقيقي: `false` أثناء التجارب — لا يُقيَّد أي وصول،
  /// وتظهر ملاحظة صغيرة فقط بالباقة المطلوبة. `true` يفرض الصلاحيات.
  static const bool enforced = false;

  /// يُمنع فتح القسم فعليًا (عند التفعيل الحقيقي فقط).
  static bool blocksView(String module) => enforced && !canView(module);

  static const silver = SubscriptionPlan(
    id: 'silver',
    name: 'الفضية',
    tagline: 'لإدارة شؤونك الشخصية',
    monthly: 9,
    yearly: 90,
    color: Color(0xFF7D8A92),
    icon: Icons.workspace_premium_outlined,
    access: {
      PlanModules.personal: PlanAccessLevel.full,
      PlanModules.people: PlanAccessLevel.full,
      PlanModules.shared: PlanAccessLevel.view,
      PlanModules.realEstate: PlanAccessLevel.view,
      PlanModules.equipment: PlanAccessLevel.view,
      PlanModules.activity: PlanAccessLevel.locked,
      PlanModules.documents: PlanAccessLevel.view,
      PlanModules.delegations: PlanAccessLevel.view,
    },
    features: <String>{},
  );

  static const gold = SubscriptionPlan(
    id: 'gold',
    name: 'الذهبية',
    tagline: 'للأسرة والمالك والمستثمر الصغير',
    monthly: 19,
    yearly: 190,
    color: Color(0xFFB8862B),
    icon: Icons.star_rounded,
    access: {
      PlanModules.personal: PlanAccessLevel.full,
      PlanModules.people: PlanAccessLevel.full,
      PlanModules.shared: PlanAccessLevel.full,
      PlanModules.realEstate: PlanAccessLevel.full,
      PlanModules.equipment: PlanAccessLevel.view,
      PlanModules.activity: PlanAccessLevel.view,
      PlanModules.documents: PlanAccessLevel.full,
      PlanModules.delegations: PlanAccessLevel.view,
    },
    features: {PlanFeatures.contracts, PlanFeatures.pdf},
  );

  static const premium = SubscriptionPlan(
    id: 'premium',
    name: 'البريميوم',
    tagline: 'لأصحاب الأعمال — كل شيء بلا قيود',
    monthly: 39,
    yearly: 390,
    color: Color(0xFF0A5A50),
    icon: Icons.diamond_outlined,
    access: {
      PlanModules.personal: PlanAccessLevel.full,
      PlanModules.people: PlanAccessLevel.full,
      PlanModules.shared: PlanAccessLevel.full,
      PlanModules.realEstate: PlanAccessLevel.full,
      PlanModules.equipment: PlanAccessLevel.full,
      PlanModules.activity: PlanAccessLevel.full,
      PlanModules.documents: PlanAccessLevel.full,
      PlanModules.delegations: PlanAccessLevel.full,
    },
    features: {PlanFeatures.contracts, PlanFeatures.pdf},
  );

  static const plans = <SubscriptionPlan>[silver, gold, premium];

  static SubscriptionPlan byId(String id) => plans.firstWhere(
    (plan) => plan.id == id,
    orElse: () => silver,
  );

  static SubscriptionPlan get current => byId(AppSettings.instance.plan);

  static PlanAccessLevel levelOf(String module) => current.levelOf(module);

  static bool canView(String module) =>
      levelOf(module) != PlanAccessLevel.locked;

  static bool canEdit(String module) => levelOf(module) == PlanAccessLevel.full;

  static bool has(String feature) => current.features.contains(feature);

  /// «إدخال محدود»: يضيف حتى هذا العدد من السجلات في القسم ويطّلع عليها.
  static const int limitedRecords = 5;

  /// إضافة سجل جديد وفي القسم [count] سجل حاليًا.
  static bool canAdd(String module, int count) =>
      canEdit(module) ||
      (levelOf(module) == PlanAccessLevel.view && count < limitedRecords);

  /// أدنى باقة تسمح بالتحكم في القسم (أو بعرضه إن [edit] = false).
  static SubscriptionPlan requiredFor(String module, {bool edit = true}) {
    for (final plan in plans) {
      final level = plan.levelOf(module);
      if (edit ? level == PlanAccessLevel.full : level != PlanAccessLevel.locked) {
        return plan;
      }
    }
    return premium;
  }

  /// أدنى باقة فيها الميزة.
  static SubscriptionPlan requiredForFeature(String feature) {
    for (final plan in plans) {
      if (plan.features.contains(feature)) return plan;
    }
    return premium;
  }

  // ===== الحماية في طبقة البيانات =====
  // كل كتابة (إضافة، تعديل، حذف) تمرّ من هنا، فلا يتجاوز أي زر في أي شاشة
  // صلاحية الباقة. الأزرار الرئيسية تُظهر نافذة الترقية قبل فتح النموذج.

  /// يرفض الكتابة في قسم ليس للباقة فيه تحكم.
  static void ensureEdit(String module) {
    // الإدخال المحدود يُضبط عدده عند زر الإضافة؛ المرفوض هنا غير المتاح فقط.
    if (!enforced || canView(module)) return;
    throw PlanLockedException(module);
  }

  /// تصنيف كل أصل، ومالك كل سجل (عقد، دفعة، حركة، بند) ← معرّف الأصل.
  static final Map<String, String> _assetCategory = {};
  static final Map<String, String> _ownerAsset = {};

  static void rememberAsset(String? assetId, String category) {
    if (assetId == null || assetId.isEmpty || category.isEmpty) return;
    _assetCategory[assetId] = category;
  }

  static void rememberOwner(String? recordId, String? assetId) {
    if (recordId == null || recordId.isEmpty) return;
    if (assetId == null || assetId.isEmpty) return;
    _ownerAsset[recordId] = assetId;
  }

  /// معرّف الأصل لسجل محفوظ (أو `null` إن لم يُعرف بعد).
  static String? assetOf(String? recordId) =>
      recordId == null ? null : _ownerAsset[recordId];

  /// يرفض الكتابة على أصل قسمُه غير مسموح. الأصل غير المعروف يُسمح به.
  static void ensureEditAsset(String? assetId) {
    final category = assetId == null ? null : _assetCategory[assetId];
    if (category == null) return;
    ensureEdit(category);
  }
}
