/// ============================================================================
/// Commitment Additions Configuration
/// Purpose: Define logical additions for each commitment entry type
/// Date: 2026-08-20
/// ============================================================================

/// Category for each addition type
enum AdditionCategory {
  payment,      // دفعة
  attachment,   // فاتورة، مستند، إيصال، عقد، صورة
  appointment,  // موعد، تذكير، موعد دفع، موعد تجديد، موعد متابعة
  note,         // ملاحظة، تسوية، تجديد، بيانات إدارية
  person,       // شخص
  location,     // موقع
}

/// Individual addition type
class AdditionType {
  final String id;
  final String displayName;
  final AdditionCategory category;
  final String icon;

  const AdditionType({
    required this.id,
    required this.displayName,
    required this.category,
    required this.icon,
  });
}

/// All available addition types
class AllAdditions {
  static const payment = AdditionType(
    id: 'payment',
    displayName: 'إضافة مالية',
    category: AdditionCategory.payment,
    icon: '💰',
  );

  static const administrative = AdditionType(
    id: 'administrative',
    displayName: 'إضافة ادارية',
    category: AdditionCategory.note,
    icon: '📊',
  );

  static const document = AdditionType(
    id: 'document',
    displayName: 'إضافة مستند',
    category: AdditionCategory.attachment,
    icon: '📄',
  );

  static const person = AdditionType(
    id: 'person',
    displayName: 'إضافة شخص/جهة',
    category: AdditionCategory.person,
    icon: '👤',
  );

  static const unit = AdditionType(
    id: 'unit',
    displayName: 'إضافة وحدة',
    category: AdditionCategory.location,
    icon: '🏠',
  );

  static const asset = AdditionType(
    id: 'asset',
    displayName: 'إضافة أصل ومحتويات',
    category: AdditionCategory.attachment,
    icon: '📦',
  );

  static const link = AdditionType(
    id: 'link',
    displayName: 'إضافة رابط',
    category: AdditionCategory.location,
    icon: '🔗',
  );

  static const other = AdditionType(
    id: 'other',
    displayName: 'أخرى',
    category: AdditionCategory.note,
    icon: '⋯',
  );

  static const note = administrative;
  static const location = unit;
  static const appointment = administrative;
  static const reminder = administrative;
  static const paymentAppointment = payment;
  static const renewalAppointment = administrative;
  static const followUpAppointment = administrative;
  static const settlement = administrative;
  static const renewal = administrative;
  static const administrativeData = administrative;
  static const invoice = document;
  static const receipt = document;
  static const contract = document;
  static const image = asset;
  static const otherAttachment = other;

  /// Get all additions as a list
  static List<AdditionType> get all => [
        payment,
        administrative,
        document,
        person,
        unit,
        asset,
        link,
        other,
      ];
}

/// Configuration for logical additions per entry type
class CommitmentAdditionsConfig {
  /// Get logical (primary) additions for an entry type
  static List<AdditionType> getLogicalAdditions(String entryType) {
    switch (entryType) {
      case 'المصروفات الشخصية':
      case 'دخل':
      case 'تحويل مالي':
      case 'دين / قرض / سلفة':
      case 'قسط':
      case 'غرامة':
      case 'عهدة مالية':
      case 'التزام شخصي / شهري':
      case 'رهن / ضمان':
      case 'إيرادات/مكتب/تجارية':
      case 'استثمار أو مشروع':
        return [
          AllAdditions.payment,
          AllAdditions.administrative,
          AllAdditions.document,
          AllAdditions.person,
        ];

      default:
        return [
          AllAdditions.payment,
          AllAdditions.document,
          AllAdditions.administrative,
          AllAdditions.person,
        ];
    }
  }

  /// Get additional (secondary) additions for an entry type
  /// These appear under "مزيد من الإضافات" button
  static List<AdditionType> getAdditionalAdditions(String entryType) {
    final logical = getLogicalAdditions(entryType);
    final logicalIds = logical.map((a) => a.id).toSet();

    // Return all additions that are NOT in the logical list
    return AllAdditions.all.where((a) => !logicalIds.contains(a.id)).toList();
  }

  /// Get all additions (logical + additional) for an entry type
  static List<AdditionType> getAllAdditions(String entryType) {
    return [
      ...getLogicalAdditions(entryType),
      ...getAdditionalAdditions(entryType),
    ];
  }

  /// Check if an addition is logical for an entry type
  static bool isLogicalAddition(String entryType, String additionId) {
    final logical = getLogicalAdditions(entryType);
    return logical.any((a) => a.id == additionId);
  }
}

/// Extension for easy access
extension EntryTypeAdditionsExtension on String {
  List<AdditionType> get logicalAdditions =>
      CommitmentAdditionsConfig.getLogicalAdditions(this);

  List<AdditionType> get additionalAdditions =>
      CommitmentAdditionsConfig.getAdditionalAdditions(this);

  List<AdditionType> get allAdditions =>
      CommitmentAdditionsConfig.getAllAdditions(this);

  bool isLogicalAddition(String additionId) =>
      CommitmentAdditionsConfig.isLogicalAddition(this, additionId);
}
