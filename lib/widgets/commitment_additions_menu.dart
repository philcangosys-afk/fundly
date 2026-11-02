import 'package:flutter/material.dart' hide Text, Align;
import '../l10n/tr_widgets.dart';
import '../l10n/app_language.dart';
import '../config/commitment_additions_config.dart';
import 'shared/app_design.dart';

/// Widget to display commitment additions menu with logical and additional options
class CommitmentAdditionsMenu extends StatefulWidget {
  final String entryType;
  final String commitmentId;
  final Function(AdditionType) onAdditionSelected;

  const CommitmentAdditionsMenu({
    super.key,
    required this.entryType,
    required this.commitmentId,
    required this.onAdditionSelected,
  });

  @override
  State<CommitmentAdditionsMenu> createState() =>
      _CommitmentAdditionsMenuState();
}

class _CommitmentAdditionsMenuState extends State<CommitmentAdditionsMenu> {
  bool _showAdditionalAdditions = false;

  @override
  Widget build(BuildContext context) {
    final logicalAdditions = CommitmentAdditionsConfig.getLogicalAdditions(
      widget.entryType,
    );
    final additionalAdditions =
        CommitmentAdditionsConfig.getAdditionalAdditions(widget.entryType);

    final visibleAdditional = _showAdditionalAdditions
        ? additionalAdditions
        : const <AdditionType>[];

    return Directionality(
      textDirection: AppTr.uiDir,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF7FAF9),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.rCard),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 700),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5DEDB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إضافة جديدة',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.entryType,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF46534F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9EDE8),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              tooltip: AppTr.tr('إضافة جديدة'),
                              splashRadius: 20,
                              onPressed: () {
                                widget.onAdditionSelected(AllAdditions.payment);
                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.add_rounded,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              splashRadius: 20,
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF022E2A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD9EDE8), Color(0xFFD9EDE8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF0A5A50),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الإضافات المقترحة تناسب هذا النوع من الالتزام',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(
                                0xFF022E2A,
                              ).withValues(alpha: 0.8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.rField),
                    ),
                    child: const Text(
                      'الشرح: استخدم الإضافات الأساسية في أغلب الحالات، أما الخيارات الإضافية فاضغط على “مزيد من الإضافات” عندما تحتاج إلى تصنيفات أكثر دقة.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF46534F),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الإضافات الأساسية',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF022E2A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildAdditionsWrap(logicalAdditions, isPrimary: true),
                  if (additionalAdditions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildMoreAdditionsButton(additionalAdditions.length),
                  ],
                  if (_showAdditionalAdditions &&
                      visibleAdditional.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'إضافات أخرى',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2C3B38),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildAdditionsWrap(visibleAdditional, isPrimary: false),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdditionsWrap(
    List<AdditionType> additions, {
    required bool isPrimary,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 360 ? 2 : 3;
        final gap = 8.0;
        final itemWidth = (width - (crossAxisCount - 1) * gap) / crossAxisCount;

        return Wrap(
          spacing: gap,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: additions
              .map(
                (addition) => SizedBox(
                  width: itemWidth,
                  child: _buildAdditionCard(addition, isPrimary: isPrimary),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildAdditionCard(AdditionType addition, {required bool isPrimary}) {
    final accentColor = isPrimary
        ? const Color(0xFF0A5A50)
        : const Color(0xFF5C6B68);
    final cardColor = isPrimary ? const Color(0xFFE9F4F1) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onAdditionSelected(addition);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? const Color(0xFF7FC7B9)
                  : const Color(0xFFE4EAE8),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    addition.icon,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AppFitText(
                    addition.displayName,
                    textAlign: TextAlign.center,
                    alignment: Alignment.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isPrimary
                          ? const Color(0xFF0A5A50)
                          : const Color(0xFF2C3B38),
                      height: 1.1,
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

  Widget _buildMoreAdditionsButton(int count) {
    return InkWell(
      onTap: () {
        setState(() {
          _showAdditionalAdditions = !_showAdditionalAdditions;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE4EAE8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  _showAdditionalAdditions
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF022E2A),
                ),
                const SizedBox(width: 8),
                Text(
                  _showAdditionalAdditions
                      ? 'إخفاء الإضافات الأخرى'
                      : 'مزيد من الإضافات ($count)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF022E2A),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A5A50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show additions menu as a bottom sheet
Future<AdditionType?> showCommitmentAdditionsMenu({
  required BuildContext context,
  required String entryType,
  required String commitmentId,
}) {
  return showModalBottomSheet<AdditionType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: CommitmentAdditionsMenu(
          entryType: entryType,
          commitmentId: commitmentId,
          onAdditionSelected: (addition) {
            Navigator.pop(context, addition);
          },
        ),
      ),
    ),
  );
}
