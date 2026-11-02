import 'package:flutter/material.dart' hide Text;

import '../../data/reminder_lead.dart';
import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';

/// «وقت التذكير»: قائمة المدة قبل الموعد، ومع «مخصص» خانة للعدد. يكتب
/// القيمة النهائية في [controller] («قبل يوم»، «قبل 3 ساعة»...).
class ReminderLeadField extends StatefulWidget {
  const ReminderLeadField({
    super.key,
    required this.controller,
    required this.decoration,
  });

  final TextEditingController controller;
  final InputDecoration decoration;

  @override
  State<ReminderLeadField> createState() => _ReminderLeadFieldState();
}

class _ReminderLeadFieldState extends State<ReminderLeadField> {
  String? _option;
  final _number = TextEditingController();

  @override
  void initState() {
    super.initState();
    final (option, number) = reminderLeadSplit(widget.controller.text);
    _option = option.isEmpty ? null : option;
    _number.text = number;
    // قيمة قديمة (ساعة) لا تُقابل خيارًا: تُفرَّغ فلا تُحفظ كأنها مدة.
    if (_option == null) widget.controller.text = '';
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _sync() {
    final option = _option;
    widget.controller.text =
        option == null ? '' : reminderLeadValue(option, _number.text);
  }

  @override
  Widget build(BuildContext context) {
    final custom = _option == kLeadCustomHours || _option == kLeadCustomDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _option,
          isExpanded: true,
          alignment: AlignmentDirectional.centerEnd,
          decoration: widget.decoration,
          items: [
            for (final option in kReminderLeadOptions)
              DropdownMenuItem(
                value: option,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(option, textAlign: TextAlign.right),
              ),
          ],
          onChanged: (value) {
            setState(() => _option = value);
            _sync();
          },
        ),
        if (custom) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _number,
            keyboardType: TextInputType.number,
            textAlign: AppTr.alignEnd,
            decoration: InputDecoration(
              isDense: true,
              hintText: AppTr.tr(
                _option == kLeadCustomHours
                    ? 'كم ساعة قبل الموعد؟'
                    : 'كم يومًا قبل الموعد؟',
              ),
            ),
            onChanged: (_) => _sync(),
          ),
        ],
      ],
    );
  }
}

/// قائمة اختيار فيها «مخصص» يفتح خانة نص — تُكتب قيمتها في [controller].
class CustomOptionField extends StatefulWidget {
  const CustomOptionField({
    super.key,
    required this.controller,
    required this.options,
    required this.decoration,
    this.customHint = 'اكتب القيمة',
  });

  final TextEditingController controller;

  /// الخيارات بدون «مخصص» — يُضاف آخرها.
  final List<String> options;
  final InputDecoration decoration;
  final String customHint;

  @override
  State<CustomOptionField> createState() => _CustomOptionFieldState();
}

class _CustomOptionFieldState extends State<CustomOptionField> {
  static const _custom = 'مخصص';
  String? _option;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    final stored = widget.controller.text.trim();
    if (stored.isEmpty) {
      _option = null;
    } else if (widget.options.contains(stored)) {
      _option = stored;
    } else {
      _option = _custom;
      _text.text = stored;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _sync() {
    widget.controller.text = _option == _custom
        ? _text.text.trim()
        : (_option ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _option,
          isExpanded: true,
          alignment: AlignmentDirectional.centerEnd,
          decoration: widget.decoration,
          items: [
            for (final option in [...widget.options, _custom])
              DropdownMenuItem(
                value: option,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(option, textAlign: TextAlign.right),
              ),
          ],
          onChanged: (value) {
            setState(() => _option = value);
            _sync();
          },
        ),
        if (_option == _custom) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _text,
            textAlign: AppTr.alignEnd,
            decoration: InputDecoration(
              isDense: true,
              hintText: AppTr.tr(widget.customHint),
            ),
            onChanged: (_) => _sync(),
          ),
        ],
      ],
    );
  }
}
