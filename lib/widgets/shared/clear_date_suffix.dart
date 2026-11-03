import 'package:flutter/material.dart';

import '../../l10n/app_language.dart';

/// زر × داخل حقل تاريخ / وقت اختياري: يظهر حين يكون فيه تاريخ فيمسحه
/// (يعود «غير محدد»). [onCleared] لإعادة بناء النموذج إن احتاج.
Widget clearDateSuffix(
  TextEditingController controller, {
  VoidCallback? onCleared,
}) {
  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => value.text.trim().isEmpty
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: AppTr.tr('مسح التاريخ'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () {
              controller.clear();
              onCleared?.call();
            },
          ),
  );
}
