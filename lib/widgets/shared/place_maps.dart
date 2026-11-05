import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' hide Text, Align;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_language.dart';
import '../../l10n/tr_widgets.dart';
import 'app_design.dart';

/// فتح المكان المحفوظ في تطبيقات الخرائط الموجودة في الجهاز، ونسخ رابطه.
///
/// القيمة المحفوظة في «الموقع أو الرابط» واحدة من ثلاث: إحداثيات
/// «خط العرض,خط الطول»، أو رابط خرائط، أو عنوان مكتوب.
class PlaceMaps {
  PlaceMaps._();

  /// مفتاح داخلي في تفاصيل المكان: التطبيق المختار له («حفظ هذا الاختيار»).
  static const String appKey = 'تطبيق الخرائط';

  static const String google = 'google';
  static const String apple = 'apple';
  static const String waze = 'waze';
  static const String device = 'device';

  static bool get isIos => defaultTargetPlatform == TargetPlatform.iOS;

  // بكسور عشرية فقط: «1/1, 22» في عنوان مكتوب ليست إحداثيات.
  static final RegExp _coords = RegExp(
    r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)',
  );

  static bool _isLink(String value) =>
      RegExp(r'^https?://', caseSensitive: false).hasMatch(value.trim());

  /// الإحداثيات إن كانت القيمة إحداثيات (أو رابطًا فيه إحداثيات صريحة).
  static ({double lat, double lng})? coordsOf(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final match = _coords.firstMatch(text);
    if (match == null) return null;
    // نص بلا رابط: الإحداثيات وحدها، لا جزء من عنوان.
    if (!_isLink(text) && match.group(0)!.length < text.length - 2) {
      return null;
    }
    // الرابط بلا إحداثيات صريحة (رابط مختصر) يُفتح كما هو.
    if (_isLink(text) && !text.contains('@') && !text.contains('q=') &&
        !text.contains('ll=') && !text.contains('query=')) {
      return null;
    }
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return (lat: lat, lng: lng);
  }

  /// رابط خرائط جوجل للمكان — للنسخ والمشاركة ويفتح في أي جهاز.
  static String linkOf(String value) {
    final text = value.trim();
    final c = coordsOf(text);
    if (c != null) {
      return 'https://www.google.com/maps/search/?api=1&query=${c.lat},${c.lng}';
    }
    if (_isLink(text)) return text;
    return 'https://www.google.com/maps/search/?api=1&query='
        '${Uri.encodeComponent(text)}';
  }

  static Uri _uriFor(String app, String value, String label) {
    final text = value.trim();
    final c = coordsOf(text);
    final query = c == null ? text : '${c.lat},${c.lng}';
    switch (app) {
      case apple:
        return c == null
            ? Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(text)}')
            : Uri.parse(
                'https://maps.apple.com/?ll=${c.lat},${c.lng}'
                '&q=${Uri.encodeComponent(label.isEmpty ? query : label)}',
              );
      case waze:
        return c == null
            ? Uri.parse('https://waze.com/ul?q=${Uri.encodeComponent(text)}')
            : Uri.parse(
                'https://waze.com/ul?ll=${c.lat},${c.lng}&navigate=yes',
              );
      case device:
        // أندرويد: يعرض كل تطبيقات الخرائط المثبّتة ليختار منها.
        return c == null
            ? Uri.parse('geo:0,0?q=${Uri.encodeComponent(text)}')
            : Uri.parse(
                'geo:${c.lat},${c.lng}?q=${c.lat},${c.lng}'
                '${label.isEmpty ? '' : '(${Uri.encodeComponent(label)})'}',
              );
      default:
        return Uri.parse(_isLink(text) && c == null ? text : linkOf(text));
    }
  }

  /// فتح المكان في تطبيق بعينه. يعيد false إن تعذّر.
  static Future<bool> openIn(String app, String value, {String label = ''}) async {
    try {
      return await launchUrl(
        _uriFor(app, value, label),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static String appLabel(String app) => switch (app) {
    apple => 'خرائط Apple',
    waze => 'Waze',
    device => 'تطبيقات الخرائط في جهازك',
    _ => 'خرائط Google',
  };

  static IconData _appIcon(String app) => switch (app) {
    apple => Icons.map_outlined,
    waze => Icons.navigation_rounded,
    device => Icons.apps_rounded,
    _ => Icons.travel_explore_rounded,
  };

  /// «فتح الخرائط»: التطبيق المحفوظ لهذا المكان يُفتح مباشرة، وإلا تظهر
  /// التطبيقات للاختيار مع «حفظ هذا الاختيار لهذا المكان».
  /// [onRemember] يُستدعى بالتطبيق المختار عند تفعيل الحفظ.
  static Future<void> open(
    BuildContext context, {
    required String value,
    String label = '',
    String remembered = '',
    bool forceChooser = false,
    Future<void> Function(String app)? onRemember,
  }) async {
    if (value.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!forceChooser && remembered.isNotEmpty) {
      final ok = await openIn(remembered, value, label: label);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${AppTr.tr('تعذّر فتح')} ${AppTr.tr(appLabel(remembered))}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final apps = [
      google,
      if (isIos) apple,
      waze,
      if (!isIos) device,
    ];
    var remember = false;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Directionality(
          textDirection: AppTr.uiDir,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'فتح الخرائط',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted,
                      ),
                    ),
                  if (onRemember != null)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'حفظ هذا الاختيار لهذا المكان',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      value: remember,
                      onChanged: (v) => setSheet(() => remember = v),
                    ),
                  const SizedBox(height: 4),
                  for (final app in apps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.rInner),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.rInner),
                          onTap: () => Navigator.pop(sheetContext, app),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Icon(_appIcon(app), color: AppTheme.brand),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    appLabel(app),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                  color: AppTheme.muted,
                                ),
                              ],
                            ),
                          ),
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
    if (picked == null) return;
    if (remember && onRemember != null) await onRemember(picked);
    final ok = await openIn(picked, value, label: label);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${AppTr.tr('تعذّر فتح')} ${AppTr.tr(appLabel(picked))}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// نسخ رابط المكان (خرائط Google) للصقه في أي مكان.
  static Future<void> copyLink(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: linkOf(value)));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رابط المكان'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
